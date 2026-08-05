// models/replacement.dart
//
// Models for the absence-replacement flow (Phase 3):
//  - ReplacementCandidate: one suggestion returned by
//    GET /replacements/suggest (already conflict-filtered and ranked).
//  - ReplacementRequest: the navigation payload carried into the Find
//    Replacement screen — which absence we're covering and, when opened
//    from a submitted report, the report/record to update afterwards.

import 'attendance_report.dart';
import 'employee.dart';

class ReplacementCandidate {
  final Employee employee;
  final int score; // 0-100 suitability score from the backend
  final List<String> reasons; // human-readable ranking explanations
  final int daysWorkedThisPeriod;

  const ReplacementCandidate({
    required this.employee,
    required this.score,
    required this.reasons,
    required this.daysWorkedThisPeriod,
  });

  factory ReplacementCandidate.fromJson(Map<String, dynamic> json) {
    return ReplacementCandidate(
      employee:
          Employee.fromJson(Map<String, dynamic>.from(json['employee'] ?? {})),
      score: json['score'] ?? 0,
      reasons: json['reasons'] != null
          ? List<String>.from(json['reasons'])
          : const [],
      daysWorkedThisPeriod: json['daysWorkedThisPeriod'] ?? 0,
    );
  }
}

// One admin-applied replacement — the audit record the backend writes
// when the admin confirms a substitution via POST /replacements/apply.
// Feeds the Schedule Report's Absence & Substitution Log.
class AppliedReplacement {
  final String id;
  final DateTime? date; // day of the absence
  final String station;
  final String shift; // 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | ...
  final String absentEmployeeId;
  final String absentEmployeeName;
  final String replacementEmployeeId;
  final String replacementEmployeeName;

  const AppliedReplacement({
    required this.id,
    required this.date,
    required this.station,
    required this.shift,
    required this.absentEmployeeId,
    required this.absentEmployeeName,
    required this.replacementEmployeeId,
    required this.replacementEmployeeName,
  });

  factory AppliedReplacement.fromJson(Map<String, dynamic> json) {
    return AppliedReplacement(
      id: json['id'] ?? '',
      date: DateTime.tryParse(json['date'] ?? ''),
      station: json['station'] ?? '',
      shift: json['shift'] ?? '',
      absentEmployeeId: json['absentEmployeeId'] ?? '',
      absentEmployeeName: json['absentEmployeeName'] ?? '',
      replacementEmployeeId: json['replacementEmployeeId'] ?? '',
      replacementEmployeeName: json['replacementEmployeeName'] ?? '',
    );
  }
}

class ReplacementRequest {
  final String date; // ISO date of the absence, YYYY-MM-DD
  final String station;
  final String shift; // 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | ...
  final String absentEmployeeId;
  final String absentName;

  // Present when opened from a submitted report: lets the screen stamp
  // the in-memory record after applying and navigate back to the report.
  final String? reportId;
  final AttendanceReport? report;
  final AttendanceRecord? record;

  // Present when opened from approving an emergency absence request. In
  // this "approval mode" assigning a cover also approves the request, and
  // an empty candidate list blocks the approval (no cover = can't approve).
  final String? absenceRequestId;

  const ReplacementRequest({
    required this.date,
    required this.station,
    required this.shift,
    required this.absentEmployeeId,
    required this.absentName,
    this.reportId,
    this.report,
    this.record,
    this.absenceRequestId,
  });

  // True when this screen is the "cover" step of approving an absence.
  bool get isApprovalFlow => absenceRequestId != null;
}
