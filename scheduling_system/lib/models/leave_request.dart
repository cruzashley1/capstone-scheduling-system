// models/leave_request.dart
//
// One leave record. It reaches the `leave_requests` collection two ways:
// filed by an employee from the guard app's dashboard (status 'pending',
// waiting on the admin), or recorded by the admin from Employee Details
// (status 'approved' the moment it is saved). An approved leave keeps the
// employee off the roster for its whole date range.
//
// Mirrors the JSON the Python backend stores — every rule behind these
// fields lives in backend_python/leave.py, never here.

import 'package:flutter/material.dart';

// One duty an admin-recorded leave swallowed: a post on a live roster
// that now needs a replacement rather than quietly going unmanned.
class LeaveAffectedDuty {
  final String date;
  final String stationName;
  final String shift;
  final String post;
  final String scheduleId;
  final String scheduleStatus;

  const LeaveAffectedDuty({
    required this.date,
    required this.stationName,
    required this.shift,
    required this.post,
    required this.scheduleId,
    required this.scheduleStatus,
  });

  bool get isPublished => scheduleStatus == 'published';

  factory LeaveAffectedDuty.fromJson(Map<String, dynamic> json) {
    return LeaveAffectedDuty(
      date: json['date'] ?? '',
      stationName: json['stationName'] ?? '',
      shift: json['shift'] ?? '',
      post: json['post'] ?? '',
      scheduleId: json['scheduleId'] ?? '',
      scheduleStatus: json['scheduleStatus'] ?? 'unpublished',
    );
  }
}

class LeaveRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeType; // 'regular' | 'reliever' | 'headGuard'
  final String station; // '' when floating
  final String leaveType; // one of the backend's LEAVE_TYPES
  final String startDate; // ISO YYYY-MM-DD, inclusive
  final String endDate; // ISO YYYY-MM-DD, inclusive
  final int days;
  final String title;
  final String body;
  final String source; // 'employee' | 'admin'
  final DateTime submittedAt;

  // Null until decided — never back-filled with "now", so the UI can tell
  // "not decided yet" from "decided at some point".
  final DateTime? decidedAt;
  final String? decidedBy;

  // Who at the higher authority endorsed this. Only set when the leave
  // went past its type's cap or waived a rule — the endorsement the
  // admin attested to, since the system has no supervisor account.
  final String supervisorName;
  final List<String> overriddenRules;
  final List<String> overrideNotes;

  final List<LeaveAffectedDuty> affectedDuties;

  // Mutable so the admin tab can flip these locally right after the API
  // call, without refetching the list (same convention as SpecialRequest).
  String status; // pending | approved | denied | cancelled
  String adminNote;
  bool isRead;

  LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeType,
    required this.station,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.title,
    required this.body,
    required this.source,
    required this.status,
    required this.submittedAt,
    this.decidedAt,
    this.decidedBy,
    this.supervisorName = '',
    this.overriddenRules = const [],
    this.overrideNotes = const [],
    this.affectedDuties = const [],
    this.adminNote = '',
    this.isRead = false,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'denied';
  bool get isCancelled => status == 'cancelled';

  bool get isAdminRecorded => source == 'admin';
  bool get wasEndorsed => supervisorName.isNotEmpty;
  bool get brokeRules => overriddenRules.isNotEmpty;

  // Where an approved leave stands relative to today. Computed here as
  // well as on the backend so a list that was fetched an hour ago still
  // reads correctly — the same rule either way.
  String get phase {
    if (!isApproved) return status;
    final today = _todayIso();
    if (endDate.compareTo(today) < 0) return 'completed';
    if (startDate.compareTo(today) > 0) return 'upcoming';
    return 'active';
  }

  bool get isOnLeaveNow => phase == 'active';
  bool get isUpcoming => phase == 'upcoming';

  // How many days of the leave are still to come, counting today.
  int get daysRemaining {
    final end = DateTime.tryParse(endDate);
    if (end == null || !isApproved) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final left = end.difference(today).inDays + 1;
    return left < 0 ? 0 : left;
  }

  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

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

  String get statusLabel {
    switch (phase) {
      case 'active':
        return 'On Leave';
      case 'upcoming':
        return 'Approved';
      case 'completed':
        return 'Completed';
      case 'denied':
        return 'Denied';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  // 'Friday, August 16, 2026' for a single ISO date.
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

  // 'Aug 16' — the compact form used on chips and table cells.
  static String formatShort(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}';
  }

  // 'Aug 16 – Aug 30, 2026' — one line covering the whole leave.
  String get rangeLabel {
    final s = DateTime.tryParse(startDate);
    final e = DateTime.tryParse(endDate);
    if (s == null || e == null) return '$startDate – $endDate';
    if (startDate == endDate) return '${formatShort(startDate)}, ${s.year}';
    if (s.year == e.year) {
      return '${formatShort(startDate)} – ${formatShort(endDate)}, ${s.year}';
    }
    return '${formatShort(startDate)}, ${s.year} – '
        '${formatShort(endDate)}, ${e.year}';
  }

  // The year a leave counts against — its start year, matching how the
  // backend charges the 2-per-year quota.
  int get year => int.tryParse(startDate.split('-').first) ?? 0;

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

  // Stable avatar color derived from the name, so the same employee
  // always gets the same color without storing one.
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

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeType: json['employeeType'] ?? 'regular',
      station: json['station'] ?? '',
      leaveType: json['leaveType'] ?? '',
      startDate: json['startDate'] ?? '',
      endDate: json['endDate'] ?? '',
      days: (json['days'] as num?)?.toInt() ?? 0,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      source: json['source'] ?? 'employee',
      status: json['status'] ?? 'pending',
      submittedAt:
          DateTime.tryParse(json['submittedAt'] ?? '')?.toLocal() ??
              DateTime.now(),
      decidedAt: DateTime.tryParse(json['decidedAt'] ?? '')?.toLocal(),
      decidedBy: json['decidedBy'],
      supervisorName: json['supervisorName'] ?? '',
      overriddenRules: ((json['overriddenRules'] as List?) ?? [])
          .map((r) => r.toString())
          .toList(),
      overrideNotes: ((json['overrideNotes'] as List?) ?? [])
          .map((r) => r.toString())
          .toList(),
      affectedDuties: ((json['affectedDuties'] as List?) ?? [])
          .map((d) =>
              LeaveAffectedDuty.fromJson(Map<String, dynamic>.from(d)))
          .toList(),
      adminNote: json['adminNote'] ?? '',
      isRead: json['isRead'] ?? false,
    );
  }
}

// One entry in the backend's leave catalogue: the type and the longest
// single leave it allows. Fetched rather than hardcoded, so the caps live
// in exactly one place.
class LeaveType {
  final String name;
  final int maxDays;

  const LeaveType({required this.name, required this.maxDays});

  factory LeaveType.fromJson(Map<String, dynamic> json) => LeaveType(
        name: json['name'] ?? '',
        maxDays: (json['maxDays'] as num?)?.toInt() ?? 15,
      );
}
