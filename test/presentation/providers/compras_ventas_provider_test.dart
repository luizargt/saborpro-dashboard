import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/presentation/providers/compras_ventas_provider.dart';

DateRange mes(int anio, int m) => DateRange(start: DateTime(anio, m, 1), end: DateTime(anio, m + 1, 0, 23, 59, 59), mode: PeriodMode.month);

class _Fuente implements FuenteComprasVentas {
  List<Map<String, dynamic>> fotos = [];
  List<DocLeido> ingredientes = [];
  List<DocLeido> categorias = [];
  List<DocLeido> sucursales = [];
  bool fallanSucursales = false;
  bool fallanFotos = false;
  bool fallanIngredientes = false;
  bool fallanCategorias = false;
  final pedidas = <List<String>>[];
  int lecturasDeIngredientes = 0;

  /// Para frenar la lectura de fotos y probar cargas que se pisan.
  Completer<List<Map<String, dynamic>>>? frenoFotos;

  @override
  Future<List<Map<String, dynamic>>> leerFotos(String tenantId, List<String> fechas) async {
    pedidas.add(fechas);
    if (frenoFotos != null) return frenoFotos!.future;
    if (fallanFotos) throw Exception('sin permiso');
    return fotos;
  }

  @override
  Future<List<DocLeido>> leerIngredientes(String tenantId) async {
    lecturasDeIngredientes++;
    if (fallanIngredientes) throw Exception('sin red');
    return ingredientes;
  }

  @override
  Future<List<DocLeido>> leerCategorias(String tenantId) async {
    if (fallanCategorias) throw Exception('sin red');
    return categorias;
  }

  @override
  Future<List<DocLeido>> leerSucursales(String tenantId) async {
    if (fallanSucursales) throw Exception('sin red');
    return sucursales;
  }
}

Map<String, dynamic> foto(String fecha, double total) => {
      'tenant_id': 't1',
      'fecha': fecha,
      'sucursales': {'A': {'total': total}},
    };

DocLeido ing(String id, Map<String, dynamic> d) => (id: id, datos: {'location_id': 'A', 'currentStock': 2, 'lastPurchasePrice': 10, 'active': true, 'name': id, ...d});

void main() {
  group('las fechas de las fotos de un mes', () {
    test('el día 1 y el día 1 del mes siguiente', () {
      expect(ComprasVentasProvider.fechasDeFoto(mes(2026, 10)), ['2026-10-01', '2026-11-01']);
    });

    test('en diciembre, el siguiente es enero del otro año', () {
      expect(ComprasVentasProvider.fechasDeFoto(mes(2026, 12)), ['2026-12-01', '2027-01-01']);
    });

    test('fuera de un mes no hay fotos que pedir', () {
      final dia = DateRange(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 5, 23, 59), mode: PeriodMode.day);
      expect(ComprasVentasProvider.fechasDeFoto(dia), isEmpty);
      expect(ComprasVentasProvider.aplica(dia), isFalse);
      expect(ComprasVentasProvider.aplica(mes(2026, 10)), isTrue);
    });
  });

  group('lo que lee', () {
    test('la foto del inicio y la del fin, cada una en su lugar', () async {
      final f = _Fuente()..fotos = [foto('2026-11-01', 900), foto('2026-10-01', 700)];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.inicio!.sucursales['A']!.total, 700);
      expect(p.fin!.sucursales['A']!.total, 900);
      expect(p.fotosLeidas, isTrue);
      expect(p.cargando, isFalse);
      expect(f.pedidas.single, ['2026-10-01', '2026-11-01']);
    });

    test('una foto de otra fecha o rota no se toma por buena', () async {
      final f = _Fuente()
        ..fotos = [
          foto('2026-09-01', 1),
          {'fecha': 'basura'},
          {'sucursales': {}},
          foto('2026-10-01', 700),
        ];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.inicio!.sucursales['A']!.total, 700);
      expect(p.fin, isNull);
    });

    test('sin fotos: lo demás se lee igual', () async {
      final p = ComprasVentasProvider(fuente: _Fuente()..ingredientes = [ing('i1', {})]);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.inicio, isNull);
      expect(p.fin, isNull);
      expect(p.fotosLeidas, isTrue);
      expect(p.vivo!.sucursales['A']!.total, 20);
    });

    test('la bodega de hoy y la categoría de cada ingrediente', () async {
      final f = _Fuente()
        ..ingredientes = [ing('i1', {'categoryId': 'c1'}), ing('i2', {'categoryId': 'c2', 'currentStock': 1, 'lastPurchasePrice': 5}), ing('i3', {})]
        ..categorias = [(id: 'c1', datos: {'name': 'Cerveza'}), (id: 'c2', datos: {'name': '  Carnes  '}), (id: 'c3', datos: {'name': ''})];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.categoriaDeIngrediente, {'i1': 'Cerveza', 'i2': 'Carnes'});
      expect(p.vivo!.sucursales['A']!.total, 20 + 5 + 20);
      final por = {for (final c in p.vivo!.sucursales['A']!.porCategoria) c.nombre: c.valor};
      expect(por['Cerveza'], 20);
      expect(por['Carnes'], 5);
      expect(por['Sin categoría'], 20);
      expect(p.vivoLeido, isTrue);
    });

    test('la bodega central se marca también en la de hoy (como en la foto del servidor)', () async {
      final f = _Fuente()
        ..ingredientes = [ing('i1', {}), ing('i2', {'location_id': 'CEN', 'currentStock': 100, 'lastPurchasePrice': 10})]
        ..sucursales = [
          (id: 'A', datos: {'name': 'Chiquimula'}),
          (id: 'CEN', datos: {'name': 'Centro de acopio', 'is_central_warehouse': true}),
        ];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.vivo!.sucursales['CEN']!.central, isTrue);
      expect(p.vivo!.sucursales['A']!.central, isFalse);
      expect(p.vivo!.sucursales['CEN']!.total, 1000);
    });

    test('si fallan las sucursales, la bodega de hoy se arma igual (sin saber cuál es la central)', () async {
      final f = _Fuente()
        ..fallanSucursales = true
        ..ingredientes = [ing('i1', {})];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.vivo!.sucursales['A']!.total, 20);
      expect(p.vivo!.sucursales['A']!.central, isFalse);
    });

    test('un ingrediente sin sucursal se ignora, no rompe', () async {
      final f = _Fuente()..ingredientes = [(id: 'x', datos: {'currentStock': 3}), ing('i1', {})];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.vivo!.sucursales.keys, ['A']);
    });
  });

  group('cuando algo falla', () {
    test('si fallan las fotos, la bodega de hoy y las categorías siguen', () async {
      final f = _Fuente()
        ..fallanFotos = true
        ..ingredientes = [ing('i1', {'categoryId': 'c1'})]
        ..categorias = [(id: 'c1', datos: {'name': 'Cerveza'})];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.inicio, isNull);
      expect(p.fin, isNull);
      // Ya se intentó (y falló): no es "todavía leyendo", o la tarjeta de la bodega
      // se quedaría en "Leyendo…" para siempre.
      expect(p.fotosLeidas, isTrue);
      expect(p.fotosFallaron, isTrue);
      expect(p.vivo!.sucursales['A']!.total, 20);
      expect(p.categoriaDeIngrediente, {'i1': 'Cerveza'});
      expect(p.cargando, isFalse);
    });

    test('si todo sale bien, las fotos no "fallaron"', () async {
      final p = ComprasVentasProvider(fuente: _Fuente());
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.fotosLeidas, isTrue);
      expect(p.fotosFallaron, isFalse);
    });

    test('recargar tras un fallo lo limpia si ahora sale bien', () async {
      final f = _Fuente()..fallanFotos = true;
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.fotosFallaron, isTrue);
      f
        ..fallanFotos = false
        ..fotos = [foto('2026-10-01', 700)];
      await p.recargar();
      expect(p.fotosFallaron, isFalse);
      expect(p.inicio!.sucursales['A']!.total, 700);
    });

    test('si fallan los ingredientes, las fotos siguen y no hay bodega de hoy', () async {
      final f = _Fuente()
        ..fallanIngredientes = true
        ..fotos = [foto('2026-10-01', 700)];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.inicio!.sucursales['A']!.total, 700);
      expect(p.vivo, isNull);
      expect(p.vivoLeido, isTrue);
      expect(p.categoriaDeIngrediente, isEmpty);
    });

    test('si fallan las categorías, igual hay bodega de hoy (todo "Sin categoría")', () async {
      final f = _Fuente()
        ..fallanCategorias = true
        ..ingredientes = [ing('i1', {'categoryId': 'c1'})];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.vivo!.sucursales['A']!.total, 20);
      expect(p.vivo!.sucursales['A']!.porCategoria.single.nombre, 'Sin categoría');
    });
  });

  group('cuándo vuelve a leer', () {
    test('la misma clave no relee; otro mes sí, y limpia lo del mes anterior', () async {
      final f = _Fuente()..fotos = [foto('2026-10-01', 700)];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(f.pedidas.length, 1);

      f.fotos = [foto('2026-09-01', 500)];
      await p.cargarSiHaceFalta('t1', mes(2026, 9));
      expect(f.pedidas.length, 2);
      expect(f.pedidas.last, ['2026-09-01', '2026-10-01']);
      expect(p.inicio!.sucursales['A']!.total, 500);
      expect(p.fin, isNull, reason: 'la foto del 1 de octubre ya no se pidió: no se queda la vieja');
    });

    test('recargar vuelve a leer lo mismo', () async {
      final f = _Fuente()..fotos = [foto('2026-10-01', 700)];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      f.fotos = [foto('2026-10-01', 777)];
      await p.recargar();
      expect(p.inicio!.sucursales['A']!.total, 777);
      expect(f.pedidas.length, 2);
    });

    test('recargar sin haber cargado nunca no hace nada', () async {
      final f = _Fuente();
      await ComprasVentasProvider(fuente: f).recargar();
      expect(f.pedidas, isEmpty);
    });

    test('otro negocio: lo del anterior no se queda', () async {
      final f = _Fuente()..ingredientes = [ing('i1', {})];
      final p = ComprasVentasProvider(fuente: f);
      await p.cargarSiHaceFalta('t1', mes(2026, 10));
      expect(p.vivo, isNotNull);
      f.fallanIngredientes = true;
      await p.cargarSiHaceFalta('t2', mes(2026, 10));
      expect(p.vivo, isNull, reason: 'las existencias de t1 no son de t2');
    });

    test('fuera de un mes pide cero fotos', () async {
      final f = _Fuente();
      final p = ComprasVentasProvider(fuente: f);
      final dia = DateRange(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 5, 23, 59), mode: PeriodMode.day);
      await p.cargarSiHaceFalta('t1', dia);
      expect(f.pedidas.single, isEmpty);
      expect(p.inicio, isNull);
    });

    test('una carga vieja que llega tarde no pisa a la nueva', () async {
      final freno = Completer<List<Map<String, dynamic>>>();
      final f = _Fuente()..frenoFotos = freno;
      final p = ComprasVentasProvider(fuente: f);
      final primera = p.cargarSiHaceFalta('t1', mes(2026, 10)); // se queda esperando las fotos
      await Future<void>.delayed(Duration.zero);

      f
        ..frenoFotos = null
        ..fotos = [foto('2026-09-01', 500)];
      await p.cargarSiHaceFalta('t1', mes(2026, 9));
      expect(p.inicio!.sucursales['A']!.total, 500);

      // Ahora llega la respuesta de octubre, ya vieja: no se toma.
      freno.complete([foto('2026-10-01', 700), foto('2026-09-01', 1)]);
      await primera;
      expect(p.inicio!.sucursales['A']!.total, 500);
      expect(p.fin, isNull);
    });
  });

  group('al salir de la pantalla', () {
    test('una carga en vuelo no avisa a un provider ya liberado', () async {
      final f = _Fuente()..frenoFotos = Completer();
      final p = ComprasVentasProvider(fuente: f);
      final carga = p.cargarSiHaceFalta('t1', mes(2026, 10));
      await Future<void>.delayed(Duration.zero);
      p.dispose();
      f.frenoFotos!.complete([foto('2026-10-01', 1)]);
      await carga; // si avisara después de dispose, lanzaría
    });
  });
}
