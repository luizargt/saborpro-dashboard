import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/atencion_inicio.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/cierre_admin.dart';
import 'package:saborpro_reports/data/models/cierres_caja.dart';

/// Cerrar una caja como administrador: se guarda lo que debía haber y nada
/// contado, y el corte queda descuadrado sin inventar un faltante.
void main() {
  final apertura = DateTime(2026, 9, 23, 12, 56);
  final cierre = DateTime(2026, 11, 25, 21);

  Map<String, dynamic> cajaCruda([Map<String, dynamic> extra = const {}]) => {
        'id': 'caja1',
        'tenantId': 't1',
        'userId': 'wendy',
        'userName': 'WENDY',
        'status': 'open',
        'locationId': 'sana',
        'openedAt': Timestamp.fromDate(apertura),
        'initialCash': 100.0,
        'initialCard': 0.0,
        'initialTransfer': 0.0,
        'expectedCash': 999.0,
        'actualCash': null,
        'movements': [
          {'id': 'm1', 'type': 'withdrawal', 'amount': 50.0},
        ],
        ...extra,
      };

  CashRegisterSummary caja([Map<String, dynamic> extra = const {}]) => CashRegisterSummary.fromMap(cajaCruda(extra));

  Map<String, dynamic> pedido({
    String metodo = 'cash',
    double monto = 100,
    DateTime? pagado,
    DateTime? creado,
    String? cobro = 'wendy',
    Map<String, dynamic> extra = const {},
  }) {
    final p = pagado ?? DateTime(2026, 10, 1, 10);
    return {
      'location_id': 'sana',
      'status': 'COMPLETED',
      'payment_status': 'PAID',
      'payment_method': metodo,
      'payment_amount': monto,
      'total_amount': monto,
      'paid_at': Timestamp.fromDate(p),
      'created_at': Timestamp.fromDate(creado ?? p.subtract(const Duration(minutes: 20))),
      if (cobro != null) 'paid_by_user_id': cobro,
      ...extra,
    };
  }

  group('lo vendido por método (la cuenta del cierre del POS)', () {
    test('cada método a su renglón; divididos y mixtos por sus partes', () {
      final v = VentasDeCaja.desde([
        pedido(monto: 100),
        pedido(metodo: 'card', monto: 40),
        pedido(metodo: 'transfer', monto: 30),
        pedido(metodo: 'pedidosya', monto: 20),
        pedido(metodo: 'ubereats', monto: 10),
        pedido(metodo: 'custom_vale', monto: 7),
        pedido(metodo: 'custom', monto: 3),
        pedido(metodo: 'split', monto: 60, extra: {
          'split_payments': [
            {'payment_method': 'cash', 'amount': 25},
            {'payment_method': 'card', 'amount': 35},
          ],
        }),
        pedido(metodo: 'mixed', monto: 50, extra: {
          'mixed_payments': [
            {'method': 'transfer', 'amount': 15},
            {'method': 'custom_vale', 'amount': 35},
          ],
        }),
      ]);
      expect(v.efectivo, 125);
      expect(v.tarjeta, 75);
      expect(v.transferencia, 45);
      expect(v.pedidosya, 20);
      expect(v.ubereats, 10);
      expect(v.propios, {'custom_vale': 42.0, 'custom': 3.0});
    });

    test('un método desconocido va a "otros", no al efectivo', () {
      final v = VentasDeCaja.desde([pedido(metodo: 'rappi', monto: 80)]);
      expect(v.efectivo, 0);
      expect(v.propios, {'otros': 80.0});
    });

    test('un compuesto sin desglose se queda en efectivo', () {
      final v = VentasDeCaja.desde([
        pedido(metodo: 'mixed', monto: 80),
        pedido(metodo: 'mixed', monto: 5, extra: {'mixed_payments': const []}),
        pedido(metodo: 'split', monto: 20),
      ]);
      expect(v.efectivo, 105);
    });

    test('vale lo pagado; sin ese dato, el total; sin método, efectivo', () {
      final v = VentasDeCaja.desde([
        {...pedido(), 'payment_amount': 115.0, 'total_amount': 100.0, 'payment_method': null},
        {...pedido(), 'payment_amount': null, 'total_amount': 30.0},
      ]);
      expect(v.efectivo, 145);
    });
  });

  group('qué pedidos cuentan', () {
    List<Map<String, dynamic>> delTurno(List<Map<String, dynamic>> p) =>
        CierreAdmin.pedidosDeLaCaja(p, caja(), hasta: cierre);

    test('solo dentro del turno', () {
      expect(delTurno([pedido(pagado: apertura.subtract(const Duration(minutes: 1)))]), isEmpty);
      expect(delTurno([pedido(pagado: cierre.add(const Duration(minutes: 1)))]), isEmpty);
      expect(delTurno([pedido(pagado: apertura), pedido(pagado: cierre)]), hasLength(2));
    });

    test('con el reloj atrasado vale la hora de creación, como en el POS', () {
      final atrasado = pedido(
        pagado: apertura.subtract(const Duration(days: 2)),
        creado: apertura.add(const Duration(hours: 1)),
      );
      expect(delTurno([atrasado]), hasLength(1));
    });

    test('acepta la hora como texto (cobros sin internet)', () {
      final p = {...pedido(), 'paid_at': '2026-10-01T10:00:00.000', 'created_at': '2026-10-01T09:00:00.000'};
      expect(delTurno([p]), hasLength(1));
    });

    test('ni anulados, ni sin cobrar, ni de otra sucursal, ni de otro cajero', () {
      expect(
        delTurno([
          pedido(extra: {'status': 'CANCELLED'}),
          pedido(extra: {'cancelled_at': Timestamp.fromDate(cierre)}),
          pedido(extra: {'payment_status': 'PENDING'}),
          pedido(extra: {'payment_status': null}),
          pedido(extra: {'location_id': 'otra'}),
          pedido(cobro: 'lety'),
          pedido(extra: {'paid_at': null}),
        ]),
        isEmpty,
      );
    });

    test('un cobro sin cobrador (app de reparto) no entra, aunque el pedido lo creara el cajero: como en el POS', () {
      final reparto = pedido(
        metodo: 'pedidosya',
        cobro: null,
        extra: {'waiter_name': 'WENDY', 'created_by_user_name': 'WENDY'},
      );
      expect(delTurno([reparto]), isEmpty);
    });

    test('un pedido con datos de otro tipo no impide cerrar', () {
      final raro = pedido(extra: {'status': 7, 'paid_by_user_name': 5, 'cash_register_id': 3});
      expect(delTurno([raro, pedido()]), hasLength(2));
    });

    test('el sello de caja manda sobre quién cobró', () {
      final hora = DateTime(2026, 10, 2, 9);
      Map<String, dynamic> sellado(String cajaId, String cobro) => pedido(pagado: hora, cobro: cobro, extra: {
            'cash_register_id': cajaId,
            'cash_register_paid_at': hora.toUtc().toIso8601String(),
          });
      expect(delTurno([sellado('caja1', 'lety')]), hasLength(1));
      expect(delTurno([sellado('otra-caja', 'wendy')]), isEmpty);
    });
  });

  group('lo que se escribe', () {
    final ventas = const VentasDeCaja(
      efectivo: 395,
      tarjeta: 40,
      transferencia: 175,
      propios: {'custom_vale': 30},
    );
    final datos = CierreAdmin.datos(
      caja: caja(),
      ventas: ventas,
      actualizada: cierre,
      adminId: 'a1',
      adminNombre: 'Soporte',
    );

    test('cerrada, con lo esperado (fondo incluido) y nada contado', () {
      expect(datos['status'], 'closed');
      expect(datos['updatedAt'], Timestamp.fromDate(cierre));
      // La pone el servidor: no sale del reloj de quien cierra.
      expect(datos.containsKey('closedAt'), isFalse);
      expect(datos['expectedCash'], 495);
      expect(datos['expectedCard'], 40);
      expect(datos['expectedTransfer'], 175);
      expect(datos['expectedCustomMethods'], {'custom_vale': 30.0});
      for (final m in ['Cash', 'Card', 'Transfer', 'Pedidosya', 'Ubereats']) {
        expect(datos.containsKey('actual$m'), isTrue);
        expect(datos['actual$m'], isNull);
        expect(datos['difference$m'], isNull);
      }
      expect(datos['actualCustomMethods'], isEmpty);
      expect(datos['differenceCustomMethods'], isEmpty);
    });

    test('con la marca (solo textos) y la nota que entiende el POS', () {
      expect(datos['closed_by_admin'], {'user_id': 'a1', 'user_name': 'Soporte', 'app': 'sabor_manager'});
      // El POS busca exactamente estas palabras.
      expect(datos['closingNotes'], contains('Cierre forzado'));
      expect(datos['closingNotes'], contains('Soporte'));
    });

    test('no toca los movimientos, el fondo ni de quién es la caja', () {
      for (final campo in ['movements', 'initialCash', 'userId', 'userName', 'openedAt', 'tenantId', 'locationId']) {
        expect(datos.containsKey(campo), isFalse, reason: campo);
      }
    });
  });

  group('la hora y la huella', () {
    test('updatedAt nunca queda antes que el que ya tenía la caja', () {
      final despues = cierre.add(const Duration(minutes: 5));
      // El reloj de quien cierra va atrasado respecto del último cobro.
      expect(
        CierreAdmin.horaDeActualizacion({'updatedAt': Timestamp.fromDate(despues)}, cierre),
        despues.add(const Duration(seconds: 1)),
      );
      // También si el POS lo guardó como texto.
      expect(
        CierreAdmin.horaDeActualizacion({'updatedAt': despues.toIso8601String()}, cierre),
        despues.add(const Duration(seconds: 1)),
      );
      expect(CierreAdmin.horaDeActualizacion({'updatedAt': Timestamp.fromDate(apertura)}, cierre), cierre);
      expect(CierreAdmin.horaDeActualizacion(const {}, cierre), cierre);
    });

    test('la huella cambia con un cobro y no con lo demás', () {
      final base = CierreAdmin.huellaDeCobros(cajaCruda());
      expect(CierreAdmin.huellaDeCobros(cajaCruda({'movements': const [], 'updatedAt': 'otra'})), base);
      for (final cambio in [
        {'expectedCash': 1099.0},
        {'expectedCard': 5.0},
        {'expectedTransfer': 5.0},
        {'expectedPedidosya': 5.0},
        {'expectedUbereats': 5.0},
        {
          'expectedCustomMethods': {'custom_vale': 5.0},
        },
      ]) {
        expect(CierreAdmin.huellaDeCobros(cajaCruda(cambio)), isNot(base), reason: '$cambio');
      }
    });

    test('la huella no depende del orden de los métodos propios', () {
      expect(
        CierreAdmin.huellaDeCobros(cajaCruda({
          'expectedCustomMethods': {'a': 1.0, 'b': 2.0},
        })),
        CierreAdmin.huellaDeCobros(cajaCruda({
          'expectedCustomMethods': {'b': 2.0, 'a': 1.0},
        })),
      );
    });
  });

  group('cómo se ve el corte', () {
    final datos = {
      ...CierreAdmin.datos(
        caja: caja(),
        ventas: const VentasDeCaja(efectivo: 395, transferencia: 175),
        actualizada: cierre,
        adminId: 'a1',
        adminNombre: 'Soporte',
      ),
      'closedAt': Timestamp.fromDate(cierre),
    };
    CashRegisterSummary cerrada([Map<String, dynamic> extra = const {}]) =>
        CashRegisterSummary.fromMap({...cajaCruda(), ...datos, ...extra});

    // Pedidos del período de OTRO cajero: no pueden entrar en este corte.
    final ajenos = [pedido(cobro: 'lety', monto: 5000)];

    test('descuadrada: sin diferencia, con lo vendido y sin recalcular', () {
      final r = cerrada();
      expect(r.cerradaPorAdmin, isTrue);
      expect(r.nombreDelAdmin, 'Soporte');
      expect(r.totalDifference, isNull);
      final c = CierreCaja.desde(r, ajenos, signo: 'Q');
      expect(c.estado, EstadoCierre.descuadrada);
      expect(c.diferencia, isNull);
      expect(c.recalculado, isFalse);
      expect(c.ventas, 570);
      expect(c.faltante, 0);
      expect(c.sobrante, 0);
      expect(c.aclaracion, isNull);
      // El efectivo esperado descuenta el retiro; nada contado.
      expect([for (final f in c.cuadre) (f.metodo, f.esperado, f.contado, f.diferencia)], [
        ('Efectivo', 345.0, null, null),
        ('Transferencia', 175.0, null, null),
      ]);
      expect(c.totalEfectivo, 445);
    });

    test('no es un faltante en el Inicio ni en el resumen', () {
      final r = cerrada();
      expect(AtencionInicio.faltantesDe([r]), isEmpty);
      final resumen = ResumenCierres.desde(
        cierres: [CierreCaja.desde(r, const [], signo: 'Q')],
        abiertas: const [],
        signoDeCaja: (_) => 'Q',
        ahora: cierre,
      ).porMoneda.single;
      expect(resumen.descuadradas, 1);
      expect(resumen.sinContar, 0);
      expect(resumen.conFaltante, 0);
      expect(resumen.faltante, 0);
      expect(resumen.ventas, 570);
    });

    test('si el POS la recalcula (sella diferencias sin conteo) sigue descuadrada', () {
      // Lo que escribe `recalculateClosedRegister`: contado nulo y diferencia = −esperado.
      final r = cerrada({
        'differenceCash': -445.0,
        'differenceCard': 0.0,
        'differenceTransfer': -175.0,
        'differencePedidosya': 0.0,
        'differenceUbereats': 0.0,
      });
      final c = CierreCaja.desde(r, const [], signo: 'Q');
      expect(c.estado, EstadoCierre.descuadrada);
      expect(c.faltante, 0);
      expect(c.ventas, 570);
      expect(c.cuadre.every((f) => f.contado == null), isTrue);
      expect(AtencionInicio.faltantesDe([r]), isEmpty);
    });

    test('con un método propio recalculado tampoco aparece un conteo', () {
      final r = cerrada({
        'differenceCash': -445.0,
        'expectedCustomMethods': {'custom_vale': 30.0},
        'differenceCustomMethods': {'custom_vale': -30.0},
        'actualCustomMethods': {'custom_vale': 0.0},
      });
      final c = CierreCaja.desde(r, const [], signo: 'Q');
      final vale = c.cuadre.singleWhere((f) => f.metodo == 'custom_vale');
      expect(vale.esperado, 30);
      expect(vale.contado, isNull);
    });

    test('si otro aparato la cerró encima con su conteo, vale el conteo', () {
      final r = cerrada({'actualCash': 400.0, 'differenceCash': -45.0});
      expect(r.cerradaPorAdmin, isFalse);
      expect(CierreCaja.desde(r, const [], signo: 'Q').estado, EstadoCierre.faltante);
    });

    test('un corte de siempre no se confunde', () {
      final normal = CashRegisterSummary.fromMap(cajaCruda({'status': 'closed', 'actualCash': 100.0}));
      expect(normal.cerradaPorAdmin, isFalse);
      final sinContar = CashRegisterSummary.fromMap(cajaCruda({'status': 'closed'}));
      expect(sinContar.cerradaPorAdmin, isFalse);
    });

    test('la copia con nombres de la pantalla conserva la marca', () {
      expect(cerrada().copyWith(locationName: 'Sanarate').cerradaPorAdmin, isTrue);
    });
  });
}
