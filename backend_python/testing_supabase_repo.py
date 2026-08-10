"""
Exercises SupabaseRepository against the real Supabase project.

Every method on the interface in base.py, checked for the behaviour the
document backend has: ordering, absent-vs-null, the update() raise, the
delete() silence, the days round trip, and the transaction rollback.

This is not the migration test — the golden files are. This is the layer
below them: it proves the repository does what it claims before any real
data or any endpoint depends on it, so a golden diff later means a
serialiser bug rather than a broken UPDATE.

    python testing_supabase_repo.py

Safe to run against the live project: every record it writes carries a
ZZTEST prefix and is deleted at the end, including on failure.
"""

import sys
import traceback

import tls_fix  # noqa: F401  — AVG's TLS interception, see memory
from repositories.supabase_repo import (SupabaseRepository, close_pool,
                                        to_camel, to_snake)

PREFIX = "ZZTEST"

_passed = 0
_failed = []


def check(label, got, want):
    global _passed
    if got == want:
        _passed += 1
        print(f"  ok    {label}")
    else:
        _failed.append(label)
        print(f"  FAIL  {label}\n          got:  {got!r}\n          want: {want!r}")


def check_raises(label, exc_type, fn):
    global _passed
    try:
        fn()
    except exc_type:
        _passed += 1
        print(f"  ok    {label}")
        return
    except Exception as e:
        _failed.append(label)
        print(f"  FAIL  {label} — raised {type(e).__name__}, not {exc_type.__name__}")
        return
    _failed.append(label)
    print(f"  FAIL  {label} — did not raise")


# ---------------------------------------------------------------------

def test_name_conversion():
    print("\nname conversion")
    check("to_camel assigned_station", to_camel("assigned_station"),
          "assignedStation")
    check("to_camel id", to_camel("id"), "id")
    check("to_camel head_guard_id", to_camel("head_guard_id"), "headGuardId")
    check("to_snake assignedStation", to_snake("assignedStation"),
          "assigned_station")
    check("to_snake group", to_snake("group"), "group")
    check("round trip covered_by_id",
          to_snake(to_camel("covered_by_id")), "covered_by_id")
    check("round trip replacement_employee_name",
          to_snake(to_camel("replacement_employee_name")),
          "replacement_employee_name")


def test_crud(repo):
    print("\nstations: create, read, update, delete")
    sid = f"{PREFIX}_STA1"
    repo.stations.upsert(sid, {
        "id": sid, "name": f"{PREFIX} Alpha", "isActive": True,
        "requiredEmployees": 6, "requiredMorning": 2,
        "requiredAfternoon": 2, "requiredNight": 2,
        "posts": {"morning": ["Head Guard", "Roving"],
                  "afternoon": ["Roving", "Roving", "Roving"],
                  "night": ["Head Guard", "Roving"]},
    })

    got = repo.stations.get(sid)
    check("get returns camelCase, never column names", sorted(got),
          ["id", "isActive", "name", "postTimes", "posts",
           "requiredAfternoon", "requiredEmployees", "requiredMorning",
           "requiredNight"])
    check("get name", got["name"], f"{PREFIX} Alpha")
    check("jsonb list order preserved", got["posts"]["afternoon"],
          ["Roving", "Roving", "Roving"])
    check("absent column comes back null", got["postTimes"], None)
    check("get missing returns None", repo.stations.get(f"{PREFIX}_NOPE"), None)

    repo.stations.update(sid, {"requiredNight": 3})
    check("update is partial",
          (repo.stations.get(sid)["requiredNight"],
           repo.stations.get(sid)["name"]),
          (3, f"{PREFIX} Alpha"))

    check_raises("update on missing raises KeyError", KeyError,
                 lambda: repo.stations.update(f"{PREFIX}_NOPE", {"name": "x"}))

    # upsert with merge=False REPLACES: requiredNight goes back to its
    # default rather than keeping 3.
    repo.stations.upsert(sid, {"id": sid, "name": f"{PREFIX} Alpha"})
    check("upsert replaces, absent fields reset",
          repo.stations.get(sid)["requiredNight"], 0)

    repo.stations.update(sid, {"requiredNight": 3})
    repo.stations.upsert(sid, {"id": sid, "name": f"{PREFIX} Beta"},
                         merge=True)
    check("upsert merge=True keeps other fields",
          (repo.stations.get(sid)["name"],
           repo.stations.get(sid)["requiredNight"]),
          (f"{PREFIX} Beta", 3))

    check_raises("unknown field raises rather than dropping", KeyError,
                 lambda: repo.stations.update(sid, {"notAColumn": 1}))

    repo.stations.delete(sid)
    check("delete removes", repo.stations.get(sid), None)
    repo.stations.delete(sid)
    check("delete twice is not an error", repo.stations.get(sid), None)


def test_find_and_order(repo):
    print("\nfind, ordering, absent-vs-null")
    ids = [f"{PREFIX}_E3", f"{PREFIX}_E1", f"{PREFIX}_E2"]
    for i, eid in enumerate(ids):
        repo.employees.upsert(eid, {
            "id": eid, "name": f"{PREFIX} {eid[-2:]}",
            "username": eid.lower(), "email": f"{eid}@x.test",
            "type": "regular" if i else "reliever", "isActive": True,
            "dateJoined": "2026-01-01", "password": "hash",
            "assignedStation": None if i == 2 else "Somewhere",
        })

    # ids are written out of order on purpose (E3, E1, E2) so that
    # "ORDER BY id" below is proving something. E3 is the reliever.
    found = repo.employees.find(type="regular")
    check("find equality", sorted(e["id"] for e in found),
          [f"{PREFIX}_E1", f"{PREFIX}_E2"])

    mine = [e for e in repo.employees.list() if e["id"].startswith(PREFIX)]
    check("list is ORDER BY id", [e["id"] for e in mine], sorted(ids))

    check("find with no filters behaves like list",
          len([e for e in repo.employees.find() if e["id"].startswith(PREFIX)]),
          3)

    # The rule find() inherits from Firestore: a record whose field is
    # NULL is not a match for that field's value.
    hits = [e["id"] for e in repo.employees.find(assignedStation="Somewhere")]
    check("NULL is excluded from equality match", sorted(hits),
          [f"{PREFIX}_E1", f"{PREFIX}_E3"])

    moved = repo.employees.update_where(
        {"type": "regular"}, {"assignedShift": "Night"})
    check("update_where returns the count", moved, 2)
    check("update_where wrote", sorted(
        e["id"] for e in repo.employees.find(assignedShift="Night")),
        [f"{PREFIX}_E1", f"{PREFIX}_E2"])

    repo.employees.upsert_many({
        f"{PREFIX}_E4": {"id": f"{PREFIX}_E4", "name": "four",
                         "username": "four", "email": "4@x.test",
                         "type": "regular", "dateJoined": "2026-01-01",
                         "password": "h"},
        f"{PREFIX}_E5": {"id": f"{PREFIX}_E5", "name": "five",
                         "username": "five", "email": "5@x.test",
                         "type": "reliever", "dateJoined": "2026-01-01",
                         "password": "h", "phone": "0917"},
    })
    check("upsert_many with differing column sets",
          sorted(e["id"] for e in repo.employees.list()
                 if e["id"].startswith(f"{PREFIX}_E")),
          [f"{PREFIX}_E1", f"{PREFIX}_E2", f"{PREFIX}_E3",
           f"{PREFIX}_E4", f"{PREFIX}_E5"])

    n = repo.employees.delete_many([f"{PREFIX}_E4", f"{PREFIX}_E5",
                                    f"{PREFIX}_GONE"])
    check("delete_many returns the count asked for", n, 3)


def test_days_round_trip(repo):
    print("\nschedules: days <-> duty_assignments")
    sid = f"{PREFIX}_SCH"
    days = [
        {"date": "2026-08-04", "entries": [
            {"id": f"{PREFIX}_0_1", "employeeId": "AAA111",
             "employeeName": "One", "shift": "Morning", "post": "SW Platform",
             "timeIn": "05:00", "timeOut": "14:00", "isReliever": True,
             "coveringFor": "BBB222", "isSpecial": False,
             "borrowedFrom": None},
            {"id": f"{PREFIX}_0_10", "employeeId": "CCC333",
             "employeeName": "Two", "shift": "Night", "post": "Head Guard",
             "timeIn": "22:00", "timeOut": "05:00", "isReliever": False,
             "coveringFor": None, "isSpecial": True,
             "borrowedFrom": "Elsewhere"},
            {"id": f"{PREFIX}_0_2", "employeeId": "DDD444",
             "employeeName": "Three", "shift": "Afternoon", "post": "Roving",
             "timeIn": "14:00", "timeOut": "22:00", "isReliever": False,
             "coveringFor": None, "isSpecial": False, "borrowedFrom": None},
        ]},
        {"date": "2026-08-05", "entries": []},
        {"date": "2026-08-06", "entries": []},
    ]
    schedule = {
        "id": sid, "stationId": "STA027", "stationName": "Somewhere",
        "group": 1, "startDate": "2026-08-04", "endDate": "2026-08-06",
        "status": "unpublished", "rotated": False, "rotationCycleId": "202608",
        "uncoveredPosts": 0, "createdAt": "2026-08-04T00:00:00+00:00",
        "days": days, "scheduleNotes": [{"category": "staffing",
                                         "text": "one short"}],
        "rotationNotes": [], "specialAssignments": [],
    }
    repo.schedules.upsert(sid, schedule)

    got = repo.schedules.get(sid)
    check("days count matches the period", len(got["days"]), 3)
    check("empty days survive", got["days"][1], {"date": "2026-08-05",
                                                 "entries": []})
    check("entry order is position, not id",
          [e["id"] for e in got["days"][0]["entries"]],
          [f"{PREFIX}_0_1", f"{PREFIX}_0_10", f"{PREFIX}_0_2"])
    check("entry round trips exactly", got["days"][0]["entries"][0],
          days[0]["entries"][0])
    check("no storage columns leak into entries",
          [k for k in got["days"][0]["entries"][0]
           if k in ("scheduleId", "dayIndex", "dayDate", "position")], [])
    check("jsonb notes round trip", got["scheduleNotes"],
          [{"category": "staffing", "text": "one short"}])

    # A partial update must not disturb the duties.
    repo.schedules.update(sid, {"status": "published"})
    after = repo.schedules.get(sid)
    check("update leaves days alone",
          (after["status"], len(after["days"][0]["entries"])),
          ("published", 3))

    # Rewriting days replaces them wholesale.
    repo.schedules.update(sid, {"days": [
        {"date": "2026-08-04", "entries": []},
        {"date": "2026-08-05", "entries": [dict(
            days[0]["entries"][0], id=f"{PREFIX}_1_1")]},
        {"date": "2026-08-06", "entries": []},
    ]})
    after = repo.schedules.get(sid)
    check("days replaced wholesale",
          [len(d["entries"]) for d in after["days"]], [0, 1, 0])

    check("find on schedules also attaches days",
          len(repo.schedules.find(stationId="STA027")[0]["days"]), 3)

    repo.schedules.delete(sid)
    check("delete cascades to duty_assignments", repo.schedules.get(sid), None)


def test_transaction(repo):
    print("\ntransactions")
    a, b = f"{PREFIX}_TXA", f"{PREFIX}_TXB"
    base = {"name": "x", "username": "u", "email": "e@x.test",
            "type": "regular", "dateJoined": "2026-01-01", "password": "h"}
    repo.employees.upsert(a, dict(base, id=a, assignedStation="Old"))
    repo.employees.upsert(b, dict(base, id=b, assignedStation="Old"))

    with repo.transaction() as tx:
        tx.employees.update_where({"assignedStation": "Old"},
                                  {"assignedStation": "New"})
    check("transaction commits on clean exit",
          sorted(e["id"] for e in repo.employees.find(assignedStation="New")),
          [a, b])

    try:
        with repo.transaction() as tx:
            tx.employees.update_where({"assignedStation": "New"},
                                      {"assignedStation": "Rolled"})
            tx.employees.update(f"{PREFIX}_MISSING", {"name": "boom"})
    except KeyError:
        pass
    check("a raise inside rolls everything back",
          sorted(e["id"] for e in repo.employees.find(assignedStation="New")),
          [a, b])

    with repo.transaction() as tx:
        n = tx.employees.delete_where({"assignedStation": "New"})
    check("delete_where returns the count", n, 2)
    check("delete_where committed",
          repo.employees.find(assignedStation="New"), [])

    # No 500-write cap here, unlike the document backend.
    with repo.transaction() as tx:
        for i in range(600):
            tx.employees.upsert(f"{PREFIX}_BULK{i}",
                                dict(base, id=f"{PREFIX}_BULK{i}"))
    check("transactions are not capped at 500 writes",
          len([e for e in repo.employees.list()
               if e["id"].startswith(f"{PREFIX}_BULK")]), 600)
    repo.employees.delete_many([f"{PREFIX}_BULK{i}" for i in range(600)])


def test_next_sequence(repo):
    print("\nnext_sequence")
    name = f"{PREFIX}_counter"
    first = repo.next_sequence(name)
    second = repo.next_sequence(name)
    check("first value is 1", first, 1)
    check("increments", second, 2)
    check("counters carry no id field",
          "id" in (repo.counters.get(name) or {}), False)
    check("counter value readable", repo.counters.get(name)["value"], 2)
    repo.counters.delete(name)


def cleanup(repo):
    """Removes every ZZTEST record, whatever happened above."""
    removed = 0
    for name in ("schedules", "employees", "stations", "counters", "users"):
        collection = getattr(repo, name)
        ids = [r.get("id") for r in collection.list()
               if str(r.get("id", "")).startswith(PREFIX)]
        # counters and users omit id from the body, so ask the table.
        if name in ("counters", "users"):
            with repo._pool.connection() as conn:
                rows = conn.execute(
                    f"SELECT id FROM {name} WHERE id LIKE %s",
                    [PREFIX + "%"]).fetchall()
            ids = [r["id"] for r in rows]
        if ids:
            collection.delete_many(ids)
            removed += len(ids)
    return removed


def main():
    print("=" * 66)
    print("SupabaseRepository — behaviour against the real project")
    print("=" * 66)

    repo = SupabaseRepository()

    try:
        test_name_conversion()
        test_crud(repo)
        test_find_and_order(repo)
        test_days_round_trip(repo)
        test_transaction(repo)
        test_next_sequence(repo)
    except Exception:
        traceback.print_exc()
        _failed.append("uncaught exception")
    finally:
        print(f"\ncleanup: removed {cleanup(repo)} test records")
        close_pool()

    print("\n" + "=" * 66)
    print(f"passed {_passed}, failed {len(_failed)}")
    if _failed:
        for label in _failed:
            print(f"  - {label}")
    print("=" * 66)
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
