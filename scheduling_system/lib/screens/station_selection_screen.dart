// screens/station_selection_screen.dart
//
// Shown once during onboarding, right after a guard sets their first
// password. It lists every active station and lets the employee confirm
// the preferred stations Sched should try to place them at.
//
// Because every employee already has preferred stations stored, the
// picker opens PRE-SELECTED with whatever is on their record — so this is
// a confirm/edit step, not a blank slate.
//
// Minimum rule (decided with the product owner):
//   - If the record already had preferred stations, they only need to keep
//     at least one selected to continue ("confirm as-is").
//   - If the record had NONE, they must pick at least 5 before continuing.
//
// On continue it saves the selection and clears the server-side
// mustSelectStations flag (so this screen never appears again), then routes
// straight to the employee's dashboard.
import 'package:flutter/material.dart';
import '../models/station.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import 'headguardui/head_guard_layout.dart';
import 'securityguardui/security_guard_layout.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kBlueLight = Color(0xFF1E88E5);
const Color _kInk = Color(0xFF1E293B);

// The number of stations required when the employee has no preferences yet.
const int _kMinWhenEmpty = 5;

class StationSelectionScreen extends StatefulWidget {
  final String username;
  final String role; // 'headGuard' | 'regular' | 'reliever'
  final List<String> initialStations;

  const StationSelectionScreen({
    super.key,
    required this.username,
    required this.role,
    required this.initialStations,
  });

  @override
  State<StationSelectionScreen> createState() => _StationSelectionScreenState();
}

class _StationSelectionScreenState extends State<StationSelectionScreen> {
  bool _loading = true;
  String? _error;
  List<Station> _stations = [];
  late final Set<String> _selected = widget.initialStations.toSet();
  bool _saving = false;

  // Whether the record already had preferred stations when this screen
  // opened. Drives the "min 5 only when empty" rule.
  late final bool _hadExisting = widget.initialStations.isNotEmpty;

  int get _minRequired => _hadExisting ? 1 : _kMinWhenEmpty;

  bool get _canContinue => _selected.length >= _minRequired;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.fetchStations();
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _stations = (result['stations'] as List)
            .cast<Station>()
            .where((s) => s.isActive)
            .toList();
      } else {
        _error = ApiService.friendlyError(
            result['error']?.toString() ?? 'Failed to load stations');
      }
    });
  }

  // Saved in the same order the stations are listed; any previously saved
  // name that no longer matches a live station is kept at the end so we
  // never silently drop a preference.
  List<String> get _orderedSelection {
    final ordered = _stations
        .map((s) => s.name)
        .where(_selected.contains)
        .toList();
    for (final name in _selected) {
      if (!ordered.contains(name)) ordered.add(name);
    }
    return ordered;
  }

  Future<void> _continue() async {
    if (!_canContinue || _saving) return;
    setState(() => _saving = true);

    final result = await ApiService.confirmPreferredStations(
      username: widget.username,
      preferredStations: _orderedSelection,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ApiService.friendlyError(
              result['error']?.toString() ?? 'Failed to save preferences.')),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // Onboarding is complete — remember the session so the app reopens
    // signed in, then route to the right dashboard.
    await Session.save(widget.username, widget.role);
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => widget.role == 'headGuard'
            ? HeadGuardLayout(username: widget.username)
            : SecurityGuardLayout(username: widget.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Back is disabled: the employee must confirm before entering the app.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBlue, _kBlueLight],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Icon(Icons.star_outline,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(height: 18),
              const Text(
                'Choose Your Preferred Stations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _hadExisting
                    ? 'These are the stations already on your record. '
                        'Confirm or adjust them before continuing.'
                    : 'Select at least $_kMinWhenEmpty stations you prefer to '
                        'be assigned to. The admin sees these when placing you.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kBlue));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 44, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                'Could not load stations',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadStations, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_stations.isEmpty) {
      return Center(
        child: Text(
          'No stations available yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      itemCount: _stations.length,
      itemBuilder: (context, index) => _buildStationRow(_stations[index]),
    );
  }

  Widget _buildStationRow(Station station) {
    final bool selected = _selected.contains(station.name);
    return GestureDetector(
      onTap: _saving
          ? null
          : () => setState(() {
                if (selected) {
                  _selected.remove(station.name);
                } else {
                  _selected.add(station.name);
                }
              }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _kBlue.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kBlue : const Color(0xFFE2E8F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined,
                  color: _kBlue, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                station.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kInk,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? _kBlue : Colors.grey[300],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    // The counter only nags about the minimum while it isn't met yet.
    final bool showMinHint = !_canContinue;
    final int remaining = _minRequired - _selected.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kInk,
                    ),
                  ),
                  const Spacer(),
                  if (showMinHint)
                    Text(
                      'Select $remaining more',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[700],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_canContinue && !_saving) ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
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
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
