import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/manager_notification.dart';

/// La bandeja de avisos de Sabor Manager.
///
/// Lee `manager_notifications`, que escriben las Cloud Functions al mismo
/// tiempo que mandan el push. No es la colección `user_notifications`: esa la
/// lee el POS, y estos avisos llevan el descuadre y la venta del turno.
class NotificationsProvider extends ChangeNotifier {
  /// Los mismos días que guarda el backend (helpers.js, DIAS_DE_HISTORIAL).
  static const diasDeHistorial = 7;

  // Getter y no campo: como campo se resuelve al construir el provider, o sea
  // dentro del MultiProvider, y exige Firebase ya inicializado incluso para una
  // instancia que nunca va a consultar nada.
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  String? _uid;
  List<ManagerNotification> _todas = [];
  bool _cargando = false;
  String? _error;

  List<ManagerNotification> get todas => _todas;
  bool get cargando => _cargando;
  String? get error => _error;

  int get sinLeer => _todas.where((n) => !n.read).length;
  bool get haySinLeer => sinLeer > 0;

  /// Arranca (o reengancha) el escucha en vivo para este usuario.
  ///
  /// Se puede llamar de nuevo con el mismo uid sin costo: si ya está escuchando
  /// a esa persona no rehace nada. Con uid distinto, cambia de cuenta y limpia
  /// lo anterior, que es lo que pasa al cerrar sesión y entrar con otra.
  void init(String? uid) {
    if (uid == _uid && _sub != null) return;
    _sub?.cancel();
    _uid = uid;
    _todas = [];
    _error = null;

    if (uid == null || uid.isEmpty) {
      _cargando = false;
      notifyListeners();
      return;
    }

    _cargando = true;
    notifyListeners();

    final desde = DateTime.now().subtract(
      const Duration(days: diasDeHistorial),
    );

    // El filtro por fecha va en la consulta y no en memoria: el TTL de
    // Firestore borra en su propio horario, así que puede haber documentos
    // vencidos todavía presentes y no tienen por qué llegar al teléfono.
    _sub = _db
        .collection('manager_notifications')
        .where('user_id', isEqualTo: uid)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .orderBy('created_at', descending: true)
        .limit(200)
        .snapshots()
        .listen(
      (snap) {
        _todas = snap.docs.map(ManagerNotification.fromDoc).toList();
        _cargando = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        // El caso típico acá es que falte el índice compuesto
        // (user_id + created_at). Se muestra en pantalla en vez de dejar un
        // spinner eterno.
        _cargando = false;
        _error = 'No se pudieron cargar los avisos';
        debugPrint('[NOTIF] error leyendo la bandeja: $e');
        notifyListeners();
      },
    );
  }

  /// Marca uno como leído. Optimista: la lista se actualiza en el acto y el
  /// stream confirma después. Sin esto el punto azul se queda encendido el
  /// tiempo que tarde el viaje al servidor, y parece que no funcionó.
  Future<void> marcarLeida(String id) async {
    final i = _todas.indexWhere((n) => n.id == id);
    if (i == -1 || _todas[i].read) return;
    _todas[i] = _copiaLeida(_todas[i]);
    notifyListeners();

    try {
      await _db.collection('manager_notifications').doc(id).update({
        'read': true,
        'read_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[NOTIF] no se pudo marcar como leída: $e');
      // No se revierte: el stream manda. Si la escritura falló de verdad, el
      // próximo snapshot lo devuelve a no leído solo.
    }
  }

  /// Marca todas las que están sin leer.
  Future<void> marcarTodasLeidas() async {
    final pendientes = _todas.where((n) => !n.read).toList();
    if (pendientes.isEmpty) return;

    _todas = _todas.map((n) => n.read ? n : _copiaLeida(n)).toList();
    notifyListeners();

    try {
      // En lotes de 400: Firestore corta en 500 operaciones por batch y la
      // bandeja llega hasta 200, pero el margen no cuesta nada.
      for (var i = 0; i < pendientes.length; i += 400) {
        final tanda = pendientes.skip(i).take(400);
        final batch = _db.batch();
        for (final n in tanda) {
          batch.update(_db.collection('manager_notifications').doc(n.id), {
            'read': true,
            'read_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[NOTIF] no se pudieron marcar todas: $e');
    }
  }

  ManagerNotification _copiaLeida(ManagerNotification n) => ManagerNotification(
        id: n.id,
        tipo: n.tipo,
        title: n.title,
        body: n.body,
        data: n.data,
        locationId: n.locationId,
        read: true,
        createdAt: n.createdAt,
      );

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
