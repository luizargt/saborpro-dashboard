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
}
