import 'package:flutter/foundation.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/location_service.dart';
import '../../data/models/inventory_data.dart';

class InventoryProvider extends ChangeNotifier {
  final _firestore = FirestoreService();
  final _locationService = LocationService();

  String? _tenantId;
  List<LocationModel> _locations = [];
  List<IngredientStock> _items = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdated;

  List<LocationModel> get locations => _locations;
  List<IngredientStock> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  int get criticalCount =>
      _items.where((i) => i.worstStatus == StockStatus.critical).length;
  int get lowCount =>
      _items.where((i) => i.worstStatus == StockStatus.low).length;
  int get okCount =>
      _items.where((i) => i.worstStatus == StockStatus.ok).length;

  void init(String tenantId) {
    _tenantId = tenantId;
    _loadLocations();
    load();
  }

  Future<void> _loadLocations() async {
    if (_tenantId == null) return;
    try {
      _locations = await _locationService.getLocations(_tenantId!);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> load() async {
    if (_tenantId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchIngredients(),
        _fetchConsumption(),
      ]);

      final rawItems = results[0] as List<_RawIngredient>;
      final consumption = results[1] as Map<String, Map<String, double>>;

      // Agrupar por nombre a través de sucursales
      final map = <String, _AggIngredient>{};
      for (final raw in rawItems) {
        final agg = map.putIfAbsent(raw.name, () => _AggIngredient(unit: raw.unit));
        agg.stock[raw.locationId] = raw.stock;
        agg.minStock[raw.locationId] = raw.minStock;

        // Días de stock = stockActual / consumoDiarioPromedio
        final dailyAvg = consumption[raw.docId]?[raw.locationId];
        if (dailyAvg != null && dailyAvg > 0 && raw.stock >= 0) {
          agg.daysRemaining[raw.locationId] = raw.stock / dailyAvg;
        }
      }

      _items = map.entries.map((entry) => IngredientStock(
            name: entry.key,
            unit: entry.value.unit,
            stockByLocation: Map.from(entry.value.stock),
            minStockByLocation: Map.from(entry.value.minStock),
            daysRemainingByLocation: Map.from(entry.value.daysRemaining),
          )).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _lastUpdated = DateTime.now();
    } catch (e) {
      _error = 'Error cargando inventario: $e';
    }

    _loading = false;
    notifyListeners();
  }

  Future<List<_RawIngredient>> _fetchIngredients() async {
    final snap = await _firestore.instance
        .collection('ingredients')
        .where('tenant_id', isEqualTo: _tenantId)
        .get();

    final result = <_RawIngredient>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final active = data['active'] as bool? ?? true;
      if (!active) continue;

      final name = (data['name'] as String? ?? '').trim();
      final locationId = data['location_id'] as String? ?? '';
      if (name.isEmpty || locationId.isEmpty) continue;

      result.add(_RawIngredient(
        docId: doc.id,
        name: name,
        locationId: locationId,
        unit: data['unit'] as String? ?? '',
        stock: (data['currentStock'] as num? ?? 0).toDouble(),
        minStock: (data['minStock'] as num? ?? 0).toDouble(),
      ));
    }
    return result;
  }

  // Retorna: Map<ingredientDocId, Map<locationId, consumoDiarioPromedio>>
  Future<Map<String, Map<String, double>>> _fetchConsumption() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final snap = await _firestore.instance
          .collection('inventoryMovements')
          .where('tenantId', isEqualTo: _tenantId)
          .where('createdAt', isGreaterThanOrEqualTo: thirtyDaysAgo.toIso8601String())
          .get();

      final totals = <String, Map<String, double>>{};

      for (final doc in snap.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (type != 'salidaVenta' && type != 'salidaManual') continue;

        final ingredientId = data['ingredientId'] as String? ?? '';
        final locationId = data['locationId'] as String? ?? '';
        final qty = (data['quantity'] as num? ?? 0).toDouble().abs();

        if (ingredientId.isEmpty || locationId.isEmpty || qty <= 0) continue;

        totals.putIfAbsent(ingredientId, () => {});
        totals[ingredientId]![locationId] =
            (totals[ingredientId]![locationId] ?? 0) + qty;
      }

      // Convertir a promedio diario (últimos 30 días)
      return totals.map((id, locMap) => MapEntry(
            id,
            locMap.map((locId, total) => MapEntry(locId, total / 30.0)),
          ));
    } catch (e) {
      debugPrint('[Inventory] Sin datos de consumo: $e');
      return {};
    }
  }
}

class _RawIngredient {
  final String docId, name, locationId, unit;
  final double stock, minStock;
  const _RawIngredient({
    required this.docId,
    required this.name,
    required this.locationId,
    required this.unit,
    required this.stock,
    required this.minStock,
  });
}

class _AggIngredient {
  final String unit;
  final stock = <String, double>{};
  final minStock = <String, double>{};
  final daysRemaining = <String, double>{};
  _AggIngredient({required this.unit});
}
