// services/duty_service.dart
// Derives each employee's ACTUAL duty for today from the stored
// schedules, instead of showing their preferred-station list.
//
// Rules (per the admin's request):
//   - Station Assignment = the station of the schedule the employee
//     appears in for the current period. If they are not in any active
//     schedule, the station is "Pending".
//   - Status = "On Duty" when they have an entry today, "Day Off" when
//     they are in an active schedule but have no entry today, and
//     "Unassigned" when they are not in any active schedule at all.
//   - "Absent" overrides the above once an emergency absence request for
//     today has been approved: the guard has been excused and (under the
//     approval flow) replaced. It reads "Absent (covered)" when a cover
//     is on record for the day, "Absent" while none is yet.
//   - "On Leave" overrides everything, including Absent: an approved
//     leave covering today means the employee is not reporting at all,
//     whatever the schedule or an absence record says.
import 'package:flutter/material.dart';

import '../models/absence_request.dart';
import '../models/leave_request.dart';
import '../models/replacement.dart';
import '../models/schedule.dart';
import 'api_service.dart';
import 'server_clock.dart';

enum DutyStatus {
  onDuty,
  dayOff,
  unassigned,
  absentCovered,
  absentUncovered,
  onLeave,
}

class DutyInfo {
  // Station the employee is actually assigned to for the current
  // schedule period; null when they have no active assignment.
  final String? station;
  final bool onDutyToday;

  // Set when an approved absence for today excuses this employee.
  final bool isAbsent;
  // Name of the guard covering this absence today, when one is on record.
  final String? coveredByName;

  // The approved leave covering today, when there is one. Not a flag —
  // the record itself, so screens can show its type and end date without
  // fetching the employee's leave history again.
  final LeaveRequest? leave;

  const DutyInfo({
    this.station,
    this.onDutyToday = false,
    this.isAbsent = false,
    this.coveredByName,
    this.leave,
  });

  bool get isOnLeave => leave != null;

  DutyStatus get status {
    // Leave outranks everything: approved leave means they are not
    // reporting, whatever the roster or an absence record says.
    if (leave != null) return DutyStatus.onLeave;
    // An approved absence wins over the schedule-derived status: the
    // guard's post may have already been handed to their cover.
    if (isAbsent) {
      return coveredByName != null
          ? DutyStatus.absentCovered
          : DutyStatus.absentUncovered;
    }
    if (station == null) return DutyStatus.unassigned;
    return onDutyToday ? DutyStatus.onDuty : DutyStatus.dayOff;
  }

  // What the Station Assignment column/field should display. Someone on
  // leave often has no roster to derive a station from, so their record's
  // own station stands in — "Unassigned" would read as a data problem
  // when the real answer is that they're away.
  String get stationLabel {
    if (station != null) return station!;
    final leaveStation = leave?.station;
    if (leaveStation != null && leaveStation.isNotEmpty) return leaveStation;
    return 'Pending';
  }

  String get statusLabel {
    switch (status) {
      case DutyStatus.onDuty:
        return 'On Duty';
      case DutyStatus.dayOff:
        return 'Day Off';
      case DutyStatus.unassigned:
        return 'Unassigned';
      case DutyStatus.absentCovered:
        return 'Absent (covered)';
      case DutyStatus.absentUncovered:
        return 'Absent';
      case DutyStatus.onLeave:
        return 'On Leave';
    }
  }

  // Longer form for detail screens: names the cover when there is one.
  String get statusDetailLabel {
    if (status == DutyStatus.onLeave && leave != null) {
      return 'On Leave — ${leave!.leaveType}, back on '
          '${LeaveRequest.formatShort(leave!.endDate)}';
    }
    if (status == DutyStatus.absentCovered && coveredByName != null) {
      return 'Absent — covered by $coveredByName';
    }
    if (status == DutyStatus.absentUncovered) {
      return 'Absent — no cover yet';
    }
    return statusLabel;
  }

  // Centralised status colour so every badge stays consistent.
  Color get statusColor {
    switch (status) {
      case DutyStatus.onDuty:
        return const Color(0xFF16A34A); // green
      case DutyStatus.dayOff:
        return const Color(0xFFDC2626); // red
      case DutyStatus.unassigned:
        return const Color(0xFF9E9E9E); // grey
      case DutyStatus.absentCovered:
      case DutyStatus.absentUncovered:
        return const Color(0xFFEA580C); // amber/orange
      case DutyStatus.onLeave:
        return const Color(0xFF0D9488); // teal
    }
  }
}

class DutyService {
  // Fetches every schedule (plus today's approved absences and applied
  // covers) and builds employeeId -> DutyInfo for today. Returns an empty
  // map when schedules can't be fetched, so callers can still render the
  // employee list (everything shows as Pending / Unassigned rather than
  // erroring out).
  static Future<Map<String, DutyInfo>> fetchDutyMap() async {
    final results = await Future.wait([
      ApiService.fetchSchedules(),
      ApiService.fetchAbsenceRequests(),
      ApiService.fetchReplacements(),
      ApiService.fetchActiveLeaves(),
    ]);

    final scheduleResult = results[0];
    // Leave is the one overlay that must survive a schedule failure:
    // someone on leave is on leave whether or not a roster loaded.
    final leaveResult = results[3];
    final activeLeaves = leaveResult["success"] == true
        ? (leaveResult["leaves"] as Map).cast<String, LeaveRequest>()
        : const <String, LeaveRequest>{};

    if (scheduleResult["success"] != true) {
      final duties = <String, DutyInfo>{};
      _overlayLeaves(duties, activeLeaves);
      return duties;
    }
    final List<Schedule> schedules = scheduleResult["schedules"];

    // Absences/covers are best-effort — a failure just means no one shows
    // as Absent, rather than blocking the whole map.
    final absenceResult = results[1];
    final approvedAbsences = absenceResult["success"] == true
        ? (absenceResult["requests"] as List)
            .cast<AbsenceRequest>()
            .where((r) => r.isApproved)
            .toList()
        : const <AbsenceRequest>[];

    final replacementResult = results[2];
    final replacements = replacementResult["success"] == true
        ? (replacementResult["replacements"] as List)
            .cast<AppliedReplacement>()
        : const <AppliedReplacement>[];

    return buildDutyMap(
      schedules,
      approvedAbsences: approvedAbsences,
      replacements: replacements,
      activeLeaves: activeLeaves,
    );
  }

  static Map<String, DutyInfo> buildDutyMap(
    List<Schedule> schedules, {
    List<AbsenceRequest> approvedAbsences = const [],
    List<AppliedReplacement> replacements = const [],
    Map<String, LeaveRequest> activeLeaves = const {},
  }) {
    final now = ServerClock.now();
    final today = DateTime(now.year, now.month, now.day);

    final duties = <String, DutyInfo>{};

    for (final schedule in schedules) {
      final start = _dateOnly(schedule.startDate);
      final end = _dateOnly(schedule.endDate);

      // Only schedules covering today count as the "current" assignment.
      if (today.isBefore(start) || today.isAfter(end)) continue;

      for (final day in schedule.days) {
        final isToday = _dateOnly(day.date) == today;

        for (final entry in day.entries) {
          final existing = duties[entry.employeeId];
          if (existing == null) {
            duties[entry.employeeId] = DutyInfo(
              station: schedule.stationName,
              onDutyToday: isToday,
            );
          } else {
            // If the employee shows up in more than one schedule, prefer
            // the station where they actually work today.
            duties[entry.employeeId] = DutyInfo(
              station: isToday ? schedule.stationName : existing.station,
              onDutyToday: existing.onDutyToday || isToday,
            );
          }
        }
      }
    }

    _overlayAbsences(duties, today, approvedAbsences, replacements);
    // Last, so it wins: an approved leave outranks both the roster and
    // any absence record for the same day.
    _overlayLeaves(duties, activeLeaves);
    return duties;
  }

  // Marks everyone with an approved leave covering today as On Leave,
  // keeping whatever station we derived. Employees who appear in no
  // schedule at all still get an entry here — otherwise someone on leave
  // with no current roster would fall through to "Unassigned", which is
  // exactly the wrong thing to tell an admin looking for them.
  static void _overlayLeaves(
    Map<String, DutyInfo> duties,
    Map<String, LeaveRequest> activeLeaves,
  ) {
    activeLeaves.forEach((employeeId, leave) {
      final existing = duties[employeeId];
      duties[employeeId] = DutyInfo(
        station: existing?.station,
        onDutyToday: false,
        isAbsent: existing?.isAbsent ?? false,
        coveredByName: existing?.coveredByName,
        leave: leave,
      );
    });
  }

  // Flags anyone with an approved absence for today as Absent, keeping the
  // station we already derived, and attaches the cover's name when one is
  // on record for that guard/day.
  static void _overlayAbsences(
    Map<String, DutyInfo> duties,
    DateTime today,
    List<AbsenceRequest> approvedAbsences,
    List<AppliedReplacement> replacements,
  ) {
    if (approvedAbsences.isEmpty) return;
    final todayIso = _iso(today);

    for (final absence in approvedAbsences) {
      if (absence.date != todayIso) continue;

      final coverName = _coverNameFor(replacements, absence.employeeId, today);
      final existing = duties[absence.employeeId];
      duties[absence.employeeId] = DutyInfo(
        station: existing?.station,
        onDutyToday: false,
        isAbsent: true,
        coveredByName: coverName,
      );
    }
  }

  static String? _coverNameFor(
    List<AppliedReplacement> replacements,
    String absentId,
    DateTime today,
  ) {
    for (final rep in replacements) {
      final repDate = rep.date;
      if (rep.absentEmployeeId == absentId &&
          repDate != null &&
          _dateOnly(repDate) == today &&
          rep.replacementEmployeeName.isNotEmpty) {
        return rep.replacementEmployeeName;
      }
    }
    return null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
