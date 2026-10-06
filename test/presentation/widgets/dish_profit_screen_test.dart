import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/formato_dinero.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/presentation/screens/reports/dish_profit_screen.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_table.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_widgets.dart';

import '../../helpers/menu_de_prueba.dart';
import '../../helpers/texto_completo.dart';

/// "Ver todos": la tabla de Utilidad por platillo, en teléfono y en pantalla
/// ancha.

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

Finder get desplazamientoHorizontal => find.descendant(
    of: find.byType(TablaUtilidad),
    matching: find.byType(SingleChildScrollView));

Future<void> tocarFiltro(WidgetTester tester, String prefijo) async {
  final chip = find.textContaining(prefijo);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Productos en el orden vertical en que se ven.
List<String> productosEnPantalla(WidgetTester tester, List<String> posibles) {
  final con = <(double, String)>[];
  for (final p in posibles) {
    for (final e in find.text(p).evaluate()) {
      final box = e.renderObject! as RenderBox;
      con.add((box.localToGlobal(Offset.zero).dy, p));
    }
  }
  con.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final c in con) c.$2];
}

void main() {
  late VistaUtilidadPlatillos vista;
  setUp(() => vista = VistaUtilidadPlatillos());
  tearDown(() => vista.dispose());

  for (final escala in [1.0, 1.5, 2.0]) {
    testWidgets('teléfono de 360dp con letra al ${(escala * 100).round()}%: '
        'nada se desborda, ningún monto se corta y todo se lee',
        (tester) async {
      await pintarEnTelefono(tester, lista(vista),
          escala: escala, alto: 1600);
      expect(tester.takeException(), isNull);
      expectCifrasCompletas(tester);
      expectContrasteDeCifras(tester,
          fondo: const Color(0xFF243247), // la fila más clara de la cebra
          excepto: find.byType(ChipFiltro));
    });
  }

  testWidgets('en el teléfono más angosto (320dp) tampoco', (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 320, alto: 1600);
    expect(tester.takeException(), isNull);
    expectCifrasCompletas(tester);
  });

  testWidgets('en teléfono la presentación va debajo del producto y Ganancia '
      'va primero, a la vista sin deslizar', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    expect(find.text('Presentación'), findsNothing);
    expect(find.text('Familiar de doce porciones'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Ganancia')).dx,
        lessThan(tester.getTopLeft(find.text('Costo')).dx));
    expect(tester.getTopRight(find.text('Ganancia')).dx, lessThan(360),
        reason: 'Ganancia se ve sin deslizar');
  });

  testWidgets('en pantalla ancha las columnas siguen la cuenta: costo, gasto, '
      'precio, ganancia', (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1000);
    final x = [
      for (final t in ['Costo', 'Gasto', 'Precio', 'Ganancia', '%'])
        tester.getTopLeft(find.text(t)).dx
    ];
    expect(x, [...x]..sort());
  });

  testWidgets('en pantalla ancha cada cosa tiene su columna y nada se '
      'desliza', (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1000);
    expect(tester.takeException(), isNull);
    expect(find.text('Presentación'), findsOneWidget);
    expect(desplazamientoHorizontal, findsNothing);
    expectCifrasCompletas(tester);
  });

  testWidgets('al deslizar de lado, la columna Producto se queda quieta',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    expect(desplazamientoHorizontal, findsOneWidget,
        reason: 'en 360dp las columnas no caben y la tabla se desliza');

    final productoAntes = tester.getTopLeft(find.text('Producto'));
    final gananciaAntes = tester.getTopLeft(find.text('Ganancia'));
    await tester.drag(desplazamientoHorizontal, const Offset(-250, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Producto')).dx,
        moreOrLessEquals(productoAntes.dx, epsilon: 1));
    expect(tester.getTopLeft(find.text('Ganancia')).dx,
        lessThan(gananciaAntes.dx - 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar un encabezado ordena por esa columna; otra vez, al revés',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1400);
    const productos = ['Refresco en Lata', 'Licuado de Fresa', 'Café Americano'];

    await tester.tap(find.text('Precio'));
    await tester.pumpAndSettle();
    expect(vista.columna, ColumnaOrden.precio);
    expect(vista.ascendente, isTrue);
    // Q15, Q22, Q25: de menor a mayor.
    expect(productosEnPantalla(tester, productos), productos);

    await tester.tap(find.text('Precio'));
    await tester.pumpAndSettle();
    expect(vista.ascendente, isFalse);
    expect(
        productosEnPantalla(tester, productos), productos.reversed.toList());
  });

  test('ordenado por %, las cifras se ven en orden y lo que dice "Revisar" va '
      'después', () {
    final v = VistaUtilidadPlatillos();
    final filas = filasVisibles(utilidadDificil(), v);
    final conCifra = filas
        .where((f) => celdasDe(f).pct != '—')
        .map((f) => f.pct!)
        .toList();
    expect(conCifra, [...conCifra]..sort());
    final primeraSinCifra = filas.indexWhere((f) => celdasDe(f).pct == '—');
    expect(
        filas.skip(primeraSinCifra).every((f) => celdasDe(f).pct == '—'), isTrue);
    v.dispose();
  });

  test('el orden por defecto pone primero al que más pierde y abajo lo mal '
      'cargado', () {
    final v = VistaUtilidadPlatillos();
    final orden = filasVisibles(utilidadDificil(), v)
        .map((f) => f.platillo.producto)
        .toList();
    expect(orden.first, 'Sopa del Día');
    expect(orden.indexOf('Filete de Pechuga a la Barbacoa'),
        greaterThan(orden.indexOf('Hamburguesa Clásica')));
    expect(orden.last, 'Refresco en Lata');
    v.dispose();
  });

  test('ordenar por producto es alfabético, sin grupos', () {
    final v = VistaUtilidadPlatillos()..ordenarPor(ColumnaOrden.producto);
    final orden = filasVisibles(utilidadDificil(), v)
        .map((f) => f.platillo.nombre.toLowerCase())
        .toList();
    expect(orden, [...orden]..sort());
    v.dispose();
  });

  testWidgets('con reparto: los filtros hablan de gastos', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    expect(find.text('Con utilidad 5'), findsOneWidget);
    expect(find.text('Pierden 1'), findsOneWidget);
    expect(find.text('No cubren fijos 1'), findsOneWidget);
    expect(find.text('Falta costo 1'), findsOneWidget);
  });

  testWidgets('sin reparto: Gasto vacío, la línea dice por qué y "Con costo"',
      (tester) async {
    final sinReparto = UtilidadMenu.armar(calcularMargenes(menuDificil()),
        reparto: RepartoGastos(
          ventasNetas: 1000,
          gastosFijos: 100,
          gastosVariables: 100,
          estado: EstadoReparto.periodoCorto,
        ));
    await pintarEnTelefono(tester, lista(vista, datos: sinReparto),
        ancho: 1280, alto: 1400);
    expect(find.text('Con costo 7'), findsOneWidget);
    expect(find.textContaining('Pierden'), findsNothing);
    expect(find.text('Gasto vacío: elegí Mes o Año en la fecha'),
        findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  test('el costo mal cargado dice "Revisar" en la ganancia, no una cifra '
      'absurda', () {
    final filas = {for (final f in utilidadDificil().filas) f.platillo.producto: f};
    expect(celdasDe(filas['Filete de Pechuga a la Barbacoa']!).ganancia,
        'Revisar');
    expect(celdasDe(filas['Café Americano']!).ganancia, 'Revisar');
  });

  test('Gasto muestra lo repartido con reparto y "—" sin él', () {
    final con = utilidadDificil()
        .filas
        .firstWhere((f) => f.platillo.producto == 'Hamburguesa Clásica');
    final d = con.desglose!;
    expect(CeldasFila.de(con).gasto,
        formatoDinero(d.descuento + d.variables + d.fijos));
    final sin = utilidadDificil(conReparto: false)
        .filas
        .firstWhere((f) => f.platillo.producto == 'Hamburguesa Clásica');
    expect(CeldasFila.de(sin).gasto, '—');
  });

  test('el ancho de una columna se mide con el monto y con los textos', () {
    // "Sin receta" tiene más letras que "Q1,250.00", pero con Inter el monto
    // es más ancho: elegir por letras lo cortaba.
    final c = candidatosParaMedir(
        ['Q12.00', 'Sin receta', 'Q1,250.00', '−Q8.00', 'Falta', 'Q1,250.00']);
    expect(c, containsAll(['Q1,250.00', 'Sin receta', 'Falta', '−Q8.00']));
    expect(c, isNot(contains('Q12.00')));
  });

  test('la línea de resumen dice algo en cada estado, y los avisos graves la '
      'ponen ámbar', () {
    for (final e in EstadoReparto.values) {
      final r = resumenCorto(RepartoGastos(
          ventasNetas: 1000,
          gastosFijos: 100,
          gastosVariables: 100,
          estado: e));
      expect(r, isNotNull, reason: '$e');
      expect(r!.texto, isNotEmpty);
    }
    final aMedias = resumenCorto(const RepartoGastos(
        ventasNetas: 1000,
        gastosFijos: 100,
        gastosVariables: 100,
        estado: EstadoReparto.listo,
        mesEnCurso: true))!;
    expect(aMedias.texto, contains('el mes va a medias'));
    expect(aMedias.color, kAmbar);
  });

  testWidgets('la única línea sobre la tabla resume los gastos y abre la guía',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    expect(find.text('De cada Q100 que cobrás, Q38 se van en gastos'),
        findsOneWidget);
    // Lo demás ya no está a la vista: vive en la guía.
    expect(
        find.textContaining('Sin contar Q9,000.00 de insumos'), findsNothing);

    await tester.tap(find.text('Ver más'));
    await tester.pumpAndSettle();
    expect(find.text('QUÉ DICE CADA COLUMNA'), findsOneWidget);
    expect(find.textContaining('Sin contar Q9,000.00 de insumos'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el ícono de idea junto al buscador abre la guía',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    await tester.tap(find.byTooltip('Cómo leer la tabla y consejos'));
    await tester.pumpAndSettle();
    expect(find.text('QUÉ DICE CADA COLOR'), findsOneWidget);
    expect(find.textContaining('no lo quités por esto'), findsOneWidget);
  });

  testWidgets('la guía se lee a 360dp con letra al 200%', (tester) async {
    await pintarEnTelefono(tester, lista(vista), escala: 2.0, alto: 1600);
    await tester.tap(find.byTooltip('Cómo leer la tabla y consejos'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar un platillo abre su desglose y consejos', (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1400);
    await tester.tap(find.text('Hamburguesa Clásica'));
    await tester.pumpAndSettle();
    expect(find.text('Precio de venta (con IVA)'), findsOneWidget);
    expect(find.text('Te queda, antes de impuestos'), findsOneWidget);
    expect(find.textContaining('Gastos fijos (25.0% de lo cobrado)'),
        findsOneWidget);
  });

  testWidgets('la idea de una fila abre lo mismo, y en el ámbar dice que no lo '
      'quite', (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1400);
    // La fila completa (la celda fija tiene su propio InkWell).
    final fila = find.ancestor(
        of: find.text('Licuado de Fresa'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_FilaDatos'));
    await tester.tap(find.descendant(
        of: fila, matching: find.byTooltip('Ver desglose y consejos')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No lo quités por esto'), findsOneWidget);
    expect(find.textContaining('Cubriría todos sus gastos desde'),
        findsOneWidget);
  });

  testWidgets('el detalle se lee a 360dp con letra al 200%', (tester) async {
    await pintarEnTelefono(tester, lista(vista), escala: 2.0, alto: 1600);
    await tester.tap(find.text('Hamburguesa Clásica'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectCifrasCompletas(tester);
  });

  testWidgets('en iOS el rebote no recorta la columna fija', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pintarEnTelefono(tester, lista(vista));
      final antes = tester.getTopLeft(find.text('Producto')).dx;
      // Deslizar a la derecha estando al inicio: rebota.
      final gesto = await tester.startGesture(
          tester.getCenter(find.text('Ganancia')));
      // Un gesto real, en varios pasos: de un solo salto apenas arranca.
      for (var i = 0; i < 6; i++) {
        await gesto.moveBy(const Offset(25, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getTopLeft(find.text('Producto')).dx,
          greaterThanOrEqualTo(antes - 0.5),
          reason: 'la celda fija no puede quedar a la izquierda de su lugar');
      // Durante el rebote el desplazamiento es negativo. Si la celda fija se
      // corriera con él, quedaría fuera del borde de su fila y se recortaría,
      // dejando una franja vacía.
      final fijas = tester
          .widgetList<Positioned>(find.descendant(
              of: find.byType(TablaUtilidad), matching: find.byType(Positioned)))
          .where((p) => p.left != null);
      expect(fijas, isNotEmpty);
      for (final p in fijas) {
        expect(p.left, greaterThanOrEqualTo(0));
      }
      await gesto.up();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('deslizar hacia abajo actualiza', (tester) async {
    var veces = 0;
    await pintarEnTelefono(
      tester,
      UtilidadPlatillosView(
        datos: utilidadDificil(),
        vista: vista,
        periodo: 'Octubre 2026',
        onRefresh: () async => veces++,
      ),
    );
    final inicio =
        tester.getTopLeft(find.byType(TablaUtilidad)) + const Offset(60, 80);
    await tester.flingFrom(inicio, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(veces, 1);
  });

  testWidgets('el lector de pantalla lee el platillo y cada cifra con su '
      'columna', (tester) async {
    final semantica = tester.ensureSemantics();
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1000);
    expect(
        find.bySemanticsLabel(RegExp(r'^Hamburguesa Clásica\. Costo Q15\.00\. '
            r'Gasto Q.*\. Precio Q50\.00\. Ganancia Q.*cubre sus gastos$')),
        findsOneWidget);
    expect(find.bySemanticsLabel('Ordenar por Precio'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('al cambiar de sucursal la tabla recuerda cuánto se deslizó',
      (tester) async {
    var sucursal = 'A';
    late StateSetter cambiar;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, set) {
          cambiar = set;
          return lista(vista, sucursal: sucursal);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(desplazamientoHorizontal, const Offset(-200, 0));
    await tester.pumpAndSettle();
    final antes = tester.getTopLeft(find.text('Precio')).dx;

    cambiar(() => sucursal = 'B');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Precio')).dx,
        moreOrLessEquals(antes, epsilon: 1));
  });

  testWidgets('los chips y las ideas de cada fila se tocan con el dedo (44+)',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    for (final e in find.byType(ChipFiltro).evaluate()) {
      expect(e.size!.height, greaterThanOrEqualTo(44));
    }
    final guia = tester.getSize(find.byTooltip('Cómo leer la tabla y consejos'));
    expect(guia.height, greaterThanOrEqualTo(44));
    // El encabezado también se toca para ordenar.
    final titulo = find.ancestor(
        of: find.text('Precio'), matching: find.byType(InkWell));
    expect(tester.getSize(titulo.first).height, greaterThanOrEqualTo(44));
    final ideas = find.byTooltip('Ver desglose y consejos').evaluate();
    expect(ideas, isNotEmpty);
    for (final e in ideas) {
      expect(e.size!.height, greaterThanOrEqualTo(44));
      expect(e.size!.width, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('cambiar de sucursal conserva búsqueda, filtro y orden',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista, sucursal: 'A'));
    await tocarFiltro(tester, 'Con utilidad');
    await tester.enterText(find.byType(TextField), 'hamburguesa');
    vista.ordenarPor(ColumnaOrden.precio);
    await tester.pumpAndSettle();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: lista(vista, sucursal: 'B')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('hamburguesa'), findsOneWidget, reason: 'la búsqueda');
    expect(vista.filtro, FiltroPlatillos.conUtilidad);
    expect(vista.columna, ColumnaOrden.precio);
    expect(find.text('Hamburguesa Clásica'), findsOneWidget);
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
    expect(find.byType(TablaUtilidad), findsOneWidget);
  });

  testWidgets('la búsqueda encuentra por cualquier parte del nombre',
      (tester) async {
    await pintarEnTelefono(tester, lista(vista), ancho: 1280, alto: 1000);
    await tester.enterText(find.byType(TextField), '  DOCE ');
    await tester.pumpAndSettle();
    expect(find.text('Familiar de doce porciones'), findsOneWidget);
    expect(find.text('Hamburguesa Clásica'), findsNothing);
  });

  testWidgets('arrastrar la tabla esconde el teclado', (tester) async {
    await pintarEnTelefono(tester, lista(vista));
    await tester.showKeyboard(find.byType(TextField));
    expect(tester.testTextInput.isVisible, isTrue);
    // Sobre una fila visible: la tabla es más ancha que la pantalla y su
    // centro queda fuera.
    final inicio =
        tester.getTopLeft(find.byType(TablaUtilidad)) + const Offset(60, 120);
    await tester.dragFrom(inicio, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
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

  test('las celdas: "Falta", "Sin receta", y la idea se enciende donde hay '
      'algo que revisar', () {
    final filas = {for (final f in utilidadDificil().filas) f.platillo.nombre: f};
    final pizza = CeldasFila.de(filas[
        'Pizza Familiar Especial de la Casa con Todos los Ingredientes · '
            'Mediana de ocho porciones']!);
    expect(pizza.costo, 'Falta');
    expect(pizza.conConsejo, isTrue);

    final refresco = CeldasFila.de(filas['Refresco en Lata']!);
    expect(refresco.costo, 'Sin receta');
    expect(refresco.ganancia, '—');

    expect(CeldasFila.de(filas['Hamburguesa Clásica']!).conConsejo, isFalse);
    expect(CeldasFila.de(filas['Sopa del Día']!).grave, isTrue,
        reason: 'pierde en cada venta');
  });
}
