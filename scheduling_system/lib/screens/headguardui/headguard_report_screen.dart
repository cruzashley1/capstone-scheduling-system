// screens/headguardui/headguard_report_screen.dart
//
// Attendance report for the Head Guard's station, filed PER SHIFT:
// the day head guard (HG Day) works 0500H-1700H, which straddles the
// Morning and Afternoon shifts, so they file one report for each; the
// night head guard (HG Night) works 1700H-0500H, covering the Night
// shift only, and files that one. Neither can ever file for the other's
// shifts — see _resolveCoveredShifts, which has no "all shifts"
// fallback for exactly that reason, and the matching server-side check
// in api.py's submit_attendance_report.
//
// The roster this screen is handed is the head guard's DUTY day, which
// between midnight and 0500H is yesterday — the night shift they are
// still standing. HeadGuardLayout resolves that via
// DutyClock.activeDutyDate; everything here just follows roster.date.
//
// Each shift's report can only be submitted once — after that the list
// is locked. Submissions feed the admin's Notifications screen.
import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/attendance_report.dart';
import '../../models/employee.dart';
import '../../models/guard_shift.dart';
import '../../models/station_roster.dart';
import '../../services/api_service.dart';
import '../../services/server_clock.dart';

class HeadGuardReportScreen extends StatefulWidget {
  final Employee employee;
  final StationRoster? roster;

  const HeadGuardReportScreen({
    super.key,
    required this.employee,
    this.roster,
  });

  @override
  State<HeadGuardReportScreen> createState() => _HeadGuardReportScreenState();
}

// One row in the attendance list, seeded from today's roster.
class _PersonnelRow {
  final String employeeId;
  final String name;
  final String shift;

  // This guard's own duty window, '0500H - 1400H'. Posts are staggered
  // per station, so guards on the same shift can start two hours apart —
  // the head guard needs each one's real hours to mark them present, and
  // the filed report records the hours the guard was actually due for.
  final String timeRange;

  final bool isReliever;
  bool isPresent = true;

  _PersonnelRow({
    required this.employeeId,
    required this.name,
    required this.shift,
    required this.timeRange,
    required this.isReliever,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Color get avatarColor {
    const palette = [
      Color(0xFF22C55E),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFF1034A6),
      Color(0xFF14B8A6),
      Color(0xFFEF4444),
      Color(0xFF0EA5E9),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }
}

class _HeadGuardReportScreenState extends State<HeadGuardReportScreen> {
  // Personnel per covered shift, e.g. {'Morning': [...], 'Afternoon': [...]}.
  late Map<String, List<_PersonnelRow>> _personnelByShift;
  late List<String> _coveredShifts;
  String _selectedShift = '';

  // Shifts whose report already exists on the server today — locked.
  final Set<String> _submittedShifts = {};
  bool _checkingSubmitted = true;

  // Whether this head guard is on the duty day's roster. Off duty (rest
  // day, or not in the published schedule) means the covering head guard
  // files the report, so the list is shown read-only.
  bool _onDutyToday = false;

  // This head guard's own duty on the roster date, as a GuardShift, so
  // the duty window comes off the shared shiftTimeRanges and handles HG
  // Night crossing midnight. Null when they aren't rostered.
  GuardShift? _ownDuty;

  bool _isSubmitting = false;

  // Drives the duty-window gate: without it the screen would not unlock
  // by itself at time-in, or re-lock at time-out, while it sits open.
  Timer? _ticker;
  DateTime _now = ServerClock.now();

  @override
  void initState() {
    super.initState();
    _rebuildFromRoster();
    _loadSubmittedShifts();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = ServerClock.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HeadGuardReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Layout refreshed the roster (pull-to-refresh) — rebuild the lists,
    // dropping any unsubmitted toggles, and re-check what's submitted.
    if (oldWidget.roster != widget.roster) {
      _rebuildFromRoster();
      _loadSubmittedShifts();
    }
  }

  // Which plain shifts this head guard is responsible for reporting.
  // A head guard reports on the shifts their own 12-hour duty covers and
  // on nothing else: HG Day (0500H-1700H) files Morning and Afternoon,
  // HG Night (1700H-0500H) files Night. There is deliberately NO
  // "otherwise show every shift" fallback here — that fallback is what
  // let a night head guard file Morning and Afternoon reports. A head
  // guard we can't resolve gets no shifts at all.
  //
  // `rosteredShift` is this head guard's own entry on the duty day's
  // roster ('HG Day' / 'HG Night'), or empty if they aren't on it.
  List<String> _resolveCoveredShifts(String rosteredShift) {
    // 1. Today's roster is the authority. It also gets the floating
    //    substitute head guard right: they're rostered under the post
    //    they're standing in for ('HG Day' / 'HG Night'), not their own
    //    profile, which has no fixed shift.
    final rostered = _shiftsCoveredBy(rosteredShift);
    if (rostered.isNotEmpty) return rostered;

    // 2. Off the roster today — a rest day, or the published schedule
    //    doesn't carry them. Fall back to their permanent assignment so
    //    a night head guard still only ever sees the Night shift. The
    //    screen renders read-only in this case (see _isOffDuty).
    return _shiftsCoveredBy(widget.employee.assignedShift ?? '');
  }

  // Maps a head guard duty onto the shifts it covers. Accepts both the
  // roster label ('HG Night') and the employee profile field
  // ('hgNight') — the same assignment reaches this screen both ways.
  List<String> _shiftsCoveredBy(String hgShift) {
    switch (hgShift.toLowerCase().replaceAll(' ', '')) {
      case 'hgday':
        return const ['Morning', 'Afternoon'];
      case 'hgnight':
        return const ['Night'];
      default:
        return const [];
    }
  }

  void _rebuildFromRoster() {
    final own = (widget.roster?.onDuty ?? [])
        .where((e) => e.employeeId == widget.employee.id)
        .toList();
    _onDutyToday = own.isNotEmpty;

    // Their own duty on the roster date, used for the time window below.
    // Built as a GuardShift so the hours resolve the one authoritative
    // way — the roster entry's own window first, the shift's base hours
    // only as a fallback — and HG Night's midnight crossing is handled.
    _ownDuty = own.isEmpty || widget.roster == null
        ? null
        : GuardShift(
            date: widget.roster!.date,
            scheduleId: '',
            stationId: '',
            stationName: widget.roster!.stationName ?? '',
            shift: own.first.shift,
            timeInRaw: own.first.timeIn,
            timeOutRaw: own.first.timeOut,
          );

    _coveredShifts =
        _resolveCoveredShifts(own.isNotEmpty ? own.first.shift : '');
    _personnelByShift = {
      for (final shift in _coveredShifts)
        shift: (widget.roster?.onDuty ?? [])
            .where((e) => e.shift == shift)
            .map((e) => _PersonnelRow(
                  employeeId: e.employeeId,
                  name: e.employeeName,
                  shift: e.shift,
                  timeRange: e.timeRange,
                  isReliever: e.isReliever,
                ))
            .toList(),
    };
    if (!_coveredShifts.contains(_selectedShift)) {
      _selectedShift =
          _coveredShifts.isNotEmpty ? _coveredShifts.first : '';
    }
  }

  // Asks the server which of today's reports this head guard already
  // filed, so submitted shifts stay locked across app restarts.
  Future<void> _loadSubmittedShifts() async {
    setState(() => _checkingSubmitted = true);

    final result = await ApiService.fetchAttendanceReports();
    if (!mounted) return;

    setState(() {
      _checkingSubmitted = false;
      if (result['success'] == true) {
        _submittedShifts.clear();
        final reports =
            (result['reports'] as List).cast<AttendanceReport>();
        for (final report in reports) {
          if (report.headGuardId != widget.employee.id) continue;
          if (report.date != _dateIso) continue;
          // 'Morning Shift' -> 'Morning'
          final shift = report.shiftTitle.replaceAll(' Shift', '').trim();
          _submittedShifts.add(shift);
        }
        // Land on the first shift that still needs a report.
        final pending = _coveredShifts
            .where((s) => !_submittedShifts.contains(s))
            .toList();
        if (pending.isNotEmpty && !pending.contains(_selectedShift)) {
          _selectedShift = pending.first;
        }
      }
    });
  }

  List<_PersonnelRow> get personnel => _personnelByShift[_selectedShift] ?? [];

  // Already filed today — final, can't be redone.
  bool get _isSubmitted => _submittedShifts.contains(_selectedShift);

  // Not on the duty day's roster: the head guard covering for them files
  // the report, so they can look but not submit.
  bool get _isOffDuty => !_onDutyToday;

  // Rostered, but not on post yet (or already timed out). A report may
  // only be filed while the head guard is actually standing the duty, so
  // this is measured against ServerClock, not the device clock — moving
  // the phone's clock must not open the window.
  bool get _isOutsideDutyWindow {
    final duty = _ownDuty;
    if (duty == null) return false; // covered by _isOffDuty instead
    if (duty.startsAt == null) return false; // no hours on file — allow
    return !duty.isActiveAt(_now);
  }

  // Any of the three makes the whole list read-only.
  bool get _isLocked => _isSubmitted || _isOffDuty || _isOutsideDutyWindow;

  // Whether the window is still ahead (vs. already closed), and how long
  // until it opens — drives the countdown on the banner.
  bool get _dutyNotStarted => _ownDuty?.startsAfter(_now) ?? false;

  Duration? get _untilDutyStarts {
    final start = _ownDuty?.startsAt;
    if (start == null || !start.isAfter(_now)) return null;
    return start.difference(_now);
  }

  // One sentence saying why the list can't be edited. Ordered by which
  // reason the head guard can do something about.
  String get _lockExplanation {
    if (_isSubmitted) {
      return 'The $shiftTitle report is already submitted and locked.';
    }
    if (_isOffDuty) {
      return 'You are off duty today — the head guard covering your shift '
          'files this report.';
    }
    final duty = _ownDuty;
    if (_dutyNotStarted) {
      final left = _untilDutyStarts;
      return 'Your ${duty!.shift} duty starts at ${duty.timeIn}'
          '${left == null ? '' : ' (in ${_humanize(left)})'} — '
          'you can file this report once you are on post.';
    }
    return 'Your ${duty!.shift} duty ended at ${duty.timeOut}, so this '
        'report can no longer be filed.';
  }

  static String _humanize(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return '${m}m';
    return 'less than a minute';
  }

  String get shiftTitle => '$_selectedShift Shift';

  String get shiftDate {
    final date = widget.roster?.date ?? DateTime.now();
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[date.weekday - 1]}, '
        '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String get _dateIso {
    final date = widget.roster?.date ?? DateTime.now();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  int get _totalCount => personnel.length;
  int get _presentCount => personnel.where((p) => p.isPresent).length;
  int get _absentCount => _totalCount - _presentCount;
  bool get _isComplete => _presentCount == _totalCount;

  void _toggleAttendance(int index) {
    if (_isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lockExplanation),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    setState(() {
      personnel[index].isPresent = !personnel[index].isPresent;
    });
  }

  Future<void> _handleSubmitPressed() async {
    final confirmed = await _showSubmitConfirmationDialog();
    if (confirmed == true) {
      await _submitReport();
    }
  }

  Future<bool?> _showSubmitConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Submit $shiftTitle Report?',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          content: Text(
            _isComplete
                ? 'You are about to submit the $shiftTitle attendance '
                    'report with $_presentCount of $_totalCount personnel '
                    'marked present. This can only be submitted once and '
                    'cannot be changed afterwards.'
                : 'You are about to submit the $shiftTitle attendance '
                    'report with $_absentCount personnel marked absent. '
                    'The admin will be notified and can arrange a '
                    'replacement. This can only be submitted once and '
                    'cannot be changed afterwards.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          // The action buttons live inside a Row: AlertDialog lays its
          // actions out in an OverflowBar, and putting Expanded widgets
          // directly in it is a ParentDataWidget error that renders the
          // whole dialog blank in release builds.
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1034A6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Submit',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitReport() async {
    setState(() => _isSubmitting = true);

    final records = personnel
        .map((p) => AttendanceRecord(
              employeeId: p.employeeId,
              name: p.name,
              shift: p.shift,
              time: p.timeRange,
              isPresent: p.isPresent,
              isReliever: p.isReliever,
            ))
        .toList();

    final result = await ApiService.submitAttendanceReport(
      headGuardId: widget.employee.id,
      headGuardName: widget.employee.name,
      station: widget.roster?.stationName ?? 'Unknown Station',
      shiftTitle: shiftTitle,
      date: _dateIso,
      records: records,
    );

    if (!mounted) return;

    final success = result['success'] == true;
    final error = result['error']?.toString() ?? '';
    // The backend refuses duplicates with 409 — if we hit that, this
    // shift was already filed (e.g. from another device), so lock it too.
    final alreadySubmitted = error.contains('already been submitted');

    setState(() {
      _isSubmitting = false;
      if (success || alreadySubmitted) _submittedShifts.add(_selectedShift);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '$shiftTitle report submitted — the admin has been notified.'
              : 'Failed to submit report: ${ApiService.friendlyError(error)}',
        ),
        backgroundColor: success ? Colors.green[600] : Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAnyPersonnel =
        _personnelByShift.values.any((list) => list.isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header - square corners to match Schedule/Alerts/Profile
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width < 360 ? 14 : 20,
                vertical: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1034A6),
                    Color(0xFF1E4AD0),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Attendance Report',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize:
                            MediaQuery.of(context).size.width < 360 ? 17 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (personnel.isNotEmpty) _buildStatusChip(),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _checkingSubmitted
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1034A6)),
                    )
                  : !hasAnyPersonnel
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            // Shift selector — one report per shift.
                            if (_coveredShifts.length > 1) ...[
                              _buildShiftSelector(),
                              const SizedBox(height: 16),
                            ],

                            if (personnel.isEmpty)
                              _buildNoShiftPersonnel()
                            else ...[
                              if (_isLocked) ...[
                                _buildLockedBanner(),
                                const SizedBox(height: 16),
                              ],
                              _buildSummaryCard(),
                              const SizedBox(height: 24),

                              // Personnel section
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Personnel',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE9EEF5),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '$_totalCount',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isLocked
                                            ? Icons.lock_outline
                                            : Icons.touch_app_outlined,
                                        size: 14,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isLocked
                                            ? 'Locked'
                                            : 'Tap to toggle',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              ...personnel.asMap().entries.map((entry) {
                                return _buildPersonnelCard(
                                    entry.key, entry.value);
                              }),

                              const SizedBox(height: 24),

                              _buildSubmitButton(),

                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // Submit action. Disabled — and relabelled with the reason — once the
  // shift is filed or when this head guard isn't the one on duty today.
  Widget _buildSubmitButton() {
    late final String label;
    late final IconData icon;
    if (_isSubmitted) {
      label = '$shiftTitle Report Submitted';
      icon = Icons.check_circle;
    } else if (_isOffDuty) {
      label = 'Off Duty — Reporting Locked';
      icon = Icons.lock_outline;
    } else if (_isOutsideDutyWindow) {
      label = _dutyNotStarted
          ? 'Opens at ${_ownDuty!.timeIn}'
          : 'Duty Ended — Reporting Closed';
      icon = Icons.schedule_rounded;
    } else {
      label = 'Submit $shiftTitle Report';
      icon = Icons.send_outlined;
    }

    final Color disabledColor = _isSubmitted
        ? const Color(0xFF16A34A).withOpacity(0.85)
        : (_isOffDuty || _isOutsideDutyWindow)
            ? const Color(0xFF94A3B8)
            : const Color(0xFF1034A6).withOpacity(0.5);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed:
            (_isSubmitting || _isLocked) ? null : _handleSubmitPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1034A6),
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledColor,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Header pill: where this shift's report stands right now.
  Widget _buildStatusChip() {
    late final String label;
    late final IconData icon;
    late final Color color;
    if (_isSubmitted) {
      label = 'Submitted';
      icon = Icons.check_circle;
      color = const Color(0xFF16A34A);
    } else if (_isOffDuty) {
      label = 'Off Duty';
      icon = Icons.lock_outline;
      color = const Color(0xFF64748B);
    } else if (_isOutsideDutyWindow) {
      label = _dutyNotStarted ? 'Not On Post' : 'Duty Ended';
      icon = Icons.schedule_rounded;
      color = const Color(0xFF64748B);
    } else if (_isComplete) {
      label = 'Complete';
      icon = Icons.check_circle_outline;
      color = const Color(0xFF16A34A);
    } else {
      label = 'Incomplete';
      icon = Icons.error_outline;
      color = const Color(0xFFF59E0B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Pill selector for the shifts this head guard reports on. A check
  // mark shows which ones are already submitted.
  Widget _buildShiftSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),
      child: Row(
        children: [
          for (final shift in _coveredShifts)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedShift = shift),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: _selectedShift == shift
                        ? const Color(0xFF1034A6)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_submittedShifts.contains(shift)) ...[
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: _selectedShift == shift
                              ? Colors.white
                              : const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          shift,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _selectedShift == shift
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Why the list is read-only: already filed, off duty today, or not
  // inside the duty window.
  Widget _buildLockedBanner() {
    final bool submitted = _isSubmitted;
    final Color accent =
        submitted ? const Color(0xFF16A34A) : const Color(0xFF64748B);

    late final String title;
    late final IconData icon;
    if (submitted) {
      title = 'Report submitted';
      icon = Icons.check_circle_outline;
    } else if (_isOffDuty) {
      title = 'You are off duty today';
      icon = Icons.bedtime_outlined;
    } else if (_dutyNotStarted) {
      title = 'Your duty has not started yet';
      icon = Icons.schedule_rounded;
    } else {
      title = 'Your duty has ended';
      icon = Icons.task_alt_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _lockExplanation,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final String stationName = widget.roster?.stationName ?? '';
    final Color barColor =
        _isComplete ? const Color(0xFF16A34A) : const Color(0xFF1034A6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station, then shift + its hours, then the date. Stacked
          // rather than squeezed onto one line so long station names
          // don't get ellipsised away on a narrow phone.
          if (stationName.isNotEmpty) ...[
            Text(
              stationName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1034A6).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  shiftTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1034A6),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    shiftTimeRanges[_selectedShift] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shiftDate,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),

          // Progress bar with the headline ratio beside it, so the
          // "x of y present" reading needs no separate box.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _totalCount == 0 ? 0 : _presentCount / _totalCount,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE9EEF5),
                    color: barColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_presentCount/$_totalCount',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildStatStrip(),
        ],
      ),
    );
  }

  // Present / Absent / Total as three equal columns split by hairline
  // dividers. The old Wrap laid them out shoulder to shoulder, which
  // ran them together as soon as the counts hit two digits.
  Widget _buildStatStrip() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildStatItem(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF16A34A),
                value: _presentCount,
                label: 'Present',
              ),
            ),
            _buildStatDivider(),
            Expanded(
              child: _buildStatItem(
                icon: Icons.cancel,
                iconColor: const Color(0xFFEF4444),
                value: _absentCount,
                label: 'Absent',
              ),
            ),
            _buildStatDivider(),
            Expanded(
              child: _buildStatItem(
                icon: Icons.groups_outlined,
                iconColor: const Color(0xFF1034A6),
                value: _totalCount,
                label: 'Total',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: const Color(0xFFE9EEF5),
    );
  }

  // Shown when the selected shift has no personnel (but another does).
  Widget _buildNoShiftPersonnel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(Icons.group_off_outlined, size: 44, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No one is scheduled for the $shiftTitle today.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // Shown when there is nothing this head guard can report on today.
  Widget _buildEmptyState() {
    // No covered shifts at all means neither today's roster nor the
    // profile says whether this is a day or a night head guard — an
    // employee-record problem, not an empty day, so say so plainly
    // instead of silently offering every shift like the old fallback.
    final bool unresolvedShift = _coveredShifts.isEmpty;
    final bool noSchedule =
        widget.roster == null || widget.roster?.hasSchedule != true;

    late final String title;
    late final String detail;
    late final IconData icon;
    if (unresolvedShift) {
      icon = Icons.help_outline;
      title = 'Your head guard shift is not set';
      detail = 'Your record does not say whether you are the day or the '
          'night head guard, so there is no shift to report on. Ask the '
          'admin to set it on your employee record.';
    } else if (noSchedule) {
      icon = Icons.event_busy_outlined;
      title = 'No personnel to report today';
      detail = 'There is no published schedule covering today for your '
          'station. Pull down on the Dashboard to refresh once the admin '
          'publishes one.';
    } else {
      icon = Icons.event_busy_outlined;
      title = 'No personnel to report today';
      detail = 'No one else is on duty at your station today.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // One column of the stat strip: the count on top, its label below.
  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required int value,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: iconColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 12),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersonnelCard(int index, _PersonnelRow guard) {
    final bool isPresent = guard.isPresent;

    return GestureDetector(
      onTap: () => _toggleAttendance(index),
      child: Opacity(
        opacity: _isLocked ? 0.7 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            // An absence is the thing the admin acts on, so the whole
            // row picks up a red edge rather than only the pill.
            border: Border.all(
              color: isPresent
                  ? const Color(0xFFE9EEF5)
                  : const Color(0xFFEF4444).withOpacity(0.45),
              width: isPresent ? 1 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: guard.avatarColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    guard.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name + details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guard.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${guard.shift} · ${guard.timeRange}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        if (guard.isReliever) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Reliever',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      guard.employeeId,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Present / Absent toggle pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isPresent
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPresent ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: isPresent ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPresent ? 'Present' : 'Absent',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isPresent ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
