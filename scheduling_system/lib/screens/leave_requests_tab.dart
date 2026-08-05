// screens/leave_requests_tab.dart
//
// Admin side of the leave flow: the body of the fourth tab in the
// Notifications screen. An employee files a leave from the guard app —
// a date range, a leave type, a title and a reason — and the admin
// approves or denies it here. An approved leave keeps them off the
// roster for its whole range, and the employee is told the outcome
// through their Alerts inbox.
//
// The one rule this screen has to carry visibly: a leave that runs past
// its type's day cap cannot be approved without naming the higher
// authority who endorsed it. The system has no supervisor account, so
// that endorsement is recorded as the admin attesting to it.
//
// This renders a scrollable body only — the host Notifications screen
// owns the page header and the tab bar.

import 'package:flutter/material.dart';
import '../models/leave_request.dart';
import '../services/api_service.dart';

const _kPending = Color(0xFFF59E0B);
const _kApproved = Color(0xFF16A34A);
const _kOnLeave = Color(0xFF0D9488);
const _kDenied = Color(0xFFDC2626);
const _kMuted = Color(0xFF64748B);
const _kBlue = Color(0xFF1034A6);
const _kBorder = Color(0xFFE2E8F0);
const _kText = Color(0xFF1E293B);

class LeaveRequestsTab extends StatefulWidget {
  // Fires after every successful load and right after a decision, so the
  // host can badge the tab without owning the list.
  final ValueChanged<int>? onPendingCountChanged;

  const LeaveRequestsTab({super.key, this.onPendingCountChanged});

  @override
  State<LeaveRequestsTab> createState() => LeaveRequestsTabState();
}

// Public so the host screen can hold a GlobalKey<LeaveRequestsTabState>
// and call reload() when it refreshes the whole inbox.
class LeaveRequestsTabState extends State<LeaveRequestsTab> {
  List<LeaveRequest> _requests = [];
  bool _isLoading = true;
  String? _loadError;

  String _filter = 'Pending'; // All | Pending | On Leave | Approved | Denied

  // Day cap per leave type, straight from the backend catalogue — the
  // card and the approval dialog both need it to know what "over cap"
  // means, and neither should hardcode a number.
  Map<String, int> _caps = {};

  // Id of the request currently being decided, so its buttons can't be
  // double-tapped while the call is in flight.
  String? _decidingId;

  @override
  void initState() {
    super.initState();
    _loadCaps();
    _load();
  }

  // Public entry point for the host screen's refresh button.
  Future<void> reload() => _load();

  Future<void> _loadCaps() async {
    final result = await ApiService.fetchLeaveTypes();
    if (!mounted || result['success'] != true) return;
    setState(() {
      _caps = {
        for (final t in (result['leaveTypes'] as List).cast<LeaveType>())
          t.name: t.maxDays,
      };
    });
  }

  Future<void> _load() async {
    if (_requests.isEmpty) setState(() => _isLoading = true);

    final result = await ApiService.fetchLeaveRequests();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _requests = (result['requests'] as List).cast<LeaveRequest>();
        _loadError = null;
      } else {
        _requests = [];
        _loadError = result['error']?.toString().isNotEmpty == true
            ? 'Could not reach the server — ${result['error']}'
            : 'Could not reach the server — no leave requests loaded.';
      }
    });

    if (result['success'] == true) _notifyPendingCount();
  }

  void _notifyPendingCount() =>
      widget.onPendingCountChanged?.call(_pendingCount);

  int get _pendingCount => _requests.where((r) => r.isPending).length;
  int get _onLeaveCount => _requests.where((r) => r.isOnLeaveNow).length;
  int get _approvedCount => _requests.where((r) => r.isApproved).length;
  int get _deniedCount =>
      _requests.where((r) => r.isDenied || r.isCancelled).length;

  List<LeaveRequest> get _visibleRequests {
    switch (_filter) {
      case 'Pending':
        return _requests.where((r) => r.isPending).toList();
      case 'On Leave':
        return _requests.where((r) => r.isOnLeaveNow).toList();
      case 'Approved':
        return _requests.where((r) => r.isApproved).toList();
      case 'Denied':
        return _requests.where((r) => r.isDenied || r.isCancelled).toList();
      default:
        return _requests;
    }
  }

  // How many days this leave type allows. 0 when the catalogue hasn't
  // loaded yet — the card simply doesn't draw the over-cap flag rather
  // than guessing a cap and crying wolf.
  int _capFor(LeaveRequest r) => _caps[r.leaveType] ?? 0;
  bool _isOverCap(LeaveRequest r) {
    final cap = _capFor(r);
    return cap > 0 && r.days > cap;
  }

  // ── status styling ──────────────────────────────────────────────

  Color _statusColor(LeaveRequest r) {
    switch (r.phase) {
      case 'active':
        return _kOnLeave;
      case 'upcoming':
        return _kApproved;
      case 'completed':
        return _kMuted;
      case 'denied':
        return _kDenied;
      case 'cancelled':
        return _kMuted;
      default:
        return _kPending;
    }
  }

  IconData _statusIcon(LeaveRequest r) {
    switch (r.phase) {
      case 'active':
        return Icons.beach_access_rounded;
      case 'upcoming':
        return Icons.event_available_rounded;
      case 'completed':
        return Icons.task_alt_rounded;
      case 'denied':
        return Icons.cancel_outlined;
      case 'cancelled':
        return Icons.block_rounded;
      default:
        return Icons.pending_actions_rounded;
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · '
        '$hour12:$minute $suffix';
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── actions ─────────────────────────────────────────────────────

  void _openDetail(LeaveRequest request) {
    if (!request.isRead) {
      setState(() => request.isRead = true);
      if (_loadError == null) ApiService.markLeaveRequestRead(request.id);
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _buildDetailDialog(dialogContext, request),
    );
  }

  // Collects the decision. Approving loads the coverage impact first and
  // — when the leave runs past its cap — will not let the dialog close
  // until the endorsing supervisor is named.
  Future<void> _decide(LeaveRequest request, String status) async {
    final approving = status == 'approved';

    final outcome = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LeaveDecisionDialog(
        request: request,
        approving: approving,
        cap: _capFor(request),
      ),
    );
    if (outcome == null || !mounted) return;

    setState(() => _decidingId = request.id);

    final result = await ApiService.decideLeaveRequest(
      id: request.id,
      status: status,
      adminNote: outcome['note'] as String? ?? '',
      supervisorName: outcome['supervisorName'] as String? ?? '',
      supervisorConfirmed: outcome['supervisorConfirmed'] == true,
    );
    if (!mounted) return;

    setState(() => _decidingId = null);

    if (result['success'] != true) {
      _snack(result['error']?.toString() ?? 'Could not save the decision.',
          _kDenied);
      return;
    }

    setState(() {
      final updated = result['request'];
      if (updated is LeaveRequest) {
        request.status = updated.status;
        request.adminNote = updated.adminNote;
      } else {
        request.status = status;
      }
      request.isRead = true;
    });
    _notifyPendingCount();

    _snack(
      approving
          ? 'Leave approved — ${request.employeeName} has been notified.'
          : 'Leave denied — ${request.employeeName} has been notified.',
      approving ? _kApproved : _kDenied,
    );

    await _load();
  }

  // NOTE: the admin cannot cancel a leave they already approved — an
  // approved leave is final. The employee has planned around it and the
  // roster has already been built without them, so pulling it back would
  // undo both. The "cancelled" phase is still rendered because older
  // records carry it, but nothing in this screen creates one.

  // ── build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kBlue));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadError != null) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD97706)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      size: 18, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadError!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF92400E)),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          ],

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip('All', _requests.length),
              _buildFilterChip('Pending', _pendingCount),
              _buildFilterChip('On Leave', _onLeaveCount),
              _buildFilterChip('Approved', _approvedCount),
              _buildFilterChip('Denied', _deniedCount),
            ],
          ),
          const SizedBox(height: 20),

          if (_visibleRequests.isEmpty)
            _buildEmptyState()
          else
            ..._visibleRequests.map(_buildRequestCard),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _filter == label;
    return InkWell(
      onTap: () => setState(() => _filter = label),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _kBlue : _kBorder),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : _kMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    late final String title;
    late final String subtitle;
    late final IconData icon;

    switch (_filter) {
      case 'Pending':
        icon = Icons.inbox_outlined;
        title = 'No pending leave requests';
        subtitle = 'Nothing is waiting on your decision right now.';
        break;
      case 'On Leave':
        icon = Icons.beach_access_outlined;
        title = 'Nobody is on leave today';
        subtitle = 'Employees whose approved leave covers today '
            'will be listed here.';
        break;
      case 'Approved':
        icon = Icons.event_available_outlined;
        title = 'No approved leave';
        subtitle = 'Leave you approve will be listed here.';
        break;
      case 'Denied':
        icon = Icons.cancel_outlined;
        title = 'No denied leave';
        subtitle = 'Leave you deny will be listed here.';
        break;
      default:
        icon = Icons.beach_access_outlined;
        title = 'Nothing here yet';
        subtitle = 'Leave filed by employees, and leave you record from '
            'Employee Details, will appear here.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500]),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(LeaveRequest request) {
    final color = _statusColor(request);
    final isDeciding = _decidingId == request.id;
    final overCap = _isOverCap(request);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: request.isRead ? Colors.white : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openDetail(request),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: request.isRead ? _kBorder : const Color(0xFFBFDBFE),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
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
                              request.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: request.isRead
                                    ? FontWeight.w600
                                    : FontWeight.bold,
                                color: _kText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            request.timeAgo,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                          ),
                          if (!request.isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: _kBlue, shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.employeeName} · ${request.roleLabel}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildStatusPill(request),
                          _buildRangePill(request),
                          _buildMetaChip(Icons.label_outline,
                              request.leaveType),
                          _buildMetaChip(Icons.today_outlined,
                              '${request.days} day(s)'),
                          if (request.station.isNotEmpty)
                            _buildMetaChip(
                                Icons.location_on_outlined, request.station),
                          if (request.isAdminRecorded)
                            _buildMetaChip(Icons.admin_panel_settings_outlined,
                                'Recorded by admin'),
                        ],
                      ),

                      // The one thing that must never be missed on a
                      // glance down the list.
                      if (overCap) ...[
                        const SizedBox(height: 10),
                        _buildOverCapBanner(request),
                      ],

                      const SizedBox(height: 10),
                      Text(
                        request.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            height: 1.4),
                      ),

                      if (request.isPending) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: isDeciding
                                  ? null
                                  : () => _decide(request, 'approved'),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kApproved,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: isDeciding
                                  ? null
                                  : () => _decide(request, 'denied'),
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Deny'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kDenied,
                                side: const BorderSide(
                                    color: Color(0xFFFECACA)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: isDeciding
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: _kBlue),
                                      )
                                    : Text(
                                        'View details',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _kBlue.withOpacity(0.9),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        _buildOutcomeBlock(request),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverCapBanner(LeaveRequest request) {
    final cap = _capFor(request);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_rounded, size: 16, color: Color(0xFFB91C1C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${request.days} days — past the $cap-day cap for '
              '${request.leaveType}. Approving this without proper consent '
              'from the higher authority will result to heavy penalty.',
              style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(LeaveRequest request) {
    final color = _statusColor(request);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(request), size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            request.statusLabel,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  // The leave's whole range as one pill — the thing the admin is really
  // deciding on, so it gets the app's blue rather than a grey meta chip.
  Widget _buildRangePill(LeaveRequest request) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBlue.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.date_range, size: 13, color: _kBlue),
          const SizedBox(width: 5),
          Text(
            request.rangeLabel,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _kBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeBlock(LeaveRequest request) {
    final color = _statusColor(request);
    final decided = request.decidedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon(request), size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${request.statusLabel}'
                  '${request.decidedBy != null && request.decidedBy!.isNotEmpty ? ' by ${request.decidedBy}' : ''}'
                  '${decided != null ? ' · ${_formatDateTime(decided)}' : ''}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          if (request.isOnLeaveNow) ...[
            const SizedBox(height: 6),
            Text(
              'On leave now — ${request.daysRemaining} day(s) left, '
              'back on ${LeaveRequest.formatShort(request.endDate)}.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[700], height: 1.4),
            ),
          ],
          if (request.wasEndorsed) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 13, color: Color(0xFF7C3AED)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Endorsed by ${request.supervisorName}'
                    '${request.brokeRules ? ' · overrode ${request.overriddenRules.join(", ")}' : ''}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6D28D9)),
                  ),
                ),
              ],
            ),
          ],
          if (request.adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Note: ${request.adminNote}',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[700], height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  // ── detail dialog ───────────────────────────────────────────────

  Widget _buildDetailDialog(BuildContext dialogContext, LeaveRequest r) {
    final color = _statusColor(r);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_statusIcon(r), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kText),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildStatusPill(r),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Filed ${r.timeAgo}',
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1, color: _kBorder),
              const SizedBox(height: 14),

              if (_isOverCap(r)) ...[
                _buildOverCapBanner(r),
                const SizedBox(height: 14),
              ],

              _buildDetailRow(Icons.badge_outlined, 'Employee',
                  '${r.employeeName} · ${r.roleLabel}',
                  sub: r.employeeId),
              _buildDetailRow(Icons.location_on_outlined, 'Station',
                  r.station.isEmpty ? 'Floating / As assigned' : r.station),
              _buildDetailRow(Icons.label_outline, 'Leave type',
                  '${r.leaveType}${_capFor(r) > 0 ? '  ·  cap ${_capFor(r)} days' : ''}'),
              _buildDetailRow(Icons.date_range, 'Duration',
                  '${LeaveRequest.formatDate(r.startDate)}\nto '
                  '${LeaveRequest.formatDate(r.endDate)}',
                  sub: '${r.days} calendar days'),
              _buildDetailRow(
                  Icons.schedule_send_outlined,
                  'Filed',
                  '${_formatDateTime(r.submittedAt)}'
                  '${r.isAdminRecorded ? '  ·  recorded by admin' : ''}',
                  sub: r.id),

              const SizedBox(height: 6),
              const Text(
                'Reason details',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _kText),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Text(
                  r.body.isEmpty ? 'No details provided.' : r.body,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[700], height: 1.5),
                ),
              ),

              // Duties an admin-recorded leave swallowed — each one a post
              // that needs a replacement.
              if (r.affectedDuties.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Duties needing a replacement (${r.affectedDuties.length})',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309)),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final d in r.affectedDuties)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${LeaveRequest.formatShort(d.date)}  ·  '
                              '${d.stationName}  ·  ${d.shift}'
                              '${d.post.isEmpty ? '' : '  ·  ${d.post}'}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF92400E),
                                  height: 1.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],

              if (!r.isPending) ...[
                const SizedBox(height: 14),
                _buildOutcomeBlock(r),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: TextButton.styleFrom(foregroundColor: _kMuted),
          child: const Text('Close'),
        ),
        if (r.isPending) ...[
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _decide(r, 'denied');
            },
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Deny'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kDenied,
              side: const BorderSide(color: Color(0xFFFECACA)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _decide(r, 'approved');
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kApproved,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _kBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kText),
                ),
                if (sub != null && sub.isNotEmpty)
                  Text(sub,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Shared field styling for the dialogs above and below.
InputDecoration _fieldDecoration({required String label, String? hint}) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(fontSize: 13, color: Colors.grey[600]),
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBlue),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────
// APPROVE / DENY DIALOG
// ─────────────────────────────────────────────────────────────────
// Approving loads the coverage impact first, so the admin sees what the
// leave costs the roster before deciding rather than at generation time
// two weeks later. When the leave runs past its type's cap the Approve
// button stays disabled until the endorsing supervisor is named — the
// backend refuses it anyway, so blocking here just says why sooner.

class _LeaveDecisionDialog extends StatefulWidget {
  final LeaveRequest request;
  final bool approving;
  final int cap;

  const _LeaveDecisionDialog({
    required this.request,
    required this.approving,
    required this.cap,
  });

  @override
  State<_LeaveDecisionDialog> createState() => _LeaveDecisionDialogState();
}

class _LeaveDecisionDialogState extends State<_LeaveDecisionDialog> {
  final _noteController = TextEditingController();
  final _supervisorController = TextEditingController();
  bool _endorsementConfirmed = false;

  bool _loadingImpact = false;
  Map<String, dynamic>? _impact;

  LeaveRequest get r => widget.request;

  // Trust the cap the impact call reports over the catalogue copy this
  // screen loaded earlier — it is computed from the same record the
  // decision endpoint will check.
  bool get _overCap {
    final fromImpact = _impact?['overCap'];
    if (fromImpact is bool) return fromImpact;
    return widget.cap > 0 && r.days > widget.cap;
  }

  int get _cap => (_impact?['cap'] as int?) ?? widget.cap;

  bool get _canSubmit {
    if (!widget.approving || !_overCap) return true;
    return _endorsementConfirmed &&
        _supervisorController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (widget.approving) _loadImpact();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _supervisorController.dispose();
    super.dispose();
  }

  Future<void> _loadImpact() async {
    setState(() => _loadingImpact = true);
    final result = await ApiService.fetchLeaveImpact(r.id);
    if (!mounted) return;
    setState(() {
      _loadingImpact = false;
      if (result['success'] == true) _impact = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.approving ? _kApproved : _kDenied;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            widget.approving
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.approving ? 'Approve this leave?' : 'Deny this leave?',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _kText),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r.employeeName} — ${r.leaveType}\n'
                '${LeaveRequest.formatDate(r.startDate)}\n'
                'to ${LeaveRequest.formatDate(r.endDate)}  ·  ${r.days} days',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[600], height: 1.5),
              ),

              if (widget.approving) ...[
                const SizedBox(height: 14),
                _buildImpactBlock(),
              ],

              if (widget.approving && _overCap) ...[
                const SizedBox(height: 14),
                _buildEndorsementBlock(),
              ],

              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: _fieldDecoration(
                  label: 'Note to the employee (optional)',
                  hint: widget.approving
                      ? 'e.g. Approved — coordinate your turnover before you go.'
                      : 'e.g. Denied — we are short-staffed that period.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: _kMuted),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canSubmit
              ? () => Navigator.pop(context, {
                    'note': _noteController.text.trim(),
                    'supervisorName': _supervisorController.text.trim(),
                    'supervisorConfirmed': _endorsementConfirmed,
                  })
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFCBD5E1),
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(widget.approving ? 'Approve' : 'Deny'),
        ),
      ],
    );
  }

  // What this leave costs the roster. Deliberately shown before the
  // decision, not after: a 15-day leave that empties a shift is exactly
  // the case an admin must not approve blind.
  Widget _buildImpactBlock() {
    if (_loadingImpact) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
          ),
          const SizedBox(width: 10),
          Text('Checking what this leave costs the roster…',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
        ],
      );
    }

    final impact = _impact;
    if (impact == null) {
      return Text(
        'Could not load the coverage impact — deciding is still possible.',
        style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
      );
    }

    final peers = impact['peerCount'] as int? ?? 0;
    final bare = impact['leavesShiftBare'] == true;
    final published = impact['publishedDutyCount'] as int? ?? 0;
    final station = (impact['station'] as String? ?? '').trim();
    final warn = bare || published > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFFBEB) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: warn ? const Color(0xFFFDE68A) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(warn ? Icons.warning_amber_rounded : Icons.insights_rounded,
                  size: 15,
                  color: warn ? const Color(0xFFB45309) : _kMuted),
              const SizedBox(width: 6),
              Text(
                'Coverage impact',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: warn ? const Color(0xFF92400E) : _kMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bare
                ? 'This leaves ${station.isEmpty ? 'their shift' : station} '
                    'with no other guard on their shift — every one of the '
                    '${r.days} days falls on the reliever pool.'
                : '${station.isEmpty ? 'Their shift' : station} keeps $peers '
                    'other guard(s) on the same shift for the ${r.days} days.',
            style: const TextStyle(
                fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
          ),
          if (published > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$published duty(ies) on an already-published schedule fall '
              'inside this range and will need replacements.',
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF92400E), height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  // The consent gate. Nothing here is optional — the backend refuses the
  // approval without both fields, so the button stays dead until they're
  // filled rather than failing after the fact.
  Widget _buildEndorsementBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded,
                  size: 16, color: Color(0xFFB91C1C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Higher authority required — ${r.days}-day ${r.leaveType}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF991B1B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This runs past the $_cap-day cap for ${r.leaveType}. Approving '
            'this leave without proper consent in the higher authority will '
            'result to heavy penalty.',
            style: const TextStyle(
                fontSize: 12.5, color: Color(0xFF991B1B), height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _supervisorController,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              label: 'Endorsed by (Supervisor) *',
              hint: 'Full name of the supervisor who approved it',
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _endorsementConfirmed,
            onChanged: (v) =>
                setState(() => _endorsementConfirmed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: const Color(0xFFB91C1C),
            title: const Text(
              'I confirm this leave was discussed with and approved by the '
              'supervisor named above.',
              style: TextStyle(
                  fontSize: 12.5, color: Color(0xFF7F1D1D), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
