// screens/station_management_screen.dart (Now backed by the real API)
import 'package:flutter/material.dart';
import '../models/schedule.dart';
import '../models/special_assignment.dart';
import '../models/station.dart';
import '../services/api_service.dart';
import '../widgets/station_icon.dart';
import 'main_layout.dart';
import 'add_station_dialog.dart';
import 'special_assignment_dialog.dart';

class StationManagementContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const StationManagementContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<StationManagementContent> createState() => _StationManagementContentState();
}

class _StationManagementContentState extends State<StationManagementContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Station> _stations = [];
  List<Schedule> _schedules = [];

  // Admin pins for the current rotation cycle (this calendar month),
  // used to badge each card with how many guards are pinned to it.
  List<SpecialAssignment> _specialAssignments = [];

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Loads every station plus every schedule from Firestore via the
  // Python backend. Schedules are needed so each card can show how many
  // guards the published schedule actually assigns to that station.
  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.fetchStations(),
      ApiService.fetchSchedules(),
      ApiService.fetchSpecialAssignments(cycleIdFor(DateTime.now())),
    ]);

    if (!mounted) return;

    final stationResult = results[0];
    final scheduleResult = results[1];
    final pinResult = results[2];

    if (stationResult["success"] == true) {
      setState(() {
        _stations = stationResult["stations"] as List<Station>;
        // Schedules or pins failing to load shouldn't block the station
        // grid — the counts just fall back to 0 until the next refresh.
        _schedules = scheduleResult["success"] == true
            ? scheduleResult["schedules"] as List<Schedule>
            : [];
        _specialAssignments = pinResult["success"] == true
            ? pinResult["specialAssignments"] as List<SpecialAssignment>
            : [];
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = stationResult["error"].toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openEditStationDialog(Station station) async {
    final updated = await showDialog<Station>(
      context: context,
      builder: (context) => AddStationDialog(station: station),
    );

    if (updated != null) {
      setState(() {
        _stations = _stations
            .map((s) => s.id == updated.id ? updated : s)
            .toList();
      });
    }
  }

  // Guards pinned to this station for the current cycle (the badge on
  // the card). The dialog itself can also manage next month's pins.
  int _pinnedCount(Station station) =>
      _specialAssignments.where((p) => p.stationId == station.id).length;

  Future<void> _openSpecialAssignmentsDialog(Station station) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SpecialAssignmentDialog(station: station),
    );

    if (result == null || !mounted) return;

    // If the save touched the current cycle, refresh the badges. A save
    // for next month changes nothing visible on this screen yet.
    if (result['cycleId'] == cycleIdFor(DateTime.now())) {
      final pinResult =
          await ApiService.fetchSpecialAssignments(cycleIdFor(DateTime.now()));
      if (!mounted) return;
      if (pinResult['success'] == true) {
        setState(() {
          _specialAssignments =
              pinResult['specialAssignments'] as List<SpecialAssignment>;
        });
      }
    }

    final notes = (result['notes'] as List<String>? ?? []);
    final saved = result['specialAssignments'] as List? ?? [];
    final cycleId = result['cycleId'] as String? ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notes.isNotEmpty
              ? notes.join('\n')
              : '${saved.length} special assignment'
                  '${saved.length != 1 ? 's' : ''} saved for '
                  '"${station.name}" — ${cycleRangeLabel(cycleId)}. '
                  'They take a post here in every schedule generated for '
                  '${cycleLabel(cycleId)}.',
        ),
      ),
    );
  }

  // How many distinct guards the station's active published schedule puts
  // on duty today. Prefers the published schedule covering today; if none
  // does (e.g. it starts next week), falls back to the most recently
  // created published one and counts its first day instead.
  int _getEmployeeCount(Station station) {
    final published = _schedules
        .where((s) =>
            s.status == ScheduleStatus.published && s.stationId == station.id)
        .toList();
    if (published.isEmpty) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Schedule schedule = published.firstWhere(
      (s) => !today.isBefore(s.startDate) && !today.isAfter(s.endDate),
      orElse: () => published.reduce(
          (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b),
    );

    if (schedule.days.isEmpty) return 0;

    final day = schedule.days.firstWhere(
      (d) =>
          d.date.year == today.year &&
          d.date.month == today.month &&
          d.date.day == today.day,
      orElse: () => schedule.days.first,
    );

    return day.entries.map((e) => e.employeeId).toSet().length;
  }

  List<Station> get _filteredStations {
    if (_searchQuery.isEmpty) return _stations;

    return _stations.where((station) {
      return station.name.toLowerCase().contains(_searchQuery);
    }).toList();
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
                  onPressed: () => widget.onNavigate(ScreenType.dashboard),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Station Management',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Monitor and manage station assignments',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Search Bar
                Container(
                  width: 280,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search stations...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[500], size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search results count
          if (_searchQuery.isNotEmpty && !_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filteredStations.length} result${_filteredStations.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(),
            ),
          ),
        ],
      ),
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
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load stations',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredStations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _searchQuery.isEmpty
                ? const StationIcon(size: 48)
                : Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No stations yet' : 'No stations found',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.4,
      ),
      itemCount: _filteredStations.length,
      itemBuilder: (context, index) {
        final station = _filteredStations[index];
        final employeeCount = _getEmployeeCount(station);
        return _buildStationCard(station, employeeCount);
      },
    );
  }

  Widget _buildStationCard(Station station, int employeeCount) {
    final isFullyStaffed = employeeCount >= station.requiredEmployees;
    final pinnedCount = _pinnedCount(station);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          widget.onNavigate(ScreenType.stationDetail, data: station);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isFullyStaffed ? Colors.transparent : Colors.red.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const StationIcon(size: 46),
                    const Spacer(),
                    if (!isFullyStaffed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Attention Needed',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Fully Staffed',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Station options',
                      icon: Icon(Icons.more_vert,
                          color: Colors.grey[600], size: 20),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openEditStationDialog(station);
                        } else if (value == 'special') {
                          _openSpecialAssignmentsDialog(station);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Edit Station'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'special',
                          child: Row(
                            children: [
                              Icon(Icons.push_pin_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Special Assignments'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 6),
                              Text(
                                '$employeeCount / ${station.requiredEmployees} Employees',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Pin badge: how many guards are specially
                        // assigned here this month. Tapping it opens the
                        // dialog directly.
                        if (pinnedCount > 0) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message:
                                '$pinnedCount specially assigned this month '
                                '— click to manage',
                            child: InkWell(
                              onTap: () =>
                                  _openSpecialAssignmentsDialog(station),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1034A6)
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF1034A6)
                                        .withOpacity(0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.push_pin,
                                        size: 14, color: Color(0xFF1034A6)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$pinnedCount',
                                      style: const TextStyle(
                                        color: Color(0xFF1034A6),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}