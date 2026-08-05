// screens/special_assignment_dialog.dart
//
// The Special Assignments dialog for one station: pick employees on the
// left, they land in the pinned list on the right with a shift chooser.
// Saving replaces the station's pins for the selected rotation cycle
// (calendar month) in one idempotent PUT.
//
// A pin means: when a schedule is generated for a period inside that
// month, this employee is placed at this station on that shift — ahead
// of the monthly rotation shuffle and their permanent assignment. Pins
// last one cycle and expire on their own.
import 'package:flutter/material.dart';
import '../models/duty_post.dart';
import '../models/employee.dart';
import '../models/special_assignment.dart';
import '../models/station.dart';
import '../services/api_service.dart';

const _primary = Color(0xFF1034A6);

// Duty chips. Amber is the one that matters: that guard is on another
// station's saved schedule for these dates, so pinning them here strands
// that roster until it is regenerated.
const _dutyElsewhere = Color(0xFFB45309);
const _dutyFree = Color(0xFF64748B);

// Storable shift value -> label shown in dropdowns and chips.
const Map<String, String> _shiftLabels = {
  'morning': 'Morning',
  'afternoon': 'Afternoon',
  'night': 'Night',
  'hgDay': 'HG Day',
  'hgNight': 'HG Night',
};

List<String> _shiftOptionsFor(EmployeeType type) {
  switch (type) {
    case EmployeeType.headGuard:
      return const ['hgDay', 'hgNight'];
    case EmployeeType.reliever:
      return const []; // relievers float morning/afternoon, never pinned to a shift
    case EmployeeType.regular:
      return const ['morning', 'afternoon', 'night'];
  }
}

class SpecialAssignmentDialog extends StatefulWidget {
  final Station station;

  const SpecialAssignmentDialog({super.key, required this.station});

  @override
  State<SpecialAssignmentDialog> createState() =>
      _SpecialAssignmentDialogState();
}

class _SpecialAssignmentDialogState extends State<SpecialAssignmentDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  EmployeeType? _typeFilter;

  late String _cycleId;
  late final List<String> _cycleOptions;

  List<Employee> _employees = [];

  // Every pin in the selected cycle (all stations), so we can warn when
  // adding someone who is already pinned somewhere else this month.
  List<SpecialAssignment> _allPins = [];

  // Where each employee is already rostered during the selected month,
  // from the saved schedules. Empty when the lookup fails — the picker
  // just falls back to showing no duty chips rather than blocking.
  Map<String, List<DutyPost>> _dutyByEmployee = {};

  // Working copy of THIS station's pins — what Save sends.
  List<SpecialAssignment> _pinned = [];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _dirty = false;
  String? _error;

  // How far ahead the month picker lets an admin pin. A year of runway
  // is far more than anyone plans for and keeps the list scannable.
  static const int _monthsAhead = 12;

  @override
  void initState() {
    super.initState();
    // The current month onwards. Months already gone are simply not on
    // the list — a pin only ever affects schedules generated after it is
    // saved, so pinning someone into a month that has already passed
    // could never change a roster.
    final now = DateTime.now();
    _cycleOptions = List.generate(
      _monthsAhead,
      (i) => cycleIdFor(DateTime(now.year, now.month + i, 1)),
    );
    _cycleId = _cycleOptions.first;
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.fetchEmployees(),
      ApiService.fetchSpecialAssignments(_cycleId),
      ApiService.fetchDutyStatus(_cycleId),
    ]);

    if (!mounted) return;

    final employeeResult = results[0];
    final pinResult = results[1];
    final dutyResult = results[2];

    if (employeeResult['success'] != true || pinResult['success'] != true) {
      setState(() {
        _error = (employeeResult['success'] != true
                ? employeeResult['error']
                : pinResult['error'])
            .toString();
        _isLoading = false;
      });
      return;
    }

    final pins = pinResult['specialAssignments'] as List<SpecialAssignment>;
    setState(() {
      _employees = (employeeResult['employees'] as List<Employee>)
          .where((e) => e.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _allPins = pins;
      // Duty chips are decoration on top of the picker, so a failed
      // lookup costs the warnings, not the dialog.
      _dutyByEmployee = dutyResult['success'] == true
          ? dutyResult['dutyStatus'] as Map<String, List<DutyPost>>
          : {};
      _pinned = pins
          .where((p) => p.stationId == widget.station.id)
          .toList()
        ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
      _dirty = false;
      _isLoading = false;
    });
  }

  Future<void> _switchCycle(String cycleId) async {
    if (cycleId == _cycleId) return;

    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: Text(
            'You have unsaved changes for ${cycleLabel(_cycleId)}. '
            'Switching months will discard them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }

    setState(() => _cycleId = cycleId);
    await _load();
  }

  // The pin this employee already holds at ANOTHER station this cycle,
  // if any — saving would move them here, which deserves a warning.
  SpecialAssignment? _pinElsewhere(String employeeId) {
    for (final p in _allPins) {
      if (p.employeeId == employeeId && p.stationId != widget.station.id) {
        return p;
      }
    }
    return null;
  }

  void _addEmployee(Employee employee) {
    final options = _shiftOptionsFor(employee.type);
    // Their usual shift when it fits their type, else the first option.
    final shift = options.contains(employee.assignedShift)
        ? employee.assignedShift
        : (options.isEmpty ? null : options.first);

    setState(() {
      _pinned = [
        ..._pinned,
        SpecialAssignment(
          id: '${_cycleId}_${employee.id}',
          rotationCycleId: _cycleId,
          employeeId: employee.id,
          employeeName: employee.name,
          employeeType: employee.type,
          stationId: widget.station.id,
          stationName: widget.station.name,
          shift: shift,
          homeStation: employee.assignedStation,
        ),
      ]..sort((a, b) => a.employeeName.compareTo(b.employeeName));
      _dirty = true;
    });
  }

  void _removePin(SpecialAssignment pin) {
    setState(() {
      _pinned = _pinned.where((p) => p.employeeId != pin.employeeId).toList();
      _dirty = true;
    });
  }

  void _changeShift(SpecialAssignment pin, String shift) {
    setState(() {
      _pinned = _pinned
          .map((p) => p.employeeId == pin.employeeId
              ? SpecialAssignment(
                  id: p.id,
                  rotationCycleId: p.rotationCycleId,
                  employeeId: p.employeeId,
                  employeeName: p.employeeName,
                  employeeType: p.employeeType,
                  stationId: p.stationId,
                  stationName: p.stationName,
                  shift: shift,
                  homeStation: p.homeStation,
                )
              : p)
          .toList();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final result = await ApiService.saveSpecialAssignments(
      stationId: widget.station.id,
      cycleId: _cycleId,
      assignments: _pinned,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      final notes = result['notes'] as List<String>;
      Navigator.pop(context, {
        'cycleId': _cycleId,
        'specialAssignments': result['specialAssignments'],
        'notes': notes,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'].toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Employee> get _availableEmployees {
    final pinnedIds = _pinned.map((p) => p.employeeId).toSet();
    return _employees.where((e) {
      if (pinnedIds.contains(e.id)) return false;
      if (_typeFilter != null && e.type != _typeFilter) return false;
      if (_searchQuery.isEmpty) return true;
      return e.name.toLowerCase().contains(_searchQuery) ||
          e.id.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // Pinned-per-shift vs the station's required headcount, e.g. Morning
  // 2/8 — a quick read on whether the admin is over-pinning one shift.
  int _pinnedOn(String shift) =>
      _pinned.where((p) => p.shift == shift).length;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 920,
        height: 640,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildCycleSelector(),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
            const SizedBox(height: 16),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.push_pin, color: _primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Special Assignments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                'Pin employees to ${widget.station.name} for a whole month',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // Which month these pins apply to. Only the current month and the ones
  // after it are offered — see initState.
  Widget _buildCycleSelector() {
    return Row(
      children: [
        Text(
          'Month:',
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _primary.withOpacity(0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _cycleId,
              isDense: true,
              borderRadius: BorderRadius.circular(8),
              icon: const Icon(Icons.expand_more, color: _primary, size: 20),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) _switchCycle(value);
                    },
              items: _cycleOptions.map((cycle) {
                final isCurrent = cycle == _cycleOptions.first;
                return DropdownMenuItem(
                  value: cycle,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cycleLabel(cycle),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Text(
                          'current',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // The exact window the pins below cover, so "one cycle" is never
        // something the admin has to work out from the month name.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.date_range, size: 14, color: _primary),
              const SizedBox(width: 6),
              Text(
                '${cycleRangeLabel(_cycleId)} · '
                '${cycleStatusLabel(_cycleId)}',
                style: const TextStyle(
                  color: _primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Icon(Icons.info_outline, size: 15, color: Colors.grey[500]),
        const SizedBox(width: 6),
        // Takes whatever width is left rather than sitting behind a
        // Spacer, so the sentence wraps at most once on a narrow window.
        Expanded(
          child: Text(
            'Applies to every schedule generated for this month, then '
            'expires. Past months can\'t be pinned.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildEmployeePicker()),
        const SizedBox(width: 20),
        Expanded(child: _buildPinnedPane()),
      ],
    );
  }

  // ---- Left pane: searchable employee list -------------------------------

  Widget _buildEmployeePicker() {
    final available = _availableEmployees;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or ID...',
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
              prefixIcon:
                  Icon(Icons.search, color: Colors.grey[500], size: 20),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              _typeChip(null, 'All'),
              _typeChip(EmployeeType.regular, 'Regular'),
              _typeChip(EmployeeType.reliever, 'Reliever'),
              _typeChip(EmployeeType.headGuard, 'Head Guard'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${available.length} employee${available.length != 1 ? 's' : ''}',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: available.isEmpty
                ? Center(
                    child: Text(
                      'No employees match.',
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: available.length,
                    itemBuilder: (context, index) =>
                        _buildEmployeeTile(available[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(EmployeeType? type, String label) {
    final selected = _typeFilter == type;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _typeFilter = type),
      visualDensity: VisualDensity.compact,
      selectedColor: _primary.withOpacity(0.12),
      labelStyle: TextStyle(
        color: selected ? _primary : Colors.grey[600],
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  // Where this employee is already rostered this month, other stations
  // first — that's the half worth warning about.
  List<DutyPost> _dutyPosts(String employeeId) {
    final posts = List<DutyPost>.from(_dutyByEmployee[employeeId] ?? const []);
    posts.sort((a, b) {
      final aHere = a.stationId == widget.station.id ? 1 : 0;
      final bHere = b.stationId == widget.station.id ? 1 : 0;
      return aHere != bHere
          ? aHere.compareTo(bHere)
          : a.startDate.compareTo(b.startDate);
    });
    return posts;
  }

  // The duty line under a name: on duty somewhere else this month, on
  // this station's own roster already, or on nobody's schedule yet.
  // Explicit in all three cases — an empty row reads as "no data", not
  // as "this guard is free".
  Widget _buildDutyChip(String employeeId) {
    final posts = _dutyPosts(employeeId);

    if (posts.isEmpty) {
      return _dutyPill(
        icon: Icons.event_available,
        color: _dutyFree,
        text: 'Not on any schedule this month',
        faint: true,
      );
    }

    final elsewhere =
        posts.where((p) => p.stationId != widget.station.id).toList();

    if (elsewhere.isEmpty) {
      final here = posts.first;
      return _dutyPill(
        icon: Icons.check_circle_outline,
        color: _primary,
        text: 'Already on this station · ${here.periodLabel}',
      );
    }

    final first = elsewhere.first;
    final more = elsewhere.length - 1;
    return _dutyPill(
      icon: Icons.warning_amber_rounded,
      color: _dutyElsewhere,
      text: 'On duty · ${first.stationName} · ${first.periodLabel}'
          '${first.isPublished ? ' (published)' : ''}'
          '${more > 0 ? ' +$more more' : ''}',
      tooltip: 'Rostered at ${elsewhere.map((p) => p.stationName).join(', ')} '
          'for these dates. Pinning them here means that schedule has to '
          'be regenerated before this one can be.',
    );
  }

  Widget _dutyPill({
    required IconData icon,
    required Color color,
    required String text,
    bool faint = false,
    String? tooltip,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(faint ? 0.05 : 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: faint ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }

  // "PAS512 · Regular · Balintawak", or "· Unassigned" when they have no
  // permanent station at all — previously that just rendered as nothing,
  // which was indistinguishable from a station whose name didn't load.
  Widget _buildEmployeeIdentity(Employee employee) {
    final home = (employee.assignedStation ?? '').trim();
    return Row(
      children: [
        Flexible(
          child: Text(
            '${employee.id} · ${employeeTypeToRoleString(employee.type)} · ',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
        ),
        Text(
          home.isEmpty ? 'Unassigned' : home,
          style: TextStyle(
            color: home.isEmpty ? _dutyElsewhere : Colors.grey[600],
            fontSize: 11,
            fontWeight: home.isEmpty ? FontWeight.w700 : FontWeight.w400,
            fontStyle: home.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeTile(Employee employee) {
    final elsewhere = _pinElsewhere(employee.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        // Not dense any more, and three-line: the subtitle now carries an
        // identity line AND a duty chip, which a dense two-line tile
        // clips.
        isThreeLine: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _primary.withOpacity(0.1),
          child: Text(
            employee.initials,
            style: const TextStyle(
              color: _primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          employee.name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEmployeeIdentity(employee),
            const SizedBox(height: 4),
            _buildDutyChip(employee.id),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (elsewhere != null)
              Tooltip(
                message: 'Already pinned to ${elsewhere.stationName} '
                    'this cycle',
                child: Icon(Icons.push_pin,
                    size: 16, color: Colors.amber[700]),
              ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: _primary, size: 20),
              tooltip: 'Pin to ${widget.station.name}',
              onPressed: () => _addEmployee(employee),
            ),
          ],
        ),
        onTap: () => _addEmployee(employee),
      ),
    );
  }

  // ---- Right pane: this station's pins ------------------------------------

  Widget _buildPinnedPane() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primary.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.push_pin, size: 16, color: _primary),
              const SizedBox(width: 6),
              Text(
                'Pinned to ${widget.station.name} (${_pinned.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          if (widget.station.hasShiftBreakdown) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                _capacityChip('Morning',
                    _pinnedOn('morning'), widget.station.requiredMorning),
                _capacityChip('Afternoon',
                    _pinnedOn('afternoon'), widget.station.requiredAfternoon),
                _capacityChip('Night',
                    _pinnedOn('night'), widget.station.requiredNight),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: _pinned.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.push_pin_outlined,
                            size: 36, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text(
                          'No one pinned yet',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pick employees on the left to guarantee them\n'
                          'a post here in the next generated schedule.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _pinned.length,
                    itemBuilder: (context, index) =>
                        _buildPinTile(_pinned[index]),
                  ),
          ),
        ],
      ),
    );
  }

  // Over-pinning a shift (more pins than posts) flips the chip red.
  Widget _capacityChip(String label, int pinned, int required) {
    final over = required > 0 && pinned > required;
    final color = over ? Colors.red : (pinned > 0 ? _primary : Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label $pinned/$required',
        style: TextStyle(
          color: over ? Colors.red : (pinned > 0 ? _primary : Colors.grey[600]),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPinTile(SpecialAssignment pin) {
    final elsewhere = _pinElsewhere(pin.employeeId);
    final options = _shiftOptionsFor(pin.employeeType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pin.employeeName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '${pin.employeeId} · '
                      '${employeeTypeToRoleString(pin.employeeType)}'
                      '${(pin.homeStation ?? '').trim().isEmpty
                          ? ' · Unassigned'
                          : ' · ${pin.homeStation}'}',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (options.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Floats · AM/PM',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                )
              else
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: pin.shift,
                    isDense: true,
                    borderRadius: BorderRadius.circular(8),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                    ),
                    items: options
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(_shiftLabels[s] ?? s),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _changeShift(pin, value);
                    },
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    color: Colors.red[400], size: 20),
                tooltip: 'Remove pin',
                onPressed: () => _removePin(pin),
              ),
            ],
          ),
          if (elsewhere != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.amber[800]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Currently pinned to ${elsewhere.stationName} — '
                      'saving moves them here.',
                      style: TextStyle(
                          color: Colors.amber[900], fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          // The consequence of this pin, spelled out where the admin is
          // deciding it: that station's saved roster still has them, and
          // generation refuses to write two rosters that disagree.
          ..._buildPinDutyWarning(pin),
        ],
      ),
    );
  }

  // Stations whose saved schedule still rosters this guard for the month
  // — each one has to be regenerated once the pin is saved.
  List<Widget> _buildPinDutyWarning(SpecialAssignment pin) {
    final clashes = _dutyPosts(pin.employeeId)
        .where((p) => p.stationId != widget.station.id)
        .toList();
    if (clashes.isEmpty) return const [];

    final published = clashes.where((p) => p.isPublished).toList();
    final where = clashes
        .map((p) => '${p.stationName} (${p.periodLabel})')
        .join(', ');

    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_busy, size: 14, color: _dutyElsewhere),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'On duty at $where. Regenerate '
                '${clashes.length > 1 ? 'those stations' : 'that station'} '
                'after saving, or the schedule will keep them in two '
                'places.'
                '${published.isNotEmpty
                    ? ' Already published — re-publish after regenerating.'
                    : ''}',
                style: const TextStyle(
                    color: _dutyElsewhere, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildFooter() {
    return Row(
      children: [
        if (_dirty)
          Text(
            'Unsaved changes',
            style: TextStyle(
              color: Colors.amber[800],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        const Spacer(),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _isSaving || _isLoading || !_dirty ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.push_pin, size: 16),
          label: Text(_isSaving ? 'Saving...' : 'Save Assignments'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
