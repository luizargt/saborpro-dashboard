import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
import '../../core/services/store_update_service.dart';
import '../../data/models/cortesias_data.dart';
import '../../presentation/providers/dashboard_provider.dart';
import '../../presentation/providers/inventory_provider.dart';
import '../../presentation/providers/notification_settings_provider.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/inventory/inventory_screen.dart';
import '../../presentation/screens/notifications/notifications_screen.dart';
import '../../presentation/providers/notifications_provider.dart';
import '../../presentation/screens/settings/moneda_settings_screen.dart';
import '../../presentation/screens/settings/notification_settings_screen.dart';
import '../../presentation/widgets/period_selector.dart';
import '../widgets/inicio_ui.dart' show InicioColores, InicioSegmentos, inicioTexto, kInicioQuiebreTelefono;
import '../../data/models/despensa_data.dart';
import '../../core/theme/tema_manager.dart';
import '../../presentation/screens/dashboard/cortesias_screen.dart';
import '../../presentation/screens/dashboard/propinas_screen.dart';
import '../../presentation/screens/reports/cancelled_orders_report_screen.dart';
import '../../presentation/screens/reports/cash_closures_report_screen.dart';
import '../../presentation/screens/reports/compras_ventas_screen.dart';
import '../../presentation/screens/reports/expenses_report_screen.dart';
import '../../presentation/screens/reports/profitability_report_screen.dart';
import '../controllers/descargas_controller.dart';
import '../navigation/contexto_shell.dart';
import '../navigation/destinos.dart';
import '../widgets/barra_inferior.dart';
import '../widgets/barra_lateral.dart';
import '../widgets/dialogo_descargas.dart';
import '../widgets/encabezado_movil.dart';
import '../widgets/encabezado_pagina.dart';
import '../widgets/menu_cuenta.dart';
import '../widgets/paleta_de_comandos.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  /// A dónde se está mirando.
  Destino _destino = Destino.inicio;

  /// La barra lateral contraída a mano (solo en pantallas muy anchas), y en tablet, la
  /// barra expandida encima del contenido.
  bool _barraContraida = false;
  bool _barraAbierta = false;

  /// El panel de la cuenta (pantalla ancha) abierto.
  bool _cuentaAbierta = false;

  /// El negocio factura en Honduras: se ofrecen los reportes del SAR.
  bool _esHonduras = false;

  // Biometría — null mientras carga
  bool?  _biometricAvailable;
  bool   _biometricEnabled = false;
  String? _biometricError;
  BiometricKind _biometricKind = BiometricKind.fingerprint;


  /// Avisa a la hoja "Más" del teléfono (otra ruta) que algo cambió.
  final _tick = ValueNotifier<int>(0);
  int? _patchNumber;
  // La versión instalada de verdad. Antes el menú decía "v1.0.1" fijo en el
  // código, así que un teléfono al día con la 1.1.5 parecía viejo y daba a
  // entender que el aviso de actualización no funcionaba.
  String? _version;

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
    _loadBiometricState();
    StoreUpdateService().currentVersion().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _version = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = AuthService().tenantId;
      if (id != null) {
        context.read<DashboardProvider>().init(id);
        context.read<InventoryProvider>().init(id);
      }
      _setupNotificaciones();
      _cargarPaisFiscal();
    });
  }

  @override
  void dispose() {
    pestanaSolicitada.removeListener(_atenderPestanaSolicitada);
    WidgetsBinding.instance.removeObserver(this);
    _tick.dispose();
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
      setState(() => _destino = Destinos.dePestana(pedida) ?? _destino);
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
        backgroundColor: InicioColores.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.notifications_active_rounded,
                color: InicioColores.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Activa las notificaciones',
                  style: GoogleFonts.inter(
                      color: InicioColores.ink,
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
              color: InicioColores.muted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Ahora no',
                style: GoogleFonts.inter(color: InicioColores.soft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: InicioColores.accent,
              foregroundColor: InicioColores.onAccent,
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
      _pushSinPermiso = false;

      // No AuthService().logout() a secas: esto además deja al teléfono sin
      // los avisos de caja, gastos e inventario de la cuenta que abandona.
      await NotificationService().cerrarSesionYDesvincular();
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

  Future<void> _loadBiometricState() async {
    final available = await BiometricService().isHardwarePresent();
    final enabled   = await BiometricService().isEnabled();
    final kind      = await BiometricService().detectKind();
    if (mounted) {
      _cambiar(() {
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
      if (mounted) _cambiar(() {
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
            backgroundColor: InicioColores.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(_biometricIcon, color: InicioColores.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Sin ${_biometricKind.label} registrada',
                    style: GoogleFonts.inter(
                        color: InicioColores.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            content: Text(
              'Este dispositivo no tiene ${_biometricKind.label} registrada.'
              '\n\n${_biometricKind.enrollHint}',
              style: GoogleFonts.inter(
                  color: InicioColores.muted, fontSize: 14, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: InicioColores.accent,
                  foregroundColor: InicioColores.onAccent,
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
      if (mounted) _cambiar(() => _biometricEnabled = true);
    } else {
      // Solo esta cuenta: si el teléfono tiene otra vinculada, que una
      // activación fallida la desvincule sería castigar a la equivocada.
      await BiometricService().unlink(email);
      // Si el sensor falló de verdad (no fue el usuario cancelando), decirlo:
      // el interruptor volviendo solo a "apagado" no explica nada.
      if (mounted && auth.error != null) {
        _cambiar(() => _biometricError = auth.error);
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
          backgroundColor: InicioColores.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.fingerprint, color: InicioColores.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Activar acceso con huella',
                    style: GoogleFonts.inter(
                        color: InicioColores.ink,
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
                        color: InicioColores.muted, fontSize: 13)),
                const SizedBox(height: 12),
              ] else ...[
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(color: InicioColores.ink, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    labelStyle: GoogleFonts.inter(color: InicioColores.soft),
                    filled: true,
                    fillColor: InicioColores.bg,
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
                style: GoogleFonts.inter(color: InicioColores.ink, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: GoogleFonts.inter(color: InicioColores.soft),
                  filled: true,
                  fillColor: InicioColores.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: InicioColores.soft,
                        size: 18),
                    onPressed: () => setStateDialog(() => obscure = !obscure),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: GoogleFonts.inter(
                        color: InicioColores.bad, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar',
                  style: GoogleFonts.inter(color: InicioColores.soft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: InicioColores.accent,
                foregroundColor: InicioColores.onAccent,
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
      _cambiar(() {
        _biometricEnabled = true;
        _biometricError   = null;
      });
    }
  }

  Future<void> _cargarPaisFiscal() async {
    final tenantId = context.read<DashboardProvider>().tenantId;
    if (tenantId == null) return;
    final esHn = await FiscalReportsService().isHonduras(tenantId);
    if (!mounted) return;
    setState(() => _esHonduras = esHn);
  }

  /// El estado de la biometría cambió: se repinta el shell y también la hoja "Más" del
  /// teléfono, que vive en su propia ruta y no se entera de los `setState` de aquí.
  void _cambiar(VoidCallback f) {
    if (!mounted) return;
    setState(f);
    _tick.value++;
  }

  // ── A dónde se va ──────────────────────────────────────────────────────────

  void _ir(Destino d) {
    if (d == Destino.descargas) {
      _abrirDescargas();
      return;
    }
    setState(() {
      _destino = d;
      _barraAbierta = false;
      _cuentaAbierta = false;
    });
  }

  Future<void> _abrirBuscador() async {
    final d = await mostrarPaletaDeComandos(context, actual: _destino);
    if (d != null && mounted) _ir(d);
  }

  void _abrirReportes() {
    mostrarHojaManager<void>(
      context,
      builder: (ctx) => HojaReportes(
        actual: _destino,
        datos: const {},
        alertas: const {},
        onElegir: (d) {
          Navigator.of(ctx).pop();
          _ir(d);
        },
      ),
    );
  }

  void _abrirMas(String nombre, int sucursales, String versionLabel) {
    final hayOtraMoneda = context.read<DashboardProvider>().hayOtraMoneda;
    mostrarHojaManager<void>(
      context,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: _tick,
        builder: (_, __, ___) => HojaMas(
          nombre: nombre,
          rol: _rol,
          sucursales: sucursales,
          version: versionLabel,
          actual: _destino,
          onBuscar: () {
            Navigator.of(ctx).pop();
            _abrirBuscador();
          },
          onDescargas: () {
            Navigator.of(ctx).pop();
            _abrirDescargas();
          },
          onNotificaciones: () {
            Navigator.of(ctx).pop();
            _ir(Destino.notificaciones);
          },
          onCerrarSesion: () {
            Navigator.of(ctx).pop();
            _logout();
          },
          extras: _extras(grande: true, hayOtraMoneda: hayOtraMoneda, cerrar: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }

  static const _rol = 'Administrador';

  /// Lo que la app trae además de lo que dibujó el diseño: apariencia, biometría y
  /// moneda. En la hoja del teléfono ([grande]) las filas son más altas.
  List<Widget> _extras({required bool grande, required bool hayOtraMoneda, required VoidCallback cerrar}) {
    return [
      _SelectorApariencia(sangria: grande ? 4 : 10),
      if (_biometricAvailable == true) _filaBiometria(grande: grande),
      if (hayOtraMoneda)
        FilaMenu(
          grande: grande,
          icono: Icons.currency_exchange_rounded,
          texto: 'Moneda y tipo de cambio',
          onTap: () {
            // El Navigator se toma ANTES de cerrar: después, este context ya no sirve.
            final navigator = Navigator.of(context);
            cerrar();
            navigator.push(MaterialPageRoute(builder: (_) => const MonedaSettingsScreen()));
          },
        ),
    ];
  }

  Widget _filaBiometria({required bool grande}) {
    final activa = _biometricEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleBiometric(!activa),
          child: Padding(
            padding: EdgeInsets.fromLTRB(grande ? 10 : 10, grande ? 4 : 0, grande ? 4 : 4, grande ? 4 : 0),
            child: Row(
              children: [
                Icon(_biometricIcon, color: activa ? InicioColores.accent : InicioColores.muted, size: grande ? 20 : 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _biometricKind.settingsLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: inicioTexto(grande ? 15 : 14, grande ? FontWeight.w600 : FontWeight.w500, InicioColores.ink, height: 1.3),
                  ),
                ),
                Switch(
                  value: activa,
                  onChanged: _toggleBiometric,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: InicioColores.accent,
                  activeTrackColor: InicioColores.accent.withOpacity(0.3),
                  inactiveThumbColor: InicioColores.soft,
                  inactiveTrackColor: InicioColores.line,
                ),
              ],
            ),
          ),
        ),
        // El motivo por el que el interruptor rebotó a apagado.
        if (_biometricError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text(_biometricError!, style: inicioTexto(12, FontWeight.w400, InicioColores.bad, height: 1.4)),
          ),
      ],
    );
  }

  // ── Descargas ──────────────────────────────────────────────────────────────

  /// Lo que hay para descargar. Los del SAR solo si el negocio factura en Honduras:
  /// a un restaurante guatemalteco no le dicen nada.
  List<ItemDescarga> get _itemsDescarga => [
        const ItemDescarga('caja', Icons.point_of_sale_rounded, 'Reporte de caja', 'Ventas, cortesías y cancelados del período, para cuadrar con la caja'),
        const ItemDescarga('metodos', Icons.credit_card_rounded, 'Ventas por método de pago', 'Efectivo, tarjeta y demás, con su total'),
        const ItemDescarga('platillos', Icons.restaurant_menu_rounded, 'Platillos vendidos', 'Cuántos se vendieron de cada platillo y por cuánto'),
        const ItemDescarga('inventario', Icons.inventory_2_outlined, 'Inventario', 'Lo que tienes de cada producto en cada sucursal'),
        if (_esHonduras) const ItemDescarga('sar_no_utilizados', Icons.receipt_long_rounded, 'Documentos no utilizados (SAR)', 'Los números de factura que no se usaron'),
        if (_esHonduras) const ItemDescarga('sar_isv', Icons.summarize_outlined, 'Resumen de ventas por ISV (SAR)', 'Lo vendido y el impuesto de cada tasa'),
      ];

  Future<void> _abrirDescargas() async {
    final dp = context.read<DashboardProvider>();
    final controlador = DescargasController(items: _itemsDescarga, ejecutar: _ejecutarDescarga);

    // Lo que ya salió era de otro mes o de otra sucursal: deja de marcarse "Listo".
    String huella() => '${dp.range.label}|${dp.selectedLocationId}';
    var ultima = huella();
    void alCambiar() {
      final ahora = huella();
      if (ahora == ultima) return;
      ultima = ahora;
      controlador.reiniciar();
    }

    dp.addListener(alCambiar);
    try {
      await mostrarDescargas(
        context,
        controlador: controlador,
        selectorPeriodo: const DateSelectorChip(),
        sucursales: [
          (id: null, nombre: 'Todas'),
          for (final l in dp.locations) (id: l.id, nombre: l.name),
        ],
        sucursalElegida: () => dp.selectedLocationId,
        onSucursal: dp.selectLocation,
      );
    } finally {
      dp.removeListener(alCambiar);
      controlador.dispose();
    }
  }

  /// Genera un Excel con el mes y la sucursal que están elegidos.
  Future<void> _ejecutarDescarga(ItemDescarga item) async {
    final dp = context.read<DashboardProvider>();
    final ip = context.read<InventoryProvider>();
    if (dp.loading || ip.loading) throw StateError('Los datos todavía se están cargando');

    // La vista de año no baja las órdenes: los totales los suma Firestore. Un Excel sí
    // necesita cada fila, así que se piden a propósito y paginadas, sin el tope que
    // antes recortaba el período por detrás. Fuera de la vista de año esto devuelve lo
    // que ya está en memoria.
    //
    // Se pide dentro de cada reporte que las usa, y no antes del switch, para que
    // exportar inventario no arrastre un año de órdenes que no mira.
    switch (item.id) {
      case 'caja':
        // Sin convertir: este reporte se cuadra contra la caja.
        final orders = await dp.ensureDetailedOrdersLocal();
        final orderDocIds = orders.map((o) => o['_docId'] as String? ?? '').where((id) => id.isNotEmpty).toList();
        final userIdsToResolve = {
          ...orders.where((o) => (o['paid_by_user_name'] as String? ?? '').isEmpty).map((o) => o['paid_by_user_id'] as String? ?? ''),
          // Quién marcó cada cortesía, para la hoja "Cortesías": el pedido solo guarda su id.
          ...CortesiasReport.desde(orders).usuarios,
        }.where((id) => id.isNotEmpty).toList();
        final results = await Future.wait([
          dp.fetchCertifiedInvoiceOrderIds(orderDocIds),
          dp.fetchUserNamesById(userIdsToResolve),
          dp.fetchCancelledOrders(local: true),
        ]);
        ExportService.exportCajaReport(
          orders,
          results[0] as Set<String>,
          results[1] as Map<String, String>,
          dp.range.label,
          cancelledOrders: results[2] as List<Map<String, dynamic>>,
          simbolos: dp.simbolosPorMoneda,
          nombresSucursal: {
            for (final l in [...dp.locations, ...dp.sucursalesOcultas]) l.id: l.name,
          },
        );
      case 'metodos':
        ExportService.exportPaymentMethodReport(await dp.ensureDetailedOrders(), dp.range.label);
      case 'platillos':
        ExportService.exportProducts(dp.topProductsFrom(await dp.ensureDetailedOrders()), dp.range.prevLabel);
      case 'inventario':
        ExportService.exportInventory(ip.items, ip.locations);
      case 'sar_no_utilizados':
        final tenantId = dp.tenantId;
        if (tenantId == null) throw StateError('Sin negocio');
        final numeros = await FiscalReportsService().unusedNumbers(tenantId: tenantId);
        ExportService.exportUnusedNumbers(numeros, dp.range.label);
      case 'sar_isv':
        final tenantId = dp.tenantId;
        if (tenantId == null) throw StateError('Sin negocio');
        final resumen = await FiscalReportsService().isvSummary(tenantId: tenantId, from: dp.range.start, to: dp.range.end);
        ExportService.exportIsvSummary(resumen, dp.range.label);
    }
  }

  // ── Pantallas ──────────────────────────────────────────────────────────────

  Widget _pagina() {
    final Widget p = switch (_destino) {
      Destino.inicio => const DashboardScreen(),
      Destino.avisos => const NotificationsScreen(),
      Destino.despensa => const InventoryScreen(),
      Destino.rentabilidad => const ProfitabilityReportScreen(),
      Destino.comprasVentas => const ComprasVentasScreen(),
      Destino.gastos => const ExpensesReportScreen(),
      Destino.cierres => const CashClosuresReportScreen(),
      Destino.propinas => const PropinasScreen(),
      Destino.cortesias => const CortesiasScreen(),
      Destino.cancelados => const CancelledOrdersReportScreen(),
      Destino.notificaciones => const NotificationSettingsScreen(),
      Destino.descargas => const SizedBox.shrink(),
    };
    // Cada lugar con su propio estado: al cambiar de uno a otro no se arrastra lo del anterior.
    return ContextoShell(child: KeyedSubtree(key: ValueKey(_destino), child: p));
  }

  /// Los botones de la derecha del encabezado, para el de pantalla ancha y para el
  /// del teléfono: configurar avisos (solo en Avisos), descargar y la fecha (solo donde
  /// tiene efecto).
  List<Widget> _acciones({required bool telefono}) => [
        if (Destinos.muestraConfigurarAvisos(_destino))
          BotonEncabezado(icono: Icons.tune_rounded, ayuda: 'Configurar avisos', texto: 'Configurar avisos', onTap: () => _ir(Destino.notificaciones)),
        BotonEncabezado(icono: Icons.file_download_outlined, ayuda: 'Descargar reportes', onTap: _abrirDescargas),
        if (Destinos.muestraFecha(_destino))
          ConstrainedBox(constraints: BoxConstraints(maxWidth: telefono ? 140 : 260), child: const DateSelectorChip()),
      ];

  /// Pantalla ancha: la miga, el título grande y los botones.
  Widget _encabezado(String nombre) {
    return EncabezadoPagina(
      miga: Destinos.miga(_destino, hora: DateTime.now().hour, nombre: nombre),
      titulo: Destinos.nombre(_destino),
      acciones: _acciones(telefono: false),
    );
  }

  static int _agotados(InventoryProvider ip, String? elegida) {
    final ids = [
      for (final l in ip.locations)
        if (elegida == null || l.id == elegida) l.id,
    ];
    return ResumenDespensa.de(Despensa.filas(ip.items, ids), ids).agotados;
  }

  @override
  Widget build(BuildContext context) {
    final base = _version == null ? '' : 'v$_version';
    final versionLabel = _patchNumber != null ? '$base ($_patchNumber)'.trim() : base;

    final sinLeer = context.select<NotificationsProvider, int>((p) => p.sinLeer);
    final elegida = context.select<DashboardProvider, String?>((d) => d.selectedLocationId);
    final agotados = context.select<InventoryProvider, int>((p) => _agotados(p, elegida));
    final sucursales = context.select<DashboardProvider, int>((d) => d.locations.length);
    final hayCortesias = context.select<DashboardProvider, bool>((d) => (d.metrics?.courtesyCount ?? 0) > 0);
    final hayOtraMoneda = context.select<DashboardProvider, bool>((d) => d.hayOtraMoneda);
    final nSucursales = sucursales < 1 ? 1 : sucursales;
    final nombre = AuthService().displayName ?? AuthService().sessionEmail ?? 'Mi cuenta';
    final atajo = defaultTargetPlatform == TargetPlatform.macOS ? '⌘ K' : 'Ctrl K';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _abrirBuscador,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _abrirBuscador,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: InicioColores.bg,
          body: LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth <= kInicioQuiebreTelefono) {
                return _telefono(context, nombre: nombre, sucursales: nSucursales, sinLeer: sinLeer, versionLabel: versionLabel);
              }
              return _ancho(
                context,
                ancho: c.maxWidth,
                nombre: nombre,
                sucursales: nSucursales,
                sinLeer: sinLeer,
                agotados: agotados,
                puntos: {if (hayCortesias) Destino.cortesias},
                hayOtraMoneda: hayOtraMoneda,
                versionLabel: versionLabel,
                atajo: atajo,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Teléfono: una sola línea arriba (logo, nombre de la vista y botones), la pantalla y
  /// la barra de abajo. La cuenta y la búsqueda están en "Más".
  Widget _telefono(BuildContext context, {required String nombre, required int sucursales, required int sinLeer, required String versionLabel}) {
    return Column(
      children: [
        Container(
          color: InicioColores.barra,
          child: SafeArea(
            bottom: false,
            child: EncabezadoMovil(titulo: Destinos.nombre(_destino), acciones: _acciones(telefono: true)),
          ),
        ),
        Expanded(
          // Las barras ya apartaron lo suyo del borde: la pantalla no lo aparta otra vez.
          child: MediaQuery.removePadding(context: context, removeTop: true, removeBottom: true, child: _pagina()),
        ),
        SafeArea(
          top: false,
          child: BarraInferiorMovil(
            actual: pestanaDe(_destino),
            avisosSinLeer: sinLeer,
            onElegir: (p) {
              switch (p) {
                case PestanaMovil.inicio:
                  _ir(Destino.inicio);
                case PestanaMovil.reportes:
                  _abrirReportes();
                case PestanaMovil.despensa:
                  _ir(Destino.despensa);
                case PestanaMovil.avisos:
                  _ir(Destino.avisos);
                case PestanaMovil.mas:
                  _abrirMas(nombre, sucursales, versionLabel);
              }
            },
          ),
        ),
      ],
    );
  }

  /// Tablet y escritorio: la barra lateral. En tablet (hasta 1199) queda contraída y,
  /// al expandirla, se abre ENCIMA de la pantalla; en escritorio empuja la pantalla.
  Widget _ancho(
    BuildContext context, {
    required double ancho,
    required String nombre,
    required int sucursales,
    required int sinLeer,
    required int agotados,
    required Set<Destino> puntos,
    required bool hayOtraMoneda,
    required String versionLabel,
    required String atajo,
  }) {
    final tablet = ancho < 1200;
    final contraida = tablet ? !_barraAbierta : _barraContraida;
    final anchoFijo = tablet ? AnchoBarra.contraida : AnchoBarra.de(_barraContraida);
    final anchoBarra = AnchoBarra.de(contraida);
    final inset = MediaQuery.paddingOf(context);
    final alto = MediaQuery.sizeOf(context).height;

    void cerrarCuenta() => setState(() => _cuentaAbierta = false);

    return Stack(
      children: [
        Positioned.fill(
          left: anchoFijo,
          // El hueco del borde izquierdo ya lo absorbió la barra.
          child: SafeArea(
            left: false,
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: Column(
                children: [
                  _encabezado(nombre),
                  Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, removeBottom: true, child: _pagina())),
                ],
              ),
            ),
          ),
        ),
        if (tablet && _barraAbierta)
          Positioned.fill(
            left: AnchoBarra.contraida,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _barraAbierta = false), child: const ColoredBox(color: Color(0x730A0C1C))),
          ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: BarraLateral(
            actual: _destino,
            contraida: contraida,
            avisosSinLeer: sinLeer,
            agotados: agotados,
            puntos: puntos,
            sucursales: sucursales,
            nombre: nombre,
            rol: _rol,
            atajo: atajo,
            cuentaAbierta: _cuentaAbierta,
            onElegir: _ir,
            onBuscar: _abrirBuscador,
            onCuenta: () => setState(() => _cuentaAbierta = !_cuentaAbierta),
          ),
        ),
        Positioned(
          left: anchoBarra - 20,
          top: 57 + inset.top,
          child: BotonContraer(
            contraida: contraida,
            onTap: () => setState(() {
              if (tablet) {
                _barraAbierta = !_barraAbierta;
              } else {
                _barraContraida = !_barraContraida;
              }
            }),
          ),
        ),
        if (_cuentaAbierta) ...[
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: cerrarCuenta, child: const SizedBox.expand())),
          Positioned(
            left: 12,
            bottom: 78 + inset.bottom,
            width: contraida ? 240 : 256,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: alto - 78 - inset.bottom - 12 - inset.top),
              child: SingleChildScrollView(
                child: PanelCuenta(
                  nombre: nombre,
                  rol: _rol,
                  sucursales: sucursales,
                  version: versionLabel,
                  actual: _destino,
                  onDescargas: () {
                    cerrarCuenta();
                    _abrirDescargas();
                  },
                  onNotificaciones: () => _ir(Destino.notificaciones),
                  onCerrarSesion: () {
                    cerrarCuenta();
                    _logout();
                  },
                  extras: _extras(grande: false, hayOtraMoneda: hayOtraMoneda, cerrar: cerrarCuenta),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Apariencia": claro u oscuro. Claro es el modo por defecto; lo que se elige se
/// guarda en el aparato (ver `TemaManager`).
class _SelectorApariencia extends StatelessWidget {
  /// El margen de los lados: en el panel de la cuenta las filas llevan 10; en la hoja
  /// del teléfono, las de arriba ya traen el suyo.
  final double sangria;
  const _SelectorApariencia({this.sangria = 10});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TemaManager.instancia,
      builder: (context, _) => Padding(
        padding: EdgeInsets.symmetric(horizontal: sangria, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.brightness_6_outlined, color: InicioColores.muted, size: 18),
                const SizedBox(width: 10),
                Text('Apariencia', style: inicioTexto(14, FontWeight.w500, InicioColores.ink)),
              ],
            ),
            const SizedBox(height: 10),
            InicioSegmentos<ThemeMode>(
              opciones: const [(ThemeMode.light, 'Claro'), (ThemeMode.dark, 'Oscuro')],
              elegido: TemaManager.instancia.modo,
              onElegir: TemaManager.instancia.poner,
              completo: true,
            ),
          ],
        ),
      ),
    );
  }
}
