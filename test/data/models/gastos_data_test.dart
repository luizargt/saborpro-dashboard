import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/gastos_data.dart';

/// Las compras, los gastos y los análisis de Gastos. Los números salen del diseño
/// (gastos.html) y de casos chicos que se comprueban a mano.
void main() {
  Map<String, dynamic> linea(String nombre, double cantidad, double precio, {String unidad = 'u', Map<String, dynamic> extra = const {}}) => {
        'ingredient_name': nombre,
        'received_quantity': cantidad,
        'unit_price': precio,
        'unit_abbreviation': unidad,
        ...extra,
      };

  Map<String, dynamic> orden(
    int numero,
    String? proveedor,
    String fecha,
    List<Map<String, dynamic>> items, {
    double? total,
    String sucursal = 'ch',
  }) =>
      {
        'order_number': numero,
        if (proveedor != null) 'supplier_name': proveedor,
        'received_at': fecha,
        'location_id': sucursal,
        'items': items,
        'total': total ?? items.fold<double>(0, (s, i) => s + (i['received_quantity'] as double) * (i['unit_price'] as double)),
      };

  group('una línea de compra', () {
    test('cantidad por precio, y cómo se lee la cantidad', () {
      final l = LineaCompra.desde(linea('Limones', 25, 0.9984))!;
      expect(l.insumo, 'Limones');
      expect(l.cantidad, 25);
      expect(l.costo, closeTo(24.96, 1e-9));
      expect(l.precio, 0.9984);
      expect(l.cantidadTexto, '25 u');
    });

    test('el precio real pagado manda sobre el pedido', () {
      final l = LineaCompra.desde(linea('Hielo', 4, 15, extra: {'actual_unit_price': 14}))!;
      expect(l.precio, 14);
      expect(l.costo, 56);
    });

    test('lo pagado (total_pagado) es el costo, y de ahí sale el precio si faltaba', () {
      final l = LineaCompra.desde({'ingredient_name': 'Carne', 'received_quantity': 12.0, 'total_pagado': 619.94, 'unit_abbreviation': 'lb'})!;
      expect(l.costo, 619.94);
      expect(l.precio, closeTo(51.66, 0.01));
    });

    test('lo que no se consiguió no cuenta', () {
      expect(LineaCompra.desde(linea('Aguacate', 10, 5, extra: {'no_conseguido': true})), isNull);
    });

    test('sin nombre o sin forma de mapa, nada; con datos de otro tipo no lanza', () {
      expect(LineaCompra.desde('x'), isNull);
      expect(LineaCompra.desde({'received_quantity': 3}), isNull);
      expect(() => LineaCompra.desde({'ingredient_name': 5, 'received_quantity': 'x', 'unit_price': [], 'unit_abbreviation': 3}), returnsNormally);
      final t = LineaCompra.desde({'ingredient_name': 'Sal', 'received_quantity': '3', 'unit_price': '2.5'})!;
      expect(t.costo, 7.5);
    });

    test('sin lo recibido usa lo pedido', () {
      final l = LineaCompra.desde({'ingredient_name': 'Sal', 'requested_quantity': 4.0, 'unit_price': 2.0})!;
      expect(l.cantidad, 4);
      expect(l.costo, 8);
    });
  });

  group('una compra', () {
    test('proveedor, número, fecha, sucursal y total; sin proveedor se llama así', () {
      final c = Compra.desde(orden(19074, 'Distribuidora La Ceiba S.A.', '2026-10-31T10:00:00', [linea('Hielo', 4, 15)], total: 1118.7), 0);
      expect(c.numero, 19074);
      expect(c.proveedor, 'Distribuidora La Ceiba S.A.');
      expect(c.nombre, 'Distribuidora La Ceiba S.A.');
      expect(c.total, 1118.7);
      expect(c.sucursal, 'ch');
      expect(c.fecha, DateTime(2026, 10, 31, 10));
      final sin = Compra.desde(orden(5404, null, '2026-10-25T10:00:00', [linea('Carne', 12, 51)]), 1);
      expect(sin.proveedor, isNull);
      expect(sin.nombre, 'Sin proveedor');
    });

    test('un proveedor en blanco es "sin proveedor"; datos raros no lanzan', () {
      expect(Compra.desde({'supplier_name': '   ', 'total': 5}, 0).proveedor, isNull);
      expect(() => Compra.desde({'order_number': 'x', 'total': 'y', 'items': 5, 'received_at': 7, 'location_id': 3}, 0), returnsNormally);
    });

    test('la llave no se repite entre compras sin número ni entre sucursales', () {
      final a = Compra.desde({'location_id': 'ch', 'total': 1}, 0);
      final b = Compra.desde({'location_id': 'ch', 'total': 1}, 1);
      final c = Compra.desde({'location_id': 'sr', 'order_number': 7, 'total': 1}, 0);
      final d = Compra.desde({'location_id': 'ch', 'order_number': 7, 'total': 1}, 0);
      expect({a.llave, b.llave, c.llave, d.llave}, hasLength(4));
    });
  });

  group('los gastos del período', () {
    final gastos = <Map<String, dynamic>>[
      {'amount': 100, 'description': 'Gas', 'category_name': 'Servicios', 'date': '2026-10-20T10:00:00', 'location_id': 'ch', 'registered_by': 'Ana'},
      {'amount': '50', 'category_name': 'Limpieza', 'date': '2026-10-22T10:00:00', 'location_id': 'sr'},
      {'amount': 45.0, 'description': 'Hielo', 'category_name': 'Insumos', 'date': '2026-10-21T10:00:00', 'location_id': 'ch', 'source': 'cashRegister', 'register_id': 'cr1', 'register_user': 'Juan'},
    ];
    final compras = [
      orden(1, 'A', '2026-10-25T10:00:00', [linea('X', 10, 10)], total: 100),
      orden(2, null, '2026-10-26T10:00:00', [linea('Y', 1, 20)], total: 20, sucursal: 'sr'),
    ];
    final p = GastosPeriodo.desde(compras, gastos);

    test('separa compras, gastos manuales y retiros de caja', () {
      expect(p.compras, hasLength(2));
      expect(p.manuales, hasLength(2));
      expect(p.retiros, hasLength(1));
      expect(p.retiros.single.cajero, 'Juan');
      expect(p.retiros.single.idCaja, 'cr1');
      expect(p.retiros.single.esRetiro, isTrue);
    });

    test('el total es todo junto, y cada parte por separado', () {
      expect(p.totalCompras, 120);
      expect(p.totalManuales, 150);
      expect(p.totalRetiros, 45);
      expect(p.total, 315);
      expect(p.cuantos, 5);
      expect(p.hayAlgo, isTrue);
      expect(GastosPeriodo.vacio.total, 0);
      expect(GastosPeriodo.vacio.hayAlgo, isFalse);
    });

    test('lo gastado en cada sucursal suma el total', () {
      expect(p.totalEn('ch'), 100 + 100 + 45);
      expect(p.totalEn('sr'), 20 + 50);
      expect(p.totalEn('ch') + p.totalEn('sr'), p.total);
      expect(p.totalEn('otra'), 0);
    });

    test('del más reciente al más antiguo; el concepto es la descripción o la categoría', () {
      expect(p.compras.map((c) => c.numero), [2, 1]);
      expect(p.manuales.map((g) => g.concepto), ['Limpieza', 'Gas']);
      expect(p.manuales.last.usuario, 'Ana');
    });

    test('un gasto con datos raros no lanza', () {
      expect(() => GastosPeriodo.desde(const [], [{'amount': [], 'description': 5, 'category_name': 7, 'date': 3}]), returnsNormally);
    });
  });

  group('el cambio contra el período anterior', () {
    test('sube, baja, y sin con qué comparar no hay', () {
      expect(cambioPct(1200, 1000), 20);
      expect(cambioPct(800, 1000), -20);
      expect(cambioPct(1000, 1000), 0);
      expect(cambioPct(100, 0), isNull);
      expect(cambioPct(100, null), isNull);
    });
  });

  group('gastos contra ventas', () {
    test('cuántos de cada 100 vendidos se fueron; sin ventas no se dice', () {
      expect(AnalisisGastos.deCada100(1000, 4000), 25);
      expect(AnalisisGastos.deCada100(1234, 5600), 22);
      expect(AnalisisGastos.deCada100(100, 0), isNull);
      expect(AnalisisGastos.deCada100(100, null), isNull);
    });
  });

  group('sin proveedor', () {
    test('cuántas compras y cuánto', () {
      final cs = [
        Compra.desde(orden(1, null, '2026-10-25T10:00:00', const [], total: 619.94), 0),
        Compra.desde(orden(2, 'A', '2026-10-25T10:00:00', const [], total: 100), 1),
        Compra.desde(orden(3, null, '2026-10-25T10:00:00', const [], total: 75.38), 2),
      ];
      final (n, total) = AnalisisGastos.sinProveedor(cs);
      expect(n, 2);
      expect(total, closeTo(695.32, 1e-9));
      expect(AnalisisGastos.sinProveedor(const []), (0, 0.0));
    });
  });

  group('en qué se va el dinero y a quién se le compra', () {
    final cs = [
      Compra.desde(orden(1, 'La Ceiba', '2026-10-31T10:00:00', [linea('Hielo', 4, 15), linea('Gallo', 72, 7.5)]), 0),
      Compra.desde(orden(2, 'La Ceiba', '2026-10-13T10:00:00', [linea('hielo ', 6, 14), linea('Monte Carlo', 24, 6.6)]), 1),
      Compra.desde(orden(3, null, '2026-10-20T10:00:00', [linea('Cebolla', 5, 5)]), 2),
    ];

    test('los insumos de mayor a menor, juntando el mismo nombre escrito distinto', () {
      final t = AnalisisGastos.topInsumos(cs);
      expect(t.map((e) => e.$1), ['Gallo', 'Monte Carlo', 'Hielo', 'Cebolla']);
      expect(t[0].$2, 540);
      expect(t[2].$2, closeTo(60 + 84, 1e-9), reason: 'Hielo y "hielo " son el mismo');
      expect(AnalisisGastos.topInsumos(cs, n: 2), hasLength(2));
    });

    test('los proveedores de mayor a menor, con "Sin proveedor"', () {
      final t = AnalisisGastos.topProveedores(cs);
      expect(t.first.$1, 'La Ceiba');
      expect(t.last, ('Sin proveedor', 25.0));
      expect(t, hasLength(2));
    });

    test('sin compras, listas vacías', () {
      expect(AnalisisGastos.topInsumos(const []), isEmpty);
      expect(AnalisisGastos.topProveedores(const []), isEmpty);
    });
  });

  group('lo que subió de precio', () {
    Compra c(String insumo, double precio, String fecha, {String prov = 'La Ceiba', int n = 1}) =>
        Compra.desde(orden(n, prov, fecha, [linea(insumo, 10, precio)]), n);

    test('la compra más reciente del período contra la anterior del mismo insumo y proveedor', () {
      final r = AnalisisGastos.subieron(
        [c('Hielo', 15, '2026-10-31T10:00:00')],
        [c('Hielo', 14, '2026-09-15T10:00:00', n: 2)],
      );
      expect(r, hasLength(1));
      expect(r.single.insumo, 'Hielo');
      expect(r.single.anterior, 14);
      expect(r.single.nuevo, 15);
      expect(r.single.pct, 7);
    });

    test('también dentro del mismo período; lo que bajó o quedó igual no sale', () {
      final r = AnalisisGastos.subieron([
        c('Hielo', 14, '2026-10-01T10:00:00', n: 1),
        c('Hielo', 15, '2026-10-20T10:00:00', n: 2),
        c('Gallo', 7.5, '2026-10-01T10:00:00', n: 3),
        c('Gallo', 7.2, '2026-10-20T10:00:00', n: 4),
        c('Sal', 2, '2026-10-01T10:00:00', n: 5),
        c('Sal', 2, '2026-10-20T10:00:00', n: 6),
      ], const []);
      expect(r.map((e) => e.insumo), ['Hielo']);
    });

    test('de lo que más subió a lo que menos, y con otro proveedor no se compara', () {
      final r = AnalisisGastos.subieron(
        [
          c('Carne', 51.66, '2026-10-25T10:00:00', prov: 'Sin proveedor', n: 1),
          c('Pepsi', 6.5, '2026-10-25T10:00:00', prov: 'Mariposa', n: 2),
          c('Hielo', 15, '2026-10-25T10:00:00', prov: 'Otro', n: 3),
        ],
        [
          c('Carne', 48, '2026-09-25T10:00:00', prov: 'Sin proveedor', n: 4),
          c('Pepsi', 6.25, '2026-09-25T10:00:00', prov: 'Mariposa', n: 5),
          c('Hielo', 5, '2026-09-25T10:00:00', prov: 'La Ceiba', n: 6),
        ],
      );
      expect(r.map((e) => (e.insumo, e.pct)), [('Carne', 8), ('Pepsi', 4)]);
    });

    test('sin historial no hay con qué comparar; una compra vieja no cuenta como del período', () {
      expect(AnalisisGastos.subieron([c('Hielo', 15, '2026-10-31T10:00:00')], const []), isEmpty);
      // La última compra es del período anterior: no se muestra como "subió este mes".
      expect(AnalisisGastos.subieron([c('Hielo', 14, '2026-10-01T10:00:00')], [c('Hielo', 15, '2026-11-30T10:00:00', n: 2)]), isEmpty);
    });
  });

  group('el mismo insumo a distinto precio', () {
    Compra c(int n, String? prov, String insumo, double cant, double precio, {String fecha = '2026-10-10T10:00:00'}) =>
        Compra.desde(orden(n, prov, fecha, [linea(insumo, cant, precio)]), n);

    test('con quién sale más barato y cuánto se ahorraba con lo que se compró al más caro', () {
      final r = AnalisisGastos.comparar([
        c(1, 'Atlántida', 'Agua Pura 600 ml', 24, 3.6),
        c(2, 'La Mariposa', 'Agua Pura 600 ml', 24, 4.0),
      ]);
      expect(r, hasLength(1));
      expect(r.single.mejor, 'Atlántida');
      expect(r.single.precioMejor, 3.6);
      expect(r.single.otro, 'La Mariposa');
      expect(r.single.precioOtro, 4.0);
      expect(r.single.cantidad, '24 u');
      expect(r.single.ahorro, closeTo(9.6, 1e-9));
    });

    test('"Sin proveedor" también es una opción, y el último precio de cada uno es el que vale', () {
      final r = AnalisisGastos.comparar([
        c(1, 'La Ceiba', 'Hielo', 12, 20, fecha: '2026-10-01T10:00:00'),
        c(2, 'La Ceiba', 'Hielo', 12, 14, fecha: '2026-10-20T10:00:00'),
        c(3, null, 'hielo', 12, 15, fecha: '2026-10-10T10:00:00'),
      ]);
      expect(r.single.mejor, 'La Ceiba');
      expect(r.single.otro, 'Sin proveedor');
      expect(r.single.ahorro, closeTo(12, 1e-9));
    });

    test('un solo proveedor o el mismo precio no es nada que comparar; de mayor a menor ahorro', () {
      expect(AnalisisGastos.comparar([c(1, 'A', 'Sal', 5, 2), c(2, 'A', 'Sal', 5, 3)]), isEmpty);
      expect(AnalisisGastos.comparar([c(1, 'A', 'Sal', 5, 2), c(2, 'B', 'Sal', 5, 2)]), isEmpty);
      final r = AnalisisGastos.comparar([
        c(1, 'A', 'Poco', 2, 1), c(2, 'B', 'Poco', 2, 2),
        c(3, 'A', 'Mucho', 100, 1), c(4, 'B', 'Mucho', 100, 2),
      ]);
      expect(r.map((e) => e.insumo), ['Mucho', 'Poco']);
    });
  });

  group('la búsqueda', () {
    final cs = [
      Compra.desde(orden(19074, 'Distribuidora La Ceiba S.A.', '2026-10-31T10:00:00', [linea('Gallo Normal Lata', 72, 7.5), linea('Hielo', 4, 15)]), 0),
      Compra.desde(orden(5404, null, '2026-10-25T10:00:00', [linea('Carne de res', 12, 51.66)]), 1),
      Compra.desde(orden(15128, 'Mariposa', '2026-10-25T10:00:00', [linea('Pepsi', 24, 6.5)]), 2),
    ];

    test('sin búsqueda, todas, sin detalle', () {
      final r = AnalisisGastos.buscar(cs, '  ');
      expect(r, hasLength(3));
      expect(r.every((e) => e.lineas == null), isTrue);
    });

    test('por proveedor, sin acentos ni mayúsculas', () {
      expect(AnalisisGastos.buscar(cs, 'CEIBA').map((e) => e.compra.numero), [19074]);
      expect(AnalisisGastos.buscar(cs, 'sin proveedor').map((e) => e.compra.numero), [5404]);
    });

    test('por número, con o sin "#"', () {
      expect(AnalisisGastos.buscar(cs, '#5404').map((e) => e.compra.numero), [5404]);
      expect(AnalisisGastos.buscar(cs, '15128').map((e) => e.compra.numero), [15128]);
    });

    test('por insumo: trae la compra y cuáles insumos coinciden', () {
      final r = AnalisisGastos.buscar(cs, 'hielo');
      expect(r, hasLength(1));
      expect(r.single.compra.numero, 19074);
      expect(r.single.lineas!.map((l) => l.insumo), ['Hielo']);
    });

    test('sin coincidencias, nada', () {
      expect(AnalisisGastos.buscar(cs, 'zzz'), isEmpty);
    });

    test('los gastos por concepto, categoría, quién los registró o el cajero', () {
      final g = GastosPeriodo.desde(const [], [
        {'amount': 1, 'description': 'Compra de hielo', 'category_name': 'Insumos', 'registered_by': 'Juan', 'date': '2026-10-01T00:00:00'},
        {'amount': 2, 'category_name': 'Servicios', 'date': '2026-10-02T00:00:00'},
        {'amount': 3, 'description': 'Retiro', 'category_name': 'Otros', 'source': 'cashRegister', 'register_user': 'Marta', 'date': '2026-10-03T00:00:00'},
      ]);
      expect(AnalisisGastos.buscarGastos(g.manuales, 'hielo'), hasLength(1));
      expect(AnalisisGastos.buscarGastos(g.manuales, 'JUAN'), hasLength(1));
      expect(AnalisisGastos.buscarGastos(g.manuales, 'servicios'), hasLength(1));
      expect(AnalisisGastos.buscarGastos(g.retiros, 'marta'), hasLength(1));
      expect(AnalisisGastos.buscarGastos(g.manuales, ''), hasLength(2));
    });
  });

  test('claveDe: sin acentos, mayúsculas ni espacios de más', () {
    expect(claveDe('  Compañía  de   JARABES  '), 'compania de jarabes');
    expect(claveDe('Jalapeño'), 'jalapeno');
    expect(claveDe('Coca-Cola 600 ml'), 'coca-cola 600 ml');
  });
}
