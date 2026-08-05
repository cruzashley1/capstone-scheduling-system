"""
Smoke test for the special-assignment (pin) flow, run entirely against a
throw-away copy of mock_data so nothing real is touched:

    python testing_special.py

Covers the contract end to end: a pin moves the guard for the pinned
cycle, tags their entries isSpecial, keeps them out of the rotation
shuffle, warns about the post they left behind, and evaporates the
moment the next cycle is generated.
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import date

from mock_firestore import MockFirestoreClient
import scheduler
import rotation
import station_pools

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKS = []


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f" — {detail}" if detail else ""))


def main():
    tmp = tempfile.mkdtemp(prefix="special_smoke_")
    try:
        for name in ("employees.json", "stations.json"):
            shutil.copy(os.path.join(HERE, "mock_data", name), tmp)
        db = MockFirestoreClient(data_dir=tmp)

        employees = {d.id: d.to_dict()
                     for d in db.collection("employees").stream()}

        # Group 1 = stations STA001..STA008. Pick a morning regular whose
        # home is Monumento and pin them to Abad Santos for July 2026.
        guard = next(e for e in employees.values()
                     if e.get("type") == "regular"
                     and e.get("assignedShift") == "morning"
                     and (e.get("assignedStation") or "").strip() == "Monumento")
        pin_cycle = "202607"
        db.collection("special_assignments").document(f"{pin_cycle}_{guard['id']}").set({
            "id": f"{pin_cycle}_{guard['id']}",
            "rotationCycleId": pin_cycle,
            "employeeId": guard["id"],
            "employeeName": guard["name"],
            "employeeType": "regular",
            "stationId": "STA002",
            "stationName": "Abad Santos",
            "shift": "night",
            "homeStation": "Monumento",
            "createdAt": "2026-07-21T00:00:00+00:00",
        })

        print(f"Pinned {guard['name']} ({guard['id']}) "
              f"Monumento/morning -> Abad Santos/night for {pin_cycle}")

        # --- Generate July with rotation on --------------------------------
        schedules = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 7, 16), rotate=True)
        by_station = {s["stationName"]: s for s in schedules}

        def entries_for(schedule, emp_id):
            return [e for day in schedule["days"] for e in day["entries"]
                    if e["employeeId"] == emp_id]

        abad = entries_for(by_station["Abad Santos"], guard["id"])
        monu = entries_for(by_station["Monumento"], guard["id"])
        check("pinned guard scheduled at Abad Santos", len(abad) > 0,
              f"{len(abad)} entries")
        check("pinned guard absent from Monumento", len(monu) == 0)
        check("entries use the pinned shift (Night)",
              bool(abad) and all(e["shift"] == "Night" for e in abad),
              f"shifts={sorted(set(e['shift'] for e in abad))}")
        check("entries tagged isSpecial",
              bool(abad) and all(e.get("isSpecial") for e in abad))
        check("roster metadata lists the pin",
              any(p["employeeId"] == guard["id"]
                  for p in by_station["Abad Santos"]["specialAssignments"]))
        check("short-handed note for Monumento",
              any("leaving Monumento one guard short" in n
                  for n in schedules[0].get("rotationNotes", [])))

        placement = db.collection("station_rotation_assignments").document(
            f"{pin_cycle}_{guard['id']}").get().to_dict()
        check("rotation stored the pin, not a shuffle result",
              placement is not None
              and placement.get("stationName") == "Abad Santos"
              and placement.get("special") is True,
              json.dumps({k: placement.get(k) for k in
                          ("stationName", "special", "stayed")})
              if placement else "no placement doc")

        # Nobody anywhere is double-booked on any single day.
        dup = None
        seen = {}
        for s in schedules:
            for day in s["days"]:
                for e in day["entries"]:
                    key = (e["employeeId"], day["date"])
                    prev = seen.get(key)
                    if prev and prev != s["stationName"]:
                        dup = (e["employeeId"], day["date"], prev, s["stationName"])
                    seen[key] = s["stationName"]
        check("no guard works two stations on one day", dup is None,
              str(dup) if dup else "")

        # --- Generate August: the pin must have expired --------------------
        schedules_aug = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 8, 1), rotate=True)
        aug_by_station = {s["stationName"]: s for s in schedules_aug}
        aug_stations = {s["stationName"] for s in schedules_aug
                        if entries_for(s, guard["id"])}
        aug_entries = [e for s in schedules_aug
                       for e in entries_for(s, guard["id"])]
        check("August: pin expired (guard back in normal rotation)",
              bool(aug_entries) and not any(e.get("isSpecial")
                                            for e in aug_entries),
              f"now at {sorted(aug_stations)}")
        check("August: no pin metadata on any roster",
              all(not s["specialAssignments"] for s in schedules_aug))

        # --- A pin saved AFTER the cycle was first generated ---------------
        # The real-world order: the admin generates the month, then pins
        # someone, then generates the next period. The stored placement
        # already filled the station, so the pin pushes it over its number
        # — and the surplus is cut from the shift list. A pin must never be
        # what gets cut, or the guard disappears from the schedule entirely
        # (they were already pulled off their home station's roster).
        print("\nPin saved after the cycle's placement was stored:")
        scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 9, 1), rotate=True)

        stations = [d.to_dict() for d in db.collection("stations").stream()]
        g1 = station_pools.sort_stations(stations)[:8]
        target = g1[1]
        target_name = target["name"].strip()
        late_cycle = "202609"

        # Highest IDs in the group, so a plain ID sort would cut them.
        others = {s["name"].strip() for s in g1 if s["name"].strip() != target_name}
        late_pins = sorted(
            (e for e in employees.values()
             if e.get("type") == "regular"
             and e.get("assignedShift") == "morning"
             and (e.get("assignedStation") or "").strip() in others),
            key=lambda e: e["id"], reverse=True)[:2]

        for emp in late_pins:
            db.collection("special_assignments").document(
                f"{late_cycle}_{emp['id']}").set({
                    "id": f"{late_cycle}_{emp['id']}",
                    "rotationCycleId": late_cycle,
                    "employeeId": emp["id"], "employeeName": emp["name"],
                    "employeeType": "regular", "stationId": target["id"],
                    "stationName": target_name, "shift": "morning",
                    "homeStation": (emp.get("assignedStation") or "").strip(),
                    "createdAt": "2026-09-05T00:00:00+00:00"})
        print(f"  pinned {', '.join(e['id'] for e in late_pins)} "
              f"-> {target_name}/morning for {late_cycle}")

        schedules_sep = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 9, 16), rotate=True)
        sep_by_station = {s["stationName"]: s for s in schedules_sep}

        for emp in late_pins:
            at_target = entries_for(sep_by_station[target_name], emp["id"])
            check(f"late pin honoured for {emp['id']} "
                  f"(station already at its number)",
                  len(at_target) > 0,
                  f"{len(at_target)} entries at {target_name}")
            check(f"late-pinned {emp['id']} tagged isSpecial",
                  bool(at_target) and all(e.get("isSpecial") for e in at_target))

        # Displacing someone is fine — silently losing them is not.
        check("over-number shift names its surplus in the notes",
              any(target_name in n and "left unscheduled this period" in n
                  for s in schedules_sep for n in s.get("rotationNotes", [])),
              "no surplus note found")

        print()
        if all(CHECKS):
            print(f"ALL {len(CHECKS)} CHECKS PASSED")
            return 0
        print(f"{CHECKS.count(False)} of {len(CHECKS)} checks FAILED")
        return 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
