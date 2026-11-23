import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/notifications_provider.dart';
import '../../widgets/notifications_view.dart';

/// La bandeja de avisos.
///
/// Se lee de arriba abajo como una línea de tiempo: lo de hoy primero, cada día
/// bajo su propio encabezado. La densidad es a propósito alta —un gerente
/// revisa esto de reojo entre servicios— y el color hace el trabajo de
/// clasificar sin obligar a leer.
///
/// Solo conecta el provider con [NotificationsView], que es la parte que se ve
/// (diseño `avisos.html`, en su modo oscuro) y se puede probar a 360dp sin
/// Firebase. Es una pestaña del shell, sin barra propia: el título va dentro.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();

    return Scaffold(
      backgroundColor: kAvisosBg,
      body: SafeArea(
        top: false,
        child: NotificationsView(
          avisos: provider.todas,
          cargando: provider.cargando,
          error: provider.error,
          onLeer: (ids) {
            for (final id in ids) {
              provider.marcarLeida(id);
            }
          },
          onMarcarTodas: provider.marcarTodasLeidas,
        ),
      ),
    );
  }
}
