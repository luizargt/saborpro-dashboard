import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/propinas_data.dart';

/// Las propinas desglosadas (propinas.html). Los números de cada caso se pueden
/// comprobar a mano: son pocos pedidos y de cuentas redondas.
void main() {
  /// [pago]: lo cobrado, que INCLUYE la propina y el envío (como `payment_amount`
  /// en Firestore); la venta es pago − propina − envío.
  Map<String, dynamic> pedido({
    required double pago,
    double tip = 0,
    double envio = 0,
    String? usuario,
    String? nombre,
    String tipo = 'dine_in',
    String? metodo = 'card',
    String? mesa,
    DateTime? hora,
  }) =>
      {
        'payment_amount': pago,
        'tip_amount': tip,
        'delivery_fee': envio,
        if (usuario != null) 'created_by_user_id': usuario,
        if (nombre != null) 'created_by_user_name': nombre,
        'type': tipo,
        if (metodo != null) 'payment_method': metodo,
        if (mesa != null) 'table_id': mesa,
        if (hora != null) 'paid_at': Timestamp.fromDate(hora),
      };

  final dia = DateTime(2026, 11, 20);
  DateTime a(int h, [int m = 0]) => DateTime(dia.year, dia.month, dia.day, h, m);

  group('totales', () {
    test('ventas sin propina, propina, cuántos no dejaron y los promedios', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10), // venta 100
        pedido(pago: 220, tip: 20), // venta 200
        pedido(pago: 50), // venta 50, sin propina
      ]);
      expect(r.pedidos, 3);
      expect(r.ventas, 350);
      expect(r.propinas, 30);
      expect(r.sinPropina, 1);
      expect(r.tasa, closeTo(8.5714, 0.001));
      expect(r.porPedido, 10);
      expect(r.pctSinPropina, closeTo(33.33, 0.01));
      expect(r.hayPedidos, isTrue);
    });

    test('la venta es la "Venta bruta" del Inicio: sin propina ni cobro de envío', () {
      final o = pedido(pago: 160, tip: 10, envio: 30);
      expect(PropinasReporte.ventaDe(o), 120);
      // Y la suma de todos es lo que el Inicio llama Venta bruta (Σ cobrado − Σ propinas − Σ envíos).
      final lista = [pedido(pago: 160, tip: 10, envio: 30), pedido(pago: 55, tip: 5)];
      final r = PropinasReporte.desde(lista);
      expect(r.ventas, (160 + 55) - (10 + 5) - 30);
    });

    test('sin payment_amount cae a total_amount, igual que el Inicio', () {
      final o = {'total_amount': 100.0, 'tip_amount': 10.0};
      expect(PropinasReporte.ventaDe(o), 90);
    });

    test('datos a medias no rompen: campos nulos, texto donde va un número', () {
      final r = PropinasReporte.desde([
        {'payment_amount': null, 'tip_amount': null},
        {'payment_amount': '100', 'tip_amount': 'x', 'type': null},
        const <String, dynamic>{},
      ]);
      expect(r.pedidos, 3);
      expect(r.propinas, 0);
      expect(r.sinPropina, 3);
      expect(r.ventas, 0);
    });

    test('sin pedidos todo es cero y no divide entre cero', () {
      final r = PropinasReporte.desde(const []);
      expect(r.pedidos, 0);
      expect(r.tasa, 0);
      expect(r.porPedido, 0);
      expect(r.pctSinPropina, 0);
      expect(r.horas, isEmpty);
      expect(r.horaPico, isNull);
      expect(r.meseroConPocaPropina, isNull);
      expect(r.hayPedidos, isFalse);
      expect(PropinasReporte.vacio.pedidos, 0);
    });
  });

  group('contra el período anterior', () {
    test('sin pedidos de entonces no hay con qué comparar', () {
      final r = PropinasReporte.desde([pedido(pago: 110, tip: 10)]);
      expect(r.propinasAnterior, isNull);
      expect(r.cambioPct, isNull);
    });

    test('sube o baja en porcentaje', () {
      final sube = PropinasReporte.desde(
        [pedido(pago: 115, tip: 15)],
        anteriores: [pedido(pago: 105, tip: 5), pedido(pago: 105, tip: 5)],
      );
      expect(sube.propinasAnterior, 10);
      expect(sube.cambioPct, 50);

      final baja = PropinasReporte.desde(
        [pedido(pago: 105, tip: 5)],
        anteriores: [pedido(pago: 120, tip: 20)],
      );
      expect(baja.cambioPct, -75);
    });

    test('si entonces nadie dejó propina el porcentaje no existe (dividir entre cero)', () {
      final r = PropinasReporte.desde([pedido(pago: 110, tip: 10)], anteriores: [pedido(pago: 100)]);
      expect(r.propinasAnterior, 0);
      expect(r.cambioPct, isNull);
    });
  });

  group('quién recibe propina', () {
    test('agrupa por quien creó el pedido, de más a menos propina, con su nombre', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10, usuario: 'u1', nombre: 'Ana Cosme'),
        pedido(pago: 105, tip: 5, usuario: 'u2', nombre: 'Alex Ojom'),
        pedido(pago: 130, tip: 30, usuario: 'u1', nombre: 'Ana Cosme'),
        pedido(pago: 100, usuario: 'u2', nombre: 'Alex Ojom'),
      ]);
      expect(r.meseros.map((m) => m.nombre), ['Ana Cosme', 'Alex Ojom']);
      final ana = r.meseros.first;
      expect(ana.pedidos, 2);
      expect(ana.ventas, 100 + 100);
      expect(ana.propinas, 40);
      expect(ana.sinPropina, 0);
      expect(ana.tasa, 20);
      final alex = r.meseros.last;
      expect(alex.sinPropina, 1);
      expect(alex.propinas, 5);
    });

    test('el nombre que falta en el pedido se busca en el mapa de usuarios; si tampoco, "Sin registrar"', () {
      final r = PropinasReporte.desde(
        [
          pedido(pago: 110, tip: 10, usuario: 'u1'),
          pedido(pago: 105, tip: 5, usuario: 'u9'),
          pedido(pago: 100),
        ],
        nombresUsuario: const {'u1': 'Marta Ajiquichi'},
      );
      expect(r.meseros.map((m) => m.nombre).toSet(), {'Marta Ajiquichi', 'Sin registrar'});
      // u9 y el pedido sin dueño no se mezclan con nadie conocido.
      expect(r.meseros, hasLength(3));
    });

    test('sin id pero con nombre se agrupa por el nombre', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10, nombre: 'Luis'),
        pedido(pago: 110, tip: 10, nombre: 'Luis'),
      ]);
      expect(r.meseros.single.nombre, 'Luis');
      expect(r.meseros.single.pedidos, 2);
    });

    test('los ids sin nombre en el pedido se piden a users', () {
      final ids = PropinasReporte.idsSinNombre([
        pedido(pago: 1, usuario: 'u1'),
        pedido(pago: 1, usuario: 'u2', nombre: 'Ana'),
        pedido(pago: 1, usuario: 'u1'),
        pedido(pago: 1),
      ]);
      expect(ids, {'u1'});
    });

    test('la alerta: quien recibe claramente menos que el promedio, con muestra suficiente', () {
      List<Map<String, dynamic>> de(String u, int n, double tip) =>
          [for (var i = 0; i < n; i++) pedido(pago: 100 + tip, tip: tip, usuario: u, nombre: u)];

      // Propinas 100 + 80 + 10 = 190 sobre ventas de 3,000: promedio 6.33%;
      // "Poco" deja 1%.
      final r = PropinasReporte.desde([...de('Bien', 10, 10), ...de('Medio', 10, 8), ...de('Poco', 10, 1)]);
      expect(r.tasa, closeTo(6.3333, 0.001));
      expect(r.meseroConPocaPropina?.nombre, 'Poco');

      // Con 4 pedidos no se le señala: es mala suerte, no tendencia.
      final pocos = PropinasReporte.desde([...de('Bien', 10, 10), ...de('Poco', 4, 0)]);
      expect(pocos.meseroConPocaPropina, isNull);

      // Todos parecidos: nadie.
      final parejos = PropinasReporte.desde([...de('A', 10, 8), ...de('B', 10, 7.5)]);
      expect(parejos.meseroConPocaPropina, isNull);

      // Nadie dejó propina: no hay promedio contra el cual compararse.
      final nadie = PropinasReporte.desde([...de('A', 10, 0), ...de('B', 10, 0)]);
      expect(nadie.meseroConPocaPropina, isNull);
    });

    test('de varios con poca propina, el de la tasa más baja', () {
      List<Map<String, dynamic>> de(String u, int n, double tip) =>
          [for (var i = 0; i < n; i++) pedido(pago: 100 + tip, tip: tip, usuario: u, nombre: u)];
      final r = PropinasReporte.desde([...de('Top', 30, 15), ...de('Bajo', 6, 2), ...de('Mínimo', 6, 0)]);
      expect(r.meseroConPocaPropina?.nombre, 'Mínimo');
    });
  });

  group('a qué hora', () {
    test('horas seguidas de la primera a la última, con cero donde no hubo', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10, hora: a(9, 15)),
        pedido(pago: 105, tip: 5, hora: a(9, 50)),
        pedido(pago: 130, tip: 30, hora: a(12)),
        pedido(pago: 100, hora: a(13)),
      ]);
      expect(r.horas.map((h) => h.hora), [9, 10, 11, 12, 13]);
      expect(r.horas.map((h) => h.propinas), [15, 0, 0, 30, 0]);
      expect(r.horaPico?.hora, 12);
    });

    test('en empate gana la más temprana; sin ninguna propina no hay hora pico', () {
      final empate = PropinasReporte.desde([
        pedido(pago: 110, tip: 10, hora: a(10)),
        pedido(pago: 110, tip: 10, hora: a(15)),
      ]);
      expect(empate.horaPico?.hora, 10);
      final nada = PropinasReporte.desde([pedido(pago: 100, hora: a(10)), pedido(pago: 100, hora: a(11))]);
      expect(nada.horaPico, isNull);
      expect(nada.horas, hasLength(2));
    });

    test('un pedido sin fecha cuenta en todo menos en la gráfica de horas; la fecha puede ser texto', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10),
        {...pedido(pago: 105, tip: 5), 'paid_at': a(18).toIso8601String()},
      ]);
      expect(r.pedidos, 2);
      expect(r.propinas, 15);
      expect(r.horas.map((h) => h.hora), [18]);
    });
  });

  group('por tipo de servicio', () {
    test('con nombres de cliente, en su orden, juntando llevar y recoger', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10, tipo: 'delivery'),
        pedido(pago: 110, tip: 10, tipo: 'takeout'),
        pedido(pago: 110, tip: 10, tipo: 'pickup'),
        pedido(pago: 110, tip: 10, tipo: 'dine_in'),
        pedido(pago: 110, tip: 10, tipo: 'room_service'),
        pedido(pago: 110, tip: 10, tipo: 'algo_nuevo'),
      ]);
      expect(r.porTipo.map((g) => g.nombre), ['Mesa', 'Para llevar', 'Domicilio', 'Habitación', 'Algo_nuevo']);
      expect(r.porTipo[1].pedidos, 2);
    });
  });

  group('según el tamaño de la cuenta', () {
    test('los límites caen donde dice el diseño: 100 y 300 pertenecen a la del medio', () {
      Map<String, dynamic> conVenta(double v) => pedido(pago: v);
      final r = PropinasReporte.desde([
        conVenta(99.99),
        conVenta(100),
        conVenta(300),
        conVenta(300.01),
      ]);
      expect(r.porTamano.map((g) => (g.nombre, g.pedidos)), [
        ('Menos de Q100', 1),
        ('Q100 a Q300', 2),
        ('Más de Q300', 1),
      ]);
    });

    test('lleva el signo de la moneda de la vista', () {
      final r = PropinasReporte.desde([pedido(pago: 50)], signo: 'USD ');
      expect(r.porTamano.single.nombre, 'Menos de USD 100');
    });

    test('solo las que existen', () {
      expect(PropinasReporte.desde([pedido(pago: 500)]).porTamano.single.nombre, 'Más de Q300');
    });
  });

  group('por zona', () {
    test('solo los pedidos en mesa, con la zona de cada mesa', () {
      final r = PropinasReporte.desde(
        [
          pedido(pago: 110, tip: 10, mesa: 'm1'),
          pedido(pago: 130, tip: 30, mesa: 'm2'),
          pedido(pago: 105, tip: 5, mesa: 'm1'),
          pedido(pago: 100, tip: 5, mesa: 'm9'), // mesa que ya no existe
          pedido(pago: 100, tip: 99, tipo: 'delivery'), // no es mesa: no cuenta aquí
        ],
        zonaDeMesa: const {'m1': 'Terraza', 'm2': 'Salón principal'},
      );
      expect(r.porZona!.map((g) => g.nombre), ['Salón principal', 'Terraza', 'Sin zona']);
      expect(r.porZona!.firstWhere((g) => g.nombre == 'Terraza').pedidos, 2);
      expect(r.porZona!.fold<int>(0, (s, g) => s + g.pedidos), 4);
    });

    test('si no se pudo leer la zona de las mesas, no se inventa: nulo', () {
      expect(PropinasReporte.desde([pedido(pago: 110, tip: 10, mesa: 'm1')]).porZona, isNull);
      expect(PropinasReporte.desde([pedido(pago: 110, tip: 10, mesa: 'm1')], zonaDeMesa: const {}).porZona,
          isNotNull);
    });
  });

  group('tarjeta y efectivo', () {
    test('tarjeta, efectivo y el resto aparte', () {
      final r = PropinasReporte.desde([
        pedido(pago: 110, tip: 10, metodo: 'card'),
        pedido(pago: 105, tip: 5, metodo: 'cash'),
        pedido(pago: 120, tip: 20, metodo: 'split'),
        pedido(pago: 110, tip: 10, metodo: 'transfer'),
        pedido(pago: 100, tip: 0, metodo: null),
      ]);
      expect(r.porMetodo.map((g) => g.nombre), ['Tarjeta', 'Efectivo', 'Otros']);
      final otros = r.porMetodo.last;
      expect(otros.pedidos, 3);
      expect(otros.propinas, 30);
      // Todo suma lo mismo que el total.
      expect(r.porMetodo.fold<double>(0, (s, g) => s + g.propinas), r.propinas);
    });
  });

  group('lo que suman los desgloses', () {
    test('cada desglose reparte los mismos pedidos y las mismas propinas', () {
      final pedidos = [
        for (var i = 0; i < 40; i++)
          pedido(
            pago: 60.0 + i * 11,
            tip: i % 4 == 0 ? 0 : (i % 7).toDouble() + 1,
            usuario: 'u${i % 3}',
            nombre: 'Mesero ${i % 3}',
            tipo: ['dine_in', 'takeout', 'delivery'][i % 3],
            metodo: ['card', 'cash', 'split'][i % 3],
            mesa: i % 2 == 0 ? 'm1' : 'm2',
            hora: a(8 + i % 12),
          ),
      ];
      final r = PropinasReporte.desde(pedidos, zonaDeMesa: const {'m1': 'Terraza', 'm2': 'Salón'});
      double suma(List<GrupoPropina> l) => l.fold(0.0, (s, g) => s + g.propinas);
      int cuenta(List<GrupoPropina> l) => l.fold(0, (s, g) => s + g.pedidos);
      for (final l in [r.meseros, r.porTipo, r.porTamano, r.porMetodo]) {
        expect(suma(l), closeTo(r.propinas, 1e-9));
        expect(cuenta(l), r.pedidos);
      }
      expect(r.horas.fold<double>(0, (s, h) => s + h.propinas), closeTo(r.propinas, 1e-9));
      expect(r.meseros.fold<int>(0, (s, g) => s + g.sinPropina), r.sinPropina);
      // La zona solo ve los pedidos en mesa.
      expect(cuenta(r.porZona!), pedidos.where((o) => o['type'] == 'dine_in').length);
    });
  });
}
