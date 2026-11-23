import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/cash_register_summary.dart';
import 'package:saborpro_reports/data/models/cierres_caja.dart';

/// La cuenta de cada corte (la misma que ya hacía CajasScreen, ahora sin widgets)
/// y el resumen del período por moneda. Los números de cada caso se pueden
/// comprobar a mano.
void main() {
  /// Un corte SELLADO: trae las diferencias que el POS calculó al cerrar.
  Map<String, dynamic> corte({
    String id = 'cr-1',
    String usuario = 'Ana Cosme',
    double apertura = 0,
    double? contadoEfectivo,
    double? difEfectivo = 0,
    double? contadoTarjeta,
    double? difTarjeta,
    List<Map<String, dynamic>> movimientos = const [],
    Map<String, dynamic> extra = const {},
    String? sucursal = 'gt',
    DateTime? abierta,
    DateTime? cerrada,
  }) =>
      {
        'id': id,
        'userId': 'u-$usuario',
        'userName': usuario,
        'status': 'closed',
        'locationId': sucursal,
        'openedAt': Timestamp.fromDate(abierta ?? DateTime(2026, 11, 20, 18)),
        'closedAt': Timestamp.fromDate(cerrada ?? DateTime(2026, 11, 21, 1, 25)),
        'initialCash': apertura,
        'actualCash': contadoEfectivo,
        'differenceCash': difEfectivo,
        if (contadoTarjeta != null) 'actualCard': contadoTarjeta,
        if (difTarjeta != null) 'differenceCard': difTarjeta,
        'movements': movimientos,
        ...extra,
      };

  CierreCaja cierre(Map<String, dynamic> datos, {List<Map<String, dynamic>> pedidos = const [], String signo = 'Q', Map<String, String> nombres = const {}}) =>
      CierreCaja.desde(CashRegisterSummary.fromMap(datos).copyWith(customMethodNames: nombres), pedidos, signo: signo);

  group('un corte sellado (el de Ana Cosme del diseño)', () {
    // Fondo Q2,000. Contó Q4,149 en efectivo (Q2,149 de ventas) y faltaron Q385.
    // Tarjeta: Q9,635.50, cuadrada.
    final c = cierre(corte(
      apertura: 2000,
      contadoEfectivo: 4149,
      difEfectivo: -385,
      contadoTarjeta: 9635.5,
      difTarjeta: 0,
    ));

    test('las ventas por método salen de lo contado menos la diferencia', () {
      expect(c.ventasEfectivo, 2534);
      expect(c.ventasTarjeta, 9635.5);
      expect(c.ventas, 12169.5);
    });

    test('el efectivo en caja y el total con apertura', () {
      expect(c.apertura, 2000);
      expect(c.totalEfectivo, 4534);
      expect(c.totalConApertura, 14169.5);
    });

    test('la tabla: esperado y contado SIN el fondo, y la diferencia', () {
      expect(c.cuadre.map((f) => f.metodo), ['Efectivo', 'Tarjeta']);
      expect(c.cuadre[0].esperado, 2534);
      expect(c.cuadre[0].contado, 2149);
      expect(c.cuadre[0].diferencia, -385);
      expect(c.cuadre[1].esperado, 9635.5);
      expect(c.cuadre[1].diferencia, 0);
    });

    test('terminó con faltante y se sabe cuánto', () {
      expect(c.diferencia, -385);
      expect(c.estado, EstadoCierre.faltante);
      expect(c.faltante, 385);
      expect(c.sobrante, 0);
    });
  });

  group('retiros y depósitos', () {
    // Fondo Q1,000 y se retiraron Q500: en la gaveta quedan Q1,879 con ventas de Q1,379.
    final c = cierre(corte(
      apertura: 1000,
      contadoEfectivo: 1879,
      difEfectivo: 0,
      movimientos: [
        {'type': 'withdrawal', 'amount': 500},
      ],
    ));

    test('el efectivo esperado descuenta los retiros; la venta no', () {
      expect(c.ventasEfectivo, 1379);
      expect(c.retiros, 500);
      expect(c.totalEfectivo, 1879);
      // Esperado en la tabla: ventas − retiros; contado: lo que hay menos el fondo.
      expect(c.cuadre.single.esperado, 879);
      expect(c.cuadre.single.contado, 879);
      expect(c.estado, EstadoCierre.cuadro);
    });

    test('un depósito suma al efectivo esperado', () {
      final d = cierre(corte(
        apertura: 100,
        contadoEfectivo: 400,
        difEfectivo: 0,
        movimientos: [
          {'type': 'deposit', 'amount': 50},
        ],
      ));
      // contado 400 = fondo 100 + ventas 350 − depósitos 50 (que no son venta).
      expect(d.ventasEfectivo, 250);
      expect(d.depositos, 50);
      expect(d.totalEfectivo, 400);
      expect(d.cuadre.single.esperado, 300);
    });
  });

  group('métodos propios (lo sellado, no el acumulado con restos)', () {
    Map<String, dynamic> conPropios(Map<String, dynamic> extra) => corte(
          contadoEfectivo: 100,
          difEfectivo: 0,
          extra: extra,
        );
    const nombres = {'custom_vales': 'Vales', 'custom_cupon': 'Cupón'};

    test('uno sin declarar: en el total y en la tabla con su faltante; el resto de una venta anulada no sale', () {
      // Vendió 100 en efectivo y 25 con Vales (que no se declaró: faltan 25).
      // Cupón 10 es el resto de una venta anulada: ningún corte lo contó.
      final c = cierre(
        conPropios({
          'expectedCustomMethods': {'custom_vales': 25.0, 'custom_cupon': 10.0},
          'actualCustomMethods': <String, double>{},
          'differenceCustomMethods': {'custom_vales': -25.0},
        }),
        nombres: nombres,
      );
      expect(c.ventasPropias, {'custom_vales': 25.0});
      expect(c.ventas, 125);
      expect(c.totalConApertura, 125);
      expect(c.diferencia, -25);
      final vales = c.cuadre.firstWhere((f) => f.metodo == 'Vales');
      expect(vales.esperado, 25);
      expect(vales.contado, 0);
      expect(vales.diferencia, -25);
      expect(c.cuadre.any((f) => f.metodo == 'Cupón'), isFalse);
      expect(c.otrosMetodos, [('Vales', 25.0)]);
    });

    test('un cierre forzado: cuenta en el total y sale sin diferencia', () {
      final c = cierre(conPropios({'expectedCustomMethods': {'custom_vales': 30.0}}), nombres: nombres);
      expect(c.ventas, 130);
      expect(c.totalConApertura, 130);
      expect(c.diferencia, 0);
      final vales = c.cuadre.firstWhere((f) => f.metodo == 'Vales');
      expect(vales.esperado, 30);
      expect(vales.contado, 30, reason: 'el forzado da por contado lo esperado');
      expect(vales.diferencia, 0);
    });

    test('"otros" sale con su nombre, no con el id', () {
      final c = cierre(conPropios({
        'expectedCustomMethods': {'otros': 15.0},
        'actualCustomMethods': {'otros': 15.0},
        'differenceCustomMethods': {'otros': 0.0},
      }));
      expect(c.cuadre.map((f) => f.metodo), contains('Otros (revisar)'));
      expect(c.otrosMetodos.single.$1, 'Otros (revisar)');
    });

    test('uno declarado sin ventas sale con su sobrante', () {
      final c = cierre(
        conPropios({
          'expectedCustomMethods': <String, double>{},
          'actualCustomMethods': {'custom_vales': 40.0},
          'differenceCustomMethods': {'custom_vales': 40.0},
        }),
        nombres: nombres,
      );
      expect(c.diferencia, 40);
      expect(c.estado, EstadoCierre.sobrante);
      expect(c.sobrante, 40);
    });

    test('las ventas de un método propio en cero no se listan en "otros métodos"', () {
      final c = cierre(
        conPropios({
          'expectedCustomMethods': {'custom_vales': 30.0},
          'actualCustomMethods': {'custom_vales': 0.0},
          'differenceCustomMethods': {'custom_vales': 0.0},
        }),
        nombres: nombres,
      );
      // Sellado: ventas = declarado − diferencia = 0.
      expect(c.ventasPropias, {'custom_vales': 0.0});
      expect(c.otrosMetodos, isEmpty);
      expect(c.ventas, 100);
    });
  });

  group('otros métodos con ventas', () {
    test('tarjeta, transferencia, PedidosYa y Uber Eats, en ese orden y solo si vendieron', () {
      final c = cierre(corte(
        contadoEfectivo: 100,
        difEfectivo: 0,
        contadoTarjeta: 50,
        difTarjeta: 0,
        extra: {
          'actualTransfer': 30.0,
          'differenceTransfer': 0.0,
          'actualUbereats': 20.0,
          'differenceUbereats': 0.0,
        },
      ));
      expect(c.otrosMetodos, [('Venta con tarjeta', 50.0), ('Venta con transferencia', 30.0), ('Uber Eats', 20.0)]);
      expect(c.ventasOtros, 50, reason: 'sin la tarjeta');
      expect(c.ventas, 200);
    });
  });

  group('un corte antiguo, sin diferencias selladas: se recalcula desde los pedidos', () {
    final base = corte(
      apertura: 100,
      contadoEfectivo: 350,
      difEfectivo: null,
      contadoTarjeta: 80,
      difTarjeta: null,
      sucursal: 'gt',
      abierta: DateTime(2026, 10, 1, 8),
      cerrada: DateTime(2026, 10, 1, 16),
    );

    Map<String, dynamic> pedido(String metodo, double monto, {int hora = 10, String? estado, String sucursal = 'gt', Map<String, dynamic> extra = const {}}) => {
          'payment_method': metodo,
          'payment_amount': monto,
          'paid_at': Timestamp.fromDate(DateTime(2026, 10, 1, hora)),
          'location_id': sucursal,
          if (estado != null) 'status': estado,
          ...extra,
        };

    test('suma los pedidos de la caja por método y calcula la diferencia con lo contado', () {
      final c = cierre(base, pedidos: [
        pedido('cash', 200),
        pedido('card', 80),
        pedido('cash', 50, hora: 12),
      ]);
      expect(c.ventasEfectivo, 250);
      expect(c.ventasTarjeta, 80);
      expect(c.ventas, 330);
      // Contó 350 − 100 de fondo = 250 de efectivo y 80 de tarjeta: 330 contra 330.
      expect(c.diferencia, 0);
      expect(c.estado, EstadoCierre.cuadro);
    });

    test('no cuenta canceladas, otras sucursales ni lo cobrado fuera de la ventana de la caja', () {
      final c = cierre(base, pedidos: [
        pedido('cash', 100),
        pedido('cash', 999, estado: 'CANCELLED'),
        pedido('cash', 888, sucursal: 'sv'),
        pedido('cash', 777, hora: 18), // después del cierre
        pedido('cash', 666, hora: 7), // antes de abrir
      ]);
      expect(c.ventasEfectivo, 100);
      // Contó 250 de efectivo (350 − 100 de fondo) y 80 de tarjeta: 330 contra
      // 100 vendidos. Sobran 230.
      expect(c.diferencia, 230);
      expect(c.estado, EstadoCierre.sobrante);
    });

    test('un pedido mixto reparte cada parte en su método; uno sin partes va a efectivo', () {
      final c = cierre(base, pedidos: [
        pedido('split', 100, extra: {
          'split_payments': [
            {'payment_method': 'cash', 'amount': 60},
            {'payment_method': 'card', 'amount': 40},
          ],
        }),
        pedido('mixed', 30, extra: {
          'mixed_payments': [
            {'method': 'custom_vales', 'amount': 30},
          ],
        }),
        pedido('split', 20),
        pedido('metodo_raro', 5),
      ]);
      expect(c.ventasEfectivo, 60 + 20 + 5);
      expect(c.ventasTarjeta, 40);
      expect(c.ventasPropias, {'custom_vales': 30.0});
    });

    test('sin pedidos en la ventana, usa los acumulados del corte', () {
      final r = CashRegisterSummary.fromMap({
        ...base,
        'expectedCash': 300.0,
        'expectedCard': 80.0,
      });
      final c = CierreCaja.desde(r, [pedido('cash', 100, hora: 20)], signo: 'Q');
      expect(c.ventasEfectivo, 200, reason: 'esperado 300 − fondo 100');
      expect(c.ventasTarjeta, 80);
    });

    test('con las diferencias selladas NO se recalcula aunque haya pedidos', () {
      final sellado = corte(
        apertura: 100,
        contadoEfectivo: 350,
        difEfectivo: 0,
        abierta: DateTime(2026, 10, 1, 8),
        cerrada: DateTime(2026, 10, 1, 16),
      );
      final c = cierre(sellado, pedidos: [pedido('cash', 9999)]);
      expect(c.ventasEfectivo, 250);
    });
  });

  group('cómo terminó (el umbral de un centavo)', () {
    EstadoCierre estadoCon(double dif) => cierre(corte(contadoEfectivo: 100, difEfectivo: dif)).estado;

    test('menos de un centavo es cuadre; desde un centavo, faltante o sobrante', () {
      expect(estadoCon(0), EstadoCierre.cuadro);
      expect(estadoCon(-0.009), EstadoCierre.cuadro);
      expect(estadoCon(0.009), EstadoCierre.cuadro);
      expect(estadoCon(-0.01), EstadoCierre.faltante);
      expect(estadoCon(0.01), EstadoCierre.sobrante);
    });

    test('si no se contó nada, no hay estado (no se dice que cuadró)', () {
      final c = cierre(corte(contadoEfectivo: null, difEfectivo: null));
      expect(c.diferencia, isNull);
      expect(c.estado, EstadoCierre.sinContar);
      expect(c.faltante, 0);
      expect(c.sobrante, 0);
    });
  });

  group('la aclaración', () {
    test('solo se muestra si hubo diferencia', () {
      final con = cierre(corte(contadoEfectivo: 90, difEfectivo: -10, extra: {'closingNotes': '  Se cayó un billete  '}));
      expect(con.aclaracion, 'Se cayó un billete');
      final sin = cierre(corte(contadoEfectivo: 100, difEfectivo: 0, extra: {'closingNotes': 'Todo bien'}));
      expect(sin.aclaracion, isNull);
      final vacia = cierre(corte(contadoEfectivo: 90, difEfectivo: -10, extra: {'closingNotes': '   '}));
      expect(vacia.aclaracion, isNull);
    });
  });

  group('formatoDuracion e inicialesDe', () {
    test('horas y minutos; menos de una hora, solo minutos', () {
      expect(formatoDuracion(const Duration(hours: 7, minutes: 24)), '7h 24m');
      expect(formatoDuracion(const Duration(minutes: 50)), '50m');
      expect(formatoDuracion(const Duration(hours: 203, minutes: 49)), '203h 49m');
      expect(formatoDuracion(Duration.zero), '0m');
    });

    test('las iniciales de las dos primeras palabras', () {
      expect(inicialesDe('Ana Cosme'), 'AC');
      expect(inicialesDe('Juan Carlos Ixtan'), 'JC');
      expect(inicialesDe('  madonna '), 'M');
      expect(inicialesDe(''), '?');
    });
  });

  group('el resumen del período', () {
    final ahora = DateTime(2026, 11, 21, 2);

    CashRegisterSummary abierta(String id, String usuario, DateTime desde, {String? sucursal = 'gt'}) => CashRegisterSummary(
          id: id,
          userId: 'u-$usuario',
          userName: usuario,
          status: 'open',
          openedAt: desde,
          locationId: sucursal,
        );

    String signoDe(String? loc) => loc == 'sv' ? r'$' : 'Q';

    ResumenCierres resumen(List<CierreCaja> cierres, List<CashRegisterSummary> abiertas) =>
        ResumenCierres.desde(cierres: cierres, abiertas: abiertas, signoDeCaja: signoDe, ahora: ahora);

    final ana = cierre(corte(id: 'a', apertura: 2000, contadoEfectivo: 4149, difEfectivo: -385, contadoTarjeta: 9635.5, difTarjeta: 0));
    final juan = cierre(corte(id: 'j', usuario: 'Juan', apertura: 1000, contadoEfectivo: 1879, difEfectivo: 0, contadoTarjeta: 4830.5, difTarjeta: 0, movimientos: [
      {'type': 'withdrawal', 'amount': 500},
    ]));

    test('suma ventas, efectivo y tarjeta de los cierres de una moneda', () {
      final r = resumen([ana, juan], const []);
      expect(r.porMoneda, hasLength(1));
      final q = r.porMoneda.single;
      expect(q.signo, 'Q');
      expect(q.cierres, 2);
      expect(q.ventas, 12169.5 + 1379 + 4830.5);
      expect(q.efectivo, 2534 + 1379);
      expect(q.tarjeta, 9635.5 + 4830.5);
      expect(q.otros, 0);
    });

    test('el faltante es lo que faltó, sin netearlo contra un sobrante de otro cierre', () {
      final sobra = cierre(corte(id: 's', usuario: 'Marta', contadoEfectivo: 150, difEfectivo: 50));
      final r = resumen([ana, juan, sobra], const []).porMoneda.single;
      expect(r.conFaltante, 1);
      expect(r.faltante, 385);
      expect(r.conSobrante, 1);
      expect(r.sobrante, 50);
    });

    test('los cierres sin contar se cuentan aparte', () {
      final sin = cierre(corte(id: 'x', contadoEfectivo: null, difEfectivo: null));
      final r = resumen([ana, sin], const []).porMoneda.single;
      expect(r.sinContar, 1);
      expect(r.conFaltante, 1);
    });

    test('cajas abiertas: cuántas y cuáles son de un turno que nadie cerró (24 h o más)', () {
      final reciente = abierta('r', 'Marta', DateTime(2026, 11, 21, 1, 10));
      final vieja = abierta('v', 'Ana Lena', DateTime(2026, 11, 12, 21, 3));
      final justo = abierta('j', 'Luis', ahora.subtract(const Duration(hours: 24)));
      final casi = abierta('c', 'Eva', ahora.subtract(const Duration(hours: 23, minutes: 59)));
      final r = resumen(const [], [reciente, vieja, justo, casi]);
      expect(r.porMoneda.single.abiertas, 4);
      expect(r.olvidadas.map((c) => c.id), ['v', 'j'], reason: 'la más vieja primero; 24 h justas ya cuentan');
      expect(r.porMoneda.single.olvidadas, hasLength(2));
    });

    test('con cajas en dos monedas no se mezclan: un grupo por moneda, en el orden en que aparecen', () {
      final sv = cierre(corte(id: 'sv1', usuario: 'Rosa', sucursal: 'sv', contadoEfectivo: 80, difEfectivo: 0), signo: r'$');
      final abiertaSv = abierta('o', 'Pablo', DateTime(2026, 11, 21, 1), sucursal: 'sv');
      final r = resumen([ana, sv], [abiertaSv]);
      expect(r.porMoneda.map((g) => g.signo), ['Q', r'$']);
      expect(r.porMoneda[0].ventas, 12169.5);
      expect(r.porMoneda[1].ventas, 80);
      expect(r.porMoneda[0].abiertas, 0);
      expect(r.porMoneda[1].abiertas, 1);
    });

    test('una moneda que solo tiene cajas abiertas también tiene su grupo', () {
      final r = resumen([ana], [abierta('o', 'Pablo', DateTime(2026, 11, 21, 1), sucursal: 'sv')]);
      expect(r.porMoneda.map((g) => g.signo), ['Q', r'$']);
      expect(r.porMoneda[1].cierres, 0);
      expect(r.porMoneda[1].ventas, 0);
    });

    test('sin nada, sin grupos', () {
      expect(resumen(const [], const []).porMoneda, isEmpty);
    });
  });

  group('agrupar por moneda, no por signo', () {
    CierreCaja enMoneda(String id, String signo, String moneda, {double venta = 1000}) => CierreCaja.desde(
          CashRegisterSummary.fromMap(corte(id: id, contadoEfectivo: venta, difEfectivo: 0)),
          const [],
          signo: signo,
          moneda: moneda,
        );

    test('dos monedas que comparten el signo "\$" (MXN y USD) NO se suman', () {
      final r = ResumenCierres.desde(
        cierres: [enMoneda('a', r'$', 'MXN'), enMoneda('b', r'$', 'USD')],
        abiertas: const [],
        signoDeCaja: (_) => r'$',
        monedaDeCaja: (loc) => loc == 'usd' ? 'USD' : 'MXN',
        ahora: DateTime(2026, 11, 21),
      );
      expect(r.porMoneda.map((g) => (g.moneda, g.signo, g.ventas)), [('MXN', r'$', 1000.0), ('USD', r'$', 1000.0)]);
    });

    test('una misma moneda escrita distinto ("Q" y "Q.") es UN grupo', () {
      final r = ResumenCierres.desde(
        cierres: [enMoneda('a', 'Q', 'GTQ'), enMoneda('b', 'Q.', 'GTQ', venta: 500)],
        abiertas: const [],
        signoDeCaja: (_) => 'Q',
        monedaDeCaja: (_) => 'GTQ',
        ahora: DateTime(2026, 11, 21),
      );
      expect(r.porMoneda, hasLength(1));
      expect(r.porMoneda.single.ventas, 1500);
      expect(r.porMoneda.single.signo, 'Q', reason: 'el signo con que se muestra es el del primero');
    });

    test('las cajas abiertas se asignan a su moneda por código', () {
      final abierta = CashRegisterSummary(id: 'o', userId: 'o', userName: 'Pablo', status: 'open', openedAt: DateTime(2026, 11, 21, 1), locationId: 'usd');
      final r = ResumenCierres.desde(
        cierres: [enMoneda('a', r'$', 'MXN')],
        abiertas: [abierta],
        signoDeCaja: (_) => r'$',
        monedaDeCaja: (loc) => loc == 'usd' ? 'USD' : 'MXN',
        ahora: DateTime(2026, 11, 21, 8),
      );
      expect(r.porMoneda.map((g) => (g.moneda, g.abiertas)), [('MXN', 0), ('USD', 1)]);
    });

    test('sin el código se agrupa por signo, como antes', () {
      final r = ResumenCierres.desde(
        cierres: [enMoneda('a', 'Q', 'Q'), enMoneda('b', 'Q', 'Q')],
        abiertas: const [],
        signoDeCaja: (_) => 'Q',
        ahora: DateTime(2026, 11, 21),
      );
      expect(r.porMoneda.single.ventas, 2000);
    });
  });

  group('los cortes recalculados se avisan', () {
    test('un corte sin sellar cuyos pedidos se recalcularon cuenta como recalculado; uno sellado, no', () {
      final antiguo = CashRegisterSummary.fromMap({
        'id': 'old', 'userName': 'Ana', 'status': 'closed', 'locationId': 'gt',
        'openedAt': Timestamp.fromDate(DateTime(2026, 2, 1, 8)), 'closedAt': Timestamp.fromDate(DateTime(2026, 2, 1, 16)),
        'actualCash': 300.0,
      });
      final pedido = {'payment_method': 'cash', 'payment_amount': 100.0, 'paid_at': Timestamp.fromDate(DateTime(2026, 2, 1, 10)), 'location_id': 'gt'};
      final viejo = CierreCaja.desde(antiguo, [pedido], signo: 'Q');
      expect(viejo.recalculado, isTrue);
      final sellado = cierre(corte(contadoEfectivo: 100, difEfectivo: 0));
      expect(sellado.recalculado, isFalse);
      // Sin pedidos en su ventana usa los acumulados: tampoco es recalculado.
      expect(CierreCaja.desde(antiguo, const [], signo: 'Q').recalculado, isFalse);

      final r = ResumenCierres.desde(cierres: [viejo, sellado], abiertas: const [], signoDeCaja: (_) => 'Q', ahora: DateTime(2026, 11, 21));
      expect(r.porMoneda.single.recalculados, 1);
    });
  });

  group('formatoMonto', () {
    test('miles, centavos y el signo de moneda (con el espacio de "USD ")', () {
      expect(formatoMonto('Q', 1234567.891), 'Q1,234,567.89');
      expect(formatoMonto('USD ', 1), 'USD 1.00');
      expect(formatoMonto('Q', 0), 'Q0.00');
    });

    test('el negativo lleva "−" y lo que redondea a cero no lleva signo', () {
      expect(formatoMonto('Q', -385), '−Q385.00');
      expect(formatoMonto('Q', -0.004), 'Q0.00');
      expect(formatoMonto('Q', 0.004), 'Q0.00');
      expect(formatoMonto('Q', -0.005), '−Q0.01');
      expect(formatoMonto('Q', 0.005), 'Q0.01');
    });

    test('los mismos dígitos que la tarjeta de antes (intl sobre el valor): medio centavo', () {
      expect(formatoMonto('Q', 0.695), 'Q0.70');
      expect(formatoMonto('Q', 2.815), 'Q2.82');
      expect(formatoMonto('Q', 1.615), 'Q1.62');
    });

    test('un valor que no es número no lanza', () {
      expect(() => formatoMonto('Q', double.nan), returnsNormally);
      expect(() => formatoMonto('Q', double.infinity), returnsNormally);
    });
  });
}
