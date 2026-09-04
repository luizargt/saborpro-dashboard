import 'package:flutter/widgets.dart';

/// Índice de la pestaña de Avisos dentro de AppShell.
const int pestanaAvisos = 3;

/// Navigator raíz de la app.
///
/// Vive acá y no dentro del widget de MaterialApp porque quien más lo necesita
/// está fuera del árbol: el servicio de notificaciones tiene que poder llevar a
/// alguien a la bandeja cuando toca un aviso, y desde ahí no hay `context`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Pestaña que alguien pidió abrir desde fuera del árbol.
///
/// Es un buzón y no una llamada directa a propósito: cuando la app venía
/// cerrada y se abre tocando una notificación, el aviso llega ANTES de que
/// AppShell exista. Guardarlo acá deja que el shell lo recoja al montarse, en
/// vez de perderse por llegar temprano.
final ValueNotifier<int?> pestanaSolicitada = ValueNotifier<int?>(null);

/// Pide que se muestre la bandeja de avisos.
void solicitarPestanaAvisos() => pestanaSolicitada.value = pestanaAvisos;

/// El shell la llama cuando ya atendió el pedido, para que un cambio de
/// pestaña posterior del usuario no lo devuelva a Avisos sin motivo.
void limpiarPestanaSolicitada() => pestanaSolicitada.value = null;
