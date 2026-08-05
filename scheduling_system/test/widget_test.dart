// Basic smoke test: the app builds and shows the Sched login screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling_system/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SchedulingSystemApp());

    // The login form should be on screen.
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
