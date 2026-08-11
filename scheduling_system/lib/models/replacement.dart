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
import 'post_time.dart';

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

// The AI's read on the candidates above — POST /replacements/ai-review.
//
// ALWAYS OPTIONAL. The backend returns `review: null` whenever it has
// nothing to say (switched off, out of quota, fewer than two candidates
// to weigh, or an answer that failed validation) and answers 200 while
// doing it, because no review is a normal outcome and not an error. The
// screen this appears on is complete without it, so every field here is
// decoration on a list that already works.
//
// `recommendedId` is guaranteed by the backend to be one of the
// candidates it was shown — it validates the model's answer against the
// shortlist and discards the whole response otherwise. The UI can look
// the id up without defending against a name that does not exist.
class AiReview {
  final String recommendedId;
  final String confidence; // 'strong' | 'moderate' | 'weak'
  final String rationale; // 1-2 sentences, written for the admin
  final String? risk; // a real trade-off, or null when the pick is clean
  final String? runnerUpId;
  final String? runnerUpTradeoff;
  final String? model;

  const AiReview({
    required this.recommendedId,
    required this.confidence,
    required this.rationale,
    this.risk,
    this.runnerUpId,
    this.runnerUpTradeoff,
    this.model,
  });

  // Whether the AI passed over whoever the rule-based score ranked
  // first. Asked at render time rather than stored on the model, so the
  // review can be fetched in parallel with the ranked list instead of
  // waiting on it — the two requests are independent and the screen is
  // slow enough already.
  bool differsFrom(String? topRankedId) =>
      topRankedId != null &&
      recommendedId.isNotEmpty &&
      recommendedId != topRankedId;

  factory AiReview.fromJson(Map<String, dynamic> json) {
    return AiReview(
      recommendedId: json['recommendedId']?.toString() ?? '',
      confidence: json['confidence']?.toString() ?? 'moderate',
      rationale: json['rationale']?.toString() ?? '',
      risk: json['risk']?.toString(),
      runnerUpId: json['runnerUpId']?.toString(),
      runnerUpTradeoff: json['runnerUpTradeoff']?.toString(),
      model: json['model']?.toString(),
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

  // The hours the cover actually stood, "HH:MM". Null on a record
  // written before replacements carried their own times — the log then
  // falls back to the shift's base window, as it always did.
  final String? timeIn;
  final String? timeOut;

  // The hours the POST runs, set only when the preparation window moved
  // the duty off them: a cover assigned at short notice gets an hour to
  // get ready and travel, so an 0500H - 1700H post covered at 0900H is
  // stood 1000H - 1900H (services/prep_window.dart). The log shows both,
  // because a report saying an 0500H post ran to 1900H with no
  // explanation is a report somebody has to come and ask about.
  final String? originalTimeIn;
  final String? originalTimeOut;

  const AppliedReplacement({
    required this.id,
    required this.date,
    required this.station,
    required this.shift,
    required this.absentEmployeeId,
    required this.absentEmployeeName,
    required this.replacementEmployeeId,
    required this.replacementEmployeeName,
    this.timeIn,
    this.timeOut,
    this.originalTimeIn,
    this.originalTimeOut,
  });

  /// True when the cover stood different hours from the post itself.
  bool get isPrepAdjusted => window != null && originalWindow != null;

  /// The hours the cover stood. Null when the record carries none.
  PostTime? get window => _windowOf(timeIn, timeOut);

  /// The post's own hours, when the cover's differ from them.
  PostTime? get originalWindow => _windowOf(originalTimeIn, originalTimeOut);

  static PostTime? _windowOf(String? from, String? to) {
    final start = parseHhmm(from);
    final end = parseHhmm(to);
    if (start == null || end == null) return null;
    return PostTime(start: start, end: end);
  }

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
      timeIn: json['timeIn'],
      timeOut: json['timeOut'],
      originalTimeIn: json['originalTimeIn'],
      originalTimeOut: json['originalTimeOut'],
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
