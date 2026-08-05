// widgets/leave_request_card.dart
//
// Dashboard entry point for the leave flow. Shown on the security guard
// and head guard dashboards inside the Request section, alongside the
// special day-off and emergency absence cards — the three together are
// every request this app can file, longest-notice first.
//
// Like the other two it doubles as a status card: while a request is
// awaiting a decision it says so (with the 2-3 day expectation), while a
// leave is running it counts down to the return date, and otherwise it
// invites a new one. Always tappable, so the form and the history stay
// one tap away whatever the state.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../screens/leave_request_screen.dart';
import '../services/api_service.dart';
import '../services/duty_clock.dart';

const _kTeal = Color(0xFF0D9488);
const _kAmber = Color(0xFFF59E0B);
const _kGreen = Color(0xFF16A34A);
const _kInk = Color(0xFF1E293B);
const _kMuted = Color(0xFF64748B);

class LeaveRequestCard extends StatefulWidget {
  final Employee employee;

  // Lets the host refetch after a leave is filed, so the dashboard's duty
  // status and this card can't disagree about where the guard stands.
  final Future<void> Function()? onChanged;

  const LeaveRequestCard({
    super.key,
    required this.employee,
    this.onChanged,
  });

  @override
  State<LeaveRequestCard> createState() => _LeaveRequestCardState();
}

class _LeaveRequestCardState extends State<LeaveRequestCard> {
  List<LeaveRequest> _leaves = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await ApiService.fetchEmployeeLeaveRequests(widget.employee.id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _leaves = result['success'] == true
          ? (result['requests'] as List).cast<LeaveRequest>()
          : [];
    });
  }

  // What this card is about, in priority order: a leave running now, then
  // one awaiting a decision, then one already approved and coming up.
  LeaveRequest? get _active => DutyClock.activeLeave(_leaves);
  LeaveRequest? get _pending {
    final pending = _leaves.where((l) => l.isPending).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return pending.isEmpty ? null : pending.first;
  }

  LeaveRequest? get _upcoming => DutyClock.upcomingLeave(_leaves);

  Future<void> _open() async {
    // Grabbed before the awaits below: refreshing the dashboard can
    // rebuild this card away, and a disposed card used to swallow the
    // confirmation entirely (the guard saw the form close and nothing
    // else). The messenger outlives the card, so the message still lands.
    final messenger = ScaffoldMessenger.of(context);

    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LeaveRequestScreen(employee: widget.employee),
      ),
    );
    if (submitted != true) return;

    if (mounted) await _load();
    await widget.onChanged?.call();

    // The one thing the guard has to walk away knowing.
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Leave request sent — approval may take at least 2-3 days. '
          "You'll be notified in your Alerts.",
        ),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildPlaceholder();

    final active = _active;
    if (active != null) return _buildActive(active);

    final pending = _pending;
    if (pending != null) return _buildPending(pending);

    final upcoming = _upcoming;
    if (upcoming != null) return _buildUpcoming(upcoming);

    return _buildInvite();
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
                  width: 140,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: 200,
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
    return _shell(
      onTap: _open,
      child: _row(
        color: _kTeal,
        icon: Icons.beach_access_outlined,
        title: 'Need a longer time off?',
        subtitle: 'File a leave request — vacation, sickness, maternity.',
      ),
    );
  }

  Widget _buildPending(LeaveRequest r) {
    return _shell(
      onTap: _open,
      child: _row(
        color: _kAmber,
        icon: Icons.hourglass_bottom_rounded,
        title: r.title.isEmpty ? 'Leave request' : r.title,
        subtitle: '${r.rangeLabel} · ${r.days} days · filed ${r.timeAgo}',
        badge: 'Pending',
        // The expectation set on submit, repeated where they'll look for it.
        note: 'Approval may take at least 2-3 days.',
      ),
    );
  }

  Widget _buildActive(LeaveRequest r) {
    return _shell(
      onTap: _open,
      child: _row(
        color: _kTeal,
        icon: Icons.beach_access_rounded,
        title: 'You are on leave',
        subtitle: '${r.leaveType} · ${r.rangeLabel}',
        badge: 'On Leave',
        note: r.daysRemaining <= 1
            ? 'You report back for duty tomorrow.'
            : 'Back on duty ${LeaveRequest.formatShort(r.endDate)} — '
                '${r.daysRemaining} days left.',
      ),
    );
  }

  Widget _buildUpcoming(LeaveRequest r) {
    return _shell(
      onTap: _open,
      child: _row(
        color: _kGreen,
        icon: Icons.event_available_rounded,
        title: 'Leave approved',
        subtitle: '${r.leaveType} · ${r.rangeLabel}',
        badge: 'Approved',
        note: 'Starts ${LeaveRequest.formatDate(r.startDate)}.',
      ),
    );
  }

  Widget _row({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    String? note,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
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
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
              if (note != null) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 12),
          child: Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
        ),
      ],
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
