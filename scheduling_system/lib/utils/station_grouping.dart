// utils/station_grouping.dart
//
// Divides the 25 stations into the 3 scheduling groups from the
// "Creating Schedule Strategy" plan:
//   Group 1 -> stations 1 to 8
//   Group 2 -> stations 9 to 17
//   Group 3 -> stations 18 to 25
//
// "Station number" means the position in the list after sorting by the
// auto-generated station ID (STA001, STA002, ...), i.e. the order the
// stations were registered in. Ranges are clamped so the split still
// works if the database holds fewer than 25 stations.
//
// Also home to the group-level personnel rules (mirrored by the backend
// in station_pools.py): a group's pool is everyone who prefers one of
// its stations, and the exception rule lets personnel be deployed one
// group over — never two, so Group 1 guards never end up in Group 3.
import '../models/employee.dart';
import '../models/station.dart';

class StationGroup {
  final String name;
  final int startNumber; // 1-based, inclusive
  final int endNumber; // 1-based, inclusive

  const StationGroup({
    required this.name,
    required this.startNumber,
    required this.endNumber,
  });

  String get rangeLabel => 'Stations $startNumber to $endNumber';
}

class StationGrouping {
  static const List<StationGroup> groups = [
    StationGroup(name: 'Group 1', startNumber: 1, endNumber: 8),
    StationGroup(name: 'Group 2', startNumber: 9, endNumber: 17),
    StationGroup(name: 'Group 3', startNumber: 18, endNumber: 25),
  ];

  static List<String> get groupNames => groups.map((g) => g.name).toList();

  static StationGroup byName(String name) => groups.firstWhere(
        (g) => g.name == name,
        orElse: () => groups.first,
      );

  /// Returns the stations that belong to [groupName], sorted by station ID.
  static List<Station> stationsForGroup(
      List<Station> allStations, String groupName) {
    final sorted = [...allStations]..sort((a, b) => a.id.compareTo(b.id));
    final group = byName(groupName);

    final startIndex = group.startNumber - 1;
    if (startIndex >= sorted.length) return [];

    final endIndex =
        group.endNumber < sorted.length ? group.endNumber : sorted.length;
    return sorted.sublist(startIndex, endIndex);
  }

  /// The exception rule: personnel may also be deployed one group over,
  /// never two (Group 1 <-> Group 2 <-> Group 3).
  static const Map<int, List<int>> adjacentGroups = {
    1: [2],
    2: [1, 3],
    3: [2],
  };

  /// {station name -> 1-based group number} for the whole network.
  static Map<String, int> groupOfStations(List<Station> allStations) {
    final map = <String, int>{};
    for (var g = 0; g < groups.length; g++) {
      for (final station
          in stationsForGroup(allStations, groups[g].name)) {
        map[station.name.trim()] = g + 1;
      }
    }
    return map;
  }

  /// A guard's own group: their assigned station's group, or the group
  /// most of their preferred stations fall in for floating personnel.
  static int? homeGroup(Employee employee, Map<String, int> groupOf) {
    final assigned = groupOf[employee.assignedStation?.trim() ?? ''];
    if (assigned != null) return assigned;

    final votes = <int, int>{};
    for (final name in employee.preferredStations) {
      final group = groupOf[name.trim()];
      if (group != null) votes[group] = (votes[group] ?? 0) + 1;
    }
    if (votes.isEmpty) return null;
    // Majority wins; ties break toward the lower group number, matching
    // the backend (station_pools.home_group).
    return votes.entries
        .reduce((a, b) =>
            b.value > a.value || (b.value == a.value && b.key < a.key)
                ? b
                : a)
        .key;
  }

  /// The personnel pool for [groupName]: `direct` guards belong to the
  /// group (assigned or preferred a station in it), `adjacent` guards
  /// are borrowable from a neighbouring group under the exception rule.
  static GroupPersonnelPool personnelPool(List<Station> allStations,
      List<Employee> employees, String groupName) {
    final groupNumber = groupNames.indexOf(groupName) + 1;
    final groupOf = groupOfStations(allStations);

    final direct = <Employee>[];
    final adjacent = <Employee>[];
    for (final employee in employees) {
      if (!employee.isActive) continue;
      final prefersGroup =
          groupOf[employee.assignedStation?.trim() ?? ''] == groupNumber ||
              employee.preferredStations
                  .any((name) => groupOf[name.trim()] == groupNumber);
      if (prefersGroup) {
        direct.add(employee);
      } else if (adjacentGroups[homeGroup(employee, groupOf)]
              ?.contains(groupNumber) ??
          false) {
        adjacent.add(employee);
      }
    }
    return GroupPersonnelPool(direct: direct, adjacent: adjacent);
  }
}

/// Result of [StationGrouping.personnelPool].
class GroupPersonnelPool {
  final List<Employee> direct;
  final List<Employee> adjacent;

  const GroupPersonnelPool({required this.direct, required this.adjacent});

  int countOfType(EmployeeType type) =>
      direct.where((e) => e.type == type).length;
}
