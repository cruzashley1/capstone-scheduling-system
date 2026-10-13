// Regression guard for the "switching screens explodes" bug: navigating
// between admin screens must not raise layout (RenderFlex overflow) errors
// at any supported window size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/screens/main_layout.dart';

void main() {
  for (final size in const [
    Size(1920, 1080),
    Size(1600, 900),
    Size(1440, 900),
    Size(1366, 768),
    Size(1280, 720),
    Size(1152, 720),
    Size(1024, 640),
  ]) {
    testWidgets('no layout errors navigating at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final originalErrorHandler = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d);
      addTearDown(() => FlutterError.onError = originalErrorHandler);

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: MainLayout()));
      await tester.pump(const Duration(seconds: 1));

      Future<void> tap(String label) async {
        final before = errors.length;
        final finder = find.text(label);
        if (finder.evaluate().isEmpty) return;
        await tester.ensureVisible(finder.first);
        await tester.pump();
        await tester.tap(finder.first);
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(seconds: 1));
        for (final d in errors.sublist(before)) {
          final creator = (d.informationCollector?.call() ?? [])
              .map((n) => n.toStringDeep().split('\n').first)
              .firstWhere((s) => s.startsWith('debugCreator'),
                  orElse: () => '');
          // ignore: avoid_print
          print('!!! ${size.width.toInt()}w "$label": '
              '${d.exceptionAsString()}\n    $creator');
        }
      }

      for (var round = 0; round < 2; round++) {
        await tap('Station Management');
        await tap('Dashboard');
        await tap('Security Management');
        await tap('Dashboard');
        await tap('Schedule Management');
        await tap('Period Approvals');
        await tap('Generate Schedule');
        await tap('Notifications');
        await tap('Approval Alerts');
        await tap('Reports');
        await tap('Settings');
        await tap('Company Info');
        await tap('Dashboard');
      }

      FlutterError.onError = originalErrorHandler;
      expect(errors, isEmpty,
          reason: '${errors.length} layout errors at $size');
    });
  }
}
