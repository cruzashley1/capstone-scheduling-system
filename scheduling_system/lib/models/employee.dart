// models/employee.dart
// UPDATED: Added username, password, dateJoined, and switched `station`
// (single string) to `preferredStations` (list) so it matches what
// add_employee_dialog.dart actually collects. `station` is kept as a
// read-only getter so existing screens that call `employee.station`
// keep working without changes.
class Employee {
  final String id;
  final String name;
  final String email;
  final String phone;
  final List<String> preferredStations;
  final EmployeeType type;
  final String? profileImage;
  final bool isActive;

  // NEW: generated on the backend when the employee is created
  final String username;
  final String password;
  final DateTime dateJoined;

  // Fixed assignment written by the seeder/scheduler. Null for floating
  // substitute head guards (station) and relievers (shift).
  final String? assignedStation;
  final String? assignedShift; // 'morning'|'afternoon'|'night'|'hgDay'|'hgNight'

  Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.preferredStations,
    required this.type,
    this.profileImage,
    this.isActive = true,
    this.username = '',
    this.password = '',
    DateTime? dateJoined,
    this.assignedStation,
    this.assignedShift,
  }) : dateJoined = dateJoined ?? DateTime.now();

  // Initials for the avatar circle, e.g. 'Juan Santos' -> 'JS'.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // BACKWARD-COMPAT GETTER: old code (employee_list_screen.dart,
  // employee_detail_screen.dart) reads `employee.station` as a string.
  // This joins the list so nothing else needs to change.
  String get station =>
      preferredStations.isEmpty ? 'Unassigned' : preferredStations.join(', ');

  // Format name as "Surname, First Name M."
  String get formattedName {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      final firstName = parts[0];
      final lastName = parts.last;
      final middleInitial = parts.length > 2 ? '${parts[1][0]}.' : '';
      return '$lastName, $firstName $middleInitial'.trim();
    }
    return name;
  }

  // Builds an Employee from the JSON the Python API returns.
  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      preferredStations: json['preferredStations'] != null
          ? List<String>.from(json['preferredStations'])
          : [],
      type: EmployeeType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => EmployeeType.regular,
      ),
      profileImage: json['profileImage'],
      isActive: json['isActive'] ?? true,
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      dateJoined: json['dateJoined'] != null
          ? DateTime.tryParse(json['dateJoined']) ?? DateTime.now()
          : DateTime.now(),
      assignedStation: (json['assignedStation'] as String?)?.trim(),
      assignedShift: json['assignedShift'],
    );
  }

  // Converts to JSON for sending back to the API (used for updates later).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'preferredStations': preferredStations,
      'type': type.name,
      'profileImage': profileImage,
      'isActive': isActive,
      'username': username,
      'password': password,
      'dateJoined': dateJoined.toIso8601String(),
      'assignedStation': assignedStation,
      'assignedShift': assignedShift,
    };
  }

  Employee copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    List<String>? preferredStations,
    EmployeeType? type,
    String? profileImage,
    bool? isActive,
    String? username,
    String? password,
    DateTime? dateJoined,
    String? assignedStation,
    String? assignedShift,
  }) {
    return Employee(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      preferredStations: preferredStations ?? this.preferredStations,
      type: type ?? this.type,
      profileImage: profileImage ?? this.profileImage,
      isActive: isActive ?? this.isActive,
      username: username ?? this.username,
      password: password ?? this.password,
      dateJoined: dateJoined ?? this.dateJoined,
      assignedStation: assignedStation ?? this.assignedStation,
      assignedShift: assignedShift ?? this.assignedShift,
    );
  }
}

enum EmployeeType { regular, reliever, headGuard }

// Maps the role string from the Add Employee dropdown to the enum.
EmployeeType employeeTypeFromRoleString(String role) {
  switch (role) {
    case 'Reliever Employee':
      return EmployeeType.reliever;
    case 'Head Guard':
      return EmployeeType.headGuard;
    case 'Regular Employee':
    default:
      return EmployeeType.regular;
  }
}

// Reverse mapping, in case you need to display the role as text.
String employeeTypeToRoleString(EmployeeType type) {
  switch (type) {
    case EmployeeType.reliever:
      return 'Reliever Employee';
    case EmployeeType.headGuard:
      return 'Head Guard';
    case EmployeeType.regular:
      return 'Regular Employee';
  }
}