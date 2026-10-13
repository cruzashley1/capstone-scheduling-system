// services/profile_settings.dart
//
// App-wide account + company details edited in Settings. Kept here rather
// than in the Settings screen's State so the values survive navigating away
// (the screen is disposed every time you leave it) and so other screens can
// read them — the Schedule Report PDF prints `name` as "Prepared by", plus
// the two report signatories below.
//
// Stored locally via shared_preferences, the same way NotificationSettings
// works. Web storage belongs to the current browser profile and origin;
// these details are not synced to the backend account.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileSettings {
  ProfileSettings._();

  /// Shown in Settings if startup could not read the saved details.
  static String? loadError;

  static const _kName       = 'profile_name';
  static const _kEmail      = 'profile_email';
  static const _kOrg        = 'profile_org';
  static const _kCompany    = 'company_name';
  static const _kClient     = 'company_client';
  static const _kApprovedBy = 'report_approved_by';
  static const _kEndorsedBy = 'report_endorsed_by';

  // ── Profile ──
  static final ValueNotifier<String> name =
      ValueNotifier<String>('Administrator');
  static final ValueNotifier<String> email =
      ValueNotifier<String>('admin@kaizensecurity.com');
  static final ValueNotifier<String> organization =
      ValueNotifier<String>('Kaizen Security Agency Corp.');

  // ── Company ──
  static final ValueNotifier<String> company =
      ValueNotifier<String>('Kaizen Security Agency Corp.');
  static final ValueNotifier<String> client =
      ValueNotifier<String>('Light Rail Transit Authority');

  // ── Report signatories ──
  // "Prepared by" is not stored: it is always the profile [name] of
  // whoever produced the report.
  static final ValueNotifier<String> approvedBy =
      ValueNotifier<String>('Assistance Security');
  static final ValueNotifier<String> endorsedBy =
      ValueNotifier<String>('Area Commander');

  /// Name printed under "Prepared by" on exported reports.
  static String get preparedBy {
    final savedName = name.value.trim();
    return savedName.isEmpty ? 'Administrator' : savedName;
  }

  /// Loads the stored values. Called once from main() before runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      String pick(String key, ValueNotifier<String> fallback) {
        final v = prefs.getString(key);
        return (v == null || v.trim().isEmpty) ? fallback.value : v;
      }

      name.value         = pick(_kName, name);
      email.value        = pick(_kEmail, email);
      organization.value = pick(_kOrg, organization);
      company.value      = pick(_kCompany, company);
      client.value       = pick(_kClient, client);
      approvedBy.value   = pick(_kApprovedBy, approvedBy);
      endorsedBy.value   = pick(_kEndorsedBy, endorsedBy);
      loadError = null;
    } catch (error) {
      loadError = 'Could not load saved settings on this device. '
          'Please restart the app and try again.';
      debugPrint('Loading profile settings failed: $error');
    }
  }

  static Future<void> saveProfile({
    required String name,
    required String email,
    required String organization,
  }) async {
    await _write({
      _kName:  name,
      _kEmail: email,
      _kOrg:   organization,
    });
    ProfileSettings.name.value         = name;
    ProfileSettings.email.value        = email;
    ProfileSettings.organization.value = organization;
  }

  static Future<void> saveCompany({
    required String company,
    required String client,
    required String approvedBy,
    required String endorsedBy,
  }) async {
    await _write({
      _kCompany:    company,
      _kClient:     client,
      _kApprovedBy: approvedBy,
      _kEndorsedBy: endorsedBy,
    });
    ProfileSettings.company.value    = company;
    ProfileSettings.client.value     = client;
    ProfileSettings.approvedBy.value = approvedBy;
    ProfileSettings.endorsedBy.value = endorsedBy;
  }

  static Future<void> _write(Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      for (final e in values.entries) {
        if (!await prefs.setString(e.key, e.value)) {
          throw StateError('Storage did not save ${e.key}.');
        }
      }
      loadError = null;
    } catch (_) {
      // setString updates its cache even if the platform write fails. Drop
      // those attempted values so a later load does not treat them as saved.
      try {
        await prefs.reload();
      } catch (_) {
        // Preserve the original write error for the caller.
      }
      rethrow;
    }
  }
}
