import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/biometric_service.dart';
import 'biometric_login_button.dart';

/// Cómo se pide la verificación. Inyectable para poder probar la pantalla sin
/// el sensor: en un test los plugins nativos no existen y sus Futures nunca
/// resuelven dentro del reloj falso de flutter_test.
typedef BiometricAuthenticator = Future<BiometricAuthResult> Function(
    {String? reason});

/// Pantalla que tapa la app hasta que el dueño del teléfono se identifica.
///
/// Se muestra sobre el dashboard sin desmontarlo, así que al desbloquear el
/// gerente vuelve exactamente al reporte que estaba viendo, con sus filtros y
/// su scroll intactos.
class LockScreen extends StatefulWidget {
  /// A quién dice que está bloqueado (nombre de sesión o correo).
  final String? accountLabel;

  /// Verificación superada: el gate destapa la app.
  final VoidCallback onUnlocked;

  /// Salida de emergencia: cierra sesión y manda al login con contraseña.
  final VoidCallback onUsePassword;

  /// Sensor ya detectado. El gate lo pasa hecho para que la pantalla nazca con
  /// el ícono correcto; sin esto se ve una huella un instante antes de
  /// convertirse en Face ID.
  final BiometricKind? kind;

  /// Solo para tests: reemplaza la llamada al sensor.
  final BiometricAuthenticator? authenticator;

  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onUsePassword,
    this.accountLabel,
    this.kind,
    this.authenticator,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late BiometricKind _kind = widget.kind ?? BiometricKind.fingerprint;
  bool _verificando = false;
  String? _error;

  /// Cuántas veces falló seguido. A partir del segundo intento la salida por
  /// contraseña deja de ser un enlace discreto y se vuelve un botón: quien
  /// tiene el sensor mojado o roto no puede quedarse dando vueltas.
  int _fallos = 0;

  @override
  void initState() {
    super.initState();
    _prepararYPedir();
  }

  Future<void> _prepararYPedir() async {
    // Si el gate ya detectó el sensor, no se vuelve a preguntar.
    if (widget.kind == null) {
      final kind = await BiometricService().detectKind();
      if (!mounted) return;
      setState(() => _kind = kind);
    }
    await _pedirBiometria();
  }

  Future<void> _pedirBiometria() async {
    if (_verificando) return;
    setState(() {
      _verificando = true;
      _error = null;
    });

    final pedir = widget.authenticator ?? BiometricService().authenticate;
    final result = await pedir(
      reason: 'Verifica tu identidad para volver a Sabor Manager',
    );
    if (!mounted) return;

    if (result.success) {
      widget.onUnlocked();
      return;
    }

    // Si las credenciales se perdieron, insistir con el sensor no lleva a
    // ningún lado: la única salida real es volver a entrar con contraseña.
    if (result.needsSetup) {
      widget.onUsePassword();
      return;
    }

    setState(() {
      _verificando = false;
      _fallos++;
      _error = result.cancelled ? null : result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF7444fd);
    // Opaco y a pantalla completa: además de bloquear, tapa los números de
    // ventas que quedarían a la vista de quien tenga el teléfono en la mano.
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/SaborManagerLogo.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Sabor Manager está bloqueado',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.accountLabel != null &&
                      widget.accountLabel!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.accountLabel!,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: Colors.white38, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 36),
                  Semantics(
                    button: true,
                    label: _kind.actionLabel,
                    child: GestureDetector(
                      onTap: _verificando ? null : _pedirBiometria,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.5),
                                  width: 1.5),
                            ),
                            child: _verificando
                                ? Center(
                                    child: SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: accent),
                                    ),
                                  )
                                : Icon(
                                    BiometricLoginButton.iconFor(_kind),
                                    color: accent,
                                    size: 52,
                                  ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _verificando
                                ? 'Verificando…'
                                : 'Toca para ${_kind.actionLabel.toLowerCase()}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: const Color(0xFFEF4444),
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 32),
                  // La salida de emergencia siempre está: un sensor mojado, una
                  // huella borrada del sistema o un lector roto no pueden
                  // dejar a nadie fuera de su propia cuenta.
                  if (_fallos >= 2)
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: widget.onUsePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Ingresar con contraseña',
                          style: GoogleFonts.inter(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: widget.onUsePassword,
                      child: Text(
                        'Ingresar con contraseña',
                        style: GoogleFonts.inter(
                            color: Colors.white38, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
