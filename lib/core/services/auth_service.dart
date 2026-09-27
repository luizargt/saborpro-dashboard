import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TenantLoginCandidate {
  final Map<String, dynamic> data;
  final String docId;
  const TenantLoginCandidate(this.data, this.docId);
}

class LoginResult {
  final String? error;
  final bool needsTenantSelection;
  final List<TenantLoginCandidate> candidates;

  const LoginResult._({
    this.error,
    this.needsTenantSelection = false,
    this.candidates = const [],
  });

  bool get success => error == null && !needsTenantSelection;

  factory LoginResult.success() => const LoginResult._();
  factory LoginResult.failure(String msg) => LoginResult._(error: msg);
  factory LoginResult.tenantSelection(List<TenantLoginCandidate> c) =>
      LoginResult._(needsTenantSelection: true, candidates: c);
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kTenantId    = 'session_tenant_id';
  static const _kLocationId  = 'session_location_id';
  static const _kDisplayName = 'session_display_name';
  static const _kUid         = 'session_firestore_uid';
  static const _kEmail       = 'session_email';
  static const _kAssignedLocations = 'session_assigned_location_ids';

  User? get firebaseUser => _auth.currentUser;
  bool get isLoggedIn => firebaseUser != null || _firestoreUid != null;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? _tenantId;
  String? _locationId;
  String? _displayName;
  String? _firestoreUid;
  // Sucursales asignadas al usuario (vacío = acceso a todas)
  List<String> _assignedLocationIds = [];

  // Solo en memoria — nunca persisten en disco
  String? _sessionEmail;
  String? _sessionPassword;

  String? get tenantId => _tenantId;
  String? get locationId => _locationId;
  String? get displayName => _displayName;
  // Id del doc de users/ con el que se inició sesión. Es la llave con la que se
  // guardan el token FCM y las preferencias de notificaciones.
  String? get firestoreUid => _firestoreUid;
  String? get sessionEmail => _sessionEmail;
  String? get sessionPassword => _sessionPassword;
  List<String> get assignedLocationIds => _assignedLocationIds;

  static const _urlAdminLogin =
      'https://us-central1-saborprocom.cloudfunctions.net/adminLoginWithEmail';

  /// Relee un doc de users por ID, autoritativo (del servidor).
  ///
  /// Se usa después de tener sesión: leer por id funciona con las reglas
  /// cerradas, a diferencia de la query por correo que hace el flujo viejo.
  Future<Map<String, dynamic>?> _leerDocPorId(String docId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(docId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null;
    }
  }

  /// Camino rápido: resuelve la identidad en el servidor y deja lista la
  /// sesión de Firebase Auth, SIN leer 'users' antes de tener sesión.
  ///
  /// Devuelve null ante cualquier problema; el llamador sigue con el flujo de
  /// siempre, que queda intacto. Nunca lanza.
  Future<LoginResult?> _loginRapido(String email, String password) async {
    try {
      // Timeout TOTAL sobre el Future: acota también la resolución DNS.
      final resp = await http
          .post(
            Uri.parse(_urlAdminLogin),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map) return null;

      final lista = body['candidatos'];
      if (lista is! List || lista.isEmpty) return null;

      // Preferir la sesión REAL con proveedor password: es la que conserva el
      // cambio de contraseña. El custom token es el respaldo para cuando Auth
      // tiene otra contraseña que la de Firestore (hash viejo).
      var firmado = false;
      try {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
        firmado = true;
      } catch (_) {}
      if (!firmado) {
        final token = body['token'];
        if (token is String && token.isNotEmpty) {
          try {
            await _auth.signInWithCustomToken(token);
            firmado = true;
          } catch (_) {}
        }
      }
      if (!firmado) return null;

      final candidatos = <TenantLoginCandidate>[];
      for (final c in lista) {
        if (c is Map && c['user_id'] is String) {
          candidatos.add(TenantLoginCandidate(
              Map<String, dynamic>.from(c), c['user_id'] as String));
        }
      }
      if (candidatos.isEmpty) return null;

      // Un solo negocio: entrar directo, con el doc AUTORITATIVO por id.
      if (candidatos.length == 1) {
        final fresco = await _leerDocPorId(candidatos.first.docId);
        // Si no se pudo releer, se ABORTA el camino rápido: hidratar la sesión
        // con la versión saneada dejaría campos afuera (p. ej. la sucursal).
        if (fresco == null) return null;
        await _loadUserData(fresco, candidatos.first.docId);
        _sessionEmail = email;
        _sessionPassword = password;
        return LoginResult.success();
      }

      // Varios: que elija. completeTenantLogin relee por id igualmente.
      return LoginResult.tenantSelection(candidatos);
    } catch (_) {
      return null;
    }
  }

  Future<LoginResult> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

    // Camino rápido primero. Si no puede, sigue el flujo de siempre intacto.
    final rapido = await _loginRapido(normalizedEmail, password);
    if (rapido != null) return rapido;

    // Buscar TODOS los docs con este email (puede haber más de uno en multi-tenant)
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(10)
        .get();

    if (query.docs.isEmpty) {
      // ignore: avoid_print
      print('[AUTH] Usuario no encontrado en Firestore: $normalizedEmail');
      return LoginResult.failure('Email o contraseña incorrectos');
    }

    // Caso normal (1 doc): flujo idéntico al anterior
    if (query.docs.length == 1) {
      final data = query.docs.first.data();
      final docId = query.docs.first.id;
      final isMigrated = data['firebase_auth_migrated'] ?? false;
      // ignore: avoid_print
      print('[AUTH] firebase_auth_migrated=$isMigrated');

      if (isMigrated) {
        try {
          await _auth.signInWithEmailAndPassword(email: normalizedEmail, password: password);
          await _loadUserData(data, docId);
          _sessionEmail = normalizedEmail;
          _sessionPassword = password;
          return LoginResult.success();
        } on FirebaseAuthException catch (e) {
          return LoginResult.failure(_mapFirebaseError(e.code));
        }
      } else {
        final storedHash = (data['passwordHash'] ?? data['password_hash']) as String?;
        if (storedHash == null || !_verifyHash(password, storedHash)) {
          return LoginResult.failure('Email o contraseña incorrectos');
        }
        await _loadUserData(data, docId);
        _sessionEmail = normalizedEmail;
        _sessionPassword = password;
        return LoginResult.success();
      }
    }

    // Caso multi-tenant: validar la contraseña contra cada documento
    // ignore: avoid_print
    print('[AUTH] ${query.docs.length} docs encontrados para $normalizedEmail — validando cada uno');

    final List<TenantLoginCandidate> validCandidates = [];
    bool firebaseChecked = false;
    bool firebaseOk = false;

    for (final doc in query.docs) {
      final data = doc.data();
      final isMigrated = data['firebase_auth_migrated'] == true;

      if (isMigrated) {
        if (!firebaseChecked) {
          firebaseChecked = true;
          try {
            await _auth.signInWithEmailAndPassword(email: normalizedEmail, password: password);
            firebaseOk = true;
          } on FirebaseAuthException {
            firebaseOk = false;
          }
        }
        if (firebaseOk) validCandidates.add(TenantLoginCandidate(data, doc.id));
      } else {
        final storedHash = (data['passwordHash'] ?? data['password_hash']) as String?;
        if (storedHash != null && _verifyHash(password, storedHash)) {
          validCandidates.add(TenantLoginCandidate(data, doc.id));
        }
      }
    }

    if (validCandidates.isEmpty) {
      return LoginResult.failure('Email o contraseña incorrectos');
    }

    // Solo un doc valida: login directo
    if (validCandidates.length == 1) {
      final c = validCandidates.first;
      await _loadUserData(c.data, c.docId);
      _sessionEmail = normalizedEmail;
      _sessionPassword = password;
      return LoginResult.success();
    }

    // Varios docs válidos: pedir selección de restaurante
    return LoginResult.tenantSelection(validCandidates);
  }

  /// Completa el login después de que el usuario eligió un restaurante
  Future<LoginResult> completeTenantLogin({
    required Map<String, dynamic> data,
    required String docId,
    required String email,
    required String password,
  }) async {
    try {
      // Releer el doc por id: si el login vino del camino rápido, `data` es la
      // versión SANEADA que devuelve la function (sin hashes y sin todos los
      // campos que necesita _loadUserData, como la sucursal). Si la relectura
      // falla se usa `data`, que es lo que traía el flujo viejo.
      final fresco = await _leerDocPorId(docId);
      await _loadUserData(fresco ?? data, docId);
      _sessionEmail = email;
      _sessionPassword = password;
      return LoginResult.success();
    } catch (e) {
      return LoginResult.failure('Error al iniciar sesión');
    }
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
        return 'Email o contraseña incorrectos';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde';
      default:
        return 'Error al iniciar sesión ($code)';
    }
  }

  bool _verifyHash(String password, String storedHash) {
    try {
      if (storedHash.contains(':')) {
        final parts = storedHash.split(':');
        if (parts.length != 2) return false;
        final salt = parts[0];
        final hash = parts[1];
        // Orden correcto: password + salt
        final digest = sha256.convert(utf8.encode(password + salt)).toString();
        if (digest == hash) return true;
        // Fallback legacy: salt + password
        final digestLegacy = sha256.convert(utf8.encode(salt + password)).toString();
        return digestLegacy == hash;
      }
      // Hash legacy sin salt
      final legacy = sha256.convert(utf8.encode(password)).toString();
      return legacy.toLowerCase() == storedHash.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadUserData(Map<String, dynamic> data, String docId) async {
    _firestoreUid = docId;
    _tenantId = (data['tenant_id'] ?? data['current_tenant_id']) as String?;
    if (_tenantId == null) {
      final ids = data['tenant_ids'];
      if (ids is List && ids.isNotEmpty) {
        _tenantId = ids.first as String?;
      }
    }
    _locationId = (data['location_id'] ?? data['current_location_id']) as String?;
    _displayName  = data['name']  as String?;
    _sessionEmail ??= data['email'] as String?;
    // Sucursales asignadas (vacío = todas)
    final assigned = data['assigned_location_ids'];
    _assignedLocationIds = assigned is List
        ? assigned.map((e) => e.toString()).toList()
        : <String>[];
    // ignore: avoid_print
    print('[AUTH] tenantId=$_tenantId locationId=$_locationId name=$_displayName assigned=${_assignedLocationIds.length}');
    // Persistir sesión para sobrevivir proceso killed por Android
    try {
      await Future.wait([
        _storage.write(key: _kUid,         value: _firestoreUid),
        _storage.write(key: _kTenantId,    value: _tenantId),
        _storage.write(key: _kLocationId,  value: _locationId),
        _storage.write(key: _kDisplayName, value: _displayName),
        _storage.write(key: _kEmail, value: _sessionEmail ?? ''),
        _storage.write(key: _kAssignedLocations, value: jsonEncode(_assignedLocationIds)),
      ]);
    } catch (_) {}
  }

  Future<void> restoreSession() async {
    final user = firebaseUser;
    if (user != null) {
      try {
        final query = await _db
            .collection('users')
            .where('firebase_uid', isEqualTo: user.uid)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 10));
        if (query.docs.isNotEmpty) {
          await _loadUserData(query.docs.first.data(), query.docs.first.id);
        }
      } catch (_) {}
    } else {
      // Usuario no-migrado: restaurar desde almacenamiento seguro si Android mató el proceso
      try {
        final uid = await _storage.read(key: _kUid);
        if (uid != null) {
          _firestoreUid   = uid;
          _tenantId       = await _storage.read(key: _kTenantId);
          _locationId     = await _storage.read(key: _kLocationId);
          _displayName    = await _storage.read(key: _kDisplayName);
          _sessionEmail   = await _storage.read(key: _kEmail);
          _assignedLocationIds = _decodeAssigned(await _storage.read(key: _kAssignedLocations));
          // ignore: avoid_print
          print('[AUTH] Sesión restaurada desde storage: tenantId=$_tenantId');
        }
      } catch (_) {}
    }
  }

  /// Uid de `users/` que quedó persistido en el almacenamiento seguro.
  ///
  /// `restoreSession()` puede dejar `_firestoreUid` en null aunque haya sesión:
  /// con usuario de Firebase Auth vivo, la consulta por `firebase_uid` puede
  /// expirar (timeout de 10s) o fallar, y el catch se la come sin rastro —
  /// `isLoggedIn` sigue devolviendo true porque le basta el usuario de Firebase.
  /// Quien necesite el uid para escribir en `users/{uid}` (token FCM,
  /// preferencias de notificaciones) puede caer aquí antes de rendirse.
  Future<String?> readPersistedUid() async {
    try {
      return await _storage.read(key: _kUid);
    } catch (_) {
      return null;
    }
  }

  List<String> _decodeAssigned(String? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return <String>[];
  }

  /// Las pantallas NO la llaman directo: van por
  /// `NotificationService().cerrarSesionYDesvincular()`, que además deja al
  /// teléfono sin los avisos de la cuenta.
  Future<void> logout() async {
    _tenantId = null;
    _locationId = null;
    _displayName = null;
    _firestoreUid = null;
    _assignedLocationIds = [];
    _sessionEmail = null;
    _sessionPassword = null;
    try {
      await Future.wait([
        _storage.delete(key: _kUid),
        _storage.delete(key: _kTenantId),
        _storage.delete(key: _kLocationId),
        _storage.delete(key: _kDisplayName),
        _storage.delete(key: _kEmail),
        _storage.delete(key: _kAssignedLocations),
      ]);
    } catch (_) {}
    if (firebaseUser != null) {
      await _auth.signOut();
    }
  }
}
