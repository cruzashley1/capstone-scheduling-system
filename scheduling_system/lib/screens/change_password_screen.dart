// screens/change_password_screen.dart
//
// Shown right after a guard's FIRST successful login (while their account
// still uses the auto-generated password). The employee must set a new
// password here before they can reach their dashboard — there is no way
// to skip this screen.
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'station_selection_screen.dart';
import 'headguardui/head_guard_layout.dart';
import 'securityguardui/security_guard_layout.dart';
import '../services/api_service.dart';
import '../services/session.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String username;
  final String currentPassword;
  final String role; // 'headGuard' | 'regular' | 'reliever'

  // Carried over from login so the onboarding can continue straight into the
  // preferred-stations picker once the password is set.
  final bool mustSelectStations;
  final List<String> preferredStations;

  const ChangePasswordScreen({
    super.key,
    required this.username,
    required this.currentPassword,
    required this.role,
    this.mustSelectStations = false,
    this.preferredStations = const [],
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      setState(() => _errorText = 'Please fill in both password fields.');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _errorText = 'New password must be at least 8 characters.');
      return;
    }
    if (newPassword == widget.currentPassword) {
      setState(() =>
          _errorText = 'New password must be different from your current one.');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _errorText = 'Passwords do not match.');
      return;
    }

    setState(() {
      _errorText = null;
      _isSaving = true;
    });

    final result = await ApiService.changePassword(
      username: widget.username,
      currentPassword: widget.currentPassword,
      newPassword: newPassword,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result["success"] != true) {
      setState(() =>
          _errorText = result["error"]?.toString() ?? 'Failed to change password.');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password updated! Welcome to Sched.'),
        backgroundColor: Colors.green,
      ),
    );

    // Next onboarding step: confirm preferred stations. The station screen
    // saves the session and routes to the dashboard once it's done, so we
    // don't save the session here.
    if (widget.mustSelectStations) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StationSelectionScreen(
            username: widget.username,
            role: widget.role,
            initialStations: widget.preferredStations,
          ),
        ),
      );
      return;
    }

    // Nothing left to onboard — remember the session and go straight to the
    // right dashboard.
    await Session.save(widget.username, widget.role);
    if (!mounted) return;

    if (widget.role == 'headGuard') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HeadGuardLayout(username: widget.username),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SecurityGuardLayout(username: widget.username),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same gradient background as the mobile login screen, so the flow
    // feels like one continuous sign-in experience.
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D2B8E),
              Color(0xFF1A4DC8),
              Color(0xFF2B6DD4),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon + Header
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.lock_reset,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Set a New Password',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'For your security, you must replace the '
                            'password given to you before continuing.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),

                    // New Password
                    _buildPasswordField(
                      controller: _newPasswordController,
                      label: 'New Password',
                      obscure: _obscureNew,
                      onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    const SizedBox(height: 20),

                    // Confirm New Password
                    _buildPasswordField(
                      controller: _confirmPasswordController,
                      label: 'Confirm New Password',
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),

                    // Inline error message
                    if (_errorText != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red.shade200.withOpacity(0.6)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorText!,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1034A6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          shadowColor: Colors.black.withOpacity(0.25),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFF1034A6),
                                ),
                              )
                            : const Text(
                                'Save & Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Back out to the login screen (does NOT skip the
                    // requirement — they'll be sent here again next login).
                    Center(
                      child: TextButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AuthScreen(),
                                  ),
                                ),
                        child: const Text(
                          'Back to Sign In',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.lock_outlined, color: Colors.white60),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.white60,
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}
