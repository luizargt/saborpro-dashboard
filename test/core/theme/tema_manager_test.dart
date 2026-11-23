import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/theme/paleta.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/main.dart' show temaDeManager;
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claro por defecto; oscuro si se elige. Los colores de las pantallas salen de la
/// paleta puesta, y lo elegido se guarda.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TemaManager.instancia.ponerSinGuardar(ThemeMode.light);
  });
  tearDownAll(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  group('por defecto es claro', () {
    test('sin nada guardado, claro', () async {
      TemaManager.instancia.ponerSinGuardar(ThemeMode.dark);
      await TemaManager.instancia.cargar();
      expect(TemaManager.instancia.modo, ThemeMode.light);
      expect(TemaManager.instancia.oscuro, isFalse);
      expect(paletaActual.esOscura, isFalse);
    });

    test('aunque el teléfono esté en oscuro: no se mira el sistema', () async {
      TestWidgetsFlutterBinding.instance.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue);
      await TemaManager.instancia.cargar();
      expect(TemaManager.instancia.modo, ThemeMode.light);
    });

    test('un valor guardado que no entiende, claro', () async {
      SharedPreferences.setMockInitialValues({'manager_tema': 'quien-sabe'});
      await TemaManager.instancia.cargar();
      expect(TemaManager.instancia.modo, ThemeMode.light);
    });
  });

  group('lo que se elige se guarda', () {
    test('oscuro se guarda y vuelve igual al abrir la app', () async {
      await TemaManager.instancia.poner(ThemeMode.dark);
      expect(TemaManager.instancia.oscuro, isTrue);
      expect((await SharedPreferences.getInstance()).getString('manager_tema'), 'oscuro');

      TemaManager.instancia.ponerSinGuardar(ThemeMode.light); // "se cierra la app"
      await TemaManager.instancia.cargar();
      expect(TemaManager.instancia.modo, ThemeMode.dark);
      expect(paletaActual.esOscura, isTrue);
    });

    test('volver a claro también se guarda', () async {
      await TemaManager.instancia.poner(ThemeMode.dark);
      await TemaManager.instancia.poner(ThemeMode.light);
      expect((await SharedPreferences.getInstance()).getString('manager_tema'), 'claro');
      TemaManager.instancia.ponerSinGuardar(ThemeMode.dark);
      await TemaManager.instancia.cargar();
      expect(TemaManager.instancia.modo, ThemeMode.light);
    });

    test('elegir el mismo modo no avisa a nadie', () async {
      var avisos = 0;
      void a() => avisos++;
      TemaManager.instancia.addListener(a);
      addTearDown(() => TemaManager.instancia.removeListener(a));
      await TemaManager.instancia.poner(ThemeMode.light);
      expect(avisos, 0);
      await TemaManager.instancia.poner(ThemeMode.dark);
      expect(avisos, 1);
    });

    test('"automático" no existe: cualquier otra cosa queda en claro', () async {
      await TemaManager.instancia.poner(ThemeMode.system);
      expect(TemaManager.instancia.modo, ThemeMode.light);
    });
  });

  group('los colores de las pantallas siguen a la paleta', () {
    test('claro: los del diseño', () {
      expect(InicioColores.card, const Color(0xFFFFFFFF));
      expect(InicioColores.ink, const Color(0xFF16131F));
      expect(InicioColores.accent, const Color(0xFF6C3BF5));
      expect(InicioColores.bad, const Color(0xFFC8372D));
      expect(InicioColores.gift, const Color(0xFF0F8F74));
      expect(InicioColores.exp, const Color(0xFFD9542B));
      expect(kInicioBg, const Color(0xFFEEF1F5));
    });

    test('oscuro: los que ya usaba el Manager', () async {
      await TemaManager.instancia.poner(ThemeMode.dark);
      expect(InicioColores.card, const Color(0xFF1A1F2E));
      expect(InicioColores.ink, const Color(0xFFEEF0F6));
      expect(InicioColores.accent, const Color(0xFF9B7BFF));
      expect(InicioColores.bad, const Color(0xFFFF7A6E));
      expect(InicioColores.gift, const Color(0xFF4FD1B0));
      expect(InicioColores.exp, const Color(0xFFFF8A5C));
      expect(kInicioBg, const Color(0xFF0E1220));
    });

    test('cada color tiene su par: ninguno igual entre claro y oscuro (salvo el texto sobre morado)', () {
      const c = Paleta.clara;
      const o = Paleta.oscura;
      final pares = {
        'bg': (c.bg, o.bg), 'card': (c.card, o.card), 'subtle': (c.subtle, o.subtle), 'line': (c.line, o.line),
        'ink': (c.ink, o.ink), 'muted': (c.muted, o.muted), 'soft': (c.soft, o.soft), 'accent': (c.accent, o.accent),
        'tint': (c.tint, o.tint), 'ok': (c.ok, o.ok), 'warn': (c.warn, o.warn), 'bad': (c.bad, o.bad),
        'exp': (c.exp, o.exp), 'blue': (c.blue, o.blue),
      };
      pares.forEach((k, v) => expect(v.$1 == v.$2, isFalse, reason: k));
      expect(c.onAccent, o.onAccent);
    });

    test('el texto principal se lee sobre la tarjeta en las dos (contraste mínimo 7:1)', () {
      double lum(Color x) => x.computeLuminance();
      double contraste(Color a, Color b) {
        final la = lum(a), lb = lum(b);
        return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
      }

      for (final p in [Paleta.clara, Paleta.oscura]) {
        expect(contraste(p.ink, p.card), greaterThan(7), reason: '${p.brillo}');
        expect(contraste(p.ink, p.bg), greaterThan(7), reason: '${p.brillo}');
        expect(contraste(p.muted, p.card), greaterThan(4.5), reason: '${p.brillo}');
      }
      // Blanco sobre el morado de un botón: en claro pasa el mínimo del texto normal; en
      // oscuro (el morado es más claro, como en el diseño) llega al del texto grande y en negrita.
      expect(contraste(Paleta.clara.onAccent, Paleta.clara.accent), greaterThan(4.5));
      expect(contraste(Paleta.oscura.onAccent, Paleta.oscura.accent), greaterThan(3));
    });
  });

  group('al cambiar de modo se repinta lo que ya está en pantalla', () {
    testWidgets('una tarjeta con la paleta toma los colores nuevos sin perder su estado', (tester) async {
      final contador = ValueNotifier(0);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: contador,
            builder: (_, n, __) => Container(
              key: const Key('tarjeta'),
              color: InicioColores.card,
              child: Text('toques: $n', style: TextStyle(color: InicioColores.ink)),
            ),
          ),
        ),
      ));
      Color? fondo() => tester.widget<Container>(find.byKey(const Key('tarjeta'))).color;
      expect(fondo(), const Color(0xFFFFFFFF));

      contador.value = 3; // el estado de la pantalla no se pierde al cambiar de modo
      await tester.pump();
      await TemaManager.instancia.poner(ThemeMode.dark);
      await tester.pump();

      expect(fondo(), const Color(0xFF1A1F2E), reason: 'se repintó con la paleta oscura');
      expect(find.text('toques: 3'), findsOneWidget);
      final texto = tester.widget<Text>(find.text('toques: 3'));
      expect(texto.style!.color, const Color(0xFFEEF0F6));

      await TemaManager.instancia.poner(ThemeMode.light);
      await tester.pump();
      expect(fondo(), const Color(0xFFFFFFFF));
    });
  });

  group('el ThemeData de Material', () {
    test('claro y oscuro con su paleta', () {
      final c = temaDeManager(Paleta.clara);
      final o = temaDeManager(Paleta.oscura);
      expect(c.brightness, Brightness.light);
      expect(o.brightness, Brightness.dark);
      expect(c.scaffoldBackgroundColor, Paleta.clara.bg);
      expect(o.scaffoldBackgroundColor, Paleta.oscura.bg);
      expect(c.colorScheme.primary, Paleta.clara.accent);
      expect(o.colorScheme.surface, Paleta.oscura.card);
    });

    test('la barra de estado: iconos oscuros sobre claro y claros sobre oscuro', () async {
      expect(TemaManager.instancia.barraDeEstado.statusBarIconBrightness, Brightness.dark);
      await TemaManager.instancia.poner(ThemeMode.dark);
      expect(TemaManager.instancia.barraDeEstado.statusBarIconBrightness, Brightness.light);
    });
  });
}
