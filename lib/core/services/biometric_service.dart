import 'dart:convert';

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

  /// Cuentas vinculadas en este teléfono: `{correo: contraseña}`, en orden de
  /// uso (la última usada al final). Son varias a propósito: un gerente con
  /// dos restaurantes cambia el correo del login y entra con la cara a
  /// cualquiera de los dos, sin volver a teclear contraseñas.
  static const _keyAccounts = 'bio_accounts';

  /// Último correo con el que se entró, esté vinculado o no. Solo sirve para
  /// pre-llenar el campo del login; no es una credencial.
  static const _keyLastEmail = 'bio_last_email';

  // Esquema viejo (una sola cuenta). Se migra al mapa y se borra.
  static const _keyEmail = 'bio_email';
  static const _keyPassword = 'bio_password';
  static const _keyEnabled = 'bio_enabled';

  /// Tope de cuentas guardadas. Sin tope, cada cuenta que alguien probó una
  /// vez deja su contraseña en el teléfono para siempre.
  static const _maxAccounts = 5;

  /// El correo es la llave del mapa, así que entra siempre igual: AuthService
  /// también hace `trim().toLowerCase()` antes de buscar en Firestore, y sin
  /// esto "Ana@Resto.com" y "ana@resto.com" serían dos cuentas distintas.
  static String normalizeEmail(String email) => email.trim().toLowerCase();

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

  Future<Map<String, String>> _readAccounts() async {
    if (kIsWeb) return {};
    try {
      final raw = await _storage.read(key: _keyAccounts);
      if (raw == null || raw.isEmpty) return _migrateLegacy();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final accounts = <String, String>{};
      decoded.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          accounts[normalizeEmail(k.toString())] = v;
        }
      });
      return accounts;
    } catch (_) {
      return {};
    }
  }

  /// Pasa la única cuenta del esquema viejo al mapa nuevo.
  ///
  /// Sin esto, quien ya tenía Face ID activado lo perdería al actualizar la
  /// app: el botón aparecería apagado y tendría que escribir su contraseña sin
  /// entender por qué.
  Future<Map<String, String>> _migrateLegacy() async {
    final email = await _storage.read(key: _keyEmail);
    final password = await _storage.read(key: _keyPassword);
    final enabled = await _storage.read(key: _keyEnabled);
    if (email == null && password == null && enabled == null) return {};

    final migrated = <String, String>{};
    if (enabled == 'true' && email != null && password != null) {
      migrated[normalizeEmail(email)] = password;
      await _storage.write(key: _keyAccounts, value: jsonEncode(migrated));
      final last = await _storage.read(key: _keyLastEmail);
      if (last == null || last.isEmpty) {
        await _storage.write(key: _keyLastEmail, value: normalizeEmail(email));
      }
    }
    // Solo las claves propias: nunca deleteAll sobre este almacén, que es el
    // mismo donde AuthService guarda la sesión.
    await Future.wait([
      _storage.delete(key: _keyEmail),
      _storage.delete(key: _keyPassword),
      _storage.delete(key: _keyEnabled),
    ]);
    return migrated;
  }

  Future<void> _writeAccounts(Map<String, String> accounts) async {
    if (accounts.isEmpty) {
      await _storage.delete(key: _keyAccounts);
      return;
    }
    await _storage.write(key: _keyAccounts, value: jsonEncode(accounts));
  }

  /// Correos que pueden entrar con biometría en este teléfono.
  Future<List<String>> linkedEmails() async =>
      (await _readAccounts()).keys.toList();

  /// Si esta cuenta puntual tiene acceso rápido vinculado.
  Future<bool> isLinked(String email) async =>
      (await _readAccounts()).containsKey(normalizeEmail(email));

  /// Correo de la última cuenta vinculada. Lo usa el diálogo de ajustes para
  /// pre-llenar el campo cuando la sesión se restauró sin correo en memoria.
  Future<String?> getStoredEmail() async {
    final accounts = await _readAccounts();
    return accounts.isEmpty ? null : accounts.keys.last;
  }

  /// Último correo con el que se entró, para dejarlo escrito en el login.
  Future<String?> lastEmail() async {
    if (kIsWeb) return null;
    try {
      final stored = await _storage.read(key: _keyLastEmail);
      if (stored != null && stored.isNotEmpty) return stored;
      // Instalación anterior a esta clave: la cuenta vinculada hace de último
      // correo usado.
      return await getStoredEmail();
    } catch (_) {
      return null;
    }
  }

  /// Recuerda el correo para la próxima vez, sin guardar la contraseña.
  Future<void> rememberEmail(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) return;
    try {
      await _storage.write(key: _keyLastEmail, value: normalized);
    } catch (_) {}
  }

  // Verifica si hay alguna cuenta con acceso biométrico en este dispositivo
  Future<bool> isEnabled() async => (await _readAccounts()).isNotEmpty;

  /// Vincula (o revincula) una cuenta al acceso biométrico.
  Future<void> saveCredentials(String email, String password) async {
    final key = normalizeEmail(email);
    final accounts = await _readAccounts();
    // Quitar y volver a poner deja la cuenta al final: el mapa queda en orden
    // de uso y el recorte de abajo saca siempre la más vieja.
    accounts.remove(key);
    accounts[key] = password;
    while (accounts.length > _maxAccounts) {
      accounts.remove(accounts.keys.first);
    }
    await _writeAccounts(accounts);
    await rememberEmail(key);
  }

  /// Desvincula UNA cuenta y deja las demás intactas.
  ///
  /// Es lo que corresponde cuando falla una cuenta puntual (contraseña
  /// cambiada, activación cancelada): borrar todas castigaría a las otras.
  Future<void> unlink(String email) async {
    try {
      final accounts = await _readAccounts();
      if (accounts.remove(normalizeEmail(email)) == null) return;
      await _writeAccounts(accounts);
    } catch (_) {}
  }

  /// Apaga el acceso rápido: desvincula TODAS las cuentas.
  ///
  /// Antes usaba `deleteAll()`, que vacía el almacén entero de
  /// flutter_secure_storage — el mismo donde AuthService guarda la sesión
  /// (`session_tenant_id`, `session_firestore_uid`…). Desactivar la huella
  /// borraba de paso la sesión persistida. El último correo usado sí se
  /// conserva: es lo que deja el campo del login listo para escribir la
  /// contraseña.
  Future<void> clearCredentials() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyAccounts),
        _storage.delete(key: _keyEmail),
        _storage.delete(key: _keyPassword),
        _storage.delete(key: _keyEnabled),
      ]);
    } catch (_) {}
  }

  /// Lanza el prompt de huella/Face ID y devuelve las credenciales si pasa.
  ///
  /// [reason] permite ajustar el texto según el momento (ingresar vs. activar).
  /// [email] elige a qué cuenta entrar; sin él se usa la última vinculada, que
  /// es lo que necesita el bloqueo de pantalla (ahí la sesión ya está abierta
  /// y no hay ningún correo que escoger).
  Future<BiometricAuthResult> authenticate({
    String? reason,
    String? email,
  }) async {
    final kind = await detectKind();
    final accounts = await _readAccounts();
    final target = email == null ? '' : normalizeEmail(email);

    // La cuenta se comprueba ANTES de encender el sensor: hacer que el usuario
    // ponga la cara para decirle después que ese correo no está vinculado es
    // el peor orden posible.
    final String key;
    if (target.isNotEmpty) {
      if (!accounts.containsKey(target)) {
        return BiometricAuthResult.setupRequired(
          'El acceso rápido no está vinculado a $target. Ingresa una vez con '
          'su contraseña y podrás activarlo para esta cuenta.',
        );
      }
      key = target;
    } else {
      if (accounts.isEmpty) {
        return BiometricAuthResult.setupRequired(
          'No hay una cuenta vinculada. Ingresa con tu correo y contraseña '
          'para volver a activar el acceso rápido.',
        );
      }
      key = accounts.keys.last;
    }

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

      // Se relee después del prompt: entre que se abrió y que pasó, la cuenta
      // pudo desvincularse desde otra pantalla.
      final fresh = await _readAccounts();
      final password = fresh[key];
      if (password == null) {
        return BiometricAuthResult.setupRequired(
          'No hay una cuenta vinculada. Ingresa con tu correo y contraseña '
          'para volver a activar el acceso rápido.',
        );
      }
      return BiometricAuthResult.ok(key, password);
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
