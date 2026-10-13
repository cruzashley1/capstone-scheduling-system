// models/schedule.dart
import 'post_time.dart';
import 'schedule_note.dart';

enum ScheduleStatus { unpublished, published }

class ScheduleEntry {
  final String id;
  final String employeeId;
  final String employeeName;

  // 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | 'HG Night'
  // (old dummy data used 'Day'/'Night' — still parses fine).
  final String shift;

  // The post being manned: 'SW Platform', 'SE Platform', 'Roving',
  // 'Head Guard', an admin-typed name, or 'Undefined' until the admin
  // assigns one (a schedule with Undefined posts cannot be published).
  // Null on schedules generated before posts existed.
  final String? post;

  // The duty window this post is manned for, "HH:MM", stamped on by the
  // generator from the station's stagger ladder (Edit Station). Carried
  // per entry rather than looked up from the shift name because two
  // guards on the same shift now start two hours apart. Null on
  // schedules generated before posts carried times — `window` falls back
  // to the shift's base hours for those.
  final String? timeIn;
  final String? timeOut;

  // Set only on a post re-timed by the preparation window: a cover
  // assigned at short notice gets an hour to get ready and travel, so
  // the duty it inherits slides (services/prep_window.dart). These are
  // the hours the POST runs, kept beside the hours this guard actually
  // stands, so the schedule can show both.
  final String? originalTimeIn;
  final String? originalTimeOut;

  // How many days after this entry's date the time-in falls. Always 0
  // for a generated post; 1 only when a cover for an overnight post was
  // assigned in the small hours of the morning, which a bare "HH:MM"
  // pair has no way of saying on its own.
  final int dayOffset;

  // True when this entry is a reliever covering someone's day off.
  final bool isReliever;

  // employeeId of the person whose day off this entry covers (reliever,
  // night internal switch, or substitute head guard); null for own duty.
  final String? coveringFor;

  // True when this guard is at this station because an admin pinned them
  // here for the cycle (Station Management > Special Assignments) rather
  // than because rotation placed them.
  final bool isSpecial;

  ScheduleEntry({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.shift,
    this.post,
    this.timeIn,
    this.timeOut,
    this.originalTimeIn,
    this.originalTimeOut,
    this.dayOffset = 0,
    this.isReliever = false,
    this.coveringFor,
    this.isSpecial = false,
  });

  bool get isCovering => coveringFor != null;

  /// True when the preparation window moved this duty off the post's own
  /// hours — a cover assigned at short notice.
  bool get isPrepAdjusted => originalWindow != null;

  /// The hours the POST runs, when they differ from the hours this guard
  /// stands. Null on every ordinary entry.
  PostTime? get originalWindow {
    final start = parseHhmm(originalTimeIn);
    final end = parseHhmm(originalTimeOut);
    if (start == null || end == null) return null;
    return PostTime(start: start, end: end);
  }

  /// This entry's duty window, falling back to the shift's base hours for
  /// schedules generated before posts carried their own times.
  PostTime? get window => shiftWindow(shift, timeIn: timeIn, timeOut: timeOut);

  /// '0500H - 1400H', or empty on an unrecognized shift with no times.
  String get timeRange => window?.range ?? '';

  /// '9 hrs'
  String get duration => window?.duration ?? '';

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shift: json['shift'] ?? '',
      post: json['post'],
      timeIn: json['timeIn'],
      timeOut: json['timeOut'],
      originalTimeIn: json['originalTimeIn'],
      originalTimeOut: json['originalTimeOut'],
      dayOffset: json['dayOffset'] is int ? json['dayOffset'] as int : 0,
      isReliever: json['isReliever'] ?? false,
      coveringFor: json['coveringFor'],
      isSpecial: json['isSpecial'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'shift': shift,
        'post': post,
        'timeIn': timeIn,
        'timeOut': timeOut,
        'originalTimeIn': originalTimeIn,
        'originalTimeOut': originalTimeOut,
        'dayOffset': dayOffset,
        'isReliever': isReliever,
        'coveringFor': coveringFor,
        'isSpecial': isSpecial,
      };
}

class ScheduleDay {
  final DateTime date;
  final List<ScheduleEntry> entries;

  ScheduleDay({
    required this.date,
    required this.entries,
  });

  factory ScheduleDay.fromJson(Map<String, dynamic> json) {
    return ScheduleDay(
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      entries: (json['entries'] as List? ?? [])
          .map((e) => ScheduleEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String().substring(0, 10),
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}

class Schedule {
  final String id;
  final String stationId;
  final String stationName;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final ScheduleStatus status;
  final List<ScheduleDay> days;
  final String? approvalId;
  final String approvalStatus;
  bool get awaitingApproval => approvalStatus == 'pending_assistant' || approvalStatus == 'pending_commander';
  bool get canExport => status == ScheduleStatus.published && approvalStatus == 'approved';

  // What the generator had to bend to produce this roster. Carried on the
  // schedule itself so any screen holding one can report on it — the Auto
  // Scheduler parses the same field off its own generate response, and
  // the dashboard's Schedule Health panel aggregates these across runs.
  final List<ScheduleNote> notes;

  Schedule({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.status,
    required this.days,
    this.approvalId,
    this.approvalStatus = "draft",
    this.notes = const <ScheduleNote>[],
  });

  int get totalDays => days.length;

  int get totalAssignments =>
      days.fold(0, (sum, day) => sum + day.entries.length);

  // Distinct people appearing anywhere in the schedule.
  int get totalEmployees =>
      days.expand((d) => d.entries).map((e) => e.employeeId).toSet().length;

  // Builds a Schedule from the JSON the Python API returns.
  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] ?? '',
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['endDate'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      status: json['status'] == 'published'
          ? ScheduleStatus.published
          : ScheduleStatus.unpublished,
      days: (json['days'] as List? ?? [])
          .map((d) => ScheduleDay.fromJson(Map<String, dynamic>.from(d)))
          .toList(),
      notes: parseScheduleNotes(json),
      approvalId: json['approvalId'],
      approvalStatus: json['approvalStatus'] ?? 'draft',
    );
  }

  Schedule copyWith({
    String? id,
    String? stationId,
    String? stationName,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    ScheduleStatus? status,
    List<ScheduleDay>? days,
    List<ScheduleNote>? notes,
  }) {
    return Schedule(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      days: days ?? this.days,
      notes: notes ?? this.notes,
      approvalId: approvalId,
      approvalStatus: approvalStatus,
    );
  }
}
