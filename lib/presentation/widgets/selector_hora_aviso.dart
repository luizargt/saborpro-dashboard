/// La hoja para elegir a qué hora llega un aviso diario (ventas de ayer, stock
/// bajo): las 24 horas en cuadros grandes, con la elegida marcada.
///
/// Sin providers ni Firebase: quien la abre decide qué hacer con la hora. Se
/// prueba en test/presentation/widgets/selector_hora_aviso_test.dart.
library;

import 'package:flutter/material.dart';

import '../providers/notification_settings_provider.dart' show etiquetaDeHora;
import 'barra_inferior.dart' show mostrarHojaManager;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// El contenido de la hoja.
class SelectorHoraAviso extends StatelessWidget {
  /// Qué aviso es ("Ventas de ayer"): va en el título.
  final String aviso;

  /// La hora que está elegida hoy (0–23).
  final int actual;

  final ValueChanged<int> onElegir;

  const SelectorHoraAviso({super.key, required this.aviso, required this.actual, required this.onElegir});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿A qué hora te avisamos?', style: _t(19, FontWeight.w700, _C.ink, height: 1.3)),
        const SizedBox(height: 4),
        Text(
          '$aviso · hora de Guatemala',
          style: _t(13, FontWeight.w400, _C.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            // Tres por fila: a 360 dp cada cuadro mide ~105 dp, cómodo para el dedo
            // y con el texto "12:00 p. m." entero, incluso con letra grande.
            const separacion = 8.0;
            final ancho = (c.maxWidth - separacion * 2) / 3;
            return Wrap(
              spacing: separacion,
              runSpacing: separacion,
              children: [
                for (var h = 0; h < 24; h++)
                  SizedBox(
                    width: ancho,
                    child: _Hora(hora: h, elegida: h == actual, onTap: () => onElegir(h)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Hora extends StatelessWidget {
  final int hora;
  final bool elegida;
  final VoidCallback onTap;
  const _Hora({required this.hora, required this.elegida, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final etiqueta = etiquetaDeHora(hora);
    return Semantics(
      button: true,
      selected: elegida,
      label: etiqueta,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: elegida ? _C.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: elegida ? _C.accent : _C.line, width: 1.5),
          ),
          child: ExcludeSemantics(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(14, elegida ? FontWeight.w700 : FontWeight.w600, elegida ? _C.onAccent : _C.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre la hoja y devuelve la hora elegida (null si se cerró sin elegir).
Future<int?> mostrarSelectorHoraAviso(BuildContext context, {required String aviso, required int actual}) {
  return mostrarHojaManager<int>(
    context,
    builder: (ctx) => SelectorHoraAviso(
      aviso: aviso,
      actual: actual,
      onElegir: (h) => Navigator.of(ctx).pop(h),
    ),
  );
}
