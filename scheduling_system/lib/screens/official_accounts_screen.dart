import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../widgets/controller_dialog.dart';

class OfficialAccountsScreen extends StatefulWidget {
  final bool embedded;
  const OfficialAccountsScreen({super.key, this.embedded = false});
  @override
  State<OfficialAccountsScreen> createState() => _OfficialAccountsScreenState();
}

class _OfficialAccountsScreenState extends State<OfficialAccountsScreen> {
  List<Map<String, dynamic>> _users = [];
  String? _error;
  bool _loading = true;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ApiService.workflow('/officials');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = result['success'] == true ? null : result['error'].toString();
      if (_error == null) _users = approvalMaps(result['users']);
    });
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _credentials(
    String username,
    String password,
  ) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Account credentials'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share these credentials with the official. The password is shown only now. They can change it from Profile.',
            ),
            const SizedBox(height: 16),
            SelectableText('Username: $username\nPassword: $password'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: 'Username: $username\nPassword: $password'),
            );
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _create() async {
    final name = TextEditingController();
    final username = TextEditingController();
    var role = 'assistantSecurity';
    String? error;
    final form = GlobalKey<FormState>();
    var saving = false;
    Map<String, dynamic>? created;
    await showControllerDialog<void>(
      context: context,
      controllers: [name, username],
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: const Text('Create official account'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter the full name.'
                        : null,
                  ),
                  TextFormField(
                    controller: username,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (v) =>
                        RegExp(r'^[A-Za-z0-9_.-]{3,40}$').hasMatch(v ?? '')
                        ? null
                        : 'Use 3–40 letters, digits, periods, underscores or hyphens.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: ['assistantSecurity', 'areaCommander']
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(officialRoleLabel(r)),
                          ),
                        )
                        .toList(),
                    onChanged: saving ? null : (v) => role = v!,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'A password will be generated after you create the account. Copy it from the credentials window and share it with the official.',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      update(() => saving = true);
                      final result = await ApiService.workflow(
                        '/officials',
                        method: 'POST',
                        body: {
                          'name': name.text.trim(),
                          'username': username.text.trim(),
                          'role': role,
                        },
                      );
                      if (!ctx.mounted) return;
                      if (result['success'] == true) {
                        created = result;
                        Navigator.pop(ctx);
                      } else {
                        update(() {
                          saving = false;
                          error = result['error'].toString();
                        });
                      }
                    },
              child: Text(saving ? 'Creating…' : 'Create Account'),
            ),
          ],
        ),
      ),
    );
    final accountName = username.text.trim();
    if (created != null && mounted) {
      await _credentials(accountName, created!['temporaryPassword']);
      await _load();
    }
  }

  Future<void> _change(Map<String, dynamic> user, bool reset) async {
    final active = user['active'] != false;
    final action = reset
        ? 'Reset password'
        : active
        ? 'Deactivate account'
        : 'Activate account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action?'),
        content: Text(
          '${user['name']} (${user['username']})${reset || active ? '\nExisting sessions will be signed out.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ApiService.workflow(
      '/officials/${user['username']}${reset ? '/reset-password' : ''}',
      method: reset ? 'POST' : 'PUT',
      body: reset ? null : {'active': !active},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result['success'] != true) {
      _message(result['error'].toString());
      return;
    }
    if (reset) {
      await _credentials(user['username'], result['temporaryPassword']);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: widget.embedded,
    physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
    padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(28),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Official Accounts',
              style: TextStyle(
                fontSize: widget.embedded ? 20 : 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add Official'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Assistant Security and Area Commander review all stations. These accounts are excluded from guard scheduling.',
      ),
      const SizedBox(height: 24),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
      if (!_loading && _users.isEmpty && _error == null)
        const Text('Create one account for each official role to begin.'),
      for (final u in _users)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 32,
                      color: Color(0xFF1034A6),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u['name'] ?? u['username'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            '${officialRoleLabel(u['role'])} · ${u['username']} · ${u['active'] == false ? 'Inactive' : 'Active'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _change(u, true),
                      child: const Text('Reset Password'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _change(u, false),
                      child: Text(
                        u['active'] == false ? 'Activate' : 'Deactivate',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
