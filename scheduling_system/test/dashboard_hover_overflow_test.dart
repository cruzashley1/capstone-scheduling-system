import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling_system/screens/dashboard_screen.dart';

// Regression test: hovering a dashboard summary card repeatedly used to
// throw "Duplicate keys found" from the icon AnimatedSwitcher (only two
// keys existed, so fast re-entry collided an exiting child with the
// entering one), which surfaced as an overflow warning on the card and
// eventually corrupted the element tree.
void main() {
  Future<void> pumpDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DashboardContent(onNavigate: (_, {data}) {})),
    ));
    // Let the backend fetches fail (no server in tests) and the entrance
    // animations finish.
    await tester.pumpAndSettle();
  }

  Future<void> hoverRepeatedly(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await gesture.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
  }

  testWidgets('hover on Employees Availability card - wide window (4 columns)',
      (tester) async {
    await pumpDashboard(tester, const Size(1440, 900));
    await hoverRepeatedly(tester, find.text('Employees Availability'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover on Employees Availability card - narrow window (2 columns)',
      (tester) async {
    await pumpDashboard(tester, const Size(900, 700));
    await hoverRepeatedly(tester, find.text('Employees Availability'));
    expect(tester.takeException(), isNull);
  });
}
