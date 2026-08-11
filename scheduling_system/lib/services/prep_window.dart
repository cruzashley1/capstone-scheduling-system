// services/prep_window.dart
//
// The preparation window — the hour a replacement gets before they stand
// the post.
//
// Assigning a cover used to hand the absent guard's duty over unchanged:
// a 0500H - 1700H post stayed 0500H - 1700H, so a guard told at 0900H
// that they were covering it was, on paper, already four hours late for
// a duty they had not heard about. Nobody walks out of their house
// straight onto a post — there is a uniform to put on, food to bring,
// and a commute to make.
//
// So a cover assigned once the post is already running gets its own
// hours:
//
//   time-in    one hour from the moment the admin assigns it, which is
//              the moment the guard is told. That hour is theirs to get
//              ready and travel in, and they are expected to be AT the
//              station when it runs out.
//
//   time-out   the post's own time-out plus two hours — the hour of prep
//              the duty lost at the front, plus one hour of extension.
//
//       0500H - 1700H, assigned at 0900H  ->  1000H - 1900H
//
// A cover assigned with time to spare is left alone. The rule is
// `max(the post's own time-in, an hour from now)`, so an absence
// approved two days out, or covered at 0300H for an 0500H post, keeps
// the post's real hours — that guard already has their hour.
//
// This is the Dart mirror of backend_python/prep_window.py, and the
// backend is the one that decides: it computes these hours at the
// instant the admin confirms, and writes them onto the schedule entry.
// This side exists so Find Replacement can show the admin what they are
// about to commit to BEFORE they commit to it. The two must agree.
//
// The clock is ServerClock's, not the device's, for the same reason the
// duty statuses use it — a wound-back phone must not buy anyone an
// extra hour of preparation.

import '../models/post_time.dart';
import 'server_clock.dart';

class PrepWindow {
  const PrepWindow._();

  /// The hour handed to the guard: uniform, food, and the commute.
  static const Duration prep = Duration(hours: 1);

  /// The extension on the far end, on top of the hour the duty lost at
  /// the front. Together these are the two hours the time-out moves by.
  static const Duration extension = Duration(hours: 1);

  /// The hours a replacement assigned at [at] would actually stand.
  ///
  /// [dateIso] is the duty date and [window] the post's own hours — from
  /// the backend's cover window where the screen has it, and the shift's
  /// base hours where it doesn't. Null when neither is readable, which
  /// callers treat as "no preview to show" rather than guessing.
  static PrepAdjustment? adjust(
    String dateIso,
    PostTime? window, {
    DateTime? at,
  }) {
    if (window == null) return null;
    final date = DateTime.tryParse(dateIso);
    if (date == null) return null;

    final startsAt = DateTime(date.year, date.month, date.day)
        .add(Duration(minutes: window.start));
    final endsAt = startsAt.add(Duration(minutes: window.lengthMinutes));

    // Never less than a full hour: the stored window has no seconds, so
    // an 0917:30 assignment rounds its time-in UP to 1018H rather than
    // quietly shaving half a minute off the guard's hour.
    final now = at ?? ServerClock.now();
    var reportAt = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(prep);
    if (now.second > 0 || now.millisecond > 0 || now.microsecond > 0) {
      reportAt = reportAt.add(const Duration(minutes: 1));
    }

    if (!reportAt.isAfter(startsAt)) {
      return PrepAdjustment(
        adjusted: false,
        window: window,
        original: window,
        dayOffset: 0,
        startsAt: startsAt,
        endsAt: endsAt,
      );
    }

    final newEnd = endsAt.add(prep + extension);
    return PrepAdjustment(
      adjusted: true,
      window: PostTime(
        start: reportAt.hour * 60 + reportAt.minute,
        end: newEnd.hour * 60 + newEnd.minute,
      ),
      original: window,
      dayOffset:
          DateTime(reportAt.year, reportAt.month, reportAt.day).difference(
        DateTime(startsAt.year, startsAt.month, startsAt.day),
      ).inDays,
      startsAt: reportAt,
      endsAt: newEnd,
    );
  }
}

/// What [PrepWindow.adjust] worked out: the hours the cover stands, the
/// hours the post itself runs, and whether the two differ.
class PrepAdjustment {
  /// True once the preparation hour moved anything. False is the
  /// ordinary answer for a cover assigned ahead of time, and means
  /// [window] and [original] are the same hours.
  final bool adjusted;

  /// The hours the replacement actually stands.
  final PostTime window;

  /// The post's own hours, as the roster has them.
  final PostTime original;

  /// How many days after the duty date the time-in falls. Non-zero only
  /// for an overnight post covered in the small hours of the morning —
  /// see prep_window.py, which stores it on the schedule entry because
  /// a bare "HH:MM" pair cannot express it.
  final int dayOffset;

  final DateTime startsAt;
  final DateTime endsAt;

  const PrepAdjustment({
    required this.adjusted,
    required this.window,
    required this.original,
    required this.dayOffset,
    required this.startsAt,
    required this.endsAt,
  });

  /// '1000H - 1900H'
  String get range => window.range;

  /// '0500H - 1700H'
  String get originalRange => original.range;

  /// '1000H' — when the guard has to be standing at the station.
  String get reportBy => formatMilitary(window.start);

  /// 'you have 1 hour' — the notice, phrased from the constant so it
  /// can't drift from the hours above.
  String get noticeLabel {
    final hours = PrepWindow.prep.inMinutes / 60;
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    return '$text hour${hours == 1 ? '' : 's'}';
  }
}
