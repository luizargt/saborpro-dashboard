import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/presentation/screens/dashboard/cajas_screen.dart';

/// Cuando la misma caja se cerró en dos aparatos, el POS anota el segundo
/// cierre (que no cuenta) en `cierres_no_aplicados`. El dueño lo ve aquí, en la
/// tarjeta del corte, con lo que contó y sin montos esperados.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final corte = {
    'id': 'cr-y',
    'userName': 'Herlinda',
    'status': 'closed',
    'openedAt': Timestamp.fromDate(DateTime(2026, 9, 27, 8)),
    'closedAt': Timestamp.fromDate(DateTime(2026, 9, 27, 12, 50)),
    'actualCash': 1500.0,
    'expectedCash': 1500.0,
    'cierres_no_aplicados': [
      {
        'closed_at': Timestamp.fromDate(DateTime(2026, 9, 27, 12, 53)),
        'device_model': 'SUNMI V2s',
        'actualCash': 1250.0,
        'actualCard': 120.0,
        'actualCustomMethods': {'custom_vales': 30.0},
      },
    ],
  };

  test('el corte trae los cierres que no cuentan, sin cambiar ninguna de sus cuentas', () {
    final r = CashRegisterSummary.fromMap(corte);
    expect(r.cierresNoAplicados, hasLength(1));
    expect(r.actualCash, 1500.0);
    expect(r.totalWithdrawals, 0);
    expect(CashRegisterSummary.fromMap({...corte, 'cierres_no_aplicados': null}).cierresNoAplicados, isEmpty);
  });

  Future<void> mostrar(WidgetTester tester, double ancho, Map<String, dynamic> datos) async {
    tester.view.physicalSize = Size(ancho, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1E293B),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: CierresNoAplicadosBlock(
            CashRegisterSummary.fromMap(datos).copyWith(customMethodNames: {'custom_vales': 'Vales'}),
          ),
        ),
      ),
    ));
  }

  for (final ancho in [360.0, 640.0]) {
    testWidgets('se lee a ${ancho.toInt()}dp: qué cierre cuenta, el otro y lo que contó', (tester) async {
      await mostrar(tester, ancho, corte);

      expect(find.text('Esta caja se cerró dos veces'), findsOneWidget);
      // La hora como en la tarjeta del corte (12 h): el dueño compara las dos.
      expect(
        find.text('Vale el cierre del 27/09 a las 12:50 PM. Este otro llegó cuando la caja ya '
            'estaba cerrada y no cambia el cuadre:'),
        findsOneWidget,
      );
      expect(
        find.text('Se hizo el 27/09 a las 12:53 PM en SUNMI V2s. Contó efectivo Q1,250.00, '
            'tarjeta Q120.00, Vales Q30.00.'),
        findsOneWidget,
      );
      expect(find.textContaining('sperado'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('si lo cerró un administrador a la fuerza, lo dice: ese cierre no contó nada', (tester) async {
    await mostrar(tester, 360, {...corte, 'closingNotes': 'Cierre forzado por Super Admin'});

    expect(
      find.text('Se cerró sin contar el dinero (cierre forzado), así que el cuadre de este corte '
          'no es real. Este es el conteo que se hizo: compáralo con lo esperado.'),
      findsOneWidget,
    );
    expect(find.textContaining('Vale el cierre'), findsNothing);
  });

  testWidgets('uno hecho ANTES que el que vale dice que llegó después', (tester) async {
    await mostrar(tester, 360, {
      ...corte,
      'cierres_no_aplicados': [
        {
          'closed_at': Timestamp.fromDate(DateTime(2026, 9, 27, 12, 45)),
          'device_model': 'SUNMI V2s',
          'actualCash': 780.0,
        },
      ],
    });

    expect(
      find.text('Se hizo el 27/09 a las 12:45 PM en SUNMI V2s, pero llegó después. Contó efectivo Q780.00.'),
      findsOneWidget,
    );
  });

  testWidgets('con dos otros cierres dice "3 veces" y los métodos sin nombre van juntos', (tester) async {
    await mostrar(tester, 360, {
      ...corte,
      'cierres_no_aplicados': [
        ...(corte['cierres_no_aplicados'] as List),
        {
          'closed_at': Timestamp.fromDate(DateTime(2026, 9, 27, 13, 5)),
          'actualCash': 0.0,
          'actualCustomMethods': {'x': 10.0, 'y': 20.0},
        },
      ],
    });

    expect(find.text('Esta caja se cerró 3 veces'), findsOneWidget);
    expect(find.text('Se hizo el 27/09 a las 01:05 PM. Contó efectivo Q0.00, otros Q30.00.'), findsOneWidget);
  });

  test('un cierre forzado (no toca los métodos propios) no sale con faltante: suma de lo sellado', () {
    final forzado = CashRegisterSummary.fromMap({
      ...corte,
      'differenceCash': 0.0,
      'expectedCustomMethods': {'custom_vales': 30.0},
      'actualCustomMethods': <String, double>{},
      'differenceCustomMethods': <String, double>{},
    });
    expect(forzado.totalDifference, 0);
    final sinDeclarar = CashRegisterSummary.fromMap({
      ...corte,
      'differenceCash': 0.0,
      'expectedCustomMethods': {'custom_vales': 25.0},
      'actualCustomMethods': <String, double>{},
      'differenceCustomMethods': {'custom_vales': -25.0},
    });
    expect(sinDeclarar.totalDifference, -25, reason: 'un método propio sin declarar sí es faltante');
  });

  test('las ventas de métodos propios salen de lo sellado, no del acumulado con restos', () {
    // Se cobraron Q30 con Vales y esa orden se anuló (el acumulado no la
    // descuenta); Bono Q20. El cierre declaró Vales 0 y Bono 20: cuadrado.
    final r = CashRegisterSummary.fromMap({
      ...corte,
      'differenceCash': 0.0,
      'expectedCustomMethods': {'custom_vales': 30.0, 'custom_bono': 20.0},
      'actualCustomMethods': {'custom_vales': 0.0, 'custom_bono': 20.0},
      'differenceCustomMethods': {'custom_vales': 0.0, 'custom_bono': 0.0},
    });
    expect(r.ventasPropias, {'custom_vales': 0.0, 'custom_bono': 20.0});
    expect(r.totalSales, 1520);
    expect(r.totalDifference, 0);
    // Sin diferencias selladas (cierre forzado), el acumulado, como antes.
    final forzado = CashRegisterSummary.fromMap({
      ...corte,
      'differenceCash': 0.0,
      'expectedCustomMethods': {'custom_vales': 30.0},
    });
    expect(forzado.totalSales, 1530);
  });
}
