// screens/securityguardui/security_profile_screen.dart
//
// Profile tab for regular guards and relievers. The actual UI lives in
// the shared GuardProfileView so it stays identical to the head guard
// profile (preferred station picker, working settings, logout
// confirmation).
import 'package:flutter/material.dart';
import '../../models/employee.dart';
import '../profile/guard_profile_view.dart';

class SecurityProfileScreen extends StatelessWidget {
  final Employee employee;

  const SecurityProfileScreen({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return GuardProfileView(employee: employee);
  }
}
