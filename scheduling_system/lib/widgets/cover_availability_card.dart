// widgets/cover_availability_card.dart
//
// Dashboard entry point for the "available to cover" flow. Shown on the
// security guard and head guard dashboards ONLY when today is a rest day
// (the host decides that). It doubles as a status card: once the guard has
// offered to cover today it reports that, and once the admin assigns them
// it shows they're covering. Tapping opens the preference form for today.
import 'package:flutter/material.dart';
import '../models/cover_offer.dart';
import '../models/employee.dart';
import '../screens/cover_availability_screen.dart';
import '../services/api_service.dart';
import '../services/server_clock.dart';

class CoverAvailabilityCard extends StatefulWidget {
  final Employee employee;

  const CoverAvailabilityCard({
    super.key,
    required this.employee,
  });

  @override
  State<CoverAvailabilityCard> createState() => _CoverAvailabilityCardState();
}

class _CoverAvailabilityCardState extends State<CoverAvailabilityCard> {
  CoverOffer? _todayOffer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _today {
    final now = ServerClock.now();
    return DateTime(now.year, now.month, now.day);
  }

  String get _todayIso {
    final d = _today;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result =
        await ApiService.fetchEmployeeCoverOffers(widget.employee.id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        final offers = (result['offers'] as List).cast<CoverOffer>();
        _todayOffer = offers.where((o) => o.date == _todayIso).isEmpty
            ? null
            : offers.firstWhere((o) => o.date == _todayIso);
      } else {
        _todayOffer = null;
      }
    });
  }

  Future<void> _open() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverAvailabilityScreen(
          employee: widget.employee,
          date: _today,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildPlaceholder();
    final offer = _todayOffer;
    if (offer == null) return _buildInvite();
    if (offer.isFulfilled) return _buildFulfilled();
    return _buildActive(offer);
  }

  Widget _buildPlaceholder() {
    return _shell(
      onTap: null,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
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
    return _shell(
      onTap: _open,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.volunteer_activism_outlined,
              color: Color(0xFF16A34A),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're off today — want a duty?",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mark yourself available to cover a shift today.',
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

  Widget _buildActive(CoverOffer offer) {
    const green = Color(0xFF16A34A);
    final summary = _summaryLine(offer);
    return _shell(
      onTap: _open,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                color: green, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "You're available to cover today",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
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
                        color: green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Available',
                        style: TextStyle(
                          color: green,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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

  Widget _buildFulfilled() {
    const blue = Color(0xFF1034A6);
    return _shell(
      onTap: _open,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_outlined,
                color: blue, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're covering a shift today",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'You were assigned to cover — check your schedule.',
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

  // "Morning, Night · 2 stations" — a compact recap of what they offered.
  String _summaryLine(CoverOffer offer) {
    final shifts = offer.preferredShifts.isEmpty
        ? 'Any shift'
        : offer.preferredShifts
            .map((s) => s.startsWith('HG ') ? s.substring(3) : s)
            .join(', ');
    final n = offer.preferredStations.length;
    final stations = n == 0
        ? 'any station'
        : n == 1
            ? offer.preferredStations.first
            : '$n stations';
    return '$shifts · $stations';
  }

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
