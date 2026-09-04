import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/biometric_service.dart';

/// Candado sobre el almacén que BiometricService comparte con AuthService.
///
/// Los dos servicios usan flutter_secure_storage con las mismas opciones, o
/// sea el MISMO almacén. `clearCredentials()` usaba `deleteAll()`, así que
/// apagar la huella borraba de paso la sesión persistida
/// (`session_tenant_id`, `session_firestore_uid`…) y el usuario quedaba
/// deslogueado sin entender por qué. Si alguien vuelve a poner deleteAll,
/// estos tests fallan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late Map<String, String> almacen;
  late List<String> llamadas;

  setUp(() {
    almacen = {};
    llamadas = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      llamadas.add(call.method);
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      final key = args['key'] as String?;

      switch (call.method) {
        case 'write':
          almacen[key!] = args['value'] as String;
          return null;
        case 'read':
          return almacen[key];
        case 'delete':
          almacen.remove(key);
          return null;
        case 'deleteAll':
          almacen.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(almacen);
        case 'containsKey':
          return almacen.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Deja el almacén como queda tras un login normal: sesión de AuthService
  /// más credenciales biométricas.
  Future<void> sembrarSesionYHuella() async {
    almacen['session_tenant_id'] = 'tenant_jalapeno';
    almacen['session_firestore_uid'] = 'uid_123';
    almacen['session_location_id'] = 'sucursal_santa_rosalia';
    almacen['session_email'] = 'ana@resto.com';
    await BiometricService().saveCredentials('ana@resto.com', 'secreta');
  }

  test('apagar la huella no borra la sesión de AuthService', () async {
    await sembrarSesionYHuella();

    await BiometricService().clearCredentials();

    // Lo biométrico se fue…
    expect(almacen.containsKey('bio_email'), isFalse);
    expect(almacen.containsKey('bio_password'), isFalse);
    expect(almacen.containsKey('bio_enabled'), isFalse);
    // …y la sesión sigue intacta.
    expect(almacen['session_tenant_id'], 'tenant_jalapeno');
    expect(almacen['session_firestore_uid'], 'uid_123');
    expect(almacen['session_location_id'], 'sucursal_santa_rosalia');
    expect(almacen['session_email'], 'ana@resto.com');
  });

  test('clearCredentials nunca llama deleteAll', () async {
    await sembrarSesionYHuella();
    llamadas.clear();

    await BiometricService().clearCredentials();

    expect(llamadas, isNot(contains('deleteAll')),
        reason: 'deleteAll vacía el almacén compartido con AuthService');
    expect(llamadas.where((m) => m == 'delete').length, 3);
  });

  test('guardar credenciales las deja legibles', () async {
    await BiometricService().saveCredentials('ana@resto.com', 'secreta');

    expect(await BiometricService().isEnabled(), isTrue);
    expect(await BiometricService().getStoredEmail(), 'ana@resto.com');
  });

  test('el flag encendido sin credenciales detrás no cuenta como activado',
      () async {
    // Estado que dejaba una limpieza a medias: el login mostraba un botón
    // que al tocarlo no podía entrar a ningún lado.
    almacen['bio_enabled'] = 'true';

    expect(await BiometricService().isEnabled(), isFalse);
  });

  test('sin nada guardado la biometría está apagada', () async {
    expect(await BiometricService().isEnabled(), isFalse);
    expect(await BiometricService().getStoredEmail(), isNull);
  });

  test('clearCredentials sobre un almacén vacío no lanza', () async {
    await expectLater(BiometricService().clearCredentials(), completes);
  });
}
