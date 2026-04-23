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
  final List<ProductSummary> topProducts;

  // Campos para vista tabla
  final double grossSales;
  final double discounts;
  final double taxes;
  final double tips;
  final double refunds;
  final double deliveryFees;
  final double operationalExpenses; // gastos operacionales (collection: expenses)
  final double purchaseCosts;       // compras de insumos recibidas (collection: purchaseOrders)

  // Venta Bruta = total cobrado sin propinas ni fees de delivery
  double get ventaBruta => totalSales - tips - deliveryFees;

  double get netSales => grossSales - discounts - refunds;
  double get totalCosts => operationalExpenses + purchaseCosts;
  double get operatingProfit => netSales + tips - totalCosts;

  PeriodMetrics({
    required this.totalSales,
    required this.totalOrders,
    required this.avgTicket,
    required this.prevTotalSales,
    required this.prevTotalOrders,
    required this.prevAvgTicket,
    required this.chartPoints,
    required this.topProducts,
    this.grossSales = 0,
    this.discounts = 0,
    this.taxes = 0,
    this.tips = 0,
    this.refunds = 0,
    this.deliveryFees = 0,
    this.operationalExpenses = 0,
    this.purchaseCosts = 0,
  });

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
  final int quantity;
  final double total;
  final int prevQuantity;
  final double prevTotal;

  ProductSummary({
    required this.name,
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
