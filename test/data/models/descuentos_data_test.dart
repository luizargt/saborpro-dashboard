import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/atencion_inicio.dart';
import 'package:saborpro_reports/data/models/descuentos_data.dart';

/// El detalle de "Descuentos": lo que se descontó, a quién, quién cobró y por qué.
/// Tiene que cuadrar con la tarjeta del Inicio (mismo conteo y mismo total).
void main() {
  Map<String, dynamic> item(String nombre, double precio, {double qty = 1, Map<String, dynamic>? extra, List<Map<String, dynamic>>? mods}) => {
        'name': nombre,
        'qty': qty,
        'unit_price': precio,
        if (mods != null) 'modifiers': mods,
        ...?extra,
      };

  Map<String, dynamic> pedido({
    String id = 'p1',
    double? descuento = 10,
    double? total = 100,
    List<Map<String, dynamic>>? items,
    String? motivo,
    String? quien = 'u1',
    String? nombre,
    Object? pagado,
    String? mesa = 'Mesa 4',
    String? tipo,
    Object? numero,
    String prefijo = 'A',
    String? sucursal = 'L1',
  }) =>
      {
        '_docId': id,
        if (descuento != null) 'discount_amount': descuento,
        if (total != null) 'total_amount': total,
        'items': items ?? [item('Hamburguesa', 100)],
        if (motivo != null) 'discount_reason': motivo,
        if (quien != null) 'paid_by_user_id': quien,
        if (nombre != null) 'paid_by_user_name': nombre,
        'paid_at': pagado ?? DateTime(2026, 11, 23, 14, 30),
        if (mesa != null) 'table_name': mesa,
        if (tipo != null) 'type': tipo,
        if (numero != null) ...{'order_no': numero, 'order_prefix': prefijo},
        if (sucursal != null) 'location_id': sucursal,
      };

  DescuentosReport armar(List<Map<String, dynamic>> o) => DescuentosReport.desde(o);

  group('qué pedidos entran', () {
    test('solo los que tienen descuento mayor que cero', () {
      final r = armar([
        pedido(id: 'a', descuento: 10),
        pedido(id: 'b', descuento: 0),
        pedido(id: 'c', descuento: null),
        pedido(id: 'd', descuento: -5),
        pedido(id: 'e', descuento: 0.01),
      ]);
      expect(r.pedidos.map((p) => p.id).toSet(), {'a', 'e'});
    });

    test('un descuento que no es número (texto, nulo) no cuenta', () {
      final r = armar([
        {...pedido(id: 'a'), 'discount_amount': '10'},
        {...pedido(id: 'b'), 'discount_amount': null},
        {...pedido(id: 'c'), 'discount_amount': double.nan},
      ]);
      expect(r.vacio, isTrue);
    });

    test('CUADRA con la tarjeta: mismo conteo y mismo total que el Inicio', () {
      final ordenes = [
        pedido(id: 'a', descuento: 10),
        pedido(id: 'b', descuento: 0),
        pedido(id: 'c', descuento: 25.5, total: 200),
        pedido(id: 'd', descuento: null),
        pedido(id: 'e', descuento: 0.5, total: 20),
      ];
      final r = armar(ordenes);
      // El conteo de la tarjeta (ResumenPedidosInicio) y el total (suma de
      // discount_amount, como PeriodMetrics.discounts).
      expect(r.pedidos.length, ResumenPedidosInicio.desde(ordenes).descuentos);
      final sumaDeLaTarjeta = ordenes.fold<double>(0, (s, o) => s + ((o['discount_amount'] as num?) ?? 0));
      expect(r.total, closeTo(sumaDeLaTarjeta, 1e-9));
    });

    test('sin pedidos: el reporte está vacío y en cero', () {
      final r = armar([]);
      expect(r.vacio, isTrue);
      expect(r.total, 0);
      expect(r.cuentaTotal, 0);
      expect(r.porcentajePromedio, 0);
      expect(r.masAlto, isNull);
      expect(r.sinMotivo, 0);
      expect(r.altos, 0);
      expect(DescuentosReport.empty.vacio, isTrue);
    });
  });

  group('la cuenta y el porcentaje', () {
    test('la cuenta es el total antes del descuento y el porcentaje sale de ahí', () {
      final p = armar([pedido(descuento: 20, total: 200)]).pedidos.single;
      expect(p.cuenta, 200);
      expect(p.porcentaje, closeTo(10, 1e-9));
      expect(p.despues, 180);
      expect(p.tienePorcentaje, isTrue);
    });

    test('sin total guardado, la cuenta es lo que suman los platillos cobrados', () {
      final p = armar([
        pedido(descuento: 15, total: null, items: [item('A', 60), item('B', 40, qty: 1)]),
      ]).pedidos.single;
      expect(p.cuenta, 100);
      expect(p.porcentaje, closeTo(15, 1e-9));
    });

    test('un total en cero también cae a la suma de los platillos', () {
      final p = armar([pedido(descuento: 10, total: 0, items: [item('A', 100)])]).pedidos.single;
      expect(p.cuenta, 100);
    });

    test('sin cuenta ni platillos no hay porcentaje (no se inventa)', () {
      final p = armar([pedido(descuento: 10, total: null, items: [])]).pedidos.single;
      expect(p.cuenta, 0);
      expect(p.tienePorcentaje, isFalse);
      expect(p.porcentaje, 0);
      expect(p.alto, isFalse);
      expect(p.despues, 0);
    });

    test('un descuento mayor que la cuenta deja la cuenta en cero, nunca negativa', () {
      final p = armar([pedido(descuento: 150, total: 100)]).pedidos.single;
      expect(p.despues, 0);
      expect(p.porcentaje, closeTo(150, 1e-9));
    });

    test('alto desde el 30% exacto, no antes', () {
      final r = armar([
        pedido(id: 'a', descuento: 30, total: 100),
        pedido(id: 'b', descuento: 29.99, total: 100),
        pedido(id: 'c', descuento: 31, total: 100),
      ]);
      final altos = r.pedidos.where((p) => p.alto).map((p) => p.id).toSet();
      expect(altos, {'a', 'c'});
      expect(r.altos, 2);
      expect(kDescuentoAlto, 30);
    });

    test('el promedio pesa por cuenta: lo descontado entre lo que valían', () {
      final r = armar([
        pedido(id: 'a', descuento: 50, total: 100), // 50%
        pedido(id: 'b', descuento: 10, total: 900), // ~1.1%
      ]);
      expect(r.total, 60);
      expect(r.cuentaTotal, 1000);
      // No es el promedio de los porcentajes (25.6%): es 60/1000.
      expect(r.porcentajePromedio, closeTo(6, 1e-9));
    });
  });

  group('los platillos de la cuenta', () {
    test('no entran los anulados ni los regalados', () {
      final p = armar([
        pedido(descuento: 10, total: 100, items: [
          item('Cobrado', 100),
          item('Anulado', 50, extra: {'is_void': true}),
          item('Regalado', 30, extra: {'is_courtesy': true}),
        ]),
      ]).pedidos.single;
      expect(p.renglones.map((r) => r.nombre), ['Cobrado']);
    });

    test('una cortesía anulada tampoco entra', () {
      final p = armar([
        pedido(items: [item('X', 10, extra: {'is_courtesy': true, 'is_void': true}), item('Y', 100)]),
      ]).pedidos.single;
      expect(p.renglones.map((r) => r.nombre), ['Y']);
    });

    test('el valor de la línea incluye sus extras, como en el ticket', () {
      final p = armar([
        pedido(total: 146, items: [
          item('Hamburguesa', 55, qty: 2, mods: [
            {'price': 5.0, 'qty': 1},
            {'price': 3.0, 'qty': 2},
          ]),
        ]),
      ]).pedidos.single;
      // 55×2 + (5 + 3×2)×2 = 132
      expect(p.renglones.single.monto, closeTo(132, 1e-9));
      expect(p.renglones.single.cantidad, 2);
    });

    test('un platillo sin nombre se llama "Sin nombre" y sin qty vale 1', () {
      final p = armar([
        pedido(items: [
          {'unit_price': 10.0},
        ]),
      ]).pedidos.single;
      expect(p.renglones.single.nombre, 'Sin nombre');
      expect(p.renglones.single.cantidad, 1);
    });

    test('el descuento se reparte entre los platillos según lo que valía cada uno', () {
      final r = armar([
        pedido(descuento: 30, total: 150, items: [item('Caro', 100), item('Barato', 50)]),
      ]);
      final por = {for (final x in r.platillos) x.nombre: x.monto};
      expect(por['Caro'], closeTo(20, 1e-9));
      expect(por['Barato'], closeTo(10, 1e-9));
      // Lo repartido suma lo descontado.
      expect(r.platillos.fold<double>(0, (s, x) => s + x.monto), closeTo(30, 1e-9));
    });

    test('el mismo platillo en varios pedidos se suma, y cuenta un pedido por cada uno', () {
      final r = armar([
        pedido(id: 'a', descuento: 10, total: 100, items: [item('Café', 25, qty: 2), item('Pan', 50)]),
        pedido(id: 'b', descuento: 5, total: 50, items: [item('Café', 25, qty: 2)]),
      ]);
      final cafe = r.platillos.firstWhere((x) => x.nombre == 'Café');
      expect(cafe.cantidad, 4);
      expect(cafe.pedidos, 2);
      expect(cafe.monto, closeTo(5 + 5, 1e-9)); // 10×50/100 + 5
    });

    test('el mismo platillo en dos líneas de un pedido es UN pedido', () {
      final r = armar([
        pedido(descuento: 10, total: 100, items: [item('Café', 50), item('Café', 50)]),
      ]);
      expect(r.platillos.single.pedidos, 1);
      expect(r.platillos.single.cantidad, 2);
    });

    test('van de más a menos descontado y, al empatar, por cantidad y nombre', () {
      final r = armar([
        pedido(descuento: 30, total: 300, items: [item('B', 100), item('A', 100), item('C', 100)]),
      ]);
      expect(r.platillos.map((x) => x.nombre), ['A', 'B', 'C']);
      final r2 = armar([
        pedido(descuento: 30, total: 150, items: [item('Chico', 50), item('Grande', 100)]),
      ]);
      expect(r2.platillos.first.nombre, 'Grande');
    });

    test('sin platillos que repartir no se inventa ninguno (el pedido sí cuenta)', () {
      final r = armar([pedido(descuento: 10, total: 100, items: [])]);
      expect(r.pedidos, hasLength(1));
      expect(r.platillos, isEmpty);
      expect(r.total, 10);
    });
  });

  group('quién y por qué', () {
    test('el motivo se recorta, y vacío o solo espacios es "sin motivo"', () {
      final r = armar([
        pedido(id: 'a', motivo: '  Cliente frecuente  '),
        pedido(id: 'b', motivo: ''),
        pedido(id: 'c', motivo: '   '),
        pedido(id: 'd'),
      ]);
      final por = {for (final p in r.pedidos) p.id: p};
      expect(por['a']!.motivo, 'Cliente frecuente');
      expect(por['a']!.sinMotivo, isFalse);
      expect(por['b']!.sinMotivo, isTrue);
      expect(por['c']!.sinMotivo, isTrue);
      expect(por['d']!.sinMotivo, isTrue);
      expect(r.sinMotivo, 3);
    });

    test('lo que se descontó sin motivo se suma aparte', () {
      final r = armar([
        pedido(id: 'a', descuento: 10, motivo: 'Promo'),
        pedido(id: 'b', descuento: 7.5),
        pedido(id: 'c', descuento: 2.5, motivo: ' '),
      ]);
      expect(r.montoSinMotivo, closeTo(10, 1e-9));
    });

    test('quién cobró: por id; "unknown" y vacío no son nadie', () {
      final r = armar([
        pedido(id: 'a', quien: 'u1'),
        pedido(id: 'b', quien: 'unknown'),
        pedido(id: 'c', quien: null),
        pedido(id: 'd', quien: '  '),
      ]);
      final por = {for (final p in r.pedidos) p.id: p};
      expect(por['a']!.usuarioId, 'u1');
      expect(por['a']!.clave, 'u1');
      for (final id in ['b', 'c', 'd']) {
        expect(por[id]!.usuarioId, isNull, reason: id);
        expect(por[id]!.clave, '', reason: id);
      }
    });

    test('si el pedido guardó el nombre, se usa y no hay que buscarlo', () {
      final r = armar([
        pedido(id: 'a', quien: 'u1', nombre: 'Ana Cosme'),
        pedido(id: 'b', quien: 'u2'),
        pedido(id: 'c', quien: null, nombre: 'Carlos'),
      ]);
      final por = {for (final p in r.pedidos) p.id: p};
      expect(por['a']!.usuarioNombre, 'Ana Cosme');
      expect(por['c']!.clave, 'nombre:Carlos');
      // Solo se piden los nombres de quien no lo trae.
      expect(r.usuarios, {'u2'});
    });
  });

  group('el más alto', () {
    test('el de mayor porcentaje; al empatar, el de más monto', () {
      final r = armar([
        pedido(id: 'a', descuento: 10, total: 100), // 10%
        pedido(id: 'b', descuento: 50, total: 100), // 50%
        pedido(id: 'c', descuento: 100, total: 200), // 50% con más monto
      ]);
      expect(r.masAlto!.id, 'c');
    });

    test('los que no tienen cuenta no compiten', () {
      final r = armar([
        pedido(id: 'a', descuento: 10, total: null, items: []),
        pedido(id: 'b', descuento: 5, total: 100),
      ]);
      expect(r.masAlto!.id, 'b');
      expect(armar([pedido(descuento: 10, total: null, items: [])]).masAlto, isNull);
    });
  });

  group('de cada pedido', () {
    test('mesa, número, cliente y sucursal', () {
      final p = armar([
        {...pedido(numero: 12), 'customer_name': ' Doña Rosa '},
      ]).pedidos.single;
      expect(p.lugar, 'Mesa 4');
      expect(p.numero, '#A12');
      expect(p.cliente, 'Doña Rosa');
      expect(p.locationId, 'L1');
    });

    test('para llevar, a domicilio y sin mesa', () {
      expect(armar([pedido(tipo: 'takeout', mesa: null)]).pedidos.single.lugar, 'Para llevar');
      expect(armar([pedido(tipo: 'delivery', mesa: null)]).pedidos.single.lugar, 'A domicilio');
      expect(armar([pedido(mesa: null)]).pedidos.single.lugar, 'Consumir aquí');
      expect(armar([pedido()]).pedidos.single.numero, '');
    });

    test('la fecha se lee como Timestamp, texto ISO o DateTime', () {
      final r = armar([
        pedido(id: 'ts', pagado: Timestamp.fromDate(DateTime(2026, 11, 23, 9))),
        pedido(id: 'iso', pagado: '2026-11-23T10:00:00.000'),
        pedido(id: 'dt', pagado: DateTime(2026, 11, 23, 11)),
        pedido(id: 'nada', pagado: 'no es fecha'),
      ]);
      final por = {for (final p in r.pedidos) p.id: p};
      expect(por['ts']!.fecha, DateTime(2026, 11, 23, 9));
      expect(por['iso']!.fecha, DateTime(2026, 11, 23, 10));
      expect(por['dt']!.fecha, DateTime(2026, 11, 23, 11));
      expect(por['nada']!.fecha, isNull);
    });

    test('del más reciente al más viejo, y los sin fecha al final', () {
      final r = armar([
        pedido(id: 'viejo', pagado: DateTime(2026, 11, 23, 8)),
        pedido(id: 'sin', pagado: 'x'),
        pedido(id: 'nuevo', pagado: DateTime(2026, 11, 23, 18)),
        pedido(id: 'medio', pagado: DateTime(2026, 11, 23, 12)),
      ]);
      expect(r.pedidos.map((p) => p.id), ['nuevo', 'medio', 'viejo', 'sin']);
    });

    test('el id sale de _docId, y si no de id', () {
      expect(armar([{...pedido(), '_docId': null, 'id': 'xyz'}]).pedidos.single.id, 'xyz');
      expect(armar([{...pedido(), '_docId': null}]).pedidos.single.id, '');
    });
  });
}
