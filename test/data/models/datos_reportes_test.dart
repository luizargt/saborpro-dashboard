import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/atencion_inicio.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/dashboard_data.dart';
import 'package:saborpro_reports/data/models/datos_reportes.dart';

/// El dato de "ahora" de cada tarjeta de Reportes: cuándo se muestra y cuándo
/// se calla (lo que no se sabe no se afirma).
void main() {
  PeriodMetrics metricas({
    double gastos = 125,
    double compras = 100,
    double cortesias = 35,
    double propinas = 293,
    double propinasEnCaja = 0,
    bool detalle = true,
  }) =>
      PeriodMetrics(
        totalSales: 3259,
        totalOrders: 28,
        avgTicket: 116.39,
        prevTotalSales: 0,
        prevTotalOrders: 0,
        prevAvgTicket: 0,
        chartPoints: const [],
        topProducts: const [],
        operationalExpenses: gastos,
        purchaseCosts: compras,
        courtesyTotal: cortesias,
        tips: propinas,
        tipsOutsideSales: propinasEnCaja,
        detailAvailable: detalle,
      );

  CashRegisterSummary abierta(String id) =>
      CashRegisterSummary(id: id, userId: id, userName: id, status: 'open', openedAt: DateTime(2026, 11, 20, 8));

  CashRegisterSummary cierre(String id, double? dif, {String loc = 'GT'}) => CashRegisterSummary(
        id: id,
        userId: id,
        userName: id,
        status: 'closed',
        openedAt: DateTime(2026, 11, 20, 8),
        closedAt: DateTime(2026, 11, 20, 13),
        locationId: loc,
        differenceCash: dif,
      );

  Map<String, DatoReporte> armar({
    String periodo = 'Hoy',
    PeriodMetrics? metrics,
    bool cajasOk = true,
    List<CashRegisterSummary> abiertas = const [],
    List<CashRegisterSummary> cerradas = const [],
    ResumenPedidosInicio pedidos = ResumenPedidosInicio.vacio,
    String signoVista = 'Q',
    Map<String, String> signos = const {},
  }) =>
      DatosReportes.armar(
        periodo: periodo,
        metrics: metrics,
        cajasOk: cajasOk,
        abiertas: abiertas,
        cerradas: cerradas,
        signoDeCaja: (loc) => signos[loc] ?? 'Q',
        signoVista: signoVista,
        pedidos: pedidos,
      );

  group('lo que no se sabe no se muestra', () {
    test('sin métricas (cargando o con error) no hay gastos, propinas ni cortesías', () {
      final d = armar(metrics: null);
      expect(d.containsKey(IdReporte.gastos), isFalse);
      expect(d.containsKey(IdReporte.propinas), isFalse);
      expect(d.containsKey(IdReporte.cortesias), isFalse);
    });

    test('con las cajas sin leer no hay dato de cierres, ni "Ninguna abierta"', () {
      final d = armar(metrics: metricas(), cajasOk: false, abiertas: const [], cerradas: [cierre('a', -50)]);
      expect(d.containsKey(IdReporte.cierres), isFalse);
      // Lo demás no depende de las cajas.
      expect(d.containsKey(IdReporte.gastos), isTrue);
    });

    test('Rentabilidad y Cancelados no llevan dato (su cifra sale de otros cálculos)', () {
      final d = armar(metrics: metricas());
      expect(d.keys.toSet(), {IdReporte.cierres, IdReporte.gastos, IdReporte.propinas, IdReporte.cortesias});
    });
  });

  group('propinas', () {
    test('lo mismo que dice la tarjeta del Inicio: las de los tickets y las metidas a la caja', () {
      final d = armar(metrics: metricas(propinas: 293, propinasEnCaja: 50))[IdReporte.propinas]!;
      expect(d.texto, 'Hoy Q343.00');
      expect(d.partes.where((p) => p.negrita).map((p) => p.texto), ['Q343.00']);
      expect(d.bandera, isNull);
    });

    test('lleva el nombre del período y el signo de la vista', () {
      expect(armar(metrics: metricas(), periodo: 'noviembre 2026', signoVista: 'USD ')[IdReporte.propinas]!.texto,
          'noviembre 2026 USD 293.00');
    });

    test('sin propinas dice Q0.00, no se esconde', () {
      expect(armar(metrics: metricas(propinas: 0))[IdReporte.propinas]!.texto, 'Hoy Q0.00');
    });

    test('la vista de año sí lo sabe: es un total del servidor, no detalle de tickets', () {
      expect(armar(metrics: metricas(detalle: false)).containsKey(IdReporte.propinas), isTrue);
    });
  });

  group('cierres de caja', () {
    test('cuántas cajas siguen abiertas', () {
      expect(armar().entries.single.value.texto, 'Ninguna caja abierta');
      final una = armar(abiertas: [abierta('a')])[IdReporte.cierres]!;
      expect(una.texto, '1 caja abierta');
      expect(una.partes.where((p) => p.negrita).map((p) => p.texto), ['1']);
      expect(armar(abiertas: [abierta('a'), abierta('b')])[IdReporte.cierres]!.texto, '2 cajas abiertas');
    });

    test('el faltante del período va en una banderita roja, sumado', () {
      final d = armar(cerradas: [cierre('a', -100), cierre('b', -50), cierre('c', 20)])[IdReporte.cierres]!;
      expect(d.bandera, const BanderaReporte('Faltante Q150', TonoBandera.rojo));
    });

    test('sin faltante (cuadrado, sobrante o sin diferencias selladas) no hay banderita', () {
      expect(armar(cerradas: [cierre('a', 0), cierre('b', 40)])[IdReporte.cierres]!.bandera, isNull);
      // Sin sellar no se inventa.
      expect(armar(cerradas: [cierre('a', null)])[IdReporte.cierres]!.bandera, isNull);
    });

    test('faltantes en monedas distintas no se suman: solo cuántos cierres', () {
      final d = armar(
        cerradas: [cierre('a', -100, loc: 'GT'), cierre('b', -20, loc: 'SV')],
        signos: {'GT': 'Q', 'SV': 'USD'},
      )[IdReporte.cierres]!;
      expect(d.bandera, const BanderaReporte('2 cierres con faltante', TonoBandera.rojo));
    });

    test('faltantes de varias sucursales con la misma moneda sí se suman, con su signo', () {
      final d = armar(
        cerradas: [cierre('a', -100, loc: 'S1'), cierre('b', -20.5, loc: 'S2')],
        signos: {'S1': 'USD', 'S2': 'USD'},
      )[IdReporte.cierres]!;
      expect(d.bandera!.texto, 'Faltante USD 120.50');
    });
  });

  group('gastos', () {
    test('el total del período: gastos, retiros y compras, como la cabecera del reporte', () {
      final d = armar(metrics: metricas(gastos: 125, compras: 100))[IdReporte.gastos]!;
      expect(d.texto, 'Hoy Q225.00');
      expect(d.partes.where((p) => p.negrita).map((p) => p.texto), ['Q225.00']);
      expect(d.bandera, isNull);
    });

    test('lleva el nombre del período y el signo de la vista', () {
      expect(armar(metrics: metricas(), periodo: 'noviembre 2026', signoVista: 'USD ')[IdReporte.gastos]!.texto,
          'noviembre 2026 USD 225.00');
    });

    test('sin gastos dice Q0.00, no se esconde', () {
      expect(armar(metrics: metricas(gastos: 0, compras: 0))[IdReporte.gastos]!.texto, 'Hoy Q0.00');
    });
  });

  group('cortesías', () {
    test('lo regalado y, si hay, cuántas no dicen por qué', () {
      final d = armar(
        metrics: metricas(),
        pedidos: const ResumenPedidosInicio(cortesiasSinMotivo: 1, montoSinMotivo: 35),
      )[IdReporte.cortesias]!;
      expect(d.texto, 'Hoy Q35.00');
      expect(d.bandera, const BanderaReporte('1 sin motivo', TonoBandera.ambar));
    });

    test('con todas explicadas no hay banderita', () {
      expect(armar(metrics: metricas())[IdReporte.cortesias]!.bandera, isNull);
    });

    test('la vista de año no tiene los tickets: no hay dato', () {
      expect(armar(metrics: metricas(detalle: false)).containsKey(IdReporte.cortesias), isFalse);
      // Pero los gastos del año sí se conocen.
      expect(armar(metrics: metricas(detalle: false)).containsKey(IdReporte.gastos), isTrue);
    });
  });

  group('faltantesDe (la regla única)', () {
    test('de mayor a menor, solo con diferencias selladas y desde un centavo', () {
      final f = AtencionInicio.faltantesDe([
        cierre('a', -10),
        cierre('b', -300),
        cierre('c', null),
        cierre('d', -0.004),
        cierre('e', 5),
        cierre('f', -0.01),
      ]);
      expect(f.map((e) => e.$1.id), ['b', 'a', 'f']);
      expect(f.map((e) => e.$2), [300, 10, 0.01]);
    });
  });
}
