// screens/leave_request_screen.dart
//
// Guard-facing leave request form. A leave is the longest of the three
// requests this app files: an emergency absence covers one duty, a
// special request covers up to three scattered days, and a leave covers
// a continuous stretch — a vacation, a sickness, a maternity.
//
// Every rule behind it is the backend's (backend_python/leave.py); this
// screen's job is to show them BEFORE the guard types anything, so a
// refusal is never the first they hear of a cooldown or a quota. The
// window call answers "may you file at all, and from when", and the two
// date pickers simply cannot offer a range that breaks the rules.
//
// Pushed as a full screen from the dashboard's Request section. Pops
// with `true` once the request reaches the backend.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../services/api_service.dart';
import '../services/server_clock.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kTeal = Color(0xFF0D9488);
const Color _kInk = Color(0xFF1E293B);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kPageBg = Color(0xFFF8FAFC);
const Color _kDanger = Color(0xFFDC2626);

class LeaveRequestScreen extends StatefulWidget {
  final Employee employee;

  const LeaveRequestScreen({super.key, required this.employee});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  // Window from the backend — the whole of what this guard may do.
  bool _loadingWindow = true;
  String? _windowError;
  bool _canFile = false;
  String _blockReason = '';
  late DateTime _earliestStart;
  late DateTime _maxDate;
  int _minDays = 4;
  List<LeaveType> _types = [];
  String? _leaveType;
  Map<String, dynamic> _quota = {};
  // Days already covered by a generated roster — a leave can't reach them.
  Set<String> _blocked = {};
  LeaveRequest? _activeLeave;
  String? _pendingRequestId;

  DateTime? _start;
  DateTime? _end;

  // The guard's own leave history, shown read-only under the form.
  List<LeaveRequest> _history = [];

  bool _isSubmitting = false;
  String? _titleError;
  String? _bodyError;
  String? _dateError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadWindow();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _isoOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int get _cap {
    final match = _types.where((t) => t.name == _leaveType);
    return match.isEmpty ? 0 : match.first.maxDays;
  }

  int get _days =>
      (_start == null || _end == null) ? 0 : _end!.difference(_start!).inDays + 1;

  bool get _overCap => _cap > 0 && _days > _cap;

  Future<void> _loadWindow() async {
    setState(() {
      _loadingWindow = true;
      _windowError = null;
    });

    final result = await ApiService.fetchLeaveWindow(widget.employee.id);
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _loadingWindow = false;
        _windowError = result['error']?.toString().isNotEmpty == true
            ? 'Could not reach the server — ${result['error']}'
            : 'Could not load your leave details. Please try again.';
      });
      return;
    }

    // History loads in the background; a failure just leaves it empty.
    ApiService.fetchEmployeeLeaveRequests(widget.employee.id).then((h) {
      if (!mounted || h['success'] != true) return;
      setState(() => _history = (h['requests'] as List).cast<LeaveRequest>());
    });

    final earliest = DateTime.tryParse(result['earliestStart']?.toString() ?? '');
    final max = DateTime.tryParse(result['maxDate']?.toString() ?? '');
    final now = ServerClock.now();

    setState(() {
      _loadingWindow = false;
      _canFile = result['canFile'] == true;
      _blockReason = result['reason']?.toString() ?? '';
      _earliestStart = earliest != null
          ? _dateOnly(earliest)
          : _dateOnly(now.add(const Duration(days: 7)));
      _maxDate = max != null
          ? _dateOnly(max)
          : _dateOnly(now.add(const Duration(days: 365)));
      _types = (result['leaveTypes'] as List).cast<LeaveType>();
      _minDays = (result['minLeaveDays'] as int?) ?? _minDays;
      _leaveType = result['defaultLeaveType']?.toString();
      if (_leaveType != null && !_types.any((t) => t.name == _leaveType)) {
        _leaveType = _types.isEmpty ? null : _types.first.name;
      }
      _quota = Map<String, dynamic>.from(result['quota'] ?? {});
      _blocked =
          (result['blockedDates'] as List).map((e) => e.toString()).toSet();
      _activeLeave = result['activeLeave'] as LeaveRequest?;
      _pendingRequestId = result['pendingRequestId']?.toString();
    });
  }

  // ── date rules ──────────────────────────────────────────────────
  // The pickers enforce the backend's rules rather than reporting them
  // afterwards: a day that can't legally start (or end) a leave is simply
  // not offered.

  bool _isFree(DateTime d) => !_blocked.contains(_isoOf(d));

  // A start day works only if the minimum run of days after it is ALSO
  // free — offering a start that can't reach a legal end would just move
  // the dead end one tap later.
  bool _isSelectableStart(DateTime d) {
    if (d.isBefore(_earliestStart) || d.isAfter(_maxDate)) return false;
    for (int i = 0; i < _minDays; i++) {
      if (!_isFree(d.add(Duration(days: i)))) return false;
    }
    return true;
  }

  // The last day this leave could run to without crossing into a day some
  // roster already covers — a leave has to be one unbroken stretch.
  DateTime _maxEndFor(DateTime start) {
    var last = start;
    var probe = start.add(const Duration(days: 1));
    while (!probe.isAfter(_maxDate) && _isFree(probe)) {
      last = probe;
      probe = probe.add(const Duration(days: 1));
    }
    return last;
  }

  DateTime get _firstSelectableStart {
    var d = _earliestStart;
    while (!d.isAfter(_maxDate)) {
      if (_isSelectableStart(d)) return d;
      d = d.add(const Duration(days: 1));
    }
    return _earliestStart;
  }

  Future<DateTime?> _pickDate({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
    required String help,
    bool Function(DateTime)? predicate,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: help,
      selectableDayPredicate: predicate,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: _kBlue, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await _pickDate(
      initial: _start ?? _firstSelectableStart,
      first: _earliestStart,
      last: _maxDate,
      help: 'Leave starts on',
      predicate: _isSelectableStart,
    );
    if (picked == null || !mounted) return;
    final start = _dateOnly(picked);
    setState(() {
      _start = start;
      final floor = start.add(Duration(days: _minDays - 1));
      // Snap the end to a legal value instead of leaving an invalid pair
      // on screen for the guard to puzzle over.
      if (_end == null || _end!.isBefore(floor) ||
          _end!.isAfter(_maxEndFor(start))) {
        _end = floor;
      }
      _dateError = null;
    });
  }

  Future<void> _pickEnd() async {
    final start = _start;
    if (start == null) return;
    final floor = start.add(Duration(days: _minDays - 1));
    final ceiling = _maxEndFor(start);
    final picked = await _pickDate(
      initial: (_end != null &&
              !_end!.isBefore(floor) &&
              !_end!.isAfter(ceiling))
          ? _end!
          : floor,
      first: floor,
      last: ceiling.isBefore(floor) ? floor : ceiling,
      help: 'Leave ends on',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _end = _dateOnly(picked);
      _dateError = null;
    });
  }

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    setState(() {
      _dateError = (_start == null || _end == null)
          ? 'Choose the dates your leave starts and ends.'
          : _days < _minDays
              ? 'A leave has to run at least $_minDays days.'
              : null;
      _titleError = title.isEmpty ? 'Please give this leave a title.' : null;
      _bodyError =
          body.isEmpty ? 'Please explain why so the admin can decide.' : null;
      _submitError = null;
    });
    if (_dateError != null || title.isEmpty || body.isEmpty) return;

    setState(() => _isSubmitting = true);

    final result = await ApiService.submitLeaveRequest(
      employeeId: widget.employee.id,
      employeeName: widget.employee.name,
      employeeType: widget.employee.type.name,
      station: widget.employee.assignedStation ?? '',
      leaveType: _leaveType ?? '',
      startDate: _isoOf(_start!),
      endDate: _isoOf(_end!),
      title: title,
      body: body,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] != true) {
      // The server's message says exactly which rule refused it — show it
      // verbatim rather than inventing a vaguer one.
      setState(() => _submitError = result['error']?.toString() ??
          'Could not send your leave request. Please try again.');
      return;
    }

    // Say it reached the admin before this screen disappears. The form
    // closing on its own reads the same whether it worked or not, so the
    // guard is told plainly, and has to acknowledge it.
    await _showSubmittedDialog(result['request'] as LeaveRequest?);
    if (!mounted) return;

    Navigator.of(context).pop(true);
  }

  // The confirmation the guard walks away with: what was filed, and what
  // happens next. Mirrored by a "Leave Request Sent" alert the backend
  // writes to their Alerts inbox, so this isn't the only record of it.
  Future<void> _showSubmittedDialog(LeaveRequest? record) {
    final range = record?.rangeLabel ??
        '${LeaveRequest.formatShort(_isoOf(_start!))} - '
            '${LeaveRequest.formatShort(_isoOf(_end!))}';
    final days = record?.days ?? _days;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF16A34A), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Leave request sent',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: _kInk),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your ${_leaveType ?? 'leave'} for $range '
              '($days day(s)) is now with the admin.',
              style: const TextStyle(
                  fontSize: 13.5, color: _kInk, height: 1.45),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: const Text(
                'Approval may take at least 2-3 days. The decision will '
                'appear in your Alerts, and this request shows as Pending '
                'on your dashboard until then.',
                style:
                    TextStyle(fontSize: 12.5, color: _kMuted, height: 1.45),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _loadingWindow
                  ? const Center(
                      child: CircularProgressIndicator(color: _kBlue))
                  : _windowError != null
                      ? _buildWindowError()
                      : ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (_activeLeave != null) ...[
                              _buildActiveLeaveCard(_activeLeave!),
                              const SizedBox(height: 16),
                            ],
                            if (!_canFile) ...[
                              _buildBlockedCard(),
                              const SizedBox(height: 16),
                            ],
                            if (_canFile) ...[
                              _buildRulesCard(),
                              const SizedBox(height: 16),
                              _buildDatesCard(),
                              const SizedBox(height: 16),
                              _buildFormCard(),
                            ],
                            if (_history.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildHistoryCard(),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              'The admin reviews leave requests with the '
                              'higher authority. Approval may take at least '
                              '2-3 days, and you will get the decision in '
                              'your Alerts.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1034A6), Color(0xFF1E4AD0)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              children: [
                Text(
                  'Leave Request',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ask for a continuous stretch of days off',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildWindowError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 14),
            Text(
              _windowError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loadWindow,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // Already on leave — the form is beside the point, so it says where
  // they stand instead.
  Widget _buildActiveLeaveCard(LeaveRequest leave) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _kTeal.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.beach_access_rounded,
                    color: _kTeal, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'You are on leave',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _kInk),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${leave.leaveType} · ${leave.rangeLabel}',
                      style: const TextStyle(fontSize: 12.5, color: _kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kTeal.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kTeal.withOpacity(0.2)),
            ),
            child: Text(
              leave.daysRemaining <= 1
                  ? 'You report back for duty tomorrow.'
                  : 'You report back for duty on '
                      '${LeaveRequest.formatDate(leave.endDate)} — '
                      '${leave.daysRemaining} days left.',
              style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF0F766E),
                  height: 1.4,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // Why they can't file: a pending request, the yearly quota, or the
  // six-month cooldown. Said plainly, with the date it lifts.
  Widget _buildBlockedCard() {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_bottom_rounded,
                color: Color(0xFFD97706), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pendingRequestId != null
                      ? 'Your leave request is being reviewed'
                      : 'You cannot file a leave right now',
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: _kInk),
                ),
                const SizedBox(height: 5),
                Text(
                  _blockReason.isEmpty
                      ? 'Please try again later.'
                      : _blockReason,
                  style: const TextStyle(
                      fontSize: 12.5, color: _kMuted, height: 1.5),
                ),
                if (_pendingRequestId != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Approval may take at least 2-3 days.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The rules that govern this guard, stated before they type anything.
  Widget _buildRulesCard() {
    final used = (_quota['used'] as num?)?.toInt() ?? 0;
    final limit = (_quota['limit'] as num?)?.toInt() ?? 2;
    final year = (_quota['year'] as num?)?.toInt() ?? ServerClock.now().year;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 17, color: _kBlue),
              const SizedBox(width: 8),
              const Text(
                'Before you file',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _kInk),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$used of $limit used in $year',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kBlue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _rule('Your leave can start from '
              '${LeaveRequest.formatDate(_isoOf(_earliestStart))} — days '
              'already on a published schedule cannot be taken as leave.'),
          _rule('A leave runs at least $_minDays days in one stretch. For '
              '${_minDays - 1} days or fewer, file a special day-off '
              'request instead.'),
          _rule('You get $limit leaves a year, and the next one can be filed '
              '6 months after this one ends.'),
        ],
      ),
    );
  }

  Widget _rule(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: _kMuted),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 12.5, color: _kMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatesCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave duration',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _kInk),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dateField(
                  caption: 'Starts on',
                  value: _start,
                  hint: 'Pick a start date',
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateField(
                  caption: 'Ends on',
                  value: _end,
                  hint: _start == null ? 'Pick the start first' : 'Pick an end',
                  onTap: _start == null ? null : _pickEnd,
                ),
              ),
            ],
          ),
          if (_days > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _overCap
                        ? const Color(0xFFFEF2F2)
                        : _kBlue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _overCap
                            ? const Color(0xFFFECACA)
                            : _kBlue.withOpacity(0.2)),
                  ),
                  child: Text(
                    '$_days day(s)${_cap > 0 ? ' of $_cap' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _overCap ? _kDanger : _kBlue),
                  ),
                ),
              ],
            ),
          ],
          if (_overCap) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                'A $_leaveType can run at most $_cap days. A longer leave '
                'needs the consent of a higher authority and has to be '
                'recorded by the admin — talk to them directly.',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF991B1B), height: 1.45),
              ),
            ),
          ],
          if (_dateError != null) ...[
            const SizedBox(height: 8),
            Text(
              _dateError!,
              style: const TextStyle(fontSize: 12, color: _kDanger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateField({
    required String caption,
    required DateTime? value,
    required String hint,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: disabled ? _kPageBg : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.event,
                size: 17, color: disabled ? Colors.grey[400] : _kBlue),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(caption,
                      style:
                          TextStyle(fontSize: 10.5, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(
                    value == null
                        ? hint
                        : LeaveRequest.formatShort(_isoOf(value)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: value == null ? Colors.grey[500] : _kInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave details',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _kInk),
          ),
          const SizedBox(height: 12),

          const Text('Type of leave',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _types.map((t) {
              final selected = t.name == _leaveType;
              return InkWell(
                onTap: () => setState(() => _leaveType = t.name),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _kBlue : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: selected ? _kBlue : _kBorder),
                  ),
                  child: Text(
                    '${t.name} · ${t.maxDays}d',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _kMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          const Text('Title',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            decoration: _fieldDecoration(
                hint: 'e.g. Maternity leave', error: _titleError),
            style: const TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 16),

          const Text('Description',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyController,
            maxLines: 4,
            decoration: _fieldDecoration(
                hint: 'Explain why you need this leave.', error: _bodyError),
            style: const TextStyle(fontSize: 13.5),
          ),

          if (_submitError != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 16, color: _kDanger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _submitError!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF991B1B),
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _handleSubmit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 17),
              label: Text(_isSubmitting ? 'Sending…' : 'Submit Leave Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your leave history',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _kInk),
          ),
          const SizedBox(height: 12),
          for (final l in _history.take(6)) _buildHistoryRow(l),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(LeaveRequest l) {
    Color color;
    switch (l.phase) {
      case 'active':
        color = _kTeal;
        break;
      case 'upcoming':
        color = const Color(0xFF16A34A);
        break;
      case 'denied':
        color = _kDanger;
        break;
      case 'completed':
      case 'cancelled':
        color = _kMuted;
        break;
      default:
        color = const Color(0xFFF59E0B);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.leaveType} · ${l.rangeLabel}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: _kInk),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l.days} day(s) · ${l.statusLabel}'
                  '${l.adminNote.isEmpty ? '' : ' · ${l.adminNote}'}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint, String? error}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
      errorText: error,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBlue),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
