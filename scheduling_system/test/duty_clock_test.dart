// Verifies the guard dashboard reads its duty status off the wall clock,
// not just off today's date — the bug where a 0500H - 1400H guard still
// showed "On Duty" at 8pm and could still file an emergency absence.
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/absence_request.dart';
import 'package:scheduling_system/models/guard_shift.dart';
import 'package:scheduling_system/services/duty_clock.dart';

GuardShift shiftOn(DateTime date, String shift, {String? coveringFor}) {
  return GuardShift(
    date: date,
    scheduleId: 'sched-1',
    stationId: 'st-1',
    stationName: 'Gate 1',
    shift: shift,
    coveringFor: coveringFor,
  );
}

GuardPeriod periodFrom(DateTime start, DateTime end) {
  return GuardPeriod(
    scheduleId: 'sched-1',
    stationId: 'st-1',
    stationName: 'Gate 1',
    startDate: start,
    endDate: end,
  );
}

AbsenceRequest requestOn(DateTime date, String status) {
  return AbsenceRequest(
    id: 'req-1',
    employeeId: 'emp-1',
    employeeName: 'Test Guard',
    employeeType: 'regular',
    station: 'Gate 1',
    shiftTitle: 'Morning Shift',
    date: DutyClock.iso(date),
    title: 'Sick',
    reason: 'Sick',
    body: 'Fever',
    status: status,
    submittedAt: date,
  );
}

void main() {
  // Aug 1 2026 is a Saturday; the period runs the whole bi-week.
  final aug1 = DateTime(2026, 8, 1);
  final aug2 = DateTime(2026, 8, 2);
  final period = periodFrom(DateTime(2026, 7, 27), DateTime(2026, 8, 9));

  group('Morning shift 0500H - 1400H', () {
    final shifts = [shiftOn(aug1, 'Morning')];

    LiveDutyState at(DateTime when) =>
        DutyClock.resolve(shifts: shifts, periods: [period], at: when);

    test('before time-in reads Awaiting', () {
      final state = at(DateTime(2026, 8, 1, 4, 30));
      expect(state.status, LiveDutyStatus.awaiting);
      expect(state.label, 'Awaiting');
      expect(state.progressNote, 'Time in in 30m');
    });

    test('at time-in reads On Duty', () {
      expect(at(DateTime(2026, 8, 1, 5, 0)).status, LiveDutyStatus.onDuty);
    });

    test('mid-shift reads On Duty with progress', () {
      final state = at(DateTime(2026, 8, 1, 9, 30));
      expect(state.status, LiveDutyStatus.onDuty);
      expect(state.progressNote, 'Time out in 4h 30m');
      expect(state.progress, closeTo(0.5, 0.01));
    });

    test('at time-out it is already over', () {
      expect(at(DateTime(2026, 8, 1, 14, 0)).status, LiveDutyStatus.offShift);
    });

    // The exact case reported: duty 0500H - 1400H, clock says 8pm.
    test('8pm reads Off Shift, not On Duty', () {
      final state = at(DateTime(2026, 8, 1, 20, 0));
      expect(state.status, LiveDutyStatus.offShift);
      expect(state.label, 'Off Shift');
      expect(state.progressNote, 'Timed out 6h ago');
    });
  });

  group('Night shift 2100H - 0600H carries past midnight', () {
    final shifts = [shiftOn(aug1, 'Night')];

    LiveDutyState at(DateTime when) =>
        DutyClock.resolve(shifts: shifts, periods: [period], at: when);

    test('2000H on the duty day reads Awaiting', () {
      expect(at(DateTime(2026, 8, 1, 20, 0)).status, LiveDutyStatus.awaiting);
    });

    test('2300H reads On Duty', () {
      expect(at(DateTime(2026, 8, 1, 23, 0)).status, LiveDutyStatus.onDuty);
    });

    // 0200H the NEXT calendar day — the guard is still on post.
    test('0200H the next day still reads On Duty', () {
      final state = at(DateTime(2026, 8, 2, 2, 0));
      expect(state.status, LiveDutyStatus.onDuty);
      expect(state.shift!.date, aug1);
      expect(state.progressNote, 'Time out in 4h');
    });

    test('0600H the next day reads Off Shift', () {
      expect(at(DateTime(2026, 8, 2, 6, 0)).status, LiveDutyStatus.offShift);
    });
  });

  group('HG Night 1700H - 0500H', () {
    final shifts = [shiftOn(aug1, 'HG Night')];

    test('0400H the next day is still On Duty', () {
      final state = DutyClock.resolve(
        shifts: shifts,
        periods: [period],
        at: DateTime(2026, 8, 2, 4, 0),
      );
      expect(state.status, LiveDutyStatus.onDuty);
    });
  });

  group('Days with no duty', () {
    test('inside a published period reads Day Off', () {
      final state = DutyClock.resolve(
        shifts: [shiftOn(aug2, 'Morning')],
        periods: [period],
        at: DateTime(2026, 8, 1, 12, 0),
      );
      expect(state.status, LiveDutyStatus.dayOff);
      expect(state.headline, 'Rest Day');
      expect(state.shift, isNull);
    });

    test('with no published period reads Unassigned', () {
      final state = DutyClock.resolve(
        shifts: const [],
        periods: const [],
        at: DateTime(2026, 8, 1, 12, 0),
      );
      expect(state.status, LiveDutyStatus.unassigned);
    });
  });

  group('Absence overrides the clock', () {
    final shifts = [shiftOn(aug1, 'Morning')];

    test('an approved request for the duty day reads Absent', () {
      final state = DutyClock.resolve(
        shifts: shifts,
        periods: [period],
        absenceRequests: [requestOn(aug1, 'approved')],
        at: DateTime(2026, 8, 1, 9, 0),
      );
      expect(state.status, LiveDutyStatus.absent);
      expect(state.label, 'Absent');
    });

    test('a pending request leaves the time-based status alone', () {
      final state = DutyClock.resolve(
        shifts: shifts,
        periods: [period],
        absenceRequests: [requestOn(aug1, 'pending')],
        at: DateTime(2026, 8, 1, 9, 0),
      );
      expect(state.status, LiveDutyStatus.onDuty);
    });

    test('a denied request leaves the time-based status alone', () {
      final state = DutyClock.resolve(
        shifts: shifts,
        periods: [period],
        absenceRequests: [requestOn(aug1, 'denied')],
        at: DateTime(2026, 8, 1, 9, 0),
      );
      expect(state.status, LiveDutyStatus.onDuty);
    });
  });

  // Filing closes one hour before time-in: a guard that close to their
  // post has to be counted on to report, and there is no time left to
  // find a replacement through the app.
  group('Emergency absence is gated on the 1-hour cut-off', () {
    final shifts = [shiftOn(aug1, 'Morning'), shiftOn(aug2, 'Afternoon')];

    test('more than an hour before time-in both duties are fileable', () {
      final dates = DutyClock.fileableDates(
        shifts: shifts,
        at: DateTime(2026, 8, 1, 3, 0),
      );
      expect(dates, [aug1, aug2]);
    });

    // The reported case: a 1400H duty can't be called in absent at 1300H.
    test('at exactly one hour before time-in the duty drops out', () {
      final dates = DutyClock.fileableDates(
        shifts: [shiftOn(aug2, 'Afternoon')],
        at: DateTime(2026, 8, 2, 13, 0),
      );
      expect(dates, isEmpty);
    });

    test('a minute before the cut-off it is still fileable', () {
      final dates = DutyClock.fileableDates(
        shifts: [shiftOn(aug2, 'Afternoon')],
        at: DateTime(2026, 8, 2, 12, 59),
      );
      expect(dates, [aug2]);
    });

    test('inside the last hour today drops out, tomorrow stays', () {
      final dates = DutyClock.fileableDates(
        shifts: shifts,
        at: DateTime(2026, 8, 1, 4, 30),
      );
      expect(dates, isNot(contains(aug1)));
      expect(dates, [aug2]);
    });

    test('a duty already running can no longer be filed against', () {
      final dates = DutyClock.fileableDates(
        shifts: shifts,
        at: DateTime(2026, 8, 1, 9, 0),
      );
      expect(dates, isNot(contains(aug1)));
    });

    // The original report: at 8pm the morning duty is long done.
    test('after time-out today drops out, tomorrow stays', () {
      final dates = DutyClock.fileableDates(
        shifts: shifts,
        at: DateTime(2026, 8, 1, 20, 0),
      );
      expect(dates, isNot(contains(aug1)));
      expect(dates, [aug2]);
    });

    test('a day already requested is never offered again', () {
      final dates = DutyClock.fileableDates(
        shifts: shifts,
        existingRequests: [requestOn(aug2, 'pending')],
        at: DateTime(2026, 8, 1, 3, 0),
      );
      expect(dates, [aug1]);
    });

    test('nothing is fileable once every duty has ended', () {
      final dates = DutyClock.fileableDates(
        shifts: [shiftOn(aug1, 'Morning')],
        at: DateTime(2026, 8, 1, 20, 0),
      );
      expect(dates, isEmpty);
    });

    test('an in-progress night shift is past its cut-off after midnight', () {
      final dates = DutyClock.fileableDates(
        shifts: [shiftOn(aug1, 'Night')],
        at: DateTime(2026, 8, 2, 2, 0),
      );
      expect(dates, isEmpty);
    });

    test('a night shift is fileable up to 2000H on the duty day', () {
      final shifts = [shiftOn(aug1, 'Night')];
      expect(
        DutyClock.fileableDates(shifts: shifts, at: DateTime(2026, 8, 1, 19, 59)),
        [aug1],
      );
      expect(
        DutyClock.fileableDates(shifts: shifts, at: DateTime(2026, 8, 1, 20, 0)),
        isEmpty,
      );
    });
  });

  group('The dashboard card reads the cut-off off the live state', () {
    final period2 = periodFrom(DateTime(2026, 7, 27), DateTime(2026, 8, 9));

    LiveDutyState at(DateTime when) => DutyClock.resolve(
          shifts: [shiftOn(aug1, 'Afternoon')],
          periods: [period2],
          at: when,
        );

    test('awaiting, outside the last hour, is not past the cut-off', () {
      final state = at(DateTime(2026, 8, 1, 12, 0));
      expect(state.status, LiveDutyStatus.awaiting);
      expect(state.isPastAbsenceCutoff, isFalse);
    });

    test('awaiting, inside the last hour, is past the cut-off', () {
      final state = at(DateTime(2026, 8, 1, 13, 30));
      expect(state.status, LiveDutyStatus.awaiting);
      expect(state.isPastAbsenceCutoff, isTrue);
    });

    test('on duty is past the cut-off', () {
      expect(at(DateTime(2026, 8, 1, 16, 0)).isPastAbsenceCutoff, isTrue);
    });

    test('the deadline is one hour before time-in', () {
      final deadline = DutyClock.absenceDeadline(shiftOn(aug1, 'Afternoon'));
      expect(deadline, DateTime(2026, 8, 1, 13, 0));
      expect(DutyClock.military(deadline!), '1300H');
    });
  });

  // The roster date the Head Guard Report screen files against. A night
  // head guard on post at 0200H is still working YESTERDAY's shift, so
  // that is the roster they see and report on — not the new calendar
  // day's, which they haven't started yet.
  group('activeDutyDate', () {
    test('is today when nothing overnight is running', () {
      final shifts = [shiftOn(aug1, 'HG Night')];
      expect(
        DutyClock.activeDutyDate(
            shifts: shifts, at: DateTime(2026, 8, 1, 14, 0)),
        aug1,
      );
    });

    test('rolls back to yesterday inside an HG Night after midnight', () {
      final shifts = [shiftOn(aug1, 'HG Night')]; // 1700H Aug 1 - 0500H Aug 2
      expect(
        DutyClock.activeDutyDate(
            shifts: shifts, at: DateTime(2026, 8, 2, 2, 0)),
        aug1,
      );
    });

    test('rolls back for a plain Night shift too', () {
      final shifts = [shiftOn(aug1, 'Night')]; // 2100H Aug 1 - 0600H Aug 2
      expect(
        DutyClock.activeDutyDate(
            shifts: shifts, at: DateTime(2026, 8, 2, 3, 30)),
        aug1,
      );
    });

    test('returns to today once the overnight duty times out at 0500H', () {
      final shifts = [shiftOn(aug1, 'HG Night')];
      expect(
        DutyClock.activeDutyDate(
            shifts: shifts, at: DateTime(2026, 8, 2, 5, 0)),
        aug2,
      );
    });

    // The reason this isn't LiveDutyState.relevantDutyDate: that one
    // keeps pointing at a FINISHED overnight duty, which would strand a
    // head guard on yesterday's roster for the whole of their rest day.
    test('does not roll back later in the day after an overnight duty', () {
      final shifts = [shiftOn(aug1, 'HG Night')];
      expect(
        DutyClock.activeDutyDate(
            shifts: shifts, at: DateTime(2026, 8, 2, 15, 0)),
        aug2,
      );
    });

    test('a day duty never rolls the date back', () {
      final shifts = [shiftOn(aug1, 'HG Day')]; // 0500H - 1700H, same day
      expect(
        DutyClock.activeDutyDate(
            shifts: shifts, at: DateTime(2026, 8, 2, 2, 0)),
        aug2,
      );
    });

    test('no shifts at all is today', () {
      expect(
        DutyClock.activeDutyDate(
            shifts: const [], at: DateTime(2026, 8, 2, 2, 0)),
        aug2,
      );
    });
  });

  group('Clock formatting', () {
    test('military time matches the schedule format', () {
      expect(DutyClock.military(DateTime(2026, 8, 1, 20, 42)), '2042H');
      expect(DutyClock.military(DateTime(2026, 8, 1, 5, 0)), '0500H');
    });

    test('12-hour clock', () {
      expect(DutyClock.clock12(DateTime(2026, 8, 1, 20, 42, 7)), '8:42:07 PM');
      expect(DutyClock.clock12(DateTime(2026, 8, 1, 0, 5, 0)), '12:05:00 AM');
    });
  });
}
