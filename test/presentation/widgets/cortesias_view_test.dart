import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/cortesias_data.dart';
import 'package:saborpro_reports/data/models/dashboard_data.dart';
import 'package:saborpro_reports/presentation/widgets/cortesias_view.dart';
import 'package:saborpro_reports/presentation/widgets/metric_cards.dart';

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
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(escala)),
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
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  // La pantalla real mete el cuerpo en el cambio de sucursal
  // (LocationContentSwitcher), que es un AnimatedSwitcher: lo pone en un Stack
  // centrado y con restricciones sueltas. Un SingleChildScrollView mide lo que
  // mide su contenido, así que sin pedidos (contenido bajito) todo quedaba al
  // medio de la pantalla, con un hueco enorme entre las pestañas y la tarjeta.
  // El `wrap` de abajo no lo ve: el Scaffold da restricciones firmes.
  group('dentro del cambio de sucursal', () {
    for (final tam in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets('sin datos el contenido arranca arriba, no al medio ($tam)',
          (tester) async {
        tamano(tester, tam);
        const arribaDelArea = 100.0; // el encabezado y las pestañas
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
                        child: const CortesiasReportBody(report: CortesiasReport.empty),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // El área desplazable llena todo el alto (jalar para actualizar tiene
        // que funcionar también sobre lo que queda debajo de las tarjetas)...
        expect(
          tester.getSize(find.byType(SingleChildScrollView)).height,
          tam.height - arribaDelArea,
        );
        // ...y la primera tarjeta arranca bajo las pestañas: 8 de relleno más
        // lo que ocupa el rótulo dentro de la tarjeta, no un hueco de cientos.
        final rotulo = tester.getTopLeft(find.text('Valor regalado')).dy;
        expect(rotulo, lessThan(arribaDelArea + 60));
      });
    }
  });

  group('a 360dp', () {
    testWidgets('no desborda con datos completos y llega hasta el final',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CortesiasReportBody(
        report: _reporte(),
        nombresUsuario: const {'u1': 'Ana María de los Ángeles Pérez'},
        nombresSucursal: const {'s1': 'Centro', 's2': 'Zona 10'},
        incompleto: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Valor regalado'), findsOneWidget);
      expect(find.textContaining('más pedidos de los que se pueden leer'),
          findsOneWidget);

      // En el teléfono todo va uno debajo del otro y la lista al final.
      await bajarHasta(tester, find.text('¿Quién regala?'));
      await bajarHasta(tester, find.text('¿Por qué se regala?'));
      await bajarHasta(tester, find.text('¿Qué se regala?'));
      await bajarHasta(tester, find.text('Pedidos'));
      await bajarHasta(tester, find.textContaining('Ver los otros'));
      await tester.tap(find.textContaining('Ver los otros'));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Pedido viejo sin fecha'));
    });

    testWidgets('con letra grande tampoco desborda', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(
        CortesiasReportBody(
          report: _reporte(),
          nombresUsuario: const {'u1': 'Ana'},
          nombresSucursal: const {'s1': 'Centro', 's2': 'Zona 10'},
        ),
        escala: 1.35,
      ));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Pedidos'));
      await bajarHasta(tester, find.textContaining('Ver los otros'));
    });

    testWidgets('vacío dice que no hubo, no muestra listas', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(
          wrap(const CortesiasReportBody(report: CortesiasReport.empty)));
      await tester.pumpAndSettle();

      expect(find.text('No hubo cortesías ni donaciones en este período.'),
          findsOneWidget);
      expect(find.text('¿Qué se regala?'), findsNothing);
      expect(find.text('¿Quién regala?'), findsNothing);
      expect(find.textContaining('sin motivo'), findsNothing);
    });

    testWidgets('el total es el del reporte y cada pedido trae sus platillos',
        (tester) async {
      tamano(tester, const Size(360, 640));
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('Hamburguesa clásica', qty: 2, price: 45, by: 'u1',
              reason: 'Cumpleaños'),
          _item('Limonada', qty: 1, price: 15, type: 'DONACION'),
        ], no: 7, prefix: 'B', table: 'Mesa 4'),
      ]);
      await tester.pumpWidget(wrap(CortesiasReportBody(
        report: r,
        nombresUsuario: const {'u1': 'Ana'},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Q105.00'), findsWidgets);
      expect(find.text('3 platillos · prom. Q105.00'), findsOneWidget);
      // Cortesías y donaciones por separado.
      expect(find.text('Q90.00'), findsWidgets);
      expect(find.text('Q15.00'), findsWidgets);

      await bajarHasta(tester, find.text('Mesa 4 · #B7'));
      // "Regalado" y no "Total": no es el total del ticket.
      await bajarHasta(tester, find.text('Regalado Q105.00'));
      // Quién y por qué; la limonada no dice por qué.
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('Cumpleaños'), findsWidgets);
      expect(find.text('Sin motivo'), findsWidgets);
      // El pedido mezcla los dos tipos: cada renglón dice cuál es.
      expect(find.text('Donación'), findsWidgets);
    });

    testWidgets('guion solo si no hubo; si hubo y valió cero, Q0.00',
        (tester) async {
      tamano(tester, const Size(360, 640));
      final r = CortesiasReport.desde([
        _orden('a', [
          _item('Café', price: 12),
          _item('Arma tu bowl', price: 0, type: 'DONACION'),
        ]),
      ]);
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r)));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNothing);
      expect(find.text('Q0.00'), findsWidgets);

      final soloCortesia = CortesiasReport.desde([
        _orden('a', [_item('Café', price: 12)]),
      ]);
      await tester.pumpWidget(wrap(CortesiasReportBody(report: soloCortesia)));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('el monto va con sus extras y se ve cuáles', (tester) async {
      tamano(tester, const Size(360, 640));
      final r = CortesiasReport.desde([
        _orden('a', [
          {
            ..._item('Hamburguesa', qty: 2, price: 55),
            'modifiers': [
              {'name': 'Tocino', 'price': 10, 'qty': 1},
              {'name': 'Queso', 'price': 8, 'qty': 1},
            ],
          },
        ], table: 'Mesa 2'),
      ]);
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r)));
      await tester.pumpAndSettle();

      expect(find.textContaining('con sus extras'), findsOneWidget);
      expect(find.textContaining('redondeo'), findsNothing);
      // Q146 como el ticket, no Q110.
      expect(find.text('Q146.00'), findsWidgets);
      expect(find.text('Q110.00'), findsNothing);
      await bajarHasta(tester, find.text('Tocino · Queso'));
    });

    testWidgets('con 21 pedidos dice "Ver el otro pedido"', (tester) async {
      tamano(tester, const Size(360, 640));
      final r = CortesiasReport.desde([
        for (var i = 0; i < 21; i++)
          _orden('o$i', [_item('Platillo $i', price: 10.0 + i)]),
      ]);
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r)));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Ver el otro pedido'));
      expect(find.textContaining('Ver los otros 1'), findsNothing);
    });

    testWidgets('convertido avisa que las partes pueden no sumar exacto',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(
          CortesiasReportBody(report: _reporte(), convertido: true)));
      await tester.pumpAndSettle();
      expect(find.textContaining('por el redondeo'), findsOneWidget);
    });
  });

  group('vista de año', () {
    CortesiasReport r105() => CortesiasReport.desde([
          _orden('a', [_item('Hamburguesa', qty: 2, price: 45)]),
          _orden('b', [_item('Limonada', price: 15)]),
        ]);

    testWidgets('si la tarjeta dice otra cosa, se avisa', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(
          wrap(CortesiasReportBody(report: r105(), totalTarjeta: 90)));
      await tester.pumpAndSettle();
      expect(find.textContaining('La tarjeta del Inicio dice Q90.00'),
          findsOneWidget);
    });

    testWidgets('si coincide al centavo, no se avisa nada', (tester) async {
      tamano(tester, const Size(360, 640));
      // Una diferencia que no llega al centavo no es una diferencia.
      await tester.pumpWidget(
          wrap(CortesiasReportBody(report: r105(), totalTarjeta: 105.001)));
      await tester.pumpAndSettle();
      expect(find.textContaining('La tarjeta del Inicio'), findsNothing);
    });

    testWidgets('un centavo es redondeo; dos ya son una diferencia',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(
          wrap(CortesiasReportBody(report: r105(), totalTarjeta: 105.01)));
      await tester.pumpAndSettle();
      expect(find.textContaining('La tarjeta del Inicio'), findsNothing);

      await tester.pumpWidget(
          wrap(CortesiasReportBody(report: r105(), totalTarjeta: 105.02)));
      await tester.pumpAndSettle();
      expect(find.textContaining('La tarjeta del Inicio dice Q105.02'),
          findsOneWidget);
    });

    testWidgets('dice a qué hora se bajó, y el aviso no afirma cuál está al día',
        (tester) async {
      tamano(tester, const Size(360, 640));
      final hora = DateTime.now();
      await tester.pumpWidget(wrap(
          CortesiasReportBody(report: r105(), totalTarjeta: 105, bajadoA: hora)));
      await tester.pumpAndSettle();
      expect(find.textContaining('para actualizar los pedidos del año, bajados a las'),
          findsOneWidget);
      // "p. m." ya trae su punto: no puede salir "p. m..".
      expect(find.textContaining('..'), findsNothing);

      await tester.pumpWidget(wrap(
          CortesiasReportBody(report: r105(), totalTarjeta: 155, bajadoA: hora)));
      await tester.pumpAndSettle();
      expect(find.textContaining('de los pedidos bajados a las'), findsOneWidget);
      expect(find.textContaining('actualizar los dos'), findsOneWidget);
      expect(find.textContaining('es el de ahora'), findsNothing);
      // Con el aviso a la vista, la línea de la hora no se repite.
      expect(find.textContaining('para actualizar los pedidos del año'), findsNothing);
    });

    testWidgets('fuera del año no hay con qué comparar', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r105())));
      await tester.pumpAndSettle();
      expect(find.textContaining('La tarjeta del Inicio'), findsNothing);
    });

    testWidgets('el año no se baja solo: se pide con el botón', (tester) async {
      tamano(tester, const Size(360, 640));
      var pedidos = 0;
      await tester.pumpWidget(
          wrap(PanelDetalleAnio(onCargar: () => pedidos++), escala: 1.35));
      await tester.pumpAndSettle();

      expect(pedidos, 0);
      await tester.tap(find.text('Cargar el detalle del año'));
      expect(pedidos, 1);
    });

    testWidgets('mientras baja: rueda y sin botón', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(
          wrap(PanelDetalleAnio(onCargar: () {}, cargando: true)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('si falla: el error y "Intentar de nuevo"', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(PanelDetalleAnio(
        onCargar: () {},
        error: 'No se pudieron leer los pedidos del año: sin conexión',
      ), escala: 1.35));
      await tester.pumpAndSettle();

      expect(find.textContaining('sin conexión'), findsOneWidget);
      expect(find.text('Intentar de nuevo'), findsOneWidget);
    });
  });

  testWidgets('en pantalla ancha va en dos columnas sin desbordar',
      (tester) async {
    tamano(tester, const Size(1280, 800));
    await tester.pumpWidget(wrap(CortesiasReportBody(
      report: _reporte(),
      nombresSucursal: const {'s1': 'Centro', 's2': 'Zona 10'},
    )));
    await tester.pumpAndSettle();

    // ¿Quién? y ¿Por qué? lado a lado, y los pedidos en tabla.
    final quien = tester.getTopLeft(find.text('¿Quién regala?'));
    final porque = tester.getTopLeft(find.text('¿Por qué se regala?'));
    expect(porque.dx, greaterThan(quien.dx));
    expect(porque.dy, quien.dy);
    expect(find.text('QUIÉN · MOTIVO'), findsOneWidget);
    expect(find.text('Regalado Q105.00'), findsNothing);
  });

  group('lo nuevo del diseño', () {
    CortesiasReport r() => CortesiasReport.desde([
          _orden('a', [_item('Hamburguesa', qty: 2, price: 45, by: 'u1', reason: 'Cumpleaños')],
              table: 'Mesa 1', no: 1),
          _orden('b', [_item('Limonada', price: 15, by: 'u2')], table: 'Mesa 2', no: 2),
          _orden('c', [_item('Pastel', price: 30, type: 'DONACION', by: 'u2', reason: 'Albergue')],
              table: 'Mesa 3', no: 3),
        ]);
    const nombres = {'u1': 'Ana Cosme', 'u2': 'Carlos Pérez'};

    testWidgets('qué parte de las ventas se regaló, solo si se sabe la venta', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r(), ventas: 1350)));
      await tester.pumpAndSettle();
      expect(find.text('De tus ventas'), findsOneWidget);
      expect(find.text('10.0%'), findsOneWidget);
      expect(find.text('Vendiste Q1,350.00'), findsOneWidget);

      await tester.pumpWidget(wrap(CortesiasReportBody(report: r())));
      await tester.pumpAndSettle();
      expect(find.text('De tus ventas'), findsNothing);
    });

    testWidgets('avisa lo que no tiene motivo y "Ver cuáles" filtra', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r(), nombresUsuario: nombres)));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 cortesía sin motivo', findRichText: true), findsOneWidget);
      expect(find.textContaining('Q15.00. Pide que siempre', findRichText: true), findsOneWidget);

      await bajarHasta(tester, find.text('Ver cuáles'));
      await tester.tap(find.text('Ver cuáles'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 3'), findsOneWidget);
      expect(find.text('Regalado Q15.00'), findsOneWidget);
      expect(find.text('Regalado Q90.00'), findsNothing);
    });

    testWidgets('quién regala: de más a menos, y tocar filtra sus pedidos', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r(), nombresUsuario: nombres)));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('¿Quién regala?'));
      final ana = tester.getTopLeft(find.text('Ana Cosme').first);
      final carlos = tester.getTopLeft(find.text('Carlos Pérez').first);
      expect(ana.dy, lessThan(carlos.dy)); // Q90 antes que Q45
      expect(find.text('1 sin motivo'), findsOneWidget); // la limonada de Carlos

      await bajarHasta(tester, find.text('Carlos Pérez').first);
      await tester.tap(find.text('Carlos Pérez').first);
      await tester.pumpAndSettle();
      expect(find.text('2 de 3'), findsOneWidget);
      // Se quita con la equis del filtro.
      await bajarHasta(tester, find.byIcon(Icons.close_rounded));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('3 de 3'), findsOneWidget);
    });

    testWidgets('por qué se regala, con "Sin motivo" aparte', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CortesiasReportBody(report: r(), nombresUsuario: nombres)));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('¿Por qué se regala?'));
      expect(find.text('Cumpleaños'), findsWidgets);
      expect(find.text('Albergue'), findsWidgets);
      expect(find.text('Sin motivo'), findsWidgets);
    });
  });

  group('tarjeta del Inicio', () {
    PeriodMetrics metricas() => PeriodMetrics(
          totalSales: 1000,
          totalOrders: 10,
          avgTicket: 100,
          prevTotalSales: 900,
          prevTotalOrders: 9,
          prevAvgTicket: 100,
          chartPoints: const [],
          topProducts: const [],
          courtesyTotal: 840,
          courtesyCount: 13,
        );

    // A 1000 y no a 360: con la letra de los tests (cada letra es un cuadro)
    // las tres tarjetas de arriba, que no son parte de esto, ya desbordan a
    // 360. Con la letra real caben; lo que se prueba aquí es el toque.
    testWidgets('tocar Cortesías abre el detalle', (tester) async {
      tamano(tester, const Size(1000, 800));
      var abierto = 0;
      await tester.pumpWidget(wrap(SingleChildScrollView(
        child: MetricCards(metrics: metricas(), onCourtesyTap: () => abierto++),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Cortesías / Donaciones'));
      expect(abierto, 1);
    });

    testWidgets('sin acción no lleva flecha', (tester) async {
      tamano(tester, const Size(1000, 800));
      await tester.pumpWidget(wrap(SingleChildScrollView(
        child: MetricCards(metrics: metricas()),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Cortesías / Donaciones'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });
}

Map<String, dynamic> _item(
  String name, {
  num qty = 1,
  num price = 10,
  String type = 'CORTESIA',
  String? reason,
  String? by,
}) =>
    {
      'name': name,
      'qty': qty,
      'unit_price': price,
      'is_courtesy': true,
      'courtesy_type': type,
      if (reason != null) 'courtesy_reason': reason,
      if (by != null) 'courtesy_by_user_id': by,
    };

Map<String, dynamic> _orden(
  String id,
  List<Object?> items, {
  Object? paidAt,
  String type = 'dine_in',
  String? table,
  int? no,
  String? prefix,
  String? customer,
  String? location,
}) =>
    {
      '_docId': id,
      'items': items,
      'paid_at': paidAt ?? Timestamp.fromDate(DateTime(2026, 11, 5, 13, 40)),
      'type': type,
      if (table != null) 'table_name': table,
      if (no != null) 'order_no': no,
      if (prefix != null) 'order_prefix': prefix,
      if (customer != null) 'customer_name': customer,
      if (location != null) 'location_id': location,
    };

/// Más de 20 pedidos (para el "Ver los otros"), nombres larguísimos, montos
/// de seis cifras, los dos tipos mezclados y de dos sucursales.
CortesiasReport _reporte() {
  final ordenes = <Map<String, dynamic>>[
    _orden('largo', [
      _item(
        'Parrillada familiar especial de la casa con chorizo, costilla, '
        'puyazo y guarniciones a elegir',
        qty: 12,
        price: 9999.99,
        by: 'u1',
        reason: 'Evento de la empresa con más de cuarenta invitados que '
            'llegaron tarde',
      ),
      _item('Agua pura', qty: 3, price: 8, type: 'DONACION', by: 'u1'),
    ],
        type: 'delivery',
        no: 123456,
        prefix: 'AB',
        customer: 'Fundación de Niños con un nombre muy largo de verdad',
        location: 's1'),
    for (var i = 0; i < 24; i++)
      _orden('o$i', [_item('Platillo $i', qty: 1 + i % 3, price: 25.5 + i)],
          paidAt: Timestamp.fromDate(DateTime(2026, 11, 1 + i % 6, 8 + i % 12)),
          table: 'Mesa ${i + 1}',
          no: i + 1,
          location: i.isEven ? 's1' : 's2'),
    {
      ..._orden('sinfecha', [_item('Pedido viejo sin fecha', price: 5)],
          location: 's2'),
      'paid_at': null,
    },
  ];
  return CortesiasReport.desde(ordenes);
}
