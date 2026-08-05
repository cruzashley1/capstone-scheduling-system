// data/dummy_data.dart
import '../models/employee.dart';
import '../models/station.dart';
import '../models/schedule.dart';

class DummyData {
  static List<Employee> employees = [
    Employee(
      id: 'EMP001',
      name: 'John Smith',
      email: 'john.smith@company.com',
      phone: '+1 234-567-8901',
      preferredStations: ['Monumento'],
      type: EmployeeType.regular,
      isActive: true,
      username: 'SMI001',
      password: 'SMITH001XX',
      dateJoined: DateTime(2023, 1, 15),
    ),
    Employee(
      id: 'EMP002',
      name: 'Sarah Johnson',
      email: 'sarah.j@company.com',
      phone: '+1 234-567-8902',
      preferredStations: ['5th Avenue'],
      type: EmployeeType.regular,
      isActive: true,
      username: 'JOH002',
      password: 'JOHNSON002XX',
      dateJoined: DateTime(2023, 2, 10),
    ),
    Employee(
      id: 'EMP003',
      name: 'Mike Chen',
      email: 'mike.chen@company.com',
      phone: '+1 234-567-8903',
      preferredStations: ['Doroteo Jose'],
      type: EmployeeType.reliever,
      isActive: true,
      username: 'CHE003',
      password: 'CHEN003XX',
      dateJoined: DateTime(2023, 3, 5),
    ),
    Employee(
      id: 'EMP004',
      name: 'Emily Davis',
      email: 'emily.d@company.com',
      phone: '+1 234-567-8904',
      preferredStations: ['Carriedo'],
      type: EmployeeType.regular,
      isActive: false,
      username: 'DAV004',
      password: 'DAVIS004XX',
      dateJoined: DateTime(2023, 4, 20),
    ),
    Employee(
      id: 'EMP005',
      name: 'Robert Wilson',
      email: 'rob.w@company.com',
      phone: '+1 234-567-8905',
      preferredStations: ['Central Terminal'],
      type: EmployeeType.reliever,
      isActive: true,
      username: 'WIL005',
      password: 'WILSON005XX',
      dateJoined: DateTime(2023, 5, 12),
    ),
    Employee(
      id: 'EMP006',
      name: 'Lisa Anderson',
      email: 'lisa.a@company.com',
      phone: '+1 234-567-8906',
      preferredStations: ['Blumentrit'],
      type: EmployeeType.reliever,
      isActive: true,
      username: 'AND006',
      password: 'ANDERSON006XX',
      dateJoined: DateTime(2023, 6, 1),
    ),
  ];

  // NOTE: Station Management now loads real stations from the backend
  // (see station_management_screen.dart / ApiService.fetchStations), so
  // this list is no longer shown on that screen. It's kept only because
  // _generateSchedules() below still indexes into it for placeholder
  // schedule data. Fields now match the simplified Station model
  // (no `location`, `capacity` renamed to `requiredEmployees`).
  static List<Station> stations = [
    Station(id: 'ST001', name: 'Fernando Poe Jr.', requiredEmployees: 10),
    Station(id: 'ST002', name: 'Balintawak', requiredEmployees: 10),
    Station(id: 'ST003', name: 'Monumento', requiredEmployees: 10),
    Station(id: 'ST004', name: '5th Avenue', requiredEmployees: 10),
    Station(id: 'ST005', name: 'Abad Santos', requiredEmployees: 10),
    Station(id: 'ST006', name: 'Blumentritt', requiredEmployees: 10),
    Station(id: 'ST007', name: 'Tayuman', requiredEmployees: 10),
    Station(id: 'ST008', name: 'Bambang', requiredEmployees: 10),
    Station(id: 'ST009', name: 'Doroteo Jose', requiredEmployees: 10),
    Station(id: 'ST010', name: 'Carriedo', requiredEmployees: 10),
    Station(id: 'ST011', name: 'Central Terminal', requiredEmployees: 10),
    Station(id: 'ST012', name: 'United Nations', requiredEmployees: 10),
    Station(id: 'ST013', name: 'Pedro Gil', requiredEmployees: 10),
    Station(id: 'ST014', name: 'Quirino', requiredEmployees: 10),
    Station(id: 'ST015', name: 'Vito Cruz', requiredEmployees: 10),
    Station(id: 'ST016', name: 'Gil Puyat ', requiredEmployees: 10),
    Station(id: 'ST017', name: 'Libertad ', requiredEmployees: 10),
    Station(id: 'ST018', name: 'EDSA ', requiredEmployees: 10),
    Station(id: 'ST019', name: 'Baclaran ', requiredEmployees: 10),
    Station(id: 'ST020', name: 'Redemptorist-Aseana ', requiredEmployees: 10),
    Station(id: 'ST021', name: 'MIA Road ', requiredEmployees: 10),
    Station(id: 'ST022', name: 'PITX ', requiredEmployees: 10),
    Station(id: 'ST023', name: 'Ninoy Aquino Avenue ', requiredEmployees: 10),
    Station(id: 'ST024', name: 'Dr. Santos ', requiredEmployees: 10),
  ];

  // NEW: Bi-weekly (15-day) schedules, some unpublished, some published.
  static List<Schedule> schedules = _generateSchedules();

  static List<Schedule> _generateSchedules() {
    final activeEmployees = employees.where((e) => e.isActive).toList();
    if (activeEmployees.isEmpty) return [];

    // Each config represents one bi-weekly schedule for a station.
    final configs = [
      {'stationIndex': 2, 'start': DateTime(2026, 6, 17), 'status': ScheduleStatus.unpublished}, // Monumento
      {'stationIndex': 3, 'start': DateTime(2026, 6, 17), 'status': ScheduleStatus.unpublished}, // 5th Avenue
      {'stationIndex': 8, 'start': DateTime(2026, 6, 3), 'status': ScheduleStatus.published}, // Doroteo Jose
      {'stationIndex': 9, 'start': DateTime(2026, 6, 3), 'status': ScheduleStatus.published}, // Carriedo
      {'stationIndex': 10, 'start': DateTime(2026, 6, 3), 'status': ScheduleStatus.published}, // Central Terminal
    ];

    final List<Schedule> result = [];
    int scheduleCounter = 1;

    for (final config in configs) {
      final station = stations[config['stationIndex'] as int];
      final start = config['start'] as DateTime;
      final status = config['status'] as ScheduleStatus;
      final end = start.add(const Duration(days: 14)); // 15 days inclusive

      final days = List.generate(15, (i) {
        final date = start.add(Duration(days: i));
        final dayEmployee = activeEmployees[i % activeEmployees.length];
        final nightEmployee =
        activeEmployees[(i + 1) % activeEmployees.length];

        return ScheduleDay(
          date: date,
          entries: [
            ScheduleEntry(
              id: 'SCH${scheduleCounter}D${i}E1',
              employeeId: dayEmployee.id,
              employeeName: dayEmployee.formattedName,
              shift: 'Day',
            ),
            ScheduleEntry(
              id: 'SCH${scheduleCounter}D${i}E2',
              employeeId: nightEmployee.id,
              employeeName: nightEmployee.formattedName,
              shift: 'Night',
            ),
          ],
        );
      });

      result.add(Schedule(
        id: 'SCHD00$scheduleCounter',
        stationId: station.id,
        stationName: station.name,
        startDate: start,
        endDate: end,
        createdAt: start.subtract(const Duration(days: 3)),
        status: status,
        days: days,
      ));

      scheduleCounter++;
    }

    return result;
  }

  static Map<String, dynamic> getDashboardStats() {
    final totalEmployees = employees.length;
    final totalStations = stations.length;
    final activeEmployees = employees.where((e) => e.isActive).length;
    final relieversAvailable = employees.where((e) => e.type == EmployeeType.reliever && e.isActive).length;
    final regularEmployees = employees.where((e) => e.type == EmployeeType.regular).length;
    final absentToday = 2; // Dummy data

    return {
      'totalEmployees': totalEmployees,
      'totalStations': totalStations,
      'activeEmployees': activeEmployees,
      'relieversAvailable': relieversAvailable,
      'regularEmployees': regularEmployees,
      'absentToday': absentToday,
    };
  }
}