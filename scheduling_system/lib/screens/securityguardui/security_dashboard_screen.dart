// screens/securityguardui/security_dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/absence_request.dart';
import '../../models/employee.dart';
import '../../models/guard_shift.dart';
import '../../models/leave_request.dart';
import '../../services/duty_clock.dart';
import '../../services/server_clock.dart';
import '../../widgets/absence_request_card.dart';
import '../../widgets/cover_availability_card.dart';
import '../../widgets/leave_request_card.dart';
import '../../widgets/special_request_card.dart';
import '../../widgets/today_duty_card.dart';

class SecurityDashboardScreen extends StatefulWidget {
  final Employee employee;
  final List<GuardShift> shifts;
  final List<GuardPeriod> periods;
  final List<AbsenceRequest> absenceRequests;
  final List<LeaveRequest> leaves;

  // Refetches the layout's data — used after an absence is filed.
  final Future<void> Function() onDataChanged;

  const SecurityDashboardScreen({
    super.key,
    required this.employee,
    required this.shifts,
    required this.periods,
    required this.absenceRequests,
    this.leaves = const [],
    required this.onDataChanged,
  });

  @override
  State<SecurityDashboardScreen> createState() =>
      _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  // Drives the live clock and, with it, every status transition: the
  // dashboard flips from Awaiting to On Duty to Off Shift on its own,
  // without the guard pulling to refresh.
  Timer? _ticker;
  DateTime _now = ServerClock.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = ServerClock.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  Employee get employee => widget.employee;
  List<GuardShift> get shifts => widget.shifts;
  List<GuardPeriod> get periods => widget.periods;

  DateTime get _today => DutyClock.dateOnly(_now);

  // The published schedule period covering today, if any.
  GuardPeriod? get _currentPeriod {
    for (final p in periods) {
      if (p.contains(_today)) return p;
    }
    return null;
  }

  List<GuardShift> get _upcomingShifts {
    final upcoming = shifts.where((s) {
      final d = DutyClock.dateOnly(s.date);
      return d.isAfter(_today);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return upcoming.take(3).toList();
  }

  String get _greeting {
    final hour = _now.hour;
    if (hour < 12) return 'Good Morning! 👋';
    if (hour < 18) return 'Good Afternoon! 👋';
    return 'Good Evening! 👋';
  }

  // Where the guard works right now: the current duty's station, else
  // their fixed assignment, else the current period's station.
  String get _stationLabel {
    if (employee.assignedStation != null &&
        employee.assignedStation!.isNotEmpty) {
      return employee.assignedStation!;
    }
    if (_currentPeriod != null) return _currentPeriod!.stationName;
    return 'Unassigned';
  }

  @override
  Widget build(BuildContext context) {
    final currentPeriod = _currentPeriod;
    final upcomingShifts = _upcomingShifts;

    // The single time-aware read of "where does this guard stand right
    // now" — every badge, gate and countdown below comes off it.
    final duty = DutyClock.resolve(
      shifts: shifts,
      periods: periods,
      absenceRequests: widget.absenceRequests,
      leaves: widget.leaves,
      at: _now,
    );

    // Bi-week stats over the current period (rest days = period days
    // with no duty entry; covers = reliever/substitute duties).
    int dutyDays = 0;
    int restDays = 0;
    int coverDuties = 0;
    if (currentPeriod != null) {
      final periodShifts = shifts.where((s) => currentPeriod.contains(s.date));
      final dutyDates = <DateTime>{};
      for (final s in periodShifts) {
        dutyDates.add(DateTime(s.date.year, s.date.month, s.date.day));
        if (s.isCovering) coverDuties++;
      }
      dutyDays = dutyDates.length;
      final totalDays =
          currentPeriod.endDate.difference(currentPeriod.startDate).inDays + 1;
      restDays = totalDays - dutyDays;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1034A6),
                      Color(0xFF1E4AD0),
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                employee.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              employee.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: duty.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${employeeTypeToRoleString(employee.type)} · $_stationLabel',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Today's Duty Card — clock-aware: the status, countdown
              // and progress all come from DutyClock.resolve().
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TodayDutyCard(
                  state: duty,
                  stationLabel: _stationLabel,
                ),
              ),

              const SizedBox(height: 24),

              // Request — every request this guard can file, gathered in
              // one place under today's duty (which is the shift most of
              // them are about).
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Request',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Longest notice of the three: a continuous stretch of days
              // — a vacation, a sickness, a maternity.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LeaveRequestCard(
                  employee: employee,
                  onChanged: widget.onDataChanged,
                ),
              ),

              const SizedBox(height: 12),

              // Planned ahead: days off asked for before the schedule
              // covering them exists.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SpecialRequestCard(employee: employee),
              ),

              // Unplanned: closes an hour before time-in, so a guard about
              // to report for duty can no longer file one. Hidden while on
              // leave — there is no duty to call in absent from.
              if (!duty.isOnLeave) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AbsenceRequestCard(
                    employee: employee,
                    shifts: shifts,
                    requests: widget.absenceRequests,
                    state: duty,
                    onChanged: widget.onDataChanged,
                  ),
                ),
              ],

              // "Available to cover" entry point — only on a true rest day
              // (in a published period, no duty at all today).
              if (duty.isDayOff) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: CoverAvailabilityCard(employee: employee),
                ),
              ],

              const SizedBox(height: 24),

              // Bi-Week Stats
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'This Bi-Week',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.work_outline,
                      value: '$dutyDays',
                      label: 'Days On\nDuty',
                      iconColor: const Color(0xFF1034A6),
                      iconBgColor: const Color(0xFF1034A6).withOpacity(0.1),
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.coffee_outlined,
                      value: '$restDays',
                      label: 'Rest Days',
                      iconColor: Colors.green,
                      iconBgColor: Colors.green.withOpacity(0.1),
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.swap_horiz,
                      value: '$coverDuties',
                      label: 'Cover\nDuties',
                      iconColor: Colors.orange,
                      iconBgColor: Colors.orange.withOpacity(0.1),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Upcoming Shifts
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Upcoming Shifts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (upcomingShifts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'No upcoming shifts on the published schedule.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                )
              else
                ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: upcomingShifts.length,
                  itemBuilder: (context, index) {
                    final shift = upcomingShifts[index];
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
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1034A6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.work_outline,
                              color: Color(0xFF1034A6),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shift.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${shift.timeRange} · ${shift.stationName}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _shortDate(shift.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
    required Color iconBgColor,
  }) {
    return Expanded(
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day} · ${_weekdays[d.weekday - 1]}';
}
