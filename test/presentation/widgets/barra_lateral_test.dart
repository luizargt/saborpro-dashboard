import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/navigation/destinos.dart';
import 'package:saborpro_reports/presentation/widgets/barra_lateral.dart';

/// La barra lateral (sidebar-manager.html): lo que muestra y lo que avisa que se tocó.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  Future<void> montar(
    WidgetTester t, {
    bool contraida = false,
    Destino actual = Destino.inicio,
    int avisos = 0,
    int agotados = 0,
    Set<Destino> puntos = const {},
    String nombre = 'Luis Arreago',
    int sucursales = 3,
    double escala = 1,
    ValueChanged<Destino>? onElegir,
    VoidCallback? onBuscar,
    VoidCallback? onCuenta,
    bool cuentaAbierta = false,
  }) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(1280, 800), textScaler: TextScaler.linear(escala)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: BarraLateral(
              actual: actual,
              contraida: contraida,
              avisosSinLeer: avisos,
              agotados: agotados,
              puntos: puntos,
              sucursales: sucursales,
              nombre: nombre,
              rol: 'Administrador',
              onElegir: onElegir ?? (_) {},
              onBuscar: onBuscar ?? () {},
              onCuenta: onCuenta ?? () {},
              cuentaAbierta: cuentaAbierta,
            ),
          ),
        ),
      ),
    ));
  }

  group('expandida', () {
    testWidgets('ancho completo, el negocio y todas las secciones con sus lugares', (t) async {
      await montar(t);
      expect(t.getSize(find.byType(BarraLateral)).width, AnchoBarra.completa);
      expect(find.text('Sabor Manager'), findsOneWidget);
      expect(find.text('3 sucursales'), findsOneWidget);
      for (final s in ['GENERAL', 'REPORTES · DINERO', 'CONTROL Y PÉRDIDAS']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      for (final d in [
        Destino.inicio, Destino.avisos, Destino.despensa, Destino.rentabilidad, Destino.comprasVentas,
        Destino.gastos, Destino.cierres, Destino.propinas, Destino.cortesias, Destino.cancelados,
      ]) {
        expect(find.text(Destinos.nombre(d)), findsOneWidget, reason: Destinos.nombre(d));
      }
      // Las acciones de la cuenta no son lugares de la barra.
      expect(find.text('Descargar reportes'), findsNothing);
      expect(find.text('Notificaciones'), findsNothing);
    });

    testWidgets('una sola sucursal se escribe en singular', (t) async {
      await montar(t, sucursales: 1);
      expect(find.text('1 sucursal'), findsOneWidget);
    });

    testWidgets('tocar un lugar avisa cuál', (t) async {
      Destino? tocado;
      await montar(t, onElegir: (d) => tocado = d);
      await t.tap(find.text('Compras vs Ventas'));
      expect(tocado, Destino.comprasVentas);
      await t.tap(find.text('Pedidos cancelados'));
      expect(tocado, Destino.cancelados);
    });

    testWidgets('el lugar donde se está queda marcado', (t) async {
      await montar(t, actual: Destino.gastos);
      bool marcado(String nombre) => t.widget<Semantics>(find.ancestor(of: find.text(nombre), matching: find.byType(Semantics)).first).properties.selected ?? false;
      expect(marcado('Gastos'), isTrue);
      expect(marcado('Inicio'), isFalse);
    });

    testWidgets('en las notificaciones se enciende Avisos', (t) async {
      await montar(t, actual: Destino.notificaciones);
      final avisos = t.widget<Semantics>(find.ancestor(of: find.text('Avisos'), matching: find.byType(Semantics)).first);
      expect(avisos.properties.selected, isTrue);
    });

    testWidgets('contador rojo de avisos, y 99+ cuando son muchos', (t) async {
      await montar(t, avisos: 3);
      expect(find.text('3'), findsOneWidget);
      await montar(t, avisos: 140);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('sin avisos no hay contador', (t) async {
      await montar(t);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('los agotados salen en Despensa y el punto en Cortesías', (t) async {
      await montar(t, agotados: 12, puntos: {Destino.cortesias});
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('el buscador y la cuenta avisan; el atajo se ve', (t) async {
      var busco = 0, cuenta = 0;
      await montar(t, onBuscar: () => busco++, onCuenta: () => cuenta++);
      expect(find.text('Ctrl K'), findsOneWidget);
      await t.tap(find.text('Buscar…'));
      await t.tap(find.text('Luis Arreago'));
      expect(busco, 1);
      expect(cuenta, 1);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('L'), findsOneWidget); // la inicial del avatar
    });

    testWidgets('con nombres larguísimos y letra grande no revienta', (t) async {
      await montar(t, nombre: 'Maria de los Angeles Fernandez de la Cruz y Soto', escala: 1.4, avisos: 120, agotados: 1000);
      expect(t.takeException(), isNull);
    });
  });

  group('contraída', () {
    testWidgets('76 de ancho, solo íconos (sin nombres ni secciones)', (t) async {
      await montar(t, contraida: true, avisos: 4);
      expect(t.getSize(find.byType(BarraLateral)).width, AnchoBarra.contraida);
      expect(find.text('Sabor Manager'), findsNothing);
      expect(find.text('GENERAL'), findsNothing);
      expect(find.text('Rentabilidad'), findsNothing);
      // El contador rojo sí se ve; el nombre de cada lugar sale como ayuda al pasar el cursor.
      expect(find.text('4'), findsOneWidget);
      expect(find.byTooltip('Rentabilidad'), findsOneWidget);
      expect(find.byTooltip('Buscar'), findsOneWidget);
    });

    testWidgets('el contador ámbar de Despensa ya no cabe y se omite', (t) async {
      await montar(t, contraida: true, agotados: 9);
      expect(find.text('9'), findsNothing);
    });

    testWidgets('se puede tocar igual', (t) async {
      Destino? tocado;
      await montar(t, contraida: true, onElegir: (d) => tocado = d);
      await t.tap(find.byTooltip('Propinas'));
      expect(tocado, Destino.propinas);
    });
  });

  group('botón de contraer', () {
    testWidgets('dice qué hará y avisa', (t) async {
      var toques = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: BotonContraer(contraida: false, onTap: () => toques++)))));
      expect(find.byTooltip('Contraer menú'), findsOneWidget);
      await t.tap(find.byType(BotonContraer));
      expect(toques, 1);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: BotonContraer(contraida: true, onTap: () {})))));
      expect(find.byTooltip('Expandir menú'), findsOneWidget);
    });
  });

  group('en modo oscuro', () {
    testWidgets('también se arma sin errores', (t) async {
      TemaManager.instancia.ponerSinGuardar(ThemeMode.dark);
      await montar(t, avisos: 2, puntos: {Destino.cancelados});
      expect(find.text('Sabor Manager'), findsOneWidget);
    });
  });

  test('inicialDe y textoSucursales', () {
    expect(inicialDe('luis'), 'L');
    expect(inicialDe('  ana'), 'A');
    expect(inicialDe(''), '?');
    expect(inicialDe(null), '?');
    expect(textoSucursales(1), '1 sucursal');
    expect(textoSucursales(2), '2 sucursales');
  });
}
