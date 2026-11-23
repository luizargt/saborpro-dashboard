import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/providers/notification_settings_provider.dart';

/// Las preferencias de avisos: el opt-out (ausente = encendido) y las dos horas
/// elegibles. Las llaves y los valores por defecto tienen que ser los mismos que
/// usan las Cloud Functions (saborpro_app/functions/notifications/).
class _Almacen implements AlmacenPreferenciasAvisos {
  Map<String, dynamic>? guardado;
  final escrituras = <(String, String, Object)>[];
  Object? falla;

  _Almacen([this.guardado]);

  @override
  Future<Map<String, dynamic>?> leer(String uid) async {
    if (falla != null) throw falla!;
    return guardado;
  }

  @override
  Future<void> guardar(String uid, String llave, Object valor) async {
    if (falla != null) throw falla!;
    escrituras.add((uid, llave, valor));
    (guardado ??= {})[llave] = valor;
  }
}

void main() {
  group('llaves', () {
    test('están los tres avisos nuevos y los cinco de siempre, sin repetir', () {
      expect(NotificationSettingsProvider.keys, [
        'cash_open',
        'cash_close',
        'yesterday_sales',
        'courtesy',
        'cancellation',
        'expense',
        'inventory_movement',
        'low_stock_summary',
      ]);
    });

    test('las horas de siempre: ventas 7, stock bajo 8', () {
      expect(NotificationSettingsProvider.horaPorDefecto['yesterday_sales_hour'], 7);
      expect(NotificationSettingsProvider.horaPorDefecto['low_stock_summary_hour'], 8);
      expect(NotificationSettingsProvider.horaDe['yesterday_sales'], 'yesterday_sales_hour');
      expect(NotificationSettingsProvider.horaDe['low_stock_summary'], 'low_stock_summary_hour');
    });
  });

  group('etiquetaDeHora', () {
    test('de madrugada a medianoche', () {
      expect(etiquetaDeHora(0), '12:00 a. m.');
      expect(etiquetaDeHora(7), '7:00 a. m.');
      expect(etiquetaDeHora(11), '11:00 a. m.');
      expect(etiquetaDeHora(12), '12:00 p. m.');
      expect(etiquetaDeHora(13), '1:00 p. m.');
      expect(etiquetaDeHora(23), '11:00 p. m.');
    });
  });

  group('lectura', () {
    test('sin nada guardado todo está ENCENDIDO y las horas son las de siempre', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen());
      // Antes de leer ya vale lo mismo (regla opt-out).
      expect(p.value('courtesy'), isTrue);
      await p.init('u1');
      for (final k in NotificationSettingsProvider.keys) {
        expect(p.value(k), isTrue, reason: k);
      }
      expect(p.hora('yesterday_sales_hour'), 7);
      expect(p.hora('low_stock_summary_hour'), 8);
      expect(p.initialized, isTrue);
      expect(p.loading, isFalse);
    });

    test('solo un false explícito apaga un aviso', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen({
        'courtesy': false,
        'cancellation': true,
        'yesterday_sales': null,
      }));
      await p.init('u1');
      expect(p.value('courtesy'), isFalse);
      expect(p.value('cancellation'), isTrue);
      expect(p.value('yesterday_sales'), isTrue, reason: 'null no es "no"');
      expect(p.value('cash_open'), isTrue);
    });

    test('lee las horas elegidas', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen({
        'yesterday_sales_hour': 6,
        'low_stock_summary_hour': 21,
      }));
      await p.init('u1');
      expect(p.hora('yesterday_sales_hour'), 6);
      expect(p.hora('low_stock_summary_hour'), 21);
    });

    test('0 (medianoche) y 23 son horas válidas', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen({
        'yesterday_sales_hour': 0,
        'low_stock_summary_hour': 23,
      }));
      await p.init('u1');
      expect(p.hora('yesterday_sales_hour'), 0);
      expect(p.hora('low_stock_summary_hour'), 23);
    });

    test('una hora mal escrita vale la de por defecto (igual que el servidor)', () async {
      for (final mala in <Object?>[24, -1, 7.5, '9', null, true]) {
        final p = NotificationSettingsProvider(almacen: _Almacen({
          'yesterday_sales_hour': mala,
          'low_stock_summary_hour': mala,
        }));
        await p.init('u1');
        expect(p.hora('yesterday_sales_hour'), 7, reason: '$mala');
        expect(p.hora('low_stock_summary_hour'), 8, reason: '$mala');
      }
    });

    test('una hora que Firestore devuelve como 7.0 es la hora 7', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen({'yesterday_sales_hour': 7.0, 'low_stock_summary_hour': 9.0}));
      await p.init('u1');
      expect(p.hora('yesterday_sales_hour'), 7);
      expect(p.hora('low_stock_summary_hour'), 9);
    });

    test('si no se puede leer, cae del lado seguro: todo encendido y horas de siempre', () async {
      final almacen = _Almacen()..falla = Exception('sin red');
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      expect(p.initialized, isTrue);
      expect(p.loading, isFalse);
      expect(p.value('courtesy'), isTrue);
      expect(p.hora('low_stock_summary_hour'), 8);
    });
  });

  group('interruptores', () {
    test('apagar uno lo guarda con su llave y no toca los demás', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      expect(await p.setValue('cancellation', false), isTrue);
      expect(p.value('cancellation'), isFalse);
      expect(almacen.escrituras, [('u1', 'cancellation', false)]);
      expect(p.value('courtesy'), isTrue);
    });

    test('si no se pudo guardar, vuelve al valor de antes y dice que falló', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      almacen.falla = Exception('permiso');
      expect(await p.setValue('courtesy', false), isFalse);
      expect(p.value('courtesy'), isTrue);
    });

    test('sin uid no se guarda y se revierte', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen());
      expect(await p.setValue('courtesy', false), isFalse);
      expect(p.value('courtesy'), isTrue);
    });
  });

  group('horas', () {
    test('cambiar la hora la guarda como número con su llave', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      expect(await p.setHora('yesterday_sales_hour', 21), isTrue);
      expect(p.hora('yesterday_sales_hour'), 21);
      expect(almacen.escrituras, [('u1', 'yesterday_sales_hour', 21)]);
      expect(p.hora('low_stock_summary_hour'), 8, reason: 'la otra hora no cambia');
    });

    test('la misma hora no escribe nada', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      expect(await p.setHora('low_stock_summary_hour', 8), isTrue);
      expect(almacen.escrituras, isEmpty);
    });

    test('0 y 23 se pueden guardar; 24 y -1 no', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      expect(await p.setHora('yesterday_sales_hour', 0), isTrue);
      expect(await p.setHora('yesterday_sales_hour', 23), isTrue);
      expect(await p.setHora('yesterday_sales_hour', 24), isFalse);
      expect(await p.setHora('yesterday_sales_hour', -1), isFalse);
      expect(p.hora('yesterday_sales_hour'), 23);
      expect(almacen.escrituras.map((e) => e.$3), [0, 23]);
    });

    test('una llave de hora que no existe no se guarda', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      expect(await p.setHora('cash_open_hour', 9), isFalse);
      expect(almacen.escrituras, isEmpty);
    });

    test('si no se pudo guardar, la hora vuelve a la de antes', () async {
      final almacen = _Almacen();
      final p = NotificationSettingsProvider(almacen: almacen);
      await p.init('u1');
      almacen.falla = Exception('permiso');
      expect(await p.setHora('yesterday_sales_hour', 10), isFalse);
      expect(p.hora('yesterday_sales_hour'), 7);
    });

    test('sin uid no se guarda y se revierte', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen());
      expect(await p.setHora('yesterday_sales_hour', 10), isFalse);
      expect(p.hora('yesterday_sales_hour'), 7);
    });

    test('avisa a quien escucha al cambiar la hora', () async {
      final p = NotificationSettingsProvider(almacen: _Almacen());
      await p.init('u1');
      var veces = 0;
      p.addListener(() => veces++);
      await p.setHora('low_stock_summary_hour', 12);
      expect(veces, greaterThanOrEqualTo(1));
    });
  });
}
