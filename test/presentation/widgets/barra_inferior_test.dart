import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/navigation/destinos.dart';
import 'package:saborpro_reports/presentation/widgets/barra_inferior.dart';

/// La navegación del teléfono: la barra de abajo y la hoja de Reportes.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  Future<void> montar(WidgetTester t, Widget w, {double ancho = 360, double escala = 1}) async {
    t.view.physicalSize = Size(ancho, 760);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(ancho, 760), textScaler: TextScaler.linear(escala)),
        child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: w)),
      ),
    ));
  }

  group('qué pestaña se enciende', () {
    test('cada lugar enciende la suya', () {
      expect(pestanaDe(Destino.inicio), PestanaMovil.inicio);
      expect(pestanaDe(Destino.despensa), PestanaMovil.despensa);
      expect(pestanaDe(Destino.avisos), PestanaMovil.avisos);
    });

    test('todos los reportes encienden Reportes', () {
      for (final d in Destinos.deSeccion(SeccionNav.dinero) + Destinos.deSeccion(SeccionNav.control)) {
        expect(pestanaDe(d), PestanaMovil.reportes, reason: d.name);
      }
    });

    test('las notificaciones son cosa de la cuenta: encienden Más', () {
      expect(pestanaDe(Destino.notificaciones), PestanaMovil.mas);
      expect(pestanaDe(Destino.descargas), PestanaMovil.mas);
    });
  });

  group('barra de abajo', () {
    testWidgets('cinco pestañas y la actual marcada', (t) async {
      await montar(t, BarraInferiorMovil(actual: PestanaMovil.reportes, avisosSinLeer: 0, onElegir: (_) {}));
      for (final n in ['Inicio', 'Despensa', 'Reportes', 'Avisos', 'Más']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      bool marcada(String n) => t.widget<Semantics>(find.ancestor(of: find.text(n), matching: find.byType(Semantics)).first).properties.selected ?? false;
      expect(marcada('Reportes'), isTrue);
      expect(marcada('Inicio'), isFalse);
    });

    testWidgets('el orden es Inicio, Despensa, Reportes, Avisos y Más (de izquierda a derecha)', (t) async {
      await montar(t, BarraInferiorMovil(actual: PestanaMovil.inicio, avisosSinLeer: 0, onElegir: (_) {}));
      final nombres = ['Inicio', 'Despensa', 'Reportes', 'Avisos', 'Más'];
      final x = [for (final n in nombres) t.getTopLeft(find.text(n)).dx];
      for (var i = 1; i < x.length; i++) {
        expect(x[i], greaterThan(x[i - 1]), reason: '${nombres[i]} va después de ${nombres[i - 1]}');
      }
      // Y el orden del enum es el mismo (de él sale el dibujo).
      expect(PestanaMovil.values, [PestanaMovil.inicio, PestanaMovil.despensa, PestanaMovil.reportes, PestanaMovil.avisos, PestanaMovil.mas]);
    });

    testWidgets('tocar una pestaña avisa cuál', (t) async {
      final tocadas = <PestanaMovil>[];
      await montar(t, BarraInferiorMovil(actual: PestanaMovil.inicio, avisosSinLeer: 0, onElegir: tocadas.add));
      await t.tap(find.text('Despensa'));
      await t.tap(find.text('Más'));
      expect(tocadas, [PestanaMovil.despensa, PestanaMovil.mas]);
    });

    testWidgets('el contador de Avisos', (t) async {
      await montar(t, BarraInferiorMovil(actual: PestanaMovil.inicio, avisosSinLeer: 7, onElegir: (_) {}));
      expect(find.text('7'), findsOneWidget);
      await montar(t, BarraInferiorMovil(actual: PestanaMovil.inicio, avisosSinLeer: 250, onElegir: (_) {}));
      expect(find.text('99+'), findsOneWidget);
      await montar(t, BarraInferiorMovil(actual: PestanaMovil.inicio, avisosSinLeer: 0, onElegir: (_) {}));
      expect(find.text('0'), findsNothing);
    });

    for (final ancho in [320.0, 360.0, 390.0]) {
      testWidgets('cabe a $ancho con letra grande', (t) async {
        await montar(t, BarraInferiorMovil(actual: PestanaMovil.avisos, avisosSinLeer: 120, onElegir: (_) {}), ancho: ancho, escala: 1.4);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('hoja de Reportes', () {
    testWidgets('los reportes en sus dos grupos, con su descripción', (t) async {
      await montar(t, HojaReportes(actual: Destino.inicio, datos: const {}, alertas: const {}, onElegir: (_) {}));
      expect(find.text('Reportes'), findsOneWidget);
      expect(find.text('DINERO'), findsOneWidget);
      expect(find.text('CONTROL Y PÉRDIDAS'), findsOneWidget);
      for (final d in Destinos.deSeccion(SeccionNav.dinero) + Destinos.deSeccion(SeccionNav.control)) {
        expect(find.text(Destinos.nombre(d)), findsOneWidget, reason: d.name);
        expect(find.text(Destinos.descripcion(d)), findsOneWidget, reason: d.name);
      }
      // Lo que no es un reporte no está.
      expect(find.text('Inicio'), findsNothing);
      expect(find.text('Despensa'), findsNothing);
    });

    testWidgets('el dato de hoy reemplaza a la descripción', (t) async {
      await montar(t, HojaReportes(actual: Destino.inicio, datos: const {Destino.gastos: 'Q842 hoy'}, alertas: const {Destino.gastos}, onElegir: (_) {}));
      expect(find.text('Q842 hoy'), findsOneWidget);
      expect(find.text(Destinos.descripcion(Destino.gastos)), findsNothing);
    });

    testWidgets('tocar un reporte avisa cuál', (t) async {
      Destino? tocado;
      await montar(t, HojaReportes(actual: Destino.inicio, datos: const {}, alertas: const {}, onElegir: (d) => tocado = d));
      await t.tap(find.text('Propinas'));
      expect(tocado, Destino.propinas);
    });

    testWidgets('mostrarHojaManager la abre desde abajo y se cierra', (t) async {
      t.view.physicalSize = const Size(360, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Destino? tocado;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => mostrarHojaManager<void>(
                  context,
                  builder: (ctx) => HojaReportes(actual: Destino.inicio, datos: const {}, alertas: const {}, onElegir: (d) {
                    tocado = d;
                    Navigator.of(ctx).pop();
                  }),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.text('Cierres de caja'), findsOneWidget);
      await t.tap(find.text('Cierres de caja'));
      await t.pumpAndSettle();
      expect(tocado, Destino.cierres);
      expect(find.text('Cierres de caja'), findsNothing);
    });

    for (final ancho in [320.0, 360.0]) {
      testWidgets('cabe a $ancho con letra grande', (t) async {
        await montar(t, SingleChildScrollView(child: HojaReportes(actual: Destino.rentabilidad, datos: const {Destino.cortesias: 'Q340 hoy'}, alertas: const {Destino.cortesias}, onElegir: (_) {})), ancho: ancho, escala: 1.4);
        expect(t.takeException(), isNull);
      });
    }
  });
}
