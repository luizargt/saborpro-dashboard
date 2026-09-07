import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/screens/auth/login_screen.dart';

/// Cómo se comporta el botón biométrico del login.
///
/// Dos cosas que el usuario reportó desde TestFlight y que aquí quedan
/// clavadas: la app pedía Face ID sola al abrir, sin dar tiempo a nada, y el
/// correo vinculado vivía en un letrero fijo debajo del botón, imposible de
/// cambiar por otra cuenta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  // En un test no se registra ningún plugin nativo, así que local_auth cae en
  // su implementación por defecto, que sí habla por este canal.
  const authChannel = MethodChannel('plugins.flutter.io/local_auth');

  late Map<String, String> almacen;
  late int prompts;

  setUp(() {
    almacen = {};
    prompts = 0;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(storageChannel, (call) async {
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
        case 'readAll':
          return Map<String, String>.from(almacen);
        case 'containsKey':
          return almacen.containsKey(key);
        default:
          return null;
      }
    });

    messenger.setMockMethodCallHandler(authChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
          return true;
        case 'getAvailableBiometrics':
          return <String>['fingerprint'];
        case 'authenticate':
          prompts++;
          // Cancelado: así el test nunca llega a AuthService, que necesitaría
          // Firebase levantado.
          return false;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storageChannel, null);
    messenger.setMockMethodCallHandler(authChannel, null);
  });

  void vincular(String email, String password) {
    almacen['bio_accounts'] = jsonEncode({email: password});
    almacen['bio_last_email'] = email;
  }

  /// Pinta el login en un teléfono angosto real (360dp).
  Future<void> abrirLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('al abrir no pide la biometría sola', (tester) async {
    vincular('ana@resto.com', 'secreta');

    await abrirLogin(tester);

    expect(prompts, 0,
        reason: 'abrir la app no puede lanzar Face ID sin que nadie lo pida');
  });

  testWidgets('el correo recordado queda escrito en el campo, editable',
      (tester) async {
    vincular('ana@resto.com', 'secreta');

    await abrirLogin(tester);

    final campo = find.widgetWithText(TextFormField, 'ana@resto.com');
    expect(campo, findsOneWidget,
        reason: 'el correo va en el campo de arriba, no en un letrero fijo');
    // Y se puede cambiar por otro: eso es lo que no dejaba hacer el letrero.
    await tester.enterText(campo, 'luis@otro.com');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'luis@otro.com'), findsOneWidget);
  });

  testWidgets('con la cuenta vinculada, el botón la usa al tocarlo',
      (tester) async {
    vincular('ana@resto.com', 'secreta');

    await abrirLogin(tester);
    expect(find.text('Ingresar con tu huella'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fingerprint));
    await tester.pumpAndSettle();

    expect(prompts, 1);
  });

  testWidgets('si se cambia el correo por uno sin vincular, el botón lo dice',
      (tester) async {
    vincular('ana@resto.com', 'secreta');

    await abrirLogin(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'ana@resto.com'), 'luis@otro.com');
    await tester.pumpAndSettle();

    expect(find.text('Activar acceso con huella'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fingerprint));
    await tester.pumpAndSettle();

    // Ni se enciende el sensor: pedirle la cara para después decirle que esa
    // cuenta no está vinculada es el peor orden posible.
    expect(prompts, 0);
    expect(find.text('Activa el acceso rápido'), findsOneWidget);
  });

  testWidgets('sin correo escrito, el botón pide el correo en vez de fallar',
      (tester) async {
    await abrirLogin(tester);

    await tester.tap(find.byIcon(Icons.fingerprint));
    await tester.pumpAndSettle();

    expect(prompts, 0);
    expect(
      find.text('Escribe arriba el correo de la cuenta a la que quieres '
          'entrar.'),
      findsOneWidget,
    );
  });
}
