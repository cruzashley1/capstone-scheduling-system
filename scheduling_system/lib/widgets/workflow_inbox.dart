import 'dart:async';
import 'package:flutter/material.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../screens/approval_screen.dart';

class WorkflowInboxButton extends StatefulWidget {
  final String role;
  final Color? color;
  const WorkflowInboxButton({super.key, required this.role, this.color});
  @override
  State<WorkflowInboxButton> createState() => _WorkflowInboxButtonState();
}

class _WorkflowInboxButtonState extends State<WorkflowInboxButton> {
  List<Map<String, dynamic>> _items = [];
  Timer? _timer;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ApiService.workflow('/workflow-notifications');
    if (!mounted) return;
    setState(() {
      _error = result['success'] == true ? null : result['error'].toString();
      if (_error == null) _items = approvalMaps(result['notifications']);
    });
  }

  Future<void> _open() async {
    await _load();
    if (!mounted) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approval Notifications'),
        content: SizedBox(
          width: 650,
          height: 440,
          child: _error != null
              ? Text(_error!)
              : _items.isEmpty
              ? const Center(child: Text('No approval notifications yet.'))
              : ListView(
                  children: [
                    for (final n in _items)
                      ListTile(
                        leading: Icon(
                          n['isRead'] == true
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: const Color(0xFF1034A6),
                        ),
                        title: Text(
                          n['title'],
                          style: TextStyle(
                            fontWeight: n['isRead'] == true
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${n['message']}\n${approvalTime(n['createdAt'])}',
                        ),
                        onTap: () => Navigator.pop(ctx, n),
                      ),
                  ],
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
    if (selected == null) return;
    await ApiService.workflow(
      '/workflow-notifications/${selected['id']}/read',
      method: 'POST',
    );
    if (!mounted) return;
    if (selected['approvalId'] != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ApprovalReviewScreen(
            id: selected['approvalId'],
            role: widget.role,
          ),
        ),
      );
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final count = _items.where((n) => n['isRead'] != true).length;
    return TextButton.icon(
      onPressed: _open,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(Icons.notifications_outlined, color: widget.color),
      ),
      label: Text('Approval Alerts', style: TextStyle(color: widget.color)),
    );
  }
}
