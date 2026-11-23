import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/gastos_data.dart';
import 'package:saborpro_reports/presentation/widgets/gastos_view.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';

/// Gastos sin Firebase: la pantalla real le pasa el período ya armado. Los datos son
/// los del diseño (gastos.html): 8 compras en 3 sucursales, Q4,376.88 en total,
/// 9% más que el mes anterior (Q4,010) y Q31 de cada Q100 vendidos. Cualquier
/// "RenderFlex overflowed" hace fallar la prueba por sí sola.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  /// [lineas]: (nombre, cantidad, unidad, costo).
  Map<String, dynamic> compra(int n, String? prov, String fecha, String suc, double total, List<(String, double, String, double)> lineas) => {
        'order_number': n,
        if (prov != null) 'supplier_name': prov,
        'received_at': fecha,
        'location_id': suc,
        'total': total,
        'items': [
          for (final l in lineas)
            {'ingredient_name': l.$1, 'received_quantity': l.$2, 'unit_abbreviation': l.$3, 'total_pagado': l.$4, 'unit_price': l.$4 / l.$2},
        ],
      };

  const ceiba = 'Distribuidora La Ceiba S.A.';
  const mariposa = 'Compañía de Jarabes y Bebidas Gaseosas La Mariposa S.A.';
  const atlantida = 'Alimentos y Bebidas Atlantida S.A.';

  List<Map<String, dynamic>> comprasDelDiseno() => [
        compra(35741, null, '2026-10-31T09:00:00', 'sr', 54.96, [('Limones', 25, 'u', 24.96), ('Hielo', 2, 'bolsa', 30)]),
        compra(19074, ceiba, '2026-10-31T10:00:00', 'ch', 1118.70, [
          ('Gallo Normal Lata 350 ml', 72, 'u', 540),
          ('Gallo light Lata 350 ml', 48, 'u', 360),
          ('Monte Carlo Bajo Cero', 24, 'u', 158.7),
          ('Hielo', 4, 'bolsa', 60),
        ]),
        compra(5404, null, '2026-10-25T10:00:00', 'lr', 619.94, [('Carne de res', 12, 'lb', 619.94)]),
        compra(15128, mariposa, '2026-10-25T11:00:00', 'sr', 483.76, [
          ('Pepsi 600 ml', 24, 'u', 156),
          ('7Up 600 ml', 12, 'u', 78),
          ('Agua Pura Salvavidas 600 ml', 24, 'u', 96),
          ('Adrenalina 296 ml', 12, 'u', 114),
          ('Gatorade 600 ml', 4, 'u', 39.76),
        ]),
        compra(24985, atlantida, '2026-10-20T10:00:00', 'ch', 219.50, [
          ('Coca Cola Lata 355 ml', 24, 'u', 108),
          ('Fanta Uva Desechable 600 ml', 12, 'u', 54),
          ('Dassani 1 Litro', 6, 'u', 33),
          ('Sprite Lata 355 ml', 6, 'u', 24.5),
        ]),
        compra(10796, null, '2026-10-20T11:00:00', 'lr', 75.38, [('Cebolla', 5, 'lb', 25), ('Tomate', 6, 'lb', 30.38), ('Cilantro', 4, 'manojo', 20)]),
        compra(36128, ceiba, '2026-10-13T10:00:00', 'sr', 1364.40, [
          ('Gallo Normal Vidrio 350 ml', 72, 'u', 612),
          ('Gallo Ligth Vidrio 350 ml', 60, 'u', 510),
          ('Monte Carlo Bajo Cero', 24, 'u', 158.4),
          ('Hielo', 6, 'bolsa', 84),
        ]),
        compra(79990, atlantida, '2026-10-09T10:00:00', 'lr', 440.24, [
          ('Coca Cola Vidrio 355 ml', 48, 'u', 168),
          ('Coca Cola Lata 355 ml', 24, 'u', 108),
          ('Fanta Naranja 600 ml', 12, 'u', 54),
          ('Dassani 1 Litro', 6, 'u', 33),
          ('Sprite Lata 355 ml', 6, 'u', 24.5),
          ('Coca Cola Zero 600 ml', 6, 'u', 27),
          ('Fresca Lata 355 ml', 3, 'u', 12.24),
          ('Powerade 600 ml', 1, 'u', 7.5),
          ('Del Valle 1 L', 1, 'u', 6),
        ]),
      ];

  List<Map<String, dynamic>> gastosDeEjemplo() => [
        {'amount': 150.0, 'description': 'Gas para cocina', 'category_name': 'Servicios', 'date': '2026-10-22T10:00:00', 'location_id': 'ch', 'registered_by': 'Ana'},
        {'amount': 45.0, 'description': 'Hielo', 'category_name': 'Insumos', 'date': '2026-10-21T10:00:00', 'location_id': 'lr', 'source': 'cashRegister', 'register_id': 'cr1', 'register_user': 'Juan'},
      ];

  final periodo = GastosPeriodo.desde(comprasDelDiseno(), const []);
  // El mes anterior: Q1,210 + Q1,180 + Q1,620 = Q4,010.
  final anterior = GastosPeriodo.desde([
    compra(1, 'X', '2026-09-10T10:00:00', 'ch', 1210, const []),
    compra(2, 'X', '2026-09-11T10:00:00', 'lr', 1180, const []),
    compra(3, 'X', '2026-09-12T10:00:00', 'sr', 1620, const []),
  ], const []);
  final sucursales = GastoSucursal.de(const [('ch', 'Chiquimula'), ('lr', 'La Reforma'), ('sr', 'Santa Rosalia')]);
  const ventasPorSucursal = {'ch': 4600.0, 'lr': 4050.0, 'sr': 5600.0};

  Widget cuerpo({
    GastosPeriodo? p,
    GastosPeriodo? ant,
    bool sinAnterior = false,
    double? ventas = 14250,
    Map<String, double>? porSucursal = ventasPorSucursal,
    List<GastoSucursal>? suc,
  }) =>
      GastosBody(
        periodo: p ?? periodo,
        anterior: sinAnterior ? null : (ant ?? anterior),
        vsEtiqueta: 'septiembre 2026',
        ventas: ventas,
        ventasPorSucursal: porSucursal,
        sucursales: suc ?? sucursales,
        signo: 'Q',
      );

  Future<void> montar(WidgetTester tester, Widget c, {Size size = const Size(1280, 3600), double escala = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(backgroundColor: kInicioBg, body: c),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> buscar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(const Key('gastos-buscar')), texto);
    await tester.pumpAndSettle();
  }

  const tamanos = [Size(360, 3600), Size(390, 3600), Size(700, 3600), Size(1280, 3600)];

  group('el total', () {
    testWidgets('lo gastado, el cambio contra el período anterior y cuántas compras', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Total gastos del período'), findsOneWidget);
      expect(find.text('Q4,376.88'), findsWidgets);
      expect(find.text('9%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsWidgets);
      expect(find.text('vs septiembre 2026 (Q4,010.00) · 8 compras'), findsOneWidget);
    });

    testWidgets('si bajó, la flecha va para abajo y en verde', (tester) async {
      final mayor = GastosPeriodo.desde([compra(1, 'X', '2026-09-10T10:00:00', 'ch', 8000, const [])], const []);
      await montar(tester, cuerpo(ant: mayor));
      expect(find.text('45%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
    });

    testWidgets('con gastos y retiros también dice cuántos, y los suma al total', (tester) async {
      final p = GastosPeriodo.desde(comprasDelDiseno(), gastosDeEjemplo());
      await montar(tester, cuerpo(p: p));
      // 4,376.88 + 150 + 45.
      expect(find.text('Q4,571.88'), findsWidgets);
      expect(find.textContaining('8 compras · 2 gastos'), findsOneWidget);
    });

    testWidgets('sin el período anterior no hay comparación (no se inventa un 0%)', (tester) async {
      await montar(tester, cuerpo(sinAnterior: true));
      expect(find.textContaining('vs septiembre'), findsNothing);
      expect(find.text('8 compras'), findsOneWidget);
    });

    testWidgets('con varias sucursales, el reparto de cada una y cuánto cambió', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Chiquimula'), findsWidgets);
      expect(find.text('Q1,338.20'), findsOneWidget);
      expect(find.text('Q1,135.56'), findsOneWidget);
      expect(find.text('Q1,903.12'), findsOneWidget);
      // Chiquimula +11% (1,338.20 contra 1,210), La Reforma −4%, Santa Rosalia +17%.
      // (el 11% y el 17% también salen en la parte de otros bloques: Mariposa y sin proveedor).
      expect(find.text('11%'), findsNWidgets(2));
      expect(find.text('4%'), findsOneWidget);
      expect(find.text('17%'), findsNWidgets(2));
    });

    testWidgets('contra un período casi vacío el % se acota en lugar de salir enorme', (tester) async {
      final minimo = GastosPeriodo.desde([compra(1, 'X', '2026-09-10T10:00:00', 'ch', 0.5, const [])], const []);
      await montar(tester, cuerpo(ant: minimo));
      expect(find.text('>999%'), findsWidgets);
    });

    testWidgets('con una sola sucursal a la vista no hay reparto', (tester) async {
      await montar(tester, cuerpo(suc: [sucursales.first]));
      expect(find.text('Q1,903.12'), findsNothing);
    });
  });

  group('gastos contra ventas', () {
    testWidgets('de cada Q100 vendidos, cuántos se fueron; y cuánto queda', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Gastos vs. ventas'), findsOneWidget);
      expect(find.textContaining('De cada Q100 que vendiste, Q31 se fueron en gastos', findRichText: true), findsOneWidget);
      expect(find.text('Vendiste'), findsOneWidget);
      expect(find.text('Q14,250.00'), findsOneWidget);
      expect(find.text('Gastaste'), findsOneWidget);
      expect(find.text('Después de gastos'), findsOneWidget);
      expect(find.text('Q9,873.12'), findsOneWidget);
    });

    testWidgets('por sucursal: qué parte de sus ventas se fue en gastos', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('29%'), findsOneWidget);
      expect(find.text('28%'), findsOneWidget);
      expect(find.text('34%'), findsOneWidget);
    });

    testWidgets('si se gastó más de lo vendido, lo que queda va en rojo', (tester) async {
      await montar(tester, cuerpo(ventas: 1000, porSucursal: null));
      expect(find.text('−Q3,376.88'), findsNothing, reason: 'el formato de siempre de esta pantalla no lleva el menos tipográfico');
      expect(tester.widget<Text>(find.text('Q-3,376.88')).style!.color, InicioColores.bad);
    });

    testWidgets('sin ventas no se dice "de cada Q100"', (tester) async {
      await montar(tester, cuerpo(ventas: 0));
      expect(find.textContaining('De cada', findRichText: true), findsNothing);
      expect(find.text('No hubo ventas en este período para comparar.'), findsOneWidget);
      await montar(tester, cuerpo(ventas: null));
      expect(find.text('No hubo ventas en este período para comparar.'), findsOneWidget);
    });
  });

  group('compras sin proveedor', () {
    testWidgets('cuánto y qué parte del gasto, y no se pueden comparar precios', (tester) async {
      await montar(tester, cuerpo());
      expect(
        find.textContaining('Q750.28 (17%) en 3 compras sin proveedor. Sin proveedor no se pueden comparar precios.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('tocar "Ver" busca "Sin proveedor" en el listado', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('gastos-buscar'))).controller!.text, 'Sin proveedor');
      expect(find.text('#35741', findRichText: true), findsNothing);
      expect(find.textContaining('#5404', findRichText: true), findsOneWidget);
      expect(find.textContaining('#19074', findRichText: true), findsNothing);
    });

    testWidgets('si todas tienen proveedor no sale el aviso', (tester) async {
      final p = GastosPeriodo.desde([compra(1, 'A', '2026-10-01T10:00:00', 'ch', 100, const [])], const []);
      await montar(tester, cuerpo(p: p));
      expect(find.textContaining('sin proveedor'), findsNothing);
    });
  });

  group('a quién se le compra y en qué se va el dinero', () {
    testWidgets('los proveedores de mayor a menor, con "Sin proveedor"', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('¿A quién le compras más?'), findsOneWidget);
      expect(find.text('Q2,483.10'), findsOneWidget);
      expect(find.text('57%'), findsOneWidget);
      expect(find.text('Q659.74'), findsOneWidget);
      // Sin proveedor: 750.28 y 17%.
      expect(find.text('Q750.28'), findsWidgets);
      final y = [for (final n in [ceiba, 'Sin proveedor', atlantida, mariposa]) tester.getTopLeft(find.text(n).first).dy];
      expect(y[0] < y[1] && y[1] < y[2] && y[2] < y[3], isTrue, reason: '$y');
    });

    testWidgets('los cinco insumos que más gastan, numerados, con su parte', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('¿En qué se va el dinero?'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('$i'), findsWidgets);
      }
      expect(find.text('Carne de res'), findsWidgets);
      expect(find.text('Q619.94'), findsWidgets);
      expect(find.text('Gallo Normal Vidrio 350 ml'), findsWidgets);
      expect(find.text('14%'), findsNWidgets(2));
    });

    testWidgets('sin compras lo dice', (tester) async {
      final p = GastosPeriodo.desde(const [], gastosDeEjemplo());
      await montar(tester, cuerpo(p: p));
      expect(find.text('Sin compras'), findsNWidgets(2));
    });
  });

  group('precios', () {
    // El hielo de La Ceiba costaba Q14 la bolsa el 13 de octubre; el 31 costó Q15.
    testWidgets('lo que subió contra la compra anterior, con su precio de antes y de ahora', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Subieron de precio'), findsOneWidget);
      expect(find.text('vs compra anterior'), findsOneWidget);
      expect(find.text('Hielo'), findsWidgets);
      expect(find.text('$ceiba · por bolsa'), findsOneWidget);
      expect(find.text('Q14.00'), findsOneWidget);
      expect(find.text('Q15.00'), findsWidgets);
      expect(find.text('7%'), findsOneWidget);
    });

    testWidgets('con el período anterior pero sin subidas, lo dice; sin el período anterior, dice por qué no compara', (tester) async {
      final plano = GastosPeriodo.desde([compra(1, 'A', '2026-10-01T10:00:00', 'ch', 100, [('Sal', 5, 'u', 10)])], const []);
      await montar(tester, cuerpo(p: plano));
      expect(find.text('Ningún insumo subió de precio.'), findsOneWidget);
      await montar(tester, cuerpo(p: plano, sinAnterior: true));
      expect(find.text('No se pudo leer el período anterior para comparar precios.'), findsOneWidget);
    });

    testWidgets('el mismo insumo con dos proveedores: con quién sale más barato y cuánto se ahorra', (tester) async {
      final p = GastosPeriodo.desde([
        compra(1, 'Atlantida S.A.', '2026-10-10T10:00:00', 'ch', 86.4, [('Agua Pura 600 ml', 24, 'u', 86.4)]),
        compra(2, 'La Mariposa S.A.', '2026-10-11T10:00:00', 'ch', 96, [('Agua Pura 600 ml', 24, 'u', 96)]),
      ], const []);
      await montar(tester, cuerpo(p: p));
      expect(find.text('Mismo insumo, distinto precio'), findsOneWidget);
      expect(find.text('Agua Pura 600 ml'), findsWidgets);
      expect(find.text('Q3.60'), findsOneWidget);
      expect(find.text('Q4.00'), findsOneWidget);
      expect(find.text('Ahorras Q9.60 por cada 24 u comprando con Atlantida S.A.'), findsOneWidget);
    });

    testWidgets('sin nada que comparar lo dice', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Nada que comparar en este período.'), findsOneWidget);
    });
  });

  group('la búsqueda y el listado', () {
    testWidgets('las compras con su proveedor, número, insumos y fecha; en "Todas" también la sucursal', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Compras / insumos'), findsOneWidget);
      expect(find.text('Q4,376.88'), findsWidgets);
      expect(find.textContaining('#19074 · 4 insumos · Chiquimula', findRichText: true), findsOneWidget);
      expect(find.text('Q1,118.70'), findsOneWidget);
      expect(find.text('31 oct'), findsNWidgets(2));
    });

    testWidgets('con una sola sucursal a la vista no repite su nombre en cada compra', (tester) async {
      await montar(tester, cuerpo(suc: [sucursales.first]));
      expect(find.textContaining('· Chiquimula', findRichText: true), findsNothing);
    });

    testWidgets('tocar una compra la abre: sus insumos con cantidad y costo; volver a tocar la cierra', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('INSUMO'), findsNothing);
      await tester.tap(find.textContaining('#5404', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('INSUMO'), findsOneWidget);
      expect(find.text('CANTIDAD'), findsOneWidget);
      expect(find.text('COSTO'), findsOneWidget);
      expect(find.text('12 lb'), findsOneWidget);
      expect(find.text('Compra recibida en la despensa'), findsOneWidget);
      await tester.tap(find.textContaining('#5404', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('INSUMO'), findsNothing);
    });

    testWidgets('buscar un insumo trae sus compras y dice cuáles insumos coinciden', (tester) async {
      await montar(tester, cuerpo());
      await buscar(tester, 'hielo');
      expect(find.textContaining('#19074', findRichText: true), findsOneWidget);
      expect(find.textContaining('#36128', findRichText: true), findsOneWidget);
      expect(find.textContaining('#35741', findRichText: true), findsOneWidget);
      expect(find.textContaining('#5404', findRichText: true), findsNothing);
      expect(find.text('Incluye: Hielo'), findsNWidgets(3));
    });

    testWidgets('buscar por número, con o sin "#", y por proveedor sin acentos', (tester) async {
      await montar(tester, cuerpo());
      await buscar(tester, '#5404');
      expect(find.textContaining('#5404', findRichText: true), findsWidgets);
      expect(find.textContaining('#19074', findRichText: true), findsNothing);
      await buscar(tester, 'compania de jarabes');
      expect(find.textContaining('#15128', findRichText: true), findsOneWidget);
    });

    testWidgets('sin coincidencias lo dice con lo que se buscó; borrar la búsqueda lo trae todo', (tester) async {
      await montar(tester, cuerpo());
      await buscar(tester, 'zzz');
      expect(find.text('No encontramos “zzz” en este período'), findsOneWidget);
      expect(find.byKey(const Key('gastos-borrar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('gastos-borrar')));
      await tester.pumpAndSettle();
      expect(find.text('No encontramos “zzz” en este período'), findsNothing);
      expect(find.textContaining('#19074', findRichText: true), findsOneWidget);
    });

    testWidgets('los gastos operacionales y los retiros de caja siguen a la vista, cada uno en su grupo', (tester) async {
      final p = GastosPeriodo.desde(comprasDelDiseno(), gastosDeEjemplo());
      await montar(tester, cuerpo(p: p));
      expect(find.text('Gastos operacionales'), findsOneWidget);
      expect(find.text('Gas para cocina'), findsOneWidget);
      expect(find.text('Q150.00'), findsWidgets);
      expect(find.text('Retiros de caja'), findsOneWidget);
      expect(find.text('Hielo'), findsWidgets);
      expect(find.textContaining('Caja de Juan', findRichText: true), findsOneWidget);
      // La búsqueda también los alcanza.
      await buscar(tester, 'gas para');
      expect(find.text('Gas para cocina'), findsOneWidget);
      expect(find.text('Retiros de caja'), findsNothing);
      expect(find.text('Compras / insumos'), findsNothing);
    });

    testWidgets('sin gastos lo dice', (tester) async {
      await montar(tester, cuerpo(p: GastosPeriodo.vacio));
      expect(find.text('No hay gastos en este período'), findsOneWidget);
    });
  });

  group('en pantalla ancha y angosta', () {
    testWidgets('en 1280 el total y gastos-contra-ventas van lado a lado; en 360 uno debajo del otro', (tester) async {
      await montar(tester, cuerpo());
      final total = tester.getTopLeft(find.text('Total gastos del período'));
      final vs = tester.getTopLeft(find.text('Gastos vs. ventas'));
      expect(vs.dx, greaterThan(total.dx + 300), reason: 'lado a lado');
      // (la tarjeta del total centra su contenido en vertical, como el diseño)
      expect((vs.dy - total.dy).abs(), lessThan(70));
      await montar(tester, cuerpo(), size: const Size(360, 3600));
      expect(tester.getTopLeft(find.text('Gastos vs. ventas')).dy, greaterThan(tester.getBottomLeft(find.text('Total gastos del período')).dy));
    });
  });

  group('dentro del cambio de sucursal', () {
    for (final tam in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets('con poco que mostrar el contenido arranca arriba, no al medio ($tam)', (tester) async {
        tester.view.physicalSize = tam;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        const arribaDelArea = 100.0;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: kInicioBg,
            body: Column(
              children: [
                const SizedBox(height: arribaDelArea),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: const ValueKey('todas'),
                      child: RefreshIndicator(onRefresh: () async {}, child: cuerpo(p: GastosPeriodo.vacio)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(SingleChildScrollView)).height, tam.height - arribaDelArea);
        expect(tester.getTopLeft(find.text('No hay gastos en este período')).dy, lessThan(arribaDelArea + 90));
      });
    }
  });

  group('cabe sin desbordar', () {
    for (final s in tamanos) {
      testWidgets('a ${s.width.toInt()} con letra grande y datos normales', (tester) async {
        final p = GastosPeriodo.desde(comprasDelDiseno(), gastosDeEjemplo());
        await montar(tester, cuerpo(p: p), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        final fila = find.textContaining('#5404', findRichText: true);
        await tester.ensureVisible(fila);
        await tester.pumpAndSettle();
        await tester.tap(fila);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande, cifras enormes, nombres larguísimos y muchas sucursales', (tester) async {
        final suc = GastoSucursal.de([for (var i = 0; i < 6; i++) ('s$i', 'Una sucursal con un nombre larguísimo de verdad número $i')]);
        final compras = [
          for (var i = 0; i < 8; i++)
            compra(
              90000 + i,
              i.isEven ? 'Un proveedor con un nombre larguísimo de verdad para ver qué pasa número $i' : null,
              '2026-10-${10 + i}T10:00:00',
              's${i % 6}',
              987654321.55,
              [
                for (var k = 0; k < 3; k++) ('Un insumo con un nombre larguísimo de verdad número $k del proveedor $i', 1234.5, 'bolsa de un tamaño enorme', 98765432.1 + k + i),
              ],
            ),
        ];
        final p = GastosPeriodo.desde(compras, [
          {'amount': 55555555.5, 'description': 'Un gasto con un concepto larguísimo de verdad para ver qué pasa', 'category_name': 'Una categoría larguísima', 'registered_by': 'María de los Ángeles Fernández de la Vega', 'date': '2026-10-12T10:00:00', 'location_id': 's1'},
        ]);
        final ant = GastosPeriodo.desde([compra(1, 'Un proveedor con un nombre larguísimo de verdad para ver qué pasa número 0', '2026-09-10T10:00:00', 's0', 1000, [('Un insumo con un nombre larguísimo de verdad número 0 del proveedor 0', 1234.5, 'bolsa', 5)])], const []);
        await montar(
          tester,
          cuerpo(p: p, ant: ant, suc: suc, ventas: 98765432123.45, porSucursal: {for (var i = 0; i < 6; i++) 's$i': 98765432.1 + i}),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
        final fila = find.textContaining('#90001', findRichText: true).first;
        await tester.ensureVisible(fila);
        await tester.pumpAndSettle();
        await tester.tap(fila);
        await tester.pumpAndSettle();
        // Y el detalle de la compra abierta tampoco desborda.
        expect(find.text('INSUMO'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande, sin gastos o sin ventas ni período anterior', (tester) async {
        await montar(tester, cuerpo(p: GastosPeriodo.vacio), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await montar(tester, cuerpo(sinAnterior: true, ventas: null, porSucursal: null), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
