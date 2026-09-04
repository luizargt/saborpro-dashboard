import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/manager_notification.dart';
import '../../providers/notifications_provider.dart';

const _fondo = Color(0xFF0F172A);
const _tarjeta = Color(0xFF1E293B);
const _acento = Color(0xFF7444fd);

/// La bandeja de avisos.
///
/// Se lee de arriba abajo como una línea de tiempo: lo de hoy primero, cada día
/// bajo su propio encabezado. La densidad es a propósito alta —un gerente
/// revisa esto de reojo entre servicios— y el color hace el trabajo de
/// clasificar sin obligar a leer.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();

    return Scaffold(
      backgroundColor: _fondo,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Encabezado(
              sinLeer: provider.sinLeer,
              onMarcarTodas: provider.sinLeer == 0
                  ? null
                  : () => provider.marcarTodasLeidas(),
            ),
            Expanded(child: _Cuerpo(provider: provider)),
          ],
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final int sinLeer;
  final VoidCallback? onMarcarTodas;

  const _Encabezado({required this.sinLeer, this.onMarcarTodas});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Avisos',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sinLeer == 0
                      ? 'Últimos ${NotificationsProvider.diasDeHistorial} días'
                      : '$sinLeer sin leer',
                  style: GoogleFonts.inter(
                    color: sinLeer == 0 ? Colors.white38 : _acento,
                    fontSize: 12.5,
                    fontWeight:
                        sinLeer == 0 ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Aparece solo cuando hay algo que marcar: un botón permanentemente
          // deshabilitado es ruido que el ojo aprende a ignorar.
          if (onMarcarTodas != null)
            TextButton.icon(
              onPressed: onMarcarTodas,
              icon: const Icon(Icons.done_all_rounded, size: 17),
              label: Text(
                'Marcar leídas',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: _acento,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  final NotificationsProvider provider;
  const _Cuerpo({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.cargando) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: _acento),
        ),
      );
    }

    if (provider.error != null) {
      return _Vacio(
        icono: Icons.cloud_off_rounded,
        titulo: 'No se pudieron cargar',
        detalle: provider.error!,
      );
    }

    if (provider.todas.isEmpty) {
      return const _Vacio(
        icono: Icons.notifications_none_rounded,
        titulo: 'Sin avisos por ahora',
        detalle: 'Acá van a aparecer las aperturas y cierres de caja, los '
            'gastos, los retiros y los movimientos de inventario de tus '
            'sucursales.',
      );
    }

    final grupos = _agruparPorDia(provider.todas);

    return ListView.builder(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: grupos.length,
      itemBuilder: (context, i) {
        final g = grupos[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 4 : 22, bottom: 10),
              child: Text(
                g.titulo,
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            ...g.avisos.map(
              (n) => _Fila(
                aviso: n,
                onTap: () => provider.marcarLeida(n.id),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Una fila por aviso.
///
/// Sin tarjetas con sombra: a treinta avisos, cada sombra suma ruido y la
/// lista se vuelve una pila de cajas. El no leído se distingue por el fondo
/// levemente elevado y la barra de color a la izquierda; el leído se apaga.
class _Fila extends StatelessWidget {
  final ManagerNotification aviso;
  final VoidCallback onTap;

  const _Fila({required this.aviso, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final leido = aviso.read;
    final color = aviso.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: leido ? Colors.transparent : _tarjeta,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: leido ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: leido
                    ? Colors.white.withValues(alpha: 0.05)
                    : color.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: leido ? 0.08 : 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    aviso.tipo.icono,
                    size: 18,
                    color: leido ? color.withValues(alpha: 0.55) : color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _sinEmoji(aviso.title),
                              style: GoogleFonts.inter(
                                color: leido ? Colors.white54 : Colors.white,
                                fontSize: 14,
                                fontWeight:
                                    leido ? FontWeight.w500 : FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              _hora(aviso.createdAt),
                              style: GoogleFonts.inter(
                                color: Colors.white30,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (!leido) ...[
                            const SizedBox(width: 8),
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        aviso.body,
                        style: GoogleFonts.inter(
                          color: leido ? Colors.white30 : Colors.white70,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Los títulos vienen con un emoji al frente desde las Cloud Functions ("🔓
  /// Caja abierta"). En la push suma, pero en una lista de treinta se convierte
  /// en una columna de caritas que compite con el ícono de color que ya está
  /// ahí diciendo lo mismo.
  static String _sinEmoji(String titulo) {
    final limpio = titulo.replaceAll(
      RegExp(
        r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2B00}-\u{2BFF}]',
        unicode: true,
      ),
      '',
    );
    return limpio.trim().isEmpty ? titulo.trim() : limpio.trim();
  }

  static String _hora(DateTime d) => DateFormat.Hm('es').format(d);
}

class _Grupo {
  final String titulo;
  final List<ManagerNotification> avisos;
  const _Grupo(this.titulo, this.avisos);
}

/// Agrupa por día natural, no por "hace X horas": a las 00:30 un aviso de las
/// 23:50 es de ayer aunque hayan pasado cuarenta minutos, y mezclarlos bajo
/// "Hoy" confunde a quien está cuadrando el día.
List<_Grupo> _agruparPorDia(List<ManagerNotification> avisos) {
  final hoy = DateUtils.dateOnly(DateTime.now());
  final ayer = hoy.subtract(const Duration(days: 1));
  final grupos = <_Grupo>[];
  DateTime? diaActual;
  var actuales = <ManagerNotification>[];

  String titularDe(DateTime dia) {
    if (dia == hoy) return 'HOY';
    if (dia == ayer) return 'AYER';
    return DateFormat('EEEE d \'de\' MMMM', 'es').format(dia).toUpperCase();
  }

  for (final a in avisos) {
    final dia = DateUtils.dateOnly(a.createdAt);
    if (diaActual == null || dia != diaActual) {
      if (diaActual != null) grupos.add(_Grupo(titularDe(diaActual), actuales));
      diaActual = dia;
      actuales = [];
    }
    actuales.add(a);
  }
  if (diaActual != null) grupos.add(_Grupo(titularDe(diaActual), actuales));

  return grupos;
}

class _Vacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Vacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _tarjeta,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icono, color: Colors.white24, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white30,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
