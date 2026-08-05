// models/post_time.dart
//
// The duty window a single station post is manned for, and the stagger
// ladder that hands those windows out.
//
// This is the Dart mirror of backend_python/station_posts.py — the two
// must agree, because Edit Station computes windows live for the form
// while the API re-derives them on save and the generator stamps them
// onto every schedule entry. Any change to the rule below belongs in
// both files.
//
// THE LADDER
//
// Posts are not all manned at once. Each shift has a base window and the
// ladder climbs it in RUNGS OF TWO: regular posts are handed out in
// pairs, and only once a pair is full does the next one start two hours
// later, so the station keeps cover while guards rotate off and never
// leaves a rung manned by a single guard:
//
//   MORNING (base 0500H - 1400H)
//     1. Head Guard   0500H - 1700H   <- fixed 12h duty, off the ladder
//     2. SW Platform  0500H - 1400H   <- ladder slot 0 ┐ rung 0
//     3. SE Platform  0500H - 1400H   <- ladder slot 1 ┘
//     4. Roving       0700H - 1600H   <- ladder slot 2 ┐ rung 1
//     5. Ladder       0700H - 1600H   <- ladder slot 3 ┘
//     6. Concourse    0900H - 1800H   <- ladder slot 4 ┐ rung 2
//
// The duty LENGTH never changes — only the start slides, so every slot is
// as long as its shift's base window.
//
//   * The head guard slot is never on the ladder and can't be re-timed:
//     the two head guards work fixed 12-hour duties (HG Day 0500H-1700H,
//     HG Night 1700H-0500H).
//   * NIGHT doesn't stagger — it runs the night head guard plus two
//     roving guards, so every night post sits on the base window.
//   * The admin can override one slot by hand. It's then pinned
//     (auto: false) and stops moving when posts are added or removed
//     around it, until they put it back on the ladder.
//   * A ladder that climbs into the NEXT shift is allowed but flagged
//     (see overrunsNextShift) — Edit Station warns rather than refusing.
//
// THE 9-HOUR RULE
//
// Every regular duty is kStandardDutyMinutes long — the ladder only ever
// slides the start, so it can't break that on its own. A hand-pinned
// window can, which is why Edit Station REFUSES anything shorter than
// nine hours (that guard would be underworked and the post left bare)
// and WARNS about anything longer (overtime, allowed but deliberate).
// The head guard's fixed 12-hour duty is outside the rule.

import 'station.dart' show kHeadGuardPost;

const int kMinutesPerDay = 24 * 60;

/// How far each ladder step slides the start time.
const int kLadderStepMinutes = 120;

/// How many posts share one rung before the ladder climbs. Posts are
/// handed out in pairs — two on the base window, two two hours later,
/// and so on.
const int kLadderSlotsPerRung = 2;

/// The duty length every regular post is expected to run. Shorter than
/// this is refused in Edit Station, longer is warned about.
const int kStandardDutyMinutes = 9 * 60;

/// The base duty window each shift's ladder starts from, as
/// (startMinutes, endMinutes).
const Map<String, (int, int)> kShiftWindows = {
  'morning': (5 * 60, 14 * 60), // 0500H - 1400H
  'afternoon': (14 * 60, 23 * 60), // 1400H - 2300H
  'night': (21 * 60, 6 * 60), // 2100H - 0600H
};

/// The head guard's fixed 12-hour duty, keyed by the shift whose first
/// slot they man.
const Map<String, (int, int)> kHeadGuardWindows = {
  'morning': (5 * 60, 17 * 60), // HG Day  0500H - 1700H
  'night': (17 * 60, 5 * 60), // HG Night 1700H - 0500H
};

/// The same two windows keyed by the schedule's HG shift labels.
const Map<String, (int, int)> kHgShiftWindows = {
  'HG Day': (5 * 60, 17 * 60),
  'HG Night': (17 * 60, 5 * 60),
};

/// Night keeps every post on the base window.
const List<String> kStaggeredShifts = ['morning', 'afternoon'];

/// Which shift a ladder would run into if it climbs far enough.
const Map<String, String> kNextShift = {
  'morning': 'afternoon',
  'afternoon': 'night',
};

/// The schedule's shift labels, mapped back to the station setup's keys.
const Map<String, String> kShiftLabelKeys = {
  'Morning': 'morning',
  'Afternoon': 'afternoon',
  'Night': 'night',
};

/// '05:00' / '0500' / '0500H' -> 300. Null on anything unparseable.
int? parseHhmm(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 4) return null;
  final hour = int.tryParse(digits.substring(0, 2));
  final minute = int.tryParse(digits.substring(2));
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// 300 -> '05:00' — the stored form.
String formatHhmm(int minutes) {
  final m = minutes % kMinutesPerDay;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// 300 -> '0500H' — the form every screen displays.
String formatMilitary(int minutes) {
  final m = minutes % kMinutesPerDay;
  return '${(m ~/ 60).toString().padLeft(2, '0')}'
      '${(m % 60).toString().padLeft(2, '0')}H';
}

/// '0500H - 1400H'
String formatMilitaryRange(int start, int end) =>
    '${formatMilitary(start)} - ${formatMilitary(end)}';

/// Minutes from start to end, treating end <= start as crossing midnight
/// (2100H -> 0600H is 9 hours, not -15).
int windowLength(int start, int end) {
  final span = (end - start) % kMinutesPerDay;
  return span == 0 ? kMinutesPerDay : span;
}

/// Duty length as the screens phrase it: '9 hrs', '9.5 hrs'.
String formatDuration(int start, int end) {
  final hours = windowLength(start, end) / 60.0;
  final text = hours == hours.roundToDouble()
      ? hours.toStringAsFixed(0)
      : hours.toStringAsFixed(1);
  return '$text hrs';
}

/// How far slot [ladderIndex] of [shiftKey] starts after the base.
///
/// Slots are paired onto rungs — 0 and 1 share the base, 2 and 3 sit two
/// hours up, and so on — so the ladder only climbs once the rung below it
/// is full.
int ladderOffset(String shiftKey, int ladderIndex) {
  if (!kStaggeredShifts.contains(shiftKey)) return 0;
  return (ladderIndex ~/ kLadderSlotsPerRung) * kLadderStepMinutes;
}

/// True when a slot starting at [start] has climbed into the shift that
/// follows it — a morning post starting at 1500H, say.
///
/// Measured as an offset from the shift's own base so the night's
/// midnight wrap can't make the comparison lie.
bool overrunsNextShift(String shiftKey, int start) {
  final following = kNextShift[shiftKey];
  if (following == null) return false;
  final base = kShiftWindows[shiftKey]!.$1;
  final nextBase = kShiftWindows[following]!.$1;
  return (start - base) % kMinutesPerDay >=
      (nextBase - base) % kMinutesPerDay;
}

/// One slot's duty window.
///
/// [auto] false means the admin overrode this slot by hand, so the ladder
/// leaves it alone when posts are added or removed around it.
class PostTime {
  final int start;
  final int end;
  final bool auto;

  const PostTime({required this.start, required this.end, this.auto = true});

  String get range => formatMilitaryRange(start, end);

  String get duration => formatDuration(start, end);

  int get lengthMinutes => windowLength(start, end);

  /// Shorter than the standard duty — the guard is underworked and the
  /// post goes bare, so Edit Station refuses to pin one of these.
  bool get isShortDuty => lengthMinutes < kStandardDutyMinutes;

  /// Longer than the standard duty — overtime. Allowed, but warned about.
  bool get isLongDuty => lengthMinutes > kStandardDutyMinutes;

  PostTime copyWith({int? start, int? end, bool? auto}) => PostTime(
        start: start ?? this.start,
        end: end ?? this.end,
        auto: auto ?? this.auto,
      );

  static PostTime? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final start = parseHhmm(json['start']?.toString());
    final end = parseHhmm(json['end']?.toString());
    if (start == null || end == null) return null;
    return PostTime(start: start, end: end, auto: json['auto'] as bool? ?? true);
  }

  Map<String, dynamic> toJson() => {
        'start': formatHhmm(start),
        'end': formatHhmm(end),
        'auto': auto,
      };

  @override
  bool operator ==(Object other) =>
      other is PostTime &&
      other.start == start &&
      other.end == end &&
      other.auto == auto;

  @override
  int get hashCode => Object.hash(start, end, auto);
}

/// The duty window to show for one rostered guard.
///
/// The single place the fallback rule lives, so every screen agrees: the
/// entry's OWN window wins (that's the one the station's ladder gave that
/// post), and only when it's missing — a schedule generated before posts
/// carried times — does the shift's base window stand in.
///
/// [shiftLabel] is the schedule's label: 'Morning', 'Afternoon', 'Night',
/// 'HG Day' or 'HG Night'.
///
/// Null when neither is available — an unrecognized shift label with no
/// times on the entry. Callers treat that as "no time range on file" and
/// fall back to the whole day, which is what they did before posts
/// carried times.
PostTime? shiftWindow(String shiftLabel, {String? timeIn, String? timeOut}) {
  final start = parseHhmm(timeIn);
  final end = parseHhmm(timeOut);
  if (start != null && end != null) {
    return PostTime(start: start, end: end);
  }
  return baseShiftWindow(shiftLabel);
}

/// A shift label's un-staggered base window — what a guard works when the
/// schedule carries no window of its own. Null on an unknown label.
PostTime? baseShiftWindow(String shiftLabel) {
  final hg = kHgShiftWindows[shiftLabel];
  if (hg != null) return PostTime(start: hg.$1, end: hg.$2);
  final base = kShiftWindows[kShiftLabelKeys[shiftLabel] ?? ''];
  if (base == null) return null;
  return PostTime(start: base.$1, end: base.$2);
}

/// The window the ladder gives slot [index] of [shiftKey].
///
/// The head guard slot is answered with its fixed 12-hour duty and does
/// not consume a ladder step — the ladder counts REGULAR posts only, so a
/// morning's first named post still starts at the base.
PostTime autoWindow(String shiftKey, List<String> posts, int index) {
  final post = index < posts.length ? posts[index] : '';
  final headGuard = kHeadGuardWindows[shiftKey];
  if (post == kHeadGuardPost && headGuard != null) {
    return PostTime(start: headGuard.$1, end: headGuard.$2);
  }

  final base = kShiftWindows[shiftKey] ?? kShiftWindows['morning']!;
  final length = windowLength(base.$1, base.$2);
  var ladderIndex = 0;
  for (var i = 0; i < index && i < posts.length; i++) {
    if (posts[i] != kHeadGuardPost) ladderIndex++;
  }
  final start = (base.$1 + ladderOffset(shiftKey, ladderIndex)) % kMinutesPerDay;
  return PostTime(start: start, end: (start + length) % kMinutesPerDay);
}

/// One window per entry in [posts], aligned by index.
///
/// [stored] is whatever the station already had. An `auto` slot is
/// recomputed from the ladder every time — that's what makes adding a
/// post re-stagger the ones after it. A slot the admin pinned keeps its
/// window, unless it's the head guard's, whose 12-hour duty always wins.
List<PostTime> normalizePostTimes(
  String shiftKey,
  List<String> posts, [
  List<PostTime?> stored = const [],
]) {
  return [
    for (var index = 0; index < posts.length; index++)
      _resolveSlot(shiftKey, posts, index,
          index < stored.length ? stored[index] : null),
  ];
}

PostTime _resolveSlot(
    String shiftKey, List<String> posts, int index, PostTime? stored) {
  final isHeadGuard =
      posts[index] == kHeadGuardPost && kHeadGuardWindows[shiftKey] != null;
  // The head guard's duty is never re-timed, however it was stored.
  if (isHeadGuard || stored == null || stored.auto) {
    return autoWindow(shiftKey, posts, index);
  }
  return stored;
}
