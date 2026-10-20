import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/config_moneda.dart';

/// Lee y guarda la moneda principal y los tipos de cambio del negocio, en
/// `reportingCurrency/{tenantId}`. Es del negocio y no de cada persona: todos
/// los que entran a Sabor Manager tienen que ver las mismas cifras.
class ConfigMonedaService {
  ConfigMonedaService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String kCollection = 'reportingCurrency';

  /// Nulo si no se pudo leer. No es lo mismo que "no hay configuración": con
  /// una lectura fallida, quien guarde encima borraría los tipos de cambio.
  Future<ConfigMoneda?> leer(String tenantId) async {
    try {
      final doc = await _db.collection(kCollection).doc(tenantId).get();
      return ConfigMoneda.fromMap(doc.data());
    } catch (e) {
      debugPrint('[MONEDA] no se pudo leer: $e');
      return null;
    }
  }

  /// Aplica [cambio] sobre lo que está guardado AHORA, en una transacción: dos
  /// personas editando a la vez no se pisan, y una pantalla abierta desde
  /// hace rato no reescribe con lo que tenía en memoria.
  Future<ConfigMoneda> actualizar(
    String tenantId,
    ConfigMoneda Function(ConfigMoneda actual) cambio, {
    String? quien,
  }) {
    final ref = _db.collection(kCollection).doc(tenantId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final nueva = cambio(ConfigMoneda.fromMap(snap.data()));
      tx.set(ref, {
        'tenant_id': tenantId,
        ...nueva.toMap(),
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': quien,
      });
      return nueva;
    });
  }
}
