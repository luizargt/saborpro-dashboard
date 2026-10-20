// test/data/models/config_moneda_test.dart
//
// Tipos de cambio con fecha de inicio: cada venta se convierte con el que
// estaba vigente el día que se cobró, el primero vale para todo lo anterior,
// y ajustar uno no reescribe lo de antes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/sales_aggregates_service.dart';
import 'package:saborpro_reports/data/models/config_moneda.dart';

void main() {
  // 1 Q = 100 $ desde el 1 de enero; 1 Q = 125 $ desde el 15 de marzo.
  final config = const ConfigMoneda(principal: 'GTQ')
      .conTasa('ARS', TasaCambio(desde: DateTime(2026, 3, 15), valor: 125))
      .conTasa('ARS', TasaCambio(desde: DateTime(2026, 1, 1), valor: 100));

  group('qué tipo de cambio vale cada día', () {
    test('el vigente es el último que empezó ese día o antes', () {
      expect(config.tasaEn('ARS', DateTime(2026, 2, 10))!.valor, 100);
      expect(config.tasaEn('ARS', DateTime(2026, 3, 14, 23, 59))!.valor, 100);
      expect(config.tasaEn('ARS', DateTime(2026, 3, 15))!.valor, 125);
      expect(config.tasaEn('ARS', DateTime(2026, 9, 1))!.valor, 125);
    });

    test('lo anterior al primero usa el primero', () {
      expect(config.tasaEn('ARS', DateTime(2025, 6, 1))!.valor, 100);
    });

    test('el factor pasa a la principal; la principal no se toca; sin tasa no hay factor', () {
      expect(config.factor('ARS', 'GTQ', DateTime(2026, 2, 1)), closeTo(0.01, 1e-12));
      expect(config.factor('ARS', 'GTQ', DateTime(2026, 4, 1)), closeTo(0.008, 1e-12));
      expect(config.factor('GTQ', 'GTQ', DateTime(2026, 4, 1)), 1);
      expect(config.factor('MXN', 'GTQ', DateTime(2026, 4, 1)), isNull);
    });
  });

  group('cortes y firma', () {
    test('los cortes son los días en que cambia la tasa dentro del rango', () {
      expect(config.cortes('ARS', DateTime(2026, 3, 1), DateTime(2026, 4, 1)), [DateTime(2026, 3, 15)]);
      expect(config.cortes('ARS', DateTime(2026, 4, 1), DateTime(2026, 5, 1)), isEmpty);
    });

    test('la firma de un mes cambia solo si cambia una tasa que lo toca', () {
      String mes(ConfigMoneda c, int m) =>
          c.firma('GTQ', {'GTQ', 'ARS'}, DateTime(2026, m, 1), DateTime(2026, m + 1, 1));
      final ajustada = config.conTasa('ARS', TasaCambio(desde: DateTime(2026, 6, 10), valor: 140));
      expect(mes(ajustada, 2), mes(config, 2), reason: 'febrero no se toca');
      expect(mes(ajustada, 6), isNot(mes(config, 6)), reason: 'junio sí');
      expect(mes(ajustada, 7), isNot(mes(config, 7)), reason: 'y lo de después también');
    });

    test('sin tasa la firma lo dice: al ponerla, lo guardado se rehace', () {
      final sin = const ConfigMoneda(principal: 'GTQ');
      final f = sin.firma('GTQ', {'GTQ', 'ARS'}, DateTime(2026, 1, 1), DateTime(2026, 2, 1));
      expect(f, contains('ARS=sin'));
      expect(config.firma('GTQ', {'GTQ', 'ARS'}, DateTime(2026, 1, 1), DateTime(2026, 2, 1)), isNot(f));
    });
  });

  group('editar', () {
    test('el mismo día reemplaza en vez de duplicar', () {
      final c = config.conTasa('ARS', TasaCambio(desde: DateTime(2026, 3, 15), valor: 130));
      expect(c.tasas['ARS']!.map((t) => t.valor), [100, 130]);
    });

    test('borrar uno deja que el anterior siga valiendo', () {
      final c = config.sinTasa('ARS', DateTime(2026, 3, 15));
      expect(c.tasaEn('ARS', DateTime(2026, 9, 1))!.valor, 100);
    });

    test('cambiar la principal borra los tipos de cambio', () {
      final c = config.conPrincipal('USD');
      expect(c.principal, 'USD');
      expect(c.tasas, isEmpty);
      expect(identical(config.conPrincipal('GTQ'), config), isTrue);
    });

    test('se guarda y se lee igual', () {
      final leida = ConfigMoneda.fromMap(config.toMap());
      expect(leida.principal, 'GTQ');
      expect(leida.tasas['ARS']!.map((t) => (t.desde, t.valor)),
          [(DateTime(2026, 1, 1), 100.0), (DateTime(2026, 3, 15), 125.0)]);
    });

    test('lo mal guardado se ignora en vez de romper', () {
      final c = ConfigMoneda.fromMap({
        'principal_currency': '',
        'rates': {
          'ARS': [
            {'from': '2026-01-01', 'value': 0},
            {'from': 'ayer', 'value': 10},
            {'from': '2026-02-01', 'value': 90},
          ],
          'MXN': 'no es lista',
        },
      });
      expect(c.principal, isNull);
      expect(c.tasas.keys, ['ARS']);
      expect(c.tasas['ARS']!.single.valor, 90);
    });
  });

  group('convertir una fila', () {
    test('multiplica el dinero a cualquier profundidad y deja lo demás', () {
      final cobro = Timestamp.fromDate(DateTime(2026, 3, 20));
      final orden = <String, dynamic>{
        'location_id': 'palermo',
        'paid_at': cobro,
        'payment_amount': 1000,
        'total_amount': 900,
        'tip_amount': 100,
        'items': [
          {
            'qty': 2,
            'unit_price': 400,
            'modifiers': [
              {'name': 'Queso', 'price': 50, 'quantity': 1}
            ],
          },
        ],
        'split_payments': [
          {'payment_method': 'cash', 'amount': 600},
          {'payment_method': 'card', 'amount': 400},
        ],
      };
      final r = convertirFila(orden, 0.008);
      expect(r['payment_amount'], closeTo(8, 1e-9));
      expect(r['total_amount'], closeTo(7.2, 1e-9));
      expect(r['tip_amount'], closeTo(0.8, 1e-9));
      final item = (r['items'] as List).single as Map;
      expect(item['qty'], 2);
      expect(item['unit_price'], closeTo(3.2, 1e-9));
      expect(((item['modifiers'] as List).single as Map)['price'], closeTo(0.4, 1e-9));
      expect(((item['modifiers'] as List).single as Map)['quantity'], 1);
      expect(((r['split_payments'] as List).first as Map)['amount'], closeTo(4.8, 1e-9));
      expect(r['paid_at'], cobro);
      expect(r['location_id'], 'palermo');
      // La original no se toca: el crudo se reusa al cambiar de pestaña.
      expect(orden['payment_amount'], 1000);
    });

    test('con factor 1 no copia', () {
      final f = <String, dynamic>{'amount': 5};
      expect(identical(convertirFila(f, 1), f), isTrue);
    });
  });

  group('tramos de las sumas del año', () {
    test('un mes sin cambio de tasa es un solo tramo', () {
      expect(tramosEntre(DateTime(2026, 4, 1), DateTime(2026, 5, 1), [DateTime(2026, 3, 15)]),
          [(DateTime(2026, 4, 1), DateTime(2026, 5, 1))]);
    });

    test('un cambio a mitad de mes lo parte en dos', () {
      expect(tramosEntre(DateTime(2026, 3, 1), DateTime(2026, 4, 1), [DateTime(2026, 3, 15)]), [
        (DateTime(2026, 3, 1), DateTime(2026, 3, 15)),
        (DateTime(2026, 3, 15), DateTime(2026, 4, 1)),
      ]);
    });

    test('un cambio justo en el borde no crea un tramo vacío', () {
      expect(tramosEntre(DateTime(2026, 1, 1), DateTime(2026, 2, 1), [DateTime(2026, 1, 1)]),
          [(DateTime(2026, 1, 1), DateTime(2026, 2, 1))]);
    });

    test('sin tipo de cambio la sucursal vale cero', () {
      final c = ConversionSucursal.excluida();
      expect(c.excluida, isTrue);
      expect(c.factorEn(DateTime(2026, 3, 1)), 0);
    });
  });
}
