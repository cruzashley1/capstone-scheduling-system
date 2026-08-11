// screens/absent_management_screen.dart
//
// Shown when the "Absent Today" box is tapped on the dashboard.
// Lists, per station and per shift (Morning/Afternoon/Night), everyone
// who is absent today — built from the attendance reports the head
// guards submitted today.
import 'package:flutter/material.dart';
import '../models/attendance_report.dart';
import '../models/replacement.dart';
import '../services/api_service.dart';
import '../services/cover_window.dart';
import 'main_layout.dart';

// One absent person's row.
class _AbsenceRow {
  final String id;
  final String name;
  final String status; // 'Regular' or 'Reliever'
  final String time;

  // Context needed to hand this absence to the Find Replacement screen
  // (and to show "Replaced by ..." once the admin covered it).
  final AttendanceRecord record;
  final String reportId;
  final String station;
  final String date; // ISO date of the absence

  const _AbsenceRow({
    required this.id,
    required this.name,
    required this.status,
    required this.time,
    required this.record,
    required this.reportId,
    required this.station,
    required this.date,
  });
}

// One shift block within a station (Morning / Afternoon / Night).
class _ShiftAbsence {
  final String shiftLabel;
  final List<_AbsenceRow> rows;

  const _ShiftAbsence({
    required this.shiftLabel,
    required this.rows,
  });
}

// One station's block: name + its Morning/Afternoon/Night absence tables.
class _StationAbsence {
  final String stationName;
  final List<_ShiftAbsence> shifts;

  const _StationAbsence({
    required this.stationName,
    required this.shifts,
  });

  int get totalAbsent => shifts.fold(0, (sum, s) => sum + s.rows.length);
}

class AbsentManagementContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const AbsentManagementContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<AbsentManagementContent> createState() =>
      _AbsentManagementContentState();
}

class _AbsentManagementContentState extends State<AbsentManagementContent> {
  List<_StationAbsence> _stations = [];
  bool _isLoading = true;
  String? _loadError;

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Keeps the station blocks in a predictable shift order.
  static const List<String> _shiftOrder = [
    'Morning', 'Afternoon', 'Night', 'HG Day', 'HG Night',
  ];

  String get _formattedToday {
    final now = DateTime.now();
    return '${_months[now.month - 1]} ${now.day}, ${now.year}';
  }

  // Column widths for the ID | Name | Status | Time | Action table below.
  static const Map<int, TableColumnWidth> _columnWidths = {
    0: FixedColumnWidth(80),  // ID
    1: FlexColumnWidth(3),    // Name
    2: FixedColumnWidth(110), // Status
    3: FlexColumnWidth(2),    // Time
    4: FixedColumnWidth(190), // Action (Find Replacement / Replaced by)
  };

  int get _totalAbsent => _stations.fold(0, (sum, s) => sum + s.totalAbsent);

  @override
  void initState() {
    super.initState();
    _loadAbsences();
  }

  // Fetches today's submitted attendance reports and reshapes them into
  // the station -> shift -> rows structure the tables below render.
  Future<void> _loadAbsences() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final result = await ApiService.fetchAttendanceReports();
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _isLoading = false;
        _loadError = result['error']?.toString() ?? 'Failed to load reports';
      });
      return;
    }

    final reports = (result['reports'] as List)
        .cast<AttendanceReport>()
        .where((r) => r.isForToday && r.hasAbsent)
        .toList();

    // Group absences: station -> shift -> rows. Reports are merged by
    // station name, so a day-HG and night-HG report for the same station
    // end up in one block.
    final byStation = <String, Map<String, List<_AbsenceRow>>>{};
    for (final report in reports) {
      final byShift = byStation.putIfAbsent(report.station, () => {});
      for (final rec in report.absentRecords) {
        byShift.putIfAbsent(rec.shift, () => []).add(_AbsenceRow(
              id: rec.employeeId,
              name: rec.name,
              status: rec.isReliever ? 'Reliever' : 'Regular',
              time: rec.time,
              record: rec,
              reportId: report.id,
              station: report.station,
              date: report.date,
            ));
      }
    }

    final stations = byStation.entries.map((station) {
      final byShift = station.value;
      final orderedShifts = [
        for (final shift in _shiftOrder)
          if (byShift.containsKey(shift))
            _ShiftAbsence(
              shiftLabel: '$shift Shift',
              rows: byShift[shift]!,
            ),
        // Any shift label we don't know about still gets shown.
        for (final entry in byShift.entries)
          if (!_shiftOrder.contains(entry.key))
            _ShiftAbsence(shiftLabel: entry.key, rows: entry.value),
      ];
      return _StationAbsence(
        stationName: station.key,
        shifts: orderedShifts,
      );
    }).toList()
      ..sort((a, b) => a.stationName.compareTo(b.stationName));

    setState(() {
      _isLoading = false;
      _stations = stations;
    });
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
                        'Absent Today',
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Absences by station and shift',
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
                  onPressed: _isLoading ? null : _loadAbsences,
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
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF1034A6)),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loadError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFD97706)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber,
                                    size: 18, color: Color(0xFFD97706)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Could not reach the server: $_loadError',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF92400E)),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loadAbsences,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Stat cards — Date + Total Absent
                        Row(
                          children: [
                            _buildStatCard(
                              'Date',
                              _formattedToday,
                              Icons.calendar_today,
                              const Color(0xFF1034A6),
                            ),
                            const SizedBox(width: 16),
                            _buildStatCard(
                              'Total Absent',
                              _totalAbsent.toString(),
                              Icons.warning_rounded,
                              const Color(0xFFDC2626),
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
                            const Text(
                              'Absences by Station',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Station sections — each with Station name, then a
                        // Shift Type subsection + table per shift.
                        Expanded(
                          child: _stations.isEmpty
                              ? _buildEmptyState()
                              : SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: _buildStationSections(),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: Colors.green[300],
          ),
          const SizedBox(height: 16),
          Text(
            _loadError != null
                ? 'No absence data available'
                : 'No absences reported today',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _loadError != null
                ? 'Reconnect to the server to see today\'s absences.'
                : 'When a head guard reports an absence, it will show '
                    'up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStationSections() {
    final widgets = <Widget>[];
    for (int i = 0; i < _stations.length; i++) {
      widgets.add(_buildStationSection(_stations[i]));
      if (i != _stations.length - 1) widgets.add(_buildDivider());
    }
    return widgets;
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // One station block: Station name title (+ absent count badge), then a
  // Morning/Afternoon/Night shift subsection for each, each with its own
  // ID | Name | Status | Time table.
  Widget _buildStationSection(_StationAbsence station) {
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
                color: const Color(0xFFDC2626).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${station.totalAbsent} absent',
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final shift in station.shifts) ...[
          _buildShiftSection(shift),
          if (shift != station.shifts.last) const SizedBox(height: 20),
        ],
      ],
    );
  }

  // One Shift Type subsection: small label, then its table.
  Widget _buildShiftSection(_ShiftAbsence shift) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          shift.shiftLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Container(
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
            columnWidths: _columnWidths,
            border: TableBorder.all(
              color: Colors.grey[200]!,
              width: 1,
              borderRadius: BorderRadius.circular(12),
            ),
            children: [
              _buildHeaderRow(),
              ...shift.rows.map(_buildDataRow),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      children: const [
        _HeaderCell('ID'),
        _HeaderCell('NAME'),
        _HeaderCell('STATUS'),
        _HeaderCell('TIME'),
        _HeaderCell('ACTION'),
      ],
    );
  }

  TableRow _buildDataRow(_AbsenceRow row) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            row.id,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            row.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: _buildStatusBadge(row.status),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(row.time, style: const TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildActionCell(row),
        ),
      ],
    );
  }

  // "Find Replacement" opens the suggestion screen for this absence;
  // once covered, the cell shows who replaced them instead. And once the
  // post has timed out the button goes altogether — there is nobody left
  // to send to a duty that is over (see CoverWindow). This list is "today"
  // but a night post from yesterday can still be running, and a report
  // filed this morning is already history by the afternoon.
  Widget _buildActionCell(_AbsenceRow row) {
    if (row.record.isReplaced) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz,
                  size: 13, color: Color(0xFF059669)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Replaced by ${row.record.replacedByName}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final end = CoverWindow.endsAt(row.date, row.record.shift,
        range: row.record.time);
    if (end != null && CoverWindow.hasPassed(end)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: 'This ${row.record.shift} post ${CoverWindow.closedLabel(end)}'
              ' — a replacement can only be assigned while the duty is '
              'still running.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_toggle_off_rounded,
                  size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 5),
              Text(
                'Shift ended',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => widget.onNavigate(
          ScreenType.findReplacement,
          data: ReplacementRequest(
            date: row.date,
            station: row.station,
            shift: row.record.shift,
            absentEmployeeId: row.id,
            absentName: row.name,
            reportId: row.reportId,
            record: row.record,
          ),
        ),
        icon: const Icon(Icons.person_search, size: 16),
        label: const Text('Find Replacement'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF1034A6),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // Reliever -> green, Regular -> brand blue. Same convention as the
  // Reliever Availability screen.
  Widget _buildStatusBadge(String status) {
    final bool isReliever = status == 'Reliever';
    final Color color = isReliever ? const Color(0xFF059669) : const Color(0xFF1034A6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  // Thin grey separator with breathing room between station sections.
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
