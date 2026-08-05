// Locks in the two rules that decide whether a head guard may file an
// attendance report, both of which have regressed before:
//
//   1. SCOPE — HG Day files Morning + Afternoon, HG Night files Night,
//      and neither ever sees the other's shifts. The old "otherwise show
//      every shift" fallback let a night head guard file all three.
//   2. WINDOW — the report can only be filed while actually on post,
//      measured against ServerClock so the device clock can't open it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/employee.dart';
import 'package:scheduling_system/models/station_roster.dart';
import 'package:scheduling_system/screens/headguardui/headguard_report_screen.dart';
import 'package:scheduling_system/services/server_clock.dart';

Employee headGuard({required String assignedShift, String id = 'HG001'}) {
  return Employee(
    id: id,
    name: 'Test HeadGuard',
    email: 'hg@example.com',
    phone: '09170000000',
    preferredStations: const ['Ayala'],
    type: EmployeeType.headGuard,
    assignedStation: 'Ayala',
    assignedShift: assignedShift,
  );
}

// A roster for `date` holding the head guard plus one guard on each shift.
StationRoster rosterWith({
  required DateTime date,
  required String hgShift,
  bool includeHeadGuard = true,
  String hgId = 'HG001',
}) {
  return StationRoster(
    stationName: 'Ayala',
    date: date,
    hasSchedule: true,
    onDuty: [
      if (includeHeadGuard)
        RosterEntry(
            employeeId: hgId, employeeName: 'Test HeadGuard', shift: hgShift),
      RosterEntry(
          employeeId: 'E1', employeeName: 'Morning Guard', shift: 'Morning'),
      RosterEntry(
          employeeId: 'E2', employeeName: 'Afternoon Guard', shift: 'Afternoon'),
      RosterEntry(
          employeeId: 'E3', employeeName: 'Night Guard', shift: 'Night'),
    ],
    dayOff: const [],
  );
}

Future<void> pumpReport(
  WidgetTester tester, {
  required Employee employee,
  required StationRoster roster,
}) async {
  // Tall surface so the whole ListView is built: it lazily skips children
  // outside the viewport, and the locked banner pushes the submit button
  // past the bottom of a default 800px test screen.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: HeadGuardReportScreen(employee: employee, roster: roster),
  ));
  // initState fires a reports fetch; in tests HTTP is stubbed out and
  // fails fast, so a couple of pumps clears the spinner.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final aug1 = DateTime(2026, 8, 1);

  tearDown(() => ServerClock.debugNowOverride = null);

  group('Shift scope', () {
    testWidgets('HG Night is offered the Night shift and nothing else',
        (tester) async {
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 1, 20, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgNight'),
        roster: rosterWith(date: aug1, hgShift: 'HG Night'),
      );

      expect(find.textContaining('Night Shift'), findsWidgets);
      // The other two shifts must not appear anywhere on the screen.
      expect(find.textContaining('Morning Shift'), findsNothing);
      expect(find.textContaining('Afternoon Shift'), findsNothing);
      // Only the Night guard is listed as personnel.
      expect(find.text('Night Guard'), findsOneWidget);
      expect(find.text('Morning Guard'), findsNothing);
    });

    testWidgets('HG Day is offered Morning and Afternoon, never Night',
        (tester) async {
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 1, 9, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgDay'),
        roster: rosterWith(date: aug1, hgShift: 'HG Day'),
      );

      // Both covered shifts appear as selector pills.
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);
      expect(find.text('Night'), findsNothing);
    });
  });

  group('Duty window', () {
    testWidgets('on post during the duty — submit is enabled', (tester) async {
      // HG Night runs 1700H - 0500H; 2000H is mid-duty.
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 1, 20, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgNight'),
        roster: rosterWith(date: aug1, hgShift: 'HG Night'),
      );

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit Night Shift Report'),
      );
      expect(button.onPressed, isNotNull, reason: 'should be submittable');
    });

    testWidgets('after midnight but still on post — still enabled',
        (tester) async {
      // 0200H on Aug 2 is inside the duty that began 1700H on Aug 1.
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 2, 2, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgNight'),
        roster: rosterWith(date: aug1, hgShift: 'HG Night'),
      );

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit Night Shift Report'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('before time-in — locked, and says when it opens',
        (tester) async {
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 1, 15, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgNight'),
        roster: rosterWith(date: aug1, hgShift: 'HG Night'),
      );

      expect(find.text('Your duty has not started yet'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Opens at 1700H'),
      );
      expect(button.onPressed, isNull, reason: 'must not be submittable');
    });

    testWidgets('after time-out — locked', (tester) async {
      // 0600H on Aug 2, an hour after the 0500H time-out.
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 2, 6, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgNight'),
        roster: rosterWith(date: aug1, hgShift: 'HG Night'),
      );

      expect(find.text('Your duty has ended'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Duty Ended — Reporting Closed'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('not on the roster — read-only, and still only their shift',
        (tester) async {
      ServerClock.debugNowOverride = () => DateTime(2026, 8, 1, 20, 0);
      await pumpReport(
        tester,
        employee: headGuard(assignedShift: 'hgNight'),
        roster: rosterWith(
            date: aug1, hgShift: 'HG Night', includeHeadGuard: false),
      );

      expect(find.text('You are off duty today'), findsOneWidget);
      // The regression that started all this: never all three shifts.
      expect(find.text('Morning'), findsNothing);
      expect(find.text('Afternoon'), findsNothing);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Off Duty — Reporting Locked'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
