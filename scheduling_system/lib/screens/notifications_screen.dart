// screens/notifications_screen.dart
//
// Admin notification inbox. Surfaces attendance reports submitted by
// Head Guards (per the Phase 3 absence-handling flowchart: head guard
// submits report -> notify admin), loaded live from the backend.
// Tapping a notification opens the full report; "View All Reports"
// opens the Submitted Reports screen.

import 'package:flutter/material.dart';
import '../data/attendance_report_dummy_data.dart';
import '../models/absence_request.dart';
import '../models/attendance_report.dart';
import '../models/leave_request.dart';
import '../models/special_request.dart';
import '../services/api_service.dart';
import '../services/notification_center.dart';
import '../services/notification_settings.dart';
import 'absence_requests_tab.dart';
import 'leave_requests_tab.dart';
import 'special_requests_tab.dart';
import 'main_layout.dart';

class NotificationsContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data})? onNavigate;

  const NotificationsContent({
    super.key,
    this.onNavigate,
  });

  @override
  State<NotificationsContent> createState() => _NotificationsContentState();
}

class _NotificationsContentState extends State<NotificationsContent>
    with SingleTickerProviderStateMixin {
  List<AttendanceReport> _reports = [];
  bool _isLoading = true;
  // Set when the server can't be reached and we're showing sample data.
  String? _loadError;

  String _filter = 'All'; // All | Unread | With Absences

  // Four inboxes now live behind this one screen: the head-guard
  // attendance reports (tab 0, untouched), employee-filed emergency
  // absence requests (tab 1), special day-off requests (tab 2) and leave
  // requests (tab 3). The tab bar and page chrome live here; each tab
  // renders its own scrollable body.
  late final TabController _tabController;
  final GlobalKey<AbsenceRequestsTabState> _absenceTabKey =
      GlobalKey<AbsenceRequestsTabState>();
  final GlobalKey<SpecialRequestsTabState> _specialTabKey =
      GlobalKey<SpecialRequestsTabState>();
  final GlobalKey<LeaveRequestsTabState> _leaveTabKey =
      GlobalKey<LeaveRequestsTabState>();
  // Pending absence count, pushed up by the absence tab after each load
  // so the tab label and header badge reflect it without this screen
  // owning that list. Seeded by _loadPendingCounts() below — see there
  // for why the tab alone isn't enough.
  int _pendingAbsenceCount = 0;
  // Same, for the special day-off request tab.
  int _pendingSpecialCount = 0;
  // Same, for the leave request tab.
  int _pendingLeaveCount = 0;

  // Which tab is showing — drives the per-tab header subtitle, badge and
  // action buttons.
  bool get _onReports => _tabController.index == 0;
  bool get _onAbsences => _tabController.index == 1;
  bool get _onSpecials => _tabController.index == 2;
  bool get _onLeaves => _tabController.index == 3;

  @override
  void initState() {
    super.initState();
    // Rebuild the header chrome once the active tab settles so it matches
    // whichever inbox is on screen.
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging && mounted) setState(() {});
      });
    _loadReports();
    _loadPendingCounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Loads the submitted reports from the backend; falls back to sample
  // data (marked with a warning banner) if the server is down.
  Future<void> _loadReports() async {
    setState(() => _isLoading = true);

    final result = await ApiService.fetchAttendanceReports();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _reports = (result['reports'] as List).cast<AttendanceReport>();
        _loadError = null;
      } else {
        _reports = AttendanceReportDummyData.reports;
        _loadError =
            'Could not reach the server — showing sample notifications.';
      }
    });
  }

  // Seeds the three request badges without waiting for their tabs.
  //
  // TabBarView builds its children lazily, so an unvisited tab hasn't run
  // its own load yet and never reported a count — which is why the
  // Absence/Special/Leave badges used to stay blank until the admin
  // tapped the tab, reading as "nothing waiting" for an inbox that in
  // fact had pending items. Fetching the three lists here means the
  // badges are right the moment the screen opens; each tab still
  // overrides its own number once it loads or a decision is made.
  Future<void> _loadPendingCounts() async {
    final results = await Future.wait([
      ApiService.fetchAbsenceRequests(),
      ApiService.fetchSpecialRequests(),
      ApiService.fetchLeaveRequests(),
    ]);
    if (!mounted) return;

    final absence = results[0];
    final special = results[1];
    final leave = results[2];

    // A fetch that failed leaves that badge alone rather than zeroing it —
    // the same reasoning as NotificationCenter's per-inbox fallback.
    setState(() {
      if (absence['success'] == true) {
        _pendingAbsenceCount = (absence['requests'] as List)
            .cast<AbsenceRequest>()
            .where((r) => r.isPending)
            .length;
      }
      if (special['success'] == true) {
        _pendingSpecialCount = (special['requests'] as List)
            .cast<SpecialRequest>()
            .where((r) => r.isPending)
            .length;
      }
      if (leave['success'] == true) {
        _pendingLeaveCount = (leave['requests'] as List)
            .cast<LeaveRequest>()
            .where((r) => r.isPending)
            .length;
      }
    });
  }

  bool get _isLive => _loadError == null;

  int get _unreadCount => _reports.where((r) => !r.isRead).length;

  List<AttendanceReport> get _visibleReports {
    switch (_filter) {
      case 'Unread':
        return _reports.where((r) => !r.isRead).toList();
      case 'With Absences':
        return _reports.where((r) => r.hasAbsent).toList();
      default:
        return _reports;
    }
  }

  void _markAllAsRead() {
    setState(() {
      for (final r in _reports) {
        r.isRead = true;
      }
    });
    // Persist in the background; harmless if it fails, the next fetch
    // just shows them unread again. The center refresh drops the sidebar
    // badge right away instead of on the next poll.
    if (_isLive) {
      ApiService.markAllReportsRead()
          .then((_) => NotificationCenter.instance.refresh());
    }
  }

  void _openNotification(AttendanceReport report) {
    setState(() => report.isRead = true);
    if (_isLive) {
      ApiService.markReportRead(report.id)
          .then((_) => NotificationCenter.instance.refresh());
    }
    widget.onNavigate?.call(
      ScreenType.submittedReportDetail,
      data: report,
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the Settings → Allow Notifications switch changes,
    // so the inbox mutes/unmutes live.
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationSettings.allowNotifications,
      builder: (context, allowed, _) => Container(
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
            // The title and the three action controls don't fit side by side
            // on a narrow window — below ~950px they stack instead, so the
            // title never gets squeezed to nothing (which used to wrap it
            // into a tower and blow the header out of the screen).
            child: LayoutBuilder(builder: (context, constraints) {
              final bool stack = constraints.maxWidth < 950;
              final Widget titleBlock = Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => widget.onNavigate?.call(ScreenType.dashboard),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Notifications',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          // Reports tab keeps its unread-reports badge.
                          if (_onReports && _unreadCount > 0 && allowed) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$_unreadCount new',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          // Absence and special tabs each show an amber
                          // pending-count badge for their own inbox.
                          if (_onAbsences &&
                              _pendingAbsenceCount > 0 &&
                              allowed)
                            _buildPendingBadge(_pendingAbsenceCount),
                          if (_onSpecials &&
                              _pendingSpecialCount > 0 &&
                              allowed)
                            _buildPendingBadge(_pendingSpecialCount),
                          if (_onLeaves && _pendingLeaveCount > 0 && allowed)
                            _buildPendingBadge(_pendingLeaveCount),
                        ],
                      ),
                      Text(
                        _onReports
                            ? 'Attendance reports submitted by head guards'
                            : _onAbsences
                                ? 'Emergency absence requests from employees'
                                : _onSpecials
                                    ? 'Special day-off requests from employees'
                                    : 'Leave requests from employees, and leave recorded by the admin',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              );

              // Reports keeps its full action set; the absence tab only
              // needs a refresh (approve/deny live on each card).
              final Widget actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: _onReports
                    ? [
                        IconButton(
                          // Refreshing from the reports tab also re-counts
                          // the other three inboxes, so their badges keep up
                          // without the admin having to open each tab.
                          onPressed: _isLoading
                              ? null
                              : () {
                                  _loadReports();
                                  _loadPendingCounts();
                                },
                          tooltip: 'Refresh',
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFF1034A6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _unreadCount == 0 ? null : _markAllAsRead,
                          icon: const Icon(Icons.done_all, size: 18),
                          label: const Text('Mark all as read'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1034A6),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => widget.onNavigate
                              ?.call(ScreenType.submittedReports),
                          icon: const Icon(Icons.assignment_outlined, size: 18),
                          label: const Text('View All Reports'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1034A6),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ]
                    : [
                        IconButton(
                          onPressed: () {
                            if (_onAbsences) {
                              _absenceTabKey.currentState?.reload();
                            } else if (_onSpecials) {
                              _specialTabKey.currentState?.reload();
                            } else {
                              _leaveTabKey.currentState?.reload();
                            }
                          },
                          tooltip: 'Refresh',
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFF1034A6),
                          ),
                        ),
                      ],
              );

              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleBlock,
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: actions,
                    ),
                  ],
                );
              }
              return Row(
                children: [Expanded(child: titleBlock), actions],
              );
            }),
          ),

          // Tab bar between the header and the two inbox bodies; hidden
          // while notifications are muted so the muted card owns the area.
          if (allowed) _buildTabBar(),

          // Content — muted entirely when notifications are turned off
          // in Settings.
          Expanded(
            child: !allowed
                ? _buildMutedState()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 0 — existing head-guard attendance reports.
                      _buildReportsBody(),
                      // Tab 1 — employee-filed emergency absence requests.
                      AbsenceRequestsTab(
                        key: _absenceTabKey,
                        onNavigate: widget.onNavigate,
                        onPendingCountChanged: (count) {
                          if (!mounted) return;
                          setState(() => _pendingAbsenceCount = count);
                        },
                      ),
                      // Tab 2 — employee-filed special day-off requests.
                      SpecialRequestsTab(
                        key: _specialTabKey,
                        onPendingCountChanged: (count) {
                          if (!mounted) return;
                          setState(() => _pendingSpecialCount = count);
                        },
                      ),
                      // Tab 3 — leave requests, filed by employees or
                      // recorded by the admin from Employee Details.
                      LeaveRequestsTab(
                        key: _leaveTabKey,
                        onPendingCountChanged: (count) {
                          if (!mounted) return;
                          setState(() => _pendingLeaveCount = count);
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
      ),
    );
  }

  // The two-inbox tab bar. Blue primary to match the app; the absence
  // tab carries an amber pending count when something is waiting.
  Widget _buildTabBar() {
    return Material(
      color: Colors.white,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        controller: _tabController,
        labelColor: const Color(0xFF1034A6),
        unselectedLabelColor: const Color(0xFF64748B),
        indicatorColor: const Color(0xFF1034A6),
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: [
          const Tab(text: 'Attendance Reports'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Absence Requests'),
                if (_pendingAbsenceCount > 0)
                  _buildTabCountBadge(_pendingAbsenceCount),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Special Requests'),
                if (_pendingSpecialCount > 0)
                  _buildTabCountBadge(_pendingSpecialCount),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Leave Requests'),
                if (_pendingLeaveCount > 0)
                  _buildTabCountBadge(_pendingLeaveCount),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Small amber count bubble next to a tab label when that inbox has
  // items waiting on the admin.
  Widget _buildTabCountBadge(int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // The amber "N pending" pill shown in the page header for whichever
  // request inbox is active.
  Widget _buildPendingBadge(int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$count pending',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // Tab 0 body — the head-guard attendance-report inbox, unchanged from
  // the original single-tab layout, just relocated into its own tab.
  Widget _buildReportsBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1034A6)),
      );
    }
    return SingleChildScrollView(
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
                border: Border.all(color: const Color(0xFFD97706)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      size: 18, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadError!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF92400E)),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadReports,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],

          // Filter chips
          Row(
            children: [
              _buildFilterChip('All', _reports.length),
              const SizedBox(width: 8),
              _buildFilterChip('Unread', _unreadCount),
              const SizedBox(width: 8),
              _buildFilterChip(
                'With Absences',
                _reports.where((r) => r.hasAbsent).length,
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_visibleReports.isEmpty)
            _buildEmptyState()
          else
            ..._visibleReports.map((r) => _buildNotificationCard(r)),
        ],
      ),
    );
  }

  // Shown instead of the inbox when Settings → Allow Notifications is off.
  Widget _buildMutedState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_paused_rounded,
              size: 48,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 12),
            Text(
              'Notifications are turned off',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Turn them back on to see attendance reports and absence '
              'requests here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => NotificationSettings.setAllowed(true),
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: const Text('Turn On Notifications'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1034A6),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _filter == label;
    return InkWell(
      onTap: () => setState(() => _filter = label),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1034A6) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF1034A6) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 48,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text(
            'No notifications here',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Reports submitted by head guards will appear here.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(AttendanceReport report) {
    final hasAbsent = report.hasAbsent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: report.isRead ? Colors.white : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openNotification(report),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: report.isRead
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFBFDBFE),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasAbsent
                        ? Colors.red.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasAbsent
                        ? Icons.warning_amber_rounded
                        : Icons.assignment_turned_in_outlined,
                    color: hasAbsent ? Colors.red[400] : Colors.green[600],
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Attendance Report Submitted',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: report.isRead
                                    ? FontWeight.w600
                                    : FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _timeAgo(report.submittedAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (!report.isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1034A6),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${report.headGuardName} submitted the '
                        '${report.shiftTitle.toLowerCase()} report for '
                        '${report.station} — ${report.shiftDate}.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Present / absent summary pills
                      Row(
                        children: [
                          _buildSummaryPill(
                            icon: Icons.check_circle,
                            color: Colors.green,
                            label: '${report.presentCount} Present',
                          ),
                          const SizedBox(width: 8),
                          _buildSummaryPill(
                            icon: Icons.cancel,
                            color: hasAbsent ? Colors.red : Colors.grey,
                            label: '${report.absentCount} Absent',
                          ),
                          const Spacer(),
                          Text(
                            'View report',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1034A6).withOpacity(0.9),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFF1034A6),
                          ),
                        ],
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

  Widget _buildSummaryPill({
    required IconData icon,
    required MaterialColor color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color[600]),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color[700],
            ),
          ),
        ],
      ),
    );
  }
}
