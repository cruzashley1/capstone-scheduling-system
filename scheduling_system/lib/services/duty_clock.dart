// services/duty_clock.dart
//
// Turns "what does the schedule say for today" into "what is this guard's
// situation RIGHT NOW". The guard dashboards used to read On Duty for the
// whole calendar day as soon as a duty existed for that date — a 0500H -
// 1400H guard still showed On Duty at 8pm, and could still file an
// emergency absence against a duty that had already finished.
//
// Statuses:
//   On Duty   — the wall clock is inside the duty's time window.
//   Awaiting  — the duty hasn't started yet (later today).
//   Off Shift — the duty finished; the guard is done for the day.
//   Day Off   — a day inside a published schedule with no duty at all.
//   Absent    — an APPROVED absence request excuses the duty. Overrides
//               the three time-based statuses above.
//   On Leave  — an APPROVED leave covers today. Overrides everything,
//               including Absent and a duty that is running: an approved
//               leave means this guard is not reporting at all.
//   Unassigned — no published schedule reaches today.
//
// Night (2100H - 0500H) and HG Night (1700H - 0500H) run past midnight,
// so resolving "now" also has to look at YESTERDAY's duty: at 0200H a
// guard who timed in at 2100H last night is still On Duty.
import 'package:flutter/material.dart';

import '../models/absence_request.dart';
import '../models/guard_shift.dart';
import '../models/leave_request.dart';
import 'server_clock.dart';

enum LiveDutyStatus {
  onDuty,
  awaiting,
  offShift,
  dayOff,
  absent,
  onLeave,
  unassigned,
}

@immutable
class LiveDutyState {
  final LiveDutyStatus status;

  // The duty this status is about — the one running, the one coming up,
  // or the one that just finished. Null on a day off / unassigned.
  final GuardShift? shift;

  // The approved leave covering today, when there is one. Carried on the
  // state so the duty card can name the leave and count down to the
  // return date without fetching anything of its own.
  final LeaveRequest? leave;

  // The instant this state was resolved for, so the card's clock and its
  // countdown never disagree.
  final DateTime now;

  const LiveDutyState({
    required this.status,
    required this.now,
    this.shift,
    this.leave,
  });

  bool get isOnDuty => status == LiveDutyStatus.onDuty;
  bool get isDayOff => status == LiveDutyStatus.dayOff;
  bool get isAbsent => status == LiveDutyStatus.absent;
  bool get isOnLeave => status == LiveDutyStatus.onLeave;

  // True once the duty this state points at is over.
  bool get isFinished => status == LiveDutyStatus.offShift;

  // True once this state's duty is inside the emergency-absence lock-out:
  // the last hour before time-in, the duty itself, and everything after.
  // A guard about to walk onto post can no longer call in absent.
  bool get isPastAbsenceCutoff {
    final s = shift;
    return s != null && DutyClock.isPastAbsenceCutoff(s, now);
  }

  String get label {
    switch (status) {
      case LiveDutyStatus.onDuty:
        return 'On Duty';
      case LiveDutyStatus.awaiting:
        return 'Awaiting';
      case LiveDutyStatus.offShift:
        return 'Off Shift';
      case LiveDutyStatus.dayOff:
        return 'Day Off';
      case LiveDutyStatus.absent:
        return 'Absent';
      case LiveDutyStatus.onLeave:
        return 'On Leave';
      case LiveDutyStatus.unassigned:
        return 'Unassigned';
    }
  }

  // Tuned to stay legible on the blue gradient Today's Duty card, where
  // every one of these is drawn as text on a 20%-opacity chip.
  Color get color {
    switch (status) {
      case LiveDutyStatus.onDuty:
        return const Color(0xFF22C55E); // green
      case LiveDutyStatus.awaiting:
        return const Color(0xFFFBBF24); // amber
      case LiveDutyStatus.offShift:
        return const Color(0xFF94A3B8); // slate
      case LiveDutyStatus.dayOff:
        return const Color(0xFF38BDF8); // sky
      case LiveDutyStatus.absent:
        return const Color(0xFFFB923C); // orange
      case LiveDutyStatus.onLeave:
        return const Color(0xFF2DD4BF); // teal — light enough for the chip
      case LiveDutyStatus.unassigned:
        return const Color(0xFFCBD5E1); // light slate
    }
  }

  IconData get icon {
    switch (status) {
      case LiveDutyStatus.onDuty:
        return Icons.shield_outlined;
      case LiveDutyStatus.awaiting:
        return Icons.schedule_rounded;
      case LiveDutyStatus.offShift:
        return Icons.task_alt_rounded;
      case LiveDutyStatus.dayOff:
        return Icons.coffee_outlined;
      case LiveDutyStatus.absent:
        return Icons.event_busy_outlined;
      case LiveDutyStatus.onLeave:
        return Icons.beach_access_rounded;
      case LiveDutyStatus.unassigned:
        return Icons.help_outline_rounded;
    }
  }

  // Big line on the duty card. Leave speaks before the shift does: a
  // guard on approved leave isn't reporting, so naming a duty here would
  // be telling them to.
  String get headline {
    if (status == LiveDutyStatus.onLeave) {
      return leave?.leaveType ?? 'On Leave';
    }
    if (shift != null) return shift!.title;
    if (status == LiveDutyStatus.dayOff) return 'Rest Day';
    return 'No Published Schedule';
  }

  // Second line — the duty's time window, or why there isn't one.
  String get subline {
    if (status == LiveDutyStatus.onLeave) {
      return leave?.rangeLabel ?? 'You are on approved leave';
    }
    if (shift != null) {
      final range = shift!.timeRange;
      return range.isEmpty ? 'Times not set' : range;
    }
    if (status == LiveDutyStatus.dayOff) return 'Enjoy your day off!';
    return 'Your schedule will appear here once published.';
  }

  // Why this duty's hours are not the post's, when they aren't.
  //
  // A guard picked up to cover an absence at short notice is given an
  // hour to get into uniform, sort out food and travel, so their duty
  // slides off the post's own window (see prep_window.dart). Their
  // dashboard then shows 1000H - 1900H for a post everyone else calls
  // an 0500H one, and the first thing they will do is wonder whether
  // something is wrong. This is the sentence that answers it.
  //
  // Null on every ordinary duty, which is nearly all of them.
  String? get retimedNote {
    final s = shift;
    if (s == null || !s.isPrepAdjusted) return null;
    if (status == LiveDutyStatus.onLeave ||
        status == LiveDutyStatus.absent) {
      return null;
    }
    return 'Covering at short notice — the post itself runs '
        '${s.originalWindow!.range}';
  }

  // Live countdown under the time window. Recomputed on every tick.
  String? get progressNote {
    // Leave counts down in days, not hours, and has no shift to hang off.
    if (status == LiveDutyStatus.onLeave) {
      final l = leave;
      if (l == null) return null;
      final left = l.daysRemaining;
      return left <= 1
          ? 'Back on duty tomorrow'
          : 'Back on duty ${LeaveRequest.formatShort(l.endDate)} · '
              '$left days left';
    }

    final s = shift;
    if (s == null) return null;

    switch (status) {
      case LiveDutyStatus.onDuty:
        final end = s.endsAt;
        if (end == null) return null;
        return 'Time out in ${_humanize(end.difference(now))}';
      case LiveDutyStatus.awaiting:
        final start = s.startsAt;
        if (start == null) return null;
        return 'Time in in ${_humanize(start.difference(now))}';
      case LiveDutyStatus.offShift:
        final end = s.endsAt;
        if (end == null) return null;
        return 'Timed out ${_humanize(now.difference(end))} ago';
      case LiveDutyStatus.absent:
        return 'Excused from this duty';
      case LiveDutyStatus.onLeave:
      case LiveDutyStatus.dayOff:
      case LiveDutyStatus.unassigned:
        return null;
    }
  }

  // 0..1 through the duty window — drives the on-duty progress bar.
  double? get progress {
    final s = shift;
    if (s == null || status != LiveDutyStatus.onDuty) return null;
    final start = s.startsAt;
    final total = s.length;
    if (start == null || total == null || total.inMinutes <= 0) return null;
    final done = now.difference(start).inSeconds / total.inSeconds;
    return done.clamp(0.0, 1.0);
  }

  // Which duty day an absence filed "for now" belongs to. During an
  // overnight shift that's YESTERDAY, not today.
  DateTime get relevantDutyDate {
    final s = shift;
    if (s != null) return DutyClock.dateOnly(s.date);
    return DutyClock.dateOnly(now);
  }

  static String _humanize(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return 'less than a minute';
  }
}

class DutyClock {
  // How long before time-in an emergency absence stops being fileable.
  // A guard who is an hour away from post has to be counted on to show
  // up — past this point the admin can no longer find a replacement in
  // time, so the request has to be raised with the head guard instead.
  static const Duration absenceCutoff = Duration(hours: 1);

  // The last instant an absence may be filed against [shift] — one hour
  // before its time-in. Null when the shift name carries no time range.
  static DateTime? absenceDeadline(GuardShift shift) =>
      shift.startsAt?.subtract(absenceCutoff);

  // The approved leave covering [at], if any. Compared as ISO strings
  // against the date only, so a leave that ends today still counts for
  // the whole of today rather than expiring at midnight this morning.
  static LeaveRequest? activeLeave(List<LeaveRequest> leaves, {DateTime? at}) {
    final todayIso = iso(dateOnly(at ?? ServerClock.now()));
    for (final l in leaves) {
      if (!l.isApproved) continue;
      if (l.startDate.compareTo(todayIso) <= 0 &&
          l.endDate.compareTo(todayIso) >= 0) {
        return l;
      }
    }
    return null;
  }

  // The next approved leave that hasn't started yet — what the dashboard
  // card shows so a guard isn't surprised by their own leave.
  static LeaveRequest? upcomingLeave(List<LeaveRequest> leaves,
      {DateTime? at}) {
    final todayIso = iso(dateOnly(at ?? ServerClock.now()));
    final upcoming = leaves
        .where((l) => l.isApproved && l.startDate.compareTo(todayIso) > 0)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  // True once [now] has reached that deadline. Because the deadline sits
  // before time-in, this also covers a duty already running and one
  // already finished.
  static bool isPastAbsenceCutoff(GuardShift shift, DateTime now) {
    final deadline = absenceDeadline(shift);
    return deadline != null && !now.isBefore(deadline);
  }

  // Resolves the guard's status at [at] (defaults to now) from their
  // published duties, the periods those duties live in, their own absence
  // requests and their approved leave.
  static LiveDutyState resolve({
    required List<GuardShift> shifts,
    required List<GuardPeriod> periods,
    List<AbsenceRequest> absenceRequests = const [],
    List<LeaveRequest> leaves = const [],
    DateTime? at,
  }) {
    final now = at ?? ServerClock.now();
    final today = dateOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));

    // 0. Approved leave wins outright. It is checked before the clock so
    // a roster generated before the leave was granted can't put this
    // guard back on duty — the leave is the later, and stronger, fact.
    final onLeave = activeLeave(leaves, at: now);
    if (onLeave != null) {
      return LiveDutyState(
        status: LiveDutyStatus.onLeave,
        leave: onLeave,
        now: now,
      );
    }

    final approvedDates = <String>{
      for (final r in absenceRequests)
        if (r.isApproved) r.date,
    };

    // Duties that can touch this instant: today's, plus last night's if it
    // runs past midnight.
    final relevant = shifts.where((s) {
      final d = dateOnly(s.date);
      if (d == today) return true;
      return d == yesterday && s.crossesMidnight;
    }).toList();

    // 1. A duty running right now beats everything else.
    for (final s in relevant) {
      if (s.isActiveAt(now)) {
        return _withAbsence(s, now, approvedDates, LiveDutyStatus.onDuty);
      }
    }

    // 2. A duty still ahead — the soonest one.
    final upcoming = relevant.where((s) => s.startsAfter(now)).toList()
      ..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
    if (upcoming.isNotEmpty) {
      return _withAbsence(
          upcoming.first, now, approvedDates, LiveDutyStatus.awaiting);
    }

    // 3. A duty already finished — the most recent one, so a guard who
    // came off an overnight post at 0500H reads Off Shift, not Day Off.
    final finished = relevant.where((s) => s.hasEndedBy(now)).toList()
      ..sort((a, b) => b.endsAt!.compareTo(a.endsAt!));
    if (finished.isNotEmpty) {
      return _withAbsence(
          finished.first, now, approvedDates, LiveDutyStatus.offShift);
    }

    // 3b. A duty today whose shift name has no time range on file. We
    // can't place it on the clock, so fall back to the old behaviour and
    // call it On Duty rather than hiding the duty entirely.
    for (final s in relevant) {
      if (dateOnly(s.date) == today && s.startsAt == null) {
        return _withAbsence(s, now, approvedDates, LiveDutyStatus.onDuty);
      }
    }

    // 4. Scheduled, but nothing on today.
    for (final p in periods) {
      if (p.contains(today)) {
        return LiveDutyState(status: LiveDutyStatus.dayOff, now: now);
      }
    }

    return LiveDutyState(status: LiveDutyStatus.unassigned, now: now);
  }

  // An approved absence excuses the duty, whatever the clock says.
  static LiveDutyState _withAbsence(
    GuardShift shift,
    DateTime now,
    Set<String> approvedDates,
    LiveDutyStatus timeBased,
  ) {
    final excused = approvedDates.contains(iso(dateOnly(shift.date)));
    return LiveDutyState(
      status: excused ? LiveDutyStatus.absent : timeBased,
      shift: shift,
      now: now,
    );
  }

  // Which duty day the guard is standing RIGHT NOW, for screens that have
  // to pick one roster date. Normally today; during the after-midnight
  // tail of an overnight duty (Night 2100H - 0500H, HG Night 1700H -
  // 0500H) it is YESTERDAY, because that is the shift they are still on.
  //
  // Deliberately narrower than LiveDutyState.relevantDutyDate, which
  // also points back at an overnight duty that has already ENDED — using
  // that here would leave a head guard looking at last night's roster for
  // the whole of a rest day. This only rolls back while the duty is
  // genuinely still running.
  static DateTime activeDutyDate({
    required List<GuardShift> shifts,
    DateTime? at,
  }) {
    final now = at ?? ServerClock.now();
    final today = dateOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final s in shifts) {
      if (dateOnly(s.date) != yesterday) continue;
      if (!s.crossesMidnight) continue;
      if (s.isActiveAt(now)) return yesterday;
    }
    return today;
  }

  // The duty days an emergency absence may still be filed for: time-in is
  // more than [absenceCutoff] away, and the guard hasn't already filed for
  // that day. Single source of truth for both the dashboard card and the
  // form. A duty that has started — or finished — is past the cutoff by
  // definition, so it drops out here too.
  static List<DateTime> fileableDates({
    required List<GuardShift> shifts,
    List<AbsenceRequest> existingRequests = const [],
    DateTime? at,
  }) {
    final now = at ?? ServerClock.now();
    final today = dateOnly(now);
    final requested = existingRequests.map((r) => r.date).toSet();

    final dates = <DateTime>{};
    for (final s in shifts) {
      final d = dateOnly(s.date);
      if (requested.contains(iso(d))) continue;

      final deadline = absenceDeadline(s);
      if (deadline == null) {
        // No time range on file — fall back to the whole day.
        if (d.isBefore(today)) continue;
      } else if (!now.isBefore(deadline)) {
        continue; // inside the lock-out, on duty, or already done
      }
      dates.add(d);
    }
    return dates.toList()..sort();
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // '2042H' — the military format the schedules already use.
  static String military(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}H';

  // '8:42:07 PM' — the ticking clock on the dashboard.
  static String clock12(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}
