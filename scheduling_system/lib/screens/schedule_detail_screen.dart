// screens/schedule_detail_screen.dart
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/post_time.dart';
import '../models/schedule.dart';
import '../models/station.dart';
import '../services/api_service.dart';
import 'main_layout.dart';
import '../models/schedule_approval.dart';

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _shortDate(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}';

// Internal row model just for the duty-roster table below.
// Kept separate from ScheduleEntry so editing here doesn't require
// touching the shared Schedule model used by other screens.
class _DutyRow {
  final int no;

  // The schedule's shift label for this row: 'Morning' | 'Afternoon' |
  // 'Night' | 'HG Day' | 'HG Night'. Every rule in the edit dialog reads
  // off this — it decides which role may HOLD the post and which may
  // RELIEVE it, so a row can never quietly change role.
  final String shift;

  String employeeId;
  String employeeName;
  String post;
  String time;
  double hours;
  List<DateTime> offDates;

  // The guard covering this row's day-offs. The id is what the server
  // stores; the name is only what the table prints. The generator binds
  // one reliever to a guard's whole run of day-offs, so this is normally
  // the only name there is.
  String? relieverId;
  String? reliever;

  // Every guard who covered some of this row's day-offs, with how many
  // each took, longest first. Normally one entry — but a guard on LEAVE
  // is off for more days than any one reliever may work, so their days
  // are split across the station's roster and this row genuinely has
  // several. Printing only the first (which is what this table used to
  // do) read as one reliever working the whole absence: a 13-day leave
  // showed thirteen dates against a single name who in fact worked one
  // of them.
  List<_CoverShare> covers;

  _DutyRow({
    required this.no,
    required this.shift,
    required this.employeeId,
    required this.employeeName,
    required this.post,
    required this.time,
    required this.hours,
    required this.offDates,
    this.relieverId,
    this.reliever,
    List<_CoverShare>? covers,
  }) : covers = covers ?? const [];

  String get dateLabel => offDates.map(_shortDate).join(' · ');

  // What the RELIEVER column prints: the name on its own when one guard
  // covered the whole run, and "Name (n days)" per guard when it was
  // split, so the count can be reconciled against the DATE column.
  String get relieverLabel {
    if (covers.length <= 1) return reliever ?? '—';
    return covers.map((c) => '${c.name} (${c.days})').join(' · ');
  }
}

// One guard's share of covering another's day-offs.
class _CoverShare {
  final String id;
  final String name;
  final int days;

  const _CoverShare(this.id, this.name, this.days);
}

// The state of one row before an edit, so a save the server rejects can
// put the table back exactly as it was instead of leaving the screen
// showing an assignment that was never stored.
class _RowSnapshot {
  final String employeeId;
  final String employeeName;
  final String post;
  final String time;
  final double hours;
  final List<DateTime> offDates;
  final String? relieverId;
  final String? reliever;
  final List<_CoverShare> covers;

  _RowSnapshot(_DutyRow row)
      : employeeId = row.employeeId,
        employeeName = row.employeeName,
        post = row.post,
        time = row.time,
        hours = row.hours,
        offDates = List.of(row.offDates),
        relieverId = row.relieverId,
        reliever = row.reliever,
        covers = List.of(row.covers);
}

// What the guard picker hands back: a guard, or an explicit "nobody"
// (`employee == null`, offered on the reliever slot only). A null
// _GuardChoice means the admin closed the picker without choosing.
class _GuardChoice {
  final Employee? employee;
  const _GuardChoice(this.employee);
}

class ScheduleDetailScreen extends StatefulWidget {
  final Schedule schedule;
  final bool readOnly;
  final VoidCallback onBack;
  final Function(ScreenType, {dynamic data})? onNavigate;

  const ScheduleDetailScreen({
    super.key,
    required this.schedule,
    this.readOnly = false,
    required this.onBack,
    this.onNavigate,
  });

  @override
  State<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<ScheduleDetailScreen> {
  // Local copy so the Publish button can flip the badge for demo purposes
  // without needing to wire up real persistence yet.
  late ScheduleStatus _status;
  late List<_DutyRow> _morningRows;
  late List<_DutyRow> _afternoonRows;
  late List<_DutyRow> _nightRows;

  // Real employees loaded from the backend, used by the name/reliever
  // pickers in the edit dialog. Empty when the server is down — the
  // pickers then refuse to open and the dialog only edits post, times
  // and day-offs, rather than letting a name through unchecked.
  List<Employee> _employees = [];

  // This schedule's station, for the POST dropdown: the posts a guard may
  // be moved to are exactly the ones the station is set up with for that
  // shift (Edit Station), never free text.
  Station? _station;

  // employeeId -> the station whose schedule already has them on duty
  // somewhere inside this period. Nobody in here can be picked: they'd be
  // rostered in two places at once. The server enforces the same rule on
  // save — this map is only what lets the picker say so up front.
  Map<String, String> _bookedElsewhere = {};

  // Mock reliever names cycled in for display purposes only.
  static const List<String> _relieverPool = [
    'Carlo Cruz', 'Mark Santos', 'Ana Reyes', 'Jojo Bautista'
  ];

  // Mock employee names for the Morning/Afternoon/Night dummy rows below —
  // purely for previewing the shift-grouped layout, not wired to real
  // assignments yet. Swap in real per-shift data when it's available.
  static const List<String> _dummyNamePool = [
    'Juan Dela Cruz', 'Maria Santos', 'Pedro Garcia', 'Liza Ramirez',
    'Carlo Cruz', 'Ana Reyes', 'Mark Santos', 'Jojo Bautista',
  ];

  // Relative column widths — the table stretches to fill the viewport on
  // wide screens and never shrinks below _minTableWidth, scrolling
  // horizontally instead once the screen gets narrower than that.
  static const Map<int, TableColumnWidth> _columnWidths = {
    0: FlexColumnWidth(0.6),  // No.
    1: FlexColumnWidth(0.9),  // ID
    2: FlexColumnWidth(2.0),  // Name
    3: FlexColumnWidth(1.5),  // Post
    4: FlexColumnWidth(1.7),  // Time
    5: FlexColumnWidth(1.1),  // No. of Hours
    6: FlexColumnWidth(1.7),  // Date
    7: FlexColumnWidth(1.8),  // Reliever
  };

  static const double _minTableWidth = 1050;

  // Edit-dialog validation rules.
  static const double _minShiftHours = 9;
  static const double _maxShiftHours = 12;
  static const int _maxOffDates = 5;

  // True when this schedule came from the real backend generator (its
  // entries use the Morning/Afternoon/Night + HG shift labels). Old
  // dummy schedules still fall back to the sample layout below.
  bool get _hasRealRoster => widget.schedule.days.any((d) => d.entries.any(
      (e) => e.shift == 'Night' || e.shift == 'Morning' ||
          e.shift == 'Afternoon' ||
          e.shift == 'HG Day' ||
          e.shift == 'HG Night'));

  // A published roster is read-only, and there is no way back: its
  // guards have already been notified of the assignment they're holding,
  // so a quiet edit here would leave them working off a roster that no
  // longer matches. Publishing is final — the roster is reviewed and
  // fixed before it goes out, not after. The backend refuses the same
  // edits.
  bool get _isLocked => widget.readOnly || widget.schedule.awaitingApproval || _status == ScheduleStatus.published;

  @override
  void initState() {
    super.initState();
    _status = widget.schedule.status;
    if (!widget.readOnly) {
      _loadEmployees();
      _loadStation();
      _loadOtherBookings();
    }
    if (_hasRealRoster || widget.readOnly) {
      _buildRowsFromSchedule();
    } else {
      _morningRows = _buildDummyShiftRows(
        idPrefix: 20,
        shift: 'Morning',
        hgShift: 'HG Day',
        time: '0600H - 1400H',
        hours: 8.0,
      );
      _afternoonRows = _buildDummyShiftRows(
        idPrefix: 30,
        shift: 'Afternoon',
        time: '1400H - 2200H',
        hours: 8.0,
      );
      _nightRows = _buildDummyShiftRows(
        idPrefix: 40,
        shift: 'Night',
        hgShift: 'HG Night',
        time: '2200H - 0600H',
        hours: 8.0,
      );
    }
  }

  Future<void> _loadEmployees() async {
    final result = await ApiService.fetchEmployees();
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _employees = (result['employees'] as List).cast<Employee>();
      });
    }
  }

  // The station behind this schedule, matched by id and falling back to
  // the name for schedules generated before stations carried ids.
  Future<void> _loadStation() async {
    final result = await ApiService.fetchStations();
    if (!mounted || result['success'] != true) return;
    final stations = (result['stations'] as List).cast<Station>();
    final id = widget.schedule.stationId;
    final name = widget.schedule.stationName.trim().toLowerCase();
    Station? byId;
    Station? byName;
    for (final station in stations) {
      if (station.id == id) byId = station;
      if (station.name.trim().toLowerCase() == name) byName ??= station;
    }
    final match = byId ?? byName;
    if (match != null) setState(() => _station = match);
  }

  // Everyone already on duty at another station inside this period. The
  // generator refuses to double-book across stations, so a hand edit has
  // to know about those commitments before it offers someone up.
  Future<void> _loadOtherBookings() async {
    final result = await ApiService.fetchSchedules();
    if (!mounted || result['success'] != true) return;
    final start = widget.schedule.startDate;
    final end = widget.schedule.endDate;
    final booked = <String, String>{};
    for (final other in (result['schedules'] as List).cast<Schedule>()) {
      if (other.id == widget.schedule.id) continue;
      if (other.endDate.isBefore(start) || other.startDate.isAfter(end)) {
        continue;
      }
      for (final day in other.days) {
        for (final entry in day.entries) {
          booked[entry.employeeId] = other.stationName;
        }
      }
    }
    if (!mounted) return;
    setState(() => _bookedElsewhere = booked);
  }

  // Builds the per-employee roster rows from the generated schedule:
  // each own-duty entry places the employee in their shift block; each
  // covering entry (reliever / night switch / substitute HG) fills the
  // covered employee's RELIEVER column; day-offs are the period dates
  // where the employee has no own-duty entry.
  void _buildRowsFromSchedule() {
    final schedule = widget.schedule;
    final allDates = schedule.days.map((d) => d.date).toList();

    final names = <String, String>{};
    final ownShift = <String, String>{};
    final ownPost = <String, String>{};
    // Each guard's own duty window. Posts are staggered per station now,
    // so two guards on the same shift can start two hours apart — the
    // time has to come off the entry, not off the shift name.
    final ownWindow = <String, String>{};
    final ownHours = <String, double>{};
    final presentDates = <String, Set<DateTime>>{};
    // covered employeeId -> the entries covering their day-offs
    final covers = <String, List<ScheduleEntry>>{};

    for (final day in schedule.days) {
      for (final entry in day.entries) {
        names[entry.employeeId] = entry.employeeName;
        if (entry.coveringFor != null) {
          covers.putIfAbsent(entry.coveringFor!, () => []).add(entry);
        } else {
          ownShift[entry.employeeId] = entry.shift;
          if (entry.post != null && entry.post!.isNotEmpty) {
            ownPost[entry.employeeId] = entry.post!;
          }
          final window = entry.window;
          if (window != null) {
            ownWindow[entry.employeeId] = window.range;
            ownHours[entry.employeeId] = window.lengthMinutes / 60.0;
          }
          presentDates.putIfAbsent(entry.employeeId, () => {}).add(day.date);
        }
      }
    }

    List<_DutyRow> rowsFor(List<String> shifts) {
      final employeeIds = ownShift.keys
          .where((id) => shifts.contains(ownShift[id]))
          .toList()
        ..sort((a, b) {
          // Head guard first, then by ID.
          final aHg = ownShift[a]!.startsWith('HG') ? 0 : 1;
          final bHg = ownShift[b]!.startsWith('HG') ? 0 : 1;
          return aHg != bHg ? aHg.compareTo(bHg) : a.compareTo(b);
        });

      final rows = <_DutyRow>[];
      for (final id in employeeIds) {
        final shift = ownShift[id]!;
        final time = ownWindow[id] ?? '';
        final hours = ownHours[id] ?? 0.0;
        final offDates = allDates
            .where((d) => !(presentDates[id]?.contains(d) ?? false))
            .toList();
        // Who covered this guard's day-offs, and how many each took.
        // The generator binds one reliever to the whole run, so this is
        // normally a single name; a guard on leave is the exception and
        // their days really are shared out.
        final tally = <String, _CoverShare>{};
        for (final entry in covers[id] ?? const <ScheduleEntry>[]) {
          final seen = tally[entry.employeeId];
          tally[entry.employeeId] = _CoverShare(
            entry.employeeId,
            entry.employeeName,
            (seen?.days ?? 0) + 1,
          );
        }
        final shares = tally.values.toList()
          ..sort((a, b) => b.days != a.days
              ? b.days.compareTo(a.days)
              : a.name.compareTo(b.name));
        // The guard who took the most of the run is the one an edit acts
        // on — editing sets a single reliever for every day-off, so the
        // dominant name is the one that changes least.
        final cover = shares.isEmpty ? null : shares.first;

        rows.add(_DutyRow(
          no: rows.length + 1,
          shift: shift,
          employeeId: id,
          employeeName: names[id] ?? id,
          // Generated schedules carry the real post per entry; the
          // shift-based label is only the fallback for older data.
          post: ownPost[id] ??
              (shift.startsWith('HG') ? 'Head Guard' : 'Shift Guard'),
          time: time,
          hours: hours,
          offDates: offDates,
          relieverId: cover?.id,
          reliever: cover?.name,
          covers: shares,
        ));
      }
      return rows;
    }

    _morningRows = rowsFor(['HG Day', 'Morning']);
    _afternoonRows = rowsFor(['Afternoon']);
    _nightRows = rowsFor(['HG Night', 'Night']);
  }

  // Dummy duty-roster rows for one shift block (8 people), used purely to
  // preview the Morning/Afternoon/Night layout. Swap this out for real
  // per-shift data once the Schedule model tracks more than Day/Night.
  // [hgShift] gives the block its head-guard row, mirroring the real
  // layout where the day HG leads Morning and the night HG leads Night;
  // the afternoon has none, so it's left null there.
  List<_DutyRow> _buildDummyShiftRows({
    required int idPrefix,
    required String shift,
    String? hgShift,
    required String time,
    required double hours,
  }) {
    final rows = <_DutyRow>[];
    for (int i = 1; i <= 8; i++) {
      // Every third row has no reliever assigned, just to show both states.
      String? reliever;
      if (i % 3 != 0) {
        reliever = _relieverPool[(i - 1) % _relieverPool.length];
      }
      final isHeadGuard = i == 1 && hgShift != null;

      rows.add(_DutyRow(
        no: i,
        shift: isHeadGuard ? hgShift : shift,
        employeeId: '$idPrefix${i.toString().padLeft(2, '0')}',
        employeeName: _dummyNamePool[(i - 1) % _dummyNamePool.length],
        post: isHeadGuard ? kHeadGuardPost : 'Shift Guard',
        time: time,
        hours: hours,
        offDates: [widget.schedule.startDate.add(Duration(days: i - 1))],
        reliever: reliever,
      ));
    }
    return rows;
  }

  String _formatDate(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';



  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
        duration: Duration(seconds: error ? 6 : 3),
      ),
    );
  }

  void _applyRow(_DutyRow row, _RowSnapshot state) {
    row.employeeId = state.employeeId;
    row.employeeName = state.employeeName;
    row.post = state.post;
    row.time = state.time;
    row.hours = state.hours;
    row.offDates = List.of(state.offDates);
    row.relieverId = state.relieverId;
    row.reliever = state.reliever;
    row.covers = List.of(state.covers);
  }

  // Saves a whole edited row to the backend — who holds the post, the
  // post, the duty window, the day-offs and the reliever, in one call.
  // The row is updated locally first so the table never lags behind the
  // dialog, and put back exactly as it was if the server refuses (a role
  // it won't allow, or a guard already booked somewhere in this period).
  Future<void> _saveAssignment(
    _DutyRow row, {
    required String employeeId,
    required String employeeName,
    required String post,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required double hours,
    required List<DateTime> offDates,
    String? relieverId,
    String? relieverName,
  }) async {
    final before = _RowSnapshot(row);
    setState(() {
      row.employeeId = employeeId;
      row.employeeName = employeeName;
      row.post = post;
      row.time = '${_formatTime(startTime)} - ${_formatTime(endTime)}';
      row.hours = hours;
      row.offDates = List.of(offDates)..sort();
      row.relieverId = relieverId;
      row.reliever = relieverName;
      // An edit sets ONE reliever for every day-off on the row, so a run
      // that had been split between several collapses to that guard.
      row.covers = relieverId == null || relieverName == null
          ? const []
          : [_CoverShare(relieverId, relieverName, row.offDates.length)];
    });

    // Sample schedules have nothing behind them to save to.
    if (!_hasRealRoster || widget.schedule.id.isEmpty) {
      _toast('Assignment updated');
      return;
    }

    final result = await ApiService.updateScheduleAssignment(
      scheduleId: widget.schedule.id,
      employeeId: before.employeeId,
      newEmployeeId:
          employeeId == before.employeeId ? null : employeeId,
      post: post,
      timeIn: _hhmm(startTime),
      timeOut: _hhmm(endTime),
      offDates: row.offDates.map(_isoDate).toList(),
      relieverId: relieverId,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      _toast('Assignment saved');
      return;
    }
    setState(() => _applyRow(row, before));
    _toast('Not saved: ${result['error']}', error: true);
  }

  // --- Edit dialog helpers ---

  // Parses one side of a "0500H - 1400H" string. index 0 = start, 1 = end.
  TimeOfDay? _parseTimePart(String time, int index) {
    final parts = time.split('-');
    if (parts.length <= index) return null;
    final digits = RegExp(r'\d{3,4}').firstMatch(parts[index].trim())?.group(0);
    if (digits == null) return null;
    final padded = digits.padLeft(4, '0');
    final h = int.parse(padded.substring(0, 2));
    final m = int.parse(padded.substring(2));
    if (h > 23 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}H';

  // Duty length in hours; an end time at or before the start time is
  // treated as crossing midnight (e.g. 2100H - 0500H = 8 hours).
  double _hoursBetween(TimeOfDay start, TimeOfDay end) {
    var mins = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);
    if (mins <= 0) mins += 24 * 60;
    return mins / 60.0;
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // --- Role rules ---
  //
  // A row's shift decides both halves of the rule: who may HOLD the post
  // and who may RELIEVE it. Head Guard rows are head-guard-only on both
  // sides — a reliever cannot man the Head Guard post, so a head guard's
  // day-off is covered by another head guard, exactly as the generator
  // does it from the floating substitute pool.

  static bool _isHgShift(String shift) => shift.startsWith('HG');

  static EmployeeType _holderTypeFor(String shift) =>
      _isHgShift(shift) ? EmployeeType.headGuard : EmployeeType.regular;

  static EmployeeType _coverTypeFor(String shift) =>
      _isHgShift(shift) ? EmployeeType.headGuard : EmployeeType.reliever;

  static String _holderLabelFor(String shift) =>
      _isHgShift(shift) ? 'Head Guard Name' : 'Regular Name';

  static String _coverLabelFor(String shift) =>
      _isHgShift(shift) ? 'Substitute Head Guard' : 'Reliever Name';

  // The station-setup key behind a schedule's shift label. HG Day leads
  // the morning list and HG Night the night one, which is where their
  // Head Guard slot lives.
  static String _shiftKeyFor(String shift) {
    switch (shift) {
      case 'Afternoon':
        return 'afternoon';
      case 'Night':
      case 'HG Night':
        return 'night';
      default:
        return 'morning';
    }
  }

  List<_DutyRow> get _allRows =>
      [..._morningRows, ..._afternoonRows, ..._nightRows];

  // Why this guard can't take that slot, or null when they're free.
  //
  // There are two ways to already have a schedule: holding a post or
  // relieving one on THIS roster, or being on duty at another station in
  // the same period. Whoever already sits in the slot being edited is of
  // course still allowed to stay in it.
  String? _unavailableReason(
    Employee employee,
    _DutyRow row, {
    required bool asReliever,
  }) {
    for (final other in _allRows) {
      final holds = other.employeeId == employee.id;
      final relieves = other.relieverId == employee.id;
      if (!holds && !relieves) continue;
      if (identical(other, row)) {
        if (holds) {
          return asReliever
              ? 'Holds this post — nobody relieves themselves'
              : null;
        }
        return asReliever ? null : 'Already relieving this post';
      }
      return holds
          ? 'Already assigned · ${other.post} (${other.shift})'
          : 'Already relieving ${other.employeeName}';
    }
    final station = _bookedElsewhere[employee.id];
    if (station != null) return 'Already on duty · $station';
    return null;
  }

  // The posts this row may be moved to: exactly what the station is set
  // up with for that shift (Edit Station), never free text — typing was
  // what let stray post names and Undefined survive. The Head Guard slot
  // is excluded from the shift rows; it belongs to the HG rows, which
  // can't be re-posted at all.
  List<String> _postOptionsFor(_DutyRow row) {
    if (_isHgShift(row.shift)) return const [kHeadGuardPost];
    final posts =
        _station?.postsFor(_shiftKeyFor(row.shift)) ?? const <String>[];
    final options = <String>{
      for (final p in posts)
        if (p.isNotEmpty && p != kHeadGuardPost) p,
    }.toList();
    // Whatever the row is on now stays selectable even when the station's
    // setup has moved on since the schedule was generated — otherwise
    // simply opening the dialog would re-post the guard.
    if (row.post.isNotEmpty && !options.contains(row.post)) {
      options.insert(0, row.post);
    }
    return options;
  }

  // The window the station's ladder gives that post, so picking a post
  // fills Time In/Out with the hours it is actually manned for.
  PostTime? _windowForPost(String shift, String post) {
    if (_isHgShift(shift)) return baseShiftWindow(shift);
    final station = _station;
    if (station == null) return null;
    final key = _shiftKeyFor(shift);
    final index = station.postsFor(key).indexOf(post);
    if (index < 0) return null;
    final times = station.postTimesFor(key);
    return index < times.length ? times[index] : null;
  }

  static TimeOfDay _toTimeOfDay(int minutes) =>
      TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60);

  // Tap-to-open guard picker. Shows the WHOLE pool for the role this slot
  // takes — no typing needed to see who's there — and keeps the ones who
  // can't be picked visible but disabled, with the reason spelled out,
  // rather than hiding them and leaving the admin wondering.
  // [pendingBlocks] is id -> reason for picks the open edit dialog has
  // made but not yet saved — the other half of the same row. Without it
  // the admin could set a guard as the holder and then, in the same
  // dialog, pick them again as their own reliever.
  Future<_GuardChoice?> _pickGuard({
    required BuildContext context,
    required _DutyRow row,
    required bool asReliever,
    required String? selectedId,
    Map<String, String> pendingBlocks = const {},
  }) {
    final role = asReliever ? _coverTypeFor(row.shift) : _holderTypeFor(row.shift);
    final roleName = employeeTypeToRoleString(role);
    final pool = _employees.where((e) => e.type == role && e.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    var query = '';

    return showDialog<_GuardChoice>(
      context: context,
      builder: (pickerContext) {
        return StatefulBuilder(
          builder: (pickerContext, setPickerState) {
            final q = query.trim().toLowerCase();
            final matches = pool
                .where((e) =>
                    q.isEmpty ||
                    e.name.toLowerCase().contains(q) ||
                    e.id.toLowerCase().contains(q))
                .toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: Text(
                asReliever
                    ? 'Select ${_coverLabelFor(row.shift)}'
                    : 'Select ${_holderLabelFor(row.shift)}',
                style: const TextStyle(fontSize: 18),
              ),
              content: SizedBox(
                width: 460,
                height: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asReliever
                          ? 'Only a ${roleName.toLowerCase()} can cover a '
                              '${row.shift} day-off.'
                          : 'Only a ${roleName.toLowerCase()} can hold the '
                              '${row.post} post on ${row.shift}.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search by name or ID',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setPickerState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: matches.isEmpty
                          ? Center(
                              child: Text(
                                pool.isEmpty
                                    ? 'No active ${roleName.toLowerCase()} '
                                        'found.'
                                    : 'No match for "$query".',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[600]),
                              ),
                            )
                          : ListView.separated(
                              itemCount: matches.length,
                              separatorBuilder: (context, index) =>
                                  Divider(height: 1, color: Colors.grey[200]),
                              itemBuilder: (context, index) {
                                final e = matches[index];
                                return _guardTile(
                                  e,
                                  row,
                                  asReliever: asReliever,
                                  isSelected: e.id == selectedId,
                                  pendingBlocks: pendingBlocks,
                                  onPick: () => Navigator.pop(
                                      pickerContext, _GuardChoice(e)),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(pickerContext),
                  child: const Text('Cancel'),
                ),
                if (asReliever)
                  TextButton(
                    onPressed: () => Navigator.pop(
                        pickerContext, const _GuardChoice(null)),
                    child: const Text('No reliever'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _guardTile(
    Employee employee,
    _DutyRow row, {
    required bool asReliever,
    required bool isSelected,
    required VoidCallback onPick,
    Map<String, String> pendingBlocks = const {},
  }) {
    final blocked = pendingBlocks[employee.id] ??
        _unavailableReason(employee, row, asReliever: asReliever);
    final available = blocked == null;

    return ListTile(
      dense: true,
      enabled: available,
      selected: isSelected,
      selectedTileColor: const Color(0xFF1034A6).withOpacity(0.06),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: available
            ? const Color(0xFF1034A6).withOpacity(0.1)
            : Colors.grey[200],
        child: Text(
          employee.initials,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: available ? const Color(0xFF1034A6) : Colors.grey[500],
          ),
        ),
      ),
      title: Text(
        employee.name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: available ? const Color(0xFF1E293B) : Colors.grey[500],
        ),
      ),
      subtitle: Text(
        available
            ? '${employee.id} · ${employeeTypeToRoleString(employee.type)}'
            : '${employee.id} · $blocked',
        style: TextStyle(
          fontSize: 11,
          color: available ? Colors.grey[600] : const Color(0xFFB45309),
        ),
      ),
      trailing: available
          ? (isSelected
              ? const Icon(Icons.check_circle,
                  size: 18, color: Color(0xFF059669))
              : null)
          : const Icon(Icons.block, size: 16, color: Color(0xFFD97706)),
      onTap: available ? onPick : null,
    );
  }

  Widget _timeField(
    BuildContext dialogContext,
    String label,
    TimeOfDay value,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked =
            await showTimePicker(context: dialogContext, initialTime: value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.access_time, size: 18),
        ),
        child: Text(_formatTime(value), style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  void _editRow(_DutyRow row) {
    // Rows aren't tappable while published, but keep the rule here too so
    // no other path can open the dialog on a locked roster.
    if (_isLocked) {
      _toast('This schedule is published — its assignments are locked and '
          'can no longer be edited.');
      return;
    }
    // The row's shift — not its current post — decides the rules, so a
    // Head Guard row stays a head guard's even while it's being edited.
    final isHeadGuard = _isHgShift(row.shift);
    final postOptions = _postOptionsFor(row);
    final canPickGuards = _employees.isNotEmpty;

    // Held as ids, so Save sends the person who was actually picked
    // rather than a typed name that happened to look like somebody.
    String holderId = row.employeeId;
    String holderName = row.employeeName;
    String? coverId = row.relieverId;
    String? coverName = row.reliever;

    String post = postOptions.contains(row.post)
        ? row.post
        : (postOptions.isEmpty ? row.post : postOptions.first);
    TimeOfDay startTime =
        _parseTimePart(row.time, 0) ?? const TimeOfDay(hour: 5, minute: 0);
    TimeOfDay endTime =
        _parseTimePart(row.time, 1) ?? const TimeOfDay(hour: 14, minute: 0);
    final offDates = List<DateTime>.from(row.offDates)..sort();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final hours = _hoursBetween(startTime, endTime);
            final hoursValid =
                hours >= _minShiftHours && hours <= _maxShiftHours;
            final canSave =
                hoursValid && post.trim().isNotEmpty && holderId.isNotEmpty;

            // Tap-to-select guard slot. Opens the role-filtered picker;
            // the other slot's pending pick is passed along so the two
            // halves of one row can't both land on the same person
            // before anything is even saved.
            Widget guardField({
              required String label,
              required String? name,
              required String? id,
              required bool asReliever,
            }) {
              final empty = name == null || name.isEmpty;
              return InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: !canPickGuards
                    ? null
                    : () async {
                        final choice = await _pickGuard(
                          context: dialogContext,
                          row: row,
                          asReliever: asReliever,
                          selectedId: id,
                          pendingBlocks: asReliever
                              ? {
                                  if (holderId.isNotEmpty)
                                    holderId:
                                        'Holds this post — nobody relieves '
                                            'themselves',
                                }
                              : {
                                  if (coverId != null && coverId!.isNotEmpty)
                                    coverId!: 'Already relieving this post',
                                },
                        );
                        if (choice == null) return;
                        setDialogState(() {
                          if (asReliever) {
                            coverId = choice.employee?.id;
                            coverName = choice.employee?.name;
                          } else if (choice.employee != null) {
                            holderId = choice.employee!.id;
                            holderName = choice.employee!.name;
                          }
                        });
                      },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                    helperText: !canPickGuards
                        ? 'Employee list unavailable — check the server'
                        : (id == null || id.isEmpty ? null : 'ID $id'),
                  ),
                  child: Text(
                    empty
                        ? (asReliever ? 'No reliever' : 'Select a guard')
                        : name,
                    style: TextStyle(
                      fontSize: 14,
                      color: empty ? Colors.grey[500] : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text('Edit Assignment'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Row ${row.no} · ${row.shift}',
                        style: TextStyle(color: Colors.grey[900], fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isHeadGuard
                            ? 'A head guard post — only head guards can hold '
                                'or cover it.'
                            : 'A ${row.shift.toLowerCase()} shift post — held '
                                'by a regular, covered by a reliever.',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 20),
                      guardField(
                        label: _holderLabelFor(row.shift),
                        name: holderName,
                        id: holderId,
                        asReliever: false,
                      ),
                      const SizedBox(height: 16),
                      if (isHeadGuard || postOptions.isEmpty)
                        TextField(
                          enabled: false,
                          controller: TextEditingController(text: post),
                          decoration: InputDecoration(
                            labelText: 'Post',
                            helperText: isHeadGuard
                                ? 'The Head Guard post cannot be changed'
                                : 'No posts set up for this shift — add them '
                                    'in Edit Station',
                            border: const OutlineInputBorder(),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: post,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Post',
                            helperText:
                                'The posts this station is set up with for '
                                'this shift',
                            border: OutlineInputBorder(),
                          ),
                          items: postOptions
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p,
                                        style: const TextStyle(fontSize: 14)),
                                  ))
                              .toList(),
                          // Moving to another post moves the guard onto
                          // that post's window on the station's stagger
                          // ladder, so the times can't drift out of step
                          // with the setup.
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              post = value;
                              final window = _windowForPost(row.shift, value);
                              if (window != null) {
                                startTime = _toTimeOfDay(window.start);
                                endTime = _toTimeOfDay(window.end);
                              }
                            });
                          },
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _timeField(dialogContext, 'Time In',
                                startTime,
                                (t) => setDialogState(() => startTime = t)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _timeField(dialogContext, 'Time Out',
                                endTime,
                                (t) => setDialogState(() => endTime = t)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hoursValid
                            ? 'Duty length: ${hours.toStringAsFixed(2)} hours'
                            : 'Duty length: ${hours.toStringAsFixed(2)} hours — must be between 9 and 12 hours',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              hoursValid ? Colors.grey[600] : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Day-off dates (${offDates.length}/$_maxOffDates)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in offDates)
                            InputChip(
                              label: Text(_shortDate(d),
                                  style: const TextStyle(fontSize: 12)),
                              onDeleted: () =>
                                  setDialogState(() => offDates.remove(d)),
                            ),
                          if (offDates.length < _maxOffDates)
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: const Text('Add date',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final schedule = widget.schedule;
                                final picked = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: schedule.startDate,
                                  firstDate: schedule.startDate,
                                  lastDate: schedule.endDate,
                                );
                                if (picked == null) return;
                                final day = DateTime(
                                    picked.year, picked.month, picked.day);
                                final exists = offDates.any((d) =>
                                    d.year == day.year &&
                                    d.month == day.month &&
                                    d.day == day.day);
                                if (exists) return;
                                setDialogState(() {
                                  offDates.add(day);
                                  offDates.sort();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      guardField(
                        label: _coverLabelFor(row.shift),
                        name: coverName,
                        id: coverId,
                        asReliever: true,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        offDates.isEmpty
                            ? 'No day-offs, so nobody needs to cover this post.'
                            : 'Covers this post on the '
                                '${offDates.length} day-off'
                                '${offDates.length == 1 ? '' : 's'} above.',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  // Disabled until the duty length lands inside 9–12 hours
                  // and somebody actually holds the post.
                  onPressed: !canSave
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _saveAssignment(
                            row,
                            employeeId: holderId,
                            employeeName: holderName,
                            post: post.trim(),
                            startTime: startTime,
                            endTime: endTime,
                            hours: hours,
                            offDates: offDates,
                            relieverId:
                                (coverId?.isEmpty ?? true) ? null : coverId,
                            relieverName:
                                (coverName?.isEmpty ?? true) ? null : coverName,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1034A6),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    final isPublished = _status == ScheduleStatus.published;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header — unchanged
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.stationName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '${_formatDate(schedule.startDate)} – ${_formatDate(schedule.endDate)} · ${schedule.totalDays}-day schedule',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(isPublished),
                const SizedBox(width: 12),
                // Publishing is one-way, so a published schedule has no
                // action left here — only the badge saying so.
                if (!widget.readOnly)
                  ElevatedButton.icon(
                    onPressed: () => widget.onNavigate?.call(ScreenType.approvals, data: '${schedule.startDate.toIso8601String().substring(0, 10)}|${schedule.endDate.toIso8601String().substring(0, 10)}'),
                    icon: const Icon(Icons.publish, size: 18),
                    label: const Text('Period Approvals'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1034A6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ),

          // Content — redesigned duty-roster table
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1034A6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_formatDate(schedule.startDate)} - ${_formatDate(schedule.endDate)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1034A6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_morningRows.length + _afternoonRows.length + _nightRows.length}',
                          style: const TextStyle(
                            color: Color(0xFF1034A6),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !_hasRealRoster
                        ? 'Sample layout — create this schedule from Generate Schedule to see real assignments'
                        : isPublished
                            ? 'Bi-weekly duty roster · published and locked — assignments can no longer be edited · DATE column shows each employee\'s day-offs, covered by the RELIEVER column'
                            : 'Bi-weekly duty roster · tap a row to edit · DATE column shows each employee\'s day-offs, covered by the RELIEVER column',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),

                  // Each shift table stretches to fill the viewport on wide
                  // screens and scrolls horizontally on narrow ones.
                  _buildShiftSection('Morning Shift', _morningRows),
                  _buildShiftDivider(),
                  _buildShiftSection('Afternoon Shift', _afternoonRows),
                  _buildShiftDivider(),
                  _buildShiftSection('Night Shift', _nightRows),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      children: const [
        _HeaderCell('NO.'),
        _HeaderCell('ID'),
        _HeaderCell('NAME'),
        _HeaderCell('POST'),
        _HeaderCell('TIME'),
        _HeaderCell('NO. OF HOURS'),
        _HeaderCell('DATE'),
        _HeaderCell('RELIEVER'),
      ],
    );
  }

  TableRow _buildDataRow(_DutyRow row) {
    return TableRow(
      children: [
        _dataCell(row, Text('${row.no}', style: const TextStyle(fontSize: 13))),
        _dataCell(
          row,
          Text(row.employeeId, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        ),
        _dataCell(
          row,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  row.employeeName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The pencil is the row's affordance — it goes away with
              // the tap target once the schedule is published.
              if (!_isLocked) ...[
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 13, color: Colors.grey[400]),
              ],
            ],
          ),
        ),
        // Undefined posts block publishing, so they stand out in amber.
        _dataCell(
          row,
          Text(
            row.post,
            style: TextStyle(
              fontSize: 13,
              color: row.post == 'Undefined'
                  ? const Color(0xFFD97706)
                  : const Color(0xFF1E293B),
              fontWeight: row.post == 'Undefined'
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ),
        _dataCell(row, Text(row.time, style: const TextStyle(fontSize: 13))),
        _dataCell(row, Text(row.hours.toStringAsFixed(2), style: const TextStyle(fontSize: 13))),
        _dataCell(
          row,
          Text(
            row.dateLabel.isEmpty ? '—' : row.dateLabel,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _dataCell(
          row,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  row.relieverLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: row.reliever == null ? Colors.grey[400] : const Color(0xFF1E293B),
                    fontWeight: row.reliever == null ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),
              if (!_isLocked) ...[
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 13, color: Colors.grey[400]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Every cell in the row shares the same tap target, so tapping anywhere
  // on the row opens the edit dialog — except on a published schedule,
  // where the row has no tap target at all.
  Widget _dataCell(_DutyRow row, Widget child) {
    return InkWell(
      onTap: _isLocked ? null : () => _editRow(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: child,
      ),
    );
  }

  // One shift block: subtitle + headcount pill, then the same table
  // styling as before, with a totals row appended at the bottom.
  Widget _buildShiftSection(String title, List<_DutyRow> rows) {
    final totalHours = rows.fold<double>(0, (sum, r) => sum + r.hours);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1034A6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${rows.length}',
                style: const TextStyle(
                  color: Color(0xFF1034A6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The table fills whatever width is available (columns share it via
        // flex ratios) but never squeezes below _minTableWidth — past that
        // point it scrolls horizontally instead of cramping the cells.
        LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth < _minTableWidth
                ? _minTableWidth
                : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Table(
                    columnWidths: _columnWidths,
                    border: TableBorder.all(
                      color: Colors.grey[200]!,
                      width: 1,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    children: [
                      _buildHeaderRow(),
                      ...rows.map(_buildDataRow),
                      _buildTotalRow(rows.length, totalHours),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Thin grey separator with breathing room between shift sections.
  Widget _buildShiftDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      height: 1,
      color: Colors.grey[300],
    );
  }

  // Summary row appended to each shift's Table — it shares the exact same
  // columnWidths as the data rows above it, so "Total: N" lands directly
  // under NAME and the hours figure lands directly under NO. OF HOURS
  // with no separate alignment math needed.
  TableRow _buildTotalRow(int peopleCount, double totalHours) {
    return TableRow(
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.04),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      children: [
        const SizedBox(),
        const SizedBox(),
        _totalCell('Total: $peopleCount'),
        const SizedBox(),
        const SizedBox(),
        _totalCell(totalHours.toStringAsFixed(2)),
        const SizedBox(),
        const SizedBox(),
      ],
    );
  }

  Widget _totalCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1034A6),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isPublished) {
    final color = isPublished ? const Color(0xFF059669) : const Color(0xFFD97706);
    final label = widget.readOnly ? 'Submitted Roster' : widget.schedule.approvalId != null ? approvalStatusLabel(widget.schedule.approvalStatus) : isPublished ? 'Published ? Legacy' : 'Draft';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Color(0xFF1034A6),
        ),
      ),
    );
  }
}
