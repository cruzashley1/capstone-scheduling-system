import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scheduling_system/screens/settings_screen.dart';
import 'package:scheduling_system/services/profile_settings.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  late Map<String, Object> stored;
  bool rejectWrite = false;
  bool throwOnWrite = false;
  bool failRead = false;
  Completer<void>? pendingWrite;

  setUp(() async {
    stored = {
      'flutter.profile_name': 'Existing Administrator',
      'flutter.profile_email': 'admin@example.com',
      'flutter.profile_org': 'Security Agency',
      'flutter.company_name': 'Existing Company',
      'flutter.company_client': 'Existing Client',
      'flutter.report_approved_by': 'Assistance Security',
      'flutter.report_endorsed_by': 'Area Commander',
    };
    rejectWrite = false;
    throwOnWrite = false;
    failRead = false;
    pendingWrite = null;
    SharedPreferences.resetStatic();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getAll') {
        if (failRead) throw PlatformException(code: 'storage_unavailable');
        return Map<String, Object>.from(stored);
      }
      if (call.method == 'setString') {
        await pendingWrite?.future;
        if (throwOnWrite) throw PlatformException(code: 'storage_unavailable');
        if (rejectWrite) return false;
        stored[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return true;
      }
      throw StateError('Unexpected storage call: ${call.method}');
    });
    await ProfileSettings.load();
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> saveProfile() => ProfileSettings.saveProfile(
    name: 'Samuel Dagom',
    email: 'samuel@example.com',
    organization: 'Security Agency',
  );

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsContent()));
    await tester.pumpAndSettle();
  }

  test(
    'a new preferences instance restores the saved profile for the PDF',
    () async {
      await saveProfile();
      // Drop the Dart cache to model startup reading the platform store anew.
      SharedPreferences.resetStatic();
      ProfileSettings.name.value = 'Administrator';
      await ProfileSettings.load();
      expect(ProfileSettings.preparedBy, 'Samuel Dagom');
      expect(ProfileSettings.email.value, 'samuel@example.com');
      expect(ProfileSettings.loadError, isNull);
    },
  );

  test(
    'a rejected write does not become a saved name in memory or storage',
    () async {
      rejectWrite = true;
      await expectLater(saveProfile(), throwsStateError);
      expect(ProfileSettings.preparedBy, 'Existing Administrator');
      expect(
        (await SharedPreferences.getInstance()).getString('profile_name'),
        'Existing Administrator',
      );
      SharedPreferences.resetStatic();
      await ProfileSettings.load();
      expect(ProfileSettings.preparedBy, 'Existing Administrator');
    },
  );

  test('company settings also propagate storage failures', () async {
    rejectWrite = true;
    await expectLater(
      ProfileSettings.saveCompany(
        company: 'New Company',
        client: 'New Client',
        approvedBy: 'New Approver',
        endorsedBy: 'New Endorser',
      ),
      throwsStateError,
    );
    expect(ProfileSettings.company.value, 'Existing Company');
    expect(ProfileSettings.approvedBy.value, 'Assistance Security');
  });

  testWidgets('success is shown only after the platform finishes saving', (
    tester,
  ) async {
    await openSettings(tester);
    pendingWrite = Completer<void>();
    await tester.enterText(find.byType(TextField).first, 'Samuel Dagom');
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Profile updated successfully!'), findsNothing);
    expect(ProfileSettings.preparedBy, 'Existing Administrator');
    expect(
      tester
          .widget<ElevatedButton>(
            find.byWidgetPredicate((widget) => widget is ElevatedButton),
          )
          .onPressed,
      isNull,
    );

    pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Profile updated successfully!'), findsOneWidget);
    expect(ProfileSettings.preparedBy, 'Samuel Dagom');
  });

  for (final failure in ['rejected', 'exception']) {
    testWidgets('$failure is displayed as a save error, with retry available', (
      tester,
    ) async {
      await openSettings(tester);
      rejectWrite = failure == 'rejected';
      throwOnWrite = failure == 'exception';
      await tester.enterText(find.byType(TextField).first, 'Samuel Dagom');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not save your profile on this device. Please try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Profile updated successfully!'), findsNothing);
      expect(ProfileSettings.preparedBy, 'Existing Administrator');

      rejectWrite = false;
      throwOnWrite = false;
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Profile updated successfully!'), findsOneWidget);
      expect(ProfileSettings.preparedBy, 'Samuel Dagom');
    });
  }

  testWidgets('startup read errors are visible in Settings', (tester) async {
    failRead = true;
    SharedPreferences.resetStatic();
    await ProfileSettings.load();
    await openSettings(tester);
    expect(find.text(ProfileSettings.loadError!), findsOneWidget);
    failRead = false;
    await ProfileSettings.load();
    expect(ProfileSettings.loadError, isNull);
  });
}
