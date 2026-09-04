import 'package:flutter/material.dart';
import '../../core/services/app_lock_policy.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/biometric_service.dart';
import '../screens/auth/lock_screen.dart';
import '../screens/auth/login_screen.dart';

/// Tapa la app con [LockScreen] cuando hay que volver a verificar la identidad.
///
/// Se monta en `MaterialApp.builder`, o sea POR ENCIMA del Navigator: así
/// sobrevive a cualquier navegación y sigue vigilando aunque el usuario entre
/// y salga de pantallas. Montado como `home` se desmontaría en el primer
/// pushReplacement y dejaría de proteger nada.
class AppLockGate extends StatefulWidget {
  final Widget child;

  /// Navigator raíz, para poder mandar al login desde encima de las rutas.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Si al arrancar hay que pedir biometría. Se resuelve en `main()` antes de
  /// pintar, para que el dashboard no alcance a verse antes del bloqueo.
  final bool lockedAtStart;

  const AppLockGate({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.lockedAtStart,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  late bool _locked = widget.lockedAtStart;
  DateTime? _backgroundedAt;

  /// Se cachea al bloquear: consultarlo es asíncrono y el build no puede
  /// esperar.
  bool _biometricEnabled = false;
  String? _accountLabel;
  BiometricKind? _kind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refrescarEstado();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refrescarEstado() async {
    final enabled = await BiometricService().isEnabled();
    final kind = await BiometricService().detectKind();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _kind = kind;
      _accountLabel =
          AuthService().displayName ?? AuthService().sessionEmail;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Solo cuenta la primera salida: `paused` y `hidden` pueden llegar
        // ambos en la misma transición, y pisar el sello reiniciaría el
        // cronómetro dejando la app abierta más tiempo del debido.
        _backgroundedAt ??= DateTime.now();
        // El prompt biométrico del sistema manda la app a inactive/paused. Sin
        // esta relectura, volver de la propia verificación se contaría como
        // "estuvo fuera" y pediría la huella otra vez, en bucle.
        _refrescarEstado();
      case AppLifecycleState.resumed:
        _evaluarBloqueo();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _evaluarBloqueo() {
    final debeBloquear = AppLockPolicy.shouldLockOnResume(
      loggedIn: AuthService().isLoggedIn,
      biometricEnabled: _biometricEnabled,
      backgroundedAt: _backgroundedAt,
      now: DateTime.now(),
    );
    _backgroundedAt = null;
    if (debeBloquear && !_locked && mounted) {
      setState(() => _locked = true);
    }
  }

  void _desbloquear() {
    _backgroundedAt = null;
    if (mounted) setState(() => _locked = false);
  }

  /// Salida de emergencia. Cierra sesión y manda al login limpiando la pila:
  /// dejar el dashboard debajo permitiría volver con el botón atrás.
  Future<void> _usarContrasena() async {
    await AuthService().logout();
    widget.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    _desbloquear();
  }

  @override
  Widget build(BuildContext context) {
    // El child queda montado debajo: al desbloquear, el gerente vuelve al
    // reporte que estaba viendo en vez de a un dashboard recién recargado.
    return Stack(
      children: [
        widget.child,
        if (_locked)
          LockScreen(
            accountLabel: _accountLabel,
            kind: _kind,
            onUnlocked: _desbloquear,
            onUsePassword: _usarContrasena,
          ),
      ],
    );
  }
}
