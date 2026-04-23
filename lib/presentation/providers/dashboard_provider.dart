import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/location_service.dart';
import '../../core/utils/date_range.dart';
import '../../data/models/dashboard_data.dart';

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

      // Para el gráfico de horas, siempre cargamos la semana actual
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final we = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final results = await Future.wait([
        _fetchOrders(_range.start, _range.end),
        _fetchOrders(prev.start, prev.end),
        _fetchExpenses(_range.start, _range.end),
        _fetchPurchaseCosts(_range.start, _range.end),
        _fetchOrders(ws, we),
      ]);

      _weeklyHourly = _groupByHourPerDay(results[4], ws);

      _metrics = _buildMetrics(
        results[0],
        results[1],
        _range,
        expenses: results[2].fold(0.0, (s, e) => s + (e['amount'] as num? ?? 0).toDouble()),
        purchaseCosts: results[3].fold(0.0, (s, e) => s + (e['total'] as num? ?? 0).toDouble()),
      );
    } catch (e) {
      _error = 'Error cargando datos: $e';
    }

    _loading = false;
    notifyListeners();
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
    final snap = await _firestore.orders
        .where('tenant_id', isEqualTo: _tenantId)
        .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    return snap.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((o) {
          if (_selectedLocationId != null && _selectedLocationId!.isNotEmpty) {
            if (o['location_id'] != _selectedLocationId) return false;
          }
          final status = o['payment_status'] as String? ?? '';
          final orderStatus = o['status'] as String? ?? '';
          return status == 'PAID' || orderStatus == 'COBRADO' || orderStatus == 'CERRADO';
        })
        .toList();
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

    for (final o in orders) {
      final t = (o['total_amount'] as num? ?? 0).toDouble();
      total += t;
      grossSales += (o['subtotal'] as num? ?? t).toDouble();
      discounts += (o['discount_amount'] as num? ?? 0).toDouble();
      taxes += (o['tax_amount'] as num? ?? 0).toDouble();
      tips += (o['tip_amount'] as num? ?? 0).toDouble();
      deliveryFees += (o['delivery_fee'] as num? ?? 0).toDouble();
      if (o['is_refund'] == true) refunds += t;
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
        final dt = (ts as Timestamp).toDate().toLocal();
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

  List<PeriodPoint> _groupByHour(List<Map<String, dynamic>> orders) {
    final map = <int, _Acc>{};
    for (var h = 0; h < 24; h++) {
      map[h] = _Acc();
    }
    for (final o in orders) {
      final ts = o['paid_at'];
      if (ts == null) continue;
      final dt = (ts as Timestamp).toDate().toLocal();
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
      final dt = (ts as Timestamp).toDate().toLocal();
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
      final dt = (ts as Timestamp).toDate().toLocal();
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
      final dt = (ts as Timestamp).toDate().toLocal();
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
        final items = o['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final map = item as Map<String, dynamic>;
          // Saltar items anulados o de cortesía
          if (map['is_void'] == true || map['is_courtesy'] == true) continue;
          final name = map['name'] as String? ?? 'Sin nombre';
          // La app guarda el campo como 'qty', no 'quantity'
          final qty = (map['qty'] as num? ?? map['quantity'] as num? ?? 1).toInt();
          final unitPrice = (map['unit_price'] as num? ?? map['price'] as num? ?? 0).toDouble();
          // Sumar precios de modificadores (extras, ingredientes adicionales, etc.)
          double modifiersTotal = 0;
          final modifiers = map['modifiers'] as List<dynamic>? ?? [];
          for (final mod in modifiers) {
            final m = mod as Map<String, dynamic>;
            final modPrice = (m['price'] as num? ?? 0).toDouble();
            final modQty = (m['qty'] as num? ?? 1).toInt();
            modifiersTotal += modPrice * modQty * qty;
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
