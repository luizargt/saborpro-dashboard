import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/data/models/rentabilidad_data.dart';

/// Un platillo con receta de un solo ingrediente y el costo que se pida.
///
/// [precio] y [costo] en quetzales. [unidad] 'und.' + [cantidad] 1 es lo que el
/// modelo toma por "de reventa".
MargenPlatillo plato(
  String id, {
  String pres = 'p1',
  double precio = 100,
  double? costo = 30,
  EstadoCosto? estado,
  List<LineaCosto>? lineas,
  String unidad = 'kg',
  double cantidad = 1,
  String? presentacion,
}) {
  final l = lineas ??
      (costo == null
          ? const <LineaCosto>[]
          : [LineaCosto(ingrediente: 'ing-$id', cantidad: cantidad, unidad: unidad, precio: costo / cantidad)]);
  return MargenPlatillo(
    productoId: id,
    presentacionId: pres,
    producto: 'Producto $id',
    presentacion: presentacion,
    precio: (precio * 100).round(),
    estado: estado ?? (l.isEmpty ? EstadoCosto.sinReceta : EstadoCosto.completo),
    lineas: l,
  );
}

UnidadesVendidas vendidas(Map<String, (int, double)> m, {int sinIdentificar = 0}) =>
    UnidadesVendidas({for (final e in m.entries) e.key: VentaDePlatillo(e.value.$1, e.value.$2)}, sinIdentificar);

ProfitabilityData datos({
  double ventas = 100000,
  double cogs = 30000,
  List<ExpenseLine>? gastos,
}) =>
    ProfitabilityData(
      netSales: ventas,
      cogs: cogs,
      itemsConCosto: 10,
      itemsSinCosto: 0,
      expenses: gastos ?? const [ExpenseLine(categoryId: 'renta', label: 'Renta', amount: 20000, esFijo: true)],
      payroll: 0,
      paidFromCash: 0,
      purchases: 0,
      inventoryValue: 0,
      ingredientesSinPrecio: 0,
    );

DateRange mes(int anio, int m) => DateRange(
      start: DateTime(anio, m, 1),
      end: DateTime(anio, m + 1, 0, 23, 59, 59),
      mode: PeriodMode.month,
    );

void main() {
  group('metaDe: con qué meta se compara cada platillo', () {
    test('de reventa: un solo ingrediente, una unidad, y no es comida', () {
      final lata = plato('gallo', unidad: 'und.');
      expect(metaDe(lata, null), MetaReceta.reventa);
      expect(metaDe(lata, 'Bebidas'), MetaReceta.reventa);
      expect(metaDe(lata, 'Otros'), MetaReceta.reventa);
    });

    test('lo clasificado como comida o postre nunca es reventa', () {
      final pan = plato('pan', unidad: 'und.');
      expect(metaDe(pan, 'Comida'), MetaReceta.comida);
      expect(metaDe(pan, 'Postres'), MetaReceta.comida);
    });

    test('dos unidades o una unidad que no es "und." no es reventa', () {
      expect(metaDe(plato('a', unidad: 'und.', cantidad: 2), 'Bebidas'), MetaReceta.bebida);
      expect(metaDe(plato('b', unidad: 'kg'), 'Bebidas'), MetaReceta.bebida);
      // Unidad personalizada (sin abreviatura): no se sabe qué es.
      expect(metaDe(plato('c', unidad: ''), null), MetaReceta.comida);
    });

    test('con varios ingredientes: bebida si es Bebidas, si no comida', () {
      final licuado = plato('lic', lineas: const [
        LineaCosto(ingrediente: 'fresa', cantidad: 0.1, unidad: 'kg', precio: 20),
        LineaCosto(ingrediente: 'leche', cantidad: 0.2, unidad: 'L', precio: 10),
      ]);
      expect(metaDe(licuado, 'Bebidas'), MetaReceta.bebida);
      expect(metaDe(licuado, 'Comida'), MetaReceta.comida);
      expect(metaDe(licuado, null), MetaReceta.comida);
    });

    test('las metas son las del diseño', () {
      expect(MetaReceta.comida.pct, 35);
      expect(MetaReceta.bebida.pct, 25);
      expect(MetaReceta.reventa.pct, 70);
    });
  });

  group('sucursalesSinGastosFijos', () {
    final sucursales = [('A', 'Chiquimula'), ('B', 'La Reforma'), ('C', 'Santa Rosalía')];

    Map<String, dynamic> g(String? loc, double monto, String cat, {String? tipo}) =>
        {if (loc != null) 'location_id': loc, 'amount': monto, 'category_id': cat, if (tipo != null) 'type': tipo};

    test('las que no tienen ningún gasto fijo, en el orden de las pestañas', () {
      final r = sucursalesSinGastosFijos(
        gastos: [g('A', 12000, 'renta'), g('B', 500, 'luz', tipo: 'variable')],
        sucursales: sucursales,
      );
      expect(r, ['La Reforma', 'Santa Rosalía']);
    });

    test('un gasto marcado fijo por tipo cuenta aunque su categoría no sea fija', () {
      expect(
        sucursalesSinGastosFijos(gastos: [g('B', 300, 'luz', tipo: 'fixed')], sucursales: sucursales),
        ['Chiquimula', 'Santa Rosalía'],
      );
    });

    test('en cero, negativo, sin monto o sin sucursal no cuenta', () {
      final r = sucursalesSinGastosFijos(
        gastos: [
          g('A', 0, 'renta'),
          g('B', -50, 'renta'),
          g(null, 100, 'renta'),
          {'location_id': 'C', 'category_id': 'renta'},
          {'location_id': 'C', 'amount': 'mucho', 'category_id': 'renta'},
        ],
        sucursales: sucursales,
      );
      expect(r, ['Chiquimula', 'La Reforma', 'Santa Rosalía']);
    });

    test('los gastos de una sucursal que no se ve no le sirven a las que sí', () {
      expect(sucursalesSinGastosFijos(gastos: [g('Z', 100, 'renta')], sucursales: [('A', 'Chiquimula')]), ['Chiquimula']);
    });

    test('sin gastos, todas faltan; sin sucursales, ninguna', () {
      expect(sucursalesSinGastosFijos(gastos: const [], sucursales: sucursales).length, 3);
      expect(sucursalesSinGastosFijos(gastos: [g('A', 1, 'renta')], sucursales: const []), isEmpty);
    });
  });

  group('diaDeEquilibrio', () {
    // Ventas 100,000, costo 30,000 y renta 20,000: queda 70% de cada venta, así
    // que el equilibrio es 20,000 / 0.7 = 28,571.43.
    final d = datos();

    test('mes terminado: lo vendido repartido en los 31 días', () {
      // 100,000 / 31 = 3,225.8 por día → 28,571.43 se cubre el día 9.
      expect(diaDeEquilibrio(d, mes(2026, 10), DateTime(2026, 11, 3)), 9);
    });

    test('mes en curso: se reparte entre los días que van', () {
      // A día 10, 100,000 / 10 = 10,000 por día → el día 3.
      expect(diaDeEquilibrio(d, mes(2026, 10), DateTime(2026, 10, 10, 15)), 3);
    });

    test('nunca pasa del día en que se está', () {
      final justo = datos(ventas: 28572, cogs: 8000); // pasa el equilibrio (27,777) por poco
      expect(diaDeEquilibrio(justo, mes(2026, 10), DateTime(2026, 10, 5)), 5);
    });

    test('solo con un mes elegido', () {
      final dia = DateRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 1, 23, 59), mode: PeriodMode.day);
      expect(diaDeEquilibrio(d, dia, DateTime(2026, 10, 2)), isNull);
      final anio = DateRange(start: DateTime(2026), end: DateTime(2026, 12, 31), mode: PeriodMode.year);
      expect(diaDeEquilibrio(d, anio, DateTime(2027)), isNull);
    });

    test('si no se cubrió, o no se puede calcular, no hay día', () {
      expect(diaDeEquilibrio(datos(ventas: 20000), mes(2026, 10), DateTime(2026, 11, 3)), isNull);
      // Sin gastos fijos el equilibrio es cero y no dice nada.
      expect(diaDeEquilibrio(datos(gastos: const []), mes(2026, 10), DateTime(2026, 11, 3)), isNull);
      // Cada venta pierde: no hay equilibrio.
      expect(diaDeEquilibrio(datos(ventas: 100, cogs: 500), mes(2026, 10), DateTime(2026, 11, 3)), isNull);
    });

    test('un mes que todavía no empieza no tiene día', () {
      expect(diaDeEquilibrio(d, mes(2027, 1), DateTime(2026, 11, 3)), isNull);
    });
  });

  group('ComparacionSucursales', () {
    final sucs = [('A', 'Chiquimula'), ('B', 'La Reforma'), ('C', 'Santa Rosalía')];

    ProfitabilityData con({required double ventas, required double cogs, double renta = 10000}) =>
        datos(ventas: ventas, cogs: cogs, gastos: renta > 0 ? [ExpenseLine(categoryId: 'renta', label: 'Renta', amount: renta, esFijo: true)] : const []);

    test('la de más margen entre las que tienen gastos fijos', () {
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 100000, cogs: 30000), // 60%
        'B': con(ventas: 100000, cogs: 80000), // 10%
        'C': con(ventas: 50000, cogs: 10000, renta: 0), // sin gastos fijos: no se sabe
      }, sucursales: sucs);
      expect(r.filas.map((f) => f.nombre), ['Chiquimula', 'La Reforma', 'Santa Rosalía']);
      expect(r.mejor?.id, 'A');
      expect(r.filas.last.conGastosFijos, isFalse);
      expect(r.hayQueComparar, isTrue);
    });

    test('la que no tiene gastos fijos no gana aunque su "margen" sea enorme', () {
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 100000, cogs: 80000), // 10%
        'B': con(ventas: 100000, cogs: 85000), // 5%
        'C': con(ventas: 100000, cogs: 0, renta: 0), // 100% pero sin gastos
      }, sucursales: sucs);
      expect(r.mejor?.id, 'A');
    });

    test('con una sola comparable no se corona a nadie', () {
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 100000, cogs: 30000),
        'B': con(ventas: 100000, cogs: 30000, renta: 0),
        'C': con(ventas: 100000, cogs: 30000, renta: 0),
      }, sucursales: sucs);
      expect(r.mejor, isNull);
    });

    test('sin ventas no se compara', () {
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 100000, cogs: 30000),
        'B': con(ventas: 0, cogs: 0),
      }, sucursales: sucs);
      expect(r.mejor, isNull);
    });

    test('solo las sucursales que tienen números; menos de dos no es comparación', () {
      final una = ComparacionSucursales.armar(porSucursal: {'A': con(ventas: 1000, cogs: 100)}, sucursales: sucs);
      expect(una.filas.length, 1);
      expect(una.hayQueComparar, isFalse);
      expect(ComparacionSucursales.armar(porSucursal: const {}, sucursales: sucs).hayQueComparar, isFalse);
    });

    test('lo que muestra cada una: ventas, % de costo, todos los gastos y utilidad', () {
      final r = ComparacionSucursales.armar(
        porSucursal: {'A': con(ventas: 100000, cogs: 32000, renta: 12000), 'B': con(ventas: 1, cogs: 0)},
        sucursales: sucs,
      );
      final a = r.filas.first;
      expect(a.ventas, 100000);
      expect(a.costoPct, 32);
      expect(a.gastos, 12000);
      expect(a.utilidad, 56000);
      expect(a.margen, closeTo(56, 1e-9));
    });
  });

  group('UnidadesVendidas', () {
    final platillos = [
      plato('p1', pres: 'a'),
      plato('p2', pres: 'a'),
      plato('p2', pres: 'b'),
    ];

    Map<String, dynamic> item(String prod, String? pres, {Object? qty = 1, double precio = 10, bool anulado = false, bool cortesia = false}) => {
          'product_id': prod,
          if (pres != null) 'presentation_id': pres,
          if (qty != null) 'qty': qty,
          'unit_price': precio,
          if (anulado) 'is_void': true,
          if (cortesia) 'is_courtesy': true,
        };

    Map<String, dynamic> orden(String loc, List<Object?> items, {bool devolucion = false}) =>
        {'location_id': loc, 'items': items, if (devolucion) 'is_refund': true};

    test('suma unidades y plata por presentación', () {
      final u = UnidadesVendidas.desde([
        orden('A', [item('p1', 'a', qty: 2, precio: 10), item('p2', 'b', qty: 1, precio: 30)]),
        orden('B', [item('p1', 'a', qty: 3, precio: 12)]),
      ], platillos);
      expect(u.cantidadDe('p1|a'), 5);
      expect(u.porClave['p1|a']!.ventas, 2 * 10 + 3 * 12);
      expect(u.cantidadDe('p2|b'), 1);
      expect(u.cantidadDe('p2|a'), 0);
      expect(u.sinIdentificar, 0);
    });

    test('no cuentan las anuladas, las de cortesía ni los pedidos de devolución', () {
      final u = UnidadesVendidas.desde([
        orden('A', [item('p1', 'a', anulado: true), item('p1', 'a', cortesia: true), item('p1', 'a', qty: 4)]),
        orden('A', [item('p1', 'a', qty: 9)], devolucion: true),
      ], platillos);
      expect(u.cantidadDe('p1|a'), 4);
    });

    test('solo la sucursal pedida, o solo el grupo de sucursales', () {
      final ordenes = [
        orden('A', [item('p1', 'a', qty: 1)]),
        orden('B', [item('p1', 'a', qty: 10)]),
        orden('C', [item('p1', 'a', qty: 100)]),
      ];
      expect(UnidadesVendidas.desde(ordenes, platillos, sucursal: 'B').cantidadDe('p1|a'), 10);
      expect(UnidadesVendidas.desde(ordenes, platillos, soloSucursales: {'A', 'C'}).cantidadDe('p1|a'), 101);
      expect(UnidadesVendidas.desde(ordenes, platillos).cantidadDe('p1|a'), 111);
    });

    test('sin presentación, solo se sabe cuál es si el producto tiene una', () {
      final u = UnidadesVendidas.desde([
        orden('A', [item('p1', null, qty: 2), item('p2', null, qty: 5)]),
      ], platillos);
      expect(u.cantidadDe('p1|a'), 2);
      // p2 tiene dos presentaciones: no se adivina.
      expect(u.cantidadDe('p2|a') + u.cantidadDe('p2|b'), 0);
      expect(u.sinIdentificar, 5);
    });

    test('un producto o una presentación que ya no están en el menú se cuentan aparte', () {
      final u = UnidadesVendidas.desde([
        orden('A', [item('borrado', 'x', qty: 3), item('p1', 'vieja', qty: 2)]),
      ], platillos);
      expect(u.porClave, isEmpty);
      expect(u.sinIdentificar, 5);
    });

    test('un dato roto no tumba la cuenta', () {
      final u = UnidadesVendidas.desde([
        {'location_id': 'A'},
        {'location_id': 'A', 'items': 'nada'},
        orden('A', [
          'raro',
          null,
          item('p1', 'a', qty: null), // sin cantidad: una unidad
          item('p1', 'a', qty: 0),
          item('p1', 'a', qty: -3),
          item('p1', 'a', qty: double.nan),
          item('p1', 'a', qty: 2, precio: double.infinity),
          {'product_id': 'p1', 'presentation_id': 'a', 'quantity': 2, 'price': 5},
        ]),
      ], platillos);
      expect(u.cantidadDe('p1|a'), 1 + 2 + 2);
      expect(u.porClave['p1|a']!.ventas.isFinite, isTrue);
    });
  });

  group('AnalisisMenu', () {
    PlatilloVendido? buscar(AnalisisMenu a, String id) {
      for (final p in a.analizados) {
        if (p.platillo.productoId == id) return p;
      }
      return null;
    }

    test('separa lo analizable de lo que no tiene costo confiable', () {
      final platillos = [
        plato('ok'),
        plato('sinreceta', costo: null),
        plato('incompleto', estado: EstadoCosto.incompleto, lineas: const [
          LineaCosto(ingrediente: 'x', cantidad: 1, estado: EstadoLinea.sinPrecio),
        ]),
        plato('caro', precio: 10, costo: 20), // cuesta más de lo que se cobra: por revisar
        plato('gratis', precio: 0, costo: 5),
        plato('nadavendido'),
      ];
      final a = AnalisisMenu.armar(
        platillos: platillos,
        vendidas: vendidas({
          'ok|p1': (10, 100),
          'sinreceta|p1': (7, 70),
          'incompleto|p1': (3, 30),
          'caro|p1': (2, 20),
          'gratis|p1': (1, 0),
        }),
      );
      expect(a.analizados.map((p) => p.platillo.productoId), ['ok']);
      expect(a.sinReceta.map((p) => p.platillo.productoId), ['sinreceta']);
      expect(a.incompletos, 1);
      // Todo lo vendido que no entra: sin receta, incompleto, por revisar y sin precio.
      expect(a.sinCostoConfiable, 4);
      expect(a.hayAlgo, isTrue);
    });

    test('sin ventas no hay nada que analizar', () {
      final a = AnalisisMenu.armar(platillos: [plato('a')], vendidas: UnidadesVendidas.vacio);
      expect(a.hayAlgo, isFalse);
      expect(a.mapa.values.every((l) => l.isEmpty), isTrue);
      expect(a.masGanancia(8), isEmpty);
      expect(a.porVenta().revisa, isEmpty);
    });

    test('los sin receta, de más a menos vendido en plata', () {
      final a = AnalisisMenu.armar(
        platillos: [plato('a', costo: null), plato('b', costo: null), plato('c', costo: null)],
        vendidas: vendidas({'a|p1': (100, 500), 'b|p1': (5, 900), 'c|p1': (50, 700)}),
      );
      expect(a.sinReceta.map((p) => p.platillo.productoId), ['b', 'c', 'a']);
    });

    group('el mapa', () {
      // 100 y 10 unidades; Q10 y Q2 por venta. Promedio de unidades 55 (se vende
      // mucho desde 38.5) y ganancia promedio ponderada (1000+200+100+20)/220 = 6.
      final platillos = [
        plato('estrella', precio: 20, costo: 10), // gana 10
        plato('caballo', precio: 10, costo: 8), // gana 2
        plato('rompe', precio: 30, costo: 20), // gana 10
        plato('perro', precio: 6, costo: 4), // gana 2
      ];
      final a = AnalisisMenu.armar(
        platillos: platillos,
        vendidas: vendidas({'estrella|p1': (100, 0), 'caballo|p1': (100, 0), 'rompe|p1': (10, 0), 'perro|p1': (10, 0)}),
      );

      test('cada platillo cae en su cuadrante', () {
        final m = a.mapa;
        expect(m[Cuadrante.estrella]!.map((p) => p.platillo.productoId), ['estrella']);
        expect(m[Cuadrante.caballo]!.map((p) => p.platillo.productoId), ['caballo']);
        expect(m[Cuadrante.rompecabezas]!.map((p) => p.platillo.productoId), ['rompe']);
        expect(m[Cuadrante.perro]!.map((p) => p.platillo.productoId), ['perro']);
      });

      test('los promedios', () {
        expect(a.promedios.unidades, 55);
        expect(a.promedios.ganancia, closeTo(6, 1e-9));
      });

      test('todos entran en alguno, ninguno en dos', () {
        final todos = a.mapa.values.expand((l) => l).toList();
        expect(todos.length, 4);
        expect(todos.toSet().length, 4);
      });

      test('dentro de un cuadrante, los más vendidos primero', () {
        final b = AnalisisMenu.armar(
          platillos: [plato('x', precio: 20, costo: 10), plato('y', precio: 20, costo: 10)],
          vendidas: vendidas({'x|p1': (30, 0), 'y|p1': (50, 0)}),
        );
        expect(b.mapa[Cuadrante.estrella]!.map((p) => p.platillo.productoId), ['y', 'x']);
      });

      test('un solo platillo es estrella: él mismo es el promedio', () {
        final b = AnalisisMenu.armar(platillos: [plato('solo')], vendidas: vendidas({'solo|p1': (3, 0)}));
        expect(b.mapa[Cuadrante.estrella]!.length, 1);
      });
    });

    test('la ganancia total: lo que deja cada venta por lo vendido', () {
      final a = AnalisisMenu.armar(
        platillos: [plato('a', precio: 20, costo: 10), plato('b', precio: 10, costo: 8), plato('c', precio: 30, costo: 20)],
        vendidas: vendidas({'a|p1': (100, 0), 'b|p1': (100, 0), 'c|p1': (10, 0)}),
      );
      final top = a.masGanancia(2);
      expect(top.map((p) => p.platillo.productoId), ['a', 'b']);
      expect(top.first.gananciaPorVenta, 10);
      expect(top.first.gananciaTotal, 1000);
      expect(top.last.gananciaTotal, 200);
      expect(a.masGanancia(99).length, 3);
    });

    group('por venta, contra la meta de cada tipo', () {
      // Receta contra precio Q100: A 20% (comida, bajo su 35), B 50% (comida, +15),
      // C 30% (bebida, +5 sobre su 25), D 60% (reventa, −10 de su 70), E 35% (justo).
      final platillos = [
        plato('A', costo: 20),
        plato('B', costo: 50),
        plato('C', costo: 30, lineas: const [
          LineaCosto(ingrediente: 'a', cantidad: 1, unidad: 'kg', precio: 15),
          LineaCosto(ingrediente: 'b', cantidad: 1, unidad: 'kg', precio: 15),
        ]),
        plato('D', lineas: const [LineaCosto(ingrediente: 'lata', cantidad: 1, unidad: 'und.', precio: 60)]),
        plato('E', costo: 35),
      ];
      final a = AnalisisMenu.armar(
        platillos: platillos,
        vendidas: vendidas({for (final id in ['A', 'B', 'C', 'D', 'E']) '$id|p1': (10, 0)}),
        clasificacion: {'C': 'Bebidas', 'D': 'Bebidas'},
      );

      test('cada platillo con su meta', () {
        expect(buscar(a, 'A')!.meta, MetaReceta.comida);
        expect(buscar(a, 'C')!.meta, MetaReceta.bebida);
        expect(buscar(a, 'D')!.meta, MetaReceta.reventa);
        expect(buscar(a, 'B')!.recetaPct, 50);
        expect(buscar(a, 'D')!.sobreLaMeta, closeTo(-10, 1e-9));
      });

      test('"revisa" los que pasan su meta, "más ganancia" los que no; sin repetir', () {
        final r = a.porVenta();
        expect(r.revisa.map((p) => p.platillo.productoId), ['B', 'C']);
        expect(r.mas.map((p) => p.platillo.productoId), ['A', 'D', 'E']);
        final ids = [...r.revisa, ...r.mas].map((p) => p.platillo.productoId).toList();
        expect(ids.toSet().length, ids.length);
      });

      test('el tope por lista', () {
        final r = a.porVenta(n: 1);
        expect(r.revisa.length, 1);
        expect(r.mas.length, 1);
        expect(r.revisa.single.platillo.productoId, 'B');
        expect(r.mas.single.platillo.productoId, 'A');
      });
    });

    test('el porcentaje de receta usa el precio del platillo, no el cobrado', () {
      final a = AnalisisMenu.armar(platillos: [plato('a', precio: 50, costo: 10)], vendidas: vendidas({'a|p1': (1, 999)}));
      expect(a.analizados.single.recetaPct, 20);
    });
  });

  group('lo que encontró la revisión adversarial', () {
    ProfitabilityData con({required double ventas, required double cogs, double renta = 10000, int conCosto = 100, int sinCosto = 0}) => ProfitabilityData(
          netSales: ventas,
          cogs: cogs,
          itemsConCosto: conCosto,
          itemsSinCosto: sinCosto,
          expenses: [ExpenseLine(categoryId: 'renta', label: 'Renta', amount: renta, esFijo: true)],
          payroll: 0,
          paidFromCash: 0,
          purchases: 0,
          inventoryValue: 0,
          ingredientesSinPrecio: 0,
        );

    const sucs = [('A', 'Chiquimula'), ('B', 'La Reforma')];

    test('una sucursal sin costo de comida cargado no gana: su margen es falso', () {
      // B "gana" con 80% de margen porque nadie anotó lo que le costó la comida.
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 10000, cogs: 3500, renta: 2000),
        'B': con(ventas: 10000, cogs: 0, renta: 2000, conCosto: 0),
      }, sucursales: sucs);
      expect(r.mejor, isNull);
      expect(r.filas.last.costoConfiable, isFalse);
    });

    test('con poca cobertura del costo tampoco gana', () {
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 10000, cogs: 3500, renta: 2000),
        'B': con(ventas: 10000, cogs: 500, renta: 2000, conCosto: 10, sinCosto: 90),
      }, sucursales: sucs);
      expect(r.mejor, isNull);
    });

    test('con el costo confiable en las dos, sigue ganando la de más margen', () {
      final r = ComparacionSucursales.armar(porSucursal: {
        'A': con(ventas: 10000, cogs: 3500, renta: 2000),
        'B': con(ventas: 10000, cogs: 2500, renta: 2000),
      }, sucursales: sucs);
      expect(r.mejor?.id, 'B');
    });

    test('lo vendido que no está en ninguna tarjeta se calcula contra el total', () {
      final r = ComparacionSucursales.armar(
        porSucursal: {'A': con(ventas: 1000, cogs: 300), 'B': con(ventas: 500, cogs: 100)},
        sucursales: sucs,
        ventasTotales: 1850, // 300 de una sucursal oculta y 50 sin sucursal
      );
      expect(r.ventasFuera, 350);
      expect(ComparacionSucursales.armar(porSucursal: {'A': con(ventas: 1, cogs: 0)}, sucursales: sucs).ventasFuera, 0);
    });

    test('el mapa no depende del redondeo de los decimales', () {
      // Un solo platillo ES el promedio: siempre es estrella. Con promedios en
      // decimales, precio 5, costo 1.13 y 17 unidades salía "gana poco".
      for (final (precio, costo, q) in const [(5.0, 1.13, 17), (5.0, 1.37, 3), (7.3, 2.1, 11), (19.99, 4.01, 7)]) {
        final a = AnalisisMenu.armar(platillos: [plato('x', precio: precio, costo: costo)], vendidas: vendidas({'x|p1': (q, 0)}));
        expect(a.mapa[Cuadrante.estrella]!.length, 1, reason: '$precio/$costo/$q');
      }
    });

    test('varios platillos con la misma ganancia son todos estrella', () {
      final a = AnalisisMenu.armar(
        platillos: [plato('a', precio: 5, costo: 1.37), plato('b', precio: 5, costo: 1.37), plato('c', precio: 5, costo: 1.37), plato('d', precio: 5, costo: 1.37)],
        vendidas: vendidas({'a|p1': (10, 0), 'b|p1': (10, 0), 'c|p1': (10, 0), 'd|p1': (10, 0)}),
      );
      expect(a.mapa[Cuadrante.estrella]!.length, 4);
    });

    test('un platillo que no deja nada no "gana mucho"', () {
      final a = AnalisisMenu.armar(platillos: [plato('cero', precio: 10, costo: 10)], vendidas: vendidas({'cero|p1': (5, 0)}));
      expect(a.analizados.length, 1);
      expect(a.mapa[Cuadrante.estrella], isEmpty);
      expect(a.mapa[Cuadrante.rompecabezas], isEmpty);
      expect(a.mapa[Cuadrante.caballo]!.length + a.mapa[Cuadrante.perro]!.length, 1);
    });

    test('el día de equilibrio no se pasa un día por ruido de decimales', () {
      // be 150, ventas 300 en 14 días: 150 / (300 / 14) = 7.000000000000001.
      final d = datos(ventas: 300, cogs: 0, gastos: const [ExpenseLine(categoryId: 'renta', label: 'Renta', amount: 150, esFijo: true)]);
      expect(diaDeEquilibrio(d, mes(2026, 10), DateTime(2026, 10, 14, 20)), 7);
    });

    test('con números rotos no lanza', () {
      final nan = datos(ventas: double.nan);
      expect(diaDeEquilibrio(nan, mes(2026, 10), DateTime(2026, 11, 3)), isNull);
      final inf = datos(ventas: double.infinity, cogs: 0);
      expect(diaDeEquilibrio(inf, mes(2026, 10), DateTime(2026, 11, 3)), anyOf(isNull, isA<int>()));
    });

    test('una categoría que no es texto no tumba la lista de sucursales sin fijos', () {
      expect(
        sucursalesSinGastosFijos(gastos: [
          {'location_id': 'A', 'amount': 100, 'category_id': 5},
          {'location_id': 'A', 'amount': 100, 'category_id': 'renta'},
        ], sucursales: const [('A', 'Chiquimula'), ('B', 'La Reforma')]),
        ['La Reforma'],
      );
    });
  });
}
