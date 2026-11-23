import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/data/models/propinas_data.dart';
import 'package:saborpro_reports/presentation/widgets/inicio_ui.dart';
import 'package:saborpro_reports/presentation/widgets/propinas_view.dart';

/// La vista de Propinas sin Firebase: la pantalla real le pasa el reporte ya
/// armado. Cualquier "RenderFlex overflowed" hace fallar la prueba por sí solo.
///
/// El día de prueba (todo a mano, para poder comprobar cada cifra):
///   Ana (u1)   4 pedidos de Q200, propina Q20 en cada uno (10%)      → Q80
///   Luis (u2)  6 pedidos de Q100, solo 2 con propina de Q10 (3.3%)   → Q20
///   Carla (u3) 2 pedidos de Q400, propina Q50 en cada uno (12.5%)    → Q100
/// Total: 12 pedidos, ventas Q2,200, propinas Q200 (9.1%), 4 sin propina.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final dia = DateTime(2026, 11, 20);
  DateTime a(int h, [int m = 0]) => DateTime(dia.year, dia.month, dia.day, h, m);

  Map<String, dynamic> pedido({
    required double venta,
    double tip = 0,
    double envio = 0,
    String? usuario,
    String? nombre,
    String tipo = 'dine_in',
    String metodo = 'card',
    String? mesa,
    required DateTime hora,
  }) =>
      {
        // Lo cobrado incluye la propina y el envío.
        'payment_amount': venta + tip + envio,
        'tip_amount': tip,
        'delivery_fee': envio,
        if (usuario != null) 'created_by_user_id': usuario,
        if (nombre != null) 'created_by_user_name': nombre,
        'type': tipo,
        'payment_method': metodo,
        if (mesa != null) 'table_id': mesa,
        'paid_at': Timestamp.fromDate(hora),
      };

  List<Map<String, dynamic>> pedidosDelDia() => [
        // Ana: dos en la terraza, dos en el salón.
        pedido(venta: 200, tip: 20, usuario: 'u1', nombre: 'Ana Pérez', mesa: 't1', hora: a(12, 10)),
        pedido(venta: 200, tip: 20, usuario: 'u1', nombre: 'Ana Pérez', mesa: 't1', hora: a(12, 40)),
        pedido(venta: 200, tip: 20, usuario: 'u1', nombre: 'Ana Pérez', mesa: 't2', hora: a(13, 5)),
        pedido(venta: 200, tip: 20, usuario: 'u1', nombre: 'Ana Pérez', mesa: 't2', hora: a(19, 30)),
        // Luis: tres para llevar y tres a domicilio; solo dos dejaron propina.
        pedido(venta: 100, tip: 10, usuario: 'u2', nombre: 'Luis Gómez', tipo: 'takeout', metodo: 'cash', hora: a(12, 20)),
        pedido(venta: 100, usuario: 'u2', nombre: 'Luis Gómez', tipo: 'takeout', metodo: 'cash', hora: a(13, 30)),
        pedido(venta: 100, usuario: 'u2', nombre: 'Luis Gómez', tipo: 'takeout', metodo: 'cash', hora: a(14, 40)),
        pedido(venta: 100, tip: 10, envio: 15, usuario: 'u2', nombre: 'Luis Gómez', tipo: 'delivery', metodo: 'cash', hora: a(14, 10)),
        pedido(venta: 100, envio: 15, usuario: 'u2', nombre: 'Luis Gómez', tipo: 'delivery', metodo: 'cash', hora: a(15, 10)),
        pedido(venta: 100, envio: 15, usuario: 'u2', nombre: 'Luis Gómez', tipo: 'delivery', metodo: 'cash', hora: a(19, 50)),
        // Carla: el pedido no trae su nombre (se lo busca en users).
        pedido(venta: 400, tip: 50, usuario: 'u3', mesa: 't1', hora: a(13, 15)),
        pedido(venta: 400, tip: 50, usuario: 'u3', mesa: 't1', hora: a(20)),
      ];

  // Lo que se dejó el período anterior: Q160 (200 es 25% más).
  List<Map<String, dynamic>> anteriores() => [
        pedido(venta: 1000, tip: 160, usuario: 'u1', hora: a(13).subtract(const Duration(days: 1))),
      ];

  const zonas = {'t1': 'Terraza', 't2': 'Salón'};

  PropinasReporte reporte({Map<String, String>? zonaDeMesa = zonas, bool conAnterior = true}) => PropinasReporte.desde(
        pedidosDelDia(),
        anteriores: conAnterior ? anteriores() : const [],
        nombresUsuario: const {'u3': 'Carla Ruiz'},
        zonaDeMesa: zonaDeMesa,
      );

  Future<void> montar(
    WidgetTester tester,
    Widget cuerpo, {
    Size size = const Size(360, 800),
    double escala = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(backgroundColor: kInicioBg, body: cuerpo),
    ));
    await tester.pumpAndSettle();
  }

  PropinasReportBody cuerpo({
    PropinasReporte? r,
    double total = 250,
    double enCaja = 50,
    bool conDetalle = true,
    bool incompleto = false,
  }) =>
      PropinasReportBody(
        reporte: r ?? reporte(),
        totalPeriodo: total,
        enCaja: enCaja,
        vsEtiqueta: 'Ayer',
        conDetalle: conDetalle,
        incompleto: incompleto,
      );

  Future<void> bajarHasta(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  String p1(double v) => '${v.toStringAsFixed(1)}%';

  const tamanos = [Size(360, 800), Size(390, 844), Size(700, 900), Size(1280, 800)];

  group('el resumen', () {
    testWidgets('el total del período, el promedio, lo de cada pedido y los que no dejaron', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 900));
      expect(find.text('Propinas del período'), findsOneWidget);
      // Las propinas de los tickets (Q200) más las metidas a la caja (Q50).
      expect(find.text('Q250.00'), findsOneWidget);
      expect(find.text('Incluye Q50.00 metidas a la caja'), findsOneWidget);
      expect(find.text('Propina promedio'), findsOneWidget);
      expect(find.text(p1(200 / 2200 * 100)), findsOneWidget);
      expect(find.text('sobre ventas de Q2,200.00'), findsOneWidget);
      expect(find.text('Por pedido'), findsOneWidget);
      expect(find.text('Q16.67'), findsOneWidget);
      expect(find.text('12 pedidos'), findsOneWidget);
      expect(find.text('Sin propina'), findsOneWidget);
      expect(find.text('33% de los pedidos'), findsOneWidget);
    });

    testWidgets('sin propinas metidas a la caja no dice nada de la caja', (tester) async {
      await montar(tester, cuerpo(total: 200, enCaja: 0), size: const Size(1280, 900));
      expect(find.textContaining('metidas a la caja'), findsNothing);
      expect(find.text('Q200.00'), findsOneWidget);
    });

    testWidgets('compara con el período anterior, y lo nombra', (tester) async {
      await montar(tester, cuerpo());
      expect(find.text('25% vs Ayer'), findsOneWidget);
      // La flecha es un ícono (no el carácter ↑, que no todas las letras traen).
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(tester.widget<Text>(find.text('25% vs Ayer')).style!.color, InicioColores.gift);
    });

    testWidgets('si bajó, la flecha va para abajo y en rojo', (tester) async {
      final r = PropinasReporte.desde(
        pedidosDelDia(),
        anteriores: [pedido(venta: 1000, tip: 400, hora: a(13))],
      );
      await montar(tester, cuerpo(r: r));
      expect(find.text('50% vs Ayer'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(tester.widget<Text>(find.text('50% vs Ayer')).style!.color, InicioColores.bad);
    });

    testWidgets('con menos de medio punto de diferencia dice que quedó igual, no "↑ 0%"', (tester) async {
      // Q200 de propinas contra Q200: 0%.
      final r = PropinasReporte.desde(pedidosDelDia(), anteriores: [pedido(venta: 1000, tip: 200, hora: a(13))]);
      await montar(tester, cuerpo(r: r));
      expect(find.text('Igual que Ayer'), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });

    testWidgets('sin pedidos del período anterior no hay comparación (no se inventa un 0%)', (tester) async {
      await montar(tester, cuerpo(r: reporte(conAnterior: false)));
      expect(find.textContaining('vs Ayer'), findsNothing);
    });

    testWidgets('en 1280 las cuatro cifras van en una fila; en 360 de dos en dos', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 900));
      final y = [for (final t in ['Propinas del período', 'Propina promedio', 'Por pedido', 'Sin propina']) tester.getTopLeft(find.text(t)).dy];
      expect(y.toSet(), hasLength(1), reason: '$y');

      await montar(tester, cuerpo(), size: const Size(360, 800));
      final yy = [for (final t in ['Propinas del período', 'Propina promedio', 'Por pedido', 'Sin propina']) tester.getTopLeft(find.text(t)).dy];
      expect(yy[0], yy[1]);
      expect(yy[2], yy[3]);
      expect(yy[2], greaterThan(yy[0]));
    });

    testWidgets('con más de uno de cada diez sin propina la cifra se pinta de aviso', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 900));
      // 33% sin propina.
      final texto = tester.widget<Text>(find.text('4'));
      expect(texto.style!.color, InicioColores.warn);

      // Con casi todos dejando propina, queda normal.
      final bien = PropinasReporte.desde([
        for (var i = 0; i < 20; i++) pedido(venta: 100, tip: 10, hora: a(12)),
        pedido(venta: 100, hora: a(12)),
      ]);
      await montar(tester, cuerpo(r: bien, total: 200, enCaja: 0), size: const Size(1280, 900));
      expect(tester.widget<Text>(find.text('1')).style!.color, InicioColores.ink);
    });
  });

  group('el aviso del mesero con poca propina', () {
    testWidgets('dice quién, cuánto recibe, el promedio y cuántos salieron sin propina', (tester) async {
      await montar(tester, cuerpo());
      expect(
        find.textContaining(
          'recibe ${p1(20 / 600 * 100)} de propina, menos que el promedio (${p1(200 / 2200 * 100)}). '
          '4 de sus pedidos salieron sin propina.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('si nadie se queda atrás no hay aviso', (tester) async {
      final r = PropinasReporte.desde([
        for (var i = 0; i < 6; i++) pedido(venta: 100, tip: 10, usuario: 'u1', nombre: 'Ana', hora: a(12)),
        for (var i = 0; i < 6; i++) pedido(venta: 100, tip: 10, usuario: 'u2', nombre: 'Luis', hora: a(13)),
      ]);
      await montar(tester, cuerpo(r: r, total: 120, enCaja: 0));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.textContaining('menos que el promedio', findRichText: true), findsNothing);
    });
  });

  group('¿quién recibe propina?', () {
    testWidgets('de quien más recibió a quien menos, con lo que vendió y su parte del total', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      expect(find.text('¿Quién recibe propina?'), findsOneWidget);
      final y = [for (final n in ['Carla Ruiz', 'Ana Pérez', 'Luis Gómez']) tester.getTopLeft(find.text(n)).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
      expect(find.text('2 pedidos · vendió Q800.00'), findsOneWidget);
      expect(find.text('4 pedidos · vendió Q800.00'), findsOneWidget);
      expect(find.text('6 pedidos · vendió Q600.00'), findsOneWidget);
      // Q100 de Q200, Q80 de Q200, Q20 de Q200.
      expect(find.text('Q100.00'), findsOneWidget);
      expect(find.text('50% del total'), findsOneWidget);
      expect(find.text('40% del total'), findsOneWidget);
      // Luis y el efectivo: los dos son el 10%.
      expect(find.text('10% del total'), findsNWidgets(2));
    });

    testWidgets('el nombre sale del pedido y, si no, de users; sin ninguno, "Sin registrar"', (tester) async {
      final r = PropinasReporte.desde(
        [
          pedido(venta: 100, tip: 10, usuario: 'u9', hora: a(12)),
          pedido(venta: 100, tip: 5, hora: a(12)),
        ],
        nombresUsuario: const {'u9': 'Mario Ortiz'},
      );
      await montar(tester, cuerpo(r: r, total: 15, enCaja: 0));
      expect(find.text('Mario Ortiz'), findsOneWidget);
      expect(find.text('Sin registrar'), findsOneWidget);
    });

    testWidgets('lleva sus iniciales y la píldora de lo que recibe, con el "sin propina" de quien lo tiene', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      expect(find.text('CR'), findsOneWidget);
      expect(find.text('AP'), findsOneWidget);
      expect(find.text('LG'), findsOneWidget);
      expect(find.text('${p1(100 / 800 * 100)} de propina'), findsOneWidget);
      expect(find.text('${p1(20 / 600 * 100)} de propina'), findsOneWidget);
      expect(find.text('4 sin propina'), findsOneWidget);
    });

    testWidgets('con muchos meseros muestra los primeros y dice cuántos más hay', (tester) async {
      final r = PropinasReporte.desde([
        for (var i = 0; i < 20; i++)
          pedido(venta: 100, tip: 5.0 + i, usuario: 'u$i', nombre: 'Mesero $i', hora: a(12)),
      ]);
      await montar(tester, cuerpo(r: r, total: 500, enCaja: 0), size: const Size(1280, 2600));
      expect(find.text('y 5 más con menos propina'), findsOneWidget);
      // El que más recibió está; el que menos, no.
      expect(find.text('Mesero 19'), findsOneWidget);
      expect(find.text('Mesero 0'), findsNothing);
    });
  });

  group('¿a qué hora se deja más propina?', () {
    testWidgets('dice la mejor hora, con su valor, y rotula las horas', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1400));
      expect(find.text('¿A qué hora se deja más propina?'), findsOneWidget);
      // La 1 de la tarde: Q20 de Ana y Q50 de Carla.
      expect(find.text('La mejor hora: 1 PM – 2 PM'), findsOneWidget);
      expect(find.text('Q70'), findsOneWidget);
      // De las 12 a las 8 de la noche, sin huecos.
      for (final h in ['12p', '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
    });

    testWidgets('si la mejor hora es la última del día, termina a las 12 AM y no a las 12 PM', (tester) async {
      final r = PropinasReporte.desde([
        pedido(venta: 100, tip: 10, hora: a(22)),
        pedido(venta: 100, tip: 30, hora: a(23, 10)),
      ]);
      await montar(tester, cuerpo(r: r, total: 40, enCaja: 0), size: const Size(1280, 1400));
      expect(find.text('La mejor hora: 11 PM – 12 AM'), findsOneWidget);
    });

    testWidgets('si no caben todos los rótulos salen algunos; si caben, todos', (tester) async {
      final r = PropinasReporte.desde([
        for (var h = 0; h < 24; h++) pedido(venta: 100, tip: 1.0 + h, hora: a(h)),
      ]);
      // 24 barras en un teléfono (unos 12 px cada una): una sí y otra no.
      await montar(tester, cuerpo(r: r, total: 300, enCaja: 0), size: const Size(360, 3000));
      expect(find.text('12a'), findsOneWidget);
      expect(find.text('2a'), findsOneWidget);
      expect(find.text('1a'), findsNothing);

      // Con letra más grande, de a más.
      await montar(tester, cuerpo(r: r, total: 300, enCaja: 0), size: const Size(360, 3000), escala: 1.35);
      expect(find.text('12a'), findsOneWidget);
      expect(find.text('2a'), findsNothing);
      expect(find.text('3a'), findsOneWidget);

      // Las 16 horas de un día de trabajo en pantalla ancha: todas, como en el diseño.
      final dia16 = PropinasReporte.desde([
        for (var h = 7; h <= 22; h++) pedido(venta: 100, tip: 1.0 + h, hora: a(h)),
      ]);
      await montar(tester, cuerpo(r: dia16, total: 300, enCaja: 0), size: const Size(1280, 3000));
      for (final h in ['7a', '8a', '9a', '10a', '11a', '12p', '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p', '10p']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
    });
  });

  group('por tipo de servicio y por tamaño de la cuenta', () {
    testWidgets('cada tipo con sus pedidos, su propina y los que no dejaron', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1800));
      expect(find.text('Por tipo de servicio'), findsOneWidget);
      expect(find.text('Mesa'), findsOneWidget);
      expect(find.text('Para llevar'), findsOneWidget);
      expect(find.text('Domicilio'), findsOneWidget);
      expect(find.text('6 pedidos · propina Q180.00'), findsAtLeastNWidgets(1));
      // Para llevar y Domicilio: 3 pedidos, Q10 de propina y 2 sin propina.
      expect(find.text('3 pedidos · propina Q10.00 · 2 sin propina'), findsNWidgets(2));
    });

    testWidgets('el domicilio vende sin su cobro de envío (la propina se compara con la venta)', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1800));
      // 3 pedidos de Q100 de venta (con Q15 de envío aparte): Q10 / Q300 = 3.3%.
      expect(find.text(p1(10 / 300 * 100)), findsNWidgets(2));
    });

    testWidgets('los tamaños salen con el signo de la moneda y solo los que hay', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1800));
      expect(find.text('Según el tamaño de la cuenta'), findsOneWidget);
      expect(find.text('Q100 a Q300'), findsOneWidget);
      expect(find.text('Más de Q300'), findsOneWidget);
      expect(find.text('Menos de Q100'), findsNothing);
    });

    testWidgets('la barra es de aviso si el grupo se queda bajo el promedio', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 1800));
      // Mesa (11%) por encima del 9.1% de promedio: verde. Domicilio (3.3%): ámbar.
      final mesa = tester.widget<Text>(find.text(p1(180 / 1600 * 100)).first);
      expect(mesa.style!.color, InicioColores.gift);
      final domicilio = tester.widget<Text>(find.text(p1(10 / 300 * 100)).first);
      expect(domicilio.style!.color, InicioColores.warn);
    });
  });

  group('por zona y tarjeta y efectivo', () {
    testWidgets('la zona de las mesas, de la que más propina dejó a la que menos', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 2000));
      expect(find.text('Por zona'), findsOneWidget);
      expect(find.text('Solo pedidos en mesa'), findsOneWidget);
      expect(find.text('Terraza'), findsOneWidget);
      expect(find.text('Salón'), findsOneWidget);
      expect(find.text('4 pedidos · propina Q140.00'), findsOneWidget);
      expect(find.text('2 pedidos · propina Q40.00'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Terraza')).dy, lessThan(tester.getTopLeft(find.text('Salón')).dy));
    });

    testWidgets('si no se pudieron leer las mesas no hay tarjeta de zonas (no se inventan)', (tester) async {
      await montar(tester, cuerpo(r: reporte(zonaDeMesa: null)), size: const Size(1280, 2000));
      expect(find.text('Por zona'), findsNothing);
      expect(find.text('Terraza'), findsNothing);
      // La de tarjeta y efectivo ocupa el ancho.
      expect(find.text('Tarjeta y efectivo'), findsOneWidget);
    });

    testWidgets('una mesa que no está en la lista va a "Sin zona"', (tester) async {
      final r = PropinasReporte.desde(
        [pedido(venta: 100, tip: 10, mesa: 'mesa-borrada', hora: a(12))],
        zonaDeMesa: const {'t1': 'Terraza'},
      );
      await montar(tester, cuerpo(r: r, total: 10, enCaja: 0), size: const Size(1280, 2000));
      expect(find.text('Sin zona'), findsOneWidget);
    });

    testWidgets('tarjeta y efectivo: cuánto de la propina entró por cada uno', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 2000));
      expect(find.text('Tarjeta y efectivo'), findsOneWidget);
      expect(find.text('Tarjeta'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('Q180.00'), findsOneWidget);
      expect(find.text('90% del total'), findsOneWidget);
      expect(find.text('${_pedidos(6)} · ${p1(180 / 1600 * 100)} de propina'), findsOneWidget);
    });

    testWidgets('sin propinas de ningún método la barra queda vacía, sin romper', (tester) async {
      final r = PropinasReporte.desde([pedido(venta: 100, hora: a(12)), pedido(venta: 100, metodo: 'cash', hora: a(13))]);
      await montar(tester, cuerpo(r: r, total: 0, enCaja: 0), size: const Size(1280, 2000));
      expect(tester.takeException(), isNull);
      expect(find.text('Tarjeta y efectivo'), findsOneWidget);
    });
  });

  group('lo que no se puede mostrar', () {
    testWidgets('sin pedidos lo dice y deja solo el total', (tester) async {
      await montar(tester, cuerpo(r: PropinasReporte.vacio, total: 0, enCaja: 0));
      expect(find.text('No hubo ventas en este período.'), findsOneWidget);
      expect(find.text('Propinas del período'), findsOneWidget);
      expect(find.text('Q0.00'), findsOneWidget);
      expect(find.text('Propina promedio'), findsNothing);
      expect(find.text('¿Quién recibe propina?'), findsNothing);
    });

    testWidgets('la vista de año solo sabe el total: lo dice y no inventa el desglose', (tester) async {
      await montar(tester, cuerpo(r: PropinasReporte.vacio, total: 24500, enCaja: 0, conDetalle: false));
      expect(find.text('Q24,500.00'), findsOneWidget);
      expect(find.textContaining('En la vista de año no se leen los pedidos'), findsOneWidget);
      expect(find.text('No hubo ventas en este período.'), findsNothing);
      expect(find.text('Propina promedio'), findsNothing);
      expect(find.text('¿Quién recibe propina?'), findsNothing);
    });

    testWidgets('si el período se leyó incompleto, avisa que puede quedar corto', (tester) async {
      await montar(tester, cuerpo(incompleto: true));
      expect(find.textContaining('más pedidos de los que se pueden leer de una vez'), findsOneWidget);

      await montar(tester, cuerpo());
      expect(find.textContaining('más pedidos de los que se pueden leer'), findsNothing);
    });
  });

  group('las tarjetas por ancho', () {
    Future<List<double>> ys(WidgetTester tester, Size s, List<String> textos) async {
      await montar(tester, cuerpo(), size: Size(s.width, 3000));
      return [for (final t in textos) tester.getTopLeft(find.text(t)).dy];
    }

    testWidgets('en 1280 van de dos en dos, a la misma altura', (tester) async {
      final y = await ys(tester, const Size(1280, 800), ['¿Quién recibe propina?', '¿A qué hora se deja más propina?']);
      expect(y[0], y[1]);
      final z = await ys(tester, const Size(1280, 800), ['Por tipo de servicio', 'Según el tamaño de la cuenta']);
      expect(z[0], z[1]);
      final w = await ys(tester, const Size(1280, 800), ['Por zona', 'Tarjeta y efectivo']);
      expect(w[0], w[1]);
    });

    for (final s in const [Size(360, 800), Size(390, 844), Size(700, 900)]) {
      testWidgets('en ${s.width.toInt()} van una debajo de otra', (tester) async {
        final y = await ys(tester, s, ['¿Quién recibe propina?', '¿A qué hora se deja más propina?']);
        expect(y[1], greaterThan(y[0]));
        final z = await ys(tester, s, ['Por tipo de servicio', 'Según el tamaño de la cuenta']);
        expect(z[1], greaterThan(z[0]));
        final w = await ys(tester, s, ['Por zona', 'Tarjeta y efectivo']);
        expect(w[1], greaterThan(w[0]));
      });
    }

    testWidgets('a la misma altura las dos tarjetas del par miden lo mismo', (tester) async {
      await montar(tester, cuerpo(), size: const Size(1280, 3000));
      final izquierda = tester.getSize(find.ancestor(of: find.text('¿Quién recibe propina?'), matching: find.byType(InicioCard)).first);
      final derecha = tester.getSize(find.ancestor(of: find.text('¿A qué hora se deja más propina?'), matching: find.byType(InicioCard)).first);
      expect(izquierda.height, derecha.height);
    });
  });

  // La pantalla real mete el cuerpo en el cambio de sucursal
  // (LocationContentSwitcher), que es un AnimatedSwitcher: lo pone en un Stack
  // centrado y con restricciones sueltas. Un SingleChildScrollView mide lo que
  // mide su contenido, así que con poco que mostrar todo quedaba al medio de la
  // pantalla, con un hueco enorme entre las pestañas y la tarjeta. El `montar`
  // de arriba no lo ve: el Scaffold da restricciones firmes.
  group('dentro del cambio de sucursal', () {
    for (final tam in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets('con poco que mostrar el contenido arranca arriba, no al medio ($tam)', (tester) async {
        tester.view.physicalSize = tam;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        const arribaDelArea = 100.0; // el encabezado y las pestañas
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
                      child: RefreshIndicator(
                        onRefresh: () async {},
                        child: cuerpo(r: PropinasReporte.vacio, total: 0, enCaja: 0),
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
        expect(tester.getSize(find.byType(SingleChildScrollView)).height, tam.height - arribaDelArea);
        // ...y la primera tarjeta arranca bajo las pestañas, no al medio.
        expect(tester.getTopLeft(find.text('Propinas del período')).dy, lessThan(arribaDelArea + 60));
      });
    }
  });

  group('cabe sin desbordar', () {
    for (final s in tamanos) {
      testWidgets('a ${s.width.toInt()} con letra grande y datos completos', (tester) async {
        await montar(tester, cuerpo(), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await bajarHasta(tester, find.text('Tarjeta y efectivo'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande, cifras enormes, nombres larguísimos y 20 meseros', (tester) async {
        final r = PropinasReporte.desde(
          [
            for (var i = 0; i < 20; i++)
              pedido(
                venta: 98765432.1 + i,
                tip: 1234567.89 + i,
                usuario: 'u$i',
                nombre: 'María de los Ángeles Fernández de la Vega y Montoya número $i',
                tipo: i.isEven ? 'dine_in' : 'delivery',
                mesa: 'mesa-$i',
                metodo: i % 3 == 0 ? 'cash' : 'card',
                hora: a(i % 24),
              ),
          ],
          anteriores: [pedido(venta: 1, tip: 1, hora: a(1))],
          zonaDeMesa: {for (var i = 0; i < 20; i++) 'mesa-$i': 'Terraza del segundo piso junto a la piscina $i'},
        );
        await montar(tester, cuerpo(r: r, total: 98765432123.45, enCaja: 5555555.5), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await bajarHasta(tester, find.text('Tarjeta y efectivo'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a ${s.width.toInt()} con letra grande en la vista de año y sin pedidos', (tester) async {
        await montar(tester, cuerpo(r: PropinasReporte.vacio, total: 12345678.9, enCaja: 1234567.8, conDetalle: false),
            size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
        await montar(tester, cuerpo(r: PropinasReporte.vacio, total: 0, enCaja: 0, incompleto: true), size: s, escala: 1.35);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

String _pedidos(int n) => '$n pedido${n == 1 ? '' : 's'}';
