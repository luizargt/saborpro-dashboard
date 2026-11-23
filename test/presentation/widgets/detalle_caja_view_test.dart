import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/detalle_caja.dart';
import 'package:saborpro_reports/presentation/widgets/detalle_caja_view.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';

/// El detalle de un corte sin Firebase: la pantalla real carga los pedidos de la
/// caja y se los pasa ya leídos. Cualquier "RenderFlex overflowed" hace fallar la
/// prueba por sí sola.
///
/// Los seis pedidos del día (todo a mano):
///   E1   Ana   efectivo  sub 100            propina 9     pagó 109
///   E2   Ana   tarjeta   sub 250  desc 25   propina 22.5  pagó 247.5
///   AL1  Alex  efectivo  sub 50             propina 5     pagó 55
///   AL2  Alex  tarjeta   sub 80   cort 40   propina 8     pagó 48
///   L1   Juan  Vales     (sin subtotal)                   pagó 60
///   E3   Ana   mixto     (sin subtotal)                   pagó 30
/// Total pagado Q549.50, subtotal Q570, descuentos Q25, propinas Q44.50, cortesías Q40.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  final caja = CashRegisterSummary(
    id: 'cr-ana',
    userId: 'u-ana',
    userName: 'Ana Cosme',
    status: 'closed',
    openedAt: DateTime(2026, 11, 20, 18),
    closedAt: DateTime(2026, 11, 21, 1, 25),
    locationId: 'gt',
    locationName: 'Restaurante Lena’s Atlantis',
  );

  Map<String, dynamic> pedido(
    String numero,
    String usuario,
    String metodo,
    double pago, {
    double? subtotal,
    double desc = 0,
    double propina = 0,
    double cortesia = 0,
    DateTime? hora,
  }) =>
      {
        'order_no': numero,
        'paid_by_user_name': usuario,
        'payment_method': metodo,
        'payment_amount': pago,
        if (subtotal != null) 'subtotal': subtotal,
        'discount_amount': desc,
        'tip_amount': propina,
        'paid_at': Timestamp.fromDate(hora ?? DateTime(2026, 11, 21, 1, 2)),
        if (cortesia > 0)
          'items': [
            {'is_courtesy': true, 'qty': 1, 'unit_price': cortesia},
          ],
      };

  DetalleCaja seis() => DetalleCaja.desde(
        [
          pedido('E1', 'Ana Cosme', 'cash', 109, subtotal: 100, propina: 9, hora: DateTime(2026, 11, 21, 1, 2)),
          pedido('E2', 'Ana Cosme', 'card', 247.5, subtotal: 250, desc: 25, propina: 22.5, hora: DateTime(2026, 11, 21, 0, 55)),
          pedido('AL1', 'Alex Ojom', 'cash', 55, subtotal: 50, propina: 5, hora: DateTime(2026, 11, 20, 23, 50)),
          pedido('AL2', 'Alex Ojom', 'card', 48, subtotal: 80, propina: 8, cortesia: 40, hora: DateTime(2026, 11, 20, 23, 40)),
          pedido('L1', 'Juan Carlos Ixtan', 'custom_vales', 60, hora: DateTime(2026, 11, 20, 23, 30)),
          pedido('E3', 'Ana Cosme', 'split', 30, hora: DateTime(2026, 11, 20, 23, 20)),
        ],
        nombresMetodos: const {'custom_vales': 'Vales'},
      );

  final gastos = [
    GastoCaja(fecha: DateTime(2026, 11, 20, 22, 40), concepto: 'Gas', categoria: 'Gas', usuario: null, monto: 180),
    GastoCaja(fecha: DateTime(2026, 11, 20, 20, 20), concepto: 'Compra de hielo', categoria: 'Insumos', usuario: 'Juan Carlos Ixtan', monto: 45),
  ];

  Widget cuerpo({
    DetalleCaja? detalle,
    List<GastoCaja>? gastosDe,
    PestanaCaja pestana = PestanaCaja.pedidos,
    bool cargando = false,
    bool error = false,
    VoidCallback? onReintentar,
    String signo = 'Q',
  }) =>
      DetalleCajaBody(
        caja: caja,
        detalle: detalle ?? seis(),
        gastos: gastosDe ?? gastos,
        pestana: pestana,
        signo: signo,
        cargando: cargando,
        error: error,
        onReintentar: onReintentar,
      );

  Future<void> montar(WidgetTester tester, Widget c, {Size size = const Size(1280, 2600), double escala = 1.0, bool asentar = true}) async {
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
    // El indicador de carga nunca deja de animar: ahí no se espera a que se asiente.
    asentar ? await tester.pumpAndSettle() : await tester.pump();
  }

  const tamanos = [Size(360, 3000), Size(390, 3000), Size(700, 3000), Size(1280, 3000)];

  group('el encabezado', () {
    Widget encabezado({PestanaCaja p = PestanaCaja.pedidos, int? pedidos = 6, ValueChanged<PestanaCaja>? onPestana, VoidCallback? onRegresar}) =>
        DetalleCajaEncabezado(
          caja: caja,
          pestana: p,
          onPestana: onPestana ?? (_) {},
          onRegresar: onRegresar ?? () {},
          pedidos: pedidos,
          gastos: 2,
        );

    testWidgets('quién, cuándo (con el día si pasa de medianoche), dónde y las pestañas con su cuenta', (tester) async {
      await montar(tester, encabezado());
      expect(find.text('Ana Cosme'), findsOneWidget);
      expect(find.text('20 nov · 06:00 PM → 21 nov, 01:25 AM · Restaurante Lena’s Atlantis'), findsOneWidget);
      expect(find.text('Pedidos (6)'), findsOneWidget);
      expect(find.text('Gastos (2)'), findsOneWidget);
    });

    testWidgets('mientras se leen los pedidos, la pestaña no dice cuántos', (tester) async {
      await montar(tester, encabezado(pedidos: null));
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.textContaining('Pedidos ('), findsNothing);
    });

    testWidgets('un corte de un solo día muestra el día una vez', (tester) async {
      final mismoDia = CashRegisterSummary(
        id: 'x', userId: 'u', userName: 'Juan', status: 'closed',
        openedAt: DateTime(2026, 11, 21, 7), closedAt: DateTime(2026, 11, 21, 15, 5),
      );
      await montar(tester, DetalleCajaEncabezado(caja: mismoDia, pestana: PestanaCaja.pedidos, onPestana: (_) {}, onRegresar: () {}, pedidos: 1, gastos: 0));
      expect(find.text('21 nov · 07:00 AM → 03:05 PM'), findsOneWidget);
    });

    testWidgets('una caja abierta dice desde cuándo', (tester) async {
      final abierta = CashRegisterSummary(id: 'x', userId: 'u', userName: 'Juan', status: 'open', openedAt: DateTime(2026, 11, 21, 7));
      await montar(tester, DetalleCajaEncabezado(caja: abierta, pestana: PestanaCaja.pedidos, onPestana: (_) {}, onRegresar: () {}, pedidos: 1, gastos: 0));
      expect(find.text('Abierta desde 21 nov, 07:00 AM'), findsOneWidget);
    });

    testWidgets('tocar una pestaña la elige; tocar regresar regresa', (tester) async {
      final elegidas = <PestanaCaja>[];
      var regresos = 0;
      await montar(tester, encabezado(onPestana: elegidas.add, onRegresar: () => regresos++));
      await tester.tap(find.text('Gastos (2)'));
      await tester.tap(find.text('Pedidos (6)'));
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      expect(elegidas, [PestanaCaja.gastos, PestanaCaja.pedidos]);
      expect(regresos, 1);
    });

    testWidgets('la pestaña elegida va con el fondo claro; la otra, apagada', (tester) async {
      await montar(tester, encabezado(p: PestanaCaja.gastos));
      expect(tester.widget<Text>(find.text('Gastos (2)')).style!.color, InicioColores.card);
      expect(tester.widget<Text>(find.text('Pedidos (6)')).style!.color, InicioColores.muted);
    });

    testWidgets('en teléfono las pestañas bajan y ocupan todo el ancho; en ancho van a la derecha', (tester) async {
      await montar(tester, encabezado(), size: const Size(390, 800));
      expect(tester.getTopLeft(find.text('Pedidos (6)')).dy, greaterThan(tester.getBottomLeft(find.text('Ana Cosme')).dy));
      expect(tester.getSize(find.byType(DetalleCajaEncabezado)).width, 390);

      await montar(tester, encabezado());
      expect(tester.getTopLeft(find.text('Pedidos (6)')).dx, greaterThan(800));
    });
  });

  group('el resumen', () {
    testWidgets('total pagado, descuentos, propinas y cortesías', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('Total pagado'), findsOneWidget);
      expect(find.text('Q549.50'), findsWidgets);
      expect(find.text('6 pedidos · prom. Q91.58'), findsOneWidget);
      expect(find.text('Descuentos'), findsOneWidget);
      expect(find.text('−Q25.00'), findsWidgets);
      expect(find.text('1 pedido'), findsNWidgets(2), reason: 'con descuento y con cortesía');
      expect(find.text('Propinas'), findsOneWidget);
      expect(find.text('Q44.50'), findsWidgets);
      expect(find.text('8% del subtotal'), findsOneWidget);
      expect(find.text('Cortesías'), findsOneWidget);
      expect(find.text('Q40.00'), findsWidgets);
    });

    testWidgets('lo que no hubo sale apagado, no en el color de aviso', (tester) async {
      final sin = DetalleCaja.desde([pedido('A', 'Ana Cosme', 'cash', 50), pedido('B', 'Ana Cosme', 'cash', 70)]);
      await montar(tester, cuerpo(detalle: sin));
      expect(tester.widget<Text>(find.text('Q0.00').first).style!.color, InicioColores.muted);
      expect(find.text('0 pedidos'), findsNWidgets(2));
    });
  });

  group('¿quién vendió?', () {
    testWidgets('de quien más vendió a quien menos, con su parte', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('¿Quién vendió?'), findsOneWidget);
      expect(find.text('Toca para ver sus pedidos'), findsOneWidget);
      // Ana: 109 + 247.5 + 30 = 386.5 (70%); Alex: 55 + 48 = 103 (19%); Juan: 60 (11%).
      final y = [for (final n in ['Ana Cosme', 'Alex Ojom', 'Juan Carlos Ixtan']) tester.getTopLeft(find.text(n).first).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
      expect(find.text('Q386.50'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('19%'), findsOneWidget);
      expect(find.text('11%'), findsOneWidget);
      expect(find.text('3 pedidos · propinas Q31.50'), findsOneWidget);
    });

    testWidgets('con un solo usuario no sale (diría 100% de la misma persona)', (tester) async {
      final uno = DetalleCaja.desde([pedido('A', 'Ana Cosme', 'cash', 50), pedido('B', 'Ana Cosme', 'card', 70)]);
      await montar(tester, cuerpo(detalle: uno));
      expect(find.text('¿Quién vendió?'), findsNothing);
    });

    testWidgets('tocar a alguien filtra sus pedidos; su chip y volver a tocarlo lo quitan', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('6 de 6'), findsOneWidget);
      await tester.tap(find.text('Alex Ojom').first);
      await tester.pumpAndSettle();
      expect(find.text('2 de 6'), findsOneWidget);
      expect(find.text('AL1'), findsOneWidget);
      expect(find.text('AL2'), findsOneWidget);
      expect(find.text('E1'), findsNothing);
      expect(find.text('Alex Ojom ✕'), findsOneWidget);
      // El total de abajo es el de lo que se ve: 55 + 48.
      expect(find.text('Q103.00'), findsWidgets);

      await tester.tap(find.text('Alex Ojom ✕'));
      await tester.pumpAndSettle();
      expect(find.text('6 de 6'), findsOneWidget);
      expect(find.text('Alex Ojom ✕'), findsNothing);

      // O volviendo a tocar a la misma persona en la lista.
      await tester.tap(find.text('Alex Ojom').first);
      await tester.pumpAndSettle();
      expect(find.text('2 de 6'), findsOneWidget);
      await tester.tap(find.text('Alex Ojom').first);
      await tester.pumpAndSettle();
      expect(find.text('6 de 6'), findsOneWidget);
    });
  });

  group('la tabla de pedidos (pantalla ancha)', () {
    testWidgets('las columnas, los pedidos y el método con su nombre', (tester) async {
      await montar(tester, cuerpo());
      for (final h in ['HORA', 'USUARIO', '#PEDIDO', 'SUBTOTAL', 'DESCUENTO', 'PROPINA', 'CORTESÍA', 'TOTAL PAGADO', 'MÉTODO']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      for (final n in ['E1', 'E2', 'AL1', 'AL2', 'L1', 'E3']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.text('Efectivo'), findsWidgets);
      expect(find.text('Tarjeta'), findsWidgets);
      expect(find.text('Vales'), findsWidgets, reason: 'un método propio sale con su nombre, no con el id');
      expect(find.text('custom_vales'), findsNothing);
      expect(find.text('Mixto'), findsWidgets);
    });

    testWidgets('lo que es cero va con una raya; el descuento y la cortesía, en su color', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('—'), findsWidgets);
      expect(tester.widget<Text>(find.text('−Q25.00').first).style!.color, InicioColores.bad);
      expect(tester.widget<Text>(find.text('Q22.50')).style!.color, InicioColores.gift);
      expect(tester.widget<Text>(find.text('Q40.00').first).style!.color, InicioColores.warn);
    });

    testWidgets('la hora y, si es de otro día que el de la apertura, la fecha debajo', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('01:02 AM'), findsOneWidget);
      // Los dos primeros son del 21 (la caja abrió el 20); los otros cuatro no llevan fecha... el 20 es el día de apertura.
      expect(find.text('21 nov'), findsNWidgets(2));
      expect(find.text('20 nov'), findsNothing);
    });

    testWidgets('el total de abajo es el de lo que se ve', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('6 pedidos'), findsOneWidget);
      expect(find.text('Q570.00'), findsOneWidget, reason: 'subtotal');
      expect(find.text('Q549.50'), findsWidgets);
    });

    testWidgets('con muchos pedidos la tabla se desplaza por dentro y no arma todos de golpe', (tester) async {
      final muchos = DetalleCaja.desde([
        for (var i = 0; i < 80; i++) pedido('N$i', 'Ana Cosme', 'cash', 10.0 + i),
      ]);
      await montar(tester, cuerpo(detalle: muchos), size: const Size(1280, 1400));
      expect(find.text('N0'), findsOneWidget);
      expect(find.text('N79'), findsNothing, reason: 'el último todavía no se construye');
      expect(find.text('80 pedidos'), findsOneWidget);
    });
  });

  group('los pedidos como tarjetas (teléfono y tablet)', () {
    for (final ancho in [360.0, 700.0]) {
      testWidgets('a ${ancho.toInt()} no hay columnas: número, total, hora, método, quién y lo que no es cero', (tester) async {
        await montar(tester, cuerpo(), size: Size(ancho, 3400));
        expect(find.text('SUBTOTAL'), findsNothing);
        expect(find.text('E2'), findsOneWidget);
        expect(find.text('Q247.50'), findsOneWidget);
        expect(find.textContaining('Descuento −Q25.00', findRichText: true), findsOneWidget);
        expect(find.textContaining('Propina Q22.50', findRichText: true), findsOneWidget);
        expect(find.textContaining('Cortesía Q40.00', findRichText: true), findsOneWidget);
        // Un pedido sin propina, descuento ni cortesía no lleva esas líneas.
        expect(find.textContaining('Propina Q0.00', findRichText: true), findsNothing);
        expect(find.text('Alex Ojom'), findsWidgets);
      });
    }

    testWidgets('el pie dice cuántos y cuánto', (tester) async {
      await montar(tester, cuerpo(), size: const Size(360, 3400));
      expect(find.text('6 pedidos'), findsOneWidget);
      expect(find.text('Q549.50'), findsWidgets);
    });
  });

  group('los filtros', () {
    testWidgets('uno por método que se usó, con cuántos, y con descuento / con cortesía si hubo', (tester) async {
      await montar(tester, cuerpo());
      for (final n in ['Todos', 'Efectivo', 'Tarjeta', 'Vales', 'Mixto', 'Con descuento', 'Con cortesía']) {
        expect(find.text(n), findsWidgets, reason: n);
      }
      expect(find.text('6'), findsOneWidget, reason: 'Todos 6');
    });

    testWidgets('sin descuentos ni cortesías no salen esos dos filtros', (tester) async {
      final simple = DetalleCaja.desde([pedido('A', 'Ana Cosme', 'cash', 50), pedido('B', 'Ana Cosme', 'card', 70)]);
      await montar(tester, cuerpo(detalle: simple));
      expect(find.text('Con descuento'), findsNothing);
      expect(find.text('Con cortesía'), findsNothing);
    });

    testWidgets('elegir "Efectivo" deja solo esos y el total de abajo cambia', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.widgetWithText(GestureDetector, 'Efectivo').first);
      await tester.pumpAndSettle();
      expect(find.text('2 de 6'), findsOneWidget);
      expect(find.text('E1'), findsOneWidget);
      expect(find.text('AL1'), findsOneWidget);
      expect(find.text('E2'), findsNothing);
      // 109 + 55.
      expect(find.text('Q164.00'), findsWidgets);
    });

    testWidgets('"Con descuento" y "Con cortesía" dejan el pedido que corresponde', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.widgetWithText(GestureDetector, 'Con descuento'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 6'), findsOneWidget);
      expect(find.text('E2'), findsOneWidget);
      await tester.tap(find.widgetWithText(GestureDetector, 'Con cortesía'));
      await tester.pumpAndSettle();
      expect(find.text('AL2'), findsOneWidget);
      expect(find.text('E2'), findsNothing);
    });

    testWidgets('un filtro y un usuario a la vez: solo los dos; sin ninguno, lo dice', (tester) async {
      await montar(tester, cuerpo());
      await tester.tap(find.text('Alex Ojom').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GestureDetector, 'Con descuento'));
      await tester.pumpAndSettle();
      expect(find.text('0 de 6'), findsOneWidget);
      expect(find.text('Ningún pedido con este filtro'), findsOneWidget);
    });
  });

  group('gastos', () {
    testWidgets('en ancho: tabla con hora, concepto, usuario y monto, y el total arriba', (tester) async {
      await montar(tester, cuerpo(pestana: PestanaCaja.gastos));
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Q225.00'), findsOneWidget);
      for (final h in ['HORA', 'CONCEPTO', 'USUARIO', 'MONTO']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('Compra de hielo'), findsOneWidget);
      expect(find.text('Insumos'), findsOneWidget, reason: 'la categoría, cuando no es el concepto');
      expect(find.text('Q45.00'), findsOneWidget);
      expect(find.text('Gas'), findsOneWidget, reason: 'el concepto, que es la categoría (no se repite debajo)');
      expect(find.text('Q180.00'), findsOneWidget);
      // Sin quien lo registró, una raya.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('en teléfono: cada gasto con su concepto, quién y cuándo, y su monto', (tester) async {
      await montar(tester, cuerpo(pestana: PestanaCaja.gastos), size: const Size(360, 1200));
      expect(find.text('HORA'), findsNothing);
      expect(find.text('Compra de hielo'), findsOneWidget);
      expect(find.text('Insumos · Juan Carlos Ixtan · 20 nov · 08:20 PM'), findsOneWidget);
      expect(find.text('Q45.00'), findsOneWidget);
    });

    testWidgets('sin gastos lo dice', (tester) async {
      await montar(tester, cuerpo(pestana: PestanaCaja.gastos, gastosDe: const []));
      expect(find.text('Sin gastos'), findsOneWidget);
      expect(find.text('No se registraron gastos en esta caja.'), findsOneWidget);
    });

    testWidgets('la pestaña de gastos no espera a los pedidos... pero sí mientras cargan', (tester) async {
      await montar(tester, cuerpo(pestana: PestanaCaja.gastos, cargando: true), asentar: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('lo que no se puede mostrar', () {
    testWidgets('sin pedidos lo dice', (tester) async {
      await montar(tester, cuerpo(detalle: DetalleCaja.vacio));
      expect(find.text('Sin pedidos en esta caja'), findsOneWidget);
      expect(find.text('Total pagado'), findsNothing);
    });

    testWidgets('mientras carga, un indicador', (tester) async {
      await montar(tester, cuerpo(detalle: DetalleCaja.vacio, cargando: true), asentar: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sin pedidos en esta caja'), findsNothing);
    });

    testWidgets('si falló la lectura lo dice (no "sin pedidos") y deja reintentar', (tester) async {
      var intentos = 0;
      await montar(tester, cuerpo(detalle: DetalleCaja.vacio, error: true, onReintentar: () => intentos++));
      expect(find.text('No se pudieron leer los pedidos'), findsOneWidget);
      expect(find.text('Sin pedidos en esta caja'), findsNothing);
      await tester.tap(find.text('Reintentar'));
      expect(intentos, 1);
    });

    testWidgets('los avisos de vacío ocupan todo el ancho (no se achican al texto)', (tester) async {
      await montar(tester, cuerpo(detalle: DetalleCaja.vacio), size: const Size(1280, 800));
      final tarjeta = find.ancestor(of: find.text('Sin pedidos en esta caja'), matching: find.byType(InicioCard)).first;
      expect(tester.getSize(tarjeta).width, closeTo(1280 - 40, 1));
    });

    testWidgets('si llegan otros pedidos y el filtro elegido ya no existe, vuelve a "Todos"', (tester) async {
      final base = DetalleCaja.desde([pedido('A', 'Ana Cosme', 'cash', 50), pedido('B', 'Ana Cosme', 'card', 70)]);
      await montar(tester, cuerpo(detalle: base));
      await tester.tap(find.widgetWithText(GestureDetector, 'Tarjeta'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 2'), findsOneWidget);
      // Se vuelve a leer y ahora solo hay efectivo.
      await montar(tester, cuerpo(detalle: DetalleCaja.desde([pedido('A', 'Ana Cosme', 'cash', 50)])));
      expect(find.text('1 de 1'), findsOneWidget);
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
                      child: RefreshIndicator(onRefresh: () async {}, child: cuerpo(detalle: DetalleCaja.vacio)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(SingleChildScrollView)).height, tam.height - arribaDelArea);
        expect(tester.getTopLeft(find.text('Sin pedidos en esta caja')).dy, lessThan(arribaDelArea + 90));
      });
    }
  });

  group('cabe sin desbordar', () {
    for (final s in tamanos) {
      testWidgets('a ${s.width.toInt()} con letra grande y datos normales, en las dos pestañas', (tester) async {
        await montar(tester, cuerpo(), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await montar(tester, cuerpo(pestana: PestanaCaja.gastos), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande, cifras enormes, nombres larguísimos y muchos pedidos', (tester) async {
        final enormes = DetalleCaja.desde([
          for (var i = 0; i < 25; i++)
            pedido(
              'N-$i-con-un-numero-largo',
              'María de los Ángeles Fernández de la Vega y Montoya número ${i % 4}',
              i % 3 == 0 ? 'custom_x' : (i.isEven ? 'cash' : 'card'),
              987654321.55 + i,
              subtotal: 987654321.55,
              desc: i % 2 == 0 ? 12345678.9 : 0,
              propina: 1234567.89,
              cortesia: i % 5 == 0 ? 55555555.5 : 0,
              hora: DateTime(2026, 11, 20 + (i % 2), 10 + i % 12),
            ),
        ], nombresMetodos: const {'custom_x': 'Un método propio con un nombre larguísimo de verdad'});
        final gastosEnormes = [
          for (var i = 0; i < 6; i++)
            GastoCaja(
              fecha: DateTime(2026, 11, 20, 10 + i),
              concepto: 'Un gasto con un concepto larguísimo de verdad para ver qué pasa número $i',
              categoria: 'Una categoría también larguísima $i',
              usuario: 'María de los Ángeles Fernández de la Vega y Montoya',
              monto: 98765432.1,
            ),
        ];
        await montar(tester, cuerpo(detalle: enormes, gastosDe: gastosEnormes, signo: 'USD '), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await montar(tester, cuerpo(detalle: enormes, gastosDe: gastosEnormes, pestana: PestanaCaja.gastos, signo: 'USD '), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande en los estados vacío, error y cargando', (tester) async {
        for (final c in [
          cuerpo(detalle: DetalleCaja.vacio),
          cuerpo(detalle: DetalleCaja.vacio, error: true, onReintentar: () {}),
          cuerpo(detalle: DetalleCaja.vacio, cargando: true),
          cuerpo(pestana: PestanaCaja.gastos, gastosDe: const []),
        ]) {
          await montar(tester, c, size: s, escala: 1.35, asentar: false);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
