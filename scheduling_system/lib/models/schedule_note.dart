// models/schedule_note.dart
//
// One thing the generator had to bend to produce a roster, as the admin
// reads it. The Dart mirror of backend_python/schedule_notes.py.
//
// WHY THIS EXISTS
//
// Generation never refuses over a staffing problem — it builds the best
// roster the setup allows and files a note about every compromise. These
// notes are the ONLY record of those compromises: a post nobody was
// assigned to, a station with no head guard, a day off no reliever was
// free for. The schedule publishes with those holes in it if nobody
// reads them.
//
// They used to arrive as a flat list of paragraph-long sentences, shown
// under a single "Station Rotation" heading whatever they were about.
// Each one now says which heading it belongs under, how loud it is, and
// splits into the three parts a reader actually wants:
//
//   subject  what it concerns — "Ayala — Morning", or a guard's name
//   problem  what happened
//   fix      what to do about it (empty when nothing is owed)

import 'package:flutter/material.dart';

/// How loudly a note is saying it. Ordered worst-first, which is also
/// the order the sections and the notes inside them are sorted in.
enum NoteSeverity { blocker, warning, info }

/// Which section a note is filed under. Each one corresponds to a
/// different place the fix lives, which is the whole point of the split.
enum NoteCategory { staffing, headGuard, cover, assignment, leave, request, rotation }

extension NoteCategoryDisplay on NoteCategory {
  String get title {
    switch (this) {
      case NoteCategory.staffing:
        return 'Station Staffing';
      case NoteCategory.headGuard:
        return 'Head Guards';
      case NoteCategory.cover:
        return 'Reliever Cover';
      case NoteCategory.assignment:
        return 'Special Assignments';
      case NoteCategory.leave:
        return 'Leave';
      case NoteCategory.request:
        return 'Day-off Requests';
      case NoteCategory.rotation:
        return 'Station Rotation';
    }
  }

  /// One line saying what this section is about, so the admin knows
  /// whether it's worth opening before they open it.
  String get blurb {
    switch (this) {
      case NoteCategory.staffing:
        return 'Stations whose set-up and assigned guards don\'t match';
      case NoteCategory.headGuard:
        return 'Stations whose Head Guard post needed attention';
      case NoteCategory.cover:
        return 'Day-offs and the relievers standing in for them';
      case NoteCategory.assignment:
        return 'What the admin pins did to the roster';
      case NoteCategory.leave:
        return 'Approved and pending leave falling in this period';
      case NoteCategory.request:
        return 'Special day-off requests still awaiting a decision';
      case NoteCategory.rotation:
        return 'What the monthly station rotation did this cycle';
    }
  }

  IconData get icon {
    switch (this) {
      case NoteCategory.staffing:
        return Icons.groups_outlined;
      case NoteCategory.headGuard:
        return Icons.shield_outlined;
      case NoteCategory.cover:
        return Icons.swap_horiz;
      case NoteCategory.assignment:
        return Icons.push_pin_outlined;
      case NoteCategory.leave:
        return Icons.event_busy_outlined;
      case NoteCategory.request:
        return Icons.pending_actions_outlined;
      case NoteCategory.rotation:
        return Icons.event_repeat_outlined;
    }
  }
}

extension NoteSeverityDisplay on NoteSeverity {
  /// What the admin is being asked to do about a note of this loudness.
  String get label {
    switch (this) {
      case NoteSeverity.blocker:
        return 'Fix before publishing';
      case NoteSeverity.warning:
        return 'Needs a look';
      case NoteSeverity.info:
        return 'For information';
    }
  }

  Color get color {
    switch (this) {
      case NoteSeverity.blocker:
        return const Color(0xFFDC2626);
      case NoteSeverity.warning:
        return const Color(0xFFD97706);
      case NoteSeverity.info:
        return const Color(0xFF0369A1);
    }
  }

  Color get background {
    switch (this) {
      case NoteSeverity.blocker:
        return const Color(0xFFFEF2F2);
      case NoteSeverity.warning:
        return const Color(0xFFFEF3C7);
      case NoteSeverity.info:
        return const Color(0xFFEFF6FF);
    }
  }

  IconData get icon {
    switch (this) {
      case NoteSeverity.blocker:
        return Icons.report_problem_outlined;
      case NoteSeverity.warning:
        return Icons.warning_amber_rounded;
      case NoteSeverity.info:
        return Icons.info_outline;
    }
  }
}

class ScheduleNote {
  final NoteCategory category;
  final NoteSeverity severity;
  final String subject;
  final String problem;
  final String fix;

  /// The station this concerns, when it concerns one. Null on notes
  /// about a person or about the group as a whole.
  final String? station;

  const ScheduleNote({
    required this.category,
    required this.severity,
    required this.subject,
    required this.problem,
    this.fix = '',
    this.station,
  });

  static const Map<String, NoteCategory> _categories = {
    'staffing': NoteCategory.staffing,
    'headGuard': NoteCategory.headGuard,
    'cover': NoteCategory.cover,
    'assignment': NoteCategory.assignment,
    'leave': NoteCategory.leave,
    'request': NoteCategory.request,
    'rotation': NoteCategory.rotation,
  };

  static const Map<String, NoteSeverity> _severities = {
    'blocker': NoteSeverity.blocker,
    'warning': NoteSeverity.warning,
    'info': NoteSeverity.info,
  };

  factory ScheduleNote.fromJson(Map<String, dynamic> json) {
    return ScheduleNote(
      // An unrecognized category from a newer backend is still worth
      // showing — it lands under Station Staffing rather than vanishing.
      category: _categories[json['category']?.toString()] ??
          NoteCategory.staffing,
      severity: _severities[json['severity']?.toString()] ??
          NoteSeverity.warning,
      subject: json['subject']?.toString() ?? '',
      problem: json['problem']?.toString() ?? '',
      fix: json['fix']?.toString() ?? '',
      station: (json['station'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['station'].toString().trim(),
    );
  }

  /// A note rebuilt from the old flat one-liner, for schedules generated
  /// before notes carried structure. Nothing can be recovered from the
  /// string but the text itself, so it files as an unsorted warning
  /// rather than pretending to know more than it does.
  factory ScheduleNote.fromLegacyText(String text) => ScheduleNote(
        category: NoteCategory.staffing,
        severity: NoteSeverity.warning,
        subject: '',
        problem: text,
      );

  /// The whole note on one line — for tooltips and copy-out.
  String get text {
    final head = subject.isEmpty ? problem : '$subject: $problem';
    return fix.isEmpty ? head : '$head $fix';
  }
}

/// The notes of one category, ready to render as a section.
class NoteSection {
  final NoteCategory category;
  final List<ScheduleNote> notes;

  const NoteSection(this.category, this.notes);

  /// The loudest severity in the section — what the header is coloured
  /// by, and what decides whether it opens collapsed.
  NoteSeverity get severity => notes
      .map((n) => n.severity)
      .reduce((a, b) => a.index <= b.index ? a : b);
}

/// Splits a run's notes into sections, worst first, with each section's
/// own notes worst first too. Categories with nothing in them are gone
/// entirely rather than showing as empty.
List<NoteSection> groupNotes(List<ScheduleNote> notes) {
  final byCategory = <NoteCategory, List<ScheduleNote>>{};
  for (final note in notes) {
    byCategory.putIfAbsent(note.category, () => []).add(note);
  }

  final sections = byCategory.entries
      .map((e) => NoteSection(
            e.key,
            [...e.value]..sort((a, b) => a.severity.index - b.severity.index),
          ))
      .toList();

  // Worst section first; ties keep the enum's own order so the sections
  // don't reshuffle between runs that are equally clean.
  sections.sort((a, b) {
    final bySeverity = a.severity.index - b.severity.index;
    return bySeverity != 0
        ? bySeverity
        : a.category.index - b.category.index;
  });
  return sections;
}

/// How many notes actually ask the admin to do something. This is the
/// number the headline reports — counting the informational ones would
/// make a clean run look like a problem.
int actionableCount(List<ScheduleNote> notes) =>
    notes.where((n) => n.severity != NoteSeverity.info).length;
