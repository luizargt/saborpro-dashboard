import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/services/auth_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';
import 'presentation/providers/dashboard_provider.dart';
import 'presentation/providers/inventory_provider.dart';
import 'presentation/providers/notification_settings_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/shell_screen.dart';

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

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://80d27298109d32411a1d331095af590b@o4510177128677376.ingest.us.sentry.io/4511282065178624';
      options.tracesSampleRate = 0.2;
      options.environment = 'production';
    },
    appRunner: () => runApp(const SaborProAnalyticsApp()),
  );
}

class SaborProAnalyticsApp extends StatelessWidget {
  const SaborProAnalyticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        // Se crea vacío; AppShell le pasa el uid con init() al arrancar.
        ChangeNotifierProvider(create: (_) => NotificationSettingsProvider()),
      ],
      child: MaterialApp(
        title: 'Sabor Manager',
        debugShowCheckedModeBanner: false,
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
