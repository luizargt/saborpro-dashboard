import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/core/services/location_service.dart';
import 'package:saborpro_reports/core/utils/formato_dinero.dart';
import 'package:saborpro_reports/data/models/atencion_inicio.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/cuentas_abiertas.dart';
import 'package:saborpro_reports/data/models/dashboard_data.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_atencion.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:saborpro_reports/presentation/widgets/location_sales_breakdown.dart';
import 'package:saborpro_reports/presentation/widgets/metric_cards.dart';
import 'package:saborpro_reports/presentation/widgets/payment_method_breakdown.dart';
import 'package:saborpro_reports/presentation/widgets/products_list.dart';
import 'package:saborpro_reports/presentation/widgets/sales_chart.dart';
import 'package:saborpro_reports/presentation/widgets/summary_table.dart';
import 'package:saborpro_reports/presentation/widgets/top_categories_carousel.dart';

/// Las piezas del Inicio rediseñado, sin Firebase: la pantalla real solo les
/// pasa lo que el provider ya calculó. Se prueba el orden, qué sale en cada
/// caso y que nada desborde a 360dp (con letra grande) ni en pantalla ancha.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });
  setUp(() => fijarMoneda('Q'));
  tearDown(() => fijarMoneda('Q'));

  PeriodMetrics metricas({
    double total = 3259,
    int tickets = 28,
    double prev = 29728.77,
    int prevTickets = 106,
    double tips = 293,
    int tipsCount = 26,
    double courtesy = 35,
    int courtesyCount = 1,
    double discounts = 0,
    double delivery = 0,
    int deliveryCount = 0,
    double tipsOutside = 0,
    bool detalle = true,
  }) =>
      PeriodMetrics(
        totalSales: total,
        totalOrders: tickets,
        avgTicket: tickets == 0 ? 0 : (total - tips - delivery) / tickets,
        prevTotalSales: prev,
        prevTotalOrders: prevTickets,
        prevAvgTicket: 280.46,
        chartPoints: const [],
        topProducts: const [],
        tips: tips,
        tipsCount: tipsCount,
        courtesyTotal: courtesy,
        courtesyCount: courtesyCount,
        discounts: discounts,
        deliveryFees: delivery,
        deliveryCount: deliveryCount,
        tipsOutsideSales: tipsOutside,
        detailAvailable: detalle,
      );

  Widget host(Widget child, {double escala = 1.0}) => MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: c!,
        ),
        home: Scaffold(
          backgroundColor: kInicioBg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );

  Future<void> montar(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(360, 800),
    double escala = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(child, escala: escala));
    await tester.pumpAndSettle();
  }

  const tamanos = [Size(360, 800), Size(390, 844), Size(700, 900), Size(1280, 800)];

  group('KpiCards', () {
    testWidgets('en el teléfono, la venta bruta a todo el ancho y debajo tickets y promedio juntos', (tester) async {
      for (final ancho in [360.0, 390.0]) {
        await montar(tester, KpiCards(metrics: metricas()), size: Size(ancho, 844));
        final t = [for (final n in ['Venta bruta', 'Tickets', 'Promedio']) tester.getTopLeft(find.text(n))];
        expect(t[1].dy, greaterThan(t[0].dy), reason: 'tickets debajo de la venta bruta');
        expect(t[1].dy, t[2].dy, reason: 'tickets y promedio en la misma fila');
        expect(t[1].dx, lessThan(t[2].dx));
        // La venta bruta ocupa todo el ancho (menos los 16 de margen a cada lado).
        final venta = tester.getRect(find.ancestor(of: find.text('Venta bruta'), matching: find.byType(Container)).first);
        expect(venta.width, ancho - 32);
        expect(find.text('vs anterior: Q29,728.77'), findsOneWidget);
        expect(find.text('vs anterior: 106'), findsOneWidget);
      }

      await montar(tester, KpiCards(metrics: metricas()), size: const Size(1280, 800));
      final p = [for (final t in ['Venta bruta', 'Tickets', 'Promedio']) tester.getTopLeft(find.text(t))];
      expect(p[0].dy, p[1].dy);
      expect(p[1].dy, p[2].dy);
      expect(p[0].dx < p[1].dx && p[1].dx < p[2].dx, isTrue);
    });

    testWidgets('la venta bruta no cuenta propinas ni envío, y compara contra lo anterior', (tester) async {
      await montar(tester, KpiCards(metrics: metricas(delivery: 50)), size: const Size(1280, 800));
      // 3259 − 293 de propinas − 50 de envío.
      expect(find.text('Q2,916.00'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.text('vs anterior: Q29,728.77'), findsOneWidget);
      expect(find.text('vs anterior: 106'), findsOneWidget);
    });

    testWidgets('baja en rojo, sube en verde, igual en gris', (tester) async {
      await montar(tester, KpiCards(metrics: metricas()), size: const Size(1280, 800));
      // 3259 contra 29,728.77: cayó 89%.
      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.text('89.0%'), findsOneWidget);

      await montar(tester, KpiCards(metrics: metricas(total: 4000, prev: 2000, tickets: 40, prevTickets: 20)),
          size: const Size(1280, 800));
      expect(find.byIcon(Icons.arrow_upward_rounded), findsWidgets);
      expect(find.text('100.0%'), findsWidgets);

      // Sin período anterior no hay con qué comparar: queda en 0.0%.
      await montar(tester, KpiCards(metrics: metricas(prev: 0, prevTickets: 0)), size: const Size(1280, 800));
      expect(find.byIcon(Icons.remove_rounded), findsWidgets);
      expect(find.text('0.0%'), findsWidgets);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y una cifra enorme', (tester) async {
        await montar(
          tester,
          KpiCards(metrics: metricas(total: 987654321.55, prev: 123456789.12, tips: 0)),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('TarjetasRapidas', () {
    testWidgets('propinas, cortesías y descuentos, con su detalle', (tester) async {
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(discounts: 150), onCourtesyTap: () {}, descuentosCount: 4),
        size: const Size(1280, 800),
      );
      expect(find.text('Propinas'), findsOneWidget);
      expect(find.text('Q293.00'), findsOneWidget);
      expect(find.text('26 cobros'), findsOneWidget);
      expect(find.text('Cortesías / Donaciones'), findsOneWidget);
      expect(find.text('1 cobro'), findsOneWidget);
      expect(find.text('Descuentos'), findsOneWidget);
      expect(find.text('Q150.00'), findsOneWidget);
      expect(find.text('4 cobros'), findsOneWidget);
    });

    testWidgets('un descuento sin saber en cuántos cobros no dice "Ningún descuento"', (tester) async {
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 75)), size: const Size(1280, 800));
      expect(find.text('Q75.00'), findsOneWidget);
      expect(find.text('Ningún descuento'), findsNothing);
    });

    testWidgets('en cero también se ven, y lo dicen', (tester) async {
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(tips: 0, tipsCount: 0, courtesy: 0, courtesyCount: 0)),
        size: const Size(1280, 800),
      );
      expect(find.text('Sin propinas'), findsOneWidget);
      expect(find.text('Ninguna'), findsOneWidget);
      expect(find.text('Ningún descuento'), findsOneWidget);
    });

    testWidgets('propinas metidas a la caja no son cobros', (tester) async {
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(tips: 0, tipsCount: 0, tipsOutside: 80)),
        size: const Size(1280, 800),
      );
      expect(find.text('Q80.00'), findsOneWidget);
      expect(find.text('Metidas a la caja'), findsOneWidget);
    });

    testWidgets('en la vista de año las propinas de tickets no son "metidas a la caja"', (tester) async {
      // Lo que arma el provider en el año: las propinas de los tickets sumadas en
      // el servidor, sin saber en cuántos cobros (tipsCount 0), y sin detalle.
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(detalle: false, tips: 5000, tipsCount: 0, courtesy: 0, courtesyCount: 0)),
        size: const Size(1280, 800),
      );
      expect(find.text('Q5,000.00'), findsOneWidget);
      expect(find.text('Metidas a la caja'), findsNothing);
      expect(find.text('Sin propinas'), findsNothing);

      // Con algo metido a la caja además: sigue sin decirlo (hay de tickets).
      await montar(
        tester,
        TarjetasRapidas(
          metrics: metricas(detalle: false, tips: 5000, tipsCount: 0, tipsOutside: 80, courtesy: 0, courtesyCount: 0),
        ),
        size: const Size(1280, 800),
      );
      expect(find.text('Q5,080.00'), findsOneWidget);
      expect(find.text('Metidas a la caja'), findsNothing);
    });

    testWidgets('el cobro de envío solo si lo hubo', (tester) async {
      await montar(tester, TarjetasRapidas(metrics: metricas()), size: const Size(1280, 800));
      expect(find.text('Cobro Envío Domicilio'), findsNothing);

      await montar(tester, TarjetasRapidas(metrics: metricas(delivery: 120, deliveryCount: 3)),
          size: const Size(1280, 800));
      expect(find.text('Cobro Envío Domicilio'), findsOneWidget);
      expect(find.text('Q120.00'), findsOneWidget);
      expect(find.text('3 cobros'), findsOneWidget);
    });

    testWidgets('la vista de año no sabe de cortesías ni descuentos: no los inventa', (tester) async {
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(detalle: false, courtesy: 0, courtesyCount: 0)),
        size: const Size(1280, 800),
      );
      expect(find.text('Propinas'), findsOneWidget);
      expect(find.text('Cortesías / Donaciones'), findsNothing);
      expect(find.text('Descuentos'), findsNothing);

      // Sin propinas tampoco queda nada: ni una tarjeta vacía.
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(detalle: false, tips: 0, tipsCount: 0, courtesy: 0, courtesyCount: 0)),
        size: const Size(1280, 800),
      );
      expect(find.text('Propinas'), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('solo se pueden abrir cortesías y propinas, y son las únicas con flecha', (tester) async {
      var cortesias = 0, propinas = 0;
      await montar(tester, TarjetasRapidas(metrics: metricas(), onCourtesyTap: () => cortesias++),
          size: const Size(1280, 800));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Cortesías / Donaciones'));
      expect(cortesias, 1);
      // Sin a dónde llevar, tocar Propinas no hace nada.
      await tester.tap(find.text('Propinas'));
      expect(cortesias, 1);
      expect(propinas, 0);

      // Con las dos, cada una abre lo suyo y las dos llevan flecha.
      await montar(
        tester,
        TarjetasRapidas(metrics: metricas(), onCourtesyTap: () => cortesias++, onTipsTap: () => propinas++),
        size: const Size(1280, 800),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
      await tester.tap(find.text('Propinas'));
      expect(propinas, 1);
      expect(cortesias, 1);

      // Solo propinas: una flecha, y no es la de cortesías.
      await montar(tester, TarjetasRapidas(metrics: metricas(), onTipsTap: () => propinas++), size: const Size(1280, 800));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Cortesías / Donaciones'));
      expect(propinas, 1);

      await montar(tester, TarjetasRapidas(metrics: metricas()), size: const Size(1280, 800));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('Descuentos se abre desde su tarjeta, y solo con a dónde llevar lleva flecha', (tester) async {
      var descuentos = 0;
      // Sin a dónde llevar: ni flecha ni toque.
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 40)), size: const Size(1280, 800));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      await tester.tap(find.text('Descuentos'));
      expect(descuentos, 0);

      // Con a dónde llevar: una flecha (la suya) y el toque abre el detalle.
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 40), onDiscountTap: () => descuentos++),
          size: const Size(1280, 800));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Descuentos'));
      expect(descuentos, 1);

      // En el teléfono, igual.
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 40), onDiscountTap: () => descuentos++),
          size: const Size(390, 844));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Descuentos'));
      expect(descuentos, 2);
    });

    testWidgets('en teléfono, Propinas también se toca y lleva flecha', (tester) async {
      var propinas = 0;
      await montar(tester, TarjetasRapidas(metrics: metricas(), onTipsTap: () => propinas++), size: const Size(390, 844));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Propinas'));
      expect(propinas, 1);
    });

    testWidgets('en teléfono propinas a todo el ancho y debajo las demás de dos en dos; en ancho, todas en una',
        (tester) async {
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 10), onCourtesyTap: () {}),
          size: const Size(360, 800));
      final y = [for (final t in ['Propinas', 'Cortesías / Donaciones', 'Descuentos']) tester.getTopLeft(find.text(t)).dy];
      expect(y[1], greaterThan(y[0]), reason: 'cortesías debajo de propinas');
      expect(y[1], y[2], reason: 'cortesías y descuentos en la misma fila');
      expect(tester.getSize(find.ancestor(of: find.text('Propinas'), matching: find.byType(InicioToque))).width, 360 - 32);
      // Las cifras de la fila quedan a la misma altura aunque "Cortesías / Donaciones"
      // vaya en dos líneas (cada una se achica a su manera: puede variar un pelo).
      expect(tester.getCenter(find.text('Q35.00')).dy, closeTo(tester.getCenter(find.text('Q10.00')).dy, 2));

      // Con el envío: propinas sola, cortesías y descuentos, y el envío solo a todo el ancho.
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 10, delivery: 25)), size: const Size(360, 800));
      final y4 = [
        for (final t in ['Propinas', 'Cortesías / Donaciones', 'Descuentos', 'Cobro Envío Domicilio']) tester.getTopLeft(find.text(t)).dy
      ];
      expect(y4[1], greaterThan(y4[0]));
      expect(y4[1], y4[2]);
      expect(y4[3], greaterThan(y4[2]));
      expect(tester.getSize(find.ancestor(of: find.text('Cobro Envío Domicilio'), matching: find.byType(InicioToque))).width,
          360 - 32);

      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 10)), size: const Size(1280, 800));
      final yy = [for (final t in ['Propinas', 'Cortesías / Donaciones', 'Descuentos']) tester.getTopLeft(find.text(t)).dy];
      expect(yy[0], yy[1]);
      expect(yy[1], yy[2]);

      // A 900: dos columnas, la tercera baja.
      await montar(tester, TarjetasRapidas(metrics: metricas(discounts: 10)), size: const Size(900, 800));
      final y9 = [for (final t in ['Propinas', 'Cortesías / Donaciones', 'Descuentos']) tester.getTopLeft(find.text(t)).dy];
      expect(y9[0], y9[1]);
      expect(y9[2], greaterThan(y9[1]));
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y cifras enormes', (tester) async {
        await montar(
          tester,
          TarjetasRapidas(
            metrics: metricas(tips: 12345678.9, courtesy: 9876543.21, discounts: 5555555.5, delivery: 777777.7),
            onCourtesyTap: () {},
            descuentosCount: 12345,
          ),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Requiere tu atención', () {
    final items = [
      const ItemAtencion(
        gravedad: GravedadAtencion.alta,
        partes: [ParteTexto('Faltante de '), ParteTexto('Q385', negrita: true), ParteTexto(' en el cierre de Ana Cosme')],
        seccion: 'Cierres de caja',
        destino: DestinoAtencion.cierresDeCaja,
      ),
      const ItemAtencion(
        gravedad: GravedadAtencion.media,
        partes: [ParteTexto('2 cortesías sin motivo', negrita: true), ParteTexto(' por Q202')],
        seccion: 'Cortesías',
        destino: DestinoAtencion.cortesias,
      ),
    ];

    testWidgets('sin nada pendiente no se dibuja', (tester) async {
      await montar(tester, AtencionCard(items: const [], onTap: (_) {}));
      expect(find.text('Requiere tu atención'), findsNothing);
    });

    testWidgets('dice cuántos son, qué pasó y de dónde, y tocar uno lo abre', (tester) async {
      final tocados = <ItemAtencion>[];
      await montar(tester, AtencionCard(items: items, onTap: tocados.add));
      expect(find.text('Requiere tu atención'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'la cuenta de pendientes');
      expect(find.textContaining('Faltante de Q385 en el cierre de Ana Cosme'), findsOneWidget);
      expect(find.text('Cierres de caja'), findsOneWidget);
      expect(find.text('Cortesías'), findsOneWidget);

      await tester.tap(find.textContaining('2 cortesías sin motivo'));
      expect(tocados, [items[1]]);
    });

    testWidgets('la insignia cuenta incidencias, no filas', (tester) async {
      await montar(
        tester,
        AtencionCard(
          items: [
            items[0],
            const ItemAtencion(
              gravedad: GravedadAtencion.alta,
              partes: [ParteTexto('4 cierres más', negrita: true), ParteTexto(' con faltante')],
              seccion: 'Cierres de caja',
              destino: DestinoAtencion.cierresDeCaja,
              cuantos: 4,
            ),
          ],
          onTap: (_) {},
        ),
      );
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y nombres larguísimos', (tester) async {
        await montar(
          tester,
          AtencionCard(
            items: [
              ...items,
              const ItemAtencion(
                gravedad: GravedadAtencion.media,
                partes: [
                  ParteTexto('La caja de '),
                  ParteTexto('Ana Lena Katt de la Sucursal Principal de la Zona Cuatro', negrita: true),
                  ParteTexto(' lleva '),
                  ParteTexto('128 días abierta', negrita: true),
                ],
                seccion: 'Cierres de caja · Santa Rosalía de las Flores',
                destino: DestinoAtencion.cierresDeCaja,
              ),
            ],
            onTap: (_) {},
          ),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Requiere tu atención junto a "Ventas por método de pago"', () {
    final muchos = [
      for (var i = 0; i < 9; i++)
        ItemAtencion(
          gravedad: GravedadAtencion.alta,
          partes: [ParteTexto('Faltante de '), ParteTexto('Q${100 + i}', negrita: true), ParteTexto(' en el cierre número $i')],
          seccion: 'Cierres de caja',
          destino: DestinoAtencion.cierresDeCaja,
        ),
    ];

    Widget lado(List<ItemAtencion> items) => InicioLadoALado(
          izquierda: InicioCard(child: PaymentMethodBreakdown(salesByMethod: const {'card': 11081, 'cash': 3144.25})),
          derecha: AtencionCard(items: items, onTap: (_) {}, llenarAlto: true),
          altoMinimo: 200,
        );

    testWidgets('del mismo alto que métodos de pago, aunque traiga muchos avisos: se desplazan por dentro', (tester) async {
      await montar(tester, lado(muchos), size: const Size(1280, 900));
      expect(tester.takeException(), isNull);
      final pago = tester.getRect(find.byType(InicioCard));
      final atencion = tester.getRect(find.byType(AtencionCard));
      expect(atencion.height, pago.height);
      expect(atencion.top, pago.top);
      expect(atencion.left, greaterThan(pago.right), reason: 'a la derecha');
      // El último aviso no se ve hasta desplazar la tarjeta (no la pantalla).
      expect(find.textContaining('cierre número 8').hitTestable(), findsNothing);
      await tester.drag(find.textContaining('cierre número 0'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('cierre número 8').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byType(AtencionCard)), atencion, reason: 'la tarjeta no se movió');
    });

    testWidgets('con pocos avisos tampoco cambia de alto', (tester) async {
      await montar(tester, lado(muchos.take(1).toList()), size: const Size(1280, 900));
      expect(tester.getSize(find.byType(AtencionCard)).height, tester.getSize(find.byType(InicioCard)).height);
    });

    for (final s in const [Size(900, 800), Size(1280, 800)]) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y muchos avisos', (tester) async {
        await montar(tester, lado(muchos), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Requiere tu atención en el teléfono: no más de 3 avisos de alto', () {
    final muchos = [
      for (var i = 0; i < 8; i++)
        ItemAtencion(
          gravedad: GravedadAtencion.alta,
          partes: [ParteTexto('Faltante de '), ParteTexto('Q${100 + i}', negrita: true), ParteTexto(' en el cierre número $i')],
          seccion: 'Cierres de caja',
          destino: DestinoAtencion.cierresDeCaja,
        ),
    ];

    testWidgets('con muchos, mide lo que tres y los demás se desplazan por dentro', (tester) async {
      await montar(tester, AtencionCard(items: muchos.take(3).toList(), onTap: (_) {}, maxFilas: 3), size: const Size(390, 844));
      final conTres = tester.getSize(find.byType(AtencionCard)).height;

      final tocados = <ItemAtencion>[];
      await montar(tester, AtencionCard(items: muchos, onTap: tocados.add, maxFilas: 3), size: const Size(390, 844));
      expect(tester.takeException(), isNull);
      // Casi lo mismo que con tres (solo cambia un poco el margen de abajo).
      expect(tester.getSize(find.byType(AtencionCard)).height, closeTo(conTres, 6));
      expect(find.textContaining('cierre número 7').hitTestable(), findsNothing);
      await tester.drag(find.textContaining('cierre número 1').hitTestable(), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.textContaining('cierre número 7').hitTestable(), findsOneWidget);
      await tester.tap(find.textContaining('cierre número 7').hitTestable());
      expect(tocados, [muchos[7]]);
    });

    testWidgets('con tres o menos, crece normal (sin desplazamiento)', (tester) async {
      await montar(tester, AtencionCard(items: muchos.take(2).toList(), onTap: (_) {}, maxFilas: 3), size: const Size(390, 844));
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.textContaining('cierre número 1'), findsOneWidget);
    });

    for (final s in const [Size(360, 800), Size(390, 844)]) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y muchos avisos', (tester) async {
        await montar(tester, AtencionCard(items: muchos, onTap: (_) {}, maxFilas: 3), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Cajas abiertas', () {
    final hoy = DateTime(2026, 11, 20, 14, 30);

    CashRegisterSummary caja(String quien, DateTime desde) => CashRegisterSummary(
          id: quien,
          userId: quien,
          userName: quien,
          status: 'open',
          openedAt: desde,
        );

    // Los espacios que mete la librería entre la hora y "a. m." pueden ser
    // irrompibles: se igualan para comparar.
    String normal(String t) => t.replaceAll(RegExp('[\u00a0\u202f]'), ' ');

    test('el subtítulo dice quién y desde cuándo, en 12 horas con "a. m."', () {
      expect(subtituloCajasAbiertas([], ahora: hoy), 'Ninguna abierta');
      expect(
        normal(subtituloCajasAbiertas([caja('Marta', DateTime(2026, 11, 20, 8, 2))], ahora: hoy)),
        'Marta desde 8:02 a. m.',
      );
      expect(
        normal(subtituloCajasAbiertas([caja('Luis', DateTime(2026, 11, 20, 15, 30))], ahora: hoy)),
        'Luis desde 3:30 p. m.',
      );
    });

    test('con varias, la más antigua y cuántas más', () {
      final texto = subtituloCajasAbiertas([
        caja('Luis', DateTime(2026, 11, 20, 11)),
        caja('Marta', DateTime(2026, 11, 20, 8, 2)),
        caja('Rosa', DateTime(2026, 11, 20, 12)),
      ], ahora: hoy);
      expect(texto, startsWith('Marta desde '));
      expect(texto, endsWith(' y 2 más'));
    });

    test('una caja de otro día dice el día, no solo la hora', () {
      final texto = subtituloCajasAbiertas([caja('Ana', DateTime(2026, 11, 12, 9))], ahora: hoy);
      expect(texto, 'Ana desde el ${DateFormat('d MMM', 'es').format(DateTime(2026, 11, 12))}');
    });

    testWidgets('la tarjeta dice cuántas, y se abre si hay a dónde ir', (tester) async {
      var abierto = 0;
      await montar(
        tester,
        CajasAbiertasCard(abiertas: [caja('Marta', DateTime.now().subtract(const Duration(hours: 2)))], onTap: () => abierto++),
      );
      expect(find.text('Cajas abiertas'), findsOneWidget);
      expect(find.textContaining('Marta desde'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Cajas abiertas'));
      expect(abierto, 1);

      await montar(tester, const CajasAbiertasCard(abiertas: []));
      expect(find.textContaining('Ninguna abierta'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y un nombre larguísimo', (tester) async {
        await montar(
          tester,
          CajasAbiertasCard(
            abiertas: [
              caja('Ana Lena Katt de la Sucursal Principal de la Zona Cuatro', DateTime(2026, 11, 1, 8)),
              caja('Otra', DateTime(2026, 11, 2)),
            ],
            onTap: () {},
          ),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Cuentas abiertas', () {
    testWidgets('cuántas y cuánto falta por cobrar, sin flecha (no hay a dónde llevar)', (tester) async {
      await montar(
        tester,
        const CuentasAbiertasCard(resumen: CuentasPorCobrar(cuantas: 6, monto: 1240)),
        size: const Size(1280, 800),
      );
      expect(find.text('Cuentas abiertas'), findsOneWidget);
      expect(find.textContaining('6'), findsOneWidget);
      expect(find.textContaining('Q1,240 por cobrar', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      // Tocarla no hace nada ni rompe.
      await tester.tap(find.text('Cuentas abiertas'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('con centavos se ven; sin cuentas dice que no hay nada por cobrar', (tester) async {
      await montar(tester, const CuentasAbiertasCard(resumen: CuentasPorCobrar(cuantas: 1, monto: 1240.5)));
      expect(find.textContaining('Q1,240.50 por cobrar', findRichText: true), findsOneWidget);

      await montar(tester, const CuentasAbiertasCard(resumen: CuentasPorCobrar()));
      expect(find.textContaining('Nada por cobrar', findRichText: true), findsOneWidget);
      expect(find.textContaining('Q0', findRichText: true), findsNothing);
    });

    testWidgets('con otra moneda en la vista, la lleva puesta', (tester) async {
      fijarMoneda('USD');
      await montar(tester, const CuentasAbiertasCard(resumen: CuentasPorCobrar(cuantas: 3, monto: 99)));
      expect(find.textContaining('USD 99 por cobrar', findRichText: true), findsOneWidget);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y una cifra enorme', (tester) async {
        await montar(
          tester,
          const CuentasAbiertasCard(resumen: CuentasPorCobrar(cuantas: 123456, monto: 987654321.55)),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('junto a "Cajas abiertas": lado a lado, también en el teléfono; una sola a todo el ancho',
        (tester) async {
      final cuentas = const CuentasAbiertasCard(resumen: CuentasPorCobrar(cuantas: 6, monto: 1240));
      final cajas = CajasAbiertasCard(
        abiertas: [
          CashRegisterSummary(id: 'a', userId: 'a', userName: 'Marta', status: 'open', openedAt: DateTime.now()),
        ],
        onTap: () {},
      );

      await montar(tester, FilaAhora(tarjetas: [cuentas, cajas]), size: const Size(1280, 800));
      expect(tester.getTopLeft(find.text('Cuentas abiertas')).dy, tester.getTopLeft(find.text('Cajas abiertas')).dy);
      expect(tester.getTopLeft(find.text('Cuentas abiertas')).dx,
          lessThan(tester.getTopLeft(find.text('Cajas abiertas')).dx));

      for (final ancho in [360.0, 390.0]) {
        await montar(tester, FilaAhora(tarjetas: [cuentas, cajas]), size: Size(ancho, 844));
        expect(tester.getTopLeft(find.text('Cajas abiertas')).dy, tester.getTopLeft(find.text('Cuentas abiertas')).dy);
        expect(tester.getTopLeft(find.text('Cuentas abiertas')).dx,
            lessThan(tester.getTopLeft(find.text('Cajas abiertas')).dx));
        expect(tester.getSize(find.byType(CuentasAbiertasCard)).height, tester.getSize(find.byType(CajasAbiertasCard)).height);
        // Compactas: qué es, al lado del ícono; el número y el detalle en UNA línea.
        expect((tester.getCenter(find.text('Cuentas abiertas')).dy - tester.getCenter(find.byIcon(Icons.table_restaurant_rounded)).dy).abs(),
            lessThan(4));
        expect(find.text('6'), findsOneWidget);
        expect(tester.widget<Text>(find.textContaining('Marta desde')).maxLines, 1);
      }

      // Una sola ocupa todo el ancho disponible (1280 − 32 de margen).
      await montar(tester, FilaAhora(tarjetas: [cuentas]), size: const Size(1280, 800));
      expect(tester.getSize(find.byType(CuentasAbiertasCard)).width, 1280 - 32);

      // Ninguna: no ocupa nada.
      await montar(tester, const FilaAhora(tarjetas: []), size: const Size(1280, 800));
      expect(find.byType(CuentasAbiertasCard), findsNothing);
    });

    testWidgets('las dos juntas a la misma altura aunque una lleve más texto', (tester) async {
      await montar(
        tester,
        FilaAhora(tarjetas: [
          const CuentasAbiertasCard(resumen: CuentasPorCobrar(cuantas: 6, monto: 1240)),
          CajasAbiertasCard(
            abiertas: [
              CashRegisterSummary(
                id: 'a',
                userId: 'a',
                userName: 'Ana Lena Katt de la Sucursal Principal de la Zona Cuatro',
                status: 'open',
                openedAt: DateTime.now(),
              ),
              CashRegisterSummary(id: 'b', userId: 'b', userName: 'Otra', status: 'open', openedAt: DateTime.now()),
            ],
            onTap: () {},
          ),
        ]),
        size: const Size(1000, 800),
        escala: 1.35,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(CuentasAbiertasCard)).height,
        tester.getSize(find.byType(CajasAbiertasCard)).height,
      );
    });
  });

  group('Ventas por método de pago', () {
    testWidgets('de mayor a menor, con su parte, y el total', (tester) async {
      await montar(
        tester,
        PaymentMethodBreakdown(salesByMethod: const {'cash': 433, 'card': 2826, '_tips': 0}),
        size: const Size(390, 844),
      );
      expect(find.text('Ventas por método de pago'), findsOneWidget);
      expect(find.text('Tarjeta'), findsOneWidget);
      expect(find.text('Q2,826.00'), findsOneWidget);
      expect(find.text('87%'), findsOneWidget);
      expect(find.text('13%'), findsOneWidget);
      expect(find.text('Q3,259.00'), findsOneWidget);
      // Tarjeta (la mayor) arriba de efectivo.
      expect(tester.getTopLeft(find.text('Tarjeta')).dy, lessThan(tester.getTopLeft(find.text('Efectivo')).dy));
    });

    testWidgets('los métodos propios con su nombre y las propinas al final', (tester) async {
      await montar(
        tester,
        PaymentMethodBreakdown(
          salesByMethod: const {'_tips': 90, 'custom_x1': 300, 'cash': 100},
          customMethodNames: const {'custom_x1': 'Bitcoin'},
        ),
      );
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Propinas')).dy,
        greaterThan(tester.getTopLeft(find.text('Efectivo')).dy),
      );
    });

    testWidgets('sin ventas no se dibuja', (tester) async {
      await montar(tester, PaymentMethodBreakdown(salesByMethod: const {'cash': 0}));
      expect(find.text('Ventas por método de pago'), findsNothing);
    });

    // La pantalla los pone lado a lado, a la misma altura, con un
    // IntrinsicHeight: ahí no puede haber LayoutBuilders (en depuración
    // lanzan, y en producción el alto sale en cero).
    for (final s in const [Size(1280, 800), Size(900, 800)]) {
      testWidgets('junto a "Ventas por sucursal" en pantalla ancha (${s.width.toInt()})', (tester) async {
        await montar(
          tester,
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InicioCard(
                    child: PaymentMethodBreakdown(salesByMethod: const {'card': 2826, 'cash': 433}),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: LocationSalesBreakdown(
                    locations: [
                      LocationModel(id: 'a', name: 'Zona 10', currencySymbol: 'Q'),
                      LocationModel(id: 'b', name: 'Santa Rosalía', currencySymbol: 'Q'),
                    ],
                    orders: const [
                      {'location_id': 'a', 'payment_amount': 1500.0},
                      {'location_id': 'b', 'payment_amount': 500.0},
                    ],
                    expenseItems: const [],
                    purchaseItems: const [],
                  ),
                ),
              ],
            ),
          ),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
        // Las dos tarjetas a la misma altura.
        expect(find.text('Ventas por método de pago'), findsOneWidget);
        expect(find.text('Ventas por sucursal'), findsOneWidget);
      });
    }

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande', (tester) async {
        await montar(
          tester,
          PaymentMethodBreakdown(
            salesByMethod: const {'cash': 12345678.9, 'card': 98765432.1, 'transfer': 5, 'custom_a': 77.7},
            customMethodNames: const {'custom_a': 'Un método propio con un nombre larguísimo de verdad'},
          ),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Resumen financiero', () {
    testWidgets('de la venta bruta al total cobrado, con lo que resta y suma', (tester) async {
      await montar(
        tester,
        SummaryTable(metrics: metricas(discounts: 50)),
        size: const Size(390, 844),
      );
      expect(find.text('Ventas brutas'), findsOneWidget);
      expect(find.text('sin propinas ni envío'), findsOneWidget);
      expect(find.text('Descuentos'), findsOneWidget);
      expect(find.text('Q50.00'), findsOneWidget);
      expect(find.text('Propinas'), findsOneWidget);
      expect(find.text('Total cobrado'), findsOneWidget);
      expect(find.text('Q3,259.00'), findsOneWidget);
      expect(find.text('Número de tickets'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.text('Ticket promedio'), findsOneWidget);
      // Lo que no hubo no ocupa una fila.
      expect(find.text('Reembolsos'), findsNothing);
      expect(find.text('Costos y gastos'.toUpperCase()), findsNothing);
    });

    testWidgets('con costos agrega la utilidad estimada', (tester) async {
      final m = PeriodMetrics(
        totalSales: 1000,
        totalOrders: 10,
        avgTicket: 100,
        prevTotalSales: 0,
        prevTotalOrders: 0,
        prevAvgTicket: 0,
        chartPoints: const [],
        topProducts: const [],
        grossSales: 1000,
        purchaseCosts: 300,
        operationalExpenses: 100,
      );
      await montar(tester, SummaryTable(metrics: m), size: const Size(390, 844));
      expect(find.text('COSTOS Y GASTOS'), findsOneWidget);
      expect(find.text('Compras / insumos'), findsOneWidget);
      expect(find.text('Gastos operacionales'), findsOneWidget);
      expect(find.text('Utilidad estimada'), findsOneWidget);
      expect(find.text('Q600.00'), findsOneWidget);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y todas las filas', (tester) async {
        final m = PeriodMetrics(
          totalSales: 123456789.12,
          totalOrders: 99999,
          avgTicket: 1234.56,
          prevTotalSales: 0,
          prevTotalOrders: 0,
          prevAvgTicket: 0,
          chartPoints: const [],
          topProducts: const [],
          grossSales: 111111111.11,
          discounts: 22222.22,
          refunds: 333.33,
          tips: 4444.44,
          deliveryFees: 555.55,
          tipsOutsideSales: 66.66,
          purchaseCosts: 7777777.77,
          operationalExpenses: 888888.88,
        );
        await montar(tester, SummaryTable(metrics: m), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Categorías', () {
    CategorySummary cat(String n, String clase, int q, double total) =>
        CategorySummary(name: n, classification: clase, quantity: q, total: total);

    final datos = {
      'Comida': [cat('Desayunos', 'Comida', 6, 290)],
      'Bebidas': [
        cat('Cervezas', 'Bebidas', 29, 1005),
        cat('Ron', 'Bebidas', 5, 520),
        cat('Quezalteca', 'Bebidas', 5, 410),
        cat('Jugos', 'Bebidas', 2, 99), // el cuarto no sale: es un top 3
      ],
    };

    testWidgets('top 3 de cada clasificación, con su total y lo vendido', (tester) async {
      await montar(tester, TopCategoriesCarousel(categoriesByClassification: datos), size: const Size(390, 844));
      expect(find.text('Estas categorías son las que más vendes'), findsOneWidget);
      expect(find.text('Comidas'), findsOneWidget);
      expect(find.text('Q290 en total'), findsOneWidget);
      expect(find.text('Q2,034 en total'), findsOneWidget, reason: 'el total cuenta las cuatro');
      expect(find.text('Cervezas'), findsOneWidget);
      expect(find.text('29 vendidos'), findsOneWidget);
      expect(find.text('Jugos'), findsNothing);
    });

    // Es un carrusel: una sola fila de tarjetas de ancho fijo, que se desliza si
    // no caben (el dueño pidió que no fueran una cuadrícula de dos columnas).
    Finder tarjetaDe(String clasificacion) =>
        find.ancestor(of: find.text(clasificacion), matching: find.byType(InicioCard)).first;
    final carrusel = find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);

    testWidgets('en ancho, todas en UNA fila y más angostas que la mitad', (tester) async {
      final tres = {
        ...datos,
        'Postres': [cat('Pastel', 'Postres', 3, 90)],
      };
      await montar(tester, TopCategoriesCarousel(categoriesByClassification: tres), size: const Size(1280, 800));
      final y = [for (final t in ['Comidas', 'Bebidas', 'Postres']) tester.getTopLeft(find.text(t)).dy];
      expect(y[0], y[1]);
      expect(y[1], y[2], reason: 'la tercera ya no baja a otra fila');
      for (final t in ['Comidas', 'Bebidas', 'Postres']) {
        final ancho = tester.getSize(tarjetaDe(t)).width;
        expect(ancho, inInclusiveRange(300, 420), reason: t);
      }
      // Caben las tres, sin tener que deslizar.
      expect(tester.getTopRight(tarjetaDe('Postres')).dx, lessThanOrEqualTo(1280 - 16));
    });

    testWidgets('con solo dos no se estiran: siguen angostas, pegadas a la izquierda', (tester) async {
      await montar(tester, TopCategoriesCarousel(categoriesByClassification: datos), size: const Size(1280, 800));
      expect(tester.getSize(tarjetaDe('Comidas')).width, 420);
      expect(tester.getTopLeft(find.text('Comidas')).dy, tester.getTopLeft(find.text('Bebidas')).dy);
      // 16 de margen + 420 + 16 de separación + 420: no llegan al final de la fila.
      expect(tester.getTopRight(tarjetaDe('Bebidas')).dx, closeTo(16 + 420 + 16 + 420, 1));
    });

    testWidgets('en teléfono también una fila, y la segunda asoma para decir que se desliza', (tester) async {
      await montar(tester, TopCategoriesCarousel(categoriesByClassification: datos), size: const Size(390, 844));
      expect(tester.getTopLeft(find.text('Bebidas')).dy, tester.getTopLeft(find.text('Comidas')).dy);
      final segunda = tarjetaDe('Bebidas');
      expect(tester.getTopLeft(segunda).dx, lessThan(390), reason: 'empieza a la vista');
      expect(tester.getTopRight(segunda).dx, greaterThan(390), reason: 'y se corta: hay más a la derecha');
    });

    testWidgets('con muchas clasificaciones se desliza, con el dedo y con el ratón', (tester) async {
      final cinco = {
        for (final k in ['Comida', 'Bebidas', 'Postres', 'Servicios', 'Otros']) k: [cat('Algo de $k', k, 2, 10)],
      };
      await montar(tester, TopCategoriesCarousel(categoriesByClassification: cinco), size: const Size(390, 844));
      final antes = tester.getTopLeft(tarjetaDe('Otros')).dx;
      expect(antes, greaterThan(390), reason: 'la última empieza fuera de pantalla');

      // Con el dedo.
      await tester.drag(carrusel, const Offset(-600, 0));
      await tester.pumpAndSettle();
      final conDedo = tester.getTopLeft(tarjetaDe('Otros')).dx;
      expect(conDedo, lessThan(antes - 300));

      // Con el ratón (el navegador de escritorio).
      final g = await tester.startGesture(
        tester.getCenter(tarjetaDe('Postres')),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(-200, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(tarjetaDe('Otros')).dx, lessThan(conDedo));
    });

    test('el ancho de cada tarjeta', () {
      // Teléfono: el 84% de lo disponible, entre 250 y 340.
      expect(TopCategoriesCarousel.anchoTarjeta(358, 2), closeTo(300.7, 0.1));
      expect(TopCategoriesCarousel.anchoTarjeta(200, 2), 250);
      expect(TopCategoriesCarousel.anchoTarjeta(760, 5), 340);
      // Ancho: lo que les toca, pero entre 300 y 420.
      expect(TopCategoriesCarousel.anchoTarjeta(1248, 3), closeTo(405.3, 0.1));
      expect(TopCategoriesCarousel.anchoTarjeta(1248, 2), 420);
      expect(TopCategoriesCarousel.anchoTarjeta(1248, 1), 420);
      expect(TopCategoriesCarousel.anchoTarjeta(1248, 5), 300);
      expect(TopCategoriesCarousel.anchoTarjeta(800, 3), 300);
      // Sin tarjetas no divide entre cero.
      expect(TopCategoriesCarousel.anchoTarjeta(1248, 0), 420);
    });

    testWidgets('sin categorías no se dibuja', (tester) async {
      await montar(tester, const TopCategoriesCarousel(categoriesByClassification: {}));
      expect(find.text('Estas categorías son las que más vendes'), findsNothing);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande, cinco clasificaciones y nombres larguísimos',
          (tester) async {
        final todas = {
          for (final k in ['Comida', 'Bebidas', 'Postres', 'Servicios', 'Otros'])
            k: [
              cat('Una categoría con un nombre larguísimo de verdad $k', k, 123456, 9876543.21),
              cat('Otra', k, 2, 10),
            ],
        };
        await montar(tester, TopCategoriesCarousel(categoriesByClassification: todas), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Platillos vendidos', () {
    ProductSummary prod(String n, String clase, int q, double total, {double prev = 0}) => ProductSummary(
          name: n,
          category: clase,
          quantity: q,
          total: total,
          prevQuantity: 0,
          prevTotal: prev,
        );

    final productos = [
      prod('Omelette - Jamón y queso', 'Comida', 2, 100),
      prod('Acaí Bowl - Individual', 'Comida', 1, 50, prev: 150),
      prod('Cerveza Gallo', 'Bebidas', 29, 1005, prev: 810),
      prod('Ron - Trago', 'Bebidas', 5, 520, prev: 472),
    ];

    Widget lista({double tips = 293}) => ProductsList(
          products: productos,
          prevLabel: 'Ayer',
          tips: tips,
          totalSales: 3259,
        );

    testWidgets('pestañas por clasificación: cada una con sus platillos y su total', (tester) async {
      await montar(tester, lista(), size: const Size(1280, 900));
      expect(find.text('Platillos vendidos'), findsOneWidget);
      expect(find.text('Propinas no incluidas'), findsOneWidget);
      expect(find.text('vs Ayer'), findsOneWidget);
      expect(find.text('Comidas'), findsOneWidget);
      expect(find.text('Bebidas'), findsOneWidget);
      expect(find.text('Omelette - Jamón y queso'), findsOneWidget);
      expect(find.text('Cerveza Gallo'), findsNothing);
      expect(find.text('Total (2 platillos)'), findsOneWidget);
      expect(find.text('Q150'), findsOneWidget);

      await tester.tap(find.text('Bebidas'));
      await tester.pumpAndSettle();
      expect(find.text('Bebidas vendidas'), findsOneWidget);
      expect(find.text('Cerveza Gallo'), findsOneWidget);
      expect(find.text('Omelette - Jamón y queso'), findsNothing);
      expect(find.text('Total (2 bebidas)'), findsOneWidget);
    });

    testWidgets('la variación: sube en verde, baja en rojo, sin dato un guion', (tester) async {
      await montar(tester, lista(), size: const Size(1280, 900));
      // Acaí: de 150 a 50 → −67%. Omelette: sin período anterior.
      expect(find.text('67%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(find.text('—'), findsOneWidget);

      await tester.tap(find.text('Bebidas'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNWidgets(2));
      expect(find.text('24%'), findsOneWidget); // 1005 contra 810
    });

    testWidgets('en teléfono esconde "vs Ayer" y deja el Excel solo con el ícono', (tester) async {
      await montar(tester, lista(), size: const Size(390, 900));
      expect(find.text('vs Ayer'), findsNothing);
      expect(find.text('Excel'), findsNothing);
      expect(find.byTooltip('Descargar Excel'), findsOneWidget);
      expect(find.byTooltip('Filtrar'), findsOneWidget);
    });

    testWidgets('sin ventas lo dice, sin botones', (tester) async {
      await montar(
        tester,
        const ProductsList(products: [], prevLabel: 'Ayer'),
        size: const Size(390, 900),
      );
      expect(find.text('Sin ventas en este período'), findsOneWidget);
      expect(find.byTooltip('Descargar Excel'), findsNothing);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande y nombres larguísimos', (tester) async {
        await montar(
          tester,
          ProductsList(
            products: [
              for (var i = 0; i < 6; i++)
                prod('Un platillo con un nombre larguísimo de verdad número $i con extras', i.isEven ? 'Comida' : 'Bebidas',
                    123456, 98765432.1, prev: 1),
            ],
            prevLabel: 'el mes pasado',
            tips: 10,
            totalSales: 5,
          ),
          size: s,
          escala: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Gráfica por hora', () {
    List<double> horas(Map<int, double> v) => [for (var h = 0; h < 24; h++) v[h] ?? 0];

    DayHourlyPoints dia(String label, DateTime? fecha, Map<int, double> v) => DayHourlyPoints(
          dayLabel: label,
          hourlyAmounts: horas(v),
          hourlyOrders: List<int>.filled(24, 0),
          fecha: fecha,
        );

    testWidgets('hoy termina en la hora actual; los demás días llegan a la última hora', (tester) async {
      final hoy = DateUtils.dateOnly(DateTime.now());
      final dias = [
        dia('Lun 16', hoy.subtract(const Duration(days: 4)), {9: 100, 12: 500, 22: 300}),
        dia('Mar 17', hoy.subtract(const Duration(days: 3)), {9: 120, 13: 450}),
        dia('Mié 18', hoy.subtract(const Duration(days: 2)), {10: 90, 20: 800}),
        dia('Jue 19', hoy.subtract(const Duration(days: 1)), {11: 70, 21: 900}),
        // Solo a las 0: con ventas en una hora posterior a la de ahora la línea
        // llega hasta ahí (ver la prueba de abajo), y entre las 12 y la 1 de la
        // madrugada esta prueba dejaba de ser cierta.
        dia('Hoy', hoy, {0: 50}),
      ];
      await montar(
        tester,
        SalesChart(points: const [], mode: PeriodMode.day, weeklyHourly: dias),
        size: const Size(1280, 900),
      );
      final antes = DateTime.now().hour;
      final barras = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      final despues = DateTime.now().hour;
      expect(barras, hasLength(5));
      for (var i = 0; i < 4; i++) {
        expect(barras[i].spots, hasLength(24), reason: 'día ${i + 1}');
        expect(barras[i].barWidth, 2);
      }
      // Hoy: de las 0 a la hora de ahora, y más gruesa.
      expect([antes + 1, despues + 1], contains(barras[4].spots.length));
      expect(barras[4].barWidth, 3);
      // Y la leyenda dice los días.
      expect(find.text('Lun 16'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
    });

    testWidgets('una venta de hoy en una hora posterior a la del teléfono no se pierde', (tester) async {
      // El reloj del teléfono puede ir atrasado frente al del punto de venta:
      // la línea de hoy llega hasta la última hora con ventas, no solo hasta "ahora".
      final hoy = DateUtils.dateOnly(DateTime.now());
      final dias = [
        dia('Lun 16', hoy.subtract(const Duration(days: 1)), {9: 100}),
        dia('Hoy', hoy, {0: 50, 23: 80}),
      ];
      await montar(
        tester,
        SalesChart(points: const [], mode: PeriodMode.day, weeklyHourly: dias),
        size: const Size(1280, 900),
      );
      final barras = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      expect(barras[1].spots, hasLength(24));
      expect(barras[1].spots.last.y, 80);
    });

    testWidgets('con más de tres días con ventas, el resumen en palabras', (tester) async {
      final lunes = DateTime(2026, 11, 16);
      final dias = [
        for (var i = 0; i < 5; i++)
          dia('Día $i', lunes.add(Duration(days: i)), {for (var h = 9; h < 23; h++) h: 100.0 + i * 10 + (h == 21 ? 900 : 0)}),
      ];
      await montar(
        tester,
        SalesChart(points: const [], mode: PeriodMode.day, weeklyHourly: dias),
        size: const Size(1280, 900),
      );
      // Es un RichText (lo importante va en otro color).
      expect(find.textContaining('Tu mejor día de esta semana fue', findRichText: true), findsOneWidget);
      expect(find.textContaining('es cuando vendes más', findRichText: true), findsOneWidget);
    });

    for (final s in tamanos) {
      testWidgets('cabe a ${s.width.toInt()} con letra grande, en cada modo', (tester) async {
        final puntos = [
          for (var i = 0; i < 12; i++) PeriodPoint(label: 'P$i', amount: 1000.0 * (i + 1), orders: i),
        ];
        final lunes = DateTime(2026, 11, 16);
        final dias = [
          for (var i = 0; i < 7; i++)
            dia('Día $i', lunes.add(Duration(days: i)), {for (var h = 8; h < 23; h++) h: 100.0 * (i + 1) * (h - 6)}),
        ];
        for (final modo in PeriodMode.values) {
          await montar(
            tester,
            SalesChart(
              points: puntos,
              prevPoints: puntos.reversed.toList(),
              mode: modo,
              weeklyHourly: dias,
              monthlyDailyPoints: [for (var i = 0; i < 30; i++) PeriodPoint(label: '$i', amount: 100.0 * i, orders: i)],
            ),
            size: s,
            escala: 1.35,
          );
          expect(tester.takeException(), isNull, reason: '$modo a ${s.width}');
        }
      });
    }
  });
}
