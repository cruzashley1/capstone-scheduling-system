// models/absence_request.dart
//
// Emergency absence request filed from the guard app when an employee
// (head guard, regular or reliever) cannot report for duty — sickness,
// injury, an important occasion. The admin approves or denies it from
// the Notifications screen. Mirrors the JSON stored by the Python
// backend in the `absence_requests` collection.

import 'package:flutter/material.dart';

class AbsenceRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeType; // 'regular' | 'reliever' | 'headGuard'
  final String station; // '' when unknown
  final String shiftTitle; // '' when unknown / rest day
  final String date; // ISO date of the absence, YYYY-MM-DD
  final String title;
  final String reason; // Sick | Injury | Family Emergency | ...
  final String body;
  final DateTime submittedAt;

  // Null until an admin decides — never back-filled with "now", so the
  // UI can tell "not decided yet" from "decided at some point".
  final DateTime? decidedAt;
  final String? decidedBy;

  // Mutable so the admin tab and the guard screen can flip these
  // locally right after the API call, without refetching the list
  // (same convention as AttendanceReport.isRead).
  String status; // 'pending' | 'approved' | 'denied'
  String adminNote;
  bool isRead;

  AbsenceRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeType,
    required this.station,
    required this.shiftTitle,
    required this.date,
    required this.title,
    required this.reason,
    required this.body,
    required this.status,
    required this.submittedAt,
    this.decidedAt,
    this.decidedBy,
    this.adminNote = '',
    this.isRead = false,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'denied';

  // The backend stores the raw employeeType; the UI shows the label.
  String get roleLabel {
    switch (employeeType) {
      case 'headGuard':
        return 'Head Guard';
      case 'reliever':
        return 'Reliever Employee';
      default:
        return 'Regular Employee';
    }
  }

  // 'Friday, July 24, 2026' — the day the guard will be absent.
  String get displayDate {
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

  // How long ago this was filed — matches the phrasing the admin
  // Notifications screen already uses for attendance reports.
  String get timeAgo {
    final diff = DateTime.now().difference(submittedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  String get initials {
    final parts = employeeName.trim().split(RegExp(r'\s+'));
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
    return palette[employeeName.hashCode.abs() % palette.length];
  }

  factory AbsenceRequest.fromJson(Map<String, dynamic> json) {
    return AbsenceRequest(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeType: json['employeeType'] ?? 'regular',
      station: json['station'] ?? '',
      shiftTitle: json['shiftTitle'] ?? '',
      date: json['date'] ?? '',
      title: json['title'] ?? '',
      reason: json['reason'] ?? '',
      body: json['body'] ?? '',
      status: json['status'] ?? 'pending',
      submittedAt:
          DateTime.tryParse(json['submittedAt'] ?? '')?.toLocal() ??
              DateTime.now(),
      decidedAt: DateTime.tryParse(json['decidedAt'] ?? '')?.toLocal(),
      decidedBy: json['decidedBy'],
      adminNote: json['adminNote'] ?? '',
      isRead: json['isRead'] ?? false,
    );
  }
}
