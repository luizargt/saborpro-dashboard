import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/cierres_caja.dart';
import 'package:saborpro_reports/presentation/widgets/cierres_caja_view.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';

/// El historial de cierres sin Firebase: la pantalla real le pasa los cortes ya
/// contados. Los números son los del diseño (cierres-caja.html): Ana Cosme con su
/// faltante de Q385 y Juan Carlos que cuadró. Cualquier "RenderFlex overflowed"
/// hace fallar la prueba por sí sola.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  const sucursal = 'Restaurante Lena’s Atlantis';
  final ahora = DateTime(2026, 11, 21, 8, 52);

  CashRegisterSummary ana({Map<String, dynamic> extra = const {}}) => CashRegisterSummary.fromMap({
        'id': 'cr-ana',
        'userId': 'u-ana',
        'userName': 'Ana Cosme',
        'status': 'closed',
        'locationId': 'gt',
        'openedAt': Timestamp.fromDate(DateTime(2026, 11, 20, 18)),
        'closedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 1, 25)),
        'initialCash': 2000.0,
        'actualCash': 4149.0,
        'differenceCash': -385.0,
        'actualCard': 9635.5,
        'differenceCard': 0.0,
        'closingNotes': 'Efectivo (faltante Q385.00): se le dio pagado a una cuenta de guía cortesía',
        ...extra,
      }).copyWith(locationName: sucursal);

  CashRegisterSummary juan() => CashRegisterSummary.fromMap({
        'id': 'cr-juan',
        'userId': 'u-juan',
        'userName': 'Juan Carlos Ixtan',
        'status': 'closed',
        'locationId': 'gt',
        'openedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 7)),
        'closedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 15, 5)),
        'initialCash': 1000.0,
        'actualCash': 1879.0,
        'differenceCash': 0.0,
        'actualCard': 4830.5,
        'differenceCard': 0.0,
        'movements': [
          {'type': 'withdrawal', 'amount': 500},
        ],
      }).copyWith(locationName: sucursal);

  CashRegisterSummary abierta(String id, String nombre, DateTime desde, {String loc = 'gt'}) => CashRegisterSummary(
        id: id,
        userId: id,
        userName: nombre,
        status: 'open',
        openedAt: desde,
        locationId: loc,
        locationName: sucursal,
      );

  CierreCaja cierre(CashRegisterSummary r, {String signo = 'Q'}) => CierreCaja.desde(r, const [], signo: signo);

  final marta = abierta('m', 'Marta Ajiquichi', DateTime(2026, 11, 21, 8, 2));
  final vieja = abierta('v', 'Ana Lena Katt', DateTime(2026, 11, 12, 21, 3));

  final tocados = <CierreCaja>[];
  setUp(tocados.clear);

  Widget cuerpo({
    List<CierreCaja>? cierres,
    List<CashRegisterSummary>? abiertas,
    String Function(String?)? signo,
    Widget? Function(CashRegisterSummary)? accion,
  }) =>
      CierresCajaBody(
        cierres: cierres ?? [cierre(ana()), cierre(juan())],
        abiertas: abiertas ?? [marta, vieja],
        signoDeCaja: signo ?? (_) => 'Q',
        ahora: ahora,
        onVerDetalle: tocados.add,
        accionAbierta: accion,
      );

  Future<void> montar(WidgetTester tester, Widget c, {Size size = const Size(360, 3000), double escala = 1.0}) async {
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

  const tamanos = [Size(360, 3000), Size(390, 3000), Size(700, 3000), Size(1280, 3000)];

  group('el resumen', () {
    testWidgets('ventas, diferencia, efectivo y tarjeta y cajas abiertas', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.text('Ventas del período'), findsOneWidget);
      // Ana Q12,169.50 + Juan Q6,209.50.
      expect(find.text('Q18,379.00'), findsOneWidget);
      expect(find.text('2 cierres'), findsOneWidget);
      expect(find.text('Diferencia en caja'), findsOneWidget);
      // En el resumen y en la fila de efectivo de la tabla de Ana.
      expect(find.text('−Q385.00'), findsNWidgets(2));
      expect(find.text('1 cierre con faltante'), findsOneWidget);
      expect(find.text('Efectivo y tarjeta'), findsOneWidget);
      // Efectivo: Q2,534 de Ana + Q879... las ventas en efectivo son Q2,534 y Q1,379.
      expect(find.text('Q3,913.00'), findsOneWidget);
      expect(find.text('Q14,466.00'), findsOneWidget);
      expect(find.text('Cajas abiertas ahora'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1 lleva más de 8 días'), findsOneWidget);
    });

    testWidgets('sin faltantes ni sobrantes dice que cuadró, y con solo un corte dice "1 cierre"', (tester) async {
      await montar(tester, cuerpo(cierres: [cierre(juan())], abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('Cuadró'), findsWidgets);
      expect(find.text('Todos los cierres cuadraron'), findsOneWidget);
      expect(find.text('1 cierre'), findsOneWidget);
      expect(find.text('Ninguna abierta'), findsOneWidget);
    });

    testWidgets('con solo un sobrante, el valor va en ámbar y dice cuántos', (tester) async {
      final sobra = cierre(ana(extra: {'differenceCash': 50.0, 'actualCash': 4584.0}));
      await montar(tester, cuerpo(cierres: [sobra], abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('Q50.00'), findsWidgets);
      expect(find.text('1 cierre con sobrante'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Q50.00').first).style!.color, InicioColores.warn);
    });

    testWidgets('con faltante en un cierre y sobrante en otro no se netean: se dice cada uno', (tester) async {
      final sobra = cierre(ana(extra: {'id': 's', 'userName': 'Marta', 'differenceCash': 50.0, 'actualCash': 4584.0}));
      await montar(tester, cuerpo(cierres: [cierre(ana()), sobra], abiertas: const []), size: const Size(1280, 3000));
      // Lo que faltó (Q385) arriba, sin restarle el sobrante de Q50 del otro cierre.
      expect(find.text('−Q385.00'), findsNWidgets(2));
      expect(find.text('1 cierre con faltante · 1 con sobrante'), findsOneWidget);
    });

    testWidgets('sin cierres no dice "cuadró": no hay qué cuadrar', (tester) async {
      await montar(tester, cuerpo(cierres: const [], abiertas: [marta]), size: const Size(1280, 3000));
      expect(find.text('Sin cierres'), findsWidgets);
      expect(find.text('Cuadró'), findsNothing);
      expect(find.text('—'), findsWidgets);
      expect(find.text('Todo normal'), findsOneWidget);
    });

    testWidgets('un cierre sin contar no se da por cuadrado', (tester) async {
      final sin = cierre(CashRegisterSummary.fromMap({
        'id': 'x',
        'userName': 'Luis',
        'status': 'closed',
        'openedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 7)),
        'closedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 9)),
      }));
      await montar(tester, cuerpo(cierres: [sin], abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('1 sin contar'), findsOneWidget);
      expect(find.text('Sin contar'), findsOneWidget);
      expect(find.text('Cuadró'), findsNothing);
    });

    testWidgets('las cuatro cifras en una fila en 1280 y de dos en dos en 360', (tester) async {
      final etiquetas = ['Ventas del período', 'Diferencia en caja', 'Efectivo y tarjeta', 'Cajas abiertas ahora'];
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect({for (final t in etiquetas) tester.getTopLeft(find.text(t)).dy}, hasLength(1));
      await montar(tester, cuerpo());
      final y = [for (final t in etiquetas) tester.getTopLeft(find.text(t)).dy];
      expect(y[0], y[1]);
      expect(y[2], y[3]);
      expect(y[2], greaterThan(y[0]));
    });
  });

  group('cajas en más de una moneda', () {
    testWidgets('un resumen por moneda, con su rótulo; no se suman quetzales con dólares', (tester) async {
      final sv = cierre(ana(extra: {'id': 'sv1', 'userName': 'Rosa', 'locationId': 'sv', 'differenceCash': 0.0, 'actualCash': 4534.0}), signo: r'$');
      await montar(
        tester,
        cuerpo(
          cierres: [cierre(ana()), sv],
          abiertas: const [],
          signo: (loc) => loc == 'sv' ? r'$' : 'Q',
        ),
        size: const Size(1280, 3600),
      );
      expect(find.text('Cajas en Q'), findsOneWidget);
      expect(find.text(r'Cajas en $'), findsOneWidget);
      expect(find.text('Ventas del período'), findsNWidgets(2));
      expect(find.text('Q12,169.50'), findsWidgets);
      expect(find.text(r'$12,169.50'), findsWidgets);
    });

    testWidgets('con una sola moneda no sale ningún rótulo', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.textContaining('Cajas en '), findsNothing);
    });
  });

  group('el aviso de la caja que nadie cerró', () {
    testWidgets('dice quién y cuánto lleva abierta', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(
        find.textContaining(
          'Ana Lena Katt tiene la caja abierta desde hace 203h 49m. Una caja tan larga mezcla días y no se puede cuadrar bien.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('con varias dice cuántas más hay; sin ninguna, no hay aviso', (tester) async {
      final otra = abierta('o', 'Pablo', DateTime(2026, 11, 19, 8));
      final otra2 = abierta('o2', 'Eva', DateTime(2026, 11, 18, 8));
      await montar(tester, cuerpo(abiertas: [marta, vieja, otra, otra2]), size: const Size(1280, 3000));
      expect(find.textContaining('Hay otras 2 cajas con más de 24 horas abiertas.', findRichText: true), findsOneWidget);
      // La más vieja es la que se nombra.
      expect(find.textContaining('Ana Lena Katt tiene la caja abierta', findRichText: true), findsOneWidget);

      await montar(tester, cuerpo(abiertas: [marta]), size: const Size(1280, 3000));
      expect(find.textContaining('tiene la caja abierta', findRichText: true), findsNothing);
    });
  });

  group('en caja ahora', () {
    testWidgets('quién, desde cuándo, dónde y cuánto lleva', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.text('EN CAJA AHORA'), findsOneWidget);
      expect(find.text('Marta Ajiquichi'), findsOneWidget);
      expect(find.text('Abierta desde las 08:02 AM · $sucursal'), findsOneWidget);
      expect(find.text('50m'), findsOneWidget);
      // La vieja dice el día, no solo la hora.
      expect(find.text('Abierta desde el 12 nov, 09:03 PM · $sucursal'), findsOneWidget);
      expect(find.text('203h 49m'), findsOneWidget);
    });

    testWidgets('la que lleva más de 24 h va en ámbar y la reciente en verde', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(tester.widget<Text>(find.text('203h 49m')).style!.color, InicioColores.warn);
      expect(tester.widget<Text>(find.text('50m')).style!.color, InicioColores.ink);
    });

    testWidgets('en 1280 van de a dos; en 360, una por fila', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(tester.getTopLeft(find.text('Marta Ajiquichi')).dy, closeTo(tester.getTopLeft(find.text('Ana Lena Katt')).dy, 20));
      await montar(tester, cuerpo());
      expect(tester.getTopLeft(find.text('Ana Lena Katt')).dy, greaterThan(tester.getTopLeft(find.text('Marta Ajiquichi')).dy + 40));
    });

    testWidgets('lleva el botón que le pase la pantalla (el cierre forzado, solo al depurar)', (tester) async {
      await montar(
        tester,
        cuerpo(accion: (r) => Icon(Icons.close_rounded, key: ValueKey('cerrar-${r.id}'))),
        size: const Size(1280, 3000),
      );
      expect(find.byKey(const ValueKey('cerrar-m')), findsOneWidget);
      expect(find.byKey(const ValueKey('cerrar-v')), findsOneWidget);
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('sin cajas abiertas no sale la sección', (tester) async {
      await montar(tester, cuerpo(abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('EN CAJA AHORA'), findsNothing);
    });
  });

  group('el cuadre de cada corte', () {
    testWidgets('quién, cuándo, el estado y lo vendido', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.text('CIERRES DEL PERÍODO'), findsOneWidget);
      expect(find.text('Ana Cosme'), findsOneWidget);
      expect(find.text('AC'), findsOneWidget);
      // Ana abrió ayer: dice el día.
      expect(find.text('20 nov · 06:00 PM → 01:25 AM · 7h 25m · $sucursal'), findsOneWidget);
      expect(find.text('Faltante Q385.00'), findsOneWidget);
      expect(find.text('Q12,169.50'), findsOneWidget);
      // Juan abrió hoy: solo la hora.
      expect(find.text('07:00 AM → 03:05 PM · 8h 5m · $sucursal'), findsOneWidget);
      expect(find.text('Cuadró'), findsWidgets);
      expect(find.text('Q6,209.50'), findsOneWidget);
      expect(find.text('en ventas'), findsNWidgets(2));
    });

    testWidgets('la tabla ¿Cuadró la caja?: esperado, contado y diferencia por método', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.text('¿CUADRÓ LA CAJA?'), findsNWidgets(2));
      expect(find.text('MÉTODO'), findsNWidgets(2));
      expect(find.text('Q2,534.00'), findsWidgets);
      expect(find.text('Q2,149.00'), findsOneWidget);
      expect(find.text('−Q385.00'), findsNWidgets(2), reason: 'el resumen de arriba y la fila de efectivo');
      expect(find.text('Q9,635.50'), findsWidgets);
      // La diferencia en negativo va en rojo; la que cuadra, normal.
      final dif = tester.widgetList<Text>(find.text('−Q385.00')).last;
      expect(dif.style!.color, InicioColores.bad);
    });

    testWidgets('en un teléfono angosto cada método pasa a dos líneas', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('MÉTODO'), findsNothing);
      expect(find.text('Esperado Q2,534.00 · Contado Q2,149.00'), findsOneWidget);
      expect(find.text('Esperado Q9,635.50 · Contado Q9,635.50'), findsOneWidget);
    });

    testWidgets('la aclaración, solo en el corte con diferencia', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(
        find.textContaining('Aclaración: Efectivo (faltante Q385.00): se le dio pagado a una cuenta de guía cortesía', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('efectivo en caja: apertura, ventas, depósitos, retiros y totales', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.text('EFECTIVO EN CAJA'), findsNWidgets(2));
      expect(find.text('Apertura'), findsNWidgets(2));
      expect(find.text('Q2,000.00'), findsOneWidget);
      expect(find.text('Venta en efectivo'), findsNWidgets(2));
      expect(find.text('Q4,534.00'), findsOneWidget, reason: 'total efectivo de Ana');
      expect(find.text('Q14,169.50'), findsOneWidget, reason: 'total con apertura de Ana');
      // Juan: retiró Q500.
      expect(find.text('−Q500.00'), findsOneWidget);
      expect(find.text('Q1,879.00'), findsOneWidget);
      expect(find.text('Q6,709.50'), findsOneWidget);
      // Sin depósitos, una raya.
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('los demás métodos con ventas salen entre el efectivo y el total', (tester) async {
      final c = cierre(ana(extra: {'actualTransfer': 300.0, 'differenceTransfer': 0.0}));
      await montar(tester, cuerpo(cierres: [c], abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('Venta con tarjeta'), findsOneWidget);
      expect(find.text('Venta con transferencia'), findsOneWidget);
      expect(find.text('Q300.00'), findsWidgets);
      // 4,534 + 9,635.50 + 300.
      expect(find.text('Q14,469.50'), findsOneWidget);
    });

    testWidgets('en 1280 las dos cajas del corte van lado a lado; en 700, una debajo de la otra', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(tester.getTopLeft(find.text('¿CUADRÓ LA CAJA?').first).dy, tester.getTopLeft(find.text('EFECTIVO EN CAJA').first).dy);
      await montar(tester, cuerpo(), size: const Size(700, 3000));
      expect(tester.getTopLeft(find.text('EFECTIVO EN CAJA').first).dy, greaterThan(tester.getTopLeft(find.text('¿CUADRÓ LA CAJA?').first).dy + 40));
    });

    testWidgets('"Ver pedidos y gastos" abre ESE corte', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      await tester.tap(find.text('Ver pedidos y gastos').last);
      expect(tocados.map((c) => c.caja.id), ['cr-juan']);
      await tester.tap(find.text('Ver pedidos y gastos').first);
      expect(tocados.map((c) => c.caja.id), ['cr-juan', 'cr-ana']);
    });

    testWidgets('si el corte se cerró dos veces, la tarjeta lo dice con lo que se contó', (tester) async {
      final doble = cierre(ana(extra: {
        'cierres_no_aplicados': [
          {
            'closed_at': Timestamp.fromDate(DateTime(2026, 11, 21, 1, 40)),
            'device_model': 'SUNMI V2s',
            'actualCash': 3900.0,
          },
        ],
      }));
      await montar(tester, cuerpo(cierres: [doble], abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('Esta caja se cerró dos veces'), findsOneWidget);
      expect(find.textContaining('Contó efectivo Q3,900.00'), findsOneWidget);
    });

    testWidgets('los métodos propios con su nombre y lo contado = esperado + diferencia sellada', (tester) async {
      final c = CierreCaja.desde(
        CashRegisterSummary.fromMap({
          'id': 'cr-v',
          'userName': 'Herlinda',
          'status': 'closed',
          'openedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 7)),
          'closedAt': Timestamp.fromDate(DateTime(2026, 11, 21, 12)),
          'actualCash': 100.0,
          'differenceCash': 0.0,
          'expectedCustomMethods': {'custom_vales': 25.0, 'custom_cupon': 10.0},
          'actualCustomMethods': <String, double>{},
          'differenceCustomMethods': {'custom_vales': -25.0},
        }).copyWith(customMethodNames: {'custom_vales': 'Vales', 'custom_cupon': 'Cupón'}),
        const [],
        signo: 'Q',
      );
      await montar(tester, cuerpo(cierres: [c], abiertas: const []), size: const Size(1280, 3000));
      expect(find.text('Vales'), findsWidgets);
      expect(find.text('Cupón'), findsNothing, reason: 'el resto de una venta anulada no es de ningún corte');
      expect(find.text('Faltante Q25.00'), findsOneWidget);
      expect(find.text('Q125.00'), findsWidgets);
    });
  });

  group('sin nada', () {
    testWidgets('lo dice', (tester) async {
      await montar(tester, cuerpo(cierres: const [], abiertas: const []));
      expect(find.text('Sin cierres de caja en este período'), findsOneWidget);
    });
  });

  // La pantalla real mete el cuerpo en el cambio de sucursal
  // (LocationContentSwitcher), que es un AnimatedSwitcher: lo pone en un Stack
  // centrado y con restricciones sueltas. Un SingleChildScrollView mide lo que
  // mide su contenido, así que con poco que mostrar todo quedaba al medio de la
  // pantalla. El `montar` de arriba no lo ve: el Scaffold da restricciones firmes.
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
                      child: RefreshIndicator(onRefresh: () async {}, child: cuerpo(cierres: const [], abiertas: [marta])),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(SingleChildScrollView)).height, tam.height - arribaDelArea);
        expect(tester.getTopLeft(find.text('Ventas del período')).dy, lessThan(arribaDelArea + 60));
      });
    }
  });

  group('cabe sin desbordar', () {
    for (final s in tamanos) {
      testWidgets('a ${s.width.toInt()} con letra grande y datos normales', (tester) async {
        await montar(tester, cuerpo(), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande, cifras enormes, nombres larguísimos y muchas cajas', (tester) async {
        final enormes = <CierreCaja>[
          for (var i = 0; i < 4; i++)
            cierre(
              ana(extra: {
                'id': 'e$i',
                'userName': 'María de los Ángeles Fernández de la Vega y Montoya número $i',
                'initialCash': 98765432.1,
                'actualCash': 987654321.55,
                'differenceCash': -12345678.9,
                'actualCard': 5555555.5,
                'differenceCard': 0.0,
                'closingNotes': 'Una aclaración larguísima de verdad que tiene que partirse en varias líneas sin romper nada $i',
                'movements': [
                  {'type': 'withdrawal', 'amount': 1234567.0},
                ],
              }).copyWith(locationName: 'Una sucursal con un nombre larguísimo de verdad para ver qué pasa'),
              signo: 'USD ',
            ),
        ];
        final abiertas = [
          for (var i = 0; i < 3; i++)
            abierta('o$i', 'Un cajero con un nombre larguísimo de verdad número $i', DateTime(2026, 11, 1 + i, 8)),
        ];
        await montar(tester, cuerpo(cierres: enormes, abiertas: abiertas, signo: (_) => 'USD '), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande y sin nada o solo una abierta', (tester) async {
        await montar(tester, cuerpo(cierres: const [], abiertas: const []), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await montar(tester, cuerpo(cierres: const [], abiertas: [marta]), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('la moneda por código y los cortes recalculados', () {
    testWidgets('con el código de moneda, el rótulo dice cuál es aunque compartan signo', (tester) async {
      final mx = CierreCaja.desde(ana(extra: {'id': 'mx', 'locationId': 'mx'}), const [], signo: r'$', moneda: 'MXN');
      final us = CierreCaja.desde(ana(extra: {'id': 'us', 'locationId': 'us'}), const [], signo: r'$', moneda: 'USD');
      await montar(
        tester,
        CierresCajaBody(
          cierres: [mx, us],
          abiertas: const [],
          signoDeCaja: (_) => r'$',
          monedaDeCaja: (loc) => loc == 'us' ? 'USD' : 'MXN',
          ahora: ahora,
          onVerDetalle: tocados.add,
        ),
        size: const Size(1280, 3600),
      );
      expect(find.text(r'Cajas en MXN ($)'), findsOneWidget);
      expect(find.text(r'Cajas en USD ($)'), findsOneWidget);
      expect(find.text('Ventas del período'), findsNWidgets(2), reason: 'dos resúmenes, no uno con todo sumado');
    });

    testWidgets('un corte antiguo recalculado de los pedidos se avisa en el resumen', (tester) async {
      final antiguo = CashRegisterSummary.fromMap({
        'id': 'old', 'userName': 'Ana', 'status': 'closed', 'locationId': 'gt',
        'openedAt': Timestamp.fromDate(DateTime(2026, 2, 1, 8)), 'closedAt': Timestamp.fromDate(DateTime(2026, 2, 1, 16)),
        'actualCash': 300.0,
      }).copyWith(locationName: sucursal);
      final pedido = {'payment_method': 'cash', 'payment_amount': 100.0, 'paid_at': Timestamp.fromDate(DateTime(2026, 2, 1, 10)), 'location_id': 'gt'};
      await montar(
        tester,
        cuerpo(cierres: [CierreCaja.desde(antiguo, [pedido], signo: 'Q'), cierre(juan())], abiertas: const []),
        size: const Size(1280, 3000),
      );
      expect(find.text('1 recalculado de los pedidos: pueden repetir ventas'), findsOneWidget);
    });

    testWidgets('con todos los cortes sellados no hay aviso de recalculados', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      expect(find.textContaining('recalculado'), findsNothing);
    });
  });
}
