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
      final snap = await _firestore.instance
          .collection('ingredients')
          .where('tenant_id', isEqualTo: _tenantId)
          .get();

      final map = <String, Map<String, dynamic>>{};

      for (final doc in snap.docs) {
        final data = doc.data();
        final active = data['active'] as bool? ?? true;
        if (!active) continue;

        final name = (data['name'] as String? ?? '').trim();
        final locationId = data['location_id'] as String? ?? '';
        if (name.isEmpty || locationId.isEmpty) continue;

        final stock = (data['currentStock'] as num? ?? 0).toDouble();
        final minStock = (data['minStock'] as num? ?? 0).toDouble();
        final unit = data['unit'] as String? ?? '';

        if (!map.containsKey(name)) {
          map[name] = {
            'name': name,
            'unit': unit,
            'stock': <String, double>{},
            'minStock': <String, double>{},
          };
        }
        (map[name]!['stock'] as Map<String, double>)[locationId] = stock;
        (map[name]!['minStock'] as Map<String, double>)[locationId] = minStock;
      }

      _items = map.values
          .map((e) => IngredientStock(
                name: e['name'] as String,
                unit: e['unit'] as String,
                stockByLocation: Map<String, double>.from(e['stock'] as Map),
                minStockByLocation:
                    Map<String, double>.from(e['minStock'] as Map),
              ))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _lastUpdated = DateTime.now();
    } catch (e) {
      _error = 'Error cargando inventario: $e';
    }

    _loading = false;
    notifyListeners();
  }
}
