// screens/securityguardui/security_guard_layout.dart
import 'package:flutter/material.dart';
import '../../models/absence_request.dart';
import '../../models/employee.dart';
import '../../models/guard_shift.dart';
import '../../models/leave_request.dart';
import '../../services/api_service.dart';
import '../../services/notification_center.dart';
import '../../widgets/notification_badge.dart';
import 'security_dashboard_screen.dart';
import 'security_schedule_screen.dart';
import 'security_alerts_screen.dart';
import 'security_profile_screen.dart';

class SecurityGuardLayout extends StatefulWidget {
  final String username;

  const SecurityGuardLayout({
    super.key,
    required this.username,
  });

  @override
  State<SecurityGuardLayout> createState() => _SecurityGuardLayoutState();
}

class _SecurityGuardLayoutState extends State<SecurityGuardLayout> {
  int _currentIndex = 0;

  Employee? _employee;
  List<GuardShift> _shifts = [];
  List<GuardPeriod> _periods = [];
  // Owned here so the dashboard's duty status and the absence card can't
  // disagree about whether this guard is excused today.
  List<AbsenceRequest> _absenceRequests = [];
  // Same reason, for leave — the duty clock ranks an approved leave above
  // every other status, so it has to resolve against the same list the
  // Request cards are showing.
  List<LeaveRequest> _leaves = [];
  bool _loading = true;
  String? _error;

  // Alerts tab position in the bottom bar, used by the badge and the
  // popup's View action.
  static const int _alertsIndex = 2;

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

  // Loads the guard's record, their published shifts and their absence
  // requests. A schedule failure isn't fatal — the screens just show "no
  // schedule yet"; an absence failure just means nothing shows as excused.
  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.fetchEmployee(widget.username),
      ApiService.fetchEmployeeSchedule(widget.username),
      ApiService.fetchEmployeeAbsenceRequests(widget.username),
      ApiService.fetchEmployeeLeaveRequests(widget.username),
    ]);

    if (!mounted) return;

    final empResult = results[0];
    final schedResult = results[1];
    final absenceResult = results[2];
    final leaveResult = results[3];

    if (empResult["success"] != true) {
      setState(() {
        _loading = false;
        _error = empResult["error"]?.toString() ?? 'Failed to load profile';
      });
      return;
    }

    setState(() {
      _employee = empResult["employee"];
      _shifts = schedResult["success"] == true
          ? schedResult["shifts"]
          : <GuardShift>[];
      _periods = schedResult["success"] == true
          ? schedResult["periods"]
          : <GuardPeriod>[];
      _absenceRequests = absenceResult["success"] == true
          ? (absenceResult["requests"] as List).cast<AbsenceRequest>()
          : <AbsenceRequest>[];
      _leaves = leaveResult["success"] == true
          ? (leaveResult["requests"] as List).cast<LeaveRequest>()
          : <LeaveRequest>[];
      _loading = false;
    });
  }

  // Refresh after the guard files an absence — same fetch, but without
  // blanking the screen behind a spinner.
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
      SecurityDashboardScreen(
        employee: _employee!,
        shifts: _shifts,
        periods: _periods,
        absenceRequests: _absenceRequests,
        leaves: _leaves,
        onDataChanged: _refreshQuietly,
      ),
      SecurityScheduleScreen(
        employee: _employee!,
        shifts: _shifts,
        periods: _periods,
      ),
      SecurityAlertsScreen(username: widget.username),
      SecurityProfileScreen(employee: _employee!),
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
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.dashboard_outlined, 'Dashboard', 0),
                _buildNavItem(Icons.calendar_today_outlined, 'Schedule', 1),
                _buildNavItem(Icons.notifications_outlined, 'Alerts',
                    _alertsIndex, badge: true),
                _buildNavItem(Icons.person_outline, 'Profile', 3),
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
      size: 24,
    );
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1034A6).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge ? NotificationBadge(child: iconWidget) : iconWidget,
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF1034A6) : Colors.grey[400],
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
