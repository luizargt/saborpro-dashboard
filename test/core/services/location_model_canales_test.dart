import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/location_service.dart';

/// Los canales de venta de una sucursal (`settings.sales_channels`): el Inicio
/// habla de hospedaje solo si vende habitaciones (canal `room_service`).
void main() {
  group('LocationModel.canalesDe', () {
    test('lee la lista y descarta lo que no es texto', () {
      expect(
        LocationModel.canalesDe({'sales_channels': ['dine_in', 'room_service', 7, null]}),
        ['dine_in', 'room_service'],
      );
    });

    test('sin lista (o con otra cosa) no se sabe: nulo', () {
      expect(LocationModel.canalesDe(null), isNull);
      expect(LocationModel.canalesDe('texto'), isNull);
      expect(LocationModel.canalesDe({'currency_symbol': 'Q'}), isNull);
      expect(LocationModel.canalesDe({'sales_channels': 'room_service'}), isNull);
    });

    test('una lista vacía es una lista: ningún canal', () {
      expect(LocationModel.canalesDe({'sales_channels': <String>[]}), isEmpty);
    });
  });

  group('LocationModel.vendeHabitaciones', () {
    test('solo con el canal room_service', () {
      expect(LocationModel(id: '1', name: 'Hotel', salesChannels: const ['room_service', 'quick_sale']).vendeHabitaciones, isTrue);
      expect(LocationModel(id: '2', name: 'Restaurante', salesChannels: const ['dine_in', 'takeout']).vendeHabitaciones, isFalse);
      expect(LocationModel(id: '3', name: 'Sin lista').vendeHabitaciones, isFalse);
      expect(LocationModel(id: '4', name: 'Vacía', salesChannels: const []).vendeHabitaciones, isFalse);
    });
  });
}
