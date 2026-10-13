// screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/leave_request.dart';
import '../models/replacement.dart';
import '../models/schedule.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../services/profile_settings.dart';
import 'main_layout.dart';

// Which report the screen is showing. The two share the page chrome and
// the export button but nothing else — a leave report is company-wide
// and yearly, where a schedule report is per station and per bi-week.
enum ReportKind { schedule, leave }

// ─────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────
const _kAccent      = Color(0xFF1D4ED8);
const _kBorder      = Color(0xFFE2E8F0);
const _kText        = Color(0xFF0F172A);
const _kTextMuted   = Color(0xFF64748B);
const _kSurface     = Color(0xFFF8FAFC);
const _kRelText     = Color(0xFF854D0E);
const _kAbsence     = Color(0xFFB45309);

const _kCompanyLine1 = 'KAIZEN SECURITY AGENCY CORPORATION';
const _kCompanyLine2 = 'LIGHT RAIL MANILA CORPORATION';

// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────
class GuardEntry {
  final int    no;
  final String id;
  final String name;
  final String post;
  final String time;
  final double hours;
  final String date;        // day-off dates covered by the reliever
  final String reliever;

  const GuardEntry({
    required this.no,
    required this.id,
    required this.name,
    required this.post,
    required this.time,
    required this.hours,
    this.date     = '',
    this.reliever = '',
  });

  bool get hasReliever => reliever.isNotEmpty;
}

// One absence on one specific day, and who covered it.
class AbsenceRow {
  final String dateLabel;   // e.g. "July 16"
  final String post;
  final String time;        // the hours the COVER stood
  final String name;        // the absent guard
  final String replacedBy;  // the covering guard

  // The post's own hours, when the cover stood different ones — a
  // short-notice cover is given an hour to get ready and travel, so the
  // duty slides (services/prep_window.dart). Null on every ordinary row.
  //
  // Printed under the time rather than instead of it, because both are
  // facts the report has to carry: what the post was rostered for, and
  // what was actually stood.
  final String? retimedFrom;

  const AbsenceRow({
    required this.dateLabel,
    required this.post,
    required this.time,
    required this.name,
    required this.replacedBy,
    this.retimedFrom,
  });
}

// Everything one station's report needs — built either from a real
// backend schedule or from the sample data below.
class _ReportData {
  final List<GuardEntry> morning, afternoon, night;
  final List<AbsenceRow> absences;

  const _ReportData({
    required this.morning,
    required this.afternoon,
    required this.night,
    required this.absences,
  });

  static const empty = _ReportData(
      morning: [], afternoon: [], night: [], absences: []);

  bool get isEmpty =>
      morning.isEmpty && afternoon.isEmpty && night.isEmpty;
}

class StationInfo {
  final int    no;
  final String name;
  const StationInfo({required this.no, required this.name});
  String get label => '$no. $name';
}

// One selectable reporting period. Built from the start/end dates of
// the schedules actually stored in the system; the generated 1–15 /
// 16–end halves are only used as a fallback while there's no data.
class ReportPeriod {
  final DateTime start, end;
  final String label;
  ReportPeriod(this.start, this.end) : label = _periodLabel(start, end);
}

String _periodLabel(DateTime s, DateTime e) {
  if (s.year == e.year && s.month == e.month) {
    return '${_kMonths[s.month]} ${s.day}–${e.day}, ${s.year}';
  }
  if (s.year == e.year) {
    return '${_kMonths[s.month]} ${s.day} – ${_kMonths[e.month]} ${e.day}, ${s.year}';
  }
  return '${_kMonths[s.month]} ${s.day}, ${s.year} – ${_kMonths[e.month]} ${e.day}, ${e.year}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ─────────────────────────────────────────────
// STATIONS (fallback list — replaced by the stations
// found in real schedules once the backend responds)
// ─────────────────────────────────────────────
const _kStations = [
  StationInfo(no:  1, name: 'Fernando Poe Jr. Station'),
  StationInfo(no:  2, name: 'Balintawak Station'),
  StationInfo(no:  3, name: 'Monumento Station'),
  StationInfo(no:  4, name: '5th Avenue Station'),
  StationInfo(no:  5, name: 'R. Papa Station'),
  StationInfo(no:  6, name: 'Abad Santos Station'),
  StationInfo(no:  7, name: 'Blumentritt Station'),
  StationInfo(no:  8, name: 'Tayuman Station'),
  StationInfo(no:  9, name: 'Bambang Station'),
  StationInfo(no: 10, name: 'Doroteo Jose Station'),
  StationInfo(no: 11, name: 'Carriedo Station'),
  StationInfo(no: 12, name: 'Central Terminal Station'),
  StationInfo(no: 13, name: 'United Nations Station'),
  StationInfo(no: 14, name: 'Pedro Gil Station'),
  StationInfo(no: 15, name: 'Quirino Station'),
  StationInfo(no: 16, name: 'Vito Cruz Station'),
  StationInfo(no: 17, name: 'Gil Puyat Station'),
  StationInfo(no: 18, name: 'Libertad Station'),
  StationInfo(no: 19, name: 'EDSA Station'),
  StationInfo(no: 20, name: 'Baclaran Station'),
  StationInfo(no: 21, name: 'Redemptorist-Aseana Station'),
  StationInfo(no: 22, name: 'MIA Road Station'),
  StationInfo(no: 23, name: 'PITX (Asia World) Station'),
  StationInfo(no: 24, name: 'Ninoy Aquino Avenue Station'),
  StationInfo(no: 25, name: 'Dr. Santos Station'),
];

// ─────────────────────────────────────────────
// PERIOD GENERATOR
// ─────────────────────────────────────────────
const _kMonths = [
  '', 'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];

const _kMonthsShort = [
  '', 'Jan','Feb','Mar','Apr','May','Jun',
  'Jul','Aug','Sep','Oct','Nov','Dec',
];

String _shortDate(DateTime d) => '${_kMonthsShort[d.month]} ${d.day}';
String _longDate(DateTime d)  => '${_kMonths[d.month]} ${d.day}';

List<ReportPeriod> _generatePeriods() {
  final now = DateTime.now();
  final out = <ReportPeriod>[];
  for (int offset = -6; offset <= 3; offset++) {
    int m = now.month + offset, y = now.year;
    while (m < 1)  { m += 12; y--; }
    while (m > 12) { m -= 12; y++; }
    final last = DateUtils.getDaysInMonth(y, m);
    out.add(ReportPeriod(DateTime(y, m, 1), DateTime(y, m, 15)));
    out.add(ReportPeriod(DateTime(y, m, 16), DateTime(y, m, last)));
  }
  return out;
}

// The period covering today, falling back to the first (newest) one.
ReportPeriod _pickCurrentPeriod(List<ReportPeriod> periods) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return periods.firstWhere(
    (p) => !today.isBefore(p.start) && !today.isAfter(p.end),
    orElse: () => periods.first,
  );
}

// Same shift → time/hours mapping the backend generator uses.
const Map<String, (String, double)> _kShiftTimeAndHours = {
  'Morning':   ('0500H - 1400H',  9.0),
  'Afternoon': ('1400H - 2330H',  9.5),
  'Night':     ('2100H - 0500H',  8.0),
  'HG Day':    ('0500H - 1700H', 12.0),
  'HG Night':  ('1700H - 0500H', 12.0),
};

// ─────────────────────────────────────────────
// REAL-SCHEDULE → REPORT BUILDER
// ─────────────────────────────────────────────
// Mirrors schedule_detail_screen: own-duty entries place each employee
// in their shift block, covering entries fill the RELIEVER column, and
// DATE shows the period dates where the employee has no own-duty entry.
// The absences list is NOT derived from the schedule — only the
// admin-applied replacement records passed in land in the log.
_ReportData _reportFromSchedule(
    Schedule schedule, List<AbsenceRow> absences) {
  final allDates = schedule.days.map((d) => d.date).toList();

  final names        = <String, String>{};
  final ownShift     = <String, String>{};
  final ownPost      = <String, String>{};
  final presentDates = <String, Set<DateTime>>{};
  // covered employeeId -> (date, coverer name) pairs
  final covers = <String, List<MapEntry<DateTime, String>>>{};

  for (final day in schedule.days) {
    for (final entry in day.entries) {
      names[entry.employeeId] = entry.employeeName;
      if (entry.coveringFor != null) {
        covers
            .putIfAbsent(entry.coveringFor!, () => [])
            .add(MapEntry(day.date, entry.employeeName));
      } else {
        ownShift[entry.employeeId] = entry.shift;
        if (entry.post != null && entry.post!.isNotEmpty) {
          ownPost[entry.employeeId] = entry.post!;
        }
        presentDates.putIfAbsent(entry.employeeId, () => {}).add(day.date);
      }
    }
  }

  List<GuardEntry> rowsFor(List<String> shifts) {
    final employeeIds = ownShift.keys
        .where((id) => shifts.contains(ownShift[id]))
        .toList()
      ..sort((a, b) {
        // Head guard first, then by ID.
        final aHg = ownShift[a]!.startsWith('HG') ? 0 : 1;
        final bHg = ownShift[b]!.startsWith('HG') ? 0 : 1;
        return aHg != bHg ? aHg.compareTo(bHg) : a.compareTo(b);
      });

    final rows = <GuardEntry>[];
    for (final id in employeeIds) {
      final shift = ownShift[id]!;
      final (time, hours) = _kShiftTimeAndHours[shift] ?? ('', 0.0);
      final offDates = allDates
          .where((d) => !(presentDates[id]?.contains(d) ?? false))
          .toList();
      // Who covered this guard's day-offs, and how many each took. The
      // generator binds one reliever to a guard's whole run, so this is
      // normally a single name — but a guard on LEAVE is off for more
      // days than any one reliever may work, so their days are shared
      // out across the station's roster. Printing only the first name
      // (which is what this did) put one reliever's name against a
      // thirteen-date absence they worked one day of.
      final tally = <String, int>{};
      for (final cover in covers[id] ?? const <MapEntry<DateTime, String>>[]) {
        tally[cover.value] = (tally[cover.value] ?? 0) + 1;
      }
      final shared = tally.entries.toList()
        ..sort((a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key));

      rows.add(GuardEntry(
        no: rows.length + 1,
        id: id,
        name: names[id] ?? id,
        post: ownPost[id] ??
            (shift.startsWith('HG') ? 'Head Guard' : 'Shift Guard'),
        time: time,
        hours: hours,
        date: offDates.map(_shortDate).join(' · '),
        // One name on its own for the ordinary bound case; "Name (n)"
        // per guard when the run was split, so the count reconciles
        // against the DATE column beside it.
        reliever: shared.isEmpty
            ? ''
            : shared.length == 1
                ? shared.first.key
                : shared.map((e) => '${e.key} (${e.value})').join(' · '),
      ));
    }
    return rows;
  }

  return _ReportData(
    morning:   rowsFor(['HG Day', 'Morning']),
    afternoon: rowsFor(['Afternoon']),
    night:     rowsFor(['HG Night', 'Night']),
    absences:  absences,
  );
}

// ─────────────────────────────────────────────
// SAMPLE DATA (shown only while the backend is
// unreachable or has no schedules yet)
// ─────────────────────────────────────────────
List<GuardEntry> _buildMorningShift(ReportPeriod p) {
  final month = _kMonthsShort[p.start.month];
  final startDay = p.start.day;
  final names = [
    ('Juan Dela Cruz',   '2001', 'Head Guard'),
    ('Maria Santos',     '2002', 'Shift Guard'),
    ('Pedro Garcia',     '2003', 'Shift Guard'),
    ('Liza Ramirez',     '2004', 'Shift Guard'),
    ('Carlo Cruz',       '2005', 'Shift Guard'),
    ('Ana Reyes',        '2006', 'Shift Guard'),
    ('Mark Santos',      '2007', 'Shift Guard'),
  ];
  final relievers = ['Carlo Cruz','Mark Santos','–','Jojo Bautista','Carlo Cruz','–','Ana Reyes'];
  final relDates  = ['$month $startDay','$month ${startDay+1}','','$month ${startDay+3}','$month ${startDay+4}','','$month ${startDay+6}'];

  return List.generate(7, (i) => GuardEntry(
    no: i + 1,
    id: names[i].$2,
    name: names[i].$1,
    post: names[i].$3,
    time: names[i].$3 == 'Head Guard' ? '0500H - 1700H' : '0500H - 1400H',
    hours: names[i].$3 == 'Head Guard' ? 12.00 : 9.00,
    date: relDates[i],
    reliever: relievers[i] == '–' ? '' : relievers[i],
  ));
}

List<GuardEntry> _buildAfternoonShift(ReportPeriod p) {
  final month = _kMonthsShort[p.start.month];
  final startDay = p.start.day;
  final names = [
    ('Roberto Luna',     '2101', 'Shift Guard'),
    ('Carla Mendoza',    '2102', 'Shift Guard'),
    ('Jose Reyes',       '2103', 'Shift Guard'),
    ('Nina Torres',      '2104', 'Shift Guard'),
    ('Ben Villanueva',   '2105', 'Shift Guard'),
    ('Gloria Santos',    '2106', 'Shift Guard'),
    ('Ricky Flores',     '2107', 'Shift Guard'),
  ];
  final relievers = ['–','Ricky Flores','–','Carlos Bautista','–','Nina Torres','–'];
  final relDates  = ['','$month ${startDay+2}','','$month ${startDay+5}','','$month ${startDay+7}',''];

  return List.generate(7, (i) => GuardEntry(
    no: i + 1,
    id: names[i].$2,
    name: names[i].$1,
    post: names[i].$3,
    time: '1400H - 2330H',
    hours: 9.50,
    date: relDates[i],
    reliever: relievers[i] == '–' ? '' : relievers[i],
  ));
}

List<GuardEntry> _buildNightShift(ReportPeriod p) {
  final month = _kMonthsShort[p.start.month];
  final startDay = p.start.day;
  final names = [
    ('Eduardo Bautista', '2201', 'Head Guard'),
    ('Lourdes Garcia',   '2202', 'Shift Guard'),
  ];
  final relievers = ['Jeremy Moico','–'];
  final relDates  = ['$month ${startDay+1}',''];

  return List.generate(2, (i) => GuardEntry(
    no: i + 1,
    id: names[i].$2,
    name: names[i].$1,
    post: names[i].$3,
    time: names[i].$3 == 'Head Guard' ? '1700H - 0500H' : '2100H - 0500H',
    hours: names[i].$3 == 'Head Guard' ? 12.00 : 8.00,
    date: relDates[i],
    reliever: relievers[i] == '–' ? '' : relievers[i],
  ));
}

_ReportData _sampleReport(ReportPeriod p) {
  final morning   = _buildMorningShift(p);
  final afternoon = _buildAfternoonShift(p);
  final night     = _buildNightShift(p);

  final absences = <AbsenceRow>[
    for (final e in [...morning, ...afternoon, ...night])
      if (e.hasReliever)
        AbsenceRow(
          dateLabel: e.date,
          post: e.post,
          time: e.time,
          name: e.name,
          replacedBy: e.reliever,
        ),
  ];

  return _ReportData(
    morning: morning,
    afternoon: afternoon,
    night: night,
    absences: absences,
  );
}

// ─────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────
class ReportsContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data})? onNavigate;
  const ReportsContent({super.key, this.onNavigate});

  @override
  State<ReportsContent> createState() => _ReportsContentState();
}

class _ReportsContentState extends State<ReportsContent> {
  List<StationInfo> _stations = _kStations;
  StationInfo _station = _kStations.first;

  // Starts as the generated fallback halves; replaced by the periods of
  // the schedules actually stored in the system once the backend responds.
  List<ReportPeriod> _periods = _generatePeriods();
  late ReportPeriod _period = _pickCurrentPeriod(_periods);

  List<Schedule> _schedules = [];
  // Admin-applied substitutions (audit records) — the ONLY source of
  // the Absence & Substitution Log for real schedules.
  List<AppliedReplacement> _replacements = [];
  bool _loading = true;
  String? _loadError;

  // The schedule currently on screen; null = no real schedule matches
  // the selected station + period.
  Schedule? _activeSchedule;
  _ReportData _data = _ReportData.empty;

  // Sample data is only shown when the backend has nothing to offer.
  bool get _usingSampleData => false;
  bool _exporting = false;

  // ── Leave report ──
  // A second report behind the same page chrome, switched by the segment
  // in the top bar. Its own filters (year + status), its own table and
  // its own PDF — nothing about the schedule report changes when it's on.
  ReportKind _kind = ReportKind.schedule;
  List<LeaveRequest> _leaves = [];
  bool _leavesLoading = true;
  String? _leaveError;
  int _leaveYear = DateTime.now().year;
  String _leaveStatus = 'All';

  static const _kLeaveStatuses = [
    'All', 'On Leave', 'Approved', 'Pending', 'Denied',
  ];

  bool get _onLeaveReport => _kind == ReportKind.leave;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _loadSchedules();
    _loadLeaves();
  }

  Future<void> _loadLeaves() async {
    final result = await ApiService.fetchLeaveRequests();
    if (!mounted) return;
    setState(() {
      _leavesLoading = false;
      if (result['success'] == true) {
        _leaves = (result['requests'] as List).cast<LeaveRequest>();
        _leaveError = null;
        // Land on a year that actually has records, so the report isn't
        // empty on open just because nothing was filed this year yet.
        final years = _leaveYears;
        if (!years.contains(_leaveYear) && years.isNotEmpty) {
          _leaveYear = years.first;
        }
      } else {
        _leaves = [];
        _leaveError = result['error']?.toString();
      }
    });
  }

  // Every year that has a leave on record, newest first, always including
  // the current one so the dropdown is never empty.
  List<int> get _leaveYears {
    final years = {DateTime.now().year, ..._leaves.map((l) => l.year)}
      ..removeWhere((y) => y == 0);
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  List<LeaveRequest> get _visibleLeaves {
    final ofYear = _leaves.where((l) => l.year == _leaveYear).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    switch (_leaveStatus) {
      case 'On Leave':
        return ofYear.where((l) => l.isOnLeaveNow).toList();
      case 'Approved':
        return ofYear.where((l) => l.isApproved).toList();
      case 'Pending':
        return ofYear.where((l) => l.isPending).toList();
      case 'Denied':
        return ofYear.where((l) => l.isDenied || l.isCancelled).toList();
      default:
        return ofYear;
    }
  }

  Future<void> _loadSchedules() async {
    final results = await Future.wait([
      ApiService.fetchSchedules(),
      ApiService.fetchReplacements(),
    ]);
    if (!mounted) return;
    final schedulesResult = results[0];
    final replacementsResult = results[1];
    setState(() {
      _loading = false;
      if (schedulesResult['success'] == true) {
        _schedules = (schedulesResult['schedules'] as List).cast<Schedule>();
        _loadError = null;
        _rebuildStationList();
        _rebuildPeriodList();
      } else {
        _loadError = schedulesResult['error']?.toString();
      }
      if (replacementsResult['success'] == true) {
        _replacements = (replacementsResult['replacements'] as List)
            .cast<AppliedReplacement>();
      }
      _refreshData();
    });
  }

  // Replaces the hardcoded station list with the stations that actually
  // have schedules, keeping the LRT line order where names match.
  void _rebuildStationList() {
    final names = _schedules.map((s) => s.stationName).toSet();
    if (names.isEmpty) return;

    final ordered = <String>[
      ..._kStations.map((s) => s.name).where(names.contains),
      ...(names.where((n) => !_kStations.any((s) => s.name == n)).toList()
        ..sort()),
    ];
    _stations = [
      for (int i = 0; i < ordered.length; i++)
        StationInfo(no: i + 1, name: ordered[i]),
    ];
    _station = _stations.firstWhere(
      (s) => s.name == _station.name,
      orElse: () => _stations.first,
    );
  }

  // Replaces the generated fallback halves with the distinct start/end
  // periods of the schedules actually stored in the system, newest first.
  void _rebuildPeriodList() {
    if (_schedules.isEmpty) return;

    final seen = <String>{};
    final periods = <ReportPeriod>[];
    for (final s in _schedules) {
      final key =
          '${s.startDate.year}-${s.startDate.month}-${s.startDate.day}|'
          '${s.endDate.year}-${s.endDate.month}-${s.endDate.day}';
      if (seen.add(key)) {
        periods.add(ReportPeriod(s.startDate, s.endDate));
      }
    }
    periods.sort((a, b) => b.start.compareTo(a.start));
    _periods = periods;
    _period = _pickCurrentPeriod(periods);
  }

  Schedule? _scheduleFor(StationInfo station, ReportPeriod p) {
    final matches = _schedules
        .where((s) =>
            s.stationName == station.name &&
            _sameDay(s.startDate, p.start) &&
            _sameDay(s.endDate, p.end))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.isEmpty ? null : matches.first;
  }

  // Absence & Substitution Log rows for one station in one period —
  // built exclusively from the replacements the admin applied, never
  // derived from the schedule itself.
  List<AbsenceRow> _absencesFor(String stationName, ReportPeriod p) {
    final matching = _replacements
        .where((r) =>
            r.date != null &&
            r.station.trim().toLowerCase() ==
                stationName.trim().toLowerCase() &&
            !r.date!.isBefore(p.start) &&
            !r.date!.isAfter(p.end))
        .toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));

    return [
      for (final r in matching)
        AbsenceRow(
          dateLabel: _longDate(r.date!),
          post: r.shift.startsWith('HG') ? 'Head Guard' : 'Shift Guard',
          time: _absenceTime(r),
          name: r.absentEmployeeName,
          replacedBy: r.replacementEmployeeName,
          // Stated only when the cover stood different hours from the
          // post — see _absenceTime.
          retimedFrom:
              r.isPrepAdjusted ? r.originalWindow!.range : null,
        ),
    ];
  }

  // The TIME column of one absence row: the hours the COVER actually
  // stood, which are not always the post's.
  //
  // A cover assigned at short notice is given an hour to get into
  // uniform and travel, so an 0500H - 1700H post covered at 0900H is
  // stood 1000H - 1900H (services/prep_window.dart). The record carries
  // the pair; the shift's base window — all this column used to have —
  // could not describe that, and could not describe a staggered post
  // either. It is still the fallback for records written before
  // replacements carried their own times.
  String _absenceTime(AppliedReplacement r) {
    final stood = r.window;
    if (stood != null) return stood.range;
    return (_kShiftTimeAndHours[r.shift] ?? ('', 0.0)).$1;
  }

  void _refreshData() {
    final sched = _scheduleFor(_station, _period);
    _activeSchedule = sched;
    if (sched != null) {
      _data = _reportFromSchedule(
          sched, _absencesFor(_station.name, _period));
    } else if (_usingSampleData) {
      _data = _sampleReport(_period);
    } else {
      _data = _ReportData.empty;
    }
  }

  String _printedDateTime(DateTime printedAt) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${printedAt.year.toString().padLeft(4, '0')}-'
        '${twoDigits(printedAt.month)}-${twoDigits(printedAt.day)} '
        '${twoDigits(printedAt.hour)}:${twoDigits(printedAt.minute)}:'
        '${twoDigits(printedAt.second)}';
  }

  // ── Export confirmation flow ──────────────────
  void _handleExportSingle() {
    _showExportConfirmation(exportAll: false);
  }

  void _handleExportAll() {
    _showExportConfirmation(exportAll: true);
  }

  void _showExportConfirmation({required bool exportAll}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded,
                  color: _kAccent, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Export Schedule Report',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w800, color: _kText)),
            ),
          ],
        ),
        content: Text(
          exportAll
              ? 'Export the bi-weekly schedule report for all stations as one combined PDF for ${_period.label}?'
              : 'Export the bi-weekly schedule report for ${_station.label} for ${_period.label}?',
          style: const TextStyle(fontSize: 13.5,
              color: _kTextMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              foregroundColor: _kTextMuted,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmExport(exportAll: exportAll);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExport({required bool exportAll}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      // Fetch the authorized roster and approval evidence together. Never
      // export a stale screen or sample data as an approved schedule.
      final result = await ApiService.workflow('/schedule-report', method: 'POST', body: {
        'startDate': _period.start.toIso8601String().substring(0, 10),
        'endDate': _period.end.toIso8601String().substring(0, 10),
        if (!exportAll) 'stationId': _activeSchedule?.stationId,
      });
      if (!mounted) return;
      if (result['success'] != true) {
        _showSnack(result['error'].toString(), success: false);
        await _loadSchedules();
        return;
      }
      final approval = Map<String, dynamic>.from(result['approval']);
      final schedules = approvalMaps(result['schedules']).map(Schedule.fromJson).toList();
      _replacements = approvalMaps(result['replacements']).map(AppliedReplacement.fromJson).toList();
      final doc = pw.Document();
      final printedAt = DateTime.now().toUtc().add(const Duration(hours: 8));
      for (final schedule in schedules) {
        _addStationPages(doc, schedule.stationName,
          _reportFromSchedule(schedule, _absencesFor(schedule.stationName, _period)),
          printedAt: printedAt, preparedBy: approval['submittedName'], approval: approval);
      }
      if (schedules.isEmpty) { _showSnack('No approved schedules to export.', success: false); return; }
      final stationSlug = exportAll ? 'all-stations' : _station.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      await Printing.sharePdf(bytes: await doc.save(),
        filename: 'schedule-report-$stationSlug-${approval['startDate']}-revision-${approval['revision']}.pdf');
      if (mounted) _showSnack('Approved PDF generated for ${schedules.length} station(s).');
    } catch (e) {
      if (mounted) _showSnack('Failed to generate PDF: $e', success: false);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSnack(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(success ? Icons.check_circle_rounded : Icons.error_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor:
            success ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PDF BUILDING
  // ─────────────────────────────────────────────
  static final _pdfHeaderStyle = pw.TextStyle(
      fontSize: 7.5, fontWeight: pw.FontWeight.bold);
  static const _pdfCellStyle = pw.TextStyle(fontSize: 8);

  // The PDF's built-in Helvetica can't render en/em dashes — they come
  // out as boxes — so swap them for plain hyphens in exported text.
  static String _pdfSafe(String s) =>
      s.replaceAll('–', '-').replaceAll('—', '-');

  pw.Widget _pdfPrintedAt(DateTime printedAt) {
    return pw.Text(
      'Printed: ${_printedDateTime(printedAt)}',
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
      ),
    );
  }

  void _addStationPages(
    pw.Document doc,
    String stationLabel,
    _ReportData data, {
    required DateTime printedAt,
    required String preparedBy,
    required Map<String, dynamic> approval,
  }) {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '$stationLabel - page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        // Centered company title
        pw.Center(
          child: pw.Text(_kCompanyLine1,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(_kCompanyLine2,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text('Bi-Weekly Schedule Report',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey700)),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(stationLabel,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 16),
            _pdfPrintedAt(printedAt),
          ],
        ),
        pw.SizedBox(height: 10),

        ..._pdfShiftBlock('MORNING SHIFT', data.morning),
        ..._pdfShiftBlock('AFTERNOON SHIFT', data.afternoon),
        ..._pdfShiftBlock('NIGHT SHIFT', data.night),

        pw.SizedBox(height: 6),
        pw.Text('ABSENCE & SUBSTITUTION LOG',
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _pdfAbsenceTable(data.absences),

        pw.SizedBox(height: 12),
        pw.Text('Approval reference: ${approval['id']} | Revision ${approval['revision']} | '
            '${approval['startDate']} to ${approval['endDate']}', style: const pw.TextStyle(fontSize: 8)),
        if (approvalMaps(approval['amendments']).isNotEmpty)
          pw.Text('Amended after approval: ${approvalMaps(approval['amendments']).length} emergency replacement(s) in this period. '
              'Original approvals apply to the submitted roster; later replacements are recorded separately.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange900)),
        _pdfApprovalSignatures(preparedBy, approval),
      ],
    ));
  }

  pw.Widget _pdfApprovalSignatures(String preparedBy, Map<String, dynamic> approval) {
    final decisions = approvalMaps(approval['events']).where((e) => e['action'] == 'approve').toList();
    pw.Widget signature(String title, String name, String role, String time) => pw.Expanded(
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 14), pw.Text(_pdfSafe(name), style: const pw.TextStyle(fontSize: 10)),
        pw.Divider(), pw.Text(role, style: const pw.TextStyle(fontSize: 8)),
        pw.Text(time, style: const pw.TextStyle(fontSize: 7)),
      ]));
    return pw.Padding(padding: const pw.EdgeInsets.only(top: 24), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      signature('Prepared by', preparedBy, 'Administrator', approvalTime(approval['submittedAt'])),
      for (final role in ['assistantSecurity', 'areaCommander']) ...[
        pw.SizedBox(width: 32),
        signature(role == 'assistantSecurity' ? 'Approved by' : 'Final approval by',
          decisions.firstWhere((e) => e['role'] == role)['name'], officialRoleLabel(role),
          approvalTime(decisions.firstWhere((e) => e['role'] == role)['at'])),
      ],
    ]));
  }

  // Closes the report with three evenly spaced signature blocks. "Prepared
  // by" is the profile name of whoever produced the schedule (Settings →
  // Profile); the other two come from Settings → Company Info.
  pw.Widget _pdfSignatureBlock(String preparedBy) {
    final signatories = <(String, String)>[
      ('Prepared By:', preparedBy),
      ('Approved by:', ProfileSettings.approvedBy.value),
      ('Endorsed by:', ProfileSettings.endorsedBy.value),
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 30),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < signatories.length; i++) ...[
            // Kept well apart so the three blocks never read as one line.
            if (i > 0) pw.SizedBox(width: 48),
            pw.Expanded(
              child: _pdfSignatory(
                signatories[i].$1,
                signatories[i].$2,
                role: i == 0 ? 'Administrator' : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _pdfSignatory(String label, String name, {String? role}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        // The administrator's saved name sits above the signature line;
        // the other signatories retain their current layout.
        if (role != null)
          pw.Container(
            constraints: const pw.BoxConstraints(minHeight: 30),
            alignment: pw.Alignment.bottomCenter,
            padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
            child: pw.Text(_pdfSafe(name),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black)),
          )
        else
          pw.SizedBox(height: 30),
        pw.Container(height: 0.7, color: PdfColors.grey700),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(_pdfSafe(role ?? name),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: role == null
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: PdfColors.black)),
        ),
      ],
    );
  }

  List<pw.Widget> _pdfShiftBlock(String label, List<GuardEntry> entries) {
    return [
      pw.Text(label,
          style: pw.TextStyle(
              fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      if (entries.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Text('No assignments for this shift.',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600)),
        )
      else
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.TableHelper.fromTextArray(
            headers: const [
              'NO.', 'ID', 'NAME', 'POST', 'TIME', 'NO. OF\nHOURS',
              'DATE', 'RELIEVER', 'SIGNATURE', 'SIGNATURE',
            ],
            data: [
              for (final e in entries)
                [
                  '${e.no}',
                  e.id,
                  e.name,
                  e.post,
                  e.time,
                  e.hours.toStringAsFixed(2),
                  e.date.isEmpty ? '-' : _pdfSafe(e.date),
                  e.reliever.isEmpty ? '-' : _pdfSafe(e.reliever),
                  // Blank cells: signed by hand — regular guard,
                  // then their reliever.
                  '',
                  '',
                ],
            ],
            headerStyle: _pdfHeaderStyle,
            cellStyle: _pdfCellStyle,
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4, vertical: 5),
            border: pw.TableBorder.all(
                color: PdfColors.grey500, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.55),  // NO.
              1: pw.FlexColumnWidth(1.1),   // ID
              2: pw.FlexColumnWidth(2.4),   // NAME
              3: pw.FlexColumnWidth(1.3),   // POST
              4: pw.FlexColumnWidth(1.7),   // TIME
              5: pw.FlexColumnWidth(0.9),   // HOURS
              6: pw.FlexColumnWidth(1.7),   // DATE
              7: pw.FlexColumnWidth(2.0),   // RELIEVER
              8: pw.FlexColumnWidth(1.8),   // SIGNATURE (regular)
              9: pw.FlexColumnWidth(1.8),   // SIGNATURE (reliever)
            },
          ),
        ),
    ];
  }

  pw.Widget _pdfAbsenceTable(List<AbsenceRow> absences) {
    if (absences.isEmpty) {
      return pw.Text('No absences or substitutions recorded for this period.',
          style: const pw.TextStyle(
              fontSize: 8, color: PdfColors.grey600));
    }
    return pw.TableHelper.fromTextArray(
      headers: const [
        'DATE', 'POST', 'TIME', 'NAME', 'REPLACED BY', 'SIGNATURE',
      ],
      data: [
        for (final a in absences)
          [a.dateLabel, a.post, a.time, a.name, a.replacedBy, ''],
      ],
      headerStyle: _pdfHeaderStyle,
      cellStyle: _pdfCellStyle,
      headerDecoration:
          const pw.BoxDecoration(color: PdfColors.grey300),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(2.4),
        4: pw.FlexColumnWidth(2.4),
        5: pw.FlexColumnWidth(2.0),
      },
    );
  }

  // ─────────────────────────────────────────────
  // SCREEN
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _onLeaveReport
                ? _buildLeaveBody()
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Company title card ──
                        _buildKsaHeaderCard(),
                        const SizedBox(height: 20),

                        if (_loadError != null) ...[
                          _buildBanner(
                            icon: Icons.cloud_off_rounded,
                            color: _kAbsence,
                            text:
                                'Backend unreachable — showing sample data. ($_loadError)',
                          ),
                          const SizedBox(height: 20),
                        ] else if (_activeSchedule == null &&
                            !_usingSampleData) ...[
                          _buildBanner(
                            icon: Icons.event_busy_rounded,
                            color: _kTextMuted,
                            text:
                                'No schedule found for ${_station.name} · ${_period.label}. Create one from Generate Schedule.',
                          ),
                          const SizedBox(height: 20),
                        ] else if (_activeSchedule == null &&
                            _usingSampleData) ...[
                          _buildBanner(
                            icon: Icons.info_outline_rounded,
                            color: _kTextMuted,
                            text:
                                'Sample layout — no schedules stored yet. Create one from Generate Schedule to see real data.',
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Period + station label ──
                        _buildPeriodStationLabel(),
                        const SizedBox(height: 20),

                        if (!_data.isEmpty) ...[
                          // ── Morning Shift ──
                          _buildShiftSection(
                            label:   'Morning Shift',
                            time:    '0500H – 1400H',
                            color:   const Color(0xFF1D4ED8),
                            icon:    Icons.wb_sunny_rounded,
                            entries: _data.morning,
                          ),
                          const SizedBox(height: 28),

                          // ── Afternoon Shift ──
                          _buildShiftSection(
                            label:   'Afternoon Shift',
                            time:    '1400H – 2330H',
                            color:   const Color(0xFF0369A1),
                            icon:    Icons.wb_cloudy_rounded,
                            entries: _data.afternoon,
                          ),
                          const SizedBox(height: 28),

                          // ── Night Shift ──
                          _buildShiftSection(
                            label:   'Night Shift',
                            time:    '2100H – 0500H',
                            color:   const Color(0xFF065F46),
                            icon:    Icons.nightlight_rounded,
                            entries: _data.night,
                          ),
                          const SizedBox(height: 28),

                          // ── Absence & Substitution Log ──
                          _buildAbsenceSection(),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: color,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────
  Widget _buildTopBar() {
    Widget field(String label, Widget control) => Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _kTextMuted, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8), control,
    ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _kBorder))),
      child: Wrap(spacing: 20, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _buildReportSwitch(),
        if (!_onLeaveReport) ...[
          field('Station', _buildDropdown<StationInfo>(value: _station, width: 240,
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (value) => setState(() { _station = value!; _refreshData(); }))),
          field('Period', _buildDropdown<ReportPeriod>(value: _period, width: 210,
            items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (value) => setState(() { _period = value!; _refreshData(); }))),
          _buildExportSplitButton(),
        ] else ...[
          field('Year', _buildDropdown<int>(value: _leaveYear, width: 120,
            items: _leaveYears.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
            onChanged: (value) => setState(() => _leaveYear = value!))),
          field('Status', _buildDropdown<String>(value: _leaveStatus, width: 160,
            items: _kLeaveStatuses.map((status) => DropdownMenuItem(value: status, child: Text(status))).toList(),
            onChanged: (value) => setState(() => _leaveStatus = value!))),
          IconButton(onPressed: _loadLeaves, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, color: _kAccent)),
          _buildLeaveExportButton(),
        ],
      ]),
    );
  }

  // The two-report segment. Deliberately in the top bar rather than as a
  // tab: it swaps the filters beside it and the export button after it,
  // so it reads as the thing that governs the whole row.
  Widget _buildReportSwitch() {
    Widget segment(ReportKind kind, IconData icon, String label) {
      final selected = _kind == kind;
      return InkWell(
        onTap: () => setState(() => _kind = kind),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? const [
                    BoxShadow(color: Color(0x14000000),
                        blurRadius: 4, offset: Offset(0, 1)),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15,
                  color: selected ? _kAccent : _kTextMuted),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? _kText : _kTextMuted)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(ReportKind.schedule, Icons.calendar_month_rounded,
              'Schedule Report'),
          const SizedBox(width: 3),
          segment(ReportKind.leave, Icons.beach_access_rounded,
              'Leave Report'),
        ],
      ),
    );
  }

  // ── Company title card (centered) ─────────────
  Widget _buildKsaHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000),
              blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: const Column(
        children: [
          Text(_kCompanyLine1,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                  color: _kText, letterSpacing: 0.4)),
          SizedBox(height: 3),
          Text(_kCompanyLine2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                  color: _kText, letterSpacing: 0.4)),
          SizedBox(height: 4),
          Text('Bi-Weekly Schedule Report',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _kTextMuted)),
        ],
      ),
    );
  }

  // ── Period + station label ────────────────────
  Widget _buildPeriodStationLabel() {
    final total = _data.morning.length +
        _data.afternoon.length +
        _data.night.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4, height: 28,
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _period.label,
              style: const TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w800, color: _kText),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$total',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: _kAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            _station.label,
            style: const TextStyle(fontSize: 13,
                color: _kTextMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  // ── Shift section ─────────────────────────────
  Widget _buildShiftSection({
    required String            label,
    required String            time,
    required Color             color,
    required IconData          icon,
    required List<GuardEntry>  entries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shift label row
        Row(
          children: [
            Text(label,
                style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${entries.length}',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: color)),
            ),
            const SizedBox(width: 10),
            Text(time,
                style: const TextStyle(fontSize: 12,
                    color: _kTextMuted, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 10),
        // Table
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            children: [
              _buildTableHeader(color),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No assignments for this shift.',
                      style: TextStyle(fontSize: 13,
                          color: Colors.grey[500])),
                )
              else
                ...entries.asMap().entries.map(
                        (e) => _buildTableRow(e.key, e.value, color)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Table header ──────────────────────────────
  Widget _buildTableHeader(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          _hCell('NO.',         flex: 1, color: color),
          _hCell('ID',          flex: 2, color: color),
          _hCell('NAME',        flex: 5, color: color),
          _hCell('POST',        flex: 3, color: color),
          _hCell('TIME',        flex: 3, color: color),
          _hCell('NO. OF HOURS',flex: 3, color: color),
          _hCell('DATE',        flex: 3, color: color),
          _hCell('RELIEVER',    flex: 4, color: color),
        ],
      ),
    );
  }

  Widget _hCell(String label, {required int flex, required Color color}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color, letterSpacing: 0.3)),
    );
  }

  // ── Table row ─────────────────────────────────
  Widget _buildTableRow(int index, GuardEntry e, Color shiftColor) {
    final isAlt = index % 2 == 1;
    final bg    = isAlt ? _kSurface : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
            bottom: BorderSide(color: _kBorder, width: 0.6)),
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        children: [
          // No.
          Expanded(
            flex: 1,
            child: Text('${e.no}',
                style: const TextStyle(fontSize: 13,
                    color: _kTextMuted, fontWeight: FontWeight.w500)),
          ),
          // ID
          Expanded(
            flex: 2,
            child: Text(e.id,
                style: const TextStyle(fontSize: 13, color: _kTextMuted)),
          ),
          // Name
          Expanded(
            flex: 5,
            child: Text(e.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500, color: _kText)),
          ),
          // Post
          Expanded(
            flex: 3,
            child: Text(e.post,
                style: const TextStyle(
                    fontSize: 13, color: _kTextMuted)),
          ),
          // Time
          Expanded(
            flex: 3,
            child: Text(e.time,
                style: const TextStyle(
                    fontSize: 13, color: _kTextMuted)),
          ),
          // No. of Hours
          Expanded(
            flex: 3,
            child: Text(e.hours.toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 13, color: _kText,
                    fontWeight: FontWeight.w500)),
          ),
          // Date (day-offs)
          Expanded(
            flex: 3,
            child: Text(
              e.date.isEmpty ? '–' : e.date,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: e.hasReliever
                      ? _kRelText : _kTextMuted,
                  fontWeight: e.hasReliever
                      ? FontWeight.w600 : FontWeight.normal),
            ),
          ),
          // Reliever
          Expanded(
            flex: 4,
            child: Text(
              e.reliever.isEmpty ? '–' : e.reliever,
              overflow: TextOverflow.ellipsis,
              style: e.reliever.isEmpty
                  ? TextStyle(fontSize: 13, color: Colors.grey[400])
                  : TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600, color: shiftColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Absence & Substitution Log ────────────────
  Widget _buildAbsenceSection() {
    final absences = _data.absences;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_off_rounded,
                size: 18, color: _kAbsence),
            const SizedBox(width: 8),
            const Text('Absence & Substitution Log',
                style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700, color: _kAbsence)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _kAbsence.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${absences.length}',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: _kAbsence)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _kBorder)),
                ),
                child: Row(
                  children: [
                    _hCell('DATE',        flex: 2, color: _kAbsence),
                    _hCell('POST',        flex: 3, color: _kAbsence),
                    _hCell('TIME',        flex: 3, color: _kAbsence),
                    _hCell('NAME',        flex: 5, color: _kAbsence),
                    _hCell('REPLACED BY', flex: 5, color: _kAbsence),
                  ],
                ),
              ),
              if (absences.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      'No absences or substitutions recorded for this period.',
                      style: TextStyle(fontSize: 13,
                          color: Colors.grey[500])),
                )
              else
                ...absences.asMap().entries.map(
                        (e) => _buildAbsenceRow(e.key, e.value)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAbsenceRow(int index, AbsenceRow a) {
    final isAlt = index % 2 == 1;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: isAlt ? _kSurface : Colors.white,
        border: const Border(
            bottom: BorderSide(color: _kBorder, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(a.dateLabel,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: _kRelText)),
          ),
          Expanded(
            flex: 3,
            child: Text(a.post,
                style: const TextStyle(fontSize: 13, color: _kTextMuted)),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.time,
                    style: const TextStyle(fontSize: 13, color: _kTextMuted)),
                if (a.retimedFrom != null)
                  Text('post ${a.retimedFrom} · +1 hr to report',
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          fontStyle: FontStyle.italic,
                          color: _kAbsence)),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(a.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500, color: _kText)),
          ),
          Expanded(
            flex: 5,
            child: Text(a.replacedBy,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: _kAbsence)),
          ),
        ],
      ),
    );
  }

  // ── Export split button (PopupMenuButton style) ──
  Widget _buildExportSplitButton() {
    if (_activeSchedule?.canExport != true || _loading || _loadError != null || _exporting) {
      return Tooltip(message: _exporting ? 'Preparing approved PDF' : 'Both officials must approve the period before export.',
        child: OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.lock_outline),
          label: Text(_exporting ? 'Preparing PDF' : 'Awaiting Approval')));
    }
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _kAccent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main action — Export current station
          InkWell(
            onTap: _handleExportSingle,
            borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8)),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 16, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_rounded,
                      size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Export PDF',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
          // Divider
          Container(width: 1, height: 22,
              color: Colors.white.withOpacity(0.3)),
          // Dropdown trigger
          PopupMenuButton<String>(
            tooltip: 'More export options',
            offset: const Offset(0, 44),
            color: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding: EdgeInsets.zero,
            onSelected: (value) {
              if (value == 'single') _handleExportSingle();
              if (value == 'all')    _handleExportAll();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'single',
                height: 44,
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        size: 17, color: _kAccent),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Export PDF',
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kText)),
                        Text('Current station only',
                            style: TextStyle(fontSize: 10.5,
                                color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'all',
                height: 44,
                child: Row(
                  children: [
                    const Icon(Icons.layers_outlined,
                        size: 17, color: _kAccent),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Export All PDF',
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kText)),
                        Text('All stations · combined',
                            style: TextStyle(fontSize: 10.5,
                                color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dropdown helper ───────────────────────────
  Widget _buildDropdown<T>({
    required T value, required double width,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    // `width` is the preferred width, not a hard one: on a narrow window the
    // dropdown shrinks (down to 110px) so the top bar can't overflow.
    return Flexible(
      child: Container(
      constraints: BoxConstraints(minWidth: 110, maxWidth: width),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value, isDense: true, isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down,
              color: _kTextMuted, size: 18),
          style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: _kText),
          items: items, onChanged: onChanged,
        ),
      ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LEAVE REPORT
  // ─────────────────────────────────────────────
  // Company-wide and yearly, where the schedule report is per station and
  // per bi-week — so it brings its own filters, table and PDF rather than
  // being squeezed into the bi-weekly one. Only the page chrome, the
  // company header and the signature block are shared.

  Color _leaveStatusColor(LeaveRequest l) {
    switch (l.phase) {
      case 'active':
        return const Color(0xFF0D9488);
      case 'upcoming':
        return const Color(0xFF16A34A);
      case 'completed':
        return _kTextMuted;
      case 'denied':
        return const Color(0xFFDC2626);
      case 'cancelled':
        return _kTextMuted;
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Widget _buildLeaveBody() {
    if (_leavesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final rows = _visibleLeaves;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLeaveHeaderCard(),
          const SizedBox(height: 20),

          if (_leaveError != null) ...[
            _buildBanner(
              icon: Icons.cloud_off_rounded,
              color: _kAbsence,
              text: 'Backend unreachable — no leave records loaded. '
                  '($_leaveError)',
            ),
            const SizedBox(height: 20),
          ],

          _buildLeaveSummary(rows),
          const SizedBox(height: 20),
          _buildLeaveTable(rows),
        ],
      ),
    );
  }

  Widget _buildLeaveHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000),
              blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: const Column(
        children: [
          Text(_kCompanyLine1,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                  color: _kText, letterSpacing: 0.4)),
          SizedBox(height: 3),
          Text(_kCompanyLine2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                  color: _kText, letterSpacing: 0.4)),
          SizedBox(height: 4),
          Text('Employee Leave Report',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _kTextMuted)),
        ],
      ),
    );
  }

  // Year headline plus the counts an admin actually scans for: how many
  // leaves, how many people, how many days, how many still pending.
  Widget _buildLeaveSummary(List<LeaveRequest> rows) {
    final employees = rows.map((l) => l.employeeId).toSet().length;
    final days = rows
        .where((l) => l.isApproved)
        .fold<int>(0, (sum, l) => sum + l.days);
    final pending = rows.where((l) => l.isPending).length;
    final onLeave = rows.where((l) => l.isOnLeaveNow).length;

    Widget stat(String value, String label, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11.5, color: _kTextMuted)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4, height: 28,
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text('$_leaveYear',
                style: const TextStyle(fontSize: 22,
                    fontWeight: FontWeight.w800, color: _kText)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${rows.length}',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: _kAccent)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            _leaveStatus == 'All'
                ? 'All leave records'
                : '$_leaveStatus only',
            style: const TextStyle(fontSize: 13,
                color: _kTextMuted, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Expanded(child: stat('$employees', 'Employees', _kText)),
              Expanded(child: stat('$days', 'Approved leave days', _kText)),
              Expanded(child: stat('$onLeave', 'On leave today',
                  const Color(0xFF0D9488))),
              Expanded(child: stat('$pending', 'Awaiting decision',
                  const Color(0xFFF59E0B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveTable(List<LeaveRequest> rows) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              children: [
                _hCell('NO.',         flex: 1, color: _kAccent),
                _hCell('ID',          flex: 2, color: _kAccent),
                _hCell('NAME',        flex: 4, color: _kAccent),
                _hCell('ROLE',        flex: 3, color: _kAccent),
                _hCell('STATION',     flex: 3, color: _kAccent),
                _hCell('LEAVE TYPE',  flex: 3, color: _kAccent),
                _hCell('DURATION',    flex: 4, color: _kAccent),
                _hCell('DAYS',        flex: 1, color: _kAccent),
                _hCell('STATUS',      flex: 2, color: _kAccent),
                _hCell('ENDORSED BY', flex: 3, color: _kAccent),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'No leave records for $_leaveYear'
                  '${_leaveStatus == 'All' ? '' : ' · $_leaveStatus'}.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            )
          else
            ...rows.asMap().entries.map(
                (e) => _buildLeaveRow(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildLeaveRow(int index, LeaveRequest l) {
    final color = _leaveStatusColor(l);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: index % 2 == 1 ? _kSurface : Colors.white,
        border: const Border(
            bottom: BorderSide(color: _kBorder, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text('${index + 1}',
                style: const TextStyle(fontSize: 13,
                    color: _kTextMuted, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 2,
            child: Text(l.employeeId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _kTextMuted)),
          ),
          Expanded(
            flex: 4,
            child: Text(l.employeeName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500, color: _kText)),
          ),
          Expanded(
            flex: 3,
            child: Text(l.roleLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _kTextMuted)),
          ),
          Expanded(
            flex: 3,
            child: Text(l.station.isEmpty ? '–' : l.station,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _kTextMuted)),
          ),
          Expanded(
            flex: 3,
            child: Text(l.leaveType,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _kTextMuted)),
          ),
          Expanded(
            flex: 4,
            child: Text(l.rangeLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500, color: _kText)),
          ),
          Expanded(
            flex: 1,
            child: Text('${l.days}',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: _kText)),
          ),
          Expanded(
            flex: 2,
            child: Text(l.statusLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: color)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              l.supervisorName.isEmpty ? '–' : l.supervisorName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      l.wasEndorsed ? FontWeight.w600 : FontWeight.normal,
                  color: l.wasEndorsed
                      ? const Color(0xFF6D28D9)
                      : Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Leave export ──────────────────────────────

  Widget _buildLeaveExportButton() {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: _showLeaveExportConfirmation,
        icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
        label: const Text('Export Leave PDF'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _showLeaveExportConfirmation() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded,
                  color: _kAccent, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Export Leave Report',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w800, color: _kText)),
            ),
          ],
        ),
        content: Text(
          'Export the employee leave report for $_leaveYear'
          '${_leaveStatus == 'All' ? '' : ' ($_leaveStatus only)'} as a PDF? '
          'This is separate from the bi-weekly schedule report.',
          style: const TextStyle(fontSize: 13.5,
              color: _kTextMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              foregroundColor: _kTextMuted,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmExportLeave();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExportLeave() async {
    final rows = _visibleLeaves;
    if (rows.isEmpty) {
      _showSnack('Nothing to export — no leave records for $_leaveYear.',
          success: false);
      return;
    }

    try {
      final doc = pw.Document();
      _addLeavePages(doc, rows,
          printedAt: DateTime.now(), preparedBy: ProfileSettings.preparedBy);
      final statusSlug = _leaveStatus == 'All'
          ? 'all'
          : _leaveStatus.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'leave-report-$_leaveYear-$statusSlug.pdf',
      );
      if (!mounted) return;
      _showSnack('PDF generated — ${rows.length} leave record'
          '${rows.length == 1 ? '' : 's'} for $_leaveYear');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to generate PDF: $e', success: false);
    }
  }

  void _addLeavePages(
    pw.Document doc,
    List<LeaveRequest> rows, {
    required DateTime printedAt,
    required String preparedBy,
  }) {
    final employees = rows.map((l) => l.employeeId).toSet().length;
    final approvedDays = rows
        .where((l) => l.isApproved)
        .fold<int>(0, (sum, l) => sum + l.days);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Leave Report $_leaveYear - page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        pw.Center(
          child: pw.Text(_kCompanyLine1,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(_kCompanyLine2,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text('Employee Leave Report',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey700)),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                  'Year $_leaveYear'
                  '${_leaveStatus == 'All' ? '' : '   -   $_leaveStatus only'}',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 16),
            _pdfPrintedAt(printedAt),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
            '${rows.length} leave record(s)  -  $employees employee(s)  -  '
            '$approvedDays approved leave day(s)',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),

        pw.TableHelper.fromTextArray(
          headers: const [
            'NO.', 'ID', 'NAME', 'ROLE', 'STATION', 'LEAVE TYPE',
            'FROM', 'TO', 'DAYS', 'STATUS', 'APPROVED BY', 'ENDORSED BY',
          ],
          data: [
            for (int i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                rows[i].employeeId,
                _pdfSafe(rows[i].employeeName),
                rows[i].roleLabel,
                rows[i].station.isEmpty ? '-' : _pdfSafe(rows[i].station),
                _pdfSafe(rows[i].leaveType),
                _pdfSafe(LeaveRequest.formatShort(rows[i].startDate)),
                _pdfSafe(LeaveRequest.formatShort(rows[i].endDate)),
                '${rows[i].days}',
                rows[i].statusLabel,
                _pdfSafe(rows[i].decidedBy ?? '-'),
                rows[i].supervisorName.isEmpty
                    ? '-'
                    : _pdfSafe(rows[i].supervisorName),
              ],
          ],
          headerStyle: _pdfHeaderStyle,
          cellStyle: _pdfCellStyle,
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey300),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4, vertical: 5),
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),   // NO.
            1: pw.FlexColumnWidth(1.1),   // ID
            2: pw.FlexColumnWidth(2.3),   // NAME
            3: pw.FlexColumnWidth(1.6),   // ROLE
            4: pw.FlexColumnWidth(1.7),   // STATION
            5: pw.FlexColumnWidth(1.8),   // LEAVE TYPE
            6: pw.FlexColumnWidth(1.0),   // FROM
            7: pw.FlexColumnWidth(1.0),   // TO
            8: pw.FlexColumnWidth(0.6),   // DAYS
            9: pw.FlexColumnWidth(1.2),   // STATUS
            10: pw.FlexColumnWidth(1.5),  // APPROVED BY
            11: pw.FlexColumnWidth(1.7),  // ENDORSED BY
          },
        ),

        // Leave granted past its type's cap is the part a reader has to
        // be able to audit, so the endorsement behind each one is spelled
        // out rather than left as a name in a column.
        ..._pdfEndorsementNotes(rows),

        _pdfSignatureBlock(preparedBy),
      ],
    ));
  }

  List<pw.Widget> _pdfEndorsementNotes(List<LeaveRequest> rows) {
    final endorsed = rows.where((l) => l.wasEndorsed).toList();
    if (endorsed.isEmpty) return [];
    return [
      pw.SizedBox(height: 12),
      pw.Text('LEAVE ENDORSED BY A HIGHER AUTHORITY',
          style: pw.TextStyle(
              fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      for (final l in endorsed)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            _pdfSafe(
                '${l.employeeName} (${l.employeeId})  -  ${l.leaveType}, '
                '${l.days} day(s)  -  endorsed by ${l.supervisorName}'
                '${l.brokeRules ? '  -  waived: ${l.overriddenRules.join(", ")}' : ''}'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
          ),
        ),
    ];
  }
}
