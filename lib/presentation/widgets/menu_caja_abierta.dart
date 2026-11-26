import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/services/cierre_admin_service.dart';
import '../../data/models/cash_register_summary.dart';
import '../../data/models/cierres_caja.dart' show fechaCorta;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Los tres puntos de una caja de "En caja ahora": "Cerrar caja".
///
/// Antes de cerrar avisa que la caja queda descuadrada (nadie cuenta el dinero)
/// y que no se puede deshacer.
class MenuCajaAbierta extends StatefulWidget {
  final CashRegisterSummary caja;

  /// El cierre en sí (en la app, `CierreAdminService`).
  final Future<ResultadoCierreAdmin> Function() onCerrar;

  /// Para volver a leer las cajas: se llama si la caja ya no está abierta.
  final VoidCallback? onTerminado;

  const MenuCajaAbierta({super.key, required this.caja, required this.onCerrar, this.onTerminado});

  @override
  State<MenuCajaAbierta> createState() => _MenuCajaAbiertaState();
}

class _MenuCajaAbiertaState extends State<MenuCajaAbierta> {
  bool _cerrando = false;

  Future<void> _cerrar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmarCierreAdmin(caja: widget.caja),
    );
    if (confirmado != true || !mounted) return;

    // Se toman antes de esperar: mientras tanto la pantalla puede recargarse y
    // este botón desaparecer, y el aviso tiene que salir igual.
    final avisos = ScaffoldMessenger.maybeOf(context);
    final nombre = widget.caja.userName;
    final recargar = widget.onTerminado;
    setState(() => _cerrando = true);

    String mensaje;
    var cambio = false;
    try {
      final resultado = await widget.onCerrar();
      cambio = resultado != ResultadoCierreAdmin.cobrando;
      mensaje = switch (resultado) {
        ResultadoCierreAdmin.cerrada => 'La caja de $nombre quedó cerrada por administrador, descuadrada.',
        ResultadoCierreAdmin.yaEstabaCerrada => 'La caja de $nombre ya estaba cerrada. No se cambió nada.',
        ResultadoCierreAdmin.noExiste => 'No se encontró la caja de $nombre.',
        ResultadoCierreAdmin.cobrando =>
          'No se cerró: están cobrando en la caja de $nombre. Pide que dejen de cobrar e inténtalo de nuevo.',
      };
    } catch (e, pila) {
      debugPrint('[Cajas] no se pudo cerrar la caja ${widget.caja.id}: $e');
      Sentry.captureException(e, stackTrace: pila);
      mensaje = 'No se pudo cerrar la caja de $nombre. Revisa tu internet e inténtalo de nuevo.';
    }

    avisos?.showSnackBar(SnackBar(content: Text(mensaje)));
    if (mounted) setState(() => _cerrando = false);
    if (cambio) recargar?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_cerrando) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _C.bad),
          ),
        ),
      );
    }
    return SizedBox(
      width: 44,
      height: 44,
      child: PopupMenuButton<bool>(
        tooltip: 'Opciones de la caja de ${widget.caja.userName}',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz_rounded, size: 20, color: _C.muted),
        color: _C.subtle,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _C.lineStrong),
        ),
        onSelected: (_) => _cerrar(),
        itemBuilder: (_) => [
          PopupMenuItem<bool>(
            value: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 18, color: _C.bad),
                const SizedBox(width: 10),
                Flexible(child: Text('Cerrar caja', style: _t(14.5, FontWeight.w600, _C.bad))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El aviso antes de cerrar la caja de otra persona. Devuelve `true` si se
/// confirma.
class ConfirmarCierreAdmin extends StatelessWidget {
  final CashRegisterSummary caja;

  const ConfirmarCierreAdmin({super.key, required this.caja});

  @override
  Widget build(BuildContext context) {
    final sucursal = caja.locationName;
    final desde = 'Abierta desde el ${fechaCorta(caja.openedAt)}, ${DateFormat('hh:mm a').format(caja.openedAt)}'
        '${sucursal != null && sucursal.isNotEmpty ? ' · $sucursal' : ''}';
    final cuerpo = _t(14, FontWeight.w400, _C.muted, height: 1.45);

    return AlertDialog(
      backgroundColor: _C.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      scrollable: true,
      title: Text('¿Cerrar la caja de ${caja.userName}?', style: _t(18, FontWeight.w700, _C.ink)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(desde, style: cuerpo),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: _C.warn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'La caja quedará descuadrada: nadie va a contar el dinero y no se puede hacer el cuadre.',
                      style: _t(14, FontWeight.w700, _C.ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('Quedará como "Cerrada por administrador". Esto no se puede deshacer.', style: cuerpo),
            const SizedBox(height: 8),
            Text(
              'Antes, pide que dejen de cobrar en esa caja y revisa que su aparato tenga internet: '
              'lo que no haya subido no sale en el corte, y lo que cobre después no entra en ninguno.',
              style: cuerpo,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar', style: _t(14, FontWeight.w600, _C.muted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: _C.bad, foregroundColor: Colors.white),
          child: const Text('Cerrar caja'),
        ),
      ],
    );
  }
}
