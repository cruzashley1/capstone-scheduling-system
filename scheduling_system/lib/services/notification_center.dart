// services/notification_center.dart
//
// In-app alert hub shared by every role. Polls the backend for the
// signed-in user's notifications (guards/head guards read
// `employee_notifications`; the admin reads attendance reports,
// emergency absence requests, leave requests and approval alerts), keeps a live unread
// count that drives
// the nav badges, and raises a popup callback when something new
// arrives while the app is open — so a notification is announced
// instead of sitting silently in the inbox.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/absence_request.dart';
import '../models/attendance_report.dart';
import '../models/employee_notification.dart';
import '../models/leave_request.dart';
import '../models/schedule_approval.dart';
import 'api_service.dart';
import 'notification_settings.dart';

class NotificationCenter {
  NotificationCenter._();

  static final NotificationCenter instance = NotificationCenter._();

  static const _pollInterval = Duration(seconds: 30);

  /// Live unread count for the current user; nav badges listen to this.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Set by the active layout to surface a popup (SnackBar). Cleared on
  /// dispose so a dead context is never used.
  void Function(String title, String message)? onPopup;

  Timer? _timer;
  String? _employeeId; // null while in admin mode
  bool _adminMode = false;
  bool _primed = false;
  bool _fetching = false;
  final Set<String> _knownIds = {};
  // Last good per-half contribution to the admin badge, so a one-endpoint
  // blip keeps the failed half's number instead of collapsing it to zero.
  int _lastUnreadReports = 0;
  int _lastPendingRequests = 0;
  int _lastPendingLeaves = 0;
  int _lastUnreadApprovals = 0;

  /// Starts polling a guard / head guard / reliever inbox.
  void startForEmployee(String employeeId) {
    _start(employeeId: employeeId, admin: false);
  }

  /// Starts polling the admin inbox (attendance reports).
  void startForAdmin() {
    _start(employeeId: null, admin: true);
  }

  void _start({required String? employeeId, required bool admin}) {
    // Same user resuming (e.g. layout rebuilt) keeps its seen-state so
    // old alerts aren't re-announced.
    final sameUser =
        admin == _adminMode && employeeId == _employeeId && _timer != null;
    if (!sameUser) {
      _knownIds.clear();
      _primed = false;
      _lastUnreadReports = 0;
      _lastPendingRequests = 0;
      _lastPendingLeaves = 0;
      _lastUnreadApprovals = 0;
      unreadCount.value = 0;
    }
    _employeeId = employeeId;
    _adminMode = admin;
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => refresh());
    refresh();
  }

  /// Stops polling and forgets the user (logout / layout disposed).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _employeeId = null;
    _adminMode = false;
    _primed = false;
    _knownIds.clear();
    _lastUnreadReports = 0;
    _lastPendingRequests = 0;
    _lastPendingLeaves = 0;
    _lastUnreadApprovals = 0;
    unreadCount.value = 0;
    onPopup = null;
  }

  /// Fetches the inbox now — also called by the screens right after a
  /// mark-as-read so the badge drops immediately instead of waiting for
  /// the next poll.
  Future<void> refresh() async {
    if (_fetching || (_employeeId == null && !_adminMode)) return;
    _fetching = true;
    try {
      if (_adminMode) {
        await _refreshAdmin();
      } else {
        await _refreshEmployee(_employeeId!);
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _refreshEmployee(String employeeId) async {
    final result = await ApiService.fetchEmployeeNotifications(employeeId);
    if (result['success'] != true || _employeeId != employeeId) return;

    final notifications =
        (result['notifications'] as List).cast<EmployeeNotification>();
    unreadCount.value = notifications.where((n) => !n.isRead).length;

    _announce(
      newItems: notifications
          .where((n) => !_knownIds.contains(n.id))
          .map((n) => (title: n.title, message: n.message))
          .toList(),
      allIds: notifications.map((n) => n.id),
      unread: unreadCount.value,
    );
  }

  // Attendance reports, absence requests, leave requests and approval alerts
  // contribute to the admin's Notifications badge and in-app announcements.
  Future<void> _refreshAdmin() async {
    final results = await Future.wait([
      ApiService.fetchAttendanceReports(),
      ApiService.fetchAbsenceRequests(),
      ApiService.fetchLeaveRequests(),
      ApiService.workflow('/workflow-notifications'),
    ]);
    if (!_adminMode) return;

    final reportsResult = results[0];
    final absenceResult = results[1];
    final leaveResult = results[2];
    final approvalResult = results[3];

    // Degrade gracefully: a failed fetch must not wipe the others'
    // count, so we only fold in whichever fetch succeeded and skip the
    // rest of that part (its ids stay in _knownIds, nothing re-announced).
    final reportsOk = reportsResult['success'] == true;
    final absenceOk = absenceResult['success'] == true;
    final leaveOk = leaveResult['success'] == true;
    final approvalOk = approvalResult['success'] == true;
    if (!reportsOk && !absenceOk && !leaveOk && !approvalOk) return;
    final approvals = approvalOk
        ? approvalMaps(approvalResult['notifications'])
        : const <Map<String, dynamic>>[];

    final reports = reportsOk
        ? (reportsResult['reports'] as List).cast<AttendanceReport>()
        : const <AttendanceReport>[];
    final requests = absenceOk
        ? (absenceResult['requests'] as List).cast<AbsenceRequest>()
        : const <AbsenceRequest>[];
    final leaves = leaveOk
        ? (leaveResult['requests'] as List).cast<LeaveRequest>()
        : const <LeaveRequest>[];

    // Unread reports and approvals join pending absence and leave requests
    // in the badge, since they all live behind the same sidebar
    // Notifications item. A part that failed this poll keeps its previous
    // contribution instead of collapsing to zero, so a one-endpoint blip
    // never lowers the badge.
    final unreadReports =
        reportsOk ? reports.where((r) => !r.isRead).length : _lastUnreadReports;
    final pendingRequests = absenceOk
        ? requests.where((a) => a.isPending).length
        : _lastPendingRequests;
    final pendingLeaves = leaveOk
        ? leaves.where((l) => l.isPending).length
        : _lastPendingLeaves;
    _lastUnreadReports = unreadReports;
    _lastPendingRequests = pendingRequests;
    _lastPendingLeaves = pendingLeaves;
    if (approvalOk) {
      _lastUnreadApprovals = approvals.where((n) => n['isRead'] != true).length;
    }
    unreadCount.value = unreadReports + pendingRequests + pendingLeaves + _lastUnreadApprovals;

    // Combine every id set so the seen-state logic keeps working and
    // nothing is announced twice across the inboxes.
    final newItems = <({String title, String message})>[
      ...approvals.where((n) => n['isRead'] != true && !_knownIds.contains('approval:${n['id']}'))
          .map((n) => (title: n['title'].toString(), message: n['message'].toString())),
      ...reports.where((r) => !_knownIds.contains(r.id)).map((r) => (
            title: 'Attendance Report Submitted',
            message: '${r.headGuardName} submitted the '
                '${r.shiftTitle.toLowerCase()} report for ${r.station}.',
          )),
      ...requests.where((a) => !_knownIds.contains(a.id)).map((a) => (
            title: 'Emergency Absence Request',
            message: '${a.employeeName} requested to be absent '
                'on ${a.displayDate}.',
          )),
      // Only leave the employee actually filed and that still awaits a
      // decision is worth announcing — leave the admin recorded from
      // Employee Details would be announcing their own action back to them.
      ...leaves
          .where((l) =>
              l.isPending && !l.isAdminRecorded && !_knownIds.contains(l.id))
          .map((l) => (
                title: 'New Leave Request',
                message: '${l.employeeName} requested a ${l.leaveType} for '
                    '${l.rangeLabel} (${l.days} days).',
              )),
    ];

    final allIds = <String>[
      ...approvals.map((n) => 'approval:${n['id']}'),
      ...reports.map((r) => r.id),
      ...requests.map((a) => a.id),
      ...leaves.map((l) => l.id),
    ];
    // A part that failed this poll returned no ids; keep the previously
    // seen ones so it isn't re-announced as "new" when it recovers.
    if (!reportsOk || !absenceOk || !leaveOk || !approvalOk) {
      allIds.addAll(_knownIds);
    }

    _announce(
      newItems: newItems,
      allIds: allIds,
      unread: unreadCount.value,
    );
  }

  // First fetch after login announces the unread backlog once; later
  // fetches announce only items that appeared while the app was open.
  void _announce({
    required List<({String title, String message})> newItems,
    required Iterable<String> allIds,
    required int unread,
  }) {
    final wasPrimed = _primed;
    _primed = true;
    _knownIds
      ..clear()
      ..addAll(allIds);

    if (!NotificationSettings.allowNotifications.value) return;
    final popup = onPopup;
    if (popup == null) return;

    if (!wasPrimed) {
      if (unread > 0) {
        popup(
          unread == 1 ? '1 unread notification' : '$unread unread notifications',
          'Tap to review what you missed.',
        );
      }
      return;
    }

    if (newItems.isEmpty) return;
    if (newItems.length == 1) {
      popup(newItems.first.title, newItems.first.message);
    } else {
      popup('${newItems.length} new notifications',
          'Tap to see what just arrived.');
    }
  }
}
