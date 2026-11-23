import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/detalle_caja.dart';

/// Qué pedidos son de una caja (el filtro de siempre del detalle), cómo se
/// leen y cómo se resumen.
void main() {
  final cobro = DateTime(2026, 11, 20, 19, 30);

  final caja = CashRegisterSummary(
    id: 'cr-A',
    userId: 'u-ana',
    userName: 'Ana Cosme',
    status: 'closed',
    openedAt: DateTime(2026, 11, 20, 18),
    closedAt: DateTime(2026, 11, 21, 1, 25),
    locationId: 'gt',
  );

  Map<String, dynamic> pedido({
    double? pago = 100,
    String metodo = 'cash',
    String? cobrador = 'u-ana',
    String? nombre = 'Ana Cosme',
    String sucursal = 'gt',
    String? estado,
    String? sello,
    DateTime? selladoA,
    Map<String, dynamic>? selloPor,
    DateTime? pagadoA,
    Map<String, dynamic> extra = const {},
  }) =>
      {
        if (pago != null) 'payment_amount': pago,
        'payment_method': metodo,
        if (cobrador != null) 'paid_by_user_id': cobrador,
        if (nombre != null) 'paid_by_user_name': nombre,
        'location_id': sucursal,
        if (estado != null) 'status': estado,
        if (sello != null) 'cash_register_id': sello,
        if (sello != null) 'cash_register_paid_at': Timestamp.fromDate(selladoA ?? (pagadoA ?? cobro)),
        if (selloPor != null) 'cash_register_paid_by': selloPor,
        'paid_at': Timestamp.fromDate(pagadoA ?? cobro),
        ...extra,
      };

  List<String> numeros(List<Map<String, dynamic>> l) => [for (final o in l) o['order_no'] as String];

  Map<String, dynamic> conNumero(Map<String, dynamic> o, String n) => {...o, 'order_no': n};

  group('de qué caja es cada pedido', () {
    test('sin sello, cuenta por quien cobró', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(pedido(), 'propio'),
        conNumero(pedido(cobrador: 'u-otro', nombre: 'Otro'), 'ajeno'),
      ], caja);
      expect(numeros(r), ['propio']);
    });

    test('sin el id del cobrador, por el nombre; sin ninguno de los dos, entra (pedidos muy viejos)', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(pedido(cobrador: null, nombre: 'Ana Cosme'), 'mismo-nombre'),
        conNumero(pedido(cobrador: null, nombre: 'Otra Persona'), 'otro-nombre'),
        conNumero(pedido(cobrador: null, nombre: null), 'sin-nada'),
      ], caja);
      expect(numeros(r), unorderedEquals(['mismo-nombre', 'sin-nada']));
    });

    test('un cobro sellado con ESTA caja cuenta aquí, aunque lo haya cobrado otro usuario', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(pedido(sello: 'cr-A', cobrador: 'u-otro', nombre: 'Otro'), 'sellado-aqui'),
      ], caja);
      expect(numeros(r), ['sellado-aqui']);
    });

    test('un cobro sellado con OTRA caja no cuenta aquí, aunque lo haya cobrado el mismo cajero', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(pedido(sello: 'cr-B'), 'sellado-en-otra'),
      ], caja);
      expect(r, isEmpty);
    });

    test('un sello viejo (el cobro se repitió más de un minuto después) vale el criterio de siempre', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        // Sellado con otra caja, pero el cobro cambió de hora: ya no vale el sello.
        conNumero(pedido(sello: 'cr-B', selladoA: cobro.subtract(const Duration(minutes: 5))), 'sello-viejo-cobrador-ok'),
        conNumero(pedido(sello: 'cr-B', selladoA: cobro.subtract(const Duration(minutes: 5)), cobrador: 'u-otro', nombre: 'Otro'), 'sello-viejo-cobrador-otro'),
        // Dentro del minuto de margen sí vale.
        conNumero(pedido(sello: 'cr-B', selladoA: cobro.add(const Duration(seconds: 30))), 'sello-vigente'),
      ], caja);
      expect(numeros(r), ['sello-viejo-cobrador-ok']);
    });

    test('si lo volvió a cobrar otro usuario, el sello no vale aunque la hora esté dentro del margen', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(
          pedido(sello: 'cr-B', cobrador: 'u-ana', selloPor: {'cash_register_id': 'cr-B', 'user_id': 'u-luis'}),
          'recobrado',
        ),
        // Un sello de OTRA caja en `cash_register_paid_by` no cuenta como evidencia.
        conNumero(
          pedido(sello: 'cr-A', cobrador: 'u-ana', selloPor: {'cash_register_id': 'cr-Z', 'user_id': 'u-luis'}),
          'sello-por-de-otra-caja',
        ),
      ], caja);
      expect(numeros(r), ['recobrado', 'sello-por-de-otra-caja']);
    });

    test('sin canceladas y solo de la sucursal de la caja', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(pedido(), 'ok'),
        conNumero(pedido(estado: 'CANCELLED'), 'cancelado'),
        conNumero(pedido(sucursal: 'sv'), 'otra-sucursal'),
      ], caja);
      expect(numeros(r), ['ok']);
    });

    test('una caja sin sucursal no filtra por sucursal', () {
      final sinSucursal = CashRegisterSummary(
        id: 'cr-A', userId: 'u-ana', userName: 'Ana Cosme', status: 'closed', openedAt: DateTime(2026, 11, 20, 18));
      final r = DetalleCaja.ordenesDeLaCaja([conNumero(pedido(sucursal: 'sv'), 'x')], sinSucursal);
      expect(numeros(r), ['x']);
    });

    test('del más reciente al más antiguo; los que no traen hora, al final', () {
      final r = DetalleCaja.ordenesDeLaCaja([
        conNumero(pedido(pagadoA: DateTime(2026, 11, 20, 19)), 'a-19h'),
        conNumero({...pedido(), 'paid_at': null}, 'sin-hora'),
        conNumero(pedido(pagadoA: DateTime(2026, 11, 21, 0, 30)), 'b-0030'),
        conNumero(pedido(pagadoA: DateTime(2026, 11, 20, 22)), 'c-22h'),
      ], caja);
      expect(numeros(r), ['b-0030', 'c-22h', 'a-19h', 'sin-hora']);
    });
  });

  group('un pedido', () {
    test('el total pagado (con la propina), el subtotal, el descuento, la propina y el método', () {
      final p = PedidoCaja.desde({
        ...pedido(pago: 121, metodo: 'card'),
        'subtotal': 110.0,
        'discount_amount': 5.5,
        'tip_amount': 11.0,
        'order_no': 11,
        'order_prefix': 'E',
      });
      expect(p.total, 121);
      expect(p.subtotal, 110);
      expect(p.descuento, 5.5);
      expect(p.propina, 11);
      expect(p.numero, 'E11');
      expect(p.metodo, 'card');
      expect(p.metodoNombre, 'Tarjeta');
      expect(p.usuario, 'Ana Cosme');
    });

    test('sin subtotal usa el total; sin payment_amount usa total_amount (también como texto)', () {
      final a = PedidoCaja.desde(pedido(pago: 80));
      expect(a.subtotal, 80);
      final b = PedidoCaja.desde({'total_amount': '45.5', 'payment_method': 'cash'});
      expect(b.total, 45.5);
      final c = PedidoCaja.desde({'payment_amount': '12', 'total_amount': 99});
      expect(c.total, 12);
      expect(PedidoCaja.desde({}).total, 0);
    });

    test('la cortesía suma cantidad por precio de los renglones marcados', () {
      final p = PedidoCaja.desde({
        ...pedido(),
        'items': [
          {'is_courtesy': true, 'qty': 2, 'unit_price': 25},
          {'is_courtesy': true, 'quantity': 1, 'price': 10.5},
          {'is_courtesy': false, 'qty': 5, 'unit_price': 100},
          'no-es-un-mapa',
        ],
      });
      expect(p.cortesia, 60.5);
    });

    test('el usuario: quien cobró, si no el mesero, si no quien lo creó, si no una raya', () {
      expect(PedidoCaja.desde({'paid_by_user_name': 'A', 'waiter_name': 'B', 'created_by_user_name': 'C'}).usuario, 'A');
      expect(PedidoCaja.desde({'waiter_name': 'B', 'created_by_user_name': 'C'}).usuario, 'B');
      expect(PedidoCaja.desde({'created_by_user_name': 'C'}).usuario, 'C');
      expect(PedidoCaja.desde({}).usuario, '—');
    });

    test('sin número de pedido, una raya', () {
      expect(PedidoCaja.desde({}).numero, '—');
      expect(PedidoCaja.desde({'order_no': 7}).numero, '7');
    });

    test('un método propio sale con su nombre; sin nombre, el id; split y mixed son "Mixto"', () {
      const nombres = {'custom_vales': 'Vales'};
      expect(PedidoCaja.desde(pedido(metodo: 'custom_vales'), nombresMetodos: nombres).metodoNombre, 'Vales');
      expect(PedidoCaja.desde(pedido(metodo: 'custom_x'), nombresMetodos: nombres).metodoNombre, 'custom_x');
      expect(etiquetaDelMetodo('split'), 'Mixto');
      expect(etiquetaDelMetodo('mixed'), 'Mixto');
      expect(etiquetaDelMetodo('transfer'), 'Transferencia');
      expect(etiquetaDelMetodo('pedidosya'), 'PedidosYa');
      expect(etiquetaDelMetodo('ubereats'), 'Uber Eats');
      expect(PedidoCaja.desde(pedido(metodo: 'split')).llaveMetodo, 'mixto');
      expect(PedidoCaja.desde(pedido(metodo: 'mixed')).llaveMetodo, 'mixto');
    });
  });

  group('el resumen del detalle', () {
    // Ana: 3 pedidos (uno con descuento y cortesía); Alex: 1 pedido.
    final detalle = DetalleCaja.desde([
      {...pedido(pago: 121, metodo: 'card'), 'subtotal': 110.0, 'tip_amount': 11.0},
      {...pedido(pago: 250, metodo: 'cash'), 'subtotal': 250.0, 'discount_amount': 25.0, 'items': [{'is_courtesy': true, 'qty': 1, 'unit_price': 40}]},
      {...pedido(pago: 50, metodo: 'cash'), 'subtotal': 50.0},
      {...pedido(pago: 80, metodo: 'custom_vales', nombre: 'Alex Ojom', cobrador: 'u-alex'), 'subtotal': 70.0, 'tip_amount': 10.0},
    ], nombresMetodos: const {'custom_vales': 'Vales'});

    test('los totales', () {
      final t = detalle.totales;
      expect(t.pedidos, 4);
      expect(t.total, 121 + 250 + 50 + 80);
      expect(t.subtotal, 110 + 250 + 50 + 70);
      expect(t.descuentos, 25);
      expect(t.propinas, 21);
      expect(t.cortesias, 40);
      expect(detalle.promedio, closeTo(125.25, 1e-9));
      expect(detalle.conDescuento, 1);
      expect(detalle.conCortesia, 1);
    });

    test('la propina es un % del subtotal; sin subtotal, cero', () {
      expect(detalle.propinaPct, closeTo(21 / 480 * 100, 1e-9));
      expect(DetalleCaja.vacio.propinaPct, 0);
      expect(DetalleCaja.vacio.promedio, 0);
    });

    test('quién vendió: de más a menos, con pedidos, total y propinas', () {
      final u = detalle.usuarios;
      expect(u.map((e) => e.nombre), ['Ana Cosme', 'Alex Ojom']);
      expect(u[0].pedidos, 3);
      expect(u[0].total, 421);
      expect(u[0].propinas, 11);
      expect(u[1].pedidos, 1);
      expect(u[1].total, 80);
      expect(u[1].propinas, 10);
    });

    test('los filtros: todos, un método por cada uno usado, con descuento y con cortesía', () {
      expect(detalle.filtros.map((f) => (f.id, f.nombre, f.cuantos)), [
        ('todos', 'Todos', 4),
        ('card', 'Tarjeta', 1),
        ('cash', 'Efectivo', 2),
        ('custom_vales', 'Vales', 1),
        ('descuento', 'Con descuento', 1),
        ('cortesia', 'Con cortesía', 1),
      ]);
      // Sin descuentos ni cortesías, esos dos filtros no salen.
      final simple = DetalleCaja.desde([pedido(), pedido(metodo: 'card')]);
      expect(simple.filtros.map((f) => f.id), ['todos', 'cash', 'card']);
    });

    test('split y mixed van juntos en un solo filtro "Mixto"', () {
      final d = DetalleCaja.desde([pedido(metodo: 'split'), pedido(metodo: 'mixed'), pedido()]);
      expect(d.filtros.map((f) => (f.id, f.nombre, f.cuantos)), [('todos', 'Todos', 3), ('mixto', 'Mixto', 2), ('cash', 'Efectivo', 1)]);
      expect(d.filtrar('mixto'), hasLength(2));
    });

    test('filtrar por método, por descuento, por cortesía, y por usuario encima de cualquiera', () {
      expect(detalle.filtrar('todos'), hasLength(4));
      expect(detalle.filtrar('cash').map((p) => p.total), [250, 50]);
      expect(detalle.filtrar('descuento').single.descuento, 25);
      expect(detalle.filtrar('cortesia').single.cortesia, 40);
      expect(detalle.filtrar('todos', usuario: 'Alex Ojom').single.total, 80);
      expect(detalle.filtrar('cash', usuario: 'Alex Ojom'), isEmpty);
      expect(detalle.filtrar('inexistente'), isEmpty);
    });

    test('los totales de una lista filtrada son los de lo que se ve', () {
      final t = TotalesPedidos.de(detalle.filtrar('cash'));
      expect(t.pedidos, 2);
      expect(t.total, 300);
      expect(t.descuentos, 25);
    });
  });

  group('los gastos de la caja', () {
    final items = <Map<String, dynamic>>[
      {'source': 'cashRegister', 'register_id': 'cr-A', 'date': '2026-11-20T11:20:00', 'description': 'Compra de hielo', 'category_name': 'Insumos', 'amount': 45, 'registered_by': 'Juan'},
      {'source': 'cashRegister', 'register_id': 'cr-A', 'date': '2026-11-20T13:40:00', 'description': '', 'category_name': 'Gas', 'amount': 180.5},
      {'source': 'cashRegister', 'register_id': 'cr-OTRA', 'date': '2026-11-20T12:00:00', 'description': 'ajeno', 'amount': 9},
      {'source': 'manual', 'register_id': 'cr-A', 'date': '2026-11-20T12:00:00', 'description': 'no es de caja', 'amount': 9},
    ];

    test('solo los de esa caja, del más reciente al más antiguo', () {
      final g = GastoCaja.deLaCaja(items, 'cr-A');
      expect(g.map((e) => e.monto), [180.5, 45]);
    });

    test('el concepto es la descripción y, sin ella, la categoría; sin usuario, nulo', () {
      final g = GastoCaja.deLaCaja(items, 'cr-A');
      expect(g[0].concepto, 'Gas');
      expect(g[0].usuario, isNull);
      expect(g[1].concepto, 'Compra de hielo');
      expect(g[1].categoria, 'Insumos');
      expect(g[1].usuario, 'Juan');
      expect(g[1].fecha, DateTime(2026, 11, 20, 11, 20));
    });

    test('sin gastos, lista vacía', () {
      expect(GastoCaja.deLaCaja(items, 'cr-sin-gastos'), isEmpty);
    });
  });

  group('datos raros no tiran el detalle', () {
    test('un pedido con números como texto o campos de otro tipo se lee sin lanzar', () {
      expect(
        () => PedidoCaja.desde({
          'payment_amount': '100.5',
          'subtotal': '90',
          'discount_amount': 'diez',
          'tip_amount': '5',
          'items': 'no-es-una-lista',
          'payment_method': 5,
          'order_prefix': 7,
          'paid_by_user_name': 3,
        }),
        returnsNormally,
      );
      final p = PedidoCaja.desde({'payment_amount': '100.5', 'subtotal': '90', 'discount_amount': 'diez', 'tip_amount': '5', 'items': 'x', 'payment_method': 5});
      expect(p.total, 100.5);
      expect(p.subtotal, 90);
      expect(p.descuento, 0, reason: 'lo que no se entiende no se inventa');
      expect(p.propina, 5);
      expect(p.cortesia, 0);
      expect(p.metodo, '5', reason: 'un método que no es texto se muestra tal cual, no como efectivo');
      expect(p.metodoNombre, '5');
    });

    test('los renglones de cortesía con cantidad o precio mal escritos no lanzan', () {
      final p = PedidoCaja.desde({
        'items': [
          {'is_courtesy': true, 'qty': 'dos', 'unit_price': '10'},
          {'is_courtesy': true, 'qty': 2, 'unit_price': 'x'},
          {'is_courtesy': true, 'qty': 3, 'unit_price': 5},
        ],
      });
      // dos (no se entiende → 1) × 10 + 2 × 0 + 3 × 5.
      expect(p.cortesia, 25);
    });

    test('un solo pedido raro no deja a los demás fuera del detalle', () {
      final d = DetalleCaja.desde([
        pedido(pago: 100),
        {'payment_amount': 'raro', 'items': 5, 'payment_method': 7},
        pedido(pago: 50),
      ]);
      expect(d.pedidos, hasLength(3));
      expect(d.totales.total, 150);
    });

    test('un gasto con campos de otro tipo se lee sin lanzar', () {
      final g = GastoCaja.deLaCaja([
        {'source': 'cashRegister', 'register_id': 'cr-A', 'date': 20261120, 'description': 5, 'category_name': 7, 'registered_by': 9, 'amount': 'x'},
        {'source': 'cashRegister', 'register_id': 'cr-A', 'date': '2026-11-20T10:00:00', 'description': 'Hielo', 'amount': '45'},
      ], 'cr-A');
      expect(g, hasLength(2));
      expect(g.first.concepto, 'Hielo', reason: 'el de fecha válida va primero');
      expect(g.first.monto, 45);
      expect(g.last.concepto, 'Sin categoría');
      expect(g.last.usuario, isNull);
      expect(g.last.monto, 0);
    });
  });
}
