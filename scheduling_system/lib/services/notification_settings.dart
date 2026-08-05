// services/notification_settings.dart
//
// App-wide notification preference. The Settings → Notifications switch
// writes it, and the Notifications inbox reads it (showing a muted state
// when alerts are turned off). Persisted across restarts on every
// platform (web + mobile) via shared_preferences.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings {
  NotificationSettings._();

  static const _prefsKey = 'allow_notifications';

  /// Current preference; listen to this to react to changes live.
  static final ValueNotifier<bool> allowNotifications = ValueNotifier<bool>(true);

  /// Loads the stored preference. Called once from main() before runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      allowNotifications.value = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      // Storage unavailable (e.g. blocked web storage) — keep the default.
    }
  }

  static Future<void> setAllowed(bool value) async {
    allowNotifications.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // Preference still applies for this session even if it can't persist.
    }
  }
}
