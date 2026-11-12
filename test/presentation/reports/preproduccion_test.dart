import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/core/utils/formato_dinero.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';

/// Lo que la preproducción carga por tiempo (gas, luz, mano de obra) entra al
/// costo del preparado y de ahí al costo de lo vendido. Si además se resta
/// completo en Gastos, esa parte se cuenta dos veces. Estas pruebas cuidan la
/// resta: por categoría, nunca por debajo de cero y nunca de más.

/// Una preparación tal como la guarda el POS en
/// `tenants/{t}/transformationExecutions`.
Map<String, dynamic> prep({
  String? suc = 's1',
  String fecha = '2026-10-15T09:30:00.000',
  Object? extras,
  bool reversed = false,
}) =>
    {
      'tenantId': 't1',
      if (suc != null) 'locationId': suc,
      'executedAt': fecha,
      'reversed': reversed,
      if (extras != null) 'extras': extras,
    };

Map<String, dynamic> extra(
  String? categoria,
  Object? monto, {
  String nombre = 'Gas',
}) =>
    {
      'costoId': 'costo-$nombre',
      'nombre': nombre,
      if (categoria != null) 'categoriaGasto': categoria,
      'horas': 1.5,
      'monto': monto,
    };

Map<String, double> montos(List<ExpenseLine> lineas) =>
    {for (final l in lineas) l.categoryId: l.amount};

const _renta =
    ExpenseLine(categoryId: 'renta', label: 'Renta', amount: 3000, esFijo: true);
const _luz = ExpenseLine(categoryId: 'luz', label: 'Luz / Electricidad', amount: 500);
const _gas = ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 80);

/// El reporte con lo que dejó la resta, como lo arma Rentabilidad.
ProfitabilityData conPreproduccion(
  GastosSinPreproduccion g,
  CargosPreproduccion cargos, {
  double ventas = 100000,
  double cogs = 30000,
  double sueldos = 0,
}) =>
    ProfitabilityData(
      netSales: ventas,
      cogs: cogs,
      itemsSinCosto: 0,
      itemsConCosto: 100,
      expenses: g.lineas,
      payroll: g.restadoEn({'salarios'}) > 0 ? g.montoEn({'salarios'}) : sueldos,
      paidFromCash: 0,
      purchases: 0,
      inventoryValue: 0,
      ingredientesSinPrecio: 0,
      cargadoPreproduccion: cargos.total / 100,
      restadoPreproduccion: g.totalRestado / 100,
      excesosPreproduccion: g.excesos,
      preproduccionLeida: cargos.leida,
      preproduccionCompleta: cargos.completa,
    );

void main() {
  // El aviso lleva el signo de la vista, que es global: se fija para que el
  // texto no dependa de lo que dejó otra prueba.
  setUp(() => fijarMoneda('Q'));

  group('lo cargado a la preproducción', () {
    test('suma los otros costos por categoría, en centavos', () {
      final c = CargosPreproduccion.sumar([
        prep(extras: [
          extra('gas', 120),
          extra('salarios', 200, nombre: 'Mano de obra'),
        ]),
        prep(extras: [extra('gas', 30.5)]),
      ]);
      expect(c.porCategoria, {'gas': 15050, 'salarios': 20000});
      expect(c.total, 35050);
      expect(c.leida, isTrue);
      expect(c.completa, isTrue);
    });

    test('una preparación deshecha no cuenta', () {
      final c = CargosPreproduccion.sumar([
        prep(extras: [extra('gas', 120)]),
        prep(reversed: true, extras: [extra('gas', 999)]),
      ]);
      expect(c.porCategoria, {'gas': 12000});
    });

    test('las preparaciones de antes de "otros costos" aportan cero', () {
      final c = CargosPreproduccion.sumar([
        prep(),
        prep(extras: const []),
        // El total viene del POS, pero sin la lista no se sabe a qué
        // categoría restarlo: no se adivina.
        {...prep(), 'costoExtras': 150},
      ]);
      expect(c.porCategoria, isEmpty);
      expect(c.total, 0);
    });

    test('con una sucursal elegida, solo esa', () {
      final c = CargosPreproduccion.sumar([
        prep(suc: 's1', extras: [extra('gas', 10)]),
        prep(suc: 's2', extras: [extra('gas', 20)]),
      ], sucursal: 's2');
      expect(c.porCategoria, {'gas': 2000});
    });

    test('en "Todas", quien tiene sucursales asignadas ve solo las suyas', () {
      final c = CargosPreproduccion.sumar([
        prep(suc: 's1', extras: [extra('gas', 10)]),
        prep(suc: 's2', extras: [extra('gas', 20)]),
        prep(suc: null, extras: [extra('gas', 40)]),
      ], permitidas: {'s1'});
      expect(c.porCategoria, {'gas': 1000});
    });

    test('en "Todas" sin sucursales asignadas entra todo', () {
      final c = CargosPreproduccion.sumar([
        prep(suc: 's1', extras: [extra('gas', 10)]),
        prep(suc: 's2', extras: [extra('gas', 20)]),
      ]);
      expect(c.porCategoria, {'gas': 3000});
    });

    test('cada monto pasa a la moneda de la vista con su sucursal y su fecha',
        () {
      final pedidas = <String>[];
      final c = CargosPreproduccion.sumar([
        prep(
            suc: 'palermo',
            fecha: '2026-11-10T22:35:00.000',
            extras: [extra('gas', 8000)]),
        prep(suc: 'reforma', extras: [extra('gas', 100)]),
        // Sin tipo de cambio sus gastos tampoco se suman: no hay de dónde
        // restar su preproducción.
        prep(suc: 'sin_tasa', extras: [extra('gas', 999)]),
      ], factorDe: (suc, fecha) {
        pedidas.add('$suc|${fecha?.toIso8601String()}');
        return switch (suc) {
          'palermo' => 1 / 125,
          'reforma' => 1.0,
          _ => null,
        };
      });
      expect(c.porCategoria, {'gas': 6400 + 10000});
      expect(pedidas, contains('palermo|2026-11-10T22:35:00.000'));
    });

    test('un monto roto, en cero o negativo no se resta', () {
      final c = CargosPreproduccion.sumar([
        prep(extras: [
          extra('gas', double.nan),
          extra('gas', double.infinity),
          extra('gas', -50),
          extra('gas', 0),
          extra('gas', '120'),
          extra('gas', null),
          'no es un costo',
          extra('gas', 12.34),
        ]),
      ]);
      expect(c.porCategoria, {'gas': 1234});
    });

    test('sin categoría va a "otros", igual que un gasto sin categoría', () {
      final c = CargosPreproduccion.sumar([
        prep(extras: [
          extra(null, 10),
          extra('', 20),
          extra('   ', 30),
        ]),
      ]);
      expect(c.porCategoria, {'otros': 6000});
    });

    test('la coma flotante no inventa centavos', () {
      // 0.1 + 0.2 en dobles da 0.30000000000000004: comparado contra Q0.30
      // anotados, avisaba que se cargó de más.
      final c = CargosPreproduccion.sumar([
        prep(extras: [extra('gas', 0.1), extra('gas', 0.2)]),
      ]);
      final r = descontarPreproduccion(
          const [ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 0.3)],
          c);
      expect(c.porCategoria, {'gas': 30});
      expect(r.lineas.single.amount, 0);
      expect(r.excesos, isEmpty);
    });

    test('convertido de otra moneda, se redondea una vez y no sobra un centavo',
        () {
      // Tres costos de ARS 1,000.63 contra un recibo de ARS 3,001.89, a 0.008:
      // redondeando cada costo por su lado daban Q24.03 contra Q24.02.
      final c = CargosPreproduccion.sumar([
        prep(suc: 'palermo', extras: [
          extra('gas', 1000.63),
          extra('gas', 1000.63),
          extra('gas', 1000.63),
        ]),
      ], factorDe: (_, __) => 0.008);
      final r = descontarPreproduccion(
          [ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 3001.89 * 0.008)],
          c);
      expect(c.porCategoria, {'gas': 2402});
      expect(r.lineas.single.amount, 0);
      expect(r.excesos, isEmpty);
    });

    test('si no se pudo leer, no hay nada que restar', () {
      expect(CargosPreproduccion.noLeida.leida, isFalse);
      expect(CargosPreproduccion.noLeida.total, 0);
    });
  });

  group('la resta a los gastos', () {
    test('a cada categoría se le resta lo suyo, sin bajar de cero', () {
      final gastos = [_renta, _luz, _gas];
      final r = descontarPreproduccion(
          gastos,
          const CargosPreproduccion(
              porCategoria: {'gas': 12000, 'luz': 5000}));

      expect(montos(r.lineas), {'renta': 3000, 'luz': 450, 'gas': 0});
      expect(r.restado, {'luz': 5000, 'gas': 8000});
      expect(r.totalRestado, 13000);
      expect(identical(r.lineas.first, _renta), isTrue,
          reason: 'lo que no tiene nada cargado no se toca');
    });

    test('lo que sobra en una categoría no se le resta a otra', () {
      // Q40 de gas de más no pagan la renta.
      final r = descontarPreproduccion([_renta, _gas],
          const CargosPreproduccion(porCategoria: {'gas': 12000}));
      expect(montos(r.lineas), {'renta': 3000, 'gas': 0});
      expect(r.totalRestado, 8000);
    });

    test('el orden, el nombre y si es fijo se conservan', () {
      const sueldos = ExpenseLine(
          categoryId: 'salarios',
          label: 'Sueldos / Salarios',
          amount: 10000,
          esFijo: true);
      final r = descontarPreproduccion([_gas, sueldos],
          const CargosPreproduccion(porCategoria: {'salarios': 200000}));
      expect([for (final l in r.lineas) l.categoryId], ['gas', 'salarios']);
      final s = r.lineas.last;
      expect(s.label, 'Sueldos / Salarios');
      expect(s.esFijo, isTrue);
      expect(s.amount, 8000);
      expect(r.restadoEn({'salarios'}), 200000);
      expect(r.restadoEn({'renta'}), 0);
      expect(r.montoEn({'salarios'}), 8000);
    });

    test('sin leer la preproducción no se resta nada ni se avisa exceso', () {
      final r =
          descontarPreproduccion([_renta, _gas], CargosPreproduccion.noLeida);
      expect(montos(r.lineas), {'renta': 3000, 'gas': 80});
      expect(r.totalRestado, 0);
      expect(r.excesos, isEmpty);
    });

    test('sin preproducción en el período, los gastos quedan idénticos', () {
      final gastos = [_renta, _luz, _gas];
      final r = descontarPreproduccion(gastos, const CargosPreproduccion());
      for (var i = 0; i < gastos.length; i++) {
        expect(identical(r.lineas[i], gastos[i]), isTrue);
      }
      expect(r.excesos, isEmpty);
    });

    test('se puede ordenar lo que devuelve aunque los gastos sean const', () {
      // Rentabilidad ordena las líneas en el lugar, de mayor a menor.
      for (final cargos in [
        const CargosPreproduccion(),
        const CargosPreproduccion(porCategoria: {'gas': 100}),
      ]) {
        final r = descontarPreproduccion(const [_gas, _renta], cargos);
        expect(
            () => r.lineas.sort((a, b) => b.amount.compareTo(a.amount)),
            returnsNormally);
      }
    });

    test('una corrección negativa no tiene de dónde restar', () {
      const correccion = ExpenseLine(categoryId: 'gas', label: 'Gas', amount: -5);
      final r = descontarPreproduccion([correccion],
          const CargosPreproduccion(porCategoria: {'gas': 1000}));
      expect(identical(r.lineas.single, correccion), isTrue);
      expect(r.excesos.single.anotado, 0);
    });

    test('con una corrección en la misma categoría, el neto no baja de cero',
        () {
      // Q100 anotados y una corrección de −Q60: hay Q40 de dónde restar, no
      // Q100.
      final r = descontarPreproduccion(const [
        ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 100),
        ExpenseLine(categoryId: 'gas', label: 'Gas', amount: -60),
      ], const CargosPreproduccion(porCategoria: {'gas': 10000}));
      final neto = r.lineas.fold<double>(0, (a, l) => a + l.amount);
      expect(neto, 0);
      expect(r.totalRestado, 4000);
      expect(r.excesos.single.anotado, 4000);
    });

    test('lo cargado igual a lo anotado deja la categoría en cero, sin aviso',
        () {
      final r = descontarPreproduccion(
          [_gas], const CargosPreproduccion(porCategoria: {'gas': 8000}));
      expect(r.lineas.single.amount, 0);
      expect(r.excesos, isEmpty);
    });
  });

  group('el aviso de cada categoría', () {
    test('dice cuánto se cargó y cuánto hay en Gastos', () {
      final r = descontarPreproduccion(
          [_renta, _gas], const CargosPreproduccion(porCategoria: {'gas': 12000}));
      final e = r.excesos.single;
      expect(e.categoria, 'gas');
      expect(e.cargado, 12000);
      expect(e.anotado, 8000);
      expect(
          e.aviso,
          'Gas: se cargó Q120.00 a la preproducción y en Gastos hay Q80.00. '
          'Revisá los tiempos de tus recetas o que el gasto esté anotado en '
          'esa categoría.');
      expect(e.detalle,
          'Gas: se cargó Q120.00 a la preproducción y en Gastos hay Q80.00.');
    });

    test('una categoría sin gastos se nombra como en el POS', () {
      // "Sueldos" dice dónde anotarlo; "Mano de obra" no.
      final c = CargosPreproduccion.sumar([
        prep(extras: [
          extra('agua', 25, nombre: 'Agua de cocción'),
          extra('salarios', 500, nombre: 'Mano de obra'),
        ]),
      ]);
      final r = descontarPreproduccion([_gas], c);
      expect(montos(r.lineas), {'gas': 80});
      expect([for (final e in r.excesos) e.etiqueta], ['Sueldos', 'Agua']);
      expect(
          r.excesos.last.aviso,
          'Agua: se cargó Q25.00 a la preproducción y en Gastos no hay nada '
          'anotado. Revisá los tiempos de tus recetas o que el gasto esté '
          'anotado en esa categoría.');
    });

    test('una categoría que acá no se conoce se nombra con sus costos', () {
      final c = CargosPreproduccion.sumar([
        prep(extras: [
          extra('lena', 100, nombre: 'Leña'),
          extra('lena', 50, nombre: 'Carbón'),
        ]),
        prep(extras: [extra('lena', 100, nombre: 'Leña')]),
      ]);
      expect(c.nombreDe('lena'), 'Leña, Carbón');
      expect(
          const CargosPreproduccion(porCategoria: {'pago_proveedor': 100})
              .nombreDe('pago_proveedor'),
          'Pago proveedor');
    });

    test('lleva el signo de la moneda que se está mirando', () {
      fijarMoneda('L');
      final r = descontarPreproduccion(
          [_gas], const CargosPreproduccion(porCategoria: {'gas': 12000}));
      expect(r.excesos.single.aviso, contains('se cargó L120.00'));
    });

    test('la diferencia más grande va primero', () {
      final r = descontarPreproduccion(
          [_gas, _luz],
          const CargosPreproduccion(
              porCategoria: {'gas': 9000, 'luz': 80000, 'agua': 500}));
      expect([for (final e in r.excesos) e.categoria], ['luz', 'gas', 'agua']);
    });
  });

  group('el aviso en Rentabilidad', () {
    final conExceso = descontarPreproduccion(
        [_renta, _gas], const CargosPreproduccion(porCategoria: {'gas': 12000}));
    ProfitabilityData datos({
      GastosSinPreproduccion? g,
      CargosPreproduccion cargos =
          const CargosPreproduccion(porCategoria: {'gas': 12000}),
    }) =>
        conPreproduccion(g ?? conExceso, cargos);

    final octubre = DateRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59, 59),
        mode: PeriodMode.month);
    final noviembre = DateRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30, 23, 59, 59),
        mode: PeriodMode.month);
    final anio = DateRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31, 23, 59, 59),
        mode: PeriodMode.year);
    DateRange corto(PeriodMode modo) => DateRange(
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 11, 23, 59, 59),
        mode: modo);
    final hoy = DateTime(2026, 11, 11);

    test('en un mes cerrado o en el año, una línea por categoría', () {
      for (final rango in [octubre, anio]) {
        final a = avisoPreproduccion(datos(),
            rango: rango, gastosLeidos: true, hoy: hoy)!;
        expect(a.titulo, 'Revisá la preproducción');
        expect(a.parrafos, [conExceso.excesos.single.aviso],
            reason: '${rango.mode}');
      }
    });

    test('en el mes en curso da los montos, pero no manda a revisar Gastos',
        () {
      // El 11 de noviembre la planilla del mes todavía no se anotó: mandar a
      // anotarla haría que quede dos veces cuando llegue la de verdad.
      final a = avisoPreproduccion(datos(),
          rango: noviembre, gastosLeidos: true, hoy: hoy)!;
      expect(a.parrafos.first, conExceso.excesos.single.detalle);
      expect(a.parrafos.last, contains('El mes va a medias'));
      expect(a.parrafos.join(' '), isNot(contains('esté anotado')));
    });

    test('en un día, una semana o un rango libre no manda a revisar Gastos',
        () {
      // El gas y los sueldos se anotan una vez al mes: decirlo un martes haría
      // que se anote dos veces.
      for (final modo in [PeriodMode.day, PeriodMode.week, PeriodMode.custom]) {
        final a = avisoPreproduccion(datos(),
            rango: corto(modo), gastosLeidos: true, hoy: hoy)!;
        expect(a.parrafos, hasLength(1), reason: '$modo');
        expect(a.parrafos.single, contains('una vez al mes'));
        expect(a.parrafos.single, isNot(contains('esté anotado')));
      }
    });

    test('si no se leyeron todos los gastos, no compara', () {
      final a = avisoPreproduccion(datos(),
          rango: octubre, gastosLeidos: false, hoy: hoy)!;
      expect(a.parrafos.single, contains('No se pudieron leer todos los gastos'));
      expect(a.parrafos.single, isNot(contains('esté anotado')));
    });

    test('si no se pudo leer la preproducción, lo dice y no resta', () {
      final g = descontarPreproduccion([_renta, _gas], CargosPreproduccion.noLeida);
      final d = datos(g: g, cargos: CargosPreproduccion.noLeida);
      expect(d.restadoPreproduccion, 0);
      final a = avisoPreproduccion(d,
          rango: octubre, gastosLeidos: true, hoy: hoy)!;
      expect(a.titulo, 'No se pudo leer la preproducción');
      expect(a.parrafos.single, contains('Los gastos se muestran completos'));
    });

    test('si la lectura quedó corta, lo dice', () {
      const cargos =
          CargosPreproduccion(porCategoria: {'gas': 100}, completa: false);
      final g = descontarPreproduccion([_gas], cargos);
      final a = avisoPreproduccion(datos(g: g, cargos: cargos),
          rango: octubre, gastosLeidos: true, hoy: hoy)!;
      expect(a.parrafos.single, contains('puede quedar corto'));
    });

    test('todo restado y leído: no hay nada que avisar', () {
      const cargos = CargosPreproduccion(porCategoria: {'gas': 100});
      final g = descontarPreproduccion([_gas], cargos);
      for (final rango in [
        octubre,
        noviembre,
        anio,
        for (final m in [PeriodMode.day, PeriodMode.week, PeriodMode.custom])
          corto(m),
      ]) {
        expect(
            avisoPreproduccion(datos(g: g, cargos: cargos),
                rango: rango, gastosLeidos: true, hoy: hoy),
            isNull,
            reason: '${rango.mode}');
      }
      expect(
          avisoPreproduccion(ProfitabilityData.vacio,
              rango: octubre, gastosLeidos: true, hoy: hoy),
          isNull);
    });
  });

  group('en la cascada y en el reparto por platillo', () {
    // Octubre: Q100,000 vendidos, Q30,000 de costo de lo vendido (que trae
    // Q2,000 de mano de obra y Q3,000 de gas de la preproducción).
    final gastos = [
      const ExpenseLine(
          categoryId: 'renta', label: 'Renta', amount: 15000, esFijo: true),
      const ExpenseLine(
          categoryId: 'salarios',
          label: 'Sueldos',
          amount: 10000,
          esFijo: true),
      const ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 13000),
    ];
    final cargos = CargosPreproduccion.sumar([
      prep(extras: [
        extra('salarios', 2000, nombre: 'Mano de obra'),
        extra('gas', 3000),
      ]),
    ]);

    ProfitabilityData datos(CargosPreproduccion c) =>
        conPreproduccion(descontarPreproduccion(gastos, c), c, sueldos: 10000);

    test('la utilidad deja de contar dos veces lo cargado', () {
      final antes = datos(CargosPreproduccion.noLeida);
      final d = datos(cargos);
      expect(antes.operatingProfit, 32000);
      expect(d.totalExpenses, 33000);
      expect(d.operatingProfit, 37000);
      expect(d.operatingProfit - antes.operatingProfit, d.restadoPreproduccion);
      expect(d.cargadoPreproduccion, 5000);
    });

    test('el costo primo no suma dos veces la mano de obra', () {
      final d = datos(cargos);
      expect(d.payroll, 8000);
      expect(d.primeCostPct, closeTo(38, 0.001)); // (30000 + 8000) / 100000
      expect(datos(CargosPreproduccion.noLeida).payroll, 10000);
    });

    test('el reparto usa los mismos gastos ya restados', () {
      final r = RepartoGastos.desde(
        datos: datos(cargos),
        rango: DateRange(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 31, 23, 59, 59),
          mode: PeriodMode.month,
        ),
        gastosLeidos: true,
        hoy: DateTime(2026, 11, 10),
      );
      expect(r.estado, EstadoReparto.listo);
      expect(r.ratioFijos, closeTo(0.23, 1e-9)); // renta 15000 + sueldos 8000
      expect(r.ratioVariables, closeTo(0.10, 1e-9)); // gas 13000 − 3000
    });

    test('por defecto el reporte no trae preproducción ni avisos', () {
      const d = ProfitabilityData.vacio;
      expect(d.cargadoPreproduccion, 0);
      expect(d.restadoPreproduccion, 0);
      expect(d.excesosPreproduccion, isEmpty);
      expect(d.preproduccionLeida, isTrue);
      expect(d.preproduccionCompleta, isTrue);
    });
  });
}
