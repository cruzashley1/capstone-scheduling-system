// Renders the Today's Duty card in every status at a phone width, to
// catch layout overflows the analyzer can't see.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/guard_shift.dart';
import 'package:scheduling_system/services/duty_clock.dart';
import 'package:scheduling_system/widgets/today_duty_card.dart';

void main() {
  final aug1 = DateTime(2026, 8, 1);

  GuardShift shift(String name, {String? coveringFor}) => GuardShift(
        date: aug1,
        scheduleId: 'sched-1',
        stationId: 'st-1',
        stationName: 'Ayala Malls Feliz — Main Entrance Lobby',
        shift: name,
        coveringFor: coveringFor,
      );

  Future<void> pumpCard(WidgetTester tester, LiveDutyState state) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TodayDutyCard(
              state: state,
              stationLabel: 'No station yet',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('On Duty shows the clock, countdown and progress bar',
      (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.onDuty,
        shift: shift('Morning'),
        now: DateTime(2026, 8, 1, 9, 30, 0),
      ),
    );

    expect(find.text('0930H'), findsOneWidget);
    expect(find.text('9:30:00 AM'), findsOneWidget);
    expect(find.text('On Duty'), findsOneWidget);
    expect(find.text('Morning Shift'), findsOneWidget);
    expect(find.text('0500H - 1400H'), findsOneWidget);
    expect(find.text('Time out in 4h 30m'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Off Shift at 8pm — the reported case', (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.offShift,
        shift: shift('Morning'),
        now: DateTime(2026, 8, 1, 20, 0, 0),
      ),
    );

    expect(find.text('2000H'), findsOneWidget);
    expect(find.text('Off Shift'), findsOneWidget);
    expect(find.text('On Duty'), findsNothing);
    expect(find.text('Timed out 6h ago'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('Awaiting a later shift', (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.awaiting,
        shift: shift('Afternoon'),
        now: DateTime(2026, 8, 1, 8, 0, 0),
      ),
    );

    expect(find.text('Awaiting'), findsOneWidget);
    expect(find.text('Time in in 6h'), findsOneWidget);
  });

  testWidgets('Day Off has no duty details', (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.dayOff,
        now: DateTime(2026, 8, 1, 12, 0, 0),
      ),
    );

    expect(find.text('Day Off'), findsOneWidget);
    expect(find.text('Rest Day'), findsOneWidget);
    expect(find.text('Enjoy your day off!'), findsOneWidget);
  });

  testWidgets('Absent overrides the time-based status', (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.absent,
        shift: shift('Morning'),
        now: DateTime(2026, 8, 1, 9, 0, 0),
      ),
    );

    expect(find.text('Absent'), findsOneWidget);
    expect(find.text('Excused from this duty'), findsOneWidget);
  });

  testWidgets('Unassigned when no schedule reaches today', (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.unassigned,
        now: DateTime(2026, 8, 1, 12, 0, 0),
      ),
    );

    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('No Published Schedule'), findsOneWidget);
  });

  // An overnight duty is still "today's" duty to the guard on post, but
  // its times belong to yesterday — the card has to say so.
  testWidgets('Overnight duty from yesterday is labelled', (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.onDuty,
        shift: shift('Night'),
        now: DateTime(2026, 8, 2, 2, 0, 0),
      ),
    );

    expect(find.text('On Duty'), findsOneWidget);
    expect(find.text('Overnight duty from Aug 1'), findsOneWidget);
    expect(find.text('Time out in 4h'), findsOneWidget);
  });

  testWidgets('Covering chip still renders alongside the status',
      (tester) async {
    await pumpCard(
      tester,
      LiveDutyState(
        status: LiveDutyStatus.onDuty,
        shift: shift('Morning', coveringFor: 'Juan Dela Cruz'),
        now: DateTime(2026, 8, 1, 9, 0, 0),
      ),
    );

    expect(find.text('Covering for Juan Dela Cruz'), findsOneWidget);
  });
}
