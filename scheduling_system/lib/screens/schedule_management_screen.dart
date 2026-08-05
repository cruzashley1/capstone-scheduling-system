// screens/schedule_management_screen.dart
import 'package:flutter/material.dart';
import '../data/dummy_data.dart';
import '../models/schedule.dart';
import '../services/api_service.dart';
import '../widgets/station_icon.dart';
import 'main_layout.dart';

// How a finished publish/delete went, which picks the result dialog's
// icon and colour.
enum _ResultKind { success, warning, failure }

class ScheduleManagementContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const ScheduleManagementContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<ScheduleManagementContent> createState() => _ScheduleManagementContentState();
}

class _ScheduleManagementContentState extends State<ScheduleManagementContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Real schedules loaded from the backend (created by Generate Schedule).
  // Falls back to the dummy list if the server is down.
  List<Schedule> _schedules = [];
  bool _isLoading = true;
  bool _usingDummyData = false;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedules() async {
    final result = await ApiService.fetchSchedules();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _schedules = (result['schedules'] as List).cast<Schedule>();
        _usingDummyData = false;
      } else {
        _schedules = List.of(DummyData.schedules);
        _usingDummyData = true;
      }
    });
  }

  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _formatRange(DateTime start, DateTime end) =>
      '${_formatDate(start)} \u2013 ${_formatDate(end)}';

  // Filter schedules by station name, same pattern as Station Management
  List<Schedule> get _filteredSchedules {
    if (_searchQuery.isEmpty) return _schedules;
    return _schedules
        .where((s) => s.stationName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  // --- Progress + result feedback ---

  // Runs a backend call behind a blocking spinner so publishing and
  // deleting never look like nothing happened: the screen is locked for
  // the round trip (which also re-fetches the list) instead of sitting
  // unchanged until the data quietly swaps. Returns null if this screen
  // was disposed mid-flight.
  Future<T?> _withProgress<T>(String message, Future<T> Function() task) async {
    if (!mounted) return null;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 18),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      return await task();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // The confirmation the admin actually reads. A snackbar at the bottom
  // of a full-width desktop window is easy to miss on an action this
  // consequential, so the outcome gets dismissed deliberately.
  Future<void> _showResultDialog({
    required _ResultKind kind,
    required String title,
    required String message,
  }) {
    const icons = {
      _ResultKind.success: Icons.check_circle_outline,
      _ResultKind.warning: Icons.warning_amber_rounded,
      _ResultKind.failure: Icons.error_outline,
    };
    const colors = {
      _ResultKind.success: Color(0xFF059669),
      _ResultKind.warning: Color(0xFFD97706),
      _ResultKind.failure: Color(0xFFDC2626),
    };

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(icons[kind], color: colors[kind], size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Text(
            message,
            style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1034A6),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _publishAll() async {
    // Server is the source of truth; only flip locally once it confirms
    // (or when running offline against dummy data).
    if (!_usingDummyData) {
      // The server refuses schedules that still contain Undefined posts
      // or no guards at all, so re-fetch instead of flipping everything
      // locally — both the call and the re-fetch sit behind the spinner.
      final result = await _withProgress<Map<String, dynamic>>(
        'Publishing schedules…',
        () async {
          final r = await ApiService.publishAllSchedules();
          if (r['success'] == true) await _loadSchedules();
          return r;
        },
      );
      if (result == null || !mounted) return;

      if (result['success'] != true) {
        await _showResultDialog(
          kind: _ResultKind.failure,
          title: 'Publish Failed',
          message: 'No schedule was published.\n\n${result['error']}',
        );
        return;
      }

      // Name the stations that were held back so the count is never
      // abstract and the admin knows what to fix.
      final publishedCount = result['published'] ?? 0;
      final skipped =
          (result['skippedUndefined'] as List?)?.cast<String>() ?? [];
      final skippedEmpty =
          (result['skippedEmpty'] as List?)?.cast<String>() ?? [];
      final problems = <String>[
        if (skipped.isNotEmpty)
          '${skipped.join(', ')} still have Undefined posts — open each '
              'schedule to assign them.',
        if (skippedEmpty.isNotEmpty)
          '${skippedEmpty.join(', ')} have no guards assigned — check the '
              'generation notes and re-generate.',
      ];

      await _showResultDialog(
        kind: problems.isEmpty ? _ResultKind.success : _ResultKind.warning,
        title: problems.isEmpty
            ? 'Schedules Published'
            : 'Published with Exceptions',
        message: problems.isEmpty
            ? '$publishedCount schedule(s) published. The guards on them '
                'have been notified and the rosters now show on each '
                'station\'s page.'
            : '$publishedCount schedule(s) published. These were held '
                'back:\n\n• ${problems.join('\n\n• ')}',
      );
      return;
    }

    setState(() {
      _schedules = _schedules
          .map((s) => s.status == ScheduleStatus.unpublished
              ? s.copyWith(status: ScheduleStatus.published)
              : s)
          .toList();
    });

    await _showResultDialog(
      kind: _ResultKind.success,
      title: 'Schedules Published',
      message: 'All schedules published. These are sample schedules — the '
          'server was unreachable, so nothing was saved.',
    );
  }

  // --- Bulk delete ---

  // The schedules a bulk-delete scope covers. Deliberately ignores the
  // search box: the server deletes by status, so the menu has to mean
  // the same thing the button does.
  List<Schedule> _schedulesInScope(String scope) {
    if (scope == 'unpublished') {
      return _schedules
          .where((s) => s.status == ScheduleStatus.unpublished)
          .toList();
    }
    if (scope == 'published') {
      return _schedules
          .where((s) => s.status == ScheduleStatus.published)
          .toList();
    }
    return List.of(_schedules);
  }

  Widget _buildDeleteMenu() {
    final unpublishedCount = _schedulesInScope('unpublished').length;
    final publishedCount = _schedulesInScope('published').length;
    final totalCount = _schedules.length;
    final enabled = totalCount > 0;

    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Delete schedules in bulk',
      position: PopupMenuPosition.under,
      onSelected: _bulkDelete,
      itemBuilder: (context) => [
        _buildDeleteMenuItem(
          value: 'unpublished',
          label: 'Delete Unpublished',
          count: unpublishedCount,
        ),
        _buildDeleteMenuItem(
          value: 'published',
          label: 'Delete Published',
          count: publishedCount,
        ),
        const PopupMenuDivider(),
        _buildDeleteMenuItem(
          value: 'all',
          label: 'Delete All Schedules',
          count: totalCount,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? Colors.red[300]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 18,
              color: enabled ? Colors.red[400] : Colors.grey[400],
            ),
            const SizedBox(width: 8),
            Text(
              'Delete',
              style: TextStyle(
                color: enabled ? Colors.red[400] : Colors.grey[400],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: enabled ? Colors.red[400] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  // A scope with nothing in it stays visible but disabled, so the admin
  // can see at a glance that there's nothing of that kind to delete.
  PopupMenuItem<String> _buildDeleteMenuItem({
    required String value,
    required String label,
    required int count,
  }) {
    final enabled = count > 0;
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(
            Icons.delete_outline,
            size: 18,
            color: enabled ? Colors.red[400] : Colors.grey[400],
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: enabled ? const Color(0xFF1E293B) : Colors.grey[400],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (enabled ? Colors.red[400]! : Colors.grey[400]!)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: enabled ? Colors.red[400] : Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Warns first — spelling out exactly what is about to disappear —
  // then deletes on the backend (real data) or locally (dummy/offline).
  Future<void> _bulkDelete(String scope) async {
    final targets = _schedulesInScope(scope);
    if (targets.isEmpty) return;

    const titles = {
      'unpublished': 'Delete All Unpublished Schedules',
      'published': 'Delete All Published Schedules',
      'all': 'Delete All Schedules',
    };
    const warnings = {
      'unpublished':
          'Every unpublished draft will be permanently deleted, along with '
              'the post names, added guards and day-off changes made to them. '
              'Re-generating brings back the drafts, but not those edits.',
      'published':
          'Every published schedule will be permanently deleted and will '
              'disappear from the guards\' app. They were already told to '
              'report for these shifts, so each of them gets an urgent '
              '"Schedule Withdrawn" alert.',
      'all':
          'Every schedule will be permanently deleted — unpublished drafts '
              'and published schedules alike. Guards are left with no '
              'schedule at all until new ones are generated and published, '
              'and everyone on a published schedule gets an urgent '
              '"Schedule Withdrawn" alert.',
    };

    final confirmed = await _confirmBulkDelete(
      title: titles[scope]!,
      warning: warnings[scope]!,
      targets: targets,
    );
    if (confirmed != true || !mounted) return;

    if (!_usingDummyData) {
      // Re-fetch rather than trusting the local list — another admin may
      // have added or published something since this page loaded.
      final result = await _withProgress<Map<String, dynamic>>(
        'Deleting schedules…',
        () async {
          final r = await ApiService.deleteSchedules(scope);
          if (r['success'] == true) await _loadSchedules();
          return r;
        },
      );
      if (result == null || !mounted) return;

      if (result['success'] != true) {
        await _showResultDialog(
          kind: _ResultKind.failure,
          title: 'Delete Failed',
          message: 'Nothing was deleted.\n\n${result['error']}',
        );
        return;
      }

      final deleted = result['deleted'] ?? targets.length;
      final notified = result['notified'] ?? 0;
      await _showResultDialog(
        kind: _ResultKind.success,
        title: 'Schedules Deleted',
        message: '$deleted schedule(s) permanently deleted.'
            '${notified > 0 ? '\n\n$notified guard(s) were alerted that '
                'their schedule was withdrawn.' : ''}',
      );
      return;
    }

    setState(() => _schedules.removeWhere(targets.contains));
    await _showResultDialog(
      kind: _ResultKind.success,
      title: 'Schedules Deleted',
      message: '${targets.length} schedule(s) removed from this list. These '
          'are sample schedules — the server was unreachable, so nothing '
          'was deleted on the server.',
    );
  }

  // Tells the admin that deleting a published schedule isn't silent —
  // every guard on it gets an urgent 'Schedule Withdrawn' alert. Shown
  // in both the single-card and bulk confirmations.
  Widget _buildNotifyNotice(int guards) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_outlined,
              size: 18, color: Color(0xFF1034A6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$guards guard${guards == 1 ? '' : 's'} will be alerted that '
              'their schedule has been withdrawn, so nobody reports for a '
              'shift that no longer exists.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
            ),
          ),
        ],
      ),
    );
  }

  // Shared warning dialog for the three bulk-delete scopes. Lists the
  // stations that are about to go so the count is never abstract, and
  // makes Cancel the easy default.
  Future<bool?> _confirmBulkDelete({
    required String title,
    required String warning,
    required List<Schedule> targets,
  }) {
    final names = targets.map((s) => s.stationName).toList()..sort();
    final preview = names.take(6).join(', ') +
        (names.length > 6 ? ' and ${names.length - 6} more' : '');
    // Only published schedules ever reached the guards, so only those
    // trigger a withdrawal alert.
    final notified = targets
        .where((s) => s.status == ScheduleStatus.published)
        .fold<int>(0, (sum, s) => sum + s.totalEmployees);

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This cannot be undone.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      warning,
                      style: TextStyle(fontSize: 13, color: Colors.red[900]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${targets.length} schedule${targets.length == 1 ? '' : 's'} '
                'will be deleted:',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                preview,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (notified > 0) ...[
                const SizedBox(height: 12),
                _buildNotifyNotice(notified),
              ],
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Note: this ignores your search — every matching schedule '
                  'is deleted, not just the ones shown.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('Delete ${targets.length}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSchedules;
    final unpublished =
    filtered.where((s) => s.status == ScheduleStatus.unpublished).toList();
    final published =
    filtered.where((s) => s.status == ScheduleStatus.published).toList();
    final hasUnpublished =
    _schedules.any((s) => s.status == ScheduleStatus.unpublished);

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header - back button, title, search bar, Publish All
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
                  onPressed: () => widget.onNavigate(ScreenType.dashboard),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Schedule Management',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Review unpublished schedules and manage published ones',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Search Bar
                Container(
                  width: 280,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search schedules...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[500], size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Publish All — bulk-publishes every unpublished schedule
                ElevatedButton.icon(
                  onPressed: hasUnpublished ? _publishAll : null,
                  icon: const Icon(Icons.publish, size: 18),
                  label: const Text('Publish All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1034A6),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[500],
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Bulk delete — the three scopes live behind one menu so
                // the destructive actions stay out of the way of the
                // everyday Publish All button.
                _buildDeleteMenu(),
              ],
            ),
          ),

          // Search results count
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtered.length} result${filtered.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_usingDummyData) ...[
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
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber,
                              size: 18, color: Color(0xFFD97706)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Could not reach the server — showing sample schedules.',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (unpublished.isNotEmpty) ...[
                    _buildSectionHeader(
                      'Unpublished Schedules',
                      unpublished.length,
                      const Color(0xFFD97706),
                      Icons.edit_calendar_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildScheduleGrid(unpublished),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionHeader(
                    'Published Schedules',
                    published.length,
                    const Color(0xFF059669),
                    Icons.check_circle_outline,
                  ),
                  const SizedBox(height: 16),
                  if (published.isEmpty)
                    _buildEmptyState()
                  else
                    _buildScheduleGrid(published),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // 2 columns instead of the Station grid's 3 — each tile here carries more
  // info (period, staffing, actions), so the extra width keeps it readable.
  Widget _buildScheduleGrid(List<Schedule> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 20.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map((s) => SizedBox(
            width: cardWidth,
            child: _buildScheduleCard(s),
          ))
              .toList(),
        );
      },
    );
  }

  // YOUR STATION CARD PATTERN, adapted: icon + status badge on top,
  // station name, created date, staffing details box, then edit/delete actions.
  Widget _buildScheduleCard(Schedule schedule) {
    final isPublished = schedule.status == ScheduleStatus.published;
    final statusColor = isPublished ? const Color(0xFF059669) : const Color(0xFFD97706);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onNavigate(ScreenType.scheduleDetail, data: schedule),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isPublished ? Colors.transparent : statusColor.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const StationIcon(size: 46),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration:
                            BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPublished ? 'Published' : 'Unpublished',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Station name on top, created date right below it
                Text(
                  schedule.stationName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Created ${_formatDate(schedule.createdAt)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),

                // Staffing / employee details
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.date_range, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formatRange(schedule.startDate, schedule.endDate),
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.people, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            '${schedule.totalAssignments} shifts \u00b7 ${schedule.totalDays} days',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Rostering happens in Schedule Detail now: opening a
                // schedule and editing the row is the only path that can
                // see the whole roster, so it's the only one that can tell
                // whether a guard is free and whether their role fits the
                // post. Adding from this card could do neither.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _deleteSchedule(schedule),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[400],
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

  Widget _buildEmptyState() {
    final isSearching = _searchQuery.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.event_busy,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? 'No schedules found' : 'No published schedules yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          if (!isSearching) ...[
            const SizedBox(height: 4),
            Text(
              'Create one from Generate Schedule to see it here.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  // Confirms, then deletes the schedule on the backend (real data) or
  // just locally (dummy/offline data) and removes its card.
  Future<void> _deleteSchedule(Schedule schedule) async {
    final notified = schedule.status == ScheduleStatus.published
        ? schedule.totalEmployees
        : 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Schedule'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete the ${schedule.stationName} schedule '
                '(${_formatRange(schedule.startDate, schedule.endDate)})? '
                'This cannot be undone.',
              ),
              if (notified > 0) ...[
                const SizedBox(height: 16),
                _buildNotifyNotice(notified),
              ],
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
              backgroundColor: Colors.red[400],
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (!_usingDummyData && schedule.id.isNotEmpty) {
      final result = await _withProgress<Map<String, dynamic>>(
        'Deleting ${schedule.stationName} schedule…',
        () => ApiService.deleteSchedule(schedule.id),
      );
      if (result == null || !mounted) return;
      if (result['success'] != true) {
        await _showResultDialog(
          kind: _ResultKind.failure,
          title: 'Delete Failed',
          message: 'The ${schedule.stationName} schedule was not deleted.'
              '\n\n${result['error']}',
        );
        return;
      }
    }

    setState(() => _schedules.remove(schedule));
    await _showResultDialog(
      kind: _ResultKind.success,
      title: 'Schedule Deleted',
      message: 'The ${schedule.stationName} schedule '
          '(${_formatRange(schedule.startDate, schedule.endDate)}) has been '
          'permanently deleted.'
          '${notified > 0 ? '\n\n$notified guard(s) were alerted that their '
              'schedule was withdrawn.' : ''}',
    );
  }
}