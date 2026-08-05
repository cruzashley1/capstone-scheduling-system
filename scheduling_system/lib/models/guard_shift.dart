// models/guard_shift.dart
// One duty entry belonging to the logged-in guard, as returned by
// GET /employees/{id}/schedule. A GuardPeriod is the date range of a
// published schedule the guard appears in — days inside a period with
// no GuardShift are the guard's rest days.

import 'post_time.dart';

// A shift's BASE display times — the un-staggered window every post of
// that shift starts from.
//
// These are only the fallback now. Posts are staggered per station (they
// come in pairs — two on the shift's base window, the next two two hours
// later, see post_time.dart), so a guard's real window rides on
// their own schedule entry. Use these when there is no entry to read:
// a legacy schedule with no times on it, or a guard's permanent
// assignedShift, which names a shift rather than a post.
const List<String> kShiftLabels = [
  'Morning',
  'Afternoon',
  'Night',
  'HG Day',
  'HG Night',
];

final Map<String, String> shiftTimeRanges = {
  for (final shift in kShiftLabels) shift: baseShiftWindow(shift)!.range,
};

final Map<String, String> shiftDurations = {
  for (final shift in kShiftLabels) shift: baseShiftWindow(shift)!.duration,
};

// Maps the raw assignedShift Firestore value to a display label. This is
// the guard's PERMANENT shift, not a rostered duty, so it can only name
// the shift's base window — the staggered post time comes from the
// published schedule (see GuardShift.timeRange).
String assignedShiftLabel(String? raw) {
  const labels = {
    'morning': 'Morning',
    'afternoon': 'Afternoon',
    'night': 'Night',
    'hgDay': 'HG Day',
    'hgNight': 'HG Night',
  };
  final window = labels[raw] == null ? null : baseShiftWindow(labels[raw]!);
  if (window == null) return 'Rotating / As assigned';
  return '${labels[raw]} (${window.range})';
}

class GuardShift {
  final DateTime date;
  final String scheduleId;
  final String stationId;
  final String stationName;

  // 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | 'HG Night'
  final String shift;

  // This duty's own window, "HH:MM", as the station's stagger ladder set
  // it for the post being manned. Null on schedules generated before
  // posts carried times — `window` then falls back to the shift's base
  // hours, which is exactly how the app behaved before.
  final String? timeInRaw;
  final String? timeOutRaw;

  final bool isReliever;
  final String? coveringFor;

  GuardShift({
    required this.date,
    required this.scheduleId,
    required this.stationId,
    required this.stationName,
    required this.shift,
    this.timeInRaw,
    this.timeOutRaw,
    this.isReliever = false,
    this.coveringFor,
  });

  bool get isCovering => coveringFor != null;

  String get title => '$shift Shift';

  // The duty window that actually applies to THIS guard on THIS date.
  // Two guards on the same shift can now start two hours apart, so this
  // must never be looked up from the shift name alone. Null only when the
  // shift label isn't one we know and the entry carries no times.
  PostTime? get window =>
      shiftWindow(shift, timeIn: timeInRaw, timeOut: timeOutRaw);

  String get timeRange => window?.range ?? '';

  String get duration => window?.duration ?? '';

  String get timeIn {
    final w = window;
    return w == null ? '' : formatMilitary(w.start);
  }

  String get timeOut {
    final w = window;
    return w == null ? '' : formatMilitary(w.end);
  }

  // ---- Clock-aware duty window -------------------------------------
  // The dashboards decide On Duty / Awaiting / Off Shift by comparing the
  // wall clock against these, instead of just matching the date.

  int? get _startMinutes => window?.start;
  int? get _endMinutes => window?.end;

  // Night (2100H - 0600H) and HG Night (1700H - 0500H) run past midnight:
  // their time-out lands on the day AFTER `date`. A staggered afternoon
  // post can now cross midnight too (1800H - 0300H), which this already
  // handles — it compares the times, not the shift name.
  bool get crossesMidnight {
    final s = _startMinutes;
    final e = _endMinutes;
    if (s == null || e == null) return false;
    return e <= s;
  }

  // Absolute time-in / time-out. Null when the duty has no known window —
  // callers fall back to treating the whole day as the duty.
  DateTime? get startsAt {
    final s = _startMinutes;
    if (s == null) return null;
    return DateTime(date.year, date.month, date.day)
        .add(Duration(minutes: s));
  }

  DateTime? get endsAt {
    final e = _endMinutes;
    if (_startMinutes == null || e == null) return null;
    final sameDay =
        DateTime(date.year, date.month, date.day).add(Duration(minutes: e));
    return crossesMidnight ? sameDay.add(const Duration(days: 1)) : sameDay;
  }

  Duration? get length {
    final s = startsAt;
    final e = endsAt;
    if (s == null || e == null) return null;
    return e.difference(s);
  }

  // The guard is on post right now: time-in has passed, time-out hasn't.
  bool isActiveAt(DateTime now) {
    final s = startsAt;
    final e = endsAt;
    if (s == null || e == null) return false;
    return !now.isBefore(s) && now.isBefore(e);
  }

  bool startsAfter(DateTime now) {
    final s = startsAt;
    return s != null && s.isAfter(now);
  }

  bool hasEndedBy(DateTime now) {
    final e = endsAt;
    return e != null && !now.isBefore(e);
  }

  factory GuardShift.fromJson(Map<String, dynamic> json) {
    return GuardShift(
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      scheduleId: json['scheduleId'] ?? '',
      stationId: json['stationId'] ?? '',
      stationName: (json['stationName'] ?? '').toString().trim(),
      shift: json['shift'] ?? '',
      timeInRaw: json['timeIn'],
      timeOutRaw: json['timeOut'],
      isReliever: json['isReliever'] ?? false,
      coveringFor: json['coveringFor'],
    );
  }
}

class GuardPeriod {
  final String scheduleId;
  final String stationId;
  final String stationName;
  final DateTime startDate;
  final DateTime endDate;

  // Every station the guard works during this period, busiest first.
  // A reliever is topped up towards their 12 days across the stations
  // near their own, so one period can span several — stationName above
  // is just the one they spend most of it at. Single-entry for anyone
  // who holds one post all period.
  final List<String> stationNames;

  GuardPeriod({
    required this.scheduleId,
    required this.stationId,
    required this.stationName,
    required this.startDate,
    required this.endDate,
    this.stationNames = const [],
  });

  // The stations beyond the main one, for a "+2 more" style label.
  List<String> get otherStations =>
      stationNames.where((n) => n != stationName).toList();

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(DateTime(startDate.year, startDate.month, startDate.day)) &&
        !d.isAfter(DateTime(endDate.year, endDate.month, endDate.day));
  }

  factory GuardPeriod.fromJson(Map<String, dynamic> json) {
    final name = (json['stationName'] ?? '').toString().trim();
    final names = (json['stationNames'] as List?)
            ?.map((n) => n.toString().trim())
            .where((n) => n.isNotEmpty)
            .toList() ??
        const <String>[];
    return GuardPeriod(
      scheduleId: json['scheduleId'] ?? '',
      stationId: json['stationId'] ?? '',
      stationName: name,
      startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['endDate'] ?? '') ?? DateTime.now(),
      // Older responses carry no list; the one station is the whole of it.
      stationNames: names.isEmpty ? [if (name.isNotEmpty) name] : names,
    );
  }
}
