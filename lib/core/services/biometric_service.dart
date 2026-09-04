import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Qué sensor tiene el dispositivo. Determina el ícono y el texto que ve el
/// usuario: decirle "usa tu huella" a alguien con un iPhone con Face ID lo
/// manda a buscar un sensor que su teléfono no tiene.
enum BiometricKind { faceId, touchId, fingerprint, faceAndroid, generic }

extension BiometricKindLabel on BiometricKind {
  /// Nombre del método tal como lo llama el fabricante.
  String get label => switch (this) {
        BiometricKind.faceId => 'Face ID',
        BiometricKind.touchId => 'Touch ID',
        BiometricKind.fingerprint => 'huella',
        BiometricKind.faceAndroid => 'rostro',
        BiometricKind.generic => 'biometría',
      };

  /// Texto para un botón: "Ingresar con Face ID" / "Ingresar con tu huella".
  String get actionLabel => switch (this) {
        BiometricKind.faceId => 'Ingresar con Face ID',
        BiometricKind.touchId => 'Ingresar con Touch ID',
        BiometricKind.fingerprint => 'Ingresar con tu huella',
        BiometricKind.faceAndroid => 'Ingresar con tu rostro',
        BiometricKind.generic => 'Ingresar con biometría',
      };

  /// Cómo nombrar la función en ajustes: "Inicio con Face ID".
  String get settingsLabel => switch (this) {
        BiometricKind.faceId => 'Inicio con Face ID',
        BiometricKind.touchId => 'Inicio con Touch ID',
        BiometricKind.fingerprint => 'Inicio con huella',
        BiometricKind.faceAndroid => 'Inicio con rostro',
        BiometricKind.generic => 'Inicio con biometría',
      };

  /// Dónde registrar el dato biométrico si el usuario no tiene ninguno.
  String get enrollHint => switch (this) {
        BiometricKind.faceId ||
        BiometricKind.touchId =>
          'Ve a Ajustes → Face ID y código (o Touch ID y código) '
              'para configurarlo y luego vuelve aquí.',
        _ => 'Ve a Configuración → Seguridad → Huella digital o '
            'Desbloqueo facial para registrar una y luego vuelve aquí.',
      };
}

/// Resultado de pedir la biometría.
///
/// Distingue tres desenlaces que antes se veían iguales (`null`): entró bien,
/// el usuario canceló a propósito, o algo falló de verdad. Sin esa diferencia
/// el login no sabía si callar o explicar, y siempre callaba.
class BiometricAuthResult {
  final String? email;
  final String? password;

  /// Mensaje listo para mostrar. Null cuando salió bien o cuando el usuario
  /// canceló (cancelar no es un error que merezca un letrero rojo).
  final String? error;

  /// El usuario cerró el prompt del sistema por su cuenta.
  final bool cancelled;

  /// El prompt pasó pero no había credenciales guardadas: hay que volver a
  /// activar el acceso rápido.
  final bool needsSetup;

  const BiometricAuthResult._({
    this.email,
    this.password,
    this.error,
    this.cancelled = false,
    this.needsSetup = false,
  });

  bool get success => email != null && password != null;

  factory BiometricAuthResult.ok(String email, String password) =>
      BiometricAuthResult._(email: email, password: password);
  factory BiometricAuthResult.cancelled() =>
      const BiometricAuthResult._(cancelled: true);
  factory BiometricAuthResult.failure(String msg) =>
      BiometricAuthResult._(error: msg);
  factory BiometricAuthResult.setupRequired(String msg) =>
      BiometricAuthResult._(error: msg, needsSetup: true);
}

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

  bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // Verifica si el dispositivo soporta biometría y tiene alguna enrollada
  // (usado en login para mostrar el botón de huella)
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

  // Verifica solo si el hardware biométrico existe en el dispositivo
  // (usado en ajustes: muestra la opción aunque no haya huellas registradas aún)
  Future<bool> isHardwarePresent() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (supported) return true;
      // Fallback: algunos dispositivos reportan false en isDeviceSupported
      // pero sí tienen sensor; canCheckBiometrics lo detecta correctamente
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Qué sensor ofrece este teléfono, para nombrarlo como el usuario lo conoce.
  ///
  /// En Android el plugin ya no devuelve `fingerprint` en versiones recientes:
  /// reporta `strong`/`weak`, que cubren huella, rostro e iris sin distinguir.
  /// Por eso `face` solo se toma como rostro cuando viene explícito, y todo lo
  /// demás cae en huella, que es el sensor que trae la inmensa mayoría.
  Future<BiometricKind> detectKind() async {
    if (kIsWeb) return BiometricKind.generic;
    try {
      final types = await _auth.getAvailableBiometrics();
      if (_isApple) {
        if (types.contains(BiometricType.face)) return BiometricKind.faceId;
        if (types.contains(BiometricType.fingerprint)) {
          return BiometricKind.touchId;
        }
        return BiometricKind.generic;
      }
      if (types.contains(BiometricType.face)) return BiometricKind.faceAndroid;
      if (types.isNotEmpty) return BiometricKind.fingerprint;
      // Sin nada enrollado todavía: en Android el sensor casi siempre es huella
      return BiometricKind.fingerprint;
    } catch (_) {
      return BiometricKind.generic;
    }
  }

  // Devuelve el email guardado (si existe) para pre-llenar el diálogo de configuración
  Future<String?> getStoredEmail() async {
    if (kIsWeb) return null;
    try {
      return await _storage.read(key: _keyEmail);
    } catch (_) {
      return null;
    }
  }

  // Verifica si el usuario activó el login biométrico
  Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    try {
      final val = await _storage.read(key: _keyEnabled);
      if (val != 'true') return false;
      // El flag sin credenciales detrás es basura: alguna limpieza previa pudo
      // dejarlo suelto y el login mostraría un botón que no puede entrar.
      final email = await _storage.read(key: _keyEmail);
      final password = await _storage.read(key: _keyPassword);
      return email != null && password != null;
    } catch (_) {
      return false;
    }
  }

  // Guarda credenciales y activa biometría
  Future<void> saveCredentials(String email, String password) async {
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  /// Desactiva y borra SOLO las credenciales biométricas.
  ///
  /// Antes usaba `deleteAll()`, que vacía el almacén entero de
  /// flutter_secure_storage — el mismo donde AuthService guarda la sesión
  /// (`session_tenant_id`, `session_firestore_uid`…). Desactivar la huella
  /// borraba de paso la sesión persistida.
  Future<void> clearCredentials() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyEmail),
        _storage.delete(key: _keyPassword),
        _storage.delete(key: _keyEnabled),
      ]);
    } catch (_) {}
  }

  /// Lanza el prompt de huella/Face ID y devuelve las credenciales si pasa.
  ///
  /// [reason] permite ajustar el texto según el momento (ingresar vs. activar).
  Future<BiometricAuthResult> authenticate({String? reason}) async {
    final kind = await detectKind();
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason ?? 'Verifica tu identidad para ingresar',
        options: const AuthenticationOptions(
          biometricOnly: false, // permite PIN del sistema como fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok) return BiometricAuthResult.cancelled();

      final email = await _storage.read(key: _keyEmail);
      final password = await _storage.read(key: _keyPassword);
      if (email == null || password == null) {
        return BiometricAuthResult.setupRequired(
          'No hay una cuenta vinculada. Ingresa con tu correo y contraseña '
          'para volver a activar el acceso rápido.',
        );
      }
      return BiometricAuthResult.ok(email, password);
    } on PlatformException catch (e) {
      return BiometricAuthResult.failure(_mapError(e, kind));
    } catch (_) {
      return BiometricAuthResult.failure(
        'No se pudo verificar tu ${kind.label}. Intenta de nuevo.',
      );
    }
  }

  /// Traduce los códigos de local_auth a algo que el usuario pueda accionar.
  /// Sin esto cualquier fallo real salía como silencio: el botón se tocaba y
  /// no pasaba absolutamente nada.
  String _mapError(PlatformException e, BiometricKind kind) {
    switch (e.code) {
      case auth_error.notEnrolled:
        return 'Este dispositivo no tiene ${kind.label} registrada. '
            '${kind.enrollHint}';
      case auth_error.notAvailable:
        return 'La ${kind.label} no está disponible en este dispositivo.';
      case auth_error.passcodeNotSet:
        return 'Configura primero un PIN o código de bloqueo en tu '
            'dispositivo para poder usar la ${kind.label}.';
      case auth_error.lockedOut:
        return 'Demasiados intentos fallidos. Espera unos segundos o '
            'ingresa con tu contraseña.';
      case auth_error.permanentlyLockedOut:
        return 'La ${kind.label} quedó bloqueada. Desbloquea tu dispositivo '
            'con tu PIN y vuelve a intentar.';
      default:
        return 'No se pudo verificar tu ${kind.label}. '
            'Ingresa con tu correo y contraseña.';
    }
  }
}
