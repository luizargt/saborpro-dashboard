import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/services/location_service.dart';
import 'package:saborpro_reports/core/utils/formato_dinero.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/presentation/screens/dashboard/cajas_screen.dart';
import 'package:saborpro_reports/presentation/widgets/location_sales_breakdown.dart';

/// Manager tenía la Q escrita a mano en cada pantalla: una sucursal que vende
/// en dólares veía sus ventas en quetzales. Ahora los montos llevan el signo de
/// moneda que la sucursal tiene configurado en Sabor Suite.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  // La moneda es global: dejarla puesta contaminaría los tests que esperan Q.
  tearDown(() => fijarMoneda('Q'));

  group('formatoDinero', () {
    test('sin configurar, quetzales', () {
      expect(formatoDinero(125000), 'Q1,250.00');
    });

    test('con dólares: el signo, el negativo y el cero', () {
      fijarMoneda('\$');
      expect(formatoDinero(125000), '\$1,250.00');
      expect(formatoDinero(-55800), '−\$558.00');
      expect(formatoDinero(0), '\$0.00');
    });

    test('un código de letras lleva espacio; un signo, no', () {
      fijarMoneda('USD');
      expect(formatoDinero(125000), 'USD 1,250.00');
      fijarMoneda('C\$');
      expect(formatoDinero(125000), 'C\$1,250.00');
      fijarMoneda('L');
      expect(formatoDinero(125000), 'L1,250.00');
    });

    test('un signo vacío vuelve a Q', () {
      fijarMoneda('  ');
      expect(moneda, 'Q');
    });
  });

  group('monedaMasUsada', () {
    test('sin sucursales, Q', () {
      expect(monedaMasUsada(const []), 'Q');
    });

    test('gana la que más sucursales usan', () {
      expect(monedaMasUsada(const ['Q', '\$', '\$']), '\$');
    });

    test('en empate, la primera', () {
      expect(monedaMasUsada(const ['\$', 'Q']), '\$');
    });
  });

  testWidgets('el corte de caja sale en la moneda de la sucursal', (tester) async {
    fijarMoneda('\$');
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CajasScreen(
            open: const [],
            closed: [
              CashRegisterSummary.fromMap({
                'id': 'cr-usd',
                'userName': 'Herlinda',
                'status': 'closed',
                'openedAt': Timestamp.fromDate(DateTime(2026, 10, 5, 8)),
                'closedAt': Timestamp.fromDate(DateTime(2026, 10, 5, 12)),
                'initialCash': 0.0,
                'expectedCash': 125.0,
                'actualCash': 125.0,
                'differenceCash': 0.0,
              }),
            ],
            orders: const [],
            expenseItems: const [],
            locationNames: const {},
          ),
        ),
      ),
    ));

    expect(find.textContaining('\$125.00'), findsWidgets);
    expect(find.textContaining('Q125.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en "Todas", cada sucursal muestra su venta con su propia moneda',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LocationSalesBreakdown(
          locations: [
            LocationModel(id: 'gt', name: 'Zona 10', currencySymbol: 'Q'),
            LocationModel(id: 'sv', name: 'San Salvador', currencySymbol: '\$'),
          ],
          orders: const [
            {'location_id': 'gt', 'payment_amount': 1500.0},
            {'location_id': 'sv', 'payment_amount': 200.0},
          ],
          expenseItems: const [],
          purchaseItems: const [],
        ),
      ),
    ));

    expect(find.textContaining('Q 1,500'), findsOneWidget);
    expect(find.textContaining('\$ 200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
