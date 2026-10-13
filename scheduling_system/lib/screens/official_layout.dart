import 'package:flutter/material.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../widgets/workflow_inbox.dart';
import 'approval_screen.dart';
import 'login_screen.dart';

class OfficialLayout extends StatefulWidget {
  final String username;
  final String role;
  const OfficialLayout({super.key, required this.username, required this.role});
  @override
  State<OfficialLayout> createState() => _OfficialLayoutState();
}

class _OfficialLayoutState extends State<OfficialLayout> {
  bool _profile = false;
  bool _saving = false;
  String _name = '';
  String? _error;
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = await ApiService.workflow('/account');
    if (mounted && account['success'] == true) {
      setState(() => _name = account['name']);
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _save() async {
    if (_password.text.length < 8 || _password.text != _confirm.text) {
      setState(
        () => _error = 'Use at least 8 characters and matching new passwords.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ApiService.changePassword(
      username: widget.username,
      currentPassword: _current.text,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = result['success'] == true ? null : result['error'].toString();
    });
    if (result['success'] == true) {
      _current.clear();
      _password.clear();
      _confirm.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        Container(
          width: 250,
          color: const Color(0xFF1034A6),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Sched',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '${_name.isEmpty ? widget.username : _name}\n${officialRoleLabel(widget.role)}',
                    style: const TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  selected: !_profile,
                  selectedTileColor: Colors.white12,
                  leading: const Icon(
                    Icons.fact_check_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Period Approvals',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => setState(() => _profile = false),
                ),
                WorkflowInboxButton(role: widget.role, color: Colors.white),
                ListTile(
                  selected: _profile,
                  selectedTileColor: Colors.white12,
                  leading: const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Profile',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => setState(() => _profile = true),
                ),
                const Spacer(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.white),
                  title: const Text(
                    'Log Out',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: _logout,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Expanded(
          child: !_profile
              ? ApprovalScreen(role: widget.role)
              : ListView(
                  padding: const EdgeInsets.all(36),
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(_name, style: const TextStyle(fontSize: 20)),
                    Text(
                      '${widget.username} · ${officialRoleLabel(widget.role)}',
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Change Password',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final field in [
                      (_current, 'Current password'),
                      (_password, 'New password'),
                      (_confirm, 'Confirm new password'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 440,
                            child: TextField(
                              controller: field.$1,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: field.$2,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving…' : 'Change Password'),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}
