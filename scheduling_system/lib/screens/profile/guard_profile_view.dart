// screens/profile/guard_profile_view.dart
//
// Shared Profile tab for every guard-facing mobile account — regular,
// reliever and head guard. SecurityProfileScreen and
// HeadGuardProfileScreen are thin wrappers around this widget so all
// three roles behave identically:
//   - Preferred Stations opens a picker listing every station and saves
//     the selection to the employee's record.
//   - Every Settings and Support & Legal row is functional.
//   - Log Out asks for confirmation before returning to sign-in.
import 'package:flutter/material.dart';
import '../../models/employee.dart';
import '../../models/guard_shift.dart';
import '../../models/station.dart';
import '../../services/api_service.dart';
import '../../services/notification_center.dart';
import '../../services/notification_settings.dart';
import '../../services/session.dart';
import '../login_screen.dart';
import 'info_pages.dart';
import 'profile_change_password_screen.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kInk = Color(0xFF1E293B);

class GuardProfileView extends StatefulWidget {
  final Employee employee;

  const GuardProfileView({super.key, required this.employee});

  @override
  State<GuardProfileView> createState() => _GuardProfileViewState();
}

class _GuardProfileViewState extends State<GuardProfileView> {
  // Local copy so the Preferred Stations picker can refresh the display
  // immediately after a save, before the layout re-fetches the record.
  late Employee _employee;

  static const List<String> _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
  }

  @override
  void didUpdateWidget(covariant GuardProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee != widget.employee) {
      _employee = widget.employee;
    }
  }

  String get _dateJoinedLabel {
    final d = _employee.dateJoined;
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  // --- Log out -----------------------------------------------------------

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Log Out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _kInk,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of Sched? You will need to '
          'sign in again to see your schedule.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Log Out',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Forget the persisted session and stop the alert polling — only an
    // explicit Log Out sends the user back to the login screen.
    NotificationCenter.instance.stop();
    await Session.clear();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AuthScreen()),
      (route) => false,
    );
  }

  // --- Preferred stations ------------------------------------------------

  Future<void> _openPreferredStationsPicker() async {
    final updated = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PreferredStationsSheet(employee: _employee),
    );

    if (updated != null && mounted) {
      setState(() => _employee = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Preferred stations updated.'),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // --- Settings ----------------------------------------------------------

  void _openChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ProfileChangePasswordScreen(employee: _employee),
      ),
    );
  }

  void _showNotificationPreferences() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _sheetHandle()),
              const SizedBox(height: 16),
              const Text(
                'Notification Preferences',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Control the alerts Sched shows you.',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: NotificationSettings.allowNotifications,
                  builder: (context, allowed, _) => SwitchListTile(
                    value: allowed,
                    onChanged: (v) => NotificationSettings.setAllowed(v),
                    activeThumbColor: _kBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    title: const Text(
                      'Allow notifications',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kInk,
                      ),
                    ),
                    subtitle: Text(
                      'Duty calls, schedule updates and announcements in '
                      'your Alerts tab.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'When turned off, the Alerts tab shows a muted notice '
                'until you turn notifications back on.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageSheet() {
    _showChoiceSheet(
      title: 'Language',
      subtitle: 'Choose the language Sched uses.',
      options: const [
        _ChoiceOption(label: 'English', selected: true),
        _ChoiceOption(label: 'Filipino', enabled: false, note: 'Coming soon'),
      ],
    );
  }

  void _showAppearanceSheet() {
    _showChoiceSheet(
      title: 'Appearance',
      subtitle: 'Choose how Sched looks on this device.',
      options: const [
        _ChoiceOption(label: 'Light', selected: true),
        _ChoiceOption(label: 'Dark', enabled: false, note: 'Coming soon'),
      ],
    );
  }

  void _showChoiceSheet({
    required String title,
    required String subtitle,
    required List<_ChoiceOption> options,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _sheetHandle()),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              ...options
                  .map((option) => _buildChoiceRow(sheetContext, option)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceRow(BuildContext sheetContext, _ChoiceOption option) {
    return GestureDetector(
      onTap:
          option.enabled ? () => Navigator.of(sheetContext).pop() : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: option.selected
              ? _kBlue.withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: option.selected ? _kBlue : const Color(0xFFE2E8F0),
            width: option.selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: option.enabled ? _kInk : Colors.grey[400],
                ),
              ),
            ),
            if (option.selected)
              const Icon(Icons.check_circle, color: _kBlue, size: 20),
            if (option.note != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  option.note!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHandle() {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // --- Row data -----------------------------------------------------------

  List<Map<String, dynamic>> get _personalInfo => [
        {
          'label': 'Employee ID',
          'value': _employee.username.isNotEmpty
              ? _employee.username
              : _employee.id,
          'icon': Icons.badge_outlined,
        },
        {
          'label': 'Assigned Station',
          'value': _employee.assignedStation ?? 'Floating / As assigned',
          'icon': Icons.location_on_outlined,
        },
        {
          'label': 'Shift',
          'value': assignedShiftLabel(_employee.assignedShift),
          'icon': Icons.access_time,
        },
        {
          'label': 'Preferred Stations',
          'value': _employee.preferredStations.isEmpty
              ? 'None set — tap to choose'
              : _employee.preferredStations.join(', '),
          'icon': Icons.star_outline,
          'onTap': _openPreferredStationsPicker,
        },
        {
          'label': 'Date Joined',
          'value': _dateJoinedLabel,
          'icon': Icons.calendar_today_outlined,
        },
      ];

  List<Map<String, dynamic>> get _contactInfo => [
        {
          'label': 'Email Address',
          'value':
              _employee.email.isNotEmpty ? _employee.email : 'Not provided',
          'icon': Icons.email_outlined,
        },
        {
          'label': 'Phone Number',
          'value':
              _employee.phone.isNotEmpty ? _employee.phone : 'Not provided',
          'icon': Icons.phone_outlined,
        },
      ];

  List<Map<String, dynamic>> get _settings => [
        {
          'label': 'Notification Preferences',
          'icon': Icons.notifications_outlined,
          'trailing':
              NotificationSettings.allowNotifications.value ? 'On' : 'Off',
          'onTap': _showNotificationPreferences,
        },
        {
          'label': 'Change Password',
          'icon': Icons.lock_outlined,
          'trailing': '',
          'onTap': _openChangePassword,
        },
        {
          'label': 'Language',
          'icon': Icons.language,
          'trailing': 'English',
          'onTap': _showLanguageSheet,
        },
        {
          'label': 'Appearance',
          'icon': Icons.dark_mode_outlined,
          'trailing': 'Light',
          'onTap': _showAppearanceSheet,
        },
      ];

  List<Map<String, dynamic>> get _support => [
        {
          'label': 'Privacy Policy',
          'icon': Icons.shield_outlined,
          'trailing': '',
          'onTap': () => openPrivacyPolicy(context),
        },
        {
          'label': 'Terms of Service',
          'icon': Icons.description_outlined,
          'trailing': '',
          'onTap': () => openTermsOfService(context),
        },
        {
          'label': 'Help & Support',
          'icon': Icons.help_outline,
          'trailing': '',
          'onTap': () => openHelpSupport(context),
        },
        {
          'label': 'About Sched',
          'icon': Icons.info_outline,
          'trailing': 'v1.0.0',
          'onTap': () => openAboutSched(context),
        },
      ];

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1034A6),
                      Color(0xFF1E4AD0),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _employee.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _employee.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                employeeTypeToRoleString(_employee.type),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _buildSectionTitle('Personal Information'),
              const SizedBox(height: 12),
              _buildInfoList(_personalInfo),

              const SizedBox(height: 24),

              _buildSectionTitle('Contact'),
              const SizedBox(height: 12),
              _buildInfoList(_contactInfo),

              const SizedBox(height: 24),

              _buildSectionTitle('Settings'),
              const SizedBox(height: 12),
              // Rebuilds the list when the notifications toggle changes so
              // the On/Off trailing label stays current.
              ValueListenableBuilder<bool>(
                valueListenable: NotificationSettings.allowNotifications,
                builder: (context, _, _) => _buildSettingsList(_settings),
              ),

              const SizedBox(height: 24),

              _buildSectionTitle('Support & Legal'),
              const SizedBox(height: 12),
              _buildSettingsList(_support),

              const SizedBox(height: 24),

              // Log Out
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: _confirmLogout,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.logout,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Log Out',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _kInk,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoList(List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final VoidCallback? onTap = item['onTap'];
            return Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            item['icon'],
                            color: _kBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['label'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['value'],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _kInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onTap != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (index < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: Colors.grey[200],
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSettingsList(List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final VoidCallback? onTap = item['onTap'];
            final String trailing = item['trailing'] ?? '';
            return Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            item['icon'],
                            color: _kBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _kInk,
                            ),
                          ),
                        ),
                        if (trailing.isNotEmpty)
                          Text(
                            trailing,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                if (index < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: Colors.grey[200],
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ChoiceOption {
  final String label;
  final bool selected;
  final bool enabled;
  final String? note;

  const _ChoiceOption({
    required this.label,
    this.selected = false,
    this.enabled = true,
    this.note,
  });
}

// --- Preferred stations picker sheet ---------------------------------------

class _PreferredStationsSheet extends StatefulWidget {
  final Employee employee;

  const _PreferredStationsSheet({required this.employee});

  @override
  State<_PreferredStationsSheet> createState() =>
      _PreferredStationsSheetState();
}

class _PreferredStationsSheetState extends State<_PreferredStationsSheet> {
  bool _loading = true;
  String? _error;
  List<Station> _stations = [];
  late final Set<String> _selected =
      widget.employee.preferredStations.toSet();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.fetchStations();
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _stations = (result['stations'] as List)
            .cast<Station>()
            .where((s) => s.isActive)
            .toList();
      } else {
        _error = ApiService.friendlyError(
            result['error']?.toString() ?? 'Failed to load stations');
      }
    });
  }

  // Saved in the same order the stations are listed; any previously
  // saved name that no longer matches a station is kept at the end.
  List<String> get _orderedSelection {
    final ordered = _stations
        .map((s) => s.name)
        .where(_selected.contains)
        .toList();
    for (final name in _selected) {
      if (!ordered.contains(name)) ordered.add(name);
    }
    return ordered;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final result = await ApiService.updateEmployee(
      widget.employee.id,
      preferredStations: _orderedSelection,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pop(result['employee'] as Employee);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ApiService.friendlyError(
              result['error']?.toString() ?? 'Failed to save')),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preferred Stations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select the stations you prefer to be assigned to. '
                      'The admin sees these when placing you.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildContent()),
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kBlue.withOpacity(0.5),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Text(
                              _selected.isEmpty
                                  ? 'Save (no preference)'
                                  : 'Save ${_selected.length} '
                                      'station${_selected.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kBlue),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 44, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                'Could not load stations',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadStations,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_stations.isEmpty) {
      return Center(
        child: Text(
          'No stations available yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _stations.length,
      itemBuilder: (context, index) => _buildStationRow(_stations[index]),
    );
  }

  Widget _buildStationRow(Station station) {
    final bool selected = _selected.contains(station.name);
    return GestureDetector(
      onTap: _saving
          ? null
          : () => setState(() {
                if (selected) {
                  _selected.remove(station.name);
                } else {
                  _selected.add(station.name);
                }
              }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _kBlue.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kBlue : const Color(0xFFE2E8F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: _kBlue,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                station.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kInk,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? _kBlue : Colors.grey[300],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
