import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/location_service.dart';
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

  String? _tenantId;
  String? _locationId;

  List<LocationModel> _locations = [];
  List<LocationModel> get locations => _locations;

  String? _selectedLocationId; // null = todas
  String? get selectedLocationId => _selectedLocationId;

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
    notifyListeners();

    try {
      final prev = _range.previous();
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final we = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final monthStart = DateTime(now.year, now.month, 1);

      // Etapa 1: período actual — necesario para métricas y top platillos
      final currentOrders = await _fetchOrders(_range.start, _range.end);

      // Etapa 2: período anterior — solo para comparación, se descarta al terminar esta etapa
      final prevOrders = await _fetchOrders(prev.start, prev.end);

      // Etapa 3: gastos y costos en paralelo (colecciones pequeñas, bajo impacto en memoria)
      final expResults = await Future.wait([
        _fetchExpenses(_range.start, _range.end),
        _fetchPurchaseCosts(_range.start, _range.end),
      ]);
      final expenses = expResults[0].fold<double>(0, (s, e) => s + (e['amount'] as num? ?? 0).toDouble());
      final purchaseCosts = expResults[1].fold<double>(0, (s, e) => s + (e['total'] as num? ?? 0).toDouble());

      // Etapa 4: construir métricas — después de esto prevOrders puede ser recolectado por el GC
      _metrics = _buildMetrics(
        currentOrders,
        prevOrders,
        _range,
        expenses: expenses,
        purchaseCosts: purchaseCosts,
      );

      // Etapa 5: datos del mes actual para la gráfica de barras diarias
      final monthlyOrders = await _fetchOrders(monthStart, we);
      _monthlyDailyPoints = _groupByDayOfMonth(monthlyOrders, monthStart, now);

      // Opción 2: derivar datos de la semana actual del dataset mensual ya cargado,
      // evitando un _fetchOrders extra. Si la semana cruza el inicio del mes (ej: 28 abr–4 may)
      // se carga por separado para no perder datos.
      final weekCrossesMont = ws.month != monthStart.month || ws.year != monthStart.year;
      if (weekCrossesMont) {
        final weeklyOrders = await _fetchOrders(ws, we);
        _weeklyHourly = _groupByHourPerDay(weeklyOrders, ws);
      } else {
        final weeklyOrders = monthlyOrders.where((o) {
          final dt = _toDateTime(o['paid_at']);
          return dt != null && !dt.isBefore(ws);
        }).toList();
        _weeklyHourly = _groupByHourPerDay(weeklyOrders, ws);
      }

      // Etapa 6: cajas registradoras
      await _fetchCashRegisters();
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

  Future<void> _fetchCashRegisters() async {
    try {
      // Cargar nombres de métodos personalizados desde location settings
      final customMethodNames = await _fetchCustomMethodNames();

      final snap = await _firestore.instance
          .collection('cashRegisters')
          .where('tenantId', isEqualTo: _tenantId)
          .get();

      final all = snap.docs.map((d) => d.data()).where((d) {
        if (_selectedLocationId != null && _selectedLocationId!.isNotEmpty) {
          return d['locationId'] == _selectedLocationId;
        }
        return true;
      }).toList();

      String? locName(String? locId) {
        if (locId == null) return null;
        try { return _locations.firstWhere((l) => l.id == locId).name; } catch (_) { return null; }
      }

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
      final startStr = start.toIso8601String().substring(0, 10);
      final endStr = end.toIso8601String().substring(0, 10);
      var query = _firestore.instance
          .collection('expenses')
          .where('tenant_id', isEqualTo: _tenantId)
          .where('date', isGreaterThanOrEqualTo: startStr)
          .where('date', isLessThanOrEqualTo: endStr);
      final snap = await query.get();
      return snap.docs.map((d) => d.data()).where((e) {
        if (_selectedLocationId != null && _selectedLocationId!.isNotEmpty) {
          return e['location_id'] == _selectedLocationId;
        }
        return true;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPurchaseCosts(
      DateTime start, DateTime end) async {
    try {
      final startStr = start.toIso8601String().substring(0, 10);
      final endStr = end.toIso8601String().substring(0, 10);
      var query = _firestore.instance
          .collection('purchaseOrders')
          .where('tenant_id', isEqualTo: _tenantId)
          .where('status', isEqualTo: 'received')
          .where('received_at', isGreaterThanOrEqualTo: startStr)
          .where('received_at', isLessThanOrEqualTo: endStr);
      final snap = await query.get();
      return snap.docs.map((d) => d.data()).where((e) {
        if (_selectedLocationId != null && _selectedLocationId!.isNotEmpty) {
          return e['location_id'] == _selectedLocationId;
        }
        return true;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOrders(
      DateTime start, DateTime end) async {
    try {
      // Dos queries secuenciales (no paralelas) para incluir órdenes offline (ISO string)
      // sin el pico de memoria que causaba OOM al correrlas en paralelo.
      final snapTs = await _firestore.orders
          .where('tenant_id', isEqualTo: _tenantId)
          .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      final startIso = start.toIso8601String().substring(0, 23);
      final endIso   = end.toIso8601String().substring(0, 23);
      final snapIso = await _firestore.orders
          .where('tenant_id', isEqualTo: _tenantId)
          .where('paid_at', isGreaterThanOrEqualTo: startIso)
          .where('paid_at', isLessThanOrEqualTo: endIso)
          .get();

      final seen = <String>{};
      final all  = <Map<String, dynamic>>[];
      for (final doc in [...snapTs.docs, ...snapIso.docs]) {
        if (seen.add(doc.id)) all.add(doc.data() as Map<String, dynamic>);
      }

      return all.where((o) {
        if (_selectedLocationId != null && _selectedLocationId!.isNotEmpty) {
          if (o['location_id'] != _selectedLocationId) return false;
        }
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
  }) {
    double total = 0, prevTotal = 0;
    double grossSales = 0, discounts = 0, taxes = 0, tips = 0, refunds = 0, deliveryFees = 0;
    final salesByMethod = <String, double>{};

    for (final o in orders) {
      // Usar payment_amount si existe (mismo valor que usa CashRegisterCalculator)
      final rawTotal = (o['total_amount'] as num? ?? 0).toDouble();
      final t = (o['payment_amount'] as num?)?.toDouble() ?? rawTotal;
      total += t;
      grossSales += (o['subtotal'] as num? ?? t).toDouble();
      discounts += (o['discount_amount'] as num? ?? 0).toDouble();
      taxes += (o['tax_amount'] as num? ?? 0).toDouble();
      tips += (o['tip_amount'] as num? ?? 0).toDouble();
      deliveryFees += (o['delivery_fee'] as num? ?? 0).toDouble();
      if (o['is_refund'] == true) refunds += t;

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

    return PeriodMetrics(
      totalSales: total,
      totalOrders: count,
      avgTicket: avg,
      prevTotalSales: prevTotal,
      prevTotalOrders: prevCount,
      prevAvgTicket: prevAvg,
      chartPoints: _buildChartPoints(orders, range),
      topProducts: _buildTopProducts(orders, prevOrders),
      grossSales: grossSales,
      discounts: discounts,
      taxes: taxes,
      tips: tips,
      refunds: refunds,
      deliveryFees: deliveryFees,
      operationalExpenses: expenses,
      purchaseCosts: purchaseCosts,
      salesByMethod: salesByMethod,
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

  List<ProductSummary> _buildTopProducts(
    List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> prevOrders,
  ) {
    final curr = <String, _ProductAcc>{};
    final prev = <String, _ProductAcc>{};

    void accumulateItems(List<Map<String, dynamic>> src, Map<String, _ProductAcc> dst) {
      for (final o in src) {
        final rawItems = o['items'];
        if (rawItems is! List) continue;
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
          final lineTotal = unitPrice * qty + modifiersTotal;
          dst.putIfAbsent(name, () => _ProductAcc()).add(qty, lineTotal);
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
        quantity: c.qty,
        total: c.amount,
        prevQuantity: p.qty,
        prevTotal: p.amount,
      );
    }).toList();

    result.sort((a, b) => b.total.compareTo(a.total));
    return result.take(20).toList();
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
