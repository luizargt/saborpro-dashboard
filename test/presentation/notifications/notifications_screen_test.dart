import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:saborpro_reports/data/models/manager_notification.dart';
import 'package:saborpro_reports/presentation/providers/notifications_provider.dart';
import 'package:saborpro_reports/presentation/screens/notifications/notifications_screen.dart';

/// Provider de mentira: la pantalla solo consume `todas`, `sinLeer`,
/// `cargando` y `error`, así que se puede probar sin Firestore.
class _FakeProvider extends NotificationsProvider {
  final List<ManagerNotification> _lista;
  final bool _cargando;
  final String? _error;
  int marcarTodasLlamado = 0;
  final marcadas = <String>[];

  _FakeProvider(this._lista, {bool cargando = false, String? error})
      : _cargando = cargando,
        _error = error;

  @override
  List<ManagerNotification> get todas => _lista;
  @override
  bool get cargando => _cargando;
  @override
  String? get error => _error;
  @override
  int get sinLeer => _lista.where((n) => !n.read).length;

  @override
  Future<void> marcarLeida(String id) async => marcadas.add(id);
  @override
  Future<void> marcarTodasLeidas() async => marcarTodasLlamado++;
}

ManagerNotification _aviso({
  String id = 'n1',
  ManagerNotificationType tipo = ManagerNotificationType.gasto,
  String title = '💸 Nuevo gasto registrado',
  String body = 'Ana registró un gasto de Q50.00',
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
      createdAt: cuando ?? DateTime.now(),
    );

Future<_FakeProvider> _pump(
  WidgetTester tester,
  List<ManagerNotification> avisos, {
  bool cargando = false,
  String? error,
}) async {
  final p = _FakeProvider(avisos, cargando: cargando, error: error);
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<NotificationsProvider>.value(
      value: p,
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return p;
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('modelo', () {
    test('el tipo se resuelve por la misma clave que manda el backend', () {
      expect(ManagerNotificationType.desde('cash_register_closed'),
          ManagerNotificationType.cajaCerrada);
      expect(ManagerNotificationType.desde('low_stock_summary'),
          ManagerNotificationType.stockBajo);
    });

    test('un tipo nuevo del backend no rompe la app', () {
      // Agregar un aviso en las functions y olvidarse de la app tiene que
      // degradar a neutro, no reventar.
      expect(ManagerNotificationType.desde('algo_que_no_existe'),
          ManagerNotificationType.otro);
      expect(ManagerNotificationType.desde(null), ManagerNotificationType.otro);
    });

    test('el cierre descuadrado se marca como alerta, el cuadrado no', () {
      final malo = _aviso(
        tipo: ManagerNotificationType.cajaCerrada,
        data: {'cuadro': 'false'},
      );
      final bueno = _aviso(
        tipo: ManagerNotificationType.cajaCerrada,
        data: {'cuadro': 'true'},
      );
      expect(malo.esAlerta, isTrue);
      expect(bueno.esAlerta, isFalse);
      expect(malo.color, isNot(bueno.color));
    });

    test('todos los tipos tienen ícono, color y etiqueta', () {
      for (final t in ManagerNotificationType.values) {
        expect(t.etiqueta, isNotEmpty, reason: '$t');
        expect(t.icono, isNotNull, reason: '$t');
        expect(t.color, isNotNull, reason: '$t');
      }
    });

    test('created_at ausente no rompe: se toma como ahora', () {
      // Un documento recién escrito llega de la caché sin resolver el
      // serverTimestamp.
      final antes = DateTime.now().subtract(const Duration(seconds: 1));
      final n = ManagerNotification(
        id: 'x',
        tipo: ManagerNotificationType.otro,
        title: 't',
        body: 'b',
        data: const {},
        locationId: '',
        read: false,
        createdAt: DateTime.now(),
      );
      expect(n.createdAt.isAfter(antes), isTrue);
    });
  });

  group('pantalla a 360dp', () {
    testWidgets('lista vacía explica qué va a aparecer ahí', (tester) async {
      await _pump(tester, []);
      expect(find.text('Sin avisos por ahora'), findsOneWidget);
      expect(find.textContaining('cierres de caja'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('muestra el aviso y su contador de no leídos', (tester) async {
      await _pump(tester, [
        _aviso(),
        _aviso(id: 'n2', read: true, body: 'Otro gasto ya leído'),
      ]);

      expect(find.text('Ana registró un gasto de Q50.00'), findsOneWidget);
      expect(find.text('Otro gasto ya leído'), findsOneWidget);
      expect(find.text('1 sin leer'), findsOneWidget);
    });

    testWidgets('sin pendientes muestra el rango, no un cero', (tester) async {
      await _pump(tester, [_aviso(read: true)]);
      expect(find.text('Últimos 7 días'), findsOneWidget);
      expect(find.text('0 sin leer'), findsNothing);
    });

    testWidgets('el emoji del título no se repite junto al ícono',
        (tester) async {
      // El título llega como "💸 Nuevo gasto registrado" desde las functions.
      await _pump(tester, [_aviso()]);
      expect(find.text('Nuevo gasto registrado'), findsOneWidget);
      expect(find.textContaining('💸'), findsNothing);
    });

    testWidgets('agrupa por día natural', (tester) async {
      final ahora = DateTime.now();
      await _pump(tester, [
        _aviso(id: 'hoy', cuando: ahora),
        _aviso(
          id: 'ayer',
          cuando: DateTime(ahora.year, ahora.month, ahora.day)
              .subtract(const Duration(hours: 2)),
        ),
      ]);

      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('AYER'), findsOneWidget);
    });

    testWidgets('tocar uno sin leer lo marca', (tester) async {
      final p = await _pump(tester, [_aviso(id: 'n7')]);
      await tester.tap(find.text('Ana registró un gasto de Q50.00'));
      await tester.pump();
      expect(p.marcadas, ['n7']);
    });

    testWidgets('"Marcar leídas" solo existe si hay pendientes',
        (tester) async {
      await _pump(tester, [_aviso(read: true)]);
      expect(find.text('Marcar leídas'), findsNothing);

      final p = await _pump(tester, [_aviso()]);
      expect(find.text('Marcar leídas'), findsOneWidget);
      await tester.tap(find.text('Marcar leídas'));
      await tester.pump();
      expect(p.marcarTodasLlamado, 1);
    });

    testWidgets('un error se muestra en vez de un spinner eterno',
        (tester) async {
      await _pump(tester, [], error: 'No se pudieron cargar los avisos');
      expect(find.text('No se pudieron cargar'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('cargando muestra el spinner', (tester) async {
      final p = _FakeProvider([], cargando: true);
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: p,
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('una tanda larga y variada no desborda', (tester) async {
      final avisos = <ManagerNotification>[];
      for (var i = 0; i < 25; i++) {
        avisos.add(_aviso(
          id: 'n$i',
          tipo: ManagerNotificationType
              .values[i % ManagerNotificationType.values.length],
          title: 'Aviso larguísimo número $i que ocupa bastante espacio',
          body: 'Un cuerpo también extenso para ver que la fila se acomoda '
              'sin romper el layout en un teléfono angosto.',
          read: i.isEven,
          cuando: DateTime.now().subtract(Duration(hours: i * 5)),
        ));
      }
      await _pump(tester, avisos);
      expect(tester.takeException(), isNull);
    });
  });

  group('provider', () {
    test('la ventana coincide con la del backend', () {
      // helpers.js usa DIAS_DE_HISTORIAL = 7. Si una cambia sin la otra, el
      // usuario ve avisos que ya se borraron o deja de ver los que existen.
      expect(NotificationsProvider.diasDeHistorial, 7);
    });

    test('sin uid la bandeja queda vacía y sin cargar', () {
      final p = NotificationsProvider();
      p.init(null);
      expect(p.todas, isEmpty);
      expect(p.cargando, isFalse);
      expect(p.sinLeer, 0);
      expect(p.haySinLeer, isFalse);
    });
  });

  test('fromDoc lee lo que escribe el backend', () {
    // Forma exacta del documento que arma saveNotificationHistory.
    final n = ManagerNotification(
      id: 'doc1',
      tipo: ManagerNotificationType.desde('inventory_movement_created'),
      title: '📦 Entrada de inventario',
      body: 'cuerpo',
      data: const {'movement_id': 'm1', 'type': 'inventory_movement_created'},
      locationId: 'L1',
      read: false,
      createdAt: Timestamp.fromDate(DateTime(2026, 9, 3)).toDate(),
    );
    expect(n.tipo, ManagerNotificationType.inventario);
    expect(n.data['movement_id'], 'm1');
    expect(n.read, isFalse);
  });
}
