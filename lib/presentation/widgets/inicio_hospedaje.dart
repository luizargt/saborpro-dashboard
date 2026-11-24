/// "Hospedaje" del Inicio: cómo está el hotel AHORA. Lo que dice lo arma
/// [ResumenHospedaje] con lo que se leyó de `rooms` y `reservations`; aquí solo
/// se dibuja, con el mismo lenguaje de "Cajas abiertas" y "Cuentas abiertas".
library;

import 'package:flutter/material.dart';

import '../../data/models/hospedaje_inicio.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Cuántas habitaciones hay ocupadas de las que tiene, cómo se reparte el resto
/// (reservadas para hoy, libres, en limpieza, en mantenimiento) y lo que sale hoy. Sin flecha:
/// el Manager no tiene una pantalla de habitaciones a donde llevar.
class HospedajeCard extends StatelessWidget {
  final ResumenHospedaje resumen;

  const HospedajeCard({super.key, required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;

    return InicioToque(
      onTap: null,
      radio: 22,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: telefono ? 16 : 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: _C.tint, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.hotel_rounded, size: 22, color: _C.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Hospedaje', style: _t(13, FontWeight.w400, _C.muted)),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${r.ocupadas} de ${r.total}',
                              style: _t(22, FontWeight.w800, _C.ink, height: 1.3),
                            ),
                            TextSpan(
                              text: ' ${r.ocupadas == 1 ? 'ocupada' : 'ocupadas'} · ${r.porcentaje}%',
                              style: _t(13, FontWeight.w400, _C.muted),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Barra(resumen: r),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Leyenda(color: _C.line, borde: _C.lineStrong, texto: 'Libres', n: r.libres, siempre: true),
                _Leyenda(color: _C.don, texto: 'Reservadas hoy', n: r.reservadas),
                _Leyenda(color: _C.warn, texto: 'En limpieza', n: r.enLimpieza),
                _Leyenda(color: _C.bad, texto: 'En mantenimiento', n: r.enMantenimiento),
              ],
            ),
            if (r.porSalirHoy > 0 || r.pasadasDeHora > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (r.porSalirHoy > 0) _Dato(n: r.porSalirHoy, texto: 'por salir hoy'),
                  if (r.pasadasDeHora > 0)
                    _Dato(
                      n: r.pasadasDeHora,
                      texto: r.pasadasDeHora == 1 ? 'pasada de su hora' : 'pasadas de su hora',
                      alerta: true,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// La barra del reparto: ocupadas, reservadas para hoy, en limpieza, en
/// mantenimiento y libres, cada tramo proporcional a su cantidad.
class _Barra extends StatelessWidget {
  final ResumenHospedaje resumen;

  const _Barra({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final tramos = <(Color, int)>[
      (_C.accent, r.ocupadas),
      (_C.don, r.reservadas),
      (_C.warn, r.enLimpieza),
      (_C.bad, r.enMantenimiento),
      (_C.line, r.libres),
    ].where((t) => t.$2 > 0).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(
          // Estirados: un `ColoredBox` sin hijo mide 0 de alto con restricciones
          // sueltas y la barra no se vería.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tramos.length; i++) ...[
              // Una raya fina entre tramos, del color de la tarjeta.
              if (i > 0) SizedBox(width: 2, child: ColoredBox(color: _C.card)),
              Expanded(flex: tramos[i].$2, child: ColoredBox(color: tramos[i].$1)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "● 3 Libres": el punto del color del tramo. Sin cantidad no se dibuja, salvo
/// [siempre] (los libres se dicen aunque sean cero).
class _Leyenda extends StatelessWidget {
  final Color color;

  /// Contorno del punto, para el color que casi no se distingue de la tarjeta.
  final Color? borde;
  final String texto;
  final int n;
  final bool siempre;

  const _Leyenda({required this.color, this.borde, required this.texto, required this.n, this.siempre = false});

  @override
  Widget build(BuildContext context) {
    if (n == 0 && !siempre) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: borde == null ? null : Border.all(color: borde!, width: 1),
          ),
        ),
        const SizedBox(width: 6),
        Text('$n', style: _t(13, FontWeight.w700, _C.ink)),
        const SizedBox(width: 4),
        Flexible(child: Text(texto, style: _t(13, FontWeight.w400, _C.muted), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Un dato de lo de hoy: "3 por entrar hoy". El que pide atención (las pasadas
/// de su hora) va en el color de aviso.
class _Dato extends StatelessWidget {
  final int n;
  final String texto;
  final bool alerta;

  const _Dato({required this.n, required this.texto, this.alerta = false});

  @override
  Widget build(BuildContext context) {
    final fondo = alerta ? _C.warnTint : _C.subtle;
    final color = alerta ? _C.warn : _C.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n', style: _t(14.5, FontWeight.w800, color)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(texto, style: _t(13, FontWeight.w400, alerta ? _C.warn : _C.muted), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
