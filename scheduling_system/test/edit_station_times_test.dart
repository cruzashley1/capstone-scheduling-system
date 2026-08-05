// Renders Edit Station and checks the duty-window column: the ladder's
// times appear beside each post, adding a post re-staggers the ones after
// it, tapping a time offers the windows the shift already runs rather
// than a clock, the 9-hour rule is enforced, and the row doesn't overflow
// at the dialog's width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/post_time.dart';
import 'package:scheduling_system/models/station.dart';
import 'package:scheduling_system/screens/add_station_dialog.dart';

Station stationWith(List<String> morningPosts) => Station(
      id: 'STA001',
      name: 'Monumento',
      requiredEmployees: morningPosts.length,
      requiredMorning: morningPosts.length,
      morningPosts: morningPosts,
    );

Future<void> pumpDialog(WidgetTester tester, Station station) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AddStationDialog(station: station)),
  ));
  await tester.pump();
}

/// A slot's time chip showing [range].
///
/// Scoped by the chip's own text style, because the shift card's header
/// prints that shift's base window in the same words — matching on the
/// string alone would count the header as a slot.
Finder timeChip(String range) => find.byWidgetPredicate(
      (w) => w is Text && w.data == range && w.style?.fontSize == 11.5,
      description: 'time chip "$range"',
    );

/// One offered window inside the duty-window picker, scoped by its own
/// text style for the same reason [timeChip] is.
Finder windowOption(String range) => find.byWidgetPredicate(
      (w) => w is Text && w.data == range && w.style?.fontSize == 14,
      description: 'window option "$range"',
    );

/// Opens the duty-window picker on the slot currently showing [range].
Future<void> tapTimeChip(WidgetTester tester, String range) async {
  await tester.tap(timeChip(range));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each post shows its staggered window', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      stationWith([kHeadGuardPost, 'SW Platform', 'SE Platform', 'Roving']),
    );

    // The head guard's fixed 12-hour duty, then the two base-window posts,
    // then the first rung of the ladder.
    expect(timeChip('0500H - 1700H'), findsOneWidget);
    expect(timeChip('0500H - 1400H'), findsNWidgets(2));
    expect(timeChip('0700H - 1600H'), findsOneWidget);
  });

  testWidgets('adding a post fills the open rung before climbing',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      stationWith([kHeadGuardPost, 'SW Platform', 'SE Platform', 'Roving']),
    );
    expect(timeChip('0700H - 1600H'), findsOneWidget);

    // 'Add Post' appears once per shift card; the morning card is first.
    await tester.tap(find.text('Add Post').first);
    await tester.pump();

    // The new post pairs with the one already on 0700H rather than
    // starting a rung of its own.
    expect(timeChip('0700H - 1600H'), findsNWidgets(2));
    expect(timeChip('0900H - 1800H'), findsNothing);

    // Only once that rung is full does the ladder climb.
    await tester.tap(find.text('Add Post').first);
    await tester.pump();

    expect(timeChip('0900H - 1800H'), findsOneWidget);
    // The posts already on the ladder didn't move.
    expect(timeChip('0500H - 1400H'), findsNWidgets(2));
    expect(timeChip('0700H - 1600H'), findsNWidgets(2));
  });

  testWidgets('night posts are not staggered', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      Station(
        id: 'STA001',
        name: 'Monumento',
        requiredEmployees: 3,
        requiredNight: 3,
        nightPosts: [kHeadGuardPost, 'Roving', 'Roving'],
      ),
    );

    expect(timeChip('1700H - 0500H'), findsOneWidget); // HG Night, fixed
    expect(timeChip('2100H - 0600H'), findsNWidgets(2)); // both on the base
  });

  testWidgets('a long ladder warns that posts run into the next shift',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      stationWith([
        kHeadGuardPost,
        'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K',
      ]),
    );

    expect(timeChip('1500H - 0000H'), findsOneWidget);
    expect(
      find.textContaining('start after the afternoon shift'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a time offers the windows the shift already runs',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      stationWith([kHeadGuardPost, 'SW Platform', 'SE Platform', 'Roving']),
    );

    await tapTimeChip(tester, '0700H - 1600H');

    // The shift's two live windows, one tap each — and the clock is
    // behind "Add time…" rather than being the only way in.
    expect(windowOption('0500H - 1400H'), findsOneWidget);
    expect(windowOption('0700H - 1600H'), findsOneWidget);
    expect(find.text('Add time…'), findsOneWidget);
    // The head guard's 12-hour duty is not on offer for a regular post.
    expect(windowOption('0500H - 1700H'), findsNothing);
  });

  testWidgets('picking an offered window moves the post onto it',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      stationWith([kHeadGuardPost, 'SW Platform', 'SE Platform', 'Roving']),
    );

    await tapTimeChip(tester, '0700H - 1600H');
    await tester.tap(windowOption('0500H - 1400H'));
    await tester.pumpAndSettle();

    expect(timeChip('0500H - 1400H'), findsNWidgets(3));
    expect(timeChip('0700H - 1600H'), findsNothing);
  });

  testWidgets('a post shorter than the standard duty is flagged and blocks '
      'the save', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Only a station saved before the 9-hour rule can look like this —
    // the picker refuses to create one.
    await pumpDialog(
      tester,
      Station(
        id: 'STA001',
        name: 'Monumento',
        requiredEmployees: 3,
        requiredMorning: 3,
        morningPosts: [kHeadGuardPost, 'SW Platform', 'SE Platform'],
        morningPostTimes: const [
          PostTime(start: 5 * 60, end: 17 * 60),
          PostTime(start: 5 * 60, end: 14 * 60),
          PostTime(start: 5 * 60, end: 11 * 60, auto: false), // 6 hrs
        ],
      ),
    );

    expect(timeChip('0500H - 1100H'), findsOneWidget);
    expect(find.textContaining('run less than 9 hrs'), findsOneWidget);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();

    expect(
      find.textContaining('a post is manned for less than 9 hrs'),
      findsOneWidget,
    );
  });

  testWidgets('a post longer than the standard duty is warned about',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      Station(
        id: 'STA001',
        name: 'Monumento',
        requiredEmployees: 3,
        requiredMorning: 3,
        morningPosts: [kHeadGuardPost, 'SW Platform', 'SE Platform'],
        morningPostTimes: const [
          PostTime(start: 5 * 60, end: 17 * 60),
          PostTime(start: 5 * 60, end: 14 * 60),
          PostTime(start: 5 * 60, end: 16 * 60, auto: false), // 11 hrs
        ],
      ),
    );

    expect(find.textContaining('run longer than 9 hrs'), findsOneWidget);
    // A warning, not an error — the head guard's own 12-hour duty sits
    // beside it untouched.
    expect(timeChip('0500H - 1700H'), findsOneWidget);
  });

  testWidgets('post rows do not overflow at the dialog width',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      stationWith([
        kHeadGuardPost,
        'A Very Long Post Name That Should Ellipsize',
        'B',
        'C',
        'D',
      ]),
    );

    // takeException() drains what the framework already recorded, so the
    // overflow surfaces here rather than failing the test from the
    // outside — and this runs under the test font, whose glyphs are
    // square and far wider than the real one, so passing here means the
    // row has real headroom.
    expect(tester.takeException(), isNull);
  });
}
