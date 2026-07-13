import 'dart:convert';
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
  String? get sessionEmail => _sessionEmail;
  String? get sessionPassword => _sessionPassword;
  List<String> get assignedLocationIds => _assignedLocationIds;

  Future<LoginResult> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

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
      await _loadUserData(data, docId);
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

  List<String> _decodeAssigned(String? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return <String>[];
  }

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
