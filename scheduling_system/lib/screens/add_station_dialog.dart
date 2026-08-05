// screens/add_station_dialog.dart
// "Add Station" / "Edit Station" popup form.
//
// A station is configured per shift: Morning, Afternoon and Night each
// carry a required headcount and the named posts that number is made of.
// The slots always equal the required number, so raising Morning to 7
// immediately shows 7 slots — any left unnamed are warned about here and
// generate as "Undefined", which blocks publishing until assigned.
//
// Every slot also carries the duty WINDOW it is manned for, handed out by
// the stagger ladder in models/post_time.dart: regular posts come in
// PAIRS — two on the shift's base window, the next two two hours later,
// and so on — so cover is kept while guards rotate off. Adding or
// removing a post re-staggers the slots below it live.
//
// Tapping a window opens the shift's own list of windows rather than a
// clock: the times already in use in that shift, one tap to reuse. Only
// "Add time…" opens the clock, and it is checked against the 9-hour duty
// — anything shorter is REFUSED (that guard would be underworked and the
// post left bare) and anything longer is WARNED about as overtime. A
// hand-picked window is then pinned, which the ladder leaves alone until
// it's put back on auto. The head guard's fixed 12-hour duty is never on
// the ladder, can't be re-timed, and is outside the 9-hour rule.
//
// Head guard rule, baked into the form: every station has two head guards
// on 12-hour duties, so Morning and Night reserve their first slot for the
// Head Guard (locked, not removable) and the Afternoon has none at all —
// the day head guard is still on duty through the afternoon.
//
// In add mode it submits to the Python API, which generates a sequential
// station ID (e.g. STA001) and saves the station to Firestore. In edit
// mode (a Station is passed in) the form is prefilled and submits an
// update instead. The station name is NOT editable here: employees,
// schedules and pins are joined to a station by name, so renaming is a
// data migration rather than a form field. Either way, on success the
// dialog closes itself and hands the resulting Station back to whoever
// opened it so the caller can refresh its state without a full re-fetch.
import 'package:flutter/material.dart';
import '../models/post_time.dart';
import '../models/station.dart';
import '../services/api_service.dart';

const Color kPrimaryColor = Color(0xFF1034A6);
const Color _kWarnText = Color(0xFFB45309);
const Color _kWarnBg = Color(0xFFFFFBEB);
const Color _kWarnBorder = Color(0xFFFDE68A);
const Color _kErrText = Color(0xFFB91C1C);
const Color _kErrBg = Color(0xFFFEF2F2);
const Color _kErrBorder = Color(0xFFFECACA);
const Color _kMuted = Color(0xFF64748B);

// Sentinel value for the "type your own post" item in the post dropdown.
const String _kCustomPost = '__custom__';

// Fixed width for the duty-window column, so the TIME header sits over
// the chips rather than drifting with each one's content.
const double _kTimeColumnWidth = 124;

/// One shift's editable setup: the required headcount plus one entry per
/// slot. `posts.length` is always kept equal to `required`, and `times`
/// carries one window per post.
class _ShiftSetup {
  final String key; // 'morning' | 'afternoon' | 'night'
  final String label;
  final String note;

  /// Morning and Night reserve slot 0 for the station's head guard.
  final bool hasHeadGuard;

  /// What a newly added slot starts as. Night is head guard + roving by
  /// rule, so its new slots come pre-named; the day shifts start blank
  /// because only the admin knows which post is missing.
  final String defaultPost;

  final TextEditingController requiredController;

  List<String> posts;

  /// One per post, index-aligned. Slots on `auto` are recomputed from the
  /// ladder on every change; hand-pinned ones are carried through as-is.
  List<PostTime> times;

  // Remembers what each slot was named — and any window pinned on it —
  // before the number was lowered, so typing over the number (or clearing
  // it) doesn't lose the setup.
  final List<String> _stash = [];
  final List<PostTime?> _timeStash = [];

  _ShiftSetup({
    required this.key,
    required this.label,
    required this.note,
    required this.hasHeadGuard,
    required this.defaultPost,
    required int required,
    required List<String> initialPosts,
    required List<PostTime> initialTimes,
  })  : requiredController = TextEditingController(text: required.toString()),
        posts = _normalize(initialPosts, required, hasHeadGuard, defaultPost),
        times = const <PostTime>[] {
    // _normalize can insert or drop the head guard slot, so the incoming
    // windows are re-aligned against the posts as they ended up rather
    // than as they arrived.
    times = _retime(_alignTimes(initialPosts, initialTimes, posts));
    _stash.addAll(posts);
    _timeStash.addAll(times.map((t) => t.auto ? null : t));
  }

  factory _ShiftSetup.from(
    Station? station, {
    required String key,
    required String label,
    required String note,
    required bool hasHeadGuard,
    String defaultPost = '',
  }) {
    return _ShiftSetup(
      key: key,
      label: label,
      note: note,
      hasHeadGuard: hasHeadGuard,
      defaultPost: defaultPost,
      required: station?.requiredFor(key) ?? 0,
      initialPosts: station?.postsFor(key) ?? const <String>[],
      initialTimes: station?.postTimesFor(key) ?? const <PostTime>[],
    );
  }

  /// The base window this shift's ladder climbs from, e.g. '0500H - 1400H'.
  String get baseHours {
    final window = kShiftWindows[key]!;
    return formatMilitaryRange(window.$1, window.$2);
  }

  static List<String> _normalize(
    List<String> raw,
    int required,
    bool hasHeadGuard,
    String defaultPost,
  ) {
    if (required <= 0) return <String>[];
    final posts = raw.map((p) => p.trim()).toList()
      ..removeWhere((p) => p == kHeadGuardPost);
    if (hasHeadGuard) posts.insert(0, kHeadGuardPost);
    while (posts.length < required) {
      posts.add(defaultPost);
    }
    return posts.sublist(0, required);
  }

  /// Carries pinned windows across a re-normalization that may have moved
  /// the head guard slot, by matching on the post name's position within
  /// the non-head-guard slots rather than on the raw index.
  static List<PostTime?> _alignTimes(
    List<String> rawPosts,
    List<PostTime> rawTimes,
    List<String> normalized,
  ) {
    final regularTimes = <PostTime>[];
    for (var i = 0; i < rawPosts.length; i++) {
      if (rawPosts[i].trim() == kHeadGuardPost) continue;
      if (i < rawTimes.length) regularTimes.add(rawTimes[i]);
    }
    var cursor = 0;
    return [
      for (final post in normalized)
        if (post == kHeadGuardPost)
          null
        else
          cursor < regularTimes.length ? regularTimes[cursor++] : null,
    ];
  }

  /// Recomputes every `auto` slot from the ladder, keeping pinned ones.
  List<PostTime> _retime(List<PostTime?> stored) =>
      normalizePostTimes(key, posts, stored);

  /// Re-runs the ladder over the current posts. Called after anything
  /// that changes the slot list, which is what makes adding a post pair
  /// it with the open rung, or push the ones after it up one.
  void restagger() {
    times = _retime(times.map((t) => t.auto ? null : t).toList());
  }

  int get required => posts.length;

  int get unnamed => posts.where((p) => p.isEmpty).length;

  /// Slots whose start has climbed into the next shift.
  int get overrunning => _countRegulars((t) => overrunsNextShift(key, t.start));

  /// Slots pinned to less than the standard nine hours. The picker
  /// refuses to create one, so these are only ever stations saved before
  /// the rule existed — flagged so they get fixed.
  int get undertime => _countRegulars((t) => t.isShortDuty);

  /// Slots running longer than the standard nine hours — overtime.
  int get overtime => _countRegulars((t) => t.isLongDuty);

  /// Counts regular (non head guard) slots whose window matches [test].
  int _countRegulars(bool Function(PostTime) test) {
    var count = 0;
    for (var i = 0; i < posts.length && i < times.length; i++) {
      if (isHeadGuardSlot(i)) continue;
      if (test(times[i])) count++;
    }
    return count;
  }

  bool isHeadGuardSlot(int index) => hasHeadGuard && index == 0;

  /// The windows already in use in this shift, which is what the time
  /// picker offers instead of a clock: the shift's own base window plus
  /// whatever its regular slots are currently manned for, deduplicated
  /// and ordered from the base outwards (so the night's midnight wrap
  /// doesn't sort 0600H before 2100H).
  ///
  /// The head guard's 12-hour duty is deliberately left out — it is a
  /// different kind of duty and pinning a regular post onto it would
  /// hand that guard three extra hours.
  List<PostTime> get windowOptions {
    final base = kShiftWindows[key]!;
    final seen = <String>{};
    final options = <PostTime>[];

    void offer(int start, int end) {
      if (seen.add('$start-$end')) {
        options.add(PostTime(start: start, end: end));
      }
    }

    offer(base.$1, base.$2);
    for (var i = 0; i < posts.length && i < times.length; i++) {
      if (isHeadGuardSlot(i)) continue;
      offer(times[i].start, times[i].end);
    }

    int fromBase(PostTime t) => (t.start - base.$1) % kMinutesPerDay;
    options.sort((a, b) => fromBase(a).compareTo(fromBase(b)));
    return options;
  }

  /// How many regular slots are currently manned for [window] — the
  /// "· 2 posts" note beside each option in the picker.
  int slotsOn(PostTime window) => _countRegulars(
      (t) => t.start == window.start && t.end == window.end);

  /// Resizes the slot list to `n`, restoring previously named posts — and
  /// any window pinned on them — when the number goes back up.
  ///
  /// The stash is already in normalized shape (head guard at slot 0 where
  /// the shift has one), so posts and pinned windows both restore on a
  /// plain index and only the ladder has to be re-run.
  void setRequired(int n) {
    for (var i = 0; i < posts.length; i++) {
      final pinned = i < times.length && !times[i].auto ? times[i] : null;
      if (i < _stash.length) {
        _stash[i] = posts[i];
        _timeStash[i] = pinned;
      } else {
        _stash.add(posts[i]);
        _timeStash.add(pinned);
      }
    }
    final target = n.clamp(0, 99);
    posts = _normalize(<String>[
      for (var i = 0; i < target; i++)
        i < _stash.length ? _stash[i] : defaultPost,
    ], target, hasHeadGuard, defaultPost);
    times = _retime(<PostTime?>[
      for (var i = 0; i < posts.length; i++)
        i < _timeStash.length ? _timeStash[i] : null,
    ]);
  }

  void syncRequiredField() {
    final text = required.toString();
    if (requiredController.text != text) requiredController.text = text;
  }

  void dispose() => requiredController.dispose();
}

/// What the duty-window picker handed back.
enum _TimeAction {
  /// Put this slot on a window the shift already uses.
  reuse,

  /// Open the clock and set a window that isn't in the list yet.
  addNew,

  /// Un-pin the slot and let the stagger ladder time it again.
  backToAuto,
}

class _TimeResult {
  final _TimeAction action;

  /// The chosen window — set on [_TimeAction.reuse] only.
  final PostTime? time;

  const _TimeResult(this.action, [this.time]);
}

/// The duty-window picker: the windows this shift already runs, listed
/// for one tap, with the clock tucked behind "Add time…".
///
/// Reading the options off the live [_ShiftSetup] means the list grows as
/// the admin adds windows — pin one post to 0600H and every other post in
/// the shift can be put on 0600H without touching a clock again.
class _TimeOptionsDialog extends StatelessWidget {
  final _ShiftSetup shift;
  final int index;

  const _TimeOptionsDialog({required this.shift, required this.index});

  @override
  Widget build(BuildContext context) {
    final current = shift.times[index];
    final post = shift.posts[index];
    final options = shift.windowOptions;
    final ladder = autoWindow(shift.key, shift.posts, index);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${shift.label} — post ${index + 1}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            post.isEmpty ? 'Unnamed post' : post,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Text(
                  'Times already used in this shift',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _kMuted,
                  ),
                ),
              ),
              for (final option in options)
                _option(
                  context,
                  window: option,
                  selected: option.start == current.start &&
                      option.end == current.end,
                ),
              const Divider(height: 16),
              _action(
                context,
                icon: Icons.more_time,
                label: 'Add time…',
                detail: 'Set a start and end on the clock',
                result: const _TimeResult(_TimeAction.addNew),
              ),
              if (!current.auto)
                _action(
                  context,
                  icon: Icons.auto_mode,
                  label: 'Back to the stagger ladder',
                  detail: 'Follows the shift again — ${ladder.range}',
                  result: const _TimeResult(_TimeAction.backToAuto),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Text(
                  'Every post runs '
                  '${formatDuration(0, kStandardDutyMinutes)}. A shorter '
                  'duty is refused; a longer one is allowed but flagged as '
                  'overtime.',
                  style: const TextStyle(
                      fontSize: 11, color: _kMuted, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// One reusable window: its hours, how long it runs and how many posts
  /// in this shift are already on it.
  Widget _option(
    BuildContext context, {
    required PostTime window,
    required bool selected,
  }) {
    final onIt = shift.slotsOn(window);
    final Color flag = window.isShortDuty
        ? _kErrText
        : window.isLongDuty
            ? _kWarnText
            : _kMuted;

    return InkWell(
      onTap: () => Navigator.pop(
          context, _TimeResult(_TimeAction.reuse, window)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? kPrimaryColor : _kMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    window.range,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? kPrimaryColor : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    '${window.duration} · '
                    '${onIt == 0 ? 'not used yet' : '$onIt post'
                        '${onIt != 1 ? 's' : ''}'}',
                    style: TextStyle(fontSize: 11, color: flag),
                  ),
                ],
              ),
            ),
            if (window.isShortDuty)
              const Icon(Icons.error_outline, size: 16, color: _kErrText)
            else if (window.isLongDuty)
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: _kWarnText),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String detail,
    required _TimeResult result,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, result),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: kPrimaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kPrimaryColor,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 11, color: _kMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddStationDialog extends StatefulWidget {
  // When set, the dialog edits this station instead of creating a new one.
  final Station? station;

  const AddStationDialog({super.key, this.station});

  @override
  State<AddStationDialog> createState() => _AddStationDialogState();
}

class _AddStationDialogState extends State<AddStationDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSubmitting = false;

  late final List<_ShiftSetup> _shifts;

  bool get _isEditing => widget.station != null;

  @override
  void initState() {
    super.initState();
    final station = widget.station;
    _shifts = [
      _ShiftSetup.from(
        station,
        key: 'morning',
        label: 'Morning',
        note: 'Includes the day head guard (12-hour duty, 0500H – 1700H). '
            'Posts come in pairs: the first two start at 0500H, the next '
            'two at 0700H, and so on.',
        hasHeadGuard: true,
      ),
      _ShiftSetup.from(
        station,
        key: 'afternoon',
        label: 'Afternoon',
        note: 'No head guard slot — the day head guard is still on duty '
            'through the afternoon, and the night head guard takes over '
            'from 1700H. Posts come in pairs: the first two start at '
            '1400H, the next two at 1600H, and so on.',
        hasHeadGuard: false,
      ),
      _ShiftSetup.from(
        station,
        key: 'night',
        label: 'Night',
        note: 'Night runs on the night head guard plus roving guards only, '
            'so its posts are not staggered — they all work 2100H – 0600H.',
        hasHeadGuard: true,
        defaultPost: 'Roving',
      ),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final shift in _shifts) {
      shift.dispose();
    }
    super.dispose();
  }

  int get _dailyTotal =>
      _shifts.fold(0, (sum, shift) => sum + shift.required);

  int get _unnamedTotal =>
      _shifts.fold(0, (sum, shift) => sum + shift.unnamed);

  _ShiftSetup _shift(String key) => _shifts.firstWhere((s) => s.key == key);

  Future<void> _handleSubmit() async {
    if (!_isEditing && _nameController.text.trim().isEmpty) {
      _showError('Please enter a station name.');
      return;
    }

    if (_dailyTotal <= 0) {
      _showError('Set the required number for at least one shift.');
      return;
    }

    // The 9-hour floor is a hard rule, so it blocks the save rather than
    // just colouring a chip. Only a station saved before the rule can be
    // in this state — the picker refuses to create it.
    final short = _shifts.where((s) => s.undertime > 0).toList();
    if (short.isNotEmpty) {
      _showError(
        '${short.map((s) => s.label).join(', ')}: a post is manned for less '
        'than ${formatDuration(0, kStandardDutyMinutes)}. Fix those times '
        'before saving.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final morning = _shift('morning');
    final afternoon = _shift('afternoon');
    final night = _shift('night');

    final result = _isEditing
        ? await ApiService.updateStation(
            widget.station!.id,
            requiredMorning: morning.required,
            requiredAfternoon: afternoon.required,
            requiredNight: night.required,
            morningPosts: morning.posts,
            afternoonPosts: afternoon.posts,
            nightPosts: night.posts,
            morningPostTimes: morning.times,
            afternoonPostTimes: afternoon.times,
            nightPostTimes: night.times,
          )
        : await ApiService.createStation(
            name: _nameController.text.trim(),
            requiredMorning: morning.required,
            requiredAfternoon: afternoon.required,
            requiredNight: night.required,
            morningPosts: morning.posts,
            afternoonPosts: afternoon.posts,
            nightPosts: night.posts,
            morningPostTimes: morning.times,
            afternoonPostTimes: afternoon.times,
            nightPostTimes: night.times,
          );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      // Hand the created/updated Station back to whoever opened the dialog.
      Navigator.pop(context, result['station'] as Station);
    } else {
      _showError(result['error'].toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ───────────────────────── post editing ─────────────────────────

  Future<void> _pickPost(_ShiftSetup shift, int index) async {
    final current = shift.posts[index];
    // The head guard's own slot is fixed — the station's two head guards
    // man it, and the schedule refuses to rename a Head Guard post.
    if (shift.isHeadGuardSlot(index)) return;

    final options = <String>[
      for (final post in kPostCatalog)
        if (post != kHeadGuardPost) post,
      if (current.isNotEmpty && !kPostCatalog.contains(current)) current,
    ];

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${shift.label} — post ${index + 1}'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Row(
                children: [
                  Icon(
                    option == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: option == current ? kPrimaryColor : _kMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(option),
                ],
              ),
            ),
          const Divider(height: 1),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _kCustomPost),
            child: const Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: _kMuted),
                SizedBox(width: 10),
                Text('Type another post…'),
              ],
            ),
          ),
          if (current.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Row(
                children: [
                  Icon(Icons.remove_circle_outline, size: 18, color: _kMuted),
                  SizedBox(width: 10),
                  Text('Clear this slot'),
                ],
              ),
            ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == _kCustomPost) {
      final typed = await _promptCustomPost(current);
      if (typed == null || !mounted) return;
      setState(() => shift.posts[index] = typed.trim());
      return;
    }

    setState(() => shift.posts[index] = choice);
  }

  Future<String?> _promptCustomPost(String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: _inputDecoration('e.g. Concourse'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _addPost(_ShiftSetup shift) {
    setState(() {
      shift.setRequired(shift.required + 1);
      shift.syncRequiredField();
    });
  }

  void _removePost(_ShiftSetup shift, int index) {
    setState(() {
      shift.posts.removeAt(index);
      shift.times.removeAt(index);
      shift._stash
        ..clear()
        ..addAll(shift.posts);
      shift._timeStash
        ..clear()
        ..addAll(shift.times.map((t) => t.auto ? null : t));
      // Closing the gap moves every slot below up a rung on the ladder.
      shift.restagger();
      shift.syncRequiredField();
    });
  }

  // ───────────────────────── time editing ─────────────────────────

  /// Opens the shift's list of duty windows for one slot.
  ///
  /// Setting a time by clock for every post is a chore when a station
  /// only ever runs three or four windows, so this offers the ones the
  /// shift already uses — one tap to put this post on the same hours as
  /// its neighbours. "Add time…" is the way to a clock, and only that
  /// path can introduce a window nobody is on yet.
  Future<void> _pickTime(_ShiftSetup shift, int index) async {
    // The head guard's 12-hour duty is fixed; nothing to pick.
    if (shift.isHeadGuardSlot(index)) return;

    final result = await showDialog<_TimeResult>(
      context: context,
      builder: (context) => _TimeOptionsDialog(shift: shift, index: index),
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case _TimeAction.backToAuto:
        _resetTime(shift, index);
        return;
      case _TimeAction.reuse:
        _applyTime(shift, index, result.time!);
        return;
      case _TimeAction.addNew:
        final picked = await _promptNewTime(shift, index);
        if (picked == null || !mounted) return;
        _applyTime(shift, index, picked);
        return;
    }
  }

  /// Puts [window] on a slot, enforcing the 9-hour rule.
  ///
  /// Under nine hours is refused outright — the ladder's whole promise is
  /// that every post is the same length, and a short duty leaves the post
  /// bare for the rest of the shift. Over nine is allowed but called out,
  /// because that's overtime somebody has to sign off on.
  void _applyTime(_ShiftSetup shift, int index, PostTime window) {
    if (window.isShortDuty) {
      _showError(
        '${window.range} is only ${window.duration} — a post must be at '
        'least ${formatDuration(0, kStandardDutyMinutes)}. Nothing changed.',
      );
      return;
    }

    setState(() {
      // A window that matches what the ladder would hand this slot anyway
      // is left on auto, so it keeps re-staggering with the shift instead
      // of being pinned for no reason.
      final auto = autoWindow(shift.key, shift.posts, index);
      final matchesLadder =
          window.start == auto.start && window.end == auto.end;
      shift.times[index] = window.copyWith(auto: matchesLadder);
    });

    if (window.isLongDuty) {
      _showWarning(
        'Post ${index + 1} is now ${window.duration} — longer than the '
        'standard ${formatDuration(0, kStandardDutyMinutes)} duty. That '
        'guard works overtime.',
      );
    }
  }

  /// The clock path: time in, then time out, each labelled for which end
  /// of the duty it is setting. The end picker opens on a full standard
  /// duty after the chosen start, so the usual answer is one confirm.
  Future<PostTime?> _promptNewTime(_ShiftSetup shift, int index) async {
    final current = shift.times[index];

    final start = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: current.start ~/ 60, minute: current.start % 60),
      helpText: 'START TIME — ${shift.label} post ${index + 1}',
      confirmText: 'NEXT',
      builder: _timePickerTheme,
    );
    if (start == null || !mounted) return null;

    final startMinutes = start.hour * 60 + start.minute;
    final suggestedEnd = (startMinutes + kStandardDutyMinutes) % kMinutesPerDay;

    final end = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: suggestedEnd ~/ 60, minute: suggestedEnd % 60),
      helpText: 'END TIME — in at ${formatMilitary(startMinutes)}',
      confirmText: 'SET',
      builder: _timePickerTheme,
    );
    if (end == null || !mounted) return null;

    return PostTime(
      start: startMinutes,
      end: end.hour * 60 + end.minute,
      auto: false,
    );
  }

  /// Puts the clock in the app's blue and gives the dialog a header
  /// strip naming which end of the duty is being set, so the two passes
  /// can't be confused for one another.
  Widget _timePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context)
            .colorScheme
            .copyWith(primary: kPrimaryColor),
        timePickerTheme: const TimePickerThemeData(
          helpTextStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: kPrimaryColor,
          ),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  /// Puts a hand-pinned slot back on the stagger ladder.
  void _resetTime(_ShiftSetup shift, int index) {
    setState(() {
      shift.times[index] = shift.times[index].copyWith(auto: true);
      shift.restagger();
    });
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _kWarnText),
    );
  }

  // ───────────────────────── building blocks ─────────────────────────

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
      ),
    );
  }

  /// A banner under a shift's slots. Amber is "look at this", red is
  /// "this is wrong" — the 9-hour floor is the only red one.
  Widget _notice({
    required IconData icon,
    required String message,
    bool isError = false,
  }) {
    final Color text = isError ? _kErrText : _kWarnText;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isError ? _kErrBg : _kWarnBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isError ? _kErrBorder : _kWarnBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: text),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: text, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiftCard(_ShiftSetup shift) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift header: name, hours and the required headcount.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        shift.baseHours,
                        style: const TextStyle(fontSize: 11, color: _kMuted),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Required',
                  style: TextStyle(fontSize: 12, color: _kMuted),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: shift.requiredController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: _inputDecoration('0'),
                    onChanged: (value) {
                      final parsed = int.tryParse(value.trim()) ?? 0;
                      setState(() {
                        shift.setRequired(parsed);
                        // Only correct the text when the typed number was
                        // out of range — rewriting it on every keystroke
                        // would fight the caret.
                        if (parsed > 99) shift.syncRequiredField();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              shift.note,
              style: const TextStyle(
                  fontSize: 11, color: _kMuted, height: 1.35),
            ),
          ),

          if (shift.required > 0) ...[
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  SizedBox(width: 22),
                  Expanded(
                    child: Text(
                      'POST',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: _kMuted,
                      ),
                    ),
                  ),
                  SizedBox(width: 6),
                  SizedBox(
                    width: _kTimeColumnWidth,
                    child: Text(
                      'TIME',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: _kMuted,
                      ),
                    ),
                  ),
                  SizedBox(width: 34),
                ],
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < shift.posts.length; i++)
              _postRow(shift, i),
          ],

          // Error: a slot is manned for less than a full duty. The picker
          // won't create one, so this is a station saved before the rule
          // — it stays on screen until the window is put right.
          if (shift.undertime > 0)
            _notice(
              icon: Icons.error_outline,
              isError: true,
              message: '${shift.undertime} post(s) run less than '
                  '${formatDuration(0, kStandardDutyMinutes)}. Those guards '
                  'are short of a full duty and the post is left bare for '
                  'the rest of the shift — tap the time and set it right.',
            ),

          // Warning: a slot runs longer than a standard duty. Allowed,
          // but it is overtime for whoever stands it.
          if (shift.overtime > 0)
            _notice(
              icon: Icons.hourglass_bottom,
              message: '${shift.overtime} post(s) run longer than '
                  '${formatDuration(0, kStandardDutyMinutes)}. That is '
                  'overtime for those guards — allowed, but check it is '
                  'what you want.',
            ),

          // Warning: the ladder has climbed into the next shift. Allowed
          // (a big station may genuinely want it) but worth a second look,
          // since those guards start after the next shift has come on.
          if (shift.overrunning > 0)
            _notice(
              icon: Icons.schedule_outlined,
              message: '${shift.overrunning} post(s) now start after the '
                  '${kNextShift[shift.key] ?? 'next'} shift has already '
                  'come on. That is allowed, but check it is what you '
                  'want — tap a time to put it somewhere earlier.',
            ),

          // Warning: slots without a post name generate as Undefined.
          if (shift.unnamed > 0)
            _notice(
              icon: Icons.warning_amber_rounded,
              message: '${shift.required - shift.unnamed} of '
                  '${shift.required} posts named — ${shift.unnamed} still '
                  'unnamed. Those slots generate as "Undefined" and block '
                  'publishing until you assign them.',
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: TextButton.icon(
              onPressed: () => _addPost(shift),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Post'),
              style: TextButton.styleFrom(foregroundColor: kPrimaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _postRow(_ShiftSetup shift, int index) {
    final post = shift.posts[index];
    final isHeadGuard = shift.isHeadGuardSlot(index);
    final isUnnamed = post.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}.',
              style: const TextStyle(fontSize: 12, color: _kMuted),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: isHeadGuard ? null : () => _pickPost(shift, index),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isHeadGuard ? const Color(0xFFF1F5F9) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUnnamed ? _kWarnBorder : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isUnnamed ? 'Not set' : post,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isUnnamed
                              ? _kWarnText
                              : const Color(0xFF1E293B),
                          fontStyle:
                              isUnnamed ? FontStyle.italic : FontStyle.normal,
                          fontWeight:
                              isHeadGuard ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isHeadGuard)
                      const Icon(Icons.lock_outline, size: 15, color: _kMuted)
                    else
                      const Icon(Icons.arrow_drop_down, color: _kMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _timeChip(shift, index),
          SizedBox(
            width: 34,
            child: isHeadGuard
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Remove this post',
                    icon: const Icon(Icons.close, size: 16),
                    color: _kMuted,
                    onPressed: () => _removePost(shift, index),
                  ),
          ),
        ],
      ),
    );
  }

  /// The slot's duty window, sitting to the right of the post.
  ///
  /// Auto slots follow the stagger ladder and move when posts are added
  /// or removed; tapping one opens the shift's list of windows, and
  /// tapping the pin puts it back on auto. The head guard's is fixed and
  /// inert — and outside the 9-hour rule, since its duty is 12.
  Widget _timeChip(_ShiftSetup shift, int index) {
    final isHeadGuard = shift.isHeadGuardSlot(index);
    final time = shift.times[index];
    final short = !isHeadGuard && time.isShortDuty;
    // A long duty and an overrun read the same way — worth a look, not
    // wrong — so they share the amber.
    final flagged = !isHeadGuard &&
        (time.isLongDuty || overrunsNextShift(shift.key, time.start));

    final Color border = short
        ? _kErrBorder
        : flagged
            ? _kWarnBorder
            : time.auto
                ? Colors.grey[300]!
                : kPrimaryColor.withOpacity(0.35);
    final Color text = short
        ? _kErrText
        : flagged
            ? _kWarnText
            : time.auto
                ? const Color(0xFF1E293B)
                : kPrimaryColor;

    final chip = Container(
      width: _kTimeColumnWidth,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: isHeadGuard
            ? const Color(0xFFF1F5F9)
            : short
                ? _kErrBg
                : flagged
                    ? _kWarnBg
                    : time.auto
                        ? Colors.grey[50]
                        : kPrimaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isHeadGuard ? Colors.grey[300]! : border),
      ),
      // The column is a fixed width so the TIME header lines up with the
      // chips, which means the content has to shrink to fit rather than
      // overflow — a wide-glyph font or a bigger text scale would push
      // "0500H - 1400H" plus the pin past the edge otherwise.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time.range,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isHeadGuard ? _kMuted : text,
              ),
            ),
            if (!time.auto && !isHeadGuard) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _resetTime(shift, index),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.push_pin, size: 12, color: kPrimaryColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (isHeadGuard) {
      return Tooltip(
        message: 'The head guard works a fixed 12-hour duty — not staggered '
            'and not editable.',
        child: chip,
      );
    }

    return Tooltip(
      message: time.auto
          ? '${time.duration} · set by the stagger ladder — tap to put '
              'this post on another of the shift\'s times.'
          : '${time.duration} · pinned to this time — tap the pin to put '
              'it back on the ladder.',
      child: InkWell(
        onTap: () => _pickTime(shift, index),
        borderRadius: BorderRadius.circular(8),
        child: chip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        // Wide enough for the post name and its duty window side by side.
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title — in edit mode the station name is the heading, not a
            // field: employees, schedules and pins join to a station by
            // name, so renaming isn't a plain form edit.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Edit Station' : 'Add New Station',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        if (_isEditing)
                          Text(
                            widget.station!.name,
                            style: const TextStyle(
                                fontSize: 13, color: _kMuted),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isEditing) ...[
                      _fieldLabel('Station Name'),
                      TextField(
                        controller: _nameController,
                        decoration: _inputDecoration('Enter station name'),
                      ),
                      const SizedBox(height: 18),
                    ],
                    for (final shift in _shifts) _shiftCard(shift),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_dailyTotal required per day'
                          '${_unnamedTotal > 0 ? ' · $_unnamedTotal post(s) unnamed' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _unnamedTotal > 0 ? _kWarnText : _kMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditing ? 'Save Changes' : 'Submit',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
