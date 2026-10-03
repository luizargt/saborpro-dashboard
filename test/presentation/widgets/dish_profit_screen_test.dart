import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/presentation/screens/reports/dish_profit_screen.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_widgets.dart';

import '../../helpers/menu_de_prueba.dart';
import '../../helpers/texto_completo.dart';

/// "Ver todos": la lista completa de Utilidad por platillo, a 360dp.

Widget lista(
  VistaUtilidadPlatillos vista, {
  UtilidadMenu? datos,
  String sucursal = 'A',
}) =>
    UtilidadPlatillosView(
      datos: datos ?? utilidadDificil(),
      vista: vista,
      periodo: 'Octubre 2026',
      // Lo mismo que hace LocationContentSwitcher al cambiar de sucursal:
      // re-crea todo lo que envuelve.
      envolverLista: (l) => KeyedSubtree(key: ValueKey(sucursal), child: l),
    );

Future<void> verFila(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
      f,
      150,
      scrollable: find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable)),
    );

Future<void> tocarFiltro(WidgetTester tester, String prefijo) async {
  final chip = find.textContaining(prefijo);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  late VistaUtilidadPlatillos vista;
  setUp(() => vista = VistaUtilidadPlatillos());
  tearDown(() => vista.dispose());

  for (final escala in [1.0, 1.5, 2.0]) {
    testWidgets('a 360dp con letra al ${(escala * 100).round()}%: nada se '
        'desborda ni se corta, y todo se lee', (tester) async {
      await pintarEnTelefono(tester, lista(vista),
          escala: escala, alto: 2400);
      expect(tester.takeException(), isNull);
      expectCifrasCompletas(tester);
      expectContrasteDeCifras(tester,
          fondo: kTarjeta, excepto: find.byType(ChipFiltro));

      // Con el desglose abierto, también.
      await verFila(tester, find.text('Hamburguesa Clásica'));
      await tester.tap(find.text('Hamburguesa Clásica'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectCifrasCompletas(tester);
    });
  }

  testWidgets('los chips miden al menos 44 de alto', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    for (final e in find.byType(ChipFiltro).evaluate()) {
      expect(e.size!.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('con reparto: los filtros hablan de gastos', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    // Cubren: hamburguesa, pizza familiar, tacos, pastel y lomito. La sopa
    // pierde y el licuado no cubre su parte de los fijos: van separados.
    expect(find.text('Con utilidad 5'), findsOneWidget);
    expect(find.text('Pierden 1'), findsOneWidget);
    expect(find.text('No cubren fijos 1'), findsOneWidget);
    expect(find.text('Falta costo 1'), findsOneWidget);
    expect(find.textContaining('Con costo'), findsNothing);
  });

  testWidgets('sin reparto: "Con costo" en lugar de los de gastos',
      (tester) async {
    await pintarEnTelefono(
        tester, lista(vista, datos: utilidadDificil(conReparto: false)));
    expect(find.text('Con costo 7'), findsOneWidget);
    expect(find.textContaining('No cubren'), findsNothing);
    expect(find.textContaining('Pierden'), findsNothing);
  });

  testWidgets('el orden pone primero lo confiable y abajo lo mal cargado',
      (tester) async {
    final orden = filasVisibles(utilidadDificil(), vista)
        .map((f) => f.platillo.producto)
        .toList();
    // Primero la sopa (pierde), al final los incompletos y sin receta.
    expect(orden.first, 'Sopa del Día');
    expect(orden.indexOf('Filete de Pechuga a la Barbacoa'),
        greaterThan(orden.indexOf('Hamburguesa Clásica')));
    expect(orden.last, 'Refresco en Lata');
  });

  testWidgets('cambiar de sucursal conserva búsqueda, filtro, orden y la fila '
      'abierta', (tester) async {
    await pintarEnTelefono(tester, lista(vista, sucursal: 'A'));

    await tocarFiltro(tester, 'Con utilidad');
    await tester.enterText(find.byType(TextField), 'hamburguesa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hamburguesa Clásica'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Te queda'), findsOneWidget);

    // Otra sucursal: la lista se re-crea con datos nuevos.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: lista(vista, sucursal: 'B')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('hamburguesa'), findsOneWidget, reason: 'la búsqueda');
    expect(vista.filtro, FiltroPlatillos.conUtilidad);
    expect(find.textContaining('Te queda'), findsOneWidget,
        reason: 'la fila abierta');
  });

  testWidgets('una búsqueda sin resultados lo dice y ofrece limpiarla',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    await tester.enterText(find.byType(TextField), 'sushi');
    await tester.pumpAndSettle();
    expect(find.text('Ningún platillo coincide con "sushi"'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(vista.busqueda, isEmpty);
    expect(find.textContaining('Ningún platillo coincide'), findsNothing);
  });

  testWidgets('la búsqueda encuentra por cualquier parte del nombre',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    await tester.enterText(find.byType(TextField), '  DOCE ');
    await tester.pumpAndSettle();
    expect(find.text('Familiar de doce porciones'), findsOneWidget);
    expect(find.text('Hamburguesa Clásica'), findsNothing);
  });

  testWidgets('arrastrar la lista esconde el teclado', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    await tester.showKeyboard(find.byType(TextField));
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('el desglose suma: precio − todo = te queda', (tester) async {
    await pintarEnTelefono(tester, lista(vista), alto: 1600);
    await verFila(tester, find.text('Hamburguesa Clásica'));
    await tester.tap(find.text('Hamburguesa Clásica'));
    await tester.pumpAndSettle();
    final d = utilidadDificil()
        .filas
        .firstWhere((f) => f.platillo.producto == 'Hamburguesa Clásica')
        .desglose!;
    expect(find.text('Precio de venta (con IVA)'), findsOneWidget);
    expect(find.textContaining('Descuentos (promedio del negocio'),
        findsOneWidget);
    expect(find.textContaining('Gastos variables (13.0% de lo cobrado)'),
        findsOneWidget);
    expect(find.textContaining('Gastos fijos (25.0% de lo cobrado)'),
        findsOneWidget);
    expect(find.text('Te queda, antes de impuestos'), findsOneWidget);
    expect(d.descuento + d.costo + d.variables + d.fijos + d.utilidad,
        d.precio);
  });

  testWidgets('el desglose del ámbar dice que no lo quite', (tester) async {
    await pintarEnTelefono(tester, lista(vista), alto: 1600);
    await verFila(tester, find.text('Licuado de Fresa'));
    await tester.tap(find.text('Licuado de Fresa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No lo quités por esto'), findsOneWidget);
    expect(find.textContaining('Cubriría todos sus gastos desde'),
        findsOneWidget);
  });

  testWidgets('en "Ver todos" sí se aclara lo de insumos', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    expect(find.textContaining('Sin contar Q9,000.00 de insumos'),
        findsOneWidget);
  });

  testWidgets('la presentación larga se ve entera', (tester) async {
    await pintarEnTelefono(tester, lista(vista), alto: 2400);
    await verFila(tester, find.text('Familiar de doce porciones'));
    final t = tester.widget<Text>(find.text('Familiar de doce porciones'));
    expect(t.maxLines, isNull);
    expect(t.overflow, isNull);
  });

  testWidgets('sin menú y con error: el error, nunca "no hay platillos"',
      (tester) async {
    await pintarEnTelefono(
      tester,
      UtilidadPlatillosView(
        datos: null,
        error: 'Sin conexión con el servidor.',
        vista: vista,
        periodo: 'Octubre 2026',
      ),
    );
    expect(find.text('Sin conexión con el servidor.'), findsOneWidget);
    expect(find.textContaining('no hay platillos'), findsNothing);
  });
}
