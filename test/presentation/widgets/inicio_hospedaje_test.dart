import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/data/models/hospedaje_inicio.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_hospedaje.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';

/// La tarjeta de Hospedaje del Inicio, sin Firebase: la pantalla real solo le
/// pasa el resumen que el provider ya armó. Se prueba qué dice en cada caso, que
/// la barra se dibuje y que nada desborde a 360dp (con letra grande) ni en
/// pantalla ancha.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  ResumenHospedaje resumen({
    int total = 11,
    int ocupadas = 7,
    int reservadas = 1,
    int limpieza = 1,
    int mantenimiento = 1,
    int? libres,
    int porSalir = 2,
    int pasadas = 1,
  }) =>
      ResumenHospedaje(
        total: total,
        ocupadas: ocupadas,
        reservadas: reservadas,
        enLimpieza: limpieza,
        enMantenimiento: mantenimiento,
        libres: libres ?? (total - ocupadas - reservadas - limpieza - mantenimiento),
        porSalirHoy: porSalir,
        pasadasDeHora: pasadas,
        estanciasActivas: ocupadas,
      );

  Future<void> montar(WidgetTester tester, ResumenHospedaje r, {Size size = const Size(360, 800), double escala = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: c!,
      ),
      home: Scaffold(
        backgroundColor: kInicioBg,
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: HospedajeCard(resumen: r)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder rico(String t) => find.textContaining(t, findRichText: true);

  group('HospedajeCard: lo que dice', () {
    testWidgets('cuántas ocupadas de cuántas, el porcentaje y el reparto', (tester) async {
      await montar(tester, resumen());
      expect(find.text('Hospedaje'), findsOneWidget);
      expect(rico('7 de 11'), findsOneWidget);
      expect(rico('ocupadas · 64%'), findsOneWidget);
      expect(find.text('Libres'), findsOneWidget);
      expect(find.text('Reservadas hoy'), findsOneWidget);
      expect(find.text('En limpieza'), findsOneWidget);
      expect(find.text('En mantenimiento'), findsOneWidget);
    });

    testWidgets('lo de hoy: por salir y las pasadas de su hora', (tester) async {
      await montar(tester, resumen(porSalir: 2, pasadas: 2));
      expect(find.text('por salir hoy'), findsOneWidget);
      expect(find.text('pasadas de su hora'), findsOneWidget);
      // "Por entrar" ya no es un dato aparte: son las "Reservadas hoy" del reparto.
      expect(find.textContaining('por entrar'), findsNothing);
    });

    testWidgets('en singular: una ocupada y una pasada de su hora', (tester) async {
      await montar(tester, resumen(total: 4, ocupadas: 1, reservadas: 0, limpieza: 0, mantenimiento: 0, pasadas: 1));
      expect(rico('1 de 4'), findsOneWidget);
      expect(rico(' ocupada · 25%'), findsOneWidget);
      expect(find.text('pasada de su hora'), findsOneWidget);
    });

    testWidgets('lo que está en cero no se dice, salvo los libres', (tester) async {
      await montar(tester, resumen(total: 5, ocupadas: 5, reservadas: 0, limpieza: 0, mantenimiento: 0, libres: 0, porSalir: 0, pasadas: 0));
      expect(rico('5 de 5'), findsOneWidget);
      expect(find.text('Libres'), findsOneWidget); // con su "0"
      expect(find.text('Reservadas hoy'), findsNothing);
      expect(find.text('En limpieza'), findsNothing);
      expect(find.text('En mantenimiento'), findsNothing);
      expect(find.text('por salir hoy'), findsNothing);
      expect(find.textContaining('de su hora'), findsNothing);
    });

    testWidgets('ninguna ocupada: 0 de 5 y 0%', (tester) async {
      await montar(tester, resumen(total: 5, ocupadas: 0, reservadas: 0, limpieza: 0, mantenimiento: 0, porSalir: 0, pasadas: 0));
      expect(rico('0 de 5'), findsOneWidget);
      expect(rico('ocupadas · 0%'), findsOneWidget);
    });
  });

  group('HospedajeCard: la barra', () {
    Finder tramos() => find.descendant(of: find.byType(ClipRRect), matching: find.byType(ColoredBox));

    testWidgets('se dibuja: cada tramo mide 8 de alto y todos juntos llenan el ancho', (tester) async {
      await montar(tester, resumen(), size: const Size(390, 844));
      // ocupadas, reservadas, limpieza, mantenimiento y libres + 4 rayas entre tramos.
      expect(tramos(), findsNWidgets(9));
      for (var i = 0; i < 9; i++) {
        expect(tester.getSize(tramos().at(i)).height, 8, reason: 'tramo $i');
      }
      final ancho = tester.getSize(find.byType(ClipRRect).first).width;
      final suma = [for (var i = 0; i < 9; i++) tester.getSize(tramos().at(i)).width].fold<double>(0, (a, b) => a + b);
      expect(suma, closeTo(ancho, 0.01));
    });

    testWidgets('los tramos son proporcionales a su cantidad (7 ocupadas, 1 libre)', (tester) async {
      await montar(tester, resumen(), size: const Size(390, 844));
      final ocupadas = tester.getSize(tramos().at(0)).width;
      final libres = tester.getSize(tramos().at(8)).width;
      expect(ocupadas / libres, closeTo(7.0, 0.05));
    });

    testWidgets('sin nada más que ocupadas solo queda ese tramo', (tester) async {
      await montar(tester, resumen(total: 5, ocupadas: 5, reservadas: 0, limpieza: 0, mantenimiento: 0, libres: 0, porSalir: 0, pasadas: 0));
      expect(tramos(), findsOneWidget);
    });
  });

  group('HospedajeCard: nada desborda', () {
    const tamanos = [Size(360, 800), Size(390, 844), Size(700, 900), Size(1280, 800)];
    for (final tam in tamanos) {
      for (final escala in const [1.0, 1.35]) {
        testWidgets('${tam.width.toInt()}×${tam.height.toInt()} con letra a $escala', (tester) async {
          await montar(tester, resumen(), size: tam, escala: escala);
          expect(tester.takeException(), isNull);
          await montar(
              tester, resumen(total: 1000, ocupadas: 999, reservadas: 0, limpieza: 1, mantenimiento: 0, libres: 0, porSalir: 777, pasadas: 666),
              size: tam, escala: escala);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
