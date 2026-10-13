import 'package:flutter/material.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../widgets/workflow_inbox.dart';
import 'approval_screen.dart';
import 'login_screen.dart';
import 'official_profile_screen.dart';

class OfficialLayout extends StatefulWidget {
  final String username;
  final String role;
  const OfficialLayout({super.key, required this.username, required this.role});
  @override
  State<OfficialLayout> createState() => _OfficialLayoutState();
}

class _OfficialLayoutState extends State<OfficialLayout> {
  bool _profile = false;
  bool _loggingOut = false;
  String _name = '';
  String get _displayName => _name.isEmpty ? widget.username : _name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = await ApiService.workflow('/account');
    if (mounted && account['success'] == true) {
      setState(() => _name = account['name']?.toString() ?? widget.username);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of Sched?'),
        content: const Text('You will return to the sign-in screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _loggingOut = false);
      return;
    }
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Widget _navigation({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Material(
      color: selected
          ? Colors.white.withValues(alpha: .13)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? Colors.white.withValues(alpha: .17)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Icon(
          icon,
          size: 21,
          color: selected ? Colors.white : const Color(0xFFAFBFE8),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFCCD6EE),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
      ),
    ),
  );

  Widget _sidebar() => Container(
    width: 250,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF101F46), Color(0xFF172F68)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 18, 24),
            child: Row(
              children: [
                Image.asset(
                  'assets/logo/kaizen_logo.png',
                  width: 42,
                  height: 46,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sched',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'OFFICIAL PORTAL',
                        style: TextStyle(
                          color: Color(0xFF91A8D8),
                          fontSize: 9,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2B3F68)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 22),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(26, 0, 16, 12),
                  child: Text(
                    'WORKSPACE',
                    style: TextStyle(
                      color: Color(0xFF91A8D8),
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _navigation(
                  icon: Icons.fact_check_outlined,
                  label: 'Period Approvals',
                  selected: !_profile,
                  onTap: () => setState(() => _profile = false),
                ),
                WorkflowInboxButton(role: widget.role, color: Colors.white),
                _navigation(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  selected: _profile,
                  onTap: () => setState(() => _profile = true),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .09),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: Color(0xFF92B6FF),
                        size: 22,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.role == 'assistantSecurity'
                            ? 'First review'
                            : 'Final approval',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Overseeing schedules across all stations.',
                        style: TextStyle(
                          color: Color(0xFFADBFDF),
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2B3F68)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF36558D),
                  child: Text(
                    officialInitials(_displayName),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        officialRoleLabel(widget.role),
                        style: const TextStyle(
                          color: Color(0xFFAFC0E1),
                          fontSize: 10,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: TextButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: const Icon(Icons.logout_rounded, size: 17),
              label: Text(_loggingOut ? 'Signing out...' : 'Log Out'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFCAD7F0),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        _sidebar(),
        Expanded(
          child: !_profile
              ? ApprovalScreen(role: widget.role)
              : OfficialProfileScreen(
                  username: widget.username,
                  role: widget.role,
                  initialName: _name,
                  onNameChanged: (name) {
                    if (mounted) setState(() => _name = name);
                  },
                ),
        ),
      ],
    ),
  );
}
