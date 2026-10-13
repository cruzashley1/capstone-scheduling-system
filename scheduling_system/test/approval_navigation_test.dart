import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scheduling_system/screens/approval_screen.dart';
import 'package:scheduling_system/screens/notifications_screen.dart';
import 'package:scheduling_system/screens/reports_screen.dart';
import 'package:scheduling_system/screens/settings_screen.dart';
import 'package:scheduling_system/services/api_service.dart';
import 'package:scheduling_system/services/notification_center.dart';
import 'package:scheduling_system/services/notification_settings.dart';
import 'package:scheduling_system/widgets/sidebar.dart';
import 'package:scheduling_system/widgets/workflow_inbox.dart';
import 'approval_workflow_test.dart' show fixture;

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  late List<http.Request> requests;
  late List<Map<String, dynamic>> schedules;
  late List<Map<String, dynamic>> stations;
  late List<Map<String, dynamic>> alerts;
  late Map<String, dynamic> review;
  Completer<http.Response>? delayedRead;
  Completer<http.Response>? delayedReview;
  Completer<http.Response>? delayedInbox;
  bool stationFailure = false;

  http.Response response(Map<String, dynamic> data, [int status = 200]) =>
      http.Response(
        jsonEncode({'success': status == 200, ...data}),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> roster(int index) => {
    ...Map<String, dynamic>.from(
      jsonDecode(jsonEncode(fixture('draft')['schedules'][0])),
    ),
    'id': 'STA$index',
    'stationId': 'STA$index',
    'stationName': 'Station $index',
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationSettings.allowNotifications.value = true;
    requests = [];
    schedules = [roster(1), roster(2)];
    stations = [
      for (var i = 1; i <= 25; i++)
        {'id': 'STA$i', 'name': 'Station $i', 'isActive': true},
    ];
    review = fixture('approved');
    alerts = [
      {
        'id': 'notice1',
        'approvalId': 'review1',
        'title': 'Schedule approved and published',
        'message': 'All stations have been approved.',
        'createdAt': '2099-01-01T00:00:00Z',
        'isRead': false,
      },
    ];
    delayedRead = null;
    delayedReview = null;
    delayedInbox = null;
    stationFailure = false;
    ApiService.testClient = MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/stations':
          return stationFailure
              ? response({'detail': 'Station list unavailable'}, 503)
              : response({'stations': stations});
        case '/schedules':
          return response({'schedules': schedules});
        case '/schedule-approvals':
          return response({'approvals': []});
        case '/schedule-approvals/submit':
          return response({});
        case '/schedule-approvals/review1':
          return delayedReview?.future ?? response({'approval': review});
        case '/workflow-notifications':
          return delayedInbox?.future ?? response({'notifications': alerts});
        case '/workflow-notifications/notice1/read':
          if (delayedRead != null) return delayedRead!.future;
          alerts[0]['isRead'] = true;
          return response({});
        case '/officials':
          if (request.method == 'POST') {
            return response({
              'temporaryPassword': 'test-generated-password',
              'user': jsonDecode(request.body),
            });
          }
          return response({
            'users': [
              {
                'username': 'assistant',
                'name': 'Assistant Reviewer',
                'role': 'assistantSecurity',
                'active': true,
              },
            ],
          });
        case '/employees':
          return response({'employees': []});
        case '/attendance-reports':
          return response({'reports': []});
        case '/replacements':
          return response({'replacements': []});
        default:
          return response({'requests': []});
      }
    });
  });

  tearDown(() {
    NotificationCenter.instance.stop();
    ApiService.testClient?.close();
    ApiService.testClient = null;
  });

  Future<void> open(
    WidgetTester tester,
    Widget child, {
    double width = 1366,
    NavigatorObserver? observer,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: observer == null ? const [] : [observer],
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'period submission names missing stations and unlocks only when all 25 are complete',
    (tester) async {
      await open(tester, const ApprovalScreen(role: 'admin'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 25 stations ready'), findsOneWidget);
      expect(find.text('Station 25'), findsOneWidget);
      final submit = find.byKey(const ValueKey('submit-period'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);

      schedules = [for (var i = 1; i <= 25; i++) roster(i)];
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('25 of 25 stations ready'), findsOneWidget);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Submit for Approval').last,
      );
      await tester.pumpAndSettle();
      final posted = requests.singleWhere(
        (r) => r.url.path == '/schedule-approvals/submit',
      );
      expect(jsonDecode(posted.body)['startDate'], '2099-01-01');
      expect(jsonDecode(posted.body)['endDate'], '2099-01-15');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'incomplete assignments and an unavailable station list keep submission disabled',
    (tester) async {
      stations = stations.take(2).toList();
      schedules[0]['days'][0]['entries'] = [];
      schedules[1]['days'][0]['entries'][0]['post'] = 'Undefined';
      await open(tester, const ApprovalScreen(role: 'admin'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 stations ready'), findsOneWidget);
      expect(
        find.text('Station 1: Complete the assignments for every day.'),
        findsOneWidget,
      );
      expect(
        find.text('Station 2: Assign a post to every duty.'),
        findsOneWidget,
      );
      stationFailure = true;
      schedules = [roster(1), roster(2)];
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('submit-period')))
            .onPressed,
        isNull,
      );
      expect(find.text('Station list unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rapid alert taps open one review immediately while requests are slow',
    (tester) async {
      delayedRead = Completer<http.Response>();
      delayedReview = Completer<http.Response>();
      final observer = _RouteObserver();
      await open(
        tester,
        const WorkflowInbox(role: 'admin'),
        observer: observer,
      );
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey('approval-alert-notice1')),
      );
      tile.onTap!();
      tile.onTap!();
      tile.onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(observer.pushes, 2); // App route plus exactly one review.
      expect(find.byType(ApprovalReviewScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ApprovalReviewScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        requests.where((r) => r.url.path == '/schedule-approvals/review1'),
        hasLength(1),
      );
      expect(delayedRead!.isCompleted, isFalse);
      delayedReview!.complete(response({'approval': review}));
      delayedRead!.complete(response({}));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WorkflowInbox), findsOneWidget);
      expect(find.byType(ApprovalReviewScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'official alert shortcut opens one dialog with loading feedback immediately',
    (tester) async {
      delayedInbox = Completer<http.Response>();
      await open(tester, const WorkflowInboxButton(role: 'assistantSecurity'));
      final button = tester.widget<TextButton>(
        find.byWidgetPredicate((w) => w is TextButton),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Loading approval alerts...'), findsOneWidget);
      delayedInbox!.complete(response({'notifications': alerts}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'admin alerts live directly after Leave Requests and contribute to notification count',
    (tester) async {
      await open(tester, const NotificationsContent());
      await tester.pumpAndSettle();
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.tabs.length, 5);
      expect(
        find.descendant(
          of: find.byWidget(tabs.tabs[3]),
          matching: find.text('Leave Requests'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byWidget(tabs.tabs[4]),
          matching: find.text('Approval Alerts'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Approval Alerts'));
      await tester.tap(find.text('Approval Alerts'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('approval-alert-notice1')),
        findsOneWidget,
      );
      NotificationCenter.instance.startForAdmin();
      await tester.pumpAndSettle();
      expect(NotificationCenter.instance.unreadCount.value, 1);
      NotificationCenter.instance.stop();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'official accounts are managed inside Company Info with no duplicate sidebar links',
    (tester) async {
      await open(
        tester,
        Row(
          children: [
            Sidebar(selectedIndex: 7, onItemSelected: (_) {}),
            const Expanded(child: SettingsContent()),
          ],
        ),
        width: 1024,
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Period Approvals',
        'Official Accounts',
        'Approval Alerts',
      ]) {
        expect(
          find.descendant(of: find.byType(Sidebar), matching: find.text(label)),
          findsNothing,
        );
      }
      expect(find.byType(SettingsContent), findsOneWidget);
      await tester.tap(find.text('Company Info'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Official Accounts'));
      await tester.pumpAndSettle();
      expect(find.text('Assistant Reviewer'), findsOneWidget);
      await tester.ensureVisible(find.text('Add Official'));
      await tester.tap(find.text('Add Official'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('A password will be generated'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [1024.0, 1366.0]) {
    testWidgets(
      'PDF action stays at the top right at $width pixels for both report types',
      (tester) async {
        schedules = (review['schedules'] as List).cast<Map<String, dynamic>>();
        await open(
          tester,
          Row(
            children: [
              const SizedBox(width: 260),
              const Expanded(child: ReportsContent()),
            ],
          ),
          width: width,
        );
        await tester.pumpAndSettle();
        for (final label in ['Schedule Report', 'Leave Report']) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          final control = tester.getRect(
            find.byKey(const ValueKey('report-kind-switch')),
          );
          final export = tester.getRect(
            find.byKey(const ValueKey('report-export-action')),
          );
          expect(export.center.dy, closeTo(control.center.dy, 1));
          expect(export.right, closeTo(width - 24, 1));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
