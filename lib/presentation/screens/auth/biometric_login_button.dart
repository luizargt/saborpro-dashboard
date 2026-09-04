import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/biometric_service.dart';

/// Acceso con huella / Face ID debajo del formulario de correo y contraseña.
///
/// Vive fuera de LoginScreen para poder probarlo a 360dp sin arrancar los
/// plugins nativos de biometría, que en un test solo saben lanzar
/// MissingPluginException.
class BiometricLoginButton extends StatelessWidget {
  /// Qué sensor tiene el teléfono: decide el ícono y cómo se nombra.
  final BiometricKind kind;

  /// Si el usuario ya vinculó su cuenta. Apagado el botón sigue visible, pero
  /// invita a activarlo en vez de intentar entrar.
  final bool enabled;

  /// Correo vinculado, para que se vea a qué cuenta entra. Null si no hay.
  final String? account;

  final VoidCallback? onTap;

  const BiometricLoginButton({
    super.key,
    required this.kind,
    required this.enabled,
    this.account,
    this.onTap,
  });

  static IconData iconFor(BiometricKind kind) => switch (kind) {
        BiometricKind.faceId ||
        BiometricKind.faceAndroid =>
          Icons.face_retouching_natural,
        _ => Icons.fingerprint,
      };

  String get _label =>
      enabled ? kind.actionLabel : 'Activar acceso con ${kind.label}';

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF7444fd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Divider(color: Colors.white.withValues(alpha: 0.08)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'o',
                style:
                    GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
            ),
            Expanded(
              child: Divider(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          label: _label,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: enabled
                          ? accent.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.12),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    iconFor(kind),
                    color: enabled ? accent : Colors.white30,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: enabled ? Colors.white70 : Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Con varias cuentas en el mismo teléfono, saber a cuál entra
                // evita el susto de caer en otro restaurante sin pedirlo.
                if (enabled && account != null && account!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    account!,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style:
                        GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
