import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/widgets/location_selector.dart';

/// La barra de sucursales del encabezado.
///
/// Reportado desde un iPhone con tres sucursales: "Santa Rosalía" salía partida
/// en dos líneas y montada sobre la pestaña de al lado, porque la fila repartía
/// el ancho entre todas a la fuerza. Con nombres que no caben, la barra tiene
/// que rodar en horizontal; apretujar no es una opción.
void main() {
  const cortas = [
    LocationTabItem(null, 'Todas'),
    LocationTabItem('a', 'Zona 1'),
  ];

  const largas = [
    LocationTabItem(null, 'Todas'),
    LocationTabItem('a', 'Chiquimula'),
    LocationTabItem('b', 'La Reforma'),
    LocationTabItem('c', 'Santa Rosalía'),
  ];

  /// Pinta la barra en un teléfono angosto real (360dp), con los 16px de
  /// padding que le pone LocationHeaderBar a cada lado.
  Future<String?> pintar(
    WidgetTester tester, {
    required List<LocationTabItem> items,
    String? selected,
    double ancho = 360,
  }) async {
    tester.view.physicalSize = Size(ancho, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? elegida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LocationTabsView(
              items: items,
              selectedId: selected,
              onSelected: (id) => elegida = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return elegida;
  }

  testWidgets('con nombres largos ningún nombre se parte en dos líneas',
      (tester) async {
    await pintar(tester, items: largas);

    expect(tester.takeException(), isNull);
    for (final item in largas) {
      final texto = tester.widget<Text>(find.text(item.label));
      expect(texto.maxLines, 1, reason: '${item.label} se puede partir');
      // Una línea de 16px no llega a 30 de alto ni con holgura: si esto crece,
      // es que el nombre volvió a apilarse.
      expect(tester.getSize(find.text(item.label)).height, lessThan(30),
          reason: '${item.label} ocupa más de una línea');
    }
  });

  testWidgets('si no caben, la barra rueda en horizontal', (tester) async {
    await pintar(tester, items: largas);

    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);

    // Y rueda de verdad: la última pestaña se alcanza arrastrando.
    final antes = tester.getTopLeft(find.text('Santa Rosalía')).dx;
    await tester.drag(scroll, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Santa Rosalía')).dx, lessThan(antes));
  });

  testWidgets('si caben, se reparten el ancho como siempre', (tester) async {
    await pintar(tester, items: cortas);

    expect(find.byType(SingleChildScrollView), findsNothing,
        reason: 'con dos nombres cortos no hace falta rodar');
    final a = tester.getSize(find.text('Todas')).width;
    final b = tester.getSize(find.text('Zona 1')).width;
    expect(a, greaterThan(0));
    expect(b, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la pestaña activa se ve aunque esté al final', (tester) async {
    // Entrar directo a la última sucursal no puede dejar la pestaña activa
    // fuera de la pantalla: el usuario no sabría en cuál está.
    await pintar(tester, items: largas, selected: 'c');

    final barra = tester.getRect(find.byType(LocationTabsView));
    final pestana = tester.getRect(find.text('Santa Rosalía'));
    expect(pestana.left, greaterThanOrEqualTo(barra.left - 1));
    expect(pestana.right, lessThanOrEqualTo(barra.right + 1));
  });

  testWidgets('tocar una pestaña avisa cuál se eligió', (tester) async {
    String? elegida;
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LocationTabsView(
              items: largas,
              selectedId: null,
              onSelected: (id) => elegida = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Con la fuente de reserva de los tests la pestaña queda fuera de lo
    // visible: se rueda hasta ella, que es justo lo que la barra permite ahora.
    await tester.ensureVisible(find.text('La Reforma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('La Reforma'));
    expect(elegida, 'b');
  });

  testWidgets('en tableta con espacio de sobra sigue sin rodar',
      (tester) async {
    await pintar(tester, items: largas, ancho: 900);

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
