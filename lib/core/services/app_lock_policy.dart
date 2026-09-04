/// Decide cuándo Sabor Manager tiene que volver a pedir la biometría.
///
/// Es una función pura a propósito: la regla de "cuándo bloquear" es lo único
/// que puede dejar a un gerente encerrado fuera de sus reportes, así que se
/// prueba sin arrancar la app ni el sensor.
class AppLockPolicy {
  /// Margen para volver sin que pida la huella otra vez.
  ///
  /// Salir a leer un WhatsApp y regresar no puede costar una verificación: eso
  /// enseña al usuario a odiar la función y a apagarla. Pero tampoco puede ser
  /// tan largo que alguien que dejó el teléfono en la mesa quede expuesto.
  static const graceWindow = Duration(seconds: 30);

  /// Al arrancar en frío siempre se pide: el proceso murió y nadie sabe quién
  /// está levantando el teléfono ahora.
  static bool shouldLockOnStart({
    required bool loggedIn,
    required bool biometricEnabled,
  }) =>
      loggedIn && biometricEnabled;

  /// Al volver del segundo plano se pide solo si estuvo fuera más que el
  /// margen.
  ///
  /// [backgroundedAt] null significa que nunca se fue a segundo plano: puede
  /// pasar con transiciones de ciclo de vida que llegan desparejadas, y ante la
  /// duda no se bloquea, porque bloquear de más es lo que hace que el usuario
  /// apague la función.
  static bool shouldLockOnResume({
    required bool loggedIn,
    required bool biometricEnabled,
    required DateTime? backgroundedAt,
    required DateTime now,
  }) {
    if (!loggedIn || !biometricEnabled) return false;
    if (backgroundedAt == null) return false;
    final fuera = now.difference(backgroundedAt);
    // Un reloj que camina hacia atrás (cambio de zona horaria, sincronización
    // NTP) daría una diferencia negativa. Ese caso se trata como "no sé cuánto
    // pasó" y se bloquea, que es el lado seguro.
    if (fuera.isNegative) return true;
    return fuera >= graceWindow;
  }
}
