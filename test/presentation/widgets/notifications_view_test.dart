import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/manager_notification.dart';
import 'package:saborpro_reports/presentation/widgets/cortesias_view.dart' show CortesiasColores;
import 'package:saborpro_reports/presentation/widgets/notifications_view.dart';

/// La vista de la bandeja de avisos, sin Firebase: la pantalla real solo le pasa
/// la lista del provider. Los textos de prueba son las plantillas EXACTAS que
/// escriben las Cloud Functions (ver aviso_resumen_test.dart), no frases
/// inventadas.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  // Hoy, para que "HOY" y "AYER" no dependan del reloj de quien corre la prueba.
  final ahora = DateTime(2026, 11, 20, 14, 30);

  ManagerNotification aviso(
    String id,
    ManagerNotificationType tipo,
    String title,
    String body, {
    bool read = false,
    DateTime? cuando,
    Map<String, String> data = const {},
  }) =>
      ManagerNotification(
        id: id,
        tipo: tipo,
        title: title,
        body: body,
        data: data,
        locationId: 'L1',
        read: read,
        createdAt: cuando ?? DateTime(2026, 11, 20, 8),
      );

  ManagerNotification stock({bool read = false}) => aviso(
        'stock',
        ManagerNotificationType.stockBajo,
        '📉 Stock bajo — Santa Rosalía',
        '22 producto(s) con stock bajo: Adrenalina 296 ml, Dassani 1 Litro, '
            'Fanta Uva Desechable 600 ml y 19 más',
        read: read,
      );

  ManagerNotification cierre({bool read = false}) => aviso(
        'cierre',
        ManagerNotificationType.cajaCerrada,
        '🔒 Caja cerrada — Cuadró',
        'Rosario cerró caja en Santa Rosalía. Venta total: Q2172.00',
        read: read,
        data: {'cuadro': 'true'},
        cuando: DateTime(2026, 11, 20, 7, 40),
      );

  ManagerNotification descuadre({bool read = false}) => aviso(
        'descuadre',
        ManagerNotificationType.cajaCerrada,
        '⚠️ Caja cerrada — Descuadre',
        'Rosario cerró caja en Santa Rosalía con faltante de Q25.00. Venta total: Q2860.00',
        read: read,
        data: {'cuadro': 'false'},
        cuando: DateTime(2026, 11, 20, 7, 30),
      );

  ManagerNotification apertura({bool read = false}) => aviso(
        'apertura',
        ManagerNotificationType.cajaAbierta,
        '🔓 Caja abierta',
        'Rosario abrió caja en Santa Rosalía',
        read: read,
        cuando: DateTime(2026, 11, 20, 6, 50),
      );

  ManagerNotification retiro({bool read = false}) => aviso(
        'retiro',
        ManagerNotificationType.retiro,
        '💸 Retiro de efectivo',
        'Rosario retiró Q500.00 de la caja en Santa Rosalía — Compra de hielo (Insumos)',
        read: read,
        cuando: DateTime(2026, 11, 20, 7, 20),
      );

  ManagerNotification gasto({bool read = false}) => aviso(
        'gasto',
        ManagerNotificationType.gasto,
        '💸 Nuevo gasto registrado',
        'Ana registró un gasto de Q50.00 (Servicios) en Santa Rosalía',
        read: read,
        cuando: DateTime(2026, 11, 20, 7, 10),
      );

  /// Una entrada de inventario. Por omisión, las que se juntan en una fila: la
  /// misma persona, el mismo movimiento, la misma sucursal y el mismo minuto.
  ManagerNotification entrada(
    String id,
    String producto,
    String cantidad, {
    String quien = 'Soporte',
    String movimiento = 'entrada',
    String sucursal = 'Santa Rosalía',
    DateTime? cuando,
    bool read = false,
  }) =>
      aviso(
        id,
        ManagerNotificationType.inventario,
        '📦 ${movimiento[0].toUpperCase()}${movimiento.substring(1)} de inventario',
        '$quien registró $movimiento de $cantidad en $producto ($sucursal)',
        read: read,
        cuando: cuando ?? DateTime(2026, 11, 20, 8, 15, 10),
      );

  List<ManagerNotification> tres({bool read = false}) => [
        entrada('i1', 'Monte Carlo Bajo Cero', '24', read: read),
        entrada('i2', 'Hielo', '12', read: read, cuando: DateTime(2026, 11, 20, 8, 15, 40)),
        entrada('i3', 'Sal', '6', read: read, cuando: DateTime(2026, 11, 20, 8, 15, 55)),
      ];

  Widget host(
    List<ManagerNotification> avisos, {
    bool cargando = false,
    String? error,
    ValueChanged<List<String>>? onLeer,
    VoidCallback? onMarcarTodas,
    double escala = 1.0,
  }) =>
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: kAvisosBg,
          body: NotificationsView(
            avisos: avisos,
            cargando: cargando,
            error: error,
            onLeer: onLeer ?? (_) {},
            onMarcarTodas: onMarcarTodas ?? () {},
            ahora: ahora,
          ),
        ),
      );

  void tamano(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> montar(
    WidgetTester tester,
    List<ManagerNotification> avisos, {
    Size size = const Size(360, 800),
    bool cargando = false,
    String? error,
    ValueChanged<List<String>>? onLeer,
    VoidCallback? onMarcarTodas,
    double escala = 1.0,
  }) async {
    tamano(tester, size);
    await tester.pumpWidget(host(avisos,
        cargando: cargando,
        error: error,
        onLeer: onLeer,
        onMarcarTodas: onMarcarTodas,
        escala: escala));
    await tester.pumpAndSettle();
  }

  // Los filtros son lo único que se desplaza en horizontal: sirve para ubicarlos
  // aunque el mismo texto ("Stock bajo") también sea el título de una fila.
  final filtros = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
  Finder chip(String nombre) => find.descendant(of: filtros, matching: find.text(nombre));
  // En 360dp los últimos chips quedan fuera de pantalla (la fila se desplaza):
  // primero se traen a la vista, como haría el dedo.
  Future<void> elegir(WidgetTester tester, String nombre) async {
    await tester.ensureVisible(chip(nombre));
    await tester.pumpAndSettle();
    await tester.tap(chip(nombre));
    await tester.pumpAndSettle();
  }

  List<String> textosDeFiltros() => [
        for (final e in find.descendant(of: filtros, matching: find.byType(Text)).evaluate())
          (e.widget as Text).data!,
      ];

  final puntoSinLeer = find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    return d is BoxDecoration && d.shape == BoxShape.circle && d.color == CortesiasColores.accent;
  });

  group('encabezado', () {
    testWidgets('dice cuántos faltan por leer', (tester) async {
      await montar(tester, [stock(), cierre(read: true)]);
      expect(find.text('Avisos'), findsOneWidget);
      expect(find.text('1 sin leer'), findsOneWidget);
      expect(find.text('Todo leído'), findsNothing);
    });

    testWidgets('sin pendientes dice "Todo leído", no un cero', (tester) async {
      await montar(tester, [stock(read: true)]);
      expect(find.text('Todo leído'), findsOneWidget);
      expect(find.text('0 sin leer'), findsNothing);
    });

    testWidgets('mientras carga no afirma "Todo leído": todavía no se sabe',
        (tester) async {
      tamano(tester, const Size(360, 800));
      await tester.pumpWidget(host(const [], cargando: true));
      await tester.pump();
      expect(find.text('Todo leído'), findsNothing);
      expect(find.textContaining('sin leer'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('"Marcar leídas" actúa con pendientes y no hace nada sin ellas',
        (tester) async {
      var llamadas = 0;
      await montar(tester, [stock(read: true)], onMarcarTodas: () => llamadas++);
      await tester.tap(find.byTooltip('Marcar leídas'));
      await tester.pump();
      expect(llamadas, 0, reason: 'sin pendientes el botón está apagado');

      await montar(tester, [stock()], onMarcarTodas: () => llamadas++);
      await tester.tap(find.byTooltip('Marcar leídas'));
      await tester.pump();
      expect(llamadas, 1);
    });

    testWidgets('en el teléfono es solo el ícono; en pantalla ancha lleva el nombre',
        (tester) async {
      await montar(tester, [stock()], size: const Size(390, 844));
      expect(find.text('Marcar leídas'), findsNothing);
      expect(find.byTooltip('Marcar leídas'), findsOneWidget);

      await montar(tester, [stock()], size: const Size(1280, 800));
      expect(find.text('Marcar leídas'), findsOneWidget);
    });
  });

  group('filtros', () {
    testWidgets('siempre Todos, Stock bajo, Caja e Inventario, con su cuenta',
        (tester) async {
      await montar(tester, [stock(), cierre(), descuadre(), apertura(), ...tres()]);
      // Cuenta avisos, no filas: las tres entradas juntas siguen siendo tres.
      expect(textosDeFiltros(),
          ['Todos', '7', 'Stock bajo', '1', 'Caja', '3', 'Inventario', '3']);
    });

    testWidgets('Retiros y Gastos aparecen solo si hay de ésos', (tester) async {
      await montar(tester, [stock(), retiro(), gasto()]);
      expect(textosDeFiltros(), [
        'Todos', '3', 'Stock bajo', '1', 'Caja', '0', 'Inventario', '0',
        'Retiros', '1', 'Gastos', '1',
      ]);
    });

    testWidgets('un tipo que la app no conoce tiene su filtro "Avisos"',
        (tester) async {
      await montar(tester, [
        aviso('x', ManagerNotificationType.otro, '🆕 Algo nuevo', 'Un texto'),
      ]);
      expect(textosDeFiltros().contains('Avisos'), isTrue);
    });

    testWidgets('elegir uno deja solo los de su familia, y Todos los devuelve',
        (tester) async {
      await montar(tester, [stock(), cierre(), apertura(), ...tres()]);
      // El título "Stock bajo" está dos veces: el filtro y la fila.
      expect(find.text('Stock bajo'), findsNWidgets(2));

      await elegir(tester, 'Caja');
      expect(find.text('Caja cerrada'), findsOneWidget);
      expect(find.text('Caja abierta'), findsOneWidget);
      expect(find.text('Stock bajo'), findsOneWidget, reason: 'solo el filtro');
      expect(find.text('Entrada de inventario'), findsNothing);

      await elegir(tester, 'Todos');
      expect(find.text('Stock bajo'), findsNWidgets(2));
      expect(find.text('Entrada de inventario'), findsOneWidget);
    });

    testWidgets('un filtro sin avisos dice que todo está en orden', (tester) async {
      await montar(tester, [stock()]);
      await elegir(tester, 'Inventario');
      expect(find.text('Todo en orden'), findsOneWidget);
      expect(find.text('No hay avisos aquí.'), findsOneWidget);
      // Y el encabezado sigue diciendo lo que falta por leer.
      expect(find.text('1 sin leer'), findsOneWidget);
    });

    testWidgets('si el filtro elegido se queda sin avisos, no desaparece',
        (tester) async {
      await montar(tester, [stock(), apertura()]);
      await elegir(tester, 'Caja');

      // Llega una lista sin avisos de caja con el filtro todavía en "Caja".
      await tester.pumpWidget(host([stock()]));
      await tester.pumpAndSettle();
      expect(chip('Caja'), findsOneWidget);
      expect(find.text('Todo en orden'), findsOneWidget);
    });
  });

  group('cada fila', () {
    testWidgets('cierre que cuadró: título, pastilla, quién y dónde', (tester) async {
      await montar(tester, [cierre()]);
      expect(find.text('Caja cerrada'), findsOneWidget);
      expect(find.text('Cuadró'), findsOneWidget);
      expect(find.textContaining('Rosario · Santa Rosalía'), findsOneWidget);
      // Sin el emoji que mandan las funciones.
      expect(find.textContaining('🔒'), findsNothing);
    });

    testWidgets('cierre con faltante: pastilla con lo que faltó', (tester) async {
      await montar(tester, [descuadre()]);
      expect(find.text('Faltó Q25.00'), findsOneWidget);
      expect(find.text('Cuadró'), findsNothing);
    });

    testWidgets('stock bajo: cuántos y la sucursal con los nombres', (tester) async {
      await montar(tester, [stock()]);
      expect(find.text('22'), findsOneWidget);
      expect(find.textContaining('Santa Rosalía · Adrenalina 296 ml'), findsOneWidget);
    });

    testWidgets('retiro: el motivo se ve', (tester) async {
      await montar(tester, [retiro()]);
      expect(find.text('Retiro de efectivo'), findsOneWidget);
      expect(find.textContaining('Compra de hielo (Insumos)'), findsOneWidget);
    });

    testWidgets('en el teléfono el monto abre la descripción, no va a la derecha',
        (tester) async {
      await montar(tester, [cierre()], size: const Size(390, 844));
      // Dentro del texto de la descripción: no hay un monto suelto.
      expect(find.text('Q2,172.00'), findsNothing);
      expect(find.textContaining('Q2,172.00'), findsOneWidget);
    });

    testWidgets('en pantalla ancha el monto va a la derecha, en negritas',
        (tester) async {
      await montar(tester, [cierre()], size: const Size(1280, 800));
      expect(find.text('Q2,172.00'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Q2,172.00')).dx, greaterThan(700));
      // Y la descripción ya no lo repite.
      expect(find.textContaining('Q2,172.00'), findsOneWidget);
    });

    testWidgets('lo no leído va en negritas y con el punto; lo leído, sin punto',
        (tester) async {
      await montar(tester, [apertura(), cierre(read: true)]);
      final sinLeer = tester.widget<Text>(find.text('Caja abierta'));
      final leido = tester.widget<Text>(find.text('Caja cerrada'));
      expect(sinLeer.style!.fontWeight, FontWeight.w700);
      expect(leido.style!.fontWeight, FontWeight.w600);
      expect(puntoSinLeer, findsOneWidget);
    });

    testWidgets('la descripción cabe en dos líneas en el teléfono y en una en ancho',
        (tester) async {
      await montar(tester, [stock()], size: const Size(390, 844));
      expect(tester.widget<Text>(find.textContaining('Santa Rosalía · Adrenalina')).maxLines, 2);

      await montar(tester, [stock()], size: const Size(1280, 800));
      expect(tester.widget<Text>(find.textContaining('Santa Rosalía · Adrenalina')).maxLines, 1);
    });

    testWidgets('un texto que no se entendió se muestra completo, sin cortar',
        (tester) async {
      final largo = 'Una plantilla nueva que esta versión no conoce y que trae '
          'bastante texto para que ocupe varias líneas en un teléfono angosto, '
          'hasta el final del texto';
      await montar(tester, [
        aviso('raro', ManagerNotificationType.otro, '🆕 Algo nuevo', largo),
      ]);
      final texto = find.text(largo);
      expect(texto, findsOneWidget);
      expect(tester.widget<Text>(texto).maxLines, isNull);
      final parrafo = tester.renderObject<RenderParagraph>(
          find.descendant(of: texto, matching: find.byType(RichText)));
      expect(parrafo.didExceedMaxLines, isFalse);
      expect(find.text('Algo nuevo'), findsOneWidget);
    });
  });

  group('entradas de inventario seguidas', () {
    testWidgets('se juntan en una fila con cuántas son y cuántas unidades',
        (tester) async {
      await montar(tester, tres());
      expect(find.text('Entrada de inventario'), findsOneWidget);
      // La pastilla con cuántas son, dentro de su fila (el "3" también sale en
      // las cuentas de los filtros).
      final fila = find.widgetWithText(InkWell, 'Entrada de inventario');
      expect(find.descendant(of: fila, matching: find.text('3')), findsOneWidget);
      expect(find.textContaining('Soporte · 42 unidades · Santa Rosalía'), findsOneWidget);
      // Cerrada: no muestra el detalle.
      expect(find.text('Monte Carlo Bajo Cero'), findsNothing);
    });

    testWidgets('abrirla muestra cada producto y marca leídos los tres',
        (tester) async {
      final leidos = <List<String>>[];
      await montar(tester, tres(), onLeer: leidos.add);
      await tester.tap(find.text('Entrada de inventario'));
      await tester.pumpAndSettle();

      expect(find.text('Monte Carlo Bajo Cero'), findsOneWidget);
      expect(find.text('Hielo'), findsOneWidget);
      expect(find.text('Sal'), findsOneWidget);
      expect(find.text('+24'), findsOneWidget);
      expect(leidos, [
        ['i1', 'i2', 'i3'],
      ]);
    });

    testWidgets('cerrarla otra vez ya no marca nada: ya estaban leídas',
        (tester) async {
      final leidos = <List<String>>[];
      await montar(tester, tres(), onLeer: leidos.add);
      await tester.tap(find.text('Entrada de inventario'));
      await tester.pumpAndSettle();
      expect(leidos, hasLength(1));

      // El provider devuelve los mismos avisos ya leídos.
      await tester.pumpWidget(host(tres(read: true), onLeer: leidos.add));
      await tester.pumpAndSettle();
      expect(find.text('Monte Carlo Bajo Cero'), findsOneWidget, reason: 'sigue abierta');

      await tester.tap(find.text('Entrada de inventario'));
      await tester.pumpAndSettle();
      expect(find.text('Monte Carlo Bajo Cero'), findsNothing, reason: 'se cerró');
      expect(leidos, hasLength(1));
    });

    testWidgets('otro minuto, otra persona u otro movimiento: filas aparte',
        (tester) async {
      await montar(tester, [
        entrada('a', 'Hielo', '1'),
        entrada('b', 'Sal', '1', cuando: DateTime(2026, 11, 20, 8, 16)),
        entrada('c', 'Pan', '1', quien: 'Ana', cuando: DateTime(2026, 11, 20, 8, 16, 30)),
        entrada('d', 'Vasos', '1',
            movimiento: 'salida', quien: 'Ana', cuando: DateTime(2026, 11, 20, 8, 16, 40)),
      ]);
      expect(find.text('Entrada de inventario'), findsNWidgets(3));
      expect(find.text('Salida de inventario'), findsOneWidget);
    });

    testWidgets('otra sucursal o un aviso entre medio no se mezclan', (tester) async {
      await montar(tester, [
        entrada('a', 'Hielo', '1'),
        entrada('b', 'Sal', '1', sucursal: 'Zona 10'),
        apertura(),
        entrada('c', 'Pan', '1'),
      ]);
      expect(find.text('Entrada de inventario'), findsNWidgets(3));
    });

    testWidgets('una entrada con un texto que no se entendió no se junta',
        (tester) async {
      await montar(tester, [
        entrada('a', 'Hielo', '1'),
        aviso('x', ManagerNotificationType.inventario, '📦 Entrada de inventario',
            'Algo que ninguna plantilla conoce',
            cuando: DateTime(2026, 11, 20, 8, 15, 20)),
        entrada('b', 'Sal', '1', cuando: DateTime(2026, 11, 20, 8, 15, 30)),
      ]);
      expect(find.text('Entrada de inventario'), findsNWidgets(3));
      expect(find.text('Algo que ninguna plantilla conoce'), findsOneWidget);
    });
  });

  group('tocar', () {
    testWidgets('un aviso sin leer se marca; uno leído no hace nada', (tester) async {
      final leidos = <List<String>>[];
      await montar(tester, [apertura(), cierre(read: true)], onLeer: leidos.add);

      await tester.tap(find.text('Caja cerrada'));
      await tester.pump();
      expect(leidos, isEmpty);

      await tester.tap(find.text('Caja abierta'));
      await tester.pump();
      expect(leidos, [
        ['apertura'],
      ]);
    });
  });

  group('por día', () {
    testWidgets('HOY, AYER y los más viejos con el día completo', (tester) async {
      await montar(tester, [
        apertura(),
        aviso('ayer', ManagerNotificationType.gasto, '💸 Nuevo gasto registrado',
            'Ana registró un gasto de Q50.00 (Servicios) en Santa Rosalía',
            cuando: DateTime(2026, 11, 19, 22)),
        aviso('viejo', ManagerNotificationType.gasto, '💸 Nuevo gasto registrado',
            'Ana registró un gasto de Q70.00 (Servicios) en Santa Rosalía',
            cuando: DateTime(2026, 11, 18, 9)),
      ]);
      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('AYER'), findsOneWidget);
      expect(find.text('MIÉRCOLES 18 DE NOVIEMBRE'), findsOneWidget);
    });

    testWidgets('a las 00:30 lo de las 23:50 es de ayer, no de hoy', (tester) async {
      tamano(tester, const Size(360, 800));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: kAvisosBg,
          body: NotificationsView(
            avisos: [
              aviso('a', ManagerNotificationType.cajaAbierta, '🔓 Caja abierta',
                  'Rosario abrió caja en Santa Rosalía', cuando: DateTime(2026, 11, 21, 0, 10)),
              aviso('b', ManagerNotificationType.cajaAbierta, '🔓 Caja abierta',
                  'Rosario abrió caja en Santa Rosalía', cuando: DateTime(2026, 11, 20, 23, 50)),
            ],
            onLeer: (_) {},
            onMarcarTodas: () {},
            ahora: DateTime(2026, 11, 21, 0, 30),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('AYER'), findsOneWidget);
    });
  });

  group('sin lista', () {
    testWidgets('vacía explica qué va a aparecer, arriba y sin centrar',
        (tester) async {
      await montar(tester, [], size: const Size(1280, 900));
      expect(find.text('Sin avisos por ahora'), findsOneWidget);
      expect(find.textContaining('cierres de caja'), findsOneWidget);
      // Bajo el encabezado, no en el medio de la pantalla.
      expect(tester.getTopLeft(find.text('Sin avisos por ahora')).dy, lessThan(300));
      // Sin nada que filtrar no hay filtros.
      expect(filtros, findsNothing);
    });

    testWidgets('con error lo dice en vez de un spinner eterno', (tester) async {
      await montar(tester, [], error: 'No se pudieron cargar los avisos');
      expect(find.text('No se pudieron cargar'), findsOneWidget);
      expect(find.text('No se pudieron cargar los avisos'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('cabe', () {
    // Todos los tipos, de los más largos a los más cortos, y las entradas
    // juntas abiertas (el detalle es lo más ancho).
    List<ManagerNotification> variada() => [
          stock(),
          cierre(),
          descuadre(),
          retiro(),
          gasto(),
          apertura(read: true),
          ...tres(),
          aviso('raro', ManagerNotificationType.otro, '🆕 Algo nuevo',
              'Un texto largo que ninguna plantilla conoce y que sigue y sigue y sigue'),
          aviso('ayer', ManagerNotificationType.retirosEnLote, '💸 Retiros de efectivo',
              'Se registraron 5 retiros por Q125000.00 en la caja de Rosario en Santa Rosalía',
              cuando: DateTime(2026, 11, 19, 21)),
        ];

    for (final size in const [Size(360, 640), Size(390, 844), Size(700, 900), Size(1280, 800)]) {
      for (final escala in const [1.0, 1.35]) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()} con letra a $escala',
            (tester) async {
          await montar(tester, variada(), size: size, escala: escala);
          expect(tester.takeException(), isNull);

          // En un teléfono bajo la fila queda fuera de pantalla: se trae a la vista.
          await tester.ensureVisible(find.text('Entrada de inventario'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Entrada de inventario'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Y el detalle se abrió de verdad (el toque no se perdió).
          expect(find.text('Monte Carlo Bajo Cero'), findsOneWidget);

          // Hasta el final de la lista.
          await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('un monto enorme con letra grande tampoco desborda el título',
        (tester) async {
      await montar(
        tester,
        [
          aviso(
            'g',
            ManagerNotificationType.cajaCerrada,
            '⚠️ Caja cerrada — Descuadre',
            'Rosario cerró caja en Santa Rosalía con faltante de Q12345678.00. '
                'Venta total: Q98765432.00',
            data: {'cuadro': 'false'},
          ),
        ],
        escala: 1.35,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Faltó Q12,345,678.00'), findsOneWidget);
    });
  });
}
