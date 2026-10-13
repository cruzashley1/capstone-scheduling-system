import 'dart:async';
import 'package:flutter/material.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../services/notification_center.dart';
import '../screens/approval_screen.dart';

/// Shared by the admin's Notifications tab and the officials' alert dialog.
class WorkflowInbox extends StatefulWidget {
  final String role;
  final ValueChanged<int>? onUnreadCountChanged;
  const WorkflowInbox({
    super.key,
    required this.role,
    this.onUnreadCountChanged,
  });
  @override
  State<WorkflowInbox> createState() => WorkflowInboxState();
}

class WorkflowInboxState extends State<WorkflowInbox> {
  List<Map<String, dynamic>> _items = [];
  Timer? _timer;
  String? _error;
  String? _openingId;
  bool _loading = true;
  bool _fetching = false;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    reload();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    final result = await ApiService.workflow('/workflow-notifications');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _fetching = false;
      _error = result['success'] == true ? null : result['error'].toString();
      if (_error == null) _items = approvalMaps(result['notifications']);
    });
    if (_error == null) _reportCount();
  }

  void _reportCount() => widget.onUnreadCountChanged?.call(
    _items.where((n) => n['isRead'] != true).length,
  );

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['isRead'] == true) return;
    final result = await ApiService.workflow(
      '/workflow-notifications/${item['id']}/read',
      method: 'POST',
    );
    if (!mounted || result['success'] != true) return;
    setState(() {
      for (final current in _items) {
        if (current['id'] == item['id']) current['isRead'] = true;
      }
    });
    _reportCount();
    if (widget.role == 'admin') {
      unawaited(NotificationCenter.instance.refresh());
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (_openingId != null) return;
    setState(() => _openingId = item['id'].toString());
    try {
      // The review screen opens with a spinner while its roster loads.
      // Marking the alert read must never delay navigation.
      unawaited(_markRead(item));
      final approvalId = item['approvalId'] as String?;
      if (approvalId != null && approvalId.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ApprovalReviewScreen(id: approvalId, role: widget.role),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items
        .where((n) => !_unreadOnly || n['isRead'] != true)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All alerts'),
                selected: !_unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Unread'),
                selected: _unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = true),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh approval alerts',
                onPressed: _fetching ? null : reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_fetching && !_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: _fetching ? null : reload,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading approval alerts...'),
                    ],
                  ),
                )
              : visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 44,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error != null
                            ? 'Approval alerts are unavailable.'
                            : _unreadOnly
                            ? 'You have read all approval alerts.'
                            : 'No approval alerts yet.',
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final n = visible[index];
                    final unread = n['isRead'] != true;
                    return Material(
                      color: unread ? const Color(0xFFEFF6FF) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: ValueKey('approval-alert-${n['id']}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        leading: Icon(
                          unread
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_none,
                          color: const Color(0xFF1034A6),
                        ),
                        title: Text(
                          n['title'] ?? 'Schedule approval',
                          style: TextStyle(
                            fontWeight: unread
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${n['message']}\n${approvalTime(n['createdAt'])}',
                          ),
                        ),
                        trailing: _openingId == n['id']
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _openingId != null ? null : () => _open(n),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Officials retain their sidebar shortcut; admins use Notifications instead.
class WorkflowInboxButton extends StatefulWidget {
  final String role;
  final Color? color;
  const WorkflowInboxButton({super.key, required this.role, this.color});
  @override
  State<WorkflowInboxButton> createState() => _WorkflowInboxButtonState();
}

class _WorkflowInboxButtonState extends State<WorkflowInboxButton> {
  int _unread = 0;
  bool _opening = false;
  bool _fetching = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadCount());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCount() async {
    if (_fetching || _opening) return;
    _fetching = true;
    try {
      final result = await ApiService.workflow('/workflow-notifications');
      if (!mounted || result['success'] != true) return;
      setState(
        () => _unread = approvalMaps(
          result['notifications'],
        ).where((n) => n['isRead'] != true).length,
      );
    } finally {
      _fetching = false;
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      // Open immediately, even on a slow connection, and lock repeat taps.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approval Alerts'),
          content: SizedBox(
            width: 650,
            height: 440,
            child: WorkflowInbox(
              role: widget.role,
              onUnreadCountChanged: (count) {
                if (mounted) setState(() => _unread = count);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (mounted) await _loadCount();
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _opening ? null : _open,
    icon: Badge(
      isLabelVisible: _unread > 0,
      label: Text('$_unread'),
      child: Icon(Icons.notifications_outlined, color: widget.color),
    ),
    label: Text('Approval Alerts', style: TextStyle(color: widget.color)),
  );
}
