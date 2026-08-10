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
    # Every filter VALUE below is prefixed, not just the ids. Against a
    # loaded database `find(type="regular")` matches 390 real guards and
    # `update_where` would REWRITE them — which is exactly what happened
    # the first time this ran after load_supabase.py, and why the values
    # are now unmatchable by real data.
    regular, reliever = f"{PREFIX}_regular", f"{PREFIX}_reliever"
    station = f"{PREFIX} Somewhere"

    ids = [f"{PREFIX}_E3", f"{PREFIX}_E1", f"{PREFIX}_E2"]
    for i, eid in enumerate(ids):
        repo.employees.upsert(eid, {
            "id": eid, "name": f"{PREFIX} {eid[-2:]}",
            "username": eid.lower(), "email": f"{eid}@x.test",
            "type": regular if i else reliever, "isActive": True,
            "dateJoined": "2026-01-01", "password": "hash",
            "assignedStation": None if i == 2 else station,
        })

    # ids are written out of order on purpose (E3, E1, E2) so that
    # "ORDER BY id" below is proving something. E3 is the reliever.
    found = repo.employees.find(type=regular)
    check("find equality", sorted(e["id"] for e in found),
          [f"{PREFIX}_E1", f"{PREFIX}_E2"])

    mine = [e for e in repo.employees.list() if e["id"].startswith(PREFIX)]
    check("list is ORDER BY id", [e["id"] for e in mine], sorted(ids))

    check("find with no filters behaves like list",
          len([e for e in repo.employees.find() if e["id"].startswith(PREFIX)]),
          3)

    # The rule find() inherits from Firestore: a record whose field is
    # NULL is not a match for that field's value.
    hits = [e["id"] for e in repo.employees.find(assignedStation=station)]
    check("NULL is excluded from equality match", sorted(hits),
          [f"{PREFIX}_E1", f"{PREFIX}_E3"])

    shift = f"{PREFIX}_Night"
    moved = repo.employees.update_where({"type": regular},
                                        {"assignedShift": shift})
    check("update_where returns the count", moved, 2)
    check("update_where wrote", sorted(
        e["id"] for e in repo.employees.find(assignedShift=shift)),
        [f"{PREFIX}_E1", f"{PREFIX}_E2"])

    repo.employees.upsert_many({
        f"{PREFIX}_E4": {"id": f"{PREFIX}_E4", "name": "four",
                         "username": "four", "email": "4@x.test",
                         "type": regular, "dateJoined": "2026-01-01",
                         "password": "h"},
        f"{PREFIX}_E5": {"id": f"{PREFIX}_E5", "name": "five",
                         "username": "five", "email": "5@x.test",
                         "type": reliever, "dateJoined": "2026-01-01",
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
        "id": sid, "stationId": f"{PREFIX}_STA", "stationName": f"{PREFIX} S",
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
          len(repo.schedules.find(stationId=f"{PREFIX}_STA")[0]["days"]), 3)

    repo.schedules.delete(sid)
    check("delete cascades to duty_assignments", repo.schedules.get(sid), None)


def test_transaction(repo):
    print("\ntransactions")
    a, b = f"{PREFIX}_TXA", f"{PREFIX}_TXB"
    # Prefixed station names again — delete_where below would otherwise
    # be one careless value away from clearing real employees.
    old, new = f"{PREFIX} Old", f"{PREFIX} New"
    base = {"name": "x", "username": "u", "email": "e@x.test",
            "type": f"{PREFIX}_regular", "dateJoined": "2026-01-01",
            "password": "h"}
    repo.employees.upsert(a, dict(base, id=a, assignedStation=old))
    repo.employees.upsert(b, dict(base, id=b, assignedStation=old))

    with repo.transaction() as tx:
        tx.employees.update_where({"assignedStation": old},
                                  {"assignedStation": new})
    check("transaction commits on clean exit",
          sorted(e["id"] for e in repo.employees.find(assignedStation=new)),
          [a, b])

    try:
        with repo.transaction() as tx:
            tx.employees.update_where({"assignedStation": new},
                                      {"assignedStation": f"{PREFIX} Rolled"})
            tx.employees.update(f"{PREFIX}_MISSING", {"name": "boom"})
    except KeyError:
        pass
    check("a raise inside rolls everything back",
          sorted(e["id"] for e in repo.employees.find(assignedStation=new)),
          [a, b])

    with repo.transaction() as tx:
        n = tx.employees.delete_where({"assignedStation": new})
    check("delete_where returns the count", n, 2)
    check("delete_where committed",
          repo.employees.find(assignedStation=new), [])

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


def test_auth():
    """supabase_auth against auth_accounts.

    Credentials never went through the repository — api.py reaches them
    via db_init.get_auth() — so they need their own checks. What
    matters here is parity with mock_auth: same exceptions, same
    self-upgrade, and a hash that is never returned.
    """
    print("\nauth accounts")
    import supabase_auth

    uid = f"{PREFIX}_USER"
    email = f"{uid}@schedulingsystem.local"
    supabase_auth.create_user(email=email, password="first-pass", uid=uid)

    check("correct password verifies",
          supabase_auth.verify_password(uid, "first-pass"), True)
    check("wrong password does not",
          supabase_auth.verify_password(uid, "nope"), False)
    check("unknown uid does not",
          supabase_auth.verify_password(f"{PREFIX}_GHOST", "x"), False)
    check("get_user returns the email",
          supabase_auth.get_user(uid).email, email)
    check("no attribute carries the hash",
          hasattr(supabase_auth.get_user(uid), "password_hash"), False)

    check_raises("create_user on an existing uid raises",
                 supabase_auth.UidAlreadyExistsError,
                 lambda: supabase_auth.create_user(
                     email=email, password="x", uid=uid))

    supabase_auth.update_user(uid, password="second-pass")
    check("password change takes effect",
          (supabase_auth.verify_password(uid, "second-pass"),
           supabase_auth.verify_password(uid, "first-pass")),
          (True, False))

    check_raises("update_user on a missing uid raises",
                 supabase_auth.UserNotFoundError,
                 lambda: supabase_auth.update_user(f"{PREFIX}_GHOST",
                                                   password="x"))
    check_raises("delete_user on a missing uid raises",
                 supabase_auth.UserNotFoundError,
                 lambda: supabase_auth.delete_user(f"{PREFIX}_GHOST"))

    # upsert_user must not hash a hash: bcrypt over a bcrypt string is a
    # valid hash of the wrong thing, and the login fails with nothing in
    # the logs to say why. This is the trap the loader would fall into.
    stored = _hash_of(uid)
    supabase_auth.upsert_user(uid, email, stored)
    check("re-seeding an existing hash does not re-hash it",
          supabase_auth.verify_password(uid, "second-pass"), True)

    supabase_auth.delete_user(uid)
    check_raises("deleted account is gone",
                 supabase_auth.UserNotFoundError,
                 lambda: supabase_auth.get_user(uid))


def _hash_of(uid):
    """The stored hash, read directly. Only the test needs this."""
    from repositories.supabase_repo import get_pool
    with get_pool().connection() as conn:
        return conn.execute(
            "SELECT password_hash FROM auth_accounts WHERE uid = %s",
            [uid]).fetchone()["password_hash"]


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

    with repo._pool.connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM auth_accounts WHERE uid LIKE %s",
                    [PREFIX + "%"])
        removed += cur.rowcount
    return removed


def fingerprint(repo):
    """A digest of every non-test row in the database.

    The reason this exists: the first run of this suite against a LOADED
    database rewrote 390 real employees, because `update_where({"type":
    "regular"}, ...)` matches real guards as happily as test ones. Row
    counts alone would not have caught it — nothing was created or
    deleted, 390 rows quietly changed value.

    So the check is over content, not counts, and it runs before and
    after. Every filter value in this file is ZZTEST-prefixed now; this
    is what proves it stayed that way.
    """
    digests = {}
    with repo._pool.connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT table_name FROM information_schema.tables "
                    "WHERE table_schema='public' AND table_type='BASE TABLE' "
                    "ORDER BY 1")
        for row in cur.fetchall():
            table = row["table_name"]
            key = "schedule_id" if table == "duty_assignments" else (
                "uid" if table == "auth_accounts" else "id")
            cur.execute(
                f'SELECT md5(string_agg(t::text, \'|\' ORDER BY t::text)) AS d,'
                f' count(*) AS n FROM "{table}" t WHERE {key} NOT LIKE %s',
                [PREFIX + "%"])
            result = cur.fetchone()
            digests[table] = (result["n"], result["d"])
    return digests


def main():
    global _passed
    print("=" * 66)
    print("SupabaseRepository — behaviour against the real project")
    print("=" * 66)

    repo = SupabaseRepository()
    before = fingerprint(repo)
    live = sum(n for n, _ in before.values())
    print(f"\n{live} existing rows will be fingerprinted and re-checked "
          f"at the end.")

    try:
        test_name_conversion()
        test_crud(repo)
        test_find_and_order(repo)
        test_days_round_trip(repo)
        test_transaction(repo)
        test_next_sequence(repo)
        test_auth()
    except Exception:
        traceback.print_exc()
        _failed.append("uncaught exception")
    finally:
        print(f"\ncleanup: removed {cleanup(repo)} test records")

        print("\nreal data untouched?")
        after = fingerprint(repo)
        for table in sorted(set(before) | set(after)):
            was, now = before.get(table), after.get(table)
            if was != now:
                _failed.append(f"{table} was modified")
                print(f"  FAIL  {table}: {was[0] if was else '-'} rows "
                      f"-> {now[0] if now else '-'}, content differs")
        if not any(f.endswith("was modified") for f in _failed):
            _passed += 1
            print(f"  ok    all {len(after)} tables byte-identical to "
                  f"the pre-run fingerprint")

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
