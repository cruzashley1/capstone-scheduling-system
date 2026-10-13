import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scheduling_system/screens/approval_screen.dart';
import 'package:scheduling_system/screens/official_layout.dart';
import 'package:scheduling_system/screens/reports_screen.dart';
import 'package:scheduling_system/services/api_service.dart';

Map<String, dynamic> fixture(String status) {
  final events = <Map<String, dynamic>>[
    {
      'action': 'submitted',
      'name': 'Scheduler',
      'username': 'admin',
      'role': 'admin',
      'at': '2098-12-20T00:00:00+00:00',
      'comment': '',
    },
    if (status != 'pending_assistant')
      {
        'action': 'approve',
        'name': 'Assistant Reviewer',
        'username': 'assistant',
        'role': 'assistantSecurity',
        'at': '2098-12-20T01:00:00+00:00',
        'comment': '',
      },
    if (status == 'approved')
      {
        'action': 'approve',
        'name': 'Final Reviewer',
        'username': 'commander',
        'role': 'areaCommander',
        'at': '2098-12-20T02:00:00+00:00',
        'comment': '',
      },
  ];
  return {
    'id': 'review1',
    'version': events.length,
    'revision': 1,
    'status': status,
    'startDate': '2099-01-01',
    'endDate': '2099-01-15',
    'submittedName': 'Scheduler',
    'submittedBy': 'admin',
    'submittedAt': '2098-12-20T00:00:00+00:00',
    'events': events,
    'amendments': [],
    'schedules': [
      for (var n = 1; n <= 2; n++)
        {
          'id': 'STA$n',
          'stationId': 'STA$n',
          'stationName': 'Station $n',
          'startDate': '2099-01-01',
          'endDate': '2099-01-15',
          'createdAt': '2098-12-20T00:00:00+00:00',
          'status': status == 'approved' ? 'published' : 'unpublished',
          'approvalId': 'review1',
          'approvalStatus': status,
          'days': [
            for (var day = 1; day <= 15; day++)
              {
                'date': '2099-01-${day.toString().padLeft(2, '0')}',
                'entries': [
                  {
                    'id': '$n-$day',
                    'employeeId': 'GUARD$n',
                    'employeeName': 'Guard $n',
                    'post': 'Roving',
                    'shift': 'Morning',
                    'timeIn': '05:00',
                    'timeOut': '14:00',
                    'isReliever': false,
                  },
                ],
              },
          ],
        },
    ],
  };
}

void main() {
  late Map<String, dynamic> record;
  late List<http.Request> requests;
  Uint8List? pdf;
  setUp(() {
    record = fixture('pending_assistant');
    requests = [];
    pdf = null;
    ApiService.testClient = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      Object response = {'success': true};
      if (path == '/schedule-approvals') {
        response = {
          'approvals': [record],
        };
      }
      if (path == '/schedule-approvals/review1') {
        response = {'approval': record};
      }
      if (path.endsWith('/decision')) {
        final body = jsonDecode(request.body);
        record['version'] = record['version'] + 1;
        record['status'] = body['action'] == 'return'
            ? 'returned'
            : record['status'] == 'pending_assistant'
            ? 'pending_commander'
            : 'approved';
        response = {'approval': record};
      }
      if (path == '/schedules') response = {'schedules': record['schedules']};
      if (path == '/replacements') response = {'replacements': []};
      if (path == '/leave-requests') response = {'requests': []};
      if (path == '/workflow-notifications') response = {'notifications': []};
      if (path == '/account') {
        response = {
          'name': 'Assistant Reviewer',
          'role': 'assistantSecurity',
          'username': 'assistant',
        };
      }
      if (path == '/schedule-report') {
        response = {
          'schedules': record['schedules'],
          'approval': record,
          'replacements': [],
        };
      }
      return http.Response(
        jsonEncode({'success': true, ...response as Map<String, dynamic>}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('net.nfet.printing'), (
          call,
        ) async {
          if (call.method == 'sharePdf') {
            pdf =
                call.arguments['doc'] as Uint8List? ??
                call.arguments['bytes'] as Uint8List?;
            return true;
          }
          return null;
        });
  });
  tearDown(() {
    ApiService.testClient?.close();
    ApiService.testClient = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('net.nfet.printing'),
          null,
        );
  });

  Future<void> open(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1366, 768),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Area Commander waits for Assistant Security and review never loads editing data',
    (tester) async {
      await open(
        tester,
        const ApprovalReviewScreen(id: 'review1', role: 'areaCommander'),
      );
      expect(
        find.text('Assistant Security must approve first.'),
        findsOneWidget,
      );
      expect(find.text('Approve Entire Period'), findsNothing);
      expect(requests.any((r) => r.url.path == '/employees'), isFalse);
      await tester.tap(find.text('View Every Day’s Assignments'));
      await tester.pumpAndSettle();
      expect(find.text('Guard 1'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Assistant approval sends exact revision and advances the workflow',
    (tester) async {
      await open(
        tester,
        const ApprovalReviewScreen(id: 'review1', role: 'assistantSecurity'),
      );
      await tester.tap(find.text('Approve Entire Period'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve Period'));
      await tester.pumpAndSettle();
      final posted = requests.singleWhere(
        (r) => r.url.path.endsWith('/decision'),
      );
      expect(jsonDecode(posted.body), {
        'action': 'approve',
        'comment': '',
        'version': 1,
      });
      expect(find.text('Awaiting Area Commander'), findsWidgets);
      expect(find.text('Approve Entire Period'), findsNothing);
    },
  );

  testWidgets('Area Commander final approval explains automatic publication', (
    tester,
  ) async {
    record = fixture('pending_commander');
    await open(
      tester,
      const ApprovalReviewScreen(id: 'review1', role: 'areaCommander'),
    );
    await tester.tap(find.text('Approve Entire Period'));
    await tester.pumpAndSettle();
    expect(find.textContaining('publish all schedules'), findsOneWidget);
    await tester.tap(find.text('Approve Period'));
    await tester.pumpAndSettle();
    expect(find.text('Approved · Published'), findsOneWidget);
  });

  testWidgets('Returning schedules requires a revision comment', (
    tester,
  ) async {
    await open(
      tester,
      const ApprovalReviewScreen(id: 'review1', role: 'assistantSecurity'),
    );
    await tester.tap(find.text('Return for Revision'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return to Admin'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason.'), findsOneWidget);
    expect(requests.any((r) => r.url.path.endsWith('/decision')), isFalse);
    await tester.enterText(
      find.byType(TextField),
      'Correct Station 2 duty times.',
    );
    await tester.tap(find.text('Return to Admin'));
    await tester.pumpAndSettle();
    expect(find.text('Returned for revision'), findsWidgets);
  });

  for (final width in [1024.0, 1366.0]) {
    testWidgets('official desktop layout fits ${width.toInt()} pixels', (
      tester,
    ) async {
      await open(
        tester,
        const OfficialLayout(username: 'assistant', role: 'assistantSecurity'),
        size: Size(width, 768),
      );
      expect(find.text('Generate Schedule'), findsNothing);
      expect(find.text('Official Accounts'), findsNothing);
      expect(find.text('Review & Decide'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('unapproved schedule has no PDF export action', (tester) async {
    await open(tester, const Scaffold(body: ReportsContent()));
    expect(find.text('Awaiting Approval'), findsOneWidget);
    expect(find.text('Export PDF'), findsNothing);
    expect(pdf, isNull);
  });

  testWidgets('approved PDF is generated from freshly authorized schedules', (
    tester,
  ) async {
    record = fixture('approved');
    await open(tester, const Scaffold(body: ReportsContent()));
    await tester.tap(find.text('Export PDF').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(requests.any((r) => r.url.path == '/schedule-report'), isTrue);
    expect(pdf, isNotNull);
    expect(pdf!.length, greaterThan(1000));
    expect(String.fromCharCodes(pdf!.take(5)), '%PDF-');
    expect(tester.takeException(), isNull);
  });
}
