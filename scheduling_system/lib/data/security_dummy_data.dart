// data/security_dummy_data.dart
//
// Dummy/mock data source for the Security Guard mobile UI (Phase 1 — design only).
// Swap this out for real Firestore-backed data once the UI is wired up.

enum NotificationType { alert, announcement, schedule, reminder }

class TodayDuty {
  final String status; // e.g. "On Duty"
  final String shiftName;
  final String timeIn;
  final String timeOut;
  final String station;
  final String date;
  final String hours;

  const TodayDuty({
    required this.status,
    required this.shiftName,
    required this.timeIn,
    required this.timeOut,
    required this.station,
    required this.date,
    required this.hours,
  });
}

class ShiftPreview {
  final String shiftName;
  final String time;
  final String station;
  final String date;
  final String day;

  const ShiftPreview({
    required this.shiftName,
    required this.time,
    required this.station,
    required this.date,
    required this.day,
  });
}

class ScheduleItem {
  final String day; // e.g. "Saturday"
  final String date; // day number, e.g. "12"
  final String month; // e.g. "Apr"
  final String shiftName; // "Morning Shift" or "Rest Day"
  final String? time;
  final String? station;
  final String status; // "Upcoming" | "Completed" | "Rest Day"

  const ScheduleItem({
    required this.day,
    required this.date,
    required this.month,
    required this.shiftName,
    this.time,
    this.station,
    required this.status,
  });
}

class TodayShiftDetail {
  final String dateFull;
  final String shiftName;
  final String timeIn;
  final String timeOut;
  final String station;
  final String hours;
  final String position;
  final String employeeId;

  const TodayShiftDetail({
    required this.dateFull,
    required this.shiftName,
    required this.timeIn,
    required this.timeOut,
    required this.station,
    required this.hours,
    required this.position,
    required this.employeeId,
  });
}

class NotificationItem {
  final NotificationType type;
  final String title;
  final String time;
  final String message;
  final bool isUnread;

  const NotificationItem({
    required this.type,
    required this.title,
    required this.time,
    required this.message,
    required this.isUnread,
  });
}

class SecurityGuardDummyData {
  SecurityGuardDummyData._(); // static-only access, no instances

  // ---------- Profile ----------
  static const String guardName = 'James Reyes';
  static const String guardInitials = 'JR';
  static const String role = 'Security Guard';
  static const String employeeId = 'SG-2024-001';
  static const String assignedStation = 'Main Gate';
  static const String shiftType = 'Morning Shift';
  static const String dateJoined = 'March 15, 2022';
  static const String email = 'james.reyes@secureguard.ph';
  static const String phone = '+63 912 345 6789';

  // ---------- Dashboard ----------
  static const TodayDuty todayDuty = TodayDuty(
    status: 'On Duty',
    shiftName: 'Morning Shift',
    timeIn: '06:00 AM',
    timeOut: '02:00 PM',
    station: 'Main Gate',
    date: 'Apr 11, 2025',
    hours: '8 hrs',
  );

  static const int daysOnDuty = 11;
  static const int restDays = 3;
  static const int absences = 1;

  static const List<ShiftPreview> upcomingShiftsPreview = [
    ShiftPreview(
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'Main Gate',
      date: 'Apr 12',
      day: 'Sat',
    ),
    ShiftPreview(
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'North Wing',
      date: 'Apr 14',
      day: 'Mon',
    ),
    ShiftPreview(
      shiftName: 'Afternoon Shift',
      time: '02:00 PM - 10:00 PM',
      station: 'South Entrance',
      date: 'Apr 16',
      day: 'Wed',
    ),
  ];

  // ---------- Schedule ----------
  static const TodayShiftDetail todayShiftDetail = TodayShiftDetail(
    dateFull: 'Friday, April 11, 2025',
    shiftName: 'Morning Shift',
    timeIn: '06:00 AM',
    timeOut: '02:00 PM',
    station: 'Main Gate',
    hours: '8 hrs',
    position: 'Security Guard',
    employeeId: 'SG-2024-001',
  );

  static const List<ScheduleItem> upcomingSchedule = [
    ScheduleItem(
      day: 'Saturday',
      date: '12',
      month: 'Apr',
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'Main Gate',
      status: 'Upcoming',
    ),
    ScheduleItem(
      day: 'Sunday',
      date: '13',
      month: 'Apr',
      shiftName: 'Rest Day',
      status: 'Rest Day',
    ),
    ScheduleItem(
      day: 'Monday',
      date: '14',
      month: 'Apr',
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'North Wing',
      status: 'Upcoming',
    ),
    ScheduleItem(
      day: 'Tuesday',
      date: '15',
      month: 'Apr',
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'Main Gate',
      status: 'Upcoming',
    ),
  ];

  static const List<ScheduleItem> pastSchedule = [
    ScheduleItem(
      day: 'Thursday',
      date: '10',
      month: 'Apr',
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'Main Gate',
      status: 'Completed',
    ),
    ScheduleItem(
      day: 'Wednesday',
      date: '9',
      month: 'Apr',
      shiftName: 'Afternoon Shift',
      time: '02:00 PM - 10:00 PM',
      station: 'South Entrance',
      status: 'Completed',
    ),
    ScheduleItem(
      day: 'Tuesday',
      date: '8',
      month: 'Apr',
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'Main Gate',
      status: 'Completed',
    ),
    ScheduleItem(
      day: 'Monday',
      date: '7',
      month: 'Apr',
      shiftName: 'Morning Shift',
      time: '06:00 AM - 02:00 PM',
      station: 'Main Gate',
      status: 'Completed',
    ),
  ];

  // ---------- Notifications ----------
  static const List<NotificationItem> notifications = [
    NotificationItem(
      type: NotificationType.alert,
      title: 'Sudden Duty Call',
      time: '8:45 AM',
      message:
      'Guard Martinez is unable to report. You are requested to cover the East Gate post today at 10:00 PM.',
      isUnread: true,
    ),
    NotificationItem(
      type: NotificationType.announcement,
      title: 'General Announcement',
      time: 'Yesterday',
      message:
      'Mandatory safety briefing this Saturday, April 12 at 5:30 AM before shift. Attendance is required for all personnel.',
      isUnread: true,
    ),
    NotificationItem(
      type: NotificationType.schedule,
      title: 'Schedule Updated',
      time: 'Apr 9',
      message:
      'Your schedule for the week of April 14-20 has been updated. Please review your new assignments.',
      isUnread: false,
    ),
    NotificationItem(
      type: NotificationType.reminder,
      title: 'Uniform Reminder',
      time: 'Apr 8',
      message:
      'All security personnel are reminded to wear the new uniform starting Monday, April 14. Collared ID must be visible at all times.',
      isUnread: false,
    ),
  ];

  static int get unreadNotificationCount =>
      notifications.where((n) => n.isUnread).length;
}