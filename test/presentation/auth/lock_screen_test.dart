import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/biometric_service.dart';
import 'package:saborpro_reports/presentation/screens/auth/lock_screen.dart';

/// La pantalla de bloqueo a 360dp, con el sensor simulado.
///
/// El resultado del sensor se inyecta porque en un test los plugins nativos no
/// existen y sus Futures nunca resuelven bajo el reloj falso de flutter_test.
Future<void> _pump(
  WidgetTester tester, {
  required BiometricAuthResult Function() responde,
  String? accountLabel,
  BiometricKind kind = BiometricKind.fingerprint,
  VoidCallback? onUnlocked,
  VoidCallback? onUsePassword,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: LockScreen(
        accountLabel: accountLabel,
        kind: kind,
        authenticator: ({String? reason}) async => responde(),
        onUnlocked: onUnlocked ?? () {},
        onUsePassword: onUsePassword ?? () {},
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Cuando la verificación sale bien la pantalla queda mostrando el spinner
    // de "Verificando…" hasta que el gate la desmonta. Ese giro es infinito,
    // así que pumpAndSettle nunca convergería.
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  BiometricAuthResult exito() =>
      BiometricAuthResult.ok('ana@resto.com', 'secreta');
  BiometricAuthResult fallo() =>
      BiometricAuthResult.failure('Sensor bloqueado');
  BiometricAuthResult cancelado() => BiometricAuthResult.cancelled();

  testWidgets('la huella correcta destapa la app', (tester) async {
    var desbloqueos = 0;
    await _pump(
      tester,
      responde: exito,
      onUnlocked: () => desbloqueos++,
      settle: false,
    );

    expect(desbloqueos, 1);
  });

  testWidgets('dice que está bloqueado y a quién pertenece la sesión',
      (tester) async {
    await _pump(tester, responde: fallo, accountLabel: 'ana@resto.com');

    expect(find.text('Sabor Manager está bloqueado'), findsOneWidget);
    expect(find.text('ana@resto.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin etiqueta de cuenta no pinta una línea vacía',
      (tester) async {
    await _pump(tester, responde: fallo);

    expect(find.text('Sabor Manager está bloqueado'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('un fallo del sensor se explica, no se queda mudo',
      (tester) async {
    await _pump(tester, responde: fallo);

    expect(find.text('Sensor bloqueado'), findsOneWidget);
  });

  testWidgets('cancelar no pinta letrero rojo, solo deja reintentar',
      (tester) async {
    await _pump(tester, responde: cancelado);

    expect(find.text('Sensor bloqueado'), findsNothing);
    expect(find.textContaining('Toca para'), findsOneWidget);
  });

  testWidgets('la salida por contraseña está desde el primer momento',
      (tester) async {
    // Sin ella, un sensor roto deja al gerente fuera de sus propios reportes.
    var salidas = 0;
    await _pump(tester, responde: fallo, onUsePassword: () => salidas++);

    await tester.tap(find.text('Ingresar con contraseña'));
    await tester.pump();
    expect(salidas, 1);
  });

  testWidgets('tras varios fallos la salida se vuelve botón, no enlace',
      (tester) async {
    await _pump(tester, responde: fallo);

    // Un fallo (el del montaje): todavía es un enlace discreto.
    expect(find.widgetWithText(ElevatedButton, 'Ingresar con contraseña'),
        findsNothing);

    // El usuario reintenta y vuelve a fallar: ahora se le ofrece la salida.
    await tester.tap(find.textContaining('Toca para'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Ingresar con contraseña'),
        findsOneWidget);
  });

  testWidgets('credenciales perdidas mandan directo al login, sin insistir',
      (tester) async {
    // Insistir con el sensor no llevaría a ningún lado: no hay contra qué
    // validar.
    var salidas = 0;
    await _pump(
      tester,
      responde: () => BiometricAuthResult.setupRequired('Volvé a activarlo'),
      onUsePassword: () => salidas++,
      settle: false,
    );

    expect(salidas, 1);
  });

  testWidgets('en Face ID el ícono y el texto cambian', (tester) async {
    await _pump(tester, responde: fallo, kind: BiometricKind.faceId);

    expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
    expect(find.textContaining('face id'.toLowerCase()), findsOneWidget);
  });

  testWidgets('un correo largo no desborda a 360dp', (tester) async {
    await _pump(
      tester,
      responde: fallo,
      accountLabel: 'administrador.general.sucursal@restaurantedeprueba.com.gt',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapa por completo lo que haya debajo', (tester) async {
    // Si dejara ver el dashboard, bloquear no serviría de nada.
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const Scaffold(body: Center(child: Text('VENTAS DEL DIA Q12,450'))),
            LockScreen(
              kind: BiometricKind.fingerprint,
              authenticator: ({String? reason}) async =>
                  BiometricAuthResult.failure('x'),
              onUnlocked: () {},
              onUsePassword: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lock = find.descendant(
      of: find.byType(LockScreen),
      matching: find.byType(Scaffold),
    );
    final size = tester.getSize(lock);
    expect(size.width, 360);
    expect(size.height, 720);
    expect(tester.widget<Scaffold>(lock).backgroundColor,
        const Color(0xFF0F172A));
  });

  testWidgets('mientras verifica no dispara una segunda petición',
      (tester) async {
    // Tocar dos veces seguidas encadenaría dos prompts del sistema.
    var peticiones = 0;
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          kind: BiometricKind.fingerprint,
          authenticator: ({String? reason}) async {
            peticiones++;
            await Future<void>.delayed(const Duration(seconds: 2));
            return BiometricAuthResult.failure('lento');
          },
          onUnlocked: () {},
          onUsePassword: () {},
        ),
      ),
    );
    await tester.pump();
    expect(peticiones, 1);

    // Toque extra mientras la primera sigue en vuelo.
    await tester.tap(find.byType(GestureDetector).first, warnIfMissed: false);
    await tester.pump();
    expect(peticiones, 1);

    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
