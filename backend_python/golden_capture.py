"""
Golden-file capture for the read API — the safety net for the Supabase
migration.

The migration's first rule is that response shapes must not change: Flutter
reads these endpoints through api_service.dart, so if every response is
byte-identical afterwards the app needs no changes, and any difference is a
bug rather than a feature. That rule is only worth anything if it can be
checked, which is what this does.

    python golden_capture.py capture    # record the current responses
    python golden_capture.py compare    # re-run and diff against the record

`capture` is run once against the CURRENT backend, before anything is
migrated. `compare` is run after each slice of the migration; it exits 1 on
any difference and prints a unified diff of what moved.

Only GET endpoints are called. POST/PUT/DELETE would mutate mock_data/ and
make the next run differ from the last for reasons that have nothing to do
with the migration, so the roster-changing half of the API is deliberately
out of scope — see "What this does not cover" at the bottom of this file.
The write half has its own suite, testing_supabase_api.py, which drives
the real endpoints against Supabase and restores the corpus afterwards.

RE-BASELINED 2026-08-10 against DB_BACKEND=supabase. Two consequences:

* `compare` against the MOCK backend now FAILS by design, on the same
  1636 differences the re-baseline was reviewed for — nulls where a
  document simply lacked a field, and the four order-only endpoints
  (employees, special-assignments, special-assignments-cycle,
  stations-pools). Supabase is the baseline now; mock is the one that
  differs. Point compare at the Supabase server.
* These files are DATE-SENSITIVE and rot. Leave windows, active leaves
  and duty status all move with the clock, so a comparison run weeks
  later reports differences that are the calendar's doing and not the
  code's. When that happens, the way to tell them apart is to run the
  two backends side by side on the same minute and diff those against
  each other — the same-day comparison is the one that isolates a
  backend change, not the comparison against a file recorded in the
  past.

The server must already be running, in whichever mode you want to record:

    uvicorn api:app --reload --port 8000

Set GOLDEN_BASE_URL to point somewhere else (default http://127.0.0.1:8000).
"""

import argparse
import difflib
import json
import os
import sys

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "mock_data")
GOLDEN_DIR = os.path.join(HERE, "golden")

BASE_URL = os.getenv("GOLDEN_BASE_URL", "http://127.0.0.1:8000").rstrip("/")

# Written into a masked field's place. Chosen to be obvious in a diff.
VOLATILE = "<VOLATILE>"


# --------------------------------------------------------------------------
# Subjects
#
# Which employee, station and schedule to ask about is derived from
# mock_data/ at run time rather than hard-coded, so the script keeps working
# after the data is regenerated. Picks are deterministic (sorted, then
# first match) so two runs on the same data choose the same subjects.
# --------------------------------------------------------------------------

def _load(name):
    path = os.path.join(DATA_DIR, name)
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def derive_subjects():
    """Picks the records the requests below are built from.

    Employees are chosen from a PUBLISHED schedule wherever possible.
    /employees/{id}/schedule only reads published schedules, and in the
    current mock data only 1 of 8 is published — an employee picked at
    random would return an empty roster, and an empty response proves
    nothing about whether the migration preserved its shape.
    """
    employees = _load("employees.json")
    stations = _load("stations.json")
    schedules = _load("schedules.json")

    subjects = {}

    published = sorted(
        (sid for sid, s in schedules.items() if s.get("status") == "published")
    )
    subjects["scheduleId"] = published[0] if published else None

    # Everyone rostered on the published schedule, in first-seen order.
    rostered = []
    if published:
        for day in schedules[published[0]].get("days", []):
            for entry in day.get("entries", []):
                eid = entry.get("employeeId")
                if eid and eid not in rostered:
                    rostered.append(eid)

    # One employee per type, preferring somebody actually on duty.
    for emp_type in ("regular", "reliever", "headGuard"):
        of_type = sorted(
            eid for eid, e in employees.items() if e.get("type") == emp_type
        )
        on_duty = [eid for eid in rostered if eid in set(of_type)]
        subjects[emp_type] = (on_duty or of_type or [None])[0]

    subjects["stationId"] = (sorted(stations) or [None])[0]
    subjects["stationName"] = (
        stations.get(subjects["stationId"], {}).get("name")
        if subjects["stationId"] else None
    )

    cycles = _load("rotation_cycles.json")
    subjects["cycleId"] = (sorted(cycles) or [None])[0]

    for key, filename in (
        ("leaveRequestId", "leave_requests.json"),
        ("absenceRequestId", "absence_requests.json"),
        ("specialRequestId", "special_requests.json"),
    ):
        subjects[key] = (sorted(_load(filename)) or [None])[0]

    # An employee who actually HAS a record of each kind. Without this the
    # per-employee list endpoints are asked about whoever happened to be on
    # the published schedule, who usually has no leave or absence on file —
    # and a recorded `{"requests": []}` would still match after a migration
    # that mangled every field inside a request.
    subjects["owners"] = {}
    for kind, filename in (
        ("leave-requests", "leave_requests.json"),
        ("absence-requests", "absence_requests.json"),
        ("special-requests", "special_requests.json"),
        ("cover-offers", "cover_offers.json"),
        ("notifications", "employee_notifications.json"),
    ):
        records = _load(filename)
        for rid in sorted(records):
            owner = records[rid].get("employeeId")
            if owner:
                subjects["owners"][kind] = owner
                break

    # A real (date, station, shift, absentee) combination for the
    # suggestion endpoint — invented values would just return an empty list.
    subjects["suggest"] = None
    if published:
        sched = schedules[published[0]]
        for day in sched.get("days", []):
            entries = day.get("entries") or []
            if entries:
                subjects["suggest"] = {
                    "date": day.get("date"),
                    "station": sched.get("stationName"),
                    "shift": entries[0].get("shift"),
                    "absentEmployeeId": entries[0].get("employeeId"),
                }
                break

    # A date inside the published period, for the endpoints that take one.
    subjects["dateInPeriod"] = (
        schedules[published[0]].get("startDate") if published else None
    )

    return subjects


# --------------------------------------------------------------------------
# The request list
# --------------------------------------------------------------------------

def build_requests(s):
    """Returns [(slug, path, query_params)] for every GET worth recording.

    Entries whose subject could not be derived are skipped rather than
    called with None, which would record a 404 as if it were the contract.
    """
    reqs = [
        ("root", "/", None),
        ("server-time", "/server-time", None),
        ("employees", "/employees", None),
        ("stations", "/stations", None),
        ("stations-pools", "/stations/pools", None),
        ("schedules", "/schedules", None),
        ("attendance-reports", "/attendance-reports", None),
        ("replacements", "/replacements", None),
        ("absence-requests", "/absence-requests", None),
        ("cover-offers", "/cover-offers", None),
        ("special-requests", "/special-requests", None),
        ("special-assignments", "/special-assignments", None),
        ("leave-types", "/leave-types", None),
        ("leave-requests", "/leave-requests", None),
        ("leaves-active", "/leaves/active", None),
    ]

    # The same per-employee endpoints for each type, because the response
    # differs by type: a reliever carries coveringFor, a head guard's report
    # scope is narrower, a regular has neither.
    for emp_type in ("regular", "reliever", "headGuard"):
        eid = s.get(emp_type)
        if not eid:
            continue
        for suffix, name in (
            ("", "detail"),
            ("/schedule", "schedule"),
            ("/station-overview", "station-overview"),
            ("/notifications", "notifications"),
            ("/absence-requests", "absence-requests"),
            ("/cover-offers", "cover-offers"),
            ("/special-requests", "special-requests"),
            ("/special-request-window", "special-request-window"),
            ("/leave-window", "leave-window"),
            ("/leave-requests", "leave-requests"),
        ):
            reqs.append(
                (f"employee-{emp_type}-{name}", f"/employees/{eid}{suffix}", None)
            )

    # station-overview pinned to a date inside the published period. Without
    # a date it defaults to today, which makes the file expire the moment the
    # period ends and turns every later compare into a false alarm.
    if s.get("dateInPeriod"):
        for emp_type in ("regular", "reliever", "headGuard"):
            eid = s.get(emp_type)
            if eid:
                reqs.append((
                    f"employee-{emp_type}-station-overview-dated",
                    f"/employees/{eid}/station-overview",
                    {"date": s["dateInPeriod"]},
                ))
        reqs.append(("leaves-active-dated", "/leaves/active",
                     {"date": s["dateInPeriod"]}))

    # Same endpoints again, but asked about somebody who has a record of
    # that kind, so the recorded response has fields in it to compare.
    for kind, owner in sorted((s.get("owners") or {}).items()):
        reqs.append((f"owner-{kind}", f"/employees/{owner}/{kind}", None))

    if s.get("cycleId"):
        reqs.append(("special-assignments-cycle", "/special-assignments",
                     {"cycleId": s["cycleId"]}))
        reqs.append(("special-assignments-duty-status",
                     "/special-assignments/duty-status",
                     {"cycleId": s["cycleId"]}))

    if s.get("leaveRequestId"):
        reqs.append(("leave-request-impact",
                     f"/leave-requests/{s['leaveRequestId']}/impact", None))

    if s.get("suggest"):
        reqs.append(("replacements-suggest", "/replacements/suggest",
                     s["suggest"]))

    return reqs


# --------------------------------------------------------------------------
# Volatile-field detection
#
# Some responses legitimately differ between two identical calls —
# /server-time returns the clock. Rather than maintaining a hand-written
# list of such fields, every endpoint is called TWICE and the paths that
# differ between the two calls are masked. Anything that changes without
# the database changing cannot be part of the contract, and this also
# surfaces nondeterminism nobody knew about.
# --------------------------------------------------------------------------

def differing_paths(a, b, prefix=""):
    """JSON paths where a and b disagree. A differing container is reported
    as one path rather than recursing into it."""
    if type(a) is not type(b):
        return {prefix}
    if isinstance(a, dict):
        if set(a) != set(b):
            return {prefix}
        out = set()
        for k in a:
            out |= differing_paths(a[k], b[k], f"{prefix}.{k}" if prefix else k)
        return out
    if isinstance(a, list):
        if len(a) != len(b):
            return {prefix}
        out = set()
        for i, (x, y) in enumerate(zip(a, b)):
            out |= differing_paths(x, y, f"{prefix}[{i}]")
        return out
    return set() if a == b else {prefix}


def apply_mask(obj, paths, prefix=""):
    if prefix in paths:
        return VOLATILE
    if isinstance(obj, dict):
        return {k: apply_mask(v, paths, f"{prefix}.{k}" if prefix else k)
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [apply_mask(v, paths, f"{prefix}[{i}]")
                for i, v in enumerate(obj)]
    return obj


# --------------------------------------------------------------------------
# Fetching and serialising
# --------------------------------------------------------------------------

def fetch(path, params):
    """Returns the response as a JSON-able dict, including for errors — a
    404 or a 500 is part of the contract too, and a migration that turns a
    200 into a 500 is exactly what this is meant to catch."""
    try:
        r = requests.get(BASE_URL + path, params=params, timeout=60)
    except requests.RequestException as exc:
        return {"_transport_error": type(exc).__name__}
    try:
        body = r.json()
    except ValueError:
        body = {"_non_json_body": r.text[:2000]}
    return {"_status": r.status_code, "_body": body}


def serialise(payload):
    """Keys are sorted so the stored file has a stable byte order.

    Object key order is not meaningful to Dart's jsonDecode, which builds a
    Map, so sorting removes a whole class of false alarms — Postgres will
    not return columns in Firestore's order. LIST order is left alone,
    because it IS meaningful: the order of days, entries and candidates is
    what the app renders.
    """
    return json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False)


def collect():
    """Calls every request twice and returns {slug: (text, volatile_paths)}."""
    subjects = derive_subjects()
    requests_list = build_requests(subjects)

    print(f"Base URL : {BASE_URL}")
    print(f"Subjects : regular={subjects.get('regular')} "
          f"reliever={subjects.get('reliever')} "
          f"headGuard={subjects.get('headGuard')} "
          f"schedule={subjects.get('scheduleId')}")
    print(f"Endpoints: {len(requests_list)}\n")

    results = {}
    for slug, path, params in requests_list:
        first = fetch(path, params)
        second = fetch(path, params)
        volatile = differing_paths(first, second)
        masked = apply_mask(first, volatile)
        results[slug] = (serialise(masked), volatile, path)
    return results, subjects


def _golden_path(slug):
    return os.path.join(GOLDEN_DIR, f"{slug}.json")


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def cmd_capture():
    results, _ = collect()
    os.makedirs(GOLDEN_DIR, exist_ok=True)

    errors, volatile_report = [], []
    for slug, (text, volatile, path) in sorted(results.items()):
        with open(_golden_path(slug), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text + "\n")
        payload = json.loads(text)
        status = payload.get("_status")
        if status is None or status >= 400:
            errors.append((slug, path, status or "transport error"))
        if volatile:
            volatile_report.append((slug, sorted(volatile)))

    print(f"Wrote {len(results)} files to {GOLDEN_DIR}\n")

    if volatile_report:
        print("Masked as volatile (differed between two identical calls):")
        for slug, paths in volatile_report:
            print(f"  {slug}: {', '.join(paths) or '(whole response)'}")
        print()

    if errors:
        print("Endpoints that did NOT return 2xx — check before trusting these:")
        for slug, path, status in errors:
            print(f"  [{status}] {slug}  {path}")
        print()

    print("Commit nothing here: golden/ holds real employee records and is "
          "git-ignored, like mock_data/.")
    return 0


def cmd_compare():
    if not os.path.isdir(GOLDEN_DIR):
        print(f"No golden/ directory at {GOLDEN_DIR} — run 'capture' first.")
        return 2

    results, _ = collect()
    changed, missing, added = [], [], []

    for slug, (text, _volatile, _path) in sorted(results.items()):
        path = _golden_path(slug)
        if not os.path.exists(path):
            added.append(slug)
            continue
        with open(path, encoding="utf-8") as fh:
            before = fh.read()
        after = text + "\n"
        if before != after:
            changed.append((slug, before, after))

    recorded = {f[:-5] for f in os.listdir(GOLDEN_DIR) if f.endswith(".json")}
    missing = sorted(recorded - set(results))

    for slug, before, after in changed:
        print(f"\n{'=' * 70}\nCHANGED: {slug}\n{'=' * 70}")
        diff = difflib.unified_diff(
            before.splitlines(), after.splitlines(),
            fromfile=f"golden/{slug}.json", tofile="current", lineterm="",
        )
        shown = list(diff)
        for line in shown[:80]:
            print(line)
        if len(shown) > 80:
            print(f"... {len(shown) - 80} more diff lines")

    print(f"\n{'=' * 70}")
    print(f"unchanged : {len(results) - len(changed) - len(added)}")
    print(f"changed   : {len(changed)}  {[s for s, _, _ in changed]}")
    print(f"new       : {len(added)}  {added}")
    print(f"missing   : {len(missing)}  {missing}")
    print("=" * 70)

    if changed or missing:
        print("\nFAIL — the API contract moved. Every difference above is "
              "either a bug to fix or a change to make deliberately and "
              "re-capture.")
        return 1

    print("\nOK — every recorded response is byte-identical.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("capture", "compare"),
                        nargs="?", default="capture")
    args = parser.parse_args()

    probe = fetch("/", None)
    if "_transport_error" in probe:
        print(f"Cannot reach {BASE_URL} ({probe['_transport_error']}).\n"
              f"Start the server first:  uvicorn api:app --reload --port 8000")
        return 2

    return cmd_capture() if args.mode == "capture" else cmd_compare()


if __name__ == "__main__":
    sys.exit(main())


# --------------------------------------------------------------------------
# What this does not cover
#
# * Write endpoints. POST/PUT/DELETE change mock_data/, so calling them
#   would make each run differ from the last for reasons unrelated to the
#   migration. Generation, publishing, assignment edits and the decision
#   endpoints stay covered by testing_*.py.
# * Auth. /login and /verify-password are POSTs and are about to change
#   anyway when passwords move to bcrypt, so freezing them now would only
#   record something already scheduled for replacement.
# * Anything absent from mock_data/. An endpoint whose subject cannot be
#   derived is skipped, so a thin collection means thin coverage — the
#   capture summary prints what was chosen, and it is worth reading.
# --------------------------------------------------------------------------
