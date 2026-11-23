// test/presentation/providers/cancellations_pair_test.dart
//
// ===========================================================================
// EL PAR SE LEE COMO UNA SOLA FILA
// ===========================================================================
//
// Este es el test que faltaba cuando el POS todavía no escribía `orderItemId`.
// Sin ese campo el provider caía a agrupar por el id del documento, y como la
// devolución es `dec.{ronda}.{item}.{ing}` y su merma es `wst.{ronda}.{item}.{ing}`
// —dos strings distintos— las dos mitades del MISMO par caían en grupos
// separados. Consecuencia: la resta "devolución menos merma" nunca restaba, y
// un plato que alguien declaró PERDIDO salía a la vez como producto que volvió
// a la despensa y como merma. El reporte que existe para ver lo que se pierde
// informaba el doble de lo que volvió.
//
// La agregación es pura (no toca Firestore ni AuthService), así que corre sin
// Firebase por las puertas @visibleForTesting del provider.
// ===========================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/cancellation_data.dart';
import 'package:saborpro_reports/presentation/providers/cancellations_provider.dart';

void main() {
  final ahora = DateTime(2026, 8, 30, 20, 30);
  final rango = DateRange(
    start: DateTime(2026, 8, 30),
    end: DateTime(2026, 8, 30, 23, 59, 59),
    mode: PeriodMode.day,
  );

  /// Un movimiento tal como lo escribe el POS (fase 4).
  Map<String, dynamic> doc({
    required String type,
    required double quantity,
    String itemId = 'item_cerveza',
    String itemName = 'Cerveza',
    int itemQty = 4,
    String ingredientId = 'ing_cerveza',
  }) =>
      {
        'type': type,
        'quantity': quantity,
        'ingredientId': ingredientId,
        'locationId': 'loc_1',
        'tenantId': 'tenant_1',
        'orderId': 'order_1',
        'orderItemId': itemId,
        'orderItemName': itemName,
        'orderItemQty': itemQty,
        'reason': 'Cliente cambió de opinión',
        'createdByUserId': 'u_1',
        'createdByUserName': 'Ana',
        'createdAt': ahora.toIso8601String(),
      };

  late CancellationsProvider provider;
  setUp(() => provider = CancellationsProvider());

  CancellationsReport reporteDe(List<Map<String, dynamic>> docs) {
    final movs = <CancellationMovement>[];
    for (var i = 0; i < docs.length; i++) {
      final m = provider.parseMovementForTest('doc_$i', docs[i], rango);
      if (m != null) movs.add(m);
    }
    return provider.buildForTest(
      movements: movs,
      costs: {
        'ing_cerveza': const IngredientCost(name: 'Cerveza', unit: 'u', price: 5.0),
      },
    );
  }

  test('el par devolución+merma es UNA fila, y dice que se perdió', () {
    // 4 cervezas anuladas, ninguna regresa: devolución de +4 y merma de −4.
    final r = reporteDe([
      doc(type: 'devolucionCancelacion', quantity: 4.0),
      doc(type: 'mermaCancelacion', quantity: -4.0),
    ]);

    expect(r.events, hasLength(1));
    final evento = r.events.single;
    expect(evento.items, hasLength(1),
        reason: 'las dos mitades tienen el mismo orderItemId: una sola línea');

    final linea = evento.items.single;
    expect(linea.name, equals('Cerveza'));
    expect(linea.qty, equals(4));
    expect(linea.declaredLost, isTrue);

    // Lo que volvió a la despensa es CERO: el neto del par es cero por diseño.
    expect(linea.returned.isEmpty, isTrue,
        reason: 'devolución menos merma = 0; sumar solo la devolución diría '
            'que volvió algo que nadie volvió a ver');
    expect(linea.wasted.amount, closeTo(20.0, 0.001));

    expect(r.totalReturned.isEmpty, isTrue);
    expect(r.totalWasted.amount, closeTo(20.0, 0.001));
  });

  test('devolución sola = regresó, y no cuenta como pérdida', () {
    final r = reporteDe([
      doc(type: 'devolucionCancelacion', quantity: 4.0),
    ]);

    final linea = r.events.single.items.single;
    expect(linea.declaredLost, isFalse);
    expect(linea.returned.amount, closeTo(20.0, 0.001));
    expect(linea.wasted.isEmpty, isTrue);
    expect(r.totalWasted.isEmpty, isTrue);
  });

  test('parcial (3 de 4 regresan): vuelven 3 y se pierde 1', () {
    // El POS escribe la devolución por las 4 anuladas y la merma solo por la
    // que no regresa. Si algún día se escribiera la devolución solo por lo que
    // regresa, esta resta quedaría inflada — por eso está clavada acá.
    final r = reporteDe([
      doc(type: 'devolucionCancelacion', quantity: 4.0),
      doc(type: 'mermaCancelacion', quantity: -1.0),
    ]);

    final linea = r.events.single.items.single;
    expect(linea.declaredLost, isTrue);
    expect(linea.returned.amount, closeTo(15.0, 0.001), reason: '3 × Q5');
    expect(linea.wasted.amount, closeTo(5.0, 0.001), reason: '1 × Q5');
  });

  test('dos líneas del mismo pedido no se funden aunque compartan ingrediente',
      () {
    final r = reporteDe([
      doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'item_a', itemName: 'Cerveza', itemQty: 2),
      doc(type: 'mermaCancelacion', quantity: -2.0, itemId: 'item_a', itemName: 'Cerveza', itemQty: 2),
      doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'item_b', itemName: 'Cerveza', itemQty: 1),
    ]);

    final evento = r.events.single;
    expect(evento.items, hasLength(2));
    final a = evento.items.firstWhere((i) => i.itemId == 'item_a');
    final b = evento.items.firstWhere((i) => i.itemId == 'item_b');
    expect(a.declaredLost, isTrue);
    expect(b.declaredLost, isFalse);
    expect(b.returned.amount, closeTo(5.0, 0.001));
  });

  test('el corte por persona distingue quien pierde todo de quien pierde una',
      () {
    // Sin el itemId las dos mitades caían en grupos distintos y el porcentaje
    // quedaba clavado en 0.5 para cualquiera que declarara pérdidas.
    final r = reporteDe([
      // item_a: se pierde entero
      doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'item_a', itemQty: 2),
      doc(type: 'mermaCancelacion', quantity: -2.0, itemId: 'item_a', itemQty: 2),
      // item_b y item_c: regresan
      doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'item_b', itemQty: 1),
      doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'item_c', itemQty: 1),
    ]);

    expect(r.people, hasLength(1));
    final persona = r.people.single;
    expect(persona.itemsCancelled, equals(3));
    expect(persona.itemsLost, equals(1));
    expect(persona.lostRate, closeTo(1 / 3, 0.0001));
  });

  test('el motivo llega limpio, sin el prefijo del tipo pegado adelante', () {
    final r = reporteDe([
      doc(type: 'devolucionCancelacion', quantity: 1.0),
      doc(type: 'mermaCancelacion', quantity: -1.0),
    ]);

    expect(r.events.single.reason, equals('Cliente cambió de opinión'));
  });

  test('un movimiento sin sucursal no desaparece del reporte', () {
    // El ingrediente puede haberse creado sin location_id; descartarlo dejaba
    // el reporte vacío, indistinguible de "nadie canceló nada".
    final sinSucursal = doc(type: 'mermaCancelacion', quantity: -1.0)
      ..['locationId'] = '';
    final m = provider.parseMovementForTest('doc_x', sinSucursal, rango);
    expect(m, isNotNull);
    expect(m!.locationId, isEmpty);
  });

  test('un movimiento que no es de cancelación se ignora', () {
    final venta = doc(type: 'salidaVenta', quantity: -1.0);
    expect(provider.parseMovementForTest('doc_y', venta, rango), isNull);
  });

  test('si dos personas firman renglones del mismo pedido, el evento las guarda a las dos',
      () {
    // Ana anula la cerveza (y declara que no regresa); Beto, las papas. En el
    // corte por persona cada una cuenta lo suyo; el evento tiene que poder
    // encontrarse por cualquiera de las dos.
    final r = reporteDe([
      doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'a'),
      doc(type: 'mermaCancelacion', quantity: -2.0, itemId: 'a'),
      {
        ...doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'b'),
        'createdByUserId': 'u_2',
        'createdByUserName': 'Beto',
      },
    ]);

    final e = r.events.single;
    expect(e.userName, 'Ana');
    expect(e.authors, ['Ana', 'Beto']);
    expect(e.signedBy('Ana'), isTrue);
    expect(e.signedBy('Beto'), isTrue);
    expect(e.signedBy('Carla'), isFalse);
    expect(r.people.map((p) => p.userName), containsAll(['Ana', 'Beto']));
  });

  // ===========================================================================
  // LO QUE VALÍA LO ANULADO, A PRECIO DE VENTA
  // ===========================================================================
  //
  // Sale del pedido, no del inventario: un renglón sin receta no genera ningún
  // movimiento y aun así valía plata. Son campos NUEVOS: no mueven ninguno de
  // los números de arriba (costos, porcentajes, lo perdido).
  group('valor a precio de venta', () {
    Map<String, dynamic> linea({
      required String id,
      String name = 'Hamburguesa',
      int qty = 1,
      double price = 55,
      bool isVoid = false,
      int? returned,
      int? kitchenNo,
      List<Map<String, dynamic>> modifiers = const [],
    }) =>
        {
          'id': id,
          'name': name,
          'qty': qty,
          'unit_price': price,
          'is_void': isVoid,
          'modifiers': modifiers,
          if (returned != null) 'inventory_returned_qty': returned,
          if (kitchenNo != null) 'kitchen_order_no': kitchenNo,
        };

    Map<String, dynamic> pedido({
      required String id,
      required List<Map<String, dynamic>> items,
      String status = 'CANCELLED',
    }) =>
        {
          '_docId': id,
          'id': id,
          'status': status,
          'table_name': 'Mesa 4',
          'order_number': 7,
          'cancelled_by_user_name': 'Ana',
          'cancelled_by_user_id': 'u_1',
          'cancellation_reason': 'Cliente se fue',
          'cancelled_at': ahora.toIso8601String(),
          'items': items,
        };

    CancellationsReport reporte({
      List<Map<String, dynamic>> movimientos = const [],
      List<Map<String, dynamic>> cancelados = const [],
      List<Map<String, dynamic>> cobrados = const [],
    }) {
      final movs = <CancellationMovement>[];
      for (var i = 0; i < movimientos.length; i++) {
        final m = provider.parseMovementForTest('mv_$i', movimientos[i], rango);
        if (m != null) movs.add(m);
      }
      return provider.buildForTest(
        movements: movs,
        costs: {
          'ing_cerveza':
              const IngredientCost(name: 'Cerveza', unit: 'u', price: 5.0),
        },
        cancelledOrders: cancelados,
        paidOrders: cobrados,
      );
    }

    /// La cerveza que se anuló y no regresa (par devolución + merma).
    List<Map<String, dynamic>> cervezaPerdida({String itemId = 'i1'}) => [
          doc(type: 'devolucionCancelacion', quantity: 4.0, itemId: itemId),
          doc(type: 'mermaCancelacion', quantity: -4.0, itemId: itemId),
        ];

    test('pedido cancelado entero: vale todo y se lista el renglón sin receta', () {
      final r = reporte(
        movimientos: cervezaPerdida(),
        cancelados: [
          pedido(id: 'order_1', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25), // 100, con receta
            linea(id: 'i2', name: 'Nachos', qty: 1, price: 55), // 55, sin receta
          ]),
        ],
      );

      final e = r.events.single;
      expect(e.items, hasLength(2));
      final cerveza = e.items.firstWhere((i) => i.itemId == 'i1');
      final nachos = e.items.firstWhere((i) => i.itemId == 'i2');
      expect(cerveza.movedInventory, isTrue);
      expect(cerveza.value, closeTo(100, 0.001));
      expect(nachos.movedInventory, isFalse);
      expect(nachos.qty, 1);
      expect(nachos.value, closeTo(55, 0.001));
      expect(e.value, closeTo(155, 0.001));

      expect(r.cancelledValue, closeTo(155, 0.001));
      expect(r.cancelledValueOrders, 1);
    });

    test('un renglón sin receta al que se le preguntó cuenta en los porcentajes; uno al que no, no',
        () {
      // La declaración que se revisa es la misma tenga o no receta el
      // producto: "no regresa". El que nunca se mandó a cocina no se preguntó.
      final r = reporte(
        movimientos: cervezaPerdida(),
        cancelados: [
          pedido(id: 'order_1', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25), // con receta: movimiento
            linea(id: 'i2', name: 'Nachos', price: 55, qty: 1, returned: 0), // sin receta, perdido
            linea(id: 'i3', name: 'Jugo', price: 30), // nunca se preguntó
          ]),
        ],
      );

      expect(r.events.single.items, hasLength(3));
      expect(r.itemsCancelled, 2);
      expect(r.itemsLost, 2);
      expect(r.houseLostRate, 1.0);
      // Es la misma persona: quien firmó el movimiento y quien canceló el pedido.
      expect(r.people, hasLength(1));
      expect(r.people.single.itemsCancelled, 2);
      expect(r.people.single.itemsLost, 2);
      final nachos = r.events.single.items.firstWhere((i) => i.itemId == 'i2');
      expect(nachos.declaredLost, isTrue);
      expect(nachos.asked, isTrue);
      final jugo = r.events.single.items.firstWhere((i) => i.itemId == 'i3');
      expect(jugo.asked, isFalse);
      expect(jugo.counts, isFalse);
    });

    test('el reporte de siempre no cambia: costo, devuelto y perdido salen igual', () {
      final sin = reporte(movimientos: cervezaPerdida());
      final con = reporte(
        movimientos: cervezaPerdida(),
        cancelados: [
          pedido(id: 'order_1', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25),
            linea(id: 'i2', name: 'Nachos', price: 55),
          ]),
        ],
      );

      expect(con.totalWasted.amount, closeTo(sin.totalWasted.amount, 0.0001));
      expect(con.totalReturned.isEmpty, sin.totalReturned.isEmpty);
      expect(con.itemsCancelled, sin.itemsCancelled);
      expect(con.itemsLost, sin.itemsLost);
      expect(con.events.single.wasted.amount, closeTo(20, 0.0001));
    });

    test('pedido cobrado con un producto anulado: solo vale lo anulado', () {
      final r = reporte(
        movimientos: [
          doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'i1', itemQty: 2),
        ],
        cobrados: [
          pedido(id: 'order_1', status: 'PAID', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 2, price: 25, isVoid: true), // 50
            linea(id: 'i2', name: 'Pizza', price: 90), // se cobró: no cuenta
          ]),
        ],
      );

      final e = r.events.single;
      expect(e.items.map((i) => i.itemId), ['i1']);
      expect(e.value, closeTo(50, 0.001));
      expect(r.cancelledValue, closeTo(50, 0.001));
      expect(r.cancelledValueOrders, 1);
    });

    test('el valor lleva los extras, como el ticket', () {
      final r = reporte(
        cancelados: [
          pedido(id: 'o9', items: [
            linea(id: 'i1', name: 'Hamburguesa', qty: 2, price: 55, modifiers: [
              {'name': 'Tocino', 'price': 10, 'qty': 1},
              {'name': 'Queso', 'price': 8, 'qty': 1},
            ]),
          ]),
        ],
      );

      // 55 × 2 + (10 + 8) × 2, no 110.
      expect(r.events.single.value, closeTo(146, 0.001));
      expect(r.cancelledValue, closeTo(146, 0.001));
    });

    test('sin el pedido no se inventa el precio: queda sin saber, no en cero', () {
      // Vista de año: el dashboard no trae los pedidos cobrados.
      final r = reporte(movimientos: cervezaPerdida());

      expect(r.events.single.value, isNull);
      expect(r.events.single.items.single.value, isNull);
      expect(r.cancelledValue, 0);
      expect(r.cancelledValueOrders, 0);
    });

    test('un movimiento que no se puede cruzar con el pedido no agrega renglones', () {
      // Los movimientos viejos no traen orderItemId y caen al id del documento:
      // cruzar por id sería adivinar, y se duplicaría el renglón.
      final sinItemId = doc(type: 'devolucionCancelacion', quantity: 4.0)
        ..remove('orderItemId');
      final r = reporte(
        movimientos: [sinItemId],
        cancelados: [
          pedido(id: 'order_1', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25),
            linea(id: 'i2', name: 'Nachos', price: 55),
          ]),
        ],
      );

      final e = r.events.single;
      expect(e.items, hasLength(1));
      expect(e.value, isNull);
      // El total del período sí sale del pedido, que es la fuente.
      expect(r.cancelledValue, closeTo(155, 0.001));
      expect(r.cancelledValueOrders, 1);
    });

    test('si el movimiento no trae la cantidad, se toma la del pedido', () {
      final sinQty = doc(type: 'devolucionCancelacion', quantity: 4.0, itemId: 'i1')
        ..remove('orderItemQty');
      final r = reporte(
        movimientos: [sinQty],
        cancelados: [
          pedido(id: 'order_1', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25),
          ]),
        ],
      );

      expect(r.events.single.items.single.qty, 4);
    });

    test('cancelación que no tocó inventario: cada renglón con su cantidad y precio',
        () {
      final r = reporte(cancelados: [
        // Nunca llegó a cocina.
        pedido(id: 'o1', items: [linea(id: 'a', name: 'Nachos', qty: 2, price: 55)]),
        // Llegó a cocina y no tenía receta.
        pedido(id: 'o2', items: [
          linea(id: 'b', name: 'Chilaquiles', price: 52, kitchenNo: 3),
        ]),
      ]);

      final sinCocina = r.events.firstWhere((e) => e.orderId == 'o1');
      final sinReceta = r.events.firstWhere((e) => e.orderId == 'o2');
      expect(sinCocina.impact, InventoryImpact.sinCocina);
      expect(sinReceta.impact, InventoryImpact.sinReceta);
      expect(sinCocina.items.single.qty, 2);
      expect(sinCocina.items.single.movedInventory, isFalse);
      expect(sinCocina.value, closeTo(110, 0.001));
      expect(sinReceta.value, closeTo(52, 0.001));
      expect(r.cancelledValue, closeTo(162, 0.001));
      expect(r.cancelledValueOrders, 2);
      expect(r.itemsCancelled, 0);
      expect(r.cancelledBeforeKitchen, 1);
      expect(r.cancelledWithoutRecipe, 1);
      // La persona sabe cuántas de sus cancelaciones no tocaron inventario.
      expect(r.people.single.events, 2);
      expect(r.people.single.eventsWithoutInventory, 2);
    });

    test('un pedido que viene en las dos listas cuenta una vez, y como cancelado', () {
      final items = [
        linea(id: 'i1', name: 'Cerveza', price: 25),
        linea(id: 'i2', name: 'Pizza', price: 90),
      ];
      final r = reporte(
        cancelados: [pedido(id: 'o1', items: items)],
        cobrados: [pedido(id: 'o1', status: 'PAID', items: items)],
      );

      // Como cancelado cuenta todo (115); como cobrado no habría contado nada.
      expect(r.cancelledValue, closeTo(115, 0.001));
      expect(r.cancelledValueOrders, 1);
    });

    test('un pedido sin renglones que leer no suma ni inventa', () {
      final sinItems = pedido(id: 'o1', items: const [])..remove('items');
      final r = reporte(cancelados: [sinItems]);

      expect(r.events.single.value, isNull);
      expect(r.cancelledValue, 0);
      expect(r.cancelledValueOrders, 0);
    });

    test('producto sin receta anulado en un pedido cobrado: tiene fila, quién lo anuló y por qué',
        () {
      // Antes solo contaba en los montos, sin fila ni persona: el dueño no podía
      // saber quién había declarado que se perdió. El renglón guarda quién lo
      // anuló, por qué y cuándo.
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          {
            ...linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
            'void_reason': 'Se cayó',
            'voided_by_user_id': 'u_7',
            'voided_by_user_name': 'Luis',
            'voided_at': ahora.toIso8601String(),
          },
          linea(id: 'i2', name: 'Pizza', price: 90),
        ]),
      ]);

      final e = r.events.single;
      expect(e.impact, InventoryImpact.sinReceta);
      expect(e.userName, 'Luis');
      expect(e.authors, ['Luis']);
      expect(e.reason, 'Se cayó');
      expect(e.at, ahora);
      expect(e.value, closeTo(50, 0.001));
      final taco = e.items.single;
      expect(taco.name, 'Taco');
      expect(taco.declaredLost, isTrue);
      expect(taco.asked, isTrue);
      expect(taco.movedInventory, isFalse);

      // Y aparece en el corte por persona, con su porcentaje.
      final luis = r.people.single;
      expect(luis.userName, 'Luis');
      expect(luis.events, 1);
      expect(luis.eventsWithoutInventory, 1);
      expect(luis.itemsCancelled, 1);
      expect(luis.itemsLost, 1);
      expect(r.itemsCancelled, 1);
      expect(r.itemsLost, 1);
      expect(r.cancelledWithoutRecipe, 1);

      // Los montos no cambian: lo perdido sigue sin pasar de lo anulado.
      expect(r.saleWaste.amount, closeTo(50, 0.001));
      expect(r.cancelledValue, closeTo(50, 0.001));
      expect(r.cancelledValueOrders, 1);
      expect(r.saleWaste.amount, lessThanOrEqualTo(r.cancelledValue));
    });

    test('quien anula productos con receta y sin receta es UNA sola persona', () {
      final r = reporte(
        movimientos: cervezaPerdida(),
        cobrados: [
          // La cerveza (con receta, ya con su fila por los movimientos de Ana).
          pedido(id: 'order_1', status: 'PAID', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25, isVoid: true, returned: 0),
          ]),
          // Un taco sin receta que anuló la misma Ana en otro pedido.
          pedido(id: 'o2', status: 'PAID', items: [
            {
              ...linea(id: 't1', name: 'Taco', price: 50, isVoid: true, returned: 0),
              'voided_by_user_id': 'u_1',
              'voided_by_user_name': 'Ana',
            },
          ]),
        ],
      );

      expect(r.events, hasLength(2));
      expect(r.people, hasLength(1));
      expect(r.people.single.userName, 'Ana');
      expect(r.people.single.events, 2);
      expect(r.people.single.itemsCancelled, 2);
      expect(r.people.single.itemsLost, 2);
    });

    test('un pedido cobrado que ya tiene fila por sus movimientos no se repite', () {
      final r = reporte(
        movimientos: cervezaPerdida(),
        cobrados: [
          pedido(id: 'order_1', status: 'PAID', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25, isVoid: true, returned: 0),
            linea(id: 'i2', name: 'Taco', price: 50, isVoid: true, returned: 0),
          ]),
        ],
      );

      // Una sola fila: el taco sin receta sale dentro de ella.
      expect(r.events, hasLength(1));
      expect(r.events.single.items.map((i) => i.itemId), containsAll(['i1', 'i2']));
      expect(r.cancelledWithoutRecipe, 0);
    });

    test('un pedido cancelado que también viene como cobrado no se repite', () {
      final items = [
        linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
      ];
      final r = reporte(
        cancelados: [pedido(id: 'o1', items: items)],
        cobrados: [pedido(id: 'o1', status: 'PAID', items: items)],
      );

      expect(r.events, hasLength(1));
    });

    test('un producto anulado al que nunca se le preguntó nada no tiene fila ni cuenta',
        () {
      // Nunca se mandó a cocina: no hubo despensa de por medio. Tampoco entra en
      // los montos, para que lo que suma el resumen se encuentre en la lista.
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          linea(id: 'i1', name: 'Jugo', price: 30, isVoid: true),
        ]),
      ]);

      expect(r.events, isEmpty);
      expect(r.people, isEmpty);
      expect(r.cancelledValue, 0);
      expect(r.cancelledValueOrders, 0);
    });

    test('si falta quién lo anuló, dice "Sin identificar"; el id "unknown" no es una persona',
        () {
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
        ]),
        pedido(id: 'o2', status: 'PAID', items: [
          {
            ...linea(id: 'i2', name: 'Torta', price: 40, isVoid: true, returned: 0),
            'voided_by_user_id': 'unknown',
            'voided_by_user_name': 'Pedro',
          },
        ]),
      ]);

      final o1 = r.events.firstWhere((e) => e.orderId == 'o1');
      final o2 = r.events.firstWhere((e) => e.orderId == 'o2');
      expect(o1.userName, 'Sin identificar');
      expect(o2.userName, 'Pedro');
      expect(r.people.map((p) => p.userName), unorderedEquals(['Sin identificar', 'Pedro']));
    });

    test('varias personas anulan productos del mismo pedido: la fila las guarda a todas', () {
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          {
            ...linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
            'voided_by_user_id': 'u_1',
            'voided_by_user_name': 'Ana',
          },
          {
            ...linea(id: 'i2', name: 'Torta', price: 40, isVoid: true, returned: 1),
            'voided_by_user_id': 'u_2',
            'voided_by_user_name': 'Beto',
          },
        ]),
      ]);

      final e = r.events.single;
      expect(e.authors, ['Ana', 'Beto']);
      expect(e.signedBy('Beto'), isTrue);
      expect(e.value, closeTo(90, 0.001));
      expect(r.people, hasLength(2));
      // Ana perdió el suyo; Beto, uno que regresó (1 de 1).
      final ana = r.people.firstWhere((p) => p.userName == 'Ana');
      final beto = r.people.firstWhere((p) => p.userName == 'Beto');
      expect(ana.itemsLost, 1);
      expect(beto.itemsLost, 0);
      expect(beto.itemsCancelled, 1);
    });

    // Un pedido cancelado y REACTIVADO conserva las marcas de la anulación
    // (`inventory_returned_qty`, los movimientos) aunque ya no esté anulado y se
    // cobre: el POS solo limpia la cancelación. Lo perdido y la lista ya
    // cuentan esas marcas, así que "lo anulado" tiene que contarlas también o
    // el titular podría pasar del valor cancelado.
    test('pedido reactivado y cobrado: lo perdido no pasa de lo anulado', () {
      final r = reporte(
        movimientos: cervezaPerdida(),
        cobrados: [
          pedido(id: 'order_1', status: 'PAID', items: [
            // Ya no está anulada (is_void false) pero conserva la decisión.
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25, returned: 0),
          ]),
        ],
      );

      expect(r.saleWaste.amount, closeTo(100, 0.001));
      expect(r.cancelledValue, closeTo(100, 0.001));
      expect(r.cancelledValueOrders, 1);
      expect(r.saleWaste.amount, lessThanOrEqualTo(r.cancelledValue));
      // Y la fila de la lista dice lo mismo que el resumen.
      expect(r.events.single.value, closeTo(100, 0.001));
    });

    test('una decisión de inventario sin anulación cuenta en los montos, pero no se lista como cancelación', () {
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          linea(id: 'i1', name: 'Taco', price: 50, returned: 0), // sin is_void
          linea(id: 'i2', name: 'Pizza', price: 90), // nunca se preguntó
        ]),
      ]);

      expect(r.saleWaste.amount, closeTo(50, 0.001));
      expect(r.cancelledValue, closeTo(50, 0.001));
      expect(r.saleWaste.amount, lessThanOrEqualTo(r.cancelledValue));
      // Sin is_void es de un pedido cancelado y reactivado: se vendió y no hay
      // quién ni cuándo lo anuló. Cuenta en los montos (como lo perdido) pero no
      // se lista, para no acusar a nadie de lo que se cobró.
      expect(r.events, isEmpty);
      expect(r.people, isEmpty);
    });

    test('un renglón con movimiento de cancelación cuenta aunque el pedido no lo marque',
        () {
      // Marcas viejas: el movimiento existe pero el renglón no trae is_void ni
      // decisión. El movimiento manda: es lo que dice que se anuló.
      final r = reporte(
        movimientos: cervezaPerdida(),
        cobrados: [
          pedido(id: 'order_1', status: 'PAID', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25),
            linea(id: 'i2', name: 'Pizza', price: 90),
          ]),
        ],
      );

      expect(r.events.single.value, closeTo(100, 0.001));
      expect(r.cancelledValue, closeTo(100, 0.001));
      expect(r.cancelledValueOrders, 1);
    });

    test('avisa que no se leyeron los pedidos cobrados (vista de año)', () {
      expect(reporte().withoutPaidOrders, isFalse);

      final r = provider.buildForTest(movements: const [], withoutPaidOrders: true);
      expect(r.withoutPaidOrders, isTrue);
    });

    // El POS del panel (cancelar una comanda) guarda solo el id de quien anula,
    // no su nombre: sin resolverlo, "quién lo declaró" saldría "Sin
    // identificar" teniendo el id.
    test('un renglón anulado con solo el id del usuario se resuelve a su nombre', () {
      final pedidoCobrado = pedido(id: 'o1', status: 'PAID', items: [
        {
          ...linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
          'voided_by_user_id': 'u_9',
        },
      ]);

      final sinNombres = provider.buildForTest(movements: const [], paidOrders: [pedidoCobrado]);
      expect(sinNombres.events.single.userName, 'Sin identificar');

      final r = provider.buildForTest(
        movements: const [],
        paidOrders: [pedidoCobrado],
        userNames: const {'u_9': 'Rosa'},
      );
      expect(r.events.single.userName, 'Rosa');
      expect(r.events.single.authors, ['Rosa']);
      expect(r.people.single.userName, 'Rosa');
      expect(r.people.single.userId, 'u_9');
    });

    test('el nombre de un usuario se toma de cualquier registro donde aparezca', () {
      // Primero un renglón de u_1 sin nombre y después un movimiento de u_1 con
      // nombre ("Ana"): la persona tiene que llamarse Ana, no "Sin identificar"
      // por haber visto primero el registro sin nombre, y el filtro por ella
      // tiene que encontrar las dos filas.
      final r = reporte(
        movimientos: cervezaPerdida(), // orderId 'order_1', u_1 / Ana
        cobrados: [
          pedido(id: 'o2', status: 'PAID', items: [
            {
              ...linea(id: 't1', name: 'Taco', price: 50, isVoid: true, returned: 0),
              'voided_by_user_id': 'u_1',
            },
          ]),
        ],
      );

      expect(r.people, hasLength(1));
      expect(r.people.single.userName, 'Ana');
      expect(r.people.single.events, 2);
      for (final e in r.events) {
        expect(e.signedBy('Ana'), isTrue, reason: 'orden ${e.orderId}');
      }
    });

    test('"Sin identificar" es una sola tarjeta, con id "unknown" o sin nada', () {
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
        ]),
        pedido(id: 'o2', status: 'PAID', items: [
          {
            ...linea(id: 'i2', name: 'Torta', price: 40, isVoid: true, returned: 0),
            'voided_by_user_id': 'unknown',
          },
        ]),
      ]);

      expect(r.people, hasLength(1));
      expect(r.people.single.userName, 'Sin identificar');
      expect(r.people.single.events, 2);
    });

    test('los movimientos de un mismo pedido con ids distintos no cuentan dos veces un renglón',
        () {
      // El pedido se referencia por el id del documento y por su campo id, y no
      // siempre coinciden: si los movimientos usan los dos, salen dos filas, y
      // cada una agregaba como extra el renglón con movimiento de la otra.
      final porDoc = doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'a')
        ..['orderId'] = 'doc_1';
      final porId = doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'b')
        ..['orderId'] = 'id_1';
      final r = reporte(
        movimientos: [porDoc, porId],
        cobrados: [
          {
            ...pedido(id: 'id_1', status: 'PAID', items: [
              linea(id: 'a', name: 'Cerveza', qty: 2, price: 25, isVoid: true, returned: 2),
              linea(id: 'b', name: 'Refresco', price: 20, isVoid: true, returned: 1),
            ]),
            '_docId': 'doc_1',
          },
        ],
      );

      expect(r.itemsCancelled, 2, reason: 'dos renglones, no cuatro');
      final suma = r.events.fold<double>(0, (t, e) => t + (e.value ?? 0));
      expect(suma, closeTo(r.cancelledValue, 0.001));
      expect(r.cancelledValue, closeTo(70, 0.001));
    });

    test('un renglón anulado en otro período no sale como "sin receta" en este', () {
      // Un bar pasada la medianoche: el producto con receta se anuló ayer (y salió
      // ayer por sus movimientos) y el pedido se cobró hoy. Hoy no tiene
      // movimientos, pero no es sin receta: salir otra vez sería falso.
      final ayer = DateTime(2026, 8, 29, 23, 30).toIso8601String();
      final hoyMismo = DateTime(2026, 8, 30, 10).toIso8601String();
      final r = provider.buildForTest(
        movements: const [],
        range: rango,
        paidOrders: [
          pedido(id: 'o1', status: 'PAID', items: [
            {
              ...linea(id: 'i1', name: 'Cerveza', price: 25, isVoid: true, returned: 0),
              'voided_by_user_name': 'Ana',
              'voided_at': ayer,
            },
          ]),
          pedido(id: 'o2', status: 'PAID', items: [
            {
              ...linea(id: 'i2', name: 'Taco', price: 50, isVoid: true, returned: 0),
              'voided_by_user_name': 'Luis',
              'voided_at': hoyMismo,
            },
          ]),
        ],
      );

      // Solo el de hoy tiene fila y cuenta en los porcentajes.
      expect(r.events.map((e) => e.orderId), ['o2']);
      expect(r.people.map((p) => p.userName), ['Luis']);
      expect(r.itemsCancelled, 1);
      // Los montos siguen siendo los de los pedidos cobrados en el período (como
      // lo perdido): no se recortan por fecha de anulación.
      expect(r.cancelledValue, closeTo(75, 0.001));
      expect(r.saleWaste.amount, lessThanOrEqualTo(r.cancelledValue));
    });

    test('sin fecha de anulación el renglón entra: no se puede saber que es de otro período', () {
      final r = provider.buildForTest(
        movements: const [],
        range: rango,
        paidOrders: [
          pedido(id: 'o1', status: 'PAID', items: [
            linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
          ]),
        ],
      );

      expect(r.events, hasLength(1));
    });

    test('anulado en otro período sin NINGÚN movimiento: sale aquí, que es su única oportunidad',
        () {
      // Un taco sin receta anulado ayer 23:30 y cobrado hoy: ayer el pedido no
      // estaba cobrado y no salió; hoy no tiene movimiento en ninguna fecha, así
      // que es de verdad sin receta y aquí es donde tiene que aparecer.
      final ayer = DateTime(2026, 8, 29, 23, 30).toIso8601String();
      final cobrado = pedido(id: 'o1', status: 'PAID', items: [
        {
          ...linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
          'voided_by_user_name': 'Luis',
          'voided_at': ayer,
        },
      ]);

      // Averiguado: ningún movimiento en otra fecha.
      final sinMov = provider.buildForTest(
        movements: const [],
        range: rango,
        paidOrders: [cobrado],
        movidosFuera: const <String>{},
      );
      expect(sinMov.events, hasLength(1));
      expect(sinMov.events.single.userName, 'Luis');
      expect(sinMov.people.single.itemsLost, 1);

      // Tiene movimiento en otra fecha: ya salió en su período (era con receta).
      final conMov = provider.buildForTest(
        movements: const [],
        range: rango,
        paidOrders: [cobrado],
        movidosFuera: const {'i1'},
      );
      expect(conMov.events, isEmpty);

      // No se pudo averiguar: no se lista (no se arriesga una fila falsa).
      final noSe = provider.buildForTest(
        movements: const [],
        range: rango,
        paidOrders: [cobrado],
      );
      expect(noSe.events, isEmpty);

      // En los tres casos los montos son los mismos.
      for (final r in [sinMov, conMov, noSe]) {
        expect(r.cancelledValue, closeTo(50, 0.001));
      }
    });

    test('el último segundo del día entra en la lista aunque el período termine en :59', () {
      // El período acaba en 23:59:59 sin milisegundos.
      final casiMedianoche =
          DateTime(2026, 8, 30, 23, 59, 59, 500).toIso8601String();
      final r = provider.buildForTest(
        movements: const [],
        range: rango,
        paidOrders: [
          pedido(id: 'o1', status: 'PAID', items: [
            {
              ...linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
              'voided_at': casiMedianoche,
            },
          ]),
        ],
      );

      expect(r.events, hasLength(1));
    });

    test('un pedido cancelado hoy no lista un renglón anulado antes en otro período', () {
      // Cancelado hoy; un renglón con receta se anuló ayer (y salió ayer por su
      // movimiento): hoy no tiene movimiento, pero no es sin receta.
      final ayer = DateTime(2026, 8, 29, 22).toIso8601String();
      final cancelado = pedido(id: 'o1', items: [
        {
          ...linea(id: 'i1', name: 'Cerveza', price: 25, isVoid: true, returned: 0),
          'voided_by_user_name': 'Beto',
          'voided_at': ayer,
        },
        linea(id: 'i2', name: 'Taco', price: 50, returned: 0),
      ]);

      List<String> listados(Set<String>? fuera) => provider
          .buildForTest(
            movements: const [],
            range: rango,
            cancelledOrders: [cancelado],
            movidosFuera: fuera,
          )
          .events
          .single
          .items
          .map((i) => i.itemId)
          .toList();

      expect(listados(const {'i1'}), ['i2'], reason: 'ya salió ayer por su movimiento');
      expect(listados(null), ['i2'], reason: 'sin saberlo no se lista');
      expect(listados(const <String>{}), containsAll(['i1', 'i2']),
          reason: 'sin movimiento en ninguna fecha es de verdad sin receta');
    });

    test('un renglón sin receta no se repite en cada fila cuando los movimientos usan dos ids de pedido',
        () {
      final porDoc = doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'a')
        ..['orderId'] = 'doc_1';
      final porId = doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'b')
        ..['orderId'] = 'id_1';
      final r = reporte(
        movimientos: [porDoc, porId],
        cobrados: [
          {
            ...pedido(id: 'id_1', status: 'PAID', items: [
              linea(id: 'a', name: 'Cerveza', qty: 2, price: 25, isVoid: true, returned: 2),
              linea(id: 'b', name: 'Refresco', price: 20, isVoid: true, returned: 1),
              {
                ...linea(id: 't', name: 'Taco', price: 50, isVoid: true, returned: 0),
                'voided_by_user_id': 'u_5',
                'voided_by_user_name': 'Eva',
              },
            ]),
            '_docId': 'doc_1',
          },
        ],
      );

      final conTaco = r.events.where((e) => e.items.any((i) => i.itemId == 't'));
      expect(conTaco, hasLength(1), reason: 'el taco sale en una sola fila');
      expect(r.itemsCancelled, 3, reason: 'cerveza, refresco y taco');
      final suma = r.events.fold<double>(0, (t, e) => t + (e.value ?? 0));
      expect(suma, closeTo(r.cancelledValue, 0.001));
      expect(r.people.firstWhere((p) => p.userName == 'Eva').itemsCancelled, 1);
    });

    test('un usuario con dos nombres en dos registros: la fila y la tarjeta dicen lo mismo', () {
      final r = reporte(movimientos: [
        doc(type: 'devolucionCancelacion', quantity: 2.0, itemId: 'a'),
        {
          ...doc(type: 'devolucionCancelacion', quantity: 1.0, itemId: 'b'),
          'createdByUserName': 'Ana L.',
        },
      ]);

      expect(r.people, hasLength(1));
      expect(r.people.single.userName, 'Ana');
      final e = r.events.single;
      expect(e.userName, 'Ana');
      expect(e.authors, ['Ana'], reason: 'una persona, un rótulo');
    });

    test('varios ids que nadie puede nombrar son una sola tarjeta "Sin identificar"', () {
      final r = reporte(cobrados: [
        for (final id in ['u_7', 'u_8', ''])
          pedido(id: 'o$id', status: 'PAID', items: [
            {
              ...linea(id: 'i$id', name: 'Taco', price: 50, isVoid: true, returned: 0),
              if (id.isNotEmpty) 'voided_by_user_id': id,
            },
          ]),
      ]);

      expect(r.people, hasLength(1));
      expect(r.people.single.userName, 'Sin identificar');
      expect(r.people.single.events, 3);
    });

    test('un renglón anulado sin quién no se acredita a quien firmó otro renglón', () {
      // Beto firmó el movimiento de la cerveza; el taco sin receta no dice quién
      // lo anuló: no es de Beto.
      final porBeto = {
        ...doc(type: 'devolucionCancelacion', quantity: 4.0, itemId: 'i1'),
        'createdByUserId': 'u_2',
        'createdByUserName': 'Beto',
      };
      final r = reporte(
        movimientos: [porBeto],
        cobrados: [
          pedido(id: 'order_1', status: 'PAID', items: [
            linea(id: 'i1', name: 'Cerveza', qty: 4, price: 25, isVoid: true, returned: 4),
            linea(id: 't1', name: 'Taco', price: 50, isVoid: true, returned: 0),
          ]),
        ],
      );

      final beto = r.people.firstWhere((p) => p.userName == 'Beto');
      final nadie = r.people.firstWhere((p) => p.userName == 'Sin identificar');
      expect(beto.itemsCancelled, 1);
      expect(beto.itemsLost, 0);
      expect(nadie.itemsCancelled, 1);
      expect(nadie.itemsLost, 1);
    });

    test('las filas de un pedido cobrado traen el motivo del renglón', () {
      final r = reporte(cobrados: [
        pedido(id: 'o1', status: 'PAID', items: [
          {
            ...linea(id: 'i1', name: 'Taco', price: 50, isVoid: true, returned: 0),
            'void_reason': 'Se cayó',
          },
          {
            ...linea(id: 'i2', name: 'Torta', price: 40, isVoid: true, returned: 1),
            'void_reason': 'Cliente cambió de opinión',
          },
        ]),
      ]);

      // Una sola fila por pedido: el primer motivo escrito.
      expect(r.events.single.reason, 'Se cayó');
      expect(r.events.single.items, hasLength(2));
    });
  });
}
