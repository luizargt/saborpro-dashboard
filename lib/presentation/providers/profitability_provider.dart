import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/auth_service.dart';
import '../../core/utils/date_range.dart';
import '../../data/models/profitability_data.dart';
import '../../data/models/rentabilidad_calculo.dart';
import 'dashboard_provider.dart';

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

  /// Preparaciones de preproducción que se leen de un período, como mucho. Un
  /// mes son decenas o cientos; el tope cuida la memoria del navegador en la
  /// vista de año. Si se alcanza, lo restado a los gastos sale corto (nunca de
  /// más) y la pantalla lo dice.
  static const int _kPreparacionesLimit = 5000;

  /// Movimientos de inventario que se leen de una vez (ventas y entradas del
  /// período). Si se alcanza, el costo y lo comprado salen cortos: ver
  /// [CostoLeido.truncado].
  static const int _kMovimientosLimit = 8000;

  /// Sin red, una consulta puede quedarse esperando para siempre y el reporte
  /// entero espera con ella. Holgado a propósito, como el del menú: un año en
  /// una red lenta no debe confundirse con "sin conexión".
  static const _topePreproduccion = Duration(seconds: 30);

  ProfitabilityData _data = ProfitabilityData.vacio;

  /// Los mismos números, uno por sucursal (id → lo suyo). Solo se arma en
  /// "Todas", con las órdenes en memoria y más de una sucursal a la vista: es lo
  /// que dibuja "¿qué sucursal gana más?". Sale de la MISMA cuenta que [data].
  Map<String, ProfitabilityData> _porSucursal = const {};
  CostoLeido _costo = CostoLeido.vacio;
  bool _loading = false;
  String? _error;
  String? _cacheKey;

  ProfitabilityData get data => _data;
  Map<String, ProfitabilityData> get porSucursal => _porSucursal;

  /// El costo de lo vendido y lo comprado, con su desglose por día y por ingrediente
  /// (es lo que usa Compras vs Ventas). Vacío mientras no se calcula.
  CostoLeido get costo => _costo;
  bool get loading => _loading;
  String? get error => _error;

  /// Los números de [data] corresponden a lo que el dashboard muestra AHORA.
  ///
  /// El recálculo corre después de dibujar: justo tras cambiar de sucursal,
  /// durante un cuadro [data] todavía es de la anterior. Quien combine estos
  /// números con otros de la sucursal nueva (la utilidad por platillo) tiene
  /// que esperar a que esto sea cierto.
  bool alDiaCon(DashboardProvider dash) =>
      !_loading && _error == null && _cacheKey == _keyOf(dash);

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
      '|${dash.purchaseItems.length}'
      // Las sucursales pueden llegar después de armar: la comparación por
      // sucursal (que necesita ≥2) quedaría vacía hasta que cambiara otra cosa.
      '|${dash.locations.length}'
      '|${dash.firmaMoneda}';

  /// Período y sucursal: lo que el usuario está mirando. Si esto cambia, lo
  /// que hay en pantalla dejó de corresponder, aunque siga siendo un cálculo
  /// válido del mes anterior.
  static String _contextoOf(DashboardProvider dash) =>
      '${dash.range.start.toIso8601String()}'
      '|${dash.range.end.toIso8601String()}'
      '|${dash.selectedLocationId ?? "*"}'
      '|${dash.firmaMoneda}';

  String? _contextoMostrado;
  String? _contextoPedido;
  Future<_Inventario>? _invPendiente;
  Future<CostoLeido>? _cogsPendiente;
  Future<CargosPreproduccion>? _preproPendiente;

  /// Cada carga lleva un número y solo la última escribe el resultado. Al
  /// cambiar de sucursal o de mes a media carga, la vieja seguía esperando
  /// sus consultas y, al despertar, armaba con las ventas y los gastos de la
  /// sucursal NUEVA y el costo, el inventario o la preproducción de la VIEJA.
  /// Si además terminaba última, esa mezcla se quedaba en pantalla.
  int _generacion = 0;

  /// Recalcula solo si cambió algo de lo que depende el resultado.
  Future<void> loadIfNeeded(DashboardProvider dash) async {
    final ctx = _contextoOf(dash);

    // Cambió el mes o la sucursal: lo que se ve ya no es de este período. Se
    // vacía y se muestra el spinner en vez de dejar los números viejos, que
    // sin ningún aviso se leen como si fueran los nuevos.
    if (ctx != _contextoMostrado) {
      _contextoMostrado = ctx;
      _data = ProfitabilityData.vacio;
      _porSucursal = const {};
      _costo = CostoLeido.vacio;
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
    // Misma clave = ese cálculo ya está hecho o EN CURSO. Antes se relanzaba
    // mientras cargaba, y una pantalla que escucha a este provider (la lista
    // de Utilidad por platillo) entraba en bucle: cargar → avisar →
    // reconstruir → volver a cargar, un cuadro tras otro.
    if (key == _cacheKey) return;
    await load(dash);
  }

  void _lanzarConsultas(DashboardProvider dash, String ctx) {
    if (ctx == _contextoPedido) return;
    final tenantId = dash.tenantId;
    if (tenantId == null) return;

    _contextoPedido = ctx;
    // Costos e inventario se pasan a la moneda de la vista igual que las
    // ventas: cada uno con el tipo de cambio de su sucursal y su fecha.
    final factor = dash.factorDe;
    // Quien ve solo algunas sucursales, en "Todas" ve solo las suyas (como en
    // ventas y gastos). Antes sumaba el costo de todo el negocio.
    final permitidas = AuthService().assignedLocationIds.toSet();
    final inv = _fetchValorInventario(tenantId, dash.selectedLocationId, factor, permitidas);
    // El costo necesita los precios del inventario para estimar lo que no
    // quedó sellado, así que se encadena en vez de ir en paralelo.
    final cogs = inv.then((i) => _fetchCogs(
          tenantId,
          dash.range,
          dash.selectedLocationId,
          i.precioPorIngrediente,
          factor,
          permitidas,
        ));

    // Sin esto, un fallo mientras nadie está esperando el Future sube como
    // error no capturado y tumba la zona async.
    inv.ignore();
    cogs.ignore();

    _invPendiente = inv;
    _cogsPendiente = cogs;
    _preproPendiente = _pedirPreproduccion(dash);
  }

  /// La preproducción del período y la sucursal que se están mirando, con las
  /// mismas sucursales permitidas y la misma moneda que los gastos.
  Future<CargosPreproduccion> _pedirPreproduccion(DashboardProvider dash) {
    final f = _fetchPreproduccion(
      dash.tenantId!,
      dash.range,
      dash.selectedLocationId,
      dash.factorDe,
      AuthService().assignedLocationIds.toSet(),
    );
    f.ignore();
    return f;
  }

  Future<void> load(DashboardProvider dash) async {
    final tenantId = dash.tenantId;
    if (tenantId == null) return;

    final generacion = ++_generacion;
    final contexto = _contextoOf(dash);
    final clave = _keyOf(dash);
    _cacheKey = clave;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Ventas, gastos y compras ya están en memoria: los trajo el dashboard.
      // El costo y el inventario salen de las consultas que _lanzarConsultas
      // disparó apenas cambió el período — para cuando el dashboard termina,
      // normalmente ya están resueltas y no hay nada más que esperar.
      _lanzarConsultas(dash, contexto);
      // Los pedidos de ESTA carga se toman antes de esperar: si a media
      // espera se cambia de sucursal, _lanzarConsultas pone otros en su lugar.
      final invPedido = _invPendiente!;
      final cogsPedido = _cogsPendiente!;
      // Si la última lectura de la preproducción falló, se vuelve a pedir, y
      // solo esa: es lo que hace "deslizar para reintentar". Se relanza acá y
      // no en loadIfNeeded, que corre en cada cuadro: con la red caída
      // repetiría la consulta sin fin.
      final preproPedida = _preproPendiente ??= _pedirPreproduccion(dash);
      final inventario = await invPedido;
      final cogs = await cogsPedido;
      final prepro = await preproPedida;

      // Empezó otra carga mientras esta esperaba: la que vale es esa.
      if (generacion != _generacion) return;

      // Sin preproducción el reporte sale igual, sin restar nada y con el
      // aviso; la próxima carga la vuelve a pedir.
      if (!prepro.leida && identical(_preproPendiente, preproPedida)) {
        _preproPendiente = null;
      }

      // Mientras se esperaba, el usuario pudo cambiar de mes otra vez. Estos
      // números son del período viejo: pintarlos sería el mismo error que se
      // está arreglando.
      if (_contextoOf(dash) != _contextoMostrado) {
        // Sin esto, volver a este mismo período dentro del mismo cuadro
        // encontraba la clave ya puesta y no recalculaba: spinner eterno.
        _cacheKey = null;
        return;
      }
      // Cambió el mes o la sucursal y la carga nueva todavía no arranca, o el
      // dashboard se está recargando (o ya trajo otra cosa): armar ahora
      // mezclaría contextos o daría ventas en cero con sus listas a medio
      // llenar. Sin clave, loadIfNeeded vuelve a calcular cuando el dashboard
      // termine, aunque traiga exactamente lo mismo.
      if (_contextoOf(dash) != contexto ||
          dash.loading ||
          _keyOf(dash) != clave) {
        _cacheKey = null;
        return;
      }

      _data = _armar(dash, cogs, inventario, prepro);
      _porSucursal = _armarPorSucursal(dash, cogs, prepro);
      _costo = cogs;
      _loading = false;
      notifyListeners();
    } catch (e, stack) {
      // El fallo de una carga ya reemplazada, o de un mes o una sucursal que
      // ya no se miran, no es de lo que está en pantalla. Sin clave, volver a
      // ese contexto lo recalcula en vez de esperar esta carga para siempre.
      if (generacion != _generacion) return;
      if (_contextoOf(dash) != contexto) {
        _cacheKey = null;
        return;
      }
      _loading = false;
      // Las consultas de costo e inventario se reutilizan mientras no cambie
      // el período: si una falló, "deslizar para reintentar" volvía a esperar
      // el MISMO futuro fallido y repetía el error. Así se relanzan.
      _contextoPedido = null;
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
  Future<CostoLeido> _fetchCogs(
    String tenantId,
    DateRange range,
    String? locationId,
    Map<String, double> precioActual,
    double? Function(String? locationId, DateTime? fecha) factorDe,
    Set<String> permitidas,
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
        .limit(_kMovimientosLimit)
        .get();

    // Lo del total y lo de cada sucursal se acumulan en el mismo paso, con las
    // mismas reglas: la comparación entre sucursales no puede salir de otra
    // cuenta que el total.
    final global = _AcumCosto(detallado: true);
    final porSucursal = <String, _AcumCosto>{};

    for (final doc in snap.docs) {
      final d = doc.data();
      if (locationId != null && d['locationId'] != locationId) continue;
      if (locationId == null && permitidas.isNotEmpty && !permitidas.contains(d['locationId'])) {
        continue;
      }
      final rawFecha = d['createdAt'];
      final factor = factorDe(
          d['locationId'] as String?, rawFecha is String ? DateTime.tryParse(rawFecha) : null);
      // Moneda sin tipo de cambio: no se puede sumar con lo demás.
      if (factor == null) continue;

      final sucursal = d['locationId'];
      // El día y el ingrediente de este movimiento, para el desglose del total.
      final dia = rawFecha is String && _esDia.hasMatch(rawFecha.length >= 10 ? rawFecha.substring(0, 10) : '')
          ? rawFecha.substring(0, 10)
          : null;
      final ingrediente = d['ingredientId'] is String ? d['ingredientId'] as String : null;
      final acums = [
        global,
        if (sucursal is String) porSucursal.putIfAbsent(sucursal, _AcumCosto.new),
      ];

      // Mercadería que entró: es inversión en despensa, no costo del período.
      // Se acumula aparte y NO toca la cascada.
      if (d['type'] == _tipoEntrada) {
        final costoEntrada = (d['totalCost'] as num?)?.toDouble();
        if (costoEntrada != null) {
          for (final a in acums) {
            a.compra(costoEntrada.abs() * factor, dia, ingrediente);
          }
        } else {
          // Entrada sin costo: no se puede valorizar. Se cuenta para poder
          // decir que lo invertido está incompleto en vez de dar por bueno un
          // número corto.
          for (final a in acums) {
            a.entradasSinCosto++;
          }
        }
        continue;
      }

      // Las salidas guardan cantidad negativa; lo que suma al costo es su
      // magnitud.
      final costo = (d['totalCost'] as num?)?.toDouble();
      if (costo != null) {
        for (final a in acums) {
          a.usa(costo.abs() * factor, dia, ingrediente);
          a.exactos++;
        }
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
        for (final a in acums) {
          a.usa(precio * cantidad.abs() * factor, dia, ingrediente);
          a.estimados++;
        }
      } else {
        for (final a in acums) {
          a.sinCosto++;
        }
      }
    }

    return global.aCosto(
      porSucursal: {for (final e in porSucursal.entries) e.key: e.value.aCosto()},
      truncado: snap.docs.length >= _kMovimientosLimit,
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
    double? Function(String? locationId, DateTime? fecha) factorDe,
    Set<String> permitidas,
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
      if (locationId == null && permitidas.isNotEmpty && !permitidas.contains(d['location_id'])) {
        continue;
      }

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
      // Foto de hoy: se convierte con el tipo de cambio de hoy.
      final factor = factorDe(d['location_id'] as String?, null);
      if (factor == null) continue;
      total += stock * precio * factor;
    }

    sospechosos.sort();
    return _Inventario(
      valor: total,
      sinPrecio: sinPrecio,
      precioPorIngrediente: precios,
      existenciasImposibles: sospechosos,
    );
  }

  // ── Preproducción ──────────────────────────────────────────────────────
  //
  // Lo que las recetas de preproducción cargan por tiempo (gas, luz, mano de
  // obra) entra al costo de lo vendido con cada venta del preparado (ver
  // CargosPreproduccion). Se lee para restárselo a esas mismas categorías de
  // gasto.
  //
  // Nunca lanza: si falla, devuelve "no leída" y el reporte sale igual, con
  // los gastos completos y el aviso. Un error acá no puede dejar al dueño sin
  // su rentabilidad.
  Future<CargosPreproduccion> _fetchPreproduccion(
    String tenantId,
    DateRange range,
    String? locationId,
    double? Function(String? locationId, DateTime? fecha) factorDe,
    Set<String> permitidas,
  ) async {
    // El mismo período que los gastos: días completos.
    final desde = DateTime(range.start.year, range.start.month, range.start.day);
    final hasta = DateTime(
        range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);

    try {
      // `executedAt` lo escribe el POS como String ISO local, igual que el
      // `createdAt` de los movimientos del costo, así que el rango también va
      // como String. Solo por rango: no hace falta índice compuesto. La
      // sucursal se filtra en memoria, como en el resto del reporte.
      //
      // Siempre al servidor: sin red, `.get()` normal puede devolver un
      // resultado VACÍO sin lanzar nada, y eso se leería como "no se cargó
      // nada" en vez de "no se pudo leer".
      final snap = await _db
          .collection('tenants')
          .doc(tenantId)
          .collection('transformationExecutions')
          .where('executedAt', isGreaterThanOrEqualTo: desde.toIso8601String())
          .where('executedAt', isLessThanOrEqualTo: hasta.toIso8601String())
          .limit(_kPreparacionesLimit)
          .get(const GetOptions(source: Source.server))
          .timeout(_topePreproduccion);

      final docs = [for (final d in snap.docs) d.data()];
      final completa = snap.docs.length < _kPreparacionesLimit;
      final total = CargosPreproduccion.sumar(
        docs,
        sucursal: locationId,
        permitidas: permitidas,
        factorDe: factorDe,
        completa: completa,
      );
      // Lo mismo por sucursal, para compararlas con la misma cuenta.
      final sucursales = {
        for (final p in docs)
          if (p['locationId'] is String) p['locationId'] as String,
      };
      return total.conPorSucursal({
        for (final id in sucursales)
          id: CargosPreproduccion.sumar(
            docs,
            sucursal: id,
            factorDe: factorDe,
            completa: completa,
          ),
      });
    } catch (e, stack) {
      debugPrint('[RENTABILIDAD] preproducción: $e\n$stack');
      return CargosPreproduccion.noLeida;
    }
  }

  // ── Armado ─────────────────────────────────────────────────────────────
  //
  // La cuenta vive en [armarRentabilidad] (rentabilidad_calculo.dart): la usan
  // el total y cada sucursal.
  ProfitabilityData _armar(
    DashboardProvider dash,
    CostoLeido cogs,
    _Inventario inv,
    CargosPreproduccion prepro,
  ) {
    final m = dash.metrics;
    return armarRentabilidad(
      ordenes: dash.currentOrders,
      gastos: dash.expenseItems,
      compras: dash.purchaseItems,
      sucursal: dash.selectedLocationId,
      // En la vista de año no hay órdenes en memoria: la venta sale de las
      // métricas (ver armarRentabilidad).
      ventaDeMetricas: m != null && dash.sinOrdenesEnMemoria ? m.ventaBruta : null,
      costo: cogs,
      valorInventario: inv.valor,
      ingredientesSinPrecio: inv.sinPrecio,
      existenciasImposibles: inv.existenciasImposibles,
      prepro: prepro,
    );
  }

  /// Lo mismo por cada sucursal a la vista, para compararlas. Solo en "Todas",
  /// con las órdenes en memoria (en la vista de año no hay pedidos por sucursal)
  /// y con más de una sucursal. El inventario y las compras no se separan: no
  /// entran en la comparación.
  Map<String, ProfitabilityData> _armarPorSucursal(
    DashboardProvider dash,
    CostoLeido cogs,
    CargosPreproduccion prepro,
  ) {
    if (dash.selectedLocationId != null || dash.sinOrdenesEnMemoria) return const {};
    if (dash.locations.length < 2) return const {};
    return {
      for (final l in dash.locations)
        l.id: armarRentabilidad(
          ordenes: dash.currentOrders,
          gastos: dash.expenseItems,
          compras: const [],
          sucursal: l.id,
          costo: cogs.porSucursal[l.id] ?? CostoLeido.vacio,
          prepro: prepro.porSucursal[l.id] ?? CargosPreproduccion(leida: prepro.leida, completa: prepro.completa),
        ),
    };
  }
}

/// "2026-10-14": el día de un movimiento (su `createdAt` es texto ISO local).
final _esDia = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class _Par {
  double costo = 0;
  double comprado = 0;
}

/// Suma el costo de lo vendido mientras se recorren los movimientos. Uno para
/// el total (con el desglose por día y por ingrediente) y uno por cada sucursal.
class _AcumCosto {
  _AcumCosto({this.detallado = false});

  /// Solo el del total guarda el desglose: por sucursal serían tres copias de lo
  /// mismo en memoria.
  final bool detallado;

  double total = 0;
  int exactos = 0;
  int estimados = 0;
  int sinCosto = 0;
  double comprado = 0;
  int entradasSinCosto = 0;
  final _porDia = <String, _Par>{};
  final _porIngrediente = <String, _Par>{};

  /// Lo que salió por una venta.
  void usa(double monto, String? dia, String? ingrediente) {
    total += monto;
    if (!detallado) return;
    if (dia != null) (_porDia[dia] ??= _Par()).costo += monto;
    if (ingrediente != null) (_porIngrediente[ingrediente] ??= _Par()).costo += monto;
  }

  /// Mercadería que entró.
  void compra(double monto, String? dia, String? ingrediente) {
    comprado += monto;
    if (!detallado) return;
    if (dia != null) (_porDia[dia] ??= _Par()).comprado += monto;
    if (ingrediente != null) (_porIngrediente[ingrediente] ??= _Par()).comprado += monto;
  }

  CostoLeido aCosto({Map<String, CostoLeido> porSucursal = const {}, bool truncado = false}) => CostoLeido(
        total: total,
        exactos: exactos,
        estimados: estimados,
        sinCosto: sinCosto,
        comprado: comprado,
        entradasSinCosto: entradasSinCosto,
        porSucursal: porSucursal,
        porDia: {for (final e in _porDia.entries) e.key: ParCosto(e.value.costo, e.value.comprado)},
        porIngrediente: {for (final e in _porIngrediente.entries) e.key: ParCosto(e.value.costo, e.value.comprado)},
        truncado: truncado,
      );
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
