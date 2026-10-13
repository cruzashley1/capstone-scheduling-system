import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../models/employee.dart';
import '../models/station.dart';
import '../models/schedule.dart';
import 'dashboard_screen.dart';
import 'available_management_screen.dart';
import 'absent_management_screen.dart';
import 'employee_list_screen.dart';
import 'station_management_screen.dart';
import 'station_detail_screen.dart';
import 'employee_detail_screen.dart';
import 'schedule_management_screen.dart';
import 'schedule_detail_screen.dart';
import 'auto_scheduler_screen.dart';
import 'notifications_screen.dart';
import 'submitted_reports_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'approval_screen.dart';
import 'official_accounts_screen.dart';
import 'find_replacement_screen.dart';
import '../models/attendance_report.dart';
import '../models/replacement.dart';
import '../services/notification_center.dart';

enum ScreenType {
  approvals,
  officialAccounts,
  dashboard,
  employeeList,
  employeeDetail,
  stationManagement,
  stationDetail,
  scheduleManagement,
  scheduleDetail,
  autoScheduler,
  notifications,
  submittedReports,
  submittedReportDetail,
  reports,
  settings,
  availableManagement,
  absentManagement,
  findReplacement,
}

// Navigation payload for the Employee Detail screen when it's opened
// from somewhere other than the employee list (e.g. a replacement
// candidate card) — remembers where "back" should go and with what data.
class EmployeeDetailNav {
  final Employee employee;
  final ScreenType returnTo;
  final dynamic returnData;

  const EmployeeDetailNav({
    required this.employee,
    required this.returnTo,
    this.returnData,
  });
}

class MainLayout extends StatefulWidget {
  // Username of the logged-in admin, used by screens that call
  // account-level endpoints (e.g. Settings → Change Password).
  final String username;
  const MainLayout({super.key, this.username = 'admin'});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  ScreenType _currentScreen = ScreenType.dashboard;
  dynamic _screenData;

  @override
  void initState() {
    super.initState();
    // Live alert polling: badge on the sidebar's Notifications item +
    // popup when a head guard submits a new attendance report.
    NotificationCenter.instance.startForAdmin();
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
          width: 420,
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
            onPressed: () => _navigateTo(ScreenType.notifications),
          ),
        ),
      );
  }

  void _navigateTo(ScreenType screen, {dynamic data}) {
    setState(() {
      _currentScreen = screen;
      _screenData = data;
    });
  }

  // Matches the Sidebar's actual item indices:
  // 0 Dashboard, 1 Security Management, 2 Station Management,
  // 3 Schedule Management, 4 Generate Schedule, 5 Notifications,
  // 6 Reports, 7 Settings (bottom item).
  int _getSelectedIndex() {
    switch (_currentScreen) {
      case ScreenType.approvals:
        return 8;
      case ScreenType.officialAccounts:
        return 9;
      case ScreenType.dashboard:
        return 0;
      case ScreenType.availableManagement:
      case ScreenType.absentManagement:
        return 0;
      // Highlight Notifications when the flow started from a submitted
      // report, otherwise Dashboard (came from Absent Today).
      case ScreenType.findReplacement:
        final data = _screenData;
        return (data is ReplacementRequest && data.report != null) ? 5 : 0;
      case ScreenType.employeeList:
      case ScreenType.employeeDetail:
        return 1;
      case ScreenType.stationManagement:
      case ScreenType.stationDetail:
        return 2;
      case ScreenType.scheduleManagement:
      case ScreenType.scheduleDetail:
        return 3;
      case ScreenType.autoScheduler:
        return 4;
      case ScreenType.notifications:
      case ScreenType.submittedReports:
      case ScreenType.submittedReportDetail:
        return 5;
      case ScreenType.reports:
        return 6;
      case ScreenType.settings:
        return 7;
    }
  }

  void _handleSidebarNavigation(int index) {
    switch (index) {
      case 8:
        _navigateTo(ScreenType.approvals);
        break;
      case 9:
        _navigateTo(ScreenType.officialAccounts);
        break;
      case 0:
        _navigateTo(ScreenType.dashboard);
        break;
      case 1:
        _navigateTo(ScreenType.employeeList);
        break;
      case 2:
        _navigateTo(ScreenType.stationManagement);
        break;
      case 3:
        _navigateTo(ScreenType.scheduleManagement);
        break;
      case 4:
        _navigateTo(ScreenType.autoScheduler);
        break;
      case 5:
        _navigateTo(ScreenType.notifications);
        break;
      case 6:
        _navigateTo(ScreenType.reports);
        break;
      case 7:
        _navigateTo(ScreenType.settings);
        break;
    }
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case ScreenType.approvals:
        return ApprovalScreen(role: 'admin', initialPeriod: _screenData as String?);
      case ScreenType.officialAccounts:
        return const OfficialAccountsScreen();
      case ScreenType.dashboard:
        return DashboardContent(onNavigate: _navigateTo);

      case ScreenType.availableManagement:
        return AvailableManagementContent(onNavigate: _navigateTo);

      case ScreenType.absentManagement:
        return AbsentManagementContent(onNavigate: _navigateTo);

      case ScreenType.employeeList:
        return EmployeeListContent(onNavigate: _navigateTo);

      case ScreenType.employeeDetail:
        // Opened from a replacement candidate card: back returns to the
        // Find Replacement screen with its context intact.
        if (_screenData is EmployeeDetailNav) {
          final nav = _screenData as EmployeeDetailNav;
          return EmployeeDetailScreen(
            employee: nav.employee,
            onBack: () => _navigateTo(nav.returnTo, data: nav.returnData),
            onNavigate: _navigateTo,
          );
        }
        return EmployeeDetailScreen(
          employee: _screenData as Employee,
          onBack: () => _navigateTo(ScreenType.employeeList),
          onNavigate: _navigateTo,
        );

      case ScreenType.stationManagement:
        return StationManagementContent(onNavigate: _navigateTo);

      case ScreenType.stationDetail:
        return StationDetailContent(
          station: _screenData as Station,
          onNavigate: _navigateTo,
        );

      case ScreenType.scheduleManagement:
        return ScheduleManagementContent(onNavigate: _navigateTo);

      case ScreenType.scheduleDetail:
        return ScheduleDetailScreen(
          schedule: _screenData as Schedule,
          onBack: () => _navigateTo(ScreenType.scheduleManagement),
          onNavigate: _navigateTo,
        );

      case ScreenType.autoScheduler:
        // onNavigate is what the preview's View / Review & Publish
        // buttons use to reach Schedule Management — without it they
        // silently do nothing.
        return AutoSchedulerContent(onNavigate: _navigateTo);

      case ScreenType.notifications:
        return NotificationsContent(onNavigate: _navigateTo);

      case ScreenType.submittedReports:
        return SubmittedReportsContent(onNavigate: _navigateTo);

      case ScreenType.submittedReportDetail:
        return SubmittedReportDetailContent(
          report: _screenData as AttendanceReport,
          onNavigate: _navigateTo,
        );

      case ScreenType.findReplacement:
        return FindReplacementScreen(
          request: _screenData as ReplacementRequest,
          onNavigate: _navigateTo,
        );

      case ScreenType.reports:
        return const ReportsContent();
      case ScreenType.settings:
        return SettingsContent(
          onNavigate: _navigateTo,
          username: widget.username,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(
            selectedIndex: _getSelectedIndex(),
            onItemSelected: _handleSidebarNavigation,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Container(
                key: ValueKey<ScreenType>(_currentScreen),
                child: _buildCurrentScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}