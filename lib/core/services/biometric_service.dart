import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyEmail = 'bio_email';
  static const _keyPassword = 'bio_password';
  static const _keyEnabled = 'bio_enabled';

  // Verifica si el dispositivo soporta biometría y tiene alguna enrollada
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Verifica si el usuario activó el login biométrico
  Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    final val = await _storage.read(key: _keyEnabled);
    return val == 'true';
  }

  // Guarda credenciales y activa biometría
  Future<void> saveCredentials(String email, String password) async {
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  // Desactiva y borra credenciales guardadas
  Future<void> clearCredentials() async {
    await _storage.deleteAll();
  }

  // Lanza el prompt de huella/Face ID y devuelve las credenciales si el usuario pasa
  Future<({String email, String password})?> authenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Usa tu huella o Face ID para ingresar',
        options: const AuthenticationOptions(
          biometricOnly: false, // permite PIN del sistema como fallback
          stickyAuth: true,
        ),
      );
      if (!ok) return null;
      final email = await _storage.read(key: _keyEmail);
      final password = await _storage.read(key: _keyPassword);
      if (email == null || password == null) return null;
      return (email: email, password: password);
    } on PlatformException {
      return null;
    }
  }
}
