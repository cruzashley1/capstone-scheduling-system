// screens/station_management_screen.dart (Now backed by the real API)
import 'package:flutter/material.dart';
import '../models/schedule.dart';
import '../models/special_assignment.dart';
import '../models/station.dart';
import '../services/api_service.dart';
import '../widgets/station_icon.dart';
import 'main_layout.dart';
import 'add_station_dialog.dart';
import 'employee_list_screen.dart' show VerticalDividerWidget;
import 'special_assignment_dialog.dart';

// How long a row takes to settle into (and out of) its hover state.
// Short: a colour cross-fade wants to feel instant. Any slower and
// sweeping the pointer down the table leaves a trail of rows still
// catching up, which is exactly the restlessness this avoids.
const Duration _kHoverDuration = Duration(milliseconds: 120);

// Every row is this tall. Fixed rather than intrinsic so the table scans
// as straight, even bands of text.
const double _kRowHeight = 48;

const Color _kBrandBlue = Color(0xFF1034A6);

// The hovered row's background — slate-100, the same neutral this app
// already fills its search bars with. Deliberately NOT a tinted blue:
// blue at low opacity over white goes muddy against the grey dividers.
// A step lighter (#F8FAFC, the page background) disappears on the white
// card, so this is the quietest wash that can still actually be seen.
const Color _kHoverWash = Color(0xFFF1F5F9);

// The Morning/Afternoon/Night columns are the station's REQUIRED
// headcount, which is easy to misread as today's count with the
// "Staffed Today" column sitting right beside them. The tooltip is what
// keeps the three abbreviated headings honest.
const String _kShiftHeaderTooltip = 'Guards required per shift';

/// The table's single column definition.
///
/// The header and every data row are built through this one function, so
/// the columns physically cannot drift out of alignment: changing a flex
/// here moves the header and the body together.
///
/// The three shift columns deliberately sit inside one pair of dividers.
/// They belong to a single idea — guards required per shift — but still
/// line up as separate columns you can read straight down.
List<Widget> _tableRowChildren({
  required Widget station,
  required Widget morning,
  required Widget afternoon,
  required Widget night,
  required Widget staffed,
  required Widget status,
  required Widget pinned,
  required Widget actions,
}) {
  return [
    Expanded(flex: 4, child: station),
    const VerticalDividerWidget(),
    // Flex 2 rather than 1, and all three equal: the numbers underneath
    // are single digits and would fit in half this, but "AFTERNOON" is
    // the longest heading in the table and gets clipped at flex 1. The
    // headings set the width; the three stay equal so the digits still
    // line up in an even row.
    Expanded(flex: 2, child: morning),
    Expanded(flex: 2, child: afternoon),
    Expanded(flex: 2, child: night),
    const VerticalDividerWidget(),
    Expanded(flex: 2, child: staffed),
    const VerticalDividerWidget(),
    Expanded(flex: 3, child: status),
    const VerticalDividerWidget(),
    Expanded(child: pinned),
    const VerticalDividerWidget(),
    Expanded(child: actions),
  ];
}

class StationManagementContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const StationManagementContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<StationManagementContent> createState() => _StationManagementContentState();
}

class _StationManagementContentState extends State<StationManagementContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Station> _stations = [];
  List<Schedule> _schedules = [];

  // Admin pins for the current rotation cycle (this calendar month),
  // used to badge each card with how many guards are pinned to it.
  List<SpecialAssignment> _specialAssignments = [];

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Loads every station plus every schedule from Firestore via the
  // Python backend. Schedules are needed so each card can show how many
  // guards the published schedule actually assigns to that station.
  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.fetchStations(),
      ApiService.fetchSchedules(),
      ApiService.fetchSpecialAssignments(cycleIdFor(DateTime.now())),
    ]);

    if (!mounted) return;

    final stationResult = results[0];
    final scheduleResult = results[1];
    final pinResult = results[2];

    if (stationResult["success"] == true) {
      setState(() {
        _stations = stationResult["stations"] as List<Station>;
        // Schedules or pins failing to load shouldn't block the station
        // grid — the counts just fall back to 0 until the next refresh.
        _schedules = scheduleResult["success"] == true
            ? scheduleResult["schedules"] as List<Schedule>
            : [];
        _specialAssignments = pinResult["success"] == true
            ? pinResult["specialAssignments"] as List<SpecialAssignment>
            : [];
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = stationResult["error"].toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openEditStationDialog(Station station) async {
    final updated = await showDialog<Station>(
      context: context,
      builder: (context) => AddStationDialog(station: station),
    );

    if (updated != null) {
      setState(() {
        _stations = _stations
            .map((s) => s.id == updated.id ? updated : s)
            .toList();
      });
    }
  }

  // Guards pinned to this station for the current cycle (the badge on
  // the card). The dialog itself can also manage next month's pins.
  int _pinnedCount(Station station) =>
      _specialAssignments.where((p) => p.stationId == station.id).length;

  Future<void> _openSpecialAssignmentsDialog(Station station) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SpecialAssignmentDialog(station: station),
    );

    if (result == null || !mounted) return;

    // If the save touched the current cycle, refresh the badges. A save
    // for next month changes nothing visible on this screen yet.
    if (result['cycleId'] == cycleIdFor(DateTime.now())) {
      final pinResult =
          await ApiService.fetchSpecialAssignments(cycleIdFor(DateTime.now()));
      if (!mounted) return;
      if (pinResult['success'] == true) {
        setState(() {
          _specialAssignments =
              pinResult['specialAssignments'] as List<SpecialAssignment>;
        });
      }
    }

    final notes = (result['notes'] as List<String>? ?? []);
    final saved = result['specialAssignments'] as List? ?? [];
    final cycleId = result['cycleId'] as String? ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notes.isNotEmpty
              ? notes.join('\n')
              : '${saved.length} special assignment'
                  '${saved.length != 1 ? 's' : ''} saved for '
                  '"${station.name}" — ${cycleRangeLabel(cycleId)}. '
                  'They take a post here in every schedule generated for '
                  '${cycleLabel(cycleId)}.',
        ),
      ),
    );
  }

  // How many distinct guards the station's active published schedule puts
  // on duty today. Prefers the published schedule covering today; if none
  // does (e.g. it starts next week), falls back to the most recently
  // created published one and counts its first day instead.
  int _getEmployeeCount(Station station) {
    final published = _schedules
        .where((s) =>
            s.status == ScheduleStatus.published && s.stationId == station.id)
        .toList();
    if (published.isEmpty) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Schedule schedule = published.firstWhere(
      (s) => !today.isBefore(s.startDate) && !today.isAfter(s.endDate),
      orElse: () => published.reduce(
          (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b),
    );

    if (schedule.days.isEmpty) return 0;

    final day = schedule.days.firstWhere(
      (d) =>
          d.date.year == today.year &&
          d.date.month == today.month &&
          d.date.day == today.day,
      orElse: () => schedule.days.first,
    );

    return day.entries.map((e) => e.employeeId).toSet().length;
  }

  List<Station> get _filteredStations {
    if (_searchQuery.isEmpty) return _stations;

    return _stations.where((station) {
      return station.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

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
                  onPressed: () => widget.onNavigate(ScreenType.dashboard),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Station Management',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Monitor and manage station assignments',
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
                      hintText: 'Search stations...',
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search results count
          if (_searchQuery.isNotEmpty && !_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filteredStations.length} result${_filteredStations.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load stations',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredStations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _searchQuery.isEmpty
                ? const StationIcon(size: 48)
                : Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No stations yet' : 'No stations found',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // So the tinted header and the hover accent bars stay inside the
      // card's rounded corners instead of squaring them off.
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildTableHeader(),
          Expanded(
            child: ListView.separated(
              itemCount: _filteredStations.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey[200],
              ),
              itemBuilder: (context, index) {
                final station = _filteredStations[index];
                return _StationTableRow(
                  station: station,
                  employeeCount: _getEmployeeCount(station),
                  pinnedCount: _pinnedCount(station),
                  onTap: () => widget.onNavigate(
                    ScreenType.stationDetail,
                    data: station,
                  ),
                  onEdit: () => _openEditStationDialog(station),
                  onSpecialAssignments: () =>
                      _openSpecialAssignmentsDialog(station),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kBrandBlue.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: _tableRowChildren(
          station: const _HeaderCell('STATION', align: TextAlign.left),
          // The three shift numbers are the station's REQUIRED headcount,
          // not today's count — the tooltip is what tells them apart from
          // the "Staffed Today" column sitting right next to them.
          morning: const _HeaderCell('MORNING', tooltip: _kShiftHeaderTooltip),
          afternoon:
              const _HeaderCell('AFTERNOON', tooltip: _kShiftHeaderTooltip),
          night: const _HeaderCell('NIGHT', tooltip: _kShiftHeaderTooltip),
          staffed: const _HeaderCell(
            'STAFFED TODAY',
            tooltip: 'Guards the published schedule puts on duty today, '
                'against the station\'s total requirement',
          ),
          status: const _HeaderCell('STATUS'),
          pinned: const _HeaderCell(
            'PINNED',
            tooltip: 'Guards specially assigned here this month',
          ),
          actions: const _HeaderCell(''),
        ),
      ),
    );
  }

}

/// One column heading: small tracked-out caps in the brand blue, the same
/// treatment the Employee List header uses — a size down, because this
/// table carries eight columns where that one carries five.
class _HeaderCell extends StatelessWidget {
  final String label;
  final TextAlign align;
  final String? tooltip;

  const _HeaderCell(
    this.label, {
    this.align = TextAlign.center,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: _kBrandBlue,
        fontSize: 11,
        letterSpacing: 0.4,
      ),
    );

    if (tooltip == null) return text;
    return Tooltip(message: tooltip!, child: text);
  }
}

/// One station, as a row.
///
/// Stateful only to hold [_hovered]: while the pointer is over it the row
/// eases into a blue tint and grows a brand-blue bar down its left edge.
/// The bar lives in a gutter that is always reserved and animates its
/// HEIGHT rather than its width, so hovering never nudges the cells
/// sideways — the columns stay put and only the emphasis moves.
class _StationTableRow extends StatefulWidget {
  final Station station;
  final int employeeCount;
  final int pinnedCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onSpecialAssignments;

  const _StationTableRow({
    required this.station,
    required this.employeeCount,
    required this.pinnedCount,
    required this.onTap,
    required this.onEdit,
    required this.onSpecialAssignments,
  });

  @override
  State<_StationTableRow> createState() => _StationTableRowState();
}

class _StationTableRowState extends State<_StationTableRow> {
  bool _hovered = false;

  bool get _isFullyStaffed =>
      widget.employeeCount >= widget.station.requiredEmployees;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Opaque so the whole band is the navigation target, including
        // the gaps between cells — not just the text inside them.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _kHoverDuration,
          curve: Curves.easeOut,
          height: _kRowHeight,
          // The whole hover effect, right here: a flat wash, nothing more.
          // No bar, no lift, no geometry — so dragging the pointer down a
          // long table stays quiet instead of setting rows twitching.
          color: _hovered ? _kHoverWash : Colors.white,
          // Matches the header's horizontal 16 exactly, which is what
          // keeps the columns under their headings.
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _tableRowChildren(
              station: _buildNameCell(),
              morning: _buildRequiredCell('morning'),
              afternoon: _buildRequiredCell('afternoon'),
              night: _buildRequiredCell('night'),
              staffed: _buildStaffedCell(),
              status: _buildStatusCell(),
              pinned: _buildPinnedCell(),
              actions: _buildActionsCell(),
            ),
          ),
        ),
      ),
    );
  }

  /// The station name, which deepens to the brand blue on hover. It's the
  /// second half of the effect: the wash says "this row", the colour says
  /// "and it opens".
  Widget _buildNameCell() {
    return AnimatedDefaultTextStyle(
      duration: _kHoverDuration,
      curve: Curves.easeOut,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _hovered ? _kBrandBlue : const Color(0xFF1E293B),
      ),
      child: Text(
        widget.station.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// The station's required headcount for one shift. A station saved
  /// before the per-shift breakdown existed has nothing to report here,
  /// so it gets a dash rather than a 0 that would read as "nobody needed".
  Widget _buildRequiredCell(String shift) {
    if (!widget.station.hasShiftBreakdown) return _buildEmptyCell();

    return Text(
      '${widget.station.requiredFor(shift)}',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
      ),
    );
  }

  /// Today's count against the requirement. The current number carries
  /// the colour — red the moment it falls short — because it's the one
  /// figure an admin scans this column for.
  Widget _buildStaffedCell() {
    return RichText(
      textAlign: TextAlign.center,
      // Rows are a fixed height, so this must never wrap to a second line
      // when the window gets narrow.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 13),
        children: [
          TextSpan(
            text: '${widget.employeeCount}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _isFullyStaffed
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFDC2626),
            ),
          ),
          TextSpan(
            text: ' / ${widget.station.requiredEmployees}',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCell() {
    final color = _isFullyStaffed ? Colors.green : Colors.red;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _isFullyStaffed ? 'Fully Staffed' : 'Attention Needed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How many guards are specially assigned here this month. Tapping the
  /// chip opens the dialog directly, same as it did on the card.
  Widget _buildPinnedCell() {
    if (widget.pinnedCount == 0) return _buildEmptyCell();

    return Center(
      child: Tooltip(
        message: '${widget.pinnedCount} specially assigned this month '
            '— click to manage',
        // Transparent Material so the chip's ripple paints ABOVE the
        // row's own background instead of being hidden behind it.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onSpecialAssignments,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kBrandBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBrandBlue.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.push_pin, size: 13, color: _kBrandBlue),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.pinnedCount}',
                    style: const TextStyle(
                      color: _kBrandBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsCell() {
    return Center(
      child: PopupMenuButton<String>(
        tooltip: 'Station options',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
        onSelected: (value) {
          if (value == 'edit') {
            widget.onEdit();
          } else if (value == 'special') {
            widget.onSpecialAssignments();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(width: 8),
                Text('Edit Station'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'special',
            child: Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 18),
                SizedBox(width: 8),
                Text('Special Assignments'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCell() {
    return Text(
      '—',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.grey[400], fontSize: 13),
    );
  }
}
