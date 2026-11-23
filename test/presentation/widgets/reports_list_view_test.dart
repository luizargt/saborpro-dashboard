import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/data/models/atencion_inicio.dart' show ParteTexto;
import 'package:saborpro_reports/data/models/datos_reportes.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:saborpro_reports/presentation/widgets/reports_list_view.dart';

/// La lista de Reportes sin Firebase: la pantalla real le pasa los reportes ya
/// armados. Se prueba el buscador, el orden, las columnas por ancho, los toques y
/// que nada desborde a 360dp con letra grande.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final toques = <String>[];
  setUp(toques.clear);

  List<ReporteItem> reportes() => [
        ReporteItem(
          grupo: 'Dinero',
          titulo: 'Rentabilidad',
          descripcion: 'Cuánto ganas después de costos y gastos',
          icono: Icons.trending_up_rounded,
          tono: TonoReporte.verde,
          palabras: 'ganancia utilidad margen',
          onTap: () => toques.add('rentabilidad'),
        ),
        ReporteItem(
          grupo: 'Dinero',
          titulo: 'Cierres de caja',
          descripcion: 'Lo que cuadró, faltó o sobró en cada caja',
          icono: Icons.point_of_sale_rounded,
          tono: TonoReporte.verde,
          palabras: 'caja corte arqueo',
          onTap: () => toques.add('cierres'),
          dato: const DatoReporte(
            partes: [ParteTexto('2', negrita: true), ParteTexto(' cajas abiertas')],
            bandera: BanderaReporte('Faltante Q385', TonoBandera.rojo),
          ),
        ),
        ReporteItem(
          grupo: 'Dinero',
          titulo: 'Gastos',
          descripcion: 'En qué se fue el dinero del negocio',
          icono: Icons.receipt_long_rounded,
          tono: TonoReporte.verde,
          palabras: 'compras egresos',
          onTap: () => toques.add('gastos'),
          dato: const DatoReporte(partes: [ParteTexto('Hoy '), ParteTexto('Q225.00', negrita: true)]),
        ),
        ReporteItem(
          grupo: 'Dinero',
          titulo: 'Propinas',
          descripcion: 'Quién recibe más y a qué hora se deja más',
          icono: Icons.paid_outlined,
          tono: TonoReporte.ambar,
          palabras: 'mesero propina',
          onTap: () => toques.add('propinas'),
          dato: const DatoReporte(partes: [ParteTexto('Hoy '), ParteTexto('Q293.00', negrita: true)]),
        ),
        ReporteItem(
          grupo: 'Control y pérdidas',
          titulo: 'Cortesías y donaciones',
          descripcion: 'Lo que se regaló, quién y por qué',
          icono: Icons.card_giftcard_rounded,
          tono: TonoReporte.morado,
          palabras: 'regalo cortesia donacion',
          onTap: () => toques.add('cortesias'),
          dato: const DatoReporte(
            partes: [ParteTexto('Hoy '), ParteTexto('Q35.00', negrita: true)],
            bandera: BanderaReporte('1 sin motivo', TonoBandera.ambar),
          ),
        ),
        ReporteItem(
          grupo: 'Control y pérdidas',
          titulo: 'Pedidos cancelados',
          descripcion: 'Lo anulado y el producto que se perdió',
          icono: Icons.cancel_outlined,
          tono: TonoReporte.rojo,
          palabras: 'cancelacion anulado merma bodega',
          onTap: () => toques.add('cancelados'),
        ),
      ];

  Future<void> montar(
    WidgetTester tester,
    List<ReporteItem> items, {
    Size size = const Size(360, 800),
    double escala = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(backgroundColor: kInicioBg, body: ReportsListView(reportes: items)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> buscar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField), texto);
    await tester.pumpAndSettle();
  }

  const tamanos = [Size(360, 800), Size(390, 844), Size(700, 900), Size(1280, 800)];

  group('sinAcentos', () {
    test('minúsculas y sin acentos ni tilde de la ñ', () {
      expect(sinAcentos('Cortesías y DONACIÓN'), 'cortesias y donacion');
      expect(sinAcentos('Pérdidas'), 'perdidas');
      expect(sinAcentos('Año'), 'ano');
      expect(sinAcentos('texto normal 123'), 'texto normal 123');
    });
  });

  group('la lista', () {
    testWidgets('los grupos en su orden, con su título en mayúsculas', (tester) async {
      await montar(tester, reportes(), size: const Size(360, 1800));
      expect(find.text('Reportes'), findsOneWidget);
      expect(find.text('DINERO'), findsOneWidget);
      expect(find.text('CONTROL Y PÉRDIDAS'), findsOneWidget);
      expect(tester.getTopLeft(find.text('DINERO')).dy, lessThan(tester.getTopLeft(find.text('CONTROL Y PÉRDIDAS')).dy));
      // Y cada reporte dentro del suyo.
      expect(tester.getTopLeft(find.text('Gastos')).dy, lessThan(tester.getTopLeft(find.text('CONTROL Y PÉRDIDAS')).dy));
      expect(tester.getTopLeft(find.text('Cortesías y donaciones')).dy,
          greaterThan(tester.getTopLeft(find.text('CONTROL Y PÉRDIDAS')).dy));
    });

    testWidgets('cada tarjeta lleva título, descripción y flecha', (tester) async {
      await montar(tester, reportes(), size: const Size(360, 1800));
      for (final t in ['Rentabilidad', 'Cierres de caja', 'Gastos', 'Propinas', 'Cortesías y donaciones', 'Pedidos cancelados']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Lo que cuadró, faltó o sobró en cada caja'), findsOneWidget);
      expect(find.text('Quién recibe más y a qué hora se deja más'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(6));
    });

    testWidgets('el dato de ahora y la banderita, solo en las que lo traen', (tester) async {
      await montar(tester, reportes(), size: const Size(360, 1800));
      expect(find.textContaining('cajas abiertas', findRichText: true), findsOneWidget);
      expect(find.text('Faltante Q385'), findsOneWidget);
      expect(find.textContaining('Q225.00', findRichText: true), findsOneWidget);
      expect(find.textContaining('Q293.00', findRichText: true), findsOneWidget);
      expect(find.text('1 sin motivo'), findsOneWidget);
      // Rentabilidad y Cancelados no llevan fila de dato: solo la traen Gastos,
      // Propinas y Cortesías.
      expect(find.textContaining('Hoy', findRichText: true), findsNWidgets(3));
    });

    testWidgets('la banderita va pegada al borde derecho de su tarjeta', (tester) async {
      for (final s in const [Size(390, 900), Size(1280, 900)]) {
        await montar(tester, reportes(), size: s);
        final tarjeta = find.ancestor(of: find.text('Cierres de caja'), matching: find.byType(InkWell)).first;
        final bandera = find.text('Faltante Q385');
        await tester.ensureVisible(bandera);
        await tester.pumpAndSettle();
        // Hasta el relleno de 20 y el borde de 2 de la tarjeta.
        expect(tester.getTopRight(find.ancestor(of: bandera, matching: find.byType(Container)).first).dx,
            closeTo(tester.getTopRight(tarjeta).dx - 20, 1.5),
            reason: '${s.width}');
      }
    });

    testWidgets('tocar una tarjeta abre ESE reporte', (tester) async {
      await montar(tester, reportes());
      // En un teléfono las de abajo quedan fuera de pantalla: se traen a la vista.
      for (final t in ['Gastos', 'Propinas', 'Pedidos cancelados', 'Rentabilidad']) {
        await tester.ensureVisible(find.text(t));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t));
      }
      expect(toques, ['gastos', 'propinas', 'cancelados', 'rentabilidad']);
    });

    testWidgets('una lista vacía no se rompe', (tester) async {
      await montar(tester, const []);
      expect(find.text('Reportes'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('el buscador', () {
    testWidgets('encuentra sin importar acentos ni mayúsculas, y deja solo su grupo', (tester) async {
      await montar(tester, reportes());
      await buscar(tester, 'CORTESIA');
      expect(find.text('Cortesías y donaciones'), findsOneWidget);
      expect(find.text('Gastos'), findsNothing);
      expect(find.text('CONTROL Y PÉRDIDAS'), findsOneWidget);
      expect(find.text('DINERO'), findsNothing, reason: 'un grupo sin reportes no se dibuja');
    });

    testWidgets('busca también en la descripción y en las palabras clave', (tester) async {
      await montar(tester, reportes());
      await buscar(tester, 'margen'); // palabra clave de Rentabilidad
      expect(find.text('Rentabilidad'), findsOneWidget);
      expect(find.text('Gastos'), findsNothing);

      await buscar(tester, 'se regaló'); // de la descripción
      expect(find.text('Cortesías y donaciones'), findsOneWidget);
      expect(find.text('Rentabilidad'), findsNothing);

      await buscar(tester, 'arqueo');
      expect(find.text('Cierres de caja'), findsOneWidget);

      // Quien busca "mesero" o "propina" llega a Propinas, y a nada más.
      for (final palabra in ['mesero', 'PROPINA']) {
        await buscar(tester, palabra);
        expect(find.text('Propinas'), findsOneWidget, reason: palabra);
        expect(find.text('Gastos'), findsNothing, reason: palabra);
        expect(find.text('Cierres de caja'), findsNothing, reason: palabra);
      }
    });

    testWidgets('el nombre del grupo trae todos los de ese grupo', (tester) async {
      await montar(tester, reportes());
      await buscar(tester, 'perdidas');
      expect(find.text('Cortesías y donaciones'), findsOneWidget);
      expect(find.text('Pedidos cancelados'), findsOneWidget);
      expect(find.text('Gastos'), findsNothing);
    });

    testWidgets('sin coincidencias dice qué buscó; al borrar vuelve todo', (tester) async {
      await montar(tester, reportes());
      await buscar(tester, 'zzz');
      expect(find.text('No encontré “zzz”'), findsOneWidget);
      expect(find.text('Prueba con otra palabra.'), findsOneWidget);
      expect(find.text('Gastos'), findsNothing);

      await buscar(tester, '');
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Rentabilidad'), findsOneWidget);
      expect(find.text('No encontré “zzz”'), findsNothing);
    });

    testWidgets('los espacios de más no estorban', (tester) async {
      await montar(tester, reportes());
      await buscar(tester, '   egresos  '); // palabra clave solo de Gastos
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Rentabilidad'), findsNothing);
    });
  });

  group('columnas según el ancho', () {
    Future<List<double>> ys(WidgetTester tester, List<String> titulos) async =>
        [for (final t in titulos) tester.getTopLeft(find.text(t)).dy];

    testWidgets('en teléfono, una por fila', (tester) async {
      await montar(tester, reportes(), size: const Size(390, 900));
      final y = await ys(tester, ['Rentabilidad', 'Cierres de caja', 'Gastos']);
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
      // A 700 también (el diseño pasa a teléfono en 760).
      await montar(tester, reportes(), size: const Size(700, 900));
      final y7 = await ys(tester, ['Rentabilidad', 'Cierres de caja']);
      expect(y7[0], lessThan(y7[1]));
    });

    testWidgets('a 900, dos columnas; a 1280, tres', (tester) async {
      await montar(tester, reportes(), size: const Size(900, 900));
      final y9 = await ys(tester, ['Rentabilidad', 'Cierres de caja', 'Gastos']);
      expect(y9[0], y9[1]);
      expect(y9[2], greaterThan(y9[1]), reason: 'la tercera baja');

      await montar(tester, reportes(), size: const Size(1280, 900));
      final y12 = await ys(tester, ['Rentabilidad', 'Cierres de caja', 'Gastos']);
      expect(y12[0], y12[1]);
      expect(y12[1], y12[2]);
    });

    testWidgets('las de una fila miden lo mismo aunque una no lleve dato', (tester) async {
      await montar(tester, reportes(), size: const Size(1280, 900));
      Finder tarjeta(String t) => find.ancestor(of: find.text(t), matching: find.byType(InkWell)).first;
      // Rentabilidad (sin dato) y Cierres de caja (con dato y banderita).
      expect(tester.getSize(tarjeta('Rentabilidad')).height, tester.getSize(tarjeta('Cierres de caja')).height);
      expect(tester.getSize(tarjeta('Rentabilidad')).width, tester.getSize(tarjeta('Cierres de caja')).width);
      // Y las dos de abajo tienen el mismo ancho que las de arriba (no se estiran).
      expect(tester.getSize(tarjeta('Pedidos cancelados')).width, tester.getSize(tarjeta('Gastos')).width);
    });
  });

  group('cabe', () {
    // Lo más largo que puede llegar: nombres, descripciones y datos enormes.
    List<ReporteItem> enormes() => [
          for (var i = 0; i < 4; i++)
            ReporteItem(
              grupo: i.isEven ? 'Un grupo con un nombre larguísimo de verdad para ver qué pasa' : 'Otro',
              titulo: 'Un reporte con un título larguísimo de verdad número $i para ver si se parte',
              descripcion: 'Una descripción también larguísima que tiene que partirse en varias líneas sin romper nada, $i',
              icono: Icons.bar_chart_rounded,
              tono: TonoReporte.values[i % TonoReporte.values.length],
              onTap: () {},
              dato: DatoReporte(
                partes: const [
                  ParteTexto('noviembre 2026 '),
                  ParteTexto('USD 987,654,321.55', negrita: true),
                ],
                bandera: const BanderaReporte('Faltante USD 12,345,678.90', TonoBandera.rojo),
              ),
            ),
        ];

    for (final s in tamanos) {
      for (final escala in const [1.0, 1.35]) {
        testWidgets('${s.width.toInt()}×${s.height.toInt()} con letra a $escala', (tester) async {
          await montar(tester, enormes(), size: s, escala: escala);
          expect(tester.takeException(), isNull);
          await buscar(tester, 'zzz');
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('el buscador baja bajo el título en teléfono y va al lado en ancho', (tester) async {
      await montar(tester, reportes(), size: const Size(390, 844));
      expect(tester.getTopLeft(find.byType(TextField)).dy, greaterThan(tester.getTopLeft(find.text('Reportes')).dy));

      await montar(tester, reportes(), size: const Size(1280, 800));
      expect(tester.getCenter(find.byType(TextField)).dy, closeTo(tester.getCenter(find.text('Reportes')).dy, 6));
      expect(tester.getTopLeft(find.byType(TextField)).dx, greaterThan(tester.getTopRight(find.text('Reportes')).dx));
    });
  });
}
