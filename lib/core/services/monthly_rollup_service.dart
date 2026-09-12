import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../data/models/dashboard_data.dart';

/// Resumen ya calculado de UN mes de UNA sucursal, guardado en Firestore.
///
/// Por qué en Firestore y no en el teléfono: el negocio más grande tiene 6
/// personas entrando a Sabor Manager. Guardado en cada dispositivo, ese mes se
/// calcularía 6 veces, y otra vez por cada teléfono nuevo, cada navegador y
/// cada reinstalación. Guardado acá se calcula UNA vez y lo lee todo el mundo.
///
/// Un mes cerrado no cambia nunca, así que se calcula una sola vez en la vida.
/// El mes en curso se completa con lo nuevo en vez de rehacerse entero.
class MonthlyRollup {
  const MonthlyRollup({
    required this.year,
    required this.month,
    required this.locationId,
    required this.orderCount,
    required this.cancelledCount,
    required this.lastPaidAt,
    required this.metrics,
  });

  final int year;
  final int month;
  final String locationId;

  /// Órdenes con `paid_at` en el mes, canceladas INCLUIDAS. Es la huella que
  /// permite saber si el mes cambió desde que se calculó, comparándola contra
  /// un conteo de servidor que cuesta una lectura por cada mil órdenes.
  final int orderCount;
  final int cancelledCount;

  /// La orden más reciente que entró en este resumen. Para el mes en curso,
  /// lo nuevo se pide a partir de acá en vez de rehacer el mes entero.
  final DateTime? lastPaidAt;

  /// El mes ya calculado. Se guardan los mismos números que muestra la
  /// pantalla, para que leerlo sea idéntico a haberlo calculado.
  final PeriodMetrics metrics;

  Map<String, dynamic> toMap(String tenantId) => {
        'tenant_id': tenantId,
        'location_id': locationId,
        'year': year,
        'month': month,
        'order_count': orderCount,
        'cancelled_count': cancelledCount,
        'last_paid_at': lastPaidAt == null ? null : Timestamp.fromDate(lastPaidAt!),
        'computed_at': FieldValue.serverTimestamp(),
        'schema': kSchema,
        'total_sales': metrics.totalSales,
        'total_orders': metrics.totalOrders,
        'gross_sales': metrics.grossSales,
        'discounts': metrics.discounts,
        'taxes': metrics.taxes,
        'tips': metrics.tips,
        'refunds': metrics.refunds,
        'delivery_fees': metrics.deliveryFees,
        'courtesy_total': metrics.courtesyTotal,
        'tips_count': metrics.tipsCount,
        'delivery_count': metrics.deliveryCount,
        'courtesy_count': metrics.courtesyCount,
        'sales_by_method': metrics.salesByMethod,
        // Tope de productos guardados: un documento de Firestore no pasa de
        // 1 MB y un menú largo con un año de ventas se acerca. 300 sobra para
        // cualquier top que se muestre, y el orden es por venta, así que lo
        // que se recorta es la cola irrelevante.
        'top_products': [
          for (final p in metrics.topProducts.take(kMaxProductos))
            {
              'name': p.name,
              'category': p.category,
              'quantity': p.quantity,
              'total': p.total,
            }
        ],
        'categories': {
          for (final e in metrics.categoriesByClassification.entries)
            e.key: [
              for (final c in e.value)
                {'name': c.name, 'quantity': c.quantity, 'total': c.total}
            ]
        },
      };

  static const int kSchema = 1;
  static const int kMaxProductos = 300;

  static MonthlyRollup? fromMap(Map<String, dynamic> d) {
    if ((d['schema'] as num?)?.toInt() != kSchema) return null;
    final rawLast = d['last_paid_at'];
    return MonthlyRollup(
      year: (d['year'] as num?)?.toInt() ?? 0,
      month: (d['month'] as num?)?.toInt() ?? 0,
      locationId: d['location_id'] as String? ?? '',
      orderCount: (d['order_count'] as num?)?.toInt() ?? 0,
      cancelledCount: (d['cancelled_count'] as num?)?.toInt() ?? 0,
      lastPaidAt: rawLast is Timestamp ? rawLast.toDate() : null,
      metrics: PeriodMetrics(
        totalSales: (d['total_sales'] as num?)?.toDouble() ?? 0,
        totalOrders: (d['total_orders'] as num?)?.toInt() ?? 0,
        avgTicket: 0, // se recalcula al sumar los meses
        prevTotalSales: 0,
        prevTotalOrders: 0,
        prevAvgTicket: 0,
        chartPoints: const [],
        topProducts: [
          for (final raw in (d['top_products'] as List<dynamic>? ?? []))
            if (raw is Map)
              ProductSummary(
                name: raw['name'] as String? ?? '',
                category: raw['category'] as String? ?? '',
                quantity: (raw['quantity'] as num?)?.toInt() ?? 0,
                total: (raw['total'] as num?)?.toDouble() ?? 0,
                prevQuantity: 0,
                prevTotal: 0,
              )
        ],
        categoriesByClassification: {
          for (final e in (d['categories'] as Map<String, dynamic>? ?? {}).entries)
            e.key: [
              for (final raw in (e.value as List<dynamic>? ?? []))
                if (raw is Map)
                  CategorySummary(
                    name: raw['name'] as String? ?? '',
                    classification: e.key,
                    quantity: (raw['quantity'] as num?)?.toInt() ?? 0,
                    total: (raw['total'] as num?)?.toDouble() ?? 0,
                  )
            ]
        },
        grossSales: (d['gross_sales'] as num?)?.toDouble() ?? 0,
        discounts: (d['discounts'] as num?)?.toDouble() ?? 0,
        taxes: (d['taxes'] as num?)?.toDouble() ?? 0,
        tips: (d['tips'] as num?)?.toDouble() ?? 0,
        refunds: (d['refunds'] as num?)?.toDouble() ?? 0,
        deliveryFees: (d['delivery_fees'] as num?)?.toDouble() ?? 0,
        courtesyTotal: (d['courtesy_total'] as num?)?.toDouble() ?? 0,
        tipsCount: (d['tips_count'] as num?)?.toInt() ?? 0,
        deliveryCount: (d['delivery_count'] as num?)?.toInt() ?? 0,
        courtesyCount: (d['courtesy_count'] as num?)?.toInt() ?? 0,
        salesByMethod: {
          for (final e in (d['sales_by_method'] as Map<String, dynamic>? ?? {}).entries)
            e.key: (e.value as num?)?.toDouble() ?? 0
        },
      ),
    );
  }
}

/// Qué hay que hacer con un mes antes de mostrarlo.
enum RollupEstado {
  /// No existe: hay que calcularlo entero.
  falta,

  /// Está y el mes no cambió desde que se guardó: se usa tal cual, gratis.
  alDia,

  /// Solo aparecieron órdenes nuevas: alcanza con pedir las posteriores a
  /// `lastPaidAt` y sumarlas.
  soloNuevas,

  /// Cambió algo que no es "se agregaron ventas": una cancelación tardía, una
  /// devolución, una orden borrada. Hay que rehacerlo.
  rehacer,
}

class RollupChequeo {
  const RollupChequeo(this.estado, this.rollup, this.orderCount, this.cancelledCount);
  final RollupEstado estado;
  final MonthlyRollup? rollup;
  final int orderCount;
  final int cancelledCount;
}

/// Lee y escribe los resúmenes mensuales. No calcula nada: el cálculo vive en
/// el dashboard, que es quien sabe armar las métricas de un mes.
class MonthlyRollupService {
  MonthlyRollupService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String kCollection = 'salesRollups';

  /// `locationId` vacío significa "todas las sucursales del negocio".
  String docId(String tenantId, String locationId, int year, int month) =>
      '${tenantId}__${locationId.isEmpty ? 'all' : locationId}__$year-${month.toString().padLeft(2, '0')}';

  Future<MonthlyRollup?> read(
      String tenantId, String locationId, int year, int month) async {
    try {
      final doc = await _db
          .collection(kCollection)
          .doc(docId(tenantId, locationId, year, month))
          .get();
      if (!doc.exists) return null;
      return MonthlyRollup.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('[ROLLUP] no se pudo leer $year-$month: $e');
      return null;
    }
  }

  Future<void> write(String tenantId, MonthlyRollup rollup) async {
    try {
      await _db
          .collection(kCollection)
          .doc(docId(tenantId, rollup.locationId, rollup.year, rollup.month))
          .set(rollup.toMap(tenantId));
    } catch (e) {
      // Que no se pueda guardar no puede tumbar el reporte: el mes ya está
      // calculado en memoria y se muestra igual, solo que la próxima vez habrá
      // que volver a calcularlo.
      debugPrint('[ROLLUP] no se pudo guardar ${rollup.year}-${rollup.month}: $e');
    }
  }

  /// Pregunta a Firestore cuántas órdenes tiene el mes y lo compara con lo que
  /// decía el resumen guardado. Dos conteos, entre una y cuatro lecturas cada
  /// uno, contra las miles que costaría rehacer el mes a ciegas.
  Future<RollupChequeo> chequear({
    required String tenantId,
    required String locationId,
    required int year,
    required int month,
  }) async {
    final guardado = await read(tenantId, locationId, year, month);

    Query<Map<String, dynamic>> base() {
      Query<Map<String, dynamic>> q =
          _db.collection('orders').where('tenant_id', isEqualTo: tenantId);
      if (locationId.isNotEmpty) q = q.where('location_id', isEqualTo: locationId);
      return q
          .where('paid_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(year, month, 1)))
          .where('paid_at',
              isLessThan: Timestamp.fromDate(DateTime(year, month + 1, 1)));
    }

    int total, canceladas;
    try {
      final res = await Future.wait([
        base().count().get().then((r) => r.count ?? 0),
        base()
            .where('status', isEqualTo: 'CANCELLED')
            .count()
            .get()
            .then((r) => r.count ?? 0),
      ]);
      total = res[0];
      canceladas = res[1];
    } catch (e) {
      debugPrint('[ROLLUP] no se pudo chequear $year-$month: $e');
      // Sin poder comprobar, lo seguro es rehacerlo antes que mostrar un número
      // viejo como si fuera de hoy.
      return RollupChequeo(RollupEstado.rehacer, guardado, 0, 0);
    }

    if (guardado == null) {
      return RollupChequeo(RollupEstado.falta, null, total, canceladas);
    }
    if (guardado.orderCount == total && guardado.cancelledCount == canceladas) {
      return RollupChequeo(RollupEstado.alDia, guardado, total, canceladas);
    }
    // Solo creció y nadie canceló nada: lo de antes sigue valiendo y basta con
    // sumarle lo que entró después. Cualquier otra combinación (menos órdenes,
    // o una cancelación nueva) toca números ya contados y obliga a rehacer.
    if (total > guardado.orderCount &&
        canceladas == guardado.cancelledCount &&
        guardado.lastPaidAt != null) {
      return RollupChequeo(RollupEstado.soloNuevas, guardado, total, canceladas);
    }
    return RollupChequeo(RollupEstado.rehacer, guardado, total, canceladas);
  }
}
