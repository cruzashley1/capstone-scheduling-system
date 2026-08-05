// main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'screens/headguardui/head_guard_layout.dart';
import 'screens/securityguardui/security_guard_layout.dart';
import 'services/notification_settings.dart';
import 'services/profile_settings.dart';
import 'services/server_clock.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the saved notification preference before the UI builds.
  await NotificationSettings.load();
  // Restore the "use device time" testing switch, then measure the offset
  // to the server clock. Duty decisions are settled against the server so
  // that changing the device clock can't buy a guard anything (see
  // ServerClock). Not awaited: a slow or unreachable backend must not hold
  // the splash screen — until it lands, now() is simply the device clock.
  await ServerClock.load();
  unawaited(ServerClock.sync());
  // Restore the saved profile / company details (name shown in Settings,
  // signatories printed on exported reports).
  await ProfileSettings.load();
  // Restore the saved login session (if any) so closing the app doesn't
  // send the user back to the login screen — only Log Out does.
  final session = await Session.load();
  runApp(SchedulingSystemApp(session: session));
}

class SchedulingSystemApp extends StatelessWidget {
  final Session? session;

  const SchedulingSystemApp({super.key, this.session});

  // Where the app opens: the saved user's home layout, or the login
  // screen when nobody is signed in (or the saved role is unknown).
  Widget _initialScreen() {
    final s = session;
    if (s == null) return const AuthScreen();
    switch (s.role) {
      case 'admin':
        return MainLayout(username: s.username);
      case 'headGuard':
        return HeadGuardLayout(username: s.username);
      case 'regular':
      case 'reliever':
        return SecurityGuardLayout(username: s.username);
      default:
        return const AuthScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sched',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1034A6),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1034A6),
          primary: const Color(0xFF1034A6),
          secondary: const Color(0xFF1E88E5),
        ),
        // FIXED: Use CardThemeData instead of CardTheme
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1034A6),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: _initialScreen(),
    );
  }
}
