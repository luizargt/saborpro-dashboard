import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kTenantId   = 'session_tenant_id';
  static const _kLocationId = 'session_location_id';
  static const _kDisplayName = 'session_display_name';
  static const _kUid        = 'session_firestore_uid';

  User? get firebaseUser => _auth.currentUser;
  bool get isLoggedIn => firebaseUser != null || _firestoreUid != null;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? _tenantId;
  String? _locationId;
  String? _displayName;
  String? _firestoreUid;

  String? get tenantId => _tenantId;
  String? get locationId => _locationId;
  String? get displayName => _displayName;

  Future<String?> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

    // Buscar usuario en Firestore
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      // ignore: avoid_print
      print('[AUTH] Usuario no encontrado en Firestore: $normalizedEmail');
      return 'Email o contraseña incorrectos';
    }

    final data = query.docs.first.data();
    final isMigrated = data['firebase_auth_migrated'] ?? false;
    // ignore: avoid_print
    print('[AUTH] firebase_auth_migrated=$isMigrated');
    // ignore: avoid_print
    print('[AUTH] keys en doc: ${data.keys.toList()}');

    if (isMigrated) {
      // Usuario migrado: usar Firebase Auth
      try {
        await _auth.signInWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
        );
        await _loadUserData(data, query.docs.first.id);
        return null;
      } on FirebaseAuthException catch (e) {
        switch (e.code) {
          case 'wrong-password':
          case 'user-not-found':
          case 'invalid-credential':
            return 'Email o contraseña incorrectos';
          case 'too-many-requests':
            return 'Demasiados intentos. Intenta más tarde';
          default:
            return 'Error al iniciar sesión (${e.code})';
        }
      }
    } else {
      // Usuario no migrado: validar hash en Firestore
      final storedHash = (data['passwordHash'] ?? data['password_hash']) as String?;
      // ignore: avoid_print
      print('[AUTH] passwordHash presente: ${storedHash != null}, valor: $storedHash');
      if (storedHash == null || !_verifyHash(password, storedHash)) {
        return 'Email o contraseña incorrectos';
      }
      await _loadUserData(data, query.docs.first.id);
      return null;
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
    _displayName = data['name'] as String?;
    // ignore: avoid_print
    print('[AUTH] tenantId=$_tenantId locationId=$_locationId name=$_displayName');
    // Persistir sesión para sobrevivir proceso killed por Android
    try {
      await Future.wait([
        _storage.write(key: _kUid,         value: _firestoreUid),
        _storage.write(key: _kTenantId,    value: _tenantId),
        _storage.write(key: _kLocationId,  value: _locationId),
        _storage.write(key: _kDisplayName, value: _displayName),
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
          // ignore: avoid_print
          print('[AUTH] Sesión restaurada desde storage: tenantId=$_tenantId');
        }
      } catch (_) {}
    }
  }

  Future<void> logout() async {
    _tenantId = null;
    _locationId = null;
    _displayName = null;
    _firestoreUid = null;
    try {
      await Future.wait([
        _storage.delete(key: _kUid),
        _storage.delete(key: _kTenantId),
        _storage.delete(key: _kLocationId),
        _storage.delete(key: _kDisplayName),
      ]);
    } catch (_) {}
    if (firebaseUser != null) {
      await _auth.signOut();
    }
  }
}
