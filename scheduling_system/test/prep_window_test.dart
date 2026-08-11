// test/prep_window_test.dart
//
// The preparation window — the hour a replacement gets before they stand
// the post.
//
// These are the same cases backend_python/testing_prep_window.py pins
// down, asked of the Dart mirror. The two have to agree: the backend
// computes the hours at the instant the admin confirms, and this side is
// what Find Replacement shows them BEFORE they confirm. A screen that
// promised 1000H - 1900H and produced something else would be worse than
// one that promised nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/guard_shift.dart';
import 'package:scheduling_system/models/post_time.dart';
import 'package:scheduling_system/services/prep_window.dart';

const _date = '2026-08-09';

// The head guard's fixed 12-hour duty, the window the whole feature was
// specified against.
const _hgDay = PostTime(start: 5 * 60, end: 17 * 60); // 0500H - 1700H

DateTime _at(int day, int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 8, day, hour, minute, second);

PrepAdjustment? _adjust(PostTime? window, DateTime at, {String date = _date}) =>
    PrepWindow.adjust(date, window, at: at);

void main() {
  group('an 0500H - 1700H post', () {
    test('covered at 0900H is stood 1000H - 1900H', () {
      final prep = _adjust(_hgDay, _at(9, 9))!;
      expect(prep.adjusted, isTrue);
      expect(prep.range, '1000H - 1900H');
      expect(prep.originalRange, '0500H - 1700H');
      expect(prep.reportBy, '1000H');
      expect(prep.startsAt, _at(9, 10));
    });

    test('keeps its own hours when the cover has time to prepare', () {
      // Two days out, and early enough on the day itself.
      expect(_adjust(_hgDay, _at(7, 12))!.adjusted, isFalse);
      expect(_adjust(_hgDay, _at(9, 3))!.adjusted, isFalse);
      expect(_adjust(_hgDay, _at(9, 3))!.range, '0500H - 1700H');
    });

    test('is not moved by a cover assigned exactly an hour before', () {
      expect(_adjust(_hgDay, _at(9, 4))!.adjusted, isFalse);
    });

    test('is moved by a cover assigned a minute inside that hour', () {
      final prep = _adjust(_hgDay, _at(9, 4, 1))!;
      expect(prep.adjusted, isTrue);
      expect(prep.range, '0501H - 1900H');
    });
  });

  group('the hour is exact', () {
    test('0917H times in at 1017H, not a tidier number', () {
      expect(_adjust(_hgDay, _at(9, 9, 17))!.range, '1017H - 1900H');
    });

    test('seconds round the time-in up, so the hour is never shaved', () {
      expect(_adjust(_hgDay, _at(9, 9, 17, 30))!.reportBy, '1018H');
    });

    test('the notice is phrased from the constant it enforces', () {
      expect(_adjust(_hgDay, _at(9, 9))!.noticeLabel, '1 hour');
    });
  });

  group('other posts', () {
    test('a regular 0500H - 1400H post covered at 0900H stands '
        '1000H - 1600H', () {
      final prep = _adjust(
          const PostTime(start: 5 * 60, end: 14 * 60), _at(9, 9))!;
      expect(prep.range, '1000H - 1600H');
    });

    test('an overnight post covered in the evening stays on its own date',
        () {
      // HG Night 1700H - 0500H, covered at 2000H.
      final prep = _adjust(
          const PostTime(start: 17 * 60, end: 5 * 60), _at(9, 20))!;
      expect(prep.range, '2100H - 0700H');
      expect(prep.dayOffset, 0);
    });

    test('an overnight post covered after midnight times in the NEXT day',
        () {
      // The case a bare "HH:MM" pair cannot express on its own: the duty
      // date is Aug 9, but this cover times in on Aug 10.
      final prep = _adjust(
          const PostTime(start: 17 * 60, end: 5 * 60), _at(10, 2, 30))!;
      expect(prep.range, '0330H - 0700H');
      expect(prep.dayOffset, 1);
      expect(prep.startsAt, _at(10, 3, 30));
    });

    test('there is always a duty left to stand', () {
      // Assigned a minute before an 0500H - 1400H post times out.
      final prep = _adjust(
          const PostTime(start: 5 * 60, end: 14 * 60), _at(9, 13, 59))!;
      expect(prep.range, '1459H - 1600H');
      expect(prep.endsAt.difference(prep.startsAt).inMinutes,
          greaterThan(60));
    });
  });

  group('nothing to reason about', () {
    test('no window on file', () {
      expect(_adjust(null, _at(9, 9)), isNull);
    });

    test('an unreadable date', () {
      expect(_adjust(_hgDay, _at(9, 9), date: 'not-a-date'), isNull);
    });
  });

  group('a re-timed duty on the guard\'s own dashboard', () {
    GuardShift shift({
      required String timeIn,
      required String timeOut,
      String? originalTimeIn,
      String? originalTimeOut,
      int dayOffset = 0,
      int day = 9,
    }) =>
        GuardShift(
          date: DateTime(2026, 8, day),
          scheduleId: 'SCHED-1',
          stationId: 'STA001',
          stationName: 'Monumento',
          shift: 'HG Day',
          timeInRaw: timeIn,
          timeOutRaw: timeOut,
          originalTimeInRaw: originalTimeIn,
          originalTimeOutRaw: originalTimeOut,
          dayOffset: dayOffset,
          coveringFor: 'AQU861',
        );

    test('reads its own hours, and remembers the post\'s', () {
      final s = shift(
          timeIn: '10:00',
          timeOut: '19:00',
          originalTimeIn: '05:00',
          originalTimeOut: '17:00');
      expect(s.timeRange, '1000H - 1900H');
      expect(s.isPrepAdjusted, isTrue);
      expect(s.originalWindow!.range, '0500H - 1700H');
      expect(s.startsAt, DateTime(2026, 8, 9, 10));
      expect(s.endsAt, DateTime(2026, 8, 9, 19));
    });

    test('an ordinary duty carries no adjustment at all', () {
      final s = shift(timeIn: '05:00', timeOut: '14:00');
      expect(s.isPrepAdjusted, isFalse);
      expect(s.originalWindow, isNull);
    });

    // The reason dayOffset exists: without it these hours land 24 hours
    // early, on the duty date rather than the morning after it.
    test('a dayOffset puts the duty on the day it is actually stood', () {
      final s = shift(
          timeIn: '03:30',
          timeOut: '07:00',
          originalTimeIn: '17:00',
          originalTimeOut: '05:00',
          dayOffset: 1);
      expect(s.startsAt, DateTime(2026, 8, 10, 3, 30));
      expect(s.endsAt, DateTime(2026, 8, 10, 7));
      expect(s.isActiveAt(DateTime(2026, 8, 10, 4)), isTrue);
      expect(s.isActiveAt(DateTime(2026, 8, 9, 4)), isFalse);
      // It runs past the end of its own duty date, which is what the
      // dashboards ask when they decide whether yesterday's roster can
      // still be touching now.
      expect(s.crossesMidnight, isTrue);
    });

    test('an overnight duty still crosses midnight the ordinary way', () {
      final s = shift(timeIn: '21:00', timeOut: '06:00');
      expect(s.crossesMidnight, isTrue);
      expect(s.startsAt, DateTime(2026, 8, 9, 21));
      expect(s.endsAt, DateTime(2026, 8, 10, 6));
    });

    test('a day duty does not', () {
      expect(shift(timeIn: '05:00', timeOut: '14:00').crossesMidnight,
          isFalse);
    });
  });
}
