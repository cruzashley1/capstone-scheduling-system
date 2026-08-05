// screens/headguardui/headguard_profile_screen.dart
//
// Profile tab for head guards. The actual UI lives in the shared
// GuardProfileView so it stays identical to the regular/reliever
// profile (preferred station picker, working settings, logout
// confirmation).
import 'package:flutter/material.dart';
import '../../models/employee.dart';
import '../profile/guard_profile_view.dart';

class HeadGuardProfileScreen extends StatelessWidget {
  final Employee employee;

  const HeadGuardProfileScreen({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return GuardProfileView(employee: employee);
  }
}
