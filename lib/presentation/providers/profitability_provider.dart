import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/date_range.dart';
import '../../data/models/profitability_data.dart';
import 'dashboard_provider.dart';

/// Categorías de gasto que son sueldos. Entran en el costo primo.
const _idsSueldos = {'salarios'};

/// Categorías que se pagan igual se venda o no. Son las que el POS marca como
/// `fixed` al crear un gasto.
///
/// Se consulta por id además de mirar el campo `type` porque los retiros de
/// caja llegan con `type: 'variable'` puesto a la fuerza, sin importar de qué
/// sean: un sueldo pagado en efectivo desde la caja es un costo fijo, y
/// tratarlo como variable descuadra el punto de equilibrio.
const _idsFijos = {'renta', 'salarios', 'internet', 'seguros'};

/// A partir de acá una existencia deja de ser creíble y se avisa.
///
/// Medido sobre los 2.694 ingredientes con existencia del sistema: por debajo
/// de cien mil todo es legítimo (56 litros de aceite, 98 kilos de salsa), y los
/// que pasan el millón son 26 en dos negocios, con cosas como pollo en cien mil
/// billones de porciones o una cerveza de barril en un billón de unidades. El
/// millón deja el corte donde no hay ninguna falsa alarma.
const kStockImposible = 1000000.0;

/// Movimientos de inventario que forman el costo de lo vendido.
const _tipoSalidaVenta = 'salidaVenta';

/// Mercadería que ENTRÓ a la despensa.
///
/// Es la fuente de "invertido en compras", en vez de la colección
/// `purchaseOrders`: en los datos reales muchas entradas con costo nunca
/// generan un documento de compra, así que leyendo solo allí el reporte
/// mostraba Q0.00 mientras el negocio compraba todos los días. Cada entrada de
/// mercadería SÍ queda registrada acá, con su costo, venga de una orden de
/// compra formal o de una entrada cargada a mano.
const _tipoEntrada = 'entrada';

class ProfitabilityProvider extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  ProfitabilityData _data = ProfitabilityData.vacio;
  bool _loading = false;
  String? _error;
  String? _cacheKey;

  ProfitabilityData get data => _data;
  bool get loading => _loading;
  String? get error => _error;

  /// Identifica un cálculo. Incluye cuántas órdenes y gastos tenía el
  /// dashboard, y no solo el período y la sucursal: las ventas salen de esos
  /// datos, así que cuando terminan de llegar el resultado anterior quedó
  /// viejo aunque el período no haya cambiado.
  static String _keyOf(DashboardProvider dash) =>
      '${dash.range.start.toIso8601String()}'
      '|${dash.range.end.toIso8601String()}'
      '|${dash.selectedLocationId ?? "*"}'
      '|${dash.currentOrders.length}'
      // En la vista de año no hay órdenes en memoria y el contador de arriba se
      // queda en cero para siempre: sin esto, un cálculo hecho antes de que
      // llegaran los totales se quedaría cacheado mostrando venta cero.
      '|${dash.metrics?.totalSales.toStringAsFixed(2) ?? "-"}'
      '|${dash.expenseItems.length}'
      '|${dash.purchaseItems.length}';

  /// Período y sucursal: lo que el usuario está mirando. Si esto cambia, lo
  /// que hay en pantalla dejó de corresponder, aunque siga siendo un cálculo
  /// válido del mes anterior.
  static String _contextoOf(DashboardProvider dash) =>
      '${dash.range.start.toIso8601String()}'
      '|${dash.range.end.toIso8601String()}'
      '|${dash.selectedLocationId ?? "*"}';

  String? _contextoMostrado;
  String? _contextoPedido;
  Future<_Inventario>? _invPendiente;
  Future<_Cogs>? _cogsPendiente;

  /// Recalcula solo si cambió algo de lo que depende el resultado.
  Future<void> loadIfNeeded(DashboardProvider dash) async {
    final ctx = _contextoOf(dash);

    // Cambió el mes o la sucursal: lo que se ve ya no es de este período. Se
    // vacía y se muestra el spinner en vez de dejar los números viejos, que
    // sin ningún aviso se leen como si fueran los nuevos.
    if (ctx != _contextoMostrado) {
      _contextoMostrado = ctx;
      _data = ProfitabilityData.vacio;
      _error = null;
      _loading = true;
      _cacheKey = null;
      notifyListeners();
    }

    // Las consultas propias (costo e inventario) no dependen del dashboard:
    // se lanzan apenas cambia el período, en paralelo con su carga, en vez de
    // esperar a que termine para recién empezar.
    _lanzarConsultas(dash, ctx);

    // Con el dashboard a medio cargar sus listas están vacías: calcular ahora
    // daría ventas en cero y la caché dejaría ese cero congelado aunque los
    // datos lleguen un instante después.
    if (dash.loading) return;

    final key = _keyOf(dash);
    if (key == _cacheKey && !_loading) return;
    await load(dash);
  }

  void _lanzarConsultas(DashboardProvider dash, String ctx) {
    if (ctx == _contextoPedido) return;
    final tenantId = dash.tenantId;
    if (tenantId == null) return;

    _contextoPedido = ctx;
    final inv = _fetchValorInventario(tenantId, dash.selectedLocationId);
    // El costo necesita los precios del inventario para estimar lo que no
    // quedó sellado, así que se encadena en vez de ir en paralelo.
    final cogs = inv.then((i) => _fetchCogs(
          tenantId,
          dash.range,
          dash.selectedLocationId,
          i.precioPorIngrediente,
        ));

    // Sin esto, un fallo mientras nadie está esperando el Future sube como
    // error no capturado y tumba la zona async.
    inv.ignore();
    cogs.ignore();

    _invPendiente = inv;
    _cogsPendiente = cogs;
  }

  Future<void> load(DashboardProvider dash) async {
    final tenantId = dash.tenantId;
    if (tenantId == null) return;

    _cacheKey = _keyOf(dash);
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Ventas, gastos y compras ya están en memoria: los trajo el dashboard.
      // El costo y el inventario salen de las consultas que _lanzarConsultas
      // disparó apenas cambió el período — para cuando el dashboard termina,
      // normalmente ya están resueltas y no hay nada más que esperar.
      _lanzarConsultas(dash, _contextoOf(dash));
      final inventario = await _invPendiente!;
      final cogs = await _cogsPendiente!;

      // Mientras se esperaba, el usuario pudo cambiar de mes otra vez. Estos
      // números son del período viejo: pintarlos sería el mismo error que se
      // está arreglando.
      if (_contextoOf(dash) != _contextoMostrado) return;

      _data = _armar(dash, cogs, inventario);
      _loading = false;
      notifyListeners();
    } catch (e, stack) {
      _loading = false;
      // El detalle va a la pantalla, no solo al log: en web la consola del
      // navegador no siempre está a mano, y un "no se pudo" a secas no deja
      // avanzar a nadie.
      _error = 'No se pudo calcular la rentabilidad.\n\n$e';
      debugPrint('[RENTABILIDAD] $e\n$stack');
      notifyListeners();
    }
  }

  // ── Costo de lo vendido ────────────────────────────────────────────────
  //
  // Se lee de los movimientos de inventario, que sellan `totalCost` con el
  // precio del ingrediente al momento de descontarlo. Es el dato histórico
  // correcto: valorizar hoy con el precio de hoy reescribiría el pasado cada
  // vez que sube un proveedor.
  Future<_Cogs> _fetchCogs(
    String tenantId,
    DateRange range,
    String? locationId,
    Map<String, double> precioActual,
  ) async {
    final desde = DateTime(range.start.year, range.start.month, range.start.day);
    final hasta = DateTime(
        range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);

    // `createdAt` se guarda como String ISO local (lo escribe el POS), así que
    // el rango también va como String. Índice (tenantId, type, createdAt): ya
    // existe en producción.
    final snap = await _db
        .collection('inventoryMovements')
        .where('tenantId', isEqualTo: tenantId)
        // Las dos direcciones en una sola consulta: lo que salió por venta
        // (el costo) y lo que entró (la inversión en despensa).
        .where('type', whereIn: const [_tipoSalidaVenta, _tipoEntrada])
        .where('createdAt', isGreaterThanOrEqualTo: desde.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: hasta.toIso8601String())
        // Un mes de tres sucursales son decenas de miles de movimientos y en
        // el navegador eso se paga en memoria. El tope se aplica sobre datos
        // ya filtrados por período, así que en la práctica no se alcanza; si
        // se alcanzara, el costo saldría corto y el aviso de cobertura lo
        // delata en vez de mentir en silencio.
        .limit(8000)
        .get();

    var total = 0.0;
    var exactos = 0;
    var estimados = 0;
    var sinCosto = 0;
    var comprado = 0.0;
    var entradasSinCosto = 0;

    for (final doc in snap.docs) {
      final d = doc.data();
      if (locationId != null && d['locationId'] != locationId) continue;

      // Mercadería que entró: es inversión en despensa, no costo del período.
      // Se acumula aparte y NO toca la cascada.
      if (d['type'] == _tipoEntrada) {
        final costoEntrada = (d['totalCost'] as num?)?.toDouble();
        if (costoEntrada != null) {
          comprado += costoEntrada.abs();
        } else {
          // Entrada sin costo: no se puede valorizar. Se cuenta para poder
          // decir que lo invertido está incompleto en vez de dar por bueno un
          // número corto.
          entradasSinCosto++;
        }
        continue;
      }

      // Las salidas guardan cantidad negativa; lo que suma al costo es su
      // magnitud.
      final costo = (d['totalCost'] as num?)?.toDouble();
      if (costo != null) {
        total += costo.abs();
        exactos++;
        continue;
      }

      // Sin costo sellado. Pasa con las ventas anteriores a que el ingrediente
      // tuviera precio cargado —o a que el POS empezara a sellarlo—, y ese
      // dato histórico ya no existe. Antes que devolver cero (que se ve igual
      // que "no gasté nada" y regala margen), se estima con el precio de HOY
      // del mismo ingrediente. Se cuenta aparte para poder decir en pantalla
      // qué parte del costo es exacta y qué parte es estimación.
      final ingId = d['ingredientId'] as String?;
      final precio = ingId == null ? null : precioActual[ingId];
      final cantidad = (d['quantity'] as num?)?.toDouble();

      if (precio != null && cantidad != null && cantidad != 0) {
        total += precio * cantidad.abs();
        estimados++;
      } else {
        sinCosto++;
      }
    }

    return _Cogs(
      total: total,
      exactos: exactos,
      estimados: estimados,
      sinCosto: sinCosto,
      comprado: comprado,
      entradasSinCosto: entradasSinCosto,
    );
  }

  // ── Valor de la despensa ───────────────────────────────────────────────
  //
  // Foto de HOY, no del período: no hay histórico de cuánto valía la despensa
  // en una fecha pasada. Se valoriza a precio de compra, que es lo que costó,
  // y no a precio de venta, que mezclaría ganancia futura con capital.
  Future<_Inventario> _fetchValorInventario(
    String tenantId,
    String? locationId,
  ) async {
    final snap = await _db
        .collection('ingredients')
        .where('tenant_id', isEqualTo: tenantId)
        .get();

    var total = 0.0;
    var sinPrecio = 0;
    final precios = <String, double>{};
    final sospechosos = <String>[];

    for (final doc in snap.docs) {
      final d = doc.data();
      if ((d['active'] as bool? ?? true) == false) continue;

      final precio = (d['lastPurchasePrice'] as num?)?.toDouble();
      // El precio se guarda de TODA sucursal, aun de las que no se están
      // mirando: el mismo ingrediente puede tener movimientos en varias y lo
      // que se busca es su precio, no su stock local.
      if (precio != null && precio > 0) precios[doc.id] = precio;

      if (locationId != null && d['location_id'] != locationId) continue;

      final stock = (d['currentStock'] as num?)?.toDouble() ?? 0;
      if (stock <= 0) continue;

      // Existencias imposibles: alguien escribió un número gigante para que ese
      // ingrediente nunca se agote y no le bloquee la venta. El valor SÍ las
      // sigue sumando (cambiarlo sería tocar el inventario, y el dueño pidió
      // que no), pero se avisa cuáles son para que pueda corregirlas.
      if (stock >= kStockImposible) {
        sospechosos.add(d['name'] as String? ?? 'sin nombre');
      }

      if (precio == null || precio <= 0) {
        sinPrecio++;
        continue;
      }
      total += stock * precio;
    }

    sospechosos.sort();
    return _Inventario(
      valor: total,
      sinPrecio: sinPrecio,
      precioPorIngrediente: precios,
      existenciasImposibles: sospechosos,
    );
  }

  // ── Armado ─────────────────────────────────────────────────────────────
  ProfitabilityData _armar(
    DashboardProvider dash,
    _Cogs cogs,
    _Inventario inv,
  ) {
    final locId = dash.selectedLocationId;

    // Venta neta: lo cobrado menos propina y envío. La propina es del personal
    // y el envío se cobra para pagarlo; ninguno es ingreso del negocio.
    //
    // En la vista de año el dashboard no baja las órdenes (los totales los suma
    // Firestore), así que la venta sale de las métricas, que ya son esa misma
    // resta y ya vienen filtradas por sucursal. Sin esto la rentabilidad anual
    // daría venta cero y una pérdida inventada del tamaño de los gastos.
    final m = dash.metrics;
    final sinOrdenesEnMemoria = m != null && dash.sinOrdenesEnMemoria;

    var netSales = 0.0;
    if (sinOrdenesEnMemoria) {
      // `ventaBruta` es exactamente cobrado menos propina y envío, ya filtrado
      // por sucursal por las consultas de agregación.
      netSales = m.ventaBruta;
    } else {
      for (final o in dash.currentOrders) {
        if (locId != null && o['location_id'] != locId) continue;
        final cobrado = (o['payment_amount'] as num?)?.toDouble() ??
            (o['total_amount'] as num? ?? 0).toDouble();
        final propina = (o['tip_amount'] as num? ?? 0).toDouble();
        final envio = (o['delivery_fee'] as num? ?? 0).toDouble();
        netSales += cobrado - propina - envio;
      }
    }

    // Gastos por categoría. Los retiros de caja vienen mezclados en la misma
    // lista (el dashboard los inyecta) y CUENTAN COMO GASTO igual que los
    // manuales: en los datos reales son insumos, pago a proveedores, sueldos,
    // gas y gasolina pagados en efectivo desde la caja. Es operación, no
    // reparto de utilidad. Sacarlos de la cuenta —como se hacía antes— infla
    // la ganancia y deja los sueldos pagados así fuera del costo primo.
    //
    // Se sigue midiendo cuánto de todo eso salió por caja, pero como dato
    // informativo, no como una resta aparte.
    final porCategoria = <String, ExpenseLine>{};
    var sueldos = 0.0;
    var pagadoEnEfectivo = 0.0;

    for (final e in dash.expenseItems) {
      if (locId != null && e['location_id'] != locId) continue;
      final monto = (e['amount'] as num? ?? 0).toDouble();
      if (monto == 0) continue;

      if (e['source'] == 'cashRegister') pagadoEnEfectivo += monto;

      final id = (e['category_id'] as String?) ?? 'otros';
      final nombre = (e['category_name'] as String?) ?? 'Otros gastos';
      if (_idsSueldos.contains(id)) sueldos += monto;

      // El POS marca cada gasto como 'fixed' o 'variable' al crearlo, pero los
      // retiros de caja llegan siempre como 'variable'; por eso la categoría
      // también decide. Ante la duda, variable: contar de más en los fijos
      // infla el punto de equilibrio y le diría al usuario que necesita vender
      // más de lo que realmente necesita.
      final esFijo = e['type'] == 'fixed' || _idsFijos.contains(id);

      final previa = porCategoria[id];
      porCategoria[id] = ExpenseLine(
        categoryId: id,
        label: nombre,
        amount: (previa?.amount ?? 0) + monto,
        esFijo: previa?.esFijo ?? esFijo,
      );
    }

    final lineas = porCategoria.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // Compras: informativas. No se restan — el gasto de esa mercadería ya lo
    // cuenta el costo de lo vendido cuando se vende. Restar ambas sería
    // contar dos veces lo mismo.
    //
    // El monto sale de las ENTRADAS de inventario (cogs.comprado) y no de la
    // colección de compras: en los datos reales muchas entradas con costo
    // nunca generan documento de compra, y leyendo solo allí esto mostraba
    // Q0.00 con 64 entradas valorizadas en el mismo período. Si por alguna
    // razón no hubiera entradas pero sí órdenes de compra, se usa esa segunda
    // fuente en vez de mostrar cero.
    var comprasFormales = 0.0;
    for (final p in dash.purchaseItems) {
      if (locId != null && p['location_id'] != locId) continue;
      comprasFormales += (p['total'] as num? ?? 0).toDouble();
    }
    final compras = cogs.comprado > 0 ? cogs.comprado : comprasFormales;

    return ProfitabilityData(
      netSales: netSales,
      cogs: cogs.total,
      itemsConCosto: cogs.exactos,
      itemsEstimados: cogs.estimados,
      itemsSinCosto: cogs.sinCosto,
      expenses: lineas,
      payroll: sueldos,
      paidFromCash: pagadoEnEfectivo,
      purchases: compras,
      entradasSinCosto: cogs.entradasSinCosto,
      inventoryValue: inv.valor,
      ingredientesSinPrecio: inv.sinPrecio,
      existenciasImposibles: inv.existenciasImposibles,
    );
  }
}

class _Cogs {
  final double total;

  /// Con el costo sellado al momento de la venta. Es el dato bueno.
  final int exactos;

  /// Valorizados con el precio de hoy porque el histórico no existe.
  final int estimados;

  /// Ni sellado ni estimable: el ingrediente tampoco tiene precio hoy.
  final int sinCosto;

  /// Mercadería que entró a la despensa en el período, valorizada.
  final double comprado;

  /// Entradas que no traían costo: lo invertido queda corto y hay que decirlo.
  final int entradasSinCosto;

  const _Cogs({
    required this.total,
    required this.exactos,
    required this.estimados,
    required this.sinCosto,
    this.comprado = 0,
    this.entradasSinCosto = 0,
  });
}

class _Inventario {
  final double valor;
  final int sinPrecio;

  /// Nombres de los ingredientes con existencia imposible, para poder decirle
  /// al dueño CUÁLES revisar en vez de solo que algo anda mal.
  final List<String> existenciasImposibles;

  /// id de ingrediente → último precio de compra conocido.
  final Map<String, double> precioPorIngrediente;

  const _Inventario({
    required this.valor,
    required this.sinPrecio,
    this.existenciasImposibles = const [],
    required this.precioPorIngrediente,
  });
}
