import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/despensa_data.dart';
import 'package:saborpro_reports/data/models/inventory_data.dart';

/// El estado de cada ingrediente por los días que alcanza, lo que vale la despensa
/// y el orden en que se muestra. Los números de cada caso se comprueban a mano.
void main() {
  IngredientStock ing(
    String nombre, {
    Map<String, double> stock = const {},
    Map<String, double> dias = const {},
    Map<String, double> costo = const {},
    Map<String, Map<String, double>> consumo = const {},
    Map<String, double> minimo = const {},
  }) =>
      IngredientStock(
        name: nombre,
        unit: 'u',
        stockByLocation: stock,
        minStockByLocation: minimo,
        daysRemainingByLocation: dias,
        costByLocation: costo,
        consumptionByDayByLocation: consumo,
      );

  group('el estado por días', () {
    test('sin existencia en esa sucursal no hay estado (no se maneja)', () {
      expect(estadoPorDias(null, null), isNull);
      expect(estadoPorDias(null, 3), isNull);
    });

    test('sin nada, o con faltante, está agotado', () {
      expect(estadoPorDias(0, null), EstadoDespensa.agotado);
      expect(estadoPorDias(0, 30), EstadoDespensa.agotado);
      expect(estadoPorDias(-2, null), EstadoDespensa.agotado);
    });

    test('menos de 10 días es "pronto"; desde 10, bien', () {
      expect(estadoPorDias(5, 9.99), EstadoDespensa.pronto);
      expect(estadoPorDias(5, 0.2), EstadoDespensa.pronto);
      expect(estadoPorDias(5, 10), EstadoDespensa.bien);
      expect(estadoPorDias(5, 63), EstadoDespensa.bien);
    });

    test('sin consumo no se pueden calcular los días y no se da por pronto', () {
      expect(estadoPorDias(12, null), EstadoDespensa.bien);
    });

    test('el mínimo anotado ya no manda: con stock de sobra no avisa, con 3 días sí', () {
      final i = ing('X', stock: {'a': 100}, dias: {'a': 3}, minimo: {'a': 500});
      expect(FilaDespensa(i, const ['a']).peor, EstadoDespensa.pronto);
      final j = ing('Y', stock: {'a': 1}, dias: {'a': 400}, minimo: {'a': 500});
      expect(FilaDespensa(j, const ['a']).peor, EstadoDespensa.bien);
    });
  });

  group('cómo se lee', () {
    test('los días', () {
      expect(textoDias(999), '+180 días');
      expect(textoDias(181), '+180 días');
      expect(textoDias(180), '180 días');
      expect(textoDias(0.4), '<1 día');
      expect(textoDias(1), '1 día');
      expect(textoDias(1.4), '1 día');
      expect(textoDias(11.6), '12 días');
    });

    test('las cantidades, sin ceros de más', () {
      expect(textoCantidad(0), '0');
      expect(textoCantidad(12), '12');
      expect(textoCantidad(12.5), '12.5');
      expect(textoCantidad(0.25), '0.25');
      expect(textoCantidad(1.999), '2');
      expect(textoCantidad(1.004), '1');
    });
  });

  group('una fila (un ingrediente en las sucursales que se ven)', () {
    final coca = ing(
      'Coca Cola Lata',
      stock: {'ch': 8, 'sr': 20},
      dias: {'ch': 4, 'sr': 30},
      costo: {'ch': 5.8, 'sr': 5.8},
    );

    test('lo que hay, el peor estado y los menos días', () {
      final f = FilaDespensa(coca, const ['ch', 'sr']);
      expect(f.total, 28);
      expect(f.peor, EstadoDespensa.pronto, reason: 'en Chiquimula se acaba en 4 días');
      expect(f.minDias, 4);
      expect(f.celda('ch')!.estado, EstadoDespensa.pronto);
      expect(f.celda('sr')!.estado, EstadoDespensa.bien);
      expect(f.celda('otra'), isNull);
    });

    test('con una sola sucursal a la vista, solo cuenta esa', () {
      final f = FilaDespensa(coca, const ['sr']);
      expect(f.total, 20);
      expect(f.peor, EstadoDespensa.bien);
      expect(f.minDias, 30);
    });

    test('agotado en una sucursal manda sobre todo lo demás', () {
      final i = ing('X', stock: {'a': 0, 'b': 50}, dias: {'b': 2});
      expect(FilaDespensa(i, const ['a', 'b']).peor, EstadoDespensa.agotado);
    });

    test('sin existencia en las sucursales que se ven, no tiene estado', () {
      final f = FilaDespensa(coca, const ['otra']);
      expect(f.peor, isNull);
      expect(f.total, 0);
      expect(f.minDias, isNull);
    });

    test('cuánto vale: existencia por último precio de compra', () {
      final f = FilaDespensa(coca, const ['ch', 'sr']);
      expect(f.valor, closeTo(8 * 5.8 + 20 * 5.8, 1e-9));
      expect(f.valorEn('ch'), closeTo(46.4, 1e-9));
      expect(f.sinPrecio, isFalse);
    });

    test('si falta el precio de una sucursal con existencia, no se sabe cuánto vale (no se asume cero)', () {
      final i = ing('X', stock: {'a': 10, 'b': 5}, costo: {'a': 2});
      final f = FilaDespensa(i, const ['a', 'b']);
      expect(f.valor, isNull);
      expect(f.sinPrecio, isTrue);
      expect(f.valorEn('a'), 20);
      expect(f.valorEn('b'), isNull);
    });

    test('lo agotado vale cero y no necesita precio', () {
      final i = ing('X', stock: {'a': 0});
      final f = FilaDespensa(i, const ['a']);
      expect(f.valor, 0);
      expect(f.valorEn('a'), 0);
      expect(f.sinPrecio, isFalse);
    });

    test('sin precio pero sin existencia en esa sucursal, tampoco estorba', () {
      final i = ing('X', stock: {'a': 10, 'b': 0}, costo: {'a': 3});
      expect(FilaDespensa(i, const ['a', 'b']).valor, 30);
    });

    test('el consumo de un día y el de los siete', () {
      final i = ing('X', stock: {'a': 1, 'b': 1}, consumo: {
        'a': {'2026-11-20': 3, '2026-11-19': 2},
        'b': {'2026-11-20': 4},
      });
      final f = FilaDespensa(i, const ['a', 'b']);
      expect(f.consumoDia('2026-11-20'), 7);
      expect(f.consumo7(const ['2026-11-19', '2026-11-20']), 9);
      expect(FilaDespensa(i, const ['b']).consumo7(const ['2026-11-19', '2026-11-20']), 4);
    });
  });

  group('el resumen', () {
    final items = [
      ing('Agotado', stock: {'a': 0}, costo: {'a': 10}),
      ing('Pronto', stock: {'a': 4}, dias: {'a': 3}, costo: {'a': 10}),
      ing('Pronto 2', stock: {'a': 1}, dias: {'a': 9}, costo: {'a': 10}),
      ing('Bien', stock: {'a': 20}, dias: {'a': 40}, costo: {'a': 2.5}),
      ing('Sin precio', stock: {'a': 7}, dias: {'a': 50}),
      ing('Otra sucursal', stock: {'b': 5}, dias: {'b': 1}, costo: {'b': 100}),
    ];

    test('cuántos hay de cada estado y el dinero de la sucursal', () {
      final filas = Despensa.filas(items, const ['a']);
      expect(filas, hasLength(5), reason: 'el de la otra sucursal no entra');
      final r = ResumenDespensa.de(filas, const ['a']);
      expect(r.agotados, 1);
      expect(r.pronto, 2);
      expect(r.bien, 2);
      expect(r.total, 5);
      // 0 + 4×10 + 1×10 + 20×2.5; el que no tiene precio no entra.
      expect(r.valorPorSucursal['a'], 100);
      expect(r.sinPrecio, 1);
      expect(r.cuantos(EstadoDespensa.pronto), 2);
    });

    test('con las dos sucursales a la vista, el dinero de cada una por separado', () {
      final r = ResumenDespensa.de(Despensa.filas(items, const ['a', 'b']), const ['a', 'b']);
      expect(r.valorPorSucursal['a'], 100);
      expect(r.valorPorSucursal['b'], 500);
      expect(r.total, 6);
      expect(r.pronto, 3);
    });

    test('sin nada, ceros', () {
      final r = ResumenDespensa.de(const [], const ['a']);
      expect(r.total, 0);
      expect(r.valorPorSucursal['a'], 0);
      expect(r.sinPrecio, 0);
    });
  });

  group('el orden y los filtros', () {
    final items = [
      ing('Zanahoria', stock: {'a': 20}, dias: {'a': 40}),
      ing('Aguacate', stock: {'a': 20}, dias: {'a': 12}),
      ing('Big Mix', stock: {'a': 1}, dias: {'a': 2}),
      ing('Adrenalina', stock: {'a': 0}),
      ing('Bush Light', stock: {'a': 1}, dias: {'a': 9}),
      ing('Chip Sal', stock: {'a': 9}),
      ing('Cebolla', stock: {'a': 3}, dias: {'a': 2}),
    ];
    List<String> nombres(List<FilaDespensa> f) => [for (final x in f) x.item.name];

    test('lo más urgente primero: agotados, pronto (menos días antes), y bien; sin consumo al final del grupo', () {
      final o = Despensa.porUrgencia(Despensa.filas(items, const ['a']));
      expect(nombres(o), [
        'Adrenalina', // agotado
        'Big Mix', 'Cebolla', 'Bush Light', // pronto: 2 días (Big < Cebolla por nombre), 2, 9
        'Aguacate', 'Zanahoria', 'Chip Sal', // bien: 12, 40 y sin consumo al final
      ]);
    });

    test('filtra por estado y por búsqueda (sin importar mayúsculas ni espacios)', () {
      final filas = Despensa.filas(items, const ['a']);
      expect(nombres(Despensa.porUrgencia(filas, estado: EstadoDespensa.pronto)), ['Big Mix', 'Cebolla', 'Bush Light']);
      expect(nombres(Despensa.porUrgencia(filas, consulta: '  BIG ')), ['Big Mix']);
      expect(nombres(Despensa.porUrgencia(filas, consulta: 'a', estado: EstadoDespensa.agotado)), ['Adrenalina']);
      expect(Despensa.porUrgencia(filas, consulta: 'zzz'), isEmpty);
    });

    test('el consumo de 7 días: solo lo que se consumió, de mayor a menor', () {
      final dias = ['2026-11-19', '2026-11-20'];
      final conConsumo = [
        ing('Poco', stock: {'a': 1}, consumo: {'a': {'2026-11-19': 1}}),
        ing('Mucho', stock: {'a': 1}, consumo: {'a': {'2026-11-19': 5, '2026-11-20': 4}}),
        ing('Nada', stock: {'a': 1}),
        ing('Fuera de rango', stock: {'a': 1}, consumo: {'a': {'2026-10-01': 9}}),
      ];
      final o = Despensa.porConsumo(Despensa.filas(conConsumo, const ['a']), dias);
      expect(nombres(o), ['Mucho', 'Poco']);
      expect(nombres(Despensa.porConsumo(Despensa.filas(conConsumo, const ['a']), dias, consulta: 'poc')), ['Poco']);
    });

    test('la intensidad del consumo va de 8% a 50%', () {
      expect(Despensa.intensidad(0, 10), closeTo(0.08, 1e-9));
      expect(Despensa.intensidad(10, 10), closeTo(0.50, 1e-9));
      expect(Despensa.intensidad(5, 10), closeTo(0.29, 1e-9));
      expect(Despensa.intensidad(3, 0), closeTo(0.08, 1e-9), reason: 'sin máximo no divide por cero');
    });

    test('el mayor consumo de un día en la tabla', () {
      final i = [
        ing('A', stock: {'a': 1}, consumo: {'a': {'d1': 3, 'd2': 8}}),
        ing('B', stock: {'a': 1}, consumo: {'a': {'d1': 9}}),
      ];
      expect(Despensa.maximoDiario(Despensa.filas(i, const ['a']), const ['d1', 'd2']), 9);
      expect(Despensa.maximoDiario(const [], const ['d1']), 0);
    });
  });
}
