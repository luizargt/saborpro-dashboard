import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      // Persistencia offline DESACTIVADA en web. Con persistenceEnabled la primera
      // query de cada carga se bloqueaba 11-54s (medido) esperando a inicializar
      // IndexedDB y adquirir su lock — con backoff por reintentos, sobre todo si
      // hay varias pestañas abiertas. Los round-trips de red a Firestore son
      // rápidos (~100ms, verificado en Network tab), así que el cuello de botella
      // era 100% la inicialización de persistencia, no la red. Un dashboard de
      // reportes no necesita caché offline: cada query va directo al server.
      // Persistencia OFF fue la mejora grande (32s → 11s): eliminaba el stall de
      // inicialización de IndexedDB. Se probó forzar long-polling encima pero
      // EMPEORÓ el handshake inicial (6s → 23s), así que se descartó: WebChannel
      // por defecto es lo mejor aquí.
      _db.settings = const Settings(
        persistenceEnabled: false,
      );
    }
    _initialized = true;
  }

  FirebaseFirestore get instance => _db;
  CollectionReference<Map<String, dynamic>> get orders => _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get locations => _db.collection('locations');
  CollectionReference<Map<String, dynamic>> get users => _db.collection('users');
}
