// screens/auto_scheduler_content.dart
import 'package:flutter/material.dart';
import '../data/dummy_data.dart';
import '../models/employee.dart';
import '../models/post_time.dart';
import '../models/schedule.dart';
import '../models/schedule_note.dart';
import '../models/station.dart';
import '../services/api_service.dart';
import '../utils/station_grouping.dart';
import '../widgets/station_icon.dart';
import 'main_layout.dart';

class AutoSchedulerContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data})? onNavigate; // Make nullable with ?

  const AutoSchedulerContent({
    super.key,
    this.onNavigate, // Remove required
  });

  @override
  State<AutoSchedulerContent> createState() => _AutoSchedulerContentState();
}

class _AutoSchedulerContentState extends State<AutoSchedulerContent> {
  // Bi-weekly period: always 15 days inclusive.
  static const int _periodLengthDays = 15;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startDate = _dateOnly(DateTime.now());
  DateTime _endDate = _dateOnly(DateTime.now())
      .add(const Duration(days: _periodLengthDays - 1));
  bool _isGenerating = false;
  bool _showPreview = false;

  int get _periodDays => _endDate.difference(_startDate).inDays + 1;
  bool get _isPeriodValid => _periodDays == _periodLengthDays;

  // Generation scope. By group is the everyday run (all of a group's
  // stations at once); by station regenerates a single station — for when
  // one station's roster needs redoing without disturbing its siblings.
  bool _byStation = false;

  // Group selector (top stat row)
  String _selectedGroup = 'Group 1';
  bool _isGroupHovered = false;
  static final List<String> _groupOptions = StationGrouping.groupNames;

  // The station targeted in by-station mode. Null until the admin picks
  // one, which is what blocks generation in that mode.
  Station? _selectedStation;
  bool _isStationHovered = false;

  // Real stations loaded from the backend, divided into groups by
  // StationGrouping (Group 1: 1-8, Group 2: 9-17, Group 3: 18-25).
  List<Station> _allStations = [];
  bool _isLoadingStations = true;
  String? _stationLoadError;

  // Real employees loaded from the backend (seeded via
  // backend_python/seed_employees.py). The full list is kept so the
  // Personnel Pool can be filtered per selected group.
  List<Employee> _employees = [];
  int _totalEmployees = 0;
  int _regularCount = 0;
  int _relieverCount = 0;
  int _headGuardCount = 0;
  bool _isLoadingEmployees = true;

  // Scheduling rules. Sent to the backend generator, which applies the
  // monthly station rotation (rotation.py) when this is on.
  bool _rotationSchedule = true;

  // Everything the generator had to bend on the last run, grouped by
  // what it's about. Generation never refuses over a staffing problem —
  // it builds the best roster the setup allows and reports the holes
  // here, so this is the only warning that a schedule is about to be
  // published with a post nobody is manning.
  List<ScheduleNote> _notes = [];

  // Which note sections the admin has opened. Blockers and warnings open
  // themselves (see _buildNoteSection); this tracks the overrides.
  final Set<NoteCategory> _expandedNotes = {};

  // Schedules returned by the backend generator (already saved there
  // as unpublished).
  List<Schedule> _generatedSchedules = [];

  List<Station> get _groupStations =>
      StationGrouping.stationsForGroup(_allStations, _selectedGroup);

  // Every station, in the id order the group split is based on, so the
  // by-station picker offers them in the same sequence as the group card.
  List<Station> get _sortedStations =>
      [..._allStations]..sort((a, b) => a.id.compareTo(b.id));

  // Which group a station falls in — the pool the backend will use for
  // it, since a single-station run is still computed group-wide.
  String? _groupNameOf(Station station) {
    for (final name in _groupOptions) {
      if (StationGrouping.stationsForGroup(_allStations, name)
          .any((s) => s.id == station.id)) {
        return name;
      }
    }
    return null;
  }

  // By-station mode can't generate until a station is chosen.
  bool get _isTargetChosen => !_byStation || _selectedStation != null;

  // Personnel filtered to the selected group: guards who prefer (or are
  // assigned to) one of its stations, plus the adjacent-group reserve
  // that the exception rule allows the generator to borrow from.
  GroupPersonnelPool get _personnelPool =>
      StationGrouping.personnelPool(_allStations, _employees, _selectedGroup);

  String get _adjacentGroupsLabel {
    final number = _groupOptions.indexOf(_selectedGroup) + 1;
    final neighbors = StationGrouping.adjacentGroups[number] ?? const <int>[];
    return neighbors.map((g) => 'Group $g').join(' & ');
  }

  @override
  void initState() {
    super.initState();
    _loadStations();
    _loadEmployees();
  }

  // Loads the real stations from the backend so the group split matches
  // the database. Falls back to DummyData.stations if the server is down,
  // so the screen stays usable during development.
  Future<void> _loadStations() async {
    final result = await ApiService.fetchStations();
    if (!mounted) return;

    setState(() {
      _isLoadingStations = false;
      if (result['success'] == true) {
        _allStations = result['stations'] as List<Station>;
        _stationLoadError = null;
      } else {
        _allStations = DummyData.stations;
        _stationLoadError =
            'Could not reach the server — showing sample stations.';
      }
    });
  }

  // Loads the real employees from the backend so the Total Employees
  // stat reflects the database (seeded by backend_python/seed_employees.py).
  // Falls back to the dummy count if the server is down.
  Future<void> _loadEmployees() async {
    final result = await ApiService.fetchEmployees();
    if (!mounted) return;

    final employees = result['success'] == true
        ? (result['employees'] as List).cast<Employee>()
        : DummyData.employees;

    setState(() {
      _isLoadingEmployees = false;
      _employees = employees;
      _totalEmployees = employees.length;
      _regularCount =
          employees.where((e) => e.type == EmployeeType.regular).length;
      _relieverCount =
          employees.where((e) => e.type == EmployeeType.reliever).length;
      _headGuardCount =
          employees.where((e) => e.type == EmployeeType.headGuard).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header
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
                  onPressed: () => widget.onNavigate?.call(ScreenType.dashboard),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate Schedule',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Generate optimal schedules automatically',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Generation scope — whole group, or one station.
                  _buildScopeToggle(),
                  const SizedBox(height: 16),

                  // Top Row: target selector + Employee count + Station count
                  Row(
                    children: [
                      if (_byStation)
                        _buildStationCard()
                      else
                        _buildGroupCard(),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        _isLoadingEmployees
                            ? 'Total Employees'
                            : '$_regularCount regular · $_relieverCount '
                                'reliever · $_headGuardCount head guard',
                        _isLoadingEmployees ? '...' : '$_totalEmployees',
                        Icons.people,
                        const Color(0xFF059669),
                      ),
                      const SizedBox(width: 16),
                      // In by-station mode this reports what the target
                      // station needs rather than the group's headcount.
                      if (_byStation)
                        _buildStatCard(
                          _selectedStation == null
                              ? 'Guards Required (pick a station)'
                              : 'Guards Required at '
                                  '${_selectedStation!.name.trim()}',
                          _selectedStation == null
                              ? '—'
                              : '${_selectedStation!.requiredEmployees}',
                          Icons.groups,
                          const Color(0xFFD97706),
                        )
                      else
                        _buildStatCard(
                          '$_selectedGroup Stations (of ${_allStations.length} total)',
                          _isLoadingStations ? '...' : '${_groupStations.length}',
                          Icons.location_on,
                          const Color(0xFFD97706),
                        ),
                    ],
                  ),

                  if (_stationLoadError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD97706)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              size: 18, color: Color(0xFFD97706)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _stationLoadError!,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Stations covered by the selected group
                  _buildGroupStationsCard(),

                  const SizedBox(height: 24),

                  // Main Configuration Panel
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Date Range & Rules
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            // Date Range Card
                            _buildCard(
                              title: 'Schedule Period',
                              icon: Icons.date_range,
                              child: Column(
                                children: [
                                  _buildDateField(
                                    label: 'Start Date',
                                    date: _startDate,
                                    onTap: () => _selectDate(true),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildDateField(
                                    label: 'End Date',
                                    date: _endDate,
                                    onTap: () => _selectDate(false),
                                  ),
                                  // Bi-weekly rule: the period must be
                                  // exactly 15 days, or generation is blocked.
                                  if (!_isPeriodValid) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFFD97706)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.warning_amber,
                                                  size: 16,
                                                  color: Color(0xFFD97706)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'A bi-weekly schedule must be '
                                                  'exactly $_periodLengthDays days — '
                                                  'this period is $_periodDays '
                                                  'day${_periodDays == 1 ? '' : 's'}.',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF92400E),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: () => setState(() {
                                                _endDate = _startDate.add(
                                                    const Duration(
                                                        days:
                                                            _periodLengthDays -
                                                                1));
                                              }),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    const Color(0xFF92400E),
                                                padding: const EdgeInsets
                                                    .symmetric(horizontal: 8),
                                              ),
                                              child: const Text(
                                                'Fix end date',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // The duty windows this run will actually
                            // stamp on the roster, read from the target
                            // station's own post setup — staggered
                            // in-between starts included.
                            _buildShiftReferenceCard(),

                            const SizedBox(height: 16),

                            // Scheduling Preference Card
                            _buildCard(
                              title: 'Scheduling Preference',
                              icon: Icons.sync_alt,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Rotation Schedule',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Switch(
                                        value: _rotationSchedule,
                                        onChanged: (val) => setState(
                                            () => _rotationSchedule = val),
                                        activeThumbColor:
                                            const Color(0xFF1034A6),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _rotationSchedule
                                        ? 'Guards are reassigned to different '
                                            'stations each month, except for '
                                            'at least 2 per station who stay '
                                            'on for familiarization. The same '
                                            'placement is reused for both '
                                            'periods in a month.'
                                        : 'Every guard is scheduled at their '
                                            'permanent assigned station.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 24),

                      // Right: Actions & Preview
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            // Generate panel
                            _buildGeneratePanel(),

                            const SizedBox(height: 16),

                            // Preview Panel (shown after generation) - rectangle station boxes
                            if (_showPreview)
                              _buildCard(
                                title: 'Generated Preview',
                                icon: Icons.preview,
                                action: TextButton.icon(
                                  // Schedules are already saved as
                                  // unpublished; review & publish there.
                                  onPressed: () => widget.onNavigate
                                      ?.call(ScreenType.scheduleManagement),
                                  icon: const Icon(Icons.save, size: 18),
                                  label: const Text('Review & Publish'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF1034A6),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Anything the generator had to bend
                                    // to produce these rosters, grouped
                                    // by where the fix lives.
                                    if (_notes.isNotEmpty) ...[
                                      _buildNotesPanel(),
                                      const SizedBox(height: 16),
                                    ],
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: _generatedSchedules
                                          .map(_buildStationPreviewCard)
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Generate panel
  // ---------------------------------------------------------------------

  // Formal summary-then-action panel: the admin confirms what is about to
  // be generated (group, period, coverage) before committing.
  Widget _buildGeneratePanel() {
    const navy = Color(0xFF1034A6);
    final group = StationGrouping.byName(_selectedGroup);
    final pool = _personnelPool;
    final isPoolLoading = _isLoadingEmployees || _isLoadingStations;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header band
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: navy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate Schedule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Review the details below before generating.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow('Scope',
                    _byStation ? 'Single station' : 'Whole group'),
                if (_byStation)
                  _buildSummaryRow(
                    'Target Station',
                    _selectedStation?.name.trim() ?? 'Not selected yet',
                  ),
                _buildSummaryRow('Station Group',
                    '$_selectedGroup — ${group.rangeLabel}'),
                _buildSummaryRow(
                  'Schedule Period',
                  '${_formatDate(_startDate)} to ${_formatDate(_endDate)}',
                ),
                _buildSummaryRow('Duration',
                    '$_periodDays days (bi-weekly)'),
                _buildSummaryRow(
                  'Schedules Saved',
                  _isLoadingStations
                      ? 'Loading…'
                      : _byStation
                          ? '1 station — the other '
                              '${_groupStations.length - 1} in $_selectedGroup '
                              'are computed but left untouched'
                          : '${_groupStations.length} station'
                              '${_groupStations.length == 1 ? '' : 's'}',
                ),
                // Only the guards who prefer this group's stations —
                // not the whole workforce (mirrors the generator's own
                // filtering in station_pools.py).
                _buildSummaryRow(
                  'Personnel Pool',
                  isPoolLoading
                      ? 'Loading…'
                      : '${pool.direct.length} of $_totalEmployees — '
                          '${pool.countOfType(EmployeeType.regular)} regular · '
                          '${pool.countOfType(EmployeeType.reliever)} reliever · '
                          '${pool.countOfType(EmployeeType.headGuard)} head guard',
                ),
                _buildSummaryRow(
                  'Adjacent Reserve',
                  isPoolLoading
                      ? 'Loading…'
                      : '+${pool.adjacent.length} from $_adjacentGroupsLabel — '
                          'borrowable when this group\'s own cover runs out',
                ),
                _buildSummaryRow(
                  'Station Rotation',
                  _rotationSchedule
                      ? 'On — monthly, 2 guards stay per station'
                      : 'Off — permanent station assignments',
                  isLast: true,
                ),

                const SizedBox(height: 20),

                // Method note — this is a rules-based generator, not an
                // AI/optimiser, so the copy says exactly what runs.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Assignments follow the fixed scheduling rules: '
                          '13 days on / 2 days off with staggered day-offs, '
                          'reliever cover for morning and afternoon posts, '
                          'a dedicated night reliever per station (night '
                          'shifts only for the whole period), and floating '
                          'substitutes for head-guard day-offs. Posts come '
                          'from each station\'s own per-shift setup (Station '
                          'Management → Edit Station), handed out in order; '
                          'guards beyond the posts set up there start as '
                          'Undefined and must be assigned before the '
                          'schedule can be published.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isGenerating || !_isPeriodValid || !_isTargetChosen)
                            ? null
                            : () => _generateSchedule(),
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow, size: 20),
                    label: Text(
                      _isGenerating
                          ? 'Generating…'
                          : !_isPeriodValid
                              ? 'Fix Schedule Period First'
                              : !_isTargetChosen
                                  ? 'Select a Station First'
                                  : _byStation
                                      ? 'Generate for '
                                          '${_selectedStation!.name.trim()}'
                                      : 'Generate Schedule',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'The schedule is saved as unpublished for review.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Generator notes
  // ---------------------------------------------------------------------
  //
  // What this box is, and why it can't just be deleted: generation never
  // refuses over a staffing problem. It builds the best roster the setup
  // allows and files a note about everything it had to bend — a post with
  // nobody on it, a station with no head guard, a day off no reliever was
  // free for. Publishing goes ahead regardless, holes and all, so this is
  // the only place those holes are ever announced.
  //
  // The old version showed every note, in one flat list, under a "Station
  // Rotation" heading — including notes that had nothing to do with
  // rotation. Now: a headline saying how many things actually need doing,
  // then one collapsible section per category, worst first. Sections that
  // need action open themselves; purely informational ones stay shut.

  Widget _buildNotesPanel() {
    final sections = groupNotes(_notes);
    final actionable = actionableCount(_notes);
    final worst = sections.first.severity;

    // Nothing to act on is genuinely good news, and reads as such rather
    // than as a wall of amber.
    final clean = actionable == 0;
    final accent =
        clean ? const Color(0xFF059669) : worst.color;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: clean
                  ? const Color(0xFFECFDF5)
                  : worst.background,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(9)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(clean ? Icons.check_circle_outline : worst.icon,
                    size: 18, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clean
                            ? 'Generated with nothing to fix'
                            : actionable == 1
                                ? '1 thing needs your attention'
                                : '$actionable things need your attention',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        clean
                            ? 'Every post is manned and every day off is '
                                'covered. The notes below are just a record '
                                'of what the generator decided.'
                            : 'The schedules were still generated and saved. '
                                'These are the places the roster doesn\'t '
                                'match the set-up — fix them and generate '
                                'again, or publish as-is knowing about them.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final section in sections) _buildNoteSection(section),
        ],
      ),
    );
  }

  Widget _buildNoteSection(NoteSection section) {
    // A section with something to act on is open on arrival; one that is
    // purely informational starts shut, because it's the reason the old
    // box read as a wall of text.
    final defaultOpen = section.severity != NoteSeverity.info;
    final isOpen = _expandedNotes.contains(section.category)
        ? !defaultOpen
        : defaultOpen;
    final accent = section.severity.color;
    final actionable = section.notes
        .where((n) => n.severity != NoteSeverity.info)
        .length;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              // The set holds the OVERRIDES, so toggling is add-or-remove
              // whichever way the section started.
              if (!_expandedNotes.remove(section.category)) {
                _expandedNotes.add(section.category);
              }
            }),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(section.category.icon, size: 17, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                section.category.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                actionable > 0
                                    ? '$actionable to fix'
                                    : '${section.notes.length} note'
                                        '${section.notes.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          section.category.blurb,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  for (final note in section.notes) _buildNoteTile(note),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // One note: who or what it's about, what happened, and what to do —
  // on three lines rather than in one paragraph.
  Widget _buildNoteTile(ScheduleNote note) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: note.severity.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: note.severity.color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(note.severity.icon, size: 14, color: note.severity.color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  note.subject.isEmpty ? 'This run' : note.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              // Only said out loud when it changes what the admin does;
              // labelling every note "for information" is noise.
              if (note.severity == NoteSeverity.blocker)
                Text(
                  note.severity.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                    color: note.severity.color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            note.problem,
            style: const TextStyle(
                fontSize: 12, height: 1.45, color: Color(0xFF334155)),
          ),
          if (note.fix.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.fix,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFF1F5F9)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

  // ---------------------------------------------------------------------
  // Top row cards
  // ---------------------------------------------------------------------

  // Whole group vs one station. Switching scope invalidates any preview
  // on screen, the same way switching group does.
  Widget _buildScopeToggle() {
    Widget option(String label, String detail, IconData icon, bool byStation) {
      final selected = _byStation == byStation;
      return Expanded(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: selected
                ? null
                : () => setState(() {
                      _byStation = byStation;
                      _showPreview = false;
                      _generatedSchedules = [];
                      _notes = [];
                    }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1034A6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 18,
                      color: selected ? Colors.white : Colors.grey[600]),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                selected ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          option('By Group', 'Every station in one group',
              Icons.groups, false),
          option('By Station', 'Redo a single station\'s roster',
              Icons.location_on, true),
        ],
      ),
    );
  }

  // Station picker for by-station mode. Selecting a station also switches
  // the group underneath it, because the backend still computes that
  // whole group to place this station's guards — so every group-derived
  // figure on this screen (personnel pool, adjacent reserve) stays true.
  Widget _buildStationCard() {
    final station = _selectedStation;
    final stations = _sortedStations;

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isStationHovered = true),
        onExit: (_) => setState(() => _isStationHovered = false),
        child: PopupMenuButton<Station>(
          offset: const Offset(0, 64),
          enabled: stations.isNotEmpty,
          constraints: const BoxConstraints(maxHeight: 420, minWidth: 280),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) => setState(() {
            _selectedStation = value;
            // Keep the group in step: it drives the personnel pool the
            // generator will actually use for this station.
            _selectedGroup = _groupNameOf(value) ?? _selectedGroup;
            _showPreview = false;
            _generatedSchedules = [];
            _notes = [];
          }),
          itemBuilder: (context) => [
            for (var i = 0; i < stations.length; i++)
              PopupMenuItem<Station>(
                value: stations[i],
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    Expanded(child: Text(stations[i].name.trim())),
                    const SizedBox(width: 8),
                    Text(
                      _groupNameOf(stations[i]) ?? '—',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
          ],
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isStationHovered
                    ? const Color(0xFF1034A6)
                    : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1034A6)
                      .withOpacity(_isStationHovered ? 0.18 : 0.1),
                  blurRadius: _isStationHovered ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1034A6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const StationIcon(size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station?.name.trim() ??
                            (_isLoadingStations
                                ? 'Loading…'
                                : 'Select Station'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: station == null
                              ? Colors.grey[500]
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        station == null
                            ? 'Choose the station to generate for'
                            : '$_selectedGroup · pool computed group-wide',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: _isStationHovered
                      ? const Color(0xFF1034A6)
                      : Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard() {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isGroupHovered = true),
        onExit: (_) => setState(() => _isGroupHovered = false),
        child: PopupMenuButton<String>(
          offset: const Offset(0, 64),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) => setState(() {
            _selectedGroup = value;
            // A preview generated for another group no longer applies.
            _showPreview = false;
            _generatedSchedules = [];
            _notes = [];
          }),
          itemBuilder: (context) => _groupOptions
              .map((g) => PopupMenuItem<String>(
                    value: g,
                    child: Text('$g  (${StationGrouping.byName(g).rangeLabel})'),
                  ))
              .toList(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isGroupHovered ? const Color(0xFF1034A6) : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1034A6).withOpacity(_isGroupHovered ? 0.18 : 0.1),
                  blurRadius: _isGroupHovered ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1034A6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.groups, color: Color(0xFF1034A6)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedGroup,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        StationGrouping.byName(_selectedGroup).rangeLabel,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: _isGroupHovered ? const Color(0xFF1034A6) : Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            // Expanded so long labels ("N regular · N reliever · N head
            // guard") ellipsize inside the card instead of overflowing it.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
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

  // Lists the stations covered by the selected group, numbered by their
  // position in the full station list (matches the 1-8 / 9-17 / 18-25 plan).
  Widget _buildGroupStationsCard() {
    final group = StationGrouping.byName(_selectedGroup);

    Widget content;
    if (_isLoadingStations) {
      content = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_groupStations.isEmpty) {
      content = Text(
        'No stations found for this group yet.',
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      );
    } else {
      content = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _groupStations.asMap().entries.map<Widget>((entry) {
          final stationNumber = group.startNumber + entry.key;
          final station = entry.value;
          // In by-station mode the whole group is still shown — it's the
          // pool being computed — with the one station that will actually
          // be saved marked out from its siblings.
          final isTarget = _byStation && _selectedStation?.id == station.id;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isTarget
                  ? const Color(0xFF1034A6).withOpacity(0.08)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isTarget
                    ? const Color(0xFF1034A6)
                    : Colors.grey[300]!,
                width: isTarget ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1034A6).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$stationNumber',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1034A6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  station.name.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isTarget ? FontWeight.w700 : FontWeight.w500,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                if (isTarget) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'TARGET',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF1034A6),
                    ),
                  ),
                ],
                // Required posts per shift (Morning/Afternoon/Night).
                if (station.hasShiftBreakdown) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${station.requiredMorning}M · '
                    '${station.requiredAfternoon}A · '
                    '${station.requiredNight}N',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      );
    }

    return _buildCard(
      title: _byStation
          ? '$_selectedGroup — personnel pool'
          : '$_selectedGroup — ${group.rangeLabel}',
      icon: Icons.location_city,
      customIcon: const StationIcon(size: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Says out loud why a by-station run shows the whole group:
          // the group is what gets computed, one station is what gets saved.
          if (_byStation && _selectedStation != null) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Color(0xFF1034A6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The whole of $_selectedGroup is worked out so shared '
                      'relievers and floating head guards are never booked '
                      'at two stations on one day — but only '
                      '${_selectedStation!.name.trim()} is saved. Every '
                      'other station keeps the schedule it already has.',
                      style: const TextStyle(
                          fontSize: 12, height: 1.4, color: Color(0xFF1E3A8A)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          content,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Shared card / field widgets
  // ---------------------------------------------------------------------

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? action,
    Widget? customIcon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    customIcon ?? Icon(icon, color: const Color(0xFF1034A6), size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${date.month}/${date.day}/${date.year}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Shift Times — the windows this run will actually stamp on the roster
  // ---------------------------------------------------------------------
  //
  // Not a static reference list. Every window here is read from the same
  // place the generator reads it: the station's own per-shift post setup
  // (Edit Station), run through the stagger ladder in post_time.dart. So
  // the in-between shifts — the posts that start two hours up the ladder,
  // 0700H-1600H and 0900H-1800H — appear because the station really has
  // them, and change the moment its posts do.

  // Which station's windows the card shows. Null means the first station
  // of the selected group, which is the sensible default for a group run.
  Station? _shiftTimesStation;

  // The station the shift card is describing right now.
  Station? get _shiftReferenceStation {
    if (_byStation && _selectedStation != null) return _selectedStation;
    final chosen = _shiftTimesStation;
    // A station left over from another group isn't in this group's list
    // any more, so fall back rather than describe the wrong roster.
    if (chosen != null && _groupStations.any((s) => s.id == chosen.id)) {
      return chosen;
    }
    return _groupStations.isEmpty ? null : _groupStations.first;
  }

  static const Map<String, Color> _shiftColors = {
    'morning': Color(0xFFD97706),
    'afternoon': Color(0xFF1034A6),
    'night': Color(0xFF4C1D95),
  };

  static const Map<String, String> _shiftTitles = {
    'morning': 'Morning',
    'afternoon': 'Afternoon',
    'night': 'Night',
  };

  Widget _buildShiftReferenceCard() {
    final station = _shiftReferenceStation;

    return _buildCard(
      title: 'Shift Times',
      icon: Icons.schedule,
      // Once a by-station target is chosen it IS the subject of the whole
      // screen, so there's nothing left to pick. Before that — and on
      // every group run — the admin can look at any station's windows.
      action: ((_byStation && _selectedStation != null) ||
              _groupStations.length < 2)
          ? null
          : _buildShiftStationPicker(station),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingStations)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (station == null)
            Text(
              'No station in this group to read shift times from yet.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            )
          else ...[
            Text(
              'The windows ${station.name.trim()} will be rostered on. '
              'Every station in the group works the same base shifts; the '
              'staggered starts below depend on how many posts each one '
              'has.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            for (final shift in const ['morning', 'afternoon', 'night'])
              _buildShiftBlock(station, shift),
            const SizedBox(height: 2),
            Text(
              'Post times come from Station Management → Edit Station. '
              'Head guards work fixed 12-hour duties outside the ladder.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftStationPicker(Station? station) {
    return PopupMenuButton<Station>(
      tooltip: 'Show another station\'s shift times',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(maxHeight: 400, minWidth: 220),
      onSelected: (value) => setState(() => _shiftTimesStation = value),
      itemBuilder: (context) => [
        for (final s in _groupStations)
          PopupMenuItem<Station>(value: s, child: Text(s.name.trim())),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              station?.name.trim() ?? 'Select',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1034A6),
              ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down,
              size: 18, color: Color(0xFF1034A6)),
        ],
      ),
    );
  }

  // One shift: its base window, then a line per slot the station is set
  // up for, with the window that slot is actually manned for.
  //
  // Slots the admin hasn't named yet are shown too, because the generator
  // still rosters a guard on them — it extends the ladder over the
  // unnamed slots and stamps the window (station_posts.regular_windows),
  // so those guards do have a time to report at. They just come out as
  // "Undefined" and block publishing until the post is named.
  Widget _buildShiftBlock(Station station, String shift) {
    final color = _shiftColors[shift]!;
    final base = baseShiftWindow(_shiftTitles[shift]!);

    // Padded to the station's required number, which is what Edit
    // Station configures and what the generator hands posts out against.
    final named = station.postsFor(shift);
    final required = station.requiredFor(shift);
    final posts = [
      ...named,
      if (required > named.length)
        ...List.filled(required - named.length, ''),
    ];
    final times = normalizePostTimes(
        shift, posts, station.rawPostTimesFor(shift));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _shiftTitles[shift]!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              if (base != null)
                Text(
                  'base ${base.range} · ${base.duration}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
            ],
          ),
          if (posts.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Nothing set up for this shift yet — set its number and '
              'posts in Edit Station.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.grey[600]),
            ),
          ] else ...[
            const SizedBox(height: 8),
            for (var i = 0; i < posts.length; i++)
              _buildPostTimeRow(shift, posts[i], times[i]),
            if (station.unnamedPosts(shift) > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${station.unnamedPosts(shift)} slot'
                '${station.unnamedPosts(shift) == 1 ? '' : 's'} still '
                'unnamed — those guards generate on an Undefined post and '
                'must be assigned one before the schedule can be published.',
                style: const TextStyle(
                    fontSize: 11, height: 1.4, color: Color(0xFF92400E)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // Why a post's window isn't the one you'd guess from the shift name.
  Widget _buildPostTag(String label, Color color) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
            color: color,
          ),
        ),
      );

  Widget _buildPostTimeRow(String shift, String post, PostTime time) {
    final isHeadGuard = post == kHeadGuardPost;
    // A post that doesn't start on its shift's base window is worth
    // naming — a 0700H start on a "Morning" roster is the thing admins
    // don't expect to see. Two different reasons for it, and which one
    // matters: the ladder put it there (an in-between shift, the normal
    // stagger) or the admin pinned that window by hand in Edit Station.
    final base = kShiftWindows[shift];
    final offBase =
        !isHeadGuard && base != null && time.start != base.$1;
    final isStaggered = offBase && time.auto;
    final isPinned = !isHeadGuard && !time.auto;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              post.isEmpty ? 'Unnamed post' : post,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHeadGuard ? FontWeight.w600 : FontWeight.w400,
                fontStyle: post.isEmpty ? FontStyle.italic : FontStyle.normal,
                color: post.isEmpty
                    ? Colors.grey[500]
                    : const Color(0xFF1E293B),
              ),
            ),
          ),
          if (isStaggered) _buildPostTag('IN-BETWEEN', const Color(0xFF0369A1)),
          if (isPinned) _buildPostTag('CUSTOM', const Color(0xFF7C3AED)),
          Text(
            '${time.range} · ${time.duration}',
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: time.isLongDuty ? const Color(0xFF92400E)
                  : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Generated Preview (rectangle station boxes instead of a table)
  // ---------------------------------------------------------------------

  Widget _buildStationPreviewCard(Schedule schedule) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            widget.onNavigate?.call(ScreenType.scheduleManagement),
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1034A6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on, size: 18, color: Color(0xFF1034A6)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      schedule.stationName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${schedule.totalDays} days',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${schedule.totalEmployees} guards',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      widget.onNavigate?.call(ScreenType.scheduleManagement),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1034A6),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: _dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = _dateOnly(picked);
          // Keep the period bi-weekly by default; the admin can still
          // move the end date (and will see the warning if it's not 15).
          _endDate =
              _startDate.add(const Duration(days: _periodLengthDays - 1));
        } else {
          _endDate = _dateOnly(picked);
        }
      });
    }
  }

  // Calls the Python generator for the selected group. The backend
  // builds the full 15-day roster (regulars, relievers, head guards +
  // floating substitutes) and saves it as unpublished.
  //
  // In by-station mode it sends the station id too: the backend still
  // computes the whole group (the reliever and substitute pools are
  // shared across it) but saves only that one station.
  //
  // Double-generation guard: the backend rejects the request when the
  // group — or, for a single-station run, that station — already has a
  // schedule overlapping this period; the admin must explicitly confirm
  // before it's regenerated (overwritten).
  Future<void> _generateSchedule({bool overwrite = false}) async {
    setState(() {
      _isGenerating = true;
      _showPreview = false;
    });

    final groupNumber = _groupOptions.indexOf(_selectedGroup) + 1;
    final result = await ApiService.generateSchedules(
      group: groupNumber,
      startDate: _startDate,
      overwrite: overwrite,
      rotate: _rotationSchedule,
      stationId: _byStation ? _selectedStation?.id : null,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _generatedSchedules =
            (result['schedules'] as List).cast<Schedule>();
        _notes = (result['notes'] as List?)?.cast<ScheduleNote>() ?? [];
        // Which sections were open is about the previous run's problems,
        // not this one's.
        _expandedNotes.clear();
        _isGenerating = false;
        _showPreview = true;
      });
      return;
    }

    setState(() => _isGenerating = false);

    // A special assignment has moved a guard whose old station still
    // rosters them for these dates. Overwriting won't fix that — the
    // OTHER station is the one that needs regenerating — so this gets
    // its own dialog rather than the "Regenerate?" prompt.
    if (result['code'] == 'special_assignment_clash') {
      _showSpecialAssignmentClash(
        result['error']?.toString() ?? 'A special assignment conflicts.',
        List<Map<String, dynamic>>.from(result['stations'] ?? const []),
      );
      return;
    }

    if (result['conflict'] == true) {
      _confirmOverwrite(result['error'] ?? 'A schedule already exists.');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Schedule generation failed: ${result['error']}'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  // Generation refused because a pinned guard is still on another
  // station's saved schedule for these dates. There's no "do it anyway"
  // here on purpose: writing this schedule would put that guard on two
  // rosters at once, and the fix is to regenerate the station named
  // below (or run the whole group, which rewrites all of them).
  void _showSpecialAssignmentClash(
      String message, List<Map<String, dynamic>> stations) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFB45309).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_search,
                  color: Color(0xFFB45309), size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Guard is rostered somewhere else',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 380),
          child: SingleChildScrollView(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          // Always offered, and the only fix guaranteed to work: pins
          // pointing BOTH ways between two stations block each station's
          // own run, and a group run rewrites all of them at once.
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _switchToWholeGroup();
            },
            child: const Text('Switch to whole group'),
          ),
          // One tap to the narrower fix when a single station is in the
          // way — usually the case, and it leaves the rest untouched.
          if (stations.length == 1)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1034A6),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _selectStationForRegeneration(
                    stations.first['stationId']?.toString());
              },
              child: Text(
                'Regenerate ${stations.first['stationName'] ?? 'it'}',
              ),
            ),
        ],
      ),
    );
  }

  // Flips the generator back to whole-group mode. Stops short of
  // generating: a group run replaces every station's roster for the
  // period, which is the admin's call to make deliberately.
  void _switchToWholeGroup() {
    setState(() => _byStation = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Switched to $_selectedGroup. Generating rewrites every station '
          'in the group for this period, which clears the clash in one go.',
        ),
      ),
    );
  }

  // Points the generator at the station that has to be regenerated
  // first, so the admin doesn't have to hunt for it in the dropdown.
  void _selectStationForRegeneration(String? stationId) {
    if (stationId == null) return;
    final station =
        _allStations.where((s) => s.id == stationId).firstOrNull;
    if (station == null) return;

    setState(() {
      _byStation = true;
      _selectedStation = station;
      // Same pairing the picker itself does — the group card has to
      // follow the station, not the other way round.
      _selectedGroup = _groupNameOf(station) ?? _selectedGroup;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Switched to ${station.name.trim()}. Generate it to clear the '
          'clash, then generate the station you wanted.',
        ),
      ),
    );
  }

  void _confirmOverwrite(String message) {
    // A by-station run only ever replaces that station's own schedule —
    // spelled out, because "regenerate" on the group flow means something
    // much bigger and the two share this dialog.
    final scopeNote = _byStation && _selectedStation != null
        ? 'Regenerating will replace the existing '
            '${_selectedStation!.name.trim()} schedule for this period. '
            'No other station in $_selectedGroup is touched.'
        : 'Regenerating will replace the existing schedule for '
            'this group and period.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Schedule Already Generated'),
        content: Text('$message\n\n$scopeNote'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _generateSchedule(overwrite: true);
            },
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
  }
}