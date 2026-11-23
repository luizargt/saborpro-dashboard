import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/navigation/destinos.dart';
import 'package:saborpro_reports/presentation/widgets/menu_cuenta.dart';

/// El panel de la cuenta (pantalla ancha) y la hoja "Más" (teléfono).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  Future<void> montar(WidgetTester t, Widget w, {double ancho = 400, double escala = 1}) async {
    t.view.physicalSize = Size(ancho, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(ancho, 1200), textScaler: TextScaler.linear(escala)),
        child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: w)),
      ),
    ));
  }

  PanelCuenta panel({
    String nombre = 'Luis Arreago',
    int sucursales = 3,
    String version = 'v1.1.5 (3)',
    Destino actual = Destino.inicio,
    VoidCallback? onDescargas,
    VoidCallback? onNotificaciones,
    VoidCallback? onCerrarSesion,
    List<Widget> extras = const [],
  }) =>
      PanelCuenta(
        nombre: nombre,
        rol: 'Administrador',
        sucursales: sucursales,
        version: version,
        actual: actual,
        onDescargas: onDescargas ?? () {},
        onNotificaciones: onNotificaciones ?? () {},
        onCerrarSesion: onCerrarSesion ?? () {},
        extras: extras,
      );

  HojaMas hoja({
    String nombre = 'Luis Arreago',
    String version = 'v1.1.5 (3)',
    Destino actual = Destino.inicio,
    VoidCallback? onDescargas,
    VoidCallback? onNotificaciones,
    VoidCallback? onCerrarSesion,
    List<Widget> extras = const [],
  }) =>
      HojaMas(
        nombre: nombre,
        rol: 'Administrador',
        sucursales: 1,
        version: version,
        actual: actual,
        onDescargas: onDescargas ?? () {},
        onNotificaciones: onNotificaciones ?? () {},
        onCerrarSesion: onCerrarSesion ?? () {},
        extras: extras,
      );

  group('panel de la cuenta', () {
    testWidgets('quién es, qué rol, cuántas sucursales y la versión', (t) async {
      await montar(t, panel());
      expect(find.text('Luis Arreago'), findsOneWidget);
      expect(find.text('Administrador · 3 sucursales'), findsOneWidget);
      expect(find.text('Sabor Manager v1.1.5 (3)'), findsOneWidget);
      expect(find.text('Descargar reportes'), findsOneWidget);
      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('sin versión conocida no la escribe', (t) async {
      await montar(t, panel(version: ''));
      expect(find.textContaining('Sabor Manager'), findsNothing);
    });

    testWidgets('cada fila avisa lo suyo', (t) async {
      final toques = <String>[];
      await montar(t, panel(onDescargas: () => toques.add('d'), onNotificaciones: () => toques.add('n'), onCerrarSesion: () => toques.add('s')));
      await t.tap(find.text('Descargar reportes'));
      await t.tap(find.text('Notificaciones'));
      await t.tap(find.text('Cerrar sesión'));
      expect(toques, ['d', 'n', 's']);
    });

    testWidgets('los extras (apariencia, biometría, moneda) van antes de "Cerrar sesión"', (t) async {
      await montar(t, panel(extras: [FilaMenu(icono: Icons.currency_exchange_rounded, texto: 'Moneda y tipo de cambio', onTap: () {})]));
      final moneda = t.getTopLeft(find.text('Moneda y tipo de cambio')).dy;
      final cerrar = t.getTopLeft(find.text('Cerrar sesión')).dy;
      final notif = t.getTopLeft(find.text('Notificaciones')).dy;
      expect(moneda, greaterThan(notif));
      expect(moneda, lessThan(cerrar));
    });

    testWidgets('cabe con nombre larguísimo y letra grande', (t) async {
      await montar(t, SizedBox(width: 256, child: panel(nombre: 'Maria de los Angeles Fernandez de la Cruz y Soto', sucursales: 12)), escala: 1.4);
      expect(t.takeException(), isNull);
    });
  });

  group('hoja "Más"', () {
    testWidgets('con sus descripciones', (t) async {
      await montar(t, hoja(), ancho: 360);
      expect(find.text('Descargar reportes'), findsOneWidget);
      expect(find.text('Reportes en Excel'), findsOneWidget);
      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text(Destinos.descripcion(Destino.notificaciones)), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.text('Administrador · 1 sucursal'), findsOneWidget);
    });

    testWidgets('las filas miden al menos 60 de alto (se tocan con el pulgar)', (t) async {
      await montar(t, hoja(), ancho: 360);
      expect(t.getSize(find.ancestor(of: find.text('Notificaciones'), matching: find.byType(ConstrainedBox)).first).height, greaterThanOrEqualTo(60));
    });

    testWidgets('cada fila avisa lo suyo', (t) async {
      final toques = <String>[];
      await montar(t, hoja(onDescargas: () => toques.add('d'), onNotificaciones: () => toques.add('n'), onCerrarSesion: () => toques.add('s')), ancho: 360);
      await t.tap(find.text('Descargar reportes'));
      await t.tap(find.text('Notificaciones'));
      await t.tap(find.text('Cerrar sesión'));
      expect(toques, ['d', 'n', 's']);
    });

    for (final ancho in [320.0, 360.0]) {
      testWidgets('cabe a $ancho con letra grande', (t) async {
        await montar(t, hoja(nombre: 'Maria de los Angeles Fernandez de la Cruz y Soto'), ancho: ancho, escala: 1.4);
        expect(t.takeException(), isNull);
      });
    }
  });

  testWidgets('FilaMenu "peligro" no lleva flecha', (t) async {
    await montar(t, FilaMenu(grande: true, icono: Icons.logout_rounded, texto: 'Salir', peligro: true, onTap: () {}));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    await montar(t, FilaMenu(grande: true, icono: Icons.logout_rounded, texto: 'Otra', onTap: () {}));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });
}
