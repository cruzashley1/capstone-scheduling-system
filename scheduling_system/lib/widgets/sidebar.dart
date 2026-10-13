// widgets/sidebar.dart (Updated with 3 Tools items)
import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../services/notification_center.dart';
import '../services/session.dart';
import 'notification_badge.dart';
import 'workflow_inbox.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF1034A6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo/Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // Raw logo, no backing card.
                Image.asset(
                  'assets/logo/kaizen_logo.png',
                  width: 42,
                  height: 42,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Sched',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // Main Menu
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                _buildMenuHeader('MAIN MENU'),
                _buildMenuItem(
                  index: 0,
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                ),
                _buildMenuItem(
                  index: 1,
                  icon: Icons.people_outline,
                  label: 'Security Management',
                ),
                _buildMenuItem(
                  index: 2,
                  icon: Icons.location_on_outlined,
                  label: 'Station Management',
                ),
                _buildMenuItem(
                  index: 3,
                  icon: Icons.schedule_outlined,
                  label: 'Schedule Management',
                ),

                _buildMenuItem(index: 8, icon: Icons.fact_check_outlined, label: 'Period Approvals'),
                _buildMenuItem(index: 9, icon: Icons.manage_accounts_outlined, label: 'Official Accounts'),
                const WorkflowInboxButton(role: 'admin', color: Colors.white),
                const SizedBox(height: 24),
                _buildMenuHeader('TOOLS'),
                _buildMenuItem(
                  index: 4,
                  // A calendar with a cycle arrow, not a sparkle: this is
                  // a rules-based generator working a recurring bi-weekly
                  // period, and the "AI magic" icon oversold it.
                  icon: Icons.event_repeat_outlined,
                  label: 'Generate Schedule',
                ),
                _buildMenuItem(
                  index: 5,
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  badge: true,
                ),
                _buildMenuItem(
                  index: 6,
                  icon: Icons.bar_chart_outlined,
                  label: 'Reports',
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // Bottom Menu
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildBottomMenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => onItemSelected(7),
                ),
                const SizedBox(height: 8),
                _buildBottomMenuItem(
                  icon: Icons.logout_outlined,
                  label: 'Log Out',
                  onTap: () => _confirmLogout(context),
                  isLogout: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Asks for confirmation, then returns to the login screen, clearing
  // the whole navigation stack so Back can't re-enter the admin panel.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Log Out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        content: Text(
          'You will be returned to the login screen.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              side: BorderSide(color: Colors.grey[300]!),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Log Out',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Forget the persisted session and stop the alert polling — only an
    // explicit Log Out sends the user back to the login screen.
    NotificationCenter.instance.stop();
    await Session.clear();
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthScreen()),
      (route) => false,
    );
  }

  Widget _buildMenuHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Text(
        title,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
    bool badge = false,
  }) {
    final isSelected = selectedIndex == index;
    final Widget iconWidget = Icon(
      icon,
      color: isSelected ? Colors.white : Colors.white70,
      size: 22,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => onItemSelected(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: Colors.white.withOpacity(0.3), width: 1)
                : null,
          ),
          child: Row(
            children: [
              badge ? NotificationBadge(child: iconWidget) : iconWidget,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isLogout ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isLogout ? Colors.red[300] : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: isLogout ? Colors.red[300] : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}