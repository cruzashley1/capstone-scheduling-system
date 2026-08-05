// screens/employee_detail_screen.dart
// UPDATED: Save/Delete now call the Python API instead of DummyData.
// Additional Information now shows Username/Password/Date Joined/
// Preferred Station using the employee's real data.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../services/api_service.dart';
import '../services/duty_service.dart';
import 'employee_schedule_dialog.dart';
import 'set_on_leave_dialog.dart';
import 'main_layout.dart'; // For ScreenType enum

// CHANGED: Now accepts onBack and onNavigate callbacks
// REASON: Allows navigation without using Navigator (fixes double drawer issue)
class EmployeeDetailScreen extends StatefulWidget {
  final Employee employee;
  final VoidCallback? onBack;  // NEW: Callback for back navigation
  final Function(ScreenType, {dynamic data})? onNavigate;  // NEW: Callback for internal navigation

  const EmployeeDetailScreen({
    super.key,
    required this.employee,
    this.onBack,
    this.onNavigate,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _stationController;
  late EmployeeType _selectedType;
  bool _isEditing = false;
  bool _isActive = true;
  bool _showPassword = false; // NEW: eye toggle for the password row

  // This employee's leave history. "On Leave" is DERIVED from an approved
  // record whose range covers today — never stored as a flag, so a leave
  // that ends turns itself off without anyone remembering to.
  List<LeaveRequest> _leaves = [];
  bool _loadingLeave = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employee.name);
    _emailController = TextEditingController(text: widget.employee.email);
    _phoneController = TextEditingController(text: widget.employee.phone);
    // Filled in by _loadDuty() with the employee's ACTUAL station for
    // the current schedule period; "Pending" when they have none.
    _stationController = TextEditingController(text: 'Loading...');
    _selectedType = widget.employee.type;
    _isActive = widget.employee.isActive;
    _loadDuty();
    _loadLeave();
  }

  // Looks up this employee's real assignment from the schedules.
  Future<void> _loadDuty() async {
    final duties = await DutyService.fetchDutyMap();
    if (!mounted) return;
    setState(() {
      _stationController.text =
          (duties[widget.employee.id] ?? const DutyInfo()).stationLabel;
    });
  }

  Future<void> _loadLeave() async {
    final result =
        await ApiService.fetchEmployeeLeaveRequests(widget.employee.id);
    if (!mounted) return;
    setState(() {
      _loadingLeave = false;
      if (result['success'] == true) {
        _leaves = (result['requests'] as List).cast<LeaveRequest>();
      }
    });
  }

  // The approved leave covering today, if any — what makes the status
  // pill read "On Leave" instead of On Duty / Day Off.
  LeaveRequest? get _activeLeave {
    for (final l in _leaves) {
      if (l.isOnLeaveNow) return l;
    }
    return null;
  }

  // The next approved leave that hasn't started yet, so the admin can see
  // it coming before it silently empties a roster.
  LeaveRequest? get _upcomingLeave {
    final upcoming = _leaves.where((l) => l.isUpcoming).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Future<void> _saveChanges() async {
    // NOTE: Station Assignment now shows the actual duty from the
    // generated schedule, so it is read-only here and no longer sent
    // as preferredStations (those stay as chosen at registration).
    final result = await ApiService.updateEmployee(
      widget.employee.id,
      name: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      type: _selectedType,
      isActive: _isActive,
    );

    if (!mounted) return;

    if (result["success"] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${result["error"]}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isEditing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Employee updated successfully'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    // CHANGED: Use callback instead of Navigator.pop
    // REASON: Prevents creating new routes, keeps single MainLayout structure
    if (widget.onBack != null) {
      widget.onBack!();
    }
  }

  @override
  Widget build(BuildContext context) {
    // CHANGED: Removed outer Scaffold, using Container instead
    // REASON: MainLayout already provides Scaffold, prevents double drawer
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // CHANGED: Converted AppBar to custom header container
          // REASON: AppBar requires Scaffold, we use custom header in content area
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                  onPressed: () {
                    // CHANGED: Use callback if available, fallback to Navigator
                    if (widget.onBack != null) {
                      widget.onBack!();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Employee' : 'Employee Details',
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1034A6),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: _saveChanges,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // REST OF YOUR UI - EXACTLY AS BEFORE (landscape layout)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side - Profile Section
                  // FIXED: wrapped in SingleChildScrollView so the extra
                  // edit-mode controls (type chips + Active Status switch)
                  // scroll instead of overflowing the bottom by ~65px.
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                        Container(
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
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                // Profile Image
                                Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    Container(
                                      width: 150,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            const Color(0xFF1034A6),
                                            const Color(0xFF1034A6).withOpacity(0.8),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF1034A6).withOpacity(0.3),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          widget.employee.name.substring(0, 1),
                                          style: const TextStyle(
                                            fontSize: 60,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_isEditing)
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.1),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt,
                                          size: 20,
                                          color: Color(0xFF1034A6),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Name
                                Text(
                                  widget.employee.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.employee.id,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Status Badge
                                // FIXED: each type now has its own label
                                // (Regular / Reliever / Head Guard) instead
                                // of "Reliever: Head Guard" for both.
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _typeBackgroundColor(_selectedType),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _typeBorderColor(_selectedType),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Employee Type',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _typeIcon(_selectedType),
                                            color: _typeTextColor(_selectedType),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _typeLabel(_selectedType),
                                            style: TextStyle(
                                              color: _typeTextColor(_selectedType),
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_isEditing) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _buildTypeChip(EmployeeType.regular),
                                            _buildTypeChip(EmployeeType.reliever),
                                            _buildTypeChip(EmployeeType.headGuard),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // View Schedule — full day-by-day duty list
                                // from the employee's published schedules.
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            EmployeeScheduleDialog(
                                                employee: widget.employee),
                                      );
                                    },
                                    icon: const Icon(Icons.calendar_month, size: 18),
                                    label: const Text('View Schedule'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1034A6),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),

                                // Set On Leave — records a leave against
                                // this employee. A leave already running
                                // cannot be ended from here: it runs to
                                // its end date on its own, and calling one
                                // off early is a decision that belongs
                                // with the record itself, in Notifications
                                // → Leave Requests.
                                if (!_isEditing) ...[
                                  const SizedBox(height: 10),
                                  if (_activeLeave == null)
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _openSetOnLeave,
                                        icon: const Icon(
                                            Icons.beach_access_outlined,
                                            size: 18),
                                        label: const Text('Set On Leave'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF0D9488),
                                          side: const BorderSide(
                                              color: Color(0xFF99F6E4)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    _buildLeaveRunningNote(_activeLeave!),
                                ],

                                const SizedBox(height: 16),

                                // CHANGED: Active/Inactive → On Duty/Day Off,
                                // and a third state: an approved leave whose
                                // range covers today outranks both.
                                if (_isEditing)
                                  SwitchListTile(
                                    title: const Text('Active Status'),
                                    value: _isActive,
                                    activeThumbColor: const Color(0xFF1034A6),
                                    onChanged: (value) => setState(() => _isActive = value),
                                  )
                                else
                                  _buildStatusPill(),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Delete Button
                        if (!_isEditing)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _showDeleteConfirmation,
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              label: const Text(
                                'Delete Employee',
                                style: TextStyle(color: Colors.red),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Right Side - Details Section (your exact code)
                  Expanded(
                    flex: 3,
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
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Employee Information',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Form Grid
                            LayoutBuilder(
                              builder: (context, constraints) {
                                int crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
                                return GridView.count(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 24,
                                  mainAxisSpacing: 24,
                                  childAspectRatio: 4,
                                  children: [
                                    _buildDetailField(
                                      'Full Name',
                                      _nameController,
                                      Icons.person_outline,
                                      enabled: _isEditing,
                                    ),
                                    _buildDetailField(
                                      'Email Address',
                                      _emailController,
                                      Icons.email_outlined,
                                      enabled: _isEditing,
                                      keyboardType: TextInputType.emailAddress,
                                    ),
                                    _buildDetailField(
                                      'Phone Number',
                                      _phoneController,
                                      Icons.phone_outlined,
                                      enabled: _isEditing,
                                      keyboardType: TextInputType.phone,
                                    ),
                                    // Always read-only: the actual duty comes
                                    // from the generated schedule, not typing.
                                    _buildDetailField(
                                      'Station Assignment',
                                      _stationController,
                                      Icons.location_on_outlined,
                                      enabled: false,
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 32),

                            // Additional Information Section
                            const Text(
                              'Additional Information',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 24),

                            _buildInfoRow('Username', widget.employee.username),
                            _buildPasswordRow(widget.employee.password),
                            _buildInfoRow(
                              'Date Joined',
                              _formatDate(widget.employee.dateJoined),
                            ),
                            _buildInfoRow(
                              'Preferred Station',
                              widget.employee.preferredStations.isEmpty
                                  ? 'Unassigned'
                                  : widget.employee.preferredStations.join(', '),
                            ),
                            _buildInfoRow('Leave Status', _leaveSummary),
                            _buildInfoRow(
                              'Leaves This Year',
                              _leavesThisYearSummary,
                            ),

                            if (_isEditing) ...[
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => setState(() => _isEditing = false),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        side: const BorderSide(color: Colors.grey),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _saveChanges,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1034A6),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text('Save Changes'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Leave ---

  // The three-state duty pill. An approved leave covering today wins over
  // On Duty / Day Off: whatever the active flag says, this employee is
  // not reporting for work.
  Widget _buildStatusPill() {
    final leave = _activeLeave;
    if (leave != null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D9488).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF99F6E4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D9488),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'On Leave',
                  style: TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              leave.rangeLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F766E),
              ),
            ),
            Text(
              '${leave.leaveType} · ${leave.daysRemaining} day(s) left',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: _isActive
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isActive ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            // CHANGED: Active → On Duty, Inactive → Day Off
            _isActive ? 'On Duty' : 'Day Off',
            style: TextStyle(
              color: _isActive ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // What the Additional Information block says about leave: the leave
  // running now, else the next one coming, else nothing.
  String get _leaveSummary {
    if (_loadingLeave) return 'Loading...';
    final active = _activeLeave;
    if (active != null) {
      return 'On Leave · ${active.leaveType} · ${active.rangeLabel} '
          '(${active.daysRemaining} day(s) left)';
    }
    final upcoming = _upcomingLeave;
    if (upcoming != null) {
      return 'Upcoming · ${upcoming.leaveType} · ${upcoming.rangeLabel}';
    }
    final pending = _leaves.where((l) => l.isPending).toList();
    if (pending.isNotEmpty) {
      return 'Leave request pending · ${pending.first.rangeLabel}';
    }
    return 'Not on leave';
  }

  // The 2-per-year quota as it stands, counted the same way the backend
  // charges it: by the leave's START year, pending and approved both.
  String get _leavesThisYearSummary {
    if (_loadingLeave) return 'Loading...';
    final year = DateTime.now().year;
    final used = _leaves
        .where((l) => (l.isPending || l.isApproved) && l.year == year)
        .length;
    return '$used of 2 used in $year';
  }

  Future<void> _openSetOnLeave() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SetOnLeaveDialog(employee: widget.employee),
    );
    if (result == null || !mounted) return;

    final record = result['request'] as LeaveRequest?;
    final duties =
        (result['affectedDuties'] as List?)?.cast<LeaveAffectedDuty>() ??
            const <LeaveAffectedDuty>[];

    await _loadLeave();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${widget.employee.name} is on leave — '
          '${record?.rangeLabel ?? 'dates saved'}.',
        ),
        backgroundColor: const Color(0xFF0D9488),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // A leave recorded over a live roster leaves posts behind it. Say so
    // plainly rather than letting them go unmanned unnoticed.
    if (duties.isNotEmpty) _showAffectedDutiesDialog(duties);
  }

  void _showAffectedDutiesDialog(List<LeaveAffectedDuty> duties) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFB45309), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${duties.length} duty(ies) need a replacement',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This leave covers days ${widget.employee.name} was already '
                'rostered for. Those posts are now vacant — assign cover '
                'from Find Replacement.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final d in duties)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                d.isPublished
                                    ? Icons.event_busy_rounded
                                    : Icons.edit_calendar_outlined,
                                size: 15,
                                color: d.isPublished
                                    ? const Color(0xFFB45309)
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${LeaveRequest.formatShort(d.date)}  ·  '
                                  '${d.stationName}  ·  ${d.shift}'
                                  '${d.post.isEmpty ? '' : '  ·  ${d.post}'}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF475569)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF64748B)),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onNavigate?.call(ScreenType.findReplacement);
            },
            icon: const Icon(Icons.person_search_outlined, size: 16),
            label: const Text('Find Replacement'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1034A6),
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // Shown where the Set On Leave button sits while a leave is running.
  // Deliberately not a button: a leave ends on its end date, and this
  // screen is not where it gets called off early.
  Widget _buildLeaveRunningNote(LeaveRequest leave) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_clock_outlined,
              size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave running until '
                  '${LeaveRequest.formatShort(leave.endDate)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'It ends on its own — ${leave.daysRemaining} day(s) left. '
                  'A leave cannot be ended from here.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Employee type helpers: one label/color/icon per type ---
  String _typeLabel(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return 'Regular';
      case EmployeeType.reliever:
        return 'Reliever';
      case EmployeeType.headGuard:
        return 'Head Guard';
    }
  }

  IconData _typeIcon(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return Icons.badge;
      case EmployeeType.reliever:
        return Icons.swap_horiz;
      case EmployeeType.headGuard:
        return Icons.shield;
    }
  }

  Color _typeTextColor(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return const Color(0xFF7C3AED); // purple
      case EmployeeType.reliever:
        return const Color(0xFFD97706); // amber
      case EmployeeType.headGuard:
        return const Color(0xFF0369A1); // blue
    }
  }

  Color _typeBorderColor(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return const Color(0xFF8B5CF6);
      case EmployeeType.reliever:
        return const Color(0xFFF59E0B);
      case EmployeeType.headGuard:
        return const Color(0xFF0284C7);
    }
  }

  Color _typeBackgroundColor(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return const Color(0xFFEDE9FE);
      case EmployeeType.reliever:
        return const Color(0xFFFEF3C7);
      case EmployeeType.headGuard:
        return const Color(0xFFE0F2FE);
    }
  }

  Widget _buildTypeChip(EmployeeType type) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(_typeLabel(type)),
      selected: isSelected,
      selectedColor: _typeBorderColor(type),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedType = type);
        }
      },
    );
  }

  // YOUR EXACT HELPER METHODS - NO CHANGES
  Widget _buildDetailField(
      String label,
      TextEditingController controller,
      IconData icon, {
        required bool enabled,
        TextInputType? keyboardType,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF1034A6)),
            filled: !enabled,
            fillColor: enabled ? null : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1034A6), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Same layout as _buildInfoRow, but the value is masked by default
  // with an eye icon to reveal/hide it.
  Widget _buildPasswordRow(String password) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              'Password',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  _showPassword ? password : '•' * password.length,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _showPassword = !_showPassword),
                  child: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Manual formatting (e.g. "January 15, 2023") to avoid adding the
  // intl package just for this.
  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      // FIXED: the dialog's context is named dialogContext so the code
      // below can't accidentally use it after the dialog is closed
      // (which used to crash the snackbar after deleting).
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Employee'),
        content: Text(
          'Are you sure you want to delete ${widget.employee.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // close the confirmation dialog first

              final result = await ApiService.deleteEmployee(widget.employee.id);

              if (!mounted) return;

              if (result["success"] == true) {
                // Snackbar first (while this screen's context is still
                // alive), then navigate back.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Employee deleted successfully'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // CHANGED: Use callback instead of Navigator.pop
                // REASON: Prevents creating new routes, keeps single MainLayout structure
                if (widget.onBack != null) {
                  widget.onBack!();
                } else {
                  Navigator.pop(context);
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: ${result["error"]}'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}