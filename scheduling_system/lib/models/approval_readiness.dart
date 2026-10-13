import 'schedule.dart';
import 'station.dart';

/// A preview of submission requirements. The backend revalidates on submit.
class ApprovalReadiness {
  final int total;
  final int ready;
  final List<String> missing;
  final Map<String, String> incomplete;
  final List<String> extra;
  bool get canSubmit => total > 0 && ready == total && extra.isEmpty;

  ApprovalReadiness._(
    this.total,
    this.ready,
    this.missing,
    this.incomplete,
    this.extra,
  );

  factory ApprovalReadiness.check(
    List<Station> stations,
    List<Schedule> schedules,
  ) {
    final active = stations.where((s) => s.isActive).toList();
    final missing = <String>[];
    final incomplete = <String, String>{};
    var ready = 0;
    for (final station in active) {
      final rosters = schedules
          .where((s) => s.stationId == station.id)
          .toList();
      if (rosters.isEmpty) {
        missing.add(station.name);
        continue;
      }
      if (rosters.length != 1) {
        incomplete[station.name] = 'Keep only one schedule for this period.';
        continue;
      }
      final schedule = rosters.single;
      DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
      final start = day(schedule.startDate);
      final end = day(schedule.endDate);
      final count = end.difference(start).inDays + 1;
      final expected = {
        for (var i = 0; i < count; i++) start.add(Duration(days: i)),
      };
      final actual = schedule.days.map((d) => day(d.date)).toSet();
      if (count < 1 ||
          count > 32 ||
          schedule.days.length != count ||
          actual.length != count ||
          !actual.containsAll(expected) ||
          schedule.days.any((d) => d.entries.isEmpty)) {
        incomplete[station.name] = 'Complete the assignments for every day.';
      } else if (schedule.days.any(
        (d) => d.entries.any(
          (e) =>
              e.post == null || e.post!.trim().isEmpty || e.post == 'Undefined',
        ),
      )) {
        incomplete[station.name] = 'Assign a post to every duty.';
      } else {
        ready++;
      }
    }
    final ids = active.map((s) => s.id).toSet();
    final extra = schedules
        .where((s) => !ids.contains(s.stationId))
        .map((s) => s.stationName)
        .toSet()
        .toList();
    return ApprovalReadiness._(
      active.length,
      ready,
      missing,
      incomplete,
      extra,
    );
  }
}
