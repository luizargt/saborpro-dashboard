import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Totales de ventas calculados POR FIRESTORE, sin bajar las órdenes.
///
/// Por qué existe: la vista de año bajaba hasta 5.000 órdenes con `limit()` y
/// sin `orderBy`. Firestore ordena implícitamente por el campo del filtro de
/// rango, así que ese tope devolvía las 5.000 MÁS ANTIGUAS del período y
/// descartaba en silencio todo lo posterior. En septiembre de 2026, nueve
/// clientes ya pasaban ese tope: el peor veía una cuarta parte de su año.
///
/// Subir el tope no arregla nada: una orden pesa 3,5 KB y un año del cliente
/// más grande son 69 MB y 20.669 lecturas facturadas cada vez que alguien abre
/// la pantalla. Con agregaciones el mismo año cuesta unas 170 lecturas.
///
/// LO QUE ESTE SERVICIO NO PUEDE DAR: nada que viva dentro de los renglones del
/// ticket (productos, categorías, cortesías). Eso necesita el documento entero.
/// La vista de año lo reemplaza por un aviso que invita a elegir un mes.
class SalesAggregatesService {
  SalesAggregatesService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Tope de órdenes offline que se bajan como documentos. En producción son
  /// unidades al año (6 en el peor tenant), pero si alguna vez fueran miles
  /// hay que enterarse en vez de tragarse el corte, que es justo el bug que
  /// este servicio viene a arreglar.
  static const int kOfflineLimit = 2000;

  /// Tope de canceladas que se bajan para restarlas. El tenant con más historial
  /// tiene 131 en total.
  static const int kCancelledLimit = 3000;

  /// Suma un período completo agrupado por mes.
  ///
  /// [start] y [end] deben caer dentro del mismo año calendario: el resultado
  /// se indexa por número de mes.
  Future<YearAggregate> fetchYear({
    required String tenantId,
    required int year,
    String? locationId,
    Set<String> allowedLocationIds = const {},
    List<String> desglosePorSucursal = const [],
  }) async {
    final sw = Stopwatch()..start();

    // Una consulta por sucursal cuando hay filtro; una sola global cuando el
    // usuario ve todo. Firestore no sabe filtrar por "estas sucursales sí y
    // estas no" dentro de una agregación, así que el reparto se hace acá.
    final scopes = <String?>[];
    if (locationId != null && locationId.isNotEmpty) {
      scopes.add(locationId);
    } else if (allowedLocationIds.isNotEmpty) {
      scopes.addAll(allowedLocationIds);
    } else {
      scopes.add(null); // todas: una sola consulta, sin filtro de sucursal
    }

    final months = List<_MonthAcc>.generate(12, (_) => _MonthAcc());
    final porSucursal = <String, double>{};
    var tips = 0.0;
    var delivery = 0.0;
    var truncated = false;

    for (final scope in scopes) {
      final r = await _fetchScope(tenantId, year, scope);
      for (var m = 0; m < 12; m++) {
        months[m].orders += r.months[m].orders;
        months[m].sales += r.months[m].sales;
      }
      tips += r.tips;
      delivery += r.delivery;
      truncated = truncated || r.truncated;
      // Cuando ya se consultó sucursal por sucursal, el desglose sale gratis.
      if (scope != null) {
        porSucursal[scope] = r.months.fold(0.0, (s, m) => s + m.sales);
      }
    }

    // Vista de "todas las sucursales": una consulta anual más por sucursal para
    // no perder la tabla de reparto. Son unidades de lecturas, no miles.
    if (porSucursal.isEmpty && desglosePorSucursal.length > 1) {
      final totales = await Future.wait(
        desglosePorSucursal.map((id) => _sumYearFor(tenantId, year, id)),
      );
      for (var i = 0; i < desglosePorSucursal.length; i++) {
        porSucursal[desglosePorSucursal[i]] = totales[i];
      }
    }

    debugPrint('[AGG] año $year: ${sw.elapsedMilliseconds}ms, '
        '${scopes.length} sucursal(es)');

    return YearAggregate(
      year: year,
      months: [
        for (var m = 0; m < 12; m++)
          MonthAggregate(month: m + 1, orders: months[m].orders, sales: months[m].sales),
      ],
      tips: tips,
      deliveryFees: delivery,
      salesByLocation: porSucursal,
      truncated: truncated,
    );
  }

  /// Venta del año de UNA sucursal, con los mismos ajustes que el total.
  Future<double> _sumYearFor(String tenantId, int year, String locationId) async {
    Query<Map<String, dynamic>> base() => _db
        .collection('orders')
        .where('tenant_id', isEqualTo: tenantId)
        .where('location_id', isEqualTo: locationId);
    final from = DateTime(year, 1, 1);
    final to = DateTime(year + 1, 1, 1);
    final ranged = base()
        .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('paid_at', isLessThan: Timestamp.fromDate(to));
    try {
      final res = await ranged.aggregate(sum('payment_amount')).get();
      var total = res.getSum('payment_amount') ?? 0;
      final ajustes = await Future.wait([
        _fetchCancelled(base(), from, to),
        _fetchSinPago(base(), from, to),
        _fetchOffline(base(), from, to),
      ]);
      for (final o in ajustes[0].rows) {
        total -= o.aggSales;
      }
      for (final o in ajustes[1].rows) {
        total += o.sales;
      }
      for (final o in ajustes[2].rows) {
        total += o.sales;
      }
      return total;
    } catch (e) {
      debugPrint('[AGG] sucursal $locationId: $e');
      return 0;
    }
  }

  Future<_ScopeResult> _fetchScope(String tenantId, int year, String? locationId) async {
    Query<Map<String, dynamic>> base() {
      Query<Map<String, dynamic>> q =
          _db.collection('orders').where('tenant_id', isEqualTo: tenantId);
      if (locationId != null) q = q.where('location_id', isEqualTo: locationId);
      return q;
    }

    Query<Map<String, dynamic>> ranged(DateTime from, DateTime to) => base()
        .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('paid_at', isLessThan: Timestamp.fromDate(to));

    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year + 1, 1, 1);

    // Las 12 consultas del gráfico, en paralelo.
    final monthly = await Future.wait([
      for (var m = 0; m < 12; m++)
        _sumMonth(ranged(DateTime(year, m + 1, 1), DateTime(year, m + 2, 1))),
    ]);

    // Propina y envío van en consultas aparte, y esto NO es un descuido:
    // Firestore exige que los campos del índice coincidan con los de la
    // agregación, así que cada combinación de sumas necesita su propio índice.
    // Pedirlas todas juntas obligaría a un índice de seis campos y no ahorraría
    // nada: se cobra por entradas de índice leídas, no por consulta.
    //
    // Que `delivery_fee` falte en el 97% de las órdenes no estorba: en una suma
    // un campo ausente o nulo vale cero y el documento igual cuenta.
    final extras = await Future.wait([
      _sumField(ranged(yearStart, yearEnd), 'tip_amount'),
      _sumField(ranged(yearStart, yearEnd), 'delivery_fee'),
    ]);

    // Las agregaciones no saben excluir las canceladas, así que se bajan y se
    // restan. Son decenas al año, no miles.
    final ajustes = await Future.wait([
      _fetchCancelled(base(), yearStart, yearEnd),
      _fetchOffline(base(), yearStart, yearEnd),
      _fetchSinPago(base(), yearStart, yearEnd),
    ]);
    final cancelled = ajustes[0];
    final offline = ajustes[1];
    final sinPago = ajustes[2];

    final months = List<_MonthAcc>.generate(12, (i) => _MonthAcc()
      ..orders = monthly[i].orders
      ..sales = monthly[i].sales);

    var tips = extras[0];
    var delivery = extras[1];

    for (final o in cancelled.rows) {
      final m = o.month - 1;
      if (m >= 0 && m < 12) {
        months[m].orders -= 1;
        months[m].sales -= o.aggSales;
      }
      tips -= o.tip;
      delivery -= o.delivery;
    }

    // Las de pago nulo ya están contadas como ticket, pero valiendo cero: acá
    // se les suma el monto que la pantalla les daría. Las canceladas de este
    // grupo quedaron fuera en `_fetchSinPago`, así que no se descuentan dos
    // veces.
    for (final o in sinPago.rows) {
      final m = o.month - 1;
      if (m >= 0 && m < 12) months[m].sales += o.sales;
    }

    // Las órdenes cobradas sin internet guardan `paid_at` como texto, y una
    // consulta por rango de Timestamp no las ve. Son unidades al año, así que
    // se bajan enteras y se suman al mes que les toca.
    for (final o in offline.rows) {
      final m = o.month - 1;
      if (m >= 0 && m < 12) {
        months[m].orders += 1;
        months[m].sales += o.sales;
      }
      tips += o.tip;
      delivery += o.delivery;
    }

    return _ScopeResult(
      months: months,
      tips: tips,
      delivery: delivery,
      truncated: cancelled.truncated || offline.truncated,
    );
  }

  /// Tickets y monto del mes.
  ///
  /// El monto es `sum(payment_amount)` a secas. Una suma de servidor trata el
  /// campo ausente o nulo como cero y NO descarta el documento, así que las
  /// órdenes con `payment_amount` en null entran valiendo cero. El `??` que usa
  /// la pantalla las cuenta por su `total_amount`, y esa diferencia se corrige
  /// en `_fetchSinPago`, que las busca y las suma aparte. Son 8 en todo el
  /// sistema, pero valen Q705 y un reporte de ventas tiene que cuadrar.
  Future<_MonthAcc> _sumMonth(Query<Map<String, dynamic>> q) async {
    final res = await q.aggregate(count(), sum('payment_amount')).get();
    return _MonthAcc()
      ..orders = res.count ?? 0
      ..sales = res.getSum('payment_amount') ?? 0;
  }

  /// Las órdenes cuyo `payment_amount` quedó en null: la agregación las contó
  /// valiendo cero, así que hay que devolverles su `total_amount`.
  Future<_RowsResult> _fetchSinPago(
      Query<Map<String, dynamic>> base, DateTime from, DateTime to) async {
    try {
      final snap = await base
          .where('payment_amount', isNull: true)
          .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('paid_at', isLessThan: Timestamp.fromDate(to))
          .limit(kCancelledLimit)
          .get();
      final rows = <_Row>[];
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['status'] as String?) == 'CANCELLED') continue;
        final r = _Row.from(data);
        if (r != null) rows.add(r);
      }
      return _RowsResult(rows: rows, truncated: snap.docs.length >= kCancelledLimit);
    } catch (e) {
      debugPrint('[AGG] sin pago: $e');
      return const _RowsResult(rows: [], truncated: true);
    }
  }

  Future<double> _sumField(Query<Map<String, dynamic>> q, String field) async {
    try {
      final res = await q.aggregate(sum(field)).get();
      return res.getSum(field) ?? 0;
    } catch (e) {
      // Un campo que ningún documento del tenant usa puede no tener índice.
      // Vale cero antes que tumbar la pantalla entera.
      debugPrint('[AGG] sin suma de $field: $e');
      return 0;
    }
  }

  Future<_RowsResult> _fetchCancelled(
      Query<Map<String, dynamic>> base, DateTime from, DateTime to) async {
    try {
      final snap = await base
          .where('status', isEqualTo: 'CANCELLED')
          .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('paid_at', isLessThan: Timestamp.fromDate(to))
          .limit(kCancelledLimit)
          .get();
      return _RowsResult(
        rows: snap.docs.map((d) => _Row.from(d.data())).whereType<_Row>().toList(),
        truncated: snap.docs.length >= kCancelledLimit,
      );
    } catch (e) {
      debugPrint('[AGG] canceladas: $e');
      return const _RowsResult(rows: [], truncated: true);
    }
  }

  Future<_RowsResult> _fetchOffline(
      Query<Map<String, dynamic>> base, DateTime from, DateTime to) async {
    try {
      final snap = await base
          .where('paid_at', isGreaterThanOrEqualTo: from.toIso8601String().substring(0, 23))
          .where('paid_at', isLessThan: to.toIso8601String().substring(0, 23))
          .limit(kOfflineLimit)
          .get();
      final rows = <_Row>[];
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['status'] as String?) == 'CANCELLED') continue;
        final r = _Row.from(data);
        if (r != null) rows.add(r);
      }
      return _RowsResult(rows: rows, truncated: snap.docs.length >= kOfflineLimit);
    } catch (e) {
      debugPrint('[AGG] offline: $e');
      return const _RowsResult(rows: [], truncated: true);
    }
  }
}

/// Una orden reducida a lo que hace falta para ajustar los totales.
class _Row {
  const _Row({
    required this.month,
    required this.sales,
    required this.aggSales,
    required this.tip,
    required this.delivery,
  });

  final int month;

  /// Lo que la pantalla le asigna a esta orden: `payment_amount ?? total_amount`.
  final double sales;

  /// Lo que la agregación ya le sumó: `payment_amount`, o cero si quedó en null.
  /// Restar esto y no `sales` es lo que evita descontar de más una cancelada
  /// que nunca llegó a sumar su total.
  final double aggSales;

  final double tip;
  final double delivery;

  static _Row? from(Map<String, dynamic> data) {
    final raw = data['paid_at'];
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate().toLocal();
    } else if (raw is String) {
      dt = DateTime.tryParse(raw)?.toLocal();
    }
    if (dt == null) return null;
    final total = (data['total_amount'] as num?)?.toDouble() ?? 0;
    final pago = (data['payment_amount'] as num?)?.toDouble();
    return _Row(
      month: dt.month,
      sales: pago ?? total,
      aggSales: pago ?? 0,
      tip: (data['tip_amount'] as num?)?.toDouble() ?? 0,
      delivery: (data['delivery_fee'] as num?)?.toDouble() ?? 0,
    );
  }
}

class _RowsResult {
  const _RowsResult({required this.rows, required this.truncated});
  final List<_Row> rows;
  final bool truncated;
}

class _MonthAcc {
  int orders = 0;
  double sales = 0;
}

class _ScopeResult {
  const _ScopeResult({
    required this.months,
    required this.tips,
    required this.delivery,
    required this.truncated,
  });
  final List<_MonthAcc> months;
  final double tips;
  final double delivery;
  final bool truncated;
}

/// Ventas de un mes, calculadas por Firestore.
class MonthAggregate {
  const MonthAggregate({required this.month, required this.orders, required this.sales});

  /// 1 = enero.
  final int month;
  final int orders;
  final double sales;
}

/// Ventas de un año completo, calculadas por Firestore.
class YearAggregate {
  const YearAggregate({
    required this.year,
    required this.months,
    required this.tips,
    required this.deliveryFees,
    this.salesByLocation = const {},
    this.truncated = false,
  });

  final int year;
  final List<MonthAggregate> months;
  final double tips;
  final double deliveryFees;

  /// Venta del año por sucursal, para la tabla de reparto. Vacío cuando el
  /// negocio tiene una sola sucursal, que es cuando esa tabla no se muestra.
  final Map<String, double> salesByLocation;

  /// Verdadero si algún ajuste tocó su tope y el total podría quedar corto.
  /// La pantalla lo muestra en vez de callárselo, que es lo que hacía antes.
  final bool truncated;

  int get totalOrders => months.fold(0, (s, m) => s + m.orders);
  double get totalSales => months.fold(0.0, (s, m) => s + m.sales);
  double get avgTicket => totalOrders == 0 ? 0 : totalSales / totalOrders;
}
