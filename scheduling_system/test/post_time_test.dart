// Covers the per-post stagger ladder: the rule that regular posts are
// handed out in PAIRS — two on the shift's base window, the next two two
// hours later, and so on — plus the fact that a guard's own duty window
// now rides on their schedule entry rather than being looked up from the
// shift name.
//
// The ladder is implemented twice on purpose — here and in
// backend_python/station_posts.py — because Edit Station computes it live
// while the API re-derives it on save. These cases are the contract
// between the two; change one side and this file should fail.
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/guard_shift.dart';
import 'package:scheduling_system/models/post_time.dart';
import 'package:scheduling_system/models/schedule.dart';
import 'package:scheduling_system/models/station.dart';
import 'package:scheduling_system/services/duty_clock.dart';

/// The ladder's output for one shift, as readable ranges.
List<String> ranges(String shift, List<String> posts) =>
    normalizePostTimes(shift, posts).map((t) => t.range).toList();

void main() {
  group('Stagger ladder', () {
    test('morning: posts pair up, and each pair starts 2h after the last',
        () {
      expect(
        ranges('morning', [
          kHeadGuardPost,
          'SW Platform',
          'SE Platform',
          'Roving',
          'Ladder',
          'Concourse',
          'Gate',
        ]),
        [
          '0500H - 1700H', // head guard's fixed 12-hour duty
          '0500H - 1400H',
          '0500H - 1400H',
          '0700H - 1600H',
          '0700H - 1600H',
          '0900H - 1800H',
          '0900H - 1800H',
        ],
      );
    });

    test('an odd post opens the next rung on its own', () {
      // Five regulars: two pairs, then the fifth starts the third rung
      // and waits there for a sixth post to join it.
      expect(
        ranges('morning', [kHeadGuardPost, 'A', 'B', 'C', 'D', 'E']).last,
        '0900H - 1800H',
      );
    });

    test('afternoon staggers the same way from 1400H', () {
      expect(
        ranges('afternoon', ['SW Platform', 'SE Platform', 'Roving', 'Ladder']),
        [
          '1400H - 2300H',
          '1400H - 2300H',
          '1600H - 0100H',
          '1600H - 0100H',
        ],
      );
    });

    test('night does not stagger — head guard plus roving on the base', () {
      expect(
        ranges('night', [kHeadGuardPost, 'Roving', 'Roving', 'Roving']),
        [
          '1700H - 0500H', // HG Night's fixed 12-hour duty
          '2100H - 0600H',
          '2100H - 0600H',
          '2100H - 0600H',
        ],
      );
    });

    test('the head guard slot does not consume a ladder step', () {
      // Without the head guard the first two posts still share the base.
      final withHg = ranges('morning', [kHeadGuardPost, 'A', 'B', 'C']);
      expect(withHg.sublist(1), ['0500H - 1400H', '0500H - 1400H', '0700H - 1600H']);
    });

    test('duty length is preserved as the start slides', () {
      final windows = normalizePostTimes(
          'morning', [kHeadGuardPost, 'A', 'B', 'C', 'D']);
      // Every regular post is the standard duty, head guard is 12 hours.
      expect(windows.first.lengthMinutes, 12 * 60);
      for (final w in windows.sublist(1)) {
        expect(w.lengthMinutes, kStandardDutyMinutes);
        expect(w.isShortDuty, isFalse);
        expect(w.isLongDuty, isFalse);
      }
      // The head guard's 12 hours reads as long — Edit Station keeps it
      // out of the 9-hour rule for exactly that reason.
      expect(windows.first.isLongDuty, isTrue);
    });

    test('an unnamed slot is still timed, so its guard has hours', () {
      expect(ranges('morning', [kHeadGuardPost, 'A', 'B', '', '']),
          contains('0700H - 1600H'));
    });
  });

  group('Manual override', () {
    test('a pinned window survives, and the ladder flows around it', () {
      final posts = [kHeadGuardPost, 'A', 'B', 'C', 'D'];
      final stored = <PostTime?>[
        null,
        null,
        null,
        const PostTime(start: 8 * 60 + 30, end: 17 * 60 + 30, auto: false),
        null,
      ];
      final result = normalizePostTimes('morning', posts, stored);

      expect(result[3].range, '0830H - 1730H');
      expect(result[3].auto, isFalse);
      // The slot after it keeps its own ladder position rather than
      // chaining off the pinned one — regular index 3 is the second half
      // of the 0700H rung.
      expect(result[4].range, '0700H - 1600H');
    });

    test('the head guard slot cannot be pinned away from its 12-hour duty',
        () {
      final result = normalizePostTimes(
        'morning',
        [kHeadGuardPost, 'A'],
        <PostTime?>[
          const PostTime(start: 9 * 60, end: 10 * 60, auto: false),
          null,
        ],
      );
      expect(result.first.range, '0500H - 1700H');
      expect(result.first.auto, isTrue);
    });
  });

  group('Overrun', () {
    test('flags a morning post that starts after the afternoon has come on',
        () {
      // 12 morning slots: head guard + 11 regulars. Paired onto rungs
      // that climb every second post, the 11th regular reaches 1500H.
      final posts = [
        kHeadGuardPost,
        'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K',
      ];
      final windows = normalizePostTimes('morning', posts);
      expect(windows.last.range, '1500H - 0000H');
      expect(overrunsNextShift('morning', windows.last.start), isTrue);
      // The one before it, at 1300H, is still inside the morning.
      expect(windows[10].range, '1300H - 2200H');
      expect(overrunsNextShift('morning', windows[10].start), isFalse);
    });

    test('night has no following shift, so it never overruns', () {
      expect(overrunsNextShift('night', 21 * 60), isFalse);
    });
  });

  group('Station round-trip', () {
    test('a station with no stored times still reads the ladder', () {
      final station = Station.fromJson({
        'id': 'STA001',
        'name': 'Monumento',
        'requiredEmployees': 9,
        'requiredMorning': 4,
        'posts': {
          'morning': [kHeadGuardPost, 'SW Platform', 'SE Platform', 'Roving'],
        },
      });
      expect(
        station.postTimesFor('morning').map((t) => t.range).toList(),
        ['0500H - 1700H', '0500H - 1400H', '0500H - 1400H', '0700H - 1600H'],
      );
    });

    test('stored windows survive a JSON round-trip', () {
      final station = Station.fromJson({
        'id': 'STA001',
        'name': 'Monumento',
        'requiredEmployees': 3,
        'requiredMorning': 3,
        'posts': {
          'morning': [kHeadGuardPost, 'A', 'B'],
        },
        'postTimes': {
          'morning': [
            {'start': '05:00', 'end': '17:00', 'auto': true},
            {'start': '05:00', 'end': '14:00', 'auto': true},
            {'start': '10:15', 'end': '19:15', 'auto': false},
          ],
        },
      });
      expect(station.morningPostTimes[2].range, '1015H - 1915H');
      expect(station.morningPostTimes[2].auto, isFalse);

      final again = Station.fromJson(station.toJson());
      expect(again.morningPostTimes[2].range, '1015H - 1915H');
      expect(again.morningPostTimes[2].auto, isFalse);
    });
  });

  group('The entry\'s own window beats the shift name', () {
    test('ScheduleEntry prefers its stamped times', () {
      final entry = ScheduleEntry(
        id: 'e1',
        employeeId: 'emp-1',
        employeeName: 'Guard',
        shift: 'Morning',
        post: 'Roving',
        timeIn: '07:00',
        timeOut: '16:00',
      );
      expect(entry.timeRange, '0700H - 1600H');
      expect(entry.duration, '9 hrs');
    });

    test('ScheduleEntry falls back to the shift base when untimed', () {
      final entry = ScheduleEntry(
        id: 'e1',
        employeeId: 'emp-1',
        employeeName: 'Guard',
        shift: 'Morning',
        post: 'Roving',
      );
      expect(entry.timeRange, '0500H - 1400H');
    });

    test('GuardShift puts a staggered duty on the clock', () {
      final shift = GuardShift(
        date: DateTime(2026, 8, 1),
        scheduleId: 's1',
        stationId: 'st1',
        stationName: 'Monumento',
        shift: 'Morning',
        timeInRaw: '09:00',
        timeOutRaw: '18:00',
      );
      expect(shift.timeRange, '0900H - 1800H');
      // 0800H is BEFORE this guard's time-in even though the Morning
      // shift itself started at 0500H — the whole point of the change.
      expect(shift.startsAfter(DateTime(2026, 8, 1, 8, 0)), isTrue);
      expect(shift.isActiveAt(DateTime(2026, 8, 1, 8, 0)), isFalse);
      expect(shift.isActiveAt(DateTime(2026, 8, 1, 17, 0)), isTrue);
      expect(shift.hasEndedBy(DateTime(2026, 8, 1, 18, 0)), isTrue);
    });

    test('a staggered afternoon post crossing midnight is handled', () {
      final shift = GuardShift(
        date: DateTime(2026, 8, 1),
        scheduleId: 's1',
        stationId: 'st1',
        stationName: 'Monumento',
        shift: 'Afternoon',
        timeInRaw: '18:00',
        timeOutRaw: '03:00',
      );
      expect(shift.crossesMidnight, isTrue);
      expect(shift.endsAt, DateTime(2026, 8, 2, 3, 0));
      expect(shift.isActiveAt(DateTime(2026, 8, 2, 1, 0)), isTrue);
    });

    test('DutyClock reads a staggered duty off the wall clock', () {
      final shifts = [
        GuardShift(
          date: DateTime(2026, 8, 1),
          scheduleId: 's1',
          stationId: 'st1',
          stationName: 'Monumento',
          shift: 'Morning',
          timeInRaw: '09:00',
          timeOutRaw: '18:00',
        ),
      ];
      final periods = [
        GuardPeriod(
          scheduleId: 's1',
          stationId: 'st1',
          stationName: 'Monumento',
          startDate: DateTime(2026, 7, 27),
          endDate: DateTime(2026, 8, 9),
        ),
      ];

      LiveDutyStatus at(DateTime when) =>
          DutyClock.resolve(shifts: shifts, periods: periods, at: when).status;

      // 0600H: the Morning shift has begun, but not this guard's post.
      expect(at(DateTime(2026, 8, 1, 6, 0)), LiveDutyStatus.awaiting);
      expect(at(DateTime(2026, 8, 1, 12, 0)), LiveDutyStatus.onDuty);
      // 1500H: a 0500H guard would be done; this one is still on post.
      expect(at(DateTime(2026, 8, 1, 15, 0)), LiveDutyStatus.onDuty);
      expect(at(DateTime(2026, 8, 1, 19, 0)), LiveDutyStatus.offShift);
    });
  });
}
