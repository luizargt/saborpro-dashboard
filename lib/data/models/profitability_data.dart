import 'dart:math' as math;

import '../../core/utils/date_range.dart';
import '../../core/utils/formato_dinero.dart';

/// Una línea de gasto agrupada por categoría.
class ExpenseLine {
  final String categoryId;
  final String label;
  final double amount;

  /// Si el gasto ocurre igual vendas o no (renta, sueldos, seguros) o si
  /// acompaña al volumen (luz, gas, mantenimiento). Lo marca el POS al crear
  /// el gasto; es lo que permite calcular el punto de equilibrio.
  final bool esFijo;

  const ExpenseLine({
    required this.categoryId,
    required this.label,
    required this.amount,
    this.esFijo = false,
  });
}

/// Los números del reporte de Rentabilidad, ya calculados.
///
/// Sigue la cascada de un estado de resultados: cada resta responde una
/// pregunta distinta, y los porcentajes se miden siempre sobre la venta neta,
/// que es como se comparan los restaurantes entre sí y contra sí mismos.
class ProfitabilityData {
  /// Lo cobrado, sin propinas ni envíos.
  ///
  /// La propina no es del negocio (es del personal) y el envío se cobra para
  /// pagarlo: meterlos aquí infla la venta e hincha todos los porcentajes
  /// hacia abajo, haciendo parecer que se gasta menos de lo que se gasta.
  final double netSales;

  /// Lo que costaron los ingredientes que salieron por venta, con el precio
  /// congelado al momento de vender.
  final double cogs;

  /// Movimientos de venta sin costo ni forma de estimarlo. No se rellenan con
  /// cero: se cuentan y se muestran, porque un costo bajo por falta de datos se
  /// ve idéntico a uno bajo por buena gestión.
  final int itemsSinCosto;

  /// Con el costo sellado al momento de vender. El dato bueno.
  final int itemsConCosto;

  /// Valorizados con el precio de compra de HOY porque el histórico no quedó
  /// grabado. Sirven —es mucho mejor que contarlos en cero— pero el número
  /// deja de ser exacto y la pantalla tiene que decirlo.
  final int itemsEstimados;

  /// Gastos operativos por categoría, de mayor a menor.
  ///
  /// Ya sin lo que la preproducción cargó al costo del preparado (ver
  /// [restadoPreproduccion]): esa parte entra a [cogs] al venderse, y dejarla
  /// también acá la contaría dos veces. El reparto por platillo lee estas
  /// mismas líneas.
  final List<ExpenseLine> expenses;

  /// Sueldos, separado porque entra en el costo primo. Igual a su línea en
  /// [expenses], ya con la resta de la preproducción: la mano de obra cargada
  /// a una receta entra a [cogs], y el costo primo la sumaría dos veces.
  final double payroll;

  /// Cuánto de los gastos salió en efectivo desde la caja.
  ///
  /// Es informativo y ya está DENTRO de [expenses]: en los datos reales estos
  /// retiros son insumos, pago a proveedores, sueldos y gasolina — operación,
  /// no reparto de utilidad. Antes se restaban aparte y eso inflaba la
  /// ganancia y dejaba fuera del costo primo los sueldos pagados así.
  final double paidFromCash;

  /// Mercadería que entró a la despensa en el período. Tampoco es gasto: es
  /// inversión. El gasto ya está contado en [cogs] cuando esa mercadería se
  /// vende.
  final double purchases;

  /// Entradas de mercadería sin costo cargado. Lo invertido queda corto en
  /// exactamente esas, y callarlo haría parecer que se compró menos.
  final int entradasSinCosto;

  /// Valor de la despensa hoy, a precio de compra. Es una foto del momento,
  /// no del período.
  final double inventoryValue;
  final int ingredientesSinPrecio;

  /// Ingredientes con una existencia que no puede ser real (más de un millón de
  /// unidades). Suelen ser un número gigante escrito a mano para que ese
  /// producto nunca se agote. Se listan para que el dueño sepa cuáles revisar:
  /// el valor de la despensa los sigue contando, así que la cifra se dispara.
  final List<String> existenciasImposibles;

  /// Lo que las recetas de preproducción cargaron por tiempo (gas, luz, mano
  /// de obra) en el período. Informativo. Entra a [cogs] con cada venta del
  /// preparado, a su costo por unidad; se resta según lo PREPARADO en el
  /// período, que es la regla acordada: lo preparado y no vendido (o tirado)
  /// en el período se resta igual.
  final double cargadoPreproduccion;

  /// Cuánto de [cargadoPreproduccion] se le restó a [expenses]. Es menos
  /// cuando una categoría tiene menos anotado en Gastos de lo que se cargó
  /// (ver [excesosPreproduccion]): ninguna baja de cero.
  final double restadoPreproduccion;

  /// Categorías donde lo cargado a la preproducción pasa lo anotado en Gastos.
  final List<ExcesoPreproduccion> excesosPreproduccion;

  /// False si no se pudo leer la preproducción del período. Entonces no se
  /// resta nada —restar sin saber cuánto podría regalar utilidad— y la
  /// pantalla avisa que esos gastos pueden estar contados dos veces.
  final bool preproduccionLeida;

  /// False si el período tiene más preparaciones de las que se leen de una
  /// vez: lo restado sale corto (nunca de más) y se avisa.
  final bool preproduccionCompleta;

  const ProfitabilityData({
    required this.netSales,
    required this.cogs,
    required this.itemsSinCosto,
    required this.itemsConCosto,
    this.itemsEstimados = 0,
    required this.expenses,
    required this.payroll,
    required this.paidFromCash,
    required this.purchases,
    this.entradasSinCosto = 0,
    required this.inventoryValue,
    required this.ingredientesSinPrecio,
    this.existenciasImposibles = const [],
    this.cargadoPreproduccion = 0,
    this.restadoPreproduccion = 0,
    this.excesosPreproduccion = const [],
    this.preproduccionLeida = true,
    this.preproduccionCompleta = true,
  });

  static const vacio = ProfitabilityData(
    netSales: 0,
    cogs: 0,
    itemsSinCosto: 0,
    itemsConCosto: 0,
    itemsEstimados: 0,
    expenses: [],
    payroll: 0,
    paidFromCash: 0,
    purchases: 0,
    entradasSinCosto: 0,
    inventoryValue: 0,
    ingredientesSinPrecio: 0,
  );

  bool get sinDatos => netSales == 0 && cogs == 0 && expenses.isEmpty;

  double get grossProfit => netSales - cogs;
  double get totalExpenses =>
      expenses.fold<double>(0, (a, e) => a + e.amount);
  double get operatingProfit => grossProfit - totalExpenses;

  /// Porcentaje sobre la venta neta. Sin ventas no hay porcentaje que valga:
  /// devolver 0 sería decir "0% de costo", que es lo contrario de la verdad.
  double? pct(double monto) => netSales > 0 ? monto / netSales * 100 : null;

  double? get foodCostPct => pct(cogs);
  double? get payrollPct => pct(payroll);
  double? get marginPct => pct(operatingProfit);

  /// Comida + sueldos. El número más vigilado del rubro: por encima de ~65%
  /// no alcanza por más que se venda.
  double? get primeCostPct => pct(cogs + payroll);

  int get itemsTotales => itemsConCosto + itemsEstimados + itemsSinCosto;

  /// Qué parte de lo vendido tiene algún costo detrás — sellado o estimado.
  /// Lo que queda fuera cuenta como cero y regala margen.
  double? get coberturaCosto {
    if (itemsTotales == 0) return null;
    return (itemsConCosto + itemsEstimados) / itemsTotales * 100;
  }

  /// Qué parte del costo se apoya en precios de hoy en vez del histórico.
  double? get porcentajeEstimado {
    if (itemsTotales == 0) return null;
    return itemsEstimados / itemsTotales * 100;
  }

  /// Confiable = casi todo cubierto Y casi nada estimado. Un costo cubierto al
  /// 100% pero estimado al 100% no es exacto: usa los precios de hoy para
  /// valorizar ventas de hace meses.
  bool get costoConfiable =>
      (coberturaCosto ?? 0) >= 90 && (porcentajeEstimado ?? 100) <= 10;

  /// El costo se armó sobre todo con precios actuales.
  bool get costoMayormenteEstimado => (porcentajeEstimado ?? 0) > 10;

  /// Cuántas veces se renovó la despensa en el período. Inventario que no rota
  /// es plata parada que además se echa a perder.
  double? get rotacion =>
      inventoryValue > 0 && cogs > 0 ? cogs / inventoryValue : null;

  // ── Punto de equilibrio ────────────────────────────────────────────────

  /// Lo que se paga aunque no se venda un solo plato.
  double get fixedCosts =>
      expenses.where((e) => e.esFijo).fold<double>(0, (a, e) => a + e.amount);

  /// Lo que sube y baja con las ventas: la comida más los gastos variables.
  double get variableCosts =>
      cogs +
      expenses.where((e) => !e.esFijo).fold<double>(0, (a, e) => a + e.amount);

  /// De cada quetzal vendido, cuánto queda para pagar los costos fijos.
  ///
  /// Es el corazón del punto de equilibrio: si de cada Q100 te quedan Q60
  /// después de pagar comida y variables, necesitás vender lo suficiente para
  /// que esos Q60 de cada 100 cubran la renta y los sueldos.
  double? get contributionMarginPct {
    if (netSales <= 0) return null;
    return (netSales - variableCosts) / netSales * 100;
  }

  /// Cuánto hay que vender en el período para no perder ni ganar.
  ///
  /// Null cuando no se puede calcular, y son dos casos muy distintos que la
  /// pantalla debe explicar por separado:
  /// - Sin ventas: no hay con qué medir la proporción de costos variables.
  /// - Margen de contribución en cero o negativo: cada venta cuesta más de lo
  ///   que ingresa, así que vender MÁS aumenta la pérdida. No existe un punto
  ///   donde se equilibre; el problema son los precios o el costo, no el
  ///   volumen.
  double? get breakEven {
    final margen = contributionMarginPct;
    if (margen == null || margen <= 0) return null;
    return fixedCosts / (margen / 100);
  }

  /// Qué parte del punto de equilibrio ya se cubrió (1.0 = justo en el punto).
  double? get avanceBreakEven {
    final be = breakEven;
    if (be == null || be <= 0) return null;
    return netSales / be;
  }

  /// Cuánto falta vender. Negativo o cero significa que ya se superó.
  double? get faltaParaBreakEven {
    final be = breakEven;
    return be == null ? null : be - netSales;
  }

  /// Vender más aumenta la pérdida en vez de reducirla.
  bool get pierdeConCadaVenta =>
      netSales > 0 && (contributionMarginPct ?? 0) <= 0;

  /// Sin gastos fijos cargados el punto de equilibrio da casi cero y engaña.
  /// Pasa siempre en rangos cortos: la renta se registra una vez al mes, así
  /// que un martes suelto no la incluye.
  bool get sinCostosFijos => fixedCosts <= 0;
}

/// Rangos de referencia del rubro restaurantero, para el semáforo.
enum Salud { bien, atencion, mal, desconocido }

Salud evaluarFoodCost(double? pct) {
  if (pct == null) return Salud.desconocido;
  if (pct <= 35) return Salud.bien;
  if (pct <= 40) return Salud.atencion;
  return Salud.mal;
}

Salud evaluarPrimeCost(double? pct) {
  if (pct == null) return Salud.desconocido;
  if (pct <= 65) return Salud.bien;
  if (pct <= 70) return Salud.atencion;
  return Salud.mal;
}

Salud evaluarMargen(double? pct) {
  if (pct == null) return Salud.desconocido;
  if (pct >= 10) return Salud.bien;
  if (pct >= 0) return Salud.atencion;
  return Salud.mal;
}

// ── Preproducción ───────────────────────────────────────────────────────────
//
// Salsas, masas y demás que la cocina prepara antes del servicio. Cada receta
// de preproducción puede llevar "otros costos" por tiempo (gas, luz, mano de
// obra), y el POS los mete en el costo por unidad del preparado, que guarda en
// el ingrediente como último precio de compra. De ahí entra al costo de cada
// receta que se vende, o sea al costo de lo vendido de la cascada.
//
// El negocio anota esos mismos gastos en Gastos (el recibo del gas, la
// planilla). Restados completos, la parte cargada a la preproducción se
// contaría dos veces: en el costo de lo vendido y en los gastos. Por eso a
// cada categoría de gasto se le resta lo que se le cargó a la preproducción en
// el mismo período, sin bajarla nunca de cero.
//
// Puro, sin Firestore, para poder probarlo. Los montos van en CENTAVOS
// enteros: con dobles, Q80.00 cargado en tres partes contra Q80.00 anotado
// podía decir que se cargó de más por una milésima. Cada lado se redondea UNA
// vez, ya sumado, igual que la línea de gasto: redondeando cada costo por su
// lado, tres montos convertidos de otra moneda daban un centavo de más.

/// Categoría de lo que no trae la suya: la de los gastos sin categoría, que es
/// también la que el POS le pone por defecto a un costo.
const _categoriaPorDefecto = 'otros';

/// Las categorías que el POS deja asignarle a un costo de preproducción, con
/// el nombre corto con que las muestra allí. Sirven para nombrar una categoría
/// que no tiene gastos en el período: decir "Sueldos" dice dónde anotarlo;
/// "Mano de obra" no.
const _nombresDeCategoria = {
  'gas': 'Gas',
  'luz': 'Luz',
  'agua': 'Agua',
  'salarios': 'Sueldos',
  'renta': 'Renta',
  'mantenimiento': 'Mantenimiento',
  'combustible': 'Combustible',
  'otros': 'Otros gastos',
};

String? _textoNoVacio(Object? v) =>
    v is String && v.trim().isNotEmpty ? v : null;

/// Lo que la preproducción le cargó al costo de los preparados en un período,
/// por categoría de gasto.
class CargosPreproduccion {
  /// Id de la categoría de gasto ('gas', 'luz', 'salarios'…) → centavos.
  final Map<String, int> porCategoria;

  /// Los costos que cargaron a cada categoría ("Gas", "Mano de obra"), para
  /// nombrar una categoría que el POS agregue después y acá no se conozca.
  final Map<String, List<String>> nombres;

  /// False si no se pudo leer (sin conexión, sin permiso, tardó demasiado).
  final bool leida;

  /// False si el período tiene más preparaciones de las que se leyeron.
  final bool completa;

  /// Lo mismo, separado por sucursal (id de sucursal → lo suyo): para comparar
  /// sucursales con la misma cuenta que el total.
  final Map<String, CargosPreproduccion> porSucursal;

  const CargosPreproduccion({
    this.porCategoria = const {},
    this.nombres = const {},
    this.leida = true,
    this.completa = true,
    this.porSucursal = const {},
  });

  /// Este mismo cargo, con lo suyo separado por sucursal.
  CargosPreproduccion conPorSucursal(Map<String, CargosPreproduccion> porSucursal) =>
      CargosPreproduccion(
        porCategoria: porCategoria,
        nombres: nombres,
        leida: leida,
        completa: completa,
        porSucursal: porSucursal,
      );

  /// La lectura falló: no se resta nada.
  static const noLeida = CargosPreproduccion(leida: false);

  /// Todo lo cargado, en centavos.
  int get total => porCategoria.values.fold(0, (a, c) => a + c);

  /// Suma las preparaciones tal como llegan de Firestore, ya acotadas al
  /// período por la consulta.
  ///
  /// La sucursal se filtra igual que los gastos: la elegida o, en "Todas",
  /// solo las que el usuario puede ver ([permitidas] vacío = todas).
  ///
  /// [factorDe] pasa cada monto a la moneda de la vista con el tipo de cambio
  /// de su sucursal y su fecha, igual que a los gastos. Si da null, esa moneda
  /// no tiene tipo de cambio: sus gastos tampoco entran en la cuenta, así que
  /// su preproducción no tiene de dónde restarse y se salta.
  factory CargosPreproduccion.sumar(
    Iterable<Map<String, dynamic>> preparaciones, {
    String? sucursal,
    Set<String> permitidas = const {},
    double? Function(String? sucursal, DateTime? fecha)? factorDe,
    bool completa = true,
  }) {
    // Exacto (en centavos con decimales) hasta el final: se redondea una vez
    // por categoría.
    final exactos = <String, double>{};
    final nombres = <String, List<String>>{};

    for (final p in preparaciones) {
      // Deshecha en el POS: no se preparó, así que no cargó nada.
      if (p['reversed'] == true) continue;

      final suc = _textoNoVacio(p['locationId']);
      if (sucursal != null && suc != sucursal) continue;
      if (sucursal == null &&
          permitidas.isNotEmpty &&
          !permitidas.contains(suc)) {
        continue;
      }

      // Las preparaciones de antes de "otros costos" no traen la lista: no le
      // cargaron nada al preparado.
      final extras = p['extras'];
      if (extras is! List || extras.isEmpty) continue;

      final crudo = p['executedAt'];
      final factor = factorDe == null
          ? 1.0
          : factorDe(suc, crudo is String ? DateTime.tryParse(crudo) : null);
      if (factor == null) continue;

      for (final e in extras) {
        if (e is! Map) continue;
        final monto = e['monto'];
        // Roto, en cero o negativo no se resta: no es gas ni luz que se haya
        // pagado, y restarlo regalaría utilidad.
        if (monto is! num) continue;
        final exacto = monto * factor * 100;
        if (!exacto.isFinite || exacto <= 0) continue;

        final cat = _textoNoVacio(e['categoriaGasto']) ?? _categoriaPorDefecto;
        exactos[cat] = (exactos[cat] ?? 0) + exacto;

        final nombre = _textoNoVacio(e['nombre'])?.trim();
        if (nombre != null) {
          final lista = nombres.putIfAbsent(cat, () => []);
          if (!lista.contains(nombre)) lista.add(nombre);
        }
      }
    }

    final porCategoria = <String, int>{};
    for (final e in exactos.entries) {
      if (!e.value.isFinite) continue;
      final centavos = e.value.round();
      if (centavos > 0) porCategoria[e.key] = centavos;
    }

    return CargosPreproduccion(
      porCategoria: porCategoria,
      nombres: nombres,
      completa: completa,
    );
  }

  /// Cómo nombrar una categoría que no tiene gastos en el período: como la
  /// muestra el POS al configurar los costos; si es una que acá no se conoce,
  /// con los costos que le cargaron.
  String nombreDe(String categoria) {
    final conocida = _nombresDeCategoria[categoria];
    if (conocida != null) return conocida;
    final n = nombres[categoria];
    if (n != null && n.isNotEmpty) return n.join(', ');
    final legible = categoria.replaceAll('_', ' ').trim();
    if (legible.isEmpty) return categoria;
    return legible[0].toUpperCase() + legible.substring(1);
  }
}

/// Una categoría donde la preproducción cargó más de lo que hay anotado en
/// Gastos. La categoría queda en cero, nunca negativa, y se avisa: o los
/// tiempos de las recetas están inflados (y el costo del preparado trae más gas
/// o luz de lo que se pagó), o el gasto todavía no se anotó en esa categoría.
class ExcesoPreproduccion {
  /// Id de la categoría de gasto.
  final String categoria;

  /// Cómo se llama en pantalla.
  final String etiqueta;

  /// Centavos cargados a la preproducción en el período.
  final int cargado;

  /// Centavos anotados en Gastos en esa categoría; cero si no hay nada.
  final int anotado;

  const ExcesoPreproduccion({
    required this.categoria,
    required this.etiqueta,
    required this.cargado,
    required this.anotado,
  });

  /// Los dos montos, sin consejo: el dueño tiene que poder ir a ver cuál está
  /// mal.
  String get detalle {
    final enGastos = anotado > 0
        ? 'en Gastos hay ${formatoDinero(anotado)}'
        : 'en Gastos no hay nada anotado';
    return '$etiqueta: se cargó ${formatoDinero(cargado)} a la preproducción '
        'y $enGastos.';
  }

  /// Los montos y qué revisar. "Que esté anotado en esa categoría" y no
  /// "anotá el gasto": puede estar anotado en otra categoría, y entonces hay
  /// que pasarlo, no anotarlo otra vez.
  String get aviso => '$detalle Revisá los tiempos de tus recetas o que el '
      'gasto esté anotado en esa categoría.';
}

/// Los gastos de la cascada ya sin lo que la preproducción cargó al costo de lo
/// vendido.
class GastosSinPreproduccion {
  /// Las mismas líneas y en el mismo orden; las que tenían algo cargado, con
  /// la resta hecha.
  final List<ExpenseLine> lineas;

  /// Id de categoría → centavos que se le restaron.
  final Map<String, int> restado;

  /// Las categorías donde lo cargado pasa lo anotado, la diferencia más grande
  /// primero.
  final List<ExcesoPreproduccion> excesos;

  const GastosSinPreproduccion({
    required this.lineas,
    this.restado = const {},
    this.excesos = const [],
  });

  /// Todo lo restado, en centavos.
  int get totalRestado => restado.values.fold(0, (a, c) => a + c);

  /// Lo restado a esas categorías, en centavos.
  int restadoEn(Set<String> categorias) => restado.entries
      .where((e) => categorias.contains(e.key))
      .fold(0, (a, e) => a + e.value);

  /// Lo que quedó en esas categorías, ya restado. Es el monto que se muestra,
  /// así que quien lo use (el costo primo) dice lo mismo que la cascada.
  double montoEn(Set<String> categorias) => lineas
      .where((l) => categorias.contains(l.categoryId))
      .fold(0.0, (a, l) => a + l.amount);
}

/// Le resta a cada categoría de [gastos] lo que la preproducción le cargó al
/// costo del preparado. Lo que queda para la cascada y el reparto es
/// max(0, gastos − cargado), categoría por categoría.
///
/// Si [cargos] no se pudo leer, no se resta nada. Lo que sobra en una
/// categoría (cargado de más, o sin gasto anotado) no se le resta a otra: el
/// gas de más no paga la renta. Se devuelve en
/// [GastosSinPreproduccion.excesos] para avisarlo.
GastosSinPreproduccion descontarPreproduccion(
  List<ExpenseLine> gastos,
  CargosPreproduccion cargos,
) {
  if (!cargos.leida || cargos.porCategoria.isEmpty) {
    return GastosSinPreproduccion(lineas: List.of(gastos));
  }

  int centavosDe(ExpenseLine g) =>
      g.amount.isFinite ? (g.amount * 100).round() : 0;

  // Lo anotado en cada categoría, NETO: Rentabilidad arma una línea por
  // categoría, pero si llegaran varias con una corrección negativa, restar
  // contra la positiva sola dejaría la categoría por debajo de cero.
  final anotado = <String, int>{};
  final etiquetas = <String, String>{};
  for (final g in gastos) {
    anotado[g.categoryId] = (anotado[g.categoryId] ?? 0) + centavosDe(g);
    etiquetas.putIfAbsent(g.categoryId, () => g.label);
  }
  int anotadoEn(String cat) => math.max(0, anotado[cat] ?? 0);

  // Lo que se le puede restar a cada categoría: lo cargado, sin pasar lo
  // anotado.
  final pendiente = <String, int>{
    for (final e in cargos.porCategoria.entries)
      e.key: math.min(e.value, anotadoEn(e.key)),
  };
  final restado = <String, int>{};
  final lineas = <ExpenseLine>[];

  for (final g in gastos) {
    final falta = pendiente[g.categoryId] ?? 0;
    final centavos = centavosDe(g);
    // Una línea en cero o negativa (una corrección) no tiene de dónde restar.
    final resta = math.min(falta, centavos);
    if (resta <= 0) {
      lineas.add(g);
      continue;
    }
    pendiente[g.categoryId] = falta - resta;
    restado[g.categoryId] = (restado[g.categoryId] ?? 0) + resta;
    lineas.add(ExpenseLine(
      categoryId: g.categoryId,
      label: g.label,
      amount: (centavos - resta) / 100,
      esFijo: g.esFijo,
    ));
  }

  final excesos = [
    for (final e in cargos.porCategoria.entries)
      if (e.value > anotadoEn(e.key))
        ExcesoPreproduccion(
          categoria: e.key,
          etiqueta: etiquetas[e.key] ?? cargos.nombreDe(e.key),
          cargado: e.value,
          anotado: anotadoEn(e.key),
        ),
  ]..sort((a, b) {
      final c = (b.cargado - b.anotado).compareTo(a.cargado - a.anotado);
      return c != 0 ? c : a.etiqueta.compareTo(b.etiqueta);
    });

  return GastosSinPreproduccion(
    lineas: lineas,
    restado: restado,
    excesos: excesos,
  );
}

/// Lo que la pantalla dice de la preproducción: un título y sus párrafos.
class AvisoPreproduccion {
  final String titulo;
  final List<String> parrafos;
  const AvisoPreproduccion(this.titulo, this.parrafos);
}

/// Qué avisar de la preproducción en Rentabilidad, o null si no hay nada.
///
/// [rango]: solo con Mes o Año se avisa categoría por categoría, como en el
/// reparto por platillo. El gas, la luz y los sueldos se anotan una vez al
/// mes: en un día o una semana lo cargado pasa lo anotado casi siempre, y
/// mandar a revisar si el gasto está anotado haría que se anote dos veces.
/// Por lo mismo, en el mes en curso se dan los montos pero no el consejo: la
/// planilla o el recibo pueden no haber llegado todavía.
///
/// [gastosLeidos]: falso si no se pudieron leer los gastos o los retiros de
/// caja. Comparar contra una parte diría "no hay nada anotado" de algo que sí
/// está.
AvisoPreproduccion? avisoPreproduccion(
  ProfitabilityData d, {
  required DateRange rango,
  required bool gastosLeidos,
  DateTime? hoy,
}) {
  if (!d.preproduccionLeida) {
    return const AvisoPreproduccion('No se pudo leer la preproducción', [
      'Los gastos se muestran completos: si tus recetas de preproducción '
          'cargan gas, luz o mano de obra, esa parte puede estar contada dos '
          'veces. Deslizá hacia abajo para reintentar.',
    ]);
  }

  final ahora = hoy ?? DateTime.now();
  final mensualOAnual =
      rango.mode == PeriodMode.month || rango.mode == PeriodMode.year;
  final mesEnCurso = rango.mode == PeriodMode.month &&
      !ahora.isBefore(rango.start) &&
      !ahora.isAfter(rango.end);

  final parrafos = <String>[];
  if (d.excesosPreproduccion.isNotEmpty) {
    if (!gastosLeidos) {
      parrafos.add('No se pudieron leer todos los gastos del período (gastos o '
          'retiros de caja), así que no se puede comparar con lo cargado a la '
          'preproducción. Deslizá hacia abajo para reintentar.');
    } else if (!mensualOAnual) {
      parrafos.add('En un día, una semana o un rango libre es normal que lo '
          'cargado a la preproducción pase lo anotado en Gastos: el gas, la luz '
          'y los sueldos se anotan una vez al mes. Revisalo en la vista de Mes, '
          'con un mes ya cerrado.');
    } else if (mesEnCurso) {
      parrafos.addAll([for (final e in d.excesosPreproduccion) e.detalle]);
      parrafos.add('El mes va a medias: es normal mientras falte anotar el '
          'gas, la luz o los sueldos del mes. Revisalo cuando cierre.');
    } else {
      parrafos.addAll([for (final e in d.excesosPreproduccion) e.aviso]);
    }
  }
  if (!d.preproduccionCompleta) {
    parrafos.add('Este período tiene más preparaciones de las que se pueden '
        'leer de una vez: lo restado de tus gastos puede quedar corto.');
  }
  if (parrafos.isEmpty) return null;
  return AvisoPreproduccion('Revisá la preproducción', parrafos);
}
