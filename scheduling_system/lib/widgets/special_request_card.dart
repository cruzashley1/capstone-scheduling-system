// widgets/special_request_card.dart
//
// Dashboard entry point for the special day-off request flow. Shown on the
// security guard and head guard dashboards inside the Request section,
// above the emergency absence card — a special request is the planned-ahead
// counterpart to an emergency: the guard asks for days off BEFORE the
// schedule covering them is generated.
//
// It doubles as a status card, like the other two: while the newest request
// is still awaiting a decision it reports that instead of re-inviting, and
// it always stays tappable so the guard can file for more days or read the
// history on the form.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/special_request.dart';
import '../screens/special_request_screen.dart';
import '../services/api_service.dart';

class SpecialRequestCard extends StatefulWidget {
  final Employee employee;

  const SpecialRequestCard({super.key, required this.employee});

  @override
  State<SpecialRequestCard> createState() => _SpecialRequestCardState();
}

class _SpecialRequestCardState extends State<SpecialRequestCard> {
  // Newest request on file, whatever its status — null while loading or
  // when the guard has never filed one.
  SpecialRequest? _latest;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await ApiService.fetchEmployeeSpecialRequests(widget.employee.id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success'] != true) {
        _latest = null;
        return;
      }
      final requests = (result['requests'] as List).cast<SpecialRequest>();
      if (requests.isEmpty) {
        _latest = null;
        return;
      }
      // The backend returns newest first, but sort so the card can't be
      // wrong if that ever changes.
      requests.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      _latest = requests.first;
    });
  }

  Future<void> _open() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SpecialRequestScreen(employee: widget.employee),
      ),
    );
    if (!mounted) return;
    if (submitted != true) return;

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Special request sent — the admin will review it and you'll be "
          'notified in your Alerts.',
        ),
        backgroundColor: Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _statusColor(SpecialRequest r) {
    if (r.isApproved) return const Color(0xFF16A34A);
    if (r.isDenied) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String _statusLabel(SpecialRequest r) {
    if (r.isApproved) return 'Approved';
    if (r.isDenied) return 'Denied';
    return 'Pending';
  }

  IconData _statusIcon(SpecialRequest r) {
    if (r.isApproved) return Icons.check_circle_outline;
    if (r.isDenied) return Icons.cancel_outlined;
    return Icons.hourglass_bottom_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildPlaceholder();
    final latest = _latest;
    // A decided request is history — the card goes back to inviting a new
    // one. Only a request still awaiting a decision is worth reporting.
    if (latest == null || !latest.isPending) return _buildInvite();
    return _buildStatus(latest);
  }

  Widget _buildPlaceholder() {
    return _shell(
      onTap: null,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: 210,
                  height: 11,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvite() {
    const violet = Color(0xFF7C3AED);
    return _shell(
      onTap: _open,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: violet.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: violet,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need a day off ahead of time?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'File a special day-off request before the schedule is '
                  'made.',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
        ],
      ),
    );
  }

  Widget _buildStatus(SpecialRequest request) {
    final color = _statusColor(request);
    return _shell(
      onTap: _open,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_statusIcon(request), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.title.isEmpty
                            ? 'Special day-off request'
                            : request.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(request),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${request.datesSummary} · ${request.timeAgo}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child:
                Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
          ),
        ],
      ),
    );
  }

  // Shared white card shell — same radius and shadow as the other
  // dashboard cards.
  Widget _shell({required VoidCallback? onTap, required Widget child}) {
    return Container(
      width: double.infinity,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}
