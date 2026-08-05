// screens/add_employee_dialog.dart
// "Add Employee" popup form.
// UPDATED: Submit now calls the Python API, which generates the
// username/password and saves the employee to Firestore. On success,
// this dialog closes itself and hands the created Employee back to
// whoever opened it (see employee_list_screen.dart) so the credentials
// can be shown and the list refreshed.
import 'package:flutter/material.dart';
import '../services/api_service.dart';

const Color kPrimaryColor = Color(0xFF1034A6);

const List<String> kRoles = [
  'Regular Employee',
  'Reliever Employee',
  'Head Guard',
];

class AddEmployeeDialog extends StatefulWidget {
  const AddEmployeeDialog({super.key});

  @override
  State<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<AddEmployeeDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  String? _selectedRole;
  final List<String> _selectedStations = [];
  bool _isSubmitting = false;

  // Registered stations loaded from Firestore (via the Python API), so the
  // picker shows the same stations as the Station Management screen instead
  // of a hardcoded placeholder list.
  List<String> _allStations = [];
  bool _isLoadingStations = true;
  String? _stationsError;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoadingStations = true;
      _stationsError = null;
    });

    final result = await ApiService.fetchStations();
    if (!mounted) return;

    setState(() {
      _isLoadingStations = false;
      if (result["success"] == true) {
        _allStations = (result["stations"] as List)
            .map((station) => station.name as String)
            .toList();
      } else {
        _stationsError = result["error"].toString();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Opens the multi-select picker for stations.
  Future<void> _openStationPicker() async {
    if (_isLoadingStations) {
      _showError('Still loading stations, please wait...');
      return;
    }
    if (_stationsError != null) {
      _showError('Could not load stations: $_stationsError');
      _loadStations(); // retry in the background for the next tap
      return;
    }
    if (_allStations.isEmpty) {
      _showError('No stations registered yet. Add stations in Station Management first.');
      return;
    }

    // Work on a temp copy so cancelling doesn't affect current selection.
    final List<String> tempSelected = List.from(_selectedStations);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: kPrimaryColor,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Preferred Station(s)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${tempSelected.length} selected',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Station checkbox list
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _allStations.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                        itemBuilder: (context, index) {
                          final station = _allStations[index];
                          final isChecked = tempSelected.contains(station);
                          return CheckboxListTile(
                            value: isChecked,
                            activeColor: kPrimaryColor,
                            title: Text(station),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  tempSelected.add(station);
                                } else {
                                  tempSelected.remove(station);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    // Footer actions
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                setDialogState(() => tempSelected.clear());
                              },
                              child: const Text('Clear All'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context, tempSelected),
                              child: const Text('Done'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedStations
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _handleSubmit() async {
    // Basic validation — mirrors the required fields in the form.
    if (_nameController.text.trim().isEmpty) {
      _showError("Please enter the employee's name.");
      return;
    }
    if (_mobileController.text.trim().isEmpty) {
      _showError("Please enter a mobile number.");
      return;
    }
    if (_selectedRole == null) {
      _showError("Please select a role.");
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await ApiService.createEmployee(
      name: _nameController.text.trim(),
      mobileNo: _mobileController.text.trim(),
      role: _selectedRole!,
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      preferredStations: _selectedStations,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result["success"] == true) {
      // Hand the newly created Employee (with generated username/password)
      // back to whoever opened this dialog (employee_list_screen.dart),
      // which will show the credentials and refresh the list.
      Navigator.pop(context, result["employee"]);
    } else {
      _showError(result["error"].toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _fieldLabel(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(text: text),
            if (optional)
              const TextSpan(
                text: '  (optional)',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.normal,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add New Employee',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name
                _fieldLabel('Name'),
                TextField(
                  controller: _nameController,
                  decoration: _inputDecoration('Enter full name'),
                ),
                const SizedBox(height: 16),

                // Mobile No.
                _fieldLabel('Mobile No.'),
                TextField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration('e.g. 09XXXXXXXXX'),
                ),
                const SizedBox(height: 16),

                // Role
                _fieldLabel('Role'),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: _inputDecoration('Select role'),
                  items: kRoles
                      .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedRole = value);
                  },
                ),
                const SizedBox(height: 16),

                // Email (optional)
                _fieldLabel('Email', optional: true),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('Enter email address'),
                ),
                const SizedBox(height: 16),

                // Preferred Station (multi-select)
                _fieldLabel('Preferred Station'),
                InkWell(
                  onTap: _openStationPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _selectedStations.isEmpty
                              ? const Text(
                            'No station selected',
                            style: TextStyle(color: Colors.grey),
                          )
                              : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _selectedStations
                                .map(
                                  (s) => Chip(
                                label: Text(s, style: const TextStyle(fontSize: 12)),
                                backgroundColor: kPrimaryColor.withOpacity(0.08),
                                labelStyle: const TextStyle(color: kPrimaryColor),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                                .toList(),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Submit button - calls the Python API and saves to Firestore
                Center(
                  child: SizedBox(
                    width: 200,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Submit',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}