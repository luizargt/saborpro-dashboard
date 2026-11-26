import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/cierre_admin_service.dart';

/// Los pasos del cierre por administrador, con un Firestore de mentira.
void main() {
  final apertura = DateTime(2026, 11, 20, 8);
  final ahora = DateTime(2026, 11, 25, 21);

  Map<String, dynamic> caja([Map<String, dynamic> extra = const {}]) => {
        'tenantId': 't1',
        'userId': 'wendy',
        'userName': 'WENDY',
        'status': 'open',
        'locationId': 'sana',
        'openedAt': Timestamp.fromDate(apertura),
        'initialCash': 100.0,
        'expectedCash': 350.0,
        ...extra,
      };

  Map<String, dynamic> venta(double monto, {DateTime? a}) => {
        'location_id': 'sana',
        'status': 'COMPLETED',
        'payment_status': 'PAID',
        'payment_method': 'cash',
        'payment_amount': monto,
        'paid_at': Timestamp.fromDate(a ?? DateTime(2026, 11, 21, 10)),
        'paid_by_user_id': 'wendy',
      };

  Future<ResultadoCierreAdmin> cerrar(_Falsa fuente) => CierreAdminService(fuente: fuente)
      .cerrar(cajaId: 'c1', tenantId: 't1', adminId: 'a1', adminNombre: 'Soporte', reloj: () => ahora);

  test('una caja abierta se cierra con lo vendido en su turno', () async {
    final f = _Falsa(caja(), [venta(250)]);
    expect(await cerrar(f), ResultadoCierreAdmin.cerrada);
    expect(f.escrito!['expectedCash'], 350);
    expect(f.escrito!['updatedAt'], Timestamp.fromDate(ahora));
    expect(f.escrito!['actualCash'], isNull);
    expect(f.pedidoDesde, apertura.subtract(const Duration(seconds: 1)));
  });

  test('con el reloj de este aparato atrasado no se pierden las últimas ventas', () async {
    // Cobrada "dentro de una hora" según este reloj.
    final f = _Falsa(caja(), [venta(75, a: ahora.add(const Duration(hours: 1)))]);
    expect(await cerrar(f), ResultadoCierreAdmin.cerrada);
    expect(f.escrito!['expectedCash'], 175);
    expect(f.pedidoHasta!.isAfter(ahora.add(const Duration(hours: 11))), isTrue);
  });

  test('si entra un cobro mientras se hace la cuenta, se rehace con él', () async {
    final f = _Falsa(caja(), [venta(250)]);
    f.mientrasLeePedidos = (vez) {
      if (vez == 1) {
        f.caja = caja({'expectedCash': 450.0});
        f.pedidos = [venta(250), venta(100)];
      }
    };
    // La primera lectura de pedidos no alcanza a ver el cobro nuevo.
    expect(await cerrar(f), ResultadoCierreAdmin.cerrada);
    expect(f.lecturasDePedidos, 2);
    expect(f.escrito!['expectedCash'], 450);
  });

  test('si no dejan de cobrar no se cierra y no se escribe nada', () async {
    final f = _Falsa(caja(), [venta(250)]);
    f.mientrasLeePedidos = (vez) => f.caja = caja({'expectedCash': 350.0 + vez});
    expect(await cerrar(f), ResultadoCierreAdmin.cobrando);
    expect(f.lecturasDePedidos, CierreAdminService.intentos);
    expect(f.escrito, isNull);
  });

  test('si ya estaba cerrada no lee pedidos ni escribe', () async {
    final f = _Falsa(caja({'status': 'closed'}), [venta(250)]);
    expect(await cerrar(f), ResultadoCierreAdmin.yaEstabaCerrada);
    expect(f.lecturasDePedidos, 0);
    expect(f.escrito, isNull);
  });

  test('si no existe, o es de otro negocio, no escribe', () async {
    final sin = _Falsa(null, const []);
    expect(await cerrar(sin), ResultadoCierreAdmin.noExiste);
    final ajena = _Falsa(caja({'tenantId': 't2'}), const []);
    expect(await cerrar(ajena), ResultadoCierreAdmin.noExiste);
    expect(sin.escrito, isNull);
    expect(ajena.escrito, isNull);
  });

  test('si su cajero la cierra mientras tanto, se respeta su cierre', () async {
    final f = _Falsa(caja(), [venta(250)]);
    f.mientrasLeePedidos = (_) => f.caja = caja({'status': 'closed', 'actualCash': 350.0});
    expect(await cerrar(f), ResultadoCierreAdmin.yaEstabaCerrada);
    expect(f.escrito, isNull);
  });

  test('sin poder leer los pedidos no se cierra', () async {
    final f = _Falsa(caja(), const [])..mientrasLeePedidos = (_) => throw Exception('sin internet');
    await expectLater(cerrar(f), throwsException);
    expect(f.escrito, isNull);
  });
}

class _Falsa implements FuenteDeCierre {
  Map<String, dynamic>? caja;
  List<Map<String, dynamic>> pedidos;

  /// Lo que pasa en el negocio mientras se leen los pedidos (1 = primera vez).
  void Function(int vez)? mientrasLeePedidos;

  Map<String, dynamic>? escrito;
  DateTime? pedidoDesde;
  DateTime? pedidoHasta;
  int lecturasDePedidos = 0;

  _Falsa(this.caja, this.pedidos);

  @override
  Future<Map<String, dynamic>?> leerCaja(String id) async => caja;

  @override
  Future<List<Map<String, dynamic>>> pedidosDelTurno({
    required String tenantId,
    required String cajaId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    pedidoDesde = desde;
    pedidoHasta = hasta;
    final vistos = pedidos;
    lecturasDePedidos++;
    mientrasLeePedidos?.call(lecturasDePedidos);
    return vistos;
  }

  @override
  Future<ResultadoCierreAdmin> cerrarSiSigueIgual(
    String id, {
    required String huella,
    required Map<String, dynamic> Function(Map<String, dynamic> fresca) datos,
  }) async {
    final resultado = CierreAdminService.revisar(caja, huella);
    if (resultado == ResultadoCierreAdmin.cerrada) escrito = datos(caja!);
    return resultado;
  }
}
