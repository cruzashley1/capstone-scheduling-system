// screens/set_on_leave_dialog.dart
//
// The admin's "Set On Leave" form, opened from Employee Details. Unlike
// a guard-filed request this is recorded, not requested: it saves as
// approved the moment it is submitted.
//
// Two submits, deliberately. The first sends the leave as-is; if it
// breaks a rule — the type's day cap, the 2-per-year quota, the 6-month
// cooldown, an overlapping leave — the backend refuses with the list of
// what broke, and the form reopens with those spelled out plus the
// endorsement fields. Only the second submit, naming the supervisor who
// approved it, may proceed. Nothing here decides the rules; they all
// live in backend_python/leave.py.

import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../services/api_service.dart';

const _kBlue = Color(0xFF1034A6);
const _kBorder = Color(0xFFE2E8F0);
const _kText = Color(0xFF1E293B);
const _kMuted = Color(0xFF64748B);
const _kDanger = Color(0xFFB91C1C);

class SetOnLeaveDialog extends StatefulWidget {
  final Employee employee;

  const SetOnLeaveDialog({super.key, required this.employee});

  @override
  State<SetOnLeaveDialog> createState() => _SetOnLeaveDialogState();
}

class _SetOnLeaveDialogState extends State<SetOnLeaveDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _supervisorController = TextEditingController();

  List<LeaveType> _types = [];
  String? _leaveType;

  // Kept as two separate dates rather than a DateTimeRange: the range
  // picker opens as a full-screen page on desktop, which is far too much
  // chrome for two fields inside a dialog. Two compact calendars read
  // better and let the end date's own bounds enforce the minimum length.
  DateTime? _start;
  DateTime? _end;

  // The shortest thing that counts as leave, from the backend so the
  // number lives in one place. Falls back to 4 if the catalogue call
  // fails — the server rejects anything shorter regardless.
  int _minDays = 4;

  bool _loadingTypes = true;
  bool _saving = false;

  // Set once the backend refuses: the rules this leave breaks, and the
  // endorsement the admin has to record to push past them.
  List<Map<String, dynamic>> _blockers = [];
  bool _endorsementConfirmed = false;
  String? _error;

  bool get _needsEndorsement => _blockers.isNotEmpty;

  int get _cap {
    final match = _types.where((t) => t.name == _leaveType);
    return match.isEmpty ? 0 : match.first.maxDays;
  }

  int get _days => (_start == null || _end == null)
      ? 0
      : _end!.difference(_start!).inDays + 1;

  bool get _overCap => _cap > 0 && _days > _cap;
  bool get _tooShort => _days > 0 && _days < _minDays;

  bool get _canSubmit {
    if (_saving) return false;
    if (_leaveType == null || _start == null || _end == null) return false;
    if (_tooShort) return false;
    if (_titleController.text.trim().isEmpty) return false;
    if (_bodyController.text.trim().isEmpty) return false;
    if (_needsEndorsement) {
      return _endorsementConfirmed &&
          _supervisorController.text.trim().isNotEmpty;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _supervisorController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final result = await ApiService.fetchLeaveTypes();
    if (!mounted) return;
    setState(() {
      _loadingTypes = false;
      if (result['success'] == true) {
        _types = (result['leaveTypes'] as List).cast<LeaveType>();
        _minDays = (result['minLeaveDays'] as int?) ?? _minDays;
        _leaveType = result['defaultLeaveType'] as String?;
        if (_leaveType != null && !_types.any((t) => t.name == _leaveType)) {
          _leaveType = _types.isEmpty ? null : _types.first.name;
        }
      } else {
        _error = 'Could not load the leave types — ${result['error']}';
      }
    });
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // One compact calendar dialog, themed to the app's blue. Used for both
  // ends of the range so neither takes over the screen.
  Future<DateTime?> _pickDate({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
    required String help,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: help,
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
    final now = DateTime.now();
    final picked = await _pickDate(
      initial: _start ?? DateTime(now.year, now.month, now.day),
      // The admin is recording something already agreed, so unlike the
      // guard's form this reaches back — a leave that started last week
      // still has to be enterable.
      first: DateTime(now.year - 1),
      last: DateTime(now.year + 2),
      help: 'Leave starts on',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked;
      // Keep the end date legal rather than silently leaving an invalid
      // pair on screen: anything shorter than the minimum snaps out to it.
      final floor = picked.add(Duration(days: _minDays - 1));
      if (_end == null || _end!.isBefore(floor)) _end = floor;
    });
  }

  Future<void> _pickEnd() async {
    final start = _start;
    if (start == null) return;
    // The minimum length is enforced by the calendar's own bounds — the
    // days that would make too short a leave simply aren't selectable.
    final floor = start.add(Duration(days: _minDays - 1));
    final picked = await _pickDate(
      initial: (_end != null && !_end!.isBefore(floor)) ? _end! : floor,
      first: floor,
      last: start.add(const Duration(days: 365)),
      help: 'Leave ends on',
    );
    if (picked == null || !mounted) return;
    setState(() => _end = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await ApiService.setEmployeeOnLeave(
      employeeId: widget.employee.id,
      leaveType: _leaveType!,
      startDate: _iso(_start!),
      endDate: _iso(_end!),
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      overrideRules: _needsEndorsement,
      supervisorName: _supervisorController.text.trim(),
      supervisorConfirmed: _endorsementConfirmed,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.pop(context, {
        'request': result['request'],
        'affectedDuties': result['affectedDuties'] ?? const [],
      });
      return;
    }

    // A refusal that names broken rules turns the form into the override
    // form; anything else is just an error to show.
    final blockers =
        (result['blockers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _saving = false;
      _error = result['error']?.toString() ?? 'Could not save the leave.';
      if (blockers.isNotEmpty) _blockers = blockers;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.beach_access_rounded,
                color: Color(0xFF0D9488), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set On Leave',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kText),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.employee.name} · ${widget.employee.id}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _loadingTypes
            ? const SizedBox(
                height: 120,
                child: Center(
                    child: CircularProgressIndicator(color: _kBlue)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1, color: _kBorder),
                    const SizedBox(height: 16),

                    _label('Leave type'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _leaveType,
                      isExpanded: true,
                      decoration: _decoration(),
                      items: _types
                          .map((t) => DropdownMenuItem(
                                value: t.name,
                                child: Text(
                                  '${t.name}  ·  up to ${t.maxDays} days',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _leaveType = v),
                    ),
                    const SizedBox(height: 16),

                    _label('Duration'),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _dateField(
                            caption: 'Starts on',
                            value: _start,
                            onTap: _pickStart,
                            hint: 'Pick a start date',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dateField(
                            caption: 'Ends on',
                            value: _end,
                            onTap: _start == null ? null : _pickEnd,
                            hint: _start == null
                                ? 'Pick the start first'
                                : 'Pick an end date',
                          ),
                        ),
                      ],
                    ),
                    if (_days > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _dayCountChip(),
                          const SizedBox(width: 8),
                          if (_tooShort)
                            Flexible(
                              child: Text(
                                'a leave has to run at least $_minDays days',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kDanger),
                              ),
                            )
                          else if (_overCap)
                            const Flexible(
                              child: Text(
                                'past this type\'s cap — needs endorsement',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kDanger),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    _label('Title'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _titleController,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration(
                          hint: 'e.g. Maternity leave'),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    const SizedBox(height: 16),

                    _label('Description'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bodyController,
                      onChanged: (_) => setState(() {}),
                      maxLines: 3,
                      decoration: _decoration(
                          hint: 'Why this employee is being placed on leave.'),
                      style: const TextStyle(fontSize: 13.5),
                    ),

                    if (_needsEndorsement) ...[
                      const SizedBox(height: 18),
                      _buildBlockerBlock(),
                    ] else if (_error != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorBlock(_error!),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: _kMuted),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _saving
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  _needsEndorsement
                      ? Icons.gavel_rounded
                      : Icons.check_rounded,
                  size: 16),
          label: Text(_needsEndorsement
              ? 'Override & Set On Leave'
              : 'Set On Leave'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _needsEndorsement ? _kDanger : _kBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFCBD5E1),
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted),
      );

  // One end of the range: a tappable field that reads like the rest of
  // the form and opens a normal-sized calendar rather than a full page.
  Widget _dateField({
    required String caption,
    required DateTime? value,
    required VoidCallback? onTap,
    required String hint,
  }) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFF8FAFC) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.event,
                size: 17, color: disabled ? Colors.grey[400] : _kBlue),
            const SizedBox(width: 10),
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
                        : LeaveRequest.formatDate(_iso(value)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: value == null ? Colors.grey[500] : _kText,
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

  Widget _dayCountChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (_overCap || _tooShort)
            ? const Color(0xFFFEF2F2)
            : _kBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (_overCap || _tooShort)
                ? const Color(0xFFFECACA)
                : _kBlue.withOpacity(0.2)),
      ),
      child: Text(
        '$_days day(s)${_cap > 0 ? ' of $_cap' : ''}',
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: (_overCap || _tooShort) ? _kDanger : _kBlue),
      ),
    );
  }

  InputDecoration _decoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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

  Widget _buildErrorBlock(String message) {
    return Container(
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
              message,
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF991B1B), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // The consent gate: every rule this leave breaks, spelled out, and the
  // endorsement that has to be recorded against them.
  Widget _buildBlockerBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 16, color: _kDanger),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Higher authority required',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF991B1B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in _blockers)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(
                          fontSize: 12.5, color: Color(0xFF991B1B))),
                  Expanded(
                    child: Text(
                      b['message']?.toString() ?? b['rule']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF991B1B),
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Approving this leave without proper consent in the higher '
            'authority will result to heavy penalty.',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7F1D1D),
                height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _supervisorController,
            onChanged: (_) => setState(() {}),
            decoration: _decoration(
                hint: 'Endorsed by (Supervisor) — full name *'),
            style: const TextStyle(fontSize: 13.5),
          ),
          CheckboxListTile(
            value: _endorsementConfirmed,
            onChanged: (v) =>
                setState(() => _endorsementConfirmed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _kDanger,
            title: const Text(
              'I confirm this leave was discussed with and approved by the '
              'supervisor named above.',
              style: TextStyle(
                  fontSize: 12.5, color: Color(0xFF7F1D1D), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
