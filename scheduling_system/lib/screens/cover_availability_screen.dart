// screens/cover_availability_screen.dart
//
// Guard-facing "I'm available to cover" form, opened from the dashboard
// availability card or by tapping a rest day in the schedule. The guard is
// on a rest day and offers to come in: they pick the shift times and
// stations they'd prefer, and the offer boosts them to the top of the
// admin's replacement suggestions for that date (it is not an assignment).
// Pops with `true` once the offer reaches the backend so the caller can
// refresh.
import 'package:flutter/material.dart';
import '../models/cover_offer.dart';
import '../models/employee.dart';
import '../models/station.dart';
import '../services/api_service.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kGreen = Color(0xFF16A34A);
const Color _kInk = Color(0xFF1E293B);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kPageBg = Color(0xFFF8FAFC);

class CoverAvailabilityScreen extends StatefulWidget {
  final Employee employee;

  // The rest day this offer is for (date only).
  final DateTime date;

  const CoverAvailabilityScreen({
    super.key,
    required this.employee,
    required this.date,
  });

  @override
  State<CoverAvailabilityScreen> createState() =>
      _CoverAvailabilityScreenState();
}

// A shift option: the canonical label stored on the offer, and the shorter
// label shown on the chip.
class _ShiftOption {
  final String value; // 'Morning' | 'HG Day' | ...
  final String label; // 'Morning' | 'Day' | ...
  final String time; // '0500H - 1400H'
  const _ShiftOption(this.value, this.label, this.time);
}

class _CoverAvailabilityScreenState extends State<CoverAvailabilityScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _submitError;
  String? _shiftError;
  String? _stationError;

  // The offer already on file for this date, if any.
  CoverOffer? _existing;

  // Every station name the guard can pick from.
  List<String> _allStations = [];

  final Set<String> _selectedShifts = {};
  final Set<String> _selectedStations = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isHeadGuard => widget.employee.type == EmployeeType.headGuard;

  // Head guards work 12-hour Day/Night posts; everyone else the three
  // standard shifts. Only shifts the role can actually be posted to.
  List<_ShiftOption> get _shiftOptions => _isHeadGuard
      ? const [
          _ShiftOption('HG Day', 'Day', '0500H - 1700H'),
          _ShiftOption('HG Night', 'Night', '1700H - 0500H'),
        ]
      : const [
          _ShiftOption('Morning', 'Morning', '0500H - 1400H'),
          _ShiftOption('Afternoon', 'Afternoon', '1400H - 2330H'),
          _ShiftOption('Night', 'Night', '2100H - 0500H'),
        ];

  String get _isoDate => '${widget.date.year.toString().padLeft(4, '0')}-'
      '${widget.date.month.toString().padLeft(2, '0')}-'
      '${widget.date.day.toString().padLeft(2, '0')}';

  String get _displayDate {
    final d = widget.date;
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

  // Loads the station list and any offer already on file for this date,
  // then pre-selects the form: from the existing offer when editing, else
  // from the guard's own preferred stations as a sensible starting point.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final results = await Future.wait([
      ApiService.fetchStations(),
      ApiService.fetchEmployeeCoverOffers(widget.employee.id),
    ]);
    if (!mounted) return;

    final stationResult = results[0];
    final offerResult = results[1];

    if (stationResult['success'] != true) {
      setState(() {
        _isLoading = false;
        _loadError = stationResult['error']?.toString() ??
            'Could not load stations.';
      });
      return;
    }

    final stations = (stationResult['stations'] as List).cast<Station>();
    final names = stations
        .where((s) => s.name.trim().isNotEmpty)
        .map((s) => s.name.trim())
        .toSet()
        .toList()
      ..sort();

    CoverOffer? existing;
    if (offerResult['success'] == true) {
      final offers = (offerResult['offers'] as List).cast<CoverOffer>();
      for (final o in offers) {
        if (o.date == _isoDate) {
          existing = o;
          break;
        }
      }
    }

    final validShiftValues = _shiftOptions.map((o) => o.value).toSet();

    setState(() {
      _allStations = names;
      _existing = existing;
      _selectedShifts
        ..clear()
        ..addAll(existing != null
            ? existing.preferredShifts.where(validShiftValues.contains)
            : validShiftValues); // new: default to every shift they can work
      _selectedStations
        ..clear()
        ..addAll(existing != null
            ? existing.preferredStations.where(names.contains)
            : widget.employee.preferredStations
                .map((s) => s.trim())
                .where(names.contains));
      _isLoading = false;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _shiftError =
          _selectedShifts.isEmpty ? 'Pick at least one shift you can work.' : null;
      _stationError = _selectedStations.isEmpty
          ? 'Pick at least one station you can be deployed to.'
          : null;
      _submitError = null;
    });
    if (_selectedShifts.isEmpty || _selectedStations.isEmpty) return;

    setState(() => _isSubmitting = true);

    // Keep the shift order canonical (Morning, Afternoon, Night / Day, Night).
    final orderedShifts = _shiftOptions
        .map((o) => o.value)
        .where(_selectedShifts.contains)
        .toList();
    final orderedStations = _allStations
        .where(_selectedStations.contains)
        .toList();

    final result = await ApiService.submitCoverOffer(
      employeeId: widget.employee.id,
      employeeName: widget.employee.name,
      employeeType: widget.employee.type.name,
      date: _isoDate,
      preferredShifts: orderedShifts,
      preferredStations: orderedStations,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] != true) {
      setState(() => _submitError = result['error']?.toString() ??
          'Could not save your availability. Please try again.');
      return;
    }

    Navigator.of(context).pop(true);
  }

  Future<void> _withdraw() async {
    final offer = _existing;
    if (offer == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Withdraw availability?'),
        content: Text(
          "You will no longer be offered to cover on $_displayDate.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    final result = await ApiService.withdrawCoverOffer(offer.id);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] != true) {
      setState(() => _submitError = result['error']?.toString() ??
          'Could not withdraw. Please try again.');
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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kBlue))
                  : _loadError != null
                      ? _buildLoadError()
                      : _buildBody(),
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
          colors: [_kBlue, Color(0xFF1E4AD0)],
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
                  'Available to Cover',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Volunteer to come in on your rest day',
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

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _load,
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

  Widget _buildBody() {
    final fulfilled = _existing?.isFulfilled ?? false;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildContextCard(),
        const SizedBox(height: 16),
        if (fulfilled)
          _buildFulfilledCard()
        else ...[
          _buildFormCard(),
          const SizedBox(height: 16),
          Text(
            'Marking yourself available does not assign you a duty. It puts '
            'you at the top of the list when the admin needs someone to cover '
            'an absence on this day that matches your preferences.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContextCard() {
    final active = _existing?.isActive ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.volunteer_activism_outlined,
                size: 20, color: _kGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rest day',
                    style: TextStyle(fontSize: 11, color: _kMuted)),
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
          if (active)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Available',
                style: TextStyle(
                  color: _kGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Shown when the admin has already assigned this guard to cover — the
  // offer is locked and there's nothing more to edit.
  Widget _buildFulfilledCard() {
    final offer = _existing!;
    final where = offer.fulfilledStation;
    final what = offer.fulfilledShift;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGreen.withOpacity(0.35)),
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
                  color: _kGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle_outline,
                    size: 20, color: _kGreen),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "You've been assigned to cover",
                  style: TextStyle(
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
            (where != null && what != null)
                ? 'You are covering the $what shift at $where on this day. '
                    'Check your schedule and alerts for the details.'
                : 'You have been assigned to cover on this day. Check your '
                    'schedule and alerts for the details.',
            style: const TextStyle(fontSize: 13, color: _kInk, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    final editing = _existing?.isActive ?? false;
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
          const _FieldLabel('Which shift can you take?'),
          const SizedBox(height: 4),
          const Text(
            'Pick one or more.',
            style: TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _shiftOptions.map(_buildShiftChip).toList(),
          ),
          if (_shiftError != null) _buildFieldError(_shiftError!),
          const SizedBox(height: 20),

          const _FieldLabel('Where can you be deployed?'),
          const SizedBox(height: 4),
          const Text(
            'Pick the stations you can be sent to.',
            style: TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 10),
          if (_allStations.isEmpty)
            Text(
              'No stations available.',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allStations.map(_buildStationChip).toList(),
            ),
          if (_stationError != null) _buildFieldError(_stationError!),

          if (_submitError != null) ...[
            const SizedBox(height: 16),
            _buildSubmitErrorBanner(),
          ],

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _kGreen.withOpacity(0.5),
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
                  : Text(
                      editing ? 'Update availability' : "I'm available to cover",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          if (editing) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _isSubmitting ? null : _withdraw,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Withdraw availability'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftChip(_ShiftOption option) {
    final selected = _selectedShifts.contains(option.value);
    return GestureDetector(
      onTap: _isSubmitting
          ? null
          : () => setState(() {
                selected
                    ? _selectedShifts.remove(option.value)
                    : _selectedShifts.add(option.value);
                _shiftError = null;
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kGreen : _kPageBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _kGreen : _kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 15,
                  color: selected ? Colors.white : _kMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : _kInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              option.time,
              style: TextStyle(
                fontSize: 10,
                color: selected ? Colors.white70 : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationChip(String name) {
    final selected = _selectedStations.contains(name);
    return GestureDetector(
      onTap: _isSubmitting
          ? null
          : () => setState(() {
                selected
                    ? _selectedStations.remove(name)
                    : _selectedStations.add(name);
                _stationError = null;
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kBlue : _kPageBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kBlue : _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 14, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldError(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
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
              icon:
                  const Icon(Icons.close, size: 16, color: Color(0xFF92400E)),
            ),
          ),
        ],
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
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _kInk,
      ),
    );
  }
}
