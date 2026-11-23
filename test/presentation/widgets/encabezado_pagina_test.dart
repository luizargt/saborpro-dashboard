import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/navigation/contexto_shell.dart';
import 'package:saborpro_reports/presentation/widgets/encabezado_pagina.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  Future<void> montar(WidgetTester t, Widget w, {double ancho = 1000, double escala = 1}) async {
    t.view.physicalSize = Size(ancho, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(ancho, 600), textScaler: TextScaler.linear(escala)),
        child: Scaffold(body: w),
      ),
    ));
  }

  testWidgets('la miga, el título y las acciones en orden', (t) async {
    await montar(t, EncabezadoPagina(miga: 'Buenos días, Luis', titulo: 'Inicio', acciones: [
      BotonEncabezado(icono: Icons.tune_rounded, ayuda: 'Configurar avisos', texto: 'Configurar avisos', onTap: () {}),
      BotonEncabezado(icono: Icons.file_download_outlined, ayuda: 'Descargar reportes', onTap: () {}),
    ]));
    expect(find.text('Buenos días, Luis'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget);
    expect(t.getTopLeft(find.text('Configurar avisos')).dx, lessThan(t.getTopLeft(find.byTooltip('Descargar reportes')).dx));
  });

  testWidgets('en pantalla ancha el botón lleva su texto; en el teléfono solo el ícono', (t) async {
    final boton = BotonEncabezado(icono: Icons.tune_rounded, ayuda: 'Configurar avisos', texto: 'Configurar avisos', onTap: () {});
    await montar(t, boton);
    expect(find.text('Configurar avisos'), findsOneWidget);
    await montar(t, boton, ancho: 360);
    expect(find.text('Configurar avisos'), findsNothing);
    expect(t.getSize(find.byType(BotonEncabezado)).width, 44);
  });

  testWidgets('tocar el botón avisa', (t) async {
    var toques = 0;
    await montar(t, BotonEncabezado(icono: Icons.file_download_outlined, ayuda: 'Descargar reportes', onTap: () => toques++));
    await t.tap(find.byType(BotonEncabezado));
    expect(toques, 1);
  });

  for (final ancho in [320.0, 360.0, 1000.0]) {
    testWidgets('cabe a $ancho con letra grande y título largo', (t) async {
      await montar(
        t,
        EncabezadoPagina(miga: 'Reportes · Control', titulo: 'Cortesías y donaciones del mes de noviembre', acciones: [
          BotonEncabezado(icono: Icons.file_download_outlined, ayuda: 'Descargar reportes', onTap: () {}),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: const Text('1 – 22 nov 2026 muy largo')),
        ]),
        ancho: ancho,
        escala: 1.4,
      );
      expect(t.takeException(), isNull);
    });
  }

  group('ContextoShell', () {
    testWidgets('dentro del shell lo sabe; suelta, no', (t) async {
      late bool dentro, fuera;
      await t.pumpWidget(Column(textDirection: TextDirection.ltr, children: [
        ContextoShell(child: Builder(builder: (c) {
          dentro = ContextoShell.enShell(c);
          return const SizedBox();
        })),
        Builder(builder: (c) {
          fuera = ContextoShell.enShell(c);
          return const SizedBox();
        }),
      ]));
      expect(dentro, isTrue);
      expect(fuera, isFalse);
    });
  });
}
