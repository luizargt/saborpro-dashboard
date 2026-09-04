import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El diálogo "¿A qué restaurante querés entrar?" solo aparece cuando un mismo
/// correo existe en varios restaurantes, así que en el día a día es invisible
/// y nadie se entera de que está roto hasta que le toca a un admin con muchos.
///
/// Se reproduce su forma (AlertDialog + content acotado) en vez de montar
/// LoginScreen, que arrastra Firebase. Lo que se prueba es la decisión de
/// diseño: sin SingleChildScrollView la lista queda cortada y sin salida.
Widget _dialogo({required int restaurantes, required bool conScroll}) {
  final filas = Column(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      restaurantes,
      (i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text('Restaurante $i'),
      ),
    ),
  );

  return MaterialApp(
    home: Scaffold(
      body: AlertDialog(
        title: const Text('¿A qué restaurante querés entrar?'),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        content: SizedBox(
          width: double.maxFinite,
          child: conScroll ? SingleChildScrollView(child: filas) : filas,
        ),
        actions: [TextButton(onPressed: () {}, child: const Text('Cancelar'))],
      ),
    ),
  );
}

void main() {
  testWidgets('con muchos restaurantes la lista se puede desplazar',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_dialogo(restaurantes: 12, conScroll: true));
    await tester.pumpAndSettle();

    // Hay algo desplazable: es lo que le da salida al que quedó abajo.
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);

    // Y de verdad se puede llegar al último.
    await tester.scrollUntilVisible(
      find.text('Restaurante 11'),
      120,
      scrollable: find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Restaurante 11'), findsOneWidget);
  });

  testWidgets('sin scroll, la misma lista desborda — el bug que se arregló',
      (tester) async {
    // Candado invertido: si alguien quita el SingleChildScrollView, este test
    // deja de reflejar la realidad y hay que mirar por qué.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_dialogo(restaurantes: 12, conScroll: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNotNull,
        reason: 'sin scroll una lista larga tiene que desbordar');
  });

  testWidgets('con dos restaurantes se ve entero y sin desbordar',
      (tester) async {
    // El caso común no debe cambiar de aspecto por el arreglo.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_dialogo(restaurantes: 2, conScroll: true));
    await tester.pumpAndSettle();

    expect(find.text('Restaurante 0'), findsOneWidget);
    expect(find.text('Restaurante 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
