"""
Bi-weekly (15-day) schedule generator — v1.

Implements the scheduling rules for one station group per run:

  * Regulars work their fixed station + shift, 13 days on / 2 off.
    Day-offs are staggered so daily coverage stays even.
  * Posts come from the station's own per-shift setup (Edit Station):
    each of morning / afternoon / night carries a required headcount and
    the named posts making it up, handed out to that shift's regulars in
    ID order. That number is authoritative in both directions — a shift
    rosters exactly as many guards as it has posts, so surplus regulars
    assigned to the station sit the period out (reported by name), and
    posts with no guard left to man them are reported as unmanned. The
    head guard counts inside the morning and night numbers (they man the
    first slot through their own HG Day / HG Night rows) and the
    afternoon has no head guard of its own — the day HG's 12-hour duty
    covers it. Head guards are capped by that number exactly like
    regulars: a station holding more head guards than Head Guard posts
    benches the surplus, and one holding fewer has the post held for the
    whole period by a floating substitute (resolve_head_guards). A slot
    the admin hasn't named yet generates as "Undefined" and must be given
    a real post before the schedule can be published. Stations never
    configured fall back to the old fixed behaviour (SW Platform /
    SE Platform / Roving, night all roving, no cap on the day shifts).
  * Reliever coverage: when a morning/afternoon regular is off, a
    reliever covers that post — the SAME reliever for that guard's whole
    run of day-offs, so the roster reads "Miguel Aquino — Maria Santos"
    rather than a different name against each date. Each station carries
    a small fixed roster of relievers (reliever_roster_size) and the work
    is packed onto as few of them as those slots allow, so the ones who
    do work land near their 12 days instead of everybody landing on four.
    Relievers are not confined to the station they sit at: once their own
    station's vacancies are spoken for they top up at the nearest station
    with work left. See "Reaching 12 days" below.
  * Approved LEAVE is not covered by relievers at all when it runs to
    LEAVE_REPLACEMENT_DAYS or more of the period: the guard comes off the
    roster entirely and their post is held by another REGULAR for the
    whole period — the station's own surplus first, then a guard the
    placement engine had no slot for this cycle, and for a head guard a
    floating substitute. Leaving them on the roster is what produced a
    row reading "Miguel Aquino — Jasmine Dizon (8) · Nino Cruz (2) ·
    Ramon Santiago (2) · Liza Pascual (1)". Only where no regular can be
    found does the guard stay on the roster with relievers covering, and
    the roster says so by name. A shorter leave is just a run of day-offs
    and is covered like any other (_excuse_long_leave).
  * Night coverage: night duty is capped at the station's roving night
    posts plus the night head guard. Each station has ONE night reliever
    for the period. A station's night guards have deliberately staggered
    day-offs so that one guard can cover all of them, and the whole
    station's night demand is offered to a single reliever as one bundle
    (_fill_station_cover's `bundle`). Night duty locks a reliever to
    nights for all 15 days, so the night pass runs before the day pass —
    otherwise the day pass would claim relievers the night posts then had
    nobody to fill them with. If no night reliever is available on a
    date, an on-duty night regular covers instead (internal switching, as
    a fallback).
  * Head guards: day HG 0500-1700 and night HG 1700-0500 work 13 days
    each; their staggered day-offs are covered by the shared pool of
    floating substitute head guards, drawn from every sub whose preferred
    window reaches within MAX_STATION_DISTANCE stops of the station and
    bound and packed the same way relievers are — one substitute takes a
    head guard's whole run of day-offs. A substitute standing in for a
    head guard the station doesn't have at all is booked for the whole
    period instead. That standing post goes to the NEAREST free
    substitute rather than the least-worked one, because it means
    commuting there every day for 15 days; from then on they are rostered
    exactly like the station's own head guard, including having their own
    two day-offs covered by another substitute. Substitutes are never
    double-booked across stations on the same date.

Reaching 12 days (bind, pack, then travel):
  * A reliever or substitute head guard only ever works by covering
    somebody else's vacancy, and there are nothing like enough vacancies
    to give every reliever 12 days: the whole line generates roughly 500
    day-cover-days a period against a pool of 111 relievers. Spread
    evenly that is four days each, which is the complaint this section
    exists to answer. The only way anyone reaches 12 is for someone else
    to get none — so cover is deliberately CONCENTRATED, and relievers
    with no work simply have the period off. That is expected, not a
    failure to schedule them.
  * BIND. A guard's whole run of day-offs goes to one reliever. Cover
    used to be decided one date at a time, which meant a regular's two
    day-offs could go to two different relievers and the roster report —
    which carries a single RELIEVER cell per guard — could only show one
    of them. Binding makes that cell true by construction.
  * PACK. Each station may put only so many DIFFERENT relievers on its
    roster (reliever_roster_size: 5 day + 1 night for a station set up
    for 19 or more, 4 + 1 from 12 to 18, 2 + 1 below that). Within those
    slots the reliever chosen is the one already CLOSEST to their 12
    days, not the furthest from it. Scoring per date for whoever was
    furthest behind is what put 26 different relievers on one station's
    roster at five days apiece.
  * TRAVEL. Reach is physical. Stations are stored in the order they run
    (Fernando Poe Jr. -> ... -> Dr. Santos), and a guard may be pulled to
    any station within MAX_STATION_DISTANCE (4) stops of the one they sit
    at: from Monumento that is Balintawak and 5th Avenue at one stop,
    Fernando Poe Jr. and R. Papa at two, and so on. Stations are planned
    in line order and a reliever who still has days left is preferred
    over a fresh one, which is how they walk down the line topping up —
    but only while the station can still be covered without them, so the
    last free slots are never spent on a nearly-full traveller.
  * MAX_RELIEVER_DAYS (12) is a ceiling, not a quota. Hitting it takes a
    guard off the board for the rest of the period.
  * An absence of LONG_ABSENCE_DAYS or more needs more cover-days than
    one reliever may work at all, so those days are split across the
    station's roster instead of bound to one partner — several reliever
    names on one row, which is why an approved LEAVE that long doesn't
    come here at all: the guard is taken off the roster and a regular
    holds the post instead (_excuse_long_leave). What is left for the
    split is a long run of approved special day-off requests, and a leave
    nothing could be found to replace.
  * The radius is narrower than the smallest group is wide, so the
    group-adjacency exception rule (Group 1 <-> 2 <-> 3, never 1 <-> 3)
    holds automatically and is no longer checked separately. Cover pulled
    in from another station is still marked on the entry
    (`borrowedFrom`).
  * Reaching out never double-books anyone: commitments already saved in
    other groups' schedules for the same period are honoured, and the
    12-day cap counts those external days too.

Assumptions made for v1 (flagged, easy to change):
  * A reliever with no vacancy to cover on a given day simply has that
    day off.
  * "In-between" shifts (e.g. the 04:30 early-start variant) are not
    generated yet.
  * Station placement comes from the monthly rotation engine
    (rotation.py -> placement.py) when the caller passes rotate=True:
    it fills each station's declared slots, steering 85-90% of regulars
    and head guards and 60-75% of relievers onto a station they listed
    as preferred. Guards no station had a slot for are reported and left
    unscheduled rather than pushed onto their home station, which is
    what would put it over its number. With rotate=False everyone is
    scheduled at their permanent assignedStation and a station can come
    out over or under its number — only the caps apply, nothing moves.

Output: one schedule document per station, shaped exactly like the
Flutter Schedule model (days[] -> entries[]), stored in `schedules/`:

  {
    id: "STA001_2026-07-16", stationId, stationName, group,
    startDate, endDate, createdAt, status: "unpublished",
    days: [
      { date: "2026-07-16",
        entries: [
          { id, employeeId, employeeName,
            shift: Morning|Afternoon|Night|HG Day|HG Night,
            post: "SW Platform"|"SE Platform"|"Roving"|"Head Guard"
                  |"Undefined"|<admin-typed>,   # covers inherit the
                                                # covered guard's post
            isReliever: bool,          # true = reliever covering a post
            coveringFor: str|null }    # employeeId being covered
        ] }
    ]
  }
"""

from datetime import date, datetime, timedelta, timezone

import repositories
import rotation
import schedule_notes
import station_pools
import station_posts

PERIOD_DAYS = 15

# Station-number ranges per group (shared with station_pools, which also
# owns the group-adjacency exception rule).
GROUP_RANGES = station_pools.GROUP_RANGES

# Regulars and station head guards hold one post for the period: 13 days
# on, 2 off. A substitute standing in for a head guard the station hasn't
# got works the same pattern, because they are filling that post, not
# relieving on it.
MAX_REGULAR_DAYS = 13

# The ceiling for personnel who work by covering other people's vacancies
# — relievers and substitute head guards. They are topped up towards this
# across nearby stations (see _CoverPool); reaching it stops them being
# assigned anywhere else for the rest of the period.
MAX_RELIEVER_DAYS = 12

# How many DISTINCT relievers may appear on one station's roster in a
# period, keyed by the total headcount the station is set up for
# (morning + afternoon + night, head guards included — the figure Edit
# Station shows). Each band is (minimum total, day relievers, night
# relievers):
#
#     19 or more  ->  5 day + 1 night
#     12 to 18    ->  4 day + 1 night
#     11 or fewer ->  2 day + 1 night
#
# This is a cap on NAMES, not a target to fill. A station whose work fits
# on two relievers uses two; the cap only stops a third and fourth being
# pulled in to take a day apiece. Substitute head guards are outside it —
# they man the Head Guard post, not a reliever slot.
RELIEVER_ROSTER_BANDS = ((19, 5, 1), (12, 4, 1), (0, 2, 1))

# A regular off this many days or more is on leave (or a long run of
# approved special day-offs), not taking their ordinary two day-offs.
# One reliever may not work a whole leave — it would be more days than
# MAX_RELIEVER_DAYS allows and would swallow their entire period — so
# those days are split across the station's reliever roster instead of
# being bound to a single partner (_fill_station_cover).
LONG_ABSENCE_DAYS = 4

# An APPROVED LEAVE reaching that same length doesn't take the split
# either: the guard comes off the roster for the whole period and their
# post goes to another REGULAR (_excuse_long_leave). A post is held by
# one guard for the period — that is what the roster's one row per guard
# means — and a guard who cannot work it should not be holding it. Left
# on the roster they produced exactly the row this rule exists to
# prevent: one name against the post and four different relievers in the
# RELIEVER column, an admin's "who is actually at SW Platform on the
# 9th?" answerable only by reading the day entries.
#
# Below this length a leave is still just a short run of day-offs and is
# covered like any other — one bound reliever, one name on the report.
LEAVE_REPLACEMENT_DAYS = LONG_ABSENCE_DAYS

# Night headcount when a station has no per-shift setup saved yet: this
# many roving regulars plus the night head guard. Stations configured in
# Edit Station derive their own cap from their night post list instead
# (see _shift_posts / _regular_cap).
MAX_NIGHT_REGULARS = 2

SHIFT_LABELS = {"morning": "Morning", "afternoon": "Afternoon",
                "night": "Night"}

# Posts are configured per station, per shift, in Edit Station
# (station_posts.py documents the shape). Guards beyond the configured
# posts start as Undefined; api.py refuses to publish a schedule while
# any entry still carries POST_UNDEFINED.
POST_HEAD_GUARD = station_posts.HEAD_GUARD
POST_ROVING = station_posts.ROVING
POST_UNDEFINED = station_posts.UNDEFINED

# Fallback for stations that predate the per-shift post setup, so an
# unconfigured station still generates exactly as it did before.
STANDARD_POSTS = station_posts.LEGACY_DAY_POSTS


def _shift_posts(station, shift_key):
    """The posts this station's `shift_key` hands out to REGULARS, in
    order.

    The station document stores the shift exactly as the admin sees it in
    Edit Station, head guard included: morning ["Head Guard", "Ladder",
    ...] and night ["Head Guard", "Roving", "Roving"]. The head guard is
    dropped here because they're rostered through their own HG Day / HG
    Night shift rows, not as one of the shift's regulars — what's left is
    the list of posts the regulars fill.

    Slots the admin hasn't named yet come through as empty strings and
    become POST_UNDEFINED, exactly like a guard past the end of the list:
    the position still belongs to that guard, it just has no name on it
    until the admin assigns one (which publishing requires).

    The AFTERNOON keeps everything it lists. It has no head guard of its
    own by design, so an admin who types "Head Guard" there means a
    regular manning a post of that name — dropping it would silently
    shrink the shift below its own number.

    Returns None when the station has no post list for this shift, which
    tells the caller to fall back to the old fixed behaviour.
    """
    posts = (station.get("posts") or {}).get(shift_key)
    if not posts:
        return None
    if shift_key == "afternoon":
        return [(p or POST_UNDEFINED) for p in posts]
    return [(p or POST_UNDEFINED) for p in posts if p != POST_HEAD_GUARD]


def _regular_cap(station, shift_key):
    """How many REGULARS this shift takes at this station — one per
    configured post, with the head guard slot already excluded (their own
    HG Day / HG Night rows fill it).

    This is what makes the required number in Edit Station authoritative:
    set Morning to 5 and the shift rosters the head guard plus 4 guards,
    however many happen to be assigned to the station. The surplus is
    reported, not silently squeezed onto Undefined posts.

    None means "no cap": a station with no post list for this shift keeps
    the old behaviour of rostering everyone assigned to it. Night is the
    exception — it has always been capped, so it keeps its fixed fallback.
    """
    slots = station_posts.shift_slots(station, shift_key)
    if slots is None:
        return MAX_NIGHT_REGULARS if shift_key == "night" else None
    return slots[1]


def _head_guard_cap(station, shift_key):
    """How many of the station's own head guards this shift takes.

    The mirror of _regular_cap, and the reason a station set up for 15
    rosters 15: the head guard slot is part of the shift's number, so it
    is capped by that number exactly like every other post. Without this
    the generator emitted one row per head-guard EMPLOYEE standing at the
    station — a station holding two day head guards ran one over its
    number every single day, and one holding none ran one under.

    None means the station declares nothing for the shift, so the old
    uncapped behaviour applies.
    """
    slots = station_posts.shift_slots(station, shift_key)
    if slots is None:
        return None
    return slots[0]

def station_required_total(station):
    """Total headcount the station is set up for across all three shifts,
    head guards included — the number the bands in RELIEVER_ROSTER_BANDS
    are read against. Shifts the station declares nothing for count as 0.
    """
    total = 0
    for shift_key in station_posts.SHIFT_KEYS:
        slots = station_posts.shift_slots(station, shift_key)
        if slots:
            total += slots[0] + slots[1]
    return total


def reliever_roster_size(station):
    """(day reliever slots, night reliever slots) for one station.

    How many DIFFERENT relievers may appear on this station's roster in a
    period. Sized off the station's own headcount, because that is what
    decides how much cover it generates: a station set up for 19 produces
    roughly half again the vacancy-days one set up for 13 does, and
    splitting those days over the same number of relievers would push
    each of them further below their 12.
    """
    total = station_required_total(station)
    for minimum, day_slots, night_slots in RELIEVER_ROSTER_BANDS:
        if total >= minimum:
            return day_slots, night_slots
    return RELIEVER_ROSTER_BANDS[-1][1:]


SPECIAL_ASSIGNMENTS = "special_assignments"

# Employee-filed special day-off requests. Approved ones force the guard
# off on their requested dates when this period's schedule is generated;
# pending ones are surfaced as a note so the admin decides before relying
# on the roster (see load_special_requests).
SPECIAL_REQUESTS = "special_requests"

# Employee leave. An approved leave keeps the guard off duty for its
# whole date range (see load_leaves). One long enough to swallow the
# period takes their post off them too and gives it to another regular
# (_excuse_long_leave); a shorter one is granted through the same day-off
# mechanism as a special request, so a reliever covers the days and the
# guard keeps their post.
LEAVE_REQUESTS = "leave_requests"

# Marks an employee dict as pinned, on the per-run copy only. Never
# written back to Firestore — the employee's own record still carries
# their permanent station, which is exactly what the pin expires back to.
SPECIAL_FLAG = "_specialAssignment"


def load_special_assignments(db, cycle_id, also_cycle_ids=()):
    """Returns {employeeId: pin document} for one rotation cycle.

    Pins are keyed by cycle, so simply asking for the cycle the schedule
    falls in is what makes them expire: next month's generation queries a
    different cycle ID and finds nothing.

    `also_cycle_ids` are the other cycles this period touches — a period
    started on the 25th runs into the next month, and a pin saved for
    that month is meant for most of the days being generated. They are
    loaded as a fallback only: `cycle_id` is the period's own cycle, so
    a guard pinned in both months stays where that cycle put them rather
    than flipping mid-period.
    """
    pins = {}
    for cid in list(also_cycle_ids) + [cycle_id]:
        for doc in (db.collection(SPECIAL_ASSIGNMENTS)
                    .where("rotationCycleId", "==", cid).stream()):
            data = doc.to_dict()
            pins[data["employeeId"]] = data
    return pins


def load_special_requests(db, start_date):
    """Reads every special day-off request and keeps only the dates that
    land inside this 15-day period.

    Returns (approved, pending): each maps employeeId -> a sorted list of
    ISO dates in range. `approved` dates are forced off during generation;
    `pending` dates are reported so the admin can decide before the roster
    is trusted. Keyed by employee (not group) because a request is filed
    against a person, not a station — the caller filters to the employees
    it is actually scheduling."""
    start_iso = start_date.isoformat()
    end_iso = (start_date + timedelta(days=PERIOD_DAYS - 1)).isoformat()
    approved, pending = {}, {}
    for doc in db.collection(SPECIAL_REQUESTS).stream():
        req = doc.to_dict()
        status = req.get("status")
        if status not in ("approved", "pending"):
            continue  # denied requests never touch the schedule
        emp_id = req.get("employeeId")
        if not emp_id:
            continue
        in_range = sorted(
            d for d in req.get("dates", [])
            if isinstance(d, str) and start_iso <= d <= end_iso
        )
        if not in_range:
            continue
        bucket = approved if status == "approved" else pending
        bucket.setdefault(emp_id, [])
        for d in in_range:
            if d not in bucket[emp_id]:
                bucket[emp_id].append(d)
    for bucket in (approved, pending):
        for emp_id in bucket:
            bucket[emp_id].sort()
    return approved, pending


def load_leaves(db, start_date):
    """Reads every leave record and keeps only the days that fall inside
    this 15-day period.

    Returns (approved, pending): each maps employeeId -> a sorted list of
    ISO dates in range, the same shape load_special_requests returns, so
    both feed the one day-off mechanism. Denied and cancelled leaves are
    ignored entirely; a pending one only produces a note, because a leave
    nobody has decided on must not silently empty a post.

    A leave is stored as a range, not a list of days, so it is expanded
    here — and clipped to the period, since a 105-day maternity leave
    spans seven of them."""
    start_iso = start_date.isoformat()
    end_iso = (start_date + timedelta(days=PERIOD_DAYS - 1)).isoformat()
    approved, pending = {}, {}
    for doc in db.collection(LEAVE_REQUESTS).stream():
        rec = doc.to_dict()
        status = rec.get("status")
        if status not in ("approved", "pending"):
            continue
        emp_id = rec.get("employeeId")
        leave_start, leave_end = rec.get("startDate"), rec.get("endDate")
        if not (emp_id and leave_start and leave_end):
            continue
        # Clip the leave to the period being generated.
        first = max(leave_start, start_iso)
        last = min(leave_end, end_iso)
        if first > last:
            continue
        try:
            day = datetime.strptime(first, "%Y-%m-%d").date()
            final = datetime.strptime(last, "%Y-%m-%d").date()
        except ValueError:
            continue
        bucket = approved if status == "approved" else pending
        dates = bucket.setdefault(emp_id, [])
        while day <= final:
            iso = day.isoformat()
            if iso not in dates:
                dates.append(iso)
            day += timedelta(days=1)
    for bucket in (approved, pending):
        for emp_id in bucket:
            bucket[emp_id].sort()
    return approved, pending


def long_leave_ids(leave_approved):
    """{employeeId: [iso dates]} for the approved leaves long enough to
    take the guard off the roster entirely (LEAVE_REPLACEMENT_DAYS)."""
    return {emp_id: dates for emp_id, dates in leave_approved.items()
            if len(dates) >= LEAVE_REPLACEMENT_DAYS}


def _post_cohort(employee):
    """The post an employee holds: their kind and the shift they work.

    A stand-in has to match both — a night regular cannot hold a morning
    post, and a day head guard cannot hold the night one.
    """
    return (employee.get("type"), employee.get("assignedShift"))


def _post_label(cohort):
    etype, shift = cohort
    if etype == "headGuard":
        return "HG Day" if shift == "hgDay" else "HG Night"
    return SHIFT_LABELS.get(shift, shift or "")


def _take_replacement(available, cohort, station_name):
    """Pops a guard of `cohort` off the bench, preferring one who asked
    for this station — a replacement is a posting like any other, and a
    preference is still worth honouring where it costs nothing."""
    pool = available.get(cohort)
    if not pool:
        return None
    for i, emp in enumerate(pool):
        wanted = [p.strip() for p in (emp.get("preferredStations") or []) if p]
        if station_name in wanted:
            return pool.pop(i)
    return pool.pop(0)


def _excuse_long_leave(staff_by_station, group_stations, long_leave, bench,
                       name_of):
    """Takes guards on a long approved leave off this period's roster and
    hands their post to another REGULAR.

    Three places the post can come from, in order of preference:

      1. A regular already assigned to the station but over its number —
         they were going to sit the period out anyway (_plan_station_duty
         benches the surplus), so dropping the guard on leave promotes
         them automatically and nothing else has to happen here.
      2. The group's bench: guards the placement engine found no slot for
         this cycle. They are idle for the period, they are the right
         cohort by construction, and taking one costs no other station a
         body.
      3. For a head guard, nobody: resolve_head_guards already holds a
         station's vacant Head Guard post with a single floating
         substitute for the whole period, which is the same "one name on
         the post" outcome by a different route.

    If none of those can produce a body, the guard STAYS on the roster
    with their leave as day-offs — the old behaviour — because an
    unmanned post is worse than a row with several relievers in it. The
    note says so, and names the fix.

    Mutates `staff_by_station`. Returns (handled, notes):
    `handled` is every long-leave guard this group dealt with, excused or
    not, so the caller doesn't also file the generic leave note for them.
    """
    station_by_name = {s["name"].strip(): s for s in group_stations}
    available = {}
    for emp in bench:
        available.setdefault(_post_cohort(emp), []).append(emp)
    for pool in available.values():
        pool.sort(key=lambda e: e.get("id", ""))

    handled, notes = set(), []
    for station_name in sorted(staff_by_station):
        station = station_by_name.get(station_name)
        if station is None:
            continue  # another group's station; its own run handles it
        staff = staff_by_station[station_name]
        for emp in [e for e in staff
                    if e["id"] in long_leave
                    and e.get("type") in ("regular", "headGuard")]:
            cohort = _post_cohort(emp)
            label = _post_label(cohort)
            dates = long_leave[emp["id"]]
            who = name_of.get(emp["id"], emp["id"])
            reason = (f"Away on approved leave for {dates[0]} to "
                      f"{dates[-1]} — {len(dates)} of the {PERIOD_DAYS} days "
                      f"in this period")

            replacement, source = None, None
            if emp.get("type") == "headGuard":
                replacement = _take_replacement(available, cohort,
                                                station_name)
                source = "bench" if replacement else "substitute"
            else:
                cap = _regular_cap(station, emp.get("assignedShift"))
                # Who would still be standing here for this shift. Guards
                # already excused are gone from `staff`; one still ahead
                # in this loop is discounted too, since their post is
                # about to need a body of its own. A guard nothing could
                # replace stays on the roster and does hold their slot,
                # so they keep counting (they are in `handled`).
                others = sum(1 for e in staff
                             if e is not emp
                             and e.get("type") == "regular"
                             and e.get("assignedShift")
                             == emp.get("assignedShift")
                             and not (e["id"] in long_leave
                                      and e["id"] not in handled))
                # `others` alone filling the shift is the whole test: the
                # station was over its number and the surplus was going
                # to sit out, so the post is manned without anyone new.
                if cap is not None and others >= cap:
                    source = "surplus"
                else:
                    replacement = _take_replacement(available, cohort,
                                                    station_name)
                    source = "bench" if replacement else None

            if source is None:
                handled.add(emp["id"])
                notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_LEAVE,
                    schedule_notes.SEVERITY_WARNING,
                    who,
                    f"{reason}, and no spare {label} guard was free to take "
                    f"their post at {station_name}. They stay on the roster "
                    f"and relievers cover the days.",
                    f"Assign another {label} guard to {station_name}, or "
                    f"lower its {label} number in Edit Station.",
                    station=station_name))
                continue

            staff.remove(emp)
            handled.add(emp["id"])
            # The post ended up in one pair of hands for the period, which
            # is the outcome we want — so these are FYI, not warnings.
            if replacement is not None:
                staff.append(replacement)
                notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_LEAVE,
                    schedule_notes.SEVERITY_INFO,
                    who,
                    f"{reason}, so they come off {station_name}'s roster "
                    f"for the whole period.",
                    f"{name_of.get(replacement['id'], replacement['id'])}, "
                    f"who had no station slot this cycle, holds the "
                    f"{label} post instead.",
                    station=station_name))
            elif source == "surplus":
                notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_LEAVE,
                    schedule_notes.SEVERITY_INFO,
                    who,
                    f"{reason}, so they come off {station_name}'s roster "
                    f"for the whole period.",
                    f"The {label} post goes to another regular already "
                    f"assigned there, not to relievers.",
                    station=station_name))
            else:
                notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_LEAVE,
                    schedule_notes.SEVERITY_INFO,
                    who,
                    f"{reason}, so they come off {station_name}'s roster "
                    f"for the whole period.",
                    "A substitute head guard holds the Head Guard post "
                    "instead.",
                    station=station_name))
    return handled, notes


def _apply_special(employee, pin):
    """Returns a copy of `employee` reshaped by their pin for this cycle.

    A copy, not a mutation: the same employee dict is read again on the
    next generation run, and a pin must never leak past its own cycle.
    """
    effective = dict(employee)
    effective["assignedStation"] = (pin.get("stationName") or "").strip()
    if pin.get("shift"):
        effective["assignedShift"] = pin["shift"]
    effective[SPECIAL_FLAG] = True
    return effective


# The closest together a guard's two day-offs may fall, in days. The old
# fixed "+7" always produced 7; anything from here up still reads as one
# off early in the period and one late.
MIN_DAY_OFF_GAP = 5


def _cyclic_gap(a, b):
    """Days between two day-indices the short way round the period."""
    forward = (a - b) % PERIOD_DAYS
    return min(forward, PERIOD_DAYS - forward)


def _spread_day_offs(count, station_offset=0):
    """Two day-off indices per employee, spread so each day of the period
    loses as near to the same number of people as the arithmetic allows.

    The old version placed the first off at round(i * 15 / count) and the
    second a fixed 7 days later, which wrapped: a 4-guard shift came out
    [(0,7), (4,11), (8,0), (11,3)] — two guards off on day 0 and on day
    11, and NOBODY off on nine of the fifteen days. Every station sized
    the same way got the identical pattern, so the whole line asked for
    double cover on day 0 and none at all on day 1. That was survivable
    while each station's relievers only ever covered their own station;
    once the pool is shared down the line (_StationRelieverView) the
    spike is what empties it, and the stations generated last came up
    short by exactly the doubled-up days.

    So the days are filled greedily least-loaded-first instead, with each
    guard's second off kept at least MIN_DAY_OFF_GAP from their first,
    and the whole pattern rotated by the station's position on the line
    so neighbouring stations don't all fall due on the same dates.
    """
    load = [0] * PERIOD_DAYS
    offs = []
    for i in range(count):
        # Tie-break away from the previous guard's start, so equally
        # empty days still come out staggered rather than clustered.
        first = min(range(PERIOD_DAYS),
                    key=lambda d: (load[d], (d - i) % PERIOD_DAYS))
        load[first] += 1
        spaced = [d for d in range(PERIOD_DAYS)
                  if _cyclic_gap(d, first) >= MIN_DAY_OFF_GAP]
        second = min(spaced, key=lambda d: (load[d], (d - first) % PERIOD_DAYS))
        load[second] += 1
        offs.append(((first + station_offset) % PERIOD_DAYS,
                     (second + station_offset) % PERIOD_DAYS))
    return offs


def _sorted_by_id(employees):
    return sorted(employees, key=lambda e: e.get("id", ""))


def _pinned_first(employees):
    """ID order, except admin-pinned guards come first.

    This is what makes a Special Assignment actually stick. Every shift
    is capped at the number of posts its setup declares, and the surplus
    is cut from the END of this list — so with a plain ID sort a pinned
    guard whose ID happened to sort late was silently cut, and because
    the pin had already pulled them off their home station's roster they
    vanished from the schedule entirely.

    Ordering pins first inverts that: the guard the admin placed by hand
    is guaranteed a post, and whoever the station has to give up instead
    is named in the surplus note for the admin to resolve.
    """
    return sorted(
        employees,
        key=lambda e: (0 if e.get(SPECIAL_FLAG) else 1, e.get("id", "")))


def _prefers_station(employee, station_name):
    return station_name in {(p or "").strip()
                            for p in employee.get("preferredStations") or []}


def _reach_anchor(employee, placed_station):
    """The station a guard's travel radius is measured from.

    Their PERMANENT station, not the one this cycle's rotation placed
    them at, because only the permanent one is the same in all three
    group runs. rotation.resolve_placement rotates a guard only in the
    run for the group their home station sits in, so group 2's run sees a
    group 1 reliever at their permanent station while group 1's run sees
    them at their rotated one. Anchoring on the rotated station therefore
    gave a guard two different centres and let their period sprawl across
    twice the radius — 10 stops apart in the mock roster, against a limit
    of 4.

    Falls back to where they were placed when the record carries no
    permanent station at all.
    """
    return (employee.get("assignedStation") or "").strip() or placed_station


def _reliever_candidates(line, station_name, relievers_by_station,
                         max_distance=station_pools.MAX_STATION_DISTANCE):
    """Every reliever a station may call on, as
    [(employee, stops away, did they pick this station), ...].

    Reach is physical, not organisational: anyone based within
    `max_distance` stops along the line qualifies, which subsumes the old
    "own station, then sister stations, then the adjacent group" tiers.
    The radius is narrower than a group is wide, so the group-adjacency
    exception rule still holds without being checked separately (see
    station_pools.MAX_STATION_DISTANCE).

    `relievers_by_station` is keyed by each reliever's anchor station
    (see _reach_anchor), not by wherever this cycle's rotation put them.
    """
    candidates = []
    for anchor, relievers in relievers_by_station.items():
        gap = station_pools.distance(line, station_name, anchor)
        if gap is None or gap > max_distance:
            continue
        for employee in relievers:
            # A guard the admin pinned to a station stays on it. Lending
            # them out is the exact thing the pin exists to prevent, so
            # they are candidates for their own station only.
            if gap and employee.get(SPECIAL_FLAG):
                continue
            candidates.append(
                (employee, gap, _prefers_station(employee, station_name)))
    return candidates


def _sub_candidates(line, station_name, subs,
                    max_distance=station_pools.MAX_STATION_DISTANCE):
    """The same list for floating substitute head guards.

    A substitute has no assigned station — they float across the window
    of stations they picked — so their distance to a station is measured
    from the nearest station in that window, and distance 0 means the
    station is in the window. A substitute who picked nothing at all is
    placed at the edge of the radius: usable, but only once everyone with
    a stated window is spoken for.
    """
    candidates = []
    for sub in subs:
        gaps = [gap for gap in
                (station_pools.distance(line, station_name, p)
                 for p in (sub.get("preferredStations") or []))
                if gap is not None]
        gap = min(gaps) if gaps else max_distance
        if gap > max_distance:
            continue
        candidates.append((sub, gap, gap == 0))
    return candidates


def _night_day_offs(index, station_offset):
    """The two day-indices the `index`-th night regular of a station is
    off.

    Deliberately staggered: a station's night guards must never be off on
    the same date, because one night reliever covers all of them. Shared
    with the night-demand count so the two can't drift apart.
    """
    return {(1 + 3 * index + station_offset) % PERIOD_DAYS,
            (8 + 3 * index + station_offset) % PERIOD_DAYS}


def _load_period_commitments(db, group, start_date):
    """What every employee is already booked for in OTHER groups' saved
    schedules overlapping this period.

    Returns (busy, days_worked, night_locked, day_locked): busy is
    {(employeeId, dateIso)}, and days_worked counts each employee's
    committed days. This is what keeps cross-group borrowing honest — a
    reliever already rostered at their home group's station on a date can
    never be borrowed for it, and the 13-day cap counts those days too.
    night_locked / day_locked carry the night-only rule across groups:
    a reliever already covering night posts in another group's schedule
    this period may not take day posts here, and one already covering
    day posts may not be designated a night reliever. The group's own
    documents are skipped because regenerating overwrites them."""
    start_iso = start_date.isoformat()
    end_iso = (start_date + timedelta(days=PERIOD_DAYS - 1)).isoformat()
    busy = set()
    night_locked = set()
    day_locked = set()
    for doc in db.collection("schedules").stream():
        data = doc.to_dict()
        if data.get("group") == group:
            continue
        if (data.get("endDate", "") < start_iso
                or data.get("startDate", "") > end_iso):
            continue
        for day in data.get("days", []):
            for entry in day.get("entries", []):
                if not entry.get("employeeId"):
                    continue
                busy.add((entry["employeeId"], day.get("date")))
                if entry.get("isReliever"):
                    if entry.get("shift") == SHIFT_LABELS["night"]:
                        night_locked.add(entry["employeeId"])
                    else:
                        day_locked.add(entry["employeeId"])
    days_worked = {}
    for emp_id, _ in busy:
        days_worked[emp_id] = days_worked.get(emp_id, 0) + 1
    return busy, days_worked, night_locked, day_locked


class _CoverPool:
    """Every reliever a group's run may draw on, and how full each of
    them is.

    One instance per generation run, shared by every station, so a
    reliever booked at one station can never be booked at another on the
    same date and their 12 days count across the whole line — including
    the days already committed in another group's saved schedule for the
    same period (`external_busy` / `external_days`).
    """

    def __init__(self, external_busy=frozenset(), external_days=None):
        self.busy = set()   # (employeeId, day_index)
        self.days = {}      # employeeId -> days booked in this run
        self.external_busy = external_busy
        self.external_days = external_days or {}
        # employeeId -> "day" | "night". Night duty is a whole-period
        # commitment: a reliever covering night posts works nothing but
        # night for the 15 days, and one already covering day posts can
        # never be pulled onto nights. The lock is what carries that rule
        # across stations and across groups.
        self.locked = {}

    def worked(self, emp_id):
        return self.days.get(emp_id, 0) + self.external_days.get(emp_id, 0)

    def spare(self, emp_id):
        """Days this reliever may still be given before hitting the 12."""
        return MAX_RELIEVER_DAYS - self.worked(emp_id)

    def free(self, employee, day_indices, dates):
        """Can this reliever take EVERY one of these day-indices?

        All-or-nothing, because the caller is binding them to one guard's
        whole run of day-offs — a partner who can only make one of the
        two days is not a partner.
        """
        emp_id = employee["id"]
        if len(day_indices) > self.spare(emp_id):
            return False
        for index in day_indices:
            if (emp_id, index) in self.busy:
                return False
            if (emp_id, dates[index]) in self.external_busy:
                return False
        return True

    def book(self, employee, day_indices, kind):
        emp_id = employee["id"]
        for index in day_indices:
            self.busy.add((emp_id, index))
        self.days[emp_id] = self.days.get(emp_id, 0) + len(day_indices)
        self.locked.setdefault(emp_id, kind)


class _CoverPlan:
    """Who stands in for whom, settled for the whole group before any
    station's days are built.

    Cover cannot be decided one date at a time. Picking the best reliever
    for each vacancy independently is what produced the complaint this
    class exists to fix: every station reached four stops down the line
    for whoever was furthest from their 12 days, so a station's roster
    listed 26 different relievers and each of them finished the period on
    five days. Deciding the whole period up front lets cover be BOUND —
    one reliever takes a regular's entire run of day-offs — and lets the
    work be packed onto as few relievers as the roster caps allow.

    cover   : (station, regularId, dayIndex) -> the reliever standing in
    partner : (station, regularId) -> the one reliever bound to that
              guard's whole run of day-offs, which is what the RELIEVER
              column of the roster report shows. Absent when the run had
              to be split (a leave, or nobody free for every date).
    roster  : station -> {"day": [reliever, ...], "night": [...]} — the
              distinct relievers appearing there, capped by
              reliever_roster_size.
    """

    def __init__(self):
        self.cover = {}
        self.partner = {}
        self.roster = {}
        self.notes = []

    def take(self, station, regular_id, day_index):
        return self.cover.get((station, regular_id, day_index))

    def relievers_at(self, station):
        kinds = self.roster.get(station, {})
        return kinds.get("day", []) + kinds.get("night", [])


def _fill_station_cover(plan, pool, station_name, kind, slots,
                        candidates, demand, dates, bundle=False):
    """Books cover for one station's vacancies out of `candidates`.

    `demand` is [(regularId, [day_index, ...]), ...] in roster order —
    every guard at this station who is off at some point, and the days
    they are off. `slots` is how many DIFFERENT relievers may end up on
    this station's roster for this kind of duty.

    Two rules do the work:

      * BIND. A regular's whole run of day-offs goes to one reliever, so
        the roster reads "Miguel Aquino — Maria Santos" rather than a
        different name against each date. Only when nobody can make every
        date is the run split.
      * PACK. The reliever chosen is the one already CLOSEST to their 12
        days, not the one furthest from it. Spreading the work is what
        left everybody on five days; concentrating it fills the relievers
        who are already working and leaves the rest of the pool unused,
        which is the intended outcome — the days that exist are finite,
        so the only way anyone reaches 12 is for someone else to get none.

    A reliever already on this station's roster costs no slot and is
    always preferred. Recruiting someone new prefers a reliever already
    working nearby (that is how they travel to top up towards 12) but
    only while the station can still be covered without them: taking a
    nearly-full traveller into one of the last slots would leave the
    station's remaining vacancies with nowhere to go, so `admissible`
    refuses it and a fresh reliever is recruited instead.

    `bundle` offers the station's WHOLE demand to one reliever before
    anything else is tried. Night duty is booked that way: a station's
    night guards have deliberately staggered day-offs precisely so one
    night reliever can cover all of them, and the roster allows exactly
    one. Taking the vacancies one guard at a time could hand the first to
    a reliever who is busy elsewhere on the second, and with no slot left
    for a second name the post fell through to a night regular manning
    two posts at once.

    Returns the number of vacancy-days nobody could be found for.
    """
    roster = plan.roster.setdefault(station_name, {}).setdefault(kind, [])
    on_roster = {e["id"] for e in roster}
    remaining = sum(len(offs) for _regular_id, offs in demand)

    def admissible(spare, slots_left):
        """Would taking a reliever with `spare` days left still leave
        enough room in the remaining slots for this station's remaining
        vacancies? Fresh relievers have all 12 and always pass."""
        return (remaining - spare
                <= (slots_left - 1) * MAX_RELIEVER_DAYS)

    def choose(day_indices, overflow=False):
        best, best_key = None, None
        slots_left = slots - len(roster)
        for employee, dist, prefers in candidates:
            emp_id = employee["id"]
            fresh = emp_id not in on_roster
            if fresh and slots_left <= 0 and not overflow:
                continue
            if pool.locked.get(emp_id, kind) != kind:
                continue
            if not pool.free(employee, day_indices, dates):
                continue
            worked = pool.worked(emp_id)
            if (fresh and worked and not overflow
                    and not admissible(pool.spare(emp_id), slots_left)):
                continue
            key = (
                0 if not fresh else 1,     # already here: costs no slot
                0 if worked else 1,        # then whoever is already working
                -worked,                   # fullest first — pack, don't spread
                dist,                      # then nearest
                0 if prefers else 1,       # then a station they asked for
                emp_id,                    # then stable, so reruns match
            )
            if best_key is None or key < best_key:
                best, best_key = employee, key
        return best

    overflowed = 0

    def admit(employee):
        """Puts a reliever on this station's roster, counting them as
        overflow when the station's band had no slot left for them."""
        nonlocal overflowed
        if employee["id"] in on_roster:
            return
        if len(roster) >= slots:
            overflowed += 1
        roster.append(employee)
        on_roster.add(employee["id"])

    def book(regular_id, day_indices, overflow=False):
        nonlocal remaining
        employee = choose(day_indices, overflow)
        if employee is None:
            return None
        admit(employee)
        pool.book(employee, day_indices, kind)
        for index in day_indices:
            plan.cover[(station_name, regular_id, index)] = employee
        remaining -= len(day_indices)
        return employee

    def overflow_note():
        if not overflowed:
            return
        label = "night" if kind == "night" else "morning/afternoon"
        plan.notes.append(schedule_notes.note(
            schedule_notes.CATEGORY_COVER,
            schedule_notes.SEVERITY_INFO,
            station_name,
            f"{overflowed} reliever(s) beyond the {slots} this station's "
            f"size allows were added, because its own were already booked "
            f"on the dates needed. Every guard still has one reliever for "
            f"their {label} day-offs.",
            "Nothing to fix — the roster just shows more names than usual "
            "for a station this size.",
            station=station_name))

    if bundle and len(demand) > 1:
        every_day = sorted({index for _regular_id, offs in demand
                            for index in offs})
        # Only when the day-offs really are staggered; overlapping ones
        # would mean two posts vacant at once, which no single guard can
        # man however free they are.
        if len(every_day) == sum(len(offs) for _rid, offs in demand):
            employee = choose(every_day) or choose(every_day, overflow=True)
            if employee is not None:
                admit(employee)
                pool.book(employee, every_day, kind)
                for regular_id, offs in demand:
                    plan.partner[(station_name, regular_id)] = employee
                    for index in offs:
                        plan.cover[(station_name, regular_id, index)] = employee
                overflow_note()
                return 0

    def cover_day(regular_id, index):
        """One vacancy, filled within the roster if at all possible and
        over the cap if that is the only way to man the post.

        The cap exists to keep the roster readable, not to send a guard
        home: leaving a post unmanned is a real operational hole, an
        extra name on the report is not. Overflow is counted and reported
        so the admin can see the station outgrew its band.
        """
        if book(regular_id, [index]) is not None:
            return True
        return book(regular_id, [index], overflow=True) is not None

    uncovered = 0
    absences = []
    for regular_id, offs in demand:
        # A leave is more days than one reliever may work at all. Held
        # back to the end so the ordinary two-day runs get first pick of
        # the roster and keep their single bound partner.
        if len(offs) >= LONG_ABSENCE_DAYS:
            absences.append((regular_id, offs))
            continue
        # Keeping the run whole outranks keeping the roster small. Two
        # names against one guard's two day-offs is exactly what the
        # RELIEVER column cannot express — an admin reading "Marco Garcia
        # (1) · Paolo Tolentino (1)" cannot tell which of them to expect
        # on which date — so an extra name on the station's roster is the
        # cheaper price, and it is reported either way.
        employee = book(regular_id, offs) or book(regular_id, offs,
                                                  overflow=True)
        if employee is not None:
            plan.partner[(station_name, regular_id)] = employee
            continue
        # Not even a fresh reliever could make every date. Splitting the
        # run is the last resort before leaving the post unmanned.
        for index in offs:
            if not cover_day(regular_id, index):
                uncovered += 1

    for regular_id, offs in absences:
        for index in offs:
            if not cover_day(regular_id, index):
                uncovered += 1

    overflow_note()
    return uncovered


def _cover_demand(duty, employees):
    """[(employeeId, [day_index, ...]), ...] — who at this station is off
    and when, in roster order, skipping anyone who is never off."""
    demand = []
    for employee in employees:
        offs = sorted(duty["day_offs"].get(employee["id"]) or ())
        if offs:
            demand.append((employee["id"], offs))
    return demand


def _plan_group_cover(line, group_stations, duty_of, relievers_at,
                      external_busy, external_days, night_locked,
                      day_locked, dates):
    """Settles every station's reliever cover for the whole period.

    Runs before any station's days are built, and walks the stations in
    line order so a reliever topping up away from home always does it at
    the next station along rather than jumping the line.

    NIGHT IS PLANNED FIRST. A night reliever is locked to nights for all
    15 days, so if the day pass ran first it would claim relievers the
    night posts then had nobody to fill them with.
    """
    plan = _CoverPlan()
    pool = _CoverPool(external_busy, external_days)
    for emp_id in night_locked:
        pool.locked[emp_id] = "night"
    for emp_id in day_locked:
        pool.locked[emp_id] = "day"

    ordered = sorted(group_stations,
                     key=lambda s: line.get(s["name"].strip(), 0))
    for kind in ("night", "day"):
        for station in ordered:
            name = station["name"].strip()
            duty = duty_of[name]
            day_slots, night_slots = reliever_roster_size(station)
            slots = night_slots if kind == "night" else day_slots
            by_shift = duty["regulars_by_shift"]
            regulars = (by_shift["night"] if kind == "night"
                        else by_shift["morning"] + by_shift["afternoon"])
            demand = _cover_demand(duty, regulars)
            if not demand:
                continue
            uncovered = _fill_station_cover(
                plan, pool, name, kind, slots,
                _reliever_candidates(line, name, relievers_at),
                demand, dates, bundle=(kind == "night"))
            if uncovered:
                label = "night" if kind == "night" else "morning/afternoon"
                plan.notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_COVER,
                    schedule_notes.SEVERITY_WARNING,
                    name,
                    f"{uncovered} {label} day-off(s) have nobody covering "
                    f"them — the post is unmanned on those dates. The "
                    f"station is set up for "
                    f"{station_required_total(station)} guards, which allows "
                    f"{slots} {label} reliever(s), and no reliever within "
                    f"{station_pools.MAX_STATION_DISTANCE} stops still had "
                    f"days left.",
                    "Assign more relievers near this station, or lower its "
                    "required numbers in Edit Station.",
                    station=name))
    return plan, pool


def _entry(entry_id, employee, shift, post, window=None, is_reliever=False,
           covering_for=None, borrowed_from=None):
    return {
        "id": entry_id,
        "employeeId": employee["id"],
        "employeeName": employee.get("name", ""),
        "shift": shift,
        # The post being manned. Covering entries carry the covered
        # guard's post — the cover mans the same spot.
        "post": post,
        # That post's duty window, "HH:MM", straight off the station's
        # stagger ladder (Edit Station). Carried on the entry rather than
        # looked up from the shift name because two guards on the same
        # shift now start two hours apart. A cover inherits the covered
        # guard's window along with their post — same spot, same hours.
        # None only on a station with no setup at all, where the reader
        # falls back to the shift's base window.
        "timeIn": (window or {}).get("start"),
        "timeOut": (window or {}).get("end"),
        "isReliever": is_reliever,
        "coveringFor": covering_for,
        # True when this guard is at this station because an admin pinned
        # them here for the cycle rather than because rotation put them
        # here. Purely informational — the UI badges these rows.
        "isSpecial": employee.get(SPECIAL_FLAG, False),
        # Set to the guard's home station when they were pulled in from
        # another station (sister-station or adjacent-group fallback).
        "borrowedFrom": borrowed_from,
    }


def _station_head_guards(staff):
    """The station's own head guards, split by their 12-hour duty.

    Pinned head guards lead each list so the head-guard cap below cuts
    the station's own surplus rather than the guard the admin placed
    here by hand (see _pinned_first).
    """
    hg_day, hg_night = [], []
    for emp in _pinned_first(staff):
        if emp.get("type") != "headGuard":
            continue
        if emp.get("assignedShift") == "hgDay":
            hg_day.append(emp)
        elif emp.get("assignedShift") == "hgNight":
            hg_night.append(emp)
    return hg_day, hg_night


def resolve_head_guards(station, staff, sub_view, period_dates):
    """Settles who mans this station's Head Guard posts for the period,
    capped by the number the station's setup asks for.

    Returns (hg_day, hg_night, notes). The Head Guard slot is part of the
    Morning and Night figures, so a station holding more head guards than
    slots leaves the surplus unscheduled, and one holding fewer has the
    post held all period by a floating substitute. This is what keeps a
    station set up for 15 at 15 — before it, head guards bypassed the cap
    entirely and the daily headcount drifted by one in whichever
    direction the station's head guards happened to be over or under.

    Run for EVERY station before any station's days are built. The
    substitute pool is shared and a standing substitute has to be free
    for all 15 days: resolving station by station would let the first
    station's day-off cover nibble days off the last free substitute and
    leave a later station unable to fill its post at all.
    """
    station_name = station["name"].strip()
    hg_day, hg_night = _station_head_guards(staff)
    notes = []

    for shift_key, hgs in (("morning", hg_day), ("night", hg_night)):
        cap = _head_guard_cap(station, shift_key)
        if cap is None:
            continue
        label = SHIFT_LABELS[shift_key]
        if len(hgs) > cap:
            surplus = ", ".join(e.get("name", e["id"]) for e in hgs[cap:])
            pinned = sum(1 for e in hgs[:cap] if e.get(SPECIAL_FLAG))
            del hgs[cap:]
            notes.append(schedule_notes.note(
                schedule_notes.CATEGORY_HEAD_GUARD,
                schedule_notes.SEVERITY_WARNING,
                f"{station_name} — {label}",
                f"Set up for {cap} head guard post(s), but more head guards "
                f"are assigned here. {surplus} left unscheduled this period."
                + (f" {pinned} specially assigned head guard(s) hold the "
                   f"post(s) this cycle." if pinned else ""),
                "Move them to a station that has no head guard.",
                station=station_name))
        while len(hgs) < cap:
            standing = sub_view.reserve(
                period_dates,
                exclude_ids={e["id"] for e in hg_day + hg_night})
            if standing is None:
                notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_HEAD_GUARD,
                    schedule_notes.SEVERITY_BLOCKER,
                    f"{station_name} — {label}",
                    "The Head Guard post is unmanned for the whole period. "
                    "No head guard is assigned to this station and no "
                    "substitute was free to hold it.",
                    f"Assign a head guard to {station_name}.",
                    station=station_name))
                break
            hgs.append(standing)
            notes.append(schedule_notes.note(
                schedule_notes.CATEGORY_HEAD_GUARD,
                schedule_notes.SEVERITY_INFO,
                f"{station_name} — {label}",
                f"No head guard is assigned to this station, so substitute "
                f"{standing.get('name', standing['id'])} holds the Head "
                f"Guard post for the whole period.",
                f"Assign a permanent head guard to {station_name} if this "
                f"shouldn't keep falling to a substitute.",
                station=station_name))

    # Pin priority has done its job (deciding who survived the cap), so
    # hand the lists back in plain ID order — the day-off stagger below
    # walks them by index and shouldn't shift for everyone else just
    # because one guard is pinned here.
    return _sorted_by_id(hg_day), _sorted_by_id(hg_night), notes


def _plan_station_duty(station, staff, head_guards, station_offset=0,
                       special_offs=None, leave_offs=None):
    """Who works which post at this station, and when they are off.

    Everything about the station's period that does NOT depend on the
    reliever pool: the shift rosters after the station's caps, each
    guard's fixed post and duty window, and the day-off stagger. Split
    out of _build_station_schedule because the cover planner has to know
    every station's vacancies before it can decide who fills any of them
    (_plan_group_cover).

    head_guards is (hg_day, hg_night) as already settled by
    resolve_head_guards — capped to the station's number and topped up
    with standing substitutes where the station has none of its own.

    station_offset staggers this station's day-offs relative to the other
    stations on the line — without it every station would fall due on the
    same dates and the shared reliever and substitute pools couldn't
    cover them all.

    Returns {"regulars_by_shift", "post_of", "time_of", "day_offs",
    "notes"}.
    """
    station_name = station["name"].strip()

    regulars_by_shift = {"morning": [], "afternoon": [], "night": []}
    hg_day, hg_night = head_guards

    # Pinned guards lead every shift list: the cap below cuts from the
    # end, and a Special Assignment must never be the thing that gets
    # cut (see _pinned_first).
    for emp in _pinned_first(staff):
        if emp.get("type") != "regular":
            continue
        shift = emp.get("assignedShift")
        if shift in regulars_by_shift:
            regulars_by_shift[shift].append(emp)

    # Each shift takes exactly as many guards as its setup asks for. More
    # regulars assigned to the station than the shift has posts means the
    # surplus sits out this period — reported by name, because the fix is
    # the admin's call: raise the number in Edit Station, or move those
    # guards to a station that needs them.
    notes = []
    configured_posts = station.get("posts") or {}
    for shift_key in ("morning", "afternoon", "night"):
        cap = _regular_cap(station, shift_key)
        regulars = regulars_by_shift[shift_key]
        if cap is None or len(regulars) <= cap:
            continue
        regulars_by_shift[shift_key] = regulars[:cap]
        surplus = ", ".join(e.get("name", e["id"]) for e in regulars[cap:])
        pinned = sum(1 for e in regulars[:cap] if e.get(SPECIAL_FLAG))
        label = SHIFT_LABELS[shift_key]
        if POST_HEAD_GUARD in (configured_posts.get(shift_key) or []):
            asked = f"{cap + 1} ({cap} plus the head guard)"
        else:
            asked = str(cap)
        notes.append(schedule_notes.note(
            schedule_notes.CATEGORY_STAFFING,
            schedule_notes.SEVERITY_WARNING,
            f"{station_name} — {label}",
            f"Set up for {asked}, but {len(regulars)} regular guard(s) are "
            f"assigned here. {surplus} left unscheduled this period."
            + (f" {pinned} of the posts are held by specially assigned "
               f"guard(s) this cycle, which is why the station is over "
               f"its number." if pinned else ""),
            f"Raise the {label} number in Edit Station, or move them to "
            f"another station.",
            station=station_name))

    # Cap settled — back to plain ID order so posts and day-offs land the
    # same way they always did. Pin priority decides WHO is on the shift,
    # not where they stand on it.
    for shift_key in ("morning", "afternoon", "night"):
        regulars_by_shift[shift_key] = _sorted_by_id(
            regulars_by_shift[shift_key])

    # Fixed post per guard for the whole period, handed out in ID order
    # from the station's own per-shift post lists (Edit Station). Guards
    # past the configured posts start Undefined and must be assigned by
    # the admin before the schedule can be published; posts with nobody
    # left to man them are reported below.
    # Alongside the post, the window that post is manned for. The station's
    # stagger ladder decides it (station_posts.regular_windows), so the two
    # guards sharing a shift's base window and the third one starting two
    # hours later all come out of the same setup the admin sees.
    post_of = {}
    time_of = {}
    for shift_key in ("morning", "afternoon", "night"):
        posts = _shift_posts(station, shift_key)
        if posts is None:
            # Station never configured: the old fixed behaviour.
            posts = ([POST_ROVING] * len(regulars_by_shift[shift_key])
                     if shift_key == "night" else list(STANDARD_POSTS))
        regulars = regulars_by_shift[shift_key]
        windows = station_posts.regular_windows(
            station, shift_key, len(regulars))
        for i, emp in enumerate(regulars):
            post_of[emp["id"]] = (posts[i] if i < len(posts)
                                  else POST_UNDEFINED)
            time_of[emp["id"]] = windows[i] if i < len(windows) else None
        # More posts than bodies: the station is short-staffed for this
        # shift. Generate anyway and name the posts nobody is manning.
        if len(regulars) < len(posts):
            unmanned = posts[len(regulars):]
            notes.append(schedule_notes.note(
                schedule_notes.CATEGORY_STAFFING,
                schedule_notes.SEVERITY_BLOCKER,
                f"{station_name} — {SHIFT_LABELS[shift_key]}",
                f"{len(posts)} post(s) set up but only {len(regulars)} "
                f"guard(s) assigned here, so nobody is manning "
                + ", ".join(p if p != POST_UNDEFINED else "(unnamed post)"
                            for p in unmanned)
                + ".",
                f"Assign more regular guards to {station_name}, or lower "
                f"its {SHIFT_LABELS[shift_key]} number in Edit Station.",
                station=station_name))
    # The head guards' 12-hour duties are fixed and outside the ladder.
    for hg_list, hg_label in ((hg_day, "HG Day"), (hg_night, "HG Night")):
        for emp in hg_list:
            post_of[emp["id"]] = POST_HEAD_GUARD
            time_of[emp["id"]] = station_posts.head_guard_window(hg_label)

    # Day-off plan: employeeId -> set of off day-indices.
    day_offs = {}
    for shift, regs in regulars_by_shift.items():
        if shift == "night":
            # Explicit stagger for the night pair: their off-days must
            # never land on the same date, because one night reliever
            # covers all of this station's night vacancies.
            for i, emp in enumerate(regs):
                day_offs[emp["id"]] = _night_day_offs(i, station_offset)
            continue
        for emp, offs in zip(regs, _spread_day_offs(len(regs),
                                                    station_offset)):
            day_offs[emp["id"]] = set(offs)
    # Head guard day-offs, staggered away from each other AND across
    # stations (station_offset) so the shared substitute pool keeps up.
    for i, emp in enumerate(hg_day):
        day_offs[emp["id"]] = {(4 + i + station_offset) % PERIOD_DAYS,
                               (11 + i + station_offset) % PERIOD_DAYS}
    for i, emp in enumerate(hg_night):
        day_offs[emp["id"]] = {(6 + i + station_offset) % PERIOD_DAYS,
                               (13 + i + station_offset) % PERIOD_DAYS}

    # Approved leave short enough to leave the guard on the roster — a
    # leave clipped by the period edge, mostly. It REPLACES the ordinary
    # day-offs rather than stacking on top of them: two leave days plus
    # the usual two off-days is a four-day run, which is long enough for
    # _fill_station_cover to give up on one partner and split it across
    # the roster, putting two names in a RELIEVER column that can only
    # honestly hold one. Off-days owed = PERIOD_DAYS - MAX_REGULAR_DAYS,
    # and the leave has already paid some of them.
    if leave_offs:
        owed = PERIOD_DAYS - MAX_REGULAR_DAYS
        for emp_id, on_leave in leave_offs.items():
            if emp_id not in day_offs:
                continue
            ordinary = sorted(day_offs[emp_id] - on_leave)
            keep = max(0, owed - len(on_leave))
            day_offs[emp_id] = set(on_leave) | set(ordinary[:keep])

    # Approved special day-off requests: force these regulars / head guards
    # off on their requested day-indices, on top of their regular off-days.
    # (Relievers and substitute head guards are handled by the caller via
    # the shared busy state, so they never appear in day_offs here.)
    if special_offs:
        for emp in staff:
            extra = special_offs.get(emp["id"])
            if extra and emp["id"] in day_offs:
                day_offs[emp["id"]].update(extra)

    return {
        "regulars_by_shift": regulars_by_shift,
        "post_of": post_of,
        "time_of": time_of,
        "day_offs": day_offs,
        "notes": notes,
    }


def _build_station_schedule(station, duty, cover_plan, sub_hg_tracker,
                            group, start_date, head_guards,
                            reliever_home=None):
    """Generates the 15-day schedule document for one station.
    Returns (schedule_doc, notes) — notes flag anything the admin should
    look at (e.g. night regulars beyond the cap left unscheduled).

    duty        : this station's plan from _plan_station_duty
    cover_plan  : the group-wide _CoverPlan, already settled, which says
                  who stands in for each guard on each of their days off
    sub_hg_tracker : this station's window onto the shared floating
                  substitute head guard pool

    head_guards is (hg_day, hg_night) as already settled by
    resolve_head_guards.
    """
    station_id = station["id"]
    station_name = station["name"].strip()
    hg_day, hg_night = head_guards
    regulars_by_shift = duty["regulars_by_shift"]
    post_of, time_of, day_offs = (duty["post_of"], duty["time_of"],
                                  duty["day_offs"])
    notes = list(duty["notes"])
    reliever_home = reliever_home or {}

    def borrowed_home(employee):
        """The station a reliever belongs to, or None when they are one
        of this station's own — badges cover pulled in from up the line.
        """
        home = reliever_home.get(employee["id"])
        return None if home == station_name else home

    # A head guard's two day-offs go to ONE substitute wherever the pool
    # allows it, for the same reason a regular's go to one reliever: the
    # roster report carries a single RELIEVER cell per guard, and a
    # different name against each date cannot be shown there honestly.
    sub_binding = {}
    for emp in hg_day + hg_night:
        offs = sorted(day_offs.get(emp["id"]) or ())
        if not offs:
            continue
        sub_binding[emp["id"]] = sub_hg_tracker.bind(
            offs, [(start_date + timedelta(days=i)).isoformat()
                   for i in offs],
            exclude_ids={e["id"] for e in hg_day + hg_night})

    night_cover_count = {e["id"]: 0 for e in regulars_by_shift["night"]}

    days = []
    uncovered = 0
    seq = 0

    for day_index in range(PERIOD_DAYS):
        day_date = start_date + timedelta(days=day_index)
        date_iso = day_date.isoformat()
        entries = []

        def add(employee, shift, post, window=None, is_reliever=False,
                covering_for=None, borrowed_from=None):
            nonlocal seq
            seq += 1
            entries.append(_entry(f"{station_id}_{day_index}_{seq}",
                                  employee, shift, post, window, is_reliever,
                                  covering_for, borrowed_from))

        # Regulars on duty + coverage for the ones who are off.
        for shift_key in ("morning", "afternoon", "night"):
            label = SHIFT_LABELS[shift_key]
            for emp in regulars_by_shift[shift_key]:
                if day_index not in day_offs[emp["id"]]:
                    add(emp, label, post_of[emp["id"]], time_of[emp["id"]])
                    continue
                # Whoever the group-wide plan bound to this guard's
                # day-offs. Settled before any day was built, so the same
                # reliever covers the whole run wherever one was free for
                # all of it (_plan_group_cover).
                cover = cover_plan.take(station_name, emp["id"], day_index)
                if cover is not None:
                    add(cover, label, post_of[emp["id"]], time_of[emp["id"]],
                        is_reliever=True, covering_for=emp["id"],
                        borrowed_from=borrowed_home(cover))
                elif shift_key == "night":
                    # No night reliever was free — fall back to the old
                    # internal switching by an on-duty night regular
                    # rather than leave the post unmanned.
                    others = [e for e in regulars_by_shift["night"]
                              if e["id"] != emp["id"]
                              and day_index not in day_offs[e["id"]]]
                    if others:
                        cover = min(others,
                                    key=lambda e: night_cover_count[e["id"]])
                        night_cover_count[cover["id"]] += 1
                        add(cover, label, post_of[emp["id"]],
                            time_of[emp["id"]], covering_for=emp["id"])
                    else:
                        uncovered += 1
                else:
                    uncovered += 1

        # Head guards + floating substitute coverage.
        for hg_list, hg_label in ((hg_day, "HG Day"), (hg_night, "HG Night")):
            hg_window = station_posts.head_guard_window(hg_label)
            for emp in hg_list:
                if day_index not in day_offs[emp["id"]]:
                    add(emp, hg_label, POST_HEAD_GUARD, hg_window)
                    continue
                sub = sub_binding.get(emp["id"]) or sub_hg_tracker.pick(
                    day_index, date_iso,
                    exclude_ids={e["id"] for e in hg_day + hg_night})
                if sub is not None:
                    add(sub, hg_label, POST_HEAD_GUARD, hg_window,
                        covering_for=emp["id"])
                else:
                    uncovered += 1

        days.append({"date": day_date.isoformat(), "entries": entries})

    end_date = start_date + timedelta(days=PERIOD_DAYS - 1)
    return {
        "id": f"{station_id}_{start_date.isoformat()}",
        "stationId": station_id,
        "stationName": station_name,
        "group": group,
        "startDate": start_date.isoformat(),
        "endDate": end_date.isoformat(),
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "status": "unpublished",
        "uncoveredPosts": uncovered,
        "days": days,
    }, notes


def generate_group_schedules(db, group, start_date, rotate=True):
    """Generates one bi-weekly schedule per station in the group.
    Returns the list of schedule documents (not yet written to Firestore).

    When `rotate` is on, the monthly rotation engine decides which station
    each guard works at for this cycle (see rotation.py); otherwise every
    guard stays at their permanent `assignedStation`."""
    if group not in GROUP_RANGES:
        raise ValueError(f"group must be 1, 2 or 3 (got {group})")
    if not isinstance(start_date, date):
        raise ValueError("start_date must be a date")

    stations = repositories.from_db(db).stations.list()
    stations.sort(key=lambda s: s.get("id", ""))
    lo, hi = GROUP_RANGES[group]
    group_stations = stations[lo:hi]
    if not group_stations:
        raise ValueError(f"no stations found for group {group}")

    employees = [doc.to_dict()
                 for doc in db.collection("employees").stream()
                 if doc.to_dict().get("isActive", True)]

    # Station placement for this cycle. Floating substitute head guards
    # have no home station and are never rotated — they already float
    # across their preferredStations window.
    # Admin pins for the cycle this period falls in. Loaded before
    # rotation so the rotation engine can leave pinned guards alone.
    cycle_id = rotation.build_cycle_id(start_date)
    # A 15-day period started late in the month runs into the next one,
    # and the pins the admin saved for THAT month cover most of the days
    # being generated — so load them too (the period's own cycle still
    # wins for anyone pinned in both).
    end_cycle_id = rotation.build_cycle_id(
        start_date + timedelta(days=PERIOD_DAYS - 1))
    specials = load_special_assignments(
        db, cycle_id,
        also_cycle_ids=() if end_cycle_id == cycle_id else (end_cycle_id,))

    rotation_warnings = []
    placement = {}
    if rotate:
        placement, rotation_warnings = rotation.resolve_placement(
            db, group, group_stations, employees, start_date,
            specials=specials)

    group_station_names = {s["name"].strip() for s in group_stations}

    # Approved leave, read before anybody is bucketed onto a station: a
    # guard on a long leave doesn't hold a post this period at all, and
    # who replaces them has to be decided while the bench is still whole
    # (_excuse_long_leave). Short leaves are day-offs and go through the
    # ordinary cover mechanism further down.
    leave_approved, leave_pending = load_leaves(db, start_date)
    long_leave = long_leave_ids(leave_approved)
    name_of = {e["id"]: e.get("name", e["id"]) for e in employees}

    staff_by_station = {}
    floating_subs = []
    bench = []
    special_notes = []
    for emp in employees:
        pin = specials.get(emp["id"])
        if pin:
            # A pin outranks both the rotation placement and the
            # employee's permanent station, and it applies whether or not
            # rotation ran — that is the whole point of pinning. Note the
            # `continue`: a guard pinned to some other group's station
            # deliberately does NOT get added to their home station here,
            # so they can't be scheduled in two places at once.
            effective = _apply_special(emp, pin)
            station = effective["assignedStation"]
            if station:
                staff_by_station.setdefault(station, []).append(effective)
            home = (emp.get("assignedStation") or "").strip()
            if home and home != station and home in group_station_names:
                # Pins are manual overrides, so unlike rotation they don't
                # preserve each station's headcount — someone pinned away
                # leaves a post behind them. Surfaced rather than fixed.
                special_notes.append(schedule_notes.note(
                    schedule_notes.CATEGORY_ASSIGNMENT,
                    schedule_notes.SEVERITY_WARNING,
                    emp.get("name", emp["id"]),
                    f"Pinned to {station} this cycle, leaving {home} one "
                    f"guard short.",
                    f"Assign someone else to {home} for this cycle, or drop "
                    f"the pin in Special Assignments.",
                    station=home))
            continue

        assigned = emp.get("assignedStation")
        if assigned:
            # The rotation placement overrides the permanent station for
            # the duration of this cycle. An explicit None means the
            # placement engine found no station in the group with a slot
            # for them — they sit the period out rather than being pushed
            # onto their home station and putting it over its number.
            # (placement.py reports them by name in the notes.)
            if emp["id"] in placement and placement[emp["id"]] is None:
                # Idle this period — and therefore exactly who takes the
                # post of a guard going on leave (_excuse_long_leave).
                if emp["id"] not in long_leave:
                    bench.append(emp)
                continue
            station = placement.get(emp["id"]) or assigned.strip()
            staff_by_station.setdefault(station, []).append(emp)
        elif emp.get("type") == "headGuard":
            # A floating substitute on a long leave is out of the pool
            # entirely: unlike a station's own guards there is no post of
            # theirs to fill, they simply can't be drawn on. A shorter
            # leave leaves them in — the busy-date mechanism below keeps
            # them off the days themselves.
            if emp["id"] not in long_leave:
                floating_subs.append(emp)

    # Guards on a long approved leave come off the roster here, before a
    # single day is planned, and their post is handed to a regular. Done
    # after the whole group is bucketed because the replacement may come
    # from any station's surplus or from the group-wide bench.
    leave_swap_notes = []
    long_leave_handled = set()
    if long_leave:
        long_leave_handled, leave_swap_notes = _excuse_long_leave(
            staff_by_station, group_stations, long_leave, bench, name_of)

    # Guards bucketed under a name no station carries can never be
    # scheduled anywhere — that happens when stations are deleted and
    # re-created under new names while employee records still point at
    # the old name. Surface it loudly instead of silently generating
    # schedules without them.
    all_station_names = {s["name"].strip() for s in stations}
    stranded_notes = [
        schedule_notes.note(
            schedule_notes.CATEGORY_STAFFING,
            schedule_notes.SEVERITY_BLOCKER,
            st_name,
            f"{len(staff)} guard(s) are assigned to '{st_name}', which "
            f"matches no existing station, so they were left out of this "
            f"schedule entirely.",
            "Fix the station on their employee records, or rename stations "
            "via Edit Station (which keeps employee records in sync).")
        for st_name, staff in sorted(staff_by_station.items())
        if st_name.strip() not in all_station_names
    ]

    # Commitments already saved in other groups' schedules for this
    # period — the guard rail that keeps every fallback below from
    # double-booking or overworking anyone.
    (external_busy, external_days,
     night_locked, day_locked) = _load_period_commitments(
        db, group, start_date)

    # Employee-filed special day-off requests falling in this period.
    # Approved ones are granted here; pending ones only produce a note so
    # the admin can decide before trusting the roster. Only the employees
    # this group is actually scheduling are affected.
    special_approved, special_pending = load_special_requests(db, start_date)
    # Leave (loaded above) lands in the same buckets: whatever is left of
    # it after _excuse_long_leave is a run of day-offs the guard cannot be
    # scheduled through, so it needs no mechanism of its own.
    scheduled_ids = ({e["id"] for staff in staff_by_station.values()
                      for e in staff}
                     | {s["id"] for s in floating_subs})

    # A reliever or substitute head guard is taken off a requested date by
    # marking them busy on it — the very mechanism that already keeps them
    # from being double-booked across groups, so coverage flows to the next
    # tier automatically. Regular and head-guard day-offs are applied by
    # index inside _build_station_schedule.
    # Leave is kept in its own index rather than folded in with the
    # special requests: a requested day-off is granted on top of the
    # guard's ordinary two, a leave takes their place (_plan_station_duty).
    special_off_index = {}
    leave_off_index = {}
    external_busy = set(external_busy)
    for source, index in ((special_approved, special_off_index),
                          (leave_approved, leave_off_index)):
        for emp_id, iso_dates in source.items():
            if emp_id not in scheduled_ids:
                continue
            for iso in iso_dates:
                external_busy.add((emp_id, iso))
                idx = (datetime.strptime(iso, "%Y-%m-%d").date()
                       - start_date).days
                index.setdefault(emp_id, set()).add(idx)

    # Leave is reported whether approved or not: an approved one is a
    # standing hole in the roster the admin should see coming, and a
    # pending one is a decision still owed before the roster is trusted.
    # The long ones _excuse_long_leave already dealt with are reported by
    # it instead, with the name of whoever took the post.
    leave_notes = leave_swap_notes + [
        schedule_notes.note(
            schedule_notes.CATEGORY_LEAVE,
            schedule_notes.SEVERITY_INFO,
            name_of.get(emp_id, emp_id),
            f"Away on approved leave for {iso_dates[0]} to {iso_dates[-1]} "
            f"— {len(iso_dates)} of the {PERIOD_DAYS} days in this period.",
            "Their day-offs are covered by their reliever, so nothing is "
            "owed here.")
        for emp_id, iso_dates in sorted(leave_approved.items())
        if emp_id in scheduled_ids and emp_id not in long_leave_handled
    ] + [
        schedule_notes.note(
            schedule_notes.CATEGORY_LEAVE,
            schedule_notes.SEVERITY_WARNING,
            name_of.get(emp_id, emp_id),
            f"Has a pending leave request covering {iso_dates[0]} to "
            f"{iso_dates[-1]} in this period, so they are rostered as if "
            f"they will be working.",
            "Approve or deny it, then regenerate this schedule.")
        for emp_id, iso_dates in sorted(leave_pending.items())
        if emp_id in scheduled_ids
    ]

    special_request_notes = [
        schedule_notes.note(
            schedule_notes.CATEGORY_REQUEST,
            schedule_notes.SEVERITY_WARNING,
            name_of.get(emp_id, emp_id),
            f"Has a pending special day-off request for "
            f"{', '.join(iso_dates)} in this period, so they are rostered "
            f"as if they will be working.",
            "Approve or deny it, then regenerate this schedule.")
        for emp_id, iso_dates in sorted(special_pending.items())
        if emp_id in scheduled_ids
    ]

    # Physical order of the line, which is what "nearest station" means:
    # stations are stored in the order they run, so the gap between two
    # positions is how many stops apart they are.
    line = station_pools.line_order(stations)

    # Where each reliever sits this cycle (bucket key = station after
    # rotation/pins), for the reach calculation and the borrowedFrom badge.
    # Bucketed by the station their radius is measured from — their
    # permanent one — so that every group's run agrees on where a
    # reliever is based and on who is therefore in reach of what
    # (_reach_anchor explains why the rotated station can't be used).
    relievers_at = {}
    reliever_home = {}
    for st_name, staff in staff_by_station.items():
        for emp in staff:
            if emp.get("type") == "reliever":
                anchor = _reach_anchor(emp, st_name)
                relievers_at.setdefault(anchor, []).append(emp)
                reliever_home[emp["id"]] = anchor

    # One usage state for the substitute pool for the whole generation
    # run, so nobody is booked at two stations on the same date.
    sub_state = _SubUsageState(external_busy, external_days)

    # Substitute head guards each station can reach, nearest first.
    sub_views = {
        station["name"].strip(): _StationSubView(
            sub_state,
            _sub_candidates(line, station["name"].strip(), floating_subs))
        for station in group_stations
    }

    # Settle every station's Head Guard posts BEFORE building any days.
    # A substitute standing in for a missing head guard has to be free
    # for the whole period, so the reservations have to be made while the
    # pool is still untouched — resolving them station by station inside
    # the loop let the first station's day-off cover use up the days the
    # last station needed (see resolve_head_guards).
    period_dates = [(start_date + timedelta(days=i)).isoformat()
                    for i in range(PERIOD_DAYS)]
    head_guards_of = {}
    head_guard_notes = []
    for station in group_stations:
        name = station["name"].strip()
        hg_day, hg_night, hg_notes = resolve_head_guards(
            station, staff_by_station.get(name, []), sub_views[name],
            period_dates)
        head_guards_of[name] = (hg_day, hg_night)
        head_guard_notes.extend(hg_notes)

    # Every station's posts and day-offs, settled next — the cover
    # planner has to see the whole group's vacancies before it can decide
    # who fills any of them.
    duty_of = {}
    for station in group_stations:
        name = station["name"].strip()
        duty_of[name] = _plan_station_duty(
            station,
            staff_by_station.get(name, []),
            head_guards_of[name],
            # Position on the line, not position within the group, so the
            # day-off stagger decorrelates neighbouring stations even
            # across a group boundary — the shared pools reach over it.
            station_offset=line.get(name, 0),
            special_offs=special_off_index,
            leave_offs=leave_off_index,
        )

    # Who covers whom, for the whole group at once. Bound (one reliever
    # per guard) and packed (as few relievers as the roster caps allow,
    # each as close to their 12 days as the dates permit).
    cover_plan, _cover_pool = _plan_group_cover(
        line, group_stations, duty_of, relievers_at, external_busy,
        external_days, night_locked, day_locked, period_dates)

    schedules = []
    # Kept apart rather than poured into one list: each of these files
    # under its own heading, and merging them is what used to label a
    # head-guard problem as a rotation problem.
    staffing_notes = []
    for station in group_stations:
        name = station["name"].strip()
        doc, coverage_notes = _build_station_schedule(
            station,
            duty_of[name],
            cover_plan,
            sub_views[name],
            group,
            start_date,
            head_guards=head_guards_of[name],
            reliever_home=reliever_home,
        )
        staffing_notes.extend(coverage_notes)
        doc["rotated"] = rotate
        doc["rotationCycleId"] = cycle_id
        # Who on this roster is here by admin pin, so Schedule Detail can
        # show it without re-querying the pins collection.
        doc["specialAssignments"] = [
            {"employeeId": p["employeeId"],
             "employeeName": p.get("employeeName", ""),
             "shift": p.get("shift")}
            for p in specials.values()
            if (p.get("stationName") or "").strip() == name
        ]
        schedules.append(doc)

    # rotation_warnings already arrives structured (rotation.py and the
    # placement engine below it file their own), and its first entry is
    # always the run summary — "Rotated N of M guards…", the one piece of
    # good news in the list.
    notes = (rotation_warnings + stranded_notes + staffing_notes
             + head_guard_notes + cover_plan.notes + special_notes
             + special_request_notes + leave_notes)
    if notes:
        for doc in schedules:
            # Structured form, which the admin screens group and rank by.
            doc["scheduleNotes"] = notes
            # Flat one-line form, still written so schedules generated
            # now stay readable to anything that predates the structure.
            doc["rotationNotes"] = schedule_notes.texts(notes)
    return schedules


class _SubUsageState:
    """Group-wide booking state for floating substitute head guards.

    external_busy holds their commitments in other groups' saved
    schedules for the same period, so a sub whose window straddles a
    group boundary can't be booked by both groups on one date, and
    external_days counts those days against their 12. Counting them
    matters: a substitute's window reaches four stops either way, which
    routinely straddles a group boundary, and without it each group
    granted them a fresh 12 days of its own — group 3 filling a sub to
    exactly 12 and group 2 then adding two more on top."""

    def __init__(self, external_busy=frozenset(), external_days=None):
        self.busy = set()  # (employeeId, day_index)
        self.days_worked = dict(external_days or {})
        self.external_busy = external_busy
        # Substitutes holding a station's vacant head guard post for the
        # whole period. They are booked solid, so they can never also be
        # picked to cover somebody's day-off somewhere else.
        self.standing = set()


class _StationSubView:
    """A station's view onto the shared substitute head guard pool.

    Scored exactly like _StationRelieverView, and for the same reason: a
    substitute covering only their own station's head guard finished the
    period on 2 working days, because a station head guard takes just two
    day-offs in 15. Now every substitute within MAX_STATION_DISTANCE
    stops is a candidate and the one furthest from their 12 days is taken
    first, so their Head Guard cover is spread down the line.

    A substitute has no assigned station — they float across the window
    of stations they picked — so their distance to a station is measured
    from the nearest station in that window.

    `candidates` is [(employee, distance, prefers_this_station), ...].
    """

    def __init__(self, state, candidates):
        self._state = state
        self._candidates = candidates

    def reserve(self, period_dates, exclude_ids=()):
        """Takes one substitute out of the pool to hold this station's
        vacant Head Guard post for the WHOLE period, and returns them.

        A station with no head guard of its own would otherwise run a
        body short every day of the period. The substitute is rostered
        exactly like a station head guard from here on — same 13-day
        pattern, and their own two day-offs are covered by another
        substitute through pick(), which skips them because the caller
        excludes everyone already on the station's head guard roster.

        Booking is all-or-nothing: a substitute already used on any day
        of this period, or committed in another group's schedule for it,
        is not free to stand in for 15 days. Returns None when no tier
        has anyone free.
        """
        st = self._state
        candidates = [
            (e, dist) for e, dist, _prefers in self._candidates
            if e["id"] not in exclude_ids
            and e["id"] not in st.standing
            and not any((e["id"], i) in st.busy
                        for i in range(len(period_dates)))
            and not any((e["id"], iso) in st.external_busy
                        for iso in period_dates)
        ]
        if not candidates:
            return None
        # Holding a post for 15 straight days is a posting, not a relief
        # run, so this one picks the NEAREST free substitute rather than
        # the least-worked: whoever takes it is commuting there daily for
        # the whole period.
        chosen, _dist = min(
            candidates,
            key=lambda pair: (pair[1], st.days_worked.get(pair[0]["id"], 0),
                              pair[0]["id"]))
        st.standing.add(chosen["id"])
        for i in range(len(period_dates)):
            st.busy.add((chosen["id"], i))
        # The two day-offs they still get are covered by someone
        # else, so the workload they carry is the same 13 days a
        # station head guard works.
        st.days_worked[chosen["id"]] = (
            st.days_worked.get(chosen["id"], 0) + MAX_REGULAR_DAYS)
        return chosen

    def bind(self, day_indices, dates, exclude_ids=()):
        """Books ONE substitute for a head guard's whole run of day-offs.

        The counterpart of binding a reliever to a regular: the roster
        report carries one RELIEVER cell per guard, so a head guard's two
        day-offs going to two different substitutes cannot be shown there
        honestly. All-or-nothing — returns None when nobody is free for
        every date, and the caller falls back to pick() per day.

        Packs rather than spreads, for the same reason _fill_station_cover
        does: the substitute nearest their 12 days is taken first, so the
        cover that exists lands on as few of them as possible instead of
        a day apiece across everyone in reach.
        """
        st = self._state
        best, best_key = None, None
        for employee, dist, prefers in self._candidates:
            emp_id = employee["id"]
            if emp_id in exclude_ids or emp_id in st.standing:
                continue
            worked = st.days_worked.get(emp_id, 0)
            if worked + len(day_indices) > MAX_RELIEVER_DAYS:
                continue
            if any((emp_id, i) in st.busy for i in day_indices):
                continue
            if any((emp_id, iso) in st.external_busy for iso in dates):
                continue
            key = (0 if worked else 1, -worked, dist,
                   0 if prefers else 1, emp_id)
            if best_key is None or key < best_key:
                best, best_key = employee, key
        if best is None:
            return None
        for index in day_indices:
            st.busy.add((best["id"], index))
        st.days_worked[best["id"]] = (
            st.days_worked.get(best["id"], 0) + len(day_indices))
        return best

    def pick(self, day_index, date_iso, exclude_ids=()):
        """One day's cover, for when bind() found nobody free for the
        whole run. Same packing order, one date at a time."""
        st = self._state
        best, best_key = None, None
        for employee, dist, prefers in self._candidates:
            emp_id = employee["id"]
            if emp_id in exclude_ids:
                continue
            if (emp_id, day_index) in st.busy:
                continue
            if (emp_id, date_iso) in st.external_busy:
                continue
            # Substitutes are capped at the same 12 days as relievers.
            # They had no cap at all before, which never bit only because
            # the old tiering could not find them enough work to hit one.
            worked = st.days_worked.get(emp_id, 0)
            if worked >= MAX_RELIEVER_DAYS:
                continue
            key = (0 if worked else 1, -worked, dist,
                   0 if prefers else 1, emp_id)
            if best_key is None or key < best_key:
                best, best_key = employee, key
        if best is None:
            return None
        st.busy.add((best["id"], day_index))
        st.days_worked[best["id"]] = st.days_worked.get(best["id"], 0) + 1
        return best
