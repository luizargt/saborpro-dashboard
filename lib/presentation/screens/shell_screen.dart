import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../../core/navigation/app_navigator.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/export_service.dart';
import '../../core/services/fiscal_reports_service.dart';
import '../../core/services/notification_service.dart';
import '../../presentation/providers/dashboard_provider.dart';
import '../../presentation/providers/inventory_provider.dart';
import '../../presentation/providers/notification_settings_provider.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/inventory/inventory_screen.dart';
import '../../presentation/screens/notifications/notifications_screen.dart';
import '../../presentation/providers/notifications_provider.dart';
import '../../presentation/screens/reports/reports_list_screen.dart';
import '../../presentation/screens/settings/notification_settings_screen.dart';
import '../../presentation/widgets/period_selector.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  int? _patchNumber;

  // El último intento de activar el push se quedó sin permiso. Sirve para
  // reintentar al volver de los Ajustes del sistema (ver
  // didChangeAppLifecycleState); si no, el token no se guardaría hasta el
  // siguiente arranque de la app.
  bool _pushSinPermiso = false;
  bool _reintentandoPush = false;

  // Cerrar sesión no es instantáneo (hay que desvincular el token FCM antes) y
  // no muestra spinner: sin esta guarda, el segundo toque abriría un logout en
  // paralelo. Ver _logout.
  bool _cerrandoSesion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Alguien puede haber tocado una notificación con la app cerrada: el pedido
    // quedó en el buzón antes de que este shell existiera, así que se atiende
    // el valor actual además de escuchar los que vengan.
    pestanaSolicitada.addListener(_atenderPestanaSolicitada);
    _atenderPestanaSolicitada();
    _loadPatchNumber();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = AuthService().tenantId;
      if (id != null) {
        context.read<DashboardProvider>().init(id);
        context.read<InventoryProvider>().init(id);
      }
      _setupNotificaciones();
    });
  }

  @override
  void dispose() {
    pestanaSolicitada.removeListener(_atenderPestanaSolicitada);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Atiende el pedido de abrir una pestaña que dejó una notificación tocada.
  ///
  /// El buzón se limpia después de atenderlo: si quedara puesto, el usuario que
  /// se mueve a Reportes volvería a Avisos en el siguiente rebuild.
  void _atenderPestanaSolicitada() {
    final pedida = pestanaSolicitada.value;
    if (pedida == null) return;
    // Puede llegar durante el build (el listener se dispara desde el handler de
    // FCM); el post-frame evita un setState en pleno frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _index = pedida);
      limpiarPestanaSolicitada();
    });
  }

  /// El usuario vuelve a la app. Si dejamos el push a medias por falta de
  /// permiso, puede que venga justo de activarlo en los Ajustes del sistema:
  /// hay que RELEER el estado y guardar el token en vez de esperar al próximo
  /// arranque. Releer, no pedir: ver `_reintentarPush`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    if (!_pushSinPermiso) return;
    _reintentarPush();
  }

  /// uid con el que se guardan el token FCM y las preferencias.
  ///
  /// `firestoreUid` puede venir null con la sesión viva: al restaurar, la
  /// consulta por `firebase_uid` puede expirar y el error se traga en silencio.
  /// Si nos rindiéramos ahí, el push quedaría muerto sin ninguna señal.
  Future<String?> _uidDeSesion() async =>
      AuthService().firestoreUid ?? await AuthService().readPersistedUid();

  /// Prende el push y deja el token guardado en users/{uid}.
  ///
  /// Corre en CADA entrada a AppShell, o sea en cada inicio de sesión, y eso es
  /// a propósito: quien no dio permiso vuelve a ver el recordatorio cada vez
  /// que entra. No hay flag de "no volver a preguntar" — sin permiso la app no
  /// avisa de nada y deja de servir para lo que se instaló.
  Future<void> _setupNotificaciones() async {
    final uid = await _uidDeSesion();
    if (uid == null || !mounted) return;

    // La bandeja se engancha primero y sin await: no depende del permiso de
    // push ni de que haya token. Aunque el usuario haya dicho que no a las
    // notificaciones del sistema, los avisos igual se acumulan acá dentro.
    context.read<NotificationsProvider>().init(uid);

    await NotificationService().initialize();
    if (!mounted) return;

    // Las preferencias se cargan aunque falte el permiso: la pantalla de
    // ajustes tiene que poder abrirse y mostrar los switches igual.
    await context.read<NotificationSettingsProvider>().init(uid);

    final resultado = await NotificationService().ensurePermissionAndToken(uid);
    _pushSinPermiso = resultado == ResultadoPush.permisoDenegado;
    if (!mounted) return;

    // Solo se manda a Ajustes cuando FALTA el permiso. Si el permiso está dado
    // y lo que falló fue el token (en iOS, apns-token-not-set en el primer
    // arranque), mandarlo a activar algo ya activado solo lo confunde: el
    // listener de onTokenRefresh guarda el token en cuanto FCM entregue uno.
    if (resultado != ResultadoPush.permisoDenegado) return;

    await _mostrarDialogoPermisos();
  }

  /// Reintento silencioso tras volver a la app: SOLO relee el estado del
  /// permiso y, si ya está concedido, guarda el token. No pide nada.
  ///
  /// `pedirSiHaceFalta: false` es lo que lo hace silencioso de verdad. Sin eso,
  /// el usuario que dijo "Ahora no" recibiría el diálogo NATIVO del sistema al
  /// volver de WhatsApp o de cualquier otra app, sin haber pedido nada; y en
  /// Android ese sería el segundo y último diálogo que el sistema muestra en
  /// toda la vida de la instalación: tras rechazarlo, el permiso queda denegado
  /// para siempre y solo se recupera a mano desde Ajustes. El diálogo nativo
  /// sale una sola vez, al entrar (`_setupNotificaciones`), que es cuando el
  /// usuario tiene el contexto de qué se le está preguntando.
  ///
  /// Lo que este reintento sí resuelve: quien fue a los Ajustes del sistema y
  /// activó el permiso a mano vuelve con el estado ya concedido, y aquí se le
  /// guarda el token sin esperar al próximo arranque.
  Future<void> _reintentarPush() async {
    if (_reintentandoPush) return; // varios `resumed` seguidos son normales
    _reintentandoPush = true;
    try {
      final uid = await _uidDeSesion();
      if (uid == null) return;
      final resultado = await NotificationService()
          .ensurePermissionAndToken(uid, pedirSiHaceFalta: false);
      if (resultado != ResultadoPush.permisoDenegado) _pushSinPermiso = false;
    } finally {
      _reintentandoPush = false;
    }
  }

  Future<void> _mostrarDialogoPermisos() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.notifications_active_rounded,
                color: Color(0xFF7444fd), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Activa las notificaciones',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        content: Text(
          'Sin permiso de notificaciones no te vas a enterar de las aperturas '
          'y cierres de caja, los gastos ni los movimientos de inventario de '
          'tus sucursales. Solo lo sabrías entrando a revisar a mano.\n\n'
          'Toca "Abrir Ajustes" y activa las notificaciones de Sabor Manager.',
          style: GoogleFonts.inter(
              color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Ahora no',
                style: GoogleFonts.inter(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7444fd),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              // Se cierra antes de salir de la app: al volver de Ajustes el
              // diálogo colgado tapando la pantalla se vería como un bug.
              Navigator.pop(ctx);
              try {
                await openAppSettings();
              } catch (e) {
                // permission_handler solo trae implementación de Android e
                // iOS. En macOS reventaría con MissingPluginException y se
                // llevaría la app por delante por un botón secundario.
                debugPrint('[PUSH] No se pudieron abrir los Ajustes: $e');
              }
            },
            child: Text('Abrir Ajustes', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPatchNumber() async {
    try {
      final updater = ShorebirdUpdater();
      if (!updater.isAvailable) return;

      final current = await updater.readCurrentPatch();
      final next = await updater.readNextPatch();

      // Mostrar el mayor número disponible (next si hay parche pendiente)
      final display = [current?.number, next?.number]
          .whereType<int>()
          .fold<int?>(null, (a, b) => a == null || b > a ? b : a);

      if (mounted) setState(() => _patchNumber = display);

      // Descargar nuevos parches en background sin bloquear la UI
      updater.checkForUpdate().then((status) {
        if (status == UpdateStatus.outdated) updater.update();
      });
    } catch (_) {}
  }

  Future<void> _logout() async {
    // Sin red el borrado del token tarda lo que dure su timeout (2s) y en ese
    // rato la pantalla no cambia: la hoja del menú ya se cerró y sigue el
    // dashboard. El usuario, sin ninguna señal, vuelve a abrir el menú y toca
    // "Cerrar sesión" otra vez; sin esta guarda eso dispara un segundo logout
    // en paralelo y un segundo pushReplacement al login.
    if (_cerrandoSesion) return;
    _cerrandoSesion = true;
    try {
      // El token se desvincula ANTES del logout, mientras el uid sigue vivo:
      // después AuthService lo borra de memoria y del storage y ya no habría a
      // qué doc de users/ apuntar. Sin esto, en multi-tenant el teléfono
      // seguiría recibiendo avisos de caja, gastos e inventario del tenant que
      // abandonó.
      final uid = await _uidDeSesion();
      if (uid != null) {
        // Un fallo de red no puede impedir cerrar sesión:
        // removeCurrentDeviceToken se traga sus errores y corta a los 2s.
        await NotificationService().removeCurrentDeviceToken(uid);
      }
      _pushSinPermiso = false;

      await AuthService().logout();
      // Las credenciales biométricas sobreviven al logout a propósito.
      // Borrarlas aquí dejaba el acceso con huella inservible: la pantalla de
      // login solo se ve después de cerrar sesión (con sesión viva, main.dart
      // va directo al dashboard), o sea justo cuando la huella acababa de ser
      // borrada. El botón existía únicamente en un estado inalcanzable.
      // Quien quiera desvincular la cuenta tiene el interruptor en el menú.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } finally {
      // Se libera siempre: si algo de la cadena lanzara, dejar la guarda puesta
      // significaría un usuario que ya no puede cerrar sesión hasta reiniciar la
      // app. Tras el pushReplacement este State ya está muerto y da igual.
      _cerrandoSesion = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final versionLabel = _patchNumber != null ? 'v1.0.1 ($_patchNumber)' : 'v1.0.1';
        return wide
            ? _WideShell(index: _index, onSelect: _setIndex, onLogout: _logout, versionLabel: versionLabel)
            : _NarrowShell(index: _index, onSelect: _setIndex, onLogout: _logout, versionLabel: versionLabel);
      },
    );
  }

  void _setIndex(int i) => setState(() => _index = i);
}

// ── WIDE (sidebar rail) ───────────────────────────────────────────────────────
class _WideShell extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final String versionLabel;

  const _WideShell(
      {required this.index, required this.onSelect, required this.onLogout, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      // Sin AppBar que reserve el hueco de arriba (como sí hace _NarrowShell),
      // este layout arrancaba en el píxel 0: el reloj y la batería se comían
      // las pestañas de sucursal y el selector de fecha, y abajo la barra de
      // navegación (o la taskbar de las tablets Samsung) cortaba las gráficas.
      //
      // El SafeArea no envuelve al Row entero a propósito: eso encogería
      // también los fondos y dejaría franjas del color del Scaffold detrás de
      // las barras del sistema. Cada columna pinta hasta el borde y mete el
      // hueco puertas adentro.
      body: Row(
        children: [
          _Rail(index: index, onSelect: onSelect, onLogout: onLogout, versionLabel: versionLabel),
          Container(width: 1, color: Colors.white.withOpacity(0.05)),
          Expanded(
            // left: false — el hueco lateral izquierdo ya lo absorbió el rail.
            child: SafeArea(
              left: false,
              child: _PageContent(index: index),
            ),
          ),
        ],
      ),
    );
  }
}

// ── NARROW (bottom nav) ───────────────────────────────────────────────────────
class _NarrowShell extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final String versionLabel;

  const _NarrowShell(
      {required this.index, required this.onSelect, required this.onLogout, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        // En iOS/macOS AppBar centra el título cuando hay menos de 2 actions.
        // Al ocultar el selector de fecha en Despensa la lista queda vacía y el
        // título se corría al centro; se fija a la izquierda siempre.
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sabor Manager',
              style: GoogleFonts.inter(
                color: const Color(0xFF7444fd),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              versionLabel,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          // Despensa muestra existencias al día de hoy, no un rango de fechas:
          // ahí el selector no tendría efecto y solo confundiría.
          if (index != 2) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: const DateSelectorChip(),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: _PageContent(index: index),
      bottomNavigationBar: _BottomNav(index: index, onSelect: onSelect, onLogout: onLogout),
    );
  }
}

// ── RAIL ──────────────────────────────────────────────────────────────────────
class _Rail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final String versionLabel;

  const _Rail(
      {required this.index, required this.onSelect, required this.onLogout, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      // El ancho incluye el hueco lateral: si el sistema reserva borde
      // izquierdo (gestos, notch en horizontal), los íconos se corrían fuera
      // de los 76px y quedaban cortados contra el separador.
      width: 76 + MediaQuery.of(context).padding.left,
      color: const Color(0xFF070E1A),
      // El color llega hasta arriba y abajo; lo que se aparta de las barras
      // del sistema es el contenido. right: false porque de ese lado no hay
      // borde de pantalla, hay más app.
      child: SafeArea(
        right: false,
        child: Column(
        children: [
          const SizedBox(height: 20),
          // Logo
          Image.asset(
            'assets/images/SaborManagerLogo.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 6),
          Text(
            'Sabor Manager',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            versionLabel,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),
          // Divider
          Container(height: 1, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 20),
          // Nav items
          _RailItem(
            icon: Icons.home_rounded,
            label: 'Inicio',
            active: index == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(height: 6),
          _RailItem(
            icon: Icons.stacked_bar_chart_rounded,
            label: 'Reportes',
            active: index == 1,
            onTap: () => onSelect(1),
          ),
          const SizedBox(height: 6),
          _RailItem(
            icon: Icons.inventory_2_rounded,
            label: 'Despensa',
            active: index == 2,
            onTap: () => onSelect(2),
          ),
          const SizedBox(height: 6),
          _RailItem(
            icon: Icons.notifications_rounded,
            label: 'Avisos',
            active: index == 3,
            onTap: () => onSelect(3),
            badge: context.watch<NotificationsProvider>().sinLeer,
          ),
          const Spacer(),
          // Menu
          GestureDetector(
            onTap: () => _showMenuModal(context, onLogout),
            child: Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_rounded,
                  color: Colors.white38, size: 20),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Cuántos sin leer. 0 no dibuja nada.
  final int badge;

  const _RailItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap,
      this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF7444fd).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(
                  color: const Color(0xFF7444fd).withOpacity(0.3), width: 1)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // El contador se pinta sobre el ícono sin agrandar la fila: el
            // rail mide 76px y una insignia que empuje el layout descoloca los
            // otros tres botones cada vez que entra un aviso.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon,
                    color:
                        active ? const Color(0xFF7444fd) : Colors.white38,
                    size: 22),
                if (badge > 0)
                  Positioned(right: -7, top: -5, child: _Badge(count: badge)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: active ? const Color(0xFF7444fd) : Colors.white38,
                fontSize: 10,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envuelve un ícono y le encima el contador. Para la barra inferior, donde el
/// ícono lo construye NavigationDestination y no se puede meter un Stack dentro.
class _ConBadge extends StatelessWidget {
  final int count;
  final Widget child;
  const _ConBadge({required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: -7, top: -5, child: _Badge(count: count)),
      ],
    );
  }
}

/// Contador de avisos sin leer.
///
/// Se corta en 99+: más allá de eso el número deja de informar y solo estira la
/// insignia hasta deformar el ícono que lleva debajo.
class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final texto = count > 99 ? '99+' : '$count';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: count > 9 ? 4.5 : 0),
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(9),
        // El borde del color del fondo despega la insignia del ícono cuando
        // los dos quedan encimados; sin él se leen como una sola mancha.
        border: Border.all(color: const Color(0xFF070E1A), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        texto,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

// ── BOTTOM NAV ────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _BottomNav({required this.index, required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF070E1A),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: Row(
          children: [
            Expanded(
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                indicatorColor: const Color(0xFF7444fd).withOpacity(0.2),
                selectedIndex: index,
                onDestinationSelected: onSelect,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined, color: Colors.white38),
                    selectedIcon: const Icon(Icons.home_rounded, color: Color(0xFF7444fd)),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.stacked_bar_chart_outlined, color: Colors.white38),
                    selectedIcon: const Icon(Icons.stacked_bar_chart_rounded, color: Color(0xFF7444fd)),
                    label: 'Reportes',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.inventory_2_outlined, color: Colors.white38),
                    selectedIcon: const Icon(Icons.inventory_2_rounded, color: Color(0xFF7444fd)),
                    label: 'Despensa',
                  ),
                  NavigationDestination(
                    icon: _ConBadge(
                      count: context.watch<NotificationsProvider>().sinLeer,
                      child: const Icon(Icons.notifications_none_rounded,
                          color: Colors.white38),
                    ),
                    selectedIcon: _ConBadge(
                      count: context.watch<NotificationsProvider>().sinLeer,
                      child: const Icon(Icons.notifications_rounded,
                          color: Color(0xFF7444fd)),
                    ),
                    label: 'Avisos',
                  ),
                ],
              ),
            ),
            // Menú
            GestureDetector(
              onTap: () => _showMenuModal(context, onLogout),
              child: SizedBox(
                width: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_rounded, color: Colors.white38, size: 24),
                    const SizedBox(height: 4),
                    Text('Más',
                        style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PAGE CONTENT ──────────────────────────────────────────────────────────────
class _PageContent extends StatelessWidget {
  final int index;
  const _PageContent({required this.index});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: IndexedStack(
        key: ValueKey(index),
        index: index,
        children: const [
          DashboardScreen(),
          ReportsListScreen(),
          InventoryScreen(),
          NotificationsScreen(),
        ],
      ),
    );
  }
}

// ── MENU MODAL ────────────────────────────────────────────────────────────────
void _showMenuModal(BuildContext context, VoidCallback onLogout) {
  final navBarHeight = MediaQuery.of(context).padding.bottom;
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    // El menú es alto (tipos de reporte + biometría + notificaciones + cerrar
    // sesión) y con isScrollControlled podía trepar hasta el reloj. El borde
    // de abajo ya lo cubre navBarHeight, que se midió arriba con el context
    // del rail — a propósito, porque ahí todavía no lo consumió ningún
    // SafeArea; useSafeArea solo agrega el de arriba.
    useSafeArea: true,
    builder: (_) => _MenuModal(onLogout: onLogout, navBarHeight: navBarHeight),
  );
}

enum _ReportType {
  caja('Reporte de Caja'),
  metodoPago('Ventas por Método de Pago'),
  platillos('Platillos vendidos'),
  inventario('Inventario'),

  // Solo Honduras. No son reportes de gestión: son dos obligaciones ante el
  // SAR, y el que las presenta es el contador una vez al mes.
  noUtilizados('Documentos no utilizados (SAR)', soloHonduras: true),
  resumenIsv('Resumen de ventas por ISV (SAR)', soloHonduras: true);

  final String label;
  final bool soloHonduras;
  const _ReportType(this.label, {this.soloHonduras = false});
}

class _MenuModal extends StatefulWidget {
  final VoidCallback onLogout;
  final double navBarHeight;
  const _MenuModal({required this.onLogout, this.navBarHeight = 0});

  @override
  State<_MenuModal> createState() => _MenuModalState();
}

class _MenuModalState extends State<_MenuModal> {
  _ReportType _selected = _ReportType.caja;
  bool _downloading = false;

  /// Los reportes del SAR solo se ofrecen si el tenant factura en Honduras:
  /// a un restaurante guatemalteco no le dicen nada.
  bool _esHonduras = false;

  List<_ReportType> get _reportesDisponibles => _ReportType.values
      .where((r) => !r.soloHonduras || _esHonduras)
      .toList();

  // Biometría — null mientras carga
  bool?  _biometricAvailable;
  bool   _biometricEnabled = false;
  String? _biometricError;
  BiometricKind _biometricKind = BiometricKind.fingerprint;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    _loadPaisFiscal();
  }

  Future<void> _loadPaisFiscal() async {
    final tenantId = context.read<DashboardProvider>().tenantId;
    if (tenantId == null) return;
    final esHn = await FiscalReportsService().isHonduras(tenantId);
    if (!mounted) return;
    setState(() => _esHonduras = esHn);
  }

  Future<void> _loadBiometricState() async {
    final available = await BiometricService().isHardwarePresent();
    final enabled   = await BiometricService().isEnabled();
    final kind      = await BiometricService().detectKind();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled   = enabled;
        _biometricKind      = kind;
      });
    }
  }

  IconData get _biometricIcon => switch (_biometricKind) {
        BiometricKind.faceId ||
        BiometricKind.faceAndroid =>
          Icons.face_retouching_natural,
        _ => Icons.fingerprint,
      };

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      final email    = AuthService().sessionEmail;
      final password = AuthService().sessionPassword;
      if (email != null && password != null) {
        // Credenciales completas en sesión → activar directo sin diálogo
        await _activateBiometricWithCredentials(email, password);
      } else {
        // Solo tenemos email (sesión restaurada) → pedir solo contraseña
        await _showBiometricSetupDialog();
      }
    } else {
      await BiometricService().clearCredentials();
      if (mounted) setState(() {
        _biometricEnabled = false;
        _biometricError   = null;
      });
    }
  }

  Future<void> _activateBiometricWithCredentials(
      String email, String password) async {
    final hasEnrolled = await BiometricService().isAvailable();
    if (!hasEnrolled) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(_biometricIcon, color: const Color(0xFF7444fd), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Sin ${_biometricKind.label} registrada',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            content: Text(
              'Este dispositivo no tiene ${_biometricKind.label} registrada.'
              '\n\n${_biometricKind.enrollHint}',
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7444fd),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('Entendido', style: GoogleFonts.inter()),
              ),
            ],
          ),
        );
      }
      return;
    }
    await BiometricService().saveCredentials(email, password);
    final auth = await BiometricService().authenticate(
      reason: 'Confirma tu ${_biometricKind.label} para activar el acceso rápido',
      email: email,
    );
    if (auth.success) {
      if (mounted) setState(() => _biometricEnabled = true);
    } else {
      // Solo esta cuenta: si el teléfono tiene otra vinculada, que una
      // activación fallida la desvincule sería castigar a la equivocada.
      await BiometricService().unlink(email);
      // Si el sensor falló de verdad (no fue el usuario cancelando), decirlo:
      // el interruptor volviendo solo a "apagado" no explica nada.
      if (mounted && auth.error != null) {
        setState(() => _biometricError = auth.error);
      }
    }
  }

  Future<void> _showBiometricSetupDialog() async {
    // Email: sesión en memoria > Firebase Auth > storage biométrico anterior
    final sessionEmail  = AuthService().sessionEmail ?? '';
    final firebaseEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final storedEmail   = await BiometricService().getStoredEmail() ?? '';
    final email = sessionEmail.isNotEmpty ? sessionEmail
        : firebaseEmail.isNotEmpty ? firebaseEmail
        : storedEmail;

    final emailCtrl = TextEditingController(text: email);
    final pwCtrl    = TextEditingController();
    bool obscure    = true;
    String? errorMsg;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFF7444fd), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Activar acceso con huella',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mostrar email como texto si ya lo tenemos, campo editable si no
              if (email.isNotEmpty) ...[
                Text(email,
                    style: GoogleFonts.inter(
                        color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 12),
              ] else ...[
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    labelStyle: GoogleFonts.inter(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: pwCtrl,
                obscureText: obscure,
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: GoogleFonts.inter(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                        size: 18),
                    onPressed: () => setStateDialog(() => obscure = !obscure),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: GoogleFonts.inter(
                        color: const Color(0xFFEF4444), fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar',
                  style: GoogleFonts.inter(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7444fd),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final resolvedEmail =
                    email.isNotEmpty ? email : emailCtrl.text.trim();
                if (resolvedEmail.isEmpty || pwCtrl.text.isEmpty) {
                  setStateDialog(
                      () => errorMsg = 'Ingresa tu correo y contraseña');
                  return;
                }
                final hasEnrolled = await BiometricService().isAvailable();
                if (!hasEnrolled) {
                  setStateDialog(() => errorMsg =
                      'No hay huellas registradas. Ve a Configuración → '
                      'Seguridad del dispositivo para registrar una.');
                  return;
                }
                await BiometricService()
                    .saveCredentials(resolvedEmail, pwCtrl.text);
                final auth = await BiometricService().authenticate(
                  reason: 'Confirma tu ${_biometricKind.label} para activar '
                      'el acceso rápido',
                  email: resolvedEmail,
                );
                if (auth.success) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  await BiometricService().unlink(resolvedEmail);
                  setStateDialog(() => errorMsg = auth.error ??
                      'No se pudo verificar tu ${_biometricKind.label}.');
                }
              },
              child: Text('Activar', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _biometricEnabled = true;
        _biometricError   = null;
      });
    }
  }

  Future<void> _download() async {
    final dp = context.read<DashboardProvider>();
    final ip = context.read<InventoryProvider>();
    if (dp.loading || ip.loading || _downloading) return;

    setState(() => _downloading = true);
    try {
      // La vista de año no baja las órdenes: los totales los suma Firestore.
      // Un Excel sí necesita cada fila, así que se piden a propósito y
      // paginadas, sin el tope que antes recortaba el período por detrás.
      // Fuera de la vista de año esto devuelve lo que ya está en memoria.
      //
      // Se pide dentro de cada reporte que las usa, y no antes del switch, para
      // que exportar inventario no arrastre un año de órdenes que no mira.
      switch (_selected) {
        case _ReportType.caja:
          final orders = await dp.ensureDetailedOrders();
          final orderDocIds = orders
              .map((o) => o['_docId'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
          final userIdsToResolve = orders
              .where((o) => (o['paid_by_user_name'] as String? ?? '').isEmpty)
              .map((o) => o['paid_by_user_id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          final results = await Future.wait([
            dp.fetchCertifiedInvoiceOrderIds(orderDocIds),
            dp.fetchUserNamesById(userIdsToResolve),
            dp.fetchCancelledOrders(),
          ]);
          final certifiedIds    = results[0] as Set<String>;
          final userNamesById   = results[1] as Map<String, String>;
          final cancelledOrders = results[2] as List<Map<String, dynamic>>;
          ExportService.exportCajaReport(
            orders,
            certifiedIds,
            userNamesById,
            dp.range.label,
            cancelledOrders: cancelledOrders,
          );
        case _ReportType.metodoPago:
          ExportService.exportPaymentMethodReport(
            await dp.ensureDetailedOrders(),
            dp.range.label,
          );
        case _ReportType.platillos:
          ExportService.exportProducts(
            dp.topProductsFrom(await dp.ensureDetailedOrders()),
            dp.range.prevLabel,
          );
        case _ReportType.inventario:
          ExportService.exportInventory(ip.items, ip.locations);

        case _ReportType.noUtilizados:
          final tenantId = dp.tenantId;
          if (tenantId == null) break;
          final numeros = await FiscalReportsService()
              .unusedNumbers(tenantId: tenantId);
          ExportService.exportUnusedNumbers(numeros, dp.range.label);

        case _ReportType.resumenIsv:
          final tenantId = dp.tenantId;
          if (tenantId == null) break;
          final resumen = await FiscalReportsService().isvSummary(
            tenantId: tenantId,
            from: dp.range.start,
            to: dp.range.end,
          );
          ExportService.exportIsvSummary(resumen, dp.range.label);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DashboardProvider>();
    final ip = context.watch<InventoryProvider>();
    final isLoading = dp.loading || ip.loading || _downloading;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + widget.navBarHeight + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sección Reportes
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Reportes',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${dp.range.label})',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButton<_ReportType>(
                    value: _selected,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: const Color(0xFF1E293B),
                    iconEnabledColor: Colors.white38,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    items: _reportesDisponibles
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selected = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isLoading ? null : _download,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7444fd).withOpacity(isLoading ? 0.06 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF7444fd).withOpacity(isLoading ? 0.1 : 0.3)),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF7444fd),
                          ),
                        )
                      : const Icon(Icons.download_rounded,
                          color: Color(0xFF7444fd), size: 20),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 4),

          // Biometría (solo Android/iOS con soporte)
          if (_biometricAvailable == true) ...[
            GestureDetector(
              onTap: () => _toggleBiometric(!_biometricEnabled),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _biometricIcon,
                      color: _biometricEnabled
                          ? const Color(0xFF7444fd)
                          : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _biometricKind.settingsLabel,
                        style: GoogleFonts.inter(
                          color: _biometricEnabled
                              ? Colors.white70
                              : Colors.white38,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _biometricEnabled,
                      onChanged: _toggleBiometric,
                      activeColor: const Color(0xFF7444fd),
                      activeTrackColor:
                          const Color(0xFF7444fd).withOpacity(0.3),
                      inactiveThumbColor: Colors.white38,
                      inactiveTrackColor: Colors.white12,
                    ),
                  ],
                ),
              ),
            ),
            // _biometricError se venía asignando sin pintarse en ningún lado:
            // el interruptor rebotaba a apagado y el usuario no sabía por qué.
            if (_biometricError != null)
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 8),
                child: Text(
                  _biometricError!,
                  style: GoogleFonts.inter(
                      color: const Color(0xFFEF4444), fontSize: 12, height: 1.4),
                ),
              ),
            Divider(color: Colors.white.withOpacity(0.06)),
            const SizedBox(height: 4),
          ],

          // Notificaciones
          GestureDetector(
            onTap: () {
              // El Navigator se toma ANTES del pop: después de cerrar la hoja,
              // este context ya está muerto y el push explotaría.
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.notifications_outlined,
                      color: Colors.white38, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notificaciones',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 4),

          // Botón Salir
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.logout_rounded,
                      color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Cerrar sesión',
                    style: GoogleFonts.inter(
                      color: Color(0xFFEF4444),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
