class DayHourlyPoints {
  final String dayLabel;
  final List<double> hourlyAmounts;
  final List<int> hourlyOrders;
  const DayHourlyPoints({
    required this.dayLabel,
    required this.hourlyAmounts,
    required this.hourlyOrders,
  });
}

class PeriodMetrics {
  final double totalSales;
  final int totalOrders;
  final double avgTicket;
  final double prevTotalSales;
  final int prevTotalOrders;
  final double prevAvgTicket;
  final List<PeriodPoint> chartPoints;
  // Mismos cortes que chartPoints pero del período anterior, para comparar en
  // la gráfica. Truncado al largo de chartPoints: comparar un mes completo
  // contra uno a medias haría ver una caída que no existe.
  final List<PeriodPoint> prevChartPoints;
  final List<ProductSummary> topProducts;
  /// Categorías del menú agrupadas por clasificación, ordenadas de mayor a
  /// menor venta. Clave = clasificación ('Comida', 'Bebidas', ...).
  final Map<String, List<CategorySummary>> categoriesByClassification;

  // Campos para vista tabla
  final double grossSales;
  final double discounts;
  final double taxes;
  final double tips;
  final double refunds;
  final double deliveryFees;
  final double operationalExpenses; // gastos operacionales (collection: expenses)
  final double purchaseCosts;       // compras de insumos recibidas (collection: purchaseOrders)
  final double courtesyTotal;       // valor precio original de ítems de cortesía

  // Cantidad de órdenes que aportaron a cada concepto (para mostrar "N cobros")
  final int tipsCount;
  final int deliveryCount;
  final int courtesyCount;

  // Venta Bruta = total cobrado sin propinas ni fees de delivery
  double get ventaBruta => totalSales - tips - deliveryFees;

  double get netSales => grossSales - discounts - refunds;
  double get totalCosts => operationalExpenses + purchaseCosts;
  double get operatingProfit => netSales + tips - totalCosts;

  // Ventas agrupadas por método de pago (key = payment_method value)
  final Map<String, double> salesByMethod;

  // Productos agrupados por método de pago para filtrado en UI
  final Map<String, List<ProductSummary>> productsByMethod;

  /// Falso cuando las cifras las sumó Firestore sin bajar las órdenes. Pasa en
  /// la vista de año: los totales y el gráfico son exactos, pero nada que viva
  /// dentro de los renglones del ticket (productos, categorías, métodos de
  /// pago, cortesías) se puede calcular así. La pantalla oculta esos bloques en
  /// vez de mostrarlos vacíos o a medias.
  final bool detailAvailable;

  /// Verdadero si alguna consulta tocó un tope y el total podría quedar corto.
  /// Existe para que nunca vuelva a truncarse en silencio.
  final bool truncated;

  PeriodMetrics({
    required this.totalSales,
    required this.totalOrders,
    required this.avgTicket,
    required this.prevTotalSales,
    required this.prevTotalOrders,
    required this.prevAvgTicket,
    required this.chartPoints,
    this.prevChartPoints = const [],
    required this.topProducts,
    this.categoriesByClassification = const {},
    this.grossSales = 0,
    this.discounts = 0,
    this.taxes = 0,
    this.tips = 0,
    this.refunds = 0,
    this.deliveryFees = 0,
    this.operationalExpenses = 0,
    this.purchaseCosts = 0,
    this.courtesyTotal = 0,
    this.tipsCount = 0,
    this.deliveryCount = 0,
    this.courtesyCount = 0,
    this.salesByMethod = const {},
    this.productsByMethod = const {},
    this.detailAvailable = true,
    this.truncated = false,
  });

  PeriodMetrics copyWith({
    Map<String, double>? salesByMethod,
    Map<String, List<ProductSummary>>? productsByMethod,
  }) {
    return PeriodMetrics(
      totalSales: totalSales,
      totalOrders: totalOrders,
      avgTicket: avgTicket,
      prevTotalSales: prevTotalSales,
      prevTotalOrders: prevTotalOrders,
      prevAvgTicket: prevAvgTicket,
      chartPoints: chartPoints,
      prevChartPoints: prevChartPoints,
      topProducts: topProducts,
      categoriesByClassification: categoriesByClassification,
      grossSales: grossSales,
      discounts: discounts,
      taxes: taxes,
      tips: tips,
      refunds: refunds,
      deliveryFees: deliveryFees,
      operationalExpenses: operationalExpenses,
      purchaseCosts: purchaseCosts,
      courtesyTotal: courtesyTotal,
      tipsCount: tipsCount,
      deliveryCount: deliveryCount,
      courtesyCount: courtesyCount,
      salesByMethod: salesByMethod ?? this.salesByMethod,
      productsByMethod: productsByMethod ?? this.productsByMethod,
      detailAvailable: detailAvailable,
      truncated: truncated,
    );
  }

  double get salesChangePercent {
    if (prevTotalSales == 0) return 0;
    return ((totalSales - prevTotalSales) / prevTotalSales) * 100;
  }

  double get ordersChangePercent {
    if (prevTotalOrders == 0) return 0;
    return ((totalOrders - prevTotalOrders) / prevTotalOrders) * 100;
  }

  double get avgTicketChangePercent {
    if (prevAvgTicket == 0) return 0;
    return ((avgTicket - prevAvgTicket) / prevAvgTicket) * 100;
  }
}

class PeriodPoint {
  final String label;
  final double amount;
  final int orders;

  PeriodPoint({required this.label, required this.amount, required this.orders});
}

class ProductSummary {
  final String name;
  final String category;
  final int quantity;
  final double total;
  final int prevQuantity;
  final double prevTotal;

  ProductSummary({
    required this.name,
    this.category = '',
    required this.quantity,
    required this.total,
    required this.prevQuantity,
    required this.prevTotal,
  });

  double get changePercent {
    if (prevTotal == 0) return 0;
    return ((total - prevTotal) / prevTotal) * 100;
  }
}

/// Productos y categorías de un año, calculados abriendo los tickets.
///
/// Va aparte de `PeriodMetrics` porque no llega con la pantalla: se arma con los
/// resúmenes mensuales guardados en Firestore, y el primero que abra un mes
/// nuevo es quien paga calcularlo. Ver `DashboardProvider.computeYearDetail`.
class YearDetail {
  const YearDetail({
    required this.topProducts,
    required this.categoriesByClassification,
    this.salesByMethod = const {},
  });

  final List<ProductSummary> topProducts;
  final Map<String, List<CategorySummary>> categoriesByClassification;

  /// Ventas por método de pago sumadas de los meses. También sale del detalle
  /// porque un pago repartido entre efectivo y tarjeta se desarma abriendo el
  /// ticket, y eso las sumas de servidor no lo pueden hacer.
  final Map<String, double> salesByMethod;
}

/// Ventas acumuladas de una categoría del menú ("Tacos", "Cervezas"), dentro
/// de su clasificación (Comida, Bebidas, Postres, Servicios).
class CategorySummary {
  final String name;
  final String classification;
  final int quantity;
  final double total;

  const CategorySummary({
    required this.name,
    required this.classification,
    required this.quantity,
    required this.total,
  });
}
