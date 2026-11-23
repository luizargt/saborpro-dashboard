import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/atencion_inicio.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';

/// "Requiere tu atención": cuándo el Inicio avisa y cuándo calla. Un aviso de
/// más enseña a ignorar la lista; uno de menos esconde un faltante.
void main() {
  final ahora = DateTime(2026, 11, 20, 14, 30);

  // Un cierre con las diferencias selladas, que es lo normal (el POS las escribe
  // al cerrar).
  CashRegisterSummary cierre({
    String id = 'c1',
    String quien = 'Ana Cosme',
    double? efectivo = -385,
    double tarjeta = 0,
    String? loc = 'L1',
    String? locName,
  }) =>
      CashRegisterSummary(
        id: id,
        userId: 'u-$id',
        userName: quien,
        status: 'closed',
        openedAt: DateTime(2026, 11, 20, 8),
        closedAt: DateTime(2026, 11, 20, 13),
        locationId: loc,
        locationName: locName,
        differenceCash: efectivo,
        differenceCard: efectivo == null ? null : tarjeta,
      );

  CashRegisterSummary abierta({
    String id = 'a1',
    String quien = 'Ana Lena Katt',
    required DateTime desde,
    String? loc = 'L1',
    String? locName,
  }) =>
      CashRegisterSummary(
        id: id,
        userId: 'u-$id',
        userName: quien,
        status: 'open',
        openedAt: desde,
        locationId: loc,
        locationName: locName,
      );

  List<ItemAtencion> armar({
    List<CashRegisterSummary> cerradas = const [],
    List<CashRegisterSummary> abiertas = const [],
    int cortesias = 0,
    double monto = 0,
    bool sucursal = false,
    Map<String, String> signos = const {},
    String signoVista = 'Q',
  }) =>
      AtencionInicio.armar(
        cerradas: cerradas,
        abiertas: abiertas,
        cortesiasSinMotivo: cortesias,
        montoSinMotivo: monto,
        signoDeCaja: (loc) => signos[loc] ?? 'Q',
        signoVista: signoVista,
        ahora: ahora,
        mostrarSucursal: sucursal,
      );

  group('faltantes', () {
    test('un cierre con faltante avisa: quién, cuánto, en rojo', () {
      final items = armar(cerradas: [cierre()]);
      expect(items, hasLength(1));
      final i = items.single;
      expect(i.texto, 'Faltante de Q385 en el cierre de Ana Cosme');
      expect(i.gravedad, GravedadAtencion.alta);
      expect(i.seccion, 'Cierres de caja');
      expect(i.destino, DestinoAtencion.cierresDeCaja);
      // Lo importante va en negritas: el monto, no el nombre.
      expect(i.partes.where((p) => p.negrita).map((p) => p.texto), ['Q385']);
    });

    test('con centavos se ven; redondo va sin ellos', () {
      expect(armar(cerradas: [cierre(efectivo: -385.5)]).single.texto, contains('Q385.50'));
      expect(armar(cerradas: [cierre(efectivo: -1250)]).single.texto, contains('Q1,250 '));
    });

    test('cuadrado, sobrante o menos de un centavo: no avisa', () {
      expect(armar(cerradas: [cierre(efectivo: 0)]), isEmpty);
      expect(armar(cerradas: [cierre(efectivo: 40)]), isEmpty);
      expect(armar(cerradas: [cierre(efectivo: -0.004)]), isEmpty);
      // El umbral es el del aviso push de "Descuadre": desde un centavo.
      expect(armar(cerradas: [cierre(efectivo: -0.01)]), hasLength(1));
    });

    test('la diferencia es la suma de los métodos: efectivo corto y tarjeta de más compensan', () {
      expect(armar(cerradas: [cierre(efectivo: -100, tarjeta: 100)]), isEmpty);
      final i = armar(cerradas: [cierre(efectivo: -100, tarjeta: 40)]).single;
      expect(i.texto, contains('Q60'));
    });

    test('sin diferencias selladas no se inventa un faltante', () {
      // Un cierre viejo o forzado: la diferencia se recalcularía de acumulados
      // que otro aparato pudo sobrescribir.
      expect(armar(cerradas: [cierre(efectivo: null)]), isEmpty);
    });

    test('cada caja con el signo de su sucursal', () {
      final items = armar(
        cerradas: [
          cierre(id: 'a', loc: 'GT', efectivo: -50),
          cierre(id: 'b', loc: 'SV', efectivo: -20, quien: 'Luis'),
        ],
        signos: {'GT': 'Q', 'SV': 'USD'},
      );
      expect(items.map((i) => i.texto), [
        'Faltante de Q50 en el cierre de Ana Cosme',
        // El código de letras lleva su espacio.
        'Faltante de USD 20 en el cierre de Luis',
      ]);
    });

    test('de mayor a menor y, pasando de tres, un renglón con cuántos más', () {
      final cierres = [
        for (var i = 1; i <= 5; i++) cierre(id: 'c$i', quien: 'Cajero $i', efectivo: -10.0 * i),
      ];
      final items = armar(cerradas: cierres);
      expect(items, hasLength(4));
      expect(items[0].texto, contains('Q50'));
      expect(items[1].texto, contains('Q40'));
      expect(items[2].texto, contains('Q30'));
      expect(items[3].texto, '2 cierres más con faltante');
      expect(items[3].partes.first.negrita, isTrue);
      // La insignia cuenta incidencias: tres filas sueltas y las 2 que resume.
      expect(items.fold<int>(0, (s, i) => s + i.cuantos), 5);
      expect(items[0].cuantos, 1);
      expect(items[3].cuantos, 2);

      // Con uno solo de sobra, en singular.
      final cuatro = armar(cerradas: cierres.take(4).toList());
      expect(cuatro.last.texto, '1 cierre más con faltante');
    });
  });

  group('cajas que nadie cerró', () {
    test('más de un día abierta avisa con los días, en ámbar', () {
      final items = armar(abiertas: [abierta(desde: DateTime(2026, 11, 12, 9))]);
      expect(items, hasLength(1));
      expect(items.single.texto, 'La caja de Ana Lena Katt lleva 8 días abierta');
      expect(items.single.gravedad, GravedadAtencion.media);
      expect(items.single.destino, DestinoAtencion.cierresDeCaja);
      expect(items.single.partes.where((p) => p.negrita).map((p) => p.texto),
          ['Ana Lena Katt', '8 días abierta']);
    });

    test('un día se dice en singular', () {
      final items = armar(abiertas: [abierta(desde: ahora.subtract(const Duration(hours: 30)))]);
      expect(items.single.texto, contains('lleva 1 día abierta'));
    });

    test('un turno normal (menos de 24 horas) no avisa, aunque sea de anoche', () {
      expect(armar(abiertas: [abierta(desde: DateTime(2026, 11, 19, 22))]), isEmpty);
      expect(armar(abiertas: [abierta(desde: ahora.subtract(const Duration(hours: 23, minutes: 59)))]), isEmpty);
      expect(armar(abiertas: [abierta(desde: ahora.subtract(const Duration(hours: 24)))]), hasLength(1));
    });

    test('las más viejas primero y un renglón con cuántas más', () {
      final items = armar(abiertas: [
        for (var i = 1; i <= 5; i++) abierta(id: 'a$i', quien: 'Cajero $i', desde: ahora.subtract(Duration(days: i))),
      ]);
      expect(items, hasLength(4));
      expect(items[0].texto, contains('Cajero 5'));
      expect(items[0].texto, contains('5 días'));
      expect(items[3].texto, '2 cajas más llevan días abiertas');
      expect(items[3].cuantos, 2);
    });

    test('una caja con la fecha como texto ISO también se reconoce como olvidada', () {
      // Una caja guardada sin conexión puede traer la fecha como texto: sin
      // leerla, "se abría" ahora mismo y no avisaba.
      final caja = CashRegisterSummary.fromMap({
        'id': 'x',
        'userName': 'Ana Lena Katt',
        'status': 'open',
        'openedAt': '2026-11-12T09:00:00.000',
      });
      expect(caja.openedAt, DateTime(2026, 11, 12, 9));
      final items = armar(abiertas: [caja]);
      expect(items.single.texto, 'La caja de Ana Lena Katt lleva 8 días abierta');

      // Con zona (Z) también: se pasa a la hora local.
      final utc = CashRegisterSummary.fromMap({
        'id': 'y',
        'status': 'open',
        'openedAt': '2026-11-12T15:00:00.000Z',
      });
      expect(utc.openedAt, DateTime.utc(2026, 11, 12, 15).toLocal());
    });

    test('un Timestamp sigue leyéndose igual, y lo ilegible no rompe', () {
      final t = CashRegisterSummary.fromMap({
        'id': 'z',
        'status': 'closed',
        'openedAt': Timestamp.fromDate(DateTime(2026, 11, 1, 8)),
        'closedAt': '2026-11-01T17:30:00.000',
      });
      expect(t.openedAt, DateTime(2026, 11, 1, 8));
      expect(t.closedAt, DateTime(2026, 11, 1, 17, 30));
      // Texto que no es fecha: cae a "ahora" como siempre, sin lanzar.
      final raro = CashRegisterSummary.fromMap({'id': 'w', 'status': 'open', 'openedAt': 'ayer'});
      expect(raro.openedAt.difference(DateTime.now()).inMinutes.abs(), lessThan(2));
    });
  });

  group('cortesías sin motivo', () {
    test('cuántas y cuánto, con el signo de la vista', () {
      final i = armar(cortesias: 2, monto: 202, signoVista: r'$').single;
      expect(i.texto, r'2 cortesías sin motivo por $202');
      expect(i.partes.first.negrita, isTrue);
      expect(i.seccion, 'Cortesías');
      expect(i.destino, DestinoAtencion.cortesias);
      expect(i.gravedad, GravedadAtencion.media);
    });

    test('una sola va en singular; ninguna no avisa', () {
      expect(armar(cortesias: 1, monto: 35.5).single.texto, '1 cortesía sin motivo por Q35.50');
      expect(armar(cortesias: 0), isEmpty);
    });
  });

  group('en conjunto', () {
    test('primero lo que faltó, luego lo olvidado, al final lo sin explicar', () {
      final items = armar(
        cerradas: [cierre()],
        abiertas: [abierta(desde: DateTime(2026, 11, 12, 9))],
        cortesias: 2,
        monto: 202,
      );
      expect(items.map((i) => i.destino), [
        DestinoAtencion.cierresDeCaja,
        DestinoAtencion.cierresDeCaja,
        DestinoAtencion.cortesias,
      ]);
      expect(items.map((i) => i.gravedad), [
        GravedadAtencion.alta,
        GravedadAtencion.media,
        GravedadAtencion.media,
      ]);
    });

    test('con varias sucursales, cada aviso dice cuál', () {
      final items = armar(
        cerradas: [cierre(locName: 'Zona 10')],
        abiertas: [abierta(desde: DateTime(2026, 11, 12, 9), locName: 'Santa Rosalía')],
        sucursal: true,
      );
      expect(items[0].seccion, 'Cierres de caja · Zona 10');
      expect(items[1].seccion, 'Cierres de caja · Santa Rosalía');
      // Con una sola sucursal no se repite en cada renglón.
      expect(armar(cerradas: [cierre(locName: 'Zona 10')]).single.seccion, 'Cierres de caja');
    });

    test('sin nada pendiente, la lista queda vacía (y la tarjeta no se dibuja)', () {
      expect(armar(), isEmpty);
    });
  });

  group('monto', () {
    test('redondo sin centavos, con miles; con centavos, siempre dos', () {
      expect(AtencionInicio.monto('Q', 385), 'Q385');
      expect(AtencionInicio.monto('Q', 1234567), 'Q1,234,567');
      expect(AtencionInicio.monto('Q', 0.5), 'Q0.50');
      expect(AtencionInicio.monto('USD', 20), 'USD 20');
      expect(AtencionInicio.monto('C\$', 99.9), 'C\$99.90');
    });
  });

  group('ResumenPedidosInicio', () {
    Map<String, dynamic> item({String? motivo, num precio = 10, bool cortesia = true}) => {
          'name': 'Platillo',
          'qty': 1,
          'unit_price': precio,
          if (cortesia) 'is_courtesy': true,
          if (cortesia) 'courtesy_type': 'CORTESIA',
          if (motivo != null) 'courtesy_reason': motivo,
        };

    Map<String, dynamic> pedido(String id, List<Object?> items, {num descuento = 0}) => {
          '_docId': id,
          'items': items,
          'discount_amount': descuento,
        };

    test('cuenta los cobros con descuento, no los montos', () {
      final r = ResumenPedidosInicio.desde([
        pedido('a', [], descuento: 15),
        pedido('b', [], descuento: 0),
        pedido('c', [], descuento: 2.5),
        {'_docId': 'd', 'items': <Object?>[]}, // sin el campo
      ]);
      expect(r.descuentos, 2);
    });

    test('cortesías sin motivo: pedidos y lo que suman, con los motivos aparte', () {
      final r = ResumenPedidosInicio.desde([
        pedido('a', [item(motivo: 'Cumpleaños', precio: 50)]),
        pedido('b', [item(precio: 100)]),
        // Dos renglones sin motivo en el MISMO pedido son un pedido.
        pedido('c', [item(precio: 60), item(precio: 42)]),
        // Mezclado: cuenta por el renglón que no tiene motivo.
        pedido('d', [item(motivo: 'Prueba', precio: 5), item(precio: 7)]),
        // Una venta común no es cortesía.
        pedido('e', [item(cortesia: false, precio: 999)]),
      ]);
      expect(r.cortesiasSinMotivo, 3);
      expect(r.montoSinMotivo, 100 + 60 + 42 + 7);
    });

    test('sin pedidos no hay nada que contar', () {
      final r = ResumenPedidosInicio.desde(const []);
      expect(r.descuentos, 0);
      expect(r.cortesiasSinMotivo, 0);
      expect(r.montoSinMotivo, 0);
      expect(ResumenPedidosInicio.vacio.cortesiasSinMotivo, 0);
    });
  });
}
