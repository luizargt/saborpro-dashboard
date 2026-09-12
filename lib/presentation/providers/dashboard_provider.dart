import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/sales_aggregates_service.dart';
import '../../core/services/monthly_rollup_service.dart';
import '../../core/utils/date_range.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/cash_register_summary.dart';

class DashboardProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();
  final LocationService _locationService = LocationService();
  final SalesAggregatesService _aggregates = SalesAggregatesService();

  /// La vista de año no baja las órdenes: le pide los totales a Firestore.
  /// Un año del cliente más grande son 20.669 órdenes y 69 MB; sumarlo en el
  /// servidor cuesta unas 170 lecturas y no se puede truncar.
  bool get _usaAgregados => _range.mode == PeriodMode.year;

  /// Verdadero cuando `currentOrders` está vacío a propósito porque los totales
  /// los sumó Firestore. Quien necesite recorrer órdenes tiene que mirar esto y
  /// no `metrics.detailAvailable`: ese se enciende en cuanto hay resúmenes
  /// mensuales, y aun así sigue sin haber órdenes en memoria.
  bool get sinOrdenesEnMemoria => _usaAgregados;

  YearAggregate? _yearAgg;
  YearAggregate? _prevYearAgg;

  /// Caché por sucursal: cambiar de pestaña no vuelve a consultar si ya se vio.
  /// La clave es el año y la sucursal ('' = todas).
  final Map<String, YearAggregate> _aggCache = {};

  DateRange _range = DateRange.today();
  DateRange get range => _range;

  PeriodMetrics? _metrics;
  PeriodMetrics? get metrics => _metrics;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  List<DayHourlyPoints> _weeklyHourly = [];
  List<DayHourlyPoints> get weeklyHourly => _weeklyHourly;

  List<PeriodPoint> _monthlyDailyPoints = [];
  List<PeriodPoint> get monthlyDailyPoints => _monthlyDailyPoints;

  List<CashRegisterSummary> _openRegisters = [];
  List<CashRegisterSummary> get openRegisters => _openRegisters;

  List<CashRegisterSummary> _closedRegisters = [];
  List<CashRegisterSummary> get closedRegisters => _closedRegisters;

  List<Map<String, dynamic>> _currentOrders = [];
  List<Map<String, dynamic>> get currentOrders => _currentOrders;

  List<Map<String, dynamic>> _expenseItems = [];
  List<Map<String, dynamic>> get expenseItems => _expenseItems;

  List<Map<String, dynamic>> _purchaseItems = [];
  List<Map<String, dynamic>> get purchaseItems => _purchaseItems;

  // Debug: docs totales en Firestore antes de filtrar por fecha
  int _expenseRawCount = 0;
  int get expenseRawCount => _expenseRawCount;
  String _expenseSampleDate = '';
  String get expenseSampleDate => _expenseSampleDate;

  String? _tenantId;
  String? get tenantId => _tenantId;
  String? _locationId;

  // Cache: no cambia con el rango de fechas, solo se fetcha una vez por sesión
  Map<String, String>? _cachedProductClassificationMap;
  // productId → nombre de su categoría de menú. Mismo ciclo de vida que el de
  // clasificación: se deriva del mismo fetch de `products`.
  Map<String, String>? _cachedProductCategoryNameMap;

  // ── CACHE CRUDO POR RANGO ───────────────────────────────────────────────────
  // Las queries a Firestore NO filtran por sucursal (se filtra en memoria), así
  // que un mismo fetch sirve para todas las sucursales del rango. Guardamos el
  // resultado sin filtrar para que cambiar de sucursal solo re-filtre y
  // recalcule métricas, sin volver a la red.
  bool _rawCacheValid = false;
  List<Map<String, dynamic>> _rawCurrentOrders = [];
  List<Map<String, dynamic>> _rawPrevOrders = [];
  List<Map<String, dynamic>> _rawExpenses = [];
  List<Map<String, dynamic>> _rawPurchases = [];
  List<Map<String, dynamic>> _rawCashRegisters = [];
  List<Map<String, dynamic>> _rawWeeklyOrders = [];
  List<Map<String, dynamic>> _rawMonthlyOrders = [];
  Map<String, String> _rawCategoryClassifications = {};
  Map<String, String> _rawCategoryClassificationsByName = {};
  Map<String, String> _rawCategoryNameById = {};
  Map<String, Map<String, String>> _customMethodNamesByLocation = {};
  DateTime _rawWeekStart = DateTime.now();
  DateTime _rawMonthStart = DateTime.now();
  DateTime _rawNow = DateTime.now();

  List<LocationModel> _locations = [];
  List<LocationModel> get locations => _locations;

  // Sucursales permitidas para el usuario (vacío = todas)
  Set<String> _allowedLocationIds = {};

  String? _selectedLocationId; // null = todas (dentro de las permitidas)
  String? get selectedLocationId => _selectedLocationId;

  /// Determina si un registro pasa el filtro de sucursal actual.
  /// - Con sucursal seleccionada: solo esa.
  /// - "Todas": solo las sucursales permitidas del usuario (vacío = todas).
  bool _passesLocationFilter(String? rowLocationId) {
    if (_selectedLocationId != null && _selectedLocationId!.isNotEmpty) {
      return rowLocationId == _selectedLocationId;
    }
    if (_allowedLocationIds.isNotEmpty) {
      return rowLocationId != null && _allowedLocationIds.contains(rowLocationId);
    }
    return true;
  }

  String get selectedLocationName {
    if (_selectedLocationId == null) return 'Todas las sucursales';
    return _locations.firstWhere(
      (l) => l.id == _selectedLocationId,
      orElse: () => LocationModel(id: '', name: 'Todas las sucursales'),
    ).name;
  }

  void init(String tenantId, {String? locationId}) {
    _tenantId = tenantId;
    _locationId = locationId;
    _rawCacheValid = false;
    // Los totales cacheados son de otro negocio: tirarlos antes de nada.
    _aggCache.clear();
    _detalleCache.clear();
    // Fijar sucursales permitidas de forma síncrona (load() corre en paralelo
    // con _loadLocations, así el filtro aplica desde la primera carga).
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

      // _fetchCustomMethodNames depende de _locations, que carga en paralelo con
      // load(): si llegó tarde, los nombres quedaron vacíos. Como ya no se
      // refetchan al cambiar de sucursal, se completan aquí una sola vez.
      if (_customMethodNamesByLocation.isEmpty && _locations.isNotEmpty) {
        _customMethodNamesByLocation = await _fetchCustomMethodNames();
        if (_rawCacheValid && _customMethodNamesByLocation.isNotEmpty) {
          _rebuildFromRaw();
        }
      }
    } catch (_) {}
  }

  void selectLocation(String? locationId) {
    if (_selectedLocationId == locationId) return;
    _selectedLocationId = locationId;
    // En la vista de año las sumas las hace Firestore filtrando por sucursal,
    // así que no hay nada que re-filtrar en memoria: hay que volver a pedirlas.
    // `_aggCache` hace que volver a una pestaña ya vista no cueste ni una
    // consulta.
    if (_usaAgregados) {
      load();
      return;
    }
    // Las queries no filtran por sucursal, así que el fetch del rango actual ya
    // trae los datos de todas: basta re-filtrar en memoria (instantáneo, sin red).
    if (_rawCacheValid) {
      _rebuildFromRaw();
    } else {
      load();
    }
  }

  void setRange(DateRange range) {
    _range = range;
    _rawCacheValid = false;
    load();
  }

  /// Recarga tirando lo cacheado. Es lo que hace "deslizar para actualizar":
  /// quien acaba de cobrar espera ver ese cobro, no el total de hace un rato.
  Future<void> refresh() async {
    _aggCache.clear();
    _detalleCache.clear();
    _rawCacheValid = false;
    await load();
  }

  void goNext() {
    if (_range.isFuture) return;
    setRange(_range.next());
  }

  void goPrevious() {
    setRange(_range.previous());
  }

  Future<void> load() async {
    if (_tenantId == null) return;
    _loading = true;
    _error = null;
    // Liberar listas grandes del período anterior para que el GC pueda reclamar
    // memoria antes de iniciar los nuevos fetches, evitando pico de OOM.
    _currentOrders = [];
    _monthlyDailyPoints = [];
    _weeklyHourly = [];
    _metrics = null;
    notifyListeners();

    try {
      // [PERF] Instrumentación temporal para diagnosticar lentitud de carga.
      // Revisar la consola por líneas "[PERF]" para ver qué etapa domina.
      final _swTotal = Stopwatch()..start();
      final _sw = Stopwatch()..start();
      void _mark(String stage) {
        debugPrint('[PERF] $stage: ${_sw.elapsedMilliseconds}ms (total ${_swTotal.elapsedMilliseconds}ms)');
        _sw.reset();
        _sw.start();
      }

      final prev = _range.previous();
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final we = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final monthStart = DateTime(now.year, now.month, 1);

      // Etapa 1+2 en paralelo: período actual y anterior simultáneamente.
      //
      // En la vista de año NO se bajan las órdenes. Antes se bajaban con un tope
      // de 5.000 y sin orden explícito, y como Firestore ordena por el campo del
      // filtro de rango, ese tope se quedaba con las 5.000 más antiguas y tiraba
      // el resto del año sin avisar. Ahora los totales los suma el servidor.
      var currentOrders = const <Map<String, dynamic>>[];
      var prevOrders = const <Map<String, dynamic>>[];
      if (_usaAgregados) {
        final aggs = await Future.wait([
          _loadYearAggregate(_range.start.year),
          _loadYearAggregate(prev.start.year),
        ]);
        _yearAgg = aggs[0];
        _prevYearAgg = aggs[1];
        _mark('agregados(actual+anterior) tickets=${_yearAgg?.totalOrders}');
      } else {
        _yearAgg = null;
        _prevYearAgg = null;
        final orderPair = await Future.wait([
          _fetchOrders(_range.start, _range.end),
          _fetchOrders(prev.start, prev.end),
        ]);
        currentOrders = orderPair[0];
        prevOrders = orderPair[1];
        _mark('orders(actual+anterior) docs=${currentOrders.length}+${prevOrders.length}');
      }

      // Etapa 0b: cargar clasificaciones: por categoria y por producto
      final categoryIds = _extractCategoryIds(currentOrders);
      final classMaps = await _fetchCategoryClassifications(categoryIds);
      final classificationMap = classMaps.byId;
      final classificationByName = classMaps.byName;
      _mark('categoryClassifications');
      // El mapa de productos se cachea: el menú no cambia al cambiar el rango de fechas
      final _prodWasCached = _cachedProductClassificationMap != null;
      if (!_prodWasCached) {
        final prodMaps = await _fetchProductClassifications(
            classificationMap, classMaps.nameById);
        _cachedProductClassificationMap = prodMaps.classification;
        _cachedProductCategoryNameMap = prodMaps.categoryName;
      }
      _mark('productClassifications (cached=$_prodWasCached)');

      // Etapa 3: gastos, compras, cajas, nombres de métodos y — SOLO si el modo actual
      // lo necesita — órdenes de la semana o del mes para el gráfico secundario, todo
      // en paralelo. Antes el fetch del mes completo se hacía SIEMPRE sin importar el
      // modo, incluso en la vista "Hoy" (la que ve el usuario al entrar), lo que
      // multiplicaba por semanas el volumen de datos leídos en cada carga. SalesChart
      // solo usa weeklyHourly en modo día y monthlyDailyPoints en modo semana; mes/año/
      // custom usan metrics.chartPoints, que ya se construye con currentOrders.
      final needsWeekly = _range.mode == PeriodMode.day;
      final needsMonthly = _range.mode == PeriodMode.week;
      final expResults = await Future.wait([
        _fetchExpenses(_range.start, _range.end),
        _fetchPurchaseCosts(_range.start, _range.end),
        _fetchAllCashRegisters(),
        _fetchCustomMethodNames(),
        needsWeekly ? _fetchOrders(ws, we) : Future.value(const <Map<String, dynamic>>[]),
        needsMonthly ? _fetchOrders(monthStart, we) : Future.value(const <Map<String, dynamic>>[]),
      ]);
      _mark('expenses+purchases+cashRegisters+methods+chart cajas=${(expResults[2] as List).length}');

      // Guardar el crudo (sin filtrar por sucursal) para poder recalcular al
      // cambiar de pestaña de sucursal sin volver a consultar Firestore.
      _rawCurrentOrders = currentOrders;
      _rawPrevOrders = prevOrders;
      _rawExpenses = expResults[0] as List<Map<String, dynamic>>;
      _rawPurchases = expResults[1] as List<Map<String, dynamic>>;
      _rawCashRegisters = expResults[2] as List<Map<String, dynamic>>;
      _customMethodNamesByLocation = expResults[3] as Map<String, Map<String, String>>;
      _rawWeeklyOrders = expResults[4] as List<Map<String, dynamic>>;
      _rawMonthlyOrders = expResults[5] as List<Map<String, dynamic>>;
      _rawCategoryClassifications = classificationMap;
      _rawCategoryClassificationsByName = classificationByName;
      _rawCategoryNameById = classMaps.nameById;
      _rawWeekStart = ws;
      _rawMonthStart = monthStart;
      _rawNow = now;
      _rawCacheValid = true;

      // Etapa 4: filtrar por sucursal y construir métricas (sin Firestore adicional).
      _rebuildFromRaw(notify: false);
      _mark('metrics+summaries');

      // Etapa 5, solo en la vista de año: ver qué meses ya están resumidos en
      // Firestore para mostrar el detalle sin que nadie tenga que pedirlo. No
      // se espera, porque las cifras ya están en pantalla y esto solo agrega
      // los bloques de abajo cuando llega.
      if (_usaAgregados) {
        unawaited(_cargarResumenesDelAnio());
      }
      debugPrint('[PERF] === load() TOTAL: ${_swTotal.elapsedMilliseconds}ms ===');
    } catch (e, st) {
      _rawCacheValid = false;
      _error = 'Error cargando datos: $e';
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('provider', 'dashboard');
        scope.setContexts('range', {
          'mode': _range.mode.name,
          'start': _range.start.toIso8601String(),
          'end': _range.end.toIso8601String(),
        });
      });
    }

    _loading = false;
    notifyListeners();
  }

  /// Aplica el filtro de sucursal actual sobre el cache crudo y recalcula todo
  /// lo derivado (órdenes, gastos, cajas, gráficos y métricas). No toca la red:
  /// es lo que hace que cambiar de pestaña de sucursal sea instantáneo.
  void _rebuildFromRaw({bool notify = true}) {
    bool passes(Map<String, dynamic> row, String key) =>
        _passesLocationFilter(row[key] as String?);

    final currentOrders =
        _rawCurrentOrders.where((o) => passes(o, 'location_id')).toList();
    final prevOrders =
        _rawPrevOrders.where((o) => passes(o, 'location_id')).toList();
    _currentOrders = currentOrders;

    final withdrawals =
        _extractWithdrawals(_rawCashRegisters, _range.start, _range.end);
    // _rawExpenses = gastos manuales; withdrawals = retiros de caja (ya filtrados)
    _expenseItems = [
      ..._rawExpenses.where((e) => passes(e, 'location_id')),
      ...withdrawals,
    ];
    _purchaseItems =
        _rawPurchases.where((p) => passes(p, 'location_id')).toList();
    final expenses = _expenseItems.fold<double>(
        0, (s, e) => s + (e['amount'] as num? ?? 0).toDouble());
    final purchaseCosts = _purchaseItems.fold<double>(
        0, (s, e) => s + (e['total'] as num? ?? 0).toDouble());

    _weeklyHourly = _range.mode == PeriodMode.day
        ? _groupByHourPerDay(
            _rawWeeklyOrders.where((o) => passes(o, 'location_id')).toList(),
            _rawWeekStart)
        : [];
    _monthlyDailyPoints = _range.mode == PeriodMode.week
        ? _groupByDayOfMonth(
            _rawMonthlyOrders.where((o) => passes(o, 'location_id')).toList(),
            _rawMonthStart,
            _rawNow)
        : [];

    _buildCashRegisterSummaries(_rawCashRegisters);
    if (_usaAgregados) {
      _metrics = _buildMetricsFromAggregate(
        expenses: expenses,
        purchaseCosts: purchaseCosts,
      );
      if (notify) notifyListeners();
      return;
    }
    _metrics = _buildMetrics(
      currentOrders,
      prevOrders,
      _range,
      expenses: expenses,
      purchaseCosts: purchaseCosts,
      classificationMap: _rawCategoryClassifications,
      classificationByName: _rawCategoryClassificationsByName,
      productClassificationMap: _cachedProductClassificationMap ?? const {},
      productCategoryNameMap: _cachedProductCategoryNameMap ?? const {},
      categoryNameById: _rawCategoryNameById,
    );

    if (notify) notifyListeners();
  }

  /// Fetcha solo los cashRegisters relevantes del tenant, en vez de la colección
  /// histórica completa (antes esto pulía la colección entera del tenant en cada
  /// load(), sin importar el rango de fechas — causa raíz de la lentitud reportada
  /// incluso en días sin ventas).
  ///
  /// Dos queries en paralelo:
  /// - status == 'open': todas las cajas abiertas del tenant, cualquier antigüedad
  ///   (normalmente solo hay un puñado, una por sucursal activa).
  /// - status == 'closed' AND closedAt >= _range.start: cajas cerradas cuyo cierre
  ///   cae dentro o después del inicio del rango. No se acota el límite superior
  ///   aquí porque _buildCashRegisterSummaries ya filtra closedAt <= _range.end
  ///   más abajo; esto solo evita descartar cajas que abrieron mucho antes del
  ///   rango pero siguieron abiertas/cerraron dentro de él (y así perder sus
  ///   retiros en _extractWithdrawals).
  /// closedAt puede guardarse como Timestamp o como String ISO (cajas offline),
  /// por lo que se corre una query extra para el caso String, igual que con
  /// expenses/orders en este mismo archivo.
  ///
  /// El resultado se reutiliza en _extractWithdrawals y _buildCashRegisterSummaries,
  /// evitando roundtrips adicionales a Firestore.
  /// Índice requerido: cashRegisters (tenantId ASC, status ASC, closedAt ASC) —
  /// ver nota en firestore.indexes.json del proyecto principal.
  Future<List<Map<String, dynamic>>> _fetchAllCashRegisters() async {
    if (_tenantId == null) return [];
    try {
      final startIso = _range.start.toIso8601String().substring(0, 23);

      final snaps = await Future.wait([
        _firestore.instance
            .collection('cashRegisters')
            .where('tenantId', isEqualTo: _tenantId)
            .where('status', isEqualTo: 'open')
            .get(),
        _firestore.instance
            .collection('cashRegisters')
            .where('tenantId', isEqualTo: _tenantId)
            .where('status', isEqualTo: 'closed')
            .where('closedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_range.start))
            .get(),
        _firestore.instance
            .collection('cashRegisters')
            .where('tenantId', isEqualTo: _tenantId)
            .where('status', isEqualTo: 'closed')
            .where('closedAt', isGreaterThanOrEqualTo: startIso)
            .get(),
      ]);

      final seen = <String>{};
      final all = <Map<String, dynamic>>[];
      for (final snap in snaps) {
        for (final d in snap.docs) {
          if (!seen.add(d.id)) continue;
          final data = d.data();
          data['_docId'] = d.id;
          all.add(data);
        }
      }
      return all;
    } catch (_) {
      return [];
    }
  }

  /// Construye los resúmenes de cajas abiertas y cerradas a partir de datos ya
  /// fetchados, sin hacer ninguna query adicional a Firestore.
  void _buildCashRegisterSummaries(List<Map<String, dynamic>> registers) {
    try {
      String? locName(String? locId) {
        if (locId == null) return null;
        try { return _locations.firstWhere((l) => l.id == locId).name; } catch (_) { return null; }
      }

      // Cada caja usa los métodos de pago personalizados de SU propia sucursal.
      Map<String, String> methodsFor(String? locId) =>
          _customMethodNamesByLocation[locId] ?? const {};

      final all = registers.where((d) {
        return _passesLocationFilter(d['locationId'] as String?);
      }).toList();

      _openRegisters = all
          .where((d) => d['status'] == 'open')
          .map((d) {
            final r = CashRegisterSummary.fromMap(d);
            return r.copyWith(customMethodNames: methodsFor(r.locationId), locationName: locName(r.locationId));
          })
          .toList();

      _closedRegisters = all.where((d) {
        if (d['status'] != 'closed') return false;
        final closedAt = d['closedAt'];
        if (closedAt == null) return false;
        final dt = _toDateTime(closedAt);
        if (dt == null) return false;
        return !dt.isBefore(_range.start) && !dt.isAfter(_range.end);
      }).map((d) {
            final r = CashRegisterSummary.fromMap(d);
            return r.copyWith(customMethodNames: methodsFor(r.locationId), locationName: locName(r.locationId));
          })
          .toList()
        ..sort((a, b) => (b.closedAt ?? b.openedAt).compareTo(a.closedAt ?? a.openedAt));
    } catch (_) {
      _openRegisters = [];
      _closedRegisters = [];
    }
  }

  /// Métodos de pago personalizados de TODAS las sucursales visibles, indexados
  /// por locationId. Se traen todas (son docs pequeños, en paralelo) para que
  /// cambiar de sucursal no requiera una consulta extra a Firestore.
  Future<Map<String, Map<String, String>>> _fetchCustomMethodNames() async {
    try {
      if (_locations.isEmpty) return {};
      final docs = await Future.wait(_locations.map(
        (l) => _firestore.instance.collection('locations').doc(l.id).get(),
      ));

      final result = <String, Map<String, String>>{};
      for (final doc in docs) {
        if (!doc.exists) continue;
        final settings = (doc.data() as Map<String, dynamic>)['settings'];
        if (settings == null) continue;
        final methods = settings['custom_payment_methods'] as List<dynamic>? ?? [];
        result[doc.id] = {
          for (final m in methods)
            if (m is Map<String, dynamic> && m['id'] != null && m['name'] != null)
              m['id'] as String: m['name'] as String,
        };
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> _fetchExpenses(
      DateTime start, DateTime end) async {
    try {
      final startDay = DateTime(start.year, start.month, start.day);
      final endDay   = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
      final startIso = startDay.toIso8601String().substring(0, 23);
      final endIso   = endDay.toIso8601String().substring(0, 23);

      // Dos queries en paralelo: Timestamp (gastos normales) + ISO String (gastos offline).
      // Firestore filtra por tipo de campo, los resultados son mutuamente excluyentes.
      // Índice requerido: expenses (tenant_id ASC, date ASC) — ya existe en firestore.indexes.json.
      final snaps = await Future.wait([
        _firestore.instance
            .collection('expenses')
            .where('tenant_id', isEqualTo: _tenantId)
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay))
            .get(),
        _firestore.instance
            .collection('expenses')
            .where('tenant_id', isEqualTo: _tenantId)
            .where('date', isGreaterThanOrEqualTo: startIso)
            .where('date', isLessThanOrEqualTo: endIso)
            .get(),
      ]);

      final all = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          if (!seen.add(doc.id)) continue;
          final data = doc.data();
          all.add(data);
        }
      }

      _expenseRawCount = all.length;
      _expenseSampleDate = all.isNotEmpty ? (all.first['date']?.toString() ?? 'null') : 'sin docs';
      return all;
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('query', 'fetchExpenses');
        scope.setTag('tenantId', _tenantId ?? 'null');
      });
      _expenseRawCount = -1;
      _expenseSampleDate = 'error: $e';
      return [];
    }
  }

  /// Extrae retiros de caja (withdrawal) desde datos ya fetchados de cashRegisters.
  /// Sin ninguna query adicional a Firestore — usa la lista cargada en _fetchAllCashRegisters.
  List<Map<String, dynamic>> _extractWithdrawals(
      List<Map<String, dynamic>> registers, DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay   = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final results  = <Map<String, dynamic>>[];

    for (final data in registers) {
      if (!_passesLocationFilter(data['locationId'] as String?)) continue;

      final movementsList = data['movements'] as List<dynamic>? ?? [];
      for (final raw in movementsList) {
        if (raw is! Map) continue;
        final mov = Map<String, dynamic>.from(raw);

        if (mov['type'] != 'withdrawal') continue;

        final rawDate = mov['createdAt'];
        DateTime? dt;
        if (rawDate is String) dt = DateTime.tryParse(rawDate);
        if (rawDate is Timestamp) dt = rawDate.toDate();
        if (dt == null) continue;
        if (dt.isUtc) dt = dt.toLocal();
        if (dt.isBefore(startDay) || dt.isAfter(endDay)) continue;

        results.add({
          'amount': (mov['amount'] as num? ?? 0).toDouble(),
          // La sucursal viene del documento de caja (ahí es `locationId`), pero
          // se guarda con el nombre que usan los gastos normales para que
          // ambos se agrupen igual. Sin esta clave, quien reparte por sucursal
          // descartaba los retiros: se restaban en la utilidad global pero en
          // ninguna sucursal, y la suma de las partes daba más que el total.
          'location_id': data['locationId'] as String?,
          'date': dt.toIso8601String(),
          // La categoría del retiro se conserva con las dos llaves que usan
          // los gastos normales. Sin el id no se puede saber si ese retiro fue
          // de sueldos —y hay bastantes— ni si el gasto es fijo o variable.
          'category_id': mov['expenseCategoryId'] as String?,
          'category_name': mov['expenseCategoryName'] as String? ?? 'Otros Gastos',
          'description': mov['reason'] as String?,
          'source': 'cashRegister',
          'type': 'variable',
          'assigned_to': mov['assignedTo'],
          'registered_by': mov['authorizedBy'],
          'register_id': data['_docId'],
          'register_user': data['userName'] as String? ?? '',
          'register_opened_at': _toDateTime(data['openedAt'])?.toIso8601String(),
          'register_closed_at': _toDateTime(data['closedAt'])?.toIso8601String(),
        });
      }
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _fetchPurchaseCosts(
      DateTime start, DateTime end) async {
    try {
      final startIso = start.toIso8601String().substring(0, 23);
      final endIso   = end.toIso8601String().substring(0, 23);

      // Filtro de fecha en Firestore con índice compuesto (tenant_id, status, received_at)
      // que ya existe en firestore.indexes.json — evita descargar historial completo.
      final snap = await _firestore.instance
          .collection('purchaseOrders')
          .where('tenant_id', isEqualTo: _tenantId)
          .where('status', isEqualTo: 'received')
          .where('received_at', isGreaterThanOrEqualTo: startIso)
          .where('received_at', isLessThanOrEqualTo: endIso)
          .get();

      return snap.docs.map((d) => d.data()).toList();
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('query', 'fetchPurchaseCosts');
      });
      return [];
    }
  }

  /// Baja las órdenes del período COMPLETO, paginando hasta agotarlo.
  ///
  /// La pantalla de año no las necesita y por eso no las pide: son 20.669
  /// órdenes y 69 MB en el cliente más grande. Pero exportar un reporte sí
  /// necesita cada fila, así que quien lo pide paga esa descarga a propósito,
  /// una vez, en vez de cargársela a todo el mundo al abrir el inicio.
  ///
  /// A diferencia de `_fetchOrders`, esto NO se queda corto: pagina con
  /// `orderBy` explícito y cursor, así que ningún tope recorta el período por
  /// detrás. Si el período es chico, las órdenes que ya están en memoria se
  /// devuelven tal cual.
  Future<List<Map<String, dynamic>>> ensureDetailedOrders() async {
    if (!_usaAgregados) return _currentOrders;
    if (_tenantId == null) return const [];
    return _fetchOrdersPaged(_range.start, _range.end);
  }

  /// Baja las órdenes de un rango paginando hasta agotarlo, sin ningún tope.
  Future<List<Map<String, dynamic>>> _fetchOrdersPaged(
      DateTime inicio, DateTime fin) async {
    final todas = <Map<String, dynamic>>[];
    final vistos = <String>{};

    for (final esTexto in [false, true]) {
      final desde = esTexto
          ? inicio.toIso8601String().substring(0, 23) as Object
          : Timestamp.fromDate(inicio) as Object;
      final hasta = esTexto
          ? fin.toIso8601String().substring(0, 23) as Object
          : Timestamp.fromDate(fin) as Object;

      // El cursor va por documento y no por fecha: dos órdenes cobradas en el
      // mismo segundo harían que un cursor por fecha repitiera o se saltara
      // una página.
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      // 2.000 por vuelta: un año grande son ~10 vueltas, y cada una entra en
      // memoria sin sobresaltos.
      while (true) {
        var q = _firestore.orders
            .where('tenant_id', isEqualTo: _tenantId)
            .where('paid_at', isGreaterThanOrEqualTo: desde)
            .where('paid_at', isLessThanOrEqualTo: hasta)
            .orderBy('paid_at')
            .limit(2000);
        if (cursor != null) q = q.startAfterDocument(cursor);

        final snap = await q.get();
        if (snap.docs.isEmpty) break;

        for (final doc in snap.docs) {
          if (!vistos.add(doc.id)) continue;
          final data = doc.data();
          data['_docId'] = doc.id;
          if ((data['status'] as String?) == 'CANCELLED') continue;
          todas.add(data);
        }
        if (snap.docs.length < 2000) break;
        cursor = snap.docs.last;
      }
    }

    debugPrint('[AGG] detalle bajo demanda: ${todas.length} órdenes');
    return todas.where((o) => _passesLocationFilter(o['location_id'] as String?)).toList();
  }

  // ── DETALLE DEL AÑO: RESÚMENES MENSUALES COMPARTIDOS ────────────────────────
  // Los productos y las categorías viven dentro de `items`, una lista adentro
  // de cada ticket. Las sumas de servidor de Firestore solo trabajan sobre
  // campos sueltos del documento y no saben agrupar, así que eso no se puede
  // pedir sumado: hay que abrir los tickets.
  //
  // La salida es guardar el mes ya calculado en Firestore, no en el teléfono.
  // El negocio más grande tiene 6 personas entrando a Sabor Manager: en el
  // dispositivo, ese mes se calcularía 6 veces, y otra por cada teléfono nuevo,
  // cada navegador y cada reinstalación. Compartido se calcula UNA vez.
  //
  // Un mes cerrado no cambia nunca, así que se paga una sola vez en la vida.
  // El mes en curso se completa con lo que entró después, sin rehacerlo.

  final MonthlyRollupService _rollups = MonthlyRollupService();

  bool _calculandoDetalle = false;
  bool get calculandoDetalle => _calculandoDetalle;

  /// Mes que se está procesando (1-12), para la barra de progreso.
  int _mesDetalle = 0;
  int get mesDetalle => _mesDetalle;

  /// Meses que hace falta calcular para poder mostrar el detalle del año.
  /// Cero significa que ya está todo y la pantalla lo muestra sin pedir nada.
  int _mesesPendientes = 0;
  int get mesesPendientes => _mesesPendientes;

  final Map<String, YearDetail> _detalleCache = {};

  YearDetail? get yearDetail =>
      _usaAgregados ? _detalleCache[_claveDetalle] : null;

  String get _claveDetalle => '${_range.start.year}|${_selectedLocationId ?? ''}';

  /// Sucursal con la que se guardan y leen los resúmenes. Vacío = todas.
  String get _scopeRollup => _selectedLocationId ?? '';

  /// Mira qué meses del año ya están resumidos y arma el detalle con los que
  /// estén al día. Corre al abrir la vista de año.
  ///
  /// Cuesta una lectura por mes más dos conteos de servidor, que se facturan
  /// como una lectura por cada mil órdenes. Es lo que permite saber si un mes
  /// cambió sin rehacerlo a ciegas.
  Future<void> _cargarResumenesDelAnio() async {
    if (!_usaAgregados || _tenantId == null) return;
    final year = _range.start.year;
    final ahora = DateTime.now();
    final ultimoMes = year < ahora.year ? 12 : ahora.month;

    final chequeos = await Future.wait([
      for (var m = 1; m <= ultimoMes; m++)
        _rollups.chequear(
          tenantId: _tenantId!,
          locationId: _scopeRollup,
          year: year,
          month: m,
        ),
    ]);

    final listos = <MonthlyRollup>[];
    var pendientes = 0;
    var ordenesPendientes = 0;
    for (final c in chequeos) {
      // Un mes sin una sola venta no tiene nada que resumir: está resuelto por
      // definición. Contarlo como pendiente dejaba el botón puesto para
      // siempre, porque calcular no le cambiaba nada y el siguiente chequeo lo
      // volvía a contar. Un negocio que abrió en junio arrastraba cinco meses
      // vacíos que jamás se iban a poder tachar.
      if (c.orderCount == 0) continue;
      if (c.estado == RollupEstado.alDia && c.rollup != null) {
        listos.add(c.rollup!);
      } else {
        pendientes++;
        ordenesPendientes += c.orderCount;
      }
    }

    debugPrint('[ROLLUP] año $year: ${listos.length} mes(es) listos, '
        '$pendientes pendiente(s) con $ordenesPendientes órdenes');
    _mesesPendientes = pendientes;

    if (pendientes == 0) {
      if (listos.isNotEmpty) {
        _detalleCache[_claveDetalle] = _sumarResumenes(listos);
        _completarMetricas(listos);
      }
      notifyListeners();
      return;
    }

    // Con meses sin resumir el detalle saldría incompleto, y un top de
    // productos al que le falten meses miente peor que no mostrarlo: parecería
    // que eso fue todo lo que se vendió.
    _detalleCache.remove(_claveDetalle);
    notifyListeners();

    // Se calcula solo, sin preguntar. La vista de mes tampoco pide permiso
    // para bajar sus pedidos, y hacer que el año se comporte distinto obliga al
    // dueño a entender por qué su reporte tiene un botón que los otros no.
    // Es una vez por mes en la vida del negocio: después queda guardado para
    // todos y esto no vuelve a correr.
    if (ordenesPendientes > 0) {
      await computeYearDetail();
    }
  }

  /// Calcula los meses que faltan, los guarda para todo el negocio y arma el
  /// detalle. Esto es lo que dispara el botón.
  ///
  /// Va MES A MES y suelta cada mes al terminarlo: el año entero de golpe son
  /// 20.669 órdenes y 69 MB en el cliente más grande, suficiente para colgar la
  /// pestaña de un teléfono. De a un mes el pico son unos 3.500 tickets.
  ///
  /// Sumar los meses da el mismo resultado que calcular el año de una vez: el
  /// descuento se prorratea dentro de cada pedido, así que ningún número
  /// depende de con qué otros pedidos venga agrupado.
  Future<void> computeYearDetail() async {
    if (!_usaAgregados || _tenantId == null) return;
    if (_calculandoDetalle) return;

    _calculandoDetalle = true;
    _mesDetalle = 0;
    notifyListeners();

    final year = _range.start.year;
    final ahora = DateTime.now();
    final ultimoMes = year < ahora.year ? 12 : ahora.month;
    final listos = <MonthlyRollup>[];

    try {
      for (var m = 1; m <= ultimoMes; m++) {
        _mesDetalle = m;
        notifyListeners();

        final chequeo = await _rollups.chequear(
          tenantId: _tenantId!,
          locationId: _scopeRollup,
          year: year,
          month: m,
        );

        if (chequeo.estado == RollupEstado.alDia && chequeo.rollup != null) {
          listos.add(chequeo.rollup!);
          continue;
        }
        if (chequeo.orderCount == 0) continue; // mes sin ventas

        // Mes en curso al que solo le entraron ventas: se le suman esas y
        // listo, en vez de volver a bajar el mes entero cada vez que alguien
        // abre la pantalla. Es lo que hace que el mes de hoy salga solo.
        final rollup = chequeo.estado == RollupEstado.soloNuevas
            ? await _completarMesConLoNuevo(year, m, chequeo)
            : await _calcularMes(year, m, chequeo);
        if (rollup == null) continue;
        listos.add(rollup);
        await _rollups.write(_tenantId!, rollup);
      }

      _mesesPendientes = 0;
      if (listos.isNotEmpty) {
        _detalleCache[_claveDetalle] = _sumarResumenes(listos);
        _completarMetricas(listos);
      }
    } catch (e, st) {
      _error = 'No se pudo calcular el detalle del año: $e';
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('provider', 'dashboard');
        scope.setTag('accion', 'computeYearDetail');
      });
    } finally {
      _calculandoDetalle = false;
      _mesDetalle = 0;
      notifyListeners();
    }
  }

  /// Baja un mes entero y lo reduce a un resumen guardable.
  ///
  /// La huella (`orderCount`) viene del chequeo hecho ANTES de bajar las
  /// órdenes, y eso importa: si se tomara después, una venta que entre mientras
  /// se calcula quedaría fuera del resumen pero contada en la huella, y el
  /// próximo chequeo daría el mes por completo faltándole esa venta para
  /// siempre. Tomándola antes, el desfase se ve como "entraron órdenes nuevas"
  /// y el mes se rehace. Peca de rehacer de más, nunca de mostrar de menos.
  Future<MonthlyRollup?> _calcularMes(
      int year, int month, RollupChequeo chequeo) async {
    final inicio = DateTime(year, month, 1);
    final fin = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
    final ordenes = await _fetchOrdersPaged(inicio, fin);

    // Las clasificaciones (Comidas, Bebidas, Servicios) no se cargaron al
    // entrar porque en la vista de año no había órdenes de donde sacar los ids.
    final ids = _extractCategoryIds(ordenes);
    final maps = ids.isEmpty
        ? (byId: <String, String>{}, byName: <String, String>{}, nameById: <String, String>{})
        : await _fetchCategoryClassifications(ids);
    if (_cachedProductClassificationMap == null) {
      final prodMaps = await _fetchProductClassifications(maps.byId, maps.nameById);
      _cachedProductClassificationMap = prodMaps.classification;
      _cachedProductCategoryNameMap = prodMaps.categoryName;
    }

    final metrics = _buildMetrics(
      ordenes,
      const [],
      DateRange(start: inicio, end: fin, mode: PeriodMode.month),
      classificationMap: maps.byId,
      classificationByName: maps.byName,
      productClassificationMap: _cachedProductClassificationMap ?? const {},
      productCategoryNameMap: _cachedProductCategoryNameMap ?? const {},
      categoryNameById: maps.nameById,
    );

    DateTime? ultima;
    for (final o in ordenes) {
      final dt = _toDateTime(o['paid_at']);
      if (dt != null && (ultima == null || dt.isAfter(ultima))) ultima = dt;
    }

    return MonthlyRollup(
      year: year,
      month: month,
      locationId: _scopeRollup,
      orderCount: chequeo.orderCount,
      cancelledCount: chequeo.cancelledCount,
      lastPaidAt: ultima,
      metrics: metrics,
    );
  }

  /// Le suma a un mes ya resumido solo las ventas que entraron después.
  ///
  /// Devuelve null si no se puede hacer con seguridad, y entonces el mes se
  /// rehace entero. El caso que obliga a eso es que el resumen guardado haya
  /// tocado el tope de productos: ahí la cola quedó recortada y sumarle encima
  /// propagaría el recorte en vez de corregirlo.
  Future<MonthlyRollup?> _completarMesConLoNuevo(
      int year, int month, RollupChequeo chequeo) async {
    final previo = chequeo.rollup;
    final desdeQue = previo?.lastPaidAt;
    if (previo == null || desdeQue == null) return _calcularMes(year, month, chequeo);
    if (previo.metrics.topProducts.length >= MonthlyRollup.kMaxProductos) {
      return _calcularMes(year, month, chequeo);
    }

    final finMes = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
    final nuevas = await _fetchOrdersPaged(
      desdeQue.add(const Duration(milliseconds: 1)),
      finMes,
    );
    if (nuevas.isEmpty) return previo;

    final ids = _extractCategoryIds(nuevas);
    final maps = ids.isEmpty
        ? (byId: <String, String>{}, byName: <String, String>{}, nameById: <String, String>{})
        : await _fetchCategoryClassifications(ids);

    final delta = _buildMetrics(
      nuevas,
      const [],
      DateRange(start: desdeQue, end: finMes, mode: PeriodMode.month),
      classificationMap: maps.byId,
      classificationByName: maps.byName,
      productClassificationMap: _cachedProductClassificationMap ?? const {},
      productCategoryNameMap: _cachedProductCategoryNameMap ?? const {},
      categoryNameById: maps.nameById,
    );

    final productos = <String, ProductSummary>{};
    _acumularProductos(productos, previo.metrics.topProducts);
    _acumularProductos(productos, delta.topProducts);
    final categorias = <String, Map<String, CategorySummary>>{};
    _acumularCategorias(categorias, previo.metrics.categoriesByClassification);
    _acumularCategorias(categorias, delta.categoriesByClassification);
    final metodos = <String, double>{...previo.metrics.salesByMethod};
    delta.salesByMethod.forEach((k, v) => metodos[k] = (metodos[k] ?? 0) + v);

    var ultima = desdeQue;
    for (final o in nuevas) {
      final dt = _toDateTime(o['paid_at']);
      if (dt != null && dt.isAfter(ultima)) ultima = dt;
    }

    final a = previo.metrics;
    debugPrint('[ROLLUP] $year-$month completado con ${nuevas.length} órdenes nuevas');
    return MonthlyRollup(
      year: year,
      month: month,
      locationId: _scopeRollup,
      orderCount: chequeo.orderCount,
      cancelledCount: chequeo.cancelledCount,
      lastPaidAt: ultima,
      metrics: PeriodMetrics(
        totalSales: a.totalSales + delta.totalSales,
        totalOrders: a.totalOrders + delta.totalOrders,
        avgTicket: 0,
        prevTotalSales: 0,
        prevTotalOrders: 0,
        prevAvgTicket: 0,
        chartPoints: const [],
        topProducts: productos.values.toList()
          ..sort((x, y) => y.total.compareTo(x.total)),
        categoriesByClassification: {
          for (final e in categorias.entries)
            e.key: (e.value.values.toList()..sort((x, y) => y.total.compareTo(x.total)))
        },
        grossSales: a.grossSales + delta.grossSales,
        discounts: a.discounts + delta.discounts,
        taxes: a.taxes + delta.taxes,
        tips: a.tips + delta.tips,
        refunds: a.refunds + delta.refunds,
        deliveryFees: a.deliveryFees + delta.deliveryFees,
        courtesyTotal: a.courtesyTotal + delta.courtesyTotal,
        tipsCount: a.tipsCount + delta.tipsCount,
        deliveryCount: a.deliveryCount + delta.deliveryCount,
        courtesyCount: a.courtesyCount + delta.courtesyCount,
        salesByMethod: metodos,
      ),
    );
  }

  /// Junta los meses en el detalle que ve la pantalla.
  YearDetail _sumarResumenes(List<MonthlyRollup> meses) {
    final productos = <String, ProductSummary>{};
    final categorias = <String, Map<String, CategorySummary>>{};
    final metodos = <String, double>{};

    for (final r in meses) {
      _acumularProductos(productos, r.metrics.topProducts);
      _acumularCategorias(categorias, r.metrics.categoriesByClassification);
      r.metrics.salesByMethod.forEach((k, v) {
        metodos[k] = (metodos[k] ?? 0) + v;
      });
    }

    final lista = productos.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return YearDetail(
      topProducts: lista,
      categoriesByClassification: {
        for (final e in categorias.entries)
          e.key: (e.value.values.toList()..sort((a, b) => b.total.compareTo(a.total))),
      },
      salesByMethod: metodos,
    );
  }

  /// Rellena en las métricas del año lo que solo se sabe abriendo los tickets:
  /// descuentos, impuestos, devoluciones y cortesías.
  ///
  /// La venta, los tickets, la propina y el envío NO se tocan: siguen saliendo
  /// de las sumas de servidor, que están comprobadas al centavo contra la base.
  /// Mezclar dos fuentes para el mismo número es justo como nacen los
  /// descuadres.
  void _completarMetricas(List<MonthlyRollup> meses) {
    final m = _metrics;
    if (m == null) return;

    var discounts = 0.0, taxes = 0.0, refunds = 0.0, courtesy = 0.0, gross = 0.0;
    var tipsCount = 0, deliveryCount = 0, courtesyCount = 0;
    for (final r in meses) {
      discounts += r.metrics.discounts;
      taxes += r.metrics.taxes;
      refunds += r.metrics.refunds;
      courtesy += r.metrics.courtesyTotal;
      gross += r.metrics.grossSales;
      tipsCount += r.metrics.tipsCount;
      deliveryCount += r.metrics.deliveryCount;
      courtesyCount += r.metrics.courtesyCount;
    }

    _metrics = PeriodMetrics(
      totalSales: m.totalSales,
      totalOrders: m.totalOrders,
      avgTicket: m.avgTicket,
      prevTotalSales: m.prevTotalSales,
      prevTotalOrders: m.prevTotalOrders,
      prevAvgTicket: m.prevAvgTicket,
      chartPoints: m.chartPoints,
      prevChartPoints: m.prevChartPoints,
      topProducts: _detalleCache[_claveDetalle]?.topProducts ?? const [],
      categoriesByClassification:
          _detalleCache[_claveDetalle]?.categoriesByClassification ?? const {},
      grossSales: gross,
      discounts: discounts,
      taxes: taxes,
      tips: m.tips,
      refunds: refunds,
      deliveryFees: m.deliveryFees,
      operationalExpenses: m.operationalExpenses,
      purchaseCosts: m.purchaseCosts,
      courtesyTotal: courtesy,
      tipsCount: tipsCount,
      deliveryCount: deliveryCount,
      courtesyCount: courtesyCount,
      salesByMethod: _detalleCache[_claveDetalle]?.salesByMethod ?? const {},
      // Ya hay de dónde sacar todos los bloques, así que la pantalla deja de
      // esconderlos y el año se ve igual que un mes.
      detailAvailable: true,
      truncated: m.truncated,
    );
  }

  void _acumularProductos(
      Map<String, ProductSummary> dst, List<ProductSummary> mes) {
    for (final p in mes) {
      final previo = dst[p.name];
      dst[p.name] = previo == null
          ? p
          : ProductSummary(
              name: p.name,
              category: p.category.isNotEmpty ? p.category : previo.category,
              quantity: previo.quantity + p.quantity,
              total: previo.total + p.total,
              prevQuantity: 0,
              prevTotal: 0,
            );
    }
  }

  void _acumularCategorias(Map<String, Map<String, CategorySummary>> dst,
      Map<String, List<CategorySummary>> mes) {
    for (final entry in mes.entries) {
      final porNombre = dst.putIfAbsent(entry.key, () => {});
      for (final c in entry.value) {
        final previo = porNombre[c.name];
        porNombre[c.name] = previo == null
            ? c
            : CategorySummary(
                name: c.name,
                classification: c.classification,
                quantity: previo.quantity + c.quantity,
                total: previo.total + c.total,
              );
      }
    }
  }

  /// Top de productos sobre una lista de órdenes ya bajada.
  ///
  /// En la vista de año `metrics.topProducts` viene vacío a propósito, así que
  /// quien exporta le pasa lo que consiguió con `ensureDetailedOrders`. En los
  /// demás períodos devuelve lo que ya estaba calculado.
  List<ProductSummary> topProductsFrom(List<Map<String, dynamic>> orders) {
    if (!_usaAgregados) return _metrics?.topProducts ?? const [];
    // Si los resúmenes del año ya están, el top sale de ahí y no hay que
    // recalcular nada sobre las órdenes que se acaban de bajar.
    final ya = _detalleCache[_claveDetalle];
    if (ya != null && ya.topProducts.isNotEmpty) return ya.topProducts;
    return _buildTopProducts(
      orders,
      const [],
      _rawCategoryClassifications,
      _rawCategoryClassificationsByName,
      _cachedProductClassificationMap ?? const {},
    );
  }

  /// Totales de un año pedidos a Firestore, con caché por sucursal para que
  /// cambiar de pestaña no repita las consultas.
  Future<YearAggregate> _loadYearAggregate(int year) async {
    final scope = _selectedLocationId ?? '';
    final key = '$year|$scope|${_allowedLocationIds.length}';
    final cached = _aggCache[key];
    if (cached != null) return cached;

    final agg = await _aggregates.fetchYear(
      tenantId: _tenantId!,
      year: year,
      locationId: _selectedLocationId,
      allowedLocationIds: _allowedLocationIds,
      desglosePorSucursal: [for (final l in _locations) l.id],
    );
    _aggCache[key] = agg;
    return agg;
  }

  /// Venta por sucursal en la vista de año. Vacío en los demás períodos, donde
  /// la tabla de reparto la arma el widget desde las órdenes en memoria.
  Map<String, double> get yearSalesByLocation =>
      _usaAgregados ? (_yearAgg?.salesByLocation ?? const {}) : const {};

  Future<List<Map<String, dynamic>>> _fetchOrders(
      DateTime start, DateTime end) async {
    try {
      // Dos queries en paralelo: Timestamp (órdenes normales) + ISO String (órdenes offline).
      // Límite de 5000 como válvula de seguridad anti-OOM; un mes normal tiene < 3000 órdenes.
      const kOrderLimit = 5000;
      final startIso = start.toIso8601String().substring(0, 23);
      final endIso   = end.toIso8601String().substring(0, 23);

      // [PERF] Cronometrar cada sub-query por separado para saber cuál se tarda.
      Future<QuerySnapshot<Map<String, dynamic>>> _timed(String tag, Future<QuerySnapshot<Map<String, dynamic>>> f) async {
        final sw = Stopwatch()..start();
        final snap = await f;
        debugPrint('[PERF] orders.$tag [${start.toIso8601String().substring(0,10)}]: ${sw.elapsedMilliseconds}ms docs=${snap.docs.length}');
        return snap;
      }

      final snaps = await Future.wait([
        _timed('ts', _firestore.orders
            .where('tenant_id', isEqualTo: _tenantId)
            .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .limit(kOrderLimit)
            .get()),
        _timed('str', _firestore.orders
            .where('tenant_id', isEqualTo: _tenantId)
            .where('paid_at', isGreaterThanOrEqualTo: startIso)
            .where('paid_at', isLessThanOrEqualTo: endIso)
            .limit(kOrderLimit)
            .get()),
      ]);

      final seen = <String>{};
      final all  = <Map<String, dynamic>>[];
      for (final doc in [...snaps[0].docs, ...snaps[1].docs]) {
        if (seen.add(doc.id)) {
          final data = doc.data();
          data['_docId'] = doc.id;
          all.add(data);
        }
      }

      // Sin filtro de sucursal: devolvemos crudo para poder cambiar de sucursal
      // sin volver a consultar Firestore (ver _rebuildFromRaw).
      return all.where((o) {
        final orderStatus = o['status'] as String? ?? '';
        return orderStatus != 'CANCELLED';
      }).toList();
    } catch (_) {
      return [];
    }
  }

  PeriodMetrics _buildMetrics(
    List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> prevOrders,
    DateRange range, {
    double expenses = 0,
    double purchaseCosts = 0,
    Map<String, String> classificationMap = const {},
    Map<String, String> classificationByName = const {},
    Map<String, String> productClassificationMap = const {},
    Map<String, String> productCategoryNameMap = const {},
    Map<String, String> categoryNameById = const {},
  }) {
    double total = 0, prevTotal = 0;
    double grossSales = 0, discounts = 0, taxes = 0, tips = 0, refunds = 0, deliveryFees = 0;
    double courtesyTotal = 0;
    int tipsCount = 0, deliveryCount = 0, courtesyCount = 0;
    final salesByMethod = <String, double>{};

    for (final o in orders) {
      // Usar payment_amount si existe (mismo valor que usa CashRegisterCalculator)
      final rawTotal = (o['total_amount'] as num? ?? 0).toDouble();
      final t = (o['payment_amount'] as num?)?.toDouble() ?? rawTotal;
      total += t;
      grossSales += (o['subtotal'] as num? ?? t).toDouble();
      discounts += (o['discount_amount'] as num? ?? 0).toDouble();
      taxes += (o['tax_amount'] as num? ?? 0).toDouble();
      final orderTip = (o['tip_amount'] as num? ?? 0).toDouble();
      tips += orderTip;
      if (orderTip > 0) tipsCount++;
      final orderDelivery = (o['delivery_fee'] as num? ?? 0).toDouble();
      deliveryFees += orderDelivery;
      if (orderDelivery > 0) deliveryCount++;
      if (o['is_refund'] == true) refunds += t;
      final items = o['items'];
      if (items is List) {
        var hasCourtesy = false;
        for (final item in items) {
          if (item is Map && item['is_courtesy'] == true && item['is_void'] != true) {
            final price = (item['unit_price'] as num? ?? 0).toDouble();
            final qty   = (item['qty']        as num? ?? 1).toDouble();
            courtesyTotal += price * qty;
            hasCourtesy = true;
          }
        }
        if (hasCourtesy) courtesyCount++;
      }

      // Desglose por método de pago
      // Normalizar 'mixed' a 'split' (igual que CashRegisterCalculator)
      var method = o['payment_method'] as String? ?? 'cash';
      if (method == 'mixed') {
        method = 'split';
        if (o['split_payments'] == null && o['mixed_payments'] is List) {
          final mp = o['mixed_payments'] as List<dynamic>;
          o['split_payments'] = mp.map((e) {
            if (e is! Map) return <String, dynamic>{'payment_method': 'cash', 'amount': 0};
            return <String, dynamic>{
              'payment_method': e['method'] ?? 'cash',
              'amount': e['amount'] ?? 0,
            };
          }).toList();
        }
      }
      if (method == 'split') {
        final splits = (o['split_payments'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .toList();
        final splitsSum = splits.fold<double>(
            0, (s, sp) => s + ((sp['amount'] as num? ?? 0).toDouble()));
        for (final sp in splits) {
          final sm_method = sp['payment_method'] as String? ?? 'cash';
          final sm_amount = (sp['amount'] as num? ?? 0).toDouble();
          final ratio = splitsSum > 0 ? sm_amount / splitsSum : 0.0;
          final allocated = sm_amount + (t - splitsSum) * ratio;
          salesByMethod[sm_method] = (salesByMethod[sm_method] ?? 0) + allocated;
        }
      } else {
        salesByMethod[method] = (salesByMethod[method] ?? 0) + t;
      }
    }
    for (final o in prevOrders) {
      // La MISMA fórmula que el período actual (ver arriba: payment_amount con
      // fallback a total_amount). Antes acá se sumaba solo total_amount, que va
      // sin propina, mientras el período actual la incluía: se comparaban dos
      // magnitudes distintas y el "vs anterior" salía inflado a favor del
      // presente en exactamente el monto de las propinas.
      prevTotal += (o['payment_amount'] as num?)?.toDouble() ??
          (o['total_amount'] as num? ?? 0).toDouble();
    }

    final count = orders.length;
    final prevCount = prevOrders.length;
    final avg = count > 0 ? total / count : 0.0;
    final prevAvg = prevCount > 0 ? prevTotal / prevCount : 0.0;

    final topProducts = _buildTopProducts(orders, prevOrders, classificationMap, classificationByName, productClassificationMap);
    final categoriesByClassification = _buildCategoriesByClassification(
      orders,
      productCategoryNameMap,
      productClassificationMap,
      categoryNameById,
      classificationMap,
      classificationByName,
    );

    // Construir lista de productos por método de pago para filtrado en UI
    final uniqueMethods = <String>{};
    for (final o in orders) {
      var m = o['payment_method'] as String? ?? 'cash';
      if (m == 'mixed') m = 'split';
      uniqueMethods.add(m);
    }
    final productsByMethod = <String, List<ProductSummary>>{};
    for (final method in uniqueMethods) {
      final filtered = orders.where((o) {
        var m = o['payment_method'] as String? ?? 'cash';
        if (m == 'mixed') m = 'split';
        return m == method;
      }).toList();
      productsByMethod[method] = _buildTopProducts(filtered, prevOrders, classificationMap, classificationByName, productClassificationMap);
    }

    final chartPoints = _buildChartPoints(orders, range);
    // El período anterior se corta al mismo número de cortes que el actual:
    // comparar un mes completo contra uno en curso mostraría una caída falsa.
    final prevChartPoints =
        _buildChartPoints(prevOrders, range.previous()).take(chartPoints.length).toList();

    return PeriodMetrics(
      totalSales: total,
      totalOrders: count,
      avgTicket: avg,
      prevTotalSales: prevTotal,
      prevTotalOrders: prevCount,
      prevAvgTicket: prevAvg,
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
      operationalExpenses: expenses,
      purchaseCosts: purchaseCosts,
      courtesyTotal: courtesyTotal,
      tipsCount: tipsCount,
      deliveryCount: deliveryCount,
      courtesyCount: courtesyCount,
      salesByMethod: salesByMethod,
      productsByMethod: productsByMethod,
    );
  }

  /// Métricas de la vista de año a partir de lo que sumó Firestore.
  ///
  /// Los totales y el gráfico salen exactos para cualquier volumen. Lo que se
  /// queda vacío a propósito es todo lo que vive dentro de los renglones del
  /// ticket: productos, categorías, métodos de pago y cortesías. `detailAvailable`
  /// en falso le dice a la pantalla que muestre un aviso en vez de esos bloques,
  /// porque un desglose a medias sobre un total exacto se lee como un descuadre.
  PeriodMetrics _buildMetricsFromAggregate({
    required double expenses,
    required double purchaseCosts,
  }) {
    const nombres = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    List<PeriodPoint> puntos(YearAggregate? a) => [
          for (var m = 0; m < 12; m++)
            PeriodPoint(
              label: nombres[m],
              amount: a == null ? 0 : a.months[m].sales,
              orders: a == null ? 0 : a.months[m].orders,
            ),
        ];

    final agg = _yearAgg;
    final prev = _prevYearAgg;
    final total = agg?.totalSales ?? 0;
    final count = agg?.totalOrders ?? 0;
    final prevTotal = prev?.totalSales ?? 0;
    final prevCount = prev?.totalOrders ?? 0;

    return PeriodMetrics(
      totalSales: total,
      totalOrders: count,
      avgTicket: count == 0 ? 0 : total / count,
      prevTotalSales: prevTotal,
      prevTotalOrders: prevCount,
      prevAvgTicket: prevCount == 0 ? 0 : prevTotal / prevCount,
      chartPoints: puntos(agg),
      prevChartPoints: puntos(prev),
      topProducts: const [],
      // grossSales replica lo que hace _buildMetrics cuando no hay `subtotal`,
      // que es el caso en el 100% de las órdenes de producción: cae al total.
      grossSales: total,
      tips: agg?.tips ?? 0,
      deliveryFees: agg?.deliveryFees ?? 0,
      operationalExpenses: expenses,
      purchaseCosts: purchaseCosts,
      detailAvailable: false,
      truncated: agg?.truncated ?? false,
    );
  }

  List<PeriodPoint> _buildChartPoints(
      List<Map<String, dynamic>> orders, DateRange range) {
    switch (range.mode) {
      case PeriodMode.day:
        return _groupByHour(orders);
      case PeriodMode.week:
        return _groupByDayOfWeek(orders, range);
      case PeriodMode.month:
        return _groupByWeekOfMonth(orders, range);
      case PeriodMode.year:
        return _groupByMonth(orders, range);
      case PeriodMode.custom:
        final days = range.end.difference(range.start).inDays;
        if (days <= 1) return _groupByHour(orders);
        if (days <= 31) return _groupByDayOfWeek(orders, range);
        return _groupByMonth(orders, range);
    }
  }

  List<DayHourlyPoints> _groupByHourPerDay(
      List<Map<String, dynamic>> orders, DateTime weekStart) {
    final dayLabels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final result = <DayHourlyPoints>[];

    for (var i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      if (date.isAfter(DateTime.now())) break;
      final amounts = List<double>.filled(24, 0.0);
      final counts = List<int>.filled(24, 0);
      for (final o in orders) {
        final ts = o['paid_at'];
        if (ts == null) continue;
        DateTime dt;
        if (ts is Timestamp) {
          dt = ts.toDate().toLocal();
        } else if (ts is String) {
          final parsed = DateTime.tryParse(ts);
          if (parsed == null) continue;
          dt = parsed.toLocal();
        } else {
          continue;
        }
        if (dt.year == date.year && dt.month == date.month && dt.day == date.day) {
          amounts[dt.hour] += (o['total_amount'] as num? ?? 0).toDouble();
          counts[dt.hour]++;
        }
      }
      final dowIndex = date.weekday - 1;
      result.add(DayHourlyPoints(
        dayLabel: '${dayLabels[dowIndex]} ${date.day}',
        hourlyAmounts: amounts,
        hourlyOrders: counts,
      ));
    }
    return result;
  }

  List<PeriodPoint> _groupByDayOfMonth(
      List<Map<String, dynamic>> orders, DateTime monthStart, DateTime today) {
    final map = <int, _Acc>{};
    for (var d = 1; d <= today.day; d++) {
      map[d] = _Acc();
    }
    for (final o in orders) {
      final ts = o['paid_at'];
      if (ts == null) continue;
      DateTime dt;
      if (ts is Timestamp) {
        dt = ts.toDate().toLocal();
      } else if (ts is String) {
        dt = DateTime.tryParse(ts)?.toLocal() ?? DateTime.now();
      } else continue;
      if (dt.month == monthStart.month && dt.year == monthStart.year) {
        map[dt.day]?.add((o['payment_amount'] as num?)?.toDouble() ??
            (o['total_amount'] as num? ?? 0).toDouble());
      }
    }
    return map.entries
        .map((e) => PeriodPoint(label: '${e.key}', amount: e.value.amount, orders: e.value.count))
        .toList();
  }

  List<PeriodPoint> _groupByHour(List<Map<String, dynamic>> orders) {
    final map = <int, _Acc>{};
    for (var h = 0; h < 24; h++) {
      map[h] = _Acc();
    }
    for (final o in orders) {
      final ts = o['paid_at'];
      if (ts == null) continue;
      final dt = _toDateTime(ts);
      if (dt == null) continue;
      map[dt.hour]!.add((o['total_amount'] as num? ?? 0).toDouble());
    }
    return map.entries.map((e) {
      final label = '${e.key.toString().padLeft(2, '0')}:00';
      return PeriodPoint(label: label, amount: e.value.amount, orders: e.value.count);
    }).toList();
  }

  List<PeriodPoint> _groupByDayOfWeek(
      List<Map<String, dynamic>> orders, DateRange range) {
    final days = range.end.difference(range.start).inDays + 1;
    final map = <String, _Acc>{};
    for (var i = 0; i < days; i++) {
      final d = range.start.add(Duration(days: i));
      final key = DateFormat('E d', 'es').format(d);
      map[key] = _Acc();
    }
    for (final o in orders) {
      final ts = o['paid_at'];
      if (ts == null) continue;
      final dt = _toDateTime(ts);
      if (dt == null) continue;
      final key = DateFormat('E d', 'es').format(dt);
      map[key]?.add((o['total_amount'] as num? ?? 0).toDouble());
    }
    return map.entries
        .map((e) => PeriodPoint(label: e.key, amount: e.value.amount, orders: e.value.count))
        .toList();
  }

  /// Un punto por semana del mes. Se agrupa por semanas y no por días porque
  /// cada semana contiene un día de cada tipo: así el efecto "el sábado vende
  /// el triple que el martes" se cancela solo y la comparación entre meses es
  /// justa (a nivel diario serían dos serruchos desfasados entre sí).
  List<PeriodPoint> _groupByWeekOfMonth(
      List<Map<String, dynamic>> orders, DateRange range) {
    // La semana de un día es ((día-1)/7).floor()+1, así que el número de semanas
    // se deriva del último día del rango con esa MISMA fórmula. Antes se usaba
    // ceil()+1 sobre el ancho del rango, lo que creaba siempre una semana extra
    // que ningún día podía llenar: la línea se desplomaba a cero al final.
    final now = DateTime.now();
    // Si el mes está en curso, cortar en hoy: dibujar semanas que aún no ocurren
    // las mostraría como caída de ventas.
    final lastDay = (range.end.year == now.year &&
            range.end.month == now.month &&
            range.end.isAfter(now))
        ? now.day
        : range.end.day;
    final weeksCount = ((lastDay - 1) / 7).floor() + 1;

    final map = <int, _Acc>{};
    for (var w = 1; w <= weeksCount; w++) {
      map[w] = _Acc();
    }
    for (final o in orders) {
      final dt = _toDateTime(o['paid_at']);
      if (dt == null) continue;
      if (dt.year != range.start.year || dt.month != range.start.month) continue;
      final week = ((dt.day - 1) / 7).floor() + 1;
      // Mismo monto que usan las tarjetas de arriba, para que no haya dos
      // verdades distintas en la misma pantalla.
      map[week]?.add((o['payment_amount'] as num?)?.toDouble() ??
          (o['total_amount'] as num? ?? 0).toDouble());
    }
    return map.entries
        .map((e) => PeriodPoint(
            label: 'Sem ${e.key}', amount: e.value.amount, orders: e.value.count))
        .toList();
  }

  List<PeriodPoint> _groupByMonth(
      List<Map<String, dynamic>> orders, DateRange range) {
    final map = <int, _Acc>{};
    for (var m = 1; m <= 12; m++) {
      map[m] = _Acc();
    }
    for (final o in orders) {
      final ts = o['paid_at'];
      if (ts == null) continue;
      final dt = _toDateTime(ts);
      if (dt == null) continue;
      map[dt.month]?.add((o['total_amount'] as num? ?? 0).toDouble());
    }
    final monthNames = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return map.entries
        .map((e) => PeriodPoint(label: monthNames[e.key], amount: e.value.amount, orders: e.value.count))
        .toList();
  }

  Set<String> _extractCategoryIds(List<Map<String, dynamic>> orders) {
    final ids = <String>{};
    for (final o in orders) {
      final rawItems = o['items'];
      if (rawItems is! List) continue;
      for (final item in rawItems) {
        if (item is! Map) continue;
        final id = item['category_id'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  /// Traduce la classification_key de Firestore (COMIDA/BEBIDA/POSTRES/
  /// SERVICIOS/OTRO) a la etiqueta que ve el usuario. Sin el caso SERVICIOS
  /// esos productos quedaban etiquetados en mayúsculas y no calzaban con
  /// ningún filtro de la UI.
  static String _classificationLabel(String key) {
    switch (key.toUpperCase()) {
      case 'COMIDA': return 'Comida';
      case 'BEBIDA': return 'Bebidas';
      case 'POSTRES': return 'Postres';
      case 'SERVICIOS': return 'Servicios';
      case 'OTRO': return 'Otros';
      default: return key;
    }
  }

  /// Retorna tres mapas: {categoryId → label}, {categoryName → label} y
  /// {categoryId → nombre visible de la categoría}. El tercero permite agrupar
  /// ventas por categoría del menú ("Tacos", "Cervezas") y no solo por
  /// clasificación, sin costar una lectura extra a Firestore.
  Future<({
    Map<String, String> byId,
    Map<String, String> byName,
    Map<String, String> nameById,
  })> _fetchCategoryClassifications(Set<String> categoryIds) async {
    final byId = <String, String>{};
    final byName = <String, String>{};
    final nameById = <String, String>{};

    void addDoc(String docId, Map<String, dynamic> data) {
      final key = (data['classification_key'] as String? ??
                   data['classificationKey'] as String? ?? '');
      final name = data['name'] as String? ?? '';
      final label = key.isNotEmpty ? _classificationLabel(key) : '';
      if (docId.isNotEmpty && name.isNotEmpty) nameById[docId] = name;
      if (label.isEmpty) return;
      if (docId.isNotEmpty) byId[docId] = label;
      if (name.isNotEmpty) byName[name] = label;
    }

    // Intento 1: query por tenant_id (más confiable)
    if (_tenantId != null) {
      try {
        final snap = await _firestore.instance
            .collection('categories')
            .where('tenant_id', isEqualTo: _tenantId)
            .get();
        for (final doc in snap.docs) {
          addDoc(doc.id, doc.data());
        }
      } catch (_) {}
    }

    // Intento 2: si no hubo resultados, fetch por IDs específicos
    if (byId.isEmpty && categoryIds.isNotEmpty) {
      try {
        final docs = await Future.wait(categoryIds.map((id) =>
            _firestore.instance.collection('categories').doc(id).get()));
        for (final doc in docs) {
          if (doc.exists) addDoc(doc.id, doc.data()!);
        }
      } catch (_) {}
    }

    return (byId: byId, byName: byName, nameById: nameById);
  }

  /// Busca todos los productos del tenant y construye dos mapas:
  /// productId → clasificación y productId → nombre de su categoría.
  /// Esto es necesario porque los items de las órdenes guardan category_id=null pero sí
  /// tienen product_id, que referencia la colección `products` donde sí está category_id.
  Future<({Map<String, String> classification, Map<String, String> categoryName})>
      _fetchProductClassifications(
    Map<String, String> classificationMap,
    Map<String, String> categoryNameById,
  ) async {
    if (_tenantId == null) return (classification: <String, String>{}, categoryName: <String, String>{});
    try {
      final snap = await _firestore.instance
          .collection('products')
          .where('tenant_id', isEqualTo: _tenantId)
          .get();
      final classification = <String, String>{};
      final categoryName = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final catId = data['category_id'] as String? ?? '';
        if (catId.isEmpty) continue;
        final label = classificationMap[catId] ?? '';
        if (label.isNotEmpty) classification[doc.id] = label;
        final catName = categoryNameById[catId] ?? '';
        if (catName.isNotEmpty) categoryName[doc.id] = catName;
      }
      return (classification: classification, categoryName: categoryName);
    } catch (_) {
      return (classification: <String, String>{}, categoryName: <String, String>{});
    }
  }

  List<ProductSummary> _buildTopProducts(
    List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> prevOrders,
    Map<String, String> classificationMap,
    Map<String, String> classificationByName,
    Map<String, String> productClassificationMap,
  ) {
    final curr = <String, _ProductAcc>{};
    final prev = <String, _ProductAcc>{};
    final classifications = <String, String>{};

    void accumulateItems(List<Map<String, dynamic>> src, Map<String, _ProductAcc> dst) {
      for (final o in src) {
        final rawItems = o['items'];
        if (rawItems is! List) continue;
        // Distribuir el descuento del pedido proporcionalmente entre los items
        final orderSubtotal = (o['subtotal'] as num? ?? 0).toDouble();
        final orderDiscount = (o['discount_amount'] as num? ?? 0).toDouble();
        final discountRatio = (orderSubtotal > 0 && orderDiscount > 0)
            ? orderDiscount / orderSubtotal
            : 0.0;
        for (final item in rawItems) {
          if (item is! Map) continue;
          // Saltar items anulados o de cortesía
          if (item['is_void'] == true || item['is_courtesy'] == true) continue;
          final name = item['name'] as String? ?? 'Sin nombre';
          final qty = (item['qty'] as num? ?? item['quantity'] as num? ?? 1).toInt();
          final unitPrice = (item['unit_price'] as num? ?? item['price'] as num? ?? 0).toDouble();
          double modifiersTotal = 0;
          final rawMods = item['modifiers'];
          if (rawMods is List) {
            for (final mod in rawMods) {
              if (mod is! Map) continue;
              final modPrice = (mod['price'] as num? ?? 0).toDouble();
              final modQty = (mod['qty'] as num? ?? 1).toInt();
              modifiersTotal += modPrice * modQty * qty;
            }
          }
          final lineTotal = (unitPrice * qty + modifiersTotal) * (1 - discountRatio);
          dst.putIfAbsent(name, () => _ProductAcc()).add(qty, lineTotal);
          // Lookup clasificación: producto → categoria → clasificación (fallbacks por id y nombre)
          final productId = item['product_id']?.toString() ?? '';
          final categoryId = item['category_id']?.toString() ?? '';
          final categoryName = item['category_name']?.toString() ?? '';
          final label = (productId.isNotEmpty ? productClassificationMap[productId] : null)
              ?? (categoryId.isNotEmpty ? classificationMap[categoryId] : null)
              ?? (categoryName.isNotEmpty ? classificationByName[categoryName] : null)
              ?? '';
          if (label.isNotEmpty) {
            classifications.putIfAbsent(name, () => label);
          }
        }
      }
    }

    accumulateItems(orders, curr);
    accumulateItems(prevOrders, prev);

    final allNames = curr.keys.toSet();
    final result = allNames.map((name) {
      final c = curr[name]!;
      final p = prev[name] ?? _ProductAcc();
      return ProductSummary(
        name: name,
        category: classifications[name] ?? '',
        quantity: c.qty,
        total: c.amount,
        prevQuantity: p.qty,
        prevTotal: p.amount,
      );
    }).toList();

    result.sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  /// Agrupa las ventas por categoría del menú y las devuelve indexadas por
  /// clasificación. Usa el mismo cálculo de línea que _buildTopProducts
  /// (modificadores incluidos, descuento del pedido prorrateado, sin anulados
  /// ni cortesías) para que los montos cuadren entre ambas vistas.
  ///
  /// El nombre de la categoría se resuelve por product_id: los items de las
  /// órdenes casi nunca traen category_id ni category_name (el POS no los
  /// llena), así que ese es el único camino confiable.
  Map<String, List<CategorySummary>> _buildCategoriesByClassification(
    List<Map<String, dynamic>> orders,
    Map<String, String> productCategoryNameMap,
    Map<String, String> productClassificationMap,
    Map<String, String> categoryNameById,
    Map<String, String> classificationMap,
    Map<String, String> classificationByName,
  ) {
    // clave: "clasificación|categoría"
    final acc = <String, _ProductAcc>{};
    final meta = <String, ({String classification, String name})>{};

    for (final o in orders) {
      final rawItems = o['items'];
      if (rawItems is! List) continue;
      final orderSubtotal = (o['subtotal'] as num? ?? 0).toDouble();
      final orderDiscount = (o['discount_amount'] as num? ?? 0).toDouble();
      final discountRatio = (orderSubtotal > 0 && orderDiscount > 0)
          ? orderDiscount / orderSubtotal
          : 0.0;

      for (final item in rawItems) {
        if (item is! Map) continue;
        if (item['is_void'] == true || item['is_courtesy'] == true) continue;

        final productId = item['product_id']?.toString() ?? '';
        final categoryId = item['category_id']?.toString() ?? '';
        final rawCategoryName = item['category_name']?.toString() ?? '';

        final categoryName = (productId.isNotEmpty ? productCategoryNameMap[productId] : null)
            ?? (categoryId.isNotEmpty ? categoryNameById[categoryId] : null)
            ?? (rawCategoryName.isNotEmpty ? rawCategoryName : null)
            ?? '';
        if (categoryName.isEmpty) continue;

        final classification = (productId.isNotEmpty ? productClassificationMap[productId] : null)
            ?? (categoryId.isNotEmpty ? classificationMap[categoryId] : null)
            ?? (rawCategoryName.isNotEmpty ? classificationByName[rawCategoryName] : null)
            ?? '';
        if (classification.isEmpty) continue;

        final qty = (item['qty'] as num? ?? item['quantity'] as num? ?? 1).toInt();
        final unitPrice = (item['unit_price'] as num? ?? item['price'] as num? ?? 0).toDouble();
        double modifiersTotal = 0;
        final rawMods = item['modifiers'];
        if (rawMods is List) {
          for (final mod in rawMods) {
            if (mod is! Map) continue;
            final modPrice = (mod['price'] as num? ?? 0).toDouble();
            final modQty = (mod['qty'] as num? ?? 1).toInt();
            modifiersTotal += modPrice * modQty * qty;
          }
        }
        final lineTotal = (unitPrice * qty + modifiersTotal) * (1 - discountRatio);

        final key = '$classification|$categoryName';
        acc.putIfAbsent(key, () => _ProductAcc()).add(qty, lineTotal);
        meta[key] = (classification: classification, name: categoryName);
      }
    }

    final grouped = <String, List<CategorySummary>>{};
    acc.forEach((key, value) {
      final info = meta[key]!;
      grouped.putIfAbsent(info.classification, () => []).add(CategorySummary(
            name: info.name,
            classification: info.classification,
            quantity: value.qty,
            total: value.amount,
          ));
    });
    for (final list in grouped.values) {
      list.sort((a, b) => b.total.compareTo(a.total));
    }
    return grouped;
  }

  /// Resuelve userId → nombre desde la colección users (en lotes de 30).
  Future<Map<String, String>> fetchUserNamesById(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final result = <String, String>{};
    const batchSize = 30;
    for (int i = 0; i < userIds.length; i += batchSize) {
      final batch = userIds.sublist(i, (i + batchSize).clamp(0, userIds.length));
      try {
        final snap = await _firestore.users
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          final name = doc.data()['name'] as String?;
          if (name != null && name.isNotEmpty) result[doc.id] = name;
        }
      } catch (_) {}
    }
    return result;
  }

  /// Devuelve las órdenes canceladas del rango actual, filtrando en memoria por fecha.
  Future<List<Map<String, dynamic>>> fetchCancelledOrders() async {
    if (_tenantId == null) return [];
    try {
      final snap = await _firestore.orders
          .where('tenant_id', isEqualTo: _tenantId)
          .where('status', isEqualTo: 'CANCELLED')
          .limit(2000)
          .get();

      final start = _range.start;
      final end   = _range.end;

      return snap.docs.map((d) {
        final data = d.data();
        data['_docId'] = d.id;
        return data;
      }).where((o) {
        if (!_passesLocationFilter(o['location_id'] as String?)) return false;
        // Las canceladas usan cancelled_at > updated_at > created_at para la fecha
        final raw = o['cancelled_at'] ?? o['updated_at'] ?? o['created_at'];
        final dt = _toDateTime(raw);
        if (dt == null) return false;
        return !dt.isBefore(start) && !dt.isAfter(end);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Devuelve los order_ids (doc IDs de Firestore) que tienen factura certificada.
  Future<Set<String>> fetchCertifiedInvoiceOrderIds(List<String> orderDocIds) async {
    if (orderDocIds.isEmpty || _tenantId == null) return {};
    final certified = <String>{};
    const batchSize = 30;
    for (int i = 0; i < orderDocIds.length; i += batchSize) {
      final batch = orderDocIds.sublist(
        i,
        (i + batchSize).clamp(0, orderDocIds.length),
      );
      try {
        final snap = await _firestore.instance
            .collection('invoices')
            .where('order_id', whereIn: batch)
            .where('status', isEqualTo: 'certified')
            .get();
        for (final doc in snap.docs) {
          final orderId = doc.data()['order_id'] as String?;
          if (orderId != null) certified.add(orderId);
        }
      } catch (_) {}
    }
    return certified;
  }
}

DateTime? _toDateTime(dynamic ts) {
  if (ts is Timestamp) return ts.toDate().toLocal();
  if (ts is String) return DateTime.tryParse(ts)?.toLocal();
  return null;
}

class _Acc {
  double amount = 0;
  int count = 0;
  void add(double v) {
    amount += v;
    count++;
  }
}

class _ProductAcc {
  int qty = 0;
  double amount = 0;
  void add(int q, double a) {
    qty += q;
    amount += a;
  }
}
