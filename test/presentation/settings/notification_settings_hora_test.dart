import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/providers/notification_settings_provider.dart';
import 'package:saborpro_reports/presentation/screens/settings/notification_settings_screen.dart';
import 'package:saborpro_reports/presentation/widgets/selector_hora_aviso.dart';

/// La fila de cada aviso en la pantalla de ajustes: el interruptor y, en los
/// avisos diarios, el botón con la hora y la hoja para cambiarla. (La pantalla
/// entera no se monta aquí: NotificationService toca Firebase al crearse.)
class _Almacen implements AlmacenPreferenciasAvisos {
  final Map<String, dynamic> datos;
  final escrituras = <(String, Object)>[];
  bool falla = false;
  _Almacen([Map<String, dynamic>? datos]) : datos = datos ?? {};

  @override
  Future<Map<String, dynamic>?> leer(String uid) async => datos;

  @override
  Future<void> guardar(String uid, String llave, Object valor) async {
    if (falla) throw Exception('sin permiso');
    escrituras.add((llave, valor));
    datos[llave] = valor;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  Future<NotificationSettingsProvider> montar(
    WidgetTester t,
    String llave,
    _Almacen almacen, {
    double ancho = 390,
    double escala = 1,
  }) async {
    t.view.physicalSize = Size(ancho, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final p = NotificationSettingsProvider(almacen: almacen);
    await p.init('u1');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(ancho, 1600), textScaler: TextScaler.linear(escala)),
          child: Scaffold(
            body: ListView(children: [
              FilaPreferencia(prefKey: llave, copy: NotificationSettingsScreen.copias[llave]!),
            ]),
          ),
        ),
      ),
    ));
    await t.pump();
    return p;
  }

  Finder boton(String texto) => find.text(texto);

  test('todas las llaves tienen su texto, y solo las de siempre y las nuevas', () {
    expect(NotificationSettingsScreen.copias.keys.toSet(), NotificationSettingsProvider.keys.toSet());
    for (final e in NotificationSettingsScreen.copias.entries) {
      expect(e.value.title.trim(), isNotEmpty, reason: e.key);
      expect(e.value.subtitle.trim(), isNotEmpty, reason: e.key);
    }
  });

  test('el subtítulo de stock bajo ya no promete las 8:00 (la hora se elige)', () {
    expect(NotificationSettingsScreen.copias['low_stock_summary']!.subtitle, isNot(contains('8:00')));
  });

  group('el botón de la hora', () {
    testWidgets('ventas de ayer: a las 7:00 a. m. por defecto', (t) async {
      await montar(t, 'yesterday_sales', _Almacen());
      expect(boton('A las 7:00 a. m.'), findsOneWidget);
    });

    testWidgets('stock bajo: a las 8:00 a. m. por defecto', (t) async {
      await montar(t, 'low_stock_summary', _Almacen());
      expect(boton('A las 8:00 a. m.'), findsOneWidget);
    });

    testWidgets('muestra la hora que el usuario ya eligió', (t) async {
      await montar(t, 'yesterday_sales', _Almacen({'yesterday_sales_hour': 21}));
      expect(boton('A las 9:00 p. m.'), findsOneWidget);
    });

    testWidgets('los avisos que no son diarios no traen botón de hora', (t) async {
      for (final k in ['cash_open', 'cash_close', 'courtesy', 'cancellation', 'expense', 'inventory_movement']) {
        await montar(t, k, _Almacen());
        expect(find.textContaining('A las '), findsNothing, reason: k);
      }
    });

    testWidgets('con el aviso apagado la hora se esconde', (t) async {
      await montar(t, 'yesterday_sales', _Almacen({'yesterday_sales': false}));
      expect(find.textContaining('A las '), findsNothing);
    });

    testWidgets('al apagar el interruptor la hora desaparece y al prenderlo vuelve', (t) async {
      await montar(t, 'yesterday_sales', _Almacen());
      expect(boton('A las 7:00 a. m.'), findsOneWidget);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(find.textContaining('A las '), findsNothing);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(boton('A las 7:00 a. m.'), findsOneWidget);
    });
  });

  group('elegir la hora', () {
    testWidgets('tocar el botón abre la hoja con las 24 horas y la actual marcada', (t) async {
      await montar(t, 'yesterday_sales', _Almacen());
      await t.tap(boton('A las 7:00 a. m.'));
      await t.pumpAndSettle();
      expect(find.text('¿A qué hora te avisamos?'), findsOneWidget);
      expect(find.textContaining('hora de Guatemala'), findsOneWidget);
      // 24 cuadros (más el botón de afuera, que dice "A las …").
      for (var h = 0; h < 24; h++) {
        expect(find.text(etiquetaDeHora(h)), findsOneWidget, reason: 'hora $h');
      }
    });

    testWidgets('abrir la hoja NO apaga el aviso (el toque es del botón, no de la fila)', (t) async {
      final almacen = _Almacen();
      final p = await montar(t, 'yesterday_sales', almacen);
      await t.tap(boton('A las 7:00 a. m.'));
      await t.pumpAndSettle();
      expect(p.value('yesterday_sales'), isTrue);
      expect(almacen.escrituras, isEmpty);
    });

    testWidgets('elegir una hora la guarda, cierra la hoja y actualiza el botón', (t) async {
      final almacen = _Almacen();
      final p = await montar(t, 'yesterday_sales', almacen);
      await t.tap(boton('A las 7:00 a. m.'));
      await t.pumpAndSettle();
      await t.tap(find.text('9:00 p. m.'));
      await t.pumpAndSettle();
      expect(almacen.escrituras, [('yesterday_sales_hour', 21)]);
      expect(p.hora('yesterday_sales_hour'), 21);
      expect(find.text('¿A qué hora te avisamos?'), findsNothing, reason: 'la hoja se cerró');
      expect(boton('A las 9:00 p. m.'), findsOneWidget);
    });

    testWidgets('la medianoche se puede elegir (hora 0)', (t) async {
      final almacen = _Almacen();
      await montar(t, 'low_stock_summary', almacen);
      await t.tap(boton('A las 8:00 a. m.'));
      await t.pumpAndSettle();
      await t.tap(find.text('12:00 a. m.'));
      await t.pumpAndSettle();
      expect(almacen.escrituras, [('low_stock_summary_hour', 0)]);
      expect(boton('A las 12:00 a. m.'), findsOneWidget);
    });

    testWidgets('elegir la hora de ventas no cambia la de stock bajo', (t) async {
      final almacen = _Almacen();
      final p = await montar(t, 'yesterday_sales', almacen);
      await t.tap(boton('A las 7:00 a. m.'));
      await t.pumpAndSettle();
      await t.tap(find.text('6:00 a. m.'));
      await t.pumpAndSettle();
      expect(p.hora('low_stock_summary_hour'), 8);
    });

    testWidgets('si no se pudo guardar, avisa y la hora queda como estaba', (t) async {
      final almacen = _Almacen();
      final p = await montar(t, 'yesterday_sales', almacen);
      almacen.falla = true;
      await t.tap(boton('A las 7:00 a. m.'));
      await t.pumpAndSettle();
      await t.tap(find.text('9:00 p. m.'));
      await t.pumpAndSettle();
      expect(find.text('No se pudo guardar el cambio. Intenta de nuevo.'), findsOneWidget);
      expect(p.hora('yesterday_sales_hour'), 7);
      expect(boton('A las 7:00 a. m.'), findsOneWidget);
    });

    testWidgets('cerrar la hoja sin elegir no cambia nada', (t) async {
      final almacen = _Almacen();
      await montar(t, 'yesterday_sales', almacen);
      await t.tap(boton('A las 7:00 a. m.'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(195, 20)); // el fondo oscuro de arriba
      await t.pumpAndSettle();
      expect(almacen.escrituras, isEmpty);
      expect(boton('A las 7:00 a. m.'), findsOneWidget);
    });
  });

  group('que quepa', () {
    for (final ancho in [320.0, 360.0, 390.0]) {
      testWidgets('la fila con hora cabe a $ancho con letra grande', (t) async {
        await montar(t, 'yesterday_sales', _Almacen({'yesterday_sales_hour': 23}), ancho: ancho, escala: 1.4);
        expect(t.takeException(), isNull);
      });

      testWidgets('la hoja de horas cabe a $ancho con letra grande', (t) async {
        await montar(t, 'low_stock_summary', _Almacen({'low_stock_summary_hour': 12}), ancho: ancho, escala: 1.4);
        await t.tap(find.textContaining('A las '));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('¿A qué hora te avisamos?'), findsOneWidget);
      });
    }
  });

  group('SelectorHoraAviso (solo)', () {
    testWidgets('marca la hora elegida como seleccionada', (t) async {
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectorHoraAviso(aviso: 'Ventas de ayer', actual: 7, onElegir: (_) {}),
          ),
        ),
      ));
      final seleccionados = t.widgetList<Semantics>(find.byType(Semantics)).where((s) => s.properties.selected == true).toList();
      expect(seleccionados, hasLength(1));
      expect(seleccionados.single.properties.label, '7:00 a. m.');
      expect(find.text('Ventas de ayer · hora de Guatemala'), findsOneWidget);
    });
  });
}
