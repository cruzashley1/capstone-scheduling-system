"""
End-to-end smoke test for the absence chain the head guard drives:

    roster -> head guard marks someone absent -> submits -> the report
    lands unread on the admin's Notifications -> the absentee shows up on
    Absent Today -> the admin gets replacement candidates -> applying one
    stamps the report, fills the post and tells the cover they are on.

Runs against a throw-away copy of mock_data, so nothing real is touched:

    python testing_absence_report.py

TWO CLOCKS, AND WHY THE DATA IS MOVED

Half this chain is gated on time. Filing a report is only allowed while
the head guard is standing the duty (server_clock, freezable with
SCHED_FREEZE_NOW), and assigning a cover is only allowed while the post
is still standing (replacements.py, which reads the real Philippine
clock and is NOT freezable).

So the test moves the whole mock schedule set forward onto today's date
— every station, by the same number of days, so nobody's conflicts
change — and then freezes only the head guard's own clock to put them on
post. That way both gates are answered honestly instead of one of them
being stubbed.

Both head guards are exercised, because they do not cover the same
ground: the day HG files Morning and Afternoon, the night HG files Night
alone. The replacement is applied to the NIGHT absence on purpose — an
overnight post times out at 0600H tomorrow, so its cover window is open
at every hour of today and the result does not depend on when this is
run.
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone

os.environ.setdefault("USE_MOCK_DB", "1")
os.environ.setdefault("DB_BACKEND", "mock")

import api
from models.attendance import (AttendanceRecordIn,
                               AttendanceReportCreateRequest)
from models.replacement import ReplacementApplyRequest
from mock_firestore import MockFirestoreClient

HERE = os.path.dirname(os.path.abspath(__file__))
PHT = timezone(timedelta(hours=8))
CHECKS = []

# The day in mock_data whose roster this test is built around, and which
# gets moved onto today. Monumento that day has a full Morning and
# Afternoon under one HG Day, and a Night under one HG Night.
SOURCE_DAY = date(2026, 8, 10)
STATION = "Monumento"
HG_DAY = ("CRU963", "Rosa Cruz")        # HG Day,   0500H-1700H
HG_NIGHT = ("MAN496", "Grace Manalo")   # HG Night, 1700H-0500H
DAY_ABSENTEE = "DOM458"                 # Morning, Roving 0700H-1600H
NIGHT_ABSENTEE = "GAR468"               # Night,   Roving 2100H-0600H

TODAY = datetime.now(PHT).date()
DATE = TODAY.isoformat()

COLLECTIONS = ("employees.json", "stations.json", "schedules.json",
               "attendance_reports.json", "replacements.json",
               "employee_notifications.json", "absence_requests.json",
               "counters.json", "cover_offers.json")


def check(label, ok, detail=""):
    # bool() on purpose: several checks assert on a non-empty list, and a
    # tally of `is True` would quietly drop them from the count.
    ok = bool(ok)
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}"
          + (f" - {detail}" if detail else ""))


def on_post_at(hour, minute=0):
    """Freezes the SERVER's clock at a moment on today's duty day. This
    is the clock the filing window is measured against, so this is what
    puts the head guard on post."""
    os.environ["SCHED_FREEZE_NOW"] = (
        f"{DATE}T{hour:02d}:{minute:02d}:00")


def move_schedules_onto_today(tmp):
    """Shifts every schedule in the copy forward so SOURCE_DAY lands on
    today, keeping all 16 stations in step.

    Moving one station alone would be worse than useless: replacement
    candidates are filtered by who is already rostered somewhere that
    day, so leaving the other 15 stations in August would offer up guards
    who are in fact standing a post elsewhere."""
    delta = TODAY - SOURCE_DAY
    path = os.path.join(tmp, "schedules.json")
    with open(path, encoding="utf-8") as f:
        schedules = json.load(f)

    def shift(iso):
        return (date.fromisoformat(iso) + delta).isoformat()

    for sched in schedules.values():
        sched["startDate"] = shift(sched["startDate"])
        sched["endDate"] = shift(sched["endDate"])
        for day in sched.get("days", []):
            day["date"] = shift(day["date"])

    with open(path, "w", encoding="utf-8") as f:
        json.dump(schedules, f)
    return delta


def file_report(head_guard, shift_name, roster, absentee):
    """One head guard files one shift's attendance, with `absentee`
    marked absent. Returns (report, absent name)."""
    rows = [e for e in roster if e["shift"] == shift_name]
    records = [
        AttendanceRecordIn(
            employeeId=e["employeeId"],
            name=e["employeeName"],
            shift=e["shift"],
            time=f"{e['timeIn']} - {e['timeOut']}",
            isPresent=e["employeeId"] != absentee,
            isReliever=e.get("isReliever", False),
        )
        for e in rows
    ]
    result = api.submit_attendance_report(AttendanceReportCreateRequest(
        headGuardId=head_guard[0],
        headGuardName=head_guard[1],
        station=STATION,
        shiftTitle=f"{shift_name} Shift",
        date=DATE,
        records=records,
    ))
    absent_name = next(r.name for r in records if not r.isPresent)
    return result, absent_name


def main():
    tmp = tempfile.mkdtemp(prefix="absence_chain_")
    try:
        for name in COLLECTIONS:
            src = os.path.join(HERE, "mock_data", name)
            if os.path.exists(src):
                shutil.copy(src, tmp)
        delta = move_schedules_onto_today(tmp)
        api.db = MockFirestoreClient(data_dir=tmp)

        print(f"Station:    {STATION}")
        print(f"Duty day:   {DATE} (mock rosters moved "
              f"{delta.days:+d} days onto today)")
        print(f"Day HG:     {HG_DAY[1]} ({HG_DAY[0]}), 0500H-1700H")
        print(f"Night HG:   {HG_NIGHT[1]} ({HG_NIGHT[0]}), 1700H-0500H\n")

        # --- 1. The roster the report is built from -------------------
        print("1. The day head guard opens the report - what do they get?")
        on_post_at(9)
        overview = api.get_station_overview(HG_DAY[0], date=DATE)["overview"]
        roster = overview["onDuty"]
        check("the station resolves to the one they actually work",
              overview["stationName"] == STATION, overview["stationName"])
        check("the day has a published schedule", overview["hasSchedule"])
        check("the head guard is on it themselves - off-roster locks the "
              "screen",
              any(e["employeeId"] == HG_DAY[0] for e in roster))

        morning = [e for e in roster if e["shift"] == "Morning"]
        afternoon = [e for e in roster if e["shift"] == "Afternoon"]
        night = [e for e in roster if e["shift"] == "Night"]
        check("a DAY head guard is handed Morning and Afternoon",
              morning and afternoon,
              f"{len(morning)} morning, {len(afternoon)} afternoon")
        check("Night is on the roster but is the night HG's report to file",
              len(night) > 0, f"{len(night)} night guards")
        check("the guard who will be marked absent is on that roster",
              any(e["employeeId"] == DAY_ABSENTEE for e in morning))

        # --- 2. Marking one absent and submitting ---------------------
        print("\n2. They mark one guard absent and submit:")
        result, day_absent_name = file_report(
            HG_DAY, "Morning", roster, DAY_ABSENTEE)
        report = result["report"]
        day_report_id = report["id"]
        print(f"   Absent: {day_absent_name} ({DAY_ABSENTEE})")
        check("the submission is accepted", result["success"] is True)
        check("filed under one deterministic ID per shift",
              day_report_id.endswith(f"-{HG_DAY[0]}-MORNING"), day_report_id)
        check("it arrives UNREAD - this is what raises the admin's badge",
              report["isRead"] is False)
        check("the whole shift is in the report, not just the absent one",
              len(report["records"]) == len(morning),
              f"{len(report['records'])} records")
        check("only the guard marked absent is stored absent",
              [r["employeeId"] for r in report["records"]
               if not r["isPresent"]] == [DAY_ABSENTEE])

        print("\n   The night head guard files their own shift at 2100H:")
        on_post_at(21)
        night_result, night_absent_name = file_report(
            HG_NIGHT, "Night", roster, NIGHT_ABSENTEE)
        night_report_id = night_result["report"]["id"]
        print(f"   Absent: {night_absent_name} ({NIGHT_ABSENTEE})")
        check("the night report is accepted too",
              night_result["success"] is True)
        check("it is a SEPARATE report from the day head guard's",
              night_report_id != day_report_id, night_report_id)

        # --- 3. What the admin's Notifications screen reads ------------
        print("\n3. The admin's Notifications screen:")
        feed = api.get_attendance_reports()["reports"]
        mine = next((r for r in feed if r["id"] == day_report_id), None)
        check("the report reached the admin feed", mine is not None)
        check("newest first, so a fresh report sits at the top",
              feed[0]["id"] in (day_report_id, night_report_id), feed[0]["id"])
        check("it counts as unread", mine and mine["isRead"] is False)
        check("both head guards' reports are waiting there",
              sum(1 for r in feed
                  if r["id"] in (day_report_id, night_report_id)) == 2)

        absent_records = [r for r in mine["records"] if not r["isPresent"]]
        check("the absent count the red flag renders is 1",
              len(absent_records) == 1, f"{len(absent_records)} absent")
        rec = absent_records[0]
        check("WHO, WHAT SHIFT and WHAT HOURS are all readable from the "
              "report alone",
              rec["name"] == day_absent_name and rec["shift"] == "Morning"
              and bool(rec["time"]),
              f"{rec['name']} / {rec['shift']} / {rec['time']}")
        check("and which head guard filed it, from which station",
              mine["headGuardId"] == HG_DAY[0] and mine["station"] == STATION)

        # --- 4. Absent Today ------------------------------------------
        # The same reshaping absent_management_screen.dart does: today's
        # reports that have an absence, grouped station -> shift.
        print("\n4. Absent Today (station -> shift grouping):")
        by_station = {}
        for r in feed:
            if r["date"] != DATE:
                continue
            for a in (x for x in r["records"] if not x["isPresent"]):
                by_station.setdefault(r["station"], {}) \
                          .setdefault(a["shift"], []).append(a)
        check("the station appears", STATION in by_station,
              ", ".join(by_station) or "nothing listed")
        shifts = by_station.get(STATION, {})
        check("both shifts' absences land under the one station block",
              sorted(shifts) == ["Morning", "Night"], sorted(shifts))
        check("the morning absentee is the guard the head guard marked",
              [a["employeeId"] for a in shifts.get("Morning", [])]
              == [DAY_ABSENTEE])
        check("Regular vs Reliever is carried through, which is what the "
              "admin sorts by",
              shifts["Morning"][0]["isReliever"] is False)

        # --- 5. Marking it read ---------------------------------------
        print("\n5. The admin opens it:")
        api.mark_attendance_report_read(day_report_id)
        after = next(r for r in api.get_attendance_reports()["reports"]
                     if r["id"] == day_report_id)
        check("that notification stops being unread", after["isRead"] is True)
        still = next(r for r in api.get_attendance_reports()["reports"]
                     if r["id"] == night_report_id)
        check("the other report stays unread - reading one is not reading "
              "all", still["isRead"] is False)

        # --- 6. Replacement candidates --------------------------------
        print("\n6. The admin asks who can cover the night absence:")
        suggested = api.suggest_replacements(
            date=DATE, station=STATION, shift="Night",
            absentEmployeeId=NIGHT_ABSENTEE)
        candidates = suggested["candidates"]
        window = suggested["coverWindow"]
        ids = [c["employee"]["id"] for c in candidates]
        check("candidates come back", len(candidates) > 0,
              f"{len(candidates)} eligible")
        check("the absent guard is not offered as their own cover",
              NIGHT_ABSENTEE not in ids)
        rostered = {e["employeeId"] for e in roster}
        clashes = [i for i in ids if i in rostered]
        check("nobody already standing a post at this station today is "
              "offered", not clashes, ", ".join(clashes))
        elsewhere = set()
        for sched in api.repo.schedules.list():
            for day in sched.get("days", []):
                if day["date"] == DATE:
                    elsewhere |= {e["employeeId"] for e in day["entries"]}
        double_booked = [i for i in ids if i in elsewhere]
        check("nor anyone rostered at ANOTHER station today",
              not double_booked, ", ".join(double_booked[:5]))
        check("the cover window runs to the absentee's own time-out, "
              "0600H tomorrow",
              window.get("endsAt", "").startswith(
                  (TODAY + timedelta(days=1)).isoformat() + "T06:00"),
              window.get("endsAt"))
        check("the day absentee is not offered either - already absent "
              "today", DAY_ABSENTEE not in ids)

        # --- 7. Applying one ------------------------------------------
        print("\n7. The admin assigns a cover:")
        cover = candidates[0]["employee"]
        print(f"   Cover: {cover['name']} ({cover['id']}), "
              f"rule score {candidates[0]['score']}")
        applied = api.apply_replacement(ReplacementApplyRequest(
            date=DATE, station=STATION, shift="Night",
            absentEmployeeId=NIGHT_ABSENTEE,
            absentEmployeeName=night_absent_name,
            replacementEmployeeId=cover["id"], reportId=night_report_id,
        ))
        check("the replacement is applied", applied["success"] is True)

        stamped = next(r for r in api.get_attendance_reports()["reports"]
                       if r["id"] == night_report_id)
        stamped_rec = next(r for r in stamped["records"]
                           if r["employeeId"] == NIGHT_ABSENTEE)
        check("the report's own record is stamped, so the same absence is "
              "not covered twice",
              stamped_rec.get("replacedById") == cover["id"],
              json.dumps({k: v for k, v in stamped_rec.items()
                          if k in ("replacedById", "replacedByName",
                                   "isReplaced")}) or "nothing stamped")

        day_row = next(d for s in api.repo.schedules.list()
                       if (s.get("stationName") or "").strip() == STATION
                       for d in s.get("days", []) if d["date"] == DATE)
        cover_entry = next((e for e in day_row["entries"]
                            if e["employeeId"] == cover["id"]), None)
        check("the schedule now rosters the cover onto the empty post",
              cover_entry is not None,
              cover_entry["post"] if cover_entry else "not on the schedule")
        check("and records who they are standing in for",
              cover_entry and cover_entry.get("coveringFor") == NIGHT_ABSENTEE,
              cover_entry and str(cover_entry.get("coveringFor")))

        alerts = api.get_employee_notifications(cover["id"])["notifications"]
        check("the cover is told, on their own phone, that they are on",
              any(DATE in json.dumps(a) for a in alerts),
              f"{len(alerts)} notifications")

        audit = [r for r in api.get_replacements()["replacements"]
                 if r.get("date") == DATE]
        check("an audit row is written for the Absence & Substitution Log",
              len(audit) == 1, f"{len(audit)} rows")

        print()
        failed = CHECKS.count(False)
        print(f"{CHECKS.count(True)}/{len(CHECKS)} checks passed"
              + (f", {failed} FAILED" if failed else ""))
        return 1 if failed else 0
    finally:
        os.environ.pop("SCHED_FREEZE_NOW", None)
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
