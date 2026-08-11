// screens/submitted_reports_screen.dart
//
// Admin view of all attendance reports submitted by Head Guards.
// Contains the list screen (SubmittedReportsContent) and the read-only
// detail screen (SubmittedReportDetailContent) opened from either the
// list or a notification.

import 'package:flutter/material.dart';
import '../data/attendance_report_dummy_data.dart';
import '../models/attendance_report.dart';
import '../models/replacement.dart';
import '../services/api_service.dart';
import '../services/cover_window.dart';
import 'main_layout.dart';

// ─────────────────────────────────────────────
// LIST SCREEN
// ─────────────────────────────────────────────
class SubmittedReportsContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data})? onNavigate;

  const SubmittedReportsContent({
    super.key,
    this.onNavigate,
  });

  @override
  State<SubmittedReportsContent> createState() =>
      _SubmittedReportsContentState();
}

class _SubmittedReportsContentState extends State<SubmittedReportsContent> {
  List<AttendanceReport> _reports = [];
  bool _isLoading = true;
  // Set when the server can't be reached and we're showing sample data.
  String? _loadError;

  String _searchQuery = '';
  String _filter = 'All'; // All | With Absences | All Present

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);

    final result = await ApiService.fetchAttendanceReports();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _reports = (result['reports'] as List).cast<AttendanceReport>();
        _loadError = null;
      } else {
        _reports = AttendanceReportDummyData.reports;
        _loadError = 'Could not reach the server — showing sample reports.';
      }
    });
  }

  List<AttendanceReport> get _visibleReports {
    return _reports.where((r) {
      if (_filter == 'With Absences' && !r.hasAbsent) return false;
      if (_filter == 'All Present' && r.hasAbsent) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return r.headGuardName.toLowerCase().contains(q) ||
            r.station.toLowerCase().contains(q) ||
            r.shiftTitle.toLowerCase().contains(q) ||
            r.id.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  int get _withAbsencesCount => _reports.where((r) => r.hasAbsent).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      widget.onNavigate?.call(ScreenType.notifications),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submitted Reports',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Attendance reports submitted by head guards',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _loadReports,
                  tooltip: 'Refresh',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF1034A6),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF1034A6)),
                  )
                : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
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
                            onPressed: _loadReports,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Stat row
                  Row(
                    children: [
                      _buildStatCard(
                        'Total Reports',
                        '${_reports.length}',
                        Icons.assignment_outlined,
                        const Color(0xFF1034A6),
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'With Absences',
                        '$_withAbsencesCount',
                        Icons.warning_amber_rounded,
                        const Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'All Present',
                        '${_reports.length - _withAbsencesCount}',
                        Icons.check_circle_outline,
                        const Color(0xFF059669),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Search + filters
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              hintText:
                                  'Search by head guard, station, or shift...',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 20,
                                color: Colors.grey[400],
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildFilterChip('All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('With Absences'),
                      const SizedBox(width: 8),
                      _buildFilterChip('All Present'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (_visibleReports.isEmpty)
                    _buildEmptyState()
                  else
                    ..._visibleReports.map((r) => _buildReportCard(r)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _filter == label;
    return InkWell(
      onTap: () => setState(() => _filter = label),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1034A6) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF1034A6) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 48,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text(
            'No reports found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search or filter.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(AttendanceReport report) {
    final hasAbsent = report.hasAbsent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => widget.onNavigate
              ?.call(ScreenType.submittedReportDetail, data: report),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                // Status icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasAbsent
                        ? Colors.red.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasAbsent
                        ? Icons.warning_amber_rounded
                        : Icons.assignment_turned_in_outlined,
                    color: hasAbsent ? Colors.red[400] : Colors.green[600],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // Report info
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${report.shiftTitle} — ${report.station}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.shiftDate,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        report.id,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),

                // Head guard
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submitted by',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.headGuardName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        report.headGuardId,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),

                // Attendance summary
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: hasAbsent
                            ? Colors.red.withOpacity(0.08)
                            : Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        hasAbsent
                            ? '${report.absentCount} Absent'
                            : 'All Present',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hasAbsent ? Colors.red[600] : Colors.green[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${report.presentCount}/${report.totalCount} present',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DETAIL SCREEN (read-only)
// ─────────────────────────────────────────────
class SubmittedReportDetailContent extends StatelessWidget {
  final AttendanceReport report;
  final Function(ScreenType, {dynamic data})? onNavigate;

  const SubmittedReportDetailContent({
    super.key,
    required this.report,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final hasAbsent = report.hasAbsent;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      onNavigate?.call(ScreenType.submittedReports),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${report.shiftTitle} — ${report.station}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '${report.shiftDate}  ·  ${report.id}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: hasAbsent ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hasAbsent ? Colors.red[200]! : Colors.green[200]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasAbsent
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle,
                        size: 16,
                        color: hasAbsent ? Colors.red[600] : Colors.green[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasAbsent
                            ? '${report.absentCount} Absent'
                            : 'All Present',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              hasAbsent ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildSummaryItem(
                              label: 'Submitted by',
                              value: report.headGuardName,
                              sub: report.headGuardId,
                              icon: Icons.badge_outlined,
                            ),
                            _buildSummaryItem(
                              label: 'Present',
                              value: '${report.presentCount}',
                              sub: 'of ${report.totalCount} personnel',
                              icon: Icons.check_circle_outline,
                              iconColor: Colors.green[600],
                            ),
                            _buildSummaryItem(
                              label: 'Absent',
                              value: '${report.absentCount}',
                              sub: hasAbsent
                                  ? 'needs replacement'
                                  : 'no action needed',
                              icon: Icons.cancel_outlined,
                              iconColor: hasAbsent
                                  ? Colors.red[500]
                                  : Colors.grey[400],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: report.totalCount == 0
                                ? 0
                                : report.presentCount / report.totalCount,
                            minHeight: 8,
                            backgroundColor: Colors.grey[200],
                            color: const Color(0xFF1034A6),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Absent personnel first, so the admin sees who needs
                  // a replacement immediately (flowchart: "if has absent").
                  if (hasAbsent) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.red[500]),
                        const SizedBox(width: 8),
                        const Text(
                          'Absent Personnel',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...report.absentRecords.map(
                      (r) => _buildPersonnelCard(
                        r,
                        highlightAbsent: true,
                        showReplacementAction: true,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Text(
                    'All Personnel',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...report.records.map((r) => _buildPersonnelCard(r)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    Color? iconColor,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor ?? const Color(0xFF1034A6)),
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
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  sub,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Flowchart: "AI suggest suitable replacement" — the button hands the
  // absence to the Find Replacement screen; once covered, the card shows
  // who replaced them instead.
  //
  // Reports are read long after the shift they cover, so the button also
  // has to disappear once that post has timed out: there is nobody left
  // to send to a duty that is over (see CoverWindow). What's left is a
  // record of an absence that went uncovered, which is the truth.
  Widget _buildReplacementAction(AttendanceRecord record) {
    if (record.isReplaced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF059669).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF059669)),
            const SizedBox(width: 6),
            Text(
              'Replaced by ${record.replacedByName}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF059669),
              ),
            ),
          ],
        ),
      );
    }
    final end =
        CoverWindow.endsAt(report.date, record.shift, range: record.time);
    if (end != null && CoverWindow.hasPassed(end)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_toggle_off_rounded,
                size: 14, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(
              'Shift ended — no cover possible',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: () => onNavigate?.call(
        ScreenType.findReplacement,
        data: ReplacementRequest(
          date: report.date,
          station: report.station,
          shift: record.shift,
          absentEmployeeId: record.employeeId,
          absentName: record.name,
          reportId: report.id,
          report: report,
          record: record,
        ),
      ),
      icon: const Icon(Icons.person_search, size: 16),
      label: const Text('Find Replacement'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1034A6),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildPersonnelCard(AttendanceRecord record,
      {bool highlightAbsent = false, bool showReplacementAction = false}) {
    final isPresent = record.isPresent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlightAbsent ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlightAbsent
              ? const Color(0xFFFECACA)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: record.avatarColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                record.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name + details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '${record.shift} · ${record.time}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (record.isReliever) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Reliever',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  record.employeeId,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Absent cards get the replacement action (button or
          // "Replaced by ..." once covered) next to the status pill.
          if (showReplacementAction && !isPresent) ...[
            _buildReplacementAction(record),
            const SizedBox(width: 8),
          ],

          // Present / Absent pill (read-only)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isPresent
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPresent ? Icons.check_circle : Icons.cancel,
                  size: 14,
                  color: isPresent ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  isPresent ? 'Present' : 'Absent',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isPresent ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
