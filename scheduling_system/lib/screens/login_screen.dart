// screens/login_screen.dart
import 'package:flutter/material.dart';
import 'main_layout.dart';
import 'securityguardui/security_guard_layout.dart';
import 'headguardui/head_guard_layout.dart';
import 'change_password_screen.dart';
import 'station_selection_screen.dart';
import '../services/api_service.dart';
import '../services/session.dart';

// ─────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────
const _kPrimary      = Color(0xFF1034A6);
const _kPrimaryLight = Color(0xFF1E88E5);
const _kText         = Color(0xFF0F172A);
const _kTextMuted    = Color(0xFF64748B);
const _kBorder       = Color(0xFFE2E8F0);
const _kFieldFill    = Color(0xFFF8FAFC);

// Two raw logo variants: the blue one for white surfaces, the white one
// for colored/gradient surfaces.
const String _kLogoAsset      = 'assets/logo/sched_logo.png';
const String _kLogoWhiteAsset = 'assets/logo/sched_white.png';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;

  // Login controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Signup controllers
  final _surnameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _selectedRole = 'Admin';
  final List<String> _roles = ['Admin', 'Head Guard', 'Regular Employee', 'Reliever'];

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _surnameController.dispose();
    _firstNameController.dispose();
    _signupEmailController.dispose();
    _mobileController.dispose();
    _signupPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _loginEmailController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both username and password.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoggingIn = true);

    final result = await ApiService.login(username, password);

    if (!mounted) return;
    setState(() => _isLoggingIn = false);

    if (result["success"] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ApiService.friendlyError(
              result["error"]?.toString() ?? 'Invalid username or password.')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final role = result["role"];
    final bool mustChangePassword = result["mustChangePassword"] == true;
    final bool mustSelectStations = result["mustSelectStations"] == true;
    final List<String> preferredStations =
        (result["preferredStations"] as List?)?.cast<String>() ?? <String>[];

    switch (role) {
      case 'admin':
        // Remember the session so the app reopens signed in until an
        // explicit Log Out.
        await Session.save(username, role);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainLayout(username: username)),
        );
        break;
      case 'headGuard':
      case 'regular':
      case 'reliever':
        // First login: the employee is still on their auto-generated
        // password, so force them to set a new one before the dashboard.
        // The session is NOT saved yet — it's saved once onboarding (password
        // change + preferred stations) is fully complete.
        if (mustChangePassword) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChangePasswordScreen(
                username: username,
                currentPassword: password,
                role: role,
                mustSelectStations: mustSelectStations,
                preferredStations: preferredStations,
              ),
            ),
          );
          break;
        }
        // Password already changed, but the employee hasn't confirmed their
        // preferred stations yet (e.g. an existing account onboarding for the
        // first time under this feature). Send them to the picker first.
        if (mustSelectStations) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => StationSelectionScreen(
                username: username,
                role: role,
                initialStations: preferredStations,
              ),
            ),
          );
          break;
        }
        await Session.save(username, role);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => role == 'headGuard'
                ? HeadGuardLayout(username: username)
                : SecurityGuardLayout(username: username),
          ),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login succeeded but role "$role" is not recognized.'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  void _handleSignup() {
    // Fake signup - switch back to login
    setState(() {
      _isLogin = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account created! Please login.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Below this width we're effectively on a phone (security guard app),
  // so we drop the branding panel and just show the form full-width.
  static const double _wideBreakpoint = 800;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth >= _wideBreakpoint;

          if (isWide) {
            // Web / Admin layout - branding panel + form side by side
            return Row(
              children: [
                Expanded(flex: 2, child: _buildBrandingPanel()),
                Expanded(flex: 3, child: _buildFormPanel(isWide: true)),
              ],
            );
          }

          // Mobile / Security Guard layout - form only, full width
          return _buildFormPanel(isWide: false);
        },
      ),
    );
  }

  // Raw logo image, no backing card. Pass onDark: true on colored or
  // gradient surfaces to use the white variant.
  Widget _buildLogo({required double size, bool onDark = false}) {
    return Image.asset(
      onDark ? _kLogoWhiteAsset : _kLogoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }

  // Left Side - Branding (web/admin only)
  Widget _buildBrandingPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPrimary, _kPrimaryLight],
        ),
      ),
      child: Stack(
        children: [
          // Soft decorative circles
          Positioned(
            top: -70,
            left: -70,
            child: _decorCircle(220),
          ),
          Positioned(
            bottom: -90,
            right: -60,
            child: _decorCircle(260),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildLogo(size: 150, onDark: true),
                  const SizedBox(height: 28),
                  const Text(
                    'Sched',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A Smart Scheduling System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _FeatureChip(icon: Icons.auto_awesome, label: 'Auto rosters'),
                      _FeatureChip(icon: Icons.fact_check_outlined, label: 'Attendance'),
                      _FeatureChip(icon: Icons.swap_horiz_rounded, label: 'Relievers'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decorCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.06),
      ),
    );
  }

  // Right Side - Auth Form (always shown; full width on mobile)
  Widget _buildFormPanel({required bool isWide}) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 48 : 24,
              vertical: isWide ? 48 : 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLogin
                    ? _buildLoginForm(isWide: isWide)
                    : _buildSignupForm(isWide: isWide),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm({bool isWide = true}) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo + Header (centered)
        Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Raw logo straight above the welcome heading; the form
              // panel is white, so the blue variant is used.
              _buildLogo(size: isWide ? 72 : 112),
              const SizedBox(height: 24),
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in to your account to continue',
                style: TextStyle(fontSize: 14, color: _kTextMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Username Field
        _buildTextField(
          controller: _loginEmailController,
          label: 'Username',
          hint: 'e.g. admin01',
          icon: Icons.person_outline,
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 20),

        // Password Field
        _buildTextField(
          controller: _loginPasswordController,
          label: 'Password',
          hint: '••••••••',
          icon: Icons.lock_outlined,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey[500],
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
        ),
        const SizedBox(height: 8),

        // Forgot Password
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                color: _kPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Login Button
        _buildPrimaryButton(
          onPressed: _isLoggingIn ? null : _handleLogin,
          child: _isLoggingIn
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // Gradient primary action button shared by both forms.
  Widget _buildPrimaryButton({
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: onPressed == null
                ? [Colors.grey.shade400, Colors.grey.shade400]
                : const [_kPrimary, _kPrimaryLight],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: _kPrimary.withOpacity(0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSignupForm({bool isWide = true}) {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo + Header (centered)
        Center(
          child: Column(
            children: [
              _buildLogo(size: isWide ? 72 : 96),
              const SizedBox(height: 20),
              const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Fill in your details to get started',
                style: TextStyle(fontSize: 14, color: _kTextMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Role Selection
        _buildDropdownField(
          label: 'Account Type',
          value: _selectedRole,
          items: _roles,
          icon: Icons.badge_outlined,
          onChanged: (value) {
            setState(() {
              _selectedRole = value!;
            });
          },
        ),
        const SizedBox(height: 20),

        // Name Row
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _surnameController,
                label: 'Surname',
                hint: 'Doe',
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _firstNameController,
                label: 'First Name',
                hint: 'John',
                icon: Icons.person_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Email Field
        _buildTextField(
          controller: _signupEmailController,
          label: 'Email Address',
          hint: 'john.doe@company.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),

        // Mobile Field
        _buildTextField(
          controller: _mobileController,
          label: 'Mobile Number',
          hint: '+1 234-567-8900',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 20),

        // Password Field
        _buildTextField(
          controller: _signupPasswordController,
          label: 'Password',
          hint: '••••••••',
          icon: Icons.lock_outlined,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey[500],
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
        ),
        const SizedBox(height: 20),

        // Confirm Password Field
        _buildTextField(
          controller: _confirmPasswordController,
          label: 'Confirm Password',
          hint: '••••••••',
          icon: Icons.lock_outlined,
          obscureText: _obscureConfirmPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey[500],
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
          ),
        ),
        const SizedBox(height: 28),

        _buildPrimaryButton(
          onPressed: _handleSignup,
          child: const Text(
            'Create Account',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Login Link
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Already have an account? ",
                style: TextStyle(color: _kTextMuted),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = true;
                  });
                },
                child: const Text(
                  'Sign In',
                  style: TextStyle(
                    color: _kPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _kText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: const TextStyle(color: _kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _kFieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kPrimary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _kText,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _kFieldFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              icon: const Icon(Icons.arrow_drop_down, color: _kPrimary),
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// Small translucent feature pill shown on the web branding panel.
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
