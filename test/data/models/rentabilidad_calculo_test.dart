import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/data/models/rentabilidad_calculo.dart';

/// La cuenta de Rentabilidad que antes vivía en el provider. Se prueba aquí con
/// números a mano: un error produce un número creíble y equivocado.

Map<String, dynamic> pedido(String loc, {double? pago, double? total, double propina = 0, double envio = 0}) => {
      'location_id': loc,
      if (pago != null) 'payment_amount': pago,
      if (total != null) 'total_amount': total,
      'tip_amount': propina,
      'delivery_fee': envio,
    };

Map<String, dynamic> gasto(String loc, double monto, String cat, {String? nombre, String? tipo, String? fuente}) => {
      'location_id': loc,
      'amount': monto,
      'category_id': cat,
      'category_name': nombre ?? cat,
      if (tipo != null) 'type': tipo,
      if (fuente != null) 'source': fuente,
    };

final ordenes = [
  pedido('A', pago: 1000, propina: 100, envio: 50), // neto 850
  pedido('B', total: 500), // neto 500 (sin payment_amount)
];

final gastos = [
  gasto('A', 300, 'renta', nombre: 'Renta', tipo: 'variable'), // fijo por categoría
  gasto('A', 200, 'salarios', nombre: 'Sueldos', fuente: 'cashRegister'),
  gasto('A', 50, 'luz', nombre: 'Luz', tipo: 'variable'),
  gasto('B', 100, 'internet', nombre: 'Internet'),
  gasto('A', 0, 'otros'), // en cero: no cuenta
];

const costo = CostoLeido(
  total: 400,
  exactos: 8,
  estimados: 1,
  sinCosto: 1,
  comprado: 70,
  entradasSinCosto: 2,
  porSucursal: {
    'A': CostoLeido(total: 300, exactos: 6, estimados: 0, sinCosto: 1),
    'B': CostoLeido(total: 100, exactos: 2, estimados: 1, sinCosto: 0),
  },
);

ProfitabilityData armar({
  String? sucursal,
  double? metricas,
  CostoLeido c = costo,
  CargosPreproduccion prepro = const CargosPreproduccion(),
  List<Map<String, dynamic>>? compras,
}) =>
    armarRentabilidad(
      ordenes: ordenes,
      gastos: gastos,
      compras: compras ?? const [],
      sucursal: sucursal,
      ventaDeMetricas: metricas,
      costo: c,
      valorInventario: 999,
      ingredientesSinPrecio: 3,
      existenciasImposibles: const ['Sal'],
      prepro: prepro,
    );

void main() {
  group('esGastoFijo', () {
    test('por el tipo, por la categoría o ninguno', () {
      expect(esGastoFijo({'type': 'fixed', 'category_id': 'luz'}), isTrue);
      // Los retiros de caja llegan como 'variable' aunque sean la renta.
      expect(esGastoFijo({'type': 'variable', 'category_id': 'renta'}), isTrue);
      expect(esGastoFijo({'category_id': 'salarios'}), isTrue);
      expect(esGastoFijo({'category_id': 'internet'}), isTrue);
      expect(esGastoFijo({'category_id': 'seguros'}), isTrue);
      expect(esGastoFijo({'type': 'variable', 'category_id': 'luz'}), isFalse);
      // Sin categoría es "otros": variable, ante la duda.
      expect(esGastoFijo({}), isFalse);
      expect(esGastoFijo({'type': 'variable'}), isFalse);
      // Un dato roto no lanza: cuenta como "otros".
      expect(esGastoFijo({'category_id': 5}), isFalse);
      expect(esGastoFijo({'category_id': 5, 'type': 'fixed'}), isTrue);
    });
  });

  group('la venta neta', () {
    test('cobrado menos propina y envío; sin payment_amount, el total', () {
      final d = armar();
      expect(d.netSales, 850 + 500);
    });

    test('con una sucursal, solo lo suyo', () {
      expect(armar(sucursal: 'A').netSales, 850);
      expect(armar(sucursal: 'B').netSales, 500);
    });

    test('en la vista de año la venta sale de las métricas, no de los pedidos', () {
      expect(armar(metricas: 12345).netSales, 12345);
    });

    test('un pedido sin ningún monto no rompe nada', () {
      final d = armarRentabilidad(
        ordenes: [
          {'location_id': 'A'},
          {'location_id': 'A', 'payment_amount': 10},
        ],
        gastos: const [],
        compras: const [],
        costo: CostoLeido.vacio,
        prepro: const CargosPreproduccion(),
      );
      expect(d.netSales, 10);
    });
  });

  group('los gastos', () {
    test('se agrupan por categoría, de mayor a menor, sin los de monto cero', () {
      final d = armar();
      expect(d.expenses.map((e) => e.categoryId), ['renta', 'salarios', 'internet', 'luz']);
      expect(d.totalExpenses, 650);
    });

    test('fijo = por el tipo o por la categoría; la luz es variable', () {
      final d = armar();
      expect({for (final e in d.expenses) e.categoryId: e.esFijo}, {
        'renta': true,
        'salarios': true,
        'internet': true,
        'luz': false,
      });
      expect(d.fixedCosts, 600);
      expect(d.sinCostosFijos, isFalse);
    });

    test('los sueldos aparte, y lo pagado por caja se mide pero ya va dentro', () {
      final d = armar();
      expect(d.payroll, 200);
      expect(d.paidFromCash, 200);
      expect(d.totalExpenses, 650);
    });

    test('solo los de la sucursal pedida', () {
      final a = armar(sucursal: 'A');
      expect(a.totalExpenses, 550);
      expect(a.fixedCosts, 500);
      final b = armar(sucursal: 'B');
      expect(b.totalExpenses, 100);
      expect(b.payroll, 0);
    });
  });

  group('el costo, el inventario y lo demás pasan tal cual', () {
    test('costo de lo vendido y cobertura', () {
      final d = armar();
      expect(d.cogs, 400);
      expect(d.itemsConCosto, 8);
      expect(d.itemsEstimados, 1);
      expect(d.itemsSinCosto, 1);
      expect(d.inventoryValue, 999);
      expect(d.ingredientesSinPrecio, 3);
      expect(d.existenciasImposibles, ['Sal']);
    });

    test('lo invertido sale de las entradas; sin entradas, de las compras', () {
      expect(armar().purchases, 70);
      expect(armar().entradasSinCosto, 2);
      final sinEntradas = armar(
        c: const CostoLeido(total: 400, exactos: 1, estimados: 0, sinCosto: 0),
        compras: [
          {'location_id': 'A', 'total': 30},
          {'location_id': 'B', 'total': 20},
        ],
      );
      expect(sinEntradas.purchases, 50);
      expect(armar(sucursal: 'A', c: const CostoLeido(total: 1, exactos: 1, estimados: 0, sinCosto: 0), compras: [
        {'location_id': 'A', 'total': 30},
        {'location_id': 'B', 'total': 20},
      ]).purchases, 30);
    });
  });

  group('la preproducción', () {
    test('se resta de su categoría y también del costo primo', () {
      // Q50 de mano de obra cargados a preparados.
      const prepro = CargosPreproduccion(porCategoria: {'salarios': 5000});
      final d = armar(prepro: prepro);
      final sueldos = d.expenses.firstWhere((e) => e.categoryId == 'salarios');
      expect(sueldos.amount, 150);
      expect(d.payroll, 150);
      expect(d.restadoPreproduccion, 50);
      expect(d.cargadoPreproduccion, 50);
      expect(d.totalExpenses, 600);
    });

    test('no se resta de más: lo que sobra se avisa y la categoría queda en cero', () {
      // Q80 de luz cargados, solo Q50 anotados en Gastos.
      const prepro = CargosPreproduccion(porCategoria: {'luz': 8000});
      final d = armar(prepro: prepro);
      expect(d.expenses.firstWhere((e) => e.categoryId == 'luz').amount, 0);
      expect(d.restadoPreproduccion, 50);
      expect(d.excesosPreproduccion.single.categoria, 'luz');
    });

    test('no leída: no se resta nada y se dice', () {
      final d = armar(prepro: CargosPreproduccion.noLeida);
      expect(d.totalExpenses, 650);
      expect(d.preproduccionLeida, isFalse);
    });
  });

  group('por sucursal con la misma cuenta que el total', () {
    test('las ventas, los gastos y el costo de las sucursales suman el total', () {
      final a = armar(sucursal: 'A', c: costo.porSucursal['A']!);
      final b = armar(sucursal: 'B', c: costo.porSucursal['B']!);
      final todas = armar();
      expect(a.netSales + b.netSales, todas.netSales);
      expect(a.totalExpenses + b.totalExpenses, todas.totalExpenses);
      expect(a.cogs + b.cogs, todas.cogs);
      expect(a.operatingProfit + b.operatingProfit, todas.operatingProfit);
      expect(a.fixedCosts + b.fixedCosts, todas.fixedCosts);
      expect(a.itemsConCosto + b.itemsConCosto, todas.itemsConCosto);
    });

    test('la utilidad de cada una: ventas − costo − todos sus gastos', () {
      final a = armar(sucursal: 'A', c: costo.porSucursal['A']!);
      expect(a.operatingProfit, 850 - 300 - 550);
      final b = armar(sucursal: 'B', c: costo.porSucursal['B']!);
      expect(b.operatingProfit, 500 - 100 - 100);
    });
  });
}
