"""
Smoke test for the cover window — when Find Replacement is allowed to
assign anyone at all. Runs against a throw-away copy of mock_data, so
nothing real is touched:

    python testing_replacement_window.py

The bug it pins down: an absence filed on Aug 9 still offered "Find
Replacement" on Aug 11, and applying it rewrote a schedule entry for a
shift that had finished two days earlier — sending a "report for duty"
alert about a duty nobody could report to.

The rule under test: a cover may be assigned only while the post is
still standing, i.e. up to its time-out. That covers every past date for
free, handles overnight posts timing out the next morning, and reads the
STAGGERED window off the guard's own schedule entry rather than the
shift's base hours, because two guards on one shift can time out four
hours apart.
"""

import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone

os.environ.setdefault("USE_MOCK_DB", "1")
os.environ.setdefault("DB_BACKEND", "mock")

import replacements
from models.replacement import ReplacementApplyRequest
from mock_firestore import MockFirestoreClient

HERE = os.path.dirname(os.path.abspath(__file__))
PHT = timezone(timedelta(hours=8))
CHECKS = []

DATE = "2026-08-09"
STATION = "Monumento"


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f" — {detail}" if detail else ""))


def at(day, hour, minute=0):
    """A moment on the guards' own clock."""
    return datetime(2026, 8, day, hour, minute, tzinfo=PHT)


def seed_schedule(db, entries, start=DATE, end=DATE):
    """One published schedule covering DATE with the given entries."""
    db.collection("schedules").document("SCHED-TEST").set({
        "id": "SCHED-TEST",
        "stationId": "STA001",
        "stationName": STATION,
        "startDate": start,
        "endDate": end,
        "status": "published",
        "days": [{"date": DATE, "entries": entries}],
    })


def entry(employee, shift, time_in, time_out, post="SW Platform"):
    return {
        "id": f"E-{employee['id']}",
        "employeeId": employee["id"],
        "employeeName": employee.get("name", ""),
        "shift": shift,
        "post": post,
        "timeIn": time_in,
        "timeOut": time_out,
        "isReliever": employee.get("type") == "reliever",
        "coveringFor": None,
    }


def refuses(label, fn, *, contains=""):
    """Asserts apply refuses, and that it says why in words the admin can
    act on."""
    try:
        fn()
    except ValueError as e:
        ok = contains.lower() in str(e).lower()
        check(label, ok, str(e) if not ok else f'"{e}"')
        return
    except Exception as e:  # a 404/500-shaped failure is not the refusal
        check(label, False, f"{type(e).__name__}: {e}")
        return
    check(label, False, "the replacement was applied")


def main():
    tmp = tempfile.mkdtemp(prefix="cover_window_")
    try:
        for name in ("employees.json", "stations.json"):
            shutil.copy(os.path.join(HERE, "mock_data", name), tmp)
        db = MockFirestoreClient(data_dir=tmp)

        employees = [d.to_dict() for d in db.collection("employees").stream()]
        absentee = next(e for e in employees
                        if e.get("type") == "regular"
                        and e.get("assignedShift") == "morning")
        # A morning regular who is NOT on the schedule that day, so they
        # are a legitimate candidate with no conflict.
        cover = next(e for e in employees
                     if e.get("type") == "regular"
                     and e.get("assignedShift") == "morning"
                     and e["id"] != absentee["id"])

        print(f"Absent:  {absentee['name']} ({absentee['id']})")
        print(f"Cover:   {cover['name']} ({cover['id']})")
        print(f"Date:    {DATE}, Morning at {STATION}\n")

        # --- The window itself ---------------------------------------
        # A base-hours Morning post: 0500H - 1400H on the duty date.
        seed_schedule(db, [entry(absentee, "Morning", "05:00", "14:00")])
        window = replacements.cover_window(
            db, DATE, STATION, "Morning", absentee["id"])

        print("The window, for an 0500H - 1400H Morning post:")
        check("it ends at the post's time-out, on the guards' clock",
              window["endsAt"] == at(9, 14).isoformat(), window["endsAt"])
        check("open an hour before time-out",
              not replacements.is_closed(window, at(9, 13)))
        check("open DURING the duty — a mid-shift absence is the whole "
              "point of this flow",
              not replacements.is_closed(window, at(9, 9)))
        check("open before time-in too",
              not replacements.is_closed(window, at(9, 4)))
        check("shut at time-out exactly",
              replacements.is_closed(window, at(9, 14)))
        check("shut two days later — the case the admin hit",
              replacements.is_closed(window, at(11, 10)))

        # --- Staggered posts -----------------------------------------
        # The same shift, a later rung of the station's ladder. Judging
        # this by the shift's base hours would shut the window four hours
        # early, on a post still being manned.
        print("\nA staggered 0900H - 1800H post on the same Morning shift:")
        seed_schedule(db, [entry(absentee, "Morning", "09:00", "18:00",
                                 post="Concourse")])
        staggered = replacements.cover_window(
            db, DATE, STATION, "Morning", absentee["id"])
        check("the window follows the ENTRY, not the shift's base hours",
              staggered["endsAt"] == at(9, 18).isoformat(),
              staggered["endsAt"])
        check("still open at 1500H, after the base shift would have ended",
              not replacements.is_closed(staggered, at(9, 15)))
        check("shut at 1800H", replacements.is_closed(staggered, at(9, 18)))

        # --- Overnight posts -----------------------------------------
        print("\nAn overnight Night post, 2100H - 0600H:")
        seed_schedule(db, [entry(absentee, "Night", "21:00", "06:00",
                                 post="Roving")])
        night = replacements.cover_window(
            db, DATE, STATION, "Night", absentee["id"])
        check("it times out the NEXT morning, not at midnight",
              night["endsAt"] == at(10, 6).isoformat(), night["endsAt"])
        check("still open at 0200H, while the guard is on post",
              not replacements.is_closed(night, at(10, 2)))
        check("shut at 0600H", replacements.is_closed(night, at(10, 6)))

        # --- Fallbacks -----------------------------------------------
        print("\nWhen the post's hours aren't on the entry:")
        seed_schedule(db, [entry(absentee, "Morning", None, None)])
        fallback = replacements.cover_window(
            db, DATE, STATION, "Morning", absentee["id"])
        check("the shift's base hours stand in",
              fallback["endsAt"] == at(9, 14).isoformat(), fallback["endsAt"])

        unknown = replacements.cover_window(
            db, DATE, STATION, "Split", absentee["id"])
        check("an unknown shift label falls back to the end of the day, "
              "not to 'closed' — it must not block a live cover",
              unknown["endsAt"] == at(10, 0).isoformat(), unknown["endsAt"])
        check("...and that fallback is still shut two days later",
              replacements.is_closed(unknown, at(11, 10)))

        check("an unreadable date has no window at all",
              replacements.cover_window(
                  db, "not-a-date", STATION, "Morning", absentee["id"])
              is None)
        check("no window is treated as open, never as shut",
              not replacements.is_closed(None))

        # --- suggest() stays clock-free ------------------------------
        # The ranking must say the same thing all day: the golden files
        # record this endpoint, and a response that quietly changes at
        # 1400H would turn every later compare into a false alarm.
        print("\nThe suggestion list:")
        seed_schedule(db, [entry(absentee, "Morning", "05:00", "14:00")])
        names = [c["employee"]["id"]
                 for c in replacements.suggest(
                     db, DATE, STATION, "Morning", absentee["id"])]
        check("it offers candidates for a post that is over — the window "
              "is a separate question, asked alongside it",
              cover["id"] in names, f"{len(names)} candidates")

        # --- apply_replacement enforces it ---------------------------
        print("\nApplying a cover:")
        req = ReplacementApplyRequest(
            date=DATE,
            station=STATION,
            shift="Morning",
            absentEmployeeId=absentee["id"],
            absentEmployeeName=absentee["name"],
            replacementEmployeeId=cover["id"],
        )
        refuses("refused once the post has timed out (this one is judged "
                "against the real clock, which is past 2026-08-09)",
                lambda: replacements.apply_replacement(db, req),
                contains="timed out at 1400H")
        refuses("the refusal names the post, so the admin knows which one",
                lambda: replacements.apply_replacement(db, req),
                contains=f"Morning post at {STATION}")

        entries = db.collection("schedules").document(
            "SCHED-TEST").get().to_dict()["days"][0]["entries"]
        check("and the schedule was left exactly as it was",
              entries[0]["employeeId"] == absentee["id"]
              and entries[0].get("coveringFor") is None)
        check("no audit record was written for the refused apply",
              not list(db.collection("replacements").stream()))
        check("and no 'report for duty' alert was sent to the cover",
              not [d for d in
                   db.collection("employee_notifications").stream()
                   if d.to_dict().get("employeeId") == cover["id"]])

        # The same apply, against a post that is still standing: a
        # schedule far enough ahead that its window can't have closed.
        ahead = (datetime.now(PHT) + timedelta(days=30)).date().isoformat()
        db.collection("schedules").document("SCHED-AHEAD").set({
            "id": "SCHED-AHEAD",
            "stationId": "STA001",
            "stationName": STATION,
            "startDate": ahead,
            "endDate": ahead,
            "status": "published",
            "days": [{"date": ahead, "entries": [
                dict(entry(absentee, "Morning", "05:00", "14:00"),
                     id="E-AHEAD")]}],
        })
        try:
            record = replacements.apply_replacement(
                db, ReplacementApplyRequest(
                    date=ahead,
                    station=STATION,
                    shift="Morning",
                    absentEmployeeId=absentee["id"],
                    absentEmployeeName=absentee["name"],
                    replacementEmployeeId=cover["id"],
                ))
            check("a post that hasn't timed out is still covered normally",
                  record["replacementEmployeeId"] == cover["id"])
            ahead_entries = db.collection("schedules").document(
                "SCHED-AHEAD").get().to_dict()["days"][0]["entries"]
            check("and the schedule entry passes to the cover",
                  ahead_entries[0]["employeeId"] == cover["id"]
                  and ahead_entries[0]["coveringFor"] == absentee["id"])
        except Exception as e:
            check("a post that hasn't timed out is still covered normally",
                  False, f"{type(e).__name__}: {e}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    passed = sum(1 for c in CHECKS if c)
    print(f"\n{passed}/{len(CHECKS)} checks passed")
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    sys.exit(main())
