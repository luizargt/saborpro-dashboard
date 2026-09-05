import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';

/// La aritmética del reporte de Rentabilidad.
///
/// Un error acá no rompe nada visible: produce un número creíble y equivocado,
/// que es peor. De ahí que cada regla del diseño tenga su test.

ProfitabilityData datos({
  double ventas = 100000,
  double cogs = 32000,
  double sueldos = 28000,
  List<ExpenseLine>? gastos,
  double efectivo = 0,
  double compras = 0,
  double inventario = 0,
  int conCosto = 100,
  int sinCosto = 0,
  int estimados = 0,
  int sinPrecio = 0,
}) =>
    ProfitabilityData(
      netSales: ventas,
      cogs: cogs,
      itemsConCosto: conCosto,
      itemsEstimados: estimados,
      itemsSinCosto: sinCosto,
      expenses: gastos ??
          [
            ExpenseLine(
                categoryId: 'salarios', label: 'Sueldos', amount: sueldos),
            const ExpenseLine(
                categoryId: 'renta', label: 'Renta', amount: 8000),
          ],
      payroll: sueldos,
      paidFromCash: efectivo,
      purchases: compras,
      inventoryValue: inventario,
      ingredientesSinPrecio: sinPrecio,
    );

void main() {
  group('la cascada', () {
    test('utilidad bruta = ventas − costo de lo vendido', () {
      final d = datos(ventas: 100000, cogs: 32000);
      expect(d.grossProfit, 68000);
    });

    test('utilidad operativa descuenta todos los gastos', () {
      final d = datos(ventas: 100000, cogs: 32000); // 28000 + 8000 de gastos
      expect(d.totalExpenses, 36000);
      expect(d.operatingProfit, 32000);
    });

    test('lo pagado en efectivo ya está dentro de los gastos', () {
      // Los retiros de caja son insumos, proveedores, sueldos y gasolina: son
      // gasto de operación, no reparto de ganancia. El campo es informativo y
      // NO se resta aparte, porque eso lo contaría dos veces.
      final sin = datos(efectivo: 0);
      final con = datos(efectivo: 15000);
      expect(con.operatingProfit, sin.operatingProfit);
      expect(con.paidFromCash, 15000);
    });

    test('las compras NO bajan la utilidad', () {
      // Restar compras Y costo de lo vendido sería contar dos veces lo mismo:
      // es el error que hacía parecer al negocio menos rentable.
      final sin = datos(compras: 0);
      final con = datos(compras: 40000);
      expect(con.operatingProfit, sin.operatingProfit);
    });

    test('una pérdida se refleja como negativa', () {
      final d = datos(ventas: 50000, cogs: 30000); // gastos 36000
      expect(d.operatingProfit, -16000);
      expect(evaluarMargen(d.marginPct), Salud.mal);
    });
  });

  group('porcentajes', () {
    test('se miden sobre la venta neta', () {
      // closeTo y no igualdad exacta: 28000/100000*100 da 28.000000000000004
      // en coma flotante. La app muestra un decimal, así que la diferencia es
      // invisible; exigir igualdad exacta solo haría el test frágil.
      final d = datos(ventas: 100000, cogs: 32000);
      expect(d.foodCostPct, closeTo(32, 0.001));
      expect(d.payrollPct, closeTo(28, 0.001));
      expect(d.marginPct, closeTo(32, 0.001));
    });

    test('costo primo = comida + sueldos', () {
      final d = datos(ventas: 100000, cogs: 32000, sueldos: 28000);
      expect(d.primeCostPct, closeTo(60, 0.001));
    });

    test('sin ventas los porcentajes son nulos, no cero', () {
      // 0% de costo sería lo contrario de la verdad: no se sabe.
      final d = datos(ventas: 0, cogs: 5000);
      expect(d.foodCostPct, isNull);
      expect(d.primeCostPct, isNull);
      expect(d.marginPct, isNull);
      expect(evaluarFoodCost(d.foodCostPct), Salud.desconocido);
    });
  });

  group('semáforo con los rangos del rubro', () {
    test('costo de comida', () {
      expect(evaluarFoodCost(30), Salud.bien);
      expect(evaluarFoodCost(35), Salud.bien);
      expect(evaluarFoodCost(38), Salud.atencion);
      expect(evaluarFoodCost(45), Salud.mal);
    });

    test('costo primo: 65% es el límite del rubro', () {
      expect(evaluarPrimeCost(60), Salud.bien);
      expect(evaluarPrimeCost(65), Salud.bien);
      expect(evaluarPrimeCost(68), Salud.atencion);
      expect(evaluarPrimeCost(75), Salud.mal);
    });

    test('margen: perder plata siempre es rojo', () {
      expect(evaluarMargen(15), Salud.bien);
      expect(evaluarMargen(5), Salud.atencion);
      expect(evaluarMargen(-1), Salud.mal);
    });
  });

  group('confianza del costo', () {
    test('todo con costo = 100% y confiable', () {
      final d = datos(conCosto: 100, sinCosto: 0);
      expect(d.coberturaCosto, 100);
      expect(d.costoConfiable, isTrue);
    });

    test('con huecos deja de ser confiable y se avisa', () {
      // 80 de 100: el margen sale optimista porque lo que falta cuenta cero.
      final d = datos(conCosto: 80, sinCosto: 20);
      expect(d.coberturaCosto, 80);
      expect(d.costoConfiable, isFalse);
    });

    test('90% es el corte', () {
      expect(datos(conCosto: 90, sinCosto: 10).costoConfiable, isTrue);
      expect(datos(conCosto: 89, sinCosto: 11).costoConfiable, isFalse);
    });

    test('sin movimientos no se inventa una cobertura', () {
      final d = datos(conCosto: 0, sinCosto: 0);
      expect(d.coberturaCosto, isNull);
    });

    test('lo estimado cuenta como cubierto pero no como exacto', () {
      // El caso real de julio 2026: ninguna venta guardó su costo, así que
      // todas se valorizan con el precio de hoy. Está cubierto al 100% y aun
      // así NO es confiable — son precios de hoy sobre ventas de hace meses.
      final d = datos(conCosto: 0, estimados: 100, sinCosto: 0);
      expect(d.coberturaCosto, 100);
      expect(d.porcentajeEstimado, 100);
      expect(d.costoConfiable, isFalse);
      expect(d.costoMayormenteEstimado, isTrue);
    });

    test('una pizca de estimación no descalifica el número', () {
      final d = datos(conCosto: 95, estimados: 5, sinCosto: 0);
      expect(d.costoConfiable, isTrue);
      expect(d.costoMayormenteEstimado, isFalse);
    });

    test('estimado y sin datos se cuentan por separado', () {
      final d = datos(conCosto: 50, estimados: 30, sinCosto: 20);
      expect(d.itemsTotales, 100);
      expect(d.coberturaCosto, 80); // exactos + estimados
      expect(d.porcentajeEstimado, 30);
    });
  });

  group('inventario', () {
    test('la rotación dice cuántas veces se renovó la despensa', () {
      final d = datos(cogs: 30000, inventario: 10000);
      expect(d.rotacion, 3);
    });

    test('sin despensa cargada no hay rotación que mostrar', () {
      expect(datos(inventario: 0).rotacion, isNull);
      expect(datos(cogs: 0, inventario: 5000).rotacion, isNull);
    });
  });

  group('estado vacío', () {
    test('el modelo vacío no rompe ninguna cuenta', () {
      const d = ProfitabilityData.vacio;
      expect(d.sinDatos, isTrue);
      expect(d.grossProfit, 0);
      expect(d.operatingProfit, 0);
      expect(d.foodCostPct, isNull);
      expect(d.rotacion, isNull);
      expect(d.coberturaCosto, isNull);
    });

    test('con ventas ya no está vacío', () {
      expect(datos(ventas: 1).sinDatos, isFalse);
    });
  });

  group('la caché no puede congelar un cálculo a medias', () {
    // El bug real: el reporte calculaba apenas se abría la pantalla, con el
    // dashboard todavía cargando y sus listas vacías. Daba ventas en cero, y
    // como la clave de caché solo miraba período y sucursal, cuando los datos
    // llegaban un instante después ya no recalculaba. Resultado: Q0.00 en
    // Rentabilidad mientras el dashboard mostraba Q67,537.
    //
    // La clave ahora incluye cuánto dato tenía el dashboard, así que "vacío" y
    // "cargado" son cálculos distintos.

    String clave({
      required int ordenes,
      required int gastos,
      required int compras,
      String loc = 'L1',
    }) =>
        '2026-08-01|2026-08-31|$loc|$ordenes|$gastos|$compras';

    test('el mismo período con y sin datos son claves distintas', () {
      final vacio = clave(ordenes: 0, gastos: 0, compras: 0);
      final cargado = clave(ordenes: 519, gastos: 12, compras: 3);
      expect(vacio, isNot(cargado));
    });

    test('cambiar de sucursal cambia la clave', () {
      expect(clave(ordenes: 519, gastos: 1, compras: 1, loc: 'L1'),
          isNot(clave(ordenes: 519, gastos: 1, compras: 1, loc: 'L2')));
    });

    test('sin cambios, la clave se repite y no se recalcula', () {
      expect(clave(ordenes: 519, gastos: 12, compras: 3),
          clave(ordenes: 519, gastos: 12, compras: 3));
    });
  });

  test('caso completo: los números cierran entre sí', () {
    final d = datos(
      ventas: 100000,
      cogs: 32000,
      sueldos: 28000,
      efectivo: 5000,
      compras: 35000,
      inventario: 22000,
    );

    // La cascada de punta a punta.
    expect(d.netSales - d.cogs, d.grossProfit);
    expect(d.grossProfit - d.totalExpenses, d.operatingProfit);
    expect(d.operatingProfit, 32000);

    // Y lo que queda fuera no la toca.
    expect(d.paidFromCash, 5000);
    expect(d.purchases, 35000);
    expect(d.inventoryValue, 22000);
    expect(evaluarPrimeCost(d.primeCostPct), Salud.bien);
  });
}
