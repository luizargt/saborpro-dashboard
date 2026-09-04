import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/store_update_service.dart';
import 'package:saborpro_reports/presentation/widgets/forced_update_gate.dart';

/// El aviso obligatorio a 360dp, con la tienda simulada.
Future<List<String>> _pump(
  WidgetTester tester, {
  required StoreUpdateStatus estado,
}) async {
  final abiertas = <String>[];
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: ForcedUpdateGate(
        checker: () async => estado,
        opener: (url) async {
          abiertas.add(url);
          return true;
        },
        child: const Scaffold(
          body: Center(child: Text('VENTAS DEL DIA Q12,450')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return abiertas;
}

void main() {
  const alDia = StoreUpdateStatus(
    updateAvailable: false,
    currentVersion: '1.1.0',
  );
  const atrasada = StoreUpdateStatus(
    updateAvailable: true,
    currentVersion: '1.1.0',
    storeVersion: '1.2.0',
    storeUrl: 'https://apps.apple.com/app/id6805690171',
  );

  testWidgets('al día no muestra nada y deja usar la app', (tester) async {
    await _pump(tester, estado: alDia);

    expect(find.text('Actualiza Sabor Suite'), findsNothing);
    expect(find.text('VENTAS DEL DIA Q12,450'), findsOneWidget);
  });

  testWidgets('atrasada muestra el letrero con el botón Actualizar',
      (tester) async {
    await _pump(tester, estado: atrasada);

    expect(find.text('Actualiza Sabor Suite'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Actualizar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el botón manda a la tienda', (tester) async {
    final abiertas = await _pump(tester, estado: atrasada);

    await tester.tap(find.text('Actualizar'));
    await tester.pump();

    expect(abiertas, ['https://apps.apple.com/app/id6805690171']);
  });

  testWidgets('no se puede cerrar: no hay salida más que actualizar',
      (tester) async {
    await _pump(tester, estado: atrasada);

    // Ni un botón de cerrar, ni "ahora no", ni una X.
    expect(find.text('Cerrar'), findsNothing);
    expect(find.text('Ahora no'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);

    // Y el botón atrás de Android tampoco lo saca.
    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
  });

  testWidgets('tapa lo que haya debajo', (tester) async {
    await _pump(tester, estado: atrasada);

    // El contenido sigue montado pero queda detrás de un velo opaco.
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PopScope),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, isNot(Colors.transparent));
    expect(material.color!.a, greaterThan(0.5));
  });

  testWidgets('un chequeo que falla no bloquea a nadie', (tester) async {
    // Sin señal el servicio devuelve upToDate; acá se simula que ni siquiera
    // responde a tiempo y el gate se queda sin estado.
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ForcedUpdateGate(
          checker: () => Future.delayed(
            const Duration(seconds: 30),
            () => const StoreUpdateStatus(
                updateAvailable: true, currentVersion: '1.1.0'),
          ),
          child: const Scaffold(body: Center(child: Text('reportes'))),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Actualiza Sabor Suite'), findsNothing);
    expect(find.text('reportes'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 31));
  });

  testWidgets('sin url de tienda el botón no revienta', (tester) async {
    const sinUrl = StoreUpdateStatus(
      updateAvailable: true,
      currentVersion: '1.1.0',
    );
    await _pump(tester, estado: sinUrl);

    await tester.tap(find.text('Actualizar'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a 360dp el letrero no desborda', (tester) async {
    await _pump(tester, estado: atrasada);
    expect(tester.takeException(), isNull);
  });

  testWidgets('las barras del sistema no tapan el botón Actualizar',
      (tester) async {
    // Reproduce un Android edge-to-edge: barra de estado arriba y barra de
    // navegación abajo comiéndose los bordes. El botón tiene que quedar
    // entero dentro de la zona usable, o el usuario ve un aviso que no puede
    // obedecer.
    const barraEstado = 48.0;
    const barraNavegacion = 56.0;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          padding: EdgeInsets.only(top: barraEstado, bottom: barraNavegacion),
          viewPadding:
              EdgeInsets.only(top: barraEstado, bottom: barraNavegacion),
        ),
        child: MaterialApp(
          useInheritedMediaQuery: true,
          home: ForcedUpdateGate(
            checker: () async => atrasada,
            opener: (_) async => true,
            child: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boton = find.widgetWithText(ElevatedButton, 'Actualizar');
    expect(boton, findsOneWidget);

    final caja = tester.getRect(boton);
    expect(caja.top, greaterThanOrEqualTo(barraEstado),
        reason: 'el botón se mete bajo la barra de estado');
    expect(caja.bottom, lessThanOrEqualTo(640 - barraNavegacion),
        reason: 'el botón se mete bajo la barra de navegación');

    // Y el título tampoco puede quedar debajo del reloj.
    final titulo = tester.getRect(find.text('Actualiza Sabor Suite'));
    expect(titulo.top, greaterThanOrEqualTo(barraEstado));
  });
}
