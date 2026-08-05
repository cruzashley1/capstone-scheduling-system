import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import 'main_layout.dart';
import 'dashboard_screen.dart';
import 'employee_list_screen.dart';
import 'station_management_screen.dart';

class PlaceholderScreen extends StatefulWidget {
  final String title;
  final Function(ScreenType screen, {dynamic data})? onNavigate;

  const PlaceholderScreen({
    super.key,
    required this.title,
    this.onNavigate,
  });

  @override
  State<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

class _PlaceholderScreenState extends State<PlaceholderScreen> {
  int _getIndex() {
    switch (widget.title) {
      case 'Generate Schedule':
        return 3;
      case 'Reports':
        return 4;
      case 'Settings':
        return 5;
      default:
        return 0;
    }
  }

  void _onItemSelected(int index, BuildContext context) {
    if (index == _getIndex()) return;

    final nav = widget.onNavigate;

    if (index == 0) {
      if (nav != null) {
        nav(ScreenType.dashboard);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => DashboardContent(onNavigate: (screen, {data}) {})),
        );
      }
    } else if (index == 1) {
      if (nav != null) {
        nav(ScreenType.employeeList);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => EmployeeListContent(onNavigate: (screen, {data}) {})),
        );
      }
    } else if (index == 2) {
      if (nav != null) {
        nav(ScreenType.stationManagement);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => StationManagementContent(onNavigate: (screen, {data}) {})),
        );
      }
    } else if (index == 3 || index == 4) {
      final titles = ['Generate Schedule', 'Reports'];
      final newTitle = titles[index - 3];
      if (newTitle != widget.title) {
        if (nav != null) {
          final screenType = index == 3
              ? ScreenType.autoScheduler
              : ScreenType.reports;
          nav(screenType);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PlaceholderScreen(title: newTitle)),
          );
        }
      }
    } else if (index == 4) {
      if (widget.title != 'Settings') {
        if (nav != null) {
          nav(ScreenType.settings);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PlaceholderScreen(title: 'Settings')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getIndex();

    return Scaffold(
      body: Row(
        children: [
          Sidebar(
            selectedIndex: currentIndex,
            onItemSelected: (index) => _onItemSelected(index, context),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFF8FAFC),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1034A6).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.construction,
                        size: 48,
                        color: const Color(0xFF1034A6).withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1034A6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Coming soon in Phase 2',
                        style: TextStyle(
                          color: Color(0xFF1034A6),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1034A6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}