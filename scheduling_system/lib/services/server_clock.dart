// services/server_clock.dart
//
// The app's clock. Everything that decides a duty question from the time
// — On Duty / Awaiting / Off Shift, which duty day a night head guard is
// on, whether an attendance report is inside its shift window, whether an
// emergency absence is still inside its one-hour cut-off — reads the time
// from here instead of DateTime.now().
//
// The reason is that DateTime.now() is the DEVICE clock, and the guard
// owns the device. Winding it back is enough to file an absence that is
// already past its cut-off, or to make a night head guard look like they
// are on a different duty day. Anything a guard can gain by changing the
// time has to be settled against the server.
//
// It does NOT poll. sync() asks GET /server-time once, records the offset
// between the server and this device, and now() applies that offset from
// then on. So it costs one request per session, keeps working offline,
// and stays smooth for a per-second ticker.
//
// useDeviceTime is a TESTING switch, in ADMIN Settings -> Developer only,
// and turning it on re-checks the admin's password. It deliberately does
// not live in the shared guard profile: all three guard roles use that one
// view, so a head guard would have been handed a switch that moves their
// own duty window off the server clock. Turn it on to exercise the
// after-midnight window by changing the device clock instead of waiting
// until 2 AM. It must be off in production, which is why it defaults to
// off, is hidden outside debug builds, and says so in the UI.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class ServerClock {
  ServerClock._();

  static const _prefsKey = 'use_device_time';

  // server wall clock - device wall clock, as measured by the last sync.
  static Duration _skew = Duration.zero;

  static bool _synced = false;

  /// True once a sync has succeeded this session. Until then now() is just
  /// the device clock — the app still runs, it simply can't correct yet.
  static bool get isSynced => _synced;

  /// How far the device clock is off the server's, for the Settings page.
  static Duration get skew => _skew;

  /// Whether the testing switch may be used at all.
  ///
  /// A head guard who could flip it on their own phone would defeat the
  /// entire point of server time — they could wind the clock back and
  /// re-open a duty window. So it exists in debug builds only, unless a
  /// release build is deliberately made for testing with
  ///   flutter build apk --dart-define=ALLOW_DEVICE_TIME=true
  /// In a normal release build the toggle is hidden AND ignored, so a
  /// preference left switched on can't survive into production.
  static const bool switchAvailable =
      kDebugMode || bool.fromEnvironment('ALLOW_DEVICE_TIME');

  /// TESTING ONLY — when on, now() is the raw device clock. Listen to it
  /// so screens re-resolve their duty state the moment it is flipped.
  static final ValueNotifier<bool> useDeviceTime = ValueNotifier<bool>(false);

  /// Pins the clock in tests so duty-window behaviour can be asserted
  /// without depending on what time the suite happens to run at.
  @visibleForTesting
  static DateTime Function()? debugNowOverride;

  /// The current time, corrected to the server's wall clock.
  static DateTime now() {
    final override = debugNowOverride;
    if (override != null) return override();
    if (switchAvailable && useDeviceTime.value) return DateTime.now();
    return DateTime.now().add(_skew);
  }

  /// Loads the testing switch. Called once from main() before runApp.
  static Future<void> load() async {
    if (!switchAvailable) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      useDeviceTime.value = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      // Storage unavailable — keep the safe default (server time).
    }
  }

  static Future<void> setUseDeviceTime(bool value) async {
    useDeviceTime.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // Still applies for this session even if it can't persist.
    }
  }

  /// Measures the offset to the server clock. Safe to call repeatedly —
  /// a failure leaves the previous offset in place rather than resetting
  /// it, so a dropped connection can't quietly hand control back to the
  /// device clock.
  static Future<bool> sync() async {
    final sentAt = DateTime.now();
    final result = await ApiService.fetchServerTime();
    final receivedAt = DateTime.now();

    if (result['success'] != true) return false;
    final serverNow = DateTime.tryParse(result['now']?.toString() ?? '');
    if (serverNow == null) return false;

    // The reply describes the server's clock at some point during the
    // round trip. Take the midpoint of the trip as the moment it applies
    // to, so half the latency isn't charged to the offset.
    final roundTrip = receivedAt.difference(sentAt);
    final deviceAtServerInstant =
        sentAt.add(Duration(microseconds: roundTrip.inMicroseconds ~/ 2));

    _skew = serverNow.difference(deviceAtServerInstant);
    _synced = true;
    return true;
  }
}
