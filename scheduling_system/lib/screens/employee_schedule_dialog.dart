// screens/employee_schedule_dialog.dart
//
// Opened by the "View Schedule" button on the Employee Details screen.
// Pulls the employee's shifts from every PUBLISHED schedule they appear
// in (GET /employees/{id}/schedule) and lists each period day by day:
// Date | Shift | Station | Status — so the admin can see at a glance
// where the guard is posted and which days are their days off.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/guard_shift.dart';
import '../services/api_service.dart';

const _primary = Color(0xFF1034A6);

// One table row: a day inside a schedule period, with the shift the
// employee works that day (null = day off).
class _DayRow {
  final DateTime date;
  final GuardShift? shift;

  const _DayRow({required this.date, this.shift});
}

class EmployeeScheduleDialog extends StatefulWidget {
  final Employee employee;

  const EmployeeScheduleDialog({super.key, required this.employee});

  @override
  State<EmployeeScheduleDialog> createState() => _EmployeeScheduleDialogState();
}

class _EmployeeScheduleDialogState extends State<EmployeeScheduleDialog> {
  bool _isLoading = true;
  String? _error;

  List<GuardShift> _shifts = [];
  List<GuardPeriod> _periods = [];

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const Map<int, TableColumnWidth> _columnWidths = {
    0: FixedColumnWidth(150), // Date
    1: FlexColumnWidth(3),    // Shift
    2: FlexColumnWidth(2),    // Station
    3: FixedColumnWidth(110), // Status
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.fetchEmployeeSchedule(widget.employee.id);
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _error = result['error'].toString();
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _shifts = result['shifts'] as List<GuardShift>;
      _periods = result['periods'] as List<GuardPeriod>;
      _isLoading = false;
    });
  }

  String _formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isToday(DateTime d) => _dateOnly(d) == _dateOnly(DateTime.now());

  // The employee's status right now, mirroring DutyService's rules:
  // On Duty when they have a shift today, Day Off when today falls in
  // one of their periods without a shift, Unassigned otherwise.
  String get _currentStatus {
    final today = _dateOnly(DateTime.now());
    if (_shifts.any((s) => _dateOnly(s.date) == today)) return 'On Duty';
    if (_periods.any((p) => p.contains(today))) return 'Day Off';
    return 'Unassigned';
  }

  Color get _currentStatusColor {
    switch (_currentStatus) {
      case 'On Duty':
        return Colors.green;
      case 'Day Off':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // The station heading a period. A guard holding one post all period
  // reads as just that station; a reliever topped up towards their 12
  // days across nearby stations reads as the one they spend most of it
  // at, plus how many others they cover. The per-day Station column
  // below says exactly where they are on any given date.
  String _stationLabel(GuardPeriod period) {
    final others = period.otherStations.length;
    if (others == 0) return period.stationName;
    return '${period.stationName} +$others more';
  }

  // Every day of the period, each paired with the shift(s) the employee
  // works on it — days with no entry become "Day Off" rows.
  List<_DayRow> _rowsFor(GuardPeriod period) {
    final rows = <_DayRow>[];
    var d = _dateOnly(period.startDate);
    final end = _dateOnly(period.endDate);

    while (!d.isAfter(end)) {
      // Matched by DATE, not by schedule document: a reliever topped up
      // towards their 12 days works several stations inside one period,
      // so their duties are spread over several documents that all cover
      // these same dates. Filtering by scheduleId showed only the days
      // worked at one of them and called the other ten "Day Off".
      final dayShifts =
          _shifts.where((s) => _dateOnly(s.date) == d).toList();
      if (dayShifts.isEmpty) {
        rows.add(_DayRow(date: d));
      } else {
        rows.addAll(dayShifts.map((s) => _DayRow(date: d, shift: s)));
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 760,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.calendar_month, color: _primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.employee.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                '${widget.employee.id} · '
                '${employeeTypeToRoleString(widget.employee.type)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
        if (!_isLoading && _error == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _currentStatusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentStatusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _currentStatus,
                  style: TextStyle(
                    color: _currentStatusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
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
            Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              'Failed to load schedule',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_periods.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No published schedule for this employee',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'They will appear here once a schedule that includes them '
              'is published in Schedule Management.',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _periods.length; i++) ...[
            if (i > 0) const SizedBox(height: 24),
            _buildPeriodSection(_periods[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodSection(GuardPeriod period) {
    final rows = _rowsFor(period);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_stationLabel(period)} · '
                '${_formatDate(period.startDate)} — '
                '${_formatDate(period.endDate)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            Text(
              '${rows.where((r) => r.shift != null).length} working days',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Table(
            columnWidths: _columnWidths,
            border: TableBorder.all(
              color: Colors.grey[200]!,
              width: 1,
              borderRadius: BorderRadius.circular(12),
            ),
            children: [
              _buildHeaderRow(),
              ...rows.map(_buildDataRow),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(color: _primary.withOpacity(0.05)),
      children: const [
        _HeaderCell('DATE'),
        _HeaderCell('SHIFT'),
        _HeaderCell('STATION'),
        _HeaderCell('STATUS'),
      ],
    );
  }

  TableRow _buildDataRow(_DayRow row) {
    final shift = row.shift;
    final onDuty = shift != null;
    final statusColor = onDuty ? Colors.green : Colors.red;

    String shiftText = '—';
    if (shift != null) {
      shiftText = '${shift.shift} · ${shift.timeRange}';
      if (shift.isReliever) shiftText += ' · Reliever';
    }

    return TableRow(
      decoration: _isToday(row.date)
          ? BoxDecoration(color: _primary.withOpacity(0.04))
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            _formatDate(row.date),
            style: TextStyle(
              fontSize: 13,
              fontWeight: _isToday(row.date) ? FontWeight.w700 : FontWeight.w500,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            shiftText,
            style: TextStyle(
              fontSize: 13,
              color: onDuty ? const Color(0xFF1E293B) : Colors.grey[500],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            shift?.stationName ?? '—',
            style: TextStyle(
              fontSize: 13,
              color: onDuty ? const Color(0xFF1E293B) : Colors.grey[500],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                onDuty ? 'On Duty' : 'Day Off',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: _primary,
        ),
      ),
    );
  }
}
