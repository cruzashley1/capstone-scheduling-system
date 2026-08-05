// data/attendance_report_dummy_data.dart
//
// Fallback attendance reports for when the backend is unreachable, so
// the admin Notifications / Submitted Reports screens stay usable
// during development (same pattern as DummyData.stations).

import '../models/attendance_report.dart';

class AttendanceReportDummyData {
  AttendanceReportDummyData._();

  static String _isoDaysAgo(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static List<AttendanceReport> get reports => [
        AttendanceReport(
          id: 'RPT-SAMPLE-01',
          headGuardName: 'James Reyes',
          headGuardId: 'REY001',
          station: 'Monumento Station',
          shiftTitle: 'Day Shift',
          date: _isoDaysAgo(0),
          submittedAt: DateTime.now().subtract(const Duration(minutes: 25)),
          records: [
            AttendanceRecord(
              name: 'Maria Santos',
              employeeId: 'SAN012',
              shift: 'Morning',
              time: '0600H - 1400H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Roberto Cruz',
              employeeId: 'CRU008',
              shift: 'Morning',
              time: '0600H - 1400H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Anna Lim',
              employeeId: 'LIM045',
              shift: 'Afternoon',
              time: '1400H - 2200H',
              isPresent: false,
            ),
            AttendanceRecord(
              name: 'Mark Dela Cruz',
              employeeId: 'DEL009',
              shift: 'Afternoon',
              time: '1400H - 2200H',
              isPresent: true,
              isReliever: true,
            ),
            AttendanceRecord(
              name: 'Patricia Ramos',
              employeeId: 'RAM018',
              shift: 'Night',
              time: '2200H - 0600H',
              isPresent: true,
            ),
          ],
        ),
        AttendanceReport(
          id: 'RPT-SAMPLE-02',
          headGuardName: 'Liza Ramirez',
          headGuardId: 'RAM004',
          station: 'Baclaran Station',
          shiftTitle: 'Day Shift',
          date: _isoDaysAgo(0),
          submittedAt: DateTime.now().subtract(const Duration(hours: 2)),
          records: [
            AttendanceRecord(
              name: 'Carlo Cruz',
              employeeId: 'CRU031',
              shift: 'Morning',
              time: '0600H - 1400H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Ana Reyes',
              employeeId: 'REY027',
              shift: 'Afternoon',
              time: '1400H - 2200H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Jojo Bautista',
              employeeId: 'BAU022',
              shift: 'Night',
              time: '2200H - 0600H',
              isPresent: true,
              isReliever: true,
            ),
          ],
        ),
        AttendanceReport(
          id: 'RPT-SAMPLE-03',
          headGuardName: 'Pedro Garcia',
          headGuardId: 'GAR003',
          station: 'Central Terminal Station',
          shiftTitle: 'Night Shift',
          date: _isoDaysAgo(1),
          submittedAt: DateTime.now().subtract(const Duration(hours: 14)),
          isRead: true,
          records: [
            AttendanceRecord(
              name: 'Daniel Torres',
              employeeId: 'TOR031',
              shift: 'Night',
              time: '2200H - 0600H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Carla Villanueva',
              employeeId: 'VIL027',
              shift: 'Night',
              time: '2200H - 0600H',
              isPresent: false,
            ),
            AttendanceRecord(
              name: 'Juan Dela Cruz',
              employeeId: 'DEL001',
              shift: 'Night',
              time: '2200H - 0600H',
              isPresent: false,
              isReliever: true,
            ),
          ],
        ),
        AttendanceReport(
          id: 'RPT-SAMPLE-04',
          headGuardName: 'Maria Clara Lopez',
          headGuardId: 'LOP002',
          station: 'EDSA Station',
          shiftTitle: 'Day Shift',
          date: _isoDaysAgo(2),
          submittedAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
          isRead: true,
          records: [
            AttendanceRecord(
              name: 'Rico Salazar',
              employeeId: 'SAL019',
              shift: 'Morning',
              time: '0600H - 1400H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Lea Navarro',
              employeeId: 'NAV033',
              shift: 'Afternoon',
              time: '1400H - 2200H',
              isPresent: true,
            ),
            AttendanceRecord(
              name: 'Bong Rivera',
              employeeId: 'RIV025',
              shift: 'Night',
              time: '2200H - 0600H',
              isPresent: true,
            ),
          ],
        ),
      ];
}
