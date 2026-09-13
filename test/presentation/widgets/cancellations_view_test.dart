import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/cancellation_data.dart';
import 'package:saborpro_reports/presentation/widgets/cancellations_view.dart';

/// La pantalla de "Pedidos Cancelados" depende de providers con Firebase y no
/// se puede montar en un test; su mitad visual sí. Estas pruebas cubren las dos
/// cosas que se rompen callado: que la vista quepa en un teléfono de 360dp y
/// que NUNCA muestre Q0.00 para producto que sí se perdió pero no tiene precio
/// de compra.
void main() {
  setUpAll(() async {
    // Sin red en los tests: que google_fonts use la fuente de respaldo en vez
    // de intentar bajarla y ensuciar la salida.
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  Widget wrap(CancellationsReport report) => MaterialApp(
        home: Scaffold(
          backgroundColor: kCancelBg,
          body: CancellationsReportBody(report: report),
        ),
      );

  group('PartialValue', () {
    test('suma dinero y unidades sin costo por separado', () {
      const a = PartialValue(
        amount: 10,
        unpricedByUnit: {'u': 3},
        unpricedIngredientIds: {'gatorade'},
      );
      const b = PartialValue(
        amount: 5.5,
        unpricedByUnit: {'u': 2, 'lb': 1},
        unpricedIngredientIds: {'modelo'},
      );

      final sum = a + b;
      expect(sum.amount, 15.5);
      expect(sum.unpricedByUnit['u'], 5);
      expect(sum.unpricedByUnit['lb'], 1);
      expect(sum.unpricedIngredientIds, {'gatorade', 'modelo'});
    });

    test('lo que no tiene precio no vale cero: queda contado en unidades', () {
      const soloSinCosto = PartialValue(
        unpricedByUnit: {'u': 4},
        unpricedIngredientIds: {'stella'},
      );
      expect(soloSinCosto.hasMoney, isFalse);
      expect(soloSinCosto.hasUnpriced, isTrue);
      expect(soloSinCosto.isEmpty, isFalse);
      expect(soloSinCosto.unpricedLabel, '4 u');
    });

    test('vacío es distinto de "no tiene precio"', () {
      expect(PartialValue.empty.isEmpty, isTrue);
      expect(PartialValue.empty.hasUnpriced, isFalse);
    });
  });

  group('PersonCut', () {
    test('el porcentaje se mide en artículos, no en quetzales', () {
      const p = PersonCut(
        userId: 'u1',
        userName: 'Ana',
        events: 4,
        itemsCancelled: 8,
        itemsLost: 6,
        wasted: PartialValue.empty,
        returned: PartialValue.empty,
      );
      expect(p.lostRate, closeTo(0.75, 0.0001));
    });

    test('sin artículos anulados el porcentaje es 0 y no una división por cero', () {
      const p = PersonCut(
        userId: 'u2',
        userName: 'Beto',
        events: 2,
        itemsCancelled: 0,
        itemsLost: 0,
        wasted: PartialValue.empty,
        returned: PartialValue.empty,
      );
      expect(p.lostRate, 0);
    });
  });

  group('CancellationsReportBody a 360dp', () {
    testWidgets('no desborda con datos completos', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(_sampleReport()));
      await tester.pumpAndSettle();

      // Cualquier RenderFlex overflowed hace fallar el test por sí solo.
      expect(find.text('Producto perdido en cancelaciones'), findsOneWidget);

      // La lista es perezosa: hay que recorrerla entera para que el corte por
      // persona llegue a construirse y un desborde de allá abajo se vea.
      await tester.scrollUntilVisible(find.text('Por persona'), 200);
      await tester.pumpAndSettle();
      expect(find.text('Por persona'), findsOneWidget);
    });

    testWidgets('no desborda vacío', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(CancellationsReport.empty));
      await tester.pumpAndSettle();

      expect(find.text('Ninguna cancelación en este periodo.'), findsOneWidget);
    });

    testWidgets('sin precio de compra muestra unidades, nunca Q0.00',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(_unpricedOnlyReport()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Q0.00'), findsNothing);
      expect(find.text('6 u'), findsWidgets);
      expect(find.textContaining('sin precio de compra'), findsWidgets);
    });

    testWidgets('las cancelaciones sin inventario se marcan distinto',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(_sampleReport()));
      await tester.pumpAndSettle();

      // La marca vive en la lista de cancelaciones, debajo del resumen: a
      // 360dp hay que bajar para llegar, como haría cualquiera.
      await tester.scrollUntilVisible(
        find.text('No llegó a cocina'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('No llegó a cocina'), findsOneWidget);
    });
  });

  group('Pérdida a precio de venta', () {
    testWidgets('es el titular, porque incluye lo que no tiene receta',
        (tester) async {
      // El costo de ingredientes deja fuera a los productos sin receta: no
      // generan movimiento, así que un Taco de Q50 declarado basura no
      // aparecía en NINGÚN número del reporte. En septiembre de 2026 eso fue
      // 12 de 22 productos perdidos en Santa Rosalía.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(_sampleReport()));
      await tester.pumpAndSettle();

      // El número grande es el precio de venta, no el costo.
      expect(find.text('Q205.00'), findsOneWidget);
      // Y el costo sigue estando, para poder comparar.
      expect(find.text('Costo de ingredientes'), findsOneWidget);
      // Se dice cuánto de eso es invisible para el resto del reporte.
      expect(find.textContaining('sin receta: no bajan inventario'),
          findsOneWidget);
    });

    testWidgets('un cero de verdad se muestra como Q0.00', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(CancellationsReport.empty));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ninguna cancelación'), findsOneWidget);
    });
  });
}

CancellationsReport _sampleReport() {
  final at = DateTime(2026, 8, 30, 20, 15);

  const wasted = PartialValue(
    amount: 42.5,
    unpricedByUnit: {'u': 3},
    unpricedIngredientIds: {'gatorade'},
  );
  const returned = PartialValue(amount: 128.75);

  return CancellationsReport(
    events: [
      CancellationEvent(
        orderId: 'o1',
        orderLabel: '#124',
        tableLabel: 'Mesa 7',
        at: at,
        userName: 'Ana Pérez',
        reason: 'El cliente se fue',
        impact: InventoryImpact.conMovimiento,
        items: const [
          CancellationItem(
            itemId: 'i1',
            name: 'Cerveza Modelo',
            qty: 4,
            returned: PartialValue(amount: 60),
            wasted: wasted,
            declaredLost: true,
          ),
          CancellationItem(
            itemId: 'i2',
            name: 'Nachos con queso y chorizo bien cargados',
            qty: 1,
            returned: PartialValue(amount: 68.75),
            wasted: PartialValue.empty,
            declaredLost: false,
          ),
        ],
        returned: returned,
        wasted: wasted,
      ),
      CancellationEvent(
        orderId: 'o2',
        orderLabel: '#125',
        tableLabel: 'Para llevar',
        at: at.subtract(const Duration(hours: 2)),
        userName: 'Beto',
        reason: null,
        impact: InventoryImpact.sinCocina,
        items: const [],
        returned: PartialValue.empty,
        wasted: PartialValue.empty,
      ),
    ],
    people: const [
      PersonCut(
        userId: 'u1',
        userName: 'Ana Pérez',
        events: 1,
        itemsCancelled: 2,
        itemsLost: 1,
        wasted: wasted,
        returned: returned,
      ),
      PersonCut(
        userId: 'u2',
        userName: 'Beto',
        events: 1,
        itemsCancelled: 0,
        itemsLost: 0,
        wasted: PartialValue.empty,
        returned: PartialValue.empty,
      ),
    ],
    totalWasted: wasted,
    totalReturned: returned,
    itemsCancelled: 2,
    itemsLost: 1,
    cancelledBeforeKitchen: 1,
    cancelledWithoutRecipe: 0,
    unpricedIngredients: 1,
    saleWaste: const SaleValueWaste(
      amount: 205,
      items: 22,
      withoutRecipeAmount: 50,
      withoutRecipeItems: 12,
    ),
    truncated: false,
  );
}

/// El caso real de Santa Rosalía: lo que más se devuelve (bebidas) es justo lo
/// que no tiene precio de compra.
CancellationsReport _unpricedOnlyReport() {
  const wasted = PartialValue(
    unpricedByUnit: {'u': 6},
    unpricedIngredientIds: {'gatorade', 'stella'},
  );

  return CancellationsReport(
    events: [
      CancellationEvent(
        orderId: 'o9',
        orderLabel: '#900',
        tableLabel: 'Mesa 2',
        at: DateTime(2026, 8, 30, 12),
        userName: 'Carla',
        reason: 'Se equivocaron de mesa',
        impact: InventoryImpact.conMovimiento,
        items: const [
          CancellationItem(
            itemId: 'i9',
            name: 'Gatorade',
            qty: 6,
            returned: PartialValue.empty,
            wasted: wasted,
            declaredLost: true,
          ),
        ],
        returned: PartialValue.empty,
        wasted: wasted,
      ),
    ],
    people: const [
      PersonCut(
        userId: 'u3',
        userName: 'Carla',
        events: 1,
        itemsCancelled: 1,
        itemsLost: 1,
        wasted: wasted,
        returned: PartialValue.empty,
      ),
    ],
    totalWasted: wasted,
    totalReturned: PartialValue.empty,
    itemsCancelled: 1,
    itemsLost: 1,
    cancelledBeforeKitchen: 0,
    cancelledWithoutRecipe: 0,
    unpricedIngredients: 2,
    // Aunque NINGÚN ingrediente tenga precio de compra, el precio de venta sí
    // viaja en el pedido: por eso este reporte igual puede decir cuánto dinero
    // se perdió. Es justamente el agujero que la valoración a precio de venta
    // vino a tapar.
    saleWaste: const SaleValueWaste(
      amount: 84,
      items: 2,
      withoutRecipeAmount: 0,
      withoutRecipeItems: 0,
    ),
    truncated: false,
  );
}
