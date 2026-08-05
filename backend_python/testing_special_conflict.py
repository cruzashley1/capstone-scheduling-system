"""
Regression test for the double-booking a Special Assignment used to cause:

    python testing_special_conflict.py

A pin relocates a guard for a whole month, but generation only ever writes
the documents it was asked for. A by-station run computes the entire group
(the reliever pool is shared, so it has to) and then throws every sibling
station's freshly-computed roster away — including the one the pinned guard
was correctly removed from. The station they left therefore keeps its OLD
saved schedule, which still has them, and the guard ends up rostered at two
stations on the same dates.

Generation now refuses to write a schedule it can already tell contradicts
another saved one, and names what has to be regenerated instead.
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
MOCK_DATA = os.path.join(HERE, "mock_data")
START = date(2026, 9, 1)
CYCLE = "202609"
GROUP = 1
CHECKS = []


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}"
          + (f" — {detail}" if detail else ""))


def stations_of(db, employee_id):
    """Every saved schedule that rosters this guard, by station name."""
    found = {}
    for doc in db.collection("schedules").stream():
        schedule = doc.to_dict()
        count = len([e for day in schedule.get("days", [])
                     for e in day.get("entries", [])
                     if e.get("employeeId") == employee_id])
        if count:
            found[schedule["stationName"]] = count
    return found


def main():
    workdir = tempfile.mkdtemp(prefix="special_conflict_")
    try:
        for name in ("employees.json", "stations.json", "counters.json"):
            source = os.path.join(MOCK_DATA, name)
            if os.path.exists(source):
                shutil.copy(source, workdir)
        for name in ("schedules", "special_assignments",
                     "employee_notifications",
                     "station_rotation_assignments", "rotation_cycles"):
            with open(os.path.join(workdir, f"{name}.json"), "w") as fh:
                json.dump({}, fh)

        from mock_firestore import MockFirestoreClient
        from fastapi import HTTPException
        import api
        import station_pools
        from models.schedule import ScheduleGenerateRequest

        db = MockFirestoreClient(data_dir=workdir)
        api.db = db

        stations = station_pools.sort_stations(
            [d.to_dict() for d in db.collection("stations").stream()])
        target = stations[0]   # the station the guard is pinned TO

        # 1. The admin generates the whole group first, the normal way.
        api.generate_schedules(ScheduleGenerateRequest(
            group=GROUP, startDate=START.isoformat(),
            overwrite=True, rotate=True))
        print(f"Generated group {GROUP} for {START}")

        # 2. Pick someone the run put on a station OTHER than the target,
        #    then pin them to the target — the exact move that strands the
        #    roster they came off.
        guard = None
        for doc in db.collection("schedules").stream():
            schedule = doc.to_dict()
            if schedule["stationId"] == target["id"]:
                continue
            for day in schedule.get("days", []):
                for entry in day.get("entries", []):
                    if not entry.get("isReliever"):
                        guard = (entry["employeeId"], entry["employeeName"],
                                 schedule["stationName"])
                        break
                if guard:
                    break
            if guard:
                break

        emp_id, emp_name, from_station = guard
        emp = db.collection("employees").document(emp_id).get().to_dict()
        shift = {"regular": emp.get("assignedShift", "morning"),
                 "headGuard": emp.get("assignedShift", "hgDay"),
                 "reliever": None}[emp.get("type", "regular")]
        db.collection("special_assignments").document(
            f"{CYCLE}_{emp_id}").set({
                "id": f"{CYCLE}_{emp_id}", "rotationCycleId": CYCLE,
                "employeeId": emp_id, "employeeName": emp_name,
                "employeeType": emp.get("type", "regular"),
                "stationId": target["id"], "stationName": target["name"],
                "shift": shift,
                "homeStation": (emp.get("assignedStation") or "").strip(),
                "createdAt": "2026-09-02T00:00:00+00:00"})
        print(f"Pinned {emp_name} ({emp_id}) {from_station} -> "
              f"{target['name']} for {CYCLE}\n")

        # 3. The Special Assignments picker has to warn about this BEFORE
        #    the admin pins anyone, and it has to name the same station
        #    generation is about to block on — otherwise the warning
        #    sends them somewhere the fix isn't.
        duty = api.get_duty_status(cycleId=CYCLE)["dutyStatus"]
        posts = duty.get(emp_id, [])
        check("duty status knows where the guard is already rostered",
              any(p["stationName"] == from_station for p in posts),
              str([p["stationName"] for p in posts]))
        check("duty status carries the period and publish state",
              bool(posts) and all(
                  p.get("startDate") and p.get("endDate") and p.get("status")
                  for p in posts),
              str(posts[:1]))

        # 4. Regenerating ONLY the target is what used to strand them.
        blocked = None
        try:
            api.generate_schedules(ScheduleGenerateRequest(
                group=GROUP, startDate=START.isoformat(), overwrite=True,
                rotate=True, stationId=target["id"]))
        except HTTPException as exc:
            blocked = exc

        detail = blocked.detail if blocked else {}
        message = detail.get("message", "") if isinstance(detail, dict) else ""

        check("by-station run is blocked, not silently written",
              blocked is not None and blocked.status_code == 409,
              f"status={blocked.status_code}" if blocked else "run succeeded")
        # Overwrite fixes the ordinary "already generated" 409 but can
        # never fix this one, so the app has to tell them apart.
        check("blocked with the special-assignment code, not a plain 409",
              isinstance(detail, dict)
              and detail.get("code") == "special_assignment_clash",
              str(detail)[:80])
        check("the message names the stranded station",
              from_station in message, from_station)
        check("the message names the guard", emp_name in message)
        check("the message says what to do about it", "Regenerate" in message)
        check("the stranded station is listed machine-readably",
              isinstance(detail, dict)
              and any(s.get("stationName") == from_station
                      for s in detail.get("stations", [])),
              str(detail.get("stations") if isinstance(detail, dict) else ""))

        where = stations_of(db, emp_id)
        check("nothing was saved while the clash stands",
              len(where) == 1 and from_station in where, str(where))

        # 5. Regenerating the stranded station clears the clash: the pin
        #    takes the guard off it, so nothing contradicts the pin.
        api.generate_schedules(ScheduleGenerateRequest(
            group=GROUP, startDate=START.isoformat(), overwrite=True,
            rotate=True,
            stationId=next(s["id"] for s in stations
                           if s["name"] == from_station)))
        where = stations_of(db, emp_id)
        check(f"regenerating {from_station} drops the pinned guard",
              from_station not in where, str(where))

        # 6. ...and now the target generates cleanly.
        api.generate_schedules(ScheduleGenerateRequest(
            group=GROUP, startDate=START.isoformat(), overwrite=True,
            rotate=True, stationId=target["id"]))
        where = stations_of(db, emp_id)
        check("target station now generates without being blocked",
              target["name"] in where, str(where))
        check("guard is rostered at exactly one station",
              len(where) == 1, str(where))

        # 7. A full-group run was never at risk — it rewrites every
        #    station in the group, so no sibling is left holding them.
        api.generate_schedules(ScheduleGenerateRequest(
            group=GROUP, startDate=START.isoformat(),
            overwrite=True, rotate=True))
        where = stations_of(db, emp_id)
        check("full-group run still works and honours the pin",
              where == {target["name"]: where.get(target["name"])},
              str(where))

        # 8. The ordinary "this period already has a schedule" 409 must
        #    keep its plain-string detail — the app reads that one as
        #    "ask whether to overwrite", which is still the right fix.
        plain = None
        try:
            api.generate_schedules(ScheduleGenerateRequest(
                group=GROUP, startDate=START.isoformat(), rotate=True))
        except HTTPException as exc:
            plain = exc
        check("plain overlap conflict still returns a 409 string",
              plain is not None and plain.status_code == 409
              and isinstance(plain.detail, str)
              and "already has a generated schedule" in plain.detail,
              str(plain.detail)[:80] if plain else "no conflict raised")

        print()
        if all(CHECKS):
            print(f"ALL {len(CHECKS)} CHECKS PASSED")
            return 0
        print(f"{CHECKS.count(False)} of {len(CHECKS)} checks FAILED")
        return 1
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
