import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';

/// El punto de equilibrio.
///
/// Es el número que el usuario va a usar para decidir ("¿abro el domingo?"),
/// así que equivocarlo cuesta caro. Los casos donde NO se puede calcular
/// importan tanto como el cálculo: devolver un número inventado ahí sería
/// peor que no mostrar nada.

ProfitabilityData datos({
  double ventas = 100000,
  double cogs = 30000,
  double fijos = 36000,
  double variables = 10000,
}) =>
    ProfitabilityData(
      netSales: ventas,
      cogs: cogs,
      itemsConCosto: 100,
      itemsSinCosto: 0,
      expenses: [
        ExpenseLine(
            categoryId: 'renta', label: 'Renta', amount: fijos, esFijo: true),
        ExpenseLine(
            categoryId: 'luz', label: 'Luz', amount: variables, esFijo: false),
      ],
      payroll: 0,
      ownerWithdrawals: 0,
      purchases: 0,
      inventoryValue: 0,
      ingredientesSinPrecio: 0,
    );

void main() {
  group('separación fijo / variable', () {
    test('los fijos son solo los marcados como tales', () {
      final d = datos(fijos: 36000, variables: 10000);
      expect(d.fixedCosts, 36000);
    });

    test('los variables incluyen la comida', () {
      // El costo de lo vendido es el costo variable más grande de un
      // restaurante; dejarlo fuera daría un punto de equilibrio irreal.
      final d = datos(cogs: 30000, variables: 10000);
      expect(d.variableCosts, 40000);
    });
  });

  group('margen de contribución', () {
    test('es lo que queda de cada venta tras los costos variables', () {
      // 100000 − (30000 + 10000) = 60000 → 60%
      final d = datos();
      expect(d.contributionMarginPct, closeTo(60, 0.001));
    });

    test('sin ventas no se puede medir', () {
      expect(datos(ventas: 0).contributionMarginPct, isNull);
    });
  });

  group('el cálculo', () {
    test('fijos divididos por el margen de contribución', () {
      // 36000 / 0.60 = 60000
      final d = datos();
      expect(d.breakEven, closeTo(60000, 0.01));
    });

    test('vendiendo justo el punto, la utilidad es cero', () {
      // La prueba de que la fórmula es la correcta: si vendo exactamente el
      // punto de equilibrio, no gano ni pierdo.
      const fijos = 36000.0;
      final base = datos();
      final be = base.breakEven!;

      // A ese volumen, los variables escalan en la misma proporción.
      final proporcionVariable = base.variableCosts / base.netSales;
      final variablesEnBe = be * proporcionVariable;
      final utilidad = be - variablesEnBe - fijos;

      expect(utilidad, closeTo(0, 0.01));
    });

    test('más costos fijos exigen vender más', () {
      final poco = datos(fijos: 30000).breakEven!;
      final mucho = datos(fijos: 60000).breakEven!;
      expect(mucho, greaterThan(poco));
    });

    test('mejor margen exige vender menos', () {
      final margenFlaco = datos(cogs: 50000).breakEven!;
      final margenGordo = datos(cogs: 20000).breakEven!;
      expect(margenGordo, lessThan(margenFlaco));
    });
  });

  group('avance', () {
    test('vendiendo la mitad del punto, el avance es 50%', () {
      final d = datos(ventas: 100000);
      final be = d.breakEven!; // 60000
      expect(be, closeTo(60000, 0.01));
      // Con ventas de 30000 el avance sería la mitad.
      final mitad = datos(ventas: 30000, cogs: 9000, variables: 3000);
      expect(mitad.avanceBreakEven, closeTo(30000 / mitad.breakEven!, 0.001));
    });

    test('superar el punto deja "falta" en negativo', () {
      final d = datos(ventas: 100000); // be 60000
      expect(d.faltaParaBreakEven, lessThan(0));
    });
  });

  group('los casos donde NO se puede calcular', () {
    test('si cada venta pierde plata, no hay punto de equilibrio', () {
      // Costos variables por encima de las ventas: vender más agranda el
      // agujero. Devolver un número acá sería mentir.
      final d = datos(ventas: 100000, cogs: 90000, variables: 30000);
      expect(d.pierdeConCadaVenta, isTrue);
      expect(d.breakEven, isNull);
    });

    test('margen de contribución exactamente cero tampoco tiene solución', () {
      final d = datos(ventas: 100000, cogs: 100000, variables: 0);
      expect(d.contributionMarginPct, 0);
      expect(d.breakEven, isNull);
      expect(d.pierdeConCadaVenta, isTrue);
    });

    test('sin gastos fijos registrados se avisa en vez de dar casi cero', () {
      // Pasa en rangos de un día: la renta se registra una vez al mes.
      final d = datos(fijos: 0);
      expect(d.sinCostosFijos, isTrue);
    });

    test('sin ventas no hay punto de equilibrio', () {
      final d = datos(ventas: 0);
      expect(d.breakEven, isNull);
      expect(d.avanceBreakEven, isNull);
      // Y no se confunde con "cada venta pierde": no hubo ventas.
      expect(d.pierdeConCadaVenta, isFalse);
    });

    test('el modelo vacío no revienta', () {
      const d = ProfitabilityData.vacio;
      expect(d.breakEven, isNull);
      expect(d.fixedCosts, 0);
      expect(d.variableCosts, 0);
      expect(d.pierdeConCadaVenta, isFalse);
    });
  });
}
