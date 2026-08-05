// models/station_roster.dart
// Today's roster for one station, as returned by
// GET /employees/{id}/station-overview — used by the Head Guard
// dashboard and Station Overview screen.

import 'post_time.dart';

class RosterEntry {
  final String employeeId;
  final String employeeName;
  final String shift; // 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | 'HG Night'

  // The post this guard is manning today, and the window they man it for.
  // Posts are staggered per station, so two guards on the same shift can
  // start two hours apart — the head guard's roster has to show each
  // guard's own hours rather than one time for the whole shift.
  final String? post;
  final String? timeIn;
  final String? timeOut;

  final bool isReliever;
  final String? coveringFor;

  RosterEntry({
    required this.employeeId,
    required this.employeeName,
    required this.shift,
    this.post,
    this.timeIn,
    this.timeOut,
    this.isReliever = false,
    this.coveringFor,
  });

  bool get isCovering => coveringFor != null;

  PostTime? get window => shiftWindow(shift, timeIn: timeIn, timeOut: timeOut);

  /// '0500H - 1400H'
  String get timeRange => window?.range ?? '';

  factory RosterEntry.fromJson(Map<String, dynamic> json) {
    return RosterEntry(
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shift: json['shift'] ?? '',
      post: json['post'],
      timeIn: json['timeIn'],
      timeOut: json['timeOut'],
      isReliever: json['isReliever'] ?? false,
      coveringFor: json['coveringFor'],
    );
  }
}

class DayOffEntry {
  final String employeeId;
  final String employeeName;
  final DateTime? nextDutyDate;
  final String? nextShift;

  DayOffEntry({
    required this.employeeId,
    required this.employeeName,
    this.nextDutyDate,
    this.nextShift,
  });

  factory DayOffEntry.fromJson(Map<String, dynamic> json) {
    return DayOffEntry(
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      nextDutyDate: json['nextDutyDate'] != null
          ? DateTime.tryParse(json['nextDutyDate'])
          : null,
      nextShift: json['nextShift'],
    );
  }
}

class StationRoster {
  final String? stationName;
  final DateTime date;
  final bool hasSchedule;
  final List<RosterEntry> onDuty;
  final List<DayOffEntry> dayOff;

  StationRoster({
    required this.stationName,
    required this.date,
    required this.hasSchedule,
    required this.onDuty,
    required this.dayOff,
  });

  int get totalEmployees => onDuty.length + dayOff.length;

  factory StationRoster.fromJson(Map<String, dynamic> json) {
    return StationRoster(
      stationName: (json['stationName'] as String?)?.trim(),
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      hasSchedule: json['hasSchedule'] ?? false,
      onDuty: (json['onDuty'] as List? ?? [])
          .map((e) => RosterEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      dayOff: (json['dayOff'] as List? ?? [])
          .map((e) => DayOffEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
