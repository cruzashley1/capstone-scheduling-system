// screens/available_management_screen.dart
//
// Shown when the "Employees Available" box is tapped on the dashboard.
// Three tabs, driven by the stat cards themselves — tap a card to switch:
//   - Volunteer Employee: everyone who filed a cover offer for today from
//     the guard app ("I'm available to work"), whether they are on a day
//     off or not yet assigned to any station. Shows what they signed up
//     for (preferred shift / station).
//   - Day Off Today: in a schedule covering today but with no entry today,
//     grouped under the station of that schedule.
//   - Unassigned: not in any schedule covering today.
// Day off / unassigned use the same DutyService rules as the dashboard
// card so the numbers match.
import 'package:flutter/material.dart';
import '../models/cover_offer.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/duty_service.dart';
import 'main_layout.dart';

// Which stat card is currently acting as the selected tab.
enum _AvailabilityTab { volunteer, dayOff, unassigned }

// One person's row in a day-off / unassigned table.
class _AvailabilityRow {
  final String id;
  final String name;
  final String role; // 'Regular Employee' | 'Reliever Employee' | 'Head Guard'
  final String status; // 'Day Off' or 'Unassigned'

  const _AvailabilityRow({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
  });
}

// One volunteer's row: who they are, where they stand today, and the
// shift/station they said they'd take.
class _VolunteerRow {
  final String id;
  final String name;
  final String role;
  final String status; // current standing today: 'Day Off' | 'Unassigned' | …
  final String preferredShifts; // 'Any' when they didn't narrow it
  final String preferredStations; // 'Any' when they didn't narrow it

  const _VolunteerRow({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.preferredShifts,
    required this.preferredStations,
  });
}

// One station's block: name + the day-off people tied to it.
class _StationAvailability {
  final String stationName;
  final List<_AvailabilityRow> rows;

  const _StationAvailability({
    required this.stationName,
    required this.rows,
  });
}

class AvailableManagementContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const AvailableManagementContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<AvailableManagementContent> createState() =>
      _AvailableManagementContentState();
}

class _AvailableManagementContentState
    extends State<AvailableManagementContent> {
  bool _isLoading = true;
  String? _error;
  // Set only when the volunteer list itself couldn't be fetched — the rest
  // of the screen still renders.
  String? _volunteerError;

  _AvailabilityTab _tab = _AvailabilityTab.volunteer;

  // Day-off employees grouped per station.
  List<_StationAvailability> _dayOffSections = [];
  List<_AvailabilityRow> _unassignedRows = [];
  List<_VolunteerRow> _volunteerRows = [];

  int _dayOffToday = 0;

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  String get _formattedToday {
    final now = DateTime.now();
    return '${_months[now.month - 1]} ${now.day}, ${now.year}';
  }

  String get _todayIso {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // Column widths for the ID | Name | Role | Status table.
  static const Map<int, TableColumnWidth> _columnWidths = {
    0: FixedColumnWidth(110), // ID
    1: FlexColumnWidth(3),    // Name
    2: FlexColumnWidth(2),    // Role
    3: FlexColumnWidth(2),    // Status
  };

  // Volunteer table adds the two preference columns.
  static const Map<int, TableColumnWidth> _volunteerColumnWidths = {
    0: FixedColumnWidth(110), // ID
    1: FlexColumnWidth(3),    // Name
    2: FlexColumnWidth(2),    // Role
    3: FlexColumnWidth(2),    // Status
    4: FlexColumnWidth(2),    // Preferred shift
    5: FlexColumnWidth(3),    // Preferred station
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Fetches employees, the duty map and today's cover offers in parallel.
  // DutyService already encodes the availability rules (on duty / day off /
  // unassigned) — the same map the dashboard card counts from.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _volunteerError = null;
    });

    final results = await Future.wait([
      ApiService.fetchEmployees(),
      DutyService.fetchDutyMap(),
      ApiService.fetchCoverOffersForDate(_todayIso),
    ]);

    if (!mounted) return;

    final employeeResult = results[0] as Map;
    final duties = results[1] as Map<String, DutyInfo>;
    final offerResult = results[2] as Map;

    if (employeeResult["success"] != true) {
      setState(() {
        _error = employeeResult["error"].toString();
        _isLoading = false;
      });
      return;
    }

    final employees =
        (employeeResult["employees"] as List).cast<Employee>();

    final dayOffByStation = <String, List<_AvailabilityRow>>{};
    final unassignedRows = <_AvailabilityRow>[];

    for (final employee in employees) {
      if (!employee.isActive) continue;
      final duty = duties[employee.id];
      if (duty == null) {
        unassignedRows.add(_rowFor(employee, 'Unassigned'));
      } else if (!duty.onDutyToday) {
        dayOffByStation
            .putIfAbsent(duty.stationLabel, () => [])
            .add(_rowFor(employee, 'Day Off'));
      }
    }

    final stationNames = dayOffByStation.keys.toList()..sort();
    final sections = [
      for (final name in stationNames)
        _StationAvailability(
          stationName: name,
          rows: dayOffByStation[name]!
            ..sort((a, b) => a.name.compareTo(b.name)),
        ),
    ];

    // Volunteers: today's still-standing cover offers, matched back to the
    // employee record so the role and current standing are the live ones.
    final byId = {for (final e in employees) e.id: e};
    final volunteerRows = <_VolunteerRow>[];
    if (offerResult["success"] == true) {
      final offers = (offerResult["offers"] as List).cast<CoverOffer>();
      for (final offer in offers) {
        final employee = byId[offer.employeeId];
        // Skip anyone who has since been deactivated.
        if (employee != null && !employee.isActive) continue;
        volunteerRows.add(_VolunteerRow(
          id: offer.employeeId,
          name: employee?.name ?? offer.employeeName,
          role: employee != null
              ? employeeTypeToRoleString(employee.type)
              : _roleFromOfferType(offer.employeeType),
          status: duties[offer.employeeId]?.statusLabel ?? 'Unassigned',
          preferredShifts: _joinOrAny(offer.preferredShifts),
          preferredStations: _joinOrAny(offer.preferredStations),
        ));
      }
      volunteerRows.sort((a, b) => a.name.compareTo(b.name));
    }

    setState(() {
      _dayOffSections = sections;
      _unassignedRows = unassignedRows..sort((a, b) => a.name.compareTo(b.name));
      _volunteerRows = volunteerRows;
      _volunteerError = offerResult["success"] == true
          ? null
          : offerResult["error"].toString();
      _dayOffToday =
          dayOffByStation.values.fold(0, (sum, rows) => sum + rows.length);
      _isLoading = false;
    });
  }

  static String _joinOrAny(List<String> values) =>
      values.isEmpty ? 'Any' : values.join(', ');

  static String _roleFromOfferType(String type) {
    switch (type) {
      case 'reliever':
        return 'Reliever Employee';
      case 'headGuard':
        return 'Head Guard';
      default:
        return 'Regular Employee';
    }
  }

  _AvailabilityRow _rowFor(Employee employee, String status) {
    return _AvailabilityRow(
      id: employee.id,
      name: employee.name,
      role: employeeTypeToRoleString(employee.type),
      status: status,
    );
  }

  // Title + subtitle for the list area, per selected tab.
  String get _sectionTitle {
    switch (_tab) {
      case _AvailabilityTab.volunteer:
        return 'Volunteers Today';
      case _AvailabilityTab.dayOff:
        return 'Availability by Station';
      case _AvailabilityTab.unassigned:
        return 'Unassigned Employees';
    }
  }

  String get _headerSubtitle {
    switch (_tab) {
      case _AvailabilityTab.volunteer:
        return 'Employees who offered to work today';
      case _AvailabilityTab.dayOff:
        return 'Employees resting today, grouped by station';
      case _AvailabilityTab.unassigned:
        return 'Employees not yet assigned to a station';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Custom AppBar area — same treatment as Station Detail
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                  onPressed: () => widget.onNavigate(ScreenType.dashboard),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Employees Availability',
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _headerSubtitle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _loadData,
                  tooltip: 'Refresh',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF1034A6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDC2626).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Color(0xFFDC2626)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Could not reach the server: $_error',
                              style: const TextStyle(color: Color(0xFFDC2626)),
                            ),
                          ),
                          TextButton(
                            onPressed: _loadData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Stat cards — Date, then the three tabs. Tapping a card
                  // switches the list below it.
                  Row(
                    children: [
                      _buildStatCard(
                        'Date',
                        _formattedToday,
                        Icons.calendar_today,
                        const Color(0xFF1034A6),
                        valueFontSize: 18,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'Volunteer Employee',
                        _isLoading ? '…' : '${_volunteerRows.length}',
                        Icons.volunteer_activism_rounded,
                        const Color(0xFF059669),
                        tab: _AvailabilityTab.volunteer,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'Day Off Today',
                        _isLoading ? '…' : '$_dayOffToday',
                        Icons.event_busy_rounded,
                        const Color(0xFFEA580C),
                        tab: _AvailabilityTab.dayOff,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'Unassigned',
                        _isLoading ? '…' : '${_unassignedRows.length}',
                        Icons.person_search_rounded,
                        const Color(0xFFDC2626),
                        tab: _AvailabilityTab.unassigned,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Section title
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1034A6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _sectionTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF1034A6),
                            ),
                          )
                        : _buildTabBody(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tab) {
      case _AvailabilityTab.volunteer:
        return _buildVolunteerTab();
      case _AvailabilityTab.dayOff:
        return _buildDayOffTab();
      case _AvailabilityTab.unassigned:
        return _buildUnassignedTab();
    }
  }

  // Volunteers — one flat table, since a volunteer's station is a
  // preference rather than a posting.
  Widget _buildVolunteerTab() {
    if (_volunteerError != null) {
      return _buildEmptyState(
        'Could not load volunteers: $_volunteerError',
      );
    }
    if (_volunteerRows.isEmpty) {
      return _buildEmptyState(
        'No one has volunteered to work today.',
      );
    }
    return SingleChildScrollView(
      child: _buildTableCard(
        columnWidths: _volunteerColumnWidths,
        header: const TableRow(
          decoration: BoxDecoration(),
          children: [
            _HeaderCell('ID'),
            _HeaderCell('NAME'),
            _HeaderCell('ROLE'),
            _HeaderCell('STATUS'),
            _HeaderCell('PREFERRED SHIFT'),
            _HeaderCell('PREFERRED STATION'),
          ],
        ),
        rows: _volunteerRows.map(_buildVolunteerDataRow).toList(),
      ),
    );
  }

  // Day off — unchanged: one block per station with the guards resting there.
  Widget _buildDayOffTab() {
    if (_dayOffSections.isEmpty) {
      return _buildEmptyState(
        _error != null
            ? 'Nothing to show.'
            : 'No one is on a day off today — every assigned employee is on duty.',
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildStationSections(),
      ),
    );
  }

  // Unassigned — everyone with no schedule covering today, one flat table.
  Widget _buildUnassignedTab() {
    if (_unassignedRows.isEmpty) {
      return _buildEmptyState(
        _error != null
            ? 'Nothing to show.'
            : 'Every active employee is assigned to a station.',
      );
    }
    return SingleChildScrollView(
      child: _buildTableCard(
        columnWidths: _columnWidths,
        header: _buildHeaderRow(),
        rows: _unassignedRows.map(_buildDataRow).toList(),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  List<Widget> _buildStationSections() {
    final widgets = <Widget>[];
    for (int i = 0; i < _dayOffSections.length; i++) {
      widgets.add(_buildStationSection(_dayOffSections[i]));
      if (i != _dayOffSections.length - 1) widgets.add(_buildDivider());
    }
    return widgets;
  }

  // A stat card. With `tab` set it doubles as that tab's button and shows a
  // coloured border while selected; the Date card stays inert.
  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color iconColor, {
    _AvailabilityTab? tab,
    // The counts sit comfortably at 24; the Date card holds a whole
    // "August 1, 2026" in the same width, so it gets a smaller size.
    double valueFontSize = 24,
  }) {
    final bool isSelected = tab != null && tab == _tab;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? iconColor : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isSelected ? 0.10 : 0.04),
            blurRadius: isSelected ? 14 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(isSelected ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? iconColor : Colors.grey[600],
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (tab == null) return Expanded(child: card);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _tab = tab),
          child: card,
        ),
      ),
    );
  }

  // One station block: Station name title (+ headcount badge), then the
  // ID | Name | Role | Status table for everyone resting there.
  Widget _buildStationSection(_StationAvailability station) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              station.stationName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1034A6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${station.rows.length}',
                style: const TextStyle(
                  color: Color(0xFF1034A6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTableCard(
          columnWidths: _columnWidths,
          header: _buildHeaderRow(),
          rows: station.rows.map(_buildDataRow).toList(),
        ),
      ],
    );
  }

  // Shared white card + bordered table used by every tab.
  Widget _buildTableCard({
    required Map<int, TableColumnWidth> columnWidths,
    required TableRow header,
    required List<TableRow> rows,
  }) {
    return Container(
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
      child: Table(
        columnWidths: columnWidths,
        border: TableBorder.all(
          color: Colors.grey[200]!,
          width: 1,
          borderRadius: BorderRadius.circular(12),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: const Color(0xFF1034A6).withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            children: header.children,
          ),
          ...rows,
        ],
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return const TableRow(
      children: [
        _HeaderCell('ID'),
        _HeaderCell('NAME'),
        _HeaderCell('ROLE'),
        _HeaderCell('STATUS'),
      ],
    );
  }

  TableRow _buildDataRow(_AvailabilityRow row) {
    return TableRow(
      children: [
        _idCell(row.id),
        _nameCell(row.name),
        _mutedCell(row.role),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: _buildStatusBadge(row.status),
        ),
      ],
    );
  }

  TableRow _buildVolunteerDataRow(_VolunteerRow row) {
    return TableRow(
      children: [
        _idCell(row.id),
        _nameCell(row.name),
        _mutedCell(row.role),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: _buildStatusBadge(row.status),
        ),
        _mutedCell(row.preferredShifts),
        _mutedCell(row.preferredStations),
      ],
    );
  }

  Widget _idCell(String id) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          id,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _nameCell(String name) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      );

  Widget _mutedCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      );

  // Day Off -> orange (resting, could be called in), Unassigned -> red
  // (no station yet — needs a posting), anything else (On Duty / Absent,
  // possible on the volunteer tab) -> grey.
  Widget _buildStatusBadge(String status) {
    final Color color;
    switch (status) {
      case 'Day Off':
        color = const Color(0xFFEA580C);
        break;
      case 'Unassigned':
        color = const Color(0xFFDC2626);
        break;
      default:
        color = const Color(0xFF64748B);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status,
          style:
              TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // Thin grey separator with breathing room between station sections —
  // same treatment used on the other detail screens.
  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      height: 1,
      color: Colors.grey[300],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Color(0xFF1034A6),
        ),
      ),
    );
  }
}
