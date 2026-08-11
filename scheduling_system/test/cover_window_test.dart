// Verifies Find Replacement closes when the post it would cover has
// timed out — the bug where a notification filed on Aug 9 still offered
// "Find Replacement" on Aug 11, letting the admin assign a guard to a
// shift that finished two days earlier.
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/services/cover_window.dart';

void main() {
  // 2026-08-11, 10:00 — mid-morning, so the same day's Morning post is
  // still running and Aug 9's is long gone.
  final now = DateTime(2026, 8, 11, 10, 0);

  group('shift labels', () {
    test('the titled form guards file is reduced to the post label', () {
      expect(CoverWindow.canonicalShift('Morning Shift'), 'Morning');
      expect(CoverWindow.canonicalShift('HG Night Shift'), 'HG Night');
      expect(CoverWindow.canonicalShift('Night'), 'Night');
    });
  });

  group('a past date', () {
    test('is closed however the shift is named', () {
      for (final shift in ['Morning', 'Afternoon', 'Night', 'HG Day',
        'HG Night']) {
        expect(CoverWindow.isClosed('2026-08-09', shift, at: now), isTrue,
            reason: '$shift on Aug 9 is over by Aug 11');
      }
    });

    test('is closed even when the shift label means nothing', () {
      // No hours on file: the whole calendar day stands in as the duty,
      // so a past date is still past.
      expect(CoverWindow.isClosed('2026-08-09', 'Split', at: now), isTrue);
    });
  });

  group('today', () {
    test('a running Morning post is still coverable', () {
      // 0500H - 1400H, and it is 10:00.
      expect(CoverWindow.isClosed('2026-08-11', 'Morning', at: now), isFalse);
    });

    test('a Morning post that has timed out is not', () {
      expect(
        CoverWindow.isClosed('2026-08-11', 'Morning',
            at: DateTime(2026, 8, 11, 14, 0)),
        isTrue,
      );
    });

    test('the window shuts exactly at time-out, not a minute before', () {
      expect(
        CoverWindow.isClosed('2026-08-11', 'Morning',
            at: DateTime(2026, 8, 11, 13, 59)),
        isFalse,
      );
    });

    test('an Afternoon post not yet started is coverable', () {
      expect(CoverWindow.isClosed('2026-08-11', 'Afternoon', at: now), isFalse);
    });

    test('a duty with no hours on file lasts the whole calendar day', () {
      expect(CoverWindow.isClosed('2026-08-11', 'Split', at: now), isFalse);
      expect(
        CoverWindow.isClosed('2026-08-11', 'Split',
            at: DateTime(2026, 8, 11, 23, 59)),
        isFalse,
      );
    });
  });

  group('overnight posts', () {
    test('last night\'s Night post is still running at 0200H', () {
      // Night is 2100H - 0600H, so Aug 10's post times out Aug 11 0600H.
      expect(
        CoverWindow.isClosed('2026-08-10', 'Night',
            at: DateTime(2026, 8, 11, 2, 0)),
        isFalse,
      );
    });

    test('and is closed once it times out the next morning', () {
      expect(
        CoverWindow.isClosed('2026-08-10', 'Night',
            at: DateTime(2026, 8, 11, 6, 0)),
        isTrue,
      );
    });

    test('HG Night runs 1700H - 0500H across the same boundary', () {
      expect(
        CoverWindow.isClosed('2026-08-10', 'HG Night',
            at: DateTime(2026, 8, 11, 4, 59)),
        isFalse,
      );
      expect(
        CoverWindow.isClosed('2026-08-10', 'HG Night',
            at: DateTime(2026, 8, 11, 5, 0)),
        isTrue,
      );
    });
  });

  group('staggered posts', () {
    // Posts on one shift start up to hours apart, so the shift's base
    // hours are the wrong answer whenever the real window is known.
    test('a late Morning post outlives the shift\'s base hours', () {
      final at = DateTime(2026, 8, 11, 15, 0); // past the 1400H base
      expect(CoverWindow.isClosed('2026-08-11', 'Morning', at: at), isTrue);
      expect(
        CoverWindow.isClosed('2026-08-11', 'Morning',
            range: '0900H - 1800H', at: at),
        isFalse,
        reason: 'this post is manned until 1800H',
      );
    });

    test('an unreadable range falls back to the shift\'s base hours', () {
      expect(
        CoverWindow.isClosed('2026-08-11', 'Morning',
            range: '', at: DateTime(2026, 8, 11, 15, 0)),
        isTrue,
      );
    });
  });

  group('the backend\'s answer', () {
    test('wins over anything derived locally', () {
      // The server read this post's window off the schedule entry: it
      // runs to 1800H even though the shift's base hours say 1400H.
      expect(
        CoverWindow.isClosed('2026-08-11', 'Morning',
            endsAtIso: '2026-08-11T18:00:00+08:00',
            at: DateTime(2026, 8, 11, 15, 0)),
        isFalse,
      );
    });

    test('is compared as an instant, offset and all', () {
      // 1400H+08:00 is 06:00 UTC — the comparison must not read the
      // wall-clock digits and conclude the post runs until this evening.
      expect(
        CoverWindow.isClosed('2026-08-11', 'Morning',
            endsAtIso: '2026-08-11T14:00:00+08:00',
            at: DateTime.utc(2026, 8, 11, 6, 30)),
        isTrue,
      );
    });

    test('an unparseable one falls back rather than opening the window', () {
      expect(
        CoverWindow.isClosed('2026-08-09', 'Morning',
            endsAtIso: 'not-a-date', at: now),
        isTrue,
      );
    });
  });

  group('certainlyClosed — the reading that can\'t be wrong', () {
    // For the absence-request inbox, which holds a shift NAME and no post
    // window: being early here would push the admin to approve without a
    // cover while one was still assignable.
    test('Aug 9 is certainly over by Aug 11 — the case the admin hit', () {
      expect(CoverWindow.certainlyClosed('2026-08-09', at: now), isTrue);
    });

    test('today is never certainly over', () {
      expect(
        CoverWindow.certainlyClosed('2026-08-11',
            at: DateTime(2026, 8, 11, 23, 59)),
        isFalse,
      );
    });

    test('yesterday is not either — an overnight post may still be on', () {
      expect(
        CoverWindow.certainlyClosed('2026-08-10',
            at: DateTime(2026, 8, 11, 2, 0)),
        isFalse,
      );
    });

    test('it holds off until the whole of the following day has gone', () {
      expect(
        CoverWindow.certainlyClosed('2026-08-09',
            at: DateTime(2026, 8, 10, 23, 59)),
        isFalse,
        reason: 'a post staggered late on the 9th could still be running',
      );
      expect(
        CoverWindow.certainlyClosed('2026-08-09',
            at: DateTime(2026, 8, 11, 0, 0)),
        isTrue,
      );
    });

    test('it never fires on a date it cannot read', () {
      expect(CoverWindow.certainlyClosed('', at: now), isFalse);
    });

    test('it is later than the exact window, never earlier', () {
      // A staggered post the base hours would call finished at 1400H.
      final at = DateTime(2026, 8, 11, 15, 0);
      expect(CoverWindow.isClosed('2026-08-11', 'Morning', at: at), isTrue);
      expect(CoverWindow.certainlyClosed('2026-08-11', at: at), isFalse);
    });
  });

  test('an unreadable date closes nothing', () {
    // Nothing to compare against — refusing on a date we can't read would
    // hide the button on a live absence.
    expect(CoverWindow.isClosed('', 'Morning', at: now), isFalse);
    expect(CoverWindow.endsAt('', 'Morning'), isNull);
  });

  test('the closed label names the time-out the admin is looking at', () {
    final end = CoverWindow.endsAt('2026-08-09', 'Morning');
    expect(end, DateTime(2026, 8, 9, 14, 0));
    expect(CoverWindow.closedLabel(end!), 'timed out 1400H · Aug 9');
  });
}
