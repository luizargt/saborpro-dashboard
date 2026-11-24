import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/widgets/barra_lateral.dart' show LogoManager;
import 'package:saborpro_reports/presentation/widgets/encabezado_movil.dart';

/// La línea de arriba del teléfono: el logo, el nombre de la vista y sus botones, y nada
/// más (ni el negocio, ni la lupa, ni la foto de perfil: eso vive en "Más").
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
        child: Scaffold(body: Align(alignment: Alignment.topCenter, child: w)),
      ),
    ));
  }

  /// Un botón de 44 como los del encabezado.
  Widget boton(String ayuda, {VoidCallback? onTap}) => Tooltip(
        message: ayuda,
        child: GestureDetector(onTap: onTap, child: const SizedBox(width: 44, height: 44, child: Icon(Icons.file_download_outlined))),
      );

  testWidgets('el logo, el nombre de la vista y los botones van en UNA línea', (t) async {
    await montar(t, EncabezadoMovil(titulo: 'Despensa', acciones: [boton('Descargar reportes'), boton('Fecha')]));
    expect(find.byType(LogoManager), findsOneWidget);
    expect(find.text('Despensa'), findsOneWidget);

    // Todo a la misma altura (el centro de cada pieza coincide con el del logo).
    final cy = t.getCenter(find.byType(LogoManager)).dy;
    expect((t.getCenter(find.text('Despensa')).dy - cy).abs(), lessThan(4));
    expect((t.getCenter(find.byTooltip('Descargar reportes')).dy - cy).abs(), lessThan(4));
    expect((t.getCenter(find.byTooltip('Fecha')).dy - cy).abs(), lessThan(4));

    // De izquierda a derecha: logo, título, botones en el orden dado.
    expect(t.getTopLeft(find.byType(LogoManager)).dx, lessThan(t.getTopLeft(find.text('Despensa')).dx));
    expect(t.getTopLeft(find.text('Despensa')).dx, lessThan(t.getTopLeft(find.byTooltip('Descargar reportes')).dx));
    expect(t.getTopLeft(find.byTooltip('Descargar reportes')).dx, lessThan(t.getTopLeft(find.byTooltip('Fecha')).dx));
  });

  testWidgets('no trae el negocio, la lupa ni la foto de perfil', (t) async {
    await montar(t, const EncabezadoMovil(titulo: 'Inicio'));
    expect(find.text('Sabor Manager'), findsNothing);
    expect(find.textContaining('sucursal'), findsNothing);
    expect(find.byTooltip('Buscar'), findsNothing);
    expect(find.byTooltip('Cuenta'), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
  });

  testWidgets('mide poco: una línea, no dos encabezados', (t) async {
    await montar(t, EncabezadoMovil(titulo: 'Inicio', acciones: [boton('Descargar reportes')]));
    // 8 + 44 (el botón) + 8, más el borde: bastante menos que las dos barras de antes (~130).
    expect(t.getSize(find.byType(EncabezadoMovil)).height, lessThan(70));
  });

  testWidgets('sin botones es solo el logo y el título', (t) async {
    await montar(t, const EncabezadoMovil(titulo: 'Avisos'));
    expect(find.text('Avisos'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('un nombre largo baja a una segunda línea y no se sale', (t) async {
    await montar(t, EncabezadoMovil(titulo: 'Cortesías y donaciones', acciones: [boton('Descargar reportes'), SizedBox(width: 100, height: 44, child: boton('Fecha'))]));
    expect(t.takeException(), isNull);
    // Dos líneas de 18 px (~22 de alto cada una) como mucho.
    expect(t.getSize(find.text('Cortesías y donaciones')).height, lessThan(60));
  });

  testWidgets('el título es un encabezado para los lectores de pantalla', (t) async {
    final handle = t.ensureSemantics();
    await montar(t, const EncabezadoMovil(titulo: 'Gastos'));
    expect(t.getSemantics(find.text('Gastos')).flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  for (final ancho in [320.0, 360.0, 390.0]) {
    for (final escala in [1.0, 1.4]) {
      testWidgets('cabe a $ancho con letra a $escala, con fecha y descarga y un nombre largo', (t) async {
        await montar(
          t,
          EncabezadoMovil(
            titulo: 'Compras vs Ventas',
            acciones: [
              boton('Descargar reportes'),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: const SizedBox(width: 140, height: 44, child: Placeholder())),
            ],
          ),
          ancho: ancho,
          escala: escala,
        );
        expect(t.takeException(), isNull);
      });
    }
  }
}
