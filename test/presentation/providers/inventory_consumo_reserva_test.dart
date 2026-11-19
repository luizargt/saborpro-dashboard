// test/presentation/providers/inventory_consumo_reserva_test.dart
//
// El consumo del inventario en Sabor Reports cuenta lo consumido de las
// reservas que se cierran en la Despensa del POS. Ese movimiento
// (`consumoReserva`) trae `quantity` 0 —el stock ya había bajado al reservar—
// y lo consumido en `consumedQuantity`. La reserva y lo que regresó no son
// consumo, y ventas y salidas manuales se cuentan igual que siempre.

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/providers/inventory_provider.dart';

void main() {
  double? consumo(Map<String, dynamic> m) => InventoryProvider.cantidadConsumida(m);

  test('ventas y salidas manuales: la cantidad, como siempre', () {
    expect(consumo({'type': 'salidaVenta', 'quantity': -3}), 3);
    expect(consumo({'type': 'salidaManual', 'quantity': -1.5}), 1.5);
  });

  test('lo consumido de una reserva cuenta por consumedQuantity', () {
    expect(consumo({'type': 'consumoReserva', 'quantity': 0, 'consumedQuantity': 25}), 25);
  });

  test('la reserva y su devolución no son consumo', () {
    expect(consumo({'type': 'reserva', 'quantity': -50}), isNull);
    expect(consumo({'type': 'devolucionReserva', 'quantity': 25}), isNull);
    expect(consumo({'type': 'entrada', 'quantity': 10}), isNull);
    expect(consumo({'type': 'ajuste', 'quantity': -2}), isNull);
  });

  test('un valor ilegible no cuenta ni revienta', () {
    expect(consumo({'type': 'consumoReserva', 'consumedQuantity': 'mucho'}), 0);
    expect(consumo({'type': 'salidaVenta', 'quantity': 'x'}), 0);
  });
}
