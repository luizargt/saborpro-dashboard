import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/navigation/app_navigator.dart';
import 'core/services/app_lock_policy.dart';
import 'core/services/auth_service.dart';
import 'core/services/biometric_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/paleta.dart';
import 'core/theme/tema_manager.dart';
import 'firebase_options.dart';
import 'presentation/providers/dashboard_provider.dart';
import 'presentation/providers/inventory_provider.dart';
import 'presentation/providers/notification_settings_provider.dart';
import 'presentation/providers/notifications_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/shell_screen.dart';
import 'presentation/widgets/app_lock_gate.dart';
import 'presentation/widgets/forced_update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // El modo claro/oscuro se lee ANTES de pintar: si no, se vería un instante en claro
  // y saltaría a oscuro. Por defecto es claro.
  await TemaManager.instancia.cargar();
  await initializeDateFormatting('es', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Tiene que registrarse antes de runApp y con Firebase ya inicializado: si se
  // registra después, los mensajes que lleguen con la app cerrada no despiertan
  // ningún isolate y se pierden.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await FirestoreService().initialize();
  await AuthService().restoreSession();

  // Arranque sin sesión: si un cierre de sesión anterior no alcanzó a borrar
  // el token de push (sin red, o la app murió a la mitad), se termina aquí
  // para que este teléfono deje de recibir los avisos de esa cuenta.
  if (!AuthService().isLoggedIn) {
    NotificationService.completarBorradoPendiente();
  }

  // Se resuelve ANTES de pintar: si se decidiera dentro del primer build, el
  // dashboard con las ventas del día alcanzaría a verse un frame antes de que
  // baje el bloqueo.
  final lockedAtStart = AppLockPolicy.shouldLockOnStart(
    loggedIn: AuthService().isLoggedIn,
    biometricEnabled: await BiometricService().isEnabled(),
  );

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://80d27298109d32411a1d331095af590b@o4510177128677376.ingest.us.sentry.io/4511282065178624';
      options.tracesSampleRate = 0.2;
      options.environment = 'production';
    },
    appRunner: () =>
        runApp(SaborProAnalyticsApp(lockedAtStart: lockedAtStart)),
  );
}

class SaborProAnalyticsApp extends StatelessWidget {
  /// Si al arrancar hay que pedir la biometría antes de mostrar nada.
  final bool lockedAtStart;

  const SaborProAnalyticsApp({super.key, this.lockedAtStart = false});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        // Se crea vacío; AppShell le pasa el uid con init() al arrancar.
        ChangeNotifierProvider(create: (_) => NotificationSettingsProvider()),
        // La bandeja de avisos. Igual que la de arriba, nace vacía y AppShell
        // le pasa el uid al arrancar.
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
      ],
      // Escucha al tema: al cambiar de claro a oscuro se repinta con la otra paleta.
      child: ListenableBuilder(
        listenable: TemaManager.instancia,
        builder: (context, _) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: TemaManager.instancia.barraDeEstado,
          child: MaterialApp(
            title: 'Sabor Manager',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            // En builder y no en home: así el bloqueo queda por encima del
            // Navigator y sigue vigilando aunque el usuario navegue. Como home se
            // desmontaría en el primer pushReplacement.
            // El aviso de actualización va por fuera del bloqueo biométrico: si la
            // app quedó vieja, da igual quién sea el que la abre.
            builder: (context, child) => ForcedUpdateGate(
              child: AppLockGate(
                navigatorKey: navigatorKey,
                lockedAtStart: lockedAtStart,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            themeMode: TemaManager.instancia.modo,
            theme: temaDeManager(Paleta.clara),
            darkTheme: temaDeManager(Paleta.oscura),
            home: AuthService().isLoggedIn
                ? const AppShell()
                : const LoginScreen(),
          ),
        ),
      ),
    );
  }
}

/// El `ThemeData` de una paleta. Las pantallas pintan con los colores de la paleta
/// (`CortesiasColores`), no con esto; esto es para lo que Material pinta solo:
/// diálogos, calendarios, hojas, avisos y el fondo.
ThemeData temaDeManager(Paleta p) {
  final esquema = ColorScheme(
    brightness: p.brillo,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.bad,
    onError: p.onAccent,
    surface: p.card,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.line,
    outlineVariant: p.line,
    surfaceContainerHighest: p.subtle,
  );
  return ThemeData(
    brightness: p.brillo,
    colorScheme: esquema,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.card,
    dividerColor: p.line,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(color: p.card, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.esOscura ? p.subtle : p.ink,
      contentTextStyle: TextStyle(color: p.esOscura ? p.ink : p.card),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.accent, selectionColor: p.accent.withValues(alpha: 0.3)),
  );
}
