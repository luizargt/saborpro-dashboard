enum StockStatus { critical, low, ok, noData }

class IngredientStock {
  final String name;
  final String unit;
  final Map<String, double> stockByLocation;
  final Map<String, double> minStockByLocation;

  const IngredientStock({
    required this.name,
    required this.unit,
    required this.stockByLocation,
    required this.minStockByLocation,
  });

  double get totalStock =>
      stockByLocation.values.fold(0.0, (a, b) => a + b);

  StockStatus statusAt(String locationId) {
    final stock = stockByLocation[locationId];
    if (stock == null) return StockStatus.noData;
    if (stock <= 0) return StockStatus.critical;
    final min = minStockByLocation[locationId] ?? 0;
    if (min <= 0) return StockStatus.ok;
    final ratio = stock / min;
    if (ratio < 0.5) return StockStatus.critical;
    if (ratio <= 1.0) return StockStatus.low;
    return StockStatus.ok;
  }

  StockStatus get worstStatus {
    if (stockByLocation.isEmpty) return StockStatus.noData;
    StockStatus worst = StockStatus.ok;
    for (final loc in stockByLocation.keys) {
      final s = statusAt(loc);
      if (s == StockStatus.critical) return StockStatus.critical;
      if (s == StockStatus.low) worst = StockStatus.low;
    }
    return worst;
  }
}
