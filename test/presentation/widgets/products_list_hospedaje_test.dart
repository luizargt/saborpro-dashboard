import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/dashboard_data.dart';
import 'package:saborpro_reports/data/models/hospedaje_inicio.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:saborpro_reports/presentation/widgets/products_list.dart';

/// "Platillos vendidos" en un hotel: los cargos de hospedaje tienen su propia
/// pestaña ("Hospedaje vendido"), en vez de caer en "Otros" bajo un título de
/// platillos.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  ProductSummary prod(String nombre, String categoria, int cant, double total) => ProductSummary(
        name: nombre,
        category: categoria,
        quantity: cant,
        total: total,
        prevQuantity: 0,
        prevTotal: 0,
      );

  Future<void> montar(WidgetTester tester, List<ProductSummary> productos, {Size size = const Size(1280, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: kInicioBg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ProductsList(products: productos, prevLabel: 'Ayer', totalSales: 5000),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('la clasificación del cargo de hospedaje es "Hospedaje" y su id el del POS', () {
    expect(kProductoHospedaje, 'hospedaje');
    expect(kClasificacionHospedaje, 'Hospedaje');
  });

  testWidgets('un hotel sin comida: "Hospedaje vendido" (una sola clasificación, sin pestañas) y nada de "platillos"', (tester) async {
    await montar(tester, [
      prod('Noche de Hospedaje', kClasificacionHospedaje, 12, 4260),
      prod('Hora de Hospedaje', kClasificacionHospedaje, 30, 3000),
    ]);
    expect(find.text('Hospedaje vendido'), findsOneWidget);
    expect(find.text('Hospedaje'), findsNothing); // con una sola clasificación no hay pestañas
    expect(find.text('Noche de Hospedaje'), findsOneWidget);
    expect(find.text('Total (2 conceptos)'), findsOneWidget);
    expect(find.textContaining('latillos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un hotel que vende de todo: la comida primero, el hospedaje después y "Otros" al final', (tester) async {
    await montar(tester, [
      prod('Hamburguesa', 'Comida', 8, 800),
      prod('Noche de Hospedaje', kClasificacionHospedaje, 12, 4260),
      prod('Llavero', 'Otros', 2, 40),
    ]);
    // La primera pestaña (la activa) es la de comida.
    expect(find.text('Platillos vendidos'), findsOneWidget);
    expect(find.text('Hamburguesa'), findsOneWidget);
    final x = [for (final p in ['Comidas', 'Hospedaje', 'Otros']) tester.getTopLeft(find.text(p)).dx];
    expect(x[0] < x[1] && x[1] < x[2], isTrue, reason: 'orden de las pestañas: $x');

    await tester.tap(find.text('Hospedaje'));
    await tester.pumpAndSettle();
    expect(find.text('Hospedaje vendido'), findsOneWidget);
    expect(find.text('Noche de Hospedaje'), findsOneWidget);
    expect(find.text('Hamburguesa'), findsNothing);
  });

  testWidgets('un restaurante sin hospedaje se ve igual que siempre', (tester) async {
    await montar(tester, [prod('Hamburguesa', 'Comida', 8, 800), prod('Cerveza', 'Bebidas', 20, 500)]);
    expect(find.text('Platillos vendidos'), findsOneWidget);
    expect(find.text('Comidas'), findsOneWidget);
    expect(find.text('Bebidas'), findsOneWidget);
    expect(find.text('Hospedaje'), findsNothing);
  });

  testWidgets('a 360 de ancho tampoco desborda con la pestaña de hospedaje', (tester) async {
    await montar(
      tester,
      [
        prod('Hamburguesa', 'Comida', 8, 800),
        prod('Noche de Hospedaje', kClasificacionHospedaje, 12, 4260),
        prod('Llavero', 'Otros', 2, 40),
      ],
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
  });
}
