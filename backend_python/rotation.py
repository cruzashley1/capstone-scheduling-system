"""
Monthly station-rotation engine.

Decides which station each guard works at for a calendar month, then
hands the resulting placement to the bi-weekly generator in scheduler.py.

--------------------------------------------------------------------
STATION SETUP DRIVES THE PLACEMENT

The normal path is demand-driven and lives in placement.py: every
station declares, per shift, how many head guards and regulars it takes
(Edit Station), and the engine fills exactly those slots, steering each
cohort toward the share of preferred-station hits it is meant to get.
Read placement.py for the rules — this module is the Firestore and
idempotency layer around it.

The cohort-derangement planner below (plan_rotation) is the FALLBACK for
a group whose stations carry no per-shift setup at all. It has no notion
of how many guards a station wants, so it can only preserve the shape it
started with:

1. Rotate within a cohort, never across one.

   A "cohort" is (employee type, assigned shift) — e.g. every morning
   regular, or every hgNight head guard. Guards are only ever permuted
   with others in the same cohort, so each station ends the rotation
   with exactly the same headcount per shift and per role it started
   with.

2. At least MIN_STAYED_PER_STATION guards stay put.

   Real stations need someone who knows the place. Those guards are
   "anchors" (stayed=True). Anchor duty is rotated too — a guard who
   anchored last cycle is picked last this cycle, so nobody gets stuck
   at one station forever. Anchors are spread across different cohorts
   where possible, so the familiar face isn't always on the same shift.

   The demand-driven path keeps this rule; placement.pick_anchors is the
   same selection logic.

Everyone who is not an anchor is a "mover", and movers are deranged:
no mover is allowed to land back on their own station. The demand-driven
path drops the derangement — a guard who asked for the station they are
already at should be allowed to stay, and the preference share (85-90%
of regulars, 60-75% of relievers) is what keeps people moving instead.

--------------------------------------------------------------------
WHAT IS AND ISN'T ROTATED

Floating substitute head guards (assignedStation = None) are NOT
rotated. They have no home station — they already float across the
`preferredStations` window scheduler.py filters them by.

--------------------------------------------------------------------
IDEMPOTENCY — the important bit

Rotation is keyed to the CALENDAR MONTH (rotation_cycles/{yyyymm}),
but schedules are generated per 15-day period, so a month contains
roughly two generation runs. The placement is therefore computed ONCE
per (cycle, group) and stored in `station_rotation_assignments`. Every
later run in that month — including regenerating with overwrite —
reads the stored placement back instead of reshuffling.

Without this, generating the second half of the month would move
everybody again mid-cycle and the first half's schedule would no
longer match reality.

The baseline a cycle rotates FROM is the previous cycle's stored
placement, falling back to the employee's own `assignedStation` when
no previous cycle exists (i.e. the first ever rotation).
"""

import random
from datetime import date, datetime, timezone

import placement as placement_engine
import schedule_notes

# A station keeps at least this many familiar guards each cycle.
MIN_STAYED_PER_STATION = placement_engine.ANCHOR_TARGET

ROTATION_CYCLES = "rotation_cycles"
ROTATION_ASSIGNMENTS = "station_rotation_assignments"


def build_cycle_id(day):
    """Rotation cycles are monthly: 2026-07-16 -> '202607'."""
    return f"{day.year}{day.month:02d}"


def previous_cycle_id(cycle_id):
    year, month = int(cycle_id[:4]), int(cycle_id[4:])
    return f"{year - 1}12" if month == 1 else f"{year}{month - 1:02d}"


def station_role(employee):
    """Maps the employee's global type onto its per-station role."""
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


def _cohort_key(employee):
    """Guards are only ever swapped with others in the same cohort, which
    is what keeps every station's per-shift headcount unchanged."""
    return (employee.get("type"), employee.get("assignedShift"))


# ---------------------------------------------------------------------------
# Anchors
# ---------------------------------------------------------------------------

def _pick_anchors(station_staff, previously_stayed, seed,
                  target=MIN_STAYED_PER_STATION):
    """Chooses which guards stay at their station for familiarization.

    `target` is how many anchors this station still needs. It is normally
    MIN_STAYED_PER_STATION, but drops when admin pins are already holding
    familiar guards in place — see plan_rotation.

    Preference order:
      1. Guards who did NOT anchor last cycle (so anchor duty rotates).
      2. Spread across cohorts, so the familiar faces aren't all on the
         same shift.
      3. A per-cycle shuffle to break ties.

    That third key matters more than it looks. Sorting ties by employee
    ID instead would hand anchor duty to the same low-numbered guards
    every cycle — in a 12-cycle simulation one guard anchored half the
    time. Seeding the tiebreak with the cycle spreads the load while
    keeping a rerun of the same cycle reproducible.
    """
    rng = random.Random(seed)
    jitter = {e["id"]: rng.random() for e in station_staff}
    ordered = sorted(
        station_staff,
        key=lambda e: (e["id"] in previously_stayed, jitter[e["id"]]),
    )

    anchors = []
    used_cohorts = set()

    # First pass: one anchor per cohort, so day and night both keep
    # someone who knows the station.
    for emp in ordered:
        if len(anchors) >= target:
            break
        cohort = _cohort_key(emp)
        if cohort not in used_cohorts:
            anchors.append(emp)
            used_cohorts.add(cohort)

    # Second pass: if the station has fewer cohorts than the anchor
    # target, top up from whatever is left.
    if len(anchors) < target:
        chosen = {e["id"] for e in anchors}
        for emp in ordered:
            if len(anchors) >= target:
                break
            if emp["id"] not in chosen:
                anchors.append(emp)

    return {e["id"] for e in anchors}


# ---------------------------------------------------------------------------
# Derangement — move every mover to a station that isn't their own
# ---------------------------------------------------------------------------

def _deranged_assignment(movers, rng):
    """Redistributes movers across their cohort's stations so that nobody
    lands back where they started.

    `movers` is a list of (employeeId, currentStation). The number of
    open slots at each station equals the number of movers leaving it,
    so the cohort's per-station headcount is unchanged.

    Strategy: assign each guard to the station with the most remaining
    slots that isn't their own ("most constrained first" — the standard
    greedy for this class of problem). A valid derangement exists as
    long as no single station holds more than half the movers; when the
    greedy paints itself into a corner anyway, a repair swap fixes it.

    Returns (assignment, unmoved) where `unmoved` lists guards that
    could not be placed elsewhere and stay put.
    """
    remaining = {}
    for _, station in movers:
        remaining[station] = remaining.get(station, 0) + 1

    # Shuffle for fairness between equally-placed guards, then order by
    # how crowded each guard's own station is: guards from the biggest
    # station are the hardest to place, so they go first.
    shuffled = list(movers)
    rng.shuffle(shuffled)
    shuffled.sort(key=lambda m: -remaining[m[1]])

    assignment = {}   # employeeId -> new station
    origin = {}       # employeeId -> old station
    unmoved = []

    for emp_id, current in shuffled:
        origin[emp_id] = current
        options = [s for s, n in remaining.items() if n > 0 and s != current]

        if options:
            # Most remaining slots first; station name breaks ties so the
            # result is reproducible across runs.
            target = min(options, key=lambda s: (-remaining[s], s))
            assignment[emp_id] = target
            remaining[target] -= 1
            continue

        # Only this guard's own station has slots left. Swap with an
        # already-placed guard: they take our leftover slot, we take
        # theirs. Valid only if neither ends up at their own station.
        swapped = False
        for other_id, other_target in assignment.items():
            if other_target != current and origin[other_id] != current:
                assignment[other_id] = current
                assignment[emp_id] = other_target
                swapped = True
                break

        if not swapped:
            # Cohort is too small or too lopsided to derange (e.g. every
            # mover comes from the same station). Leave them in place.
            assignment[emp_id] = current
            unmoved.append(emp_id)
        remaining[current] -= 1

    return assignment, unmoved


# ---------------------------------------------------------------------------
# Pure planner
# ---------------------------------------------------------------------------

def plan_rotation(employees, current_station_of, previously_stayed, seed,
                  special_station_of=None):
    """Computes one cycle's placement. Pure — no Firestore, no clock.

    employees          : list of employee dicts (floating subs excluded
                         by the caller)
    current_station_of : employeeId -> station name they occupy now
    previously_stayed  : set of employeeIds that anchored last cycle
    seed               : string used to seed tie-breaking, so a rerun of
                         the same cycle produces the same placement
    special_station_of : employeeId -> station name the admin pinned them
                         to for this cycle. Pinned guards are placed by
                         hand and take no part in the shuffle.

    Returns (placement, warnings) where placement maps employeeId ->
    {"station": name, "stayed": bool, "role": str, "special": bool}.
    """
    warnings = []
    special_station_of = special_station_of or {}

    by_station = {}
    for emp in employees:
        station = current_station_of.get(emp["id"])
        if not station:
            continue
        by_station.setdefault(station, []).append(emp)

    pinned_ids = {e["id"] for e in employees if e["id"] in special_station_of}

    # A pin that keeps someone where they already are IS a familiar face,
    # so it counts against that station's floor and spares another guard
    # from being held back. A pin bringing someone in from elsewhere does
    # not — they're new to the station, which is the thing the floor
    # exists to protect against.
    pinned_staying = {}
    for emp_id, station in special_station_of.items():
        if current_station_of.get(emp_id) == station:
            pinned_staying[station] = pinned_staying.get(station, 0) + 1

    # Step 1 — anchors stay, everyone else moves.
    anchor_ids = set()
    for station, staff in sorted(by_station.items()):
        rotatable = [e for e in staff if e["id"] not in pinned_ids]
        target = max(0, MIN_STAYED_PER_STATION - pinned_staying.get(station, 0))

        if target == 0 or not rotatable:
            # Pins alone already satisfy the familiarization floor (or
            # there is nobody left to anchor), so everyone still eligible
            # is free to rotate.
            continue

        if len(rotatable) <= target:
            # Station is at or below the familiarization floor, so nobody
            # can be spared; the whole station stays.
            anchor_ids.update(e["id"] for e in rotatable)
            warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_INFO,
                station,
                f"has only {len(rotatable)} rotatable guard(s) — all kept "
                f"in place to preserve familiarization.",
                station=station,
            ))
            continue

        anchor_ids.update(
            _pick_anchors(rotatable, previously_stayed, f"{seed}:{station}",
                          target))

    # Step 2 — derange the movers, one cohort at a time.
    cohorts = {}
    for emp in employees:
        if (emp["id"] in anchor_ids
                or emp["id"] in pinned_ids
                or emp["id"] not in current_station_of):
            continue
        cohorts.setdefault(_cohort_key(emp), []).append(
            (emp["id"], current_station_of[emp["id"]])
        )

    new_station_of = {}
    for cohort, movers in sorted(cohorts.items(), key=lambda kv: str(kv[0])):
        label = f"{cohort[0]}/{cohort[1] or 'any shift'}"

        if len(movers) < 2:
            # Nothing to swap with — a single mover would have to return
            # to their own station.
            for emp_id, station in movers:
                new_station_of[emp_id] = station
            if movers:
                warnings.append(schedule_notes.note(
                    schedule_notes.CATEGORY_ROTATION,
                    schedule_notes.SEVERITY_INFO,
                    f"Cohort {label}",
                    f"has only {len(movers)} rotatable guard(s) — left in "
                    f"place.",
                ))
            continue

        rng = random.Random(f"{seed}:{cohort}")
        assignment, unmoved = _deranged_assignment(movers, rng)
        new_station_of.update(assignment)
        if unmoved:
            warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_INFO,
                f"Cohort {label}",
                f"{len(unmoved)} guard(s) could not be moved to a different "
                f"station and stayed put.",
            ))

    # Step 3 — final placement. `stayed` is derived from the outcome, not
    # from anchor status, so a mover that couldn't be placed is still
    # correctly recorded as having stayed.
    placement = {}
    for emp in employees:
        emp_id = emp["id"]
        current = current_station_of.get(emp_id)
        if not current:
            continue
        pinned = emp_id in special_station_of
        station = (special_station_of[emp_id] if pinned
                   else new_station_of.get(emp_id, current))
        placement[emp_id] = {
            "station": station,
            "stayed": station == current,
            "role": station_role(emp),
            "special": pinned,
        }

    # Safety net: verify the familiarization rule actually held.
    stayed_per_station = {}
    for emp_id, info in placement.items():
        if info["stayed"]:
            stayed_per_station[info["station"]] = (
                stayed_per_station.get(info["station"], 0) + 1
            )
    for station, staff in sorted(by_station.items()):
        kept = stayed_per_station.get(station, 0)
        if kept < min(MIN_STAYED_PER_STATION, len(staff)):
            warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_WARNING,
                station,
                f"kept only {kept} familiar guard(s) this cycle, below the "
                f"target of {MIN_STAYED_PER_STATION}.",
                "Nobody here knows the post from last month. Check the "
                "station has enough guards assigned to it.",
                station=station,
            ))

    return placement, warnings


# ---------------------------------------------------------------------------
# Firestore layer
# ---------------------------------------------------------------------------

def _load_cycle_placement(db, cycle_id, group):
    """Reads a stored placement back. Returns employeeId -> assignment dict."""
    docs = (db.collection(ROTATION_ASSIGNMENTS)
              .where("rotationCycleId", "==", cycle_id)
              .where("group", "==", group).stream())
    return {d.to_dict()["employeeId"]: d.to_dict() for d in docs}


def _delete_cycle_placement(db, cycle_id, group):
    """Removes a cycle's stored placement so the next run recomputes it
    (used when the placement references stations that no longer exist)."""
    batch = db.batch()
    for doc in (db.collection(ROTATION_ASSIGNMENTS)
                .where("rotationCycleId", "==", cycle_id)
                .where("group", "==", group).stream()):
        batch.delete(doc.reference)
    batch.commit()


def _setup_changed(stored, rotatable, group_stations):
    """True when the stations' declared numbers no longer match what the
    stored placement fills, AND recomputing would actually change that.

    A placement is saved once per cycle and reused for the rest of the
    month, which is what stops the roster reshuffling mid-cycle. But it
    is only a valid answer to the question the admin asked at the time:
    raise Monumento from 13 to 19 in Edit Station and the stored
    placement still sends it 13, so the generator dutifully reports three
    Roving posts unmanned every single day and the station never reaches
    the number that was typed in. Checking station NAMES (which is all
    the reuse path used to do) cannot see that — the names did not
    change, the numbers did.

    Only a difference that recomputing could FIX counts, so a group that
    is genuinely short of morning regulars keeps its stable placement
    instead of reshuffling every generation to no effect:

      * a station holding MORE of a cohort than it now asks for is always
        recomputable — the surplus has somewhere else to be;
      * a station holding FEWER only counts when that cohort has guards
        the placement benched, who could fill the gap.
    """
    demand = {}
    for station in group_stations:
        name = station["name"].strip()
        for cohort, slots in placement_engine.station_demand(station).items():
            demand.setdefault(cohort, {})[name] = slots

    filled, benched = {}, {}
    by_id = {e["id"]: e for e in rotatable}
    for emp_id, doc in stored.items():
        employee = by_id.get(emp_id)
        if employee is None:
            continue
        cohort = placement_engine.cohort_key(employee)
        name = (doc.get("stationName") or "").strip()
        if name:
            counts = filled.setdefault(cohort, {})
            counts[name] = counts.get(name, 0) + 1
        else:
            benched[cohort] = benched.get(cohort, 0) + 1

    # Relievers are deliberately skipped: no station declares a number
    # for them (placement.reliever_demand spreads whatever the group has),
    # so there is nothing here for a changed station setup to contradict.
    for cohort, wanted in demand.items():
        have = filled.get(cohort, {})
        for name, slots in wanted.items():
            got = have.get(name, 0)
            if got > slots or (got < slots and benched.get(cohort, 0)):
                return True
    for cohort, have in filled.items():
        if cohort not in demand:
            continue
        for name, got in have.items():
            if got > demand[cohort].get(name, 0):
                return True
    return False


def _save_cycle_placement(db, cycle_id, group, month_start, placement,
                          station_ids):
    batch = db.batch()
    batch.set(
        db.collection(ROTATION_CYCLES).document(cycle_id),
        {
            "id": cycle_id,
            "monthStart": month_start.isoformat(),
            "createdAt": datetime.now(timezone.utc).isoformat(),
        },
        merge=True,
    )
    for emp_id, info in placement.items():
        doc_id = f"{cycle_id}_{emp_id}"
        station = info["station"]
        batch.set(
            db.collection(ROTATION_ASSIGNMENTS).document(doc_id),
            {
                "id": doc_id,
                "rotationCycleId": cycle_id,
                "group": group,
                "employeeId": emp_id,
                "stationId": station_ids.get(station, ""),
                "stationName": station or "",
                "stationRole": info["role"],
                "stayed": info["stayed"],
                "special": info.get("special", False),
                # False when no station in the group had a slot for them
                # this cycle. Stored explicitly so reusing the placement
                # keeps them out rather than silently falling back to
                # their home station and pushing it over its number.
                "deployed": bool(station),
                # True when this station is one they listed as preferred.
                "preferred": info.get("preferred", False),
            },
        )
    batch.commit()


def resolve_placement(db, group, group_stations, employees, start_date,
                      specials=None):
    """Returns (employeeId -> station name, warnings) for the cycle that
    `start_date` falls in, generating and storing the placement the first
    time the cycle is scheduled and reusing it on every later run.

    Only guards with a home station rotate; floating substitute head
    guards are filtered out by the caller.

    `specials` is {employeeId: pin document} for this cycle (see
    scheduler.load_special_assignments). Pinned guards sit out the
    shuffle — their station comes from the pin. A pin saved AFTER this
    cycle's placement was stored still wins, because the caller applies
    pins on top of whatever placement is returned; the reuse path below
    therefore doesn't need to re-check them.
    """
    cycle_id = build_cycle_id(start_date)
    month_start = date(start_date.year, start_date.month, 1)
    station_names = {s["name"].strip() for s in group_stations}
    station_ids = {s["name"].strip(): s.get("id", "") for s in group_stations}
    special_station_of = {
        emp_id: (pin.get("stationName") or "").strip()
        for emp_id, pin in (specials or {}).items()
        if (pin.get("stationName") or "").strip()
    }

    # Only rotate guards whose home station is inside this group.
    rotatable = [
        e for e in employees
        if (e.get("assignedStation") or "").strip() in station_names
    ]
    if not rotatable:
        return {}, ["No rotatable guards found for this group."]

    # Already rotated this month — reuse it, don't reshuffle mid-cycle.
    # A stored placement is only trustworthy while every station it names
    # still exists: stations deleted or re-created under a new name since
    # it was saved would silently strand every guard placed at the old
    # name, so a stale placement is discarded and recomputed instead.
    stored = _load_cycle_placement(db, cycle_id, group)
    recompute_warnings = []
    if stored:
        stale = sorted(
            {(doc.get("stationName") or "").strip()
             for doc in stored.values()} - station_names - {""})
        # A placement is only reusable while it still covers everybody it
        # is being asked about. Guards hired, reactivated or moved into
        # the group since it was saved are missing from it, and falling
        # back to their home station for those would put a station over
        # the number Edit Station asks for — exactly the drift that used
        # to leave one station with two day head guards and another with
        # none. A short placement is recomputed instead.
        missing = sorted(e["id"] for e in rotatable if e["id"] not in stored)
        # ...and only while it still fills the numbers Edit Station asks
        # for. Those numbers can change after a cycle has been placed.
        resized = (not stale and not missing
                   and _setup_changed(stored, rotatable, group_stations))
        if not stale and not missing and not resized:
            placement = {
                emp_id: ((doc.get("stationName") or "").strip() or None)
                for emp_id, doc in stored.items()
            }
            moved = sum(1 for d in stored.values()
                        if not d.get("stayed", False))
            benched = sum(1 for name in placement.values() if name is None)
            summary = (f"Reusing the existing rotation for cycle "
                       f"{cycle_id} — {moved} of {len(stored)} guards "
                       f"rotated.")
            if benched:
                summary += (f" {benched} guard(s) have no station slot this "
                            "cycle and stay unscheduled.")
            return placement, [schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_INFO,
                "This cycle",
                summary,
            )]
        _delete_cycle_placement(db, cycle_id, group)
        if stale:
            recompute_warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_WARNING,
                "This cycle",
                f"The stored rotation for cycle {cycle_id} referenced "
                f"station(s) that no longer exist ({', '.join(stale)}), so "
                f"the placement was recomputed against the current "
                f"stations.",
                "Guards may be at a different station than they were "
                "earlier this month."))
        if missing:
            recompute_warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_WARNING,
                "This cycle",
                f"The stored rotation for cycle {cycle_id} was missing "
                f"{len(missing)} guard(s) who are now in this group, so the "
                f"placement was recomputed to keep every station at the "
                f"headcount it asks for.",
                "Guards may be at a different station than they were "
                "earlier this month."))
        if resized:
            recompute_warnings.append(schedule_notes.note(
                schedule_notes.CATEGORY_ROTATION,
                schedule_notes.SEVERITY_WARNING,
                "This cycle",
                f"A station's required numbers changed since cycle "
                f"{cycle_id} was placed, so the stored rotation no longer "
                f"filled them and the placement was recomputed against the "
                f"current Edit Station setup.",
                "Guards may be at a different station than they were "
                "earlier this month."))

    # Baseline: last cycle's placement, else the employee's home station.
    previous = _load_cycle_placement(db, previous_cycle_id(cycle_id), group)
    current_station_of = {}
    for emp in rotatable:
        prior = previous.get(emp["id"], {}).get("stationName")
        station = prior if prior in station_names else None
        current_station_of[emp["id"]] = (
            station or emp["assignedStation"].strip()
        )
    previously_stayed = {
        emp_id for emp_id, doc in previous.items() if doc.get("stayed", False)
    }

    # Demand-driven placement is the normal path: it fills exactly the
    # slots the stations declare. A group whose stations carry no
    # per-shift setup at all has no demand to fill, so it falls back to
    # the old cohort derangement, which at least preserves the staffing
    # shape it started with.
    configured = any(placement_engine.station_demand(s) for s in group_stations)
    if configured:
        placement, _stats, warnings = placement_engine.allocate(
            group_stations, rotatable,
            seed=f"{cycle_id}:{group}",
            current_station_of=current_station_of,
            pinned_station_of=special_station_of,
            previously_stayed=previously_stayed,
        )
        for emp_id in special_station_of:
            if emp_id in placement:
                placement[emp_id]["special"] = True
    else:
        placement, warnings = plan_rotation(
            rotatable, current_station_of, previously_stayed,
            seed=f"{cycle_id}:{group}", special_station_of=special_station_of,
        )
        warnings.insert(
            0,
            "No station in this group has a per-shift setup saved, so guards "
            "were rotated by the old cohort shuffle instead of being placed "
            "against each station's required numbers. Set the Morning / "
            "Afternoon / Night numbers in Edit Station.")
    warnings = recompute_warnings + warnings

    _save_cycle_placement(db, cycle_id, group, month_start, placement,
                          station_ids)

    moved = sum(1 for info in placement.values()
                if info["station"] and not info["stayed"])
    warnings.insert(0, schedule_notes.note(
        schedule_notes.CATEGORY_ROTATION,
        schedule_notes.SEVERITY_INFO,
        "This cycle",
        f"Rotated {moved} of {len(placement)} guards for cycle {cycle_id}.",
    ))
    return {e: info["station"] for e, info in placement.items()}, warnings
