// models/station.dart

import 'post_time.dart';

/// The post the station's fixed head guards man. It occupies the first
/// slot of the Morning and Night post lists and is never editable: every
/// station has exactly two head guards on 12-hour duties (day HG covers
/// morning through most of the afternoon, night HG covers the night), so
/// the Afternoon list deliberately has no Head Guard slot at all.
const String kHeadGuardPost = 'Head Guard';

/// Posts offered as suggestions in Edit Station. Free text is still
/// accepted — this is a starting list, not a whitelist.
const List<String> kPostCatalog = <String>[
  kHeadGuardPost,
  'Ladder',
  'Roving',
  'SE Platform',
  'SW Platform',
];

class Station {
  final String id;
  final String name;

  // Total required posts per day (= morning + afternoon + night).
  // Kept as a stored field so the older screens that show one headline
  // number keep working; the backend recomputes it from the three shift
  // numbers on every save.
  final int requiredEmployees;

  // Per-shift required headcount. These INCLUDE the head guard slot:
  // Morning 7 means the day head guard plus 6 other posts, Night 3 means
  // the night head guard plus 2 roving posts. Afternoon has no head
  // guard of its own — the day HG's 12-hour duty covers it.
  // 0 means the breakdown hasn't been set on this station yet.
  final int requiredMorning;
  final int requiredAfternoon;
  final int requiredNight;

  // One entry per slot, in the order the generator hands them out, so
  // the list length matches the shift's required number. Morning and
  // Night start with [kHeadGuardPost]. An empty string is a slot the
  // admin hasn't named yet — it generates as "Undefined" and blocks
  // publishing until assigned, which is what the Edit Station warning
  // is telling you about.
  final List<String> morningPosts;
  final List<String> afternoonPosts;
  final List<String> nightPosts;

  // The duty window each of those slots is manned for, aligned by index.
  // Handed out by the stagger ladder in post_time.dart: regular posts
  // come in pairs — two on the shift's base window, the next two two
  // hours later — unless the admin pinned one by hand.
  // Empty on stations saved before posts carried times — postTimesFor()
  // falls back to computing the ladder, so they read the same either way.
  final List<PostTime> morningPostTimes;
  final List<PostTime> afternoonPostTimes;
  final List<PostTime> nightPostTimes;

  final bool isActive;

  Station({
    required this.id,
    required this.name,
    required this.requiredEmployees,
    this.requiredMorning = 0,
    this.requiredAfternoon = 0,
    this.requiredNight = 0,
    this.morningPosts = const <String>[],
    this.afternoonPosts = const <String>[],
    this.nightPosts = const <String>[],
    this.morningPostTimes = const <PostTime>[],
    this.afternoonPostTimes = const <PostTime>[],
    this.nightPostTimes = const <PostTime>[],
    this.isActive = true,
  });

  bool get hasShiftBreakdown =>
      requiredMorning + requiredAfternoon + requiredNight > 0;

  int requiredFor(String shift) {
    switch (shift) {
      case 'morning':
        return requiredMorning;
      case 'afternoon':
        return requiredAfternoon;
      case 'night':
        return requiredNight;
      default:
        return 0;
    }
  }

  List<String> postsFor(String shift) {
    switch (shift) {
      case 'morning':
        return morningPosts;
      case 'afternoon':
        return afternoonPosts;
      case 'night':
        return nightPosts;
      default:
        return const <String>[];
    }
  }

  List<PostTime> rawPostTimesFor(String shift) {
    switch (shift) {
      case 'morning':
        return morningPostTimes;
      case 'afternoon':
        return afternoonPostTimes;
      case 'night':
        return nightPostTimes;
      default:
        return const <PostTime>[];
    }
  }

  /// The duty window for each of a shift's slots, always one per post.
  ///
  /// Runs whatever was stored back through the ladder, so a station saved
  /// before posts had times — or one whose stored list has drifted out of
  /// step with its posts — still reads a sensible window per slot.
  List<PostTime> postTimesFor(String shift) => normalizePostTimes(
        shift,
        postsFor(shift),
        rawPostTimesFor(shift),
      );

  /// How many of a shift's slots still have no post name on them.
  int unnamedPosts(String shift) {
    final posts = postsFor(shift);
    final missing = requiredFor(shift) - posts.length;
    return posts.where((p) => p.isEmpty).length + (missing > 0 ? missing : 0);
  }

  /// Shifts with at least one unnamed slot — the gap the Edit Station
  /// warning and the generator's Undefined posts both come from.
  List<String> get shiftsMissingPosts => <String>[
        for (final shift in const ['morning', 'afternoon', 'night'])
          if (unnamedPosts(shift) > 0) shift,
      ];

  // Empty entries are kept: they mark an unnamed slot, and dropping them
  // would shift every post after it onto the wrong guard.
  static List<String> _posts(Map<String, dynamic>? posts, String key) {
    final raw = posts?[key];
    if (raw is! List) return const <String>[];
    return raw.map((p) => p.toString().trim()).toList();
  }

  // Unreadable entries come through as null so normalizePostTimes puts
  // that slot back on the ladder rather than dropping it and shifting
  // every window after it onto the wrong post.
  static List<PostTime?> _postTimes(Map<String, dynamic>? times, String key) {
    final raw = times?[key];
    if (raw is! List) return const <PostTime?>[];
    return raw
        .map((t) => t is Map
            ? PostTime.fromJson(Map<String, dynamic>.from(t))
            : null)
        .toList();
  }

  factory Station.fromJson(Map<String, dynamic> json) {
    final posts = json['posts'] is Map
        ? Map<String, dynamic>.from(json['posts'] as Map)
        : null;
    final postTimes = json['postTimes'] is Map
        ? Map<String, dynamic>.from(json['postTimes'] as Map)
        : null;

    final morningPosts = _posts(posts, 'morning');
    final afternoonPosts = _posts(posts, 'afternoon');
    final nightPosts = _posts(posts, 'night');

    return Station(
      id: json['id'] as String,
      name: json['name'] as String,
      requiredEmployees: (json['requiredEmployees'] as num?)?.toInt() ?? 0,
      requiredMorning: (json['requiredMorning'] as num?)?.toInt() ?? 0,
      requiredAfternoon: (json['requiredAfternoon'] as num?)?.toInt() ?? 0,
      requiredNight: (json['requiredNight'] as num?)?.toInt() ?? 0,
      morningPosts: morningPosts,
      afternoonPosts: afternoonPosts,
      nightPosts: nightPosts,
      // Normalized on the way in, so every reader gets one window per
      // post whether or not this station has ever been timed.
      morningPostTimes: normalizePostTimes(
          'morning', morningPosts, _postTimes(postTimes, 'morning')),
      afternoonPostTimes: normalizePostTimes(
          'afternoon', afternoonPosts, _postTimes(postTimes, 'afternoon')),
      nightPostTimes: normalizePostTimes(
          'night', nightPosts, _postTimes(postTimes, 'night')),
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'requiredEmployees': requiredEmployees,
      'requiredMorning': requiredMorning,
      'requiredAfternoon': requiredAfternoon,
      'requiredNight': requiredNight,
      'posts': {
        'morning': morningPosts,
        'afternoon': afternoonPosts,
        'night': nightPosts,
      },
      'postTimes': {
        'morning': morningPostTimes.map((t) => t.toJson()).toList(),
        'afternoon': afternoonPostTimes.map((t) => t.toJson()).toList(),
        'night': nightPostTimes.map((t) => t.toJson()).toList(),
      },
      'isActive': isActive,
    };
  }
}
