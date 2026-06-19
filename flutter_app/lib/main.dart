import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/app_colors.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/passcode_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/dashboard_screen.dart';

/// Lets [ScannerScreen] release its camera while another screen
/// (e.g. the admin enrollment camera) is on top of it.
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() {
  runApp(const FaceAttendanceApp());
}

class FaceAttendanceApp extends StatelessWidget {
  const FaceAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Face Biometric',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [routeObserver],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/login': (_) => const LoginScreen(),
          '/signup': (_) => const SignUpScreen(),
          '/scanner': (_) => const ScannerScreen(),
          '/passcode': (_) => const PasscodeScreen(),
          '/admin': (_) => const AdminScreen(),
          '/dashboard': (_) => const DashboardScreen(),
        },
      ),
    );
  }
}
