"""
Smoke test for the preparation window — the hour a replacement gets
before they stand the post. Runs against a throw-away copy of mock_data,
so nothing real is touched:

    python testing_prep_window.py

The problem it fixes: assigning a cover handed over the absent guard's
duty unchanged. A guard told at 0900H that they were covering an 0500H -
1700H post was, on paper, already four hours into a duty they had not
heard about — with no time to put a uniform on, pack food, or travel.

The rule under test:

    time-in   = the later of the post's own time-in and one hour from
                the assignment. Exactly one hour, to the minute.
    time-out  = the post's own time-out plus two hours — the hour lost
                at the front, plus an hour of extension.

    0500H - 1700H, assigned at 0900H  ->  1000H - 1900H

and, just as importantly, that a cover assigned with time to spare keeps
the post's real hours and gets no adjustment at all.
"""

import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone

os.environ.setdefault("USE_MOCK_DB", "1")
os.environ.setdefault("DB_BACKEND", "mock")

import prep_window
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


def at(day, hour, minute=0, second=0):
    """A moment on the guards' own clock."""
    return datetime(2026, 8, day, hour, minute, second, tzinfo=PHT)


def window(time_in, time_out, moment, date_iso=DATE):
    return prep_window.adjust(date_iso, time_in, time_out, now=moment)


def seed_schedule(db, entries, doc="SCHED-TEST", start=DATE, end=DATE):
    db.collection("schedules").document(doc).set({
        "id": doc,
        "stationId": "STA001",
        "stationName": STATION,
        "startDate": start,
        "endDate": end,
        "status": "published",
        "days": [{"date": start, "entries": entries}],
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


def main():
    print("The arithmetic — an 0500H - 1700H head guard post:")

    # The example the whole feature was specified from.
    w = window("05:00", "17:00", at(9, 9))
    check("reported at 0900H, the cover stands 1000H - 1900H",
          w["range"] == "1000H - 1900H", w["range"])
    check("and it is flagged as adjusted", w["adjusted"] is True)
    check("the post's own hours are kept alongside",
          w["originalRange"] == "0500H - 1700H", w["originalRange"])
    check("the time-in is on the duty date itself", w["dayOffset"] == 0)
    check("the guard is told when to be there",
          w["startsAt"] == at(9, 10).isoformat(), w["startsAt"])

    print("\nWhen there is already time to prepare, nothing moves:")
    check("assigned two days ahead",
          window("05:00", "17:00", at(7, 12))["adjusted"] is False)
    check("assigned at 0300H for an 0500H post — two hours is enough",
          window("05:00", "17:00", at(9, 3))["adjusted"] is False)
    check("assigned exactly one hour before time-in, to the minute",
          window("05:00", "17:00", at(9, 4))["adjusted"] is False)
    check("...and those covers keep the post's real hours",
          window("05:00", "17:00", at(9, 3))["range"] == "0500H - 1700H")

    print("\nA minute inside the hour is short notice, and moves:")
    late = window("05:00", "17:00", at(9, 4, 1))
    check("assigned 59 minutes before time-in",
          late["adjusted"] and late["range"] == "0501H - 1900H",
          late["range"])

    print("\nThe hour is exact, never rounded to a tidy number:")
    check("0917H assignment times in at 1017H",
          window("05:00", "17:00", at(9, 9, 17))["range"] == "1017H - 1900H",
          window("05:00", "17:00", at(9, 9, 17))["range"])
    check("seconds round the time-in UP, so the hour is never shaved",
          window("05:00", "17:00", at(9, 9, 17, 30))["timeIn"] == "10:18",
          window("05:00", "17:00", at(9, 9, 17, 30))["timeIn"])

    print("\nA regular 0500H - 1400H post, not the head guard's:")
    regular = window("05:00", "14:00", at(9, 9))
    check("reported at 0900H, the cover stands 1000H - 1600H",
          regular["range"] == "1000H - 1600H", regular["range"])

    print("\nOvernight posts (HG Night 1700H - 0500H):")
    evening = window("17:00", "05:00", at(9, 20))
    check("assigned at 2000H, the cover stands 2100H - 0700H",
          evening["range"] == "2100H - 0700H", evening["range"])
    check("and its time-in is still on the duty date",
          evening["dayOffset"] == 0)

    # The case a bare "HH:MM" pair cannot express on its own: the duty
    # date is Aug 9, but this cover times in on Aug 10.
    small_hours = window("17:00", "05:00", at(10, 2, 30))
    check("assigned at 0230H the NEXT morning, it stands 0330H - 0700H",
          small_hours["range"] == "0330H - 0700H", small_hours["range"])
    check("and dayOffset says that time-in is the following day",
          small_hours["dayOffset"] == 1, str(small_hours["dayOffset"]))

    print("\nThere is always a duty left to stand:")
    last_minute = window("05:00", "14:00", at(9, 13, 59))
    check("assigned a minute before the post times out, the cover still "
          "gets an hour on post",
          last_minute["range"] == "1459H - 1600H", last_minute["range"])

    print("\nUnreadable hours are left alone rather than guessed at:")
    check("no times on file", window(None, None, at(9, 9)) is None)
    check("an unreadable date",
          window("05:00", "17:00", at(9, 9), date_iso="not-a-date") is None)

    # --- End to end, through apply_replacement -----------------------
    tmp = tempfile.mkdtemp(prefix="prep_window_")
    try:
        for name in ("employees.json", "stations.json"):
            shutil.copy(os.path.join(HERE, "mock_data", name), tmp)
        db = MockFirestoreClient(data_dir=tmp)

        employees = [d.to_dict() for d in db.collection("employees").stream()]
        head_guards = [e for e in employees if e.get("type") == "headGuard"]
        absentee, cover = head_guards[0], head_guards[1]

        print(f"\nAssigning a cover for real — {absentee['name']} absent, "
              f"{cover['name']} covering:")

        seed_schedule(db, [entry(absentee, "HG Day", "05:00", "17:00",
                                 post="Head Guard")])
        record = replacements.apply_replacement(
            db, ReplacementApplyRequest(
                date=DATE, station=STATION, shift="HG Day",
                absentEmployeeId=absentee["id"],
                absentEmployeeName=absentee["name"],
                replacementEmployeeId=cover["id"]),
            now=at(9, 9))

        entries = db.collection("schedules").document(
            "SCHED-TEST").get().to_dict()["days"][0]["entries"]
        stood = entries[0]
        check("the schedule entry passes to the cover",
              stood["employeeId"] == cover["id"]
              and stood["coveringFor"] == absentee["id"])
        check("the entry now reads 1000H - 1900H",
              (stood["timeIn"], stood["timeOut"]) == ("10:00", "19:00"),
              f"{stood['timeIn']} - {stood['timeOut']}")
        check("and it remembers the post's own hours",
              (stood["originalTimeIn"], stood["originalTimeOut"])
              == ("05:00", "17:00"))
        check("the audit record carries both, for the absence log",
              record["timeIn"] == "10:00"
              and record["originalTimeOut"] == "17:00"
              and record["prepAdjusted"] is True,
              str({k: record[k] for k in
                   ("timeIn", "timeOut", "originalTimeIn", "originalTimeOut",
                    "prepAdjusted")}))

        notice = db.collection("employee_notifications").document(
            f"NTF-{DATE.replace('-', '')}-{cover['id']}-HGDAY"
        ).get().to_dict()["message"]
        check("the guard is told the hour is theirs to prepare in",
              "1 hour to get ready and travel" in notice, notice)
        check("...and where to be when it runs out",
              f"be at {STATION} by 1000H" in notice, notice)
        check("...and what their duty now is",
              "1000H - 1900H" in notice, notice)

        # The same absence, covered with two days' notice: nothing about
        # the post's hours should change.
        ahead = "2026-08-12"
        seed_schedule(db, [entry(absentee, "HG Day", "05:00", "17:00",
                                 post="Head Guard")],
                      doc="SCHED-AHEAD", start=ahead, end=ahead)
        replacements.apply_replacement(
            db, ReplacementApplyRequest(
                date=ahead, station=STATION, shift="HG Day",
                absentEmployeeId=absentee["id"],
                absentEmployeeName=absentee["name"],
                replacementEmployeeId=cover["id"]),
            now=at(10, 9))

        planned = db.collection("schedules").document(
            "SCHED-AHEAD").get().to_dict()["days"][0]["entries"][0]
        print("\nA cover assigned two days ahead:")
        check("keeps the post's real hours",
              (planned["timeIn"], planned["timeOut"]) == ("05:00", "17:00"),
              f"{planned['timeIn']} - {planned['timeOut']}")
        check("and carries no adjustment to explain",
              "originalTimeIn" not in planned)

        early_notice = db.collection("employee_notifications").document(
            f"NTF-{ahead.replace('-', '')}-{cover['id']}-HGDAY"
        ).get().to_dict()["message"]
        check("its notification names the duty without the prep wording",
              "0500H - 1700H" in early_notice
              and "get ready and travel" not in early_notice,
              early_notice)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    passed = sum(1 for c in CHECKS if c)
    print(f"\n{passed}/{len(CHECKS)} checks passed")
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    sys.exit(main())
