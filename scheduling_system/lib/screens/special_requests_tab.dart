// screens/special_requests_tab.dart
//
// Admin side of the special day-off flow: the body of the third tab in
// the Notifications screen. An employee asks — ahead of the schedule —
// for up to three specific days off; the admin approves or denies the
// whole request here, and an approved request forces those days off when
// that period's schedule is generated. The employee is told the outcome
// through their Alerts inbox.
//
// This renders a scrollable body only — the host Notifications screen
// owns the page header and the tab bar.

import 'package:flutter/material.dart';
import '../models/special_request.dart';
import '../services/api_service.dart';

class SpecialRequestsTab extends StatefulWidget {
  // Fires after every successful load and right after a decision, so the
  // host can badge the tab without owning the list.
  final ValueChanged<int>? onPendingCountChanged;

  const SpecialRequestsTab({
    super.key,
    this.onPendingCountChanged,
  });

  @override
  State<SpecialRequestsTab> createState() => SpecialRequestsTabState();
}

// Public so the host screen can hold a GlobalKey<SpecialRequestsTabState>
// and call reload() when it refreshes the whole inbox.
class SpecialRequestsTabState extends State<SpecialRequestsTab> {
  List<SpecialRequest> _requests = [];
  bool _isLoading = true;
  String? _loadError;

  String _filter = 'Pending'; // All | Pending | Approved | Denied

  // Id of the request currently being decided, so its buttons can't be
  // double-tapped while the call is in flight.
  String? _decidingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Public entry point for the host screen's refresh button.
  Future<void> reload() => _load();

  Future<void> _load() async {
    if (_requests.isEmpty) setState(() => _isLoading = true);

    final result = await ApiService.fetchSpecialRequests();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _requests = (result['requests'] as List).cast<SpecialRequest>();
        _loadError = null;
      } else {
        _requests = [];
        _loadError = result['error']?.toString().isNotEmpty == true
            ? 'Could not reach the server — ${result['error']}'
            : 'Could not reach the server — no special requests loaded.';
      }
    });

    if (result['success'] == true) _notifyPendingCount();
  }

  void _notifyPendingCount() {
    widget.onPendingCountChanged?.call(_pendingCount);
  }

  int get _pendingCount => _requests.where((r) => r.isPending).length;
  int get _approvedCount => _requests.where((r) => r.isApproved).length;
  int get _deniedCount => _requests.where((r) => r.isDenied).length;

  List<SpecialRequest> get _visibleRequests {
    switch (_filter) {
      case 'Pending':
        return _requests.where((r) => r.isPending).toList();
      case 'Approved':
        return _requests.where((r) => r.isApproved).toList();
      case 'Denied':
        return _requests.where((r) => r.isDenied).toList();
      default:
        return _requests;
    }
  }

  // ── status styling ──────────────────────────────────────────────

  Color _statusColor(SpecialRequest r) {
    if (r.isApproved) return const Color(0xFF16A34A);
    if (r.isDenied) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  IconData _statusIcon(SpecialRequest r) {
    if (r.isApproved) return Icons.check_circle_outline;
    if (r.isDenied) return Icons.cancel_outlined;
    return Icons.pending_actions_rounded;
  }

  String _statusLabel(SpecialRequest r) {
    if (r.isApproved) return 'Approved';
    if (r.isDenied) return 'Denied';
    return 'Pending';
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

  // ── actions ─────────────────────────────────────────────────────

  void _openDetail(SpecialRequest request) {
    if (!request.isRead) {
      setState(() => request.isRead = true);
      if (_loadError == null) ApiService.markSpecialRequestRead(request.id);
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _buildDetailDialog(dialogContext, request),
    );
  }

  // Confirms the decision and collects the optional note the employee will
  // see in their Alerts inbox, then writes it through the API. The whole
  // request (all its dates) is approved or denied together.
  Future<void> _decide(SpecialRequest request, String status) async {
    final approving = status == 'approved';
    final accent =
        approving ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final noteController = TextEditingController();

    String note = '';
    bool confirmed = false;
    try {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    approving
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      approving
                          ? 'Approve this request?'
                          : 'Deny this request?',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.employeeName} — ${request.title}\n'
                      '${request.dayCount} day(s): ${request.datesSummary}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                    if (approving) ...[
                      const SizedBox(height: 10),
                      Text(
                        'These days will be set off when that period\'s '
                        'schedule is generated.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Note to the employee (optional)',
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        hintText: approving
                            ? 'e.g. Approved — enjoy your time off.'
                            : 'e.g. Denied — we are short-staffed those days.',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[400],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF1034A6)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(approving ? 'Approve' : 'Deny'),
                ),
              ],
            ),
          ) ??
          false;
      note = noteController.text.trim();
    } finally {
      noteController.dispose();
    }

    if (!confirmed || !mounted) return;

    setState(() => _decidingId = request.id);

    final result = await ApiService.decideSpecialRequest(
      id: request.id,
      status: status,
      adminNote: note,
    );
    if (!mounted) return;

    setState(() => _decidingId = null);

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['error']?.toString() ?? 'Could not save the decision.',
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final updated = result['request'];
    setState(() {
      if (updated is SpecialRequest) {
        request.status = updated.status;
        request.adminNote = updated.adminNote;
      } else {
        request.status = status;
        request.adminNote = note;
      }
      request.isRead = true;
    });
    _notifyPendingCount();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approving
              ? 'Request approved — ${request.employeeName} has been notified.'
              : 'Request denied — ${request.employeeName} has been notified.',
        ),
        backgroundColor: accent,
        behavior: SnackBarBehavior.floating,
      ),
    );

    await _load();
  }

  // ── build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1034A6)),
      );
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
                  TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
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
              _buildFilterChip('Approved', _approvedCount),
              _buildFilterChip('Denied', _deniedCount),
            ],
          ),
          const SizedBox(height: 20),

          if (_visibleRequests.isEmpty)
            _buildEmptyState()
          else
            ..._visibleRequests.map((r) => _buildRequestCard(r)),
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
          color: isSelected ? const Color(0xFF1034A6) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF1034A6) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
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
        title = 'No pending requests';
        subtitle = 'Nothing is waiting on your decision right now.';
        break;
      case 'Approved':
        icon = Icons.check_circle_outline;
        title = 'No approved requests';
        subtitle = 'Requests you approve will be listed here.';
        break;
      case 'Denied':
        icon = Icons.cancel_outlined;
        title = 'No denied requests';
        subtitle = 'Requests you deny will be listed here.';
        break;
      default:
        icon = Icons.event_available_outlined;
        title = 'Nothing here yet';
        subtitle = 'Special day-off requests filed by employees '
            'will appear here.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
              color: Colors.grey[500],
            ),
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

  Widget _buildRequestCard(SpecialRequest request) {
    final color = _statusColor(request);
    final isDeciding = _decidingId == request.id;

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
                color: request.isRead
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFBFDBFE),
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
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            request.timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (!request.isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1034A6),
                                shape: BoxShape.circle,
                              ),
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
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildStatusPill(request),
                          _buildMetaChip(
                            Icons.event_available_outlined,
                            '${request.dayCount} day(s)',
                          ),
                          if (request.station.isNotEmpty)
                            _buildMetaChip(
                                Icons.location_on_outlined, request.station),
                          _buildMetaChip(
                              Icons.label_outline, request.reason),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // The requested days, each as its own chip.
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: request.dates
                            .map((d) => _buildDatePill(d))
                            .toList(),
                      ),
                      const SizedBox(height: 10),

                      Text(
                        request.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
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
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
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
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(
                                    color: Color(0xFFFECACA)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
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
                                          strokeWidth: 2,
                                          color: Color(0xFF1034A6),
                                        ),
                                      )
                                    : Text(
                                        'View details',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF1034A6)
                                              .withOpacity(0.9),
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

  Widget _buildStatusPill(SpecialRequest request) {
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
            _statusLabel(request),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
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
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A single requested day, rendered in the app's blue so the dates stand
  // out from the grey meta chips.
  Widget _buildDatePill(String iso) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1034A6).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event, size: 13, color: Color(0xFF1034A6)),
          const SizedBox(width: 5),
          Text(
            SpecialRequest.formatShort(iso),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1034A6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeBlock(SpecialRequest request) {
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
                  '${_statusLabel(request)}'
                  '${request.decidedBy != null && request.decidedBy!.isNotEmpty ? ' by ${request.decidedBy}' : ''}'
                  '${decided != null ? ' · ${_formatDateTime(decided)}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (request.adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Note: ${request.adminNote}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── detail dialog ───────────────────────────────────────────────

  Widget _buildDetailDialog(BuildContext dialogContext, SpecialRequest r) {
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
                    color: Color(0xFF1E293B),
                  ),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
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
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 14),

              _buildDetailRow(
                Icons.badge_outlined,
                'Employee',
                '${r.employeeName} · ${r.roleLabel}',
                sub: r.employeeId,
              ),
              _buildDetailRow(
                Icons.location_on_outlined,
                'Station',
                r.station.isEmpty ? 'Floating / As assigned' : r.station,
              ),
              _buildDetailRow(
                Icons.label_outline,
                'Reason',
                r.reason,
              ),
              _buildDetailRow(
                Icons.schedule_send_outlined,
                'Filed',
                _formatDateTime(r.submittedAt),
                sub: r.id,
              ),

              const SizedBox(height: 6),
              Text(
                'Days requested (${r.dayCount})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              ...r.dates.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.event,
                          size: 16, color: Color(0xFF1034A6)),
                      const SizedBox(width: 8),
                      Text(
                        SpecialRequest.formatDate(d),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Reason details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  r.body.isEmpty ? 'No details provided.' : r.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
              ),

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
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
          ),
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
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFECACA)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
          Icon(icon, size: 18, color: const Color(0xFF1034A6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (sub != null && sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
