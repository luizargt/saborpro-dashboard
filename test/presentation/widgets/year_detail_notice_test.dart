import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/presentation/widgets/year_detail_notice.dart';

/// El aviso que ocupa el lugar de los productos mientras se preparan en la
/// vista de año.
///
/// Lo que se rompe callado en un widget así es el ancho: el texto es largo y
/// en un teléfono angosto se desborda sin que nadie lo note hasta que un
/// cliente manda la captura con la franja amarilla y negra.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap({int mes = 0}) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: YearDetailNotice(mes: mes),
          ),
        ),
      );

  testWidgets('cabe en un teléfono de 360dp sin desbordarse', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(mes: 12));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('cabe en una pantalla ancha sin desbordarse', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(mes: 3));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('deja claro que el total del año NO está incompleto',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pump();

    // Ese es el miedo que deja el bug viejo: creer que faltan ventas.
    expect(find.textContaining('ya están completas'), findsOneWidget);
  });

  testWidgets('dice por qué mes va, no solo que espere', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(mes: 7));
    await tester.pump();

    expect(find.textContaining('julio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no ofrece ningún botón: el año se prepara solo', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(mes: 2));
    await tester.pump();

    // La vista de mes no pide permiso para cargar; la de año tampoco debe.
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.textContaining('Calcular'), findsNothing);
  });
}
