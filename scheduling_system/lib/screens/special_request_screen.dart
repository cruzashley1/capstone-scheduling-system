// screens/special_request_screen.dart
//
// Guard-facing special day-off request form. Unlike an emergency absence
// (which is filed against a duty already on the schedule), a special
// request is filed AHEAD of time — the guard picks up to three upcoming
// days that no schedule covers yet, and an approved request forces those
// days off when that period's schedule is later generated.
//
// Pushed as a full screen from the Profile tab. Pops with `true` once the
// request reaches the backend so the host can show the confirmation.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/special_request.dart';
import '../services/api_service.dart';
import '../services/server_clock.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kInk = Color(0xFF1E293B);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kPageBg = Color(0xFFF8FAFC);

class SpecialRequestScreen extends StatefulWidget {
  final Employee employee;

  const SpecialRequestScreen({super.key, required this.employee});

  @override
  State<SpecialRequestScreen> createState() => _SpecialRequestScreenState();
}

class _SpecialRequestScreenState extends State<SpecialRequestScreen> {
  static const List<String> _reasons = [
    'Vacation',
    'Family Event',
    'Medical',
    'Personal',
    'Other',
  ];

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _reason = 'Vacation';
  String? _autoFilledTitle;

  // Window loaded from the backend: what the picker may offer.
  bool _loadingWindow = true;
  String? _windowError;
  late DateTime _minDate; // earliest selectable (tomorrow)
  late DateTime _maxDate; // latest selectable (+horizon)
  int _maxDates = 3;
  // ISO days the guard may NOT pick: already scheduled, or already on one
  // of their own pending/approved requests.
  Set<String> _blocked = {};
  Set<String> _requested = {};

  // The days the guard has chosen for this request (date-only), max _maxDates.
  final List<DateTime> _selectedDates = [];

  // The guard's own recent requests, shown as read-only history.
  List<SpecialRequest> _history = [];

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

  Future<void> _loadWindow() async {
    setState(() {
      _loadingWindow = true;
      _windowError = null;
    });

    final result =
        await ApiService.fetchSpecialRequestWindow(widget.employee.id);
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _loadingWindow = false;
        _windowError = result['error']?.toString().isNotEmpty == true
            ? 'Could not reach the server — ${result['error']}'
            : 'Could not load the request window. Please try again.';
      });
      return;
    }

    final min = DateTime.tryParse(result['minDate']?.toString() ?? '');
    final max = DateTime.tryParse(result['maxDate']?.toString() ?? '');
    // Load history in the background; a failure here just leaves it empty.
    ApiService.fetchEmployeeSpecialRequests(widget.employee.id).then((h) {
      if (!mounted || h['success'] != true) return;
      setState(() =>
          _history = (h['requests'] as List).cast<SpecialRequest>());
    });

    setState(() {
      _loadingWindow = false;
      final now = ServerClock.now();
      _minDate = min != null
          ? _dateOnly(min)
          : _dateOnly(now.add(const Duration(days: 1)));
      _maxDate = max != null
          ? _dateOnly(max)
          : _dateOnly(now.add(const Duration(days: 60)));
      _maxDates = (result['maxDates'] as int?) ?? 3;
      _blocked = (result['blockedDates'] as List).map((e) => e.toString()).toSet();
      _requested =
          (result['requestedDates'] as List).map((e) => e.toString()).toSet();
    });
  }

  // A day can be picked when it is inside the window, not already
  // scheduled, not already on one of the guard's requests, and not
  // already chosen for this one.
  bool _isSelectable(DateTime d) {
    final iso = _isoOf(d);
    if (d.isBefore(_minDate) || d.isAfter(_maxDate)) return false;
    if (_blocked.contains(iso)) return false;
    if (_requested.contains(iso)) return false;
    if (_selectedDates.any((s) => _isoOf(s) == iso)) return false;
    return true;
  }

  // The first day in the window still open to pick — the date picker needs
  // a selectable day to open on. Null when nothing is left.
  DateTime? get _firstSelectable {
    var d = _minDate;
    while (!d.isAfter(_maxDate)) {
      if (_isSelectable(d)) return d;
      d = d.add(const Duration(days: 1));
    }
    return null;
  }

  bool get _canAddMore => _selectedDates.length < _maxDates;

  Future<void> _pickDate() async {
    final initial = _firstSelectable;
    if (initial == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _minDate,
      lastDate: _maxDate,
      selectableDayPredicate: _isSelectable,
      helpText: 'Select a day off to request',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDates.add(_dateOnly(picked));
        _selectedDates.sort();
        _dateError = null;
      });
    }
  }

  void _removeDate(DateTime d) {
    setState(() => _selectedDates.removeWhere((s) => _isoOf(s) == _isoOf(d)));
  }

  void _selectReason(String reason) {
    final current = _titleController.text.trim();
    setState(() {
      _reason = reason;
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
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    setState(() {
      _dateError =
          _selectedDates.isEmpty ? 'Add at least one day to request off.' : null;
      _titleError = title.isEmpty ? 'Please give this request a title.' : null;
      _bodyError = body.isEmpty
          ? 'Please explain why so the admin can decide.'
          : null;
      _submitError = null;
    });
    if (_selectedDates.isEmpty || title.isEmpty || body.isEmpty) return;

    setState(() => _isSubmitting = true);

    final result = await ApiService.submitSpecialRequest(
      employeeId: widget.employee.id,
      employeeName: widget.employee.name,
      employeeType: widget.employee.type.name,
      station: widget.employee.assignedStation ?? '',
      dates: _selectedDates.map(_isoOf).toList(),
      title: title,
      reason: _reason,
      body: body,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] != true) {
      // Show the server's message verbatim — the 409 explains exactly why
      // (a date became scheduled, or was already requested).
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
              child: _loadingWindow
                  ? const Center(
                      child: CircularProgressIndicator(color: _kBlue))
                  : _windowError != null
                      ? _buildWindowError()
                      : ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            _buildDatesCard(),
                            const SizedBox(height: 16),
                            _buildFormCard(),
                            if (_history.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildHistoryCard(),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              'The admin reviews special requests and you '
                              'will get the decision in your Alerts. Approved '
                              'days are set off when that schedule is made.',
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
                  'Special Day-Off Request',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ask for days off before the schedule is made',
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
            Icon(Icons.cloud_off, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              _windowError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _kInk, height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadWindow,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Date chooser: the chosen days as removable chips + an Add button,
  // capped at the backend's maximum.
  Widget _buildDatesCard() {
    final noneLeft = _firstSelectable == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _dateError != null ? Colors.red[300]! : _kBorder),
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
                child: const Icon(Icons.event_available_outlined,
                    size: 20, color: _kBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Days off requested',
                        style: TextStyle(fontSize: 11, color: _kMuted)),
                    const SizedBox(height: 2),
                    Text(
                      '${_selectedDates.length} of $_maxDates selected',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_selectedDates.isEmpty)
            Text(
              noneLeft
                  ? 'There are no open days left to request in the next '
                      'stretch — every upcoming day is already scheduled or '
                      'requested.'
                  : 'No days chosen yet. Add up to $_maxDates upcoming days '
                      'you would like off.',
              style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.4),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedDates.map(_buildDateChip).toList(),
            ),

          if (_dateError != null) _buildFieldError(_dateError!),

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_isSubmitting || !_canAddMore || noneLeft)
                  ? null
                  : _pickDate,
              icon: const Icon(Icons.add, size: 18),
              label: Text(_canAddMore
                  ? 'Add a day'
                  : 'Maximum of $_maxDates days reached'),
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
      ),
    );
  }

  Widget _buildDateChip(DateTime d) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: _kBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBlue.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event, size: 15, color: _kBlue),
          const SizedBox(width: 6),
          Text(
            SpecialRequest.formatDate(_isoOf(d)),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kBlue,
            ),
          ),
          SizedBox(
            width: 26,
            height: 26,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: _isSubmitting ? null : () => _removeDate(d),
              icon: const Icon(Icons.close, size: 15, color: _kBlue),
            ),
          ),
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
              hint: 'Short title, e.g. "Family vacation"',
              hasError: _titleError != null,
            ),
          ),
          if (_titleError != null) _buildFieldError(_titleError!),
          const SizedBox(height: 12),

          const _FieldLabel('Reason details'),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyController,
            enabled: !_isSubmitting,
            minLines: 4,
            maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: _kInk, height: 1.4),
            onChanged: (_) {
              if (_bodyError != null) setState(() => _bodyError = null);
            },
            decoration: _inputDecoration(
              hint: 'Explain why you need these days off.',
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

  // Compact read-only list of what this guard already filed, so they don't
  // re-file the same days and can see each request's status.
  Widget _buildHistoryCard() {
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
          const Text(
            'Your requests',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 12),
          ..._history.take(5).map(_buildHistoryRow),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(SpecialRequest r) {
    late final Color color;
    late final String label;
    if (r.isApproved) {
      color = const Color(0xFF16A34A);
      label = 'Approved';
    } else if (r.isDenied) {
      color = const Color(0xFFDC2626);
      label = 'Denied';
    } else {
      color = const Color(0xFFF59E0B);
      label = 'Pending';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.datesSummary,
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
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
            child:
                Icon(Icons.warning_amber, size: 18, color: Color(0xFFD97706)),
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
              icon: const Icon(Icons.close, size: 16, color: Color(0xFF92400E)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
