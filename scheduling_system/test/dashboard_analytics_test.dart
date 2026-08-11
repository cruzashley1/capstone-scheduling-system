// Locks in the arithmetic behind the dashboard's analytics band. All
// three panels are pure functions over lists the dashboard already
// holds, so they can be checked without building a widget.
//
// Two rules here have already been got wrong once each:
//
//   1. HEAD GUARDS. A station's requiredMorning INCLUDES its day head
//      guard, but that guard's entry is filed under the shift 'HG Day',
//      not 'Morning'. Bucket naively and every station reads two posts
//      short — which looks exactly like a staffing crisis and isn't.
//
//   2. WHAT COVERAGE IS MEASURED AGAINST. Measured against only the
//      stations that HAVE a schedule, coverage is 100% by construction
//      — the generator fills what it is asked to fill. The panel
//      measures against every active station, so an unscheduled station
//      shows up as the real shortfall it is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/attendance_report.dart';
import 'package:scheduling_system/models/schedule.dart';
import 'package:scheduling_system/models/schedule_note.dart';
import 'package:scheduling_system/models/station.dart';
import 'package:scheduling_system/widgets/dashboard_analytics.dart';

final DateTime today = DateTime(2026, 8, 10);

Station station({
  String id = 'STA001',
  int morning = 3,
  int afternoon = 2,
  int night = 2,
  bool isActive = true,
}) {
  return Station(
    id: id,
    name: 'Station $id',
    requiredEmployees: morning + afternoon + night,
    requiredMorning: morning,
    requiredAfternoon: afternoon,
    requiredNight: night,
    isActive: isActive,
  );
}

ScheduleEntry entry(String shift, {String id = 'E'}) => ScheduleEntry(
      id: '$id-$shift',
      employeeId: id,
      employeeName: 'Guard $id',
      shift: shift,
    );

Schedule schedule({
  String stationId = 'STA001',
  ScheduleStatus status = ScheduleStatus.published,
  required List<ScheduleEntry> entries,
  DateTime? start,
  DateTime? end,
  DateTime? dayDate,
  List<ScheduleNote> notes = const [],
}) {
  return Schedule(
    id: '${stationId}_x',
    stationId: stationId,
    stationName: 'Station $stationId',
    startDate: start ?? DateTime(2026, 8, 4),
    endDate: end ?? DateTime(2026, 8, 18),
    createdAt: DateTime(2026, 8, 1),
    status: status,
    days: [ScheduleDay(date: dayDate ?? today, entries: entries)],
    notes: notes,
  );
}

ScheduleNote note(
  NoteCategory category,
  NoteSeverity severity, {
  String subject = 'Ayala',
  String problem = 'something',
  String fix = '',
  String? station,
}) =>
    ScheduleNote(
      category: category,
      severity: severity,
      subject: subject,
      problem: problem,
      fix: fix,
      station: station,
    );

AttendanceReport report({
  required String date,
  required int present,
  required int absent,
  String station = 'Ayala',
}) {
  return AttendanceReport(
    id: 'RPT-$date-$station-$present$absent',
    headGuardName: 'HG',
    headGuardId: 'HG001',
    station: station,
    shiftTitle: 'Morning Shift',
    date: date,
    submittedAt: DateTime.parse('${date}T09:00:00Z'),
    records: [
      for (var i = 0; i < present; i++)
        AttendanceRecord(
          name: 'Present $i',
          employeeId: 'P$i',
          shift: 'Morning',
          time: '0500H - 1400H',
          isPresent: true,
        ),
      for (var i = 0; i < absent; i++)
        AttendanceRecord(
          name: 'Absent $i',
          employeeId: 'A$i',
          shift: 'Morning',
          time: '0500H - 1400H',
          isPresent: false,
        ),
    ],
  );
}

void main() {
  group('coverage — shift bucketing', () {
    test('HG Day counts toward Morning and HG Night toward Night', () {
      // 3 morning posts = day head guard + 2 others; 2 night = night HG
      // + 1 other. Fully manned, so this must read 100% — not 5/7.
      final coverage = computeCoverage(
        stations: [station(morning: 3, afternoon: 2, night: 2)],
        schedules: [
          schedule(entries: [
            entry('HG Day', id: 'HG1'),
            entry('Morning', id: 'A'),
            entry('Morning', id: 'B'),
            entry('Afternoon', id: 'C'),
            entry('Afternoon', id: 'D'),
            entry('HG Night', id: 'HG2'),
            entry('Night', id: 'E'),
          ]),
        ],
        today: today,
      );

      expect(coverage.manned, 7);
      expect(coverage.totalDemand, 7);
      expect(coverage.rate, 1.0);

      final morning = coverage.shifts.firstWhere((s) => s.label == 'Morning');
      expect(morning.manned, 3, reason: 'HG Day belongs to Morning');
      final night = coverage.shifts.firstWhere((s) => s.label == 'Night');
      expect(night.manned, 2, reason: 'HG Night belongs to Night');
    });

    test('the day head guard is not double-counted into Afternoon', () {
      // The day HG's 12-hour duty spans the afternoon, but the station
      // has no afternoon head guard slot — so Afternoon must count only
      // its own entries or it reads over-staffed.
      final coverage = computeCoverage(
        stations: [station(morning: 1, afternoon: 1, night: 0)],
        schedules: [
          schedule(entries: [
            entry('HG Day', id: 'HG1'),
            entry('Afternoon', id: 'A'),
          ]),
        ],
        today: today,
      );

      final afternoon =
          coverage.shifts.firstWhere((s) => s.label == 'Afternoon');
      expect(afternoon.manned, 1);
      expect(afternoon.totalDemand, 1);
    });
  });

  group('coverage — where the shortfall is', () {
    test('a post left empty inside a published schedule reads as '
        'unfilled, not unscheduled', () {
      final coverage = computeCoverage(
        stations: [station(morning: 3, afternoon: 0, night: 0)],
        schedules: [
          schedule(entries: [entry('HG Day', id: 'HG1'), entry('Morning')]),
        ],
        today: today,
      );

      final morning = coverage.shifts.firstWhere((s) => s.label == 'Morning');
      expect(morning.manned, 2);
      expect(morning.unfilled, 1);
      expect(morning.unscheduled, 0);
      expect(coverage.rate, closeTo(2 / 3, 0.0001));
      expect(coverage.scheduledRate, closeTo(2 / 3, 0.0001));
    });

    test('an unscheduled station\'s posts count as demand and as '
        'unscheduled, never as unfilled', () {
      final coverage = computeCoverage(
        stations: [
          station(id: 'STA001', morning: 2, afternoon: 0, night: 0),
          station(id: 'STA002', morning: 6, afternoon: 0, night: 0),
        ],
        schedules: [
          schedule(stationId: 'STA001', entries: [
            entry('HG Day', id: 'HG1'),
            entry('Morning', id: 'A'),
          ]),
        ],
        today: today,
      );

      expect(coverage.manned, 2);
      expect(coverage.totalDemand, 8, reason: 'both stations need manning');
      expect(coverage.scheduledDemand, 2);
      expect(coverage.unfilled, 0, reason: 'STA001 is fully manned');
      expect(coverage.unscheduled, 6, reason: 'all of STA002');
      expect(coverage.scheduledStations, 1);
      expect(coverage.unscheduledStations, 1);

      // The headline is the operational number...
      expect(coverage.rate, closeTo(2 / 8, 0.0001));
      // ...while the roster the generator DID produce is perfect. Both
      // are true, and reporting only the second is what made the first
      // version of this panel read a flat 100%.
      expect(coverage.scheduledRate, 1.0);
    });

    test('the three segments always account for the whole demand', () {
      final coverage = computeCoverage(
        stations: [
          station(id: 'STA001', morning: 4, afternoon: 2, night: 2),
          station(id: 'STA002', morning: 3, afternoon: 3, night: 1),
        ],
        schedules: [
          schedule(stationId: 'STA001', entries: [entry('Morning')]),
        ],
        today: today,
      );

      expect(
        coverage.manned + coverage.unfilled + coverage.unscheduled,
        coverage.totalDemand,
      );
      for (final shift in coverage.shifts) {
        expect(
          shift.manned + shift.unfilled + shift.unscheduled,
          shift.totalDemand,
          reason: '${shift.label} segments must tile its bar exactly',
        );
      }
    });
  });

  group('coverage — which stations count', () {
    test('a schedule that does not cover today leaves the station '
        'unscheduled rather than reporting a stale day', () {
      final coverage = computeCoverage(
        stations: [station()],
        schedules: [
          schedule(
            entries: [entry('Morning')],
            start: DateTime(2026, 7, 1),
            end: DateTime(2026, 7, 15),
            dayDate: DateTime(2026, 7, 1),
          ),
        ],
        today: today,
      );

      expect(coverage.scheduledStations, 0);
      expect(coverage.unscheduledStations, 1);
      expect(coverage.manned, 0);
      expect(coverage.unscheduled, 7);
    });

    test('unpublished schedules do not count as coverage', () {
      final coverage = computeCoverage(
        stations: [station()],
        schedules: [
          schedule(
            status: ScheduleStatus.unpublished,
            entries: [entry('Morning')],
          ),
        ],
        today: today,
      );

      expect(coverage.scheduledStations, 0);
      expect(coverage.manned, 0);
    });

    test('inactive stations are ignored entirely', () {
      final coverage = computeCoverage(
        stations: [station(id: 'STA001', isActive: false)],
        schedules: const [],
        today: today,
      );

      expect(coverage.hasData, isFalse);
      expect(coverage.totalDemand, 0);
      expect(coverage.unscheduledStations, 0);
    });

    test('a station with no shift breakdown contributes no demand', () {
      final coverage = computeCoverage(
        stations: [
          station(id: 'STA001', morning: 0, afternoon: 0, night: 0),
          station(id: 'STA002', morning: 2, afternoon: 0, night: 0),
        ],
        schedules: const [],
        today: today,
      );

      expect(coverage.totalDemand, 2, reason: 'only STA002 has a requirement');
      expect(coverage.unscheduledStations, 1);
    });
  });

  group('attendance trend', () {
    test('reports on the same day are summed into one column', () {
      final trend = computeAttendanceTrend([
        report(date: '2026-08-09', present: 5, absent: 0, station: 'A'),
        report(date: '2026-08-09', present: 3, absent: 1, station: 'B'),
      ]);

      expect(trend.days, hasLength(1));
      expect(trend.days.single.present, 8);
      expect(trend.days.single.absent, 1);
      expect(trend.days.single.reports, 2);
      expect(trend.rate, closeTo(8 / 9, 0.0001));
    });

    test('columns come out oldest first, whatever order they arrived', () {
      final trend = computeAttendanceTrend([
        report(date: '2026-08-09', present: 1, absent: 0),
        report(date: '2026-07-16', present: 1, absent: 0),
        report(date: '2026-08-02', present: 1, absent: 0),
      ]);

      expect(
        trend.days.map((d) => d.date.day).toList(),
        [16, 2, 9],
      );
    });

    test('only days a report was filed become columns — a quiet day is '
        'absent from the axis, not a zero', () {
      // Jul 16 and Aug 9 are 24 days apart. Plotting calendar days would
      // draw 23 empty columns and read as a collapse in attendance.
      final trend = computeAttendanceTrend([
        report(date: '2026-07-16', present: 4, absent: 0),
        report(date: '2026-08-09', present: 4, absent: 0),
      ]);

      expect(trend.days, hasLength(2));
      expect(trend.rate, 1.0);
    });

    test('keeps only the most recent reporting days', () {
      final trend = computeAttendanceTrend([
        for (var d = 1; d <= 20; d++)
          report(
            date: '2026-08-${d.toString().padLeft(2, '0')}',
            present: 1,
            absent: 0,
          ),
      ], maxDays: 14);

      expect(trend.days, hasLength(14));
      expect(trend.days.first.date.day, 7, reason: 'Aug 7..Aug 20');
      expect(trend.days.last.date.day, 20);
    });

    test('the tallest column scales the plot', () {
      final trend = computeAttendanceTrend([
        report(date: '2026-08-01', present: 2, absent: 0),
        report(date: '2026-08-02', present: 8, absent: 1),
      ]);

      expect(trend.busiestDay, 9);
      expect(trend.daysWithAbsence, 1);
    });

    test('no reports reads as no data rather than 0% attendance', () {
      final trend = computeAttendanceTrend(const []);

      expect(trend.hasData, isFalse);
      expect(trend.rate, 0);
      expect(trend.total, 0);
    });
  });

  group('schedule health', () {
    test('notes are tallied by category, biggest first', () {
      final health = computeScheduleHealth([
        schedule(entries: const [], notes: [
          note(NoteCategory.cover, NoteSeverity.info),
          note(NoteCategory.leave, NoteSeverity.info),
          note(NoteCategory.leave, NoteSeverity.warning),
        ]),
        schedule(stationId: 'STA002', entries: const [], notes: [
          note(NoteCategory.leave, NoteSeverity.info),
        ]),
      ]);

      expect(health.total, 4);
      expect(health.scheduleCount, 2);
      expect(health.tallies.first.category, NoteCategory.leave);
      expect(health.tallies.first.count, 3);
      expect(health.maxCount, 3);
    });

    test('only non-info notes count as actionable', () {
      final health = computeScheduleHealth([
        schedule(entries: const [], notes: [
          note(NoteCategory.staffing, NoteSeverity.blocker),
          note(NoteCategory.headGuard, NoteSeverity.warning),
          note(NoteCategory.leave, NoteSeverity.info),
          note(NoteCategory.rotation, NoteSeverity.info),
        ]),
      ]);

      expect(health.total, 4);
      expect(health.actionable, 2,
          reason: 'counting info notes would make a clean run look broken');
    });

    test('no notes reads as no data rather than a zeroed chart', () {
      final health = computeScheduleHealth([
        schedule(entries: const [], notes: const []),
      ]);

      expect(health.hasData, isFalse);
      expect(health.scheduleCount, 0);
    });
  });

  group('schedule model', () {
    test('parses scheduleNotes off a stored schedule', () {
      final parsed = Schedule.fromJson({
        'id': 'STA001_2026-08-04',
        'stationId': 'STA001',
        'stationName': 'Ayala',
        'startDate': '2026-08-04',
        'endDate': '2026-08-18',
        'createdAt': '2026-08-01T00:00:00Z',
        'status': 'published',
        'days': [],
        'scheduleNotes': [
          {
            'category': 'leave',
            'severity': 'warning',
            'subject': 'Ayala',
            'problem': 'on leave',
            'fix': '',
          },
        ],
      });

      expect(parsed.notes, hasLength(1));
      expect(parsed.notes.first.category, NoteCategory.leave);
      expect(parsed.notes.first.severity, NoteSeverity.warning);
    });

    test('falls back to the legacy flat rotationNotes list', () {
      final parsed = Schedule.fromJson({
        'id': 'STA001_2026-08-04',
        'stationId': 'STA001',
        'stationName': 'Ayala',
        'startDate': '2026-08-04',
        'endDate': '2026-08-18',
        'createdAt': '2026-08-01T00:00:00Z',
        'status': 'published',
        'days': [],
        'rotationNotes': ['Ayala had no reliever free on Aug 6'],
      });

      expect(parsed.notes, hasLength(1));
      expect(parsed.notes.first.severity, NoteSeverity.warning);
      expect(parsed.notes.first.problem, contains('no reliever'));
    });
  });

  // The panel can only say HOW MANY compromises there were. Everything
  // that makes a note actionable — which roster, which fortnight, which
  // station — lives in these fields, and the aggregate used to discard
  // all of it.
  group('schedule health — the breakdown behind the bars', () {
    test('a note carries the run that filed it', () {
      final health = computeScheduleHealth([
        schedule(
          stationId: 'STA001',
          entries: const [],
          start: DateTime(2026, 8, 4),
          end: DateTime(2026, 8, 18),
          notes: [note(NoteCategory.cover, NoteSeverity.warning)],
        ),
      ]);

      final filed = health.notes.single;
      expect(filed.scheduleId, 'STA001_x');
      expect(filed.stationName, 'Station STA001');
      expect(filed.periodLabel, 'Aug 4 – Aug 18');
    });

    test('a note naming its own station keeps that name over the '
        'schedule\'s', () {
      // Cover and rotation notes are about a guard moving BETWEEN
      // stations, so the note's station is the one that matters.
      final health = computeScheduleHealth([
        schedule(stationId: 'STA001', entries: const [], notes: [
          note(NoteCategory.cover, NoteSeverity.warning, station: 'Ayala'),
        ]),
      ]);

      expect(health.notes.single.stationName, 'Ayala');
    });

    test('notes come out worst first', () {
      final health = computeScheduleHealth([
        schedule(entries: const [], notes: [
          note(NoteCategory.leave, NoteSeverity.info, problem: 'third'),
          note(NoteCategory.staffing, NoteSeverity.blocker, problem: 'first'),
          note(NoteCategory.cover, NoteSeverity.warning, problem: 'second'),
        ]),
      ]);

      expect(
        health.notes.map((n) => n.note.problem).toList(),
        ['first', 'second', 'third'],
      );
    });

    test('a tally knows its severity mix, so the bar can be stacked by '
        'it and still total the headline', () {
      final health = computeScheduleHealth([
        schedule(stationId: 'STA001', entries: const [], notes: [
          note(NoteCategory.cover, NoteSeverity.blocker, station: 'Ayala'),
          note(NoteCategory.cover, NoteSeverity.warning, station: 'Ayala'),
          note(NoteCategory.cover, NoteSeverity.info, station: 'BGC'),
        ]),
      ]);

      final cover = health.tallies.single;
      expect(cover.count, 3);
      expect(cover.severityCount(NoteSeverity.blocker), 1);
      expect(cover.severityCount(NoteSeverity.warning), 1);
      expect(cover.severityCount(NoteSeverity.info), 1);
      expect(cover.actionable, 2);
      expect(cover.worst, NoteSeverity.blocker);
      expect(cover.stationCount, 2);

      // The severity segments across every bar must add up to the same
      // number the headline reports, or the panel contradicts itself.
      final actionableInBars = health.tallies.fold<int>(
        0,
        (sum, t) =>
            sum +
            t.severityCount(NoteSeverity.blocker) +
            t.severityCount(NoteSeverity.warning),
      );
      expect(actionableInBars, health.actionable);
    });

    test('stationCount counts distinct stations across every run', () {
      final health = computeScheduleHealth([
        schedule(stationId: 'STA001', entries: const [], notes: [
          note(NoteCategory.cover, NoteSeverity.warning, station: 'Ayala'),
          note(NoteCategory.leave, NoteSeverity.info, station: 'Ayala'),
        ]),
        schedule(stationId: 'STA002', entries: const [], notes: [
          note(NoteCategory.leave, NoteSeverity.info, station: 'BGC'),
        ]),
      ]);

      expect(health.stationCount, 2);
      expect(health.severityCount(NoteSeverity.info), 2);
    });
  });

  // Layout regressions here are silent: an overflow inside a card just
  // paints a stripe nobody screenshots. These pump the real band at the
  // two widths it has separate layouts for.
  group('the analytics band renders', () {
    final stations = [
      station(id: 'STA001', morning: 3, afternoon: 2, night: 2),
      station(id: 'STA002', morning: 4, afternoon: 2, night: 2),
    ];

    final schedules = [
      schedule(
        stationId: 'STA001',
        entries: [entry('HG Day', id: 'HG1'), entry('Morning', id: 'A')],
        notes: [
          note(
            NoteCategory.cover,
            NoteSeverity.warning,
            subject: 'Station STA001 — Aug 6',
            problem: 'No reliever was free to cover the day off',
            fix: 'Assign another reliever to this station.',
          ),
          note(
            NoteCategory.leave,
            NoteSeverity.info,
            subject: 'Maria Santos',
            problem: 'On approved leave for the whole period',
          ),
        ],
      ),
    ];

    final reports = [
      report(date: '2026-08-08', present: 6, absent: 0),
      report(date: '2026-08-09', present: 5, absent: 1),
    ];

    Widget harness(double width) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: DashboardAnalytics(
                stations: stations,
                schedules: schedules,
                attendanceReports: reports,
                isLoading: false,
                today: today,
              ),
            ),
          ),
        ),
      );
    }

    // The view, not setSurfaceSize: the dialog caps its own height at a
    // share of MediaQuery, and setSurfaceSize leaves MediaQuery on the
    // default 800x600 — which silently gives the breakdown a 195px list
    // and makes a section that renders fine look missing.
    void useScreen(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('wide, with the coverage panel split into its two halves',
        (tester) async {
      useScreen(tester, const Size(1400, 2400));

      await tester.pumpWidget(harness(1400));

      expect(find.text('Operations Analytics'), findsOneWidget);
      expect(find.text('Post Coverage — Today'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Schedule Health'), findsOneWidget);
      expect(find.text('Aug 10, 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow, with everything stacked', (tester) async {
      useScreen(tester, const Size(720, 3000));

      await tester.pumpWidget(harness(720));

      expect(find.text('Schedule Health'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a section opens the notes behind that bar',
        (tester) async {
      useScreen(tester, const Size(1400, 2400));

      await tester.pumpWidget(harness(1400));

      // The bar says "1". It does not say WHICH day off went uncovered.
      expect(find.text('Reliever Cover'), findsOneWidget);
      expect(
        find.textContaining('No reliever was free'),
        findsNothing,
      );

      await tester.tap(find.text('Reliever Cover'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No reliever was free'), findsOneWidget);
      expect(find.textContaining('Assign another reliever'), findsOneWidget);
      // Opened from a bar, the breakdown arrives filtered to it — so the
      // other category's note is not in the list yet.
      expect(find.textContaining('On approved leave'), findsNothing);
      expect(find.text('Showing 1 of 2 notes'), findsOneWidget);
    });

    testWidgets('the breakdown opens whole from the panel button, and a '
        'severity toggle hides that severity', (tester) async {
      useScreen(tester, const Size(1400, 2400));

      await tester.pumpWidget(harness(1400));

      await tester.tap(find.text('Breakdown'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No reliever was free'), findsOneWidget);
      expect(find.textContaining('On approved leave'), findsOneWidget);

      await tester.tap(find.text('For information'));
      await tester.pumpAndSettle();

      expect(find.textContaining('On approved leave'), findsNothing);
      expect(find.textContaining('No reliever was free'), findsOneWidget);
      expect(find.text('Showing 1 of 2 notes'), findsOneWidget);
    });

    testWidgets('an empty band says what is missing rather than drawing '
        'zeroes', (tester) async {
      useScreen(tester, const Size(1400, 2400));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 1400,
                child: DashboardAnalytics(
                  stations: const [],
                  schedules: const [],
                  attendanceReports: const [],
                  isLoading: false,
                  today: today,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('No station has a per-shift'), findsOneWidget);
      expect(find.textContaining('No head guard has filed'), findsOneWidget);
      expect(find.textContaining('Nothing to report'), findsOneWidget);
      // Nothing to open, so nothing pretends to be openable.
      expect(find.text('Breakdown'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
