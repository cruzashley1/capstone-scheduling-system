"""
The WRITE endpoints, against a running Supabase-backed server.

The gap this fills: golden_capture.py is GET-only, so the whole read
surface can be byte-identical while every write path is broken. That is
not hypothetical — `repositories.from_db()` returned a Firestore-shaped
repository whatever DB_BACKEND said, and eleven endpoints answered 500
while the reads stayed perfect. Reads and writes fail independently, so
they need separate proof.

The six testing_*.py suites cannot cover this. They hand api.db their
own MockFirestoreClient over a tempdir, and now that from_db honours
DB_BACKEND that handle is ignored — running them against Supabase would
write to the live project instead of the tempdir. So this suite goes the
other way: it drives the real HTTP API and treats the database as the
thing under test.

    # start the server first
    DB_BACKEND=supabase python -m uvicorn api:app --port 8000
    python testing_supabase_api.py

It picks the repository mechanics that reads never touch:

    next_sequence      creating an employee and a station
    update + 404       editing one, and the raise a missing id depends on
    delete             removing one, and the auth account with it
    transaction        the station rename fanning out across collections
    upsert WITH days   generation, the only writer of duty_assignments
    upsert_many        publishing, which notifies every guard at once
    update_where       mark-all-read, which reports the count it changed
    delete + cascade   deleting a schedule and its duty rows

THIS SUITE MUTATES THE DATABASE and cannot do otherwise — a write test
that writes nowhere proves nothing. It restores the corpus at the end by
running load_supabase.py's own wipe-and-load, then re-reads every record
to confirm the database is back to exactly what mock_data holds. That
restore runs on failure too.
"""

import subprocess
import sys

import requests

BASE_URL = "http://127.0.0.1:8000"
PREFIX = "ZZAPI"

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


def note(label, value):
    print(f"  ..    {label}: {value}")


def get_schedule(schedule_id):
    """One schedule, from the list endpoint.

    There is no GET /schedules/{id} — the app has only the collection
    route, and the path pattern exists solely for DELETE, so asking for
    one by id answers 405 rather than 404.
    """
    _, body = call("GET", "/schedules")
    for schedule in body.get("schedules", []):
        if schedule.get("id") == schedule_id:
            return schedule
    return None


def call(method, path, **kwargs):
    """(status, body) for one request. Never raises on a 4xx/5xx."""
    response = requests.request(method, BASE_URL + path, timeout=120, **kwargs)
    try:
        return response.status_code, response.json()
    except ValueError:
        return response.status_code, {"_text": response.text[:200]}


# ---------------------------------------------------------------------

def test_employee_lifecycle():
    """next_sequence, upsert, update, the 404 raise, delete."""
    print("\nemployees: create, edit, delete")

    status, body = call("POST", "/employees", json={
        "name": f"{PREFIX} Testperson",
        "mobileNo": "09170000000",
        "role": "Regular Employee",
        "preferredStations": [],
    })
    check("POST /employees succeeds", status, 200)
    employee_id = (body.get("employee") or {}).get("id") or body.get("id")
    note("generated id", employee_id)
    check("an id was generated", bool(employee_id), True)
    if not employee_id:
        return None

    status, body = call("GET", f"/employees/{employee_id}")
    check("the new employee reads back", status, 200)

    status, _ = call("PUT", f"/employees/{employee_id}",
                     json={"name": f"{PREFIX} Renamed"})
    check("PUT /employees updates", status, 200)
    _, body = call("GET", f"/employees/{employee_id}")
    got = (body.get("employee") or body).get("name")
    check("the edit is visible", got, f"{PREFIX} Renamed")

    # The 404 depends on the repository's update() RAISING on a missing
    # row. A Supabase update that silently inserted would answer 200 here.
    status, _ = call("PUT", f"/employees/{PREFIX}_NOSUCH",
                     json={"name": "ghost"})
    check("PUT on a missing employee is 404, not 200", status, 404)

    status, _ = call("DELETE", f"/employees/{employee_id}")
    check("DELETE /employees succeeds", status, 200)
    status, _ = call("GET", f"/employees/{employee_id}")
    check("the employee is gone", status, 404)

    # The credential must go with them, or the uid is taken forever and
    # the next create_user on it raises UidAlreadyExists.
    import supabase_auth
    try:
        supabase_auth.get_user(employee_id)
        check("the auth account was deleted too", "still there", "gone")
    except supabase_auth.UserNotFoundError:
        check("the auth account was deleted too", "gone", "gone")
    return employee_id


def test_station_lifecycle():
    """next_sequence on a second counter, then the rename transaction."""
    print("\nstations: create, rename, delete")

    status, body = call("POST", "/stations", json={
        "name": f"{PREFIX} Station",
        "requiredMorning": 2,
        "requiredAfternoon": 1,
        "requiredNight": 2,
        "posts": {"morning": ["Head Guard", "Roving"],
                  "afternoon": ["Roving"],
                  "night": ["Head Guard", "Roving"]},
    })
    check("POST /stations succeeds", status, 200)
    station_id = (body.get("station") or {}).get("id") or body.get("id")
    note("generated id", station_id)
    if not station_id:
        _failed.append("no station id")
        return None

    # The rename is the transaction: it must fan out across schedules and
    # employees, and either all of it lands or none does.
    status, _ = call("PUT", f"/stations/{station_id}",
                     json={"name": f"{PREFIX} Renamed"})
    check("PUT /stations renames", status, 200)
    _, body = call("GET", "/stations")
    stations = body.get("stations", body if isinstance(body, list) else [])
    names = [s.get("name") for s in stations]
    check("the rename is visible", f"{PREFIX} Renamed" in names, True)
    check("the old name is gone", f"{PREFIX} Station" in names, False)

    status, _ = call("DELETE", f"/stations/{station_id}")
    check("DELETE /stations succeeds", status, 200)
    _, body = call("GET", "/stations")
    stations = body.get("stations", body if isinstance(body, list) else [])
    check("the station is gone",
          any(s.get("id") == station_id for s in stations), False)
    return station_id


def test_generation_and_publish():
    """The heaviest write path: upsert WITH days, then publish.

    Generation is the only thing that writes duty_assignments, and it
    does it inside a transaction alongside deleting the schedules it
    replaces. Publishing then updates the status and fans notifications
    out through upsert_many.
    """
    print("\nschedules: generate, publish, delete")

    _, body = call("GET", "/schedules")
    before = body.get("schedules", [])
    note("schedules before", len(before))

    status, body = call("POST", "/schedules/generate", json={
        "group": 1,
        "startDate": "2026-09-01",
        "overwrite": True,
        "rotate": True,
    })
    check("POST /schedules/generate succeeds", status, 200)
    if status != 200:
        note("detail", str(body)[:300])
        return []

    generated = body.get("schedules", [])
    note("schedules generated", len(generated))
    check("generation produced schedules", len(generated) > 0, True)
    if not generated:
        return []

    ids = [s["id"] for s in generated]
    entries_written = sum(len(d.get("entries", []))
                          for s in generated for d in s.get("days", []))
    note("duty entries written", entries_written)

    # Read one back through the API: days must be reassembled from
    # duty_assignments into exactly the nested shape Flutter expects.
    # This is the check that matters most in the whole suite — it is the
    # only place the decomposition is proven end to end, from generator
    # output through 225 rows and back into nested JSON.
    schedule = get_schedule(ids[0])
    check("the generated schedule reads back", schedule is not None, True)
    days = (schedule or {}).get("days", [])
    check("days survived the round trip", len(days), 15)
    note("day 1 entries", len(days[0].get("entries", [])) if days else 0)

    source = next(s for s in generated if s["id"] == ids[0])
    check("the reassembled days match what was generated",
          [[e["id"] for e in d.get("entries", [])] for d in days],
          [[e["id"] for e in d.get("entries", [])]
           for d in source.get("days", [])])
    check("every entry field round trips, not just the ids",
          [d.get("entries") for d in days],
          [d.get("entries") for d in source.get("days", [])])
    check("empty days are preserved, not dropped",
          [d["date"] for d in days],
          [d["date"] for d in source.get("days", [])])

    # Publishing updates the schedule and notifies every guard on it.
    # It answers {"success": true} and nothing else, so the status has
    # to be read back from the list.
    status, body = call("POST", f"/schedules/{ids[0]}/publish")
    check("POST publish succeeds", status, 200)
    if status == 200:
        check("the schedule is published",
              (get_schedule(ids[0]) or {}).get("status"), "published")

    return ids


def test_notifications_read_all():
    """update_where, which must report the count it changed."""
    print("\nnotifications: mark all read")

    _, body = call("GET", "/employees")
    employees = body.get("employees", [])
    target = None
    for employee in employees:
        _, nbody = call("GET", f"/employees/{employee['id']}/notifications")
        unread = [n for n in nbody.get("notifications", [])
                  if not n.get("isRead")]
        if unread:
            target, count = employee["id"], len(unread)
            break

    if target is None:
        note("skipped", "no employee has unread notifications")
        return

    note("employee", f"{target} with {count} unread")
    status, body = call("POST", f"/employees/{target}/notifications/read-all")
    check("POST read-all succeeds", status, 200)
    check("it reports the number it changed", body.get("updated"), count)

    _, nbody = call("GET", f"/employees/{target}/notifications")
    still = [n for n in nbody.get("notifications", []) if not n.get("isRead")]
    check("nothing is unread afterwards", len(still), 0)


def test_leave_filing():
    """A plain upsert through a path with real validation behind it."""
    print("\nleave: file a request")

    _, body = call("GET", "/employees")
    employees = body.get("employees", [])
    if not employees:
        _failed.append("no employees to file leave for")
        return

    employee = employees[0]
    status, body = call("POST", "/leave-requests", json={
        "employeeId": employee["id"],
        "employeeName": employee.get("name", ""),
        "employeeType": employee.get("type", "regular"),
        "station": employee.get("assignedStation") or "",
        "leaveType": "Vacation / Personal",
        "startDate": "2026-12-01",
        "endDate": "2026-12-05",
        "title": f"{PREFIX} leave",
        "body": "write-path test",
    })
    # A refusal is a legitimate answer — the cooldown and quota rules are
    # real. What must not happen is a 500.
    check("POST /leave-requests is answered, not crashed",
          status in (200, 400, 409), True)
    note("status", f"{status} {str(body)[:120]}")

    if status == 200:
        request_id = (body.get("request") or {}).get("id")
        if request_id:
            _, lbody = call("GET", "/leave-requests")
            ids = [r["id"] for r in lbody.get("requests", [])]
            check("the filed leave is listed", request_id in ids, True)
            call("DELETE", f"/leave-requests/{request_id}")


def test_schedule_delete_cascades(schedule_ids):
    """Deleting a schedule must take its duty rows with it."""
    print("\nschedules: delete cascades to duty_assignments")
    if not schedule_ids:
        note("skipped", "nothing was generated")
        return

    from repositories.supabase_repo import get_pool
    target = schedule_ids[0]
    with get_pool().connection() as conn:
        before = conn.execute(
            "SELECT count(*) AS n FROM duty_assignments WHERE schedule_id = %s",
            [target]).fetchone()["n"]
    note("duty rows before", before)
    check("the schedule had duty rows", before > 0, True)

    status, _ = call("DELETE", f"/schedules/{target}")
    check("DELETE /schedules succeeds", status, 200)

    with get_pool().connection() as conn:
        after = conn.execute(
            "SELECT count(*) AS n FROM duty_assignments WHERE schedule_id = %s",
            [target]).fetchone()["n"]
    check("its duty rows went with it", after, 0)

    # And nothing else lost any.
    with get_pool().connection() as conn:
        orphans = conn.execute(
            "SELECT count(*) AS n FROM duty_assignments d "
            "LEFT JOIN schedules s ON s.id = d.schedule_id "
            "WHERE s.id IS NULL").fetchone()["n"]
    check("no orphaned duty rows anywhere", orphans, 0)


# ---------------------------------------------------------------------

def restore():
    """Puts the corpus back, and proves it.

    load_supabase.py already validates, wipes, loads and then re-reads
    every record against mock_data. Calling it as a subprocess rather
    than importing it keeps this suite from sharing a connection pool
    with the loader mid-restore.
    """
    print("\n" + "=" * 66)
    print("Restoring the corpus")
    print("=" * 66)
    result = subprocess.run(
        [sys.executable, "load_supabase.py", "--wipe"],
        capture_output=True, text=True, timeout=900)
    tail = [ln for ln in result.stdout.splitlines() if ln.strip()][-3:]
    for line in tail:
        print(f"  {line}")
    if result.returncode != 0:
        _failed.append("corpus restore FAILED")
        print(result.stdout[-2000:])
        print(result.stderr[-2000:])
    return result.returncode == 0


def main():
    print("=" * 66)
    print("Supabase WRITE paths, through the running API")
    print("=" * 66)

    try:
        requests.get(BASE_URL + "/", timeout=10)
    except requests.RequestException as e:
        print(f"Cannot reach {BASE_URL} ({e}).\nStart it first:\n"
              f"  DB_BACKEND=supabase python -m uvicorn api:app --port 8000")
        return 2

    schedule_ids = []
    try:
        test_employee_lifecycle()
        test_station_lifecycle()
        schedule_ids = test_generation_and_publish()
        test_notifications_read_all()
        test_leave_filing()
        test_schedule_delete_cascades(schedule_ids)
    except Exception:
        import traceback
        traceback.print_exc()
        _failed.append("uncaught exception")
    finally:
        restore()

    print("\n" + "=" * 66)
    print(f"passed {_passed}, failed {len(_failed)}")
    for label in _failed:
        print(f"  - {label}")
    print("=" * 66)
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
