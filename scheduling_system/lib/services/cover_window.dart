// services/cover_window.dart
//
// When the door closes on covering an absence.
//
// A replacement is somebody sent to STAND a post. Once the post has timed
// out there is nothing left to stand: assigning then would rewrite a duty
// that is already history, send a "report for duty" alert about a shift
// that finished hours ago, and leave the schedule disagreeing with what
// actually happened on the ground. So Find Replacement closes at the
// post's time-out — which also takes care of every past date, since those
// posts timed out long ago.
//
// It closes at time-OUT, not time-in. A guard going absent mid-shift is
// exactly what this flow exists for, and the rest of the post is still
// worth manning.
//
// This is the Dart mirror of replacements.cover_window() /
// replacements.is_closed() in the backend. The two must agree, because
// the admin screens hide the button from here while POST
// /replacements/apply is the one that actually refuses.
//
// WHICH HOURS. Posts are staggered per station (see post_time.dart), so
// two guards on the same Morning shift can time out four hours apart —
// the shift NAME is never enough on its own. In order of trust:
//
//   1. endsAt straight from the backend (GET /replacements/suggest) —
//      read off the guard's own schedule entry, so it is exact.
//   2. A duty window already on screen, like an attendance record's
//      '0600H - 1400H' — the same entry's hours, just in display form.
//   3. The shift's base window, for a caller holding nothing but a name.
//   4. Nothing readable at all: the whole calendar day counts as the
//      duty. The permissive read, matching the backend, so an unknown
//      shift label can't block a cover that is still needed.
//
// The clock is ServerClock's, not the device's, for the same reason the
// duty statuses use it: a wound-back clock must not re-open a window.

import '../models/post_time.dart';
import 'server_clock.dart';

class CoverWindow {
  const CoverWindow._();

  /// 'Morning Shift' -> 'Morning'. Absence requests store the titled
  /// form, schedules and reports store the bare label.
  static String canonicalShift(String shiftTitle) {
    final t = shiftTitle.trim();
    if (t.toLowerCase().endsWith(' shift')) {
      return t.substring(0, t.length - ' shift'.length).trim();
    }
    return t;
  }

  /// The instant the post times out, or null when [dateIso] isn't a date.
  ///
  /// [range] is a duty window already on screen ('0600H - 1400H'), and
  /// wins over [shift]'s base hours. [endsAtIso] is the backend's own
  /// answer and wins over both.
  static DateTime? endsAt(
    String dateIso,
    String shift, {
    String? range,
    String? endsAtIso,
  }) {
    if (endsAtIso != null && endsAtIso.isNotEmpty) {
      final parsed = DateTime.tryParse(endsAtIso);
      if (parsed != null) return parsed;
    }

    final date = DateTime.tryParse(dateIso);
    if (date == null) return null;
    final day = DateTime(date.year, date.month, date.day);

    final window = _window(shift, range);
    // No hours on file — treat the whole calendar day as the duty.
    if (window == null) return day.add(const Duration(days: 1));

    // An overnight post (Night 2100H - 0500H) times out the NEXT day.
    final crossesMidnight = window.end <= window.start;
    return day
        .add(Duration(days: crossesMidnight ? 1 : 0))
        .add(Duration(minutes: window.end));
  }

  /// True once that post has timed out and a cover is no longer possible.
  static bool isClosed(
    String dateIso,
    String shift, {
    String? range,
    String? endsAtIso,
    DateTime? at,
  }) {
    final end = endsAt(dateIso, shift, range: range, endsAtIso: endsAtIso);
    return end != null && hasPassed(end, at: at);
  }

  /// True once [end] is behind the server clock. Compares instants, so a
  /// backend timestamp carrying +08:00 and a locally built time both work.
  static bool hasPassed(DateTime end, {DateTime? at}) =>
      !(at ?? ServerClock.now()).isBefore(end);

  /// True when NO post on [dateIso] can still be running, whatever hours
  /// it was given.
  ///
  /// For callers holding a date and nothing else. The station's ladder can
  /// start a post hours after its shift's base window (see post_time.dart)
  /// and an overnight post times out the next morning, so isClosed() on a
  /// bare shift name can shut the door on a duty still being manned. This
  /// is the reading that can't be wrong: past the end of the FOLLOWING
  /// day, no post from [dateIso] survives on any ladder.
  ///
  /// Being late is the safe direction here — the exact window still
  /// decides on the Find Replacement screen, which fetches it.
  static bool certainlyClosed(String dateIso, {DateTime? at}) {
    final date = DateTime.tryParse(dateIso);
    if (date == null) return false;
    final lastPossibleEnd =
        DateTime(date.year, date.month, date.day).add(const Duration(days: 2));
    return hasPassed(lastPossibleEnd, at: at);
  }

  /// 'timed out 1400H · Aug 9' — the muted line shown where the Find
  /// Replacement button used to be, so the admin can see WHY it's gone.
  static String closedLabel(DateTime end) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = end.isUtc ? end.toLocal() : end;
    return 'timed out ${formatMilitary(local.hour * 60 + local.minute)} · '
        '${months[local.month - 1]} ${local.day}';
  }

  /// The post's hours: the range on screen first, then the shift's base
  /// window. Null when neither can be read.
  static PostTime? _window(String shift, String? range) {
    final parsed = _parseRange(range);
    if (parsed != null) return parsed;
    return baseShiftWindow(canonicalShift(shift));
  }

  /// '0600H - 1400H' -> the window it names. Null on anything else,
  /// including the empty string older records carry.
  static PostTime? _parseRange(String? range) {
    if (range == null) return null;
    final parts = range.split('-');
    if (parts.length != 2) return null;
    final start = parseHhmm(parts[0].trim());
    final end = parseHhmm(parts[1].trim());
    if (start == null || end == null) return null;
    return PostTime(start: start, end: end);
  }
}
