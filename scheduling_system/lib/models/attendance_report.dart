// models/attendance_report.dart
//
// Attendance report submitted by a Head Guard after taking attendance
// for a shift. The admin reviews these from the Notifications /
// Submitted Reports screens. Mirrors the JSON stored by the Python
// backend in the `attendance_reports` collection.

import 'package:flutter/material.dart';

class AttendanceRecord {
  final String name;
  final String employeeId;
  final String shift; // 'Morning' | 'Afternoon' | 'Night' | ...
  final String time; // display string, e.g. '0600H - 1400H'
  final bool isPresent;
  final bool isReliever;

  // Set (by the backend, or locally right after applying) once the
  // admin assigned someone to cover this absence. Mutable so the
  // screens can stamp it without refetching the whole report.
  String? replacedById;
  String? replacedByName;

  AttendanceRecord({
    required this.name,
    required this.employeeId,
    required this.shift,
    required this.time,
    required this.isPresent,
    this.isReliever = false,
    this.replacedById,
    this.replacedByName,
  });

  bool get isReplaced =>
      replacedById != null && replacedById!.isNotEmpty;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // Stable avatar color derived from the name, so the same guard always
  // gets the same color without storing one.
  Color get avatarColor {
    const palette = [
      Color(0xFF22C55E),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFF1034A6),
      Color(0xFF14B8A6),
      Color(0xFFEF4444),
      Color(0xFF0EA5E9),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      name: json['name'] ?? '',
      employeeId: json['employeeId'] ?? '',
      shift: json['shift'] ?? '',
      time: json['time'] ?? '',
      isPresent: json['isPresent'] ?? true,
      isReliever: json['isReliever'] ?? false,
      replacedById: json['replacedById'],
      replacedByName: json['replacedByName'],
    );
  }

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'name': name,
        'shift': shift,
        'time': time,
        'isPresent': isPresent,
        'isReliever': isReliever,
      };
}

class AttendanceReport {
  final String id;
  final String headGuardName;
  final String headGuardId;
  final String station;
  final String shiftTitle;
  final String date; // ISO date the attendance is for, YYYY-MM-DD
  final DateTime submittedAt;
  final List<AttendanceRecord> records;

  // Whether the admin has opened this report's notification. Mutable so
  // the Notifications screen can flip it locally after telling the API.
  bool isRead;

  AttendanceReport({
    required this.id,
    required this.headGuardName,
    required this.headGuardId,
    required this.station,
    required this.shiftTitle,
    required this.date,
    required this.submittedAt,
    required this.records,
    this.isRead = false,
  });

  int get totalCount => records.length;
  int get presentCount => records.where((r) => r.isPresent).length;
  int get absentCount => totalCount - presentCount;
  bool get hasAbsent => absentCount > 0;
  List<AttendanceRecord> get absentRecords =>
      records.where((r) => !r.isPresent).toList();

  bool get isForToday {
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return date == today;
  }

  // 'Friday, April 11, 2025' — for display alongside shiftTitle.
  String get shiftDate {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[parsed.weekday - 1]}, '
        '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  factory AttendanceReport.fromJson(Map<String, dynamic> json) {
    return AttendanceReport(
      id: json['id'] ?? '',
      headGuardName: json['headGuardName'] ?? '',
      headGuardId: json['headGuardId'] ?? '',
      station: json['station'] ?? '',
      shiftTitle: json['shiftTitle'] ?? '',
      date: json['date'] ?? '',
      submittedAt:
          DateTime.tryParse(json['submittedAt'] ?? '')?.toLocal() ??
              DateTime.now(),
      isRead: json['isRead'] ?? false,
      records: (json['records'] as List? ?? [])
          .map((r) => AttendanceRecord.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }
}
