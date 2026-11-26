import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/models/cash_register_summary.dart';
import '../../data/models/cierre_admin.dart';
import 'firestore_service.dart';

enum ResultadoCierreAdmin {
  cerrada,

  /// Alguien (su cajero u otro administrador) la cerró antes: no se toca.
  yaEstabaCerrada,
  noExiste,

  /// Le entraron cobros mientras se hacía la cuenta: no se cierra.
  cobrando,
}

/// De dónde se lee y dónde se escribe un cierre por administrador.
abstract class FuenteDeCierre {
  /// La caja como está en el servidor; nula si no existe.
  Future<Map<String, dynamic>?> leerCaja(String id);

  /// Los pedidos que pueden ser de la caja (pueden venir de más).
  Future<List<Map<String, dynamic>>> pedidosDelTurno({
    required String tenantId,
    required String cajaId,
    required DateTime desde,
    required DateTime hasta,
  });

  /// Relee la caja y, si [CierreAdminService.revisar] lo permite, le escribe lo
  /// que devuelva [datos] para esa lectura, todo en una sola operación.
  Future<ResultadoCierreAdmin> cerrarSiSigueIgual(
    String id, {
    required String huella,
    required Map<String, dynamic> Function(Map<String, dynamic> fresca) datos,
  });
}

/// Cierra una caja abierta desde Sabor Manager. Qué se escribe lo decide
/// [CierreAdmin]. Necesita internet: si algo no se puede leer, lanza y la caja
/// queda como estaba.
class CierreAdminService {
  final FuenteDeCierre _fuente;

  CierreAdminService({FuenteDeCierre? fuente}) : _fuente = fuente ?? _FuenteFirestore();

  /// Cuántas veces se rehace la cuenta si entran cobros mientras tanto.
  static const intentos = 3;

  /// ¿Se puede escribir el cierre sobre [fresca], la caja recién releída?
  /// [huella]: la de cuando se hizo la cuenta.
  static ResultadoCierreAdmin revisar(Map<String, dynamic>? fresca, String huella) {
    if (fresca == null) return ResultadoCierreAdmin.noExiste;
    if (fresca['status'] != 'open') return ResultadoCierreAdmin.yaEstabaCerrada;
    if (CierreAdmin.huellaDeCobros(fresca) != huella) return ResultadoCierreAdmin.cobrando;
    return ResultadoCierreAdmin.cerrada;
  }

  Future<ResultadoCierreAdmin> cerrar({
    required String cajaId,
    required String tenantId,
    required String adminId,
    required String adminNombre,
    DateTime Function() reloj = DateTime.now,
  }) async {
    for (var intento = 0; intento < intentos; intento++) {
      final cruda = await _fuente.leerCaja(cajaId);
      if (cruda == null || cruda['tenantId'] != tenantId) return ResultadoCierreAdmin.noExiste;
      if (cruda['status'] != 'open') return ResultadoCierreAdmin.yaEstabaCerrada;

      final caja = CashRegisterSummary.fromMap({...cruda, 'id': cajaId});
      // Holgado a propósito: lo que ya está en el servidor se cobró antes de este
      // cierre, y cortar con el reloj de este aparato (si va atrasado) dejaba
      // fuera las últimas ventas.
      final hasta = reloj().add(const Duration(hours: 12));
      final pedidos = await _fuente.pedidosDelTurno(
        tenantId: tenantId,
        cajaId: cajaId,
        desde: caja.openedAt.subtract(const Duration(seconds: 1)),
        hasta: hasta,
      );
      final ventas = VentasDeCaja.desde(CierreAdmin.pedidosDeLaCaja(pedidos, caja, hasta: hasta));

      final resultado = await _fuente.cerrarSiSigueIgual(
        cajaId,
        huella: CierreAdmin.huellaDeCobros(cruda),
        datos: (fresca) => CierreAdmin.datos(
          caja: caja,
          ventas: ventas,
          actualizada: CierreAdmin.horaDeActualizacion(fresca, reloj()),
          adminId: adminId,
          adminNombre: adminNombre,
        ),
      );
      if (resultado != ResultadoCierreAdmin.cobrando) return resultado;
    }
    return ResultadoCierreAdmin.cobrando;
  }
}

class _FuenteFirestore implements FuenteDeCierre {
  static const _espera = Duration(seconds: 20);

  /// Una caja olvidada por meses son miles de pedidos.
  static const _esperaPedidos = Duration(minutes: 3);
  static const _delServidor = GetOptions(source: Source.server);

  FirebaseFirestore get _db => FirestoreService().instance;

  DocumentReference<Map<String, dynamic>> _caja(String id) => _db.collection('cashRegisters').doc(id);

  @override
  Future<Map<String, dynamic>?> leerCaja(String id) async {
    final doc = await _caja(id).get(_delServidor).timeout(_espera);
    return doc.data();
  }

  @override
  Future<List<Map<String, dynamic>>> pedidosDelTurno({
    required String tenantId,
    required String cajaId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final delNegocio = _db.collection('orders').where('tenant_id', isEqualTo: tenantId);
    final consultas = await Future.wait([
      // `paid_at` como fecha de Firestore (lo normal)…
      delNegocio
          .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
          .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(hasta))
          .get(_delServidor),
      // …o como texto (cobros sin internet).
      delNegocio
          .where('paid_at', isGreaterThanOrEqualTo: desde.toIso8601String().substring(0, 23))
          .where('paid_at', isLessThanOrEqualTo: hasta.toIso8601String().substring(0, 23))
          .get(_delServidor),
      // Y las selladas con esta caja, aunque su hora de pago venga de un reloj mal puesto.
      delNegocio.where('cash_register_id', isEqualTo: cajaId).get(_delServidor),
    ]).timeout(_esperaPedidos);

    final vistos = <String>{};
    return [
      for (final c in consultas)
        for (final doc in c.docs)
          if (vistos.add(doc.id)) doc.data(),
    ];
  }

  @override
  Future<ResultadoCierreAdmin> cerrarSiSigueIgual(
    String id, {
    required String huella,
    required Map<String, dynamic> Function(Map<String, dynamic> fresca) datos,
  }) {
    final ref = _caja(id);
    // En transacción: si su cajero la cierra en este instante, su conteo no se pisa.
    return _db.runTransaction<ResultadoCierreAdmin>((tx) async {
      final fresca = (await tx.get(ref)).data();
      final resultado = CierreAdminService.revisar(fresca, huella);
      if (resultado == ResultadoCierreAdmin.cerrada) {
        tx.update(ref, {
          ...datos(fresca!),
          // La hora del cierre es la del servidor: decide qué ventas son del
          // turno y no puede depender del reloj de quien cierra.
          'closedAt': FieldValue.serverTimestamp(),
          'syncedAt': FieldValue.serverTimestamp(),
          'sync_status': 'synced',
        });
      }
      return resultado;
    }, timeout: _espera);
  }
}
