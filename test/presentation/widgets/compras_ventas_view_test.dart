import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/compras_ventas.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/data/models/rentabilidad_calculo.dart';
import 'package:saborpro_reports/presentation/widgets/compras_ventas_view.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';

/// Compras vs Ventas sin Firebase: la pantalla real le pasa los números ya armados.
/// Los datos son los del diseño (compras-ventas.html): 3 sucursales, Q373,981
/// vendidos con Q115,934 de costo, Q124,600 comprados, la bodega pasó de Q11,500 a
/// Q20,166. Cualquier "RenderFlex overflowed" hace fallar la prueba por sí sola.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  final octubre = DateRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31, 23, 59, 59), mode: PeriodMode.month);

  ProfitabilityData datos({double ventas = 373981, double cogs = 115934, double compras = 124600, int conCosto = 100, int sinCosto = 0, int estimados = 0}) => ProfitabilityData(
        netSales: ventas,
        cogs: cogs,
        itemsConCosto: conCosto,
        itemsEstimados: estimados,
        itemsSinCosto: sinCosto,
        expenses: const [],
        payroll: 0,
        paidFromCash: 0,
        purchases: compras,
        inventoryValue: 0,
        ingredientesSinPrecio: 0,
      );

  BodegaVista bodegaCompleta({double ini = 11500, double fin = 20166, bool hoy = false, int sinPrecio = 0, List<String> imposibles = const []}) => BodegaVista(
        estado: DatoBodega.completo,
        ecuacion: EcuacionBodega(tenias: ini, compraste: 124600, usaste: 115934, teQueda: fin),
        fin: fin,
        finEsHoy: hoy,
        sinPrecio: sinPrecio,
        imposibles: imposibles,
      );

  // Por sucursal: (id, nombre, compras, ventas, costo, inicio, fin).
  const sucs = [
    ('ch', 'Chiquimula', 35900.0, 118420.0, 36710.0, 2600.0, 1790.0),
    ('lr', 'La Reforma', 28400.0, 102350.0, 33775.0, 6800.0, 1425.0),
    ('sr', 'Santa Rosalia', 60300.0, 153211.0, 45449.0, 2100.0, 16951.0),
  ];

  List<FilaSucursalCV> filasSucursal() => FilaSucursalCV.armar(
        porSucursal: {for (final s in sucs) s.$1: datos(ventas: s.$4, cogs: s.$5, compras: s.$3)},
        sucursales: [for (final s in sucs) (s.$1, s.$2)],
        bodega: BodegaPeriodo(
          inicio: 11500,
          fin: 20166,
          inicioPorSucursal: {for (final s in sucs) s.$1: s.$6},
          finPorSucursal: {for (final s in sucs) s.$1: s.$7},
        ),
      );

  // Categorías: (nombre, inicial, compras, queda, vendiste si es reventa).
  const cats = [
    ('Cerveza', 4200.0, 38200.0, 6800.0, 72400.0),
    ('Gaseosas y agua', 2100.0, 21500.0, 4300.0, 33800.0),
    ('Licores', 800.0, 9400.0, 2600.0, 21000.0),
    ('Carnes', 1800.0, 31800.0, 2100.0, null),
    ('Abarrotes', 2300.0, 14300.0, 3900.0, null),
    ('Verduras y frutas', 300.0, 9400.0, 466.0, null),
  ];

  CategoriasCV categorias() => CategoriasCV.armar(
        porIngrediente: {for (final c in cats) c.$1: ParCosto(c.$2 + c.$3 - c.$4, c.$3)},
        categoriaDe: {for (final c in cats) c.$1: c.$1},
        reventaPorIngrediente: {for (final c in cats) if (c.$5 != null) c.$1: c.$5!},
        bodegaPorCategoria: {for (final c in cats) claveDeCategoria(c.$1): CategoriaValor(c.$1, c.$4)},
        ventasTotales: 373981,
      );

  List<SemanaCV> semanas() {
    const wv = [.12, .22, .22, .23, .21];
    const wc = [.25, .14, .30, .10, .21];
    const rangos = [(1, 4), (5, 11), (12, 18), (19, 25), (26, 31)];
    return [
      for (var i = 0; i < 5; i++)
        SemanaCV(
          numero: i + 1,
          desde: DateTime(2026, 10, rangos[i].$1),
          hasta: DateTime(2026, 10, rangos[i].$2),
          vendiste: wv[i] * 373981,
          compraste: wc[i] * 124600,
          usaste: wv[i] * 115934,
        ),
    ];
  }

  Widget cuerpo({
    ProfitabilityData? d,
    BodegaVista? bodega,
    bool conSucursales = true,
    bool conCategorias = true,
    bool conSemanas = true,
    bool incompleta = false,
    DateRange? rango,
    ValueChanged<String>? alElegir,
    VoidCallback? alRentabilidad,
  }) =>
      ComprasVentasBody(
        datos: d ?? datos(),
        rango: rango ?? octubre,
        signo: 'Q',
        bodega: bodega ?? bodegaCompleta(),
        sucursales: conSucursales ? filasSucursal() : const [],
        categorias: conCategorias ? categorias() : CategoriasCV.vacia,
        semanas: conSemanas ? semanas() : const [],
        lecturaIncompleta: incompleta,
        onElegirSucursal: alElegir,
        onVerRentabilidad: alRentabilidad,
      );

  Future<void> montar(WidgetTester tester, Widget c, {Size size = const Size(1280, 4200), double escala = 1.0}) async {
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

  const telefono = Size(360, 6400);

  group('¿cuánto ganaste?', () {
    testWidgets('vendiste − lo que usaste = ganaste, igual que la utilidad bruta de Rentabilidad', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Ganaste con tu mercadería'), findsOneWidget);
      // 373,981 − 115,934.
      expect(find.text('Q258,047'), findsWidgets);
      expect(find.text('Vendiste'), findsWidgets);
      expect(find.text('Q373,981'), findsWidgets);
      expect(find.text('Lo que usaste para venderlo'), findsOneWidget);
      expect(find.text('Q115,934'), findsWidgets);
      expect(find.text('Ganaste'), findsOneWidget);
    });

    testWidgets('por cada Q1 de mercadería, cuánto se vendió', (tester) async {
      await montar(tester, cuerpo());
      // 373,981 / 115,934 = 3.2259.
      expect(find.textContaining('vendiste Q3.23'), findsOneWidget);
    });

    testWidgets('aclara que no es la ganancia final y manda a Rentabilidad', (tester) async {
      var n = 0;
      await montar(tester, cuerpo(alRentabilidad: () => n++));
      expect(find.textContaining('Esto no es tu ganancia final.'), findsOneWidget);
      expect(find.textContaining('renta, sueldos, luz, agua, internet'), findsOneWidget);
      await tester.tap(find.text('Ver ganancia real en Rentabilidad'));
      expect(n, 1);
    });

    testWidgets('sin acceso a Rentabilidad no hay enlace', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Ver ganancia real en Rentabilidad'), findsNothing);
    });

    testWidgets('si se perdió, lo dice y va en rojo', (tester) async {
      await montar(tester, cuerpo(d: datos(ventas: 1000, cogs: 4000, compras: 3000)));
      expect(find.text('Perdiste con tu mercadería'), findsOneWidget);
      expect(find.text('Perdiste'), findsOneWidget);
      final t = tester.widget<Text>(find.text('Q3,000').first);
      expect(t.style?.color, InicioColores.bad);
    });

    testWidgets('sin costo no hay "por cada Q1" (no se divide entre cero)', (tester) async {
      await montar(tester, cuerpo(d: datos(cogs: 0, conCosto: 0, sinCosto: 0)));
      expect(find.textContaining('Por cada'), findsNothing);
    });

    testWidgets('con poca cobertura del costo avisa que lo ganado sale mayor de lo real', (tester) async {
      await montar(tester, cuerpo(d: datos(conCosto: 40, sinCosto: 60)));
      expect(find.textContaining('Solo 40.0% de lo que vendiste tiene costo'), findsOneWidget);
    });

    testWidgets('si el costo es de precios de hoy lo dice', (tester) async {
      await montar(tester, cuerpo(d: datos(conCosto: 40, estimados: 60)));
      expect(find.textContaining('precios de compra de hoy'), findsOneWidget);
    });

    testWidgets('un costo bueno no trae aviso', (tester) async {
      await montar(tester, cuerpo());
      expect(find.textContaining('tiene costo'), findsNothing);
      expect(find.textContaining('precios de compra de hoy'), findsNothing);
    });
  });

  group('¿cuánto te queda?', () {
    testWidgets('la cuenta completa: tenías + compraste − usaste = te queda', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Te queda en bodega'), findsOneWidget);
      expect(find.text('Q20,166'), findsWidgets);
      expect(find.text('Tenías el 1 de octubre'), findsOneWidget);
      expect(find.text('Q11,500'), findsWidgets);
      expect(find.text('Compraste'), findsWidgets);
      expect(find.text('Q124,600'), findsWidgets);
      expect(find.text('Usaste'), findsWidgets);
      expect(find.text('Te queda'), findsOneWidget);
      // Cuadra: no hay fila de merma.
      expect(find.text('Merma, ajustes y precios'), findsNothing);
    });

    testWidgets('si creció, avisa que es plata parada', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Tu bodega creció Q8,666'), findsOneWidget);
      expect(find.textContaining('ese dinero está parado en bodega'), findsOneWidget);
    });

    testWidgets('si bajó, avisa que pronto habrá que comprar', (tester) async {
      await montar(tester, cuerpo(bodega: BodegaVista(
        estado: DatoBodega.completo,
        ecuacion: const EcuacionBodega(tenias: 20000, compraste: 100000, usaste: 120000, teQueda: 5000),
        fin: 5000,
      )));
      expect(find.text('Tu bodega bajó Q15,000'), findsOneWidget);
      expect(find.textContaining('pronto tendrás que comprar'), findsOneWidget);
    });

    testWidgets('si quedó casi igual, lo dice', (tester) async {
      await montar(tester, cuerpo(bodega: BodegaVista(
        estado: DatoBodega.completo,
        ecuacion: const EcuacionBodega(tenias: 10000, compraste: 50000, usaste: 50000, teQueda: 10100),
        fin: 10100,
      )));
      expect(find.text('Tu bodega quedó igual'), findsOneWidget);
    });

    testWidgets('lo que la cuenta no explica sale aparte, con su explicación', (tester) async {
      // 11,500 + 124,600 − 115,934 = 20,166; hay 19,866: salieron 300 más.
      await montar(tester, cuerpo(bodega: bodegaCompleta(fin: 19866)));
      expect(find.text('Merma, ajustes y precios'), findsOneWidget);
      expect(find.text('salió más de lo que vendiste'), findsOneWidget);
      expect(find.text('Q300'), findsOneWidget);
    });

    testWidgets('si entró más de lo comprado, la fila dice lo contrario', (tester) async {
      await montar(tester, cuerpo(bodega: bodegaCompleta(fin: 20466)));
      expect(find.text('Ajustes y precios'), findsOneWidget);
      expect(find.text('entró más de lo que compraste'), findsOneWidget);
    });

    testWidgets('en un mes abierto, "Te queda" es de hoy', (tester) async {
      await montar(tester, cuerpo(bodega: bodegaCompleta(hoy: true)));
      expect(find.text('Te queda en bodega hoy'), findsOneWidget);
      expect(find.text('Te queda hoy'), findsOneWidget);
    });

    testWidgets('solo con el valor de hoy: no se inventa lo de antes', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(estado: DatoBodega.soloFin, fin: 900, finEsHoy: true)));
      expect(find.text('Q900'), findsWidgets);
      expect(find.textContaining('Todavía no hay foto del 1 de octubre'), findsOneWidget);
      expect(find.text('Tenías el 1 de octubre'), findsNothing);
      expect(find.textContaining('Tu bodega creció'), findsNothing);
    });

    testWidgets('sin fotos del mes: lo explica y el número es "—"', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(estado: DatoBodega.sinFotos)));
      expect(find.textContaining('Todavía no hay foto de tu bodega de ese mes'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('si la lectura de la foto falló, lo dice y no se queda "leyendo"', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(estado: DatoBodega.noSePudo, fallo: true)));
      expect(find.textContaining('No se pudo leer la foto de tu bodega de ese mes'), findsOneWidget);
      expect(find.textContaining('Desliza hacia abajo para reintentar'), findsOneWidget);
      expect(find.text('Leyendo tu bodega…'), findsNothing);
      expect(find.textContaining('Todavía no hay foto'), findsNothing);
    });

    testWidgets('con la bodega de hoy pero sin poder leer la foto del inicio, también lo dice', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(estado: DatoBodega.soloFin, fin: 900, finEsHoy: true, fallo: true)));
      expect(find.textContaining('No se pudo leer la foto del 1 de octubre'), findsOneWidget);
      expect(find.textContaining('Todavía no hay foto del 1 de octubre'), findsNothing);
    });

    testWidgets('una foto tomada mucho después del día 1 se marca como aproximada', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(
        estado: DatoBodega.completo,
        ecuacion: EcuacionBodega(tenias: 11500, compraste: 124600, usaste: 115934, teQueda: 20166),
        fin: 20166,
        aproximada: true,
      )));
      expect(find.textContaining('se tomó bastante después del día 1'), findsOneWidget);
      expect(find.textContaining('no es exacta'), findsOneWidget);
    });

    testWidgets('lo comprado que queda fuera de la cuenta de la bodega se explica', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(
        estado: DatoBodega.completo,
        ecuacion: EcuacionBodega(tenias: 11500, compraste: 100000, usaste: 90000, teQueda: 21500),
        fin: 21500,
        comprasFuera: 24600,
      )));
      expect(find.textContaining('"Compraste" suma Q24,600 más que esta cuenta'), findsOneWidget);
      expect(find.textContaining('bodega central'), findsWidgets);
    });

    testWidgets('sin diferencia no hay nota', (tester) async {
      await montar(tester, cuerpo());
      expect(find.textContaining('suma Q'), findsNothing);
      expect(find.textContaining('se tomó bastante después'), findsNothing);
    });

    testWidgets('fuera de un mes pide elegir uno', (tester) async {
      await montar(tester, cuerpo(bodega: const BodegaVista(estado: DatoBodega.noAplica)));
      expect(find.textContaining('Elige un mes'), findsOneWidget);
    });

    testWidgets('mientras lee, un "Leyendo tu bodega…"', (tester) async {
      tester.view.physicalSize = const Size(1280, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: kInicioBg, body: cuerpo(bodega: const BodegaVista(estado: DatoBodega.cargando)))));
      await tester.pump();
      expect(find.text('Leyendo tu bodega…'), findsOneWidget);
    });

    testWidgets('avisa de las existencias que no se pudieron valorar', (tester) async {
      await montar(tester, cuerpo(bodega: bodegaCompleta(sinPrecio: 3, imposibles: ['Pollo', 'Sal', 'Azúcar', 'Harina'])));
      expect(find.textContaining('3 ingrediente(s) con existencia pero sin precio'), findsOneWidget);
      expect(find.textContaining('Pollo, Sal, Azúcar y 1 más'), findsOneWidget);
    });
  });

  group('por sucursal', () {
    testWidgets('los montos de cada sucursal', (tester) async {
      await montar(tester, cuerpo(alElegir: (_) {}));
      expect(find.text('Por sucursal'), findsOneWidget);
      expect(find.text('Toca una sucursal para ver su detalle'), findsOneWidget);
      // Chiquimula: compró 35,900 · vendió 118,420 · ganó 81,710 · le queda 1,790.
      expect(find.text('Q35,900'), findsOneWidget);
      expect(find.text('Q118,420'), findsOneWidget);
      expect(find.text('Q81,710'), findsOneWidget);
      expect(find.text('Q1,790'), findsWidgets);
      // Santa Rosalia: ganó 153,211 − 45,449 = 107,762.
      expect(find.text('Q107,762'), findsOneWidget);
      // El total.
      expect(find.text('Total'), findsWidgets);
      expect(find.text('Q124,600'), findsWidgets);
    });

    testWidgets('qué pasó con la bodega de cada una', (tester) async {
      await montar(tester, cuerpo(alElegir: (_) {}));
      // Chiquimula bajó Q810, menos del 3% de lo que compró (Q1,077): igual.
      expect(find.text('= igual'), findsOneWidget);
      // La Reforma bajó Q5,375; Santa Rosalia creció Q14,851.
      expect(find.text('Q5,375'), findsOneWidget);
      expect(find.text('Q14,851'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('si el héroe suma más que las filas (central, sucursales ocultas), lo explica', (tester) async {
      // Las tres filas suman 373,981 vendidos y 124,600 comprados; el total de arriba trae más.
      await montar(tester, cuerpo(d: datos(ventas: 373981 + 5000, compras: 124600 + 2000), alElegir: (_) {}));
      expect(find.textContaining('Los totales de arriba también suman Q5,000 vendidos y Q2,000 comprados'), findsOneWidget);
      expect(find.textContaining('no están en estas filas'), findsOneWidget);
    });

    testWidgets('si coinciden, no hay nota', (tester) async {
      await montar(tester, cuerpo(alElegir: (_) {}));
      expect(find.textContaining('Los totales de arriba también suman'), findsNothing);
    });

    testWidgets('tocar una sucursal la abre', (tester) async {
      String? elegida;
      await montar(tester, cuerpo(alElegir: (id) => elegida = id));
      await tester.tap(find.text('La Reforma'));
      expect(elegida, 'lr');
    });

    testWidgets('sin la pista de tocar si nadie escucha', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Toca una sucursal para ver su detalle'), findsNothing);
    });

    testWidgets('con una sola sucursal (o en su pestaña) no hay tabla', (tester) async {
      await montar(tester, cuerpo(conSucursales: false, alElegir: (_) {}));
      expect(find.text('Por sucursal'), findsNothing);
    });

    testWidgets('sin foto, "Le queda" y la bodega son "—"', (tester) async {
      final filas = FilaSucursalCV.armar(
        porSucursal: {'ch': datos(ventas: 1000, cogs: 300, compras: 800), 'lr': datos(ventas: 500, cogs: 200, compras: 100)},
        sucursales: const [('ch', 'Chiquimula'), ('lr', 'La Reforma')],
        bodega: BodegaPeriodo.vacia,
      );
      await montar(tester, ComprasVentasBody(datos: datos(), rango: octubre, signo: 'Q', bodega: const BodegaVista(estado: DatoBodega.sinFotos), sucursales: filas));
      expect(find.text('—'), findsWidgets);
      expect(find.text('Q700'), findsOneWidget);
    });

    testWidgets('en el teléfono cada sucursal es una tarjeta con sus rótulos', (tester) async {
      await montar(tester, cuerpo(alElegir: (_) {}), size: telefono);
      // Las tres sucursales y la fila del total.
      expect(find.text('COMPRÓ'), findsNWidgets(4));
      expect(find.text('VENDIÓ'), findsNWidgets(4));
      expect(find.text('GANÓ*'), findsNWidgets(4));
      expect(find.text('LE QUEDA'), findsNWidgets(4));
    });
  });

  group('¿en qué compraste y cuánto ganaste?', () {
    testWidgets('lo que se revende se ve directo', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('¿En qué compraste y cuánto ganaste?'), findsOneWidget);
      expect(find.text('Cerveza'), findsOneWidget);
      // Cerveza usó 4,200 + 38,200 − 6,800 = 35,600 y vendió 72,400: ganó 36,800.
      expect(find.text('Q38,200'), findsOneWidget);
      expect(find.text('Q72,400'), findsOneWidget);
      expect(find.text('Q36,800'), findsOneWidget);
      expect(find.text('por cada Q1 vendiste Q2.03'), findsOneWidget);
      expect(find.text('Gaseosas y agua'), findsOneWidget);
      expect(find.text('Licores'), findsOneWidget);
    });

    testWidgets('los insumos de cocina van juntos en "Platillos" y se abren', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Platillos'), findsOneWidget);
      expect(find.text('carnes, abarrotes, verduras'), findsOneWidget);
      // Vendió 373,981 − 127,200 de reventa = 246,781 y usó 53,434: ganó 193,347.
      expect(find.text('Q246,781'), findsOneWidget);
      expect(find.text('Q193,347'), findsOneWidget);
      // Cerrado: no se ven los insumos.
      expect(find.text('Carnes'), findsNothing);
      expect(find.text('en platillos'), findsNothing);

      await tester.tap(find.text('Platillos'));
      await tester.pumpAndSettle();
      expect(find.text('Carnes'), findsOneWidget);
      expect(find.text('Abarrotes'), findsOneWidget);
      expect(find.text('Verduras y frutas'), findsOneWidget);
      expect(find.text('en platillos'), findsNWidgets(3));

      await tester.tap(find.text('Platillos'));
      await tester.pumpAndSettle();
      expect(find.text('Carnes'), findsNothing);
    });

    testWidgets('el total cierra con la venta y la ganancia de arriba', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Q373,981'), findsWidgets);
      expect(find.text('Q258,047'), findsWidgets);
      // Te queda: lo mismo de la bodega.
      expect(find.text('Q20,166'), findsWidgets);
    });

    testWidgets('sin la bodega, "Te queda" es "—" en todas las filas', (tester) async {
      final sin = CategoriasCV.armar(
        porIngrediente: {for (final c in cats) c.$1: ParCosto(c.$2 + c.$3 - c.$4, c.$3)},
        categoriaDe: {for (final c in cats) c.$1: c.$1},
        reventaPorIngrediente: {for (final c in cats) if (c.$5 != null) c.$1: c.$5!},
        bodegaPorCategoria: null,
        ventasTotales: 373981,
      );
      await montar(tester, ComprasVentasBody(datos: datos(), rango: octubre, signo: 'Q', bodega: const BodegaVista(estado: DatoBodega.sinFotos), categorias: sin));
      expect(find.text('Q6,800'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('sin categorías la tarjeta no aparece', (tester) async {
      await montar(tester, cuerpo(conCategorias: false));
      expect(find.text('¿En qué compraste y cuánto ganaste?'), findsNothing);
    });

    testWidgets('en el teléfono cada producto es una tarjeta con sus rótulos', (tester) async {
      await montar(tester, cuerpo(), size: telefono);
      expect(find.text('COMPRASTE'), findsWidgets);
      expect(find.text('VENDISTE'), findsWidgets);
      expect(find.text('GANASTE'), findsWidgets);
    });
  });

  group('si la lectura quedó corta', () {
    testWidgets('lo avisa arriba, donde duele: ganaste se ve mayor de lo real', (tester) async {
      await montar(tester, cuerpo(incompleta: true));
      expect(find.textContaining('más movimientos de inventario de los que se leen de una vez'), findsOneWidget);
      expect(find.textContaining('sobre todo en las últimas semanas'), findsOneWidget);
      // Sale encima de todo lo demás, no escondido en una tabla.
      expect(tester.getTopLeft(find.textContaining('más movimientos de inventario')).dy, lessThan(tester.getTopLeft(find.text('Por sucursal')).dy));
    });

    testWidgets('sale aunque no haya tabla de categorías (el menú no cargó o es la vista de año)', (tester) async {
      await montar(tester, cuerpo(incompleta: true, conCategorias: false, conSucursales: false, conSemanas: false));
      expect(find.textContaining('más movimientos de inventario de los que se leen de una vez'), findsOneWidget);
    });

    testWidgets('si no, no hay aviso', (tester) async {
      await montar(tester, cuerpo());
      expect(find.textContaining('más movimientos de inventario'), findsNothing);
    });
  });

  group('semana por semana', () {
    testWidgets('cinco semanas con sus fechas, y lo que se ganó en cada una', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Semana por semana'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('Sem $i'), findsOneWidget);
      }
      expect(find.textContaining('1 – 4'), findsWidgets);
      expect(find.textContaining('26 – 31'), findsWidgets);
      // Semana 1: vendió 12% de 373,981 y usó 12% de 115,934: ganó 30,966.
      expect(find.text('+31.0k'), findsOneWidget);
      expect(find.text('Vendiste'), findsWidgets);
      expect(find.text('Compraste'), findsWidgets);
    });

    testWidgets('el detalle por semana y su total', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Detalle por semana'), findsOneWidget);
      expect(find.text('Semana 1'), findsOneWidget);
      expect(find.text('Total octubre'), findsOneWidget);
      // Sumas: lo vendido, comprado, usado y ganado del mes.
      expect(find.text('Q373,981'), findsWidgets);
      expect(find.text('Q124,600'), findsWidgets);
      expect(find.text('Q115,934'), findsWidgets);
    });

    testWidgets('una semana que perdió va en rojo', (tester) async {
      final s = [SemanaCV(numero: 1, desde: DateTime(2026, 10, 1), hasta: DateTime(2026, 10, 4), vendiste: 100, compraste: 50, usaste: 400)];
      await montar(tester, ComprasVentasBody(datos: datos(), rango: octubre, signo: 'Q', bodega: bodegaCompleta(), semanas: s));
      expect(find.text('−0.3k'), findsNothing);
      expect(find.text('−300'), findsOneWidget);
    });

    testWidgets('sin semanas (no es un mes) no hay gráfica ni detalle', (tester) async {
      await montar(tester, cuerpo(conSemanas: false));
      expect(find.text('Semana por semana'), findsNothing);
      expect(find.text('Detalle por semana'), findsNothing);
    });

    testWidgets('en el teléfono se esconden los números sobre las barras', (tester) async {
      await montar(tester, cuerpo(), size: telefono);
      expect(find.text('Semana por semana'), findsOneWidget);
      // En ancho, el 12% de 373,981 sale sobre su barra ("45k").
      expect(find.text('45k'), findsNothing);
      await montar(tester, cuerpo());
      expect(find.text('45k'), findsOneWidget);
    });
  });

  group('el pie', () {
    testWidgets('aclara que las ganancias son antes de gastos fijos y qué es cada cosa', (tester) async {
      await montar(tester, cuerpo());
      expect(find.textContaining('*Todas las ganancias de este reporte son antes de gastos fijos'), findsOneWidget);
      expect(find.textContaining('"Usaste" = el costo de lo que vendiste'), findsOneWidget);
      expect(find.textContaining('foto de tu bodega que se toma el día 1 de cada mes'), findsOneWidget);
    });
  });

  group('cabe en cualquier pantalla (cualquier overflow falla la prueba)', () {
    const tamanos = [Size(320, 7600), Size(360, 7000), Size(390, 7000), Size(700, 5200), Size(800, 5200), Size(1280, 4200)];
    for (final tam in tamanos) {
      for (final escala in const [1.0, 1.4]) {
        testWidgets('${tam.width.toInt()} de ancho, letra ×$escala', (tester) async {
          await montar(tester, cuerpo(alElegir: (_) {}, alRentabilidad: () {}, bodega: bodegaCompleta(fin: 19866, sinPrecio: 2, imposibles: ['Pollo']), incompleta: true, d: datos(conCosto: 50, sinCosto: 50)), size: tam, escala: escala);
          expect(find.text('Ganaste con tu mercadería'), findsOneWidget);
          await tester.ensureVisible(find.text('Platillos'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Platillos'));
          await tester.pumpAndSettle();
          expect(find.text('Carnes'), findsOneWidget);
        });
      }
    }

    testWidgets('montos enormes y nombres larguísimos no revientan', (tester) async {
      final grande = datos(ventas: 98765432101, cogs: 12345678901, compras: 54321098765);
      final filas = FilaSucursalCV.armar(
        porSucursal: {'x': grande},
        sucursales: const [('x', 'Una sucursal con un nombre larguísimo que no cabe en ninguna pantalla de teléfono'), ],
        bodega: const BodegaPeriodo(inicioPorSucursal: {'x': 1e11}, finPorSucursal: {'x': 3e11}, inicio: 1e11, fin: 3e11),
      );
      final cs = CategoriasCV.armar(
        porIngrediente: {'a': const ParCosto(1e10, 2e10), 'b': const ParCosto(1e9, 5e9)},
        categoriaDe: const {'a': 'Una categoría con un nombre larguísimo que tampoco cabe en ningún teléfono', 'b': 'Otra categoría igual de larga para probar que cabe bien'},
        reventaPorIngrediente: const {'a': 5e10},
        bodegaPorCategoria: null,
        ventasTotales: 98765432101,
      );
      await montar(
        tester,
        ComprasVentasBody(datos: grande, rango: octubre, signo: 'Q', bodega: bodegaCompleta(ini: 1e11, fin: 3e11), sucursales: [...filas, ...filas], categorias: cs, semanas: semanas(), onElegirSucursal: (_) {}),
        size: const Size(360, 7000),
      );
      expect(find.text('Ganaste con tu mercadería'), findsOneWidget);
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
                      child: RefreshIndicator(
                        onRefresh: () async {},
                        child: cuerpo(conSucursales: false, conCategorias: false, conSemanas: false, bodega: const BodegaVista(estado: DatoBodega.noAplica)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Ganaste con tu mercadería')).dy, lessThan(260));
      });
    }
  });
}
