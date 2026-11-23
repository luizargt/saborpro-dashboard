import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/compras_ventas.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/data/models/rentabilidad_calculo.dart';
import 'package:saborpro_reports/presentation/widgets/compras_ventas_view.dart' show BodegaVista, DatoBodega;

DateRange mes(int anio, int m) => DateRange(start: DateTime(anio, m, 1), end: DateTime(anio, m + 1, 0, 23, 59, 59), mode: PeriodMode.month);

ProfitabilityData datos({double ventas = 1000, double cogs = 400, double compras = 500}) => ProfitabilityData(
      netSales: ventas,
      cogs: cogs,
      itemsConCosto: 10,
      itemsSinCosto: 0,
      expenses: const [],
      payroll: 0,
      paidFromCash: 0,
      purchases: compras,
      inventoryValue: 0,
      ingredientesSinPrecio: 0,
    );

IngredienteVivo ing(Map<String, dynamic> o) => IngredienteVivo.desde(
      o['id'] as String? ?? 'x',
      {'location_id': 'A', 'currentStock': 1, 'lastPurchasePrice': 1, 'active': true, 'name': 'x', ...o},
    )!;

void main() {
  group('la foto del servidor, leída sin lanzar', () {
    test('un documento bueno', () {
      final f = FotoBodega.desde({
        'tenant_id': 't1',
        'fecha': '2026-11-01',
        'sucursales': {
          'A': {
            'total': 1234.5,
            'central': false,
            'sin_precio': 2,
            'imposibles': ['Pollo'],
            'por_categoria': [
              {'nombre': 'Cerveza', 'valor': 1000},
              {'nombre': 'Carnes', 'valor': 234.5},
            ],
          },
          'CEN': {'total': 99, 'central': true},
        },
      })!;
      expect(f.fecha, '2026-11-01');
      expect(f.dia, DateTime(2026, 11, 1));
      expect(f.sucursales['A']!.total, 1234.5);
      expect(f.sucursales['A']!.sinPrecio, 2);
      expect(f.sucursales['A']!.imposibles, ['Pollo']);
      expect(f.sucursales['A']!.porCategoria.map((c) => c.nombre), ['Cerveza', 'Carnes']);
      expect(f.sucursales['CEN']!.central, isTrue);
    });

    test('sin fecha válida no hay foto', () {
      expect(FotoBodega.desde({'sucursales': {}}), isNull);
      expect(FotoBodega.desde({'fecha': '1 de noviembre'}), isNull);
      expect(FotoBodega.desde({'fecha': 20261101}), isNull);
    });

    test('una sucursal rota se salta y las demás se leen', () {
      final f = FotoBodega.desde({
        'fecha': '2026-11-01',
        'sucursales': {
          'A': {'total': 10},
          'B': 'nada',
          'C': {'total': 'mucho'},
          'D': {'total': double.nan},
          'E': {
            'total': 5,
            'por_categoria': [
              'x',
              {'nombre': '', 'valor': 1},
              {'nombre': 'Ok', 'valor': 2},
              {'nombre': 'Mal', 'valor': 'a'},
            ],
          },
        },
      })!;
      expect(f.sucursales.keys, ['A', 'E']);
      expect(f.sucursales['E']!.porCategoria.map((c) => c.nombre), ['Ok']);
    });

    test('sin sucursales es una foto vacía, no un error', () {
      expect(FotoBodega.desde({'fecha': '2026-11-01'})!.sucursales, isEmpty);
      expect(FotoBodega.desde({'fecha': '2026-11-01', 'sucursales': 5})!.sucursales, isEmpty);
    });
  });

  group('valorarBodega: las mismas reglas que la función del servidor', () {
    final hoy = DateTime(2026, 11, 22);
    FotoBodega v(List<IngredienteVivo> l, {Map<String, String> cats = const {}, Map<String, bool> centrales = const {}}) =>
        valorarBodega(ingredientes: l, nombreDeCategoria: cats, centrales: centrales, hoy: hoy);

    test('existencia × último precio, por sucursal', () {
      final f = v([
        ing({'currentStock': 10, 'lastPurchasePrice': 7.5}),
        ing({'currentStock': 2, 'lastPurchasePrice': 3}),
        ing({'location_id': 'B', 'currentStock': 1, 'lastPurchasePrice': 5}),
      ]);
      expect(f.fecha, '2026-11-22');
      expect(f.sucursales['A']!.total, 81);
      expect(f.sucursales['B']!.total, 5);
    });

    test('inactivos, en cero, negativos e ilegibles no cuentan', () {
      final f = v([
        ing({'active': false, 'currentStock': 100, 'lastPurchasePrice': 100}),
        ing({'currentStock': 0}),
        ing({'currentStock': -5}),
        ing({'currentStock': 'mucho'}),
        ing({'currentStock': 4, 'lastPurchasePrice': 2}),
      ]);
      expect(f.sucursales['A']!.total, 8);
    });

    test('sin precio no suma y se cuenta', () {
      final f = v([
        ing({'currentStock': 5, 'lastPurchasePrice': null}),
        ing({'currentStock': 5, 'lastPurchasePrice': 0}),
        ing({'currentStock': 5, 'lastPurchasePrice': -1}),
        ing({'currentStock': 1, 'lastPurchasePrice': 4}),
      ]);
      expect(f.sucursales['A']!.total, 4);
      expect(f.sucursales['A']!.sinPrecio, 3);
    });

    test('una existencia imposible no suma y se nombra; justo por debajo sí cuenta', () {
      final f = v([
        ing({'name': 'Pollo', 'currentStock': kStockImposible, 'lastPurchasePrice': 10}),
        ing({'currentStock': kStockImposible - 1, 'lastPurchasePrice': 1}),
      ]);
      expect(f.sucursales['A']!.imposibles, ['Pollo']);
      expect(f.sucursales['A']!.total, kStockImposible - 1);
    });

    test('las categorías se unen por nombre, sin importar mayúsculas ni tildes', () {
      final f = v([
        ing({'categoryId': 'c1', 'currentStock': 1, 'lastPurchasePrice': 10}),
        ing({'categoryId': 'c3', 'currentStock': 1, 'lastPurchasePrice': 5}),
        ing({'categoryId': 'c2', 'currentStock': 1, 'lastPurchasePrice': 30}),
        ing({'categoryId': null, 'currentStock': 1, 'lastPurchasePrice': 1}),
      ], cats: {'c1': 'Cervezá', 'c3': 'cervezA', 'c2': 'Carnes'});
      final por = {for (final c in f.sucursales['A']!.porCategoria) c.nombre: c.valor};
      expect(por['Cervezá'], 15);
      expect(por['Carnes'], 30);
      expect(por['Sin categoría'], 1);
      expect(f.sucursales['A']!.porCategoria.first.nombre, 'Carnes');
    });

    test('la bodega central se marca', () {
      final f = v([ing({'location_id': 'CEN'}), ing({'location_id': 'A'})], centrales: {'CEN': true});
      expect(f.sucursales['CEN']!.central, isTrue);
      expect(f.sucursales['A']!.central, isFalse);
    });

    test('un ingrediente sin sucursal no se puede ligar y se ignora', () {
      expect(IngredienteVivo.desde('x', {'currentStock': 3}), isNull);
      expect(IngredienteVivo.desde('x', {'location_id': '  ', 'currentStock': 3}), isNull);
    });
  });

  group('BodegaPeriodo: el valor al inicio y al fin, en la moneda de la vista', () {
    final inicio = FotoBodega('2026-10-01', {
      'A': const SucursalFoto(total: 100),
      'B': const SucursalFoto(total: 50),
      'CEN': const SucursalFoto(total: 999, central: true),
    });
    final fin = FotoBodega('2026-11-01', {
      'A': const SucursalFoto(total: 120, sinPrecio: 1, imposibles: ['Pollo'], porCategoria: [CategoriaValor('Cerveza', 70), CategoriaValor('Carnes', 50)]),
      'B': const SucursalFoto(total: 30, porCategoria: [CategoriaValor('cerveza', 30)]),
      'CEN': const SucursalFoto(total: 500, central: true),
    });

    test('suma las sucursales que se ven, convertidas, sin la bodega central', () {
      final b = BodegaPeriodo.armar(
        inicio: inicio,
        fin: fin,
        finEsHoy: false,
        sucursales: {'A', 'B', 'CEN'},
        factor: (loc, fecha) => loc == 'B' ? 2.0 : 1.0,
      );
      expect(b.inicio, 100 + 50 * 2);
      expect(b.fin, 120 + 30 * 2);
      expect(b.inicioPorSucursal.keys, unorderedEquals(['A', 'B']));
      expect(b.completa, isTrue);
    });

    test('solo las sucursales a la vista', () {
      final b = BodegaPeriodo.armar(inicio: inicio, fin: fin, finEsHoy: false, sucursales: {'A'}, factor: (_, __) => 1);
      expect(b.inicio, 100);
      expect(b.fin, 120);
    });

    test('una moneda sin tipo de cambio no se suma', () {
      final b = BodegaPeriodo.armar(
        inicio: inicio,
        fin: fin,
        finEsHoy: false,
        sucursales: {'A', 'B'},
        factor: (loc, _) => loc == 'B' ? null : 1.0,
      );
      expect(b.inicio, 100);
      expect(b.fin, 120);
    });

    test('el factor se pide a la fecha de cada foto', () {
      final fechas = <String>[];
      BodegaPeriodo.armar(inicio: inicio, fin: fin, finEsHoy: false, sucursales: {'A'}, factor: (loc, f) {
        fechas.add('$loc ${f.month}');
        return 1.0;
      });
      expect(fechas, containsAll(['A 10', 'A 11']));
    });

    test('lo que queda por categoría, unido por nombre y convertido', () {
      final b = BodegaPeriodo.armar(inicio: inicio, fin: fin, finEsHoy: false, sucursales: {'A', 'B'}, factor: (loc, _) => loc == 'B' ? 2.0 : 1.0);
      expect(b.finPorCategoria['cerveza']!.valor, 70 + 30 * 2);
      expect(b.finPorCategoria['cerveza']!.nombre, 'Cerveza');
      expect(b.finPorCategoria['carnes']!.valor, 50);
    });

    test('las existencias sin valorar se juntan para avisarlo', () {
      final b = BodegaPeriodo.armar(inicio: inicio, fin: fin, finEsHoy: false, sucursales: {'A', 'B'}, factor: (_, __) => 1);
      expect(b.sinPrecio, 1);
      expect(b.imposibles, ['Pollo']);
    });

    test('sin foto del inicio no hay "Tenías"; sin la del fin no hay "Te queda"', () {
      final a = BodegaPeriodo.armar(inicio: null, fin: fin, finEsHoy: false, sucursales: {'A'}, factor: (_, __) => 1);
      expect(a.inicio, isNull);
      expect(a.fin, 120);
      expect(a.completa, isFalse);
      final b = BodegaPeriodo.armar(inicio: inicio, fin: null, finEsHoy: false, sucursales: {'A'}, factor: (_, __) => 1);
      expect(b.inicio, 100);
      expect(b.fin, isNull);
    });

    test('una foto sin una sucursal vale cero para ella, no rompe', () {
      final b = BodegaPeriodo.armar(inicio: inicio, fin: fin, finEsHoy: false, sucursales: {'A', 'NUEVA'}, factor: (_, __) => 1);
      expect(b.inicio, 100);
      expect(b.finPorSucursal.containsKey('NUEVA'), isFalse);
    });
  });

  group('qué pasó con la bodega', () {
    test('igual si cambió menos del 3% de lo comprado', () {
      expect(estadoDeBodega(inicio: 1000, fin: 1020, compraste: 1000), EstadoBodega.igual);
      expect(estadoDeBodega(inicio: 1000, fin: 970, compraste: 1000), EstadoBodega.igual);
      expect(estadoDeBodega(inicio: 1000, fin: 1031, compraste: 1000), EstadoBodega.crecio);
      expect(estadoDeBodega(inicio: 1000, fin: 969, compraste: 1000), EstadoBodega.bajo);
    });

    test('sin compras, cualquier cambio cuenta', () {
      expect(estadoDeBodega(inicio: 100, fin: 100, compraste: 0), EstadoBodega.igual);
      expect(estadoDeBodega(inicio: 100, fin: 101, compraste: 0), EstadoBodega.crecio);
    });

    test('la cuenta: lo que no explican las compras ni lo usado queda aparte', () {
      // Tenías 1,000 + compraste 5,000 − usaste 4,000 = 2,000; hay 1,700: 300 que no se explican.
      const e = EcuacionBodega(tenias: 1000, compraste: 5000, usaste: 4000, teQueda: 1700);
      expect(e.otros, 300);
      expect(e.hayOtros, isTrue);
      expect(e.estado, EstadoBodega.crecio);
    });

    test('si cuadra, no hay "otros"; menos de Q1 es ruido', () {
      const cuadra = EcuacionBodega(tenias: 1000, compraste: 5000, usaste: 4000, teQueda: 2000);
      expect(cuadra.hayOtros, isFalse);
      const ruido = EcuacionBodega(tenias: 1000, compraste: 5000, usaste: 4000, teQueda: 1999.6);
      expect(ruido.hayOtros, isFalse);
    });

    test('si entró más de lo comprado, "otros" es negativo', () {
      const e = EcuacionBodega(tenias: 1000, compraste: 500, usaste: 800, teQueda: 900);
      expect(e.otros, -200);
    });
  });

  group('BodegaVista: qué se puede decir', () {
    BodegaPeriodo bodega({double? ini, double? fin, bool hoy = false, bool aprox = false}) =>
        BodegaPeriodo(inicio: ini, fin: fin, finEsHoy: hoy, aproximada: aprox);
    BodegaVista vista(DateRange r, BodegaPeriodo b, {bool leyendo = false, double compras = 500, double usaste = 400, bool fallaron = false, double fuera = 0}) =>
        BodegaVista.armar(rango: r, bodega: b, leyendo: leyendo, compraste: compras, usaste: usaste, fotosFallaron: fallaron, comprasFuera: fuera);

    test('con las dos fotos, la cuenta completa con lo comprado y lo usado que se le pasa', () {
      final v = vista(mes(2026, 10), bodega(ini: 2000, fin: 3000), compras: 1500, usaste: 400);
      expect(v.estado, DatoBodega.completo);
      expect(v.ecuacion!.tenias, 2000);
      expect(v.ecuacion!.compraste, 1500);
      expect(v.ecuacion!.usaste, 400);
      expect(v.ecuacion!.teQueda, 3000);
      expect(v.fin, 3000);
    });

    test('solo el fin (hoy o cierre): se sabe cuánto queda, no cuánto había', () {
      final v = vista(mes(2026, 11), bodega(fin: 900, hoy: true));
      expect(v.estado, DatoBodega.soloFin);
      expect(v.fin, 900);
      expect(v.finEsHoy, isTrue);
      expect(v.ecuacion, isNull);
      expect(v.fallo, isFalse);
    });

    test('sin fin no se sabe nada, aunque haya foto del inicio', () {
      expect(vista(mes(2026, 10), bodega(ini: 2000)).estado, DatoBodega.sinFotos);
    });

    test('si la lectura de las fotos falló, no es lo mismo que "todavía no hay foto"', () {
      final v = vista(mes(2026, 10), BodegaPeriodo.vacia, fallaron: true);
      expect(v.estado, DatoBodega.noSePudo);
      expect(v.fallo, isTrue);
    });

    test('mes abierto con la bodega de hoy pero sin la foto del inicio porque falló: lo dice', () {
      final v = vista(mes(2026, 11), bodega(fin: 900, hoy: true), fallaron: true);
      expect(v.estado, DatoBodega.soloFin);
      expect(v.fallo, isTrue);
    });

    test('fuera de un mes, no aplica', () {
      final dia = DateRange(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 5, 23, 59), mode: PeriodMode.day);
      expect(vista(dia, bodega(ini: 1, fin: 2)).estado, DatoBodega.noAplica);
      final anio = DateRange(start: DateTime(2026), end: DateTime(2026, 12, 31), mode: PeriodMode.year);
      expect(vista(anio, bodega(ini: 1, fin: 2)).estado, DatoBodega.noAplica);
    });

    test('mientras se lee, "cargando"; leer manda sobre un fallo anterior', () {
      expect(vista(mes(2026, 10), BodegaPeriodo.vacia, leyendo: true).estado, DatoBodega.cargando);
      expect(vista(mes(2026, 10), BodegaPeriodo.vacia, leyendo: true, fallaron: true).estado, DatoBodega.cargando);
    });

    test('lleva a la tarjeta lo de las fotos aproximadas y lo comprado fuera de la cuenta', () {
      final v = vista(mes(2026, 10), bodega(ini: 100, fin: 200, aprox: true), fuera: 350);
      expect(v.aproximada, isTrue);
      expect(v.comprasFuera, 350);
    });
  });

  group('ventasPorDia', () {
    Map<String, dynamic> pedido(String loc, String fecha, double pago, {double propina = 0, double envio = 0}) =>
        {'location_id': loc, 'paid_at': fecha, 'payment_amount': pago, 'tip_amount': propina, 'delivery_fee': envio};

    test('la venta neta (sin propina ni envío) de cada día', () {
      final r = ventasPorDia([
        pedido('A', '2026-10-14T10:00:00', 100, propina: 10),
        pedido('A', '2026-10-14T20:00:00', 50, envio: 5),
        pedido('A', '2026-10-15T12:00:00', 30),
      ]);
      expect(r['2026-10-14'], 90 + 45);
      expect(r['2026-10-15'], 30);
    });

    test('una sucursal, o todas', () {
      final p = [pedido('A', '2026-10-14T10:00:00', 100), pedido('B', '2026-10-14T10:00:00', 40)];
      expect(ventasPorDia(p, sucursal: 'B')['2026-10-14'], 40);
      expect(ventasPorDia(p)['2026-10-14'], 140);
    });

    test('sin fecha de cobro o con un monto roto no entra ni lanza', () {
      final r = ventasPorDia([
        {'location_id': 'A', 'payment_amount': 100},
        {'location_id': 'A', 'paid_at': 'ayer', 'payment_amount': 100},
        {'location_id': 'A', 'paid_at': '2026-10-14T10:00:00', 'payment_amount': double.nan},
        pedido('A', '2026-10-14T10:00:00', 7),
      ]);
      expect(r['2026-10-14'], 7);
    });

    test('la llave de un día', () {
      expect(llaveDeDia(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });
  });

  group('semanasDelMes', () {
    test('octubre de 2026 empieza en jueves: 1–4, 5–11, 12–18, 19–25 y 26–31', () {
      final s = semanasDelMes(rango: mes(2026, 10), ventas: const {}, porDia: const {});
      expect(s.map((x) => (x.desde.day, x.hasta.day)), [(1, 4), (5, 11), (12, 18), (19, 25), (26, 31)]);
      expect(s.map((x) => x.nombre), ['Semana 1', 'Semana 2', 'Semana 3', 'Semana 4', 'Semana 5']);
    });

    test('un mes que empieza en lunes tiene semanas completas', () {
      // Junio de 2026 empieza en lunes.
      final s = semanasDelMes(rango: mes(2026, 6), ventas: const {}, porDia: const {});
      expect(s.first.desde.day, 1);
      expect(s.first.hasta.day, 7);
      expect(s.last.hasta.day, 30);
    });

    test('lo vendido, comprado y usado de cada semana, y que todo suma', () {
      final ventas = {'2026-10-01': 100.0, '2026-10-04': 50.0, '2026-10-05': 200.0, '2026-10-31': 10.0};
      final dias = {
        '2026-10-02': const ParCosto(30, 500),
        '2026-10-07': const ParCosto(60, 0),
        '2026-10-30': const ParCosto(5, 20),
      };
      final s = semanasDelMes(rango: mes(2026, 10), ventas: ventas, porDia: dias);
      expect(s[0].vendiste, 150);
      expect(s[0].compraste, 500);
      expect(s[0].usaste, 30);
      expect(s[0].ganaste, 120);
      expect(s[1].vendiste, 200);
      expect(s[1].usaste, 60);
      expect(s[4].vendiste, 10);
      expect(s[4].compraste, 20);
      expect(s.fold<double>(0, (a, x) => a + x.vendiste), 360);
      expect(s.fold<double>(0, (a, x) => a + x.usaste), 95);
    });

    test('solo con un mes elegido', () {
      final semana = DateRange(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 11), mode: PeriodMode.week);
      expect(semanasDelMes(rango: semana, ventas: const {}, porDia: const {}), isEmpty);
    });

    test('el rótulo del rango', () {
      final s = semanasDelMes(rango: mes(2026, 10), ventas: const {}, porDia: const {});
      expect(s[0].rango, contains('1 – 4'));
      expect(s[1].rango, contains('5 – 11'));
    });
  });

  group('CategoriasCV', () {
    final porIng = {
      'i1': const ParCosto(100, 200), // cerveza
      'i2': const ParCosto(50, 80), // "cerveza" en otra sucursal
      'i3': const ParCosto(30, 40), // carnes
      'i4': const ParCosto(10, 0), // sin categoría conocida
    };
    final categoriaDe = {'i1': 'Cerveza', 'i2': 'cerveza', 'i3': 'Carnes'};

    CategoriasCV armar({Map<String, double> reventa = const {'i1': 500}, Map<String, CategoriaValor>? bodega, double ventas = 1000}) => CategoriasCV.armar(
          porIngrediente: porIng,
          categoriaDe: categoriaDe,
          reventaPorIngrediente: reventa,
          bodegaPorCategoria: bodega,
          ventasTotales: ventas,
        );

    test('lo que se revende se ve directo: compras, uso, ventas y ganancia', () {
      final c = armar();
      final cerveza = c.reventa.single;
      expect(cerveza.nombre, 'Cerveza');
      expect(cerveza.compraste, 280);
      expect(cerveza.usaste, 150);
      expect(cerveza.vendiste, 500);
      expect(cerveza.ganaste, 350);
      expect(cerveza.porCadaQ, closeTo(500 / 150, 1e-9));
      expect(cerveza.esReventa, isTrue);
    });

    test('lo demás va junto en "Platillos": lo que no se vendió directo', () {
      final c = armar();
      expect(c.insumos.map((f) => f.nombre), ['Carnes', 'Sin categoría']);
      final p = c.platillos!;
      expect(p.nombre, 'Platillos');
      expect(p.compraste, 40);
      expect(p.usaste, 40);
      expect(p.vendiste, 500); // 1,000 − 500 de reventa
      expect(p.ganaste, 460);
    });

    test('sin reventa, todo es de platillos', () {
      final c = armar(reventa: const {});
      expect(c.reventa, isEmpty);
      expect(c.platillos!.vendiste, 1000);
      expect(c.insumos.length, 3);
    });

    test('si la reventa pasa lo vendido, platillos no sale negativo', () {
      final c = armar(reventa: const {'i1': 5000});
      expect(c.platillos!.vendiste, 0);
    });

    test('lo que queda en bodega, por categoría; sin dato, null', () {
      final sin = armar();
      expect(sin.reventa.single.teQueda, isNull);
      final con = armar(bodega: {
        'cerveza': const CategoriaValor('Cerveza', 70),
        'carnes': const CategoriaValor('Carnes', 25),
        'verduras': const CategoriaValor('Verduras', 9),
      });
      expect(con.reventa.single.teQueda, 70);
      expect(con.insumos.firstWhere((f) => f.nombre == 'Carnes').teQueda, 25);
      // Una categoría con algo en bodega aunque no se movió en el período.
      expect(con.insumos.firstWhere((f) => f.nombre == 'Verduras').teQueda, 9);
      expect(con.insumos.firstWhere((f) => f.nombre == 'Verduras').compraste, 0);
      expect(con.platillos!.teQueda, 25 + 0 + 9);
    });

    test('las reventas, de más a menos vendidas; los insumos, de más a menos comprados', () {
      final c = CategoriasCV.armar(
        porIngrediente: {'a': const ParCosto(1, 10), 'b': const ParCosto(1, 20), 'c': const ParCosto(1, 5), 'd': const ParCosto(1, 50)},
        categoriaDe: {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'},
        reventaPorIngrediente: {'a': 100, 'b': 300},
        bodegaPorCategoria: null,
        ventasTotales: 1000,
      );
      expect(c.reventa.map((f) => f.nombre), ['B', 'A']);
      expect(c.insumos.map((f) => f.nombre), ['D', 'C']);
    });

    test('sin nada, no hay qué mostrar', () {
      final c = CategoriasCV.armar(porIngrediente: const {}, categoriaDe: const {}, reventaPorIngrediente: const {}, bodegaPorCategoria: null, ventasTotales: 0);
      expect(c.hayAlgo, isFalse);
      expect(c.platillos, isNull);
    });

    test('una venta de reventa en cero o rota no crea una categoría', () {
      final c = armar(reventa: {'i1': 0, 'i3': double.nan, 'i2': -5});
      expect(c.reventa, isEmpty);
    });
  });

  group('FilaSucursalCV', () {
    final sucs = [('A', 'Chiquimula'), ('B', 'La Reforma')];
    final porSucursal = {'A': datos(ventas: 1000, cogs: 300, compras: 800), 'B': datos(ventas: 500, cogs: 200, compras: 100)};

    test('compró, vendió y ganó salen de Rentabilidad', () {
      final f = FilaSucursalCV.armar(porSucursal: porSucursal, sucursales: sucs, bodega: BodegaPeriodo.vacia);
      expect(f.map((x) => x.nombre), ['Chiquimula', 'La Reforma']);
      expect(f[0].compro, 800);
      expect(f[0].vendio, 1000);
      expect(f[0].gano, 700);
      expect(f[1].gano, 300);
    });

    test('sin fotos no se sabe qué le queda ni qué pasó con su bodega', () {
      final f = FilaSucursalCV.armar(porSucursal: porSucursal, sucursales: sucs, bodega: BodegaPeriodo.vacia);
      expect(f[0].leQueda, isNull);
      expect(f[0].estado, isNull);
      expect(f[0].cambio, isNull);
    });

    test('con las dos fotos: lo que queda, cuánto cambió y si creció', () {
      final b = BodegaPeriodo(
        inicio: 0,
        fin: 0,
        inicioPorSucursal: const {'A': 1000, 'B': 500},
        finPorSucursal: const {'A': 1800, 'B': 400},
      );
      final f = FilaSucursalCV.armar(porSucursal: porSucursal, sucursales: sucs, bodega: b);
      expect(f[0].leQueda, 1800);
      expect(f[0].cambio, 800);
      expect(f[0].estado, EstadoBodega.crecio); // 800 > 3% de 800
      expect(f[1].cambio, -100);
      expect(f[1].estado, EstadoBodega.bajo); // −100 pasa el 3% de 100
    });

    test('solo con el fin: se sabe qué le queda, no qué pasó', () {
      final b = BodegaPeriodo(fin: 0, finPorSucursal: const {'A': 700});
      final f = FilaSucursalCV.armar(porSucursal: porSucursal, sucursales: sucs, bodega: b);
      expect(f[0].leQueda, 700);
      expect(f[0].estado, isNull);
    });

    test('una sucursal sin números no sale', () {
      final f = FilaSucursalCV.armar(porSucursal: {'A': porSucursal['A']!}, sucursales: sucs, bodega: BodegaPeriodo.vacia);
      expect(f.map((x) => x.id), ['A']);
    });
  });

  group('claveDeCategoria', () {
    test('sin mayúsculas, tildes ni espacios de más', () {
      expect(claveDeCategoria('  Gaseosas y Agua '), 'gaseosas y agua');
      expect(claveDeCategoria('Verdúras'), 'verduras');
      expect(claveDeCategoria('PIÑA'), 'pina');
    });
  });

  group('las fotos tomadas tarde', () {
    test('la automática (minutos después de la medianoche) no es aproximada', () {
      final f = FotoBodega('2026-11-01', const {}, tomadaEn: DateTime(2026, 11, 1, 0, 3));
      expect(f.esAproximada, isFalse);
    });

    test('tomada con el script semanas después, sí', () {
      final f = FotoBodega('2026-11-01', const {}, tomadaEn: DateTime(2026, 11, 22, 10));
      expect(f.esAproximada, isTrue);
    });

    test('sin saber cuándo se tomó, no se marca (la de hoy en vivo no trae hora)', () {
      expect(const FotoBodega('2026-11-22', {}).esAproximada, isFalse);
    });

    test('se lee `tomada_en` del documento (texto) y la aproximada llega a BodegaPeriodo', () {
      final tarde = FotoBodega.desde({
        'fecha': '2026-10-01',
        'tomada_en': '2026-11-22T10:00:00',
        'sucursales': {'A': {'total': 100}},
      })!;
      expect(tarde.esAproximada, isTrue);
      final buena = FotoBodega.desde({
        'fecha': '2026-11-01',
        'tomada_en': '2026-11-01T00:02:00',
        'sucursales': {'A': {'total': 120}},
      })!;
      expect(buena.esAproximada, isFalse);
      final b = BodegaPeriodo.armar(inicio: tarde, fin: buena, finEsHoy: false, sucursales: {'A'}, factor: (_, __) => 1);
      expect(b.aproximada, isTrue);
      final c = BodegaPeriodo.armar(inicio: buena, fin: buena, finEsHoy: false, sucursales: {'A'}, factor: (_, __) => 1);
      expect(c.aproximada, isFalse);
    });

    test('un `tomada_en` roto no tumba la lectura', () {
      final f = FotoBodega.desde({'fecha': '2026-10-01', 'tomada_en': 12345, 'sucursales': <String, dynamic>{}})!;
      expect(f.tomadaEn, isNull);
      expect(f.esAproximada, isFalse);
    });
  });

  group('si ninguna sucursal aporta, no se sabe (no es cero)', () {
    final foto = FotoBodega('2026-10-01', {'A': const SucursalFoto(total: 100)});

    test('ninguna sucursal a la vista', () {
      final b = BodegaPeriodo.armar(inicio: foto, fin: foto, finEsHoy: false, sucursales: <String>{}, factor: (_, __) => 1);
      expect(b.inicio, isNull);
      expect(b.fin, isNull);
      expect(b.completa, isFalse);
    });

    test('la sucursal elegida no está en la foto', () {
      final b = BodegaPeriodo.armar(inicio: foto, fin: foto, finEsHoy: false, sucursales: {'OTRA'}, factor: (_, __) => 1);
      expect(b.inicio, isNull);
    });

    test('la sucursal solo es la bodega central', () {
      final c = FotoBodega('2026-10-01', {'CEN': const SucursalFoto(total: 500, central: true)});
      final b = BodegaPeriodo.armar(inicio: c, fin: c, finEsHoy: false, sucursales: {'CEN'}, factor: (_, __) => 1);
      expect(b.inicio, isNull);
    });

    test('una moneda sin tipo de cambio en la única sucursal', () {
      final b = BodegaPeriodo.armar(inicio: foto, fin: foto, finEsHoy: false, sucursales: {'A'}, factor: (_, __) => null);
      expect(b.inicio, isNull);
    });
  });

  group('claveDeCategoria cubre más letras, y las marcas sueltas', () {
    test('las más comunes del latín', () {
      expect(claveDeCategoria('Açúcar'), 'acucar');
      expect(claveDeCategoria('Pão'), 'pao');
      expect(claveDeCategoria('Šampú'), 'sampu');
      expect(claveDeCategoria('Ýerba'), 'yerba');
    });

    test('una tilde escrita en dos piezas es la misma letra', () {
      expect(claveDeCategoria('Cafe\u0301'), claveDeCategoria('Café'));
      expect(claveDeCategoria('Cafe\u0301'), 'cafe');
    });
  });

  group('"Platillos" siempre absorbe lo que no es reventa', () {
    test('sin insumos que no sean reventa, igual sale lo vendido sin costo', () {
      final c = CategoriasCV.armar(
        porIngrediente: {'a': const ParCosto(100, 150)},
        categoriaDe: {'a': 'Cerveza'},
        reventaPorIngrediente: {'a': 600},
        bodegaPorCategoria: null,
        ventasTotales: 1000,
      );
      expect(c.insumos, isEmpty);
      expect(c.platillos, isNotNull);
      expect(c.platillos!.vendiste, 400);
      expect(c.platillos!.compraste, 0);
      expect(c.platillos!.usaste, 0);
      // Las filas suman el total.
      final suma = c.reventa.fold<double>(0, (a, f) => a + f.vendiste!) + c.platillos!.vendiste!;
      expect(suma, 1000);
    });

    test('si no queda nada que no sea reventa, no hay fila de platillos', () {
      final c = CategoriasCV.armar(
        porIngrediente: {'a': const ParCosto(100, 150)},
        categoriaDe: {'a': 'Cerveza'},
        reventaPorIngrediente: {'a': 1000},
        bodegaPorCategoria: null,
        ventasTotales: 1000,
      );
      expect(c.platillos, isNull);
    });

    test('las filas suman el total con insumos y reventa', () {
      final c = CategoriasCV.armar(
        porIngrediente: {'a': const ParCosto(100, 150), 'b': const ParCosto(30, 40)},
        categoriaDe: {'a': 'Cerveza', 'b': 'Carnes'},
        reventaPorIngrediente: {'a': 600},
        bodegaPorCategoria: null,
        ventasTotales: 1000,
      );
      final v = c.reventa.fold<double>(0, (a, f) => a + f.vendiste!) + c.platillos!.vendiste!;
      final u = c.reventa.fold<double>(0, (a, f) => a + f.usaste) + c.platillos!.usaste;
      expect(v, 1000);
      expect(u, 130);
    });
  });
}
