// services/session.dart
//
// Persisted login session. Saved after a successful sign-in, restored
// by main() on startup. The backend enforces token expiry and revocation.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class Session {
  static const _kUsername = 'session_username';
  static const _kRole = 'session_role';
  static const _kToken = 'session_token';
  static String? token;
  static String? logoutUrl;

  static Future<void> setToken(String? value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, value);
    }
  }

  final String username;
  final String role; // admin, assistantSecurity, areaCommander, headGuard, regular, reliever

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
      token = prefs.getString(_kToken);
      if (token == null || token!.isEmpty) return null;
      if (username == null || username.isEmpty || role == null) return null;
      return Session._restored(username, role);
    } catch (_) {
      return null;
    }
  }

  /// Forgets the session (Log Out).
  static Future<void> clear() async {
    final oldToken = token;
    token = null;
    if (oldToken != null && logoutUrl != null) {
      try {
        await http.post(Uri.parse(logoutUrl!), headers: {
          'Authorization': 'Bearer $oldToken',
        }).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUsername);
      await prefs.remove(_kRole);
      await prefs.remove(_kToken);
    } catch (_) {
      // Nothing stored anyway if storage is unavailable.
    }
  }
}
