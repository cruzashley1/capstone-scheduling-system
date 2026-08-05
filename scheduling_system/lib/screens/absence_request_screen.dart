// screens/absence_request_screen.dart
//
// Guard-facing emergency absence form. Pushed as a full screen (not a
// sheet) from the dashboard card so the guard has room to type a proper
// description. Pops with `true` once the request reaches the backend —
// the host shows the confirmation.
import 'package:flutter/material.dart';
import '../models/absence_request.dart';
import '../models/employee.dart';
import '../models/guard_shift.dart';
import '../services/api_service.dart';
import '../services/duty_clock.dart';
import '../services/server_clock.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kInk = Color(0xFF1E293B);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kPageBg = Color(0xFFF8FAFC);

class AbsenceRequestScreen extends StatefulWidget {
  final Employee employee;

  // The guard's upcoming duties from the published schedule — the only
  // dates an absence can be filed for (you can only be absent from a
  // scheduled duty, and only for today or a future day still on the
  // schedule). Station and shift are read from the duty for the picked day.
  final List<GuardShift> shifts;

  // Every request this guard has already filed (any status). The date it
  // opens on defaults to today; if a day already has one of these, the
  // form shows that decision instead of letting them file it again.
  final List<AbsenceRequest> existingRequests;

  // The day the form opens on — always today's date, so the guard sees
  // the current date first and changes it only if they mean another day.
  final DateTime initialDate;

  const AbsenceRequestScreen({
    super.key,
    required this.employee,
    required this.shifts,
    required this.existingRequests,
    required this.initialDate,
  });

  @override
  State<AbsenceRequestScreen> createState() => _AbsenceRequestScreenState();
}

class _AbsenceRequestScreenState extends State<AbsenceRequestScreen> {
  static const List<String> _reasons = [
    'Sick',
    'Injury',
    'Family Emergency',
    'Important Occasion',
    'Other',
  ];

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _reason = 'Sick';

  // Remembers what a chip last wrote into the title so we only overwrite
  // our own suggestion — anything the guard typed themselves is kept.
  String? _autoFilledTitle;

  bool _isSubmitting = false;
  String? _titleError;
  String? _bodyError;
  String? _submitError;

  // Duty dates the guard may FILE a new request for: today or later, still
  // on the schedule, and not already requested. Empty => nothing to file.
  List<DateTime> _selectableDates = [];
  // The day the form is showing. Defaults to today and only moves when the
  // guard picks another day — so today's date is always what they see first.
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.initialDate);
    _computeSelectableDates();
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

  // Every duty still on the schedule whose 1-hour lock-out hasn't started
  // and that the guard hasn't already filed for — the days a NEW request
  // may target. Filing closes an hour before time-in: a 1400H duty stops
  // being fileable at 1300H, not at midnight.
  void _computeSelectableDates() {
    _selectableDates = DutyClock.fileableDates(
      shifts: widget.shifts,
      existingRequests: widget.existingRequests,
    );
  }

  // A duty exists on the shown day but its time-out has already passed.
  bool get _selectedDutyAlreadyEnded {
    final shift = _selectedShift;
    if (shift == null) return false;
    return shift.hasEndedBy(ServerClock.now());
  }

  // A duty exists on the shown day but it is within an hour of time-in,
  // running, or over — the reason the form is closed matters to the guard.
  bool get _selectedDutyLocked {
    final shift = _selectedShift;
    if (shift == null) return false;
    return DutyClock.isPastAbsenceCutoff(shift, ServerClock.now());
  }

  // 'You can file until 1300H' — the deadline for the shown day's duty.
  String? get _selectedCutoffLabel {
    final shift = _selectedShift;
    if (shift == null) return null;
    final deadline = DutyClock.absenceDeadline(shift);
    return deadline == null ? null : DutyClock.military(deadline);
  }

  String get _noDutyExplanation {
    final tail = _selectableDates.isEmpty
        ? ''
        : ' You can still file for an upcoming duty.';
    if (_selectedDutyAlreadyEnded) {
      final out = _selectedShift?.timeOut ?? '';
      final when = out.isEmpty ? 'has already ended' : 'ended at $out';
      return 'Your ${_shiftTitle.toLowerCase()} $when. An absence can only '
          'be filed before the duty starts.$tail';
    }
    if (_selectedDutyLocked) {
      final cutoff = _selectedCutoffLabel;
      final inTime = _selectedShift?.timeIn ?? '';
      return 'Requests close 1 hour before time-in. Your '
          '${_shiftTitle.toLowerCase()}'
          '${inTime.isEmpty ? '' : ' starts at $inTime'}, so the cut-off'
          '${cutoff == null ? '' : ' of $cutoff'} has passed — report the '
          'emergency to your head guard directly.$tail';
    }
    if (_selectableDates.isEmpty) {
      return 'You have no upcoming duty on the schedule to request off.';
    }
    return 'You can only file an absence for a day you are on duty. '
        'Change the date to one of your upcoming duties.';
  }

  // The request already on file for the day being shown, if any — drives
  // the "already approved / denied / pending" state.
  AbsenceRequest? get _existingForSelected {
    final iso = _isoDate;
    for (final r in widget.existingRequests) {
      if (r.date == iso) return r;
    }
    return null;
  }

  // A new request can be filed for the shown day only when it's one of the
  // selectable duty days (has a duty, not already filed) AND that duty
  // hasn't crossed its cut-off in the meantime — the list is built once on
  // open, so the lock-out can begin while the form sits there.
  bool get _isSelectedFileable =>
      _selectableDates.any((d) => d == _selectedDate) &&
      !_selectedDutyLocked;

  // The duty for the shown day — carries its station and shift.
  GuardShift? get _selectedShift {
    for (final s in widget.shifts) {
      if (_dateOnly(s.date) == _selectedDate) return s;
    }
    return null;
  }

  // Station for the request: the day's duty station, else the fixed
  // assignment, else blank so the backend/admin sees "unknown".
  String get _station {
    final shift = _selectedShift;
    if (shift != null && shift.stationName.isNotEmpty) return shift.stationName;
    final assigned = widget.employee.assignedStation;
    if (assigned != null && assigned.isNotEmpty) return assigned;
    return '';
  }

  String get _shiftTitle => _selectedShift?.title ?? '';

  // 'YYYY-MM-DD' — the exact shape the absence_requests collection wants.
  String get _isoDate => _isoOf(_selectedDate);

  // 'Friday, July 24, 2026' — same wording as AttendanceReport.shiftDate.
  String get _displayDate {
    final d = _selectedDate;
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} '
        '${d.day}, ${d.year}';
  }

  // Lets the guard change which duty day they'll be absent from, bounded
  // to their selectable duty dates only.
  Future<void> _pickDate() async {
    if (_selectableDates.isEmpty) return;
    final selectable = _selectableDates.map(_isoOf).toSet();
    // The dialog's initial day must itself be selectable; today may not be
    // (already filed / a rest day), so fall back to the first duty day.
    final initial = selectable.contains(_isoDate)
        ? _selectedDate
        : _selectableDates.first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _selectableDates.first,
      lastDate: _selectableDates.last,
      selectableDayPredicate: (d) => selectable.contains(_isoOf(d)),
      helpText: 'Select the duty day you will be absent',
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = _dateOnly(picked));
    }
  }

  void _selectReason(String reason) {
    final current = _titleController.text.trim();
    setState(() {
      _reason = reason;
      // Only prefill while the title is untouched or still holds the
      // previous chip's text, so typing over it sticks.
      if (current.isEmpty || current == _autoFilledTitle) {
        _titleController.text = reason;
        _titleController.selection =
            TextSelection.collapsed(offset: reason.length);
        _autoFilledTitle = reason;
        _titleError = null;
      }
    });
  }

  Future<void> _handleSubmit() async {
    // The shown day must actually be fileable — not already requested, and
    // a real upcoming duty. (The button is disabled otherwise; this guards
    // against a stale tap.)
    if (!_isSelectedFileable) {
      setState(() {
        if (_existingForSelected != null) {
          _submitError = 'You have already filed a request for this day.';
        } else if (_selectedDutyAlreadyEnded) {
          _submitError = 'This duty has already ended — an absence can no '
              'longer be filed for it.';
        } else if (_selectedDutyLocked) {
          _submitError = 'Requests close 1 hour before time-in. This duty is '
              'inside that window, so it can no longer be filed for.';
        } else {
          _submitError = 'You have no scheduled duty on this day to request '
              'off.';
        }
      });
      return;
    }

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    setState(() {
      _titleError = title.isEmpty ? 'Please give a short reason.' : null;
      _bodyError = body.isEmpty
          ? 'Please describe what happened so the admin can decide.'
          : null;
      _submitError = null;
    });
    if (title.isEmpty || body.isEmpty) return;

    setState(() => _isSubmitting = true);

    final result = await ApiService.submitAbsenceRequest(
      employeeId: widget.employee.id,
      employeeName: widget.employee.name,
      employeeType: widget.employee.type.name,
      station: _station,
      shiftTitle: _shiftTitle,
      date: _isoDate,
      title: title,
      reason: _reason,
      body: body,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] != true) {
      // Show the server's message verbatim — the duplicate-request 409
      // explains exactly why the submit was rejected.
      setState(() => _submitError = result['error']?.toString() ??
          'Could not send your request. Please try again.');
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildContextCard(),
                  const SizedBox(height: 16),
                  // What the shown day is: an existing decision, a day with
                  // no duty, or a fileable duty (the actual form).
                  if (_existingForSelected != null)
                    _buildAlreadyRequestedCard(_existingForSelected!)
                  else if (!_isSelectedFileable)
                    _buildNoDutyCard()
                  else
                    _buildFormCard(),
                  const SizedBox(height: 16),
                  Text(
                    'Requests close 1 hour before your time-in. The admin '
                    'reviews emergency requests as soon as they come in, and '
                    'you will get the decision in your Alerts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                      height: 1.4,
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
                  'Emergency Absence Request',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Sent to the admin for approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          // Balances the back button so the title sits centred.
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  // Recap of the duty this request covers. The date is editable — bounded
  // to the guard's upcoming, not-yet-requested duty days.
  Widget _buildContextCard() {
    final hasDuty = _selectedShift != null;
    // Station/shift only make sense on a day the guard is actually on duty.
    final station = hasDuty ? _station.trim() : '';
    final shift = hasDuty ? _shiftTitle.trim() : '';
    final hasStation = station.isNotEmpty;
    final hasShift = shift.isNotEmpty;
    final hasCutoff = _isSelectedFileable && _selectedCutoffLabel != null;
    // Offer "Change" whenever there's a fileable day to move to that isn't
    // the one already shown.
    final canChangeDate = !_isSubmitting &&
        _selectableDates.any((d) => d != _selectedDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_busy_outlined,
                    size: 20, color: _kBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Absence for',
                      style: TextStyle(fontSize: 11, color: _kMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayDate,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (canChangeDate)
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                  label: const Text('Change'),
                  style: TextButton.styleFrom(
                    foregroundColor: _kBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (hasStation || hasShift || hasCutoff) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 12),
            if (hasStation)
              _buildContextRow(Icons.location_on_outlined, station),
            if (hasStation && hasShift) const SizedBox(height: 8),
            if (hasShift)
              _buildContextRow(Icons.schedule_outlined, shift),
            // The deadline, spelled out while there's still time to meet it.
            if (hasCutoff) ...[
              if (hasStation || hasShift) const SizedBox(height: 8),
              _buildContextRow(
                Icons.timer_outlined,
                'File before ${_selectedCutoffLabel!} — 1 hour before '
                'time-in',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildContextRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: _kMuted),
          ),
        ),
      ],
    );
  }

  // Shown in place of the form when the day already has a request: the
  // guard can't file it twice, but sees the decision and can change the
  // date to file for another day.
  Widget _buildAlreadyRequestedCard(AbsenceRequest request) {
    late final Color color;
    late final IconData icon;
    late final String label;
    late final String message;
    if (request.isApproved) {
      color = const Color(0xFF16A34A);
      icon = Icons.check_circle_outline;
      label = 'Approved';
      message = 'Your absence for this day has been approved.';
    } else if (request.isDenied) {
      color = const Color(0xFFDC2626);
      icon = Icons.cancel_outlined;
      label = 'Denied';
      message = 'Your absence for this day was denied — please report for '
          'duty as scheduled.';
    } else {
      color = const Color(0xFFF59E0B);
      icon = Icons.hourglass_bottom_rounded;
      label = 'Pending';
      message = 'You already filed for this day. The admin is still '
          'reviewing it.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Already requested',
                      style: TextStyle(fontSize: 11, color: _kMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: _kInk, height: 1.4),
          ),
          if (request.adminNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Admin note: ${request.adminNote}',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[600], height: 1.4),
            ),
          ],
          if (_selectableDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _pickDate,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Request for another day'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Shown when the chosen day has no duty (e.g. today is a rest day): the
  // guard can't be absent from a day they aren't scheduled, but can change
  // to an upcoming duty day.
  Widget _buildNoDutyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kMuted.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_available_outlined,
                    size: 20, color: _kMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedDutyAlreadyEnded
                      ? 'This duty has already ended'
                      : _selectedDutyLocked
                          ? 'Too close to your time-in'
                          : 'No duty scheduled on this day',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _noDutyExplanation,
            style: const TextStyle(fontSize: 13, color: _kInk, height: 1.4),
          ),
          if (_selectableDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _pickDate,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Pick an upcoming duty'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Reason'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reasons.map(_buildReasonChip).toList(),
          ),
          const SizedBox(height: 20),

          const _FieldLabel('Title'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            enabled: !_isSubmitting,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: _kInk),
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            decoration: _inputDecoration(
              hint: 'Short reason, e.g. "Sudden high fever"',
              hasError: _titleError != null,
            ),
          ),
          if (_titleError != null) _buildFieldError(_titleError!),
          const SizedBox(height: 12),

          const _FieldLabel('Description'),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyController,
            enabled: !_isSubmitting,
            minLines: 5,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: _kInk, height: 1.4),
            onChanged: (_) {
              if (_bodyError != null) setState(() => _bodyError = null);
            },
            decoration: _inputDecoration(
              hint: 'What happened, and do you expect to return for your '
                  'next duty?',
              hasError: _bodyError != null,
            ),
          ),
          if (_bodyError != null) _buildFieldError(_bodyError!),

          if (_submitError != null) ...[
            const SizedBox(height: 16),
            _buildSubmitErrorBanner(),
          ],

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _kBlue.withOpacity(0.5),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Request',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonChip(String reason) {
    final selected = _reason == reason;
    return GestureDetector(
      onTap: _isSubmitting ? null : () => _selectReason(reason),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kBlue : _kPageBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kBlue : _kBorder),
        ),
        child: Text(
          reason,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : _kMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildFieldError(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 14, color: Colors.red[700]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[700],
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Server-side failures (duplicate pending request, network, validation)
  // land here in full — the 409 text is the guard's only explanation.
  Widget _buildSubmitErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD97706)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber,
                size: 18, color: Color(0xFFD97706)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _submitError!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E),
                height: 1.35,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _submitError = null),
              icon: const Icon(Icons.close,
                  size: 16, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required bool hasError,
  }) {
    final border = hasError ? Colors.red[300]! : _kBorder;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
      filled: true,
      fillColor: _kPageBg,
      counterStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? Colors.red[400]! : _kBlue,
          width: 1.5,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _kInk,
      ),
    );
  }
}
