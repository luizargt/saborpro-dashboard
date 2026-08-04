import 'package:flutter/foundation.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/inventory_data.dart';

class InventoryProvider extends ChangeNotifier {
  final _firestore = FirestoreService();
  final _locationService = LocationService();

  String? _tenantId;
  // Sucursales permitidas para el usuario (vacío = todas)
  Set<String> _allowedLocationIds = {};
  List<LocationModel> _locations = [];
  List<IngredientStock> _items = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdated;
  // Claves (yyyy-MM-dd) de los últimos 7 días, ordenadas de más antigua a más reciente.
  List<String> _last7DayKeys = [];

  List<LocationModel> get locations => _locations;
  List<IngredientStock> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  List<String> get last7DayKeys => _last7DayKeys;

  int get criticalCount =>
      _items.where((i) => i.worstStatus == StockStatus.critical).length;
  int get lowCount =>
      _items.where((i) => i.worstStatus == StockStatus.low).length;
  int get okCount =>
      _items.where((i) => i.worstStatus == StockStatus.ok).length;

  void init(String tenantId) {
    _tenantId = tenantId;
    // Fijar sucursales permitidas de forma síncrona (load() corre en paralelo).
    _allowedLocationIds = AuthService().assignedLocationIds.toSet();
    _loadLocations();
    load();
  }

  Future<void> _loadLocations() async {
    if (_tenantId == null) return;
    try {
      final all = await _locationService.getLocations(_tenantId!);
      // Restringir a las sucursales asignadas al usuario (vacío = todas)
      _locations = _allowedLocationIds.isNotEmpty
          ? all.where((l) => _allowedLocationIds.contains(l.id)).toList()
          : all;
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
      final consumption = results[1] as _ConsumptionResult;

      // Agrupar por nombre a través de sucursales
      final map = <String, _AggIngredient>{};
      for (final raw in rawItems) {
        final agg = map.putIfAbsent(raw.name, () => _AggIngredient(unit: raw.unit));
        agg.stock[raw.locationId] = raw.stock;
        agg.minStock[raw.locationId] = raw.minStock;

        // Días de stock = stockActual / consumoDiarioPromedio
        final dailyAvg = consumption.dailyAvg[raw.docId]?[raw.locationId];
        if (dailyAvg != null && dailyAvg > 0 && raw.stock >= 0) {
          agg.daysRemaining[raw.locationId] = raw.stock / dailyAvg;
        }

        final byDay = consumption.byDay[raw.docId]?[raw.locationId];
        if (byDay != null && byDay.isNotEmpty) {
          agg.consumptionByDay[raw.locationId] = Map.from(byDay);
        }
      }

      _items = map.entries.map((entry) => IngredientStock(
            name: entry.key,
            unit: entry.value.unit,
            stockByLocation: Map.from(entry.value.stock),
            minStockByLocation: Map.from(entry.value.minStock),
            daysRemainingByLocation: Map.from(entry.value.daysRemaining),
            consumptionByDayByLocation: Map.from(entry.value.consumptionByDay),
          )).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _last7DayKeys = consumption.last7DayKeys;
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
      // Restringir a sucursales permitidas (vacío = todas)
      if (_allowedLocationIds.isNotEmpty && !_allowedLocationIds.contains(locationId)) {
        continue;
      }

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

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Calcula, a partir de una única consulta de 30 días:
  // - el promedio diario de consumo (para "días restantes")
  // - el desglose de consumo por día para los últimos 7 días (incluye hoy)
  Future<_ConsumptionResult> _fetchConsumption() async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final last7DayKeys = List.generate(
          7, (i) => _dayKey(now.subtract(Duration(days: 6 - i))));
      final last7Start = _dayKey(now.subtract(const Duration(days: 6)));

      // Acotamos por createdAt >= hace 30 días en el servidor para no traer toda
      // la colección histórica de movimientos (crecía sin límite y hacía lenta la
      // carga aunque no hubiera consumo reciente). createdAt se guarda como String
      // ISO, así que el rango lexicográfico coincide con el orden cronológico.
      // El filtro de tipo (salidaVenta/salidaManual) sigue haciéndose en Dart.
      // Índice requerido: inventoryMovements (tenantId ASC, createdAt ASC).
      final thirtyDaysAgoIso = thirtyDaysAgo.toIso8601String();
      final snap = await _firestore.instance
          .collection('inventoryMovements')
          .where('tenantId', isEqualTo: _tenantId)
          .where('createdAt', isGreaterThanOrEqualTo: thirtyDaysAgoIso)
          .get();

      // totals[ingredientId][locationId] = cantidad consumida (30 días)
      final totals = <String, Map<String, double>>{};
      // oldest[ingredientId][locationId] = fecha del movimiento más antiguo
      final oldest = <String, Map<String, DateTime>>{};
      // byDay[ingredientId][locationId][dayKey] = cantidad consumida ese día
      final byDay = <String, Map<String, Map<String, double>>>{};

      for (final doc in snap.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (type != 'salidaVenta' && type != 'salidaManual') continue;

        // Filtrar por los últimos 30 días en Dart
        final createdAtRaw = data['createdAt'] as String? ?? '';
        final date = createdAtRaw.isNotEmpty ? DateTime.tryParse(createdAtRaw) : null;
        if (date == null || date.isBefore(thirtyDaysAgo)) continue;

        final ingredientId = data['ingredientId'] as String? ?? '';
        final locationId = data['locationId'] as String? ?? '';
        final qty = (data['quantity'] as num? ?? 0).toDouble().abs();

        if (ingredientId.isEmpty || locationId.isEmpty || qty <= 0) continue;

        totals.putIfAbsent(ingredientId, () => {});
        totals[ingredientId]![locationId] =
            (totals[ingredientId]![locationId] ?? 0) + qty;

        // Rastrear el movimiento más antiguo para calcular días reales
        oldest.putIfAbsent(ingredientId, () => {});
        final current = oldest[ingredientId]![locationId];
        if (current == null || date.isBefore(current)) {
          oldest[ingredientId]![locationId] = date;
        }

        // Desglose por día, solo para los últimos 7 días
        final dayKey = _dayKey(date);
        if (dayKey.compareTo(last7Start) >= 0) {
          byDay.putIfAbsent(ingredientId, () => {});
          byDay[ingredientId]!.putIfAbsent(locationId, () => {});
          byDay[ingredientId]![locationId]![dayKey] =
              (byDay[ingredientId]![locationId]![dayKey] ?? 0) + qty;
        }
      }

      // Convertir a promedio diario usando días reales con datos (mínimo 1)
      final dailyAvg = <String, Map<String, double>>{};
      for (final entry in totals.entries) {
        final ingredientId = entry.key;
        dailyAvg[ingredientId] = {};
        for (final locEntry in entry.value.entries) {
          final locationId = locEntry.key;
          final totalConsumed = locEntry.value;
          final oldestDate = oldest[ingredientId]?[locationId];
          final actualDays = oldestDate != null
              ? now.difference(oldestDate).inDays.clamp(1, 30)
              : 30;
          dailyAvg[ingredientId]![locationId] = totalConsumed / actualDays;
        }
      }

      return _ConsumptionResult(
        dailyAvg: dailyAvg,
        byDay: byDay,
        last7DayKeys: last7DayKeys,
      );
    } catch (e) {
      debugPrint('[Inventory] Sin datos de consumo: $e');
      return _ConsumptionResult(dailyAvg: {}, byDay: {}, last7DayKeys: []);
    }
  }
}

class _ConsumptionResult {
  final Map<String, Map<String, double>> dailyAvg;
  final Map<String, Map<String, Map<String, double>>> byDay;
  final List<String> last7DayKeys;
  const _ConsumptionResult({
    required this.dailyAvg,
    required this.byDay,
    required this.last7DayKeys,
  });
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
  final consumptionByDay = <String, Map<String, double>>{};
  _AggIngredient({required this.unit});
}
