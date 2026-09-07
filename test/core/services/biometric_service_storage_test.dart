import 'dart:convert';

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

  Map<String, String> cuentasGuardadas() =>
      (jsonDecode(almacen['bio_accounts']!) as Map).cast<String, String>();

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
    expect(almacen.containsKey('bio_accounts'), isFalse);
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
    // Una por clave propia: el mapa de cuentas y las tres del esquema viejo.
    expect(llamadas.where((m) => m == 'delete').length, 4);
  });

  test('apagar la huella conserva el último correo', () async {
    // El correo recordado no es una credencial: es lo que deja el campo del
    // login escrito para que el usuario solo teclee su contraseña.
    await sembrarSesionYHuella();

    await BiometricService().clearCredentials();

    expect(await BiometricService().isEnabled(), isFalse);
    expect(await BiometricService().lastEmail(), 'ana@resto.com');
  });

  test('guardar credenciales las deja legibles', () async {
    await BiometricService().saveCredentials('ana@resto.com', 'secreta');

    expect(await BiometricService().isEnabled(), isTrue);
    expect(await BiometricService().isLinked('ana@resto.com'), isTrue);
    expect(await BiometricService().getStoredEmail(), 'ana@resto.com');
    expect(await BiometricService().lastEmail(), 'ana@resto.com');
  });

  test('el correo entra siempre en minúsculas y sin espacios', () async {
    // Si no, "Ana@Resto.com" y "ana@resto.com" serían dos cuentas distintas y
    // el botón aparecería apagado según cómo se tecleó el correo.
    await BiometricService().saveCredentials('  Ana@Resto.com ', 'secreta');

    expect(await BiometricService().isLinked('ana@resto.com'), isTrue);
    expect(await BiometricService().isLinked('ANA@resto.com'), isTrue);
    expect(cuentasGuardadas().keys, ['ana@resto.com']);
  });

  test('dos cuentas conviven: un gerente con dos restaurantes', () async {
    await BiometricService().saveCredentials('ana@resto.com', 'secreta');
    await BiometricService().saveCredentials('luis@otro.com', 'otra');

    expect(await BiometricService().linkedEmails(),
        containsAll(['ana@resto.com', 'luis@otro.com']));
    // El último usado queda al final: es el que ofrece el bloqueo de pantalla,
    // que no tiene ningún correo escrito de dónde escoger.
    expect(await BiometricService().getStoredEmail(), 'luis@otro.com');
  });

  test('desvincular una cuenta deja viva a la otra', () async {
    await BiometricService().saveCredentials('ana@resto.com', 'secreta');
    await BiometricService().saveCredentials('luis@otro.com', 'otra');

    await BiometricService().unlink('luis@otro.com');

    expect(await BiometricService().isLinked('luis@otro.com'), isFalse);
    expect(await BiometricService().isLinked('ana@resto.com'), isTrue);
    expect(await BiometricService().isEnabled(), isTrue);
  });

  test('se guardan como mucho 5 cuentas y se va la más vieja', () async {
    for (var i = 1; i <= 6; i++) {
      await BiometricService().saveCredentials('user$i@resto.com', 'pw$i');
    }

    final vinculadas = await BiometricService().linkedEmails();
    expect(vinculadas.length, 5);
    expect(vinculadas, isNot(contains('user1@resto.com')));
    expect(vinculadas, contains('user6@resto.com'));
  });

  test('quien ya tenía la huella activada no la pierde al actualizar',
      () async {
    // Esquema viejo: una sola cuenta en tres claves sueltas.
    almacen['bio_email'] = 'ana@resto.com';
    almacen['bio_password'] = 'secreta';
    almacen['bio_enabled'] = 'true';

    expect(await BiometricService().isEnabled(), isTrue);
    expect(await BiometricService().isLinked('ana@resto.com'), isTrue);
    expect(await BiometricService().lastEmail(), 'ana@resto.com');
    // Y las claves viejas ya no quedan tiradas con la contraseña adentro.
    expect(almacen.containsKey('bio_password'), isFalse);
    expect(almacen.containsKey('bio_email'), isFalse);
    expect(almacen.containsKey('bio_enabled'), isFalse);
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
    expect(await BiometricService().lastEmail(), isNull);
    expect(await BiometricService().linkedEmails(), isEmpty);
  });

  test('un mapa de cuentas corrupto no tumba el login', () async {
    almacen['bio_accounts'] = 'esto no es json';

    expect(await BiometricService().isEnabled(), isFalse);
    expect(await BiometricService().linkedEmails(), isEmpty);
  });

  test('clearCredentials sobre un almacén vacío no lanza', () async {
    await expectLater(BiometricService().clearCredentials(), completes);
  });

  test('unlink de una cuenta que no está no lanza ni escribe', () async {
    await expectLater(BiometricService().unlink('nadie@resto.com'), completes);
    expect(almacen.containsKey('bio_accounts'), isFalse);
  });
}
