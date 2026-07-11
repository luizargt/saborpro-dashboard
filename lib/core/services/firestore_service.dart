import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    // Persistencia offline DESACTIVADA en TODAS las plataformas: este es un dashboard
    // de reportes financieros, debe reflejar siempre el estado real del servidor y
    // nunca datos cacheados desactualizados — no tiene sentido que funcione offline.
    // En web además evita el stall de inicialización de IndexedDB: con
    // persistenceEnabled la primera query de cada carga se bloqueaba 11-54s (medido)
    // esperando a adquirir el lock de IndexedDB, sobre todo con varias pestañas
    // abiertas. Los round-trips de red a Firestore son rápidos (~100ms, verificado en
    // Network tab), así que el cuello de botella era 100% la inicialización de
    // persistencia, no la red. Persistencia OFF fue la mejora grande en web (32s →
    // 11s). Se probó forzar long-polling encima pero EMPEORÓ el handshake inicial
    // (6s → 23s), así que se descartó: WebChannel por defecto es lo mejor aquí.
    _db.settings = const Settings(
      persistenceEnabled: false,
    );
    _initialized = true;
  }

  FirebaseFirestore get instance => _db;
  CollectionReference<Map<String, dynamic>> get orders => _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get locations => _db.collection('locations');
  CollectionReference<Map<String, dynamic>> get users => _db.collection('users');
}
