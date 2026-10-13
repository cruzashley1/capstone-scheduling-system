import 'schedule.dart';

String officialRoleLabel(String role) => switch (role) {
  'assistantSecurity' => 'Assistant Security',
  'areaCommander' => 'Area Commander',
  'admin' => 'Administrator',
  _ => role,
};

String approvalStatusLabel(String status) => switch (status) {
  'pending_assistant' => 'Awaiting Assistant Security',
  'pending_commander' => 'Awaiting Area Commander',
  'approved' => 'Approved · Published',
  'returned' => 'Returned for revision',
  'withdrawn' => 'Withdrawn for revision',
  _ => 'Draft',
};

String approvalTime(dynamic value) {
  final time = DateTime.tryParse(
    value?.toString() ?? '',
  )?.toUtc().add(const Duration(hours: 8));
  if (time == null) return '';
  return '${time.toIso8601String().substring(0, 10)} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} PHT';
}

List<Map<String, dynamic>> approvalMaps(dynamic value) =>
    (value as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

class ScheduleApproval {
  final Map<String, dynamic> data;
  ScheduleApproval(this.data);
  String get id => data['id'];
  String get status => data['status'];
  int get version => data['version'];
  int get revision => data['revision'];
  String get start => data['startDate'];
  String get end => data['endDate'];
  String get period => '$start – $end';
  int get stationCount =>
      data['stationCount'] ?? (data['schedules'] as List? ?? []).length;
  List<Schedule> get schedules =>
      approvalMaps(data['schedules']).map(Schedule.fromJson).toList();
  List<Map<String, dynamic>> get events => approvalMaps(data['events']);
  List<Map<String, dynamic>> get amendments => approvalMaps(data['amendments']);
  bool get locked =>
      ['pending_assistant', 'pending_commander', 'approved'].contains(status);
  bool canDecide(String role) =>
      (role == 'assistantSecurity' && status == 'pending_assistant') ||
      (role == 'areaCommander' && status == 'pending_commander');
}
