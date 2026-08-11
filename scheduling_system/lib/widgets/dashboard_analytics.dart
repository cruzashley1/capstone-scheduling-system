// widgets/dashboard_analytics.dart
//
// The dashboard's analytics band — three panels reading the data the
// summary cards can't say anything about.
//
//   Post Coverage    of every post the 25 active stations need manned
//                    today, how many actually have a guard on them, and
//                    WHERE the gap is: a hole inside a published
//                    schedule, or a station nobody has scheduled at all.
//
//   Attendance       present vs absent across the head guard reports
//                    actually filed, by reporting day.
//
//   Schedule Health  what the generator had to bend, aggregated across
//                    every run, grouped by the section the fix lives in.
//
// All three compute from lists the dashboard already fetches, so none
// costs an extra request.
//
// LAYOUT
//
// Each panel splits into a READING half and a PLOT half. The reading
// half is the one figure the panel is about plus a rail of supporting
// numbers, right-aligned on tabular figures so they scan as a column.
// The plot half is the chart. On a wide dashboard Coverage sets them
// side by side across one full-width card, divided by a hairline; below
// ~720px inside the card they stack and the rail lies down into a strip.
// Attendance and Schedule Health are half-width, so they always stack.
//
// WHY COVERAGE IS MEASURED AGAINST ALL ACTIVE STATIONS
//
// Measuring only the stations that HAVE a published schedule reports
// 100% every time — the generator fills what it is asked to fill, so
// that ratio is a tautology and reads like a hardcoded number. The
// operation's real question is "of the posts that need manning today,
// how many are manned", and against all 25 stations that is currently
// nearer 38%. The panel shows both: the headline is the operational
// number, and the split underneath says how much of the shortfall is
// unscheduled stations rather than gaps in a roster.
//
// WHY SCHEDULE HEALTH OPENS
//
// The panel used to report two different things that looked like one:
// the headline counted notes by SEVERITY ("7 need a look") while the
// bars counted them by CATEGORY, so no arithmetic connected the number
// to the chart and the panel could not be read, only glanced at. Now
// each category bar is stacked by severity — the red and amber lengths
// across all bars ARE the headline — and every row opens the notes
// behind it, because a count of compromises is useless without the
// sentence saying which post nobody was assigned to.
//
// COLOR
//
// Coverage bars are an ORDINAL ramp — manned -> unfilled -> unscheduled
// is a sequence, so it takes one hue in monotone lightness steps
// (validated: monotone L, adjacent dL >= 0.06, light end 2.01:1 on
// white). Attendance is two named states, so it takes the reserved
// status pair, which clears CVD separation at dE 8.6 and normal vision
// at 32.0. Schedule Health's segments are the three severities, which
// are states as well: #DC2626 / #CA8A04 / #0369A1 clears at dE 10.0
// under deuteranopia and 19.2 under normal vision, with the amber's
// 2.86:1 on white carried by the count beside every bar and the legend
// naming all three.
//
// Note the app's usual amber #EA580C is deliberately NOT used beside
// #DC2626 here: the pair measures dE 8.7 under normal vision, under the
// 15 floor, so the two would be hard to tell apart. The severity amber
// the note TILES wear (#D97706, from NoteSeverity.color) is out for the
// same reason — dE 14.4 against #DC2626, a fail. Chart marks therefore
// take #CA8A04 while the tiles inside the breakdown keep the model's
// own colour: one is a mark read by length, the other is chrome around
// a sentence that already names its severity.

import 'package:flutter/material.dart';

import '../models/attendance_report.dart';
import '../models/schedule.dart';
import '../models/schedule_note.dart';
import '../models/station.dart';

const Color _kInk = Color(0xFF1E293B);
const Color _kBody = Color(0xFF334155);
const Color _kLine = Color(0xFFE8EDF5);
const Color _kSurface = Colors.white;

// Ordinal ramp for the coverage bars, darkest = manned.
const Color _kManned = Color(0xFF1034A6);
const Color _kUnfilled = Color(0xFF4F7BD9);
const Color _kUnscheduled = Color(0xFF9CB8E8);

// Reserved status scale. Don't swap one of these for a nearby hue
// without re-running the separation check.
const Color _kGood = Color(0xFF059669);
const Color _kWarn = Color(0xFFCA8A04);
const Color _kAbsent = Color(0xFFDC2626);
const Color _kInfo = Color(0xFF0369A1);

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The colour a severity wears as a CHART MARK. Not the same as
/// NoteSeverity.color — see the COLOR note at the top of the file.
Color _severityMark(NoteSeverity severity) {
  switch (severity) {
    case NoteSeverity.blocker:
      return _kAbsent;
    case NoteSeverity.warning:
      return _kWarn;
    case NoteSeverity.info:
      return _kInfo;
  }
}

/// 1830 -> "1,830"
String _comma(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 0.384 -> "38%", 1.0 -> "100%". Keeps a decimal only where rounding
/// would otherwise claim a clean 100%.
String _pct(double rate) {
  final v = rate * 100;
  if (v >= 99.95 && rate < 1.0) return '99.9%';
  return '${v.toStringAsFixed(0)}%';
}

/// 'Aug 10'
String _shortDate(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}';

/// 'Aug 10, 2026'
String _longDate(DateTime d) => '${_shortDate(d)}, ${d.year}';

String _plural(int n, String one, [String? many]) =>
    n == 1 ? one : (many ?? '${one}s');

// ---------------------------------------------------------------------
// Coverage
// ---------------------------------------------------------------------

/// One shift's posts today, split three ways.
class ShiftCoverage {
  final String label;

  /// Guards actually on post today.
  final int manned;

  /// Posts required by the stations that DO have a published schedule
  /// covering today.
  final int scheduledDemand;

  /// Posts required across every active station, scheduled or not.
  final int totalDemand;

  const ShiftCoverage({
    required this.label,
    required this.manned,
    required this.scheduledDemand,
    required this.totalDemand,
  });

  /// Posts inside a published schedule that still have nobody on them.
  int get unfilled =>
      scheduledDemand > manned ? scheduledDemand - manned : 0;

  /// Posts at stations with no published schedule at all.
  int get unscheduled =>
      totalDemand > scheduledDemand ? totalDemand - scheduledDemand : 0;

  double get rate => totalDemand == 0 ? 0 : manned / totalDemand;
}

class CoverageBreakdown {
  final List<ShiftCoverage> shifts;
  final int scheduledStations;
  final int unscheduledStations;

  const CoverageBreakdown({
    required this.shifts,
    required this.scheduledStations,
    required this.unscheduledStations,
  });

  int get manned => shifts.fold(0, (s, c) => s + c.manned);
  int get scheduledDemand => shifts.fold(0, (s, c) => s + c.scheduledDemand);
  int get totalDemand => shifts.fold(0, (s, c) => s + c.totalDemand);
  int get unfilled => shifts.fold(0, (s, c) => s + c.unfilled);
  int get unscheduled => shifts.fold(0, (s, c) => s + c.unscheduled);

  int get activeStations => scheduledStations + unscheduledStations;

  /// Manned against every post the operation needs today.
  double get rate => totalDemand == 0 ? 0 : manned / totalDemand;

  /// Manned against only what was actually scheduled — how well the
  /// generator filled the rosters it produced.
  double get scheduledRate =>
      scheduledDemand == 0 ? 0 : manned / scheduledDemand;

  bool get hasData => totalDemand > 0;
}

/// Which required-headcount bucket a schedule entry's shift counts
/// toward.
///
/// Head guards carry their own shift labels — 'HG Day' and 'HG Night' —
/// but a station's per-shift required numbers INCLUDE the head guard
/// slot (Morning 7 means the day head guard plus 6 other posts). So
/// HG Day counts toward Morning and HG Night toward Night, or every
/// station reads two posts short.
///
/// Afternoon deliberately takes nothing: it has no head guard slot of
/// its own, because the day HG's 12-hour duty already covers it.
String? _shiftBucket(String shift) {
  switch (shift) {
    case 'Morning':
    case 'HG Day':
    case 'Day': // pre-split schedules
      return 'morning';
    case 'Afternoon':
      return 'afternoon';
    case 'Night':
    case 'HG Night':
      return 'night';
    default:
      return null;
  }
}

/// Coverage for [today].
///
/// Unlike the station cards, this does NOT fall back to the most recent
/// published schedule when none covers today — a number captioned
/// "today" must not quietly report a fortnight ago.
CoverageBreakdown computeCoverage({
  required List<Station> stations,
  required List<Schedule> schedules,
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);

  final published =
      schedules.where((s) => s.status == ScheduleStatus.published).toList();

  const buckets = ['morning', 'afternoon', 'night'];
  final manned = {for (final b in buckets) b: 0};
  final scheduledDemand = {for (final b in buckets) b: 0};
  final totalDemand = {for (final b in buckets) b: 0};
  var scheduled = 0;
  var unscheduled = 0;

  for (final station in stations) {
    if (!station.isActive) continue;

    // A station with no per-shift breakdown has no requirement to
    // measure against, so it contributes no demand either way.
    if (!station.hasShiftBreakdown) continue;

    for (final b in buckets) {
      totalDemand[b] = totalDemand[b]! + station.requiredFor(b);
    }

    Schedule? covering;
    for (final s in published) {
      if (s.stationId != station.id) continue;
      if (day.isBefore(s.startDate) || day.isAfter(s.endDate)) continue;
      covering = s;
      break;
    }

    if (covering == null) {
      unscheduled++;
      continue;
    }
    scheduled++;

    for (final b in buckets) {
      scheduledDemand[b] = scheduledDemand[b]! + station.requiredFor(b);
    }

    for (final d in covering.days) {
      if (d.date.year != day.year ||
          d.date.month != day.month ||
          d.date.day != day.day) {
        continue;
      }
      for (final entry in d.entries) {
        final bucket = _shiftBucket(entry.shift);
        if (bucket != null) manned[bucket] = manned[bucket]! + 1;
      }
    }
  }

  return CoverageBreakdown(
    shifts: [
      for (final b in buckets)
        ShiftCoverage(
          label: '${b[0].toUpperCase()}${b.substring(1)}',
          manned: manned[b]!,
          scheduledDemand: scheduledDemand[b]!,
          totalDemand: totalDemand[b]!,
        ),
    ],
    scheduledStations: scheduled,
    unscheduledStations: unscheduled,
  );
}

// ---------------------------------------------------------------------
// Attendance
// ---------------------------------------------------------------------

/// One day's attendance, summed across every report filed for it.
class AttendanceDay {
  final DateTime date;
  final int present;
  final int absent;
  final int reports;

  const AttendanceDay({
    required this.date,
    required this.present,
    required this.absent,
    required this.reports,
  });

  int get total => present + absent;
  double get rate => total == 0 ? 0 : present / total;

  /// 'Aug 9'
  String get shortLabel => _shortDate(date);
}

class AttendanceTrend {
  /// Oldest first. These are REPORTING days — days a head guard
  /// actually filed — not calendar days. Plotting calendar days would
  /// draw a run of empty slots for days nobody reported and read as a
  /// collapse in attendance rather than an absence of data.
  final List<AttendanceDay> days;

  final int present;
  final int absent;
  final int reports;

  const AttendanceTrend({
    required this.days,
    required this.present,
    required this.absent,
    required this.reports,
  });

  int get total => present + absent;
  double get rate => total == 0 ? 0 : present / total;
  bool get hasData => days.isNotEmpty;

  /// Tallest column, for scaling the plot.
  int get busiestDay =>
      days.isEmpty ? 0 : days.map((d) => d.total).reduce((a, b) => a > b ? a : b);

  int get daysWithAbsence => days.where((d) => d.absent > 0).length;
}

/// Groups the filed reports into reporting days, newest [maxDays] kept.
AttendanceTrend computeAttendanceTrend(
  List<AttendanceReport> reports, {
  int maxDays = 14,
}) {
  final byDate = <String, List<AttendanceReport>>{};
  for (final report in reports) {
    final parsed = DateTime.tryParse(report.date);
    if (parsed == null) continue;
    byDate.putIfAbsent(report.date, () => []).add(report);
  }

  final keys = byDate.keys.toList()..sort(); // ISO dates sort correctly
  final kept = keys.length > maxDays
      ? keys.sublist(keys.length - maxDays)
      : keys;

  final days = <AttendanceDay>[];
  for (final key in kept) {
    final forDate = byDate[key]!;
    var present = 0;
    var absent = 0;
    for (final report in forDate) {
      present += report.presentCount;
      absent += report.absentCount;
    }
    days.add(AttendanceDay(
      date: DateTime.parse(key),
      present: present,
      absent: absent,
      reports: forDate.length,
    ));
  }

  return AttendanceTrend(
    days: days,
    present: days.fold(0, (s, d) => s + d.present),
    absent: days.fold(0, (s, d) => s + d.absent),
    reports: days.fold(0, (s, d) => s + d.reports),
  );
}

// ---------------------------------------------------------------------
// Schedule health
// ---------------------------------------------------------------------

/// One filed note, plus the run that filed it.
///
/// The panel aggregates across every schedule, so a note on its own has
/// lost the one thing that makes it actionable — WHICH roster and which
/// fortnight it belongs to. The breakdown needs that back, so the tally
/// carries whole notes rather than a bare count.
class HealthNote {
  final String scheduleId;
  final String stationName;
  final DateTime startDate;
  final DateTime endDate;
  final ScheduleNote note;

  const HealthNote({
    required this.scheduleId,
    required this.stationName,
    required this.startDate,
    required this.endDate,
    required this.note,
  });

  NoteCategory get category => note.category;
  NoteSeverity get severity => note.severity;

  /// 'Aug 4 – Aug 18'
  String get periodLabel => '${_shortDate(startDate)} – ${_shortDate(endDate)}';
}

/// Worst first, then oldest run first, then by station — so two refreshes
/// of the same data list the notes in the same order.
int _compareHealthNotes(HealthNote a, HealthNote b) {
  final bySeverity = a.severity.index - b.severity.index;
  if (bySeverity != 0) return bySeverity;
  final byStart = a.startDate.compareTo(b.startDate);
  if (byStart != 0) return byStart;
  return a.stationName.compareTo(b.stationName);
}

class NoteTally {
  final NoteCategory category;

  /// Every note filed under this category, worst first.
  final List<HealthNote> notes;

  const NoteTally(this.category, this.notes);

  int get count => notes.length;

  int severityCount(NoteSeverity severity) =>
      notes.where((n) => n.severity == severity).length;

  /// The part of this bar that is asking for something to be done.
  int get actionable =>
      notes.where((n) => n.severity != NoteSeverity.info).length;

  /// Loudest severity in the category — what the row's badge reads.
  NoteSeverity get worst => notes.isEmpty
      ? NoteSeverity.info
      : notes.map((n) => n.severity).reduce((a, b) => a.index <= b.index ? a : b);

  /// How many distinct stations are represented, so a row can say
  /// whether 12 notes are one station's problem or twelve stations'.
  int get stationCount => notes.map((n) => n.stationName).toSet().length;
}

class ScheduleHealth {
  final List<NoteTally> tallies; // biggest first

  /// Every note across every run, worst first. What the breakdown reads.
  final List<HealthNote> notes;

  final int actionable; // severity != info
  final int total;
  final int scheduleCount;

  const ScheduleHealth({
    required this.tallies,
    required this.notes,
    required this.actionable,
    required this.total,
    required this.scheduleCount,
  });

  bool get hasData => total > 0;
  int get maxCount => tallies.isEmpty ? 0 : tallies.first.count;

  int severityCount(NoteSeverity severity) =>
      notes.where((n) => n.severity == severity).length;

  int get stationCount => notes.map((n) => n.stationName).toSet().length;
}

ScheduleHealth computeScheduleHealth(List<Schedule> schedules) {
  final notes = <HealthNote>[];
  for (final schedule in schedules) {
    for (final note in schedule.notes) {
      notes.add(HealthNote(
        scheduleId: schedule.id,
        // A note can name its own station; fall back to the schedule's.
        stationName: note.station ?? schedule.stationName,
        startDate: schedule.startDate,
        endDate: schedule.endDate,
        note: note,
      ));
    }
  }
  notes.sort(_compareHealthNotes);

  final byCategory = <NoteCategory, List<HealthNote>>{};
  for (final note in notes) {
    byCategory.putIfAbsent(note.category, () => []).add(note);
  }

  final tallies = byCategory.entries
      .map((e) => NoteTally(e.key, e.value))
      .toList()
    // Biggest first; ties keep the enum's own order so equal categories
    // don't reshuffle between refreshes.
    ..sort((a, b) {
      final byCount = b.count - a.count;
      return byCount != 0 ? byCount : a.category.index - b.category.index;
    });

  return ScheduleHealth(
    tallies: tallies,
    notes: notes,
    actionable: actionableCount(notes.map((n) => n.note).toList()),
    total: notes.length,
    scheduleCount: schedules.where((s) => s.notes.isNotEmpty).length,
  );
}

// ---------------------------------------------------------------------
// The section
// ---------------------------------------------------------------------

/// The analytics band, sat between the summary cards and Recent
/// Stations. Purely additive — it reads the lists the dashboard already
/// holds and navigates into screens that already exist.
class DashboardAnalytics extends StatelessWidget {
  final List<Station> stations;
  final List<Schedule> schedules;
  final List<AttendanceReport> attendanceReports;
  final bool isLoading;
  final DateTime today;
  final VoidCallback? onOpenSchedules;
  final VoidCallback? onOpenReports;

  const DashboardAnalytics({
    super.key,
    required this.stations,
    required this.schedules,
    required this.attendanceReports,
    required this.isLoading,
    required this.today,
    this.onOpenSchedules,
    this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    final coverage = computeCoverage(
      stations: stations,
      schedules: schedules,
      today: today,
    );
    final attendance = computeAttendanceTrend(attendanceReports);
    final health = computeScheduleHealth(schedules);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Operations Analytics',
          subtitle: 'Read live from the stations, schedules and reports '
              'already on this dashboard',
          trailing: _AsOfPill(today: today),
        ),
        const SizedBox(height: 16),

        // Coverage leads and takes the full width — it carries the most
        // information and the one number the band is about.
        _CoveragePanel(coverage: coverage, isLoading: isLoading),
        const SizedBox(height: 20),

        LayoutBuilder(
          builder: (context, constraints) {
            final attendancePanel = _AttendancePanel(
              trend: attendance,
              isLoading: isLoading,
              onOpenReports: onOpenReports,
            );
            final healthPanel = _HealthPanel(
              health: health,
              isLoading: isLoading,
              onOpenSchedules: onOpenSchedules,
            );

            if (constraints.maxWidth <= 1000) {
              return Column(
                children: [
                  attendancePanel,
                  const SizedBox(height: 20),
                  healthPanel,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: attendancePanel),
                  const SizedBox(width: 20),
                  Expanded(child: healthPanel),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 34,
          decoration: BoxDecoration(
            color: _kManned,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

/// The day everything captioned "today" is actually about. Spelled out
/// so a stale tab can't quietly pass yesterday's coverage off as now.
class _AsOfPill extends StatelessWidget {
  final DateTime today;

  const _AsOfPill({required this.today});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _kManned.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kManned.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.today_outlined, size: 14, color: _kManned),
          const SizedBox(width: 7),
          Text(
            _longDate(today),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _kManned,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared card shell.
class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  /// A quiet line under the plot — how to read it, or how to open it.
  final String? footnote;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 8),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 20),
          child,
          if (footnote != null) ...[
            const SizedBox(height: 14),
            Text(
              footnote!,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelLink extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  const _PanelLink({required this.label, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: const TextStyle(fontSize: 12));
    final style = TextButton.styleFrom(
      foregroundColor: _kManned,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    if (icon == null) {
      return TextButton(onPressed: onPressed, style: style, child: text);
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 15),
      label: text,
    );
  }
}

class _PanelPlaceholder extends StatelessWidget {
  final Widget child;
  const _PanelPlaceholder({required this.child});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 170, child: Center(child: child));
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
        ),
      );
}

/// A colour key. Present for every chart carrying two or more meanings,
/// so identity never rests on colour recall alone. An item may carry its
/// own total, which is what lets the severity key double as the count
/// the headline is drawn from.
class _LegendItem {
  final Color color;
  final String label;
  final String? value;

  const _LegendItem(this.color, this.label, [this.value]);
}

class _Legend extends StatelessWidget {
  final List<_LegendItem> items;

  const _Legend(this.items);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 7,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              if (item.value != null) ...[
                Text(
                  item.value!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                item.label,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Reading half: the hero figure and its supporting numbers
// ---------------------------------------------------------------------

/// The one figure a panel is about.
class _Hero extends StatelessWidget {
  final String value;
  final String caption;
  final double valueSize;
  final Color? valueColor;

  const _Hero({
    required this.value,
    required this.caption,
    this.valueSize = 48,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: valueSize,
            fontWeight: FontWeight.bold,
            color: valueColor ?? _kInk,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 7),
        Text(
          caption,
          style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

/// One supporting number. The label stays on ONE line.
class _Stat {
  final String value;
  final String label;
  final Color? color;

  const _Stat(this.value, this.label, [this.color]);
}

/// Supporting numbers as a COLUMN — values right-aligned on tabular
/// figures so the digits line up and the eye can run down them, labels
/// hanging off to the right. This is the wide-layout form, where the
/// rail sits under the hero in its own column.
class _StatRail extends StatelessWidget {
  final List<_Stat> stats;

  const _StatRail(this.stats);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stats.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: i == 0 ? _kLine : const Color(0xFFF3F6FB)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    stats[i].value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: stats[i].color ?? _kInk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stats[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The same numbers laid down into a strip, for the stacked layout and
/// for the half-width panels. Value over label rather than beside it:
/// a 15px number and an 11.5px label on one line leave the captions
/// floating at different depths and reading as a mistake.
class _StatStrip extends StatelessWidget {
  final List<_Stat> stats;

  const _StatStrip(this.stats);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kLine)),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 12,
        children: [
          for (final stat in stats)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: stat.color ?? _kInk,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Coverage panel
// ---------------------------------------------------------------------

class _CoveragePanel extends StatelessWidget {
  final CoverageBreakdown coverage;
  final bool isLoading;

  /// Below this the reading half and the plot half stack instead of
  /// sitting side by side.
  static const double _splitAt = 720;

  const _CoveragePanel({required this.coverage, required this.isLoading});

  List<_Stat> get _stats => [
        _Stat(
          '${coverage.scheduledStations}/${coverage.activeStations}',
          'stations scheduled',
        ),
        _Stat(
          _comma(coverage.unfilled),
          'posts unfilled',
          coverage.unfilled > 0 ? _kWarn : _kGood,
        ),
        _Stat(
          _comma(coverage.unscheduled),
          'posts unscheduled',
          coverage.unscheduled > 0 ? _kWarn : _kGood,
        ),
        _Stat(_pct(coverage.scheduledRate), 'filled where scheduled'),
      ];

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Post Coverage — Today',
      subtitle: 'Every post the ${coverage.activeStations} active stations '
          'need manned today, and how many actually have a guard on them',
      footnote: coverage.hasData
          ? 'Measured against every active station, not only the ones with a '
              'schedule — an unscheduled station is a real gap in cover, not '
              'a missing row.'
          : null,
      child: isLoading
          ? const _PanelPlaceholder(
              child: CircularProgressIndicator(color: _kManned),
            )
          : !coverage.hasData
              ? const _PanelPlaceholder(
                  child: _EmptyNote(
                    'No station has a per-shift required headcount set yet — '
                    'configure one in Station Management to see coverage.',
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final hero = _Hero(
                      value: _pct(coverage.rate),
                      caption: '${_comma(coverage.manned)} of '
                          '${_comma(coverage.totalDemand)} posts manned today',
                    );

                    final plot = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final shift in coverage.shifts) ...[
                          _CoverageBar(shift: shift),
                          if (shift != coverage.shifts.last)
                            const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 18),
                        const _Legend([
                          _LegendItem(_kManned, 'Manned'),
                          _LegendItem(
                              _kUnfilled, 'Unfilled in a published schedule'),
                          _LegendItem(_kUnscheduled, 'No schedule published'),
                        ]),
                      ],
                    );

                    if (constraints.maxWidth < _splitAt) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          hero,
                          _StatStrip(_stats),
                          const SizedBox(height: 24),
                          plot,
                        ],
                      );
                    }

                    // stretch, not start: the hairline between the two
                    // halves has no height of its own, so it only draws
                    // if the row hands it one.
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 250,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                hero,
                                const SizedBox(height: 20),
                                _StatRail(_stats),
                              ],
                            ),
                          ),
                          const SizedBox(width: 28),
                          const SizedBox(
                            width: 1,
                            child: ColoredBox(color: _kLine),
                          ),
                          const SizedBox(width: 28),
                          Expanded(child: plot),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// One shift's bar: the full width is everything that shift needs today,
/// split into what is manned, what a published schedule left unfilled,
/// and what belongs to a station nobody has scheduled.
class _CoverageBar extends StatelessWidget {
  final ShiftCoverage shift;

  const _CoverageBar({required this.shift});

  @override
  Widget build(BuildContext context) {
    final segments = <(int, Color)>[
      if (shift.manned > 0) (shift.manned, _kManned),
      if (shift.unfilled > 0) (shift.unfilled, _kUnfilled),
      if (shift.unscheduled > 0) (shift.unscheduled, _kUnscheduled),
    ];

    return Tooltip(
      message: '${shift.label} — ${shift.totalDemand} posts required today\n'
          '${shift.manned} manned\n'
          '${shift.unfilled} unfilled inside a published schedule\n'
          '${shift.unscheduled} at stations with no schedule published',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  shift.label,
                  // Never wrap: a two-line label pushes the bar out of
                  // step with its neighbours and the row reads broken.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _kInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Values wear ink, never the data colour.
              Text(
                '${_comma(shift.manned)} / ${_comma(shift.totalDemand)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kInk,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 38,
                child: Text(
                  _pct(shift.rate),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 12,
            child: segments.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      for (var i = 0; i < segments.length; i++) ...[
                        // A 2px gap in the surface colour separates
                        // touching fills — never a border.
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: segments[i].$1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: segments[i].$2,
                              borderRadius: BorderRadius.horizontal(
                                left: Radius.circular(i == 0 ? 4 : 0),
                                right: Radius.circular(
                                    i == segments.length - 1 ? 4 : 0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Attendance panel
// ---------------------------------------------------------------------

class _AttendancePanel extends StatelessWidget {
  final AttendanceTrend trend;
  final bool isLoading;
  final VoidCallback? onOpenReports;

  const _AttendancePanel({
    required this.trend,
    required this.isLoading,
    this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Attendance',
      subtitle: 'Present vs absent per reporting day, from the head guard '
          'reports actually filed',
      action: onOpenReports == null
          ? null
          : _PanelLink(label: 'Reports', onPressed: onOpenReports!),
      footnote: trend.hasData
          ? 'Columns are days a report was filed, not calendar days — no '
              'report means no data, not a gap in cover.'
          : null,
      child: isLoading
          ? const _PanelPlaceholder(
              child: CircularProgressIndicator(color: _kManned),
            )
          : !trend.hasData
              ? const _PanelPlaceholder(
                  child: _EmptyNote(
                    'No head guard has filed an attendance report yet — the '
                    'trend fills in as reports come through.',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Hero(
                      value: _pct(trend.rate),
                      valueSize: 38,
                      caption: '${_comma(trend.present)} of '
                          '${_comma(trend.total)} guard-shifts present',
                    ),
                    _StatStrip([
                      _Stat(
                        '${trend.absent}',
                        _plural(trend.absent, 'absence', 'absences'),
                        trend.absent > 0 ? _kAbsent : _kGood,
                      ),
                      _Stat('${trend.days.length}', 'reporting days'),
                      _Stat(
                        '${trend.reports}',
                        '${_plural(trend.reports, 'report')} filed',
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _AttendanceChart(trend: trend),
                    const SizedBox(height: 14),
                    const _Legend([
                      _LegendItem(_kGood, 'Present'),
                      _LegendItem(_kAbsent, 'Absent'),
                    ]),
                  ],
                ),
    );
  }
}

/// Stacked columns, one per reporting day. Column height is how many
/// guard-shifts that day's reports covered, so a busy day reads taller
/// than a single-station one instead of both being normalised to 100%.
class _AttendanceChart extends StatelessWidget {
  final AttendanceTrend trend;

  const _AttendanceChart({required this.trend});

  static const double _plotHeight = 104;

  // The column is taller than the plot: an absence label rides above
  // each bar and the date sits beneath it. Sizing the box to the plot
  // alone clips the date band and nests a scrollbar inside the card.
  static const double _labelBand = 16; // absence count above the bar
  static const double _dateBand = 8 + 14; // gap + date text
  static const double totalHeight = _plotHeight + _labelBand + _dateBand;

  @override
  Widget build(BuildContext context) {
    final busiest = trend.busiestDay;

    return SizedBox(
      height: totalHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in trend.days)
            Expanded(
              child: _AttendanceColumn(day: day, busiest: busiest),
            ),
        ],
      ),
    );
  }
}

class _AttendanceColumn extends StatelessWidget {
  final AttendanceDay day;
  final int busiest;

  const _AttendanceColumn({required this.day, required this.busiest});

  @override
  Widget build(BuildContext context) {
    final scale = busiest == 0 ? 0.0 : day.total / busiest;
    final columnHeight = _AttendanceChart._plotHeight * scale;

    // Split the column by its own composition, leaving room for the 2px
    // surface gap when both states are present.
    final hasBoth = day.present > 0 && day.absent > 0;
    final usable = columnHeight - (hasBoth ? 2 : 0);
    final presentHeight =
        day.total == 0 ? 0.0 : usable * (day.present / day.total);
    final absentHeight =
        day.total == 0 ? 0.0 : usable * (day.absent / day.total);

    return Tooltip(
      message: '${day.shortLabel} — ${day.present} present, '
          '${day.absent} absent\n'
          '${day.reports} ${_plural(day.reports, 'report')} filed',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Direct-label the story: the days that had an absence. A
          // number over every column would go unread.
          SizedBox(
            height: 16,
            child: day.absent > 0
                ? Text(
                    '${day.absent}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kAbsent,
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: ConstrainedBox(
              // Cap the mark so a short series doesn't render slabs.
              constraints: const BoxConstraints(maxWidth: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (absentHeight > 0)
                    Container(
                      height: absentHeight,
                      decoration: const BoxDecoration(
                        color: _kAbsent,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  if (hasBoth) const SizedBox(height: 2),
                  if (presentHeight > 0)
                    Container(
                      height: presentHeight,
                      decoration: BoxDecoration(
                        color: _kGood,
                        borderRadius: BorderRadius.vertical(
                          // Only the top of the whole column is rounded.
                          top: Radius.circular(day.absent > 0 ? 0 : 4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 14,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                day.shortLabel,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Schedule health panel
// ---------------------------------------------------------------------

class _HealthPanel extends StatelessWidget {
  final ScheduleHealth health;
  final bool isLoading;
  final VoidCallback? onOpenSchedules;

  const _HealthPanel({
    required this.health,
    required this.isLoading,
    this.onOpenSchedules,
  });

  @override
  Widget build(BuildContext context) {
    final blockers = health.severityCount(NoteSeverity.blocker);
    final warnings = health.severityCount(NoteSeverity.warning);
    final infos = health.severityCount(NoteSeverity.info);

    return _Panel(
      title: 'Schedule Health',
      subtitle: 'What the generator had to bend, grouped by where the fix '
          'lives',
      action: !health.hasData
          ? null
          : _PanelLink(
              label: 'Breakdown',
              icon: Icons.unfold_more,
              onPressed: () => showHealthBreakdown(
                context,
                health,
                onOpenSchedules: onOpenSchedules,
              ),
            ),
      footnote: health.hasData
          ? 'Every bar opens — tap a section to read the notes filed under it.'
          : null,
      child: isLoading
          ? const _PanelPlaceholder(
              child: CircularProgressIndicator(color: _kManned),
            )
          : !health.hasData
              ? const _PanelPlaceholder(
                  child: _EmptyNote(
                    'Nothing to report — no generated schedule has filed a '
                    'note.',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Hero(
                      value: '${health.actionable}',
                      valueSize: 38,
                      valueColor: health.actionable > 0 ? _kWarn : _kGood,
                      caption: health.actionable > 0
                          ? 'of ${health.total} '
                              '${_plural(health.total, 'note')} filed '
                              'need a look'
                          : 'need a look — all ${health.total} '
                              '${_plural(health.total, 'note')} filed are '
                              'informational',
                    ),
                    _StatStrip([
                      _Stat('${health.total}', 'notes filed'),
                      _Stat(
                        '${health.scheduleCount}',
                        _plural(health.scheduleCount, 'schedule'),
                      ),
                      _Stat(
                        '${health.stationCount}',
                        _plural(health.stationCount, 'station'),
                      ),
                    ]),
                    const SizedBox(height: 22),

                    // The key carries the severity totals, so the
                    // headline can be checked against the bars: the red
                    // and amber lengths below ARE these two numbers.
                    _Legend([
                      if (blockers > 0)
                        _LegendItem(
                            _kAbsent, 'fix before publishing', '$blockers'),
                      if (warnings > 0)
                        _LegendItem(_kWarn, 'needs a look', '$warnings'),
                      if (infos > 0)
                        _LegendItem(_kInfo, 'for information', '$infos'),
                    ]),
                    const SizedBox(height: 14),

                    for (final tally in health.tallies)
                      _HealthRow(
                        tally: tally,
                        max: health.maxCount,
                        onTap: () => showHealthBreakdown(
                          context,
                          health,
                          category: tally.category,
                          onOpenSchedules: onOpenSchedules,
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// One category's row. Bar LENGTH is how many notes the category holds;
/// the split inside it is how loud they are — so a long quiet bar and a
/// short red one can't be confused for each other.
class _HealthRow extends StatelessWidget {
  final NoteTally tally;
  final int max;
  final VoidCallback onTap;

  const _HealthRow({
    required this.tally,
    required this.max,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final factor = max == 0 ? 0.0 : (tally.count / max).clamp(0.0, 1.0);

    final segments = <(int, Color)>[
      for (final severity in NoteSeverity.values)
        if (tally.severityCount(severity) > 0)
          (tally.severityCount(severity), _severityMark(severity)),
    ];

    return Tooltip(
      message: '${tally.category.title} — ${tally.count} '
          '${_plural(tally.count, 'note')}\n'
          '${tally.category.blurb}\n'
          '${tally.actionable} needing a look, across '
          '${tally.stationCount} ${_plural(tally.stationCount, 'station')}',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(tally.category.icon, size: 15, color: Colors.grey[500]),
              const SizedBox(width: 9),
              SizedBox(
                width: 112,
                child: Text(
                  tally.category.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kBody,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: _kManned.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: factor,
                    child: Row(
                      children: [
                        for (var i = 0; i < segments.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: segments[i].$1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: segments[i].$2,
                                borderRadius: BorderRadius.horizontal(
                                  left: Radius.circular(i == 0 ? 4 : 0),
                                  right: Radius.circular(
                                      i == segments.length - 1 ? 4 : 0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 26,
                child: Text(
                  '${tally.count}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kInk,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 17, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Schedule health — the breakdown
// ---------------------------------------------------------------------

/// Opens the notes behind the Schedule Health panel, optionally already
/// narrowed to one [category].
///
/// The panel can only ever say HOW MANY compromises there were. This is
/// where the admin reads WHICH ones — the same three-line note tile the
/// Auto Scheduler shows after a run, so a note looks the same wherever
/// it's met.
void showHealthBreakdown(
  BuildContext context,
  ScheduleHealth health, {
  NoteCategory? category,
  VoidCallback? onOpenSchedules,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (_) => _HealthBreakdownDialog(
      health: health,
      initialCategory: category,
      onOpenSchedules: onOpenSchedules,
    ),
  );
}

class _HealthBreakdownDialog extends StatefulWidget {
  final ScheduleHealth health;
  final NoteCategory? initialCategory;
  final VoidCallback? onOpenSchedules;

  const _HealthBreakdownDialog({
    required this.health,
    this.initialCategory,
    this.onOpenSchedules,
  });

  @override
  State<_HealthBreakdownDialog> createState() =>
      _HealthBreakdownDialogState();
}

class _HealthBreakdownDialogState extends State<_HealthBreakdownDialog> {
  /// null = every section.
  NoteCategory? _category;

  /// Which severities are showing. Starts as all three — the dialog is
  /// opened to READ, and hiding a row by default would make the counts
  /// on the panel behind it not add up.
  final Set<NoteSeverity> _severities = {...NoteSeverity.values};

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
  }

  List<HealthNote> get _filtered => widget.health.notes
      .where((n) =>
          (_category == null || n.category == _category) &&
          _severities.contains(n.severity))
      .toList();

  void _toggleSeverity(NoteSeverity severity) {
    setState(() {
      if (!_severities.remove(severity)) _severities.add(severity);
    });
  }

  @override
  Widget build(BuildContext context) {
    final health = widget.health;
    final filtered = _filtered;

    // Grouped the way the panel is grouped, in the panel's own order —
    // so the list under a bar is that bar, expanded.
    final grouped = <NoteTally>[
      for (final tally in health.tallies)
        if (filtered.any((n) => n.category == tally.category))
          NoteTally(
            tally.category,
            filtered.where((n) => n.category == tally.category).toList(),
          ),
    ];

    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BreakdownHeader(health: health),
            _BreakdownFilters(
              health: health,
              category: _category,
              severities: _severities,
              onCategory: (c) => setState(() => _category = c),
              onSeverity: _toggleSeverity,
            ),
            Flexible(
              child: grouped.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
                      child: _EmptyNote(
                        _severities.isEmpty
                            ? 'Every severity is switched off — turn one back '
                                'on to see its notes.'
                            : 'No note in this section matches the severities '
                                'you have on.',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                      children: [
                        for (var i = 0; i < grouped.length; i++) ...[
                          if (i > 0) const SizedBox(height: 22),
                          _BreakdownSection(tally: grouped[i]),
                        ],
                      ],
                    ),
            ),
            _BreakdownFooter(
              showing: filtered.length,
              total: health.total,
              onOpenSchedules: widget.onOpenSchedules,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownHeader extends StatelessWidget {
  final ScheduleHealth health;

  const _BreakdownHeader({required this.health});

  @override
  Widget build(BuildContext context) {
    final clean = health.actionable == 0;
    final accent = clean ? _kGood : _kWarn;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kLine)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              clean ? Icons.check_circle_outline : Icons.fact_check_outlined,
              size: 20,
              color: accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule Health — what the generator had to bend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  clean
                      ? '${health.total} ${_plural(health.total, 'note')} filed '
                          'across ${health.scheduleCount} '
                          '${_plural(health.scheduleCount, 'schedule')} — all '
                          'of them a record of what was decided, not a problem '
                          'to fix.'
                      : '${health.actionable} of ${health.total} notes need a '
                          'look, across ${health.scheduleCount} '
                          '${_plural(health.scheduleCount, 'schedule')} and '
                          '${health.stationCount} '
                          '${_plural(health.stationCount, 'station')}. The '
                          'rosters were still generated and saved.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            color: Colors.grey[600],
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _BreakdownFilters extends StatelessWidget {
  final ScheduleHealth health;
  final NoteCategory? category;
  final Set<NoteSeverity> severities;
  final ValueChanged<NoteCategory?> onCategory;
  final ValueChanged<NoteSeverity> onSeverity;

  const _BreakdownFilters({
    required this.health,
    required this.category,
    required this.severities,
    required this.onCategory,
    required this.onSeverity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFD),
        border: Border(bottom: BorderSide(color: _kLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterPill(
                label: 'All sections',
                count: health.total,
                selected: category == null,
                accent: _kManned,
                onTap: () => onCategory(null),
              ),
              for (final tally in health.tallies)
                _FilterPill(
                  label: tally.category.title,
                  count: tally.count,
                  icon: tally.category.icon,
                  selected: category == tally.category,
                  accent: _kManned,
                  onTap: () => onCategory(tally.category),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 2, top: 5),
                child: Text(
                  'Showing',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
              ),
              for (final severity in NoteSeverity.values)
                if (health.severityCount(severity) > 0)
                  _FilterPill(
                    label: severity.label,
                    count: health.severityCount(severity),
                    icon: severity.icon,
                    selected: severities.contains(severity),
                    accent: _severityMark(severity),
                    onTap: () => onSeverity(severity),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A filter toggle. Selected state is carried by the fill, the border
/// AND the ink — never by colour alone, because the severity pills are
/// already colour-coded for something else.
class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color accent;
  final IconData? icon;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.10) : _kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent.withOpacity(0.55) : const Color(0xFFDCE3EE),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected ? accent : Colors.grey[500],
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : Colors.grey[700],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? accent : Colors.grey[500],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One category inside the breakdown: the bar's own heading, then the
/// notes that made it.
class _BreakdownSection extends StatelessWidget {
  final NoteTally tally;

  const _BreakdownSection({required this.tally});

  @override
  Widget build(BuildContext context) {
    final accent = _severityMark(tally.worst);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(tally.category.icon, size: 17, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tally.category.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _kInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tally.category.blurb,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${tally.count} ${_plural(tally.count, 'note')}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final note in tally.notes) _NoteTile(entry: note),
      ],
    );
  }
}

/// One note: who or what it's about, which roster it came from, what
/// happened, and what to do. The same three-line shape the Auto
/// Scheduler uses, plus the run it belongs to — which the panel's
/// aggregate would otherwise have thrown away.
class _NoteTile extends StatelessWidget {
  final HealthNote entry;

  const _NoteTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final note = entry.note;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: note.severity.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: note.severity.color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(note.severity.icon, size: 14, color: note.severity.color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  note.subject.isEmpty ? entry.stationName : note.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Only said out loud when it changes what the admin does;
              // labelling every note "for information" is noise.
              if (note.severity == NoteSeverity.blocker)
                Text(
                  note.severity.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                    color: note.severity.color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          // Which roster filed it. Without this the note is a sentence
          // with no address — there are 25 stations and a new schedule
          // every fortnight.
          Row(
            children: [
              Icon(Icons.place_outlined, size: 11, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  entry.stationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.date_range_outlined, size: 11, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                entry.periodLabel,
                style: TextStyle(fontSize: 10.5, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.problem,
            style: const TextStyle(fontSize: 12, height: 1.45, color: _kBody),
          ),
          if (note.fix.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.fix,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownFooter extends StatelessWidget {
  final int showing;
  final int total;
  final VoidCallback? onOpenSchedules;

  const _BreakdownFooter({
    required this.showing,
    required this.total,
    this.onOpenSchedules,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFD),
        border: Border(top: BorderSide(color: _kLine)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $showing of $total ${_plural(total, 'note')}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
            ),
          ),
          if (onOpenSchedules != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onOpenSchedules!();
              },
              style: TextButton.styleFrom(foregroundColor: _kManned),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text(
                'Open Schedules',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
            child: const Text('Close', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
