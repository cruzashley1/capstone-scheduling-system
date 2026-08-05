// screens/headguardui/head_guard_layout.dart
import 'package:flutter/material.dart';
import '../../models/absence_request.dart';
import '../../models/employee.dart';
import '../../models/guard_shift.dart';
import '../../models/leave_request.dart';
import '../../models/station_roster.dart';
import '../../services/api_service.dart';
import '../../services/duty_clock.dart';
import '../../services/server_clock.dart';
import '../../services/notification_center.dart';
import '../../widgets/notification_badge.dart';
import 'headguard_dashboard_screen.dart';
import 'headguard_schedule_screen.dart';
import 'headguard_report_screen.dart';
import 'headguard_profile_screen.dart';
import '../securityguardui/security_alerts_screen.dart';

class HeadGuardLayout extends StatefulWidget {
  final String username;

  const HeadGuardLayout({
    super.key,
    required this.username,
  });

  @override
  State<HeadGuardLayout> createState() => _HeadGuardLayoutState();
}

class _HeadGuardLayoutState extends State<HeadGuardLayout> {
  int _currentIndex = 0;

  Employee? _employee;
  List<GuardShift> _shifts = [];
  List<GuardPeriod> _periods = [];
  StationRoster? _roster;
  // Owned here so the dashboard's duty status and the absence card can't
  // disagree about whether this head guard is excused today.
  List<AbsenceRequest> _absenceRequests = [];
  // Same reason as the absences: the duty clock ranks an approved leave
  // above every other status, so it has to resolve against the same list
  // the Request cards are showing.
  List<LeaveRequest> _leaves = [];
  bool _loading = true;
  String? _error;

  // Alerts tab position in the bottom bar, used by the badge and the
  // popup's View action.
  static const int _alertsIndex = 3;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Live alert polling: badge on the Alerts tab + popup when a new
    // notification arrives while the app is open.
    NotificationCenter.instance.startForEmployee(widget.username);
    NotificationCenter.instance.onPopup = _showNotificationPopup;
  }

  @override
  void dispose() {
    // Still owning the popup hook means no logout/new layout took over —
    // shut the polling down with this layout.
    if (NotificationCenter.instance.onPopup == _showNotificationPopup) {
      NotificationCenter.instance.stop();
    }
    super.dispose();
  }

  void _showNotificationPopup(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
          duration: const Duration(seconds: 5),
          // A SnackBar with an action defaults to persist:true (stays until
          // dismissed). Force false so it auto-hides after the 5s duration.
          persist: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Color(0xFF60A5FA), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: const Color(0xFF60A5FA),
            onPressed: () => setState(() => _currentIndex = _alertsIndex),
          ),
        ),
      );
  }

  // Loads the head guard's record, their published shifts, today's station
  // roster and their absence requests. Only a profile failure is fatal —
  // the other screens just show "no schedule yet" states, and an absence
  // failure just means nothing shows as excused.
  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.fetchEmployee(widget.username),
      ApiService.fetchEmployeeSchedule(widget.username),
      ApiService.fetchStationOverview(widget.username),
      ApiService.fetchEmployeeAbsenceRequests(widget.username),
      ApiService.fetchEmployeeLeaveRequests(widget.username),
    ]);

    if (!mounted) return;

    final empResult = results[0];
    final schedResult = results[1];
    final rosterResult = results[2];
    final absenceResult = results[3];
    final leaveResult = results[4];

    if (empResult["success"] != true) {
      setState(() {
        _loading = false;
        _error = empResult["error"]?.toString() ?? 'Failed to load profile';
      });
      return;
    }

    final shifts = schedResult["success"] == true
        ? schedResult["shifts"] as List<GuardShift>
        : <GuardShift>[];

    setState(() {
      _employee = empResult["employee"];
      _shifts = shifts;
      _periods = schedResult["success"] == true
          ? schedResult["periods"]
          : <GuardPeriod>[];
      _roster = rosterResult["success"] == true ? rosterResult["roster"] : null;
      _absenceRequests = absenceResult["success"] == true
          ? (absenceResult["requests"] as List).cast<AbsenceRequest>()
          : <AbsenceRequest>[];
      _leaves = leaveResult["success"] == true
          ? (leaveResult["requests"] as List).cast<LeaveRequest>()
          : <LeaveRequest>[];
      _loading = false;
    });

    await _syncRosterToDutyDay(shifts);
  }

  // A night head guard's duty runs 1700H - 0500H, so between midnight and
  // time-out the roster they are actually working is YESTERDAY's — that
  // is the one the Report screen has to show and file against. The
  // parallel fetch above always asks for today, which is right for
  // everyone else, so only re-fetch in that narrow window.
  Future<void> _syncRosterToDutyDay(List<GuardShift> shifts) async {
    final dutyDate = DutyClock.activeDutyDate(shifts: shifts);
    if (dutyDate == DutyClock.dateOnly(ServerClock.now())) return;

    final result = await ApiService.fetchStationOverview(
      widget.username,
      date: DutyClock.iso(dutyDate),
    );
    if (!mounted || result["success"] != true) return;
    setState(() => _roster = result["roster"]);
  }

  // Refresh after the head guard files an absence — same fetch, but
  // without blanking the screen behind a spinner.
  Future<void> _refreshQuietly() async {
    final results = await Future.wait([
      ApiService.fetchEmployeeSchedule(widget.username),
      ApiService.fetchEmployeeAbsenceRequests(widget.username),
      ApiService.fetchEmployeeLeaveRequests(widget.username),
    ]);
    if (!mounted) return;

    final schedResult = results[0];
    final absenceResult = results[1];
    final leaveResult = results[2];

    setState(() {
      if (schedResult["success"] == true) {
        _shifts = schedResult["shifts"];
        _periods = schedResult["periods"];
      }
      if (absenceResult["success"] == true) {
        _absenceRequests =
            (absenceResult["requests"] as List).cast<AbsenceRequest>();
      }
      if (leaveResult["success"] == true) {
        _leaves = (leaveResult["requests"] as List).cast<LeaveRequest>();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1034A6)),
        ),
      );
    }

    if (_error != null || _employee == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Could not load your profile',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error ?? 'Unknown error',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1034A6),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final screens = [
      HeadGuardDashboardScreen(
        employee: _employee!,
        shifts: _shifts,
        periods: _periods,
        absenceRequests: _absenceRequests,
        leaves: _leaves,
        roster: _roster,
        onDataChanged: _refreshQuietly,
      ),
      HeadGuardScheduleScreen(
        employee: _employee!,
        shifts: _shifts,
        periods: _periods,
      ),
      HeadGuardReportScreen(
        employee: _employee!,
        roster: _roster,
      ),
      // Reuses the guard Alerts screen, which now shows this user's REAL
      // notifications (e.g. substitute HGs assigned to cover an absence).
      SecurityAlertsScreen(username: widget.username),
      HeadGuardProfileScreen(employee: _employee!),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: const Color(0xFF1034A6),
        child: screens[_currentIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.dashboard_outlined, 'Dashboard', 0),
                _buildNavItem(Icons.calendar_today_outlined, 'Schedule', 1),
                _buildNavItem(Icons.assignment_outlined, 'Report', 2),
                _buildNavItem(Icons.notifications_outlined, 'Alerts',
                    _alertsIndex, badge: true),
                _buildNavItem(Icons.person_outline, 'Profile', 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index,
      {bool badge = false}) {
    final isSelected = _currentIndex == index;
    final Widget iconWidget = Icon(
      icon,
      color: isSelected ? const Color(0xFF1034A6) : Colors.grey[400],
      size: 22,
    );
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1034A6).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge ? NotificationBadge(child: iconWidget) : iconWidget,
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF1034A6) : Colors.grey[400],
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
