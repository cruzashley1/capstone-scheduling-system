"""
The per-shift post setup shared by the scheduler, the seeds and the
migration.

A station document carries, per shift, a required headcount, a `posts`
list with one entry per slot, and a `postTimes` list carrying that slot's
duty window:

    requiredMorning: 9
    requiredAfternoon: 8
    requiredNight: 3
    posts: {
      "morning":   ["Head Guard", "SW Platform", "SE Platform", "Roving",
                    "", "", "", "", ""],
      "afternoon": ["SW Platform", "SE Platform", "Roving", "", ...],
      "night":     ["Head Guard", "Roving", "Roving"],
    }
    postTimes: {
      "morning":   [{"start": "05:00", "end": "17:00", "auto": true},
                    {"start": "05:00", "end": "14:00", "auto": true},
                    {"start": "05:00", "end": "14:00", "auto": true},
                    {"start": "07:00", "end": "16:00", "auto": true},
                    {"start": "07:00", "end": "16:00", "auto": true}, ...],
      ...
    }

Rules the whole system leans on:

  * The head guard counts INSIDE its shift's number. Every station has two
    head guards on 12-hour duties: the day HG mans the first Morning slot
    (05:00-17:00, so it runs well into the afternoon) and the night HG
    mans the first Night slot (17:00-05:00).
  * The AFTERNOON therefore has no head guard slot of its own.
  * Night is the night head guard plus roving guards, nothing else.
  * An empty string is a slot the admin hasn't named yet. It generates as
    "Undefined", which is allowed but blocks publishing — Edit Station
    warns about it rather than refusing to save.

--------------------------------------------------------------------
THE STAGGER LADDER (`postTimes`)

Posts are not all manned at once. Each shift has a base window and the
ladder climbs it in RUNGS OF TWO: regular posts are handed out in pairs,
and only once a pair is full does the next one start two hours later, so
the station keeps cover while guards rotate off and never leaves a rung
manned by a single guard:

    MORNING (base 05:00-14:00)
      1. Head Guard     05:00-17:00   <- fixed 12h duty, outside the ladder
      2. SW Platform    05:00-14:00   <- ladder slot 0  | rung 0
      3. SE Platform    05:00-14:00   <- ladder slot 1  |
      4. Roving         07:00-16:00   <- ladder slot 2  | rung 1
      5. Ladder         07:00-16:00   <- ladder slot 3  |
      6. Concourse      09:00-18:00   <- ladder slot 4  | rung 2

The duty LENGTH never changes — only the start slides, so every slot on
the ladder is as long as its shift's base window — STANDARD_DUTY_MINUTES,
nine hours. Edit Station refuses to pin a shorter window by hand and
warns about a longer one; the head guard's fixed 12-hour duty is outside
the rule.

  * The head guard slot is never on the ladder. Its 12-hour duty is fixed
    (HG Day 05:00-17:00, HG Night 17:00-05:00) and cannot be re-timed.
  * NIGHT does not stagger. It runs the night head guard plus two roving
    guards, so every night post sits on the base window.
  * An admin can override any one slot's window by hand. That slot is
    then pinned (`auto: false`) and stops moving when posts are added or
    removed around it; clearing the override puts it back on the ladder.
  * A ladder that runs long enough to start inside the NEXT shift is
    allowed but flagged — see `overruns_next_shift`. Edit Station warns
    rather than refusing, because a genuinely huge station may want it.
"""

HEAD_GUARD = "Head Guard"
ROVING = "Roving"
UNDEFINED = "Undefined"

SHIFT_KEYS = ("morning", "afternoon", "night")

# The base duty window each shift's ladder starts from.
SHIFT_WINDOWS = {
    "morning": ("05:00", "14:00"),
    "afternoon": ("14:00", "23:00"),
    "night": ("21:00", "06:00"),
}

# The head guard's fixed 12-hour duty, by the shift whose first slot they
# man. Never staggered, never overridable.
HEAD_GUARD_WINDOWS = {
    "morning": ("05:00", "17:00"),
    "night": ("17:00", "05:00"),
}

# The same two windows keyed by the schedule's HG shift labels, for the
# generator and the report screens.
HG_SHIFT_WINDOWS = {
    "HG Day": HEAD_GUARD_WINDOWS["morning"],
    "HG Night": HEAD_GUARD_WINDOWS["night"],
}

# How far each ladder step slides the start time, and how many posts
# share one rung before the ladder climbs. Posts come in pairs: two on
# the base window, two two hours later, and so on.
LADDER_STEP_MINUTES = 120
LADDER_SLOTS_PER_RUNG = 2

# The duty length every regular post runs. The ladder only slides the
# start, so it always holds; a hand-pinned window is checked against it
# in Edit Station.
STANDARD_DUTY_MINUTES = 9 * 60

# Night keeps every post on the base window (head guard + roving only).
STAGGERED_SHIFTS = ("morning", "afternoon")

# Which shift a ladder would run into if it climbs far enough.
NEXT_SHIFT = {"morning": "afternoon", "afternoon": "night"}

MINUTES_PER_DAY = 24 * 60


# ---------------------------------------------------------------------
# Time helpers. Windows are stored as "HH:MM" strings (readable in the
# Firestore console) and handled as minutes-since-midnight internally.
# ---------------------------------------------------------------------

def parse_hhmm(value):
    """"05:00" / "0500" / "0500H" -> 300. None on anything unparseable."""
    if value is None:
        return None
    digits = "".join(c for c in str(value) if c.isdigit())
    if len(digits) != 4:
        return None
    hour, minute = int(digits[:2]), int(digits[2:])
    if hour > 23 or minute > 59:
        return None
    return hour * 60 + minute


def format_hhmm(minutes):
    """300 -> "05:00" — the stored form."""
    minutes %= MINUTES_PER_DAY
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def format_military(minutes):
    """300 -> "0500H" — the form every screen displays."""
    minutes %= MINUTES_PER_DAY
    return f"{minutes // 60:02d}{minutes % 60:02d}H"


def window_length(start, end):
    """Minutes from start to end, treating end <= start as crossing
    midnight (21:00 -> 06:00 is 9 hours, not -15)."""
    span = (end - start) % MINUTES_PER_DAY
    return span or MINUTES_PER_DAY


def ladder_offset(shift_key, ladder_index):
    """How far slot `ladder_index` of `shift_key` starts after the base.

    Slots are paired onto rungs of LADDER_SLOTS_PER_RUNG — 0 and 1 share
    the base, 2 and 3 sit LADDER_STEP_MINUTES up, and so on — so the
    ladder only climbs once the rung below it is full.
    """
    if shift_key not in STAGGERED_SHIFTS:
        return 0
    return (ladder_index // LADDER_SLOTS_PER_RUNG) * LADDER_STEP_MINUTES


def auto_window(shift_key, posts, index):
    """The window the ladder gives slot `index`, as (start, end) minutes.

    The head guard slot is answered with its fixed 12-hour duty and does
    not consume a ladder step — the ladder counts REGULAR posts only, so
    a morning's first named post still starts at the base.
    """
    base = SHIFT_WINDOWS.get(shift_key)
    if base is None:
        return None, None
    post = posts[index] if index < len(posts) else ""

    if post == HEAD_GUARD and shift_key in HEAD_GUARD_WINDOWS:
        hg_start, hg_end = HEAD_GUARD_WINDOWS[shift_key]
        return parse_hhmm(hg_start), parse_hhmm(hg_end)

    base_start = parse_hhmm(base[0])
    length = window_length(base_start, parse_hhmm(base[1]))
    ladder_index = sum(1 for p in posts[:index] if p != HEAD_GUARD)
    start = (base_start + ladder_offset(shift_key, ladder_index)) \
        % MINUTES_PER_DAY
    return start, (start + length) % MINUTES_PER_DAY


def overruns_next_shift(shift_key, start):
    """True when a slot starting at `start` has climbed into the shift
    that follows it — a morning post starting at 15:00, say.

    Measured as an offset from the shift's own base so the night's
    midnight wrap can't make the comparison lie.
    """
    following = NEXT_SHIFT.get(shift_key)
    if following is None or start is None:
        return False
    base = parse_hhmm(SHIFT_WINDOWS[shift_key][0])
    next_base = parse_hhmm(SHIFT_WINDOWS[following][0])
    return ((start - base) % MINUTES_PER_DAY) >= \
        ((next_base - base) % MINUTES_PER_DAY)


def normalize_post_times(shift_key, posts, stored=None):
    """One `{start, end, auto}` window per entry in `posts`.

    `stored` is whatever the station document already had, aligned by
    index. An `auto` slot is recomputed from the ladder every time, which
    is what makes adding a post re-stagger the ones after it. A slot the
    admin pinned keeps its window — unless it's the head guard's, whose
    12-hour duty is fixed and always wins.
    """
    stored = stored or []
    windows = []
    for index, post in enumerate(posts):
        raw = stored[index] if index < len(stored) else None
        raw = raw if isinstance(raw, dict) else {}

        auto = bool(raw.get("auto", True))
        start, end = parse_hhmm(raw.get("start")), parse_hhmm(raw.get("end"))

        # The head guard's duty is never re-timed, however it was stored.
        if post == HEAD_GUARD and shift_key in HEAD_GUARD_WINDOWS:
            auto = True

        # A pinned slot with an unreadable window falls back to the ladder
        # rather than generating a schedule with no times on it.
        if auto or start is None or end is None:
            start, end = auto_window(shift_key, posts, index)
            auto = True

        windows.append({
            "start": format_hhmm(start),
            "end": format_hhmm(end),
            "auto": auto,
        })
    return windows


def regular_windows(station, shift_key, count):
    """The duty windows for the first `count` REGULAR slots of a shift, as
    `{start, end}` dicts in the order the generator hands posts out.

    Mirrors scheduler._shift_posts exactly: morning and night drop their
    head guard slot (that guard is rostered through their own HG Day /
    HG Night row), the afternoon keeps everything it lists. A station
    short of post names still gets a window per guard — the ladder is
    extended over the unnamed slots, so a guard on an "Undefined" post
    still has a time to report at.
    """
    posts = list((station.get("posts") or {}).get(shift_key) or [])
    stored = list((station.get("postTimes") or {}).get(shift_key) or [])

    drops_head_guard = shift_key != "afternoon"
    head_guard_slots = 1 if (drops_head_guard and posts
                             and posts[0] == HEAD_GUARD) else 0
    while len(posts) - head_guard_slots < count:
        posts.append("")

    windows = normalize_post_times(shift_key, posts, stored)
    return [
        window for post, window in zip(posts, windows)
        if not (drops_head_guard and post == HEAD_GUARD)
    ][:count]


def head_guard_window(hg_shift_label):
    """`{start, end}` for an "HG Day" / "HG Night" schedule row."""
    window = HG_SHIFT_WINDOWS.get(hg_shift_label)
    if window is None:
        return None
    return {"start": window[0], "end": window[1]}


# The schedule's shift labels, mapped back to the station setup's keys.
SHIFT_LABEL_KEYS = {
    "Morning": "morning",
    "Afternoon": "afternoon",
    "Night": "night",
}


def base_window(shift_key):
    """`{start, end}` for a shift's un-staggered base window."""
    window = SHIFT_WINDOWS.get(shift_key)
    if window is None:
        return None
    return {"start": window[0], "end": window[1]}


def window_for_post(station, shift_label, post):
    """The window a guard rostered onto `post` by hand should work.

    Used by the manual-add endpoint, which has a post name rather than a
    ladder position. The station's own slot for that post wins; a post
    the station doesn't list falls back to the shift's base window, so a
    hand-added guard always has a time to report at.
    """
    if shift_label in HG_SHIFT_WINDOWS:
        return head_guard_window(shift_label)

    shift_key = SHIFT_LABEL_KEYS.get(shift_label)
    if shift_key is None:
        return None

    posts = list((station.get("posts") or {}).get(shift_key) or [])
    windows = normalize_post_times(
        shift_key, posts,
        (station.get("postTimes") or {}).get(shift_key) or [])
    drops_head_guard = shift_key != "afternoon"
    for name, window in zip(posts, windows):
        if name == post and not (drops_head_guard and name == HEAD_GUARD):
            return {"start": window["start"], "end": window["end"]}
    return base_window(shift_key)

# Where each shift's required number lives on the station document.
REQUIRED_KEYS = {
    "morning": "requiredMorning",
    "afternoon": "requiredAfternoon",
    "night": "requiredNight",
}

# The posts the generator handed out before they were configurable, kept
# as the default so migrating a station changes nothing about its roster.
LEGACY_DAY_POSTS = ("SW Platform", "SE Platform", ROVING)


def default_posts(shift, count):
    """The default post list for one shift, exactly `count` slots long.

    Reproduces the old fixed behaviour: morning and afternoon get the
    three standard day posts and leave the rest unnamed (they used to
    generate as Undefined), night gets the head guard plus roving.
    """
    if count <= 0:
        return []
    if shift == "night":
        return [HEAD_GUARD] + [ROVING] * (count - 1)

    posts = [HEAD_GUARD] if shift == "morning" else []
    for post in LEGACY_DAY_POSTS:
        if len(posts) >= count:
            break
        posts.append(post)
    while len(posts) < count:
        posts.append("")
    return posts[:count]


def shift_slots(station, shift_key):
    """How many bodies one shift of one station asks for, split by role:
    ``(head_guard_slots, regular_slots)``.

    This is the single definition of a station's demand — the generator
    caps its roster with it and the placement engine fills stations with
    it, so the number the admin types in Edit Station is what lands on
    the schedule, head guard included.

    The post list wins when the station has one: every ``Head Guard``
    entry is a slot the station's own head guard mans through their HG
    Day / HG Night rows, and every other entry is a regular's post.
    Stations carrying only the older required numbers fall back to the
    documented rule — morning and night reserve one head guard slot, the
    afternoon none, because the day HG's 12-hour duty already covers it.

    Returns None when the station declares nothing at all for the shift,
    which means "no cap": roster whoever is assigned here, the way the
    system behaved before stations were configurable.
    """
    posts = (station.get("posts") or {}).get(shift_key)
    if posts:
        head_guards = sum(1 for p in posts if p == HEAD_GUARD)
        return head_guards, len(posts) - head_guards

    required = station.get(REQUIRED_KEYS.get(shift_key, ""))
    try:
        required = int(required or 0)
    except (TypeError, ValueError):
        required = 0
    if required <= 0:
        return None
    head_guards = 0 if shift_key == "afternoon" else 1
    head_guards = min(head_guards, required)
    return head_guards, required - head_guards


def regulars_needed(shift, count):
    """How many REGULARS a shift's number asks for — the head guard slot
    is manned by the station's own head guard, who is rostered through
    their HG Day / HG Night shift instead."""
    if count <= 0:
        return 0
    return count - 1 if shift in ("morning", "night") else count
