// screens/find_replacement_screen.dart
//
// "Show List of Suitable Replacement" step of the absence flow.
// Fetches ranked, conflict-free candidates from the backend for one
// absence, lets the admin open each candidate's full profile
// (employee_detail_screen), and commits the chosen replacement —
// which updates the schedule, stamps the report record, and notifies
// the chosen guard.
//
// Unless the post has already timed out. A cover is somebody sent to
// stand a post, so once the duty is over there is nobody to send: the
// screen then shows the closed window instead of a candidate list. The
// backend refuses the same case with 409, so a screen left open across
// the deadline can't slip one through either — see CoverWindow.
//
// A cover assigned once the post is already running does not inherit the
// absent guard's hours: the duty slides so the guard has an hour to get
// ready and travel (see PrepWindow). Those are the hours the admin is
// actually committing to, so the screen states them before they commit —
// the backend computes the authoritative pair at the instant of the
// assignment, and this is what that will be.

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/post_time.dart';
import '../models/replacement.dart';
import '../services/api_service.dart';
import '../services/cover_window.dart';
import '../services/prep_window.dart';
import '../widgets/ai_review_panel.dart';
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

  // When the post being covered times out. The backend reads it off the
  // absent guard's own schedule entry, so it accounts for the station's
  // staggered post times; until the fetch lands it's derived from the
  // shift name, which is enough to keep a plainly-finished duty from
  // flashing a list of candidates.
  DateTime? _windowEndsAt;

  // The post's own hours, for working out what a cover assigned NOW
  // would actually stand. Starts at the shift's base window and is
  // replaced by the backend's exact one when /suggest lands — the same
  // order of trust _windowEndsAt uses, and for the same reason: posts
  // are staggered per station, so the shift name is never enough.
  PostTime? _postWindow;

  // The AI's read on the shortlist. Null is the ordinary state, not a
  // failure — the AI may be switched off, out of quota, or looking at
  // too few candidates to have an opinion worth the request. The list
  // below renders identically either way.
  AiReview? _aiReview;
  bool _aiLoading = false;

  ReplacementRequest get _req => widget.request;

  // The duty is over — nobody can be sent to stand a post that has
  // already been stood, so there is nothing to assign here.
  bool get _isWindowClosed {
    final end = _windowEndsAt;
    return end != null && CoverWindow.hasPassed(end);
  }

  // What a cover assigned at this instant would stand. Recomputed on
  // every read rather than stored, because it moves with the clock: an
  // admin who leaves this screen open for twenty minutes has to be shown
  // the hours they would be committing to now, not twenty minutes ago.
  PrepAdjustment? get _prep =>
      PrepWindow.adjust(_req.date, _postWindow);

  @override
  void initState() {
    super.initState();
    _windowEndsAt = CoverWindow.endsAt(_req.date, _req.shift);
    _postWindow = baseShiftWindow(CoverWindow.canonicalShift(_req.shift));
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _aiReview = null;
      _aiLoading = true;
    });

    // Both requests go out together and the screen waits only on the
    // ranked list. The AI review is the slower of the two by a wide
    // margin, and it is the one the admin can act without — so it lands
    // into a panel above a list that is already usable, rather than
    // holding that list back.
    final reviewFuture = ApiService.aiReviewReplacements(
      date: _req.date,
      station: _req.station,
      shift: _req.shift,
      absentEmployeeId: _req.absentEmployeeId,
    );
    unawaited(_awaitReview(reviewFuture));

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
        // The server's window is the exact one — it knows which post this
        // guard mans. Keep the estimate if an older backend omits it.
        _windowEndsAt = CoverWindow.endsAt(
              _req.date,
              _req.shift,
              endsAtIso: result['coverWindowEndsAt']?.toString(),
            ) ??
            _windowEndsAt;
        _postWindow = shiftWindow(
              _req.shift,
              timeIn: result['coverWindowTimeIn']?.toString(),
              timeOut: result['coverWindowTimeOut']?.toString(),
            ) ??
            _postWindow;
      } else {
        _loadError = result['error']?.toString() ?? 'Failed to load';
      }
    });
  }

  // A candidate's display name, or null when that id is not on the
  // current shortlist. The panel refuses to name anybody this cannot
  // resolve — the backend already discards a review that recommends
  // somebody it was not shown, and this is the same guarantee held on
  // the screen, where the list may have been reloaded since.
  String? _nameForCandidate(String id) {
    for (final c in _candidates) {
      if (c.employee.id == id) return c.employee.name;
    }
    return null;
  }

  // Lands the AI review whenever it arrives, which may be well after the
  // list. A null answer is the ordinary "nothing to add" and clears the
  // spinner without putting anything in its place.
  Future<void> _awaitReview(Future<AiReview?> pending) async {
    final review = await pending;
    if (!mounted) return;
    setState(() {
      _aiReview = review;
      _aiLoading = false;
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
    // The window can shut while this screen sits open — nothing here
    // ticks, so re-check it on the way in rather than sending a doomed
    // request the backend will refuse anyway.
    if (_isWindowClosed) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('The ${_req.shift} post on ${_req.date} has timed '
              'out — a replacement can no longer be assigned.'),
          backgroundColor: const Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Read at the last possible moment, so the hours in the dialog are
    // the ones the backend is about to compute rather than the ones that
    // applied when the screen was drawn.
    final prep = _prep;
    final retimed = prep != null && prep.adjusted;

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
          'on ${_req.date}?\n\n'
          '${retimed ? 'The post runs ${prep.originalRange} and has already '
              'started, so ${candidate.employee.name} is scheduled '
              '${prep.range} — ${prep.noticeLabel} to get ready and travel, '
              'then an hour of extension. They will be told to be at '
              '${_req.station} by ${prep.reportBy}.\n\n' : ''}'
          'The schedule will be updated and '
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

    // The hours quoted back are the backend's, not the preview's — it
    // computed them at the instant it committed them, and that is the
    // pair now on the schedule.
    final applied = result['replacement'] is Map
        ? AppliedReplacement.fromJson(
            Map<String, dynamic>.from(result['replacement'] as Map))
        : null;
    final hours = (applied?.isPrepAdjusted ?? false)
        ? ', ${applied!.window!.range}'
        : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_req.isApprovalFlow
            ? 'Absence approved — ${candidate.employee.name} now covers '
                '${_req.absentName}\'s post$hours.'
            : 'Schedule updated — ${candidate.employee.name} now covers '
                '${_req.absentName}\'s post$hours.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _goBack();
  }

  // Approves the absence request with no cover attached — the only
  // decision left once the post has timed out. Same call the Notifications
  // tab makes for a request with nothing to cover, offered from here
  // because this is where the admin finds out there's nothing to assign.
  Future<void> _approveWithoutCover() async {
    final absenceId = _req.absenceRequestId;
    if (absenceId == null) return;

    final noteController = TextEditingController();
    bool confirmed = false;
    String note = '';
    try {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Approve without a cover?'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_req.absentName}\'s absence on ${_req.date} will be '
                      'marked approved. The ${_req.shift} post at '
                      '${_req.station} stays uncovered on the record, '
                      'because that shift has already ended.',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[700], height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Note to the employee (optional)',
                        labelStyle:
                            TextStyle(fontSize: 13, color: Colors.grey[600]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Approve'),
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

    setState(() => _isApplying = true);
    final result = await ApiService.decideAbsenceRequest(
      id: absenceId,
      status: 'approved',
      adminNote: note,
    );
    if (!mounted) return;
    setState(() => _isApplying = false);

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ??
              'Could not save the decision.'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Absence approved — ${_req.absentName} has been '
            'notified. No cover was assigned.'),
        backgroundColor: const Color(0xFF16A34A),
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
                        _isWindowClosed
                            ? 'This duty has already ended'
                            : _req.isApprovalFlow
                                ? 'Assign a cover to approve this absence'
                                : 'Suitable, conflict-free candidates for '
                                    'this post',
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
                        if (!_isWindowClosed && (_prep?.adjusted ?? false)) ...[
                          const SizedBox(height: 12),
                          _buildPrepWindowCard(_prep!),
                        ],
                        const SizedBox(height: 24),

                        if (_loadError != null)
                          _buildErrorBanner()
                        else if (_isWindowClosed)
                          _buildWindowClosedState()
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
                          // Above the list, and only when there is a list
                          // to have an opinion about. On an empty result
                          // the admin needs the empty state, not a
                          // recommendation drawn from nothing.
                          if (_candidates.isNotEmpty)
                            AiReviewPanel(
                              review: _aiReview,
                              isLoading: _aiLoading,
                              topRankedId: _candidates.first.employee.id,
                              nameFor: _nameForCandidate,
                            ),
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

  // Who is absent, where, when — the post that needs covering. Once the
  // duty is over it is drawn in slate rather than red: nothing is
  // outstanding any more, it's a record of what happened.
  Widget _buildAbsenceContextCard() {
    final closed = _isWindowClosed;
    final accent =
        closed ? const Color(0xFF64748B) : Colors.red[500]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: closed ? const Color(0xFFF1F5F9) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: closed ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.person_off_outlined, color: accent, size: 26),
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
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              closed ? 'Shift ended' : 'Needs replacement',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: closed ? const Color(0xFF475569) : Colors.red[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The hours the cover will actually stand, shown BEFORE the admin
  // picks anybody.
  //
  // Without this the screen would quietly do something surprising: the
  // admin assigns a guard to an 0500H - 1700H post and the schedule
  // comes back saying 1000H - 1900H. The reason is good — nobody walks
  // out of their house straight onto a post — but it has to be visible
  // at the moment of the decision, not discovered afterwards in the
  // report. Only drawn when the hour actually moves something; a cover
  // assigned days ahead has nothing to explain.
  Widget _buildPrepWindowCard(PrepAdjustment prep) {
    const accent = Color(0xFF0E7490); // teal — informative, not alarming
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFEFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA5F3FC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.timer_outlined, color: accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This cover will be scheduled ${prep.range}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF155E75),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'The post itself runs ${prep.originalRange}, which has '
                  'already started. Whoever you assign gets '
                  '${prep.noticeLabel} to get into uniform, sort out food '
                  'and travel — they are expected at ${_req.station} by '
                  '${prep.reportBy} — and their duty is extended an hour '
                  'at the far end to make up for the late start.',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF155E75), height: 1.45),
                ),
              ],
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

  // Shown instead of the candidate list once the post has timed out.
  // There is no "retry" here and no way back into the list — the duty is
  // over, and the only honest thing left is to say so and point the admin
  // at what they CAN still do.
  Widget _buildWindowClosedState() {
    final end = _windowEndsAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF94A3B8).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_toggle_off_rounded,
                size: 34, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          const Text(
            'This duty has already ended',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The ${_req.shift} post at ${_req.station} on ${_req.date} '
            '${end == null ? 'is over' : CoverWindow.closedLabel(end)}. '
            'A replacement is somebody sent to stand the post, so there is '
            'no longer anyone to send — ${_req.absentName}\'s absence stays '
            'on the record as it happened.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
          ),
          if (_req.isApprovalFlow) ...[
            const SizedBox(height: 10),
            Text(
              'The request itself still needs an answer. Approving it now '
              'excuses the absence without a cover — which is all that is '
              'left to decide once the shift is finished.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey[600], height: 1.5),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isApplying ? null : _goBack,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(
                    _req.isApprovalFlow ? 'Back to the request' : 'Back'),
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
              // Without this the approval flow dead-ends: the admin was
              // sent here to find a cover, there is no cover to find, and
              // going back only offers the same button again.
              if (_req.isApprovalFlow)
                ElevatedButton.icon(
                  onPressed: _isApplying ? null : _approveWithoutCover,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve without a cover'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
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
