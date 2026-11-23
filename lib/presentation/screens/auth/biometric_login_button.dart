import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/biometric_service.dart';
import '../../widgets/inicio_ui.dart' show InicioColores;

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
    final accent = InicioColores.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Divider(color: InicioColores.line),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'o',
                style:
                    GoogleFonts.inter(color: InicioColores.soft, fontSize: 12),
              ),
            ),
            Expanded(
              child: Divider(color: InicioColores.line),
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
                    color: InicioColores.card,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: enabled
                          ? accent.withValues(alpha: 0.5)
                          : InicioColores.line,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    iconFor(kind),
                    color: enabled ? accent : InicioColores.soft,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: enabled ? InicioColores.muted : InicioColores.soft,
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
                        GoogleFonts.inter(color: InicioColores.soft, fontSize: 11),
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
