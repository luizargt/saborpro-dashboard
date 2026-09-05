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

  /// Movimientos de venta sin costo cargado. No se rellenan con cero: se
  /// cuentan y se muestran, porque un COGS bajo por falta de datos se ve
  /// idéntico a un COGS bajo por buena gestión.
  final int itemsSinCosto;
  final int itemsConCosto;

  /// Gastos operativos por categoría, de mayor a menor.
  final List<ExpenseLine> expenses;

  /// Sueldos, separado porque entra en el costo primo.
  final double payroll;

  /// Retiros de efectivo del dueño. NO son gasto del negocio: son reparto de
  /// utilidad. Van fuera de la cascada.
  final double ownerWithdrawals;

  /// Compras del período. Tampoco son gasto: son inversión en despensa. El
  /// gasto ya está contado en [cogs] cuando esa mercadería se vende.
  final double purchases;

  /// Valor de la despensa hoy, a precio de compra. Es una foto del momento,
  /// no del período.
  final double inventoryValue;
  final int ingredientesSinPrecio;

  const ProfitabilityData({
    required this.netSales,
    required this.cogs,
    required this.itemsSinCosto,
    required this.itemsConCosto,
    required this.expenses,
    required this.payroll,
    required this.ownerWithdrawals,
    required this.purchases,
    required this.inventoryValue,
    required this.ingredientesSinPrecio,
  });

  static const vacio = ProfitabilityData(
    netSales: 0,
    cogs: 0,
    itemsSinCosto: 0,
    itemsConCosto: 0,
    expenses: [],
    payroll: 0,
    ownerWithdrawals: 0,
    purchases: 0,
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

  /// Qué parte de lo vendido tiene costo conocido. Por debajo de ~90% el
  /// margen bruto es una estimación optimista y hay que decirlo.
  double? get coberturaCosto {
    final total = itemsConCosto + itemsSinCosto;
    if (total == 0) return null;
    return itemsConCosto / total * 100;
  }

  bool get costoConfiable => (coberturaCosto ?? 0) >= 90;

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
