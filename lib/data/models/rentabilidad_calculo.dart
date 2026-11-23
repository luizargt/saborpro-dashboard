// El armado de los números de Rentabilidad a partir de lo que ya está leído:
// pedidos, gastos, compras, el costo de lo vendido y la preproducción.
//
// Vivía dentro del provider (privado, sin forma de probarlo). Se sacó tal cual
// para poder usarlo también POR SUCURSAL —la comparación "¿qué sucursal gana
// más?" tiene que salir de la misma cuenta que el total, no de una parecida— y
// para probarlo sin Firestore.
//
// Todo es Dart puro.

import 'profitability_data.dart';

/// Categorías de gasto que son sueldos. Entran en el costo primo.
const idsSueldos = {'salarios'};

/// Categorías que se pagan igual se venda o no. Son las que el POS marca como
/// `fixed` al crear un gasto.
///
/// Se consulta por id además de mirar el campo `type` porque los retiros de
/// caja llegan con `type: 'variable'` puesto a la fuerza, sin importar de qué
/// sean: un sueldo pagado en efectivo desde la caja es un costo fijo, y
/// tratarlo como variable descuadra el punto de equilibrio.
const idsGastosFijos = {'renta', 'salarios', 'internet', 'seguros'};

/// Si un gasto (tal como lo trae el dashboard) es de los que se pagan igual se
/// venda o no. Ante la duda, variable: contar de más en los fijos infla el
/// punto de equilibrio y le diría al usuario que necesita vender más de lo que
/// realmente necesita.
bool esGastoFijo(Map<String, dynamic> gasto) {
  // Una categoría que no sea texto (un dato roto) es "otros": no debe tumbar la
  // pantalla.
  final cat = gasto['category_id'];
  final id = cat is String ? cat : 'otros';
  return gasto['type'] == 'fixed' || idsGastosFijos.contains(id);
}

/// Lo comprado y lo usado en un día o por un ingrediente.
class ParCosto {
  /// Costo de lo que salió por venta.
  final double costo;

  /// Mercadería que entró (compras).
  final double comprado;
  const ParCosto(this.costo, this.comprado);
}

/// Lo que costó lo vendido en el período, leído de los movimientos de
/// inventario.
class CostoLeido {
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

  /// Lo mismo, separado por sucursal (id de sucursal → su parte). Sirve para
  /// comparar sucursales con la misma cuenta que el total.
  final Map<String, CostoLeido> porSucursal;

  /// Costo y compras de cada día ("2026-10-14"), con la MISMA cuenta que [total]
  /// y [comprado]. Solo lo llena el total, no cada sucursal.
  final Map<String, ParCosto> porDia;

  /// Costo y compras de cada ingrediente (su id), con la misma cuenta.
  final Map<String, ParCosto> porIngrediente;

  /// Se llegó al tope de movimientos que se leen de una vez: el período tiene más
  /// y todos los números de aquí salen cortos.
  final bool truncado;

  const CostoLeido({
    required this.total,
    required this.exactos,
    required this.estimados,
    required this.sinCosto,
    this.comprado = 0,
    this.entradasSinCosto = 0,
    this.porSucursal = const {},
    this.porDia = const {},
    this.porIngrediente = const {},
    this.truncado = false,
  });

  static const vacio = CostoLeido(total: 0, exactos: 0, estimados: 0, sinCosto: 0);
}

/// Arma los números del reporte.
///
/// [sucursal] null es "Todas"; con un id, solo lo de esa sucursal.
///
/// [ventaDeMetricas]: en la vista de año el dashboard no baja las órdenes (los
/// totales los suma Firestore), así que la venta sale de las métricas, que ya
/// son cobrado menos propina y envío y ya vienen filtradas por sucursal. Sin
/// esto la rentabilidad anual daría venta cero y una pérdida inventada del
/// tamaño de los gastos. Cuando es null, la venta sale de [ordenes].
ProfitabilityData armarRentabilidad({
  required List<Map<String, dynamic>> ordenes,
  required List<Map<String, dynamic>> gastos,
  required List<Map<String, dynamic>> compras,
  String? sucursal,
  double? ventaDeMetricas,
  required CostoLeido costo,
  double valorInventario = 0,
  int ingredientesSinPrecio = 0,
  List<String> existenciasImposibles = const [],
  required CargosPreproduccion prepro,
}) {
  final locId = sucursal;

  // Venta neta: lo cobrado menos propina y envío. La propina es del personal
  // y el envío se cobra para pagarlo; ninguno es ingreso del negocio.
  var netSales = 0.0;
  if (ventaDeMetricas != null) {
    netSales = ventaDeMetricas;
  } else {
    for (final o in ordenes) {
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

  for (final e in gastos) {
    if (locId != null && e['location_id'] != locId) continue;
    final monto = (e['amount'] as num? ?? 0).toDouble();
    if (monto == 0) continue;

    if (e['source'] == 'cashRegister') pagadoEnEfectivo += monto;

    final id = (e['category_id'] as String?) ?? 'otros';
    final nombre = (e['category_name'] as String?) ?? 'Otros gastos';
    if (idsSueldos.contains(id)) sueldos += monto;

    // El POS marca cada gasto como 'fixed' o 'variable' al crearlo, pero los
    // retiros de caja llegan siempre como 'variable'; por eso la categoría
    // también decide (ver [esGastoFijo]).
    final esFijo = esGastoFijo(e);

    final previa = porCategoria[id];
    porCategoria[id] = ExpenseLine(
      categoryId: id,
      label: nombre,
      amount: (previa?.amount ?? 0) + monto,
      esFijo: previa?.esFijo ?? esFijo,
    );
  }

  // Lo que la preproducción cargó por tiempo (gas, luz, mano de obra) entra
  // al costo de lo vendido con cada venta del preparado: se le resta a su
  // categoría, que baja como mucho hasta cero. Sin esto esa parte se
  // contaría dos veces, en la cascada y en el reparto por platillo, que lee
  // estas mismas líneas.
  final sinPrepro =
      descontarPreproduccion(porCategoria.values.toList(), prepro);
  final lineas = sinPrepro.lineas
    ..sort((a, b) => b.amount.compareTo(a.amount));

  // Compras: informativas. No se restan — el gasto de esa mercadería ya lo
  // cuenta el costo de lo vendido cuando se vende. Restar ambas sería
  // contar dos veces lo mismo.
  //
  // El monto sale de las ENTRADAS de inventario (costo.comprado) y no de la
  // colección de compras: en los datos reales muchas entradas con costo
  // nunca generan documento de compra, y leyendo solo allí esto mostraba
  // Q0.00 con 64 entradas valorizadas en el mismo período. Si por alguna
  // razón no hubiera entradas pero sí órdenes de compra, se usa esa segunda
  // fuente en vez de mostrar cero.
  var comprasFormales = 0.0;
  for (final p in compras) {
    if (locId != null && p['location_id'] != locId) continue;
    comprasFormales += (p['total'] as num? ?? 0).toDouble();
  }
  final comprado = costo.comprado > 0 ? costo.comprado : comprasFormales;

  return ProfitabilityData(
    netSales: netSales,
    cogs: costo.total,
    itemsConCosto: costo.exactos,
    itemsEstimados: costo.estimados,
    itemsSinCosto: costo.sinCosto,
    expenses: lineas,
    // La mano de obra cargada a la preproducción sale también del costo
    // primo, que si no la sumaría dos veces: queda igual a la línea de
    // sueldos de la cascada. Sin nada restado, el mismo número de siempre.
    payroll: sinPrepro.restadoEn(idsSueldos) > 0
        ? sinPrepro.montoEn(idsSueldos)
        : sueldos,
    paidFromCash: pagadoEnEfectivo,
    purchases: comprado,
    entradasSinCosto: costo.entradasSinCosto,
    inventoryValue: valorInventario,
    ingredientesSinPrecio: ingredientesSinPrecio,
    existenciasImposibles: existenciasImposibles,
    cargadoPreproduccion: prepro.total / 100,
    restadoPreproduccion: sinPrepro.totalRestado / 100,
    excesosPreproduccion: sinPrepro.excesos,
    preproduccionLeida: prepro.leida,
    preproduccionCompleta: prepro.completa,
  );
}
