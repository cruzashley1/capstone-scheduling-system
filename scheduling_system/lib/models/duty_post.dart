// models/duty_post.dart
//
// One place an employee is already rostered during a rotation cycle,
// read from GET /special-assignments/duty-status.
//
// This is what lets the Special Assignments picker say "already on duty
// at Balintawak, Sep 1 – 15" next to a guard's name. It matters because
// a pin relocates them for the whole month while the OTHER station's
// saved schedule still has them: generation refuses to write a roster it
// can already tell contradicts another, so knowing before you pin saves
// finding out at generation time.
class DutyPost {
  final String stationId;
  final String stationName;
  final DateTime startDate;
  final DateTime endDate;

  // 'published' | 'unpublished'. A published clash is the worse one —
  // its guards have already been notified of those shifts.
  final String status;

  // True when they only ever appear here covering someone's day off,
  // rather than manning a post of their own.
  final bool isReliever;

  const DutyPost({
    required this.stationId,
    required this.stationName,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.isReliever = false,
  });

  bool get isPublished => status == 'published';

  factory DutyPost.fromJson(Map<String, dynamic> json) {
    return DutyPost(
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime(1970),
      endDate: DateTime.tryParse(json['endDate'] ?? '') ?? DateTime(1970),
      status: json['status'] ?? 'unpublished',
      isReliever: json['isReliever'] ?? false,
    );
  }

  // "Sep 1 – 15" / "Sep 28 – Oct 12" — short enough to sit inside a chip
  // beside the station name.
  String get periodLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final from = '${months[startDate.month - 1]} ${startDate.day}';
    final to = startDate.month == endDate.month
        ? '${endDate.day}'
        : '${months[endDate.month - 1]} ${endDate.day}';
    return '$from – $to';
  }
}
