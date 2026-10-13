import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scheduling_system/screens/approval_screen.dart';
import 'package:scheduling_system/screens/official_layout.dart';
import 'package:scheduling_system/screens/official_profile_screen.dart';
import 'package:scheduling_system/services/api_service.dart';
import 'package:scheduling_system/services/session.dart';

import 'approval_workflow_test.dart' show fixture;

void main() {
  late List<http.Request> requests;
  late List<Map<String, dynamic>> approvals;
  late Map<String, dynamic> account;
  Future<http.Response> Function(http.Request)? override;

  http.Response response(Map<String, dynamic> data, [int status = 200]) =>
      http.Response(
        jsonEncode(data),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Session.token = 'old-test-token';
    Session.logoutUrl = null;
    requests = [];
    approvals = [fixture('approved')];
    account = {
      'success': true,
      'username': 'assistant',
      'name': 'Assistant Reviewer',
      'role': 'assistantSecurity',
    };
    override = null;
    ApiService.testClient = MockClient((request) async {
      requests.add(request);
      if (override != null) return override!(request);
      switch (request.url.path) {
        case '/account':
          if (request.method == 'PUT') {
            account['name'] = jsonDecode(request.body)['name'];
          }
          return response(account);
        case '/schedule-approvals':
          return response({'approvals': approvals});
        case '/schedule-approvals/review1':
          return response({'approval': approvals.first});
        case '/change-password':
          return response({'success': true, 'token': 'new-test-token'});
        case '/workflow-notifications':
          return response({'notifications': []});
        default:
          throw StateError(
            'Unexpected request: ${request.method} ${request.url}',
          );
      }
    });
  });

  tearDown(() {
    ApiService.testClient?.close();
    ApiService.testClient = null;
    Session.token = null;
    Session.logoutUrl = null;
  });

  Future<void> open(
    WidgetTester tester, {
    bool layout = false,
    Size size = const Size(1366, 1100),
    ValueChanged<String>? onNameChanged,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: layout
            ? OfficialLayout(
                username: account['username'],
                role: account['role'],
              )
            : Scaffold(
                body: Row(
                  children: [
                    const SizedBox(width: 250),
                    Expanded(
                      child: OfficialProfileScreen(
                        username: account['username'],
                        role: account['role'],
                        initialName: account['name'],
                        onNameChanged: onNameChanged ?? (_) {},
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
    await tester.pumpAndSettle();
    if (layout) {
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String label) async {
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(OfficialProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ChoiceChip, label));
  }

  Finder password(int index) =>
      find.byKey(ValueKey('official-password-$index'));
  Future<void> enterPasswords(
    WidgetTester tester,
    String current,
    String next,
    String confirm,
  ) async {
    for (final entry in [(0, current), (1, next), (2, confirm)]) {
      await tester.ensureVisible(password(entry.$1));
      await tester.enterText(password(entry.$1), entry.$2);
    }
  }

  for (final role in ['assistantSecurity', 'areaCommander']) {
    for (final size in [const Size(1024, 640), const Size(1366, 768)]) {
      testWidgets('$role profile fits ${size.width.toInt()} desktop', (
        tester,
      ) async {
        account['role'] = role;
        account['name'] = 'Maria Alexandra Dela Cruz';
        await open(tester, layout: true, size: size);
        expect(find.text('Your profile'), findsOneWidget);
        expect(find.text('Maria Alexandra Dela Cruz'), findsWidgets);
        expect(
          find.text(
            role == 'assistantSecurity' ? 'First review' : 'Final approval',
          ),
          findsWidgets,
        );
        expect(find.text('All stations'), findsWidgets);
        expect(find.text('Period Approvals'), findsOneWidget);
        expect(find.text('Approval Alerts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tab(tester, 'Security');
        await tester.ensureVisible(find.text('Update password'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tab(tester, 'My Decisions');
        expect(find.text('My decision history'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'name saves persist, update sidebar, and send only the trimmed name',
    (tester) async {
      await open(tester, layout: true);
      await tap(tester, find.text('Edit name'));
      await tester.enterText(
        find.byKey(const ValueKey('official-name')),
        '  Maria Dela Cruz  ',
      );
      await tap(tester, find.text('Save name'));
      expect(
        find.text('Your name has been saved to your account.'),
        findsOneWidget,
      );
      expect(find.text('Maria Dela Cruz'), findsWidgets);
      final saved = requests.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(saved.body), {'name': 'Maria Dela Cruz'});
      await tester.tap(find.text('Period Approvals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Maria Dela Cruz'), findsWidgets);
      expect(find.text('Assistant Reviewer'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'name validates blank input and prevents duplicate saves on a slow failure',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Edit name'));
      await tester.enterText(
        find.byKey(const ValueKey('official-name')),
        '   ',
      );
      await tap(tester, find.text('Save name'));
      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      final pending = Completer<http.Response>();
      override = (_) => pending.future;
      await tester.enterText(
        find.byKey(const ValueKey('official-name')),
        'Updated Assistant',
      );
      await tester.tap(find.text('Save name'));
      await tester.pump();
      expect(find.text('Saving...'), findsOneWidget);
      await tester.tap(find.text('Saving...'));
      await tester.pump();
      expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
      pending.complete(response({'detail': 'Unable to save right now.'}, 503));
      await tester.pumpAndSettle();
      expect(find.text('Unable to save right now.'), findsOneWidget);
      expect(find.text('Assistant Reviewer'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('official-name')))
            .controller!
            .text,
        'Updated Assistant',
      );
      expect(
        find.text('Your name has been saved to your account.'),
        findsNothing,
      );
    },
  );

  testWidgets('account load failure disables name editing and can be retried', (
    tester,
  ) async {
    override = (_) async =>
        response({'detail': 'Account temporarily unavailable.'}, 503);
    await open(tester);
    expect(find.text('Account temporarily unavailable.'), findsOneWidget);
    await tap(tester, find.text('Edit name'));
    expect(find.byKey(const ValueKey('official-name')), findsNothing);
    override = null;
    await tap(tester, find.text('Retry'));
    await tap(tester, find.text('Edit name'));
    expect(find.byKey(const ValueKey('official-name')), findsOneWidget);
  });

  testWidgets(
    'decision history shows only own decisions, newest first, with filters',
    (tester) async {
      final approved = fixture('approved');
      (approved['events'] as List)[1]['comment'] = 'Approved by this account';
      (approved['events'] as List)[2]['comment'] = 'Other official comment';
      final returned = fixture('returned')..['id'] = 'returned1';
      returned['events'] = [
        {
          'username': 'assistant',
          'action': 'return',
          'name': 'Assistant Reviewer',
          'at': '2098-12-21T01:00:00+00:00',
          'comment': 'Correct station coverage',
        },
      ];
      approvals = [approved, returned];
      await open(tester);
      expect(
        requests.where((r) => r.url.path == '/schedule-approvals'),
        isEmpty,
      );
      await tab(tester, 'My Decisions');
      expect(find.text('Other official comment'), findsNothing);
      expect(find.text('Approved by this account'), findsOneWidget);
      expect(find.text('Correct station coverage'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Correct station coverage')).dy,
        lessThan(tester.getTopLeft(find.text('Approved by this account')).dy),
      );
      expect(find.text('2098-12-21 09:00 PHT'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Returned'));
      expect(find.text('Approved by this account'), findsNothing);
      expect(find.text('Correct station coverage'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Approved'));
      expect(find.text('Correct station coverage'), findsNothing);
      expect(find.text('Approved by this account'), findsOneWidget);
      await tap(tester, find.text('View submission'));
      expect(find.byType(ApprovalReviewScreen), findsOneWidget);
      expect(
        requests.where((r) => r.url.path == '/schedule-approvals/review1'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history failures show retry instead of invented zero counts', (
    tester,
  ) async {
    await open(tester);
    override = (_) async =>
        response({'detail': 'History temporarily unavailable.'}, 503);
    await tab(tester, 'My Decisions');
    expect(find.text('History temporarily unavailable.'), findsOneWidget);
    expect(find.text('Your decisions will appear here.'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'All decisions'), findsNothing);
    approvals = [fixture('pending_assistant')];
    override = null;
    await tap(tester, find.text('Retry'));
    expect(find.text('Your decisions will appear here.'), findsOneWidget);
  });

  testWidgets(
    'password validation, visibility, and clearing when leaving security',
    (tester) async {
      await open(tester);
      await tab(tester, 'Security');
      await tap(tester, find.text('Update password'));
      expect(find.text('Enter current password.'), findsOneWidget);
      await enterPasswords(tester, 'old-test-password', 'short', 'mismatch');
      await tap(tester, find.text('Update password'));
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('The new passwords do not match.'), findsOneWidget);
      await enterPasswords(
        tester,
        'old-test-password',
        'old-test-password',
        'old-test-password',
      );
      await tap(tester, find.text('Update password'));
      expect(find.text('Choose a different password.'), findsOneWidget);
      expect(requests.where((r) => r.url.path == '/change-password'), isEmpty);
      await tap(tester, find.byTooltip('Show current password'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: password(0),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
      await tab(tester, 'Account Overview');
      await tab(tester, 'Security');
      for (var i = 0; i < 3; i++) {
        expect(
          tester.widget<TextFormField>(password(i)).controller!.text,
          isEmpty,
        );
      }
      expect(find.byTooltip('Show current password'), findsOneWidget);
    },
  );

  testWidgets(
    'password change prevents duplicate posts and replaces the session token',
    (tester) async {
      await open(tester);
      await tab(tester, 'Security');
      await enterPasswords(
        tester,
        'old-test-password',
        'new-test-password',
        'new-test-password',
      );
      final pending = Completer<http.Response>();
      override = (_) => pending.future;
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pump();
      await tester.tap(find.text('Updating...'));
      await tester.pump();
      final posted = requests
          .where((r) => r.url.path == '/change-password')
          .single;
      expect(jsonDecode(posted.body), {
        'username': 'assistant',
        'currentPassword': 'old-test-password',
        'newPassword': 'new-test-password',
      });
      pending.complete(response({'success': true, 'token': 'new-test-token'}));
      await tester.pumpAndSettle();
      expect(Session.token, 'new-test-token');
      expect(
        (await SharedPreferences.getInstance()).getString('session_token'),
        'new-test-token',
      );
      expect(
        find.text(
          'Password changed. Your other sessions have been signed out.',
        ),
        findsOneWidget,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          tester.widget<TextFormField>(password(i)).controller!.text,
          isEmpty,
        );
      }
    },
  );

  testWidgets(
    'wrong current password keeps the existing session and reports failure',
    (tester) async {
      await open(tester);
      await tab(tester, 'Security');
      await enterPasswords(
        tester,
        'wrong-password',
        'new-test-password',
        'new-test-password',
      );
      override = (_) async =>
          response({'detail': 'Current password is incorrect.'}, 400);
      await tap(tester, find.text('Update password'));
      expect(find.text('Current password is incorrect.'), findsOneWidget);
      expect(Session.token, 'old-test-token');
      expect(
        find.text(
          'Password changed. Your other sessions have been signed out.',
        ),
        findsNothing,
      );
    },
  );
}
