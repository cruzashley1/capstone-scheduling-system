import 'dart:async';
import 'package:flutter/material.dart';
import '../models/schedule.dart';
import '../models/schedule_approval.dart';
import '../services/api_service.dart';
import '../services/profile_settings.dart';
import 'schedule_detail_screen.dart';
import '../widgets/controller_dialog.dart';

const _blue = Color(0xFF1034A6);

class ApprovalScreen extends StatefulWidget {
  final String role;
  final String? initialPeriod;
  const ApprovalScreen({super.key, required this.role, this.initialPeriod});
  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  List<ScheduleApproval> _records = [];
  List<Schedule> _schedules = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _period;
  String _filter = 'All';
  Timer? _timer;
  bool get _admin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ApiService.workflow('/schedule-approvals'),
      if (_admin) ApiService.fetchSchedules(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = results[0]['success'] == true
          ? null
          : results[0]['error'].toString();
      if (_error == null) {
        _records = approvalMaps(
          results[0]['approvals'],
        ).map(ScheduleApproval.new).toList();
      }
      if (_admin && results[1]['success'] == true) {
        _schedules = (results[1]['schedules'] as List).cast<Schedule>();
        final keys = _periods.keys.toList()..sort((a, b) => b.compareTo(a));
        if (!keys.contains(_period)) _period = keys.firstOrNull;
      } else if (_admin) {
        _error = results[1]['error'].toString();
      }
    });
  }

  Map<String, List<Schedule>> get _periods {
    final periods = <String, List<Schedule>>{};
    for (final s in _schedules) {
      final key =
          '${s.startDate.toIso8601String().substring(0, 10)}|${s.endDate.toIso8601String().substring(0, 10)}';
      periods.putIfAbsent(key, () => []).add(s);
    }
    return periods;
  }

  Future<void> _submit() async {
    if (_period == null || _busy) return;
    final dates = _period!.split('|');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit the entire period?'),
        content: Text(
          '${dates[0]} – ${dates[1]}\n\nAll active stations must have complete schedules for these exact dates. The rosters will be locked during review. Assistant Security approves first, followed by Area Commander. Final approval publishes the entire period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit for Approval'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ApiService.workflow(
      '/schedule-approvals/submit',
      method: 'POST',
      body: {
        'startDate': dates[0],
        'endDate': dates[1],
        'preparedBy': ProfileSettings.preparedBy,
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _message(
      result['success'] == true
          ? 'Period submitted to Assistant Security.'
          : result['error'].toString(),
    );
    await _load();
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(ScheduleApproval record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApprovalReviewScreen(id: record.id, role: widget.role),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _records
        .where(
          (r) => switch (_filter) {
            'Pending' => r.status.startsWith('pending_'),
            'Approved' => r.status == 'approved',
            'Returned' => r.status == 'returned' || r.status == 'withdrawn',
            _ => true,
          },
        )
        .toList();
    final selected = _period?.split('|');
    final locked =
        selected != null &&
        _records.any(
          (r) => r.start == selected[0] && r.end == selected[1] && r.locked,
        );
    return ColoredBox(
      color: const Color(0xFFF5F7FB),
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Period Approvals',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'All stations · Assistant Security → Area Commander → Published',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in {
                'Pending': _records
                    .where((r) => r.status.startsWith('pending_'))
                    .length,
                'Approved': _records
                    .where((r) => r.status == 'approved')
                    .length,
                'Returned': _records
                    .where(
                      (r) => r.status == 'returned' || r.status == 'withdrawn',
                    )
                    .length,
              }.entries)
                SizedBox(
                  width: 185,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: _blue,
                            ),
                          ),
                          Text(entry.key),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_admin) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Submit schedules for review',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 340,
                          child: DropdownButtonFormField<String>(
                            initialValue: _period,
                            key: ValueKey(_period),
                            decoration: const InputDecoration(
                              labelText: 'Schedule period',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                (_periods.keys.toList()
                                      ..sort((a, b) => b.compareTo(a)))
                                    .map(
                                      (key) => DropdownMenuItem(
                                        value: key,
                                        child: Text(
                                          '${key.replaceAll('|', ' – ')} (${_periods[key]!.length} stations)',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _period = value),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed:
                              _busy ||
                                  _loading ||
                                  _error != null ||
                                  _period == null ||
                                  locked
                              ? null
                              : _submit,
                          icon: const Icon(Icons.send_outlined),
                          label: Text(
                            _busy ? 'Submitting…' : 'Submit for Approval',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      locked
                          ? 'This period is already in review or approved. Open its submission below to start a revision.'
                          : 'Generate every active station for the same period before submitting. Returned drafts can be corrected in Schedule Management.',
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            children: [
              for (final label in ['All', 'Pending', 'Approved', 'Returned'])
                ChoiceChip(
                  label: Text(label),
                  selected: _filter == label,
                  onSelected: (_) => setState(() => _filter = label),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (!_loading && visible.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No submissions in this view.'),
            ),
          for (final r in visible)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: Icon(
                  r.status == 'approved'
                      ? Icons.verified_outlined
                      : Icons.fact_check_outlined,
                  color: _blue,
                ),
                title: Text(
                  r.period,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${r.stationCount} stations · Revision ${r.revision}\n${approvalStatusLabel(r.status)}\nSubmitted by ${r.data['submittedName']} · ${approvalTime(r.data['submittedAt'])}',
                  ),
                ),
                trailing: OutlinedButton(
                  onPressed: () => _open(r),
                  child: Text(
                    r.canDecide(widget.role)
                        ? 'Review & Decide'
                        : 'View Details',
                  ),
                ),
                onTap: () => _open(r),
              ),
            ),
        ],
      ),
    );
  }
}

class ApprovalReviewScreen extends StatefulWidget {
  final String id;
  final String role;
  const ApprovalReviewScreen({super.key, required this.id, required this.role});
  @override
  State<ApprovalReviewScreen> createState() => _ApprovalReviewScreenState();
}

class _ApprovalReviewScreenState extends State<ApprovalReviewScreen> {
  ScheduleApproval? _record;
  String? _error;
  bool _busy = false;
  int _station = 0;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ApiService.workflow(
      '/schedule-approvals/${widget.id}',
    );
    if (!mounted) return;
    setState(() {
      _error = result['success'] == true ? null : result['error'].toString();
      if (_error == null) {
        _record = ScheduleApproval(
          Map<String, dynamic>.from(result['approval']),
        );
      }
    });
  }

  Future<void> _decide(String action) async {
    final r = _record!;
    final text = TextEditingController();
    final revise = action == 'revise';
    final needsComment = action != 'approve';
    String? validation;
    final accepted = await showControllerDialog<bool>(
      context: context,
      controllers: [text],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text(
            revise
                ? 'Start a revision?'
                : action == 'return'
                ? 'Return for revision?'
                : 'Approve this entire period?',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.period} · ${r.stationCount} stations\n\n${revise
                      ? 'All schedules in this period will become unpublished. Guards will be notified if the period was published. Both approvals are required after resubmission.'
                      : action == 'approve' && widget.role == 'areaCommander'
                      ? 'Your approval will publish all schedules in this submission and notify the guards.'
                      : action == 'approve'
                      ? 'Your approval will send this submission to Area Commander.'
                      : 'The admin will see your comments and can correct the schedules.'}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: text,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: needsComment
                        ? 'Reason (required)'
                        : 'Comment (optional)',
                    errorText: validation,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (needsComment && text.text.trim().isEmpty) {
                  update(() => validation = 'Enter a reason.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(
                revise
                    ? 'Start Revision'
                    : action == 'return'
                    ? 'Return to Admin'
                    : 'Approve Period',
              ),
            ),
          ],
        ),
      ),
    );
    final comment = text.text.trim();
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ApiService.workflow(
      '/schedule-approvals/${r.id}/${revise ? 'revise' : 'decision'}',
      method: 'POST',
      body: {'action': action, 'comment': comment, 'version': r.version},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'Decision saved.'
              : result['error'].toString(),
        ),
      ),
    );
    await _load();
  }

  Widget _timeline() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      for (final e in _record!.events)
        Card(
          child: ListTile(
            leading: const Icon(Icons.history, color: _blue),
            title: Text(
              '${e['action'].toString().replaceAll('_', ' ')} · ${e['name']} (${officialRoleLabel(e['role'])})',
            ),
            subtitle: Text('${approvalTime(e['at'])}\n${e['comment']}'),
            isThreeLine: true,
          ),
        ),
    ],
  );

  Widget _amendments() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'The submitted rosters remain preserved. These emergency replacements took effect immediately after approval.',
        style: TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 16),
      if (_record!.amendments.isEmpty) const Text('No emergency amendments.'),
      for (final a in _record!.amendments)
        Card(
          child: ExpansionTile(
            title: Text(
              '${a['replacement']['station']} · ${a['replacement']['date']} · ${a['replacement']['shift']}',
            ),
            subtitle: Text(
              '${a['replacement']['absentEmployeeName']} → ${a['replacement']['replacementEmployeeName']}\nBy ${a['name']} · ${approvalTime(a['at'])}\n${a['comment']}',
            ),
            children: [
              for (final key in ['before', 'after'])
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key == 'before'
                            ? 'Before replacement'
                            : 'After replacement',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final day in approvalMaps(a[key]))
                        for (final e in approvalMaps(day['entries']))
                          Text(
                            '${e['employeeName']} · ${e['post']} · ${e['shift']} · ${e['timeIn'] ?? ''}–${e['timeOut'] ?? ''}',
                          ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ],
  );

  void _dailyAssignments(Schedule schedule) {
    var index = 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final day = schedule.days[index];
          final names = <String, String>{
            for (final d in schedule.days)
              for (final e in d.entries) e.employeeId: e.employeeName,
          };
          final working = day.entries.map((e) => e.employeeId).toSet();
          return AlertDialog(
            title: Text('${schedule.stationName} · Daily assignments'),
            content: SizedBox(
              width: 1040,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<int>(
                    value: index,
                    items: [
                      for (var i = 0; i < schedule.days.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            schedule.days[i].date.toIso8601String().substring(
                              0,
                              10,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) => update(() => index = v!),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            for (final label in [
                              'Guard',
                              'Post',
                              'Shift',
                              'Duty time',
                              'Covering for',
                            ])
                              DataColumn(label: Text(label)),
                          ],
                          rows: [
                            for (final e in day.entries)
                              DataRow(
                                cells: [
                                  DataCell(Text(e.employeeName)),
                                  DataCell(Text(e.post ?? 'Undefined')),
                                  DataCell(Text(e.shift)),
                                  DataCell(Text(e.timeRange)),
                                  DataCell(
                                    Text(
                                      names[e.coveringFor] ??
                                          e.coveringFor ??
                                          '—',
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No duty at this station today: ${names.entries.where((e) => !working.contains(e.key)).map((e) => e.value).join(', ')}',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    final schedules = r?.schedules ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          r == null
              ? 'Review submission'
              : '${r.period} · Revision ${r.revision}',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: r == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator(),
            )
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        approvalStatusLabel(r.status),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _blue,
                        ),
                      ),
                      Text(
                        '${r.stationCount} stations · Submitted by ${r.data['submittedName']}',
                      ),
                      if (r.canDecide(widget.role)) ...[
                        OutlinedButton(
                          onPressed: _busy ? null : () => _decide('return'),
                          child: const Text('Return for Revision'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _decide('approve'),
                          icon: const Icon(Icons.check),
                          label: const Text('Approve Entire Period'),
                        ),
                      ],
                      if (widget.role == 'admin' && r.locked)
                        OutlinedButton(
                          onPressed: _busy ? null : () => _decide('revise'),
                          child: const Text('Start Revision'),
                        ),
                      if (widget.role == 'areaCommander' &&
                          r.status == 'pending_assistant')
                        const Text('Assistant Security must approve first.'),
                      if (_busy)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SegmentedButton<int>(
                    segments: [
                      const ButtonSegment(
                        value: 0,
                        label: Text('Submitted Schedules'),
                        icon: Icon(Icons.calendar_month),
                      ),
                      const ButtonSegment(
                        value: 1,
                        label: Text('Decision History'),
                        icon: Icon(Icons.history),
                      ),
                      ButtonSegment(
                        value: 2,
                        label: Text(
                          'Emergency Amendments (${r.amendments.length})',
                        ),
                        icon: const Icon(Icons.swap_horiz),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (v) => setState(() => _tab = v.first),
                  ),
                ),
                Expanded(
                  child: _tab == 1
                      ? _timeline()
                      : _tab == 2
                      ? _amendments()
                      : Row(
                          children: [
                            SizedBox(
                              width: 220,
                              child: ListView(
                                children: [
                                  for (var i = 0; i < schedules.length; i++)
                                    ListTile(
                                      selected: i == _station,
                                      selectedColor: _blue,
                                      title: Text(schedules[i].stationName),
                                      subtitle: Text(
                                        '${schedules[i].totalEmployees} guards · ${schedules[i].notes.length} notes',
                                      ),
                                      onTap: () => setState(() => _station = i),
                                    ),
                                ],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            if (schedules.isNotEmpty)
                              Expanded(
                                child: Column(
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed:
                                            schedules[_station].days.isEmpty
                                            ? null
                                            : () => _dailyAssignments(
                                                schedules[_station],
                                              ),
                                        icon: const Icon(
                                          Icons.view_day_outlined,
                                        ),
                                        label: const Text(
                                          'View Every Day’s Assignments',
                                        ),
                                      ),
                                    ),
                                    if (schedules[_station].notes.isNotEmpty)
                                      ExpansionTile(
                                        title: Text(
                                          'Scheduling notes (${schedules[_station].notes.length})',
                                        ),
                                        children: [
                                          SizedBox(
                                            height: 180,
                                            child: ListView(
                                              children: [
                                                for (final note
                                                    in schedules[_station]
                                                        .notes)
                                                  ListTile(
                                                    title: Text(
                                                      '${note.subject}: ${note.problem}',
                                                    ),
                                                    subtitle: Text(note.fix),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    Expanded(
                                      child: ScheduleDetailScreen(
                                        key: ValueKey(
                                          '${r.id}-$_station-${r.version}',
                                        ),
                                        schedule: schedules[_station],
                                        readOnly: true,
                                        onBack: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ],
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
