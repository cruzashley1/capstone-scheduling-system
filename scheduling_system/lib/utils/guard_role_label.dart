import '../models/employee.dart';
import '../services/duty_clock.dart';

/// The assigned post shown beneath the employee's name on phone dashboards.
String guardRoleLabel({
  required EmployeeType employeeType,
  required LiveDutyState duty,
}) {
  if (duty.shift == null) return 'No post assigned';
  if (employeeType == EmployeeType.headGuard) return 'Head Guard';

  // Reuse the dashboard's duty selection, including overnight duties and
  // today's upcoming or completed shift. Rest days have no assigned post.
  final post = duty.shift?.post?.trim();
  return post == null || post.isEmpty ? 'No post assigned' : post;
}
