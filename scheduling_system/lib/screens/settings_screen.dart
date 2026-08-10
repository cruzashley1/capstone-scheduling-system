// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'main_layout.dart';
import '../services/api_service.dart';
import '../services/notification_settings.dart';
import '../services/profile_settings.dart';
import '../services/server_clock.dart';

// ─────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────
const _kPrimary      = Color(0xFF1D4ED8);
const _kPrimaryLight = Color(0xFFEFF6FF);
const _kBorder       = Color(0xFFE2E8F0);
const _kText         = Color(0xFF0F172A);
const _kTextMuted    = Color(0xFF64748B);
const _kSurface      = Color(0xFFF8FAFC);
const _kSuccess      = Color(0xFF16A34A);
const _kDanger       = Color(0xFFDC2626);
const _kWarning      = Color(0xFFF59E0B);

// ─────────────────────────────────────────────
// SETTINGS TABS
// ─────────────────────────────────────────────
enum _SettingsTab {
  profile,
  password,
  notifications,
  scheduleInfo,
  companyInfo,
  aboutUs,
  developer,
}

// A shift entry shown in the Shift Configuration section. Defaults mirror
// the auto scheduler's Shift Times reference and cannot be deleted.
class _ShiftEntry {
  final String label;
  final String time;
  final IconData icon;
  final Color color;
  final bool isDefault;

  const _ShiftEntry({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
    this.isDefault = false,
  });
}

// ─────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────
class SettingsContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data})? onNavigate;
  final String username;
  const SettingsContent({super.key, this.onNavigate, this.username = 'admin'});

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  _SettingsTab _activeTab = _SettingsTab.profile;

  // Profile (editable) — saved values drive the avatar/header display and
  // are mirrored into ProfileSettings so they survive leaving this screen
  // (its State is disposed on navigation) and reach the report PDF.
  String _savedName  = ProfileSettings.name.value;
  String _savedEmail = ProfileSettings.email.value;
  String _savedOrg   = ProfileSettings.organization.value;
  late final _nameCtrl  = TextEditingController(text: _savedName);
  late final _emailCtrl = TextEditingController(text: _savedEmail);
  late final _orgCtrl   = TextEditingController(text: _savedOrg);
  bool _profileSaved = false;
  String? _profileError;

  // Password fields
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl     = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _showCurrent    = false;
  bool _showNew        = false;
  bool _showConfirm    = false;
  bool _pwLoading      = false;
  String? _pwError;
  bool   _pwSuccess    = false;

  // Notifications preference lives in NotificationSettings (persisted
  // app-wide), not in local state — see _buildNotificationsPanel.

  // Schedule info — shift times mirror the schedule generator's reference,
  // including the head guard shifts. Custom shifts can be added/removed.
  final List<_ShiftEntry> _shifts = [
    const _ShiftEntry(label: 'Morning Shift',      time: '0500H – 1400H', icon: Icons.wb_sunny_rounded,    color: Color(0xFFD97706), isDefault: true),
    const _ShiftEntry(label: 'Afternoon Shift',    time: '1400H – 2330H', icon: Icons.wb_cloudy_rounded,   color: Color(0xFF1D4ED8), isDefault: true),
    const _ShiftEntry(label: 'Night Shift',        time: '2100H – 0500H', icon: Icons.nightlight_rounded,  color: Color(0xFF4C1D95), isDefault: true),
    const _ShiftEntry(label: 'Head Guard — Day',   time: '0500H – 1700H', icon: Icons.shield_rounded,      color: Color(0xFF059669), isDefault: true),
    const _ShiftEntry(label: 'Head Guard — Night', time: '1700H – 0500H', icon: Icons.shield_moon_rounded, color: Color(0xFF0D9488), isDefault: true),
  ];
  static const _customShiftColors = [
    Color(0xFFBE185D), Color(0xFF0369A1), Color(0xFF7C3AED),
    Color(0xFF065F46), Color(0xFFB45309),
  ];
  int _nextShiftColor = 0;

  // Security positions (add / delete)
  final List<String> _positions = [
    'Head Guard', 'SW Platform', 'SE Jackman', 'SE Platform',
    'Roving', 'K9 Unit', 'S Street Roving Guard',
    'N SM Roving Guard', 'Inspection Guard', 'Train Marshall',
  ];

  // Company info (partially editable)
  String _savedCompany = ProfileSettings.company.value;
  String _savedClient  = ProfileSettings.client.value;
  late final _companyCtrl = TextEditingController(text: _savedCompany);
  late final _clientCtrl  = TextEditingController(text: _savedClient);

  // Report signatories printed at the bottom of every exported schedule
  // report. "Prepared by" is not editable here — it is always the profile
  // name of whoever produced the report.
  String _savedApprovedBy = ProfileSettings.approvedBy.value;
  String _savedEndorsedBy = ProfileSettings.endorsedBy.value;
  late final _approvedCtrl = TextEditingController(text: _savedApprovedBy);
  late final _endorsedCtrl = TextEditingController(text: _savedEndorsedBy);

  bool _companySaved = false;
  String? _companyError;

  // Live counts pulled from the backend for the Company Info panel.
  bool _statsLoading  = true;
  int? _stationCount;
  int? _personnelCount;

  @override
  void initState() {
    super.initState();
    _loadCompanyStats();
    // Editing again clears the previous result, so pressing Save a second
    // time always produces a visible change instead of looking like a no-op.
    for (final c in [_nameCtrl, _emailCtrl, _orgCtrl]) {
      c.addListener(_clearProfileFeedback);
    }
    for (final c in [_companyCtrl, _clientCtrl, _approvedCtrl, _endorsedCtrl]) {
      c.addListener(_clearCompanyFeedback);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _orgCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _companyCtrl.dispose();
    _clientCtrl.dispose();
    _approvedCtrl.dispose();
    _endorsedCtrl.dispose();
    super.dispose();
  }

  void _clearProfileFeedback() {
    if (!_profileSaved && _profileError == null) return;
    setState(() { _profileSaved = false; _profileError = null; });
  }

  void _clearCompanyFeedback() {
    if (!_companySaved && _companyError == null) return;
    setState(() { _companySaved = false; _companyError = null; });
  }

  Future<void> _loadCompanyStats() async {
    final results = await Future.wait([
      ApiService.fetchStations(),
      ApiService.fetchEmployees(),
    ]);
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (results[0]['success'] == true) {
        _stationCount = (results[0]['stations'] as List).length;
      }
      if (results[1]['success'] == true) {
        _personnelCount = (results[1]['employees'] as List).length;
      }
    });
  }

  Future<void> _handleChangePassword() async {
    setState(() { _pwError = null; _pwSuccess = false; });
    if (_currentPwCtrl.text.isEmpty || _newPwCtrl.text.isEmpty || _confirmPwCtrl.text.isEmpty) {
      setState(() => _pwError = 'Please fill in all password fields.');
      return;
    }
    if (_newPwCtrl.text.length < 8) {
      setState(() => _pwError = 'New password must be at least 8 characters.');
      return;
    }
    if (_newPwCtrl.text != _confirmPwCtrl.text) {
      setState(() => _pwError = 'New passwords do not match.');
      return;
    }

    setState(() => _pwLoading = true);
    final result = await ApiService.changePassword(
      username: widget.username,
      currentPassword: _currentPwCtrl.text,
      newPassword: _newPwCtrl.text,
    );
    if (!mounted) return;

    setState(() {
      _pwLoading = false;
      if (result['success'] == true) {
        _pwSuccess = true;
        _currentPwCtrl.clear();
        _newPwCtrl.clear();
        _confirmPwCtrl.clear();
      } else {
        _pwError = result['error']?.toString() ?? 'Failed to change password.';
      }
    });
  }

  Future<void> _handleSaveProfile() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final org   = _orgCtrl.text.trim();

    // Silently doing nothing here used to read as a dead Save button, so
    // an empty field now explains itself.
    if (name.isEmpty || email.isEmpty) {
      setState(() {
        _profileSaved = false;
        _profileError = name.isEmpty
            ? 'Full Name cannot be empty.'
            : 'Email Address cannot be empty.';
      });
      return;
    }

    setState(() {
      _savedName    = name;
      _savedEmail   = email;
      _savedOrg     = org;
      _profileError = null;
      _profileSaved = true;
    });
    // Written through so the name sticks after leaving Settings and is what
    // the report PDF prints under "Prepared by".
    await ProfileSettings.saveProfile(
      name: name, email: email, organization: org);
  }

  Future<void> _handleSaveCompany() async {
    final company  = _companyCtrl.text.trim();
    final client   = _clientCtrl.text.trim();
    final approved = _approvedCtrl.text.trim();
    final endorsed = _endorsedCtrl.text.trim();

    if (company.isEmpty || client.isEmpty ||
        approved.isEmpty || endorsed.isEmpty) {
      setState(() {
        _companySaved = false;
        _companyError = 'Company Name, Client, Approved By and Endorsed By '
            'cannot be empty.';
      });
      return;
    }

    setState(() {
      _savedCompany    = company;
      _savedClient     = client;
      _savedApprovedBy = approved;
      _savedEndorsedBy = endorsed;
      _companyError    = null;
      _companySaved    = true;
    });
    await ProfileSettings.saveCompany(
      company: company,
      client: client,
      approvedBy: approved,
      endorsedBy: endorsed,
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0]));
    final letters = parts.map((w) => w[0].toUpperCase()).take(3).join();
    return letters.isEmpty ? 'A' : letters;
  }

  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Left sub-nav (scrolls on short windows) ──
                  SingleChildScrollView(child: _buildSubNav()),
                  const SizedBox(width: 20),
                  // ── Right content ──
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // TOP BAR
  // ══════════════════════════════════════════
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2563EB), Color(0xFF1E3A8A)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Settings',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        color: _kText, letterSpacing: -0.3)),
                Text('Manage your account, preferences, and system settings',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _kTextMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kPrimaryLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kPrimary.withOpacity(0.15)),
            ),
            child: const Text('v1.0.0-beta',
                style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: _kPrimary)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // LEFT SUB-NAV
  // ══════════════════════════════════════════
  Widget _buildSubNav() {
    final accountTabs = [
      (_SettingsTab.profile,      Icons.person_rounded,         'Profile Settings'),
      (_SettingsTab.password,     Icons.lock_rounded,           'Password'),
      (_SettingsTab.notifications,Icons.notifications_rounded,  'Notifications'),
    ];
    final systemTabs = [
      (_SettingsTab.scheduleInfo, Icons.calendar_month_rounded, 'Schedule Info'),
      (_SettingsTab.companyInfo,  Icons.business_rounded,       'Company Info'),
      (_SettingsTab.aboutUs,      Icons.info_rounded,           'About Us'),
      // Testing only — absent from a normal release build. See
      // ServerClock.switchAvailable.
      if (ServerClock.switchAvailable)
        (_SettingsTab.developer,  Icons.code_rounded,           'Developer'),
    ];

    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nav header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2563EB), Color(0xFF1E3A8A)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(_savedName.isEmpty ? 'A' : _savedName[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white,
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_savedName,
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700, color: _kText),
                          overflow: TextOverflow.ellipsis),
                      const Text('Supervisor',
                          style: TextStyle(fontSize: 10, color: _kTextMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Nav items, grouped
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _navGroupLabel('ACCOUNT'),
                ...accountTabs.map((t) => _navItem(t.$1, t.$2, t.$3)),
                const SizedBox(height: 10),
                _navGroupLabel('SYSTEM'),
                ...systemTabs.map((t) => _navItem(t.$1, t.$2, t.$3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navGroupLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 1.1, color: _kTextMuted.withOpacity(0.8))),
    );
  }

  Widget _navItem(_SettingsTab tab, IconData icon, String label) {
    final isActive = _activeTab == tab;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? _kPrimaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isActive
                ? Border.all(color: _kPrimary.withOpacity(0.15))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: isActive
                      ? _kPrimary.withOpacity(0.12)
                      : _kSurface,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon,
                    size: 15,
                    color: isActive ? _kPrimary : _kTextMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? _kPrimary : _kTextMuted)),
              ),
              if (isActive)
                Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                      color: _kPrimary, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  // RIGHT CONTENT PANEL
  // ══════════════════════════════════════════
  Widget _buildContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(
        key: ValueKey(_activeTab),
        child: switch (_activeTab) {
          _SettingsTab.profile       => _buildProfilePanel(),
          _SettingsTab.password      => _buildPasswordPanel(),
          _SettingsTab.notifications => _buildNotificationsPanel(),
          _SettingsTab.scheduleInfo  => _buildScheduleInfoPanel(),
          _SettingsTab.companyInfo   => _buildCompanyInfoPanel(),
          _SettingsTab.aboutUs       => _buildAboutUsPanel(),
          _SettingsTab.developer     => _buildDeveloperPanel(),
        },
      ),
    );
  }

  // ── Panel wrapper ──
  Widget _panel({required String title, required String subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: _kText)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(fontSize: 13, color: _kTextMuted)),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorder),
          // Panel content
          Padding(
            padding: const EdgeInsets.all(28),
            child: child,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // 1. PROFILE PANEL
  // ══════════════════════════════════════════
  Widget _buildProfilePanel() {
    return _panel(
      title: 'Profile Settings',
      subtitle: 'Update your account information and role details.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar row
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Center(
                      child: Text(_savedName.isEmpty ? 'A' : _savedName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white,
                              fontSize: 32, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kBorder, width: 1.5),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 14, color: _kTextMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_savedName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18,
                            fontWeight: FontWeight.w800, color: _kText)),
                    const SizedBox(height: 4),
                    Text(_savedEmail,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: _kTextMuted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kSuccess.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kSuccess.withOpacity(0.3)),
                      ),
                      child: const Text('Supervisor',
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700, color: _kSuccess)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 28),

          // Info grid
          _fieldRow(
            left: _editField('Full Name', _nameCtrl),
            right: _readOnlyField('Role', 'Supervisor'),
          ),
          const SizedBox(height: 20),
          _fieldRow(
            left: _editField('Email Address', _emailCtrl),
            right: _editField('Organization', _orgCtrl),
          ),
          const SizedBox(height: 28),

          if (_profileError != null) ...[
            _feedbackBanner(_profileError!, isError: true),
            const SizedBox(height: 16),
          ],
          if (_profileSaved) ...[
            _feedbackBanner('Profile updated successfully!', isError: false),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _handleSaveProfile,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // 2. PASSWORD PANEL
  // ══════════════════════════════════════════
  Widget _buildPasswordPanel() {
    return _panel(
      title: 'Change Password',
      subtitle: 'Update your password to keep your account secure.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pwField('Current Password', _currentPwCtrl, _showCurrent,
                    () => setState(() => _showCurrent = !_showCurrent)),
            const SizedBox(height: 20),
            _pwField('New Password', _newPwCtrl, _showNew,
                    () => setState(() => _showNew = !_showNew)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 5),
                Text('Minimum 8 characters required.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ],
            ),
            const SizedBox(height: 20),
            _pwField('Confirm New Password', _confirmPwCtrl, _showConfirm,
                    () => setState(() => _showConfirm = !_showConfirm)),
            const SizedBox(height: 24),

            if (_pwError != null) ...[
              _feedbackBanner(_pwError!, isError: true),
              const SizedBox(height: 16),
            ],
            if (_pwSuccess) ...[
              _feedbackBanner('Password updated successfully!', isError: false),
              const SizedBox(height: 16),
            ],

            ElevatedButton(
              onPressed: _pwLoading ? null : _handleChangePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: _pwLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  // 3. NOTIFICATIONS PANEL
  // ══════════════════════════════════════════
  Widget _buildNotificationsPanel() {
    // The preference is app-wide and persisted: the Notifications inbox
    // reads the same value and mutes itself when alerts are off.
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationSettings.allowNotifications,
      builder: (context, allowed, _) => _panel(
        title: 'Notification Settings',
        subtitle: 'Control whether the system sends you alerts.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _notifTile(
              icon: allowed
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: allowed ? _kPrimary : _kTextMuted,
              title: 'Allow Notifications',
              subtitle: 'Receive alerts for absences, reliever assignments, '
                  'published schedules, and unassigned shifts.',
              value: allowed,
              onChanged: (v) => NotificationSettings.setAllowed(v),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: allowed
                    ? _kSuccess.withOpacity(0.08)
                    : _kSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: allowed ? _kSuccess.withOpacity(0.25) : _kBorder),
              ),
              child: Row(
                children: [
                  Icon(
                      allowed
                          ? Icons.check_circle_outline_rounded
                          : Icons.notifications_paused_rounded,
                      size: 16,
                      color: allowed ? _kSuccess : _kTextMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      allowed
                          ? 'Notifications are on — new alerts will appear in the Notifications inbox.'
                          : 'Notifications are off — the Notifications inbox is muted until you turn them back on. This choice is remembered.',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: allowed ? _kSuccess : _kTextMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  // 4. SCHEDULE INFO PANEL
  // ══════════════════════════════════════════
  Widget _buildScheduleInfoPanel() {
    return _panel(
      title: 'Schedule Configuration',
      subtitle: 'Shift times and security positions used by Generate Schedule.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift configuration
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Shift Configuration',
                        style: TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700, color: _kText)),
                    SizedBox(height: 4),
                    Text('Shift times applied by Generate Schedule, including head guard shifts. '
                        'Guards may report earlier for mandatory meetings.',
                        style: TextStyle(fontSize: 12, color: _kTextMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _addButton('Add Shift', _showAddShiftDialog),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: _shifts.map((s) => SizedBox(
              width: 280,
              child: _shiftCard(s),
            )).toList(),
          ),
          const SizedBox(height: 28),

          // Positions list
          Row(
            children: [
              const Expanded(
                child: Text('Security Positions',
                    style: TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w700, color: _kText)),
              ),
              const SizedBox(width: 16),
              _addButton('Add Position', _showAddPositionDialog),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _positions.asMap().entries.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${e.key + 1}',
                          style: const TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w800, color: _kPrimary)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(e.value,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600, color: _kText)),
                  const SizedBox(width: 7),
                  GestureDetector(
                    onTap: () => setState(() => _positions.removeAt(e.key)),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: _kTextMuted),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _kPrimary,
        side: BorderSide(color: _kPrimary.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  void _showAddShiftDialog() {
    final nameCtrl  = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl   = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Add Shift',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kText)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField('Shift Name', nameCtrl, hint: 'e.g. Mid Shift'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _dialogField('Start Time', startCtrl, hint: 'e.g. 0900H')),
                    const SizedBox(width: 12),
                    Expanded(child: _dialogField('End Time', endCtrl, hint: 'e.g. 1800H')),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600, color: _kDanger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: _kTextMuted, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () {
                final name  = nameCtrl.text.trim();
                final start = startCtrl.text.trim();
                final end   = endCtrl.text.trim();
                if (name.isEmpty || start.isEmpty || end.isEmpty) {
                  setDialogState(() => error = 'Please fill in all fields.');
                  return;
                }
                if (_shifts.any((s) => s.label.toLowerCase() == name.toLowerCase())) {
                  setDialogState(() => error = 'A shift with that name already exists.');
                  return;
                }
                setState(() {
                  _shifts.add(_ShiftEntry(
                    label: name,
                    time: '$start – $end',
                    icon: Icons.access_time_rounded,
                    color: _customShiftColors[_nextShiftColor % _customShiftColors.length],
                  ));
                  _nextShiftColor++;
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Add Shift',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPositionDialog() {
    final nameCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Add Security Position',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kText)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField('Position Name', nameCtrl, hint: 'e.g. Gate Guard'),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600, color: _kDanger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: _kTextMuted, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'Please enter a position name.');
                  return;
                }
                if (_positions.any((p) => p.toLowerCase() == name.toLowerCase())) {
                  setDialogState(() => error = 'That position already exists.');
                  return;
                }
                setState(() => _positions.add(name));
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Add Position',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  // 5. COMPANY INFO PANEL
  // ══════════════════════════════════════════
  Widget _buildCompanyInfoPanel() {
    final stationsValue = _statsLoading
        ? 'Loading…'
        : (_stationCount != null ? '$_stationCount LRT Stations' : 'Unavailable');
    final personnelValue = _statsLoading
        ? 'Loading…'
        : (_personnelCount != null ? '$_personnelCount Guards' : 'Unavailable');

    return _panel(
      title: 'Company Information',
      subtitle: 'Details about $_savedCompany used across the system.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + name
          Row(
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(_initials(_savedCompany),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_savedCompany.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w900, color: _kText, letterSpacing: 0.3)),
                    const SizedBox(height: 4),
                    const Text('Security Services Provider',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: _kTextMuted)),
                    const SizedBox(height: 8),
                    Text('Client: $_savedClient',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: _kTextMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 28),

          _fieldRow(
            left: _editField('Company Name', _companyCtrl),
            right: _editField('Client', _clientCtrl),
          ),
          const SizedBox(height: 20),
          _fieldRow(
            left: _readOnlyField('Total Stations Covered', stationsValue),
            right: _readOnlyField('Total Security Personnel', personnelValue),
          ),
          const SizedBox(height: 20),
          _fieldRow(
            left: _readOnlyField('Schedule System Version', 'v1.0.0-beta'),
            right: _readOnlyField('Report Period', 'Bi-Weekly'),
          ),

          const SizedBox(height: 28),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 24),

          // ── Report signatories ──
          const Text('Report Signatories',
              style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: _kText)),
          const SizedBox(height: 4),
          const Text('Printed as three evenly spaced signature blocks at the '
              'bottom of every exported schedule report PDF.',
              style: TextStyle(fontSize: 12, color: _kTextMuted)),
          const SizedBox(height: 16),
          _signatoryRow(
            left: _readOnlyField('Prepared By', _savedName),
            middle: _editField('Approved By', _approvedCtrl),
            right: _editField('Endorsed By', _endorsedCtrl),
          ),
          const SizedBox(height: 8),
          const Text('Prepared By always follows the name in Profile Settings '
              '— it is whoever produced the schedule.',
              style: TextStyle(fontSize: 11, color: _kTextMuted)),
          const SizedBox(height: 28),

          if (_companyError != null) ...[
            _feedbackBanner(_companyError!, isError: true),
            const SizedBox(height: 16),
          ],
          if (_companySaved) ...[
            _feedbackBanner('Company information updated!', isError: false),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _handleSaveCompany,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Station and personnel totals are pulled live from the system. '
                  'Saved signatories apply to every report exported from now on.',
                  style: TextStyle(fontSize: 12, color: _kTextMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // 6. ABOUT US PANEL
  // ══════════════════════════════════════════
  Widget _buildAboutUsPanel() {
    return _panel(
      title: 'About Us',
      subtitle: 'Learn more about this system and the team behind it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Centered logo + system name (placeholder design)
          Center(
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Raw logo — the panel is white, so the blue variant works
                // without any backing.
                Image.asset(
                  'assets/logo/sched_logo.png',
                  width: 110,
                  height: 110,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(height: 18),
                const Text('Sched',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                        color: _kText, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                const Text('Security Guard Scheduling System',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: _kTextMuted)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kPrimaryLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kPrimary.withOpacity(0.15)),
                  ),
                  child: const Text('v1.0.0-beta',
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w700, color: _kPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 24),

          // Normal left-aligned content, matching the other panels
          const Text('About This System',
              style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: _kText)),
          const SizedBox(height: 8),
          const Text(
            'Sched automates the scheduling of security personnel across '
            'LRT stations. It generates fair bi-weekly duty rosters, tracks '
            'attendance, and finds qualified relievers for absent guards — '
            'replacing hours of manual plotting with a few clicks, so '
            'operations officers can focus on keeping stations safe.',
            style: TextStyle(fontSize: 13, color: _kTextMuted, height: 1.6),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              const Icon(Icons.code_rounded, size: 16, color: _kPrimary),
              const SizedBox(width: 8),
              const Text('Built by Team ',
                  style: TextStyle(fontSize: 13, color: _kTextMuted)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('KamoteCoder',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contact Us',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: _kText)),
                const SizedBox(height: 12),
                _contactRow(Icons.email_rounded, 'kamotecoder.team@gmail.com'),
                const SizedBox(height: 8),
                _contactRow(Icons.phone_rounded, '+63 912 345 6789'),
                const SizedBox(height: 8),
                _contactRow(Icons.location_on_rounded, 'Manila, Philippines'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _kPrimary),
        const SizedBox(width: 8),
        Text(value,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w500, color: _kTextMuted)),
      ],
    );
  }

  // ══════════════════════════════════════════
  // SHARED HELPERS
  // ══════════════════════════════════════════
  Widget _fieldRow({required Widget left, required Widget right}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 20),
        Expanded(child: right),
      ],
    );
  }

  // Three equal-width columns with breathing room between them — the same
  // even split the signature blocks get in the exported PDF.
  Widget _signatoryRow({
    required Widget left,
    required Widget middle,
    required Widget right,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 24),
        Expanded(child: middle),
        const SizedBox(width: 24),
        Expanded(child: right),
      ],
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: _kText)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w500, color: _kTextMuted)),
        ),
      ],
    );
  }

  Widget _editField(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: _kText)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w500, color: _kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: _kSurface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: _kText)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          autofocus: label.contains('Name'),
          style: const TextStyle(fontSize: 13, color: _kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            filled: true,
            fillColor: _kSurface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _feedbackBanner(String message, {required bool isError}) {
    final color = isError ? _kDanger : _kSuccess;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _pwField(String label, TextEditingController ctrl,
      bool visible, VoidCallback toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: _kText)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: !visible,
          style: const TextStyle(fontSize: 13, color: _kText),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(color: Colors.grey[400]),
            suffixIcon: IconButton(
              icon: Icon(
                  visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18, color: _kTextMuted),
              onPressed: toggle,
            ),
            filled: true,
            fillColor: _kSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════
  // 7. DEVELOPER PANEL  (testing builds only)
  // ══════════════════════════════════════════
  //
  // Holds the device-time override. It lives here, in admin Settings,
  // rather than in the shared guard profile: every guard role uses that
  // one view, so putting it there handed a head guard a switch that would
  // let them move their own duty window off the server clock. Turning it
  // ON additionally re-checks the admin's password.
  Widget _buildDeveloperPanel() {
    return ValueListenableBuilder<bool>(
      valueListenable: ServerClock.useDeviceTime,
      builder: (context, useDevice, _) => _panel(
        title: 'Developer',
        subtitle: 'Testing tools. Not available in a production build.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _notifTile(
              icon: useDevice
                  ? Icons.phonelink_erase_rounded
                  : Icons.cloud_done_rounded,
              color: useDevice ? _kWarning : _kPrimary,
              title: 'Use device time',
              subtitle: 'Drive duty windows off this device\'s clock instead '
                  'of the server\'s, so the after-midnight HG Night window '
                  'can be tested without waiting until 2 AM.',
              value: useDevice,
              onChanged: _onDeviceTimeToggled,
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: useDevice ? _kWarning.withOpacity(0.08) : _kSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: useDevice ? _kWarning.withOpacity(0.25) : _kBorder),
              ),
              child: Row(
                children: [
                  Icon(
                      useDevice
                          ? Icons.warning_amber_rounded
                          : Icons.verified_user_outlined,
                      size: 16,
                      color: useDevice ? _kWarning : _kTextMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _clockStatusLine(useDevice),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: useDevice ? _kWarning : _kTextMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _clockStatusLine(bool useDevice) {
    if (useDevice) {
      return 'Device time is ON — duty windows follow this machine\'s clock '
          'and can be moved by changing it. Turn this off before testing '
          'anything that depends on real timing.';
    }
    if (!ServerClock.isSynced) {
      return 'Server time has not been reached yet — falling back to this '
          'device\'s clock until it syncs.';
    }
    final skew = ServerClock.skew;
    if (skew.inSeconds.abs() < 2) {
      return 'Using server time. This device is in step with the server.';
    }
    final off = skew.abs();
    final amount =
        off.inMinutes >= 1 ? '${off.inMinutes} min' : '${off.inSeconds} sec';
    return 'Using server time. This device is $amount '
        '${skew.isNegative ? 'ahead of' : 'behind'} the server, and is being '
        'corrected.';
  }

  // Turning the override OFF returns to the safe state, so it is free.
  // Turning it ON is re-authenticated against the admin's own password.
  Future<void> _onDeviceTimeToggled(bool value) async {
    if (!value) {
      await ServerClock.setUseDeviceTime(false);
      return;
    }
    final ok = await _promptForPassword();
    if (ok) await ServerClock.setUseDeviceTime(true);
  }

  Future<bool> _promptForPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _PasswordPrompt(
        username: widget.username,
        controller: controller,
      ),
    );
    controller.dispose();
    return result == true;
  }

  Widget _notifTile({
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: _kText)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: _kTextMuted)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(value: value, onChanged: onChanged, activeThumbColor: _kPrimary),
        ],
      ),
    );
  }

  Widget _shiftCard(_ShiftEntry shift) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: shift.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: shift.color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: shift.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(shift.icon, color: shift.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shift.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: shift.color)),
                const SizedBox(height: 2),
                Text(shift.time,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _kTextMuted)),
              ],
            ),
          ),
          if (!shift.isDefault) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _shifts.remove(shift)),
              child: Icon(Icons.close_rounded, size: 16, color: _kTextMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Re-authentication prompt for enabling Developer mode.
//
// The password is checked by the server (POST /verify-password) against
// the admin's own stored credential — it is never compared to
// anything held in the app, and no password is stored here.
// ─────────────────────────────────────────────
class _PasswordPrompt extends StatefulWidget {
  final String username;
  final TextEditingController controller;

  const _PasswordPrompt({required this.username, required this.controller});

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    final password = widget.controller.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.verifyPassword(
      username: widget.username,
      password: password,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _loading = false;
      _error = ApiService.friendlyError(
          result['error']?.toString() ?? 'Password is incorrect.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Confirm your password',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: _kText)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Turning on device time lets duty windows be moved by changing '
            'this machine\'s clock. Enter your password to continue.',
            style: TextStyle(fontSize: 13, color: _kTextMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            obscureText: _obscure,
            autofocus: true,
            enabled: !_loading,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : const Text('Turn On',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
