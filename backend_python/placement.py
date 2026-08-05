"""
Demand-driven station placement.

Where the old engine asked "who works here, and where do we move them?",
this one asks "what does this station need, and who best fills it?" —
which is the only way the number typed into Edit Station can be the
number that lands on the schedule. Each station declares, per shift, how
many head guards and how many regulars it takes (station_posts.shift_slots);
placement fills exactly those slots and nothing else, so a station set up
for 15 rosters 15.

--------------------------------------------------------------------
PREFERRED STATIONS ARE A TARGET, NOT A PROMISE

Guards pick preferred stations, but stations have fixed sizes, so not
everyone can have what they asked for. Each cohort is therefore steered
to a SHARE of preference hits rather than to a per-guard guarantee:

    regular / head guard   85-90% land on a station they listed
    reliever               60-75%

The exact share is drawn per cycle from the range, so consecutive cycles
don't reshuffle to the same fixed quota. Landing on ANY station in the
guard's `preferredStations` list counts as a hit — the list is unordered
in the UI, so there is no "first choice" to honour.

The share is a ceiling as much as a floor. The engine first computes the
MAXIMUM number of hits the cohort could possibly get (a capacity-limited
bipartite matching), then deliberately breaks matches at random until it
is down to the drawn target. Without that step a group whose guards all
listed the same five stations would land near 100% every cycle and
nobody would ever move.

Where the two pull against each other, the station's headcount wins: a
post is never left unmanned to protect somebody's preference.

--------------------------------------------------------------------
GUARDS WHO PICKED NOTHING

A guard with an empty `preferredStations` list is still deployable
anywhere — they just have NO_PREFERENCE_WEIGHT (a tenth) of the pull of
someone who asked for the station. That only bites when a cohort has
more guards than the stations ask for: the surplus sits the period out,
and the guards who never stated a preference are the ones most likely to
be it. They are reported by name, never silently dropped.

--------------------------------------------------------------------
FAMILIARIZATION

Stations still keep ANCHOR_TARGET guards who were already there, chosen
the same way as before (someone who anchored last cycle goes last, and
anchors are spread across shifts). Anchors are placed first and consume
their station's slots; everyone else is allocated by preference around
them.
"""

import random

import schedule_notes
import station_posts

# Share of a cohort that should land on a station the guard actually
# asked for, drawn per cycle from the range.
PREFERRED_TARGET = {
    "regular": (0.85, 0.90),
    "headGuard": (0.85, 0.90),
    "reliever": (0.60, 0.75),
}
DEFAULT_TARGET = (0.85, 0.90)

# How much pull a guard who listed no preferred stations has, relative to
# one who listed this station. Decides who sits out when a cohort has
# more guards than slots — it is not a chance of being deployed.
NO_PREFERENCE_WEIGHT = 0.10

# Guards per station who were already there and stay, for familiarization.
ANCHOR_TARGET = 2

# The shift a station's head guard slots are filled from. The afternoon
# has none of its own — the day HG's 12-hour duty covers it.
HG_SHIFT_OF = {"morning": "hgDay", "night": "hgNight"}

RELIEVER_COHORT = ("reliever", None)


def cohort_key(employee):
    """The pool an employee is allocated within. Relievers are one pool
    per group regardless of the shift on their record: they float across
    a station's shifts as cover, so splitting them by shift would fence
    off relievers the station needs."""
    etype = employee.get("type")
    if etype == "reliever":
        return RELIEVER_COHORT
    return (etype, employee.get("assignedShift"))


def preferred_of(employee):
    return [p.strip() for p in (employee.get("preferredStations") or [])
            if p and p.strip()]


def _pull(employee):
    return 1.0 if preferred_of(employee) else NO_PREFERENCE_WEIGHT


def station_demand(station):
    """{(type, shift): slots} — what one station asks for.

    Head guard slots become the hgDay / hgNight cohorts because that is
    who mans them: the morning's Head Guard post is the station's day
    head guard, working their own 12-hour HG Day row.
    """
    demand = {}
    for shift_key in station_posts.SHIFT_KEYS:
        slots = station_posts.shift_slots(station, shift_key)
        if slots is None:
            continue
        head_guards, regulars = slots
        if regulars > 0:
            demand[("regular", shift_key)] = regulars
        hg_shift = HG_SHIFT_OF.get(shift_key)
        if head_guards > 0 and hg_shift:
            key = ("headGuard", hg_shift)
            demand[key] = demand.get(key, 0) + head_guards
    return demand


def reliever_demand(stations, total_relievers):
    """How many relievers each station gets.

    Relievers are cover, not posts, so no station declares a number for
    them. They are spread as evenly as the supply allows, with the spare
    ones going to the biggest stations first — every station needs at
    least one, because one of them is designated the night reliever for
    the period.
    """
    names = [s["name"].strip() for s in stations]
    if not names or total_relievers <= 0:
        return {name: 0 for name in names}
    base, extra = divmod(total_relievers, len(names))
    by_size = sorted(
        stations,
        key=lambda s: (-int(s.get("requiredEmployees") or 0), s["name"].strip()),
    )
    demand = {name: base for name in names}
    for station in by_size[:extra]:
        demand[station["name"].strip()] += 1
    return demand


# ---------------------------------------------------------------------------
# Who gets deployed at all
# ---------------------------------------------------------------------------

def _weighted_order(employees, rng):
    """Employees ordered by a weighted random draw, best first.

    Efraimidis-Spirakis: raising a uniform draw to the power 1/weight and
    taking the largest keys is a weighted sample without replacement, so
    a guard with no stated preference is a tenth as likely to come out
    near the front as one who named a station.
    """
    keyed = []
    for emp in employees:
        key = rng.random() ** (1.0 / _pull(emp))
        keyed.append((-key, emp.get("id", ""), emp))
    keyed.sort(key=lambda t: (t[0], t[1]))
    return [t[2] for t in keyed]


# ---------------------------------------------------------------------------
# Maximum preference matching
# ---------------------------------------------------------------------------

def _max_matching(employees, options_of, capacity):
    """The most guards that can simultaneously be placed, given each
    guard's list of allowed stations and each station's free slots.

    Used twice, in opposite directions: once over the stations each guard
    ASKED for, to find the ceiling on preference hits, and once over the
    stations they did NOT ask for, to park the guards being held back
    from their preference without accidentally handing it to them anyway.
    Doing the second pass as a matching rather than greedily matters —
    greedy leaves guards stranded with only preferred slots free, which
    pushes the achieved share back above target.

    Kuhn's augmenting-path algorithm with station capacities: when a
    guard's station is full, try to relocate one of its incumbents to
    another station they also allow and take the freed slot. `visited`
    bounds the recursion to the number of stations.

    Returns {employeeId: station}.
    """
    holders = {name: [] for name in capacity}
    assigned = {}

    def augment(emp_id, visited):
        for name in options_of.get(emp_id, ()):
            if name in visited or capacity.get(name, 0) <= 0:
                continue
            visited.add(name)
            if len(holders[name]) < capacity[name]:
                holders[name].append(emp_id)
                assigned[emp_id] = name
                return True
            for incumbent in list(holders[name]):
                if augment(incumbent, visited):
                    holders[name].remove(incumbent)
                    holders[name].append(emp_id)
                    assigned[emp_id] = name
                    return True
        return False

    for emp in employees:
        augment(emp["id"], set())
    return assigned


# ---------------------------------------------------------------------------
# One cohort
# ---------------------------------------------------------------------------

def _allocate_cohort(capacity, supply, rng, target_range):
    """Places one cohort's guards into one cohort's slots.

    Returns (assignment, benched) where assignment maps employeeId ->
    station and benched lists the guards the stations had no slot for.
    """
    capacity = {name: n for name, n in capacity.items() if n > 0}
    slots = sum(capacity.values())

    # Step 1 — a cohort with more guards than slots leaves the surplus
    # out, weighted so guards who stated a preference are kept first.
    ordered = _weighted_order(supply, rng)
    deployed, benched = ordered[:slots], ordered[slots:]
    if not deployed:
        return {}, benched

    # Step 2 — the ceiling: the most preference hits this cohort could
    # possibly get. Options are shuffled so a guard isn't always handed
    # whichever station they happened to list first.
    options_of = {}
    for emp in deployed:
        wanted = [name for name in preferred_of(emp) if name in capacity]
        rng.shuffle(wanted)
        options_of[emp["id"]] = wanted
    matched = _max_matching(deployed, options_of, capacity)

    # Step 3 — come down to the drawn share. Breaking matches at random
    # is what keeps guards moving between cycles instead of settling on
    # their preferred station forever.
    low, high = target_range
    target = int(round(rng.uniform(low, high) * len(deployed)))
    target = max(0, min(target, len(matched)))
    for emp_id in rng.sample(sorted(matched), len(matched) - target):
        del matched[emp_id]

    # Step 4 — everyone still unplaced fills what is left, on a station
    # they did NOT ask for wherever the slots allow it, so topping up the
    # roster doesn't quietly push the share back above target. This is a
    # matching too, not a greedy pass: taking each guard's easiest slot
    # in turn strands the last few with nothing but preferred slots free.
    remaining = dict(capacity)
    for name in matched.values():
        remaining[name] -= 1

    assignment = dict(matched)
    leftovers = [e for e in deployed if e["id"] not in matched]
    rng.shuffle(leftovers)

    open_slots = {name: n for name, n in remaining.items() if n > 0}
    avoid_options = {}
    for emp in leftovers:
        wanted = set(preferred_of(emp))
        options = [name for name in open_slots if name not in wanted]
        rng.shuffle(options)
        avoid_options[emp["id"]] = options
    parked = _max_matching(leftovers, avoid_options, open_slots)
    assignment.update(parked)
    for name in parked.values():
        remaining[name] -= 1

    # Anyone the matching couldn't park has only preferred slots left to
    # take. They take one: an unmanned post is worse than a share that
    # comes in over target.
    for emp in leftovers:
        if emp["id"] in parked:
            continue
        open_names = [name for name, n in remaining.items() if n > 0]
        if not open_names:
            benched.append(emp)
            continue
        # Emptiest station first, so the last few guards can't all pile
        # onto one station and leave another short.
        chosen = min(open_names, key=lambda name: (-remaining[name], name))
        assignment[emp["id"]] = chosen
        remaining[chosen] -= 1

    return assignment, benched


# ---------------------------------------------------------------------------
# Anchors
# ---------------------------------------------------------------------------

def pick_anchors(station_staff, previously_stayed, seed, target=ANCHOR_TARGET):
    """Which guards stay at their station for familiarization.

    Preference order, unchanged from the old engine:
      1. Guards who did NOT anchor last cycle, so anchor duty rotates.
      2. Spread across cohorts, so the familiar faces aren't all on one
         shift.
      3. A per-cycle shuffle to break ties — sorting by employee ID
         instead would hand anchor duty to the same low-numbered guards
         every single cycle.
    """
    rng = random.Random(seed)
    jitter = {e["id"]: rng.random() for e in station_staff}
    ordered = sorted(
        station_staff,
        key=lambda e: (e["id"] in previously_stayed, jitter[e["id"]]),
    )

    anchors = []
    used_cohorts = set()
    for emp in ordered:
        if len(anchors) >= target:
            break
        cohort = cohort_key(emp)
        if cohort not in used_cohorts:
            anchors.append(emp)
            used_cohorts.add(cohort)

    if len(anchors) < target:
        chosen = {e["id"] for e in anchors}
        for emp in ordered:
            if len(anchors) >= target:
                break
            if emp["id"] not in chosen:
                anchors.append(emp)

    return {e["id"] for e in anchors}


# ---------------------------------------------------------------------------
# The engine
# ---------------------------------------------------------------------------

def allocate(stations, employees, seed, current_station_of=None,
             pinned_station_of=None, previously_stayed=frozenset(),
             anchor_target=ANCHOR_TARGET):
    """Fills every station's declared slots from `employees`.

    stations           : the group's station documents, carrying the
                         per-shift setup Edit Station saved
    employees          : the group's guards (floating substitute head
                         guards excluded by the caller — they have no
                         home station and are drawn on as cover instead)
    seed               : seeds every random draw, so rerunning the same
                         cycle reproduces the same placement
    current_station_of : employeeId -> where they are now, for anchors
                         and the `stayed` flag
    pinned_station_of  : employeeId -> station an admin pinned them to;
                         pins are placed by hand and consume a slot
    previously_stayed  : employeeIds that anchored last cycle

    Returns (placement, stats, warnings). `placement` maps employeeId ->
    {"station": name or None, "stayed", "preferred", "role", "special"};
    station is None for a guard the stations had no slot for. `stats`
    reports the preference share actually achieved per cohort.
    """
    current_station_of = dict(current_station_of or {})
    pinned_station_of = dict(pinned_station_of or {})
    warnings = []

    station_names = [s["name"].strip() for s in stations]
    if not station_names:
        return {}, {}, ["No stations to place guards into."]

    # --- demand -----------------------------------------------------
    demand = {}   # cohort -> {station: slots}
    unconfigured = []
    for station in stations:
        name = station["name"].strip()
        per_station = station_demand(station)
        if not per_station:
            unconfigured.append(name)
        for cohort, slots in per_station.items():
            demand.setdefault(cohort, {})[name] = slots
    if unconfigured:
        warnings.append(schedule_notes.note(
            schedule_notes.CATEGORY_STAFFING,
            schedule_notes.SEVERITY_BLOCKER,
            ", ".join(sorted(unconfigured)),
            "No per-shift setup is saved, so no guard could be placed here "
            "at all.",
            "Set the Morning / Afternoon / Night numbers in Edit Station."))

    by_cohort = {}
    for emp in employees:
        by_cohort.setdefault(cohort_key(emp), []).append(emp)

    relievers = by_cohort.get(RELIEVER_COHORT, [])
    if relievers:
        demand[RELIEVER_COHORT] = reliever_demand(stations, len(relievers))

    # --- pins and anchors consume their slots first -----------------
    fixed = {}   # employeeId -> station
    for emp_id, name in pinned_station_of.items():
        if name:
            fixed[emp_id] = name.strip()

    staff_now = {}
    for emp in employees:
        if emp["id"] in fixed:
            continue
        here = current_station_of.get(emp["id"])
        if here:
            staff_now.setdefault(here, []).append(emp)

    for name in sorted(staff_now):
        if name not in station_names:
            continue
        anchors = pick_anchors(staff_now[name], previously_stayed,
                               f"{seed}:{name}", anchor_target)
        for emp_id in anchors:
            fixed[emp_id] = name

    # A fixed guard only holds a slot the station actually declared —
    # pinning or anchoring someone onto a shift the station no longer
    # runs would push it over its number, which is the bug this engine
    # exists to stop.
    employee_by_id = {e["id"]: e for e in employees}
    placement = {}
    for emp_id, name in sorted(fixed.items()):
        emp = employee_by_id.get(emp_id)
        if emp is None:
            continue
        cohort = cohort_key(emp)
        left = demand.get(cohort, {}).get(name, 0)
        if left <= 0:
            if emp_id in pinned_station_of:
                warnings.append(schedule_notes.note(
                    schedule_notes.CATEGORY_ASSIGNMENT,
                    schedule_notes.SEVERITY_WARNING,
                    emp.get("name", emp_id),
                    f"Pinned to {name}, which has no "
                    f"{_cohort_label(cohort)} slot left, so the pin could "
                    f"not be honoured — they were placed by the normal "
                    f"allocation instead.",
                    f"Raise {name}'s numbers in Edit Station, or drop the "
                    f"pin in Special Assignments.",
                    station=name))
            continue  # not fixed after all; falls through to allocation
        demand[cohort][name] = left - 1
        placement[emp_id] = _record(emp, name, current_station_of)

    # --- allocate the rest, one cohort at a time --------------------
    stats = {}
    benched_all = []
    for cohort in sorted(demand, key=str):
        supply = [e for e in by_cohort.get(cohort, [])
                  if e["id"] not in placement]
        capacity = demand[cohort]
        if not supply:
            short = sum(capacity.values())
            if short:
                warnings.append(schedule_notes.note(
                    schedule_notes.CATEGORY_STAFFING,
                    schedule_notes.SEVERITY_BLOCKER,
                    f"{_cohort_label(cohort).capitalize()} guards",
                    f"None are available for this group, so {short} post(s) "
                    f"have nobody on them.",
                    "Move guards of that kind into this group, or lower the "
                    "stations' required numbers in Edit Station."))
            continue

        target_range = PREFERRED_TARGET.get(cohort[0], DEFAULT_TARGET)
        rng = random.Random(f"{seed}:{cohort}")
        assignment, benched = _allocate_cohort(capacity, supply, rng,
                                               target_range)

        for emp in supply:
            name = assignment.get(emp["id"])
            if name:
                placement[emp["id"]] = _record(emp, name, current_station_of)
        benched_all.extend(benched)

        placed = [e for e in supply if assignment.get(e["id"])]
        hits = sum(1 for e in placed
                   if assignment[e["id"]] in preferred_of(e))
        if placed:
            stats[cohort] = {
                "placed": len(placed),
                "preferred": hits,
                "share": hits / len(placed),
                "target": target_range,
            }
        unfilled = sum(capacity.values()) - len(assignment)
        if unfilled > 0:
            warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_STAFFING,
                schedule_notes.SEVERITY_BLOCKER,
                f"{_cohort_label(cohort).capitalize()} guards",
                f"{unfilled} post(s) across this group have nobody on them "
                f"— there are not enough guards of that kind.",
                "Lower the numbers in Edit Station, or hire/reassign."))

    # Guards whose cohort no station in the group asks for at all — a
    # head guard on a shift none of the stations reserves a Head Guard
    # post for, say. They are benched like any other surplus. Recording
    # them matters beyond the report: a stored placement that doesn't
    # mention every guard is treated as stale and recomputed, which would
    # reshuffle the whole group halfway through the month.
    roleless = [emp for emp in employees if emp["id"] not in placement
                and emp not in benched_all]
    if roleless:
        benched_all.extend(roleless)
        kinds = sorted({_cohort_label(cohort_key(e)) for e in roleless})
        warnings.append(schedule_notes.note(
            schedule_notes.CATEGORY_STAFFING,
            schedule_notes.SEVERITY_WARNING,
            f"{len(roleless)} guard(s) with no matching post",
            f"No station in this group reserves a post for: "
            f"{', '.join(kinds)}. They are unscheduled this period.",
            "Add posts for them in Edit Station, or move them to a group "
            "that needs them."))

    # Guards no station had room for. Named, because the fix is the
    # admin's call: raise a station's numbers or move them elsewhere.
    for emp in benched_all:
        placement[emp["id"]] = _record(emp, None, current_station_of)
    if benched_all:
        names = ", ".join(sorted(e.get("name", e["id"]) for e in benched_all))
        warnings.append(schedule_notes.note(
            schedule_notes.CATEGORY_STAFFING,
            schedule_notes.SEVERITY_WARNING,
            f"{len(benched_all)} guard(s) unscheduled",
            f"No station in this group had room for them this period: "
            f"{names}.",
            "Raise a station's required numbers in Edit Station, or move "
            "them to a group that needs them."))

    # How well the placement honoured people's preferred stations. Pure
    # statistics — nothing is owed, so these file as info under Rotation
    # rather than joining the list of things to fix.
    for cohort, info in sorted(stats.items(), key=lambda kv: str(kv[0])):
        low, high = info["target"]
        label = _cohort_label(cohort).capitalize()
        warnings.append(schedule_notes.note(
            schedule_notes.CATEGORY_ROTATION,
            schedule_notes.SEVERITY_INFO,
            label,
            f"{info['preferred']} of {info['placed']} "
            f"({info['share'] * 100:.0f}%) got a station they asked for "
            f"(target {low * 100:.0f}-{high * 100:.0f}%)."))

    return placement, stats, warnings


def _record(employee, station, current_station_of):
    return {
        "station": station,
        "stayed": bool(station)
                  and station == current_station_of.get(employee["id"]),
        "preferred": bool(station) and station in preferred_of(employee),
        "role": _role(employee),
        "special": False,
    }


def _role(employee):
    """The employee's per-station role, matching rotation.station_role so
    stored placement documents keep the same shape."""
    etype = employee.get("type")
    shift = employee.get("assignedShift")
    if etype == "reliever":
        return "reliever_float"
    if etype == "headGuard":
        if shift == "hgDay":
            return "hg_morning_primary"
        if shift == "hgNight":
            return "hg_night_primary"
        return "hg_substitute"
    return "regular_fixed"


_COHORT_LABELS = {
    ("regular", "morning"): "morning regular",
    ("regular", "afternoon"): "afternoon regular",
    ("regular", "night"): "night regular",
    ("headGuard", "hgDay"): "day head guard",
    ("headGuard", "hgNight"): "night head guard",
    RELIEVER_COHORT: "reliever",
}


def _cohort_label(cohort):
    return _COHORT_LABELS.get(
        cohort, f"{cohort[0]}/{cohort[1] or 'any shift'}")
