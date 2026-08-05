// screens/find_replacement_screen.dart
//
// "Show List of Suitable Replacement" step of the absence flow.
// Fetches ranked, conflict-free candidates from the backend for one
// absence, lets the admin open each candidate's full profile
// (employee_detail_screen), and commits the chosen replacement —
// which updates the schedule, stamps the report record, and notifies
// the chosen guard.

import 'package:flutter/material.dart';
import '../models/replacement.dart';
import '../services/api_service.dart';
import 'main_layout.dart';

class FindReplacementScreen extends StatefulWidget {
  final ReplacementRequest request;
  final Function(ScreenType, {dynamic data}) onNavigate;

  const FindReplacementScreen({
    super.key,
    required this.request,
    required this.onNavigate,
  });

  @override
  State<FindReplacementScreen> createState() => _FindReplacementScreenState();
}

class _FindReplacementScreenState extends State<FindReplacementScreen> {
  List<ReplacementCandidate> _candidates = [];
  bool _isLoading = true;
  String? _loadError;
  bool _isApplying = false;

  ReplacementRequest get _req => widget.request;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final result = await ApiService.suggestReplacements(
      date: _req.date,
      station: _req.station,
      shift: _req.shift,
      absentEmployeeId: _req.absentEmployeeId,
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _candidates =
            (result['candidates'] as List).cast<ReplacementCandidate>();
      } else {
        _loadError = result['error']?.toString() ?? 'Failed to load';
      }
    });
  }

  // Back to wherever this screen was opened from: the absence-request
  // inbox (approval flow), the submitted report detail, or the Absent
  // Today list.
  void _goBack() {
    if (_req.isApprovalFlow) {
      widget.onNavigate(ScreenType.notifications);
    } else if (_req.report != null) {
      widget.onNavigate(ScreenType.submittedReportDetail, data: _req.report);
    } else {
      widget.onNavigate(ScreenType.absentManagement);
    }
  }

  Future<void> _confirmAndAssign(ReplacementCandidate candidate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(_req.isApprovalFlow
            ? 'Approve absence & assign cover'
            : 'Assign Replacement'),
        content: Text(
          'Assign ${candidate.employee.name} to cover '
          '${_req.absentName}\'s ${_req.shift} shift at ${_req.station} '
          'on ${_req.date}?\n\nThe schedule will be updated and '
          '${candidate.employee.name} will be notified.'
          '${_req.isApprovalFlow ? '\n\n${_req.absentName}\'s absence request '
              'will be approved.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1034A6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isApplying = true);

    final result = await ApiService.applyReplacement(
      date: _req.date,
      station: _req.station,
      shift: _req.shift,
      absentEmployeeId: _req.absentEmployeeId,
      absentEmployeeName: _req.absentName,
      replacementEmployeeId: candidate.employee.id,
      reportId: _req.reportId,
      absenceRequestId: _req.absenceRequestId,
    );
    if (!mounted) return;

    setState(() => _isApplying = false);

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign: ${result['error']}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // A 409 means the candidate list went stale — refresh it.
      if (result['conflict'] == true) _loadCandidates();
      return;
    }

    // Stamp the in-memory report record so the detail screen shows
    // "Replaced by ..." immediately (the backend already saved it).
    _req.record?.replacedById = candidate.employee.id;
    _req.record?.replacedByName = candidate.employee.name;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_req.isApprovalFlow
            ? 'Absence approved — ${candidate.employee.name} now covers '
                '${_req.absentName}\'s post.'
            : 'Schedule updated — ${candidate.employee.name} now covers '
                '${_req.absentName}\'s post.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _goBack();
  }

  void _openEmployeeDetail(ReplacementCandidate candidate) {
    widget.onNavigate(
      ScreenType.employeeDetail,
      data: EmployeeDetailNav(
        employee: candidate.employee,
        returnTo: ScreenType.findReplacement,
        returnData: _req,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                  onPressed: _goBack,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Find Replacement',
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _req.isApprovalFlow
                            ? 'Assign a cover to approve this absence'
                            : 'Suitable, conflict-free candidates for this post',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _loadCandidates,
                  tooltip: 'Refresh',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF1034A6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1034A6)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAbsenceContextCard(),
                        const SizedBox(height: 24),

                        if (_loadError != null)
                          _buildErrorBanner()
                        else ...[
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1034A6),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Suggested Replacements '
                                '(${_candidates.length})',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              'Everyone below is free on ${_req.date} — '
                              'no schedule conflicts. Tap a card to view '
                              'the full profile.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_candidates.isEmpty)
                            _buildEmptyState()
                          else
                            ..._candidates.asMap().entries.map(
                                (e) => _buildCandidateCard(e.key, e.value)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Who is absent, where, when — the post that needs covering.
  Widget _buildAbsenceContextCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.person_off_outlined,
                color: Colors.red[500], size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_req.absentName} is absent',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_req.absentEmployeeId} · ${_req.shift} shift · '
                  '${_req.station} · ${_req.date}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Needs replacement',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.red[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD97706)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 18, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not load suggestions: $_loadError',
              style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
            ),
          ),
          TextButton(
            onPressed: _loadCandidates,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(Icons.person_search, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _req.isApprovalFlow
                ? 'No cover available — can\'t approve'
                : 'No suitable replacement available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _req.isApprovalFlow
                  ? 'No eligible ${_req.shift} guard is free on ${_req.date} '
                      'to cover ${_req.absentName}. This absence can\'t be '
                      'approved without a cover — go back and Deny it, or '
                      'leave it pending until someone frees up.'
                  : 'Everyone eligible for this ${_req.shift} post is already '
                      'scheduled on ${_req.date} (or also absent). The post '
                      'may need internal switching handled manually.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ),
          if (_req.isApprovalFlow) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to the request'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1034A6),
                side: const BorderSide(color: Color(0xFFC7D2FE)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCandidateCard(int index, ReplacementCandidate candidate) {
    final employee = candidate.employee;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          // Flowchart: the list is clickable and opens the employee's
          // detail screen.
          onTap: () => _openEmployeeDetail(candidate),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: index == 0
                    ? const Color(0xFF1034A6).withOpacity(0.45)
                    : const Color(0xFFE2E8F0),
                width: index == 0 ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank + avatar
                Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1034A6),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          employee.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '#${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: index == 0
                            ? const Color(0xFF1034A6)
                            : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),

                // Name, id, badges, reasons
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              employee.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildTypeBadge(employee.type.name),
                          if (index == 0) ...[
                            const SizedBox(width: 6),
                            _buildBestMatchBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${employee.id} · ${employee.phone}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildReasonChip(
                            'No schedule conflict',
                            icon: Icons.check_circle,
                            color: const Color(0xFF059669),
                          ),
                          ...candidate.reasons.map(_buildReasonChip),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Score + assign button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildScoreBadge(candidate.score),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed:
                          _isApplying ? null : () => _confirmAndAssign(candidate),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Assign'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1034A6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String typeName) {
    final label = typeName == 'headGuard'
        ? 'Head Guard'
        : typeName == 'reliever'
            ? 'Reliever'
            : 'Regular';
    final color = typeName == 'headGuard'
        ? const Color(0xFF0369A1)
        : typeName == 'reliever'
            ? const Color(0xFF059669)
            : const Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBestMatchBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Best match',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildReasonChip(String text, {IconData? icon, Color? color}) {
    final chipColor = color ?? const Color(0xFF475569);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: chipColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBadge(int score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$score',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1034A6),
          ),
        ),
        Text(
          'match score',
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }
}
