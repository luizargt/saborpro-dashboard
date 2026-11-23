import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/data/models/rentabilidad_data.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:saborpro_reports/presentation/widgets/rentabilidad_view.dart';

/// Rentabilidad sin Firebase: la pantalla real le pasa los números ya armados. Los
/// datos son los del diseño (rentabilidad.html): 3 sucursales, Q373,981 vendidos,
/// 14 productos con receta y 5 sin ella. Cualquier "RenderFlex overflowed" hace
/// fallar la prueba por sí sola.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  final octubre = DateRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31, 23, 59, 59), mode: PeriodMode.month);
  final despues = DateTime(2026, 11, 3);

  ExpenseLine fijo(String id, String nombre, double monto) => ExpenseLine(categoryId: id, label: nombre, amount: monto, esFijo: true);
  ExpenseLine variable(String id, String nombre, double monto) => ExpenseLine(categoryId: id, label: nombre, amount: monto);

  ProfitabilityData datos({
    double ventas = 373981,
    double cogs = 115934,
    List<ExpenseLine>? gastos,
    double sueldos = 88000,
    int conCosto = 100,
    int estimados = 0,
    int sinCosto = 0,
    double efectivo = 0,
    double cargadoPrepro = 0,
    double restadoPrepro = 0,
  }) =>
      ProfitabilityData(
        netSales: ventas,
        cogs: cogs,
        itemsConCosto: conCosto,
        itemsEstimados: estimados,
        itemsSinCosto: sinCosto,
        expenses: gastos ??
            [
              fijo('salarios', 'Sueldos', 88000),
              fijo('renta', 'Renta', 28000),
              fijo('internet', 'Luz, agua, internet', 20000),
              variable('otros', 'Otros', 14000),
            ],
        payroll: sueldos,
        paidFromCash: efectivo,
        purchases: 42000,
        inventoryValue: 95000.5,
        ingredientesSinPrecio: 0,
        cargadoPreproduccion: cargadoPrepro,
        restadoPreproduccion: restadoPrepro,
      );

  // ── El menú del diseño ────────────────────────────────────────────────────
  MargenPlatillo plato(String id, String nombre, double precio, double costo, {String? pres, bool reventa = false, EstadoCosto? estado}) => MargenPlatillo(
        productoId: id,
        presentacionId: 'p1',
        producto: nombre,
        presentacion: pres,
        precio: (precio * 100).round(),
        estado: estado ?? (costo < 0 ? EstadoCosto.sinReceta : EstadoCosto.completo),
        lineas: costo < 0
            ? const []
            : reventa
                ? [LineaCosto(ingrediente: 'lata $id', cantidad: 1, unidad: 'und.', precio: costo)]
                : [LineaCosto(ingrediente: 'a $id', cantidad: 1, unidad: 'kg', precio: costo / 2), LineaCosto(ingrediente: 'b $id', cantidad: 1, unidad: 'kg', precio: costo / 2)],
      );

  // (id, nombre, presentación, precio, costo, reventa, bebida, vendidos)
  final catalogo = <(String, String, String, double, double, bool, bool, int)>[
    ('gallo', 'Gallo', 'Lata 350 ml', 15, 7.5, true, true, 620),
    ('coca', 'Coca Cola', 'Personal 500 ml', 5, 4.08, true, true, 900),
    ('gatorade', 'Gatorade', 'Desechable Fresa', 10, 8.33, true, true, 60),
    ('agua', 'Agua Pura', '600 ml', 6, 4.2, true, true, 460),
    ('limonada', 'Limonada', 'Vaso', 15, 1.8, false, true, 280),
    ('cafe', 'Café americano', 'Taza', 12, 1.5, false, true, 180),
    ('licuado', 'Licuado de fresa', 'Vaso', 20, 6.4, false, true, 120),
    ('papas', 'Papas fritas', 'Orden', 25, 4.5, false, false, 440),
    ('pupusas', 'Pupusas revueltas', 'Unidad', 10, 2.1, false, false, 1250),
    ('hamb', 'Hamburguesa clásica', 'Con papas', 55, 16.5, false, false, 260),
    ('churrasco', 'Churrasco', 'Plato', 95, 42, false, false, 105),
    ('ceviche', 'Ceviche de camarón', 'Copa', 85, 25.5, false, false, 26),
    ('sopa', 'Sopa de res', 'Plato', 45, 20.25, false, false, 18),
    ('alitas', 'Alitas BBQ', '10 piezas', 60, 19.8, false, false, 220),
  ];
  // Sin receta: (id, nombre, presentación, precio, vendidos).
  final sinReceta = <(String, String, String?, double, int)>[
    ('michelada', 'Michelada', null, 25, 550),
    ('tacos', 'Tacos al pastor', 'Orden de 3', 35, 380),
    ('desayuno', 'Desayuno chapín', null, 45, 280),
    ('corona', 'Corona', '355 ml', 20, 300),
    ('club', 'Club sándwich', null, 50, 130),
  ];

  AnalisisMenu menuDelDiseno() {
    final platillos = [
      for (final c in catalogo) plato(c.$1, c.$2, c.$4, c.$5, pres: c.$3, reventa: c.$6),
      for (final s in sinReceta) plato(s.$1, s.$2, s.$4, -1, pres: s.$3),
    ];
    return AnalisisMenu.armar(
      platillos: platillos,
      vendidas: UnidadesVendidas({
        for (final c in catalogo) '${c.$1}|p1': VentaDePlatillo(c.$8, c.$8 * c.$4),
        for (final s in sinReceta) '${s.$1}|p1': VentaDePlatillo(s.$5, s.$5 * s.$4),
      }, 0),
      clasificacion: {for (final c in catalogo) c.$1: c.$7 ? 'Bebidas' : 'Comida'},
    );
  }

  ComparacionSucursales comparacion() => ComparacionSucursales.armar(
        porSucursal: {
          'ch': datos(ventas: 118420, cogs: 36710, gastos: [fijo('salarios', 'Sueldos', 40000), fijo('renta', 'Renta', 12000), fijo('internet', 'Luz', 9000), variable('otros', 'Otros', 7000)]),
          'lr': datos(ventas: 102350, cogs: 33775, gastos: const []),
          'sr': datos(ventas: 153211, cogs: 45449, gastos: [fijo('salarios', 'Sueldos', 48000), fijo('renta', 'Renta', 16000), fijo('internet', 'Luz', 11000), variable('otros', 'Otros', 7000)]),
        },
        sucursales: const [('ch', 'Chiquimula'), ('lr', 'La Reforma'), ('sr', 'Santa Rosalia')],
      );

  Widget cuerpo({
    ProfitabilityData? d,
    DateRange? rango,
    List<String> sinFijos = const [],
    bool varias = true,
    ComparacionSucursales? comp,
    AnalisisMenu? menu,
    bool sinMenu = false,
    bool cargando = false,
    String? error,
    bool sinPedidos = false,
    bool incompletas = false,
    String? notaMoneda,
    String notaPrecios = 'Precios y costos de Chiquimula.',
    AvisoPreproduccion? prepro,
    VoidCallback? alGastos,
    VoidCallback? alReintentar,
    VoidCallback? alUtilidad,
    bool conUtilidad = true,
    DateTime? ahora,
  }) =>
      RentabilidadBody(
        datos: d ?? datos(),
        rango: rango ?? octubre,
        ahora: ahora ?? despues,
        signo: 'Q',
        sinGastosFijos: sinFijos,
        variasSucursales: varias,
        comparacion: comp ?? ComparacionSucursales.vacia,
        menu: sinMenu ? null : (menu ?? menuDelDiseno()),
        menuCargando: cargando,
        menuError: error,
        menuSinPedidos: sinPedidos,
        ventasIncompletas: incompletas,
        notaMoneda: notaMoneda,
        notaPrecios: notaPrecios,
        avisoPreproduccion: prepro,
        onReintentarMenu: alReintentar,
        onIrAGastos: alGastos ?? () {},
        onVerUtilidadPlatillos: conUtilidad ? (alUtilidad ?? () {}) : null,
      );

  Future<void> montar(WidgetTester tester, Widget c, {Size size = const Size(1280, 5200), double escala = 1.0}) async {
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

  const telefono = Size(360, 6800);

  group('el héroe: ¿ganaste?', () {
    testWidgets('dice cuánto ganaste, y desde qué día se cubrió el equilibrio', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('En octubre ganaste'), findsOneWidget);
      // 373,981 − 115,934 − 150,000.
      expect(find.text('Q108,047.00'), findsWidgets);
      expect(find.text('después de pagar comida y gastos'), findsOneWidget);
      expect(find.text('¿Cuánto necesitas vender para no perder?'), findsOneWidget);
      expect(find.text('Para no perder'), findsOneWidget);
      expect(find.textContaining('Vendiste'), findsOneWidget);
      // Equilibrio de Q208,4xx; vendiendo 12,064 al día se cubre el día 18.
      expect(find.textContaining('día 18 de octubre'), findsOneWidget);
      expect(find.textContaining('Lo que vendiste después fue ganancia'), findsOneWidget);
    });

    testWidgets('si perdiste, el monto va en rojo y lo dice', (tester) async {
      await montar(tester, cuerpo(d: datos(ventas: 100000, cogs: 40000, gastos: [fijo('renta', 'Renta', 80000)], sueldos: 0)));
      expect(find.text('En octubre perdiste'), findsOneWidget);
      expect(find.text('Q20,000.00'), findsWidgets);
      final monto = tester.widget<Text>(find.text('Q20,000.00').first);
      expect(monto.style?.color, InicioColores.bad);
      // Faltan Q 80,000/0.6 − 100,000 = 33,333.
      expect(find.textContaining('Te faltaron'), findsOneWidget);
      expect(find.textContaining('Q33,333'), findsOneWidget);
    });

    testWidgets('el mes en curso dice "te faltan", no "te faltaron"', (tester) async {
      await montar(
        tester,
        cuerpo(d: datos(ventas: 100000, cogs: 40000, gastos: [fijo('renta', 'Renta', 80000)], sueldos: 0), ahora: DateTime(2026, 10, 15)),
      );
      expect(find.textContaining('Te faltan '), findsOneWidget);
      expect(find.textContaining('Te faltaron'), findsNothing);
    });

    testWidgets('sin gastos fijos no se inventa una ganancia: "¿?" y por qué', (tester) async {
      await montar(tester, cuerpo(d: datos(gastos: [variable('otros', 'Otros', 500)], sueldos: 0)));
      expect(find.text('En octubre ganaste'), findsOneWidget);
      expect(find.text('¿?'), findsOneWidget);
      expect(find.text('Registra tus gastos fijos'), findsOneWidget);
      expect(find.text('¿Cuánto necesitas vender para no perder?'), findsNothing);
      // La utilidad sigue a la vista en el estado de resultados.
      expect(find.text('Utilidad operativa'), findsOneWidget);
      expect(find.text('No es real aún'), findsOneWidget);
    });

    testWidgets('en un día o una semana, avisa que es normal no tener gastos fijos', (tester) async {
      final dia = DateRange(start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 10, 23, 59), mode: PeriodMode.day);
      await montar(tester, cuerpo(rango: dia, d: datos(gastos: [variable('otros', 'Otros', 500)], sueldos: 0)));
      expect(find.textContaining('se anotan una vez al mes'), findsOneWidget);
      await montar(tester, cuerpo(d: datos(gastos: [variable('otros', 'Otros', 500)], sueldos: 0)));
      expect(find.textContaining('se anotan una vez al mes'), findsNothing);
    });

    testWidgets('si cada venta pierde dinero, lo dice en vez de un punto de equilibrio imposible', (tester) async {
      await montar(tester, cuerpo(d: datos(ventas: 1000, cogs: 1500, gastos: [fijo('renta', 'Renta', 100)], sueldos: 0)));
      expect(find.textContaining('Cada venta te cuesta dinero'), findsOneWidget);
      expect(find.text('Para no perder'), findsNothing);
    });

    testWidgets('con una sucursal sin gastos, avisa de cuál', (tester) async {
      await montar(tester, cuerpo(sinFijos: const ['La Reforma']));
      expect(find.text('Sin contar gastos de La Reforma'), findsOneWidget);
    });

    testWidgets('con una sola sucursal no la nombra', (tester) async {
      await montar(tester, cuerpo(sinFijos: const ['La Reforma'], varias: false));
      expect(find.text('Sin contar gastos fijos'), findsOneWidget);
      expect(find.textContaining('La Reforma'), findsNothing);
    });

    testWidgets('en el año dice "al año"; el día no se calcula', (tester) async {
      final anio = DateRange(start: DateTime(2026), end: DateTime(2026, 12, 31), mode: PeriodMode.year);
      await montar(tester, cuerpo(rango: anio));
      expect(find.text('En 2026 ganaste'), findsOneWidget);
      expect(find.textContaining('día '), findsNothing);
      expect(find.textContaining('Ya cubriste tus gastos'), findsOneWidget);
    });
  });

  group('los tres indicadores', () {
    testWidgets('costo de comida, costo primo y margen, con su estado', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Costo de comida'), findsOneWidget);
      // El del indicador y el de la fila "− Costo de lo vendido" del estado de resultados.
      expect(find.text('31.0%'), findsNWidgets(2));
      expect(find.text('Meta: menos de 35%'), findsOneWidget);
      expect(find.text('Costo primo'), findsOneWidget);
      // (115,934 + 88,000) / 373,981.
      expect(find.text('54.5%'), findsOneWidget);
      expect(find.text('Margen'), findsOneWidget);
      expect(find.text('28.9%'), findsWidgets);
      expect(find.text('Bien'), findsNWidgets(2));
      expect(find.text('Sano'), findsOneWidget);
      // Las marcas de las metas.
      expect(find.text('35%'), findsWidgets);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('10%'), findsWidgets);
    });

    testWidgets('un costo de comida alto se marca "Alto"', (tester) async {
      await montar(tester, cuerpo(d: datos(cogs: 180000)));
      expect(find.text('Alto'), findsWidgets);
    });

    testWidgets('entre 35% y 40% es "Atención", no "Alto"', (tester) async {
      await montar(tester, cuerpo(d: datos(cogs: 373981 * 0.37)));
      expect(find.text('Atención'), findsOneWidget);
    });

    testWidgets('un margen bajo o negativo se marca', (tester) async {
      await montar(tester, cuerpo(d: datos(cogs: 200000)));
      // 373,981 − 200,000 − 150,000 = 23,981 → 6.4%: entre 0 y 10%.
      expect(find.text('Atención'), findsWidgets);
      await montar(tester, cuerpo(d: datos(cogs: 300000)));
      expect(find.text('Bajo'), findsOneWidget);
    });

    testWidgets('sin sueldos anotados, el costo primo dice que faltan', (tester) async {
      await montar(tester, cuerpo(d: datos(sueldos: 0, gastos: [fijo('renta', 'Renta', 28000)])));
      expect(find.text('Faltan sueldos'), findsOneWidget);
    });

    testWidgets('con sucursales sin gastos, el margen es "Parcial"', (tester) async {
      await montar(tester, cuerpo(sinFijos: const ['La Reforma']));
      expect(find.text('Parcial'), findsOneWidget);
      expect(find.text('Faltan sueldos'), findsOneWidget);
    });

    testWidgets('si falta costo, "Incompleto" y el aviso de que la ganancia puede ser menor', (tester) async {
      await montar(tester, cuerpo(d: datos(conCosto: 40, sinCosto: 60)));
      expect(find.text('Incompleto'), findsOneWidget);
      expect(find.text('Tu ganancia real puede ser menor'), findsOneWidget);
      expect(find.textContaining('Solo 40.0% de lo que vendiste tiene costo'), findsOneWidget);
    });

    testWidgets('si el costo es de precios de hoy, "Estimado" y su aviso', (tester) async {
      await montar(tester, cuerpo(d: datos(conCosto: 50, estimados: 50)));
      expect(find.text('Estimado'), findsOneWidget);
      expect(find.text('El costo es una estimación'), findsOneWidget);
    });

    testWidgets('un costo bueno no trae aviso', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Incompleto'), findsNothing);
      expect(find.text('Tu ganancia real puede ser menor'), findsNothing);
    });
  });

  group('el estado de resultados', () {
    testWidgets('la cascada con sus porcentajes', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Ventas netas'), findsOneWidget);
      expect(find.text('Sin propinas ni envíos'), findsOneWidget);
      expect(find.text('Q373,981.00'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('− Costo de lo vendido'), findsOneWidget);
      expect(find.text('−Q115,934.00'), findsOneWidget);
      expect(find.text('Utilidad bruta'), findsOneWidget);
      expect(find.text('Q258,047.00'), findsOneWidget);
      expect(find.text('− Sueldos'), findsOneWidget);
      expect(find.text('−Q88,000.00'), findsOneWidget);
      expect(find.text('23.5%'), findsOneWidget);
      expect(find.text('Utilidad operativa'), findsOneWidget);
      expect(find.text('Q108,047.00'), findsWidgets);
    });

    testWidgets('una pérdida va en rojo', (tester) async {
      await montar(tester, cuerpo(d: datos(cogs: 300000)));
      final t = tester.widget<Text>(find.text('−Q76,019.00').last);
      expect(t.style?.color, InicioColores.bad);
    });

    testWidgets('una categoría que la preproducción dejó en cero no sale "−Q0.00"', (tester) async {
      await montar(tester, cuerpo(d: datos(gastos: [fijo('renta', 'Renta', 28000), variable('luz', 'Luz', 0)])));
      expect(find.text('Q0.00'), findsWidgets);
      expect(find.textContaining('−Q0.00'), findsNothing);
    });

    testWidgets('sin gastos registrados lo dice', (tester) async {
      await montar(tester, cuerpo(d: datos(gastos: const [], sueldos: 0)));
      expect(find.text('Sin gastos registrados en el período'), findsOneWidget);
    });

    testWidgets('si faltan gastos fijos de una sucursal, la fila los nombra y manda a Gastos', (tester) async {
      var fue = 0;
      await montar(tester, cuerpo(sinFijos: const ['La Reforma', 'Santa Rosalia'], alGastos: () => fue++));
      expect(find.text('Faltan gastos fijos de La Reforma, Santa Rosalia'), findsOneWidget);
      expect(find.textContaining('la utilidad sale más alta de lo real'), findsOneWidget);
      await tester.tap(find.text('Ir a Gastos'));
      expect(fue, 1);
    });

    testWidgets('con todo anotado no hay fila de faltantes', (tester) async {
      await montar(tester, cuerpo());
      expect(find.textContaining('Faltan gastos fijos'), findsNothing);
      expect(find.text('Ir a Gastos'), findsNothing);
    });

    testWidgets('sin ningún gasto fijo, la fila lo dice (sin nombrar sucursales)', (tester) async {
      await montar(tester, cuerpo(d: datos(gastos: [variable('otros', 'Otros', 500)], sueldos: 0), varias: false));
      expect(find.text('Faltan gastos fijos'), findsOneWidget);
    });
  });

  group('¿qué sucursal gana más?', () {
    testWidgets('una tarjeta por sucursal; la de más margen se corona', (tester) async {
      await montar(tester, cuerpo(comp: comparacion()));
      expect(find.text('¿Qué sucursal gana más?'), findsOneWidget);
      expect(find.text('Chiquimula'), findsOneWidget);
      expect(find.text('La Reforma'), findsOneWidget);
      expect(find.text('Santa Rosalia'), findsOneWidget);
      // Chiquimula: 118,420 − 36,710 − 68,000 = 13,710 (11.6%). Santa Rosalia:
      // 153,211 − 45,449 − 82,000 = 25,762 (16.8%): gana.
      expect(find.text('Q25,762'), findsOneWidget);
      expect(find.text('Q13,710'), findsOneWidget);
      expect(find.text('16.8% margen'), findsOneWidget);
      expect(find.text('11.6% margen'), findsOneWidget);
      expect(find.text('Más margen'), findsOneWidget);
      // Sin gastos fijos: no se sabe, y no gana.
      expect(find.text('Sin gastos fijos · no se sabe'), findsOneWidget);
      expect(find.text('Vendió'), findsNWidgets(3));
      expect(find.text('Q153,211'), findsOneWidget);
      expect(find.text('Costo de comida'), findsNWidgets(4)); // 3 tarjetas + el indicador
    });

    testWidgets('el costo de comida pasado de la meta va en rojo', (tester) async {
      final c = ComparacionSucursales.armar(
        porSucursal: {
          'ch': datos(ventas: 100000, cogs: 50000, gastos: [fijo('renta', 'Renta', 10000)]),
          'lr': datos(ventas: 100000, cogs: 20000, gastos: [fijo('renta', 'Renta', 10000)]),
        },
        sucursales: const [('ch', 'Chiquimula'), ('lr', 'La Reforma')],
      );
      await montar(tester, cuerpo(comp: c));
      final alto = tester.widget<Text>(find.text('50.0%').last);
      expect(alto.style?.color, InicioColores.bad);
    });

    testWidgets('una sucursal sin costo de comida cargado lo dice y no se corona', (tester) async {
      final c = ComparacionSucursales.armar(
        porSucursal: {
          'ch': datos(ventas: 100000, cogs: 35000, gastos: [fijo('renta', 'Renta', 20000)]),
          'lr': datos(ventas: 100000, cogs: 0, conCosto: 0, gastos: [fijo('renta', 'Renta', 20000)]),
        },
        sucursales: const [('ch', 'Chiquimula'), ('lr', 'La Reforma')],
      );
      await montar(tester, cuerpo(comp: c));
      expect(find.text('Costo incompleto'), findsOneWidget);
      expect(find.text('Más margen'), findsNothing);
    });

    testWidgets('lo vendido fuera de las tarjetas se explica', (tester) async {
      final c = ComparacionSucursales.armar(
        porSucursal: {
          'ch': datos(ventas: 118420, cogs: 36710, gastos: [fijo('renta', 'Renta', 12000)]),
          'sr': datos(ventas: 153211, cogs: 45449, gastos: [fijo('renta', 'Renta', 16000)]),
        },
        sucursales: const [('ch', 'Chiquimula'), ('sr', 'Santa Rosalia')],
        ventasTotales: 271631 + 4000,
      );
      await montar(tester, cuerpo(comp: c));
      expect(find.textContaining('también entran Q4,000 vendidos en sucursales ocultas'), findsOneWidget);
      await montar(tester, cuerpo(comp: comparacion()));
      expect(find.textContaining('sucursales ocultas'), findsNothing);
    });

    testWidgets('un porcentaje que redondea a cero no lleva signo', (tester) async {
      // Utilidad de −Q40 sobre Q100,000: −0.04%.
      await montar(tester, cuerpo(d: datos(ventas: 100000, cogs: 40000, gastos: [fijo('renta', 'Renta', 60040)], sueldos: 0)));
      expect(find.textContaining('-0.0%'), findsNothing);
      expect(find.textContaining('−0.0%'), findsNothing);
      expect(find.text('0.0%'), findsWidgets);
    });

    testWidgets('sin comparación (una sucursal o una pestaña) no hay sección', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('¿Qué sucursal gana más?'), findsNothing);
    });

    testWidgets('una sucursal sin movimiento lo dice', (tester) async {
      final c = ComparacionSucursales.armar(
        porSucursal: {
          'ch': datos(ventas: 100000, cogs: 50000, gastos: [fijo('renta', 'Renta', 10000)]),
          'lr': datos(ventas: 0, cogs: 0, gastos: const [], sueldos: 0),
        },
        sucursales: const [('ch', 'Chiquimula'), ('lr', 'La Reforma')],
      );
      await montar(tester, cuerpo(comp: c));
      expect(find.text('Sin movimiento en el período'), findsOneWidget);
    });

    testWidgets('ancho: en una hilera; teléfono: una debajo de otra', (tester) async {
      await montar(tester, cuerpo(comp: comparacion()));
      final a = tester.getTopLeft(find.text('Chiquimula'));
      final b = tester.getTopLeft(find.text('La Reforma'));
      expect(b.dx, greaterThan(a.dx + 200));
      expect((b.dy - a.dy).abs(), lessThan(8));
      await montar(tester, cuerpo(comp: comparacion()), size: telefono);
      final a2 = tester.getTopLeft(find.text('Chiquimula'));
      final b2 = tester.getTopLeft(find.text('La Reforma'));
      expect(b2.dy, greaterThan(a2.dy + 100));
    });
  });

  group('completa estas recetas primero', () {
    testWidgets('lo que más se vende sin receta, de más a menos', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Completa estas recetas primero'), findsOneWidget);
      expect(find.text('5 sin receta'), findsOneWidget);
      expect(find.textContaining('sin receta que más vendes'), findsOneWidget);
      // En plata: Michelada 13,750 · Tacos 13,300 · Desayuno 12,600 · Club 6,500 · Corona 6,000.
      final y = [for (final n in ['Michelada', 'Tacos al pastor', 'Desayuno chapín', 'Club sándwich', 'Corona']) tester.getTopLeft(find.text(n)).dy];
      expect(y, orderedEquals([...y]..sort()));
      expect(find.text('Q13,750'), findsOneWidget);
      expect(find.text('Orden de 3 · 380 vendidos'), findsOneWidget);
      expect(find.text('550 vendidos'), findsOneWidget);
      expect(find.text('en ventas'), findsNWidgets(5));
    });

    testWidgets('son cinco como mucho, y dice cuántas más hay', (tester) async {
      final platillos = [for (var i = 0; i < 8; i++) plato('s$i', 'Sin $i', 10, -1)];
      final menu = AnalisisMenu.armar(
        platillos: platillos,
        vendidas: UnidadesVendidas({for (var i = 0; i < 8; i++) 's$i|p1': VentaDePlatillo(10 + i, (10 + i) * 10.0)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      expect(find.text('8 sin receta'), findsOneWidget);
      expect(find.text('y 3 más'), findsOneWidget);
      expect(find.text('Sin 7'), findsOneWidget);
      expect(find.text('Sin 0'), findsNothing);
    });

    testWidgets('los de receta sin precio de algún ingrediente se cuentan aparte', (tester) async {
      final menu = AnalisisMenu.armar(
        platillos: [
          plato('a', 'A', 10, 3),
          plato('inc', 'Incompleto', 10, 3, estado: EstadoCosto.incompleto),
        ],
        vendidas: UnidadesVendidas({'a|p1': const VentaDePlatillo(5, 50), 'inc|p1': const VentaDePlatillo(5, 50)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      expect(find.textContaining('Otro platillo vendido tiene receta'), findsOneWidget);
      // Nada sin receta: no hay chip ni la frase de "los que más vendes".
      expect(find.textContaining('sin receta que más vendes'), findsNothing);
      expect(find.text('1 sin receta'), findsNothing);
    });

    testWidgets('si todo tiene receta, la tarjeta no aparece', (tester) async {
      final menu = AnalisisMenu.armar(
        platillos: [plato('a', 'A', 10, 3)],
        vendidas: UnidadesVendidas({'a|p1': const VentaDePlatillo(5, 50)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      expect(find.text('Completa estas recetas primero'), findsNothing);
    });
  });

  group('el mapa de tu menú', () {
    testWidgets('los cuatro cuadrantes con su consejo y sus productos', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Mapa de tu menú'), findsOneWidget);
      expect(find.text('¿qué hacer con cada platillo?'), findsOneWidget);
      expect(find.text('Gana mucho, se vende mucho'), findsOneWidget);
      expect(find.text('Cuídalo: no le cambies nada'), findsOneWidget);
      expect(find.text('Gana poco, se vende mucho'), findsOneWidget);
      expect(find.text('Súbele el precio o baja su costo'), findsOneWidget);
      expect(find.text('Gana mucho, se vende poco'), findsOneWidget);
      expect(find.text('Promociónalo o ponlo más visible'), findsOneWidget);
      expect(find.text('Gana poco, se vende poco'), findsOneWidget);
      expect(find.text('Considera quitarlo del menú'), findsOneWidget);
      expect(find.text('Gana más por venta'), findsOneWidget);
      expect(find.text('Se vende más'), findsOneWidget);
    });

    testWidgets('los catorce productos con costo están, cada uno una vez, con lo vendido', (tester) async {
      await montar(tester, cuerpo());
      // Los de reventa sin receta del diseño no entran: no hay costo.
      for (final c in catalogo) {
        expect(find.widgetWithText(Row, c.$2), findsWidgets, reason: c.$2);
      }
      expect(find.text('1,250'), findsOneWidget); // Pupusas
      expect(find.text('900'), findsOneWidget); // Coca Cola
    });

    testWidgets('los de cada cuadrante suman los productos analizados', (tester) async {
      await montar(tester, cuerpo());
      final cuentas = find.textContaining(RegExp(r'^\d+ productos?$'));
      var total = 0;
      for (final e in tester.widgetList<Text>(cuentas)) {
        total += int.parse(e.data!.split(' ').first);
      }
      expect(total, 14);
    });

    testWidgets('un cuadrante vacío dice "Ninguno"', (tester) async {
      final menu = AnalisisMenu.armar(
        platillos: [plato('a', 'A', 20, 10)],
        vendidas: UnidadesVendidas({'a|p1': const VentaDePlatillo(5, 100)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      expect(find.text('Ninguno'), findsNWidgets(3));
      expect(find.text('1 producto'), findsOneWidget);
    });

    testWidgets('con muchos productos, los primeros y "+N más"', (tester) async {
      final platillos = [for (var i = 0; i < 40; i++) plato('m$i', 'Menú $i', 20, 10)];
      final menu = AnalisisMenu.armar(
        platillos: platillos,
        vendidas: UnidadesVendidas({for (var i = 0; i < 40; i++) 'm$i|p1': VentaDePlatillo(100 - i, 0)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      expect(find.text('+25 más'), findsOneWidget);
      expect(find.text('Menú 0'), findsWidgets);
      expect(find.text('Menú 39'), findsNothing);
    });

    testWidgets('en el teléfono no hay ejes y los cuadros van uno debajo de otro', (tester) async {
      await montar(tester, cuerpo(), size: telefono);
      expect(find.text('Gana más por venta'), findsNothing);
      final a = tester.getTopLeft(find.text('Gana mucho, se vende poco')).dy;
      final b = tester.getTopLeft(find.text('Gana mucho, se vende mucho')).dy;
      expect(b, greaterThan(a + 80));
    });

    testWidgets('en ancho van de dos en dos', (tester) async {
      await montar(tester, cuerpo());
      final a = tester.getTopLeft(find.text('Gana mucho, se vende poco'));
      final b = tester.getTopLeft(find.text('Gana mucho, se vende mucho'));
      expect(b.dx, greaterThan(a.dx + 200));
      expect((b.dy - a.dy).abs(), lessThan(8));
    });
  });

  group('ganancia por platillo', () {
    testWidgets('por defecto, el total del mes: los ocho que más dejan', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Ganancia por platillo'), findsOneWidget);
      expect(find.text('Total del mes'), findsOneWidget);
      expect(find.text('Por venta'), findsOneWidget);
      // Hamburguesa 260 × Q38.50 = 10,010 · Pupusas 1,250 × 7.90 = 9,875.
      expect(find.text('Q10,010'), findsOneWidget);
      expect(find.text('260 × Q38.50'), findsOneWidget);
      expect(find.text('Q9,875'), findsOneWidget);
      expect(find.text('1,250 × Q7.90'), findsOneWidget);
      // Son ocho (los números del 1 al 8).
      for (var i = 1; i <= 8; i++) {
        expect(find.text('$i'), findsWidgets);
      }
      expect(find.text('Coca Cola'), findsNWidgets(1)); // en el mapa; no entra al top 8
    });

    testWidgets('el primero va arriba del segundo', (tester) async {
      await montar(tester, cuerpo());
      expect(tester.getTopLeft(find.text('Q10,010')).dy, lessThan(tester.getTopLeft(find.text('Q9,875')).dy));
    });

    testWidgets('fuera de un mes dice "Total del período"', (tester) async {
      final semana = DateRange(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 11), mode: PeriodMode.week);
      await montar(tester, cuerpo(rango: semana));
      expect(find.text('Total del período'), findsOneWidget);
      expect(find.text('Total del mes'), findsNothing);
    });

    testWidgets('"Por venta" cambia a lo que se pasa de su meta y lo que queda bajo ella', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.text('Por venta'));
      await tester.pumpAndSettle();
      expect(find.text('Revisa su precio'), findsOneWidget);
      expect(find.text('más arriba de su meta'), findsOneWidget);
      expect(find.text('Más ganancia'), findsOneWidget);
      expect(find.text('más abajo de su meta'), findsOneWidget);
      expect(find.text('por venta'), findsWidgets);
      expect(find.text('Reventa'), findsWidgets);
      // Se esconde el total.
      expect(find.text('260 × Q38.50'), findsNothing);
      // Y se puede volver.
      await tester.tap(find.text('Total del mes'));
      await tester.pumpAndSettle();
      expect(find.text('260 × Q38.50'), findsOneWidget);
    });

    testWidgets('Gatorade (receta de 83%, meta 70%) pide revisar su precio; la limonada deja mucho', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.text('Por venta'));
      await tester.pumpAndSettle();
      final bloques = find.byType(Column);
      expect(bloques, findsWidgets);
      expect(find.textContaining('Gatorade'), findsWidgets);
      // 8.33 / 10 = 83%, rojo.
      expect(find.text('83%'), findsOneWidget);
      // Limonada: 1.80 / 15 = 12%, verde.
      expect(find.text('12%'), findsOneWidget);
    });

    testWidgets('cada lista trae como mucho cinco', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.text('Por venta'));
      await tester.pumpAndSettle();
      expect(tester.widgetList(find.text('por venta')).length, lessThanOrEqualTo(10));
    });

    testWidgets('si nadie pasa su meta, el bloque lo dice', (tester) async {
      final menu = AnalisisMenu.armar(
        platillos: [plato('a', 'A', 100, 10), plato('b', 'B', 100, 20)],
        vendidas: UnidadesVendidas({'a|p1': const VentaDePlatillo(5, 0), 'b|p1': const VentaDePlatillo(5, 0)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      await tester.tap(find.text('Por venta'));
      await tester.pumpAndSettle();
      expect(find.text('Ninguno pasa su meta'), findsOneWidget);
    });

    testWidgets('las metas del diseño están a la vista', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Meta de receta:'), findsOneWidget);
      expect(find.textContaining('Comida 35%'), findsOneWidget);
      expect(find.textContaining('Bebida preparada 25%'), findsOneWidget);
      expect(find.textContaining('Reventa 70%'), findsOneWidget);
    });

    testWidgets('la nota de precios, y de lo que no entró', (tester) async {
      await montar(tester, cuerpo(notaPrecios: 'Precios y costos de Chiquimula.'));
      expect(find.textContaining('Precios y costos de Chiquimula.'), findsOneWidget);
      // 5 vendidos sin receta no entran al mapa.
      expect(find.textContaining('5 platillos vendidos no entran'), findsOneWidget);
    });

    testWidgets('si el período es muy grande lo avisa', (tester) async {
      await montar(tester, cuerpo(incompletas: true));
      expect(find.textContaining('más pedidos de los que se leen de una vez'), findsOneWidget);
    });

    testWidgets('la nota de monedas', (tester) async {
      await montar(tester, cuerpo(notaMoneda: 'Acá entran solo las sucursales en Q: X vende en otra moneda.'));
      expect(find.textContaining('Acá entran solo las sucursales en Q'), findsOneWidget);
    });
  });

  group('cuando no hay menú que mostrar', () {
    testWidgets('el año no trae pedidos: lo dice y no inventa un mapa', (tester) async {
      await montar(tester, cuerpo(sinPedidos: true, sinMenu: true));
      expect(find.textContaining('La vista de año no detalla qué platillos se vendieron'), findsOneWidget);
      expect(find.text('Mapa de tu menú'), findsNothing);
    });

    testWidgets('cargando el menú', (tester) async {
      tester.view.physicalSize = const Size(1280, 5200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: kInicioBg, body: cuerpo(sinMenu: true, cargando: true))));
      await tester.pump();
      expect(find.text('Cargando tu menú…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error del menú con "Reintentar"', (tester) async {
      var n = 0;
      await montar(tester, cuerpo(sinMenu: true, error: 'Sin conexión con el servidor.', alReintentar: () => n++));
      expect(find.text('Sin conexión con el servidor.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(n, 1);
    });

    testWidgets('el resto del reporte sigue ahí aunque el menú falle', (tester) async {
      await montar(tester, cuerpo(sinMenu: true, error: 'Sin conexión.'));
      expect(find.text('Utilidad operativa'), findsOneWidget);
      expect(find.text('Costo de comida'), findsOneWidget);
    });

    testWidgets('nada vendido con receta', (tester) async {
      await montar(tester, cuerpo(menu: AnalisisMenu.vacio));
      expect(find.textContaining('No hay platillos vendidos con receta'), findsOneWidget);
    });

    testWidgets('vendidos, pero ninguno con costo completo', (tester) async {
      final menu = AnalisisMenu.armar(
        platillos: [plato('a', 'A', 10, -1)],
        vendidas: UnidadesVendidas({'a|p1': const VentaDePlatillo(5, 50)}, 0),
      );
      await montar(tester, cuerpo(menu: menu));
      expect(find.text('Completa estas recetas primero'), findsOneWidget);
      expect(find.textContaining('Ningún platillo vendido tiene el costo completo'), findsOneWidget);
      expect(find.text('Mapa de tu menú'), findsNothing);
    });
  });

  group('lo que sigue diciéndose', () {
    testWidgets('fuera de la cuenta: caja, preproducción, compras y despensa', (tester) async {
      await montar(tester, cuerpo(d: datos(efectivo: 1500, cargadoPrepro: 300, restadoPrepro: 300)));
      expect(find.text('Fuera de la cuenta'), findsOneWidget);
      expect(find.text('Pagado en efectivo desde caja'), findsOneWidget);
      expect(find.text('Cargado a la preproducción'), findsOneWidget);
      expect(find.text('Invertido en compras'), findsOneWidget);
      expect(find.text('Q42,000.00'), findsOneWidget);
      expect(find.text('Valor de tu despensa hoy'), findsOneWidget);
      expect(find.text('Q95,000.50'), findsOneWidget);
    });

    testWidgets('sin efectivo ni preproducción esas filas no están', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Pagado en efectivo desde caja'), findsNothing);
      expect(find.text('Cargado a la preproducción'), findsNothing);
    });

    testWidgets('el aviso de la preproducción', (tester) async {
      await montar(tester, cuerpo(prepro: const AvisoPreproduccion('Revisa la preproducción', ['Luz: se cargó Q80.00 a la preproducción.'])));
      expect(find.text('Revisa la preproducción'), findsOneWidget);
      expect(find.textContaining('Luz: se cargó Q80.00'), findsOneWidget);
    });

    testWidgets('el acceso a la utilidad por platillo se toca', (tester) async {
      var n = 0;
      await montar(tester, cuerpo(alUtilidad: () => n++));
      await tester.tap(find.text('Utilidad por platillo'));
      expect(n, 1);
    });

    testWidgets('sin acceso a esa pantalla no hay fila', (tester) async {
      await montar(tester, cuerpo(conUtilidad: false));
      expect(find.text('Utilidad por platillo'), findsNothing);
    });
  });

  group('cabe en cualquier pantalla (cualquier overflow falla la prueba)', () {
    const tamanos = [Size(320, 6800), Size(360, 6800), Size(390, 6800), Size(700, 5200), Size(800, 5200), Size(1280, 5200)];
    for (final tam in tamanos) {
      for (final escala in const [1.0, 1.4]) {
        testWidgets('${tam.width.toInt()} de ancho, letra ×$escala', (tester) async {
          await montar(
            tester,
            cuerpo(comp: comparacion(), sinFijos: const ['La Reforma'], d: datos(conCosto: 50, sinCosto: 50, efectivo: 100, cargadoPrepro: 50, restadoPrepro: 10)),
            size: tam,
            escala: escala,
          );
          expect(find.text('Mapa de tu menú'), findsOneWidget);
          await tester.ensureVisible(find.text('Por venta'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Por venta'));
          await tester.pumpAndSettle();
          expect(find.text('Revisa su precio'), findsOneWidget);
        });
      }
    }

    testWidgets('montos enormes y nombres larguísimos no revientan', (tester) async {
      final platillos = [
        plato('x', 'Un platillo con un nombre larguísimo que no cabe en ninguna pantalla de teléfono del mundo', 123456, 100, pres: 'Presentación igual de larga que el nombre del platillo'),
        plato('y', 'Otro', 10, 1),
      ];
      final menu = AnalisisMenu.armar(
        platillos: platillos,
        vendidas: UnidadesVendidas({'x|p1': const VentaDePlatillo(987654, 0), 'y|p1': const VentaDePlatillo(3, 0)}, 0),
      );
      final grande = datos(ventas: 98765432101, cogs: 12345678901, gastos: [fijo('renta', 'Una categoría de gasto con un nombre muy pero muy largo', 5432109876)], sueldos: 0);
      await montar(tester, cuerpo(d: grande, menu: menu, comp: comparacion()), size: const Size(360, 6800));
      await tester.ensureVisible(find.text('Por venta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Por venta'));
      await tester.pumpAndSettle();
      expect(find.text('Mapa de tu menú'), findsOneWidget);
    });
  });

  group('dentro del cambio de sucursal', () {
    for (final tam in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets('con poco que mostrar el contenido arranca arriba, no al medio ($tam)', (tester) async {
        tester.view.physicalSize = tam;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: kInicioBg,
            body: Column(
              children: [
                const SizedBox(height: 100),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: const ValueKey('todas'),
                      child: RefreshIndicator(onRefresh: () async {}, child: cuerpo(sinMenu: true, error: 'x')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('En octubre ganaste')).dy, lessThan(260));
      });
    }
  });
}
