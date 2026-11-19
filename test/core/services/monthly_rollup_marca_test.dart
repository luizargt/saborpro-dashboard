import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/monthly_rollup_service.dart';
import 'package:saborpro_reports/data/models/dashboard_data.dart';

/// Desde 2026-11 la cortesía se valora con sus extras. Los resúmenes de cada
/// mes guardados antes la tienen sin extras y se reconocen por no traer la
/// marca `courtesy_with_extras`: esos se rehacen una vez (ver
/// MonthlyRollupService.chequear).
void main() {
  Map<String, dynamic> guardado({Object? marca}) => {
        'schema': MonthlyRollup.kSchema,
        'year': 2026,
        'month': 3,
        'location_id': '',
        'order_count': 10,
        'cancelled_count': 0,
        'courtesy_total': 110.0,
        'courtesy_count': 1,
        'scope_verified': true,
        if (marca != null) 'courtesy_with_extras': marca,
      };

  test('un resumen de antes, sin la marca, se lee como sin extras', () {
    final r = MonthlyRollup.fromMap(guardado());
    expect(r, isNotNull, reason: 'el esquema no cambió: se sigue leyendo');
    expect(r!.cortesiaConExtras, isFalse);
  });

  test('con la marca se lee como con extras', () {
    expect(MonthlyRollup.fromMap(guardado(marca: true))!.cortesiaConExtras,
        isTrue);
    expect(MonthlyRollup.fromMap(guardado(marca: 'true'))!.cortesiaConExtras,
        isFalse);
  });

  test('uno recién calculado se guarda con la marca y con el mismo esquema',
      () {
    final nuevo = MonthlyRollup(
      year: 2026,
      month: 11,
      locationId: '',
      orderCount: 3,
      cancelledCount: 0,
      lastPaidAt: null,
      metrics: PeriodMetrics(
        totalSales: 0,
        totalOrders: 0,
        avgTicket: 0,
        prevTotalSales: 0,
        prevTotalOrders: 0,
        prevAvgTicket: 0,
        chartPoints: const [],
        topProducts: const [],
        courtesyTotal: 146,
      ),
    );
    expect(nuevo.cortesiaConExtras, isTrue);
    final mapa = nuevo.toMap('t1');
    expect(mapa['courtesy_with_extras'], isTrue);
    // Subir el esquema haría que las apps sin actualizar tiraran los
    // resúmenes nuevos y la nueva los de ellas, una y otra vez.
    expect(mapa['schema'], 1);
    expect(MonthlyRollup.kSchema, 1);
  });
}
