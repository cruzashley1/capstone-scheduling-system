// screens/securityguardui/security_alerts_screen.dart
//
// UPDATED: now loads the logged-in guard's real notifications from the
// backend (`employee_notifications` collection) instead of hardcoded
// dummy data — this is where the "Sudden Duty Call" notice lands when
// the admin assigns this guard to cover an absent colleague.
// Tapping a notification opens a bottom sheet with its full details.
import 'package:flutter/material.dart';
import '../../models/employee_notification.dart';
import '../../services/api_service.dart';
import '../../services/notification_center.dart';
import '../../services/notification_settings.dart';

class SecurityAlertsScreen extends StatefulWidget {
  // Username = employee document ID, same value the layout logs in with.
  final String username;

  const SecurityAlertsScreen({super.key, required this.username});

  @override
  State<SecurityAlertsScreen> createState() => _SecurityAlertsScreenState();
}

class _SecurityAlertsScreenState extends State<SecurityAlertsScreen> {
  List<EmployeeNotification> _notifications = [];
  bool _isLoading = true;
  String? _loadError;

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final result =
        await ApiService.fetchEmployeeNotifications(widget.username);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _notifications =
            (result['notifications'] as List).cast<EmployeeNotification>();
      } else {
        _loadError = result['error']?.toString() ?? 'Failed to load';
      }
    });
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (final n in _notifications) {
        n.isRead = true;
      }
    });
    // Fire-and-forget: the local state is already updated. The center
    // refresh drops the nav badge right away instead of on the next poll.
    await ApiService.markAllNotificationsRead(widget.username);
    await NotificationCenter.instance.refresh();
  }

  Future<void> _markRead(EmployeeNotification notification) async {
    if (notification.isRead) return;
    setState(() => notification.isRead = true);
    await ApiService.markNotificationRead(notification.id);
    await NotificationCenter.instance.refresh();
  }

  // Tap: mark read and show the full notification in a bottom sheet.
  void _openNotification(EmployeeNotification notification) {
    _markRead(notification);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NotificationDetailSheet(
        notification: notification,
        icon: _iconFor(notification.type),
        color: _colorFor(notification.type),
      ),
    );
  }

  // Same icon/color conventions the dummy list used, keyed by type.
  IconData _iconFor(String type) {
    switch (type) {
      case 'urgent':
        return Icons.warning_amber_rounded;
      case 'schedule':
        return Icons.calendar_today_outlined;
      default:
        return Icons.campaign_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'urgent':
        return Colors.red;
      case 'schedule':
        return Colors.orange;
      default:
        return const Color(0xFF1034A6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_unreadCount unread',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _isLoading ? null : _loadNotifications,
                        tooltip: 'Refresh',
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                        ),
                      ),
                      TextButton(
                        onPressed: _unreadCount == 0 ? null : _markAllRead,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          backgroundColor: Colors.white.withOpacity(0.15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Mark all read',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Muted notice — controlled by Profile → Settings →
            // Notification Preferences.
            ValueListenableBuilder<bool>(
              valueListenable: NotificationSettings.allowNotifications,
              builder: (context, allowed, _) {
                if (allowed) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.orange.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_off_outlined,
                          size: 18, color: Colors.orange[800]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notifications are turned off. New alerts still '
                          'appear here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[900],
                            height: 1.4,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            NotificationSettings.setAllowed(true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange[800],
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text(
                          'Turn on',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Notifications List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1034A6)),
                    )
                  : _loadError != null
                      ? _buildErrorState()
                      : _notifications.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(20),
                              itemCount: _notifications.length,
                              itemBuilder: (context, index) =>
                                  _buildNotificationCard(
                                      _notifications[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Could not load notifications',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '$_loadError',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadNotifications,
            child: const Text('Retry'),
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
          Icon(Icons.notifications_none, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Duty calls and schedule updates will show up here.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(EmployeeNotification notification) {
    final color = _colorFor(notification.type);

    return InkWell(
      onTap: () => _openNotification(notification),
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
          border: !notification.isRead
              ? Border.all(
                  color: const Color(0xFF1034A6).withOpacity(0.2),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconFor(notification.type),
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            notification.displayTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (!notification.isRead) ...[
                            const SizedBox(width: 6),
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Tap to view details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1034A6).withOpacity(0.85),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
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
    );
  }
}

// Full-details view opened by tapping a notification card: the whole
// message (cards clip it at 3 lines), the duty date it refers to, and
// when it was received.
class _NotificationDetailSheet extends StatelessWidget {
  final EmployeeNotification notification;
  final IconData icon;
  final Color color;

  const _NotificationDetailSheet({
    required this.notification,
    required this.icon,
    required this.color,
  });

  String get _typeLabel {
    switch (notification.type) {
      case 'urgent':
        return 'Urgent';
      case 'schedule':
        return 'Schedule Update';
      default:
        return 'Announcement';
    }
  }

  // '2026-07-22' -> 'July 22, 2026'; falls back to the raw value.
  String _prettyDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Keeps the sheet above the keyboard/gesture areas.
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 12,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _typeLabel.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Full message — no truncation here.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                notification.message,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (notification.date.isNotEmpty) ...[
              _buildInfoRow(
                Icons.event_outlined,
                'Duty date',
                _prettyDate(notification.date),
              ),
              const SizedBox(height: 10),
            ],
            _buildInfoRow(
              Icons.access_time_rounded,
              'Received',
              notification.displayTime,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1034A6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData rowIcon, String label, String value) {
    return Row(
      children: [
        Icon(rowIcon, size: 18, color: Colors.grey[500]),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}
