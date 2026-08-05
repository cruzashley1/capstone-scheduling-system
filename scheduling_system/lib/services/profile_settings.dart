// services/profile_settings.dart
//
// App-wide account + company details edited in Settings. Kept here rather
// than in the Settings screen's State so the values survive navigating away
// (the screen is disposed every time you leave it) and so other screens can
// read them — the Schedule Report PDF prints `name` as "Prepared by", plus
// the two report signatories below.
//
// Persisted across restarts on every platform (web + mobile) via
// shared_preferences, the same way NotificationSettings works.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileSettings {
  ProfileSettings._();

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
  static String get preparedBy => name.value;

  /// Loads the stored values. Called once from main() before runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
    } catch (_) {
      // Storage unavailable (e.g. blocked web storage) — keep the defaults.
    }
  }

  static Future<void> saveProfile({
    required String name,
    required String email,
    required String organization,
  }) async {
    ProfileSettings.name.value         = name;
    ProfileSettings.email.value        = email;
    ProfileSettings.organization.value = organization;
    await _write({
      _kName:  name,
      _kEmail: email,
      _kOrg:   organization,
    });
  }

  static Future<void> saveCompany({
    required String company,
    required String client,
    required String approvedBy,
    required String endorsedBy,
  }) async {
    ProfileSettings.company.value    = company;
    ProfileSettings.client.value     = client;
    ProfileSettings.approvedBy.value = approvedBy;
    ProfileSettings.endorsedBy.value = endorsedBy;
    await _write({
      _kCompany:    company,
      _kClient:     client,
      _kApprovedBy: approvedBy,
      _kEndorsedBy: endorsedBy,
    });
  }

  static Future<void> _write(Map<String, String> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in values.entries) {
        await prefs.setString(e.key, e.value);
      }
    } catch (_) {
      // The change still applies for this session even if it can't persist.
    }
  }
}
