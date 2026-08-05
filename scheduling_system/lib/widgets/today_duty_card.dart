// widgets/today_duty_card.dart
//
// The "Today's Duty" hero card shared by the security guard and head guard
// dashboards. Everything it shows comes from a LiveDutyState resolved
// against the wall clock, so the status (On Duty / Awaiting / Off Shift /
// Day Off / Absent) and the countdown change as the shift actually runs.
// The host owns the ticker and hands a fresh state down each second.
import 'package:flutter/material.dart';

import '../services/duty_clock.dart';

class TodayDutyCard extends StatelessWidget {
  final LiveDutyState state;

  // Where the guard works — today's duty station when there is one, else
  // the host's fallback (fixed assignment / current period / roster).
  final String stationLabel;

  const TodayDutyCard({
    super.key,
    required this.state,
    required this.stationLabel,
  });

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final shift = state.shift;
    final note = state.progressNote;
    final progress = state.progress;
    final now = state.now;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1034A6),
            Color(0xFF1E4AD0),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1034A6).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The badge carries the longest labels ('Unassigned', 'Off
          // Shift'), so the title yields first rather than overflowing
          // the row at large text scales.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  "Today's Duty",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(),
            ],
          ),
          const SizedBox(height: 16),

          // The live clock is the anchor for everything below it — it's
          // what tells the guard the status is being read off the real
          // time and not just off today's date.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                DutyClock.military(now),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  height: 1.05,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  DutyClock.clock12(now),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            state.headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.subline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          // How far through the shift the guard is.
          if (progress != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(state.color),
              ),
            ),
          ],

          if (note != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(state.icon, color: state.color, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: state.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  shift != null && shift.stationName.isNotEmpty
                      ? shift.stationName
                      : stationLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              const Icon(
                Icons.calendar_today_outlined,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${_months[now.month - 1]} ${now.day}, ${now.year}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          // An overnight duty that started yesterday is still "today's"
          // duty to the guard standing the post — say which day it's from
          // so the times on the card make sense.
          if (shift != null &&
              DutyClock.dateOnly(shift.date) != DutyClock.dateOnly(now)) ...[
            const SizedBox(height: 12),
            _chip(
              'Overnight duty from '
              '${_months[shift.date.month - 1]} ${shift.date.day}',
              const Color(0xFF93C5FD),
            ),
          ],

          if (shift != null && shift.isCovering) ...[
            const SizedBox(height: 12),
            _chip('Covering for ${shift.coveringFor}', Colors.amber),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final color = state.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            state.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
