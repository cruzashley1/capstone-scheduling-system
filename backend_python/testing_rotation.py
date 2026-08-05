"""
testing_rotation.py

Standalone test harness for rotation.py — the monthly station-rotation
engine. Companion to testing.py (which covers services/scheduler.py).

Run it with:
    python testing_rotation.py

Three suites, in increasing order of realism:

  1. INVARIANTS   Pure planner over 6 simulated cycles on a synthetic
                  8-station group. Checks the rules that must never
                  break, plus anchor fairness over 12 cycles.

  2. EDGE CASES   The degenerate shapes that break naive rotation:
                  stations too small to spare anyone, cohorts where a
                  derangement is mathematically impossible, single
                  stations. Plus 300 randomized shapes against the
                  derangement primitive.

  3. END TO END   The real generator (scheduler.py) against the real
                  mock Firestore client, using your seeded mock_data.

SAFETY: suite 3 copies mock_data into a temp directory and runs there,
then deletes it. Your real mock_data is never written to, and Firestore
is never contacted by any suite.
"""

import json
import os
import random
import shutil
import sys
import tempfile
from collections import Counter
from datetime import date

# Warning text contains em-dashes; keep them from blowing up a cp1252
# console rather than losing the whole test run to an encoding error.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, ValueError):
    pass

from rotation import (
    MIN_STAYED_PER_STATION,
    _deranged_assignment,
    plan_rotation,
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MOCK_DATA = os.path.join(BASE_DIR, "mock_data")


def check(label, passed, detail=""):
    mark = "✅" if passed else "❌"
    print(f"  {mark} {label}" + (f"  [{detail}]" if detail else ""))
    return passed


def banner(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def employee(seq, station, etype="regular", shift="morning"):
    return {
        "id": f"E{seq:03d}",
        "type": etype,
        "assignedStation": station,
        "assignedShift": shift,
    }


def staffing_shape(placement, employees):
    """Headcount per (station, type, shift). This is the number that must
    survive a rotation untouched — if it changes, some shift somewhere
    just gained or lost a post."""
    by_id = {e["id"]: e for e in employees}
    shape = Counter()
    for emp_id, info in placement.items():
        emp = by_id[emp_id]
        shape[(info["station"], emp["type"], emp["assignedShift"])] += 1
    return shape


def home_shape(employees):
    return Counter(
        (e["assignedStation"], e["type"], e["assignedShift"]) for e in employees
    )


def stayed_per_station(placement):
    counts = Counter()
    for info in placement.values():
        if info["stayed"]:
            counts[info["station"]] += 1
    return counts


# ---------------------------------------------------------------------------
# Suite 1 — invariants across repeated cycles
# ---------------------------------------------------------------------------

STATIONS = [f"Station {i}" for i in range(1, 9)]


def build_synthetic_group():
    """8 stations shaped like the seeded data: regulars on three shifts,
    2 relievers, 1 day + 1 night head guard. Headcount deliberately
    varies per station so the rotation has uneven blocks to solve."""
    employees = []
    seq = 0
    for index, station in enumerate(STATIONS):
        counts = (
            ("morning", 3 + index % 2),
            ("afternoon", 2 + index % 3),
            ("night", 2),
        )
        for shift, count in counts:
            for _ in range(count):
                seq += 1
                employees.append(employee(seq, station, "regular", shift))
        for _ in range(2):
            seq += 1
            employees.append(employee(seq, station, "reliever", None))
        for shift in ("hgDay", "hgNight"):
            seq += 1
            employees.append(employee(seq, station, "headGuard", shift))
    return employees


def suite_invariants():
    banner("SUITE 1 — INVARIANTS OVER REPEATED CYCLES")
    employees = build_synthetic_group()
    baseline = home_shape(employees)
    print(f"\nSynthetic group: {len(employees)} guards, "
          f"{len(STATIONS)} stations\n")

    passed = True
    current = {e["id"]: e["assignedStation"] for e in employees}
    previously_stayed = set()

    for cycle in range(1, 7):
        placement, warnings = plan_rotation(
            employees, current, previously_stayed, seed=f"2026{cycle:02d}:1"
        )

        shape_ok = staffing_shape(placement, employees) == baseline
        kept = stayed_per_station(placement)
        familiar_ok = all(
            kept.get(s, 0) >= MIN_STAYED_PER_STATION for s in STATIONS
        )
        # A guard recorded as having moved must genuinely be somewhere else.
        moves_real = all(
            info["station"] != current[emp_id]
            for emp_id, info in placement.items()
            if not info["stayed"]
        )

        moved = sum(1 for i in placement.values() if not i["stayed"])
        print(f"cycle {cycle}: {moved:3d} moved, "
              f"{len(placement) - moved:3d} stayed")
        passed &= check("staffing shape per shift unchanged", shape_ok)
        passed &= check(
            f"every station keeps >={MIN_STAYED_PER_STATION} familiar guards",
            familiar_ok, detail=f"min={min(kept.values())}")
        passed &= check("no guard 'moved' to their own station", moves_real)
        for w in warnings:
            print(f"     note: {w}")

        current = {e: i["station"] for e, i in placement.items()}
        previously_stayed = {e for e, i in placement.items() if i["stayed"]}

    # Anchor fairness: nobody should be stuck as the familiar face forever.
    print("\nAnchor fairness over 12 cycles:")
    current = {e["id"]: e["assignedStation"] for e in employees}
    previously_stayed = set()
    anchor_counts = Counter()
    for cycle in range(1, 13):
        placement, _ = plan_rotation(
            employees, current, previously_stayed, seed=f"2027{cycle:02d}:1"
        )
        for emp_id, info in placement.items():
            if info["stayed"]:
                anchor_counts[emp_id] += 1
        current = {e: i["station"] for e, i in placement.items()}
        previously_stayed = {e for e, i in placement.items() if i["stayed"]}

    worst = max(anchor_counts.values())
    share = len(anchor_counts) / len(employees)
    passed &= check(
        "anchor duty spread across the workforce", share > 0.5,
        detail=f"{len(anchor_counts)}/{len(employees)} guards anchored at least once")
    passed &= check(
        "no guard anchors more than half the cycles", worst <= 6,
        detail=f"worst = {worst}/12")

    # Same cycle, same result — required for the reuse path to be stable.
    home = {e["id"]: e["assignedStation"] for e in employees}
    first, _ = plan_rotation(employees, home, set(), seed="202607:1")
    second, _ = plan_rotation(employees, home, set(), seed="202607:1")
    passed &= check("rerunning the same cycle is deterministic",
                    first == second)
    return passed


# ---------------------------------------------------------------------------
# Suite 2 — degenerate shapes
# ---------------------------------------------------------------------------

def run_edge_case(label, employees):
    """A rotation may legitimately decline to move people (too few guards,
    impossible derangement) but must never corrupt the staffing shape or
    claim a move it didn't make."""
    current = {e["id"]: e["assignedStation"] for e in employees}
    placement, warnings = plan_rotation(employees, current, set(), seed="edge")

    shape_ok = staffing_shape(placement, employees) == home_shape(employees)
    moves_real = all(
        info["station"] != current[emp_id]
        for emp_id, info in placement.items()
        if not info["stayed"]
    )
    moved = sum(1 for i in placement.values() if not i["stayed"])

    print(f"\n{label}  ({moved}/{len(placement)} moved)")
    ok = check("staffing shape preserved", shape_ok)
    ok &= check("no fake moves reported", moves_real)
    for w in warnings:
        print(f"     note: {w}")
    return ok


def suite_edge_cases():
    banner("SUITE 2 — DEGENERATE SHAPES")
    passed = True

    passed &= run_edge_case(
        "two stations, 4 morning regulars each",
        [employee(i, "A") for i in range(4)]
        + [employee(i + 10, "B") for i in range(4)])

    passed &= run_edge_case(
        "a station holding only 2 guards (nobody can be spared)",
        [employee(i, "A") for i in range(2)]
        + [employee(i + 10, "B") for i in range(6)])

    passed &= run_edge_case(
        "a station holding a single guard",
        [employee(0, "A")] + [employee(i + 10, "B") for i in range(6)])

    passed &= run_edge_case(
        "lopsided cohort: 9 guards at one station, 1 at the other",
        [employee(i, "A") for i in range(9)] + [employee(20, "B")]
        + [employee(i + 30, "A", "reliever", None) for i in range(3)]
        + [employee(i + 40, "B", "reliever", None) for i in range(3)])

    passed &= run_edge_case(
        "a group with only one station (nothing can rotate)",
        [employee(i, "A") for i in range(6)])

    passed &= run_edge_case(
        "cohort of exactly 1 night regular per station",
        [employee(i, f"S{i}", "regular", "night") for i in range(5)]
        + [employee(i + 50, f"S{i}", "regular", "morning") for i in range(5)]
        + [employee(i + 60, f"S{i}", "regular", "morning") for i in range(5)]
        + [employee(i + 70, f"S{i}", "regular", "afternoon") for i in range(5)])

    head_guards = []
    for i in range(6):
        head_guards += [
            employee(i * 2, f"S{i}", "headGuard", "hgDay"),
            employee(i * 2 + 1, f"S{i}", "headGuard", "hgNight"),
        ]
        head_guards += [
            employee(100 + i * 3 + j, f"S{i}", "regular", "morning")
            for j in range(3)
        ]
    passed &= run_edge_case(
        "6 stations with exactly 1 hgDay + 1 hgNight each", head_guards)

    # Fuzz the derangement primitive directly across random block sizes.
    print("\nrandomized derangement stress (300 shapes)")
    violations = 0
    for trial in range(300):
        rng = random.Random(trial)
        movers = []
        seq = 0
        for station in range(rng.randint(2, 6)):
            for _ in range(rng.randint(1, 5)):
                seq += 1
                movers.append((f"X{seq}", f"S{station}"))

        assignment, unmoved = _deranged_assignment(movers, rng)
        origin = dict(movers)
        for emp_id, target in assignment.items():
            if target == origin[emp_id] and emp_id not in unmoved:
                violations += 1
        if Counter(assignment.values()) != Counter(origin.values()):
            violations += 1

    passed &= check("no self-assignments, slot counts always preserved",
                    violations == 0, detail=f"{violations} violations")
    return passed


# ---------------------------------------------------------------------------
# Suite 3 — end to end against the mock Firestore
# ---------------------------------------------------------------------------

def stations_worked_by_guard(schedules):
    """From generated schedule docs: employeeId -> set of station names
    they appear at during the period."""
    worked = {}
    for schedule in schedules:
        for day in schedule["days"]:
            for entry in day["entries"]:
                worked.setdefault(entry["employeeId"], set()).add(
                    schedule["stationName"])
    return worked


def postings_by_guard(schedules):
    """employeeId -> set of stations they are POSTED to, ignoring cover.

    A guard covering someone's day-off at a sister station legitimately
    appears on that station's schedule without being posted there, so
    `stations_worked_by_guard` is the wrong lens for asking whether the
    placement moved. Cover entries carry isReliever or coveringFor.
    """
    posted = {}
    for schedule in schedules:
        for day in schedule["days"]:
            for entry in day["entries"]:
                if entry.get("isReliever") or entry.get("coveringFor"):
                    continue
                posted.setdefault(entry["employeeId"], set()).add(
                    schedule["stationName"])
    return posted


def same_day_clashes(schedules):
    """(employeeId, date) pairs appearing on two stations the same day —
    the invariant that actually matters. Working two stations on
    different days of the period is normal cover."""
    seen = {}
    for schedule in schedules:
        for day in schedule["days"]:
            for entry in day["entries"]:
                key = (entry["employeeId"], day["date"])
                seen.setdefault(key, set()).add(schedule["stationName"])
    return {key: names for key, names in seen.items() if len(names) > 1}


def suite_end_to_end(group=1):
    banner("SUITE 3 — END TO END (real generator, mock Firestore)")

    if not os.path.isdir(MOCK_DATA):
        print("\n  SKIPPED — mock_data/ not found. Seed it first.")
        return True

    workdir = tempfile.mkdtemp(prefix="rotation_test_")
    try:
        for name in ("employees.json", "stations.json", "counters.json"):
            source = os.path.join(MOCK_DATA, name)
            if os.path.exists(source):
                shutil.copy(source, workdir)
        # Start from a clean slate: no schedules, no rotation history.
        for name in ("schedules", "rotation_cycles",
                     "station_rotation_assignments"):
            with open(os.path.join(workdir, f"{name}.json"), "w") as fh:
                json.dump({}, fh)

        from mock_firestore import MockFirestoreClient
        import scheduler

        db = MockFirestoreClient(data_dir=workdir)
        passed = True

        def totals(schedules):
            entries = sum(len(d["entries"])
                          for s in schedules for d in s["days"])
            uncovered = sum(s["uncoveredPosts"] for s in schedules)
            return entries, uncovered

        # --- Baseline: rotation off
        print(f"\nGroup {group}, period starting 2026-07-16")
        base = scheduler.generate_group_schedules(
            db, group, date(2026, 7, 16), rotate=False)
        base_entries, base_uncovered = totals(base)
        base_where = stations_worked_by_guard(base)
        print(f"\n  rotation OFF: {len(base)} stations, {base_entries} entries, "
              f"{base_uncovered} uncovered posts")

        # --- Rotation on, first run of the cycle
        july = scheduler.generate_group_schedules(
            db, group, date(2026, 7, 16), rotate=True)
        july_entries, july_uncovered = totals(july)
        july_where = stations_worked_by_guard(july)
        print(f"  rotation ON:  {len(july)} stations, {july_entries} entries, "
              f"{july_uncovered} uncovered posts")
        for note in july[0].get("rotationNotes", []):
            print(f"     note: {note}")

        print()
        # Placement is demand-driven: every station rosters exactly the
        # headcount its per-shift setup asks for, every day. The
        # un-rotated baseline can't promise that — it leaves everyone on
        # their home station, so a station holding too many or too few
        # guards of a given kind runs over or under its number.
        wanted = sum(
            int(s.to_dict().get("requiredEmployees") or 0)
            for s in db.collection("stations").stream()
            if s.to_dict()["name"].strip() in {sc["stationName"] for sc in july}
        ) * 15
        passed &= check("rotation rosters exactly what the stations ask for",
                        july_entries == wanted,
                        detail=f"{july_entries} entries vs {wanted} required "
                               f"(baseline without rotation: {base_entries})")
        passed &= check("rotation does not add uncovered posts",
                        july_uncovered <= base_uncovered,
                        detail=f"{base_uncovered} -> {july_uncovered}")

        moved = [e for e in july_where
                 if e in base_where and july_where[e] != base_where[e]]
        passed &= check("guards actually changed station", len(moved) > 0,
                        detail=f"{len(moved)} moved")

        stored = [d.to_dict() for d in
                  db.collection("station_rotation_assignments")
                    .where("group", "==", group).stream()]
        rotated_ids = {d["employeeId"] for d in stored}
        kept = Counter(d["stationName"] for d in stored if d["stayed"])
        passed &= check(
            f"every station keeps >={MIN_STAYED_PER_STATION} familiar guards",
            kept and min(kept.values()) >= MIN_STAYED_PER_STATION,
            detail=", ".join(f"{s}:{n}" for s, n in sorted(kept.items())))

        # Nobody may be on two stations on the SAME DAY. Working a sister
        # station on another day is the coverage fallback doing its job —
        # relievers spread across the group are borrowed exactly that way,
        # and the entry carries borrowedFrom to say so.
        clashes = same_day_clashes(july)
        passed &= check("no guard booked at two stations on one day",
                        not clashes,
                        detail=f"{len(clashes)} clash(es)")
        posted_twice = [e for e, s in postings_by_guard(july).items()
                        if len(s) > 1]
        passed &= check("no guard posted to two stations",
                        not posted_twice,
                        detail=f"{len(posted_twice)} posted twice")

        # --- Idempotency: second period of the same month
        print("\nRegenerating the second period of the same month "
              "(2026-07-31)")
        stored_before = {d.to_dict()["employeeId"]: d.to_dict()["stationName"]
                         for d in db.collection("station_rotation_assignments")
                                    .where("group", "==", group).stream()}
        rerun = scheduler.generate_group_schedules(
            db, group, date(2026, 7, 31), rotate=True)
        for note in rerun[0].get("rotationNotes", []):
            print(f"     note: {note}")
        stored_after = {d.to_dict()["employeeId"]: d.to_dict()["stationName"]
                        for d in db.collection("station_rotation_assignments")
                                   .where("group", "==", group).stream()}
        passed &= check("placement reused, nobody reshuffled mid-month",
                        stored_before == stored_after)
        # The rosters must agree too — but only on where guards are
        # POSTED. The two periods have different day-offs and a different
        # designated night reliever, so who covers what legitimately
        # differs between them.
        july_posted, rerun_posted = postings_by_guard(july), postings_by_guard(rerun)
        stable = all(july_posted.get(e) == rerun_posted.get(e)
                     for e in july_posted if e in rotated_ids)
        passed &= check("postings unchanged mid-month", stable)

        # --- Next cycle rotates again
        print("\nNext cycle (2026-08-16)")
        august = scheduler.generate_group_schedules(
            db, group, date(2026, 8, 16), rotate=True)
        august_where = stations_worked_by_guard(august)
        for note in august[0].get("rotationNotes", []):
            print(f"     note: {note}")

        moved_again = [e for e in august_where
                       if e in july_where and e in rotated_ids
                       and august_where[e] != july_where[e]]
        passed &= check("August rotates again", len(moved_again) > 0,
                        detail=f"{len(moved_again)} moved since July")

        august_stored = [
            d.to_dict() for d in
            db.collection("station_rotation_assignments")
              .where("rotationCycleId", "==", "202608").stream()]
        august_kept = Counter(
            d["stationName"] for d in august_stored if d["stayed"])
        passed &= check(
            "familiarization holds in August too",
            august_kept and min(august_kept.values()) >= MIN_STAYED_PER_STATION,
            detail=", ".join(f"{s}:{n}"
                             for s, n in sorted(august_kept.items())))

        july_anchors = {d["employeeId"] for d in stored if d["stayed"]}
        august_anchors = {d["employeeId"] for d in august_stored if d["stayed"]}
        overlap = july_anchors & august_anchors
        passed &= check("anchor duty rotates between cycles",
                        len(overlap) < len(july_anchors),
                        detail=f"July {len(july_anchors)}, "
                               f"August {len(august_anchors)}, "
                               f"overlap {len(overlap)}")
        return passed
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


# ---------------------------------------------------------------------------

if __name__ == "__main__":
    overall = suite_invariants()
    overall = suite_edge_cases() and overall
    overall = suite_end_to_end() and overall

    print("\n" + "=" * 78)
    print("OVERALL RESULT:",
          "✅ ALL CHECKS PASSED" if overall
          else "❌ SOME CHECKS FAILED - see above")
    print("=" * 78)
    sys.exit(0 if overall else 1)
