// screens/station_detail_screen.dart
// Shows one station's roster pulled from its PUBLISHED schedule: the
// screen fetches every schedule, keeps the published ones for this
// station, and displays the day being covered (today when the period
// includes it, otherwise the schedule's first day). Unpublished
// schedules never show up here — publishing in Schedule Management is
// what makes a roster appear on this screen.
import 'package:flutter/material.dart';
import '../models/station.dart';
import '../models/schedule.dart';
import '../models/special_assignment.dart';
import '../services/api_service.dart';
import 'main_layout.dart';
import 'add_station_dialog.dart';

// Internal row model for the Morning/Afternoon/Night shift tables.
class _ShiftRow {
  final String id;
  final String name;
  final String position;
  final String time;

  // True when this guard is here via a Station Management special
  // assignment (admin pin) rather than normal rotation.
  final bool isSpecial;

  // True when this guard is covering someone's day off as a reliever.
  // Reliever isn't a post — they man the post of the guard they cover —
  // so this is shown by highlighting their ID instead of the Position.
  final bool isReliever;

  const _ShiftRow({
    required this.id,
    required this.name,
    required this.position,
    required this.time,
    this.isSpecial = false,
    this.isReliever = false,
  });
}

// A guard named in the Total Assigned list.
class _Person {
  final String id;
  final String name;

  const _Person(this.id, this.name);
}

// One manned post at this station across the whole published period: the
// regular who owns it, plus any reliever who covers them on their days
// off. This is the unit Total Assigned counts — a regular and their
// reliever are ONE, because the reliever mans that same post when the
// regular is off rather than standing as a second body on the roster.
class _AssignedUnit {
  final _Person regular;
  final List<_Person> relievers;

  // The shift and post the regular holds most often over the period —
  // what decides which section of the list they're filed under.
  final String shift;
  final String post;

  // True when this guard is here on an admin pin for the cycle.
  final bool isSpecial;

  // True when nobody owns this post outright — a reliever whose regular
  // never appears in this station's schedule, so they stand alone.
  final bool isOrphanReliever;

  const _AssignedUnit({
    required this.regular,
    required this.relievers,
    required this.shift,
    required this.post,
    required this.isSpecial,
    required this.isOrphanReliever,
  });
}

class StationDetailContent extends StatefulWidget {
  final Station station;
  final Function(ScreenType, {dynamic data}) onNavigate;

  const StationDetailContent({
    super.key,
    required this.station,
    required this.onNavigate,
  });

  @override
  State<StationDetailContent> createState() => _StationDetailContentState();
}

class _StationDetailContentState extends State<StationDetailContent> {
  late Station _station;

  bool _isLoading = true;
  String? _error;

  // The published schedule being displayed and which of its days.
  Schedule? _schedule;
  ScheduleDay? _day;

  // This station's Special Assignments (admin pins) for the displayed
  // day's rotation cycle, plus which cycle that is — shown in the stat
  // card next to Required and listed in a dialog when it's tapped.
  List<SpecialAssignment> _specialPins = [];
  String _pinCycleId = '';

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Same shift times used on the schedule detail screen so both screens
  // always agree on what each shift means.
  static const Map<String, String> _shiftTimes = {
    'Morning': '0500H - 1400H',
    'Afternoon': '1400H - 2330H',
    'Night': '2100H - 0500H',
    'HG Day': '0500H - 1700H',
    'HG Night': '1700H - 0500H',
  };

  // Yellow marker behind a reliever's ID in the tables below — the one
  // signal that says "this guard is covering the post, not assigned to
  // it", since Position now always names a real post.
  static const Color _relieverHighlight = Color(0xFFFDE047);

  // Column widths for the ID | Name | Position | Time shift tables below.
  // ID is fixed; the rest flex to fill the card's width. 120 rather than
  // the 110 used elsewhere because a reliever's ID sits inside a padded
  // highlight chip — at 80 an ID like FER554 wrapped mid-token.
  static const Map<int, TableColumnWidth> _shiftColumnWidths = {
    0: FixedColumnWidth(120), // ID
    1: FlexColumnWidth(3),    // Name
    2: FlexColumnWidth(2),    // Position
    3: FlexColumnWidth(2),    // Time
  };

  @override
  void initState() {
    super.initState();
    _station = widget.station;
    _loadSchedule();
  }

  String _formatDate(DateTime date) {
    return '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // Fetches every schedule and picks this station's active PUBLISHED one:
  // the schedule whose 15-day period covers today, or (if today falls
  // outside every period, e.g. the schedule starts next week) the most
  // recently created published one.
  Future<void> _loadSchedule() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.fetchSchedules();
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _error = result['error'].toString();
        _isLoading = false;
      });
      return;
    }

    final published = (result['schedules'] as List<Schedule>)
        .where((s) =>
            s.status == ScheduleStatus.published &&
            s.stationId == _station.id)
        .toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Schedule? schedule;
    ScheduleDay? day;
    if (published.isNotEmpty) {
      schedule = published.firstWhere(
        (s) => !today.isBefore(s.startDate) && !today.isAfter(s.endDate),
        orElse: () => published.reduce(
            (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b),
      );
      if (schedule.days.isNotEmpty) {
        day = schedule.days.firstWhere(
          (d) =>
              d.date.year == today.year &&
              d.date.month == today.month &&
              d.date.day == today.day,
          orElse: () => schedule!.days.first,
        );
      }
    }

    // Pins live per rotation cycle (calendar month), so fetch the ones
    // covering the day being displayed and keep this station's.
    final cycleId = cycleIdFor(day?.date ?? today);
    final pinResult = await ApiService.fetchSpecialAssignments(cycleId);
    if (!mounted) return;

    List<SpecialAssignment> pins = [];
    if (pinResult['success'] == true) {
      pins = (pinResult['specialAssignments'] as List<SpecialAssignment>)
          .where((p) => p.stationId == _station.id)
          .toList()
        ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    }

    setState(() {
      _schedule = schedule;
      _day = day;
      _units = _buildUnits(schedule);
      _specialPins = pins;
      _pinCycleId = cycleId;
      _isLoading = false;
    });
  }

  Future<void> _openEditStationDialog() async {
    final updated = await showDialog<Station>(
      context: context,
      builder: (context) => AddStationDialog(station: _station),
    );

    if (updated != null) {
      setState(() => _station = updated);
    }
  }

  // Read-only list of the admin pins counted by the Special Assignment
  // stat card — who is pinned here this cycle, on which shift, and the
  // station they return to when the pin expires.
  static const Map<String, String> _pinShiftLabels = {
    'morning': 'Morning',
    'afternoon': 'Afternoon',
    'night': 'Night',
    'hgDay': 'HG Day',
    'hgNight': 'HG Night',
  };

  void _showSpecialAssignmentList() {
    showDialog(
      context: context,
      builder: (context) => _buildListDialog(
        icon: Icons.push_pin,
        title: 'Special Assignments',
        subtitle: '${_station.name} · ${cycleRangeLabel(_pinCycleId)} '
            '(${cycleStatusLabel(_pinCycleId)})',
        width: 440,
        // Bounded rather than sized: each row carries a duration line as
        // well, so a station with a handful of pins would run past the
        // bottom of the dialog. The shell's height cap lets the list
        // scroll inside it instead.
        child: _specialPins.isEmpty
            ? _buildDialogEmptyState(
                Icons.push_pin_outlined,
                'No special assignments for this cycle',
                'Pin employees to this station from '
                    'Station Management > Special Assignments.',
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _specialPins.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Colors.grey[200]),
                itemBuilder: (context, index) =>
                    _buildPinTile(_specialPins[index]),
              ),
      ),
    );
  }

  // "August 1 – 31, 2026 · 31 days · 12 days left" — how long this guard
  // is posted here. A pin runs for exactly one rotation cycle, so the
  // window comes from the cycle itself rather than dates of its own.
  Widget _buildPinDuration(SpecialAssignment pin) {
    final ended = cycleStatusLabel(pin.rotationCycleId) == 'ended';
    final color = ended ? Colors.grey[500]! : const Color(0xFF1034A6);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${cycleRangeLabel(pin.rotationCycleId)} · '
              '${pin.durationDays} days · '
              '${cycleStatusLabel(pin.rotationCycleId)}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // One pinned guard: who they are, the post window they're here for,
  // and the shift the pin puts them on.
  Widget _buildPinTile(SpecialAssignment pin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF1034A6).withOpacity(0.1),
            child: Text(
              pin.employeeName.isEmpty
                  ? '?'
                  : pin.employeeName.substring(0, 1),
              style: const TextStyle(
                color: Color(0xFF1034A6),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pin.employeeName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pin.employeeId}'
                  '${pin.homeStation != null ? ' · Home: ${pin.homeStation}' : ''}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                _buildPinDuration(pin),
                if (pin.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Assigned on ${_formatDate(pin.createdAt!)}',
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1034A6).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              pin.shift == null
                  ? 'Floats · AM/PM'
                  : _pinShiftLabels[pin.shift] ?? pin.shift!,
              style: const TextStyle(
                color: Color(0xFF1034A6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Manned posts across the whole published period — a regular and the
  // reliever who covers their days off count as ONE. Built once per load
  // and listed by the Total Assigned card.
  List<_AssignedUnit> _units = [];

  int get _assignedCount => _units.length;

  bool get _isComplete => _assignedCount >= _station.requiredEmployees;

  // True when this entry is somebody standing in for another guard —
  // a reliever, a night internal switch, or a substitute head guard.
  static bool _isCover(ScheduleEntry e) =>
      e.isReliever || (e.coveringFor?.isNotEmpty ?? false);

  // The value appearing most often in [values]; ties break on the first
  // one seen, so a guard who moves posts mid-period is filed under the
  // post they actually hold.
  static String _dominant(Iterable<String> values, String fallback) {
    final counts = <String, int>{};
    for (final v in values) {
      if (v.isEmpty) continue;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) return fallback;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  // Folds the published period's entries into one unit per manned post.
  //
  // A guard with any duty of their OWN here owns a post — head guards
  // included. A guard whose every entry covers somebody else is a pure
  // reliever: they don't get a unit, they get folded into the regular
  // they relieve, which is what makes the pair count as one. Relievers
  // whose regular never appears in this station's schedule stand alone
  // rather than vanishing from the count.
  List<_AssignedUnit> _buildUnits(Schedule? schedule) {
    if (schedule == null) return [];

    final all = schedule.days.expand((d) => d.entries).toList();
    if (all.isEmpty) return [];

    final postOwners = <String>{
      for (final e in all)
        if (!_isCover(e)) e.employeeId,
    };

    // employeeId -> the entries that make them a unit.
    final own = <String, List<ScheduleEntry>>{};
    // regular's employeeId -> the entries of the relievers covering them.
    final covers = <String, List<ScheduleEntry>>{};

    for (final e in all) {
      final coveredId = e.coveringFor;
      final isPureReliever = _isCover(e) && !postOwners.contains(e.employeeId);
      if (isPureReliever &&
          coveredId != null &&
          postOwners.contains(coveredId)) {
        covers.putIfAbsent(coveredId, () => []).add(e);
      } else {
        own.putIfAbsent(e.employeeId, () => []).add(e);
      }
    }

    final units = <_AssignedUnit>[];
    own.forEach((employeeId, entries) {
      // A guard's own duties decide their shift and post; a lone
      // reliever has nothing but cover entries, so those speak for them.
      final defining = entries.where((e) => !_isCover(e)).toList();
      final source = defining.isEmpty ? entries : defining;

      final relieverEntries = covers[employeeId] ?? const <ScheduleEntry>[];
      final relievers = <String, _Person>{};
      for (final r in relieverEntries) {
        relievers[r.employeeId] = _Person(r.employeeId, r.employeeName);
      }

      final shift = _dominant(source.map((e) => e.shift), '');
      units.add(_AssignedUnit(
        regular: _Person(employeeId, source.first.employeeName),
        relievers: relievers.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
        shift: shift,
        post: shift.startsWith('HG')
            ? 'Head Guard'
            : _dominant(source.map((e) => e.post ?? ''), 'Shift Guard'),
        isSpecial: entries.any((e) => e.isSpecial),
        isOrphanReliever: defining.isEmpty,
      ));
    });

    // Head guard leads their block, then posts alphabetically, then name
    // — the same ordering the shift tables below use.
    units.sort((a, b) {
      final aHg = a.shift.startsWith('HG') ? 0 : 1;
      final bHg = b.shift.startsWith('HG') ? 0 : 1;
      if (aHg != bHg) return aHg.compareTo(bHg);
      final byPost = a.post.compareTo(b.post);
      return byPost != 0 ? byPost : a.regular.name.compareTo(b.regular.name);
    });
    return units;
  }

  // Rows for one shift section, built from the displayed day's entries.
  // Head guards lead their block (HG Day with Morning, HG Night with
  // Night), mirroring the schedule detail screen's grouping.
  List<_ShiftRow> _rowsFor(List<String> shifts) {
    final entries = _day?.entries
            .where((e) => shifts.contains(e.shift))
            .toList() ??
        [];

    entries.sort((a, b) {
      final aHg = a.shift.startsWith('HG') ? 0 : 1;
      final bHg = b.shift.startsWith('HG') ? 0 : 1;
      return aHg != bHg
          ? aHg.compareTo(bHg)
          : a.employeeName.compareTo(b.employeeName);
    });

    return entries.map((e) {
      final String position;
      if (e.shift.startsWith('HG')) {
        position = 'Head Guard';
      } else {
        // Real post from the generator (SW Platform / SE Platform /
        // Roving / …); old schedules without one fall back as before.
        // Relievers included: they man the post of the guard whose day
        // off they're covering, which is what the generator stored.
        position = e.post ?? 'Shift Guard';
      }
      return _ShiftRow(
        id: e.employeeId,
        name: e.employeeName,
        position: position,
        time: _shiftTimes[e.shift] ?? '',
        isSpecial: e.isSpecial,
        isReliever: e.isReliever,
      );
    }).toList();
  }

  // ── Total Assigned list ────────────────────────────────────────────
  //
  // Everyone manning this station over the published period, filed under
  // the shift they work. A regular and the reliever covering their days
  // off share one row and count once, which is what the Total Assigned
  // number on the card is counting.
  void _showAssignedList() {
    final sections = <String, List<_AssignedUnit>>{
      'Morning Shift': _unitsFor(const ['HG Day', 'Morning']),
      'Afternoon Shift': _unitsFor(const ['Afternoon']),
      'Night Shift': _unitsFor(const ['HG Night', 'Night']),
    };
    // Anything on a shift label these three don't cover (very old dummy
    // data used 'Day') still has to be visible — it's inside the count.
    final known = const ['HG Day', 'Morning', 'Afternoon', 'HG Night', 'Night'];
    final other =
        _units.where((u) => !known.contains(u.shift)).toList();
    if (other.isNotEmpty) sections['Other'] = other;

    showDialog(
      context: context,
      builder: (context) => _buildListDialog(
        icon: Icons.people,
        title: 'Total Assigned',
        subtitle: _schedule == null
            ? _station.name
            : '${_station.name} · '
                '${_formatDate(_schedule!.startDate)} — '
                '${_formatDate(_schedule!.endDate)}',
        child: _units.isEmpty
            ? _buildDialogEmptyState(
                Icons.event_busy,
                'No one assigned to this station',
                'Publish a schedule for this station in Schedule '
                    'Management to see its roster here.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final section in sections.entries) ...[
                          _buildDialogSectionHeader(
                              section.key, '${section.value.length}'),
                          if (section.value.isEmpty)
                            _buildDialogEmptyRow(
                                'No one assigned to this shift.')
                          else
                            ...section.value.map(_buildUnitTile),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  _buildDialogTotal(
                    'TOTAL ASSIGNED',
                    _assignedCount.toString(),
                    note: 'A regular and their reliever count as one.',
                  ),
                ],
              ),
      ),
    );
  }

  List<_AssignedUnit> _unitsFor(List<String> shifts) =>
      _units.where((u) => shifts.contains(u.shift)).toList();

  // One manned post: the post name, the regular holding it, and the
  // reliever(s) who stand in on their days off — side by side, one row,
  // one head counted.
  Widget _buildUnitTile(_AssignedUnit unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              unit.post,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1034A6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildPersonChip(unit.regular,
                    isReliever: unit.isOrphanReliever),
                if (unit.isSpecial)
                  const Tooltip(
                    message: 'Specially assigned to this station this cycle',
                    child: Icon(Icons.push_pin,
                        size: 13, color: Color(0xFF1034A6)),
                  ),
                for (final reliever in unit.relievers) ...[
                  Icon(Icons.arrow_forward,
                      size: 14, color: Colors.grey[500]),
                  _buildPersonChip(reliever, isReliever: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // "DELA CRUZ, J.  REG441" — the ID carries the same yellow marker the
  // shift tables use when the guard is here as a reliever.
  Widget _buildPersonChip(_Person person, {required bool isReliever}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          person.name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: isReliever
              ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
              : EdgeInsets.zero,
          decoration: isReliever
              ? BoxDecoration(
                  color: _relieverHighlight,
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Text(
            person.id,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: isReliever ? FontWeight.w700 : FontWeight.normal,
              color: isReliever
                  ? const Color(0xFF713F12)
                  : Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  // ── Required list ──────────────────────────────────────────────────
  //
  // The station setup itself: how many guards each shift needs and the
  // post each of those slots is, in the order Edit Station holds them.
  void _showRequiredList() {
    const shiftLabels = {
      'morning': 'Morning Shift',
      'afternoon': 'Afternoon Shift',
      'night': 'Night Shift',
    };

    showDialog(
      context: context,
      builder: (context) => _buildListDialog(
        icon: Icons.groups,
        title: 'Required',
        subtitle: '${_station.name} · post setup per shift',
        child: !_station.hasShiftBreakdown
            ? _buildDialogEmptyState(
                Icons.groups_outlined,
                'No per-shift requirement set',
                'Set the required number and the post for each slot in '
                    'Edit Station.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final entry in shiftLabels.entries) ...[
                          _buildDialogSectionHeader(
                            entry.value,
                            '${_station.requiredFor(entry.key)} required',
                          ),
                          ..._buildRequiredSlots(entry.key),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  _buildDialogTotal(
                    'TOTAL REQUIRED',
                    (_station.requiredMorning +
                            _station.requiredAfternoon +
                            _station.requiredNight)
                        .toString(),
                    note: 'Head guards are counted inside Morning and Night.',
                  ),
                ],
              ),
      ),
    );
  }

  // One row per slot the shift needs. A slot with no post name yet is
  // still listed — it's part of the required number, and it's the same
  // gap Edit Station warns about and the generator fills with "Undefined".
  List<Widget> _buildRequiredSlots(String shiftKey) {
    final posts = _station.postsFor(shiftKey);
    final times = _station.postTimesFor(shiftKey);
    final required = _station.requiredFor(shiftKey);
    final count = required > posts.length ? required : posts.length;

    if (count == 0) {
      return [_buildDialogEmptyRow('No posts required on this shift.')];
    }

    return [
      for (var i = 0; i < count; i++)
        _buildRequiredSlotRow(
          i + 1,
          i < posts.length ? posts[i] : '',
          i < times.length ? times[i].range : '',
        ),
    ];
  }

  Widget _buildRequiredSlotRow(int slot, String post, String time) {
    final named = post.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1034A6).withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$slot',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1034A6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              named ? post : 'Post not assigned yet',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: named ? FontWeight.w600 : FontWeight.normal,
                fontStyle: named ? FontStyle.normal : FontStyle.italic,
                color: named ? const Color(0xFF1E293B) : Colors.orange[800],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            time,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared dialog parts ────────────────────────────────────────────

  // Same shell the Special Assignments dialog uses: icon, title, station
  // subtitle, close button, and a height-capped body that scrolls.
  Widget _buildListDialog({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    double width = 520,
  }) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1034A6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF1034A6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
            minWidth: width, maxWidth: width, maxHeight: 460),
        child: child,
      ),
    );
  }

  Widget _buildDialogSectionHeader(String title, String trailing) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1034A6),
              ),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1034A6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogEmptyRow(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
    );
  }

  Widget _buildDialogEmptyState(
      IconData icon, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  // The number the stat card shows, restated at the foot of its list so
  // the list can be read as an accounting of that one figure.
  Widget _buildDialogTotal(String label, String value, {String? note}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Color(0xFF1034A6),
                  ),
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      note,
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1034A6),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Custom AppBar area
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                  onPressed: () =>
                      widget.onNavigate(ScreenType.stationManagement),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _station.name,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _openEditStationDialog,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Station'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1034A6),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body
          Expanded(child: _buildBody()),
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
              'Failed to load this station\'s schedule',
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
              onPressed: _loadSchedule,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final displayDate = _day?.date ?? DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station Stats — Date, Total Assigned, Required, Status
          Row(
            children: [
              // The date is the only long value in this row, so it gets a
              // smaller type size (and shrinks further on a narrow window)
              // instead of being cut off as "August 1,…".
              _buildStatCard(
                  'Date', _formatDate(displayDate), Icons.calendar_today,
                  valueFontSize: 14),
              const SizedBox(width: 16),
              _buildStatCard(
                  'Total Assigned', _assignedCount.toString(), Icons.people,
                  onTap: _showAssignedList),
              const SizedBox(width: 16),
              _buildStatCard('Required',
                  _station.requiredEmployees.toString(), Icons.groups,
                  onTap: _showRequiredList),
              const SizedBox(width: 16),
              _buildStatCard('Special Assignment',
                  _specialPins.length.toString(), Icons.push_pin,
                  onTap: _showSpecialAssignmentList),
              const SizedBox(width: 16),
              _buildStatCard(
                  'Status',
                  _isComplete ? 'Complete' : 'Incomplete',
                  Icons.verified,
                  isPositive: _isComplete),
            ],
          ),
          const SizedBox(height: 32),

          // Section Title
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
              const Text(
                'Assigned Employees',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 16),
              _buildRelieverLegend(),
              const Spacer(),
              if (_schedule != null)
                Text(
                  'From published schedule '
                  '${_formatDate(_schedule!.startDate)} — '
                  '${_formatDate(_schedule!.endDate)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Employee List — grouped into Morning/Afternoon/Night shift
          // tables, or an empty state when nothing is published yet.
          Expanded(
            child: _day == null ? _buildNoScheduleState() : _buildRoster(),
          ),
        ],
      ),
    );
  }

  // Explains the yellow ID marker used in the shift tables. Kept next to
  // the section title so it's read before the tables, not after them.
  Widget _buildRelieverLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _relieverHighlight,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Highlighted ID = reliever',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildNoScheduleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No published schedule for this station',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a schedule in Generate Schedule, then publish it in '
            'Schedule Management to see assignments here.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRoster() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildShiftSection('Morning Shift', _rowsFor(['HG Day', 'Morning'])),
          _buildShiftDivider(),
          _buildShiftSection('Afternoon Shift', _rowsFor(['Afternoon'])),
          _buildShiftDivider(),
          _buildShiftSection('Night Shift', _rowsFor(['HG Night', 'Night'])),
        ],
      ),
    );
  }

  // valueFontSize overrides the default 20pt value type for cards whose
  // value is text rather than a short number (the Date card). When it's
  // given, the value also scales itself down rather than ellipsizing if
  // the card gets narrower than the text.
  Widget _buildStatCard(String label, String value, IconData icon,
      {bool isPositive = false, VoidCallback? onTap, double? valueFontSize}) {
    // Color logic for Complete vs Incomplete Status card
    Color iconColor = const Color(0xFF1034A6);
    if (label == 'Status') {
      iconColor = isPositive ? Colors.green : Colors.orange;
    }

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (context) {
                          final valueText = Text(
                            value,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: valueFontSize ?? 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                            overflow: valueFontSize == null
                                ? TextOverflow.ellipsis
                                : TextOverflow.visible,
                          );
                          if (valueFontSize == null) return valueText;
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: valueText,
                          );
                        }),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
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

  // One shift block: subtitle, then a card-style table of
  // ID / Name / Position / Time rows for the displayed day.
  Widget _buildShiftSection(String title, List<_ShiftRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        Container(
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
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No one assigned to this shift.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                )
              : Table(
                  columnWidths: _shiftColumnWidths,
                  border: TableBorder.all(
                    color: Colors.grey[200]!,
                    width: 1,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  children: [
                    _buildShiftHeaderRow(),
                    ...rows.map(_buildShiftDataRow),
                  ],
                ),
        ),
      ],
    );
  }

  TableRow _buildShiftHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6).withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      children: const [
        _ShiftHeaderCell('ID'),
        _ShiftHeaderCell('NAME'),
        _ShiftHeaderCell('POSITION'),
        _ShiftHeaderCell('TIME'),
      ],
    );
  }

  // The employee ID, marked yellow when this guard is a reliever. The
  // Position column names the post they're manning either way, so this
  // marker is what tells the two apart.
  Widget _buildIdCell(_ShiftRow row) {
    if (!row.isReliever) {
      return Text(
        row.id,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      );
    }

    return Tooltip(
      message: 'Reliever — covering this post for the guard who is off',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _relieverHighlight,
          borderRadius: BorderRadius.circular(4),
        ),
        // softWrap off so an ID is never broken across two lines inside
        // the chip — it reads as one token or not at all.
        child: Text(
          row.id,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            color: Color(0xFF713F12),
          ),
        ),
      ),
    );
  }

  TableRow _buildShiftDataRow(_ShiftRow row) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildIdCell(row),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (row.isSpecial) ...[
                const SizedBox(width: 6),
                const Tooltip(
                  message: 'Specially assigned to this station this cycle',
                  child: Icon(Icons.push_pin,
                      size: 13, color: Color(0xFF1034A6)),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(row.position, style: const TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(row.time, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  // Thin grey separator with breathing room between shift sections —
  // same treatment used on the schedule detail screen.
  Widget _buildShiftDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      height: 1,
      color: Colors.grey[300],
    );
  }
}

class _ShiftHeaderCell extends StatelessWidget {
  final String text;
  const _ShiftHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Color(0xFF1034A6),
        ),
      ),
    );
  }
}
