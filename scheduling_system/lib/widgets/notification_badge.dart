// widgets/notification_badge.dart
//
// Red unread-count badge overlaid on a nav icon. Listens to the
// NotificationCenter's live unread count and to the Allow Notifications
// preference (badge hides while notifications are muted), so every
// layout — admin sidebar, head guard and guard bottom bars — shows the
// same indicator without wiring its own state.
import 'package:flutter/material.dart';
import '../services/notification_center.dart';
import '../services/notification_settings.dart';

class NotificationBadge extends StatelessWidget {
  final Widget child;

  const NotificationBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        NotificationCenter.instance.unreadCount,
        NotificationSettings.allowNotifications,
      ]),
      builder: (context, _) {
        final count = NotificationSettings.allowNotifications.value
            ? NotificationCenter.instance.unreadCount.value
            : 0;
        if (count == 0) return child;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              right: -8,
              top: -6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
