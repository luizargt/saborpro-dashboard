import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/presentation/screens/dashboard/cajas_screen.dart';

/// Un pedido con un dato raro no puede hacer desaparecer toda la pantalla de
/// cajas: con la versión anterior solo se perdía la tarjeta de ese corte.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  CashRegisterSummary sellada(String id, String nombre, int hora) => CashRegisterSummary.fromMap({
        'id': id,
        'userName': nombre,
        'status': 'closed',
        'locationId': 'gt',
        'openedAt': Timestamp.fromDate(DateTime(2026, 11, 20, hora)),
        'closedAt': Timestamp.fromDate(DateTime(2026, 11, 20, hora + 2)),
        'actualCash': 100.0,
        'differenceCash': 0.0,
      });

  // Un corte antiguo, sin diferencias selladas: sus ventas se recalculan desde los pedidos.
  final sinSellar = CashRegisterSummary.fromMap({
    'id': 'beto',
    'userName': 'Beto SinSellar',
    'status': 'closed',
    'locationId': 'gt',
    'openedAt': Timestamp.fromDate(DateTime(2026, 2, 1, 8)),
    'closedAt': Timestamp.fromDate(DateTime(2026, 2, 1, 16)),
    'expectedCash': 250.0,
    'actualCash': 250.0,
  });

  Future<void> mostrar(WidgetTester tester, List<Map<String, dynamic>> pedidos) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CajasScreen(
            open: const [],
            closed: [sellada('ana', 'Ana Sellada', 8), sinSellar, sellada('carla', 'Carla Sellada', 12)],
            orders: pedidos,
            expenseItems: const [],
            locationNames: const {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('un pedido con el método de pago de otro tipo no hace desaparecer los demás cortes', (tester) async {
    await mostrar(tester, [
      {
        'payment_method': 5, // un dato mal escrito, dentro de la ventana del corte sin sellar
        'payment_amount': 100.0,
        'paid_at': Timestamp.fromDate(DateTime(2026, 2, 1, 10)),
        'location_id': 'gt',
      },
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Ana Sellada'), findsOneWidget);
    expect(find.text('Carla Sellada'), findsOneWidget);
    // El corte afectado sigue a la vista, con los acumulados del corte.
    expect(find.text('Beto SinSellar'), findsOneWidget);
  });

  testWidgets('con pedidos normales, el corte sin sellar se recalcula desde ellos', (tester) async {
    await mostrar(tester, [
      {
        'payment_method': 'cash',
        'payment_amount': 100.0,
        'paid_at': Timestamp.fromDate(DateTime(2026, 2, 1, 10)),
        'location_id': 'gt',
      },
    ]);
    expect(find.text('Beto SinSellar'), findsOneWidget);
    expect(find.text('1 recalculado de los pedidos: pueden repetir ventas'), findsOneWidget);
  });
}
