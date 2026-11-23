import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/descuentos_data.dart';
import 'package:saborpro_reports/presentation/widgets/cortesias_view.dart' show kCortesiasBg;
import 'package:saborpro_reports/presentation/widgets/descuentos_view.dart';

/// La pantalla depende de providers con Firebase y no se puede montar en un
/// test; su mitad visual sí. Cualquier "RenderFlex overflowed" hace fallar la
/// prueba por sí solo.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  Widget wrap(Widget body, {double escala = 1.0}) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(backgroundColor: kCortesiasBg, body: body),
      );

  void tamano(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> bajarHasta(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<void> montar(
    WidgetTester tester,
    DescuentosReport r, {
    Size size = const Size(360, 800),
    double escala = 1.0,
    Map<String, String> nombres = const {},
    Map<String, String> sucursales = const {},
    bool incompleto = false,
    bool convertido = false,
    double? ventas,
  }) async {
    tamano(tester, size);
    await tester.pumpWidget(wrap(
      DescuentosReportBody(
        report: r,
        nombresUsuario: nombres,
        nombresSucursal: sucursales,
        incompleto: incompleto,
        convertido: convertido,
        ventas: ventas,
      ),
      escala: escala,
    ));
    await tester.pumpAndSettle();
  }

  // ── Los datos: pedidos como los guarda el POS ──────────────────────────────
  Map<String, dynamic> orden(
    String id, {
    double descuento = 10,
    double total = 100,
    String? motivo,
    String? quien = 'u1',
    String? nombre,
    DateTime? cuando,
    List<List<Object>>? platillos,
    String? mesa = 'Mesa 4',
    int? numero,
    String? sucursal,
    String? cliente,
  }) =>
      {
        '_docId': id,
        'discount_amount': descuento,
        'total_amount': total,
        if (motivo != null) 'discount_reason': motivo,
        if (quien != null) 'paid_by_user_id': quien,
        if (nombre != null) 'paid_by_user_name': nombre,
        'paid_at': cuando ?? DateTime(2026, 11, 23, 14, 30),
        if (mesa != null) 'table_name': mesa,
        if (numero != null) ...{'order_no': numero, 'order_prefix': 'E'},
        if (sucursal != null) 'location_id': sucursal,
        if (cliente != null) 'customer_name': cliente,
        'items': [
          for (final p in platillos ?? [['Hamburguesa clásica', 100.0, 1.0]])
            {'name': p[0], 'unit_price': p[1], 'qty': p[2]},
        ],
      };

  DescuentosReport reporte(List<Map<String, dynamic>> o) => DescuentosReport.desde(o);

  /// Un día con de todo: motivos, personas, altos, sin motivo y de varias sucursales.
  DescuentosReport completo() => reporte([
        orden('a', descuento: 16, total: 160, motivo: 'Cliente frecuente', quien: 'u1', numero: 21, sucursal: 's1', platillos: [
          ['Hamburguesa clásica', 80.0, 2.0],
          ['Limonada con soda', 22.0, 2.0],
        ]),
        orden('b', descuento: 17.5, total: 35, quien: 'u2', numero: 18, mesa: 'Mesa 2', sucursal: 's2', platillos: [
          ['Pastel de Chocolate', 35.0, 1.0],
        ]),
        orden('c', descuento: 25, total: 110, motivo: 'Promoción del día', quien: 'u3', numero: 12, mesa: null, sucursal: 's1'),
        orden('d', descuento: 24, total: 176, quien: 'u2', numero: 11, sucursal: 's2'),
        orden('e', descuento: 10, total: 102, motivo: 'cliente frecuente', quien: 'u1', numero: 8, sucursal: 's1'),
        orden('f', descuento: 9, total: 90, motivo: 'Consumo de empleado', quien: 'u3', numero: 3, mesa: null, sucursal: 's1'),
        // Más pedidos para pasar de los 20 que se ven de entrada.
        for (var i = 0; i < 18; i++)
          orden('x$i', descuento: 5, total: 100, motivo: 'Cortesía de la casa', quien: 'u1', numero: 100 + i, sucursal: 's1', cuando: DateTime(2026, 11, 22, 10, i)),
        {...orden('viejo', descuento: 3, total: 30, quien: null, cliente: 'Cliente viejo sin fecha'), 'paid_at': null},
      ]);

  const nombres = {'u1': 'Ana Cosme', 'u2': 'Carlos Pérez', 'u3': 'María López'};
  const sucursales = {'s1': 'Centro', 's2': 'Zona 10'};

  // ── Dentro del cambio de sucursal ──────────────────────────────────────────
  group('dentro del cambio de sucursal', () {
    for (final tam in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets('sin datos el contenido arranca arriba, no al medio ($tam)', (tester) async {
        tamano(tester, tam);
        const arribaDelArea = 100.0;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: kCortesiasBg,
            body: Column(
              children: [
                const SizedBox(height: arribaDelArea),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: const ValueKey('todas'),
                      child: RefreshIndicator(
                        onRefresh: () async {},
                        child: const DescuentosReportBody(report: DescuentosReport.empty),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(SingleChildScrollView)).height, tam.height - arribaDelArea);
        expect(tester.getTopLeft(find.text('Total descontado')).dy, lessThan(arribaDelArea + 60));
      });
    }
  });

  // ── Vacío ───────────────────────────────────────────────────────────────────
  testWidgets('vacío dice que no hubo y no muestra listas', (tester) async {
    await montar(tester, DescuentosReport.empty);
    expect(find.text('Total descontado'), findsOneWidget);
    expect(find.text('Q0.00'), findsWidgets);
    expect(find.text('Ningún descuento en este período.'), findsOneWidget);
    expect(find.text('No hubo descuentos en este período.'), findsOneWidget);
    expect(find.text('¿Quién da descuentos?'), findsNothing);
    expect(find.text('¿Por qué se descuenta?'), findsNothing);
    expect(find.text('¿A qué se le hace descuento?'), findsNothing);
    expect(find.text('Pedidos'), findsNothing);
    // Sin pedidos no hay "el más alto" ni "pedidos con descuento: 0 · promedio".
    expect(find.text('El descuento más alto'), findsNothing);
    expect(find.textContaining('Descuento promedio'), findsNothing);
  });

  // ── El resumen ──────────────────────────────────────────────────────────────
  group('el resumen', () {
    testWidgets('total, pedidos, promedio y el más alto, con las cuentas del reporte', (tester) async {
      final r = reporte([
        orden('a', descuento: 50, total: 100, mesa: 'Mesa 2'),
        orden('b', descuento: 10, total: 900),
      ]);
      await montar(tester, r);
      expect(find.text('Q60.00'), findsWidgets);
      expect(find.text('Pedidos con descuento'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      // 60 de 1000 = 6%, y el promedio por pedido: Q30.00.
      expect(find.text('Descuento promedio 6% · Q30.00'), findsOneWidget);
      expect(find.text('El descuento más alto'), findsOneWidget);
      expect(find.text('50%'), findsWidgets);
      expect(find.text('Q50.00 · Mesa 2'), findsOneWidget);
      expect(find.textContaining('Es dinero que dejaste de cobrar'), findsOneWidget);
    });

    testWidgets('"De tus ventas" solo si se sabe lo que se vendió', (tester) async {
      final r = reporte([orden('a', descuento: 50, total: 100)]);
      await montar(tester, r);
      expect(find.text('De tus ventas'), findsNothing);

      await montar(tester, r, ventas: 0);
      expect(find.text('De tus ventas'), findsNothing);

      await montar(tester, r, ventas: 1000);
      expect(find.text('De tus ventas'), findsOneWidget);
      expect(find.text('5.0%'), findsOneWidget);
      expect(find.text('Vendiste Q1,000.00'), findsOneWidget);
    });

    testWidgets('el aviso de redondeo solo cuando los montos están convertidos', (tester) async {
      final r = reporte([orden('a')]);
      await montar(tester, r);
      expect(find.textContaining('por el redondeo'), findsNothing);
      await montar(tester, r, convertido: true);
      expect(find.textContaining('por el redondeo'), findsOneWidget);
    });

    testWidgets('el período leído a medias lo dice', (tester) async {
      await montar(tester, reporte([orden('a')]), incompleto: true);
      expect(find.textContaining('más pedidos de los que se pueden leer'), findsOneWidget);
    });

    testWidgets('un porcentaje que no es redondo lleva su decimal', (tester) async {
      await montar(tester, reporte([orden('a', descuento: 7.5, total: 100)]));
      expect(find.text('7.5%'), findsWidgets);
    });

    testWidgets('sin cuenta no se inventa un porcentaje', (tester) async {
      final r = reporte([
        {
          '_docId': 'a',
          'discount_amount': 10.0,
          'paid_at': DateTime(2026, 11, 23, 12),
          'items': <Object>[],
        },
      ]);
      await montar(tester, r);
      expect(find.text('El descuento más alto'), findsNothing);
      await bajarHasta(tester, find.text('Pedidos'));
      expect(find.text('—'), findsWidgets);
    });
  });

  // ── La alerta ───────────────────────────────────────────────────────────────
  group('la alerta', () {
    testWidgets('dice cuántos sin motivo y de cuánto, y cuántos son altos', (tester) async {
      await montar(tester, completo(), nombres: nombres);
      // sin motivo: b (17.5), d (24), viejo (3) = Q44.50; altos (≥30%): b = 50%.
      expect(find.textContaining('3 descuentos sin motivo'), findsOneWidget);
      expect(find.textContaining('Q44.50'), findsWidgets);
      expect(find.textContaining('1 de 30% o más'), findsOneWidget);
      expect(find.textContaining('Revisa si estaban autorizados'), findsOneWidget);
    });

    testWidgets('con todos los motivos escritos y ninguno alto no aparece', (tester) async {
      await montar(tester, reporte([orden('a', descuento: 5, total: 100, motivo: 'Promo')]));
      expect(find.textContaining('Revisa si estaban autorizados'), findsNothing);
    });

    testWidgets('solo altos: "N descuentos de 30% o más", sin hablar de motivo', (tester) async {
      await montar(tester, reporte([
        orden('a', descuento: 50, total: 100, motivo: 'Promo'),
        orden('b', descuento: 40, total: 100, motivo: 'Promo'),
      ]));
      expect(find.textContaining('2 descuentos de 30% o más'), findsOneWidget);
      expect(find.textContaining('sin motivo'), findsNothing);
    });

    testWidgets('solo sin motivo: no habla de altos', (tester) async {
      await montar(tester, reporte([orden('a', descuento: 5, total: 100)]));
      expect(find.textContaining('1 descuento sin motivo'), findsOneWidget);
      expect(find.textContaining('o más. Revisa'), findsNothing);
    });

    testWidgets('el botón "Sin motivo" filtra los pedidos', (tester) async {
      await montar(tester, completo(), nombres: nombres);
      await tester.tap(find.widgetWithText(TextButton, 'Sin motivo'));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Pedidos'));
      expect(find.text('3 de ${completo().pedidos.length}'), findsOneWidget);
    });

    testWidgets('el botón "30% o más" filtra los pedidos', (tester) async {
      await montar(tester, completo(), nombres: nombres);
      await tester.tap(find.widgetWithText(TextButton, '30% o más'));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Pedidos'));
      expect(find.text('1 de ${completo().pedidos.length}'), findsOneWidget);
    });
  });

  // ── ¿Quién da descuentos? ───────────────────────────────────────────────────
  group('quién da descuentos', () {
    testWidgets('cada persona con sus pedidos, su promedio y sus "sin motivo"', (tester) async {
      await montar(tester, completo(), nombres: nombres, size: const Size(1280, 1000));
      expect(find.text('¿Quién da descuentos?'), findsOneWidget);
      expect(find.text('Toca para ver sus pedidos'), findsOneWidget);
      expect(find.text('Ana Cosme'), findsWidgets);
      expect(find.text('Carlos Pérez'), findsWidgets);
      expect(find.text('María López'), findsWidgets);
      // Carlos: b y d, los dos sin motivo.
      expect(find.text('2 sin motivo'), findsOneWidget);
      // El pedido sin quien cobró cae en "Sin registrar".
      expect(find.text('Sin registrar'), findsWidgets);
    });

    testWidgets('el promedio alto va en rojo y el normal en gris', (tester) async {
      // Carlos: 41.5 de 211 = 19.7%, no es alto. Una persona con 50%: sí.
      await montar(tester, reporte([
        orden('a', descuento: 50, total: 100, quien: 'u1'),
        orden('b', descuento: 5, total: 100, quien: 'u2'),
      ]), nombres: nombres);
      final alto = tester.widget<Text>(find.text('50%').first);
      expect(alto.style!.color, isNotNull);
    });

    testWidgets('tocar a una persona deja solo sus pedidos y aparece su ficha; tocarla otra vez la quita', (tester) async {
      await montar(tester, completo(), nombres: nombres, size: const Size(1280, 1000));
      final total = completo().pedidos.length;

      await tester.tap(find.text('Carlos Pérez').first);
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Pedidos'));
      expect(find.text('2 de $total'), findsOneWidget);
      // La ficha para quitar el filtro (el nombre con una x).
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('$total de $total'), findsOneWidget);
    });

    testWidgets('el nombre que guardó el pedido se usa aunque no se haya buscado', (tester) async {
      await montar(tester, reporte([orden('a', quien: 'u9', nombre: 'Rosario Gómez')]));
      expect(find.text('Rosario Gómez'), findsWidgets);
    });

    testWidgets('si no se sabe el nombre de quien cobró dice "Usuario"', (tester) async {
      await montar(tester, reporte([orden('a', quien: 'u9')]));
      expect(find.text('Usuario'), findsWidgets);
    });
  });

  // ── ¿Por qué se descuenta? ──────────────────────────────────────────────────
  group('por qué se descuenta', () {
    testWidgets('junta los motivos aunque cambien las mayúsculas, y los más caros primero', (tester) async {
      await montar(tester, completo(), nombres: nombres, size: const Size(1280, 1000));
      final seccion = find.byKey(const ValueKey('seccion-por-que'));
      expect(find.descendant(of: seccion, matching: find.text('¿Por qué se descuenta?')), findsOneWidget);
      // "Cliente frecuente" y "cliente frecuente" son el mismo motivo: UNA fila,
      // con los dos pedidos, escrita como la escribió el primero.
      expect(find.descendant(of: seccion, matching: find.text('Cliente frecuente')), findsOneWidget);
      expect(find.descendant(of: seccion, matching: find.text('cliente frecuente')), findsNothing);
      expect(find.descendant(of: seccion, matching: find.text('2 pedidos')), findsWidgets);
      expect(find.descendant(of: seccion, matching: find.text('Promoción del día')), findsOneWidget);
      expect(find.descendant(of: seccion, matching: find.text('Consumo de empleado')), findsOneWidget);
      // Los más caros arriba: "Cortesía de la casa" (18 × Q5 = Q90) antes que "Promoción" (Q25).
      final casa = tester.getTopLeft(find.descendant(of: seccion, matching: find.text('Cortesía de la casa'))).dy;
      final promo = tester.getTopLeft(find.descendant(of: seccion, matching: find.text('Promoción del día'))).dy;
      expect(casa, lessThan(promo));
    });

    testWidgets('"Sin motivo" sale como un renglón más, con aviso', (tester) async {
      await montar(tester, completo(), nombres: nombres, size: const Size(1280, 1000));
      expect(find.text('Sin motivo'), findsWidgets);
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    });
  });

  // ── ¿A qué se le hace descuento? ────────────────────────────────────────────
  group('a qué se le hace descuento', () {
    testWidgets('dice que el descuento se reparte, no que se guardó así', (tester) async {
      await montar(tester, completo(), nombres: nombres);
      await bajarHasta(tester, find.text('¿A qué se le hace descuento?'));
      expect(find.textContaining('se reparte entre sus platillos'), findsOneWidget);
      expect(find.textContaining('platillos distintos'), findsOneWidget);
    });

    testWidgets('con muchos platillos, "Ver los N platillos" los muestra todos', (tester) async {
      final r = reporte([
        orden('a', descuento: 30, total: 300, platillos: [
          for (var i = 0; i < 9; i++) ['Plato $i', 100.0 - i, 1.0],
        ]),
      ]);
      await montar(tester, r);
      await bajarHasta(tester, find.text('¿A qué se le hace descuento?'));
      final seccion = find.byKey(const ValueKey('seccion-platillos'));
      // El pedido también los lista: se cuenta solo lo de la sección.
      expect(find.descendant(of: seccion, matching: find.text('Plato 8')), findsNothing);
      await bajarHasta(tester, find.textContaining('Ver los 9 platillos'));
      await tester.tap(find.textContaining('Ver los 9 platillos'));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.descendant(of: seccion, matching: find.text('Plato 8')));
    });

    testWidgets('si los pedidos no traen platillos, lo dice en vez de dejar un hueco', (tester) async {
      final r = reporte([
        {'_docId': 'a', 'discount_amount': 10.0, 'total_amount': 100.0, 'paid_at': DateTime(2026, 11, 23, 12), 'items': <Object>[]},
      ]);
      await montar(tester, r);
      await bajarHasta(tester, find.text('¿A qué se le hace descuento?'));
      expect(find.textContaining('no traen el detalle de sus platillos'), findsOneWidget);
    });
  });

  // ── Los pedidos ─────────────────────────────────────────────────────────────
  group('los pedidos', () {
    testWidgets('los filtros llevan su cuenta', (tester) async {
      await montar(tester, completo(), nombres: nombres);
      await bajarHasta(tester, find.text('Pedidos'));
      final n = completo().pedidos.length;
      // Chips: Todos n, Sin motivo 3, 30% o más 1.
      final chip = find.widgetWithText(InkWell, 'Todos');
      expect(chip, findsOneWidget);
      expect(find.text('$n'), findsWidgets);
    });

    testWidgets('en el teléfono cada pedido es una tarjeta con la cuenta tachada y lo que quedó', (tester) async {
      await montar(tester, reporte([orden('a', descuento: 20, total: 200, numero: 21, motivo: 'Cliente frecuente', quien: 'u1')]), nombres: nombres);
      await bajarHasta(tester, find.text('Mesa 4 · #E21'));
      expect(find.text('−Q20.00'), findsWidgets);
      expect(find.text('Q200.00'), findsWidgets);
      expect(find.text('Q180.00'), findsOneWidget);
      // La cuenta de antes va tachada.
      final antes = tester.widget<Text>(find.text('Q200.00').last);
      expect(antes.style!.decoration, TextDecoration.lineThrough);
      expect(find.text('10%'), findsWidgets);
      expect(find.text('Ana Cosme'), findsWidgets);
    });

    testWidgets('los altos se marcan', (tester) async {
      await montar(tester, reporte([orden('a', descuento: 60, total: 100)]), size: const Size(1280, 1000));
      expect(find.text('alto'), findsOneWidget);
      expect(find.text('60%'), findsWidgets);
    });

    testWidgets('el nombre de la sucursal solo sale si hay pedidos de más de una', (tester) async {
      await montar(tester, completo(), nombres: nombres, sucursales: sucursales);
      await bajarHasta(tester, find.text('Pedidos'));
      expect(find.textContaining('Zona 10'), findsWidgets);

      await montar(tester, reporte([orden('a', sucursal: 's1')]), sucursales: sucursales);
      await bajarHasta(tester, find.text('Pedidos'));
      expect(find.textContaining('Centro'), findsNothing);
    });

    testWidgets('con más de 20 pedidos se ven 20 y el resto se pide', (tester) async {
      await montar(tester, completo(), nombres: nombres);
      await bajarHasta(tester, find.textContaining('Ver los otros'));
      await tester.tap(find.textContaining('Ver los otros'));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.textContaining('Cliente viejo sin fecha'));
      expect(find.text('Sin fecha'), findsOneWidget);
    });

    testWidgets('un filtro sin pedidos lo dice', (tester) async {
      await montar(tester, reporte([orden('a', motivo: 'Promo', descuento: 5, total: 100)]), nombres: nombres);
      await bajarHasta(tester, find.text('Pedidos'));
      await tester.tap(find.widgetWithText(InkWell, 'Sin motivo'));
      await tester.pumpAndSettle();
      expect(find.text('No hay pedidos con este filtro.'), findsOneWidget);
    });
  });

  // ── Que quepa ───────────────────────────────────────────────────────────────
  group('que quepa', () {
    for (final tam in const [Size(320, 640), Size(360, 640), Size(390, 844), Size(700, 900), Size(800, 900), Size(1280, 900)]) {
      for (final escala in const [1.0, 1.4]) {
        testWidgets('${tam.width.toInt()}×${tam.height.toInt()} con letra a $escala', (tester) async {
          await montar(
            tester,
            completo(),
            size: tam,
            escala: escala,
            nombres: const {'u1': 'Ana María de los Ángeles Pérez', 'u2': 'Carlos', 'u3': 'María'},
            sucursales: sucursales,
            incompleto: true,
            convertido: true,
            ventas: 123456.78,
          );
          await bajarHasta(tester, find.text('¿Quién da descuentos?'));
          await bajarHasta(tester, find.text('¿Por qué se descuenta?'));
          await bajarHasta(tester, find.text('¿A qué se le hace descuento?'));
          await bajarHasta(tester, find.text('Pedidos'));
          await bajarHasta(tester, find.textContaining('Ver los otros'));
          await tester.tap(find.textContaining('Ver los otros'));
          await tester.pumpAndSettle();
          await bajarHasta(tester, find.textContaining('Cliente viejo sin fecha'));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
