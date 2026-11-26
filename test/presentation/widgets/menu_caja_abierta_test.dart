import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/core/services/cierre_admin_service.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/presentation/widgets/cierres_caja_view.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:saborpro_reports/presentation/widgets/menu_caja_abierta.dart';

/// Los tres puntos de "En caja ahora": "Cerrar caja", con su aviso. Cualquier
/// "RenderFlex overflowed" hace fallar la prueba por sí sola.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  final ahora = DateTime(2026, 11, 25, 21);

  CashRegisterSummary abierta(String id, String nombre, DateTime desde) => CashRegisterSummary(
        id: id,
        userId: id,
        userName: nombre,
        status: 'open',
        openedAt: desde,
        locationName: 'Sanarate, El Progreso',
      );

  final wendy = abierta('w', 'WENDY', DateTime(2026, 9, 23, 12, 56));

  late int cierres;
  late int recargas;

  setUp(() {
    cierres = 0;
    recargas = 0;
  });

  Future<void> montar(
    WidgetTester tester, {
    Future<ResultadoCierreAdmin> Function()? alCerrar,
    List<CashRegisterSummary>? cajas,
    Size size = const Size(360, 780),
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
      home: Scaffold(
        backgroundColor: kInicioBg,
        body: CierresCajaBody(
          cierres: const [],
          abiertas: cajas ?? [wendy],
          signoDeCaja: (_) => 'Q',
          ahora: ahora,
          onVerDetalle: (_) {},
          accionAbierta: (r) => MenuCajaAbierta(
            caja: r,
            onCerrar: () {
              cierres++;
              return alCerrar?.call() ?? Future.value(ResultadoCierreAdmin.cerrada);
            },
            onTerminado: () => recargas++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> abrirAviso(WidgetTester tester) async {
    await tester.ensureVisible(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar caja'));
    await tester.pumpAndSettle();
  }

  Finder botonCerrar() => find.widgetWithText(FilledButton, 'Cerrar caja');

  testWidgets('los tres puntos van en la esquina de arriba a la derecha de la tarjeta', (tester) async {
    for (final size in const [Size(360, 780), Size(1280, 900)]) {
      await montar(tester, size: size);
      final tarjeta = tester.getRect(find.byKey(const ValueKey('abierta-w')));
      final puntos = tester.getRect(find.byType(MenuCajaAbierta));
      expect(tarjeta.right - puntos.right, lessThanOrEqualTo(6), reason: '$size');
      expect(puntos.top - tarjeta.top, lessThanOrEqualTo(6), reason: '$size');
      // Un blanco que se pueda tocar con el dedo.
      expect(puntos.width, greaterThanOrEqualTo(44));
      expect(puntos.height, greaterThanOrEqualTo(44));
      // No tapan el tiempo que lleva abierta.
      final dibujo = tester.getRect(find.byIcon(Icons.more_horiz_rounded));
      expect(tester.getRect(find.text('Abierta')).overlaps(dibujo), isFalse, reason: '$size');
    }
  });

  testWidgets('al tocarlos sale "Cerrar caja" y antes de cerrar avisa que queda descuadrada', (tester) async {
    await montar(tester);
    expect(find.text('Cerrar caja'), findsNothing);
    await abrirAviso(tester);
    expect(find.text('¿Cerrar la caja de WENDY?'), findsOneWidget);
    expect(find.textContaining('quedará descuadrada'), findsOneWidget);
    expect(find.textContaining('"Cerrada por administrador"'), findsOneWidget);
    expect(find.textContaining('no se puede deshacer'), findsOneWidget);
    expect(find.textContaining('pide que dejen de cobrar'), findsOneWidget);
    expect(find.textContaining('lo que no haya subido no sale en el corte'), findsOneWidget);
    // El aviso repite qué caja es: desde cuándo y dónde.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Abierta desde el 23 sept, 12:56 PM · Sanarate, El Progreso'),
      ),
      findsOneWidget,
    );
    expect(cierres, 0, reason: 'todavía no se confirma');
  });

  testWidgets('cancelar no cierra nada', (tester) async {
    await montar(tester);
    await abrirAviso(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(cierres, 0);
    expect(recargas, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('tocar fuera del aviso tampoco cierra', (tester) async {
    await montar(tester);
    await abrirAviso(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(cierres, 0);
  });

  testWidgets('confirmar cierra una vez, lo dice y vuelve a leer las cajas', (tester) async {
    final espera = Completer<ResultadoCierreAdmin>();
    await montar(tester, alCerrar: () => espera.future);
    await abrirAviso(tester);
    await tester.tap(botonCerrar());
    await tester.pump(const Duration(milliseconds: 500));
    // Mientras cierra no hay forma de pedirlo otra vez.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    espera.complete(ResultadoCierreAdmin.cerrada);
    await tester.pumpAndSettle();
    expect(cierres, 1);
    expect(recargas, 1);
    expect(find.text('La caja de WENDY quedó cerrada por administrador, descuadrada.'), findsOneWidget);
  });

  testWidgets('si ya estaba cerrada lo dice y vuelve a leer', (tester) async {
    await montar(tester, alCerrar: () async => ResultadoCierreAdmin.yaEstabaCerrada);
    await abrirAviso(tester);
    await tester.tap(botonCerrar());
    await tester.pumpAndSettle();
    expect(find.text('La caja de WENDY ya estaba cerrada. No se cambió nada.'), findsOneWidget);
    expect(recargas, 1);
  });

  testWidgets('si le están cobrando no la cierra y lo dice', (tester) async {
    await montar(tester, alCerrar: () async => ResultadoCierreAdmin.cobrando);
    await abrirAviso(tester);
    await tester.tap(botonCerrar());
    await tester.pumpAndSettle();
    expect(find.textContaining('No se cerró: están cobrando en la caja de WENDY'), findsOneWidget);
    expect(recargas, 0);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('si falla lo dice, no recarga y se puede reintentar', (tester) async {
    await montar(tester, alCerrar: () async => throw Exception('sin internet'));
    await abrirAviso(tester);
    await tester.tap(botonCerrar());
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo cerrar la caja de WENDY'), findsOneWidget);
    expect(recargas, 0);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('si la pantalla se recarga mientras cierra, el aviso sale igual', (tester) async {
    final espera = Completer<ResultadoCierreAdmin>();
    var visible = true;
    late StateSetter cambiar;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          cambiar = setState;
          return visible
              ? MenuCajaAbierta(caja: wendy, onCerrar: () => espera.future, onTerminado: () => recargas++)
              : const Text('cargando');
        }),
      ),
    ));
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar caja'));
    await tester.pumpAndSettle();
    await tester.tap(botonCerrar());
    await tester.pump(const Duration(milliseconds: 500));
    cambiar(() => visible = false);
    await tester.pump();
    espera.complete(ResultadoCierreAdmin.cerrada);
    await tester.pumpAndSettle();
    expect(find.text('La caja de WENDY quedó cerrada por administrador, descuadrada.'), findsOneWidget);
    expect(recargas, 1);
  });

  testWidgets('en teléfono y escritorio, también con letra grande, nada se sale', (tester) async {
    final cajas = [wendy, abierta('l', 'Ana Lena Katt de los Ángeles Ajiquichí', DateTime(2026, 11, 25, 8))];
    for (final size in const [Size(320, 3000), Size(360, 3000), Size(700, 3000), Size(1280, 3000)]) {
      for (final escala in const [1.0, 1.3, 2.0]) {
        await montar(tester, cajas: cajas, size: size, escala: escala);
        expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(2));
        expect(tester.takeException(), isNull, reason: '$size x$escala');
      }
    }
  });

  testWidgets('el aviso cabe en un teléfono chico con letra grande', (tester) async {
    await montar(tester, size: const Size(320, 640), escala: 2.0);
    await abrirAviso(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(botonCerrar());
    await tester.pumpAndSettle();
    await tester.tap(botonCerrar());
    await tester.pumpAndSettle();
    expect(cierres, 1);
  });
}
