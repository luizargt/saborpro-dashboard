import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/biometric_service.dart';
import 'package:saborpro_reports/presentation/screens/auth/biometric_login_button.dart';

/// Envuelve el botón en un teléfono angosto real (360dp, el ancho del Android
/// de gama baja que usan los clientes) para cazar desbordes de layout.
Future<void> _pump(
  WidgetTester tester, {
  required BiometricKind kind,
  required bool enabled,
  String? account,
  VoidCallback? onTap,
}) async {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: BiometricLoginButton(
            kind: kind,
            enabled: enabled,
            account: account,
            onTap: onTap,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('BiometricKind — cómo se le habla al usuario', () {
    test('en iPhone con Face ID nunca se le pide una huella', () {
      expect(BiometricKind.faceId.label, 'Face ID');
      expect(BiometricKind.faceId.actionLabel, 'Ingresar con Face ID');
      expect(BiometricKind.faceId.settingsLabel, 'Inicio con Face ID');
      // El instructivo de registro tiene que mandarlo a Ajustes de iOS, no a
      // "Configuración → Seguridad", que es un menú que su teléfono no tiene.
      expect(BiometricKind.faceId.enrollHint, contains('Ajustes'));
      expect(BiometricKind.faceId.enrollHint, isNot(contains('Configuración')));
    });

    test('en Android el instructivo apunta al menú de Android', () {
      expect(BiometricKind.fingerprint.label, 'huella');
      expect(BiometricKind.fingerprint.enrollHint, contains('Configuración'));
      expect(BiometricKind.faceAndroid.label, 'rostro');
      expect(BiometricKind.faceAndroid.enrollHint, contains('Configuración'));
    });

    test('Touch ID se distingue de Face ID', () {
      expect(BiometricKind.touchId.label, 'Touch ID');
      expect(BiometricKind.touchId.actionLabel, 'Ingresar con Touch ID');
    });

    test('todos los tipos tienen texto: ninguno cae en cadena vacía', () {
      for (final kind in BiometricKind.values) {
        expect(kind.label, isNotEmpty, reason: '$kind sin label');
        expect(kind.actionLabel, isNotEmpty, reason: '$kind sin actionLabel');
        expect(kind.settingsLabel, isNotEmpty,
            reason: '$kind sin settingsLabel');
        expect(kind.enrollHint, isNotEmpty, reason: '$kind sin enrollHint');
      }
    });
  });

  group('BiometricAuthResult — cancelar no es fallar', () {
    test('cancelar no trae error: no merece un letrero rojo', () {
      final r = BiometricAuthResult.cancelled();
      expect(r.success, isFalse);
      expect(r.cancelled, isTrue);
      expect(r.error, isNull);
    });

    test('un fallo real sí trae mensaje, para no quedarse mudo', () {
      final r = BiometricAuthResult.failure('Sensor bloqueado');
      expect(r.success, isFalse);
      expect(r.cancelled, isFalse);
      expect(r.error, 'Sensor bloqueado');
    });

    test('sin credenciales guardadas pide reconfigurar, no reintentar', () {
      final r = BiometricAuthResult.setupRequired('Vuelve a activarlo');
      expect(r.needsSetup, isTrue);
      expect(r.success, isFalse);
      expect(r.error, isNotNull);
    });

    test('éxito trae las dos credenciales, nunca una sola', () {
      final r = BiometricAuthResult.ok('ana@resto.com', 'secreta');
      expect(r.success, isTrue);
      expect(r.email, 'ana@resto.com');
      expect(r.password, 'secreta');
      expect(r.error, isNull);
      expect(r.cancelled, isFalse);
    });
  });

  group('BiometricLoginButton a 360dp', () {
    testWidgets('activado invita a entrar y dice con qué cuenta',
        (tester) async {
      await _pump(
        tester,
        kind: BiometricKind.fingerprint,
        enabled: true,
        account: 'ana@resto.com',
      );

      expect(find.text('Ingresar con tu huella'), findsOneWidget);
      expect(find.text('ana@resto.com'), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('apagado sigue visible e invita a activarlo', (tester) async {
      // Este es el caso que el usuario nunca podía ver: antes el botón se
      // escondía si no estaba activado, y cerrar sesión lo desactivaba.
      await _pump(tester, kind: BiometricKind.fingerprint, enabled: false);

      expect(find.text('Activar acceso con huella'), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('apagado no filtra el correo de la cuenta vinculada',
        (tester) async {
      await _pump(
        tester,
        kind: BiometricKind.fingerprint,
        enabled: false,
        account: 'ana@resto.com',
      );

      expect(find.text('ana@resto.com'), findsNothing);
    });

    testWidgets('en Face ID cambia ícono y texto', (tester) async {
      await _pump(tester, kind: BiometricKind.faceId, enabled: true);

      expect(find.text('Ingresar con Face ID'), findsOneWidget);
      expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('un correo largo se recorta en vez de desbordar',
        (tester) async {
      await _pump(
        tester,
        kind: BiometricKind.faceId,
        enabled: true,
        account: 'administrador.general.sucursal@restaurantedeprueba.com.gt',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('sin cuenta vinculada no pinta una línea vacía',
        (tester) async {
      await _pump(tester, kind: BiometricKind.fingerprint, enabled: true);
      expect(find.text(''), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('responde al toque', (tester) async {
      var toques = 0;
      await _pump(
        tester,
        kind: BiometricKind.fingerprint,
        enabled: false,
        onTap: () => toques++,
      );

      await tester.tap(find.byIcon(Icons.fingerprint));
      expect(toques, 1);
    });

    testWidgets('sin onTap el toque no explota', (tester) async {
      await _pump(tester, kind: BiometricKind.fingerprint, enabled: true);
      await tester.tap(find.byIcon(Icons.fingerprint));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cada tipo de sensor renderiza a 360dp', (tester) async {
      for (final kind in BiometricKind.values) {
        await _pump(tester, kind: kind, enabled: true, account: 'a@b.com');
        expect(tester.takeException(), isNull, reason: '$kind desborda');
      }
    });
  });
}
