import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/cortesias_data.dart';

/// Copia literal de cómo suma la tarjeta "Cortesías / Donaciones" del Inicio
/// (DashboardProvider._buildMetrics). El provider no se puede crear en un test
/// (levanta Firebase), así que el contrato vive aquí: si alguien cambia el
/// bucle de la tarjeta, tiene que cambiar esta copia y el reporte a la vez.
({double total, int count}) _comoLaTarjeta(List<Map<String, dynamic>> orders) {
  double courtesyTotal = 0;
  int courtesyCount = 0;
  for (final o in orders) {
    final items = o['items'];
    if (items is List) {
      var hasCourtesy = false;
      for (final item in items) {
        if (cuentaComoCortesia(item)) {
          courtesyTotal += valorCortesia(item as Map);
          hasCourtesy = true;
        }
      }
      if (hasCourtesy) courtesyCount++;
    }
  }
  return (total: courtesyTotal, count: courtesyCount);
}

/// La cuenta del POS escrita aparte, sin usar valorCortesia:
/// OrderItem.originalPrice = unitPrice * qty + modifiersPrice, con
/// modifiersPrice = suma de mod.price * mod.qty * qty.
double _comoElPos(Map<String, dynamic> item) {
  final qty = (item['qty'] as num? ?? 1).toDouble();
  final mods = (item['modifiers'] as List? ?? const [])
      .whereType<Map>()
      .fold<double>(
          0,
          (s, m) =>
              s +
              (m['price'] as num? ?? 0).toDouble() *
                  (m['qty'] as num? ?? 1).toDouble() *
                  qty);
  return (item['unit_price'] as num? ?? 0).toDouble() * qty + mods;
}

Map<String, dynamic> _item(
  String name, {
  num? qty = 1,
  num? price = 10,
  bool courtesy = true,
  bool voided = false,
  String? type = 'CORTESIA',
  String? reason,
  String? by,
  List<Object?>? mods,
}) =>
    {
      'name': name,
      if (mods != null) 'modifiers': mods,
      if (qty != null) 'qty': qty,
      if (price != null) 'unit_price': price,
      'is_courtesy': courtesy,
      'is_void': voided,
      if (courtesy && type != null) 'courtesy_type': type,
      if (reason != null) 'courtesy_reason': reason,
      if (by != null) 'courtesy_by_user_id': by,
    };

Map<String, dynamic> _orden(
  String id,
  List<Object?> items, {
  Object? paidAt,
  String type = 'dine_in',
  String? table,
  int? no,
  String? prefix,
  String? customer,
  String? location,
}) =>
    {
      '_docId': id,
      'items': items,
      'paid_at': paidAt ?? Timestamp.fromDate(DateTime(2026, 11, 5, 13)),
      'type': type,
      if (table != null) 'table_name': table,
      if (no != null) 'order_no': no,
      if (prefix != null) 'order_prefix': prefix,
      if (customer != null) 'customer_name': customer,
      if (location != null) 'location_id': location,
    };

void main() {
  group('cuadra con la tarjeta del Inicio', () {
    test('mismo total y mismo número de pedidos en un caso a mano', () {
      final orders = [
        _orden('a', [
          _item('Hamburguesa', qty: 2, price: 45),
          _item('Limonada', price: 15, courtesy: false),
          // Anulada: no cuenta aunque diga cortesía.
          _item('Papas', price: 20, voided: true),
        ]),
        _orden('b', [_item('Postre', qty: null, price: 25)]),
        // Sin cortesías: no aparece ni cuenta como pedido.
        _orden('c', [_item('Café', price: 12, courtesy: false)]),
        // Basura que la tarjeta tolera: renglones que no son mapas, sin items.
        _orden('d', ['texto', null, 7]),
        {'_docId': 'e', 'items': null},
        _orden('f', [_item('Agua', price: null)]),
      ];

      final r = CortesiasReport.desde(orders);
      final tarjeta = _comoLaTarjeta(orders);

      expect(r.total, tarjeta.total);
      expect(r.total, 115.0);
      expect(r.pedidos.length, tarjeta.count);
      expect(r.pedidos.length, 3);
    });

    test('al centavo con cientos de pedidos de decimales feos', () {
      // Montos como 12.35 × 3 no son exactos en binario: si el reporte
      // sumara en otro orden que la tarjeta, el último centavo podría bailar.
      final rnd = Random(20261107);
      const precios = [12.35, 7.1, 45.99, 0.3, 19.95, 103.4, 2.2, 33.33];
      final orders = <Map<String, dynamic>>[];
      for (var i = 0; i < 600; i++) {
        final items = <Object?>[];
        for (var j = 0; j < 1 + rnd.nextInt(6); j++) {
          items.add(_item(
            'P${rnd.nextInt(15)}',
            qty: 1 + rnd.nextInt(4),
            price: precios[rnd.nextInt(precios.length)],
            courtesy: rnd.nextInt(3) == 0,
            voided: rnd.nextInt(7) == 0,
            type: rnd.nextBool() ? 'CORTESIA' : 'DONACION',
            mods: rnd.nextInt(3) == 0
                ? [
                    for (var k = 0; k < 1 + rnd.nextInt(3); k++)
                      {
                        'name': 'Extra $k',
                        'price': precios[rnd.nextInt(precios.length)],
                        'qty': 1 + rnd.nextInt(2),
                      }
                  ]
                : null,
          ));
        }
        orders.add(_orden('o$i', items));
      }

      final r = CortesiasReport.desde(orders);
      final tarjeta = _comoLaTarjeta(orders);

      expect(r.total, tarjeta.total, reason: 'idéntico, no "parecido"');
      expect(r.total.toStringAsFixed(2), tarjeta.total.toStringAsFixed(2));
      expect(r.pedidos.length, tarjeta.count);
      // Lo de cada pedido y lo de cada platillo suman lo mismo que el total.
      final porPedidos = r.pedidos.fold<double>(0, (s, p) => s + p.monto);
      final porPlatillos = r.platillos.fold<double>(0, (s, p) => s + p.monto);
      expect(porPedidos, closeTo(r.total, 1e-6));
      expect(porPlatillos, closeTo(r.total, 1e-6));
      expect(r.totalCortesia + r.totalDonacion, closeTo(r.total, 1e-6));
      // Y cada renglón vale lo que el POS dice que vale.
      for (final o in orders) {
        for (final item in o['items'] as List) {
          if (!cuentaComoCortesia(item)) continue;
          final it = item as Map<String, dynamic>;
          expect(valorCortesia(it), closeTo(_comoElPos(it), 1e-9));
        }
      }
    });
  });

  group('extras (como el POS)', () {
    test('2 hamburguesas de Q55 con tocino y queso valen Q146, como el ticket',
        () {
      final item = _item('Hamburguesa', qty: 2, price: 55, mods: [
        {'name': 'Tocino', 'price': 10, 'qty': 1},
        {'name': 'Queso', 'price': 8, 'qty': 1},
      ]);
      expect(valorCortesia(item), 146);
      expect(valorCortesia(item), _comoElPos(item));

      final r = CortesiasReport.desde([
        _orden('a', [item])
      ]);
      expect(r.total, 146);
      expect(r.pedidos.single.renglones.single.extras, ['Tocino', 'Queso']);
      expect(r.platillos.single.monto, 146);
    });

    test('un platillo de Q0 con extras vale sus extras, no Q0', () {
      final item = _item('Arma tu bowl', price: 0, mods: [
        {'name': 'Pollo', 'price': 25},
        {'name': 'Aguacate', 'price': 10},
      ]);
      expect(valorCortesia(item), 35);
    });

    test('el extra se multiplica por su cantidad y por la del platillo', () {
      final item = _item('Taco', qty: 3, price: 12, mods: [
        {'name': 'Queso', 'price': 5, 'qty': 2},
      ]);
      expect(valorCortesia(item), 3 * 12 + 5 * 2 * 3);
      final r = CortesiasReport.desde([
        _orden('a', [item])
      ]);
      expect(r.pedidos.single.renglones.single.extras, ['Queso ×2']);
    });

    test('extras sin precio, sin nombre o mal formados no rompen nada', () {
      final item = _item('Sopa', price: 20, mods: [
        {'name': 'Sin cebolla'},
        {'price': 4},
        'texto',
        null,
      ]);
      expect(valorCortesia(item), 24);
      final r = CortesiasReport.desde([
        _orden('a', [item])
      ]);
      // El de Q4 sin nombre no se puede mostrar, pero sí entra en el monto.
      expect(r.pedidos.single.renglones.single.extras, ['Sin cebolla']);
      expect(r.total, 24);
    });

    test('un renglón anulado no cuenta aunque lleve extras', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('Hamburguesa', price: 55, voided: true, mods: [
            {'name': 'Tocino', 'price': 10},
          ]),
        ]),
      ]);
      expect(r.vacio, isTrue);
    });
  });

  group('detalle', () {
    test('los pedidos van del más reciente al más viejo, sin fecha al final', () {
      final r = CortesiasReport.desde([
        _orden('viejo', [_item('A')],
            paidAt: Timestamp.fromDate(DateTime(2026, 11, 1, 9))),
        _orden('sin', [_item('B')], paidAt: 'no es fecha'),
        _orden('nuevo', [_item('C')],
            // Los pedidos offline guardan la fecha como texto.
            paidAt: '2026-11-06T20:30:00.000'),
      ]);
      expect(r.pedidos.map((p) => p.id), ['nuevo', 'viejo', 'sin']);
      expect(r.pedidos.first.fecha, DateTime(2026, 11, 6, 20, 30));
      expect(r.pedidos.last.fecha, isNull);
    });

    test('solo trae los renglones regalados, con cantidad y monto', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('Hamburguesa', qty: 2, price: 45),
          _item('Limonada', price: 15, courtesy: false),
        ], table: 'Mesa 4', no: 123, prefix: 'A'),
      ]);
      final p = r.pedidos.single;
      expect(p.renglones.map((x) => x.nombre), ['Hamburguesa']);
      expect(p.renglones.single.cantidad, 2);
      expect(p.renglones.single.monto, 90);
      expect(p.numero, '#A123');
      expect(p.lugar, 'Mesa 4');
    });

    test('dónde se pidió', () {
      String lugar(String type, {String? table}) => CortesiasReport.desde([
            _orden('x', [_item('A')], type: type, table: table),
          ]).pedidos.single.lugar;

      expect(lugar('dine_in', table: 'Terraza 2'), 'Terraza 2');
      expect(lugar('dine_in'), 'Consumir aquí');
      expect(lugar('takeout'), 'Para llevar');
      expect(lugar('pickup'), 'Para llevar');
      expect(lugar('delivery'), 'A domicilio');
      expect(lugar('quick_sale'), 'Entrega inmediata');
      expect(lugar('room_service', table: 'Hab. 12'), 'Hab. 12');
      expect(lugar('room_service'), 'Hospedaje');
    });

    test('cortesía y donación por separado; sin tipo es cortesía', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('A', price: 30, type: 'CORTESIA'),
          _item('B', price: 20, type: 'DONACION'),
          _item('C', price: 5, type: null),
        ]),
      ]);
      expect(r.totalCortesia, 35);
      expect(r.totalDonacion, 20);
      expect(r.renglonesCortesia, 2);
      expect(r.renglonesDonacion, 1);
      expect(r.pedidos.single.tipos,
          {TipoCortesia.cortesia, TipoCortesia.donacion});
    });

    test('una donación de precio cero sí cuenta como que hubo', () {
      final r = CortesiasReport.desde([
        _orden('a', [_item('Arma tu bowl', price: 0, type: 'DONACION')]),
      ]);
      expect(r.totalDonacion, 0);
      expect(r.renglonesDonacion, 1);
      expect(r.renglonesCortesia, 0);
    });

    test('quién la marcó y el motivo, sin repetir y sin "unknown"', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('A', by: 'u1', reason: 'Cumpleaños'),
          _item('B', by: 'u1', reason: 'Cumpleaños'),
          _item('C', by: 'unknown'),
          _item('D', by: '  '),
        ]),
        _orden('b', [_item('E', by: 'u2')]),
      ]);
      final a = r.pedidos.firstWhere((p) => p.id == 'a');
      expect(a.usuarios, ['u1']);
      expect(a.motivos, ['Cumpleaños']);
      expect(r.usuarios, {'u1', 'u2'});
    });
  });

  group('resumen por platillo', () {
    test('suma cantidad y monto, y cuenta pedidos distintos', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('Hamburguesa', qty: 2, price: 45),
          // El mismo platillo dos veces en un pedido es UN pedido.
          _item('Hamburguesa', qty: 1, price: 45),
          _item('Limonada', qty: 1, price: 15),
        ]),
        _orden('b', [_item('Hamburguesa', qty: 1, price: 45)]),
      ]);

      final h = r.platillos.firstWhere((p) => p.nombre == 'Hamburguesa');
      expect(h.cantidad, 4);
      expect(h.monto, 180);
      expect(h.pedidos, 2);
      expect(r.cantidad, 5);
    });

    test('de más a menos monto; empate, el que más se regaló', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('Barato', qty: 1, price: 5),
          _item('Caro', qty: 1, price: 100),
          _item('Medio dos', qty: 2, price: 10),
          _item('Medio uno', qty: 1, price: 20),
        ]),
      ]);
      expect(r.platillos.map((p) => p.nombre),
          ['Caro', 'Medio dos', 'Medio uno', 'Barato']);
    });

    test('sin nombre no se pierde: queda como "Sin nombre"', () {
      final r = CortesiasReport.desde([
        _orden('a', [
          {'is_courtesy': true, 'unit_price': 8, 'qty': 1},
        ]),
      ]);
      expect(r.platillos.single.nombre, 'Sin nombre');
      expect(r.total, 8);
    });
  });

  test('sin cortesías el reporte queda vacío', () {
    final r = CortesiasReport.desde([
      _orden('a', [_item('A', courtesy: false)]),
    ]);
    expect(r.vacio, isTrue);
    expect(r.total, 0);
    expect(r.platillos, isEmpty);
  });
}
