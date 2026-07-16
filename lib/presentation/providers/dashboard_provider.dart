import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/date_range.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/cash_register_summary.dart';

class DashboardProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();
  final LocationService _locationService = LocationService();

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
    } catch (_) {}
  }

  void selectLocation(String? locationId) {
    _selectedLocationId = locationId;
    load();
  }

  void setRange(DateRange range) {
    _range = range;
    load();
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

      // Etapa 1+2 en paralelo: período actual y anterior simultáneamente
      final orderPair = await Future.wait([
        _fetchOrders(_range.start, _range.end),
        _fetchOrders(prev.start, prev.end),
      ]);
      final currentOrders = orderPair[0];
      var prevOrders = orderPair[1];
      _currentOrders = currentOrders;
      _mark('orders(actual+anterior) docs=${currentOrders.length}+${prevOrders.length}');

      // Etapa 0b: cargar clasificaciones: por categoria y por producto
      final categoryIds = _extractCategoryIds(currentOrders);
      final classMaps = await _fetchCategoryClassifications(categoryIds);
      final classificationMap = classMaps.byId;
      final classificationByName = classMaps.byName;
      _mark('categoryClassifications');
      // El mapa de productos se cachea: el menú no cambia al cambiar el rango de fechas
      final _prodWasCached = _cachedProductClassificationMap != null;
      _cachedProductClassificationMap ??= await _fetchProductClassifications(classificationMap);
      final productClassificationMap = _cachedProductClassificationMap!;
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
      final rawCashRegisters = expResults[2] as List<Map<String, dynamic>>;
      final customMethodNames = expResults[3] as Map<String, String>;
      final withdrawals = _extractWithdrawals(rawCashRegisters, _range.start, _range.end);
      // _fetchExpenses = gastos manuales; withdrawals = retiros de caja
      _expenseItems = [...expResults[0] as List<Map<String, dynamic>>, ...withdrawals];
      _purchaseItems = expResults[1] as List<Map<String, dynamic>>;
      final expenses = _expenseItems.fold<double>(0, (s, e) => s + (e['amount'] as num? ?? 0).toDouble());
      final purchaseCosts = _purchaseItems.fold<double>(0, (s, e) => s + (e['total'] as num? ?? 0).toDouble());

      _weeklyHourly = needsWeekly
          ? _groupByHourPerDay(expResults[4] as List<Map<String, dynamic>>, ws)
          : [];
      _monthlyDailyPoints = needsMonthly
          ? _groupByDayOfMonth(expResults[5] as List<Map<String, dynamic>>, monthStart, now)
          : [];

      // Etapa 4: resumir cajas (sin Firestore adicional) y construir métricas finales.
      _buildCashRegisterSummaries(rawCashRegisters, customMethodNames);
      _metrics = _buildMetrics(
        currentOrders,
        prevOrders,
        _range,
        expenses: expenses,
        purchaseCosts: purchaseCosts,
        classificationMap: classificationMap,
        classificationByName: classificationByName,
        productClassificationMap: productClassificationMap,
      );
      prevOrders = [];
      _mark('metrics+summaries');
      debugPrint('[PERF] === load() TOTAL: ${_swTotal.elapsedMilliseconds}ms ===');
    } catch (e, st) {
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
  void _buildCashRegisterSummaries(
      List<Map<String, dynamic>> registers, Map<String, String> customMethodNames) {
    try {
      String? locName(String? locId) {
        if (locId == null) return null;
        try { return _locations.firstWhere((l) => l.id == locId).name; } catch (_) { return null; }
      }

      final all = registers.where((d) {
        return _passesLocationFilter(d['locationId'] as String?);
      }).toList();

      _openRegisters = all
          .where((d) => d['status'] == 'open')
          .map((d) {
            final r = CashRegisterSummary.fromMap(d);
            return r.copyWith(customMethodNames: customMethodNames, locationName: locName(r.locationId));
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
            return r.copyWith(customMethodNames: customMethodNames, locationName: locName(r.locationId));
          })
          .toList()
        ..sort((a, b) => (b.closedAt ?? b.openedAt).compareTo(a.closedAt ?? a.openedAt));
    } catch (_) {
      _openRegisters = [];
      _closedRegisters = [];
    }
  }

  Future<Map<String, String>> _fetchCustomMethodNames() async {
    try {
      final locationId = _selectedLocationId ?? (_locations.isNotEmpty ? _locations.first.id : null);
      if (locationId == null) return {};
      final doc = await _firestore.instance.collection('locations').doc(locationId).get();
      if (!doc.exists) return {};
      final settings = (doc.data() as Map<String, dynamic>)['settings'];
      if (settings == null) return {};
      final methods = settings['custom_payment_methods'] as List<dynamic>? ?? [];
      return {
        for (final m in methods)
          if (m is Map<String, dynamic> && m['id'] != null && m['name'] != null)
            m['id'] as String: m['name'] as String,
      };
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
          if (!_passesLocationFilter(data['location_id'] as String?)) continue;
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
          'date': dt.toIso8601String(),
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

      return snap.docs.map((d) => d.data()).where((e) {
        return _passesLocationFilter(e['location_id'] as String?);
      }).toList();
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('query', 'fetchPurchaseCosts');
      });
      return [];
    }
  }

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

      return all.where((o) {
        if (!_passesLocationFilter(o['location_id'] as String?)) return false;
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
      prevTotal += (o['total_amount'] as num? ?? 0).toDouble();
    }

    final count = orders.length;
    final prevCount = prevOrders.length;
    final avg = count > 0 ? total / count : 0.0;
    final prevAvg = prevCount > 0 ? prevTotal / prevCount : 0.0;

    final topProducts = _buildTopProducts(orders, prevOrders, classificationMap, classificationByName, productClassificationMap);

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

    return PeriodMetrics(
      totalSales: total,
      totalOrders: count,
      avgTicket: avg,
      prevTotalSales: prevTotal,
      prevTotalOrders: prevCount,
      prevAvgTicket: prevAvg,
      chartPoints: _buildChartPoints(orders, range),
      topProducts: topProducts,
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

  List<PeriodPoint> _groupByWeekOfMonth(
      List<Map<String, dynamic>> orders, DateRange range) {
    final map = <int, _Acc>{};
    final weeksCount = ((range.end.day - range.start.day) / 7).ceil() + 1;
    for (var w = 1; w <= weeksCount; w++) {
      map[w] = _Acc();
    }
    for (final o in orders) {
      final ts = o['paid_at'];
      if (ts == null) continue;
      final dt = _toDateTime(ts);
      if (dt == null) continue;
      final week = ((dt.day - 1) / 7).floor() + 1;
      map[week]?.add((o['total_amount'] as num? ?? 0).toDouble());
    }
    return map.entries
        .map((e) => PeriodPoint(label: 'Sem ${e.key}', amount: e.value.amount, orders: e.value.count))
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

  static String _classificationLabel(String key) {
    switch (key.toUpperCase()) {
      case 'COMIDA': return 'Comida';
      case 'BEBIDA': return 'Bebidas';
      case 'POSTRES': return 'Postres';
      default: return key;
    }
  }

  /// Retorna dos mapas: {categoryId → label} y {categoryName → label}
  Future<({Map<String, String> byId, Map<String, String> byName})>
      _fetchCategoryClassifications(Set<String> categoryIds) async {
    final byId = <String, String>{};
    final byName = <String, String>{};

    void addDoc(String docId, Map<String, dynamic> data) {
      final key = (data['classification_key'] as String? ??
                   data['classificationKey'] as String? ?? '');
      final name = data['name'] as String? ?? '';
      final label = key.isNotEmpty ? _classificationLabel(key) : '';
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

    return (byId: byId, byName: byName);
  }

  /// Busca todos los productos del tenant y construye un mapa productId → clasificación.
  /// Esto es necesario porque los items de las órdenes guardan category_id=null pero sí
  /// tienen product_id, que referencia la colección `products` donde sí está category_id.
  Future<Map<String, String>> _fetchProductClassifications(
      Map<String, String> classificationMap) async {
    if (_tenantId == null || classificationMap.isEmpty) return {};
    try {
      final snap = await _firestore.instance
          .collection('products')
          .where('tenant_id', isEqualTo: _tenantId)
          .get();
      final result = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final catId = data['category_id'] as String? ?? '';
        final label = classificationMap[catId] ?? '';
        if (label.isNotEmpty) result[doc.id] = label;
      }
      return result;
    } catch (_) {
      return {};
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
