// test/presentation/widgets/location_breakdown_moneda_test.dart
//
// "Ventas por sucursal" con sucursales en monedas distintas: convertido, todo
// va con el signo de la principal; una sucursal sin tipo de cambio no entra
// ni en la tabla ni en el porcentaje (sumarla sin convertir inflaría el
// total con pesos contados como quetzales). Y las cajas, que nunca se
// convierten, se pintan con el signo de su sucursal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/services/location_service.dart';
import 'package:saborpro_reports/core/utils/formato_dinero.dart';
import 'package:saborpro_reports/presentation/widgets/location_sales_breakdown.dart';

final _reforma = LocationModel(id: 'reforma', name: 'La Reforma', currencySymbol: 'Q');
final _zacapa = LocationModel(id: 'zacapa', name: 'Zacapa', currencySymbol: 'Q');
final _palermo =
    LocationModel(id: 'palermo', name: 'Palermo', currencySymbol: '\$', country: 'Argentina');

Future<void> _montar(WidgetTester tester, Widget w) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => fijarMoneda('Q'));

  testWidgets('convertido: todas con el signo de la principal', (tester) async {
    await _montar(
      tester,
      LocationSalesBreakdown(
        locations: [_palermo, _reforma],
        orders: const [
          {'location_id': 'reforma', 'payment_amount': 600.0},
          // Ya convertida a quetzales por el dashboard.
          {'location_id': 'palermo', 'payment_amount': 400.0},
        ],
        expenseItems: const [],
        purchaseItems: const [],
        simboloConvertido: 'Q',
      ),
    );
    expect(find.textContaining('Q 400'), findsOneWidget);
    expect(find.textContaining('\$ 400'), findsNothing);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('sin tipo de cambio: fuera de la tabla y del porcentaje', (tester) async {
    await _montar(
      tester,
      LocationSalesBreakdown(
        locations: [_palermo, _reforma, _zacapa],
        orders: const [
          {'location_id': 'reforma', 'payment_amount': 600.0},
          {'location_id': 'zacapa', 'payment_amount': 400.0},
        ],
        expenseItems: const [],
        purchaseItems: const [],
        // Vista de año: la suma de Palermo llega en pesos.
        precomputedSales: const {'reforma': 600, 'zacapa': 400, 'palermo': 125000},
        simboloConvertido: 'Q',
        excluidas: const {'palermo'},
      ),
    );
    expect(find.text('Palermo'), findsNothing);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('una sola moneda: igual que antes, cada una con su signo', (tester) async {
    await _montar(
      tester,
      LocationSalesBreakdown(
        locations: [_reforma, _zacapa],
        orders: const [
          {'location_id': 'reforma', 'payment_amount': 500.0},
          {'location_id': 'zacapa', 'payment_amount': 500.0},
        ],
        expenseItems: const [],
        purchaseItems: const [],
      ),
    );
    expect(find.textContaining('Q 500'), findsNWidgets(2));
  });

  testWidgets('MonedaLocal pinta una parte con el signo de su sucursal', (tester) async {
    fijarMoneda('Q');
    late String adentro, afuera;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Builder(builder: (c) {
          afuera = MonedaLocal.de(c);
          return const SizedBox();
        }),
        MonedaLocal(
          simbolo: 'CLP',
          child: Builder(builder: (c) {
            adentro = MonedaLocal.de(c);
            return const SizedBox();
          }),
        ),
      ]),
    ));
    expect(afuera, 'Q');
    expect(adentro, 'CLP ');
  });

  testWidgets('una inactiva que vendió en el período aparece y la tabla cuadra con el total',
      (tester) async {
    final cerrada = LocationModel(id: 'vieja', name: 'Zona 1', currencySymbol: 'Q', active: false);
    await _montar(
      tester,
      LocationSalesBreakdown(
        locations: [_reforma, _zacapa],
        otras: [cerrada],
        orders: const [
          {'location_id': 'reforma', 'payment_amount': 600.0},
          {'location_id': 'zacapa', 'payment_amount': 400.0},
          {'location_id': 'vieja', 'payment_amount': 1000.0},
        ],
        expenseItems: const [],
        purchaseItems: const [],
      ),
    );
    expect(find.text('Zona 1 (inactiva)'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
  });

  testWidgets('una inactiva sin ventas en el período no aparece', (tester) async {
    final cerrada = LocationModel(id: 'vieja', name: 'Zona 1', currencySymbol: 'Q', active: false);
    await _montar(
      tester,
      LocationSalesBreakdown(
        locations: [_reforma, _zacapa],
        otras: [cerrada],
        orders: const [
          {'location_id': 'reforma', 'payment_amount': 600.0},
          {'location_id': 'zacapa', 'payment_amount': 400.0},
        ],
        expenseItems: const [],
        purchaseItems: const [],
      ),
    );
    expect(find.textContaining('Zona 1'), findsNothing);
    expect(find.text('60%'), findsOneWidget);
  });
}
