// screens/employee_list_content.dart
// UPDATED: Now fetches employees from Firestore via the Python API
// instead of DummyData.
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/duty_service.dart';
import 'main_layout.dart';
import 'add_employee_dialog.dart';

class EmployeeListContent extends StatefulWidget {
  final Function(ScreenType, {dynamic data}) onNavigate;

  const EmployeeListContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<EmployeeListContent> createState() => _EmployeeListContentState();
}

class _EmployeeListContentState extends State<EmployeeListContent> {
  EmployeeType _selectedType = EmployeeType.regular;

  // Raw list fetched from Firestore (via the Python API).
  List<Employee> _allEmployees = [];
  // Filtered by _selectedType, shown in the table.
  List<Employee> _employees = [];

  // employeeId -> actual duty for today, derived from the schedules.
  // Drives the Station Assignment and Status columns.
  Map<String, DutyInfo> _duties = {};

  bool _isLoading = true;
  String? _errorMessage;

  // NEW: Search controller
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    // NEW: Listen to search changes
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

  // Fetches the full employee list from the backend.
  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Employees and schedules load in parallel; the schedules tell us
    // each employee's actual duty (station + on duty / day off) today.
    final results = await Future.wait([
      ApiService.fetchEmployees(),
      DutyService.fetchDutyMap(),
    ]);
    final result = results[0];
    final duties = results[1] as Map<String, DutyInfo>;

    if (!mounted) return;

    if (result["success"] == true) {
      setState(() {
        _allEmployees = result["employees"];
        _duties = duties;
        _isLoading = false;
      });
      _filterEmployees();
    } else {
      setState(() {
        _errorMessage = result["error"].toString();
        _isLoading = false;
      });
    }
  }

  // Update this method to sort by surname alphabetically
  void _filterEmployees() {
    setState(() {
      _employees = _allEmployees
          .where((e) => e.type == _selectedType)
          .toList()
        ..sort((a, b) {
          // Extract surnames for alphabetical sorting
          final aSurname = a.formattedName.split(',').first;
          final bSurname = b.formattedName.split(',').first;
          return aSurname.compareTo(bSurname);
        });
    });
  }

  // Search matches the employee themselves only — ID, name and email.
  // The station assignment is deliberately NOT searched: typing "B" used
  // to surface guards posted at Bambang even though no letter of their
  // name matched. formattedName is included so the "Surname, First"
  // form shown in the table can be typed as-is.
  //
  // A search spans ALL employee types, not just the selected tab: the
  // admin types a name to find a person, and having to guess whether that
  // person is filed under Regular, Reliever or Head Guard before the name
  // will match defeats the point. Each result carries a type badge, and
  // the type toggles only govern the unsearched list.
  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;

    return _allEmployees.where((e) {
      final searchLower = _searchQuery;
      return e.id.toLowerCase().contains(searchLower) ||
          e.name.toLowerCase().contains(searchLower) ||
          e.formattedName.toLowerCase().contains(searchLower) ||
          e.email.toLowerCase().contains(searchLower);
    }).toList()
      ..sort((a, b) {
        final aSurname = a.formattedName.split(',').first;
        final bSurname = b.formattedName.split(',').first;
        return aSurname.compareTo(bSurname);
      });
  }

  static String _typeLabel(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return 'Regular';
      case EmployeeType.reliever:
        return 'Reliever';
      case EmployeeType.headGuard:
        return 'Head Guard';
    }
  }

  static Color _typeColor(EmployeeType type) {
    switch (type) {
      case EmployeeType.regular:
        return const Color(0xFF1034A6);
      case EmployeeType.reliever:
        return const Color(0xFF0D9488);
      case EmployeeType.headGuard:
        return const Color(0xFF7C3AED);
    }
  }

  // Shown once, right after an employee is registered, so the admin can
  // note down the login details. The same info is also saved permanently
  // on the employee's detail page.
  void _showCredentialsDialog(Employee employee) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Employee Registered'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${employee.name} has been added. Share these login details with them:',
            ),
            const SizedBox(height: 16),
            _credentialRow('Username', employee.username),
            const SizedBox(height: 8),
            _credentialRow('Password', employee.password),
            const SizedBox(height: 16),
            Text(
              "You can view this again anytime on ${employee.name}'s detail page.",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1034A6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _credentialRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header - UPDATED with Search Bar
        Container(
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => widget.onNavigate(ScreenType.dashboard),
                    ),
                    const SizedBox(width: 16),
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Security Management',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Manage your staff and assignments',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // NEW: Search Bar added here
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search employees...',
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
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  // AddEmployeeDialog returns the created Employee (with
                  // generated username/password) on success, or null if
                  // the admin cancelled.
                  final newEmployee = await showDialog<Employee>(
                    context: context,
                    builder: (context) => const AddEmployeeDialog(),
                  );

                  if (newEmployee != null) {
                    _showCredentialsDialog(newEmployee);
                    _loadEmployees(); // refresh the table with the new hire
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Employee'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1034A6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Toggle Buttons - EXACTLY AS YOU DESIGNED
        Padding(
          padding: const EdgeInsets.all(24),
          // Scrolls sideways on a narrow window instead of overflowing.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToggleButton(
                  'Regular Employee',
                  EmployeeType.regular,
                  Icons.badge,
                ),
                const SizedBox(width: 12),
                _buildToggleButton(
                  'Reliever Employee',
                  EmployeeType.reliever,
                  Icons.swap_horiz,
                ),
                const SizedBox(width: 12),
                _buildToggleButton(
                  'Head Guard',
                  EmployeeType.headGuard,
                  Icons.shield,
                ),
              ],
            ),
          ),
        ),

        // NEW: Show search results count
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filteredEmployees.length} result${_filteredEmployees.length != 1 ? 's' : ''} found '
                'across all employee types',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
          ),

        // Loading state — shown while fetching from Firestore
        if (_isLoading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        // Error state — backend unreachable or Firestore error
        else if (_errorMessage != null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Could not load employees.\n$_errorMessage',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadEmployees,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1034A6),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
        // Employee Table - EXACTLY AS YOU DESIGNED
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Table Header - EXACTLY AS YOU DESIGNED
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1034A6).withOpacity(0.05),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildTableHeader('Employee ID', 1),
                          // ADDED: Vertical divider
                          const VerticalDividerWidget(),
                          _buildTableHeader('Name', 2),
                          // ADDED: Vertical divider
                          const VerticalDividerWidget(),
                          _buildTableHeader('Station Assignment', 2),
                          // ADDED: Vertical divider
                          const VerticalDividerWidget(),
                          // Status/Actions cells are centered, so their
                          // headers are centered too to keep columns aligned.
                          _buildTableHeader('Status', 1, align: TextAlign.center),
                          // ADDED: Vertical divider
                          const VerticalDividerWidget(),
                          _buildTableHeader('Actions', 1, align: TextAlign.center),
                        ],
                      ),
                    ),

                    // Table Body - UPDATED to use filtered list
                    Expanded(
                      child: _filteredEmployees.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? 'No employees found' : 'No results found',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                          : ListView.separated(
                        itemCount: _filteredEmployees.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final employee = _filteredEmployees[index];
                          // While searching, results can come from any
                          // type — label each one so the admin knows
                          // which list the person actually lives in.
                          return _buildEmployeeRow(
                            employee,
                            showType: _searchQuery.isNotEmpty,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ALL YOUR EXACT ORIGINAL METHODS
  Widget _buildToggleButton(String label, EmployeeType type, IconData icon) {
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
          _filterEmployees();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1034A6) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF1034A6) : Colors.grey[300]!,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: const Color(0xFF1034A6).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_allEmployees.where((e) => e.type == type).length}',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String label, int flex, {TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1034A6),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildEmployeeRow(Employee employee, {bool showType = false}) {
    // Actual duty for today (from the schedules), NOT the preferred
    // station list. No duty found => "Pending" / "Unassigned".
    final duty = _duties[employee.id] ?? const DutyInfo();

    return InkWell(
      onTap: () {
        widget.onNavigate(ScreenType.employeeDetail, data: employee);
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Text(
                employee.id,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // ADDED: Vertical divider
            const VerticalDividerWidget(),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      employee.formattedName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (showType) ...[
                    const SizedBox(width: 8),
                    _buildTypeBadge(employee.type),
                  ],
                ],
              ),
            ),
            // ADDED: Vertical divider
            const VerticalDividerWidget(),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: duty.station == null ? Colors.grey[400] : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  // Shows the employee's ACTUAL station for the current
                  // schedule period; "Pending" when they have none.
                  Expanded(
                    child: Text(
                      duty.stationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: duty.station == null
                          ? TextStyle(
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            // ADDED: Vertical divider
            const VerticalDividerWidget(),
            Expanded(
              flex: 1,
              // Center keeps the badge sized to its text instead of
              // stretching across the column, so the Status column
              // lines up under its (centered) header.
              child: Center(child: _buildStatusBadge(duty)),
            ),
            // ADDED: Vertical divider
            const VerticalDividerWidget(),
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                    onPressed: () {
                      widget.onNavigate(ScreenType.employeeDetail, data: employee);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () => _showDeleteDialog(employee),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Which list this person belongs to — only drawn on search results,
  // where the rows no longer all share the selected type.
  Widget _buildTypeBadge(EmployeeType type) {
    final color = _typeColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Status badge: On Duty (working today), Day Off (scheduled this
  // period but not today), Unassigned (not in any current schedule).
  Widget _buildStatusBadge(DutyInfo duty) {
    final color = duty.statusColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        duty.statusLabel,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showDeleteDialog(Employee employee) {
    showDialog(
      context: context,
      // FIXED: the dialog's context is named dialogContext so the code
      // below can't accidentally use it after the dialog is closed
      // (which used to crash the snackbar after deleting).
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Are you sure you want to delete ${employee.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // close the confirmation dialog first
              final result = await ApiService.deleteEmployee(employee.id);

              if (!mounted) return;

              if (result["success"] == true) {
                _loadEmployees(); // refresh from Firestore
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Employee deleted successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: ${result["error"]}'),
                    backgroundColor: Colors.red,
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

// ADDED: Reusable vertical divider widget for table columns
class VerticalDividerWidget extends StatelessWidget {
  const VerticalDividerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey[300],
    );
  }
}