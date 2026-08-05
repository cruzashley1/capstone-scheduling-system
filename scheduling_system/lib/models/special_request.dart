// models/special_request.dart
//
// Special day-off request filed ahead of time from the guard app: an
// employee asks for up to three specific dates off — a vacation, a
// family event, a medical appointment — before any schedule covers
// them. The admin approves or denies the whole request from the
// Notifications screen, and an approved request forces those days off
// when that period's schedule is later generated. Mirrors the JSON the
// Python backend stores in the `special_requests` collection.

import 'package:flutter/material.dart';

class SpecialRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeType; // 'regular' | 'reliever' | 'headGuard'
  final String station; // '' when unknown / floating
  final List<String> dates; // 1..3 ISO dates, YYYY-MM-DD, sorted
  final String title;
  final String reason; // Vacation | Family Event | Medical | Personal | Other
  final String body;
  final DateTime submittedAt;

  // Null until an admin decides — never back-filled with "now", so the
  // UI can tell "not decided yet" from "decided at some point".
  final DateTime? decidedAt;
  final String? decidedBy;

  // Mutable so the admin tab and the guard screen can flip these locally
  // right after the API call, without refetching the list.
  String status; // 'pending' | 'approved' | 'denied'
  String adminNote;
  bool isRead;

  SpecialRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeType,
    required this.station,
    required this.dates,
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

  int get dayCount => dates.length;

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

  // 'Friday, July 24, 2026' for a single ISO date.
  static String formatDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
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

  // 'Aug 12' — the compact form used on chips where the full weekday
  // wording would overflow.
  static String formatShort(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}';
  }

  // 'Aug 12, Aug 15 and Aug 20' — a one-line summary of every date.
  String get datesSummary {
    if (dates.isEmpty) return '—';
    final parts = dates.map(formatShort).toList();
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} '
        'and ${parts.last}';
  }

  // How long ago this was filed — matches the phrasing the admin
  // Notifications screen already uses elsewhere.
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

  factory SpecialRequest.fromJson(Map<String, dynamic> json) {
    return SpecialRequest(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeType: json['employeeType'] ?? 'regular',
      station: json['station'] ?? '',
      dates: ((json['dates'] as List?) ?? [])
          .map((d) => d.toString())
          .toList(),
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
