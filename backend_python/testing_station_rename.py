"""
Regression test for the Station Management / Schedule Management
disconnection caused by renaming stations destructively.

THE BUG
-------
Deleting a station and re-creating it under a new name (rather than using
Edit Station) leaves two things pointing at the old name:

  * every employee's `assignedStation` / `preferredStations`
  * the month's stored rotation placement in
    `station_rotation_assignments`

The generator buckets staff BY STATION NAME, so those guards land in a
bucket no station claims and are silently dropped. The station still gets
a schedule document — with zero entries on all 15 days. Publishing it
marked it "published" in Schedule Management while Station Management,
which counts guards in the published schedule, kept showing 0/N. The two
screens disagreed with no error anywhere.

WHAT THIS ASSERTS
-----------------
  1. A stored rotation placement naming a station that no longer exists is
     discarded and recomputed, with a warning (rotation.py).
  2. Guards stranded on an unknown station name produce a loud generation
     note instead of vanishing quietly (scheduler.py).
  3. The renamed station is staffed to its required headcount regardless,
     because placement fills what a station asks for from whoever the
     group has (placement.py) rather than from whoever's record happens
     to name it. The stranded guards are still a bug to fix — note 2 is
     what surfaces them — but they no longer cost the station its roster.
  4. An all-empty schedule cannot be published, individually or via
     Publish All (api.py) — the disconnection can no longer be reached.

Runs entirely in a temp directory against a copy of mock_data; the real
mock_data is never touched.
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import date

try:
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass

os.environ["USE_MOCK_DB"] = "1"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MOCK_DATA = os.path.join(BASE_DIR, "mock_data")

RENAMED_FROM = "MIA"
RENAMED_TO = "MIA Terminal"
GROUP = 3
START = date(2026, 7, 22)


def check(label, passed, detail=""):
    print(f"  {'PASS' if passed else 'FAIL'}  {label}"
          + (f"  - {detail}" if detail else ""))
    return passed


def main():
    if not os.path.isdir(MOCK_DATA):
        print("SKIPPED - mock_data/ not found. Seed it first.")
        return True

    workdir = tempfile.mkdtemp(prefix="station_rename_test_")
    try:
        for name in ("employees.json", "stations.json", "counters.json",
                     "station_rotation_assignments.json",
                     "rotation_cycles.json"):
            source = os.path.join(MOCK_DATA, name)
            if os.path.exists(source):
                shutil.copy(source, workdir)
        for name in ("schedules", "special_assignments",
                     "employee_notifications"):
            with open(os.path.join(workdir, f"{name}.json"), "w") as fh:
                json.dump({}, fh)

        from mock_firestore import MockFirestoreClient
        import api
        from models.schedule import ScheduleGenerateRequest

        db = MockFirestoreClient(data_dir=workdir)
        api.db = db
        passed = True

        # Reproduce the destructive rename: the station document changes
        # name without the employee records or the stored placement
        # following it (exactly what delete + re-create does).
        target = next(d for d in db.collection("stations").stream()
                      if d.to_dict()["name"].strip() == RENAMED_FROM)
        station_id = target.id
        db.collection("stations").document(station_id).update(
            {"name": RENAMED_TO})
        print(f"\nRenamed {station_id} '{RENAMED_FROM}' -> '{RENAMED_TO}' "
              "destructively (employees still say "
              f"'{RENAMED_FROM}')\n")

        stranded = [d.to_dict() for d in db.collection("employees").stream()
                    if (d.to_dict().get("assignedStation") or "").strip()
                    == RENAMED_FROM]
        passed &= check("test setup stranded some guards",
                        len(stranded) > 0, f"{len(stranded)} guards")

        result = api.generate_schedules(ScheduleGenerateRequest(
            group=GROUP, startDate=START.isoformat(),
            overwrite=True, rotate=True))
        notes = result.get("rotationNotes", [])

        # 1. The stale rotation placement is detected and recomputed.
        passed &= check(
            "stale rotation placement recomputed, not reused",
            any("no longer exist" in n for n in notes),
            next((n for n in notes if "no longer exist" in n), "no such note"))
        passed &= check(
            "stale placement was NOT silently reused",
            not any("Reusing the existing rotation" in n for n in notes))

        # 2. Stranded guards are reported rather than silently dropped.
        stranded_note = next(
            (n for n in notes
             if "matches no existing station" in n and RENAMED_FROM in n),
            None)
        passed &= check("stranded guards reported in generation notes",
                        stranded_note is not None,
                        stranded_note or "no such note")

        # 3. The renamed station is STAFFED anyway. Placement is
        #    demand-driven now: the station asks for a headcount and the
        #    engine fills it from whoever the group still has, so losing
        #    the guards whose records name the old station no longer
        #    leaves an empty schedule behind. The stranded guards are
        #    still a real problem — note 2 above is what reports them.
        renamed = next(s for s in result["schedules"]
                       if s["stationId"] == station_id)
        station = db.collection("stations").document(station_id).get().to_dict()
        required = int(station.get("requiredEmployees") or 0)
        daily = sorted({len(d["entries"]) for d in renamed["days"]})
        passed &= check(
            "renamed station is still staffed despite the stranded guards",
            daily == [required],
            f"required {required}, daily headcount {daily}")

        # The publish guard rails still have to hold for a schedule that
        # IS empty, whatever caused it — so assert them against one.
        empty_id = f"{station_id}_empty_probe"
        db.collection("schedules").document(empty_id).set({
            **renamed, "id": empty_id, "status": "unpublished",
            "days": [{"date": d["date"], "entries": []}
                     for d in renamed["days"]],
        })
        try:
            api.publish_schedule(empty_id)
            passed &= check("single publish refuses an empty schedule",
                            False, "it published anyway")
        except Exception as exc:
            passed &= check("single publish refuses an empty schedule",
                            "no guards assigned" in str(exc), str(exc)[:120])

        bulk = api.publish_all_schedules()
        passed &= check("Publish All skips the empty schedule",
                        RENAMED_TO in bulk.get("skippedEmpty", []),
                        f"skippedEmpty={bulk.get('skippedEmpty')}")

        stored = db.collection("schedules").document(empty_id).get()
        passed &= check(
            "empty schedule is still unpublished after Publish All",
            stored.to_dict().get("status") == "unpublished",
            f"status={stored.to_dict().get('status')}")

        # 4. Every schedule that DID publish actually has guards in it, so
        #    Station Management and Schedule Management cannot disagree.
        mismatched = []
        for doc in db.collection("schedules").stream():
            data = doc.to_dict()
            if data.get("status") != "published":
                continue
            if not any(d["entries"] for d in data.get("days", [])):
                mismatched.append(data.get("stationName"))
        passed &= check(
            "no published schedule is empty (no screen disagreement)",
            not mismatched, f"{mismatched}" if mismatched else "all populated")

        print("\n" + ("ALL CHECKS PASSED" if passed
                      else "SOME CHECKS FAILED - see above"))
        return passed
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
