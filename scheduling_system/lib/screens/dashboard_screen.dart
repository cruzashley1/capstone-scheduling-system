import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/attendance_report.dart';
import '../models/employee.dart';
import '../models/schedule.dart';
import '../models/station.dart';
import '../services/api_service.dart';
import '../services/duty_service.dart';
import '../services/server_clock.dart';
import '../widgets/dashboard_analytics.dart';
import '../widgets/station_icon.dart';
import 'main_layout.dart';

class DashboardContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const DashboardContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> {
  // Real data pulled from the Python backend (Firestore).
  int? _totalEmployees;
  int _activeEmployees = 0;
  List<Employee> _employees = [];
  List<Station> _stations = [];
  List<Schedule> _schedules = [];
  List<AttendanceReport> _attendanceReports = [];
  bool _isLoading = true;
  String? _error;

  // Distinct guards marked absent in today's submitted head guard
  // reports — feeds the "Absent Today" card.
  int get _absentToday => _attendanceReports
      .where((r) => r.isForToday)
      .expand((r) => r.absentRecords)
      .map((rec) => rec.employeeId)
      .toSet()
      .length;

  // Active employees free to be deployed today: those whose current
  // schedule gives them a day off today, plus those not assigned to any
  // active schedule at all. Reuses the same duty rules as the employee
  // list screen (DutyService).
  int _dayOffToday = 0;
  int _unassignedToday = 0;
  int get _employeesAvailable => _dayOffToday + _unassignedToday;

  void _recomputeAvailability() {
    final duties = DutyService.buildDutyMap(_schedules);
    var dayOff = 0;
    var unassigned = 0;
    for (final employee in _employees) {
      if (!employee.isActive) continue;
      final duty = duties[employee.id];
      if (duty == null) {
        unassigned++;
      } else if (!duty.onDutyToday) {
        dayOff++;
      }
    }
    _dayOffToday = dayOff;
    _unassignedToday = unassigned;
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Fetches employees, stations and schedules in parallel. Employees and
  // stations drive the summary cards; schedules give each recent-station
  // card its "guards on duty today" count (same logic as Station
  // Management).
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.fetchEmployees(),
      ApiService.fetchStations(),
      ApiService.fetchSchedules(),
      ApiService.fetchAttendanceReports(),
    ]);

    if (!mounted) return;

    final employeeResult = results[0];
    final stationResult = results[1];
    final scheduleResult = results[2];
    final reportResult = results[3];

    setState(() {
      if (employeeResult["success"] == true) {
        final employees = employeeResult["employees"] as List;
        _employees = employees.cast<Employee>();
        _totalEmployees = _employees.length;
        _activeEmployees = _employees.where((e) => e.isActive).length;
      }
      if (stationResult["success"] == true) {
        _stations = stationResult["stations"] as List<Station>;
      }
      // Schedules failing to load shouldn't block the dashboard — the
      // per-station counts just fall back to 0 until the next refresh.
      _schedules = scheduleResult["success"] == true
          ? scheduleResult["schedules"] as List<Schedule>
          : [];
      // Same for attendance reports — Absent Today just shows 0 until
      // the next refresh.
      _attendanceReports = reportResult["success"] == true
          ? (reportResult["reports"] as List).cast<AttendanceReport>()
          : [];

      _recomputeAvailability();

      if (employeeResult["success"] != true &&
          stationResult["success"] != true) {
        _error = employeeResult["error"].toString();
      }
      _isLoading = false;
    });
  }

  // How many distinct guards the station's active published schedule puts
  // on duty today. Prefers the published schedule covering today; if none
  // does, falls back to the most recently created published one.
  int _assignedTodayCount(Station station) {
    final published = _schedules
        .where((s) =>
            s.status == ScheduleStatus.published && s.stationId == station.id)
        .toList();
    if (published.isEmpty) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Schedule schedule = published.firstWhere(
      (s) => !today.isBefore(s.startDate) && !today.isAfter(s.endDate),
      orElse: () => published
          .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b),
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

  // Newest stations first (IDs are sequential, so the highest ID is the
  // most recently created), capped at 5 for the horizontal strip.
  List<Map<String, dynamic>> get _recentStations {
    final sorted = [..._stations]..sort((a, b) => b.id.compareTo(a.id));
    return sorted.take(5).map((station) {
      final assigned = _assignedTodayCount(station);
      final shortage = station.requiredEmployees > assigned
          ? station.requiredEmployees - assigned
          : 0;
      return {
        'station': station,
        'totalEmployees': assigned,
        'shortage': shortage,
      };
    }).toList();
  }

  String get _todayLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final stationsWithAttendance = _recentStations;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modern Header - EXACTLY AS YOU DESIGNED
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible so a narrow window shrinks the title instead of
                // overflowing the header row.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Dashboard Overview',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Welcome back, Administrator',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _isLoading ? null : _loadDashboardData,
                      tooltip: 'Refresh',
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFF1034A6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1034A6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: const Color(0xFF1034A6)),
                          const SizedBox(width: 8),
                          Text(
                            _todayLabel,
                            style: TextStyle(
                              color: const Color(0xFF1034A6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF1034A6),
                      child: const Text(
                        'AD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Content - EXACTLY AS YOU DESIGNED
          Expanded(
            child: SingleChildScrollView(
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
                            onPressed: _loadDashboardData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Enhanced Summary Cards - MODIFIED: Only 4 cards now
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // The stacked cards (picture → number → label) sit best
                      // as one row of four; drop to two columns once the
                      // content area gets too narrow to keep them readable.
                      final int crossAxisCount =
                          constraints.maxWidth > 1000 ? 4 : 2;
                      const double spacing = 20;
                      // Derive the ratio from the real tile width so the cards
                      // keep the same height at either column count instead of
                      // stretching to whatever the ratio happens to produce.
                      const double tileHeight = 244;
                      final double tileWidth =
                          (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
                              crossAxisCount;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: tileWidth / tileHeight,
                        children: [
                          _buildAnimatedCard(
                            'Total Employees',
                            _isLoading
                                ? '…'
                                : (_totalEmployees?.toString() ?? '—'),
                            'assets/images/all_employeev2.png',
                            'assets/images/all_employee.png',
                            const Color(0xFF1034A6),
                            _totalEmployees == null
                                ? 'Loading…'
                                : '$_activeEmployees active',
                                () => widget.onNavigate(ScreenType.employeeList),
                          ),
                          _buildAnimatedCard(
                            'Total Stations',
                            _isLoading ? '…' : _stations.length.toString(),
                            'assets/images/stationv2.png',
                            'assets/images/station.png',
                            const Color(0xFF059669),
                            _isLoading
                                ? 'Loading…'
                                : '${_stations.where((s) => s.isActive).length} operational',
                                () => widget.onNavigate(ScreenType.stationManagement),
                          ),
                          _buildAnimatedCard(
                            'Employees Availability',
                            _isLoading ? '…' : '$_employeesAvailable',
                            'assets/images/availablev2.png',
                            'assets/images/available.png',
                            // Amber to match the available.png swap-arrows
                            // artwork (red is reserved for the Absent card).
                            const Color(0xFFEA580C),
                            _isLoading
                                ? 'Loading…'
                                : '$_dayOffToday day off · $_unassignedToday unassigned',
                                () => widget.onNavigate(ScreenType.availableManagement),
                          ),
                          _buildAnimatedCard(
                            'Absent Today',
                            _isLoading ? '…' : '$_absentToday',
                            'assets/images/absentv2.png',
                            'assets/images/absent.png',
                            // Red to match the absent.png warning-triangle
                            // artwork.
                            const Color(0xFFDC2626),
                            _absentToday > 0
                                ? 'Needs replacement'
                                : 'No absences reported',
                                () => widget.onNavigate(ScreenType.absentManagement),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Analytics band: Post Coverage beside Attendance.
                  // Purely additive — it reads the stations and
                  // schedules already fetched above, so it costs no
                  // extra request, and every card and the station strip
                  // below are untouched. onOpenSchedules is still handed
                  // over for the parked Schedule Health panel.
                  DashboardAnalytics(
                    stations: _stations,
                    schedules: _schedules,
                    attendanceReports: _attendanceReports,
                    isLoading: _isLoading,
                    today: ServerClock.now(),
                    onOpenSchedules: () =>
                        widget.onNavigate(ScreenType.scheduleManagement),
                    onOpenReports: () =>
                        widget.onNavigate(ScreenType.submittedReports),
                  ),

                  const SizedBox(height: 32),

                  // Modern Section Header - MODIFIED: Changed to Recent Stations
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
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
                            const Flexible(
                              child: Text(
                                'Recent Stations',  // CHANGED: Was 'Recent Employees'
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => widget.onNavigate(ScreenType.stationManagement),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('View All'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1034A6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFF1034A6)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Horizontal Station List - MODIFIED: Now shows real stations
                  SizedBox(
                    height: 220,
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF1034A6),
                            ),
                          )
                        : stationsWithAttendance.isEmpty
                            ? Center(
                                child: Text(
                                  'No stations yet — add one from Station Management.',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              )
                            // Press-and-drag to scroll: desktop/web ignore
                            // mouse drags on a ListView by default, so opt the
                            // mouse (and trackpad) into dragDevices. The grab
                            // cursor signals the strip is draggable.
                            : MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: ScrollConfiguration(
                                  behavior:
                                      ScrollConfiguration.of(context).copyWith(
                                    dragDevices: {
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.trackpad,
                                    },
                                    scrollbars: false,
                                  ),
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: stationsWithAttendance.length,
                                    itemBuilder: (context, index) {
                                      final stationData =
                                          stationsWithAttendance[index];
                                      return _buildModernStationCard(
                                          stationData);
                                    },
                                  ),
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

  // UPDATED: now delegates to _HoverStatCard so the box can react to the
  // mouse (scale up + blue tinted glow) on hover. iconAsset/iconHoverAsset
  // are the "standard" and "hover" PNGs that crossfade on mouse-over.
  Widget _buildAnimatedCard(String title, String value, String iconAsset,
      String iconHoverAsset, Color color, String subtitle, VoidCallback? onTap) {
    return _HoverStatCard(
      title: title,
      value: value,
      iconAsset: iconAsset,
      iconHoverAsset: iconHoverAsset,
      color: color,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  // Station card with staffing status. "Attention Needed" now means the
  // published schedule puts fewer guards on duty today than the station
  // requires (there is no per-day absence feed yet).
  Widget _buildModernStationCard(Map<String, dynamic> stationData) {
    final Station station = stationData['station'] as Station;
    final int totalEmployees = stationData['totalEmployees'] as int;
    final int shortage = stationData['shortage'] as int;

    final bool needsAttention = shortage > 0;
    final Color statusColor = needsAttention ? const Color(0xFFDC2626) : const Color(0xFF059669);
    final String statusText = needsAttention ? 'Attention Needed' : 'Fully Staffed';
    final IconData statusIcon = needsAttention ? Icons.warning_rounded : Icons.check_circle_rounded;

    return GestureDetector(
      onTap: () {
        // Open the station's own detail page (same destination as tapping
        // its row in Station Management), not the management list.
        widget.onNavigate(ScreenType.stationDetail, data: station);
      },
      child: Container(
        width: 300,
        margin: const EdgeInsets.only(right: 16),
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
          // Add subtle border highlight if attention needed
          border: needsAttention ? Border.all(color: const Color(0xFFDC2626).withOpacity(0.3), width: 1) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Raw station logo, no backing tile — the card border
                  // already flags stations needing attention.
                  const StationIcon(size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          station.id,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          statusIcon,
                          size: 12,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Employee Count Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people_alt_rounded, size: 16, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Text(
                              'On Duty Today:',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$totalEmployees / ${station.requiredEmployees}',
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (needsAttention) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_rounded, size: 16, color: const Color(0xFFDC2626)),
                              const SizedBox(width: 6),
                              Text(
                                'Understaffed by:',
                                style: TextStyle(
                                  color: const Color(0xFFDC2626),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '$shortage',
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// Hoverable version of the summary stat card. Same look as before at rest;
// on hover (desktop/web — touch devices won't trigger this) the card lifts
// off the page with its own accent color (no overlay tint or blue wash) and
// its icon badge fills in solid, the way a clean dashboard card "pops" on
// hover. Cards with no onTap (onTap == null) intentionally don't react to
// hover.
class _HoverStatCard extends StatefulWidget {
  final String title;
  final String value;
  final String iconAsset;
  final String iconHoverAsset;
  final Color color;
  final String subtitle;
  final VoidCallback? onTap;

  const _HoverStatCard({
    required this.title,
    required this.value,
    required this.iconAsset,
    required this.iconHoverAsset,
    required this.color,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_HoverStatCard> createState() => _HoverStatCardState();
}

class _HoverStatCardState extends State<_HoverStatCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bool canHover = widget.onTap != null;
    final bool active = _hovering && canHover;

    return MouseRegion(
      cursor: canHover ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 400),
          builder: (context, double entrance, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - entrance)),
              child: Opacity(
                opacity: entrance,
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            // Lift the whole card up a touch on hover instead of washing it
            // in a tinted overlay — reads as "raised off the page".
            transform: Matrix4.identity()
              ..translate(0.0, active ? -6.0 : 0.0)
              ..scale(active ? 1.012 : 1.0),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? widget.color.withOpacity(0.25) : Colors.transparent,
                width: 1.2,
              ),
              boxShadow: [
                // Soft, colored "contact" shadow that grows and drops lower
                // on hover, simulating the card lifting toward the light —
                // tinted with the card's own accent color, not a fixed blue.
                BoxShadow(
                  color: active ? widget.color.withOpacity(0.24) : widget.color.withOpacity(0.10),
                  blurRadius: active ? 26 : 10,
                  offset: active ? const Offset(0, 16) : const Offset(0, 4),
                ),
                if (active)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            // Clip so the watermark background image below respects the
            // card's rounded corners.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // Decorative background art, sat behind everything else.
                  // >>> ADJUST THE CARD BACKGROUND STRENGTH HERE <<<
                  // Lower = more subtle/washed out, higher = more visible.
                  //
                  // >>> ADJUST THE PATTERN ZOOM WITH `scale` BELOW <<<
                  // The Transform.scale zooms the network pattern IN so the
                  // hexagons/nodes read large and fill the card (bigger =
                  // more zoomed in, 1.0 = fit the whole image). Overflow is
                  // clipped by the ClipRRect above.
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.15,
                      child: Transform.scale(
                        scale: 2.6,
                        child: Image.asset(
                          'assets/images/card_background.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Picture sits alone at the top of the stack. Both
                        // art variants stay mounted and crossfade via
                        // opacity — an AnimatedSwitcher keyed on the hover
                        // flag throws "Duplicate keys found" when the mouse
                        // re-enters before the 200ms switch finishes (only
                        // two keys exist, so an exiting child can collide
                        // with the entering one), which then cascades into
                        // overflow errors and a corrupted element tree.
                        // cacheWidth decodes the 1754px-wide PNGs at icon
                        // size instead of ~9 MB apiece.
                        SizedBox(
                          width: 66,
                          height: 66,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedOpacity(
                                opacity: active ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Image.asset(
                                  widget.iconAsset,
                                  fit: BoxFit.contain,
                                  cacheWidth: 132,
                                ),
                              ),
                              AnimatedOpacity(
                                opacity: active ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Image.asset(
                                  widget.iconHoverAsset,
                                  fit: BoxFit.contain,
                                  cacheWidth: 132,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Number, then the label beneath it.
                        Text(
                          widget.value,
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Status chip closes the stack. It gets its own row so
                        // the longer subtitles ("N day off · N unassigned")
                        // have the full card width instead of competing with
                        // the picture for space.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
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
      ),
    );
  }
}
