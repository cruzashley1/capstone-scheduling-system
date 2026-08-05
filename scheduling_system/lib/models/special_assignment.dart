// models/special_assignment.dart
//
// One admin pin: "this employee works THIS station for THIS rotation
// cycle (calendar month), overriding whatever the monthly rotation
// would have decided." Pins expire on their own — the backend keys them
// by cycle ID, so next month's generation simply doesn't find them.
import 'employee.dart';

class SpecialAssignment {
  final String id; // "{cycleId}_{employeeId}"
  final String rotationCycleId; // "202607"
  final String employeeId;
  final String employeeName;
  final EmployeeType employeeType;
  final String stationId;
  final String stationName;

  // 'morning' | 'afternoon' | 'night' | 'hgDay' | 'hgNight';
  // null for relievers, who float across morning/afternoon posts.
  final String? shift;

  // The station the employee returns to when the pin expires.
  final String? homeStation;

  // When the admin saved this pin. Not the same thing as when it takes
  // effect — the cycle decides that — but it's what answers "how long
  // has this guard been posted here?" on the station detail screen.
  final DateTime? createdAt;

  const SpecialAssignment({
    required this.id,
    required this.rotationCycleId,
    required this.employeeId,
    required this.employeeName,
    required this.employeeType,
    required this.stationId,
    required this.stationName,
    this.shift,
    this.homeStation,
    this.createdAt,
  });

  // First and last day this pin is in force. A pin covers exactly one
  // rotation cycle — a whole calendar month — so the window is derivable
  // from the cycle ID alone and never needs its own stored dates.
  DateTime get startDate => cycleStartDate(rotationCycleId);
  DateTime get endDate => cycleEndDate(rotationCycleId);
  int get durationDays => endDate.difference(startDate).inDays + 1;

  factory SpecialAssignment.fromJson(Map<String, dynamic> json) {
    return SpecialAssignment(
      id: json['id'] ?? '',
      rotationCycleId: json['rotationCycleId'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeType: EmployeeType.values.firstWhere(
        (e) => e.name == json['employeeType'],
        orElse: () => EmployeeType.regular,
      ),
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      shift: json['shift'],
      homeStation: json['homeStation'],
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'])?.toLocal()
          : null,
    );
  }

  // Shape the PUT /stations/{id}/special-assignments endpoint expects
  // per entry — everything else it re-derives server-side.
  Map<String, dynamic> toSaveJson() => {
        'employeeId': employeeId,
        'shift': shift,
      };
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

// Cycle IDs mirror rotation.build_cycle_id in the backend: 2026-07 -> "202607".
String cycleIdFor(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}';

// (year, month) parsed out of a cycle ID, or null when it's malformed.
(int, int)? _cycleParts(String cycleId) {
  if (cycleId.length != 6) return null;
  final year = int.tryParse(cycleId.substring(0, 4));
  final month = int.tryParse(cycleId.substring(4));
  if (year == null || month == null || month < 1 || month > 12) return null;
  return (year, month);
}

// "202607" -> "July 2026", for the month picker and dialog headers.
String cycleLabel(String cycleId) {
  final parts = _cycleParts(cycleId);
  if (parts == null) return cycleId;
  return '${_monthNames[parts.$2 - 1]} ${parts.$1}';
}

// A pin runs for one whole rotation cycle, so its window is the calendar
// month the cycle names — these are what the UI shows as its duration.
DateTime cycleStartDate(String cycleId) {
  final parts = _cycleParts(cycleId);
  if (parts == null) return DateTime(1970);
  return DateTime(parts.$1, parts.$2, 1);
}

// Day 0 of the NEXT month is the last day of this one, which gets 28/29/
// 30/31 right without a leap-year table.
DateTime cycleEndDate(String cycleId) {
  final parts = _cycleParts(cycleId);
  if (parts == null) return DateTime(1970);
  return DateTime(parts.$1, parts.$2 + 1, 0);
}

// "August 1 – 31, 2026" — the span a special assignment covers.
String cycleRangeLabel(String cycleId) {
  final parts = _cycleParts(cycleId);
  if (parts == null) return cycleId;
  final month = _monthNames[parts.$2 - 1];
  return '$month 1 – ${cycleEndDate(cycleId).day}, ${parts.$1}';
}

// Where the cycle sits relative to today, e.g. "12 days left" — the bit
// that says whether a pin is still running, not yet started, or spent.
String cycleStatusLabel(String cycleId, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final start = cycleStartDate(cycleId);
  final end = cycleEndDate(cycleId);
  final day = DateTime(today.year, today.month, today.day);

  if (day.isBefore(start)) {
    final days = start.difference(day).inDays;
    return days == 1 ? 'starts tomorrow' : 'starts in $days days';
  }
  if (day.isAfter(end)) return 'ended';
  final left = end.difference(day).inDays + 1;
  return left == 1 ? 'last day' : '$left days left';
}
