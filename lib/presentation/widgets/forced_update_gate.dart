import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/store_update_service.dart';

/// Aviso de actualización obligatoria.
///
/// Se muestra sobre todo lo demás cuando la tienda tiene una versión más nueva
/// que la instalada, y no se puede cerrar: mientras esté arriba, la app no se
/// usa. Por eso el chequeo que lo dispara (StoreUpdateService) falla siempre
/// hacia "estás al día" — un teléfono sin señal no puede quedarse sin reportes.
class ForcedUpdateGate extends StatefulWidget {
  final Widget child;

  /// Inyectable para tests: por defecto pregunta a la tienda de verdad.
  final Future<StoreUpdateStatus> Function()? checker;

  /// Inyectable para tests: por defecto abre la tienda.
  final Future<bool> Function(String url)? opener;

  const ForcedUpdateGate({
    super.key,
    required this.child,
    this.checker,
    this.opener,
  });

  @override
  State<ForcedUpdateGate> createState() => _ForcedUpdateGateState();
}

class _ForcedUpdateGateState extends State<ForcedUpdateGate>
    with WidgetsBindingObserver {
  StoreUpdateStatus? _estado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver se revisa de nuevo: el usuario acaba de ir a la tienda a
    // actualizar y tiene que poder entrar sin reiniciar la app a mano.
    if (state == AppLifecycleState.resumed) _revisar();
  }

  Future<void> _revisar() async {
    final check = widget.checker ?? StoreUpdateService().check;
    final estado = await check();
    if (!mounted) return;
    setState(() => _estado = estado);
  }

  Future<void> _abrirTienda() async {
    final url = _estado?.storeUrl;
    if (url == null) return;
    final abrir = widget.opener ??
        (String u) => launchUrl(Uri.parse(u),
            mode: LaunchMode.externalApplication);
    await abrir(url);
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = _estado?.updateAvailable ?? false;
    return Stack(
      children: [
        widget.child,
        if (bloqueado)
          _UpdateModal(
            storeVersion: _estado?.storeVersion,
            onUpdate: _abrirTienda,
          ),
      ],
    );
  }
}

/// El letrero. Chico y con una sola salida: actualizar.
class _UpdateModal extends StatelessWidget {
  final String? storeVersion;
  final VoidCallback onUpdate;

  const _UpdateModal({required this.onUpdate, this.storeVersion});

  @override
  Widget build(BuildContext context) {
    // PopScope corta el botón atrás de Android: sin esto el aviso se esquiva
    // con un gesto y deja de ser obligatorio.
    return PopScope(
      canPop: false,
      child: Material(
        // El velo cubre de borde a borde (también detrás de las barras del
        // sistema); lo que se aparta de ellas es la tarjeta, vía SafeArea.
        color: Colors.black.withValues(alpha: 0.75),
        child: SafeArea(
          child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7444fd).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Color(0xFF7444fd), size: 30),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Actualiza Sabor Suite',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hay una versión nueva disponible. Actualiza para '
                      'seguir usando la app.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: onUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7444fd),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Actualizar',
                          style: GoogleFonts.inter(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
