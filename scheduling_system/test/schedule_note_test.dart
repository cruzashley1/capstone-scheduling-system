// Covers the two things the post-generation notes panel rests on:
// grouping/ranking (what the admin sees first, and how many things the
// headline claims need doing), and the padded ladder the Shift Times
// card renders.
//
// The categories and severities are the Dart half of a contract with
// backend_python/schedule_notes.py — the strings below are the wire
// values the generator sends, so a rename on either side fails here.
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/post_time.dart';
import 'package:scheduling_system/models/schedule_note.dart';
import 'package:scheduling_system/models/station.dart';

ScheduleNote note(String category, String severity, {String fix = ''}) =>
    ScheduleNote.fromJson({
      'category': category,
      'severity': severity,
      'subject': 'Ayala — Morning',
      'problem': 'something happened',
      'fix': fix,
    });

void main() {
  group('Note parsing', () {
    test('reads the wire form the generator sends', () {
      final parsed = ScheduleNote.fromJson({
        'category': 'headGuard',
        'severity': 'blocker',
        'subject': 'Monumento — Night',
        'problem': 'The Head Guard post is unmanned.',
        'fix': 'Assign a head guard to Monumento.',
        'station': 'Monumento',
      });

      expect(parsed.category, NoteCategory.headGuard);
      expect(parsed.severity, NoteSeverity.blocker);
      expect(parsed.station, 'Monumento');
      expect(parsed.text,
          'Monumento — Night: The Head Guard post is unmanned. '
          'Assign a head guard to Monumento.');
    });

    test('an unknown category is still shown, never dropped', () {
      final parsed = ScheduleNote.fromJson({
        'category': 'somethingNewer',
        'severity': 'warning',
        'subject': 'X',
        'problem': 'y',
      });
      expect(parsed.category, NoteCategory.staffing);
    });

    test('a legacy one-liner survives as a plain warning', () {
      final parsed = ScheduleNote.fromLegacyText('Ayala: 2 posts unmanned.');
      expect(parsed.problem, 'Ayala: 2 posts unmanned.');
      expect(parsed.severity, NoteSeverity.warning);
      expect(parsed.text, 'Ayala: 2 posts unmanned.');
    });
  });

  group('Grouping and ranking', () {
    test('sections come worst-first, and so do the notes inside them', () {
      final sections = groupNotes([
        note('rotation', 'info'),
        note('cover', 'warning'),
        note('staffing', 'info'),
        note('staffing', 'blocker'),
      ]);

      expect(sections.map((s) => s.category), [
        NoteCategory.staffing, // has the blocker
        NoteCategory.cover, // has a warning
        NoteCategory.rotation, // info only
      ]);
      // Within Station Staffing the blocker leads, not the info note.
      expect(sections.first.notes.first.severity, NoteSeverity.blocker);
      expect(sections.first.severity, NoteSeverity.blocker);
    });

    test('the headline counts only what needs doing', () {
      // The whole point of the split: seven rotation stat lines are not
      // seven problems, and the old box presented them as if they were.
      final notes = [
        for (var i = 0; i < 7; i++) note('rotation', 'info'),
        note('staffing', 'warning'),
        note('headGuard', 'blocker'),
      ];
      expect(notes.length, 9);
      expect(actionableCount(notes), 2);
    });

    test('a run with nothing to fix reports zero', () {
      expect(actionableCount([note('rotation', 'info')]), 0);
    });
  });

  group('Shift Times card — the windows it renders', () {
    // The card pads a shift's posts out to the station's required number
    // before running the ladder, because the generator does the same:
    // a guard on a slot nobody named still gets a window and a time to
    // report at (station_posts.regular_windows), they just come out on
    // an Undefined post.
    List<String> renderedRanges(Station station, String shift) {
      final named = station.postsFor(shift);
      final required = station.requiredFor(shift);
      final posts = [
        ...named,
        if (required > named.length)
          ...List.filled(required - named.length, ''),
      ];
      return normalizePostTimes(shift, posts, station.rawPostTimesFor(shift))
          .map((t) => t.range)
          .toList();
    }

    final station = Station.fromJson({
      'id': 'S1',
      'name': 'Ayala',
      'requiredEmployees': 6,
      'requiredMorning': 6,
      'requiredAfternoon': 0,
      'requiredNight': 3,
      'posts': {
        // Two slots short of the six the station asks for.
        'morning': [kHeadGuardPost, 'SW Platform', 'SE Platform', 'Roving'],
        'afternoon': <String>[],
        'night': [kHeadGuardPost, 'Roving', 'Roving'],
      },
    });

    test('unnamed slots keep climbing the ladder', () {
      expect(renderedRanges(station, 'morning'), [
        '0500H - 1700H', // head guard, fixed 12h, off the ladder
        '0500H - 1400H',
        '0500H - 1400H',
        '0700H - 1600H',
        '0700H - 1600H', // unnamed, still on the rung
        '0900H - 1800H', // unnamed, next rung up
      ]);
      expect(station.unnamedPosts('morning'), 2);
    });

    test('night does not stagger', () {
      expect(renderedRanges(station, 'night'), [
        '1700H - 0500H', // HG Night's fixed 12h duty
        '2100H - 0600H',
        '2100H - 0600H',
      ]);
    });

    test('the base windows are the real ones, not the old hardcoded text',
        () {
      // The card used to claim Afternoon 1400H-2330H (9.5 hrs) and Night
      // 2100H-0500H (8 hrs). Both were wrong; these are what the
      // generator actually stamps.
      expect(baseShiftWindow('Morning')!.range, '0500H - 1400H');
      expect(baseShiftWindow('Morning')!.duration, '9 hrs');
      expect(baseShiftWindow('Afternoon')!.range, '1400H - 2300H');
      expect(baseShiftWindow('Afternoon')!.duration, '9 hrs');
      expect(baseShiftWindow('Night')!.range, '2100H - 0600H');
      expect(baseShiftWindow('Night')!.duration, '9 hrs');
    });
  });
}
