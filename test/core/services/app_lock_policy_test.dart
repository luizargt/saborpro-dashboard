import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/app_lock_policy.dart';

/// La regla que decide cuándo Sabor Manager vuelve a pedir la huella.
///
/// Se prueba aparte porque los dos errores posibles duelen distinto: bloquear
/// de menos deja las ventas del día a la vista de cualquiera que agarre el
/// teléfono; bloquear de más enseña al gerente a apagar la función.
void main() {
  final ahora = DateTime(2026, 9, 3, 14, 30);

  group('arranque en frío', () {
    test('con sesión y biometría activada pide verificación', () {
      expect(
        AppLockPolicy.shouldLockOnStart(loggedIn: true, biometricEnabled: true),
        isTrue,
      );
    });

    test('sin biometría activada no bloquea: dejaría al usuario encerrado', () {
      // Quien nunca activó la huella no tiene con qué desbloquear.
      expect(
        AppLockPolicy.shouldLockOnStart(
            loggedIn: true, biometricEnabled: false),
        isFalse,
      );
    });

    test('sin sesión no bloquea: el login ya es la puerta', () {
      expect(
        AppLockPolicy.shouldLockOnStart(
            loggedIn: false, biometricEnabled: true),
        isFalse,
      );
    });
  });

  group('vuelta del segundo plano', () {
    bool alVolver({
      required Duration fuera,
      bool loggedIn = true,
      bool biometricEnabled = true,
    }) =>
        AppLockPolicy.shouldLockOnResume(
          loggedIn: loggedIn,
          biometricEnabled: biometricEnabled,
          backgroundedAt: ahora.subtract(fuera),
          now: ahora,
        );

    test('salir a leer un WhatsApp y volver no cuesta una verificación', () {
      expect(alVolver(fuera: const Duration(seconds: 5)), isFalse);
      expect(alVolver(fuera: const Duration(seconds: 29)), isFalse);
    });

    test('pasado el margen sí pide verificación', () {
      expect(alVolver(fuera: const Duration(seconds: 31)), isTrue);
      expect(alVolver(fuera: const Duration(minutes: 10)), isTrue);
      expect(alVolver(fuera: const Duration(hours: 8)), isTrue);
    });

    test('justo en el límite bloquea: el borde cae del lado seguro', () {
      expect(alVolver(fuera: AppLockPolicy.graceWindow), isTrue);
    });

    test('sin biometría activada nunca bloquea, por más que estuvo fuera', () {
      expect(
        alVolver(fuera: const Duration(hours: 5), biometricEnabled: false),
        isFalse,
      );
    });

    test('sin sesión no bloquea', () {
      expect(
        alVolver(fuera: const Duration(hours: 5), loggedIn: false),
        isFalse,
      );
    });

    test('si nunca se fue a segundo plano no bloquea', () {
      // Transiciones de ciclo de vida desparejadas: ante la duda, no molestar.
      expect(
        AppLockPolicy.shouldLockOnResume(
          loggedIn: true,
          biometricEnabled: true,
          backgroundedAt: null,
          now: ahora,
        ),
        isFalse,
      );
    });

    test('un reloj que camina hacia atrás bloquea, no deja pasar', () {
      // Cambio de zona horaria o sincronización NTP: la diferencia sale
      // negativa y no se sabe cuánto pasó de verdad.
      expect(
        AppLockPolicy.shouldLockOnResume(
          loggedIn: true,
          biometricEnabled: true,
          backgroundedAt: ahora.add(const Duration(hours: 2)),
          now: ahora,
        ),
        isTrue,
      );
    });
  });

  test('el margen es corto pero no cero', () {
    // Cero convertiría cada notificación en una verificación; un margen largo
    // dejaría el teléfono abierto sobre la mesa.
    expect(AppLockPolicy.graceWindow.inSeconds, greaterThan(0));
    expect(AppLockPolicy.graceWindow.inMinutes, lessThanOrEqualTo(2));
  });
}
