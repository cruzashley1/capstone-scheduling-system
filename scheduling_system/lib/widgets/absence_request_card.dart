// widgets/absence_request_card.dart
//
// Dashboard entry point for the emergency absence request flow. Shown on
// both the security guard and head guard dashboards right under Today's
// Duty. It doubles as a status card: once the guard has filed for the duty
// in question it stops inviting a new request and reports where that one
// stands.
//
// It is gated on the clock, not just the date: filing closes one hour
// before time-in (DutyClock.absenceCutoff), so a duty about to start, one
// already running and one already stood are all off limits. When nothing
// is fileable at all the card goes flat and untappable instead of opening
// a form with no valid date.
import 'package:flutter/material.dart';
import '../models/absence_request.dart';
import '../models/employee.dart';
import '../models/guard_shift.dart';
import '../screens/absence_request_screen.dart';
import '../services/duty_clock.dart';

class AbsenceRequestCard extends StatelessWidget {
  final Employee employee;
  final List<GuardShift> shifts;

  // Every request this guard has filed, owned by the host layout so the
  // duty card and this card can't disagree about who is absent.
  final List<AbsenceRequest> requests;

  // The guard's status right now — decides which duty day this card is
  // about (during an overnight shift that's yesterday, not today).
  final LiveDutyState state;

  // Refetches the host's data after a successful submission.
  final Future<void> Function() onChanged;

  const AbsenceRequestCard({
    super.key,
    required this.employee,
    required this.shifts,
    required this.requests,
    required this.state,
    required this.onChanged,
  });

  // The duty day this card speaks for: the one the status badge is about.
  DateTime get _dutyDate => state.relevantDutyDate;

  String get _dutyIso => DutyClock.iso(_dutyDate);

  // Duty days a NEW request may still target — empty means there's
  // nothing left to file for.
  List<DateTime> get _fileableDates => DutyClock.fileableDates(
        shifts: shifts,
        existingRequests: requests,
        at: state.now,
      );

  // Newest request already on file for this card's duty day, if any.
  AbsenceRequest? get _dutyRequest {
    final forDay = requests.where((r) => r.date == _dutyIso).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return forDay.isEmpty ? null : forDay.first;
  }

  Future<void> _openRequestScreen(BuildContext context) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AbsenceRequestScreen(
          employee: employee,
          shifts: shifts,
          // Already-filed days (any status) show their decision instead
          // of letting them re-file; finished duties aren't offered.
          existingRequests: requests,
          initialDate: _dutyDate,
        ),
      ),
    );
    if (submitted != true || !context.mounted) return;

    await onChanged();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Absence request submitted. The admin will review it shortly.',
        ),
        backgroundColor: Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _statusColor(AbsenceRequest request) {
    if (request.isApproved) return const Color(0xFF16A34A);
    if (request.isDenied) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String _statusLabel(AbsenceRequest request) {
    if (request.isApproved) return 'Approved';
    if (request.isDenied) return 'Denied';
    return 'Pending';
  }

  IconData _statusIcon(AbsenceRequest request) {
    if (request.isApproved) return Icons.check_circle_outline;
    if (request.isDenied) return Icons.cancel_outlined;
    return Icons.hourglass_bottom_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final request = _dutyRequest;
    final fileable = _fileableDates;

    if (request != null) return _buildStatus(context, request, fileable);
    if (fileable.isEmpty) return _buildClosed();
    return _buildInvite(context, fileable);
  }

  // Nothing left to file against: the lock-out before today's duty has
  // started, that duty is over, or there is no duty on the published
  // schedule to be absent from.
  Widget _buildClosed() {
    final String reason;
    final shift = state.shift;
    if (state.isFinished && shift != null) {
      reason = 'Your ${shift.title.toLowerCase()} ended at '
          '${shift.timeOut.isEmpty ? 'its scheduled time' : shift.timeOut}. '
          'An absence can only be filed before a duty ends.';
    } else if (state.isAbsent) {
      reason = "You're already excused from this duty.";
    } else if (shift != null && state.isPastAbsenceCutoff) {
      final deadline = DutyClock.absenceDeadline(shift);
      final cutoff = deadline == null ? '' : DutyClock.military(deadline);
      reason = 'Requests close 1 hour before time-in. Your '
          '${shift.title.toLowerCase()} starts at ${shift.timeIn}, so the '
          'cut-off${cutoff.isEmpty ? '' : ' ($cutoff)'} has passed — tell '
          'your head guard directly.';
    } else if (state.isDayOff) {
      reason = 'You have no duty scheduled today.';
    } else {
      reason = 'No upcoming duty on your published schedule.';
    }

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
            child: const Icon(
              Icons.event_busy_outlined,
              color: Color(0xFF94A3B8),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency absence unavailable',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvite(BuildContext context, List<DateTime> fileable) {
    // Whether the duty being shown on the status badge is itself still
    // fileable — otherwise the guard is filing for a later day.
    final forThisDuty = fileable.any((d) => d == _dutyDate);
    final subtitle = forThisDuty
        ? 'File now — requests close 1 hour before time-in.'
        : 'File an emergency absence request for an upcoming duty.';

    return _shell(
      onTap: () => _openRequestScreen(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy_outlined,
              color: Color(0xFFDC2626),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Can't report for duty?",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF94A3B8),
            size: 20,
          ),
        ],
      ),
    );
  }

  // Stays tappable while some other duty can still be filed for, so the
  // guard can file for an upcoming day. The form's date picker excludes
  // every date they've already requested and every duty that has ended,
  // so the same day can't be filed twice and a finished one can't be
  // filed at all.
  Widget _buildStatus(
    BuildContext context,
    AbsenceRequest request,
    List<DateTime> fileable,
  ) {
    final color = _statusColor(request);
    final canFileMore = fileable.isNotEmpty;

    return _shell(
      onTap: canFileMore ? () => _openRequestScreen(context) : null,
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
                        request.title,
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
                  'Absence request · ${request.timeAgo}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (canFileMore)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
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
