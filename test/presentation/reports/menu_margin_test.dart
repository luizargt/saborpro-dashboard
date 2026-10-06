import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/core/utils/formato_dinero.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_card.dart';

/// La aritmética de Utilidad por platillo.
///
/// Un error aquí no rompe nada visible: produce una utilidad creíble y
/// equivocada, y el dueño fija sus precios con ella. Cada regla tiene su
/// prueba, y las que copian al POS citan qué copian.

IngredienteCosto ing(
  String id, {
  double? precio = 10,
  String nombre = 'Ingrediente',
  String? sucursal = 's1',
  String? master,
  String? codigo,
  bool activo = true,
  String unidad = 'unidades',
  String? personalizada,
}) =>
    IngredienteCosto(
      id: id,
      nombre: nombre,
      sucursalId: sucursal,
      masterId: master,
      codigo: codigo,
      activo: activo,
      unidad: unidad,
      unidadPersonalizada: personalizada,
      precio: precio,
    );

var _doc = 0;
LineaReceta linea(
  String ingrediente,
  double cantidad, {
  String producto = 'p1',
  String presentacion = 'pr1',
  String? master,
  String? docId,
}) =>
    LineaReceta(
      docId: docId ?? 'doc${_doc++}',
      productoId: producto,
      presentacionId: presentacion,
      ingredienteId: ingrediente,
      masterId: master,
      cantidad: cantidad,
    );

ProductoMenu producto({
  double precio = 50,
  String id = 'p1',
  String nombre = 'Hamburguesa',
  List<PresentacionMenu>? presentaciones,
}) =>
    ProductoMenu(
      id: id,
      nombre: nombre,
      presentaciones: presentaciones ??
          [PresentacionMenu(id: 'pr1', nombre: 'Normal', precio: precio)],
    );

MargenPlatillo uno(
  List<LineaReceta> recetas,
  List<IngredienteCosto> ingredientes, {
  double precio = 50,
  String? sucursal,
  Set<String> permitidas = const {},
  Set<String> vendibles = const {'s1', 's2'},
  Map<String, double> preciosSucursal = const {},
}) {
  final m = calcularMargenes(
    MenuCrudo(
      productos: [producto(precio: precio)],
      recetas: recetas,
      ingredientes: ingredientes,
      preciosSucursal: preciosSucursal,
      sucursalesVendibles: vendibles,
    ),
    sucursalId: sucursal,
    sucursalesPermitidas: permitidas,
  );
  expect(m, hasLength(1));
  return m.single;
}

ProfitabilityData rentabilidad({
  double ventas = 100000,
  List<ExpenseLine> gastos = const [],
}) =>
    ProfitabilityData(
      netSales: ventas,
      cogs: 0,
      itemsSinCosto: 0,
      itemsConCosto: 0,
      expenses: gastos,
      payroll: 0,
      paidFromCash: 0,
      purchases: 0,
      inventoryValue: 0,
      ingredientesSinPrecio: 0,
    );

final octubre = DateRange(
  start: DateTime(2026, 10, 1),
  end: DateTime(2026, 10, 31, 23, 59, 59),
  mode: PeriodMode.month,
);

RepartoGastos repartoDe({
  double ventas = 100000,
  double fijos = 25000,
  double variables = 13000,
  double comida = 0,
  double descuentos = 0,
  DateRange? rango,
  bool gastosLeidos = true,
  DateTime? hoy,
}) =>
    RepartoGastos.desde(
      datos: rentabilidad(ventas: ventas, gastos: [
        if (fijos > 0)
          ExpenseLine(
              categoryId: 'renta', label: 'Renta', amount: fijos, esFijo: true),
        if (variables > 0)
          ExpenseLine(categoryId: 'gas', label: 'Gas', amount: variables),
        if (comida > 0)
          ExpenseLine(categoryId: 'insumos', label: 'Insumos', amount: comida),
      ]),
      rango: rango ?? octubre,
      gastosLeidos: gastosLeidos,
      descuentos: descuentos,
      hoy: hoy ?? DateTime(2026, 11, 15),
    );

void main() {
  group('la cuenta de la receta', () {
    test('el costo es la suma de cantidad × último precio, en centavos', () {
      final p = uno(
        [linea('a', 2), linea('b', 0.5)],
        [ing('a', precio: 10), ing('b', precio: 8)],
      );
      expect(p.estado, EstadoCosto.completo);
      expect(p.costo, 2400); // 2×10 + 0.5×8 = Q24.00
      expect(p.margenReceta, 2600);
      expect(p.margenRecetaPct, 52);
    });

    test('la coma flotante no inventa pérdidas', () {
      // Con dobles, 0.1 + 0.1 + 0.1 contra 0.30 daba −0.0% y alerta roja.
      final p = uno(
        [linea('a', 1), linea('b', 1), linea('c', 1)],
        [ing('a', precio: 0.1), ing('b', precio: 0.1), ing('c', precio: 0.1)],
        precio: 0.30,
      );
      expect(p.costo, 30);
      expect(p.margenReceta, 0);
      expect(p.alertas, isEmpty);
      expect(formatoDinero(p.margenReceta!), 'Q0.00');
      expect(formatoPct(p.margenRecetaPct), '0.0%');
    });

    test('con precio de venta en cero no hay porcentaje', () {
      final p = uno([linea('a', 1)], [ing('a')], precio: 0);
      expect(p.margenRecetaPct, isNull);
    });
  });

  group('lo que no se puede costear no se inventa', () {
    test('sin receta no hay costo', () {
      final p = uno([], [ing('a')]);
      expect(p.estado, EstadoCosto.sinReceta);
      expect(p.costo, isNull);
    });

    test('un ingrediente sin precio deja la receta incompleta y se nombra', () {
      final p = uno(
        [linea('a', 1), linea('b', 1)],
        [ing('a'), ing('b', precio: null, nombre: 'Queso')],
      );
      expect(p.estado, EstadoCosto.incompleto);
      expect(p.costo, isNull);
      expect(p.sinPrecio, ['Queso']);
    });

    test('un precio de compra en cero cuenta como sin precio', () {
      final p = uno([linea('a', 1)], [ing('a', precio: 0)]);
      expect(p.estado, EstadoCosto.incompleto);
    });

    test('un ingrediente borrado no existe en la sucursal', () {
      final p = uno([linea('fantasma', 1)], const [], sucursal: 's1');
      expect(p.noEnSucursal, ['Ingrediente eliminado']);
    });
  });

  group('la receta de cada presentación', () {
    final dos = producto(presentaciones: const [
      PresentacionMenu(id: 'sencilla', nombre: 'Sencilla', precio: 40),
      PresentacionMenu(id: 'doble', nombre: 'Doble', precio: 60),
    ]);

    test('no usa las líneas de otra presentación (POS: clave exacta)', () {
      final m = calcularMargenes(MenuCrudo(
        productos: [dos],
        recetas: [
          linea('a', 1, presentacion: 'sencilla'),
          linea('a', 3, presentacion: 'doble'),
        ],
        ingredientes: [ing('a', precio: 5)],
      ));
      final por = {for (final p in m) p.presentacion: p};
      expect(por['Sencilla']!.costo, 500);
      expect(por['Doble']!.costo, 1500);
    });

    test('una presentación sin receta propia queda sin receta', () {
      final m = calcularMargenes(MenuCrudo(
        productos: [dos],
        recetas: [linea('a', 1, presentacion: 'sencilla')],
        ingredientes: [ing('a')],
      ));
      expect(m.firstWhere((p) => p.presentacion == 'Doble').estado,
          EstadoCosto.sinReceta);
    });

    test('con una sola presentación no se nombra; con varias, sí', () {
      expect(uno([linea('a', 1)], [ing('a')]).presentacion, isNull);
      final m = calcularMargenes(MenuCrudo(productos: [dos]));
      expect(m.map((p) => p.nombre),
          ['Hamburguesa · Sencilla', 'Hamburguesa · Doble']);
    });
  });

  group('el ingrediente que descuenta el POS en la sucursal', () {
    test('primero por el maestro de la receta', () {
      final p = uno(
        [linea('a1', 2, master: 'M')],
        [
          ing('a1', precio: 10, sucursal: 's1', master: 'M'),
          ing('a2', precio: 14, sucursal: 's2', master: 'M'),
        ],
        sucursal: 's2',
      );
      expect(p.costo, 2800);
    });

    test('si la receta no trae maestro, usa el del ingrediente propio', () {
      final p = uno(
        [linea('a1', 1)],
        [
          ing('a1', precio: 10, sucursal: 's1', master: 'M'),
          ing('a2', precio: 14, sucursal: 's2', master: 'M'),
        ],
        sucursal: 's2',
      );
      expect(p.costo, 1400);
    });

    test('sin maestro busca por CÓDIGO antes que por nombre', () {
      final p = uno(
        [linea('a1', 1)],
        [
          ing('a1', precio: 10, sucursal: 's1', nombre: 'Pollo', codigo: 'P-1'),
          ing('porNombre', precio: 99, sucursal: 's2', nombre: 'Pollo'),
          ing('porCodigo', precio: 14, sucursal: 's2', nombre: 'Pechuga',
              codigo: ' p-1 '),
        ],
        sucursal: 's2',
      );
      expect(p.costo, 1400);
    });

    test('el nombre se compara sin mayúsculas ni espacios de los bordes', () {
      final p = uno(
        [linea('a1', 1)],
        [
          ing('a1', precio: 10, sucursal: 's1', nombre: ' Pollo '),
          ing('a2', precio: 14, sucursal: 's2', nombre: 'pollo'),
        ],
        sucursal: 's2',
      );
      expect(p.costo, 1400);
    });

    test('si no existe en la sucursal NO toma el precio de otra', () {
      final p = uno(
        [linea('a1', 1)],
        [ing('a1', precio: 10, sucursal: 's1', nombre: 'Pollo')],
        sucursal: 's2',
      );
      expect(p.estado, EstadoCosto.incompleto);
      expect(p.noEnSucursal, ['Pollo']);
    });

    test('si existe sin precio queda sin precio, aunque otra sucursal lo tenga',
        () {
      final p = uno(
        [linea('a1', 1, master: 'M')],
        [
          ing('a1', precio: 10, sucursal: 's1', master: 'M'),
          ing('a2', precio: null, sucursal: 's2', master: 'M'),
        ],
        sucursal: 's2',
      );
      expect(p.estado, EstadoCosto.incompleto);
      expect(p.sinPrecio, hasLength(1));
    });

    test('un inactivo no se resuelve: el POS solo guarda los activos', () {
      final p = uno(
        [linea('a1', 1, master: 'M')],
        [
          ing('a1', precio: 10, sucursal: 's1', master: 'M'),
          ing('viejo', precio: 99, sucursal: 's2', master: 'M', activo: false),
        ],
        sucursal: 's2',
      );
      expect(p.noEnSucursal, hasLength(1));
    });

    test('con dos candidatos gana el de id mayor, como el índice del POS', () {
      final p = uno(
        [linea('a1', 1, master: 'M')],
        [
          ing('a1', precio: 10, sucursal: 's1', master: 'M'),
          ing('b', precio: 11, sucursal: 's2', master: 'M'),
          ing('c', precio: 12, sucursal: 's2', master: 'M'),
        ],
        sucursal: 's2',
      );
      expect(p.costo, 1200);
    });

    test('en "Todas" con varias sucursales usa el ingrediente de la receta', () {
      final p = uno(
        [linea('a1', 1, master: 'M')],
        [
          ing('a1', precio: 10, sucursal: 's1', master: 'M'),
          ing('a2', precio: 14, sucursal: 's2', master: 'M'),
        ],
      );
      expect(p.costo, 1000);
    });

    test('con una sola sucursal que vende, "Todas" es esa sucursal', () {
      final p = uno(
        [linea('a1', 1, master: 'M')],
        [
          ing('a1', precio: 10, sucursal: 'vieja', master: 'M'),
          ing('a2', precio: 14, sucursal: 's1', master: 'M'),
        ],
        vendibles: {'s1'},
        preciosSucursal: {'pr1|s1': 70},
      );
      expect(p.costo, 1400);
      expect(p.precio, 7000);
    });

    test('nada de una sucursal que el usuario no tiene asignada', () {
      final p = uno(
        [linea('a1', 1)],
        [ing('a1', precio: 10, sucursal: 's1')],
        permitidas: {'s2'},
      );
      expect(p.estado, EstadoCosto.incompleto);
    });

    test('unidad distinta a la de la receta se marca; personalizadas no', () {
      final distinta = uno(
        [linea('a1', 200, master: 'M')],
        [
          ing('a1', sucursal: 's1', master: 'M', unidad: 'gramos'),
          ing('a2', sucursal: 's2', master: 'M', unidad: 'kilogramos'),
        ],
        sucursal: 's2',
      );
      expect(distinta.alertas, contains(AlertaReceta.unidadDistinta));

      final personalizadas = uno(
        [linea('a1', 1, master: 'M')],
        [
          ing('a1', sucursal: 's1', master: 'M', personalizada: 'u1'),
          ing('a2', sucursal: 's2', master: 'M', personalizada: 'u2'),
        ],
        sucursal: 's2',
      );
      expect(personalizadas.alertas, isNot(contains(AlertaReceta.unidadDistinta)));
    });
  });

  group('precio y disponibilidad por sucursal', () {
    test('cobra el precio de la sucursal si existe; en "Todas", el base', () {
      final precios = {'pr1|s2': 65.0};
      expect(
          uno([], const [], sucursal: 's2', preciosSucursal: precios).precio,
          6500);
      expect(
          uno([], const [], sucursal: 's1', preciosSucursal: precios).precio,
          5000);
      expect(uno([], const [], preciosSucursal: precios).precio, 5000);
    });

    test('un producto apagado en la sucursal no aparece ahí', () {
      final menu = MenuCrudo(
        productos: [producto()],
        apagados: {'p1|s2'},
        sucursalesVendibles: {'s1', 's2'},
      );
      expect(calcularMargenes(menu, sucursalId: 's2'), isEmpty);
      expect(calcularMargenes(menu, sucursalId: 's1'), hasLength(1));
      expect(calcularMargenes(menu), hasLength(1));
    });

    test('con una sola sucursal que vende, el apagado se ignora como en el POS',
        () {
      final menu = MenuCrudo(
        productos: [producto()],
        apagados: {'p1|s1'},
        sucursalesVendibles: {'s1'},
      );
      expect(calcularMargenes(menu, sucursalId: 's1'), hasLength(1));
    });
  });

  group('recetas duplicadas', () {
    test('cuenta UNA línea, la de id mayor, y lo marca', () {
      final p = uno(
        [
          linea('a', 0.45, docId: 'aaa'),
          linea('a', 0.50, docId: 'zzz'),
        ],
        [ing('a', precio: 36)],
      );
      expect(p.costo, 1800); // 0.50 × 36, no la suma de ambas
      expect(p.alertas, contains(AlertaReceta.recetaDuplicada));
    });
  });

  group('alertas de dato sospechoso', () {
    MargenPlatillo conCosto(double precio, double costo) =>
        uno([linea('a', 1)], [ing('a', precio: costo)], precio: precio);

    test('la receta cuesta más que el precio', () {
      expect(conCosto(50, 80).alertas,
          contains(AlertaReceta.cuestaMasQueElPrecio));
    });

    test('costo igual al precio no es alerta', () {
      expect(conCosto(50, 50).alertas, isEmpty);
    });

    test('una cantidad cero o negativa en la receta se marca', () {
      final p = uno([linea('a', 2), linea('b', -1)],
          [ing('a', precio: 10), ing('b', precio: 15)]);
      expect(p.alertas, contains(AlertaReceta.cantidadInvalida));
    });

    test('95% exacto no alerta; por encima sí', () {
      expect(conCosto(100, 5).alertas, isEmpty);
      expect(conCosto(100, 4).alertas, contains(AlertaReceta.margenMuyAlto));
    });
  });

  group('reparto de gastos', () {
    test('fijos y variables sobre la venta neta, sin la comida', () {
      final r = repartoDe(fijos: 25000, variables: 13000, comida: 9000);
      expect(r.estado, EstadoReparto.listo);
      expect(r.ratioFijos, 0.25);
      expect(r.ratioVariables, 0.13);
      expect(r.gastosDeComida, 9000);
    });

    test('pago a proveedor tampoco se reparte', () {
      final r = RepartoGastos.desde(
        datos: rentabilidad(gastos: const [
          ExpenseLine(
              categoryId: 'pago_proveedor', label: 'Proveedor', amount: 5000),
        ]),
        rango: octubre,
        gastosLeidos: true,
        hoy: DateTime(2026, 11, 2),
      );
      expect(r.ratio, 0);
      expect(r.gastosDeComida, 5000);
    });

    test('solo Mes o Año reparten; día, semana y rangos libres no', () {
      // Un rango libre de 32 días mete dos rentas y uno de 28 puede no meter
      // ninguna; además el dashboard corta las órdenes de un rango largo.
      for (final modo in [PeriodMode.day, PeriodMode.week, PeriodMode.custom]) {
        final rango = DateRange(
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 10, 31, 23, 59, 59),
            mode: modo);
        expect(repartoDe(rango: rango).estado, EstadoReparto.periodoCorto,
            reason: '$modo');
      }
      final anio = DateRange(
          start: DateTime(2025, 1, 1),
          end: DateTime(2025, 12, 31, 23, 59, 59),
          mode: PeriodMode.year);
      expect(repartoDe(rango: anio).estado, EstadoReparto.listo);
    });

    test('sin ventas, sin gastos, gastos sin leer, ventas cortadas y gastos '
        'mayores que la venta', () {
      expect(repartoDe(ventas: 0).estado, EstadoReparto.sinVentas);
      expect(repartoDe(fijos: 0, variables: 0).estado, EstadoReparto.sinGastos,
          reason: 'repartir cero pintaría todo de verde');
      expect(repartoDe(gastosLeidos: false).estado,
          EstadoReparto.gastosNoLeidos);
      expect(
          RepartoGastos.desde(
            datos: rentabilidad(gastos: const [
              ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 100),
            ]),
            rango: octubre,
            gastosLeidos: true,
            ventasCompletas: false,
            hoy: DateTime(2026, 11, 5),
          ).estado,
          EstadoReparto.ventasIncompletas);
      expect(repartoDe(ventas: 30000, fijos: 25000, variables: 5000).estado,
          EstadoReparto.gastosSuperanVentas);
    });

    test('un total de gastos negativo no regala utilidad', () {
      final r = repartoDe(fijos: 0, variables: 13000);
      final conNegativo = RepartoGastos.desde(
        datos: rentabilidad(gastos: const [
          ExpenseLine(
              categoryId: 'renta', label: 'Renta', amount: -5000, esFijo: true),
          ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 13000),
        ]),
        rango: octubre,
        gastosLeidos: true,
        hoy: DateTime(2026, 11, 5),
      );
      expect(conNegativo.ratioFijos, 0);
      expect(conNegativo.ratio, r.ratio);
    });

    test('sin el detalle del año, el descuento es desconocido y se dice', () {
      final r = RepartoGastos.desde(
        datos: rentabilidad(gastos: const [
          ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 100),
        ]),
        rango: octubre,
        gastosLeidos: true,
        descuentos: null,
        hoy: DateTime(2026, 11, 5),
      );
      expect(r.descuentoConocido, isFalse);
      expect(r.tasaDescuento, 0);
    });

    test('"de cada Q100" suma: fijos + variables = total', () {
      final c = repartoDe(fijos: 12500, variables: 12500).cada100;
      expect(c.total, 25);
      expect(c.fijos + c.variables, 25);
    });

    test('el mes en curso se avisa; uno cerrado no', () {
      expect(repartoDe(hoy: DateTime(2026, 10, 3)).mesEnCurso, isTrue);
      expect(repartoDe(hoy: DateTime(2026, 11, 3)).mesEnCurso, isFalse);
    });

    test('la tasa de descuento se mide sobre el precio de lista', () {
      // Cobrado 97,000 con 3,000 de descuento: la lista era 100,000.
      expect(repartoDe(ventas: 97000, descuentos: 3000).tasaDescuento, 0.03);
    });
  });

  group('el desglose por platillo', () {
    test('los renglones suman exacto al precio, siempre', () {
      final azar = Random(20261003);
      for (var i = 0; i < 1000; i++) {
        final p = uno(
          [linea('a', azar.nextDouble() * 3)],
          [ing('a', precio: azar.nextDouble() * 40 + 0.01)],
          precio: (azar.nextInt(30000) + 100) / 100,
        );
        final r = repartoDe(
          fijos: azar.nextDouble() * 40000,
          variables: azar.nextDouble() * 30000,
          descuentos: azar.nextDouble() * 5000,
        );
        final d = Desglose.de(p, r);
        expect(d.descuento + d.costo + d.variables + d.fijos + d.utilidad,
            d.precio);
      }
    });

    test('Q100 con receta Q30, 25% fijos, 13% variables, 3% descuento', () {
      final p = uno([linea('a', 1)], [ing('a', precio: 30)], precio: 100);
      final d = Desglose.de(
          p, repartoDe(ventas: 97000, descuentos: 3000, fijos: 24250, variables: 12610));
      expect(d.descuento, 300);
      expect(d.variables, 1261); // 97 × 13%
      expect(d.fijos, 2425); // 97 × 25%
      expect(d.utilidad, 10000 - 300 - 3000 - 1261 - 2425);
      expect(d.banda, Banda.cubreTodo);
    });

    test('bandas: pierde, no cubre fijos, cubre todo', () {
      final r = repartoDe(fijos: 25000, variables: 13000);
      MargenPlatillo conCosto(double c) =>
          uno([linea('a', 1)], [ing('a', precio: c)], precio: 100);
      expect(Desglose.de(conCosto(90), r).banda, Banda.pierde); // 100−90−13 <0
      expect(Desglose.de(conCosto(70), r).banda, Banda.noCubreFijos);
      expect(Desglose.de(conCosto(50), r).banda, Banda.cubreTodo);
    });

    test('al precio mínimo el platillo cubre sus gastos, siempre', () {
      // Con la fórmula sola, 298 de 20.000 casos quedaban un centavo cortos y
      // el desglose decía "cubre desde Q70.34" junto a "te queda −Q0.01".
      final azar = Random(70);
      for (var i = 0; i < 3000; i++) {
        final costo = azar.nextDouble() * 80 + 1;
        final r = repartoDe(
          fijos: azar.nextDouble() * 40000,
          variables: azar.nextDouble() * 20000,
          descuentos: azar.nextDouble() * 6000,
        );
        final p = uno([linea('a', 1)], [ing('a', precio: costo)], precio: 50);
        final minimo = Desglose.de(p, r).precioMinimo!;
        final alMinimo =
            uno([linea('a', 1)], [ing('a', precio: costo)], precio: minimo / 100);
        expect(Desglose.de(alMinimo, r).utilidad, greaterThanOrEqualTo(0),
            reason: 'costo $costo, mínimo $minimo');
      }
    });
  });

  group('la tarjeta y la lista', () {
    UtilidadMenu menuCon(List<double> costos, {RepartoGastos? reparto}) {
      final productos = [
        for (var i = 0; i < costos.length; i++)
          producto(id: 'p$i', nombre: 'Plato $i', precio: 100)
      ];
      final recetas = [
        for (var i = 0; i < costos.length; i++)
          linea('i$i', 1, producto: 'p$i')
      ];
      final ingredientes = [
        for (var i = 0; i < costos.length; i++) ing('i$i', precio: costos[i])
      ];
      return UtilidadMenu.armar(
        calcularMargenes(MenuCrudo(
            productos: productos, recetas: recetas, ingredientes: ingredientes)),
        reparto: reparto,
      );
    }

    test('sin reparto listo no hay desglose', () {
      final m = menuCon([30],
          reparto: repartoDe(rango: DateRange.today(), hoy: DateTime.now()));
      expect(m.conReparto, isFalse);
      expect(m.filas.single.desglose, isNull);
      expect(m.filas.single.pct, 70); // margen de receta
    });

    test('menos y más no se repiten y dejan fuera los sospechosos', () {
      final m = menuCon([10, 20, 30, 40, 50, 60, 70, 200, 1],
          reparto: repartoDe());
      final abajo = m.menosDejan(3).map((f) => f.platillo.producto).toList();
      final arriba = m.masDejan(3).map((f) => f.platillo.producto).toList();
      expect(abajo, ['Plato 6', 'Plato 5', 'Plato 4']);
      expect(arriba, ['Plato 0', 'Plato 1', 'Plato 2']);
      // Plato 7 cuesta más que su precio y Plato 8 deja 99%: por revisar.
      expect([...abajo, ...arriba], isNot(contains('Plato 7')));
      expect([...abajo, ...arriba], isNot(contains('Plato 8')));
      expect(m.porRevisar, 2);
    });

    test('un platillo de Q0 no entra al ranking', () {
      // Costo que redondea a cero centavos y precio cero: sin la regla no hay
      // ninguna alerta que lo saque, y encabezaba "los que menos dejan".
      final m = UtilidadMenu.armar(calcularMargenes(MenuCrudo(
        productos: [producto(precio: 0)],
        recetas: [linea('a', 1)],
        ingredientes: [ing('a', precio: 0.001)],
      )));
      expect(m.filas.single.platillo.alertas, isEmpty);
      expect(m.confiables, isEmpty);
    });

    test('los faltantes se ordenan por en cuántos platillos faltan', () {
      final m = UtilidadMenu.armar(calcularMargenes(MenuCrudo(
        productos: [
          producto(id: 'a', nombre: 'A'),
          producto(id: 'b', nombre: 'B'),
        ],
        recetas: [
          linea('queso', 1, producto: 'a'),
          linea('queso', 1, producto: 'b'),
          linea('tomate', 1, producto: 'b'),
        ],
        ingredientes: [
          ing('queso', precio: null, nombre: 'Queso'),
          ing('tomate', precio: null, nombre: 'Tomate'),
        ],
      )));
      final f = m.faltantes(5);
      expect(f.map((x) => '${x.ingrediente}:${x.platillos}'),
          ['Queso:2', 'Tomate:1']);
    });
  });

  group('lectura de Firestore', () {
    test('un producto borrado, apagado o sin presentaciones no entra', () {
      final base = {
        'name': 'X',
        'presentations': [
          {'id': 'p', 'name': 'N', 'price': 10},
        ],
      };
      expect(leerProducto('1', {...base}), isNotNull);
      expect(leerProducto('1', {...base, 'deleted': true}), isNull);
      expect(leerProducto('1', {...base, 'active': false}), isNull);
      expect(
          leerProducto('1', {
            'name': 'X',
            'presentations': [
              {'id': 'p', 'name': 'N', 'price': 10, 'deleted': true},
            ],
          }),
          isNull);
    });

    test('el precio entero se lee igual que el decimal', () {
      final p = leerProducto('1', {
        'name': 'X',
        'presentations': [
          {'id': 'a', 'name': 'N', 'price': 45},
        ],
      })!;
      expect(p.presentaciones.single.precio, 45.0);
    });

    test('toda línea con modifierId es de un extra, aunque venga vacío', () {
      for (final mod in ['mod1', '']) {
        expect(
            leerLineaReceta('d', {
              'productId': 'p',
              'presentationId': 'x',
              'ingredientId': 'a',
              'quantity': 1,
              'modifierId': mod,
            }),
            isNull);
      }
    });

    test('campos de otro tipo no revientan la lectura', () {
      final i = leerIngrediente('a', {
        'name': 'Sal',
        'code': 1001,
        'location_id': 7,
        'masterIngredientId': 5,
      })!;
      expect(i.codigo, '1001');
      expect(i.sucursalId, '7');
      expect(i.masterId, '5');

      final l = leerLineaReceta('d', {
        'productId': 'p',
        'presentationId': 'x',
        'ingredientId': 'a',
        'quantity': 1,
        'masterIngredientId': 9,
      })!;
      expect(l.masterId, '9');
    });

    test('un ingrediente sin nombre se usa como "Sin nombre", como el POS', () {
      expect(leerIngrediente('a', {'lastPurchasePrice': 3})!.nombre,
          'Sin nombre');
    });

    test('NaN o infinito no revientan: cuentan como dato ausente', () {
      expect(leerIngrediente('a', {'name': 'S', 'lastPurchasePrice': double.nan})!
          .tienePrecio, isFalse);
      expect(
          leerLineaReceta('d', {
            'productId': 'p',
            'presentationId': 'x',
            'ingredientId': 'a',
            'quantity': double.infinity,
          }),
          isNull);
    });

    test('unidad ausente o desconocida vale "unidades", como en el POS', () {
      expect(leerIngrediente('a', {'name': 'S'})!.unidad, 'unidades');
      expect(leerIngrediente('a', {'name': 'S', 'unit': 'tazas'})!.unidad,
          'unidades');
      expect(
          leerIngrediente('a', {'name': 'S', 'unit': 'kilogramos'})!
              .abreviatura,
          'kg');
      expect(
          leerIngrediente('a', {'name': 'S', 'customUnitId': 'u'})!.abreviatura,
          '');
    });

    test('precio por sucursal, disponibilidad y sucursales que venden', () {
      final m = interpretarMenu(const MenuDescargado(
        preciosSucursal: [
          DocCrudo('pr1_s2', {
            'presentation_id': 'pr1',
            'location_id': 's2',
            'price_override': 65,
            'enabled': false, // el POS cobra igual: no mira `enabled`
          }),
          DocCrudo('pr2_s2', {'presentation_id': 'pr2', 'location_id': 's2'}),
        ],
        disponibilidad: [
          DocCrudo('p1_s2',
              {'product_id': 'p1', 'location_id': 's2', 'enabled': false}),
          DocCrudo('p2_s2', {'product_id': 'p2', 'location_id': 's2'}),
        ],
        sucursales: [
          DocCrudo('s1', {'active': true}),
          DocCrudo('s2', {}),
          DocCrudo('bodega', {'is_central_warehouse': true}),
          DocCrudo('cerrada', {'active': false}),
        ],
      ));
      expect(m.preciosSucursal, {'pr1|s2': 65.0});
      expect(m.apagados, {'p1|s2'});
      expect(m.sucursalesVendibles, {'s1', 's2'});
    });

    test('un documento roto se cuenta y no tumba nada', () {
      final m = interpretarMenu(MenuDescargado(
        productos: [
          DocCrudo('roto', _MapaQueRevienta()),
          const DocCrudo('ok', {
            'name': 'X',
            'presentations': [
              {'id': 'a', 'name': 'N', 'price': 10},
            ],
          }),
        ],
      ));
      expect(m.productos, hasLength(1));
      expect(m.descartados, 1);
    });
  });

  group('la sucursal con que se costea', () {
    test('la elegida, si hay una elegida', () {
      expect(sucursalEfectiva('b', ['a', 'b']), 'b');
    });

    test('con una sola a la vista es esa, aunque el selector esté escondido',
        () {
      // Un usuario con una sola sucursal asignada no tiene pestañas: quedaba
      // en "Todas", con el precio base y la receta de otra sucursal.
      expect(sucursalEfectiva(null, ['a']), 'a');
    });

    test('con varias y ninguna elegida es "Todas"', () {
      expect(sucursalEfectiva(null, ['a', 'b']), isNull);
    });
  });

  group('formato', () {
    test('miles con coma, signo de resta tipográfico y cero sin signo', () {
      expect(formatoDinero(125000), 'Q1,250.00');
      expect(formatoDinero(-55800), '−Q558.00');
      expect(formatoDinero(0), 'Q0.00');
      expect(formatoPct(-620), '−620.0%');
      expect(formatoPct(-0.04), '0.0%');
    });

    test('las cantidades no pierden decimales que cambian la cuenta', () {
      expect(formatoCantidad(2), '2');
      expect(formatoCantidad(0.0125), '0.0125');
      expect(formatoCantidad(0.5), '0.5');
    });
  });
}

/// Un documento cuyo acceso revienta, para probar que se descarta solo.
class _MapaQueRevienta extends MapBase<String, dynamic> {
  @override
  dynamic operator [](Object? key) => throw StateError('documento roto');
  @override
  void operator []=(String key, dynamic value) {}
  @override
  void clear() {}
  @override
  Iterable<String> get keys => const [];
  @override
  dynamic remove(Object? key) => null;
}
