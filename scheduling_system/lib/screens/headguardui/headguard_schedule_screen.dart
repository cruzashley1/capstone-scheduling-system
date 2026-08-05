// screens/headguardui/headguard_schedule_screen.dart
import 'package:flutter/material.dart';
import '../../models/cover_offer.dart';
import '../../models/employee.dart';
import '../../models/guard_shift.dart';
import '../../services/api_service.dart';
import '../../services/server_clock.dart';
import '../cover_availability_screen.dart';

class HeadGuardScheduleScreen extends StatefulWidget {
  final Employee employee;
  final List<GuardShift> shifts;
  final List<GuardPeriod> periods;

  const HeadGuardScheduleScreen({
    super.key,
    required this.employee,
    required this.shifts,
    required this.periods,
  });

  @override
  State<HeadGuardScheduleScreen> createState() => _HeadGuardScheduleScreenState();
}

// One row in the Upcoming tab: either a duty shift or a rest day
// (a date inside a schedule period with no shift).
class _DayItem {
  final DateTime date;
  final GuardShift? shift;

  _DayItem(this.date, this.shift);

  bool get isRestDay => shift == null;
}

class _HeadGuardScheduleScreenState extends State<HeadGuardScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    'Saturday', 'Sunday',
  ];

  // This guard's cover offers, keyed by ISO date — used to badge rest days
  // in Upcoming as "Available" / "Covering".
  Map<String, CoverOffer> _offersByDate = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOffers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    final result =
        await ApiService.fetchEmployeeCoverOffers(widget.employee.id);
    if (!mounted || result['success'] != true) return;
    final offers = (result['offers'] as List).cast<CoverOffer>();
    setState(() {
      _offersByDate = {for (final o in offers) o.date: o};
    });
  }

  String _isoOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // Opens the availability form for a rest day, then refreshes the badges.
  Future<void> _openCover(DateTime date) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverAvailabilityScreen(
          employee: widget.employee,
          date: date,
        ),
      ),
    );
    if (saved == true) await _loadOffers();
  }

  DateTime get _today {
    final now = ServerClock.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  GuardShift? get _todayShift {
    for (final s in widget.shifts) {
      if (_dateOnly(s.date) == _today) return s;
    }
    return null;
  }

  GuardPeriod? get _currentPeriod {
    for (final p in widget.periods) {
      if (p.contains(_today)) return p;
    }
    return null;
  }

  // Upcoming = every date after today inside a published period:
  // duty days show their shift, the rest show as Rest Day.
  List<_DayItem> get _upcomingItems {
    final shiftByDate = <DateTime, GuardShift>{};
    for (final s in widget.shifts) {
      shiftByDate[_dateOnly(s.date)] = s;
    }

    final items = <_DayItem>[];
    for (final period in widget.periods) {
      var day = _dateOnly(period.startDate);
      final end = _dateOnly(period.endDate);
      while (!day.isAfter(end)) {
        if (day.isAfter(_today)) {
          items.add(_DayItem(day, shiftByDate[day]));
        }
        day = day.add(const Duration(days: 1));
      }
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  // Past = worked shifts before today, newest first.
  List<GuardShift> get _pastShifts {
    final past = widget.shifts
        .where((s) => _dateOnly(s.date).isBefore(_today))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return past;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width < 360 ? 14 : 20,
                vertical: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1034A6),
                    Color(0xFF1E4AD0),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Schedule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: MediaQuery.of(context).size.width < 360 ? 17 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            widget.employee.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Today'),
                        Tab(text: 'Upcoming'),
                        Tab(text: 'Past'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTodayTab(),
                  _buildUpcomingTab(),
                  _buildPastTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTab() {
    final todayShift = _todayShift;
    final currentPeriod = _currentPeriod;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 360;
        return SingleChildScrollView(
          padding: EdgeInsets.all(isSmall ? 14 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isSmall ? 16 : 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1034A6),
                      Color(0xFF1E4AD0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1034A6).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _longDate(_today),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isSmall ? 11 : 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      todayShift != null
                          ? todayShift.title
                          : (currentPeriod != null
                              ? 'Rest Day'
                              : 'No Published Schedule'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmall ? 18 : 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (todayShift != null) ...[
                      if (todayShift.isCovering) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Covering for ${todayShift.coveringFor}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.login,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Time In',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                todayShift.timeIn,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.logout,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Time Out',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                todayShift.timeOut,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildInfoChip(
                            icon: Icons.location_on_outlined,
                            label: todayShift.stationName,
                          ),
                          _buildInfoChip(
                            icon: Icons.access_time,
                            label: todayShift.duration,
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        currentPeriod != null
                            ? 'You have no duty today. Enjoy your rest day!'
                            : 'Your shifts will appear here once the admin publishes a schedule.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Shift Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
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
                  children: [
                    _buildSummaryRow(
                      'Position',
                      employeeTypeToRoleString(widget.employee.type),
                    ),
                    const Divider(height: 24),
                    _buildSummaryRow('Employee ID', widget.employee.username),
                    const Divider(height: 24),
                    _buildSummaryRow(
                      'Assigned Station',
                      widget.employee.assignedStation ??
                          currentPeriod?.stationName ??
                          'Floating / As assigned',
                    ),
                    const Divider(height: 24),
                    _buildSummaryRow(
                      'Assigned Shift',
                      assignedShiftLabel(widget.employee.assignedShift),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingTab() {
    final items = _upcomingItems;

    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.event_available,
        message: 'No upcoming days on the published schedule yet.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final shift = item.shift;
        final isRestDay = item.isRestDay;
        final offer = _offersByDate[_isoOf(item.date)];
        final hasActiveOffer = offer != null && offer.isActive;
        final isCoveringOffer = offer != null && offer.isFulfilled;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
          // Rest days are tappable — tap to offer to cover a shift that day.
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isRestDay ? () => _openCover(item.date) : null,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isRestDay
                            ? Colors.grey[100]
                            : const Color(0xFF1034A6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${item.date.day}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                              color: isRestDay
                                  ? Colors.grey[500]
                                  : const Color(0xFF1034A6),
                            ),
                          ),
                          Text(
                            _months[item.date.month - 1],
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: isRestDay
                                  ? Colors.grey[400]
                                  : const Color(0xFF1034A6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _weekdays[item.date.weekday - 1],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isRestDay ? 'Rest Day' : shift!.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isRestDay
                                  ? Colors.grey[600]
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          if (isRestDay) ...[
                            const SizedBox(height: 4),
                            Text(
                              isCoveringOffer
                                  ? "You're covering a shift this day"
                                  : hasActiveOffer
                                      ? "You're available to cover"
                                      : 'Tap to make yourself available to cover',
                              style: TextStyle(
                                fontSize: 12,
                                color: isCoveringOffer
                                    ? const Color(0xFF1034A6)
                                    : hasActiveOffer
                                        ? const Color(0xFF16A34A)
                                        : Colors.grey[500],
                                fontWeight: (hasActiveOffer || isCoveringOffer)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    shift!.timeRange,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 12,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    shift.stationName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    _buildUpcomingBadge(
                      isRestDay: isRestDay,
                      isCovering: !isRestDay && shift!.isCovering,
                      hasActiveOffer: hasActiveOffer,
                      isCoveringOffer: isCoveringOffer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Trailing status pill for an Upcoming row. Rest days reflect the cover
  // offer (Available / Covering) or invite one (Rest Day); duty days show
  // Covering / Upcoming as before.
  Widget _buildUpcomingBadge({
    required bool isRestDay,
    required bool isCovering,
    required bool hasActiveOffer,
    required bool isCoveringOffer,
  }) {
    late final Color color;
    late final String label;
    if (!isRestDay) {
      color = const Color(0xFF1034A6);
      label = isCovering ? 'Covering' : 'Upcoming';
    } else if (isCoveringOffer) {
      color = const Color(0xFF1034A6);
      label = 'Covering';
    } else if (hasActiveOffer) {
      color = const Color(0xFF16A34A);
      label = 'Available';
    } else {
      color = const Color(0xFF64748B);
      label = 'Rest Day';
    }
    final bool muted = isRestDay && !hasActiveOffer && !isCoveringOffer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: muted ? Colors.grey[100] : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted ? Colors.grey[600] : color,
        ),
      ),
    );
  }

  Widget _buildPastTab() {
    final past = _pastShifts;

    if (past.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history,
        message: 'No completed shifts on the published schedule yet.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: past.length,
      itemBuilder: (context, index) {
        final shift = past[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
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
          child: Row(
            children: [
              Container(
                width: 50,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1034A6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${shift.date.day}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        color: Color(0xFF1034A6),
                      ),
                    ),
                    Text(
                      _months[shift.date.month - 1],
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: Color(0xFF1034A6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _weekdays[shift.date.weekday - 1],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shift.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            shift.timeRange,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            shift.stationName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  String _longDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
}
