import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/presentation/screens/dashboard/cajas_screen.dart';

/// En la tarjeta de un corte sellado, el Total y la tabla por método incluyen
/// los métodos propios, con lo contado = esperado + diferencia sellada (igual
/// que el ticket del POS): la tabla suma lo mismo que la insignia. Antes el
/// Total no los sumaba y la tabla no los mostraba.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final base = {
    'id': 'cr-t',
    'userName': 'Herlinda',
    'status': 'closed',
    'openedAt': Timestamp.fromDate(DateTime(2026, 9, 27, 8)),
    'closedAt': Timestamp.fromDate(DateTime(2026, 9, 27, 12, 50)),
    'initialCash': 0.0,
    'expectedCash': 100.0,
    'actualCash': 100.0,
    'differenceCash': 0.0,
  };

  Future<void> mostrar(
    WidgetTester tester,
    Map<String, dynamic> datos, {
    Map<String, String> nombres = const {'custom_vales': 'Vales', 'custom_cupon': 'Cupón'},
  }) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SingleChildScrollView(
          child: CajasScreen(
            open: const [],
            closed: [
              CashRegisterSummary.fromMap(datos).copyWith(customMethodNames: nombres),
            ],
            orders: const [],
            expenseItems: const [],
            locationNames: const {},
          ),
        ),
      ),
    ));
  }

  Finder filaCon(String etiqueta) =>
      find.ancestor(of: find.text(etiqueta), matching: find.byType(Row)).first;

  testWidgets('un método propio sin declarar: en el Total y en la tabla con su faltante; el resto no sale', (tester) async {
    // Vendió 100 en efectivo y 25 con Vales, que se apagó y no se declaró:
    // faltan 25. Cupón 10 es el resto de una venta anulada.
    await mostrar(tester, {
      ...base,
      'expectedCustomMethods': {'custom_vales': 25.0, 'custom_cupon': 10.0},
      'actualCustomMethods': <String, double>{},
      'differenceCustomMethods': {'custom_vales': -25.0},
    });

    expect(find.descendant(of: filaCon('Total'), matching: find.text('Q125.00')), findsOneWidget);
    expect(find.text('Q-25.00'), findsOneWidget, reason: 'la fila de Vales en la tabla, igual que la insignia');
    expect(find.text('Cupón'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un cierre forzado: el método propio cuenta en el Total y sale sin diferencia', (tester) async {
    await mostrar(tester, {
      ...base,
      'expectedCustomMethods': {'custom_vales': 30.0},
    });

    expect(find.descendant(of: filaCon('Total'), matching: find.text('Q130.00')), findsOneWidget);
    expect(find.text('Q-30.00'), findsNothing, reason: 'no es un faltante: el forzado da por contado lo esperado');
    expect(find.text('+Q0.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un método propio de nombre largo no desborda la tarjeta a 360 dp', (tester) async {
    await mostrar(
      tester,
      {
        ...base,
        'expectedCustomMethods': {'custom_vales': 12345.67},
        'actualCustomMethods': {'custom_vales': 12345.67},
        'differenceCustomMethods': {'custom_vales': 0.0},
      },
      nombres: {'custom_vales': 'Vales de despensa de la Distribuidora del Norte S.A.'},
    );

    expect(tester.takeException(), isNull, reason: 'antes: "A RenderFlex overflowed"');
    expect(find.text('Vales de despensa de la Distribuidora del Norte S.A.'), findsWidgets);
  });

  testWidgets('"otros" sale con su nombre, no con el id', (tester) async {
    await mostrar(tester, {
      ...base,
      'expectedCustomMethods': {'otros': 15.0},
      'actualCustomMethods': {'otros': 15.0},
      'differenceCustomMethods': {'otros': 0.0},
    });

    expect(find.text('Otros (revisar)'), findsWidgets);
    expect(find.text('otros'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
