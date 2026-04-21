import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/services/auth_service.dart';
import 'core/services/firestore_service.dart';
import 'firebase_options.dart';
import 'presentation/providers/dashboard_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirestoreService().initialize();
  await AuthService().restoreSession();
  runApp(const SaborProAnalyticsApp());
}

class SaborProAnalyticsApp extends StatelessWidget {
  const SaborProAnalyticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
      ],
      child: MaterialApp(
        title: 'SaborPro Dashboard',
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
            ? const DashboardScreen()
            : const LoginScreen(),
      ),
    );
  }
}
