"""
Tests for demand-driven placement (placement.py) and the station
headcount it guarantees.

THE BUG THIS EXISTS FOR
-----------------------
A station configured for 15 guards a day generated 14, and one
configured for 17 generated 18. The required number governed REGULARS
only: the head guard slot is part of the Morning and Night figures, but
the generator emitted one row per head-guard EMPLOYEE standing at the
station. A station holding two day head guards ran one over its number
every day; one holding none ran one under, and only left a note about
it. Feeding that, the old rotation could deliver 0 or 2 head guards to a
station because stored monthly placements went stale and guards missing
from one silently fell back to their home station.

WHAT THIS ASSERTS
-----------------
  1. Every station rosters EXACTLY its required headcount, every day of
     the period, across all three groups.
  2. Head guards are capped by the Head Guard posts a shift declares:
     surplus head guards are benched and reported, and a station with
     none has the post held for the period by a floating substitute.
  3. The preferred-station shares land in (or above) their targets, and
     relievers are steered distinctly lower than regulars, per the
     configured ranges.
  4. Guards who listed no preferred stations are the ones most likely to
     be left out when a group has more guards than slots.
  5. Nobody works two stations on one day, and the 13-day cap holds.
  6. Placement is deterministic for a given cycle, so regenerating the
     second half of a month can't reshuffle the first half.

Runs entirely in a temp directory against a copy of mock_data; the real
mock_data is never touched.
"""

import json
import os
import shutil
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import date

try:
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass

os.environ.setdefault("USE_MOCK_DB", "1")

import placement                                          # noqa: E402
import scheduler                                          # noqa: E402
import station_pools                                      # noqa: E402
import station_posts                                      # noqa: E402
from mock_firestore import MockFirestoreClient            # noqa: E402

MOCK_DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "mock_data")
START = date(2026, 9, 1)

_results = []


def check(label, passed, detail=""):
    _results.append(bool(passed))
    mark = "PASS " if passed else "FAIL "
    print(f"  {mark} {label}" + (f"  - {detail}" if detail else ""))
    return bool(passed)


def banner(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


# ---------------------------------------------------------------------------
# Synthetic fixtures — small enough to reason about by hand
# ---------------------------------------------------------------------------

def station(sid, name, morning, afternoon, night):
    """A station configured the way Edit Station saves one: the head
    guard slot is the first Morning and Night post and counts inside the
    number, the afternoon has none of its own."""
    return {
        "id": sid,
        "name": name,
        "isActive": True,
        "requiredMorning": morning,
        "requiredAfternoon": afternoon,
        "requiredNight": night,
        "requiredEmployees": morning + afternoon + night,
        "posts": {
            key: station_posts.default_posts(key, count)
            for key, count in (("morning", morning),
                               ("afternoon", afternoon),
                               ("night", night))
        },
    }


def guard(eid, name, etype, shift, home, prefs=()):
    return {
        "id": eid, "name": name, "type": etype,
        "assignedShift": shift, "assignedStation": home,
        "preferredStations": list(prefs), "isActive": True,
    }


def build_db(stations, employees, workdir):
    for filename, rows in (("stations.json", stations),
                           ("employees.json", employees)):
        with open(os.path.join(workdir, filename), "w", encoding="utf-8") as fh:
            json.dump({row["id"]: row for row in rows}, fh)
    for name in ("schedules", "rotation_cycles",
                 "station_rotation_assignments", "special_assignments",
                 "special_requests"):
        with open(os.path.join(workdir, f"{name}.json"), "w",
                  encoding="utf-8") as fh:
            json.dump({}, fh)
    return MockFirestoreClient(data_dir=workdir)


# ---------------------------------------------------------------------------
# Suite 1 — the unit the whole fix rests on
# ---------------------------------------------------------------------------

def suite_slots():
    banner("SUITE 1 — a shift's slots, split into head guards and regulars")

    st = station("S1", "Alpha", 6, 6, 3)
    check("morning 6 = 1 head guard + 5 regulars",
          station_posts.shift_slots(st, "morning") == (1, 5),
          str(station_posts.shift_slots(st, "morning")))
    check("afternoon 6 = 0 head guards + 6 regulars",
          station_posts.shift_slots(st, "afternoon") == (0, 6),
          str(station_posts.shift_slots(st, "afternoon")))
    check("night 3 = 1 head guard + 2 regulars",
          station_posts.shift_slots(st, "night") == (1, 2),
          str(station_posts.shift_slots(st, "night")))

    # Fernando Poe Jr. and Balintawak, exactly as they are configured.
    fpj = station("S2", "Fernando Poe Jr.", 6, 6, 3)
    bal = station("S3", "Balintawak", 8, 6, 3)
    for st_, total in ((fpj, 15), (bal, 17)):
        demand = placement.station_demand(st_)
        check(f"{st_['name']} asks for {total} bodies a day",
              sum(demand.values()) == total,
              f"{sum(demand.values())} from {dict(demand)}")
        check(f"{st_['name']} asks for exactly one day + one night HG",
              demand.get(("headGuard", "hgDay")) == 1
              and demand.get(("headGuard", "hgNight")) == 1)

    # A station with no setup at all keeps the old uncapped behaviour.
    check("an unconfigured station declares no demand",
          station_posts.shift_slots({"id": "X", "name": "X"}, "morning") is None)

    # Relievers aren't posts, so they are spread rather than declared.
    stations = [station("S1", "Alpha", 6, 6, 3), station("S2", "Beta", 5, 5, 3)]
    spread = placement.reliever_demand(stations, 7)
    check("relievers spread evenly, spare to the bigger station",
          spread == {"Alpha": 4, "Beta": 3}, str(spread))
    check("every station gets a reliever when supply allows",
          min(placement.reliever_demand(stations, 2).values()) == 1,
          str(placement.reliever_demand(stations, 2)))


# ---------------------------------------------------------------------------
# Suite 2 — head guards obey the station's number
# ---------------------------------------------------------------------------

def suite_head_guard_cap():
    banner("SUITE 2 — head guards are capped and gaps are filled")

    workdir = tempfile.mkdtemp(prefix="placement_hg_")
    try:
        stations = [station("STA1", "Alpha", 6, 6, 3),
                    station("STA2", "Beta", 6, 6, 3)]
        names = ["Alpha", "Beta"]

        employees = []
        for st_name in names:
            for i in range(5):
                employees.append(guard(f"{st_name}_AM{i}", f"{st_name} AM{i}",
                                       "regular", "morning", st_name, names))
            for i in range(6):
                employees.append(guard(f"{st_name}_PM{i}", f"{st_name} PM{i}",
                                       "regular", "afternoon", st_name, names))
            for i in range(2):
                employees.append(guard(f"{st_name}_NT{i}", f"{st_name} NT{i}",
                                       "regular", "night", st_name, names))
            for i in range(5):
                employees.append(guard(f"{st_name}_REL{i}", f"{st_name} REL{i}",
                                       "reliever", "morning", st_name, names))

        # BOTH day head guards live at Alpha and there is no night head
        # guard anywhere — the two shapes that used to break the count.
        employees.append(guard("HGD_A", "Day HG A", "headGuard", "hgDay",
                               "Alpha", names))
        employees.append(guard("HGD_B", "Day HG B", "headGuard", "hgDay",
                               "Alpha", names))
        # Floating substitutes: no home station, both stations in their
        # window. Two of them end up holding a station's vacant night HG
        # post for the period — which makes them unavailable for anything
        # else, so the pool needs enough left over to cover the four head
        # guards' day-offs as well.
        for i in range(6):
            sub = guard(f"SUB{i}", f"Substitute {i}", "headGuard", None,
                        None, names)
            sub.pop("assignedStation")
            employees.append(sub)

        db = build_db(stations, employees, workdir)
        schedules = scheduler.generate_group_schedules(db, 1, START,
                                                       rotate=True)
        notes = schedules[0].get("rotationNotes", [])

        by_name = {s["stationName"]: s for s in schedules}
        for name in names:
            daily = sorted({len(d["entries"]) for d in by_name[name]["days"]})
            check(f"{name} rosters exactly 15 every day", daily == [15],
                  f"daily headcount {daily}")
        check("no post left uncovered",
              sum(s["uncoveredPosts"] for s in schedules) == 0,
              f"{sum(s['uncoveredPosts'] for s in schedules)} uncovered")

        # Only one of the two day head guards may work here; the other
        # has no slot in this group and is reported rather than rostered.
        rostered = {e["employeeId"] for s in schedules for d in s["days"]
                    for e in d["entries"]}
        check("both day head guards are used, one per station",
              {"HGD_A", "HGD_B"} <= rostered)

        # One day head guard per station, never two — even though both
        # started at Alpha.
        worst = {}
        for name in names:
            counts = [Counter(e["shift"] for e in d["entries"])
                      for d in by_name[name]["days"]]
            worst[name] = (max(c["HG Day"] for c in counts),
                           max(c["HG Night"] for c in counts))
        check("exactly one HG Day row per station per day",
              all(v[0] == 1 for v in worst.values()), str(worst))
        check("exactly one HG Night row per station per day",
              all(v[1] == 1 for v in worst.values()), str(worst))

        check("the substitutes were reported as holding the vacant posts",
              sum(1 for n in notes if "holds the Head Guard post" in n) == 2,
              next((n for n in notes if "holds the Head Guard post" in n),
                   "no such note"))

        # The two substitutes must not be the same person twice.
        standing = set()
        for name in names:
            for entry in by_name[name]["days"][0]["entries"]:
                if entry["shift"] == "HG Night":
                    standing.add(entry["employeeId"])
        check("each station got its own substitute", len(standing) == 2,
              str(standing))

        clashes = defaultdict(set)
        for sched in schedules:
            for day in sched["days"]:
                for entry in day["entries"]:
                    clashes[(entry["employeeId"], day["date"])].add(
                        sched["stationName"])
        check("no guard on two stations the same day",
              not [k for k, v in clashes.items() if len(v) > 1])
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Suite 3 — the real roster, all three groups
# ---------------------------------------------------------------------------

def suite_end_to_end():
    banner("SUITE 3 — every station hits its number (real mock_data)")

    if not os.path.isdir(MOCK_DATA):
        print("\n  SKIPPED — mock_data/ not found. Seed it first.")
        return

    workdir = tempfile.mkdtemp(prefix="placement_e2e_")
    try:
        for name in ("employees.json", "stations.json", "counters.json"):
            source = os.path.join(MOCK_DATA, name)
            if os.path.exists(source):
                shutil.copy(source, workdir)
        for name in ("schedules", "rotation_cycles",
                     "station_rotation_assignments", "special_assignments",
                     "special_requests"):
            with open(os.path.join(workdir, f"{name}.json"), "w") as fh:
                json.dump({}, fh)

        db = MockFirestoreClient(data_dir=workdir)
        required_of = {s.to_dict()["name"].strip():
                       int(s.to_dict().get("requiredEmployees") or 0)
                       for s in db.collection("stations").stream()}

        all_schedules = []
        shares = {}
        for group in (1, 2, 3):
            schedules = scheduler.generate_group_schedules(db, group, START,
                                                           rotate=True)
            # Saved between groups exactly as api.py does, so each group
            # can see what the previous one already committed people to.
            for sched in schedules:
                db.collection("schedules").document(sched["id"]).set(sched)
            all_schedules.extend(schedules)
            for note in schedules[0].get("rotationNotes", []):
                if "got a station they asked for" in note:
                    kind = note.split(":")[0]
                    shares.setdefault(kind, []).append(
                        int(note.split("(")[1].split("%")[0]))

        wrong = []
        for sched in all_schedules:
            want = required_of[sched["stationName"]]
            for day in sched["days"]:
                if len(day["entries"]) != want:
                    wrong.append(f"{sched['stationName']} {day['date']}: "
                                 f"{len(day['entries'])} vs {want}")
        check(f"all {len(all_schedules)} stations roster their exact "
              f"required headcount every day",
              not wrong, wrong[0] if wrong else "15 days x 25 stations")

        clashes = defaultdict(set)
        worked = Counter()
        stations_of = defaultdict(set)
        for sched in all_schedules:
            for day in sched["days"]:
                for entry in day["entries"]:
                    clashes[(entry["employeeId"], day["date"])].add(
                        sched["stationName"])
                    worked[entry["employeeId"]] += 1
                    stations_of[entry["employeeId"]].add(sched["stationName"])
        check("no guard on two stations the same day",
              not [k for k, v in clashes.items() if len(v) > 1],
              f"{len([1 for v in clashes.values() if len(v) > 1])} clashes")
        over = [(e, n) for e, n in worked.items()
                if n > scheduler.MAX_REGULAR_DAYS]
        check(f"nobody works more than {scheduler.MAX_REGULAR_DAYS} days",
              not over, f"worst {max(worked.values())} days")

        # Relievers are capped tighter than the guards holding a post:
        # they cover other people's vacancies, and the ceiling is what
        # stops them being topped up past it at a neighbouring station.
        employees = {d.to_dict()["id"]: d.to_dict()
                     for d in db.collection("employees").stream()}
        relievers = {e for e, emp in employees.items()
                     if emp.get("type") == "reliever"}
        rel_over = [(e, n) for e, n in worked.items()
                    if e in relievers and n > scheduler.MAX_RELIEVER_DAYS]
        rel_days = sorted(n for e, n in worked.items() if e in relievers)
        check(f"no reliever works more than "
              f"{scheduler.MAX_RELIEVER_DAYS} days",
              not rel_over,
              f"{len(rel_days)} relievers, worst {rel_days[-1]} days, "
              f"median {rel_days[len(rel_days) // 2]}")

        # The station-distance rule: a reliever topped up at neighbouring
        # stations must never be sent further than MAX_STATION_DISTANCE
        # stops from the station they are based at.
        #
        # Relievers only. Regulars and head guards each hold ONE station
        # for the whole period and the monthly rotation engine decides
        # which — a regular based at Blumentritt and rotated to Fernando
        # Poe Jr. has not travelled anywhere, they were posted there.
        # Floating substitutes are excluded too: they have no permanent
        # station, so their radius is measured off their preferred
        # window instead (scheduler._sub_candidates).
        line = station_pools.line_order(
            [d.to_dict() for d in db.collection("stations").stream()])
        trips = []
        for emp_id in relievers:
            anchor = (employees.get(emp_id, {}).get("assignedStation")
                      or "").strip()
            if not anchor:
                continue
            for name in stations_of.get(emp_id, ()):
                gap = station_pools.distance(line, anchor, name)
                if gap is not None:
                    trips.append((gap, f"{emp_id} {anchor} -> {name}"))
        too_far = [t for t in trips if t[0] > station_pools.MAX_STATION_DISTANCE]
        check(f"nobody is sent more than "
              f"{station_pools.MAX_STATION_DISTANCE} stops from their station",
              not too_far,
              too_far[0][1] if too_far
              else f"widest actual trip {max(trips)[0]} stops")

        # The configured targets, honoured as a floor. Landing above the
        # range is allowed and expected: with five preferred stations out
        # of eight or nine in a group, a placement that satisfies
        # everybody often exists, and deliberately posting someone
        # against their wishes to hit a percentage helps nobody.
        for kind, values in sorted(shares.items()):
            low = int(placement.PREFERRED_TARGET[
                "reliever" if kind == "Reliever" else "regular"][0] * 100)
            check(f"{kind}: preferred share at or above target",
                  min(values) >= low, f"{values} (target floor {low}%)")
        regular_kinds = [v for k, v in shares.items() if "regular" in k]
        if regular_kinds and "Reliever" in shares:
            worst_regular = min(min(v) for v in regular_kinds)
            check("relievers are steered lower than regulars, as configured",
                  max(shares["Reliever"]) < worst_regular,
                  f"reliever {shares['Reliever']} vs regular floor "
                  f"{worst_regular}%")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Suite 4 — the no-preference weighting and determinism
# ---------------------------------------------------------------------------

def suite_weighting():
    banner("SUITE 4 — guards who picked nothing, and determinism")

    stations = [station("STA1", "Alpha", 6, 6, 3),
                station("STA2", "Beta", 6, 6, 3)]
    names = ["Alpha", "Beta"]

    # 10 afternoon slots for 30 afternoon regulars: 20 must sit out.
    # Half the guards named both stations, half named none at all.
    employees = []
    for i in range(15):
        employees.append(guard(f"P{i}", f"Picky {i}", "regular", "afternoon",
                               "Alpha", names))
    for i in range(15):
        employees.append(guard(f"N{i}", f"NoPref {i}", "regular", "afternoon",
                               "Alpha", ()))

    benched_no_pref = 0
    trials = 40
    for trial in range(trials):
        result, _stats, _warnings = placement.allocate(
            stations, employees, seed=f"trial{trial}",
            current_station_of={}, anchor_target=0)
        benched_no_pref += sum(
            1 for e in employees
            if e["id"].startswith("N") and result[e["id"]]["station"] is None)

    # 20 benched per trial. If preference had no pull it would be 10 of
    # them; at a tenth of the pull it should be nearly all 15.
    average = benched_no_pref / trials
    check("guards with no preferred station are the ones left out",
          average > 13.0,
          f"{average:.1f} of the 15 no-preference guards benched per run "
          f"(20 benched in total; an unweighted draw would bench ~10)")

    first, _s, _w = placement.allocate(stations, employees, seed="fixed",
                                       current_station_of={})
    second, _s, _w = placement.allocate(stations, employees, seed="fixed",
                                        current_station_of={})
    check("the same cycle always produces the same placement",
          first == second)
    third, _s, _w = placement.allocate(stations, employees, seed="other",
                                       current_station_of={})
    check("a different cycle produces a different placement", first != third)


def main():
    suite_slots()
    suite_head_guard_cap()
    suite_end_to_end()
    suite_weighting()

    banner("OVERALL RESULT: "
           + ("ALL CHECKS PASSED" if all(_results)
              else f"{_results.count(False)} of {len(_results)} CHECKS FAILED"))
    return 0 if all(_results) else 1


if __name__ == "__main__":
    sys.exit(main())
