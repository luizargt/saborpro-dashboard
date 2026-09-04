import 'package:firebase_messaging/firebase_messaging.dart';
// defaultTargetPlatform y no dart:io: este archivo también se compila para web,
// donde Platform.* lanza UnsupportedError en cuanto se toca.
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../presentation/providers/notification_settings_provider.dart';
import '../../../presentation/widgets/max_content_width.dart';

/// Pantalla de preferencias de notificaciones push.
///
/// Todo llega activado por defecto: quien no quiera un tipo de aviso lo apaga
/// aquí. El provider guarda el cambio en users/{uid}.notification_preferences,
/// que es lo que consultan las Cloud Functions antes de encolar el envío.
///
/// Se abre con Navigator.push desde el menú. NO se da por hecho que el provider
/// ya venga inicializado: AppShell lo carga al iniciar sesión, pero puede no
/// haber llegado todavía (o haber salido sin uid), y antes eso dejaba esta
/// pantalla girando para siempre. Ahora se inicializa sola si hace falta, y con
/// el mismo fallback de uid que usa el shell.
///
/// Además consulta el permiso REAL del sistema: los switches de Firestore no
/// sirven de nada si el teléfono tiene bloqueadas las notificaciones de la app,
/// y sin este aviso la pantalla mentía mostrándolo todo encendido.
///
/// Esa consulta SOLO manda donde hay FCM (Android/iOS). Sabor Manager también
/// se sirve como web en el sitio `saborprodashboard`, y ahí NotificationService
/// declara la plataforma no soportada y nunca registra token: pintar el aviso
/// de permiso en el navegador era regañar al usuario por algo que no depende de
/// él y, si aceptaba el prompt del navegador, dejarlo creyendo que ya le llegan
/// avisos que este build jamás va a entregar.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  // Etiqueta, subtítulo e ícono de cada preferencia, en el orden en que se
  // muestran. Las llaves son las mismas que usa NotificationSettingsProvider.
  static const Map<String, _PrefCopy> _copy = {
    'cash_open': _PrefCopy(
      title: 'Apertura de caja',
      subtitle: 'Cuando un usuario abre caja en una sucursal',
      icon: Icons.lock_open_rounded,
    ),
    'cash_close': _PrefCopy(
      title: 'Cierre de caja',
      subtitle: 'Incluye si cuadró y el monto de venta',
      icon: Icons.lock_rounded,
    ),
    'expense': _PrefCopy(
      title: 'Gastos',
      subtitle: 'Cuando se registra un gasto',
      icon: Icons.receipt_long_rounded,
    ),
    'inventory_movement': _PrefCopy(
      title: 'Movimientos de inventario',
      subtitle: 'Entradas, salidas y ajustes',
      icon: Icons.inventory_2_rounded,
    ),
    'low_stock_summary': _PrefCopy(
      title: 'Resumen de stock bajo',
      subtitle: 'Una vez al día, a las 8:00 a.m.',
      icon: Icons.warning_amber_rounded,
    ),
  };

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  /// Permiso del sistema. null = todavía no se leyó o la lectura falló.
  ///
  /// null NO significa "plataforma sin FCM", como se suponía antes: en web el
  /// plugin no lanza, devuelve `notDetermined` mientras el navegador no haya
  /// preguntado (firebase_messaging_web mapea el permiso 'default' del
  /// navegador a notDetermined), y con eso el dashboard pintaba el aviso ámbar
  /// siempre. Quien decide si el aviso aplica es [_soportaPush].
  AuthorizationStatus? _permiso;

  /// Si esta plataforma puede recibir push. En web, Windows, Linux y macOS es
  /// false: no hay permiso que pedir ni token que registrar, así que toda la
  /// sección de permiso sobra (los switches NO: son preferencias del usuario,
  /// se guardan en Firestore y aplican a su teléfono).
  final bool _soportaPush = NotificationService().isSupported;

  /// Ya se pidió el permiso desde esta pantalla y no se concedió.
  ///
  /// Hace falta porque en Android el estado NUNCA es notDetermined: el plugin
  /// solo manda 1 (concedido) o 0 (denegado), así que por el estado no hay
  /// manera de saber si el diálogo nativo todavía puede salir. Con esta bandera
  /// el primer toque intenta el diálogo y, si no hubo permiso, el siguiente ya
  /// ofrece los Ajustes del sistema.
  bool _pedidoSinExito = false;

  /// Hay una petición de permiso/token en curso: el botón se bloquea para que
  /// un doble toque no dispare dos diálogos nativos ni dos escrituras.
  bool _resolviendo = false;

  /// Si esta pantalla es la que va a cargar las preferencias. Se decide en
  /// initState para que el primer frame ya muestre el spinner y no los valores
  /// por defecto durante un instante.
  bool _esperandoAutoInit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final provider = context.read<NotificationSettingsProvider>();
    // `isLoggedIn` y no `firestoreUid`: con la sesión viva el uid puede venir
    // null y aparecer recién al leer el almacenamiento seguro (ver
    // _asegurarPreferencias). Mirando solo firestoreUid se pintaban los valores
    // por defecto y un instante después saltaba el spinner con los reales.
    _esperandoAutoInit = !provider.initialized && AuthService().isLoggedIn;

    _revisarPermiso();
    // Post-frame porque init() llama a notifyListeners() de forma síncrona, y
    // hacerlo mientras el árbol se está construyendo lanza markNeedsBuild.
    WidgetsBinding.instance.addPostFrameCallback((_) => _asegurarPreferencias());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de los Ajustes del sistema el aviso tiene que desaparecer solo;
    // si no, el usuario haría lo correcto y la pantalla seguiría regañándolo.
    if (state == AppLifecycleState.resumed) _revisarPermiso();
  }

  /// Carga las preferencias si nadie más lo hizo (ver doc de la clase).
  Future<void> _asegurarPreferencias() async {
    if (!mounted) return;
    var provider = context.read<NotificationSettingsProvider>();
    if (provider.initialized || provider.loading) return;

    // Mismo fallback que AppShell (_uidDeSesion): al restaurar la sesión, la
    // consulta por `firebase_uid` puede expirar y dejar `firestoreUid` en null
    // con la sesión viva. Rendirse ahí no solo mostraba valores por defecto:
    // el provider se quedaba sin uid y cada switch que el usuario tocara se
    // veía cambiar sin llegar nunca a Firestore.
    final uid =
        AuthService().firestoreUid ?? await AuthService().readPersistedUid();
    if (!mounted) return;

    // Releer el provider: mientras se leía el almacenamiento seguro, el shell
    // pudo arrancar su propia carga y duplicarla no tiene sentido.
    provider = context.read<NotificationSettingsProvider>();
    if (provider.initialized || provider.loading) return;

    if (uid != null) {
      provider.init(uid);
      return;
    }

    // Sin uid no hay documento que leer y nadie más lo va a cargar, así que el
    // spinner se apaga y se muestran los valores por defecto (todo encendido,
    // la regla opt-out). Mostrar los switches encendidos es mucho menos malo
    // que dejar la pantalla girando para siempre.
    setState(() => _esperandoAutoInit = false);
  }

  Future<void> _revisarPermiso() async {
    // Sin FCM no hay permiso que consultar: en web la llamada ni siquiera
    // lanza, devuelve notDetermined, y ese dato solo serviría para acusar al
    // usuario de algo que este build no puede hacer de todos modos.
    if (!_soportaPush) return;

    AuthorizationStatus? estado;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      estado = settings.authorizationStatus;
    } catch (e) {
      // Si la lectura falla no se sabe nada, y sin dato no se muestra el aviso.
      debugPrint('[Notifs] No se pudo leer el permiso del sistema: $e');
      estado = null;
    }
    if (!mounted) return;
    setState(() => _permiso = estado);
  }

  /// ¿Todavía se puede mostrar el diálogo nativo, o solo queda mandar al
  /// usuario a los Ajustes del sistema?
  ///
  /// Mismo criterio que NotificationService.ensurePermissionAndToken: en
  /// Android el diálogo se puede intentar siempre (el estado inicial ya llega
  /// como `denied`, nunca notDetermined, así que exigir notDetermined dejaba el
  /// botón "Activar avisos" inalcanzable); en iOS solo mientras Apple no haya
  /// registrado un rechazo, porque después el diálogo no vuelve a salir jamás.
  bool get _puedePedirEnLaApp {
    if (_pedidoSinExito) return false;
    final esAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return esAndroid || _permiso == AuthorizationStatus.notDetermined;
  }

  /// Acción del botón del aviso.
  Future<void> _resolverPermiso() async {
    if (_resolviendo) return;

    if (!_puedePedirEnLaApp) {
      try {
        await openAppSettings();
      } catch (e) {
        // permission_handler solo implementa Android e iOS. En macOS reventaría
        // con MissingPluginException y se llevaría la app por un botón lateral.
        debugPrint('[Notifs] No se pudieron abrir los Ajustes: $e');
      }
      return;
    }

    setState(() => _resolviendo = true);
    try {
      // Se delega en el servicio en vez de llamar a requestPermission a secas:
      // conceder el permiso aquí no registraba el token, o sea que el aviso
      // ámbar desaparecía (señal de "ya está") mientras users/{uid}.fcm_tokens
      // seguía sin este dispositivo y nada volvía a intentarlo.
      final uid =
          AuthService().firestoreUid ?? await AuthService().readPersistedUid();

      if (uid != null) {
        // Timeout porque ensurePermissionAndToken termina escribiendo en
        // Firestore y sin servidor ese future no resuelve nunca: sin él, el
        // botón se quedaría bloqueado para siempre. Si vence, igual se relee el
        // permiso real más abajo.
        final resultado = await NotificationService()
            .ensurePermissionAndToken(uid)
            .timeout(const Duration(seconds: 20));

        // Solo `permisoDenegado` justifica seguir insistiendo. Con el permiso
        // dado y el token fallido (en iOS, apns-token-not-set en el primer
        // arranque) mandarlo a Ajustes sería mentirle: el listener de
        // onTokenRefresh guarda el token en cuanto FCM entregue uno.
        if (resultado == ResultadoPush.permisoDenegado) _pedidoSinExito = true;
      } else {
        // Sin uid no hay dónde guardar el token, pero el permiso sí se puede
        // pedir; el token lo recoge el shell en el próximo inicio de sesión.
        final r = await FirebaseMessaging.instance
            .requestPermission(alert: true, badge: true, sound: true);
        final concedido =
            r.authorizationStatus == AuthorizationStatus.authorized ||
                r.authorizationStatus == AuthorizationStatus.provisional;
        if (!concedido) _pedidoSinExito = true;
      }
    } catch (e) {
      debugPrint('[Notifs] Falló activar los avisos: $e');
    } finally {
      if (mounted) {
        setState(() => _resolviendo = false);
        // El estado real lo dicta el sistema, no lo que devolvió la llamada:
        // se relee y de ahí sale si el aviso se oculta o se queda.
        await _revisarPermiso();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationSettingsProvider>();

    // El spinner solo mientras HAY una lectura en curso (o está por arrancar la
    // de esta pantalla). Nunca por defecto: ese era el bug del spinner eterno.
    final cargando =
        provider.loading || (_esperandoAutoInit && !provider.initialized);

    // notDetermined cuenta igual que denied: en ambos casos no llega ni un
    // aviso. En iOS es el estado de quien nunca llegó a ver el diálogo nativo;
    // en Android no existe (el plugin solo manda concedido o denegado).
    //
    // Todo eso SOLO donde hay FCM: en web notDetermined es el valor normal del
    // navegador que nunca preguntó, y el aviso ahí no arregla nada porque el
    // build web no registra token pase lo que pase con el permiso.
    final bloqueado = _soportaPush &&
        (_permiso == AuthorizationStatus.denied ||
            _permiso == AuthorizationStatus.notDetermined);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Notificaciones',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7444fd)),
            )
          : MaxContentWidth(
              maxWidth: 720,
              child: ListView(
                // El 32 fijo aguanta la barra de gestos pero no los 48dp de la
                // de tres botones, y esta pantalla se abre con push (sin la
                // bottom nav de la app debajo, que es la que normalmente
                // reserva ese borde). Sumar el inset deja el último interruptor
                // alcanzable en cualquier teléfono.
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
                children: [
                  // Solo si de verdad está bloqueado: si todo está bien, no
                  // ocupa ni un píxel.
                  if (bloqueado) ...[
                    _PermisoBloqueadoCard(
                      puedePedirEnLaApp: _puedePedirEnLaApp,
                      ocupado: _resolviendo,
                      onAccion: _resolverPermiso,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _IntroCard(soportaPush: _soportaPush),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < NotificationSettingsProvider.keys.length;
                            i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 16,
                              endIndent: 16,
                              color: Colors.white.withOpacity(0.06),
                            ),
                          _PrefRow(
                            prefKey: NotificationSettingsProvider.keys[i],
                            copy: NotificationSettingsScreen
                                ._copy[NotificationSettingsProvider.keys[i]]!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── TEXTO DE CADA PREFERENCIA ─────────────────────────────────────────────────
class _PrefCopy {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PrefCopy({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

// ── AVISO DE PERMISO BLOQUEADO ────────────────────────────────────────────────
/// Solo se pinta cuando el sistema tiene bloqueadas (o nunca autorizadas) las
/// notificaciones de Sabor Manager, y solo en plataformas con FCM. Mismo
/// formato que _IntroCard pero en ámbar (0xFFF59E0B, el color de alerta que ya
/// usa el resto del dashboard), para que se lea como advertencia y no como otro
/// párrafo informativo.
class _PermisoBloqueadoCard extends StatelessWidget {
  /// El diálogo nativo todavía puede salir: el botón lo pide desde aquí. Si es
  /// false ya no hay más que hacer dentro de la app y toca ir a los Ajustes.
  final bool puedePedirEnLaApp;

  /// Petición en curso: el botón se bloquea y muestra que está trabajando.
  final bool ocupado;

  final Future<void> Function() onAccion;

  const _PermisoBloqueadoCard({
    required this.puedePedirEnLaApp,
    required this.ocupado,
    required this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    const ambar = Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ambar.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ambar.withOpacity(0.35)),
      ),
      // Column y no Row con el botón al lado: a 360dp el texto más el botón en
      // la misma fila no entran sin apretujar ninguno de los dos.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.notifications_off_rounded,
                color: ambar,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      puedePedirEnLaApp
                          ? 'Falta activar las notificaciones'
                          : 'Tu teléfono tiene bloqueadas las notificaciones',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // Corto a propósito: a 360dp cada frase de más empuja los
                      // switches fuera de la pantalla.
                      puedePedirEnLaApp
                          ? 'Todavía no le diste permiso a Sabor Manager para '
                              'avisarte. Aunque abajo esté todo encendido, no '
                              'te va a llegar nada.'
                          : 'Están apagadas en los ajustes del teléfono. '
                              'Aunque abajo esté todo encendido, no te va a '
                              'llegar nada.',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              // Bloqueado mientras se pide el permiso y se guarda el token: dos
              // toques seguidos sacarían dos diálogos nativos.
              onPressed: ocupado ? null : () => onAccion(),
              style: ElevatedButton.styleFrom(
                backgroundColor: ambar,
                foregroundColor: const Color(0xFF0F172A),
                disabledBackgroundColor: ambar.withOpacity(0.55),
                disabledForegroundColor: const Color(0xFF0F172A),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: ocupado
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0F172A),
                      ),
                    )
                  : Icon(
                      puedePedirEnLaApp
                          ? Icons.notifications_active_rounded
                          : Icons.settings_rounded,
                      size: 18,
                    ),
              label: Text(
                ocupado
                    ? 'Activando…'
                    : (puedePedirEnLaApp ? 'Activar avisos' : 'Abrir Ajustes'),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── EXPLICACIÓN DE ARRIBA ─────────────────────────────────────────────────────
/// Explicación de qué son estos avisos.
///
/// En plataformas sin FCM (web, Windows, Linux, macOS) suma una línea: los
/// switches se guardan y valen, pero ESTE dispositivo no va a sonar. Se eligió
/// decirlo aquí en tono informativo en vez de dejar el aviso ámbar de permiso,
/// que acusaba al usuario de tener algo mal configurado cuando el que no
/// soporta push es el build.
class _IntroCard extends StatelessWidget {
  final bool soportaPush;

  const _IntroCard({required this.soportaPush});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF7444fd).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7444fd).withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_active_rounded,
            color: Color(0xFF7444fd),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Estos avisos llegan a tu teléfono cuando pasa algo en tus '
                  'sucursales. Cada tipo se puede apagar por separado; lo que '
                  'apagues aquí deja de llegarte solo a ti.',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (!soportaPush) ...[
                  const SizedBox(height: 8),
                  Text(
                    'En este dispositivo no vas a recibirlos, pero lo que '
                    'cambies aquí sí se guarda y aplica a tu teléfono.',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── FILA CON SWITCH ───────────────────────────────────────────────────────────
class _PrefRow extends StatelessWidget {
  final String prefKey;
  final _PrefCopy copy;

  const _PrefRow({required this.prefKey, required this.copy});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationSettingsProvider>();
    final on = provider.value(prefKey);

    // El provider revierte el switch si el cambio no se pudo guardar (por
    // ejemplo si se quedó sin uid). Revertirlo en silencio dejaría al usuario
    // creyendo que el toque no le registró, así que aquí se dice.
    Future<void> toggle(bool v) async {
      final guardado =
          await context.read<NotificationSettingsProvider>().setValue(prefKey, v);
      if (guardado || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el cambio. Intenta de nuevo.'),
        ),
      );
    }

    // GestureDetector opaco (y no InkWell) porque la tarjeta pinta su propio
    // fondo encima del Material del Scaffold: el ripple quedaría invisible.
    return GestureDetector(
      onTap: () => toggle(!on),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              copy.icon,
              color: on ? const Color(0xFF7444fd) : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 12),
            // Expanded para que a 360dp los títulos largos ("Movimientos de
            // inventario") bajen de línea en vez de desbordar la fila.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: on ? Colors.white : Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    copy.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: on,
              onChanged: toggle,
              activeColor: const Color(0xFF7444fd),
              activeTrackColor: const Color(0xFF7444fd).withOpacity(0.3),
              inactiveThumbColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
