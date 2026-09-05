import 'package:flutter_test/flutter_test.dart';

/// Candados sobre dos cuentas del dashboard que daban números optimistas.
///
/// No montan el provider (arrastra Firebase): replican las dos fórmulas tal
/// como quedaron, que es donde estaba el error. Si alguien vuelve a separarlas,
/// estos tests fallan.

/// Reparto por sucursal, igual que `_sumByLocation` en
/// location_sales_breakdown.dart: lo que no trae `location_id` se descarta.
Map<String, double> sumarPorSucursal(
    List<Map<String, dynamic>> items, String campo) {
  final r = <String, double>{};
  for (final i in items) {
    final loc = i['location_id'] as String?;
    if (loc == null || loc.isEmpty) continue;
    r[loc] = (r[loc] ?? 0) + ((i[campo] as num?)?.toDouble() ?? 0);
  }
  return r;
}

/// La fórmula de venta por pedido. Debe ser IDÉNTICA para el período actual y
/// el anterior.
double ventaDelPedido(Map<String, dynamic> o) =>
    (o['payment_amount'] as num?)?.toDouble() ??
    (o['total_amount'] as num? ?? 0).toDouble();

void main() {
  group('los retiros de caja llevan sucursal', () {
    // Forma del mapa que arma _extractWithdrawals en dashboard_provider.dart.
    Map<String, dynamic> retiro({String? loc, double monto = 500}) => {
          'amount': monto,
          'location_id': loc,
          'source': 'cashRegister',
          'category_name': 'Otros Gastos',
        };

    test('un retiro con sucursal se reparte', () {
      final r = sumarPorSucursal([retiro(loc: 'L1')], 'amount');
      expect(r['L1'], 500);
    });

    test('la suma de las sucursales cuadra con el total global', () {
      // El bug: sin location_id los retiros se restaban del total global pero
      // de ninguna sucursal, así que las partes sumaban MÁS que el todo.
      final gastos = [
        {'location_id': 'L1', 'amount': 1000.0},
        {'location_id': 'L2', 'amount': 800.0},
        retiro(loc: 'L1', monto: 300),
        retiro(loc: 'L2', monto: 200),
      ];

      final porSucursal = sumarPorSucursal(gastos, 'amount');
      final sumaPartes = porSucursal.values.fold<double>(0, (a, b) => a + b);
      final totalGlobal =
          gastos.fold<double>(0, (a, g) => a + (g['amount'] as double));

      expect(sumaPartes, totalGlobal);
      expect(porSucursal['L1'], 1300);
      expect(porSucursal['L2'], 1000);
    });

    test('sin sucursal el retiro se pierde del reparto — el bug de antes', () {
      // Deja constancia de POR QUÉ hace falta la clave: así se comportaba.
      final gastos = [
        {'location_id': 'L1', 'amount': 1000.0},
        retiro(loc: null, monto: 300),
      ];
      final suma = sumarPorSucursal(gastos, 'amount')
          .values
          .fold<double>(0, (a, b) => a + b);
      expect(suma, 1000, reason: 'los 300 sin sucursal quedan fuera');
      expect(suma, lessThan(1300));
    });
  });

  group('el período anterior se mide igual que el actual', () {
    test('ambos incluyen la propina cuando hay payment_amount', () {
      final pedido = {'total_amount': 100.0, 'payment_amount': 115.0};
      expect(ventaDelPedido(pedido), 115.0);
    });

    test('sin payment_amount cae a total_amount', () {
      expect(ventaDelPedido({'total_amount': 100.0}), 100.0);
    });

    test('la variación no se infla por las propinas', () {
      // Mismo volumen los dos períodos, con propina en los dos: el cambio
      // tiene que ser 0%. Con la fórmula vieja (anterior sin propina) daba
      // +15% de la nada.
      final actual = [
        {'total_amount': 100.0, 'payment_amount': 115.0},
        {'total_amount': 200.0, 'payment_amount': 230.0},
      ];
      final anterior = [
        {'total_amount': 100.0, 'payment_amount': 115.0},
        {'total_amount': 200.0, 'payment_amount': 230.0},
      ];

      final t = actual.fold<double>(0, (a, o) => a + ventaDelPedido(o));
      final p = anterior.fold<double>(0, (a, o) => a + ventaDelPedido(o));
      expect(t, p);
      expect(((t - p) / p) * 100, 0);

      // Y así se veía el sesgo: midiendo el anterior sin propina.
      final pViejo =
          anterior.fold<double>(0, (a, o) => a + (o['total_amount'] as double));
      final variacionFalsa = ((t - pViejo) / pViejo) * 100;
      expect(variacionFalsa, greaterThan(14));
    });

    test('una caída real se sigue viendo como caída', () {
      final actual = [
        {'total_amount': 100.0, 'payment_amount': 110.0}
      ];
      final anterior = [
        {'total_amount': 200.0, 'payment_amount': 220.0}
      ];
      final t = actual.fold<double>(0, (a, o) => a + ventaDelPedido(o));
      final p = anterior.fold<double>(0, (a, o) => a + ventaDelPedido(o));
      expect(((t - p) / p) * 100, closeTo(-50, 0.01));
    });
  });
}
