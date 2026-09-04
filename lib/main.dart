import 'package:flutter/material.dart';
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
  await initializeDateFormatting('es', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Tiene que registrarse antes de runApp y con Firebase ya inicializado: si se
  // registra después, los mensajes que lleguen con la app cerrada no despiertan
  // ningún isolate y se pierden.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await FirestoreService().initialize();
  await AuthService().restoreSession();

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
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF7444fd),
            surface: Color(0xFF1E293B),
          ),
        ),
        home: AuthService().isLoggedIn
            ? const AppShell()
            : const LoginScreen(),
      ),
    );
  }
}
