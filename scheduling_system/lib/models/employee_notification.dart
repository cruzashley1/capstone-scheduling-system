// models/employee_notification.dart
//
// One notification shown in the guard app's Alerts tab. Mirrors the
// JSON written by the Python backend to `employee_notifications`
// (currently created when the admin assigns this guard to cover an
// absent colleague's post).

class EmployeeNotification {
  final String id;
  final String employeeId;
  final String type; // 'urgent' | 'announcement' | 'schedule'
  final String title;
  final String message;
  final String date; // ISO date the duty change is for
  final DateTime createdAt;

  // Mutable so the Alerts screen can flip it locally after telling
  // the API (same convention as AttendanceReport.isRead).
  bool isRead;

  EmployeeNotification({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.title,
    required this.message,
    required this.date,
    required this.createdAt,
    this.isRead = false,
  });

  factory EmployeeNotification.fromJson(Map<String, dynamic> json) {
    return EmployeeNotification(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      type: json['type'] ?? 'announcement',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      date: json['date'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '')?.toLocal() ??
          DateTime.now(),
      isRead: json['isRead'] ?? false,
    );
  }

  // '8:45 AM' today, 'Yesterday', or 'Apr 9' for older ones — matches
  // the display style the Alerts screen already used.
  String get displayTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final created = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final diff = today.difference(created).inDays;
    if (diff == 0) {
      final hour12 = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
      final minute = createdAt.minute.toString().padLeft(2, '0');
      final suffix = createdAt.hour >= 12 ? 'PM' : 'AM';
      return '$hour12:$minute $suffix';
    }
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}';
  }
}
