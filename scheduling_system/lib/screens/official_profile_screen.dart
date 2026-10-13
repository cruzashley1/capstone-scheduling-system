import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import 'approval_screen.dart';

const _ink = Color(0xFF14213D);
const _muted = Color(0xFF64748B);
const _blue = Color(0xFF1034A6);
const _border = Color(0xFFE2E8F0);

String officialInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'O';
  return (words.first.characters.first +
          (words.length > 1 ? words.last.characters.first : ''))
      .toUpperCase();
}

enum _ProfileTab { overview, decisions, security }

class OfficialProfileScreen extends StatefulWidget {
  final String username;
  final String role;
  final String initialName;
  final ValueChanged<String> onNameChanged;
  const OfficialProfileScreen({
    super.key,
    required this.username,
    required this.role,
    required this.initialName,
    required this.onNameChanged,
  });

  @override
  State<OfficialProfileScreen> createState() => _OfficialProfileScreenState();
}

class _OfficialProfileScreenState extends State<OfficialProfileScreen> {
  _ProfileTab _tab = _ProfileTab.overview;
  late String _name = widget.initialName;
  final _nameInput = TextEditingController();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _nameForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _visible = <bool>[false, false, false];
  bool _loading = true,
      _editing = false,
      _savingName = false,
      _savingPassword = false;
  bool _nameSaved = false, _passwordSaved = false;
  String? _accountError, _nameError, _passwordError, _activityError;
  bool _activityLoading = false, _activityLoaded = false, _opening = false;
  String _decisionFilter = 'All decisions';
  List<({ScheduleApproval approval, Map<String, dynamic> event})> _decisions =
      [];
  bool get _assistant => widget.role == 'assistantSecurity';
  String get _displayName => _name.isEmpty ? widget.username : _name;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    for (final controller in [_nameInput, _current, _password, _confirm]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    setState(() => _loading = true);
    final result = await ApiService.workflow('/account');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _accountError = result['success'] == true
          ? null
          : result['error'].toString();
      if (_accountError == null) {
        _name = result['name']?.toString() ?? widget.username;
        _nameInput.text = _name;
      }
    });
    if (_accountError == null) widget.onNameChanged(_name);
  }

  Future<void> _saveName() async {
    if (_savingName || !_nameForm.currentState!.validate()) return;
    setState(() {
      _savingName = true;
      _nameError = null;
      _nameSaved = false;
    });
    final result = await ApiService.workflow(
      '/account',
      method: 'PUT',
      body: {'name': _nameInput.text.trim()},
    );
    if (!mounted) return;
    setState(() {
      _savingName = false;
      if (result['success'] == true) {
        _name = result['name'].toString();
        _editing = false;
        _nameSaved = true;
      } else {
        _nameError = result['error'] == 'Method Not Allowed'
            ? 'Profile changes are unavailable right now. Please contact your administrator.'
            : result['error'].toString();
      }
    });
    if (result['success'] == true) widget.onNameChanged(_name);
  }

  Future<void> _savePassword() async {
    if (_savingPassword || !_passwordForm.currentState!.validate()) return;
    setState(() {
      _savingPassword = true;
      _passwordError = null;
      _passwordSaved = false;
    });
    final result = await ApiService.changePassword(
      username: widget.username,
      currentPassword: _current.text,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _savingPassword = false;
      if (result['success'] == true) {
        _current.clear();
        _password.clear();
        _confirm.clear();
        _visible.fillRange(0, 3, false);
        _passwordSaved = true;
      } else {
        _passwordError = result['error'].toString();
      }
    });
  }

  Future<void> _loadActivity() async {
    if (_activityLoading) return;
    setState(() => _activityLoading = true);
    final result = await ApiService.workflow('/schedule-approvals');
    if (!mounted) return;
    setState(() {
      _activityLoading = false;
      _activityLoaded = true;
      _activityError = result['success'] == true
          ? null
          : result['error'].toString();
      if (_activityError == null) {
        _decisions =
            [
              for (final data in approvalMaps(result['approvals']))
                for (final event in approvalMaps(data['events']))
                  if (event['username'] == widget.username &&
                      ['approve', 'return'].contains(event['action']))
                    (approval: ScheduleApproval(data), event: event),
            ]..sort(
              (a, b) =>
                  (DateTime.tryParse(b.event['at'].toString()) ??
                          DateTime(1970))
                      .compareTo(
                        DateTime.tryParse(a.event['at'].toString()) ??
                            DateTime(1970),
                      ),
            );
      }
    });
  }

  void _selectTab(_ProfileTab tab) {
    setState(() => _tab = tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // Leaving Security clears password input rather than keeping it on a hidden tab.
    if (tab != _ProfileTab.security) {
      _current.clear();
      _password.clear();
      _confirm.clear();
      _visible.fillRange(0, 3, false);
      _passwordError = null;
      _passwordSaved = false;
    }
    if (tab == _ProfileTab.decisions && !_activityLoaded) _loadActivity();
  }

  Future<void> _openDecision(ScheduleApproval approval) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ApprovalReviewScreen(id: approval.id, role: widget.role),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (mounted) await _loadActivity();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF4F6FA),
    child: ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your profile',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your identity, review history, and account security.',
                    style: TextStyle(color: _muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh profile',
              onPressed: _loading || _editing || _savingName
                  ? null
                  : _loadAccount,
              icon: const Icon(Icons.refresh_rounded, color: _muted),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _hero(),
        const SizedBox(height: 20),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_accountError != null)
          _feedback(_accountError!, error: true, retry: _loadAccount),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in [
              (
                _ProfileTab.overview,
                Icons.person_outline_rounded,
                'Account Overview',
              ),
              (_ProfileTab.decisions, Icons.history_rounded, 'My Decisions'),
              (_ProfileTab.security, Icons.lock_outline_rounded, 'Security'),
            ])
              ChoiceChip(
                label: Text(entry.$3),
                avatar: Icon(entry.$2, size: 18),
                selected: _tab == entry.$1,
                showCheckmark: false,
                selectedColor: const Color(0xFFE8EEFF),
                side: BorderSide(
                  color: _tab == entry.$1 ? const Color(0xFFB5C6F5) : _border,
                ),
                onSelected: _savingName || _savingPassword
                    ? null
                    : (_) => _selectTab(entry.$1),
              ),
          ],
        ),
        const SizedBox(height: 20),
        switch (_tab) {
          _ProfileTab.overview => _overview(),
          _ProfileTab.decisions => _activity(),
          _ProfileTab.security => _security(),
        },
        const SizedBox(height: 20),
      ],
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF14285C), Color(0xFF1C449A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .24)),
          ),
          child: Text(
            officialInitials(_displayName),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OFFICIAL ACCOUNT',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFAFC4F5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '@${widget.username}',
                style: const TextStyle(color: Color(0xFFCFDBF6), fontSize: 14),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _heroBadge(
                    Icons.verified_user_outlined,
                    officialRoleLabel(widget.role),
                  ),
                  _heroBadge(Icons.location_on_outlined, 'All stations'),
                  _heroBadge(
                    Icons.fact_check_outlined,
                    _assistant ? 'First review' : 'Final approval',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _heroBadge(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFFBDD1FF)),
        const SizedBox(width: 7),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    ),
  );

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
  }) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 21, color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 22),
        child,
      ],
    ),
  );

  Widget _columns(Widget main, Widget side) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 920) {
        return Column(children: [main, const SizedBox(height: 20), side]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: main),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: side),
        ],
      );
    },
  );

  Widget _overview() => _columns(
    _card(
      icon: Icons.badge_outlined,
      title: 'Account details',
      subtitle: 'The information attached to your official account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editing)
            Form(
              key: _nameForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    key: const ValueKey('official-name'),
                    controller: _nameInput,
                    enabled: !_savingName,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your full name.'
                        : null,
                  ),
                  if (_nameError != null) _feedback(_nameError!, error: true),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _savingName ? null : _saveName,
                        icon: _savingName
                            ? _spinner()
                            : const Icon(Icons.check, size: 18),
                        label: Text(_savingName ? 'Saving...' : 'Save name'),
                      ),
                      TextButton(
                        onPressed: _savingName
                            ? null
                            : () => setState(() {
                                _editing = false;
                                _nameInput.text = _name;
                                _nameError = null;
                              }),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            _detail(
              'Full name',
              _loading && _name.isEmpty ? 'Loading...' : _displayName,
            ),
            TextButton.icon(
              onPressed: _loading || _accountError != null
                  ? null
                  : () => setState(() {
                      _nameInput.text = _name;
                      _editing = true;
                      _nameSaved = false;
                      _nameError = null;
                    }),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit name'),
            ),
          ],
          if (_nameSaved)
            _feedback('Your name has been saved to your account.'),
          const Divider(height: 30, color: _border),
          Row(
            children: [
              Expanded(child: _detail('Username', widget.username)),
              IconButton(
                tooltip: 'Copy username',
                icon: const Icon(Icons.copy_outlined, size: 18, color: _muted),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.username));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Username copied.')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          _detail('Assigned role', officialRoleLabel(widget.role)),
          const SizedBox(height: 20),
          _detail('Coverage', 'All stations'),
          const SizedBox(height: 22),
          const Text(
            'Your name appears on future approval records. Previous decisions keep the name recorded at that time.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    ),
    Column(
      children: [
        _card(
          icon: Icons.route_outlined,
          title: 'Your responsibility',
          subtitle: _assistant
              ? 'The first review in the approval process.'
              : 'The final decision before publication.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _responsibility(
                '01',
                'Review the entire period',
                'Check duty assignments across every station.',
              ),
              _responsibility(
                '02',
                'Approve or return',
                _assistant
                    ? 'Approve to send the period to the Area Commander, or return it with a revision comment.'
                    : 'After Assistant Security approves, approve to publish the period or return it for revision.',
              ),
              _responsibility(
                '03',
                'Stay informed',
                'Read approval alerts and review recorded emergency amendments.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _card(
          icon: Icons.support_agent_outlined,
          title: 'Account assistance',
          subtitle: 'Changes managed by your administrator.',
          child: const Text(
            'Contact the admin for help with your assigned account or to reset a forgotten password.',
            style: TextStyle(color: _muted, height: 1.6, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 6),
      SelectableText(
        value,
        style: const TextStyle(
          color: _ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _responsibility(String number, String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _activity() {
    final filtered = _decisions
        .where(
          (d) =>
              _decisionFilter == 'All decisions' ||
              d.event['action'] ==
                  (_decisionFilter == 'Approved' ? 'approve' : 'return'),
        )
        .toList();
    return _card(
      icon: Icons.history_rounded,
      title: 'My decision history',
      subtitle:
          'Only approvals and returns made by your account are shown here.',
      action: IconButton(
        tooltip: 'Refresh my decisions',
        onPressed: _activityLoading ? null : _loadActivity,
        icon: const Icon(Icons.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_activityLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_activityError != null)
            _feedback(_activityError!, error: true, retry: _loadActivity),
          if (!_activityLoading && _activityError == null) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _stat('Decisions', _decisions.length, _blue),
                _stat(
                  'Approved',
                  _decisions
                      .where((d) => d.event['action'] == 'approve')
                      .length,
                  const Color(0xFF15803D),
                ),
                _stat(
                  'Returned',
                  _decisions.where((d) => d.event['action'] == 'return').length,
                  const Color(0xFFB45309),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in ['All decisions', 'Approved', 'Returned'])
                  ChoiceChip(
                    label: Text(label),
                    selected: _decisionFilter == label,
                    onSelected: (_) => setState(() => _decisionFilter = label),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.fact_check_outlined,
                        color: _muted,
                        size: 38,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _decisions.isEmpty
                            ? 'Your decisions will appear here.'
                            : 'No decisions match this filter.',
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            for (final decision in filtered)
              _decisionCard(decision.approval, decision.event),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, int count, Color color) => Container(
    width: 150,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    ),
  );

  Widget _decisionCard(ScheduleApproval approval, Map<String, dynamic> event) {
    final approved = event['action'] == 'approve';
    final color = approved ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                approved ? 'Approved' : 'Returned for revision',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              Text(
                approvalTime(event['at']),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            approval.period,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${approval.stationCount} stations · Revision ${approval.revision}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          if (event['comment']?.toString().trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                event['comment'].toString(),
                style: const TextStyle(color: _ink, height: 1.5),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Current submission: ${approvalStatusLabel(approval.status)}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _opening ? null : () => _openDecision(approval),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('View submission'),
          ),
        ],
      ),
    );
  }

  Widget _security() => _columns(
    _card(
      icon: Icons.lock_outline_rounded,
      title: 'Change password',
      subtitle: 'Choose a new password for your next sign-in.',
      child: Form(
        key: _passwordForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in [
              (0, _current, 'Current password'),
              (1, _password, 'New password'),
              (2, _confirm, 'Confirm new password'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: TextFormField(
                  key: ValueKey('official-password-${entry.$1}'),
                  controller: entry.$2,
                  enabled: !_savingPassword,
                  obscureText: !_visible[entry.$1],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: entry.$3,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip:
                          '${_visible[entry.$1] ? 'Hide' : 'Show'} ${entry.$3.toLowerCase()}',
                      onPressed: _savingPassword
                          ? null
                          : () => setState(
                              () => _visible[entry.$1] = !_visible[entry.$1],
                            ),
                      icon: Icon(
                        _visible[entry.$1]
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter ${entry.$3.toLowerCase()}.';
                    }
                    if (entry.$1 == 1) {
                      if (value.trim() != value) {
                        return 'Do not start or end with spaces.';
                      }
                      if (value.length < 8) return 'Use at least 8 characters.';
                      if (value == _current.text) {
                        return 'Choose a different password.';
                      }
                    }
                    if (entry.$1 == 2 && value != _password.text) {
                      return 'The new passwords do not match.';
                    }
                    return null;
                  },
                ),
              ),
            if (_passwordError != null) _feedback(_passwordError!, error: true),
            if (_passwordSaved)
              _feedback(
                'Password changed. Your other sessions have been signed out.',
              ),
            FilledButton.icon(
              onPressed: _savingPassword ? null : _savePassword,
              icon: _savingPassword
                  ? _spinner()
                  : const Icon(Icons.lock_reset, size: 18),
              label: Text(_savingPassword ? 'Updating...' : 'Update password'),
            ),
          ],
        ),
      ),
    ),
    _card(
      icon: Icons.shield_outlined,
      title: 'Protect your account',
      subtitle: 'Your login identifies your official decisions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _responsibility(
            '01',
            'Use a unique password',
            'Choose at least 8 characters and avoid a password you use elsewhere.',
          ),
          _responsibility(
            '02',
            'Keep your login private',
            'Each approval is recorded against the signed-in official.',
          ),
          _responsibility(
            '03',
            'Sign out on shared computers',
            'Use Log Out when you finish reviewing schedules.',
          ),
          const Divider(color: _border),
          const SizedBox(height: 12),
          const Text(
            'Changing your password signs out other sessions. You stay signed in on this device.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    ),
  );

  Widget _spinner() => const SizedBox(
    width: 17,
    height: 17,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  Widget _feedback(String message, {bool error = false, VoidCallback? retry}) =>
      Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: error ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                error ? Icons.error_outline : Icons.check_circle_outline,
                size: 20,
                color: error ? Colors.red : const Color(0xFF15803D),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: error
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF166534),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              if (retry != null)
                TextButton(onPressed: retry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
