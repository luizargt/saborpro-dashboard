import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/navigation/destinos.dart';
import 'package:saborpro_reports/presentation/widgets/paleta_de_comandos.dart';

/// La paleta de comandos (buscador de pantallas, Ctrl/⌘ K).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  /// Abre la paleta con un botón; devuelve lo que eligió cuando se cierre.
  Future<void> abrir(WidgetTester t, {Destino actual = Destino.inicio, double ancho = 1280, void Function(Destino?)? alElegir}) async {
    t.view.physicalSize = Size(ancho, 2600); // alto: la lista es perezosa y solo arma lo que se ve
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final d = await mostrarPaletaDeComandos(context, actual: actual);
                alElegir?.call(d);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester t, String q) async {
    await t.enterText(find.byKey(const Key('paleta-buscar')), q);
    await t.pump();
  }

  testWidgets('sin escribir, todo: agrupado y marcando dónde se está', (t) async {
    await abrir(t, actual: Destino.gastos);
    expect(find.text('IR A'), findsOneWidget);
    expect(find.text('REPORTES · DINERO'), findsOneWidget);
    expect(find.text('REPORTES · CONTROL'), findsOneWidget);
    expect(find.text('CUENTA'), findsOneWidget);
    expect(find.text('Estás aquí'), findsOneWidget);
    expect(find.text('Descargar reportes'), findsOneWidget);
    expect(find.text('Notificaciones'), findsOneWidget);
  });

  testWidgets('escribir filtra, sin importar tildes ni mayúsculas', (t) async {
    await abrir(t);
    await escribir(t, 'CORTESIA');
    expect(find.text('Cortesías y donaciones'), findsOneWidget);
    expect(find.text('Rentabilidad'), findsNothing);
    await escribir(t, 'cierres de CAJA');
    expect(find.text('Cierres de caja'), findsOneWidget);
    expect(find.text('Cortesías y donaciones'), findsNothing);
  });

  testWidgets('lo que no existe lo dice', (t) async {
    await abrir(t);
    await escribir(t, 'zzz');
    expect(find.text('No encontramos "zzz"'), findsOneWidget);
  });

  testWidgets('tocar un resultado lo devuelve y cierra', (t) async {
    Destino? elegido;
    var cerro = false;
    await abrir(t, alElegir: (d) {
      elegido = d;
      cerro = true;
    });
    await t.tap(find.text('Propinas'));
    await t.pumpAndSettle();
    expect(cerro, isTrue);
    expect(elegido, Destino.propinas);
    expect(find.byKey(const Key('paleta-buscar')), findsNothing);
  });

  testWidgets('Enter abre el primero; las flechas mueven la selección', (t) async {
    Destino? elegido;
    await abrir(t, alElegir: (d) => elegido = d);
    await escribir(t, 'a'); // coincide con varios
    final todos = Destinos.buscar('a');
    expect(todos.length, greaterThan(2));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.testTextInput.receiveAction(TextInputAction.go);
    await t.pumpAndSettle();
    expect(elegido, todos[2]);
  });

  testWidgets('la flecha de arriba da la vuelta al final', (t) async {
    Destino? elegido;
    await abrir(t, alElegir: (d) => elegido = d);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    await t.testTextInput.receiveAction(TextInputAction.go);
    await t.pumpAndSettle();
    expect(elegido, Destinos.buscar('').last);
  });

  testWidgets('Esc cierra sin elegir', (t) async {
    Destino? elegido = Destino.inicio;
    var cerro = false;
    await abrir(t, alElegir: (d) {
      elegido = d;
      cerro = true;
    });
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(cerro, isTrue);
    expect(elegido, isNull);
  });

  testWidgets('en el teléfono no hay pista de teclado', (t) async {
    await abrir(t, ancho: 360);
    expect(find.text('Esc'), findsNothing);
    expect(find.text('Flechas para moverte'), findsNothing);
  });

  testWidgets('en pantalla ancha sí', (t) async {
    await abrir(t);
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('Enter abrir'), findsOneWidget);
  });

  for (final ancho in [320.0, 360.0, 800.0]) {
    testWidgets('cabe a $ancho', (t) async {
      await abrir(t, ancho: ancho);
      await escribir(t, 'c');
      expect(t.takeException(), isNull);
    });
  }
}
