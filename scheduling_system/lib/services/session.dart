// services/session.dart
//
// Persisted login session. Saved after a successful sign-in, restored
// by main() on startup so closing the app doesn't send the user back
// to the login screen, and cleared only by an explicit Log Out.
import 'package:shared_preferences/shared_preferences.dart';

class Session {
  static const _kUsername = 'session_username';
  static const _kRole = 'session_role';

  final String username;
  final String role; // 'admin' | 'headGuard' | 'regular' | 'reliever'

  Session._restored(this.username, this.role);

  /// Remembers who is signed in. Called after a successful login
  /// (skipped when the user still has to change their first password).
  static Future<void> save(String username, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUsername, username);
      await prefs.setString(_kRole, role);
    } catch (_) {
      // Storage unavailable — the user just logs in again next launch.
    }
  }

  /// The saved session, or null when nobody is signed in.
  static Future<Session?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(_kUsername);
      final role = prefs.getString(_kRole);
      if (username == null || username.isEmpty || role == null) return null;
      return Session._restored(username, role);
    } catch (_) {
      return null;
    }
  }

  /// Forgets the session (Log Out).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUsername);
      await prefs.remove(_kRole);
    } catch (_) {
      // Nothing stored anyway if storage is unavailable.
    }
  }
}
