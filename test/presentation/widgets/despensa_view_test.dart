import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/inventory_data.dart';
import 'package:saborpro_reports/presentation/widgets/despensa_view.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';

/// La Despensa sin Firebase: la pantalla real le pasa los ingredientes ya leídos.
/// Los datos son los del diseño (despensa.html): 14 ingredientes en 3 sucursales.
/// Cualquier "RenderFlex overflowed" hace fallar la prueba por sí sola.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  const dias = ['2026-11-14', '2026-11-15', '2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20'];
  const sucursales = [DespensaSucursal('ch', 'Chiquimula'), DespensaSucursal('lr', 'Las Rosas'), DespensaSucursal('sr', 'San Rafael')];

  /// [celdas]: [stock, días] por sucursal (nulo = no se maneja ahí). Días 999 = no se acaba.
  IngredientStock ing(String n, List<List<num>?> celdas, double? costo, {List<double>? porDia, String unidad = 'unidades'}) {
    const ids = ['ch', 'lr', 'sr'];
    final stock = <String, double>{}, dd = <String, double>{}, costos = <String, double>{};
    final consumo = <String, Map<String, double>>{};
    for (var k = 0; k < 3; k++) {
      final c = celdas[k];
      if (c == null) continue;
      stock[ids[k]] = c[0].toDouble();
      if (c[1] > 0 || c[0] == 0) dd[ids[k]] = c[1].toDouble();
      if (costo != null) costos[ids[k]] = costo;
      if (porDia != null && k == 2) consumo[ids[k]] = {for (var d = 0; d < 7; d++) dias[d]: porDia[d]};
    }
    return IngredientStock(
      name: n,
      unit: unidad,
      stockByLocation: stock,
      minStockByLocation: const {},
      daysRemainingByLocation: dd,
      costByLocation: costos,
      consumptionByDayByLocation: consumo,
    );
  }

  List<IngredientStock> catorce() => [
        ing('Adrenalina 296 ml', [null, null, [0, 0]], 9.5, porDia: [0, 0, 0, 0, 0, 6, 0]),
        ing('Adrenalina 473 ml', [null, null, [11, 51]], 12, porDia: [0, 1, 0, 0, 0, 1, 0]),
        ing('Aqua 1 Litro', [null, null, [17, 38]], 4.5, porDia: [1, 0, 0, 0, 2, 0, 0]),
        ing('Bacardi Raspberry', [null, null, [21, 63]], 95),
        ing('Big Mix', [null, null, [1, 2]], 11, porDia: [1, 1, 0, 0, 1, 1, 0]),
        ing('Bush Light 16 onz.', [null, null, [1, 9]], 10),
        ing('Caguama', [null, null, [40, 14]], 16, porDia: [1, 0, 0, 1, 1, 6, 0]),
        ing('California Mora Uva Desech.', [null, null, [12, 999]], 6),
        ing('Chip Fuego', [null, null, [11, 40]], 4),
        ing('Chip Jalapeño', [null, null, [13, 999]], 4),
        ing('Chip Sal', [null, null, [9, 30]], 4),
        ing('Coca Cola - Vidrio 500ml', [null, [1000, 999], null], 5.2),
        ing('Coca Cola Desechable 600 ml', [null, null, [14, 11]], 6.5, porDia: [1, 2, 0, 0, 2, 2, 0]),
        ing('Coca Cola Lata 354 ml', [[8, 4], null, [20, 30]], 5.8, porDia: [0, 1, 0, 0, 2, 0, 0]),
      ];

  final actualizado = DateTime(2026, 11, 21, 8, 31);
  final ahora = DateTime(2026, 11, 21, 8, 52);

  Widget cuerpo({
    List<IngredientStock>? items,
    List<DespensaSucursal> suc = sucursales,
    bool cargando = false,
    String? error,
    bool elegida = false,
    VoidCallback? onReintentar,
    VoidCallback? onActualizar,
    VoidCallback? onDescargar,
    ValueChanged<String>? onElegir,
    DateTime? actualizadoEn,
  }) =>
      DespensaBody(
        items: items ?? catorce(),
        sucursales: suc,
        dias: dias,
        actualizado: actualizadoEn ?? actualizado,
        ahora: ahora,
        cargando: cargando,
        error: error,
        onReintentar: onReintentar,
        onActualizar: onActualizar,
        onDescargar: onDescargar,
        onElegirSucursal: onElegir,
        sucursalElegida: elegida,
      );

  Future<void> montar(WidgetTester tester, Widget c, {Size size = const Size(1280, 900), double escala = 1.0, bool asentar = true}) async {
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
    asentar ? await tester.pumpAndSettle() : await tester.pump();
  }

  const tamanos = [Size(360, 800), Size(390, 844), Size(700, 900), Size(1280, 900)];

  group('el encabezado', () {
    testWidgets('el título y hace cuánto se actualizó', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Despensa'), findsOneWidget);
      expect(find.text('Actualizado hace 21 min'), findsOneWidget);
    });

    testWidgets('segundos, minutos, horas, y "Cargando..." si no se ha leído', (tester) async {
      await montar(tester, cuerpo(actualizadoEn: ahora.subtract(const Duration(seconds: 7))));
      expect(find.text('Actualizado hace 7s'), findsOneWidget);
      await montar(tester, cuerpo(actualizadoEn: ahora.subtract(const Duration(hours: 3, minutes: 5))));
      expect(find.text('Actualizado hace 3 h'), findsOneWidget);
      await montar(tester, DespensaBody(items: const [], sucursales: sucursales, dias: dias, ahora: ahora, cargando: true), asentar: false);
      expect(find.text('Cargando...'), findsOneWidget);
    });

    testWidgets('descargar y actualizar llaman a lo suyo', (tester) async {
      var bajados = 0, refrescos = 0;
      await montar(tester, cuerpo(onDescargar: () => bajados++, onActualizar: () => refrescos++));
      await tester.tap(find.byTooltip('Descargar Excel'));
      await tester.tap(find.byTooltip('Actualizar'));
      expect((bajados, refrescos), (1, 1));
    });
  });

  group('el dinero en inventario', () {
    testWidgets('el total a precio de costo y lo de cada sucursal', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Dinero en inventario'), findsOneWidget);
      expect(find.text('Q8,521.90'), findsOneWidget);
      expect(find.text('a precio de costo'), findsOneWidget);
      expect(find.text('Chiquimula'), findsWidgets);
      expect(find.text('Q46.40'), findsOneWidget);
      expect(find.text('Q5,200.00'), findsOneWidget);
      expect(find.text('Q3,275.50'), findsOneWidget);
    });

    testWidgets('tocar una sucursal la elige', (tester) async {
      final elegidas = <String>[];
      await montar(tester, cuerpo(onElegir: elegidas.add));
      await tester.tap(find.text('Q5,200.00'));
      expect(elegidas, ['lr']);
    });

    testWidgets('con una sucursal elegida, solo el dinero de esa y lo dice', (tester) async {
      await montar(tester, cuerpo(suc: const [DespensaSucursal('sr', 'San Rafael')], elegida: true));
      expect(find.text('Dinero en inventario · San Rafael'), findsOneWidget);
      expect(find.text('Q3,275.50'), findsOneWidget);
      expect(find.text('Chiquimula'), findsNothing);
    });

    testWidgets('lo que no tiene precio anotado no se cuenta y se dice', (tester) async {
      final items = [
        ing('Con precio', [null, null, [10, 30]], 5),
        ing('Sin precio', [null, null, [10, 30]], null),
        ing('Otro sin precio', [null, null, [3, 30]], null),
      ];
      await montar(tester, cuerpo(items: items, suc: const [DespensaSucursal('sr', 'San Rafael')], elegida: true));
      expect(find.text('Q50.00'), findsWidgets);
      expect(find.text('2 ingredientes sin precio de compra: no se cuentan'), findsOneWidget);
      // En la tabla, su valor es una raya (no Q0.00).
      expect(find.text('Q0.00'), findsNothing);
    });

    testWidgets('con sucursales en dos monedas no se suman: cada moneda por su lado y sin columna de valor', (tester) async {
      final items = [
        ing('Algo', [[10, 30], null, [4, 30]], 2),
      ];
      const dos = [DespensaSucursal('ch', 'Chiquimula'), DespensaSucursal('sr', 'San Rafael', simbolo: r'$')];
      await montar(tester, cuerpo(items: items, suc: dos));
      expect(find.text(r'Q20.00 · $8.00'), findsOneWidget);
      expect(find.text('VALOR'), findsNothing);
    });

    testWidgets('en el modo consumo no sale el dinero', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.text('Consumo 7 días'));
      await tester.pumpAndSettle();
      expect(find.text('Dinero en inventario'), findsNothing);
    });
  });

  group('los filtros de estado', () {
    testWidgets('con cuántos hay de cada uno', (tester) async {
      await montar(tester, cuerpo());
      for (final n in ['Todos', 'Agotado', 'Pronto', 'Bien']) {
        expect(find.text(n), findsWidgets, reason: n);
      }
      expect(find.text('14'), findsWidgets, reason: 'Todos 14 (y lo que hay de Coca Cola Desechable)');
      expect(find.text('3'), findsWidgets);
      expect(find.text('10'), findsWidgets);
    });

    testWidgets('elegir "Agotado" deja solo los agotados; "Todos" los devuelve', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.widgetWithText(GestureDetector, 'Agotado').first);
      await tester.pumpAndSettle();
      expect(find.text('Adrenalina 296 ml'), findsOneWidget);
      expect(find.text('Big Mix'), findsNothing);
      expect(find.text('Caguama'), findsNothing);
      await tester.tap(find.widgetWithText(GestureDetector, 'Todos').first);
      await tester.pumpAndSettle();
      expect(find.text('Big Mix'), findsOneWidget);
    });

    testWidgets('"Pronto" deja los que se acaban en menos de 10 días', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.widgetWithText(GestureDetector, 'Pronto').first);
      await tester.pumpAndSettle();
      expect(find.text('Big Mix'), findsOneWidget);
      expect(find.text('Coca Cola Lata 354 ml'), findsOneWidget);
      expect(find.text('Bush Light 16 onz.'), findsOneWidget);
      expect(find.text('Caguama'), findsNothing);
    });
  });

  group('la búsqueda', () {
    testWidgets('sin importar mayúsculas, deja los que coinciden', (tester) async {
      await montar(tester, cuerpo());
      await tester.enterText(find.byKey(const Key('despensa-buscar')), 'COCA');
      await tester.pumpAndSettle();
      expect(find.text('Coca Cola Lata 354 ml'), findsOneWidget);
      expect(find.text('Coca Cola Desechable 600 ml'), findsOneWidget);
      expect(find.text('Coca Cola - Vidrio 500ml'), findsOneWidget);
      expect(find.text('Caguama'), findsNothing);
    });

    testWidgets('sin coincidencias lo dice', (tester) async {
      await montar(tester, cuerpo());
      await tester.enterText(find.byKey(const Key('despensa-buscar')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Sin resultados'), findsOneWidget);
    });
  });

  group('la tabla de días que alcanza', () {
    testWidgets('las columnas: ingrediente, cada sucursal, total y valor', (tester) async {
      await montar(tester, cuerpo());
      for (final h in ['INGREDIENTE', 'CHIQUIMULA', 'LAS ROSAS', 'SAN RAFAEL', 'TOTAL', 'VALOR']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
    });

    testWidgets('con una sola sucursal a la vista no hay columna de total', (tester) async {
      await montar(tester, cuerpo(suc: const [DespensaSucursal('sr', 'San Rafael')], elegida: true));
      expect(find.text('TOTAL'), findsNothing);
      expect(find.text('SAN RAFAEL'), findsOneWidget);
    });

    testWidgets('lo más urgente primero, en grupos: agotado, pronto y bien', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      expect(find.text('AGOTADO'), findsWidgets);
      expect(find.text('PRONTO · <10 DÍAS'), findsOneWidget);
      expect(find.text('BIEN'), findsWidgets);
      final y = [for (final n in ['Adrenalina 296 ml', 'Big Mix', 'Bush Light 16 onz.', 'Caguama']) tester.getTopLeft(find.text(n)).dy];
      expect(y[0] < y[1] && y[1] < y[2] && y[2] < y[3], isTrue, reason: '$y');
    });

    testWidgets('cada celda: lo que hay y para cuántos días, con su color', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      expect(find.text('4 días'), findsOneWidget);
      expect(find.text('2 días'), findsOneWidget);
      expect(find.text('9 días'), findsOneWidget);
      expect(find.text('30 días'), findsNWidgets(2));
      expect(find.text('+180 días'), findsNWidgets(3), reason: 'California Mora, Chip Jalapeño y Coca Cola Vidrio');
      // Agotado: el 0 y la palabra, en rojo.
      expect(tester.widget<Text>(find.text('Agotado').last).style!.color!.a, greaterThan(0.8));
    });

    testWidgets('lo que no se maneja en una sucursal va con una raya', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('el total de las sucursales y el valor de cada fila', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      // Coca Cola Lata: 8 + 20 = 28; vale 28 × Q5.80.
      expect(find.text('28'), findsOneWidget);
      expect(find.text('Q162.40'), findsOneWidget);
      expect(find.text('Q640.00'), findsOneWidget);
      expect(find.text('Q0.00'), findsOneWidget, reason: 'lo agotado vale cero');
    });

    testWidgets('un ingrediente sin consumo no dice que se acaba: "Sin consumo"', (tester) async {
      final items = [ing('Sin movimiento', [null, null, [12, 0]], 3)];
      await montar(tester, cuerpo(items: items));
      expect(find.text('Sin consumo'), findsOneWidget);
      expect(find.text('Agotado'), findsWidgets, reason: 'los filtros y la leyenda; la celda no');
      expect(find.text('PRONTO · <10 DÍAS'), findsNothing);
    });

    testWidgets('la unidad solo cuando dice algo (en "unidades" no se dice)', (tester) async {
      final items = [
        ing('Harina', [null, null, [5, 30]], 3, unidad: 'kilogramos'),
        ing('Vasos', [null, null, [5, 30]], 3),
      ];
      await montar(tester, cuerpo(items: items));
      expect(find.textContaining('Harina · kg', findRichText: true), findsOneWidget);
      expect(find.textContaining('Vasos', findRichText: true), findsOneWidget);
      expect(find.textContaining('Vasos ·', findRichText: true), findsNothing);
    });

    testWidgets('la leyenda dice de dónde salen los días', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Menos de 10 días'), findsOneWidget);
      expect(find.text('Alcanza bien'), findsOneWidget);
      expect(find.textContaining('consumo de los últimos 30 días'), findsOneWidget);
    });
  });

  group('la tabla de consumo de 7 días', () {
    Future<void> alConsumo(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
      await montar(tester, cuerpo(), size: size);
      await tester.tap(find.text('Consumo 7 días'));
      await tester.pumpAndSettle();
    }

    testWidgets('un día por columna y el total; sin los filtros de estado', (tester) async {
      await alConsumo(tester);
      for (final h in ['SÁB 14', 'DOM 15', 'LUN 16', 'MAR 17', 'MIÉ 18', 'JUE 19', 'VIE 20', 'TOTAL']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('Todos'), findsNothing);
      expect(find.text('Agotado'), findsNothing);
    });

    testWidgets('solo lo que se consumió, de más a menos', (tester) async {
      await alConsumo(tester);
      final y = [for (final n in ['Caguama', 'Coca Cola Desechable 600 ml', 'Adrenalina 296 ml']) tester.getTopLeft(find.text(n)).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
      expect(find.text('Bacardi Raspberry'), findsNothing, reason: 'no se consumió nada');
      // Caguama: 1 + 1 + 1 + 6 = 9.
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('los días sin consumo, con una raya; la leyenda dice qué es el color', (tester) async {
      await alConsumo(tester);
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('Más oscuro = más consumo'), findsOneWidget);
    });

    testWidgets('si nada se consumió, lo dice', (tester) async {
      await montar(tester, cuerpo(items: [ing('Quieto', [null, null, [5, 30]], 3)]));
      await tester.tap(find.text('Consumo 7 días'));
      await tester.pumpAndSettle();
      expect(find.text('Ningún ingrediente tuvo consumo en los últimos 7 días'), findsOneWidget);
    });

    testWidgets('volver a "Días que alcanza" trae de vuelta el dinero y los filtros', (tester) async {
      await alConsumo(tester);
      await tester.tap(find.text('Días que alcanza'));
      await tester.pumpAndSettle();
      expect(find.text('Dinero en inventario'), findsOneWidget);
      expect(find.text('Todos'), findsWidgets);
    });
  });

  group('lo que no se puede mostrar', () {
    testWidgets('sin ingredientes en las sucursales que se ven', (tester) async {
      await montar(tester, cuerpo(items: const []));
      expect(find.text('Sin resultados'), findsOneWidget);
    });

    testWidgets('si falló la lectura lo dice y deja reintentar', (tester) async {
      var intentos = 0;
      await montar(tester, cuerpo(error: 'Error cargando inventario: sin red', onReintentar: () => intentos++));
      expect(find.text('Error cargando inventario: sin red'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(intentos, 1);
      expect(find.text('Dinero en inventario'), findsNothing);
    });

    testWidgets('mientras carga, un indicador', (tester) async {
      await montar(tester, cuerpo(cargando: true), asentar: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('la columna del nombre sigue a los datos', () {
    testWidgets('al bajar por la tabla, los nombres bajan con ella', (tester) async {
      final muchos = [for (var i = 0; i < 80; i++) ing('Ingrediente ${i.toString().padLeft(2, '0')}', [null, null, [10, 30 + i]], 2)];
      await montar(tester, cuerpo(items: muchos, suc: const [DespensaSucursal('sr', 'San Rafael')], elegida: true), size: const Size(1280, 700));
      expect(find.text('Ingrediente 00'), findsOneWidget);
      expect(find.text('Ingrediente 60'), findsNothing, reason: 'todavía no se construye');
      await tester.drag(find.byType(ListView).last, const Offset(0, -2200));
      await tester.pumpAndSettle();
      expect(find.text('Ingrediente 00'), findsNothing);
      expect(find.textContaining('Ingrediente 5'), findsWidgets, reason: 'los nombres siguieron a los datos');
    });
  });

  group('cabe sin desbordar', () {
    for (final s in tamanos) {
      testWidgets('a ${s.width.toInt()} con letra grande y datos normales, en los dos modos', (tester) async {
        await montar(tester, cuerpo(), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Consumo 7 días'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande, cifras enormes, nombres larguísimos y muchas sucursales', (tester) async {
        final muchas = <DespensaSucursal>[
          for (var i = 0; i < 5; i++) DespensaSucursal('s$i', 'Una sucursal con un nombre larguísimo de verdad número $i'),
        ];
        final items = [
          for (var i = 0; i < 12; i++)
            IngredientStock(
              name: 'Un ingrediente con un nombre larguísimo de verdad para ver qué pasa número $i',
              unit: 'kilogramos',
              stockByLocation: {for (var k = 0; k < 5; k++) 's$k': 98765432.5 + i},
              minStockByLocation: const {},
              daysRemainingByLocation: {for (var k = 0; k < 5; k++) 's$k': i.isEven ? 3.0 : 4000.0},
              costByLocation: {for (var k = 0; k < 5; k++) 's$k': 123456.78},
              consumptionByDayByLocation: {for (var k = 0; k < 5; k++) 's$k': {for (final d in dias) d: 12345678.9 + i}},
            ),
        ];
        await montar(tester, cuerpo(items: items, suc: muchas), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Consumo 7 días'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande en los estados vacío, error y cargando', (tester) async {
        for (final (c, asentar) in [
          (cuerpo(items: const []), true),
          (cuerpo(error: 'Error cargando inventario: algo largo que tiene que partirse en varias líneas sin romper nada', onReintentar: () {}), true),
          (cuerpo(cargando: true), false),
        ]) {
          await montar(tester, c, size: s, escala: 1.35, asentar: asentar);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
