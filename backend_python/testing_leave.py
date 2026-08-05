"""
Smoke test for the leave rules and their effect on generation, run
entirely against a throw-away copy of mock_data so nothing real is
touched:

    python testing_leave.py

Covers the contract end to end: every rule that can refuse a leave
(duration cap, lead time, schedule conflict, 2-per-year quota, 6-month
cooldown, overlapping leaves), the admin's override path and what it
records, the duties an admin-recorded leave swallows, and — the part
that actually matters on the roster — that an approved leave keeps the
guard off duty for its whole range when the schedule is generated.
"""

import os
import shutil
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone

import leave
import scheduler
from mock_firestore import MockFirestoreClient

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKS = []


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f" — {detail}" if detail else ""))


def refuses(label, fn, *, contains=""):
    """Asserts the rule refuses, and that it says why in words the guard
    can act on."""
    try:
        fn()
    except leave.LeaveError as e:
        ok = contains.lower() in e.detail.lower()
        check(label, ok, e.detail if not ok else f'"{e.detail}"')
        return
    check(label, False, "no LeaveError raised")


def allows(label, fn):
    try:
        fn()
        check(label, True)
    except leave.LeaveError as e:
        check(label, False, e.detail)


def store(db, **fields):
    """Writes a leave record straight to the collection — the shortcut
    the API would otherwise take, so the rules can be tested against a
    history without going through FastAPI."""
    rec = {
        "id": fields.get("id", f"LV-{fields['startDate']}-{fields['employeeId']}"),
        "employeeId": fields["employeeId"],
        "employeeName": fields.get("employeeName", ""),
        "leaveType": fields.get("leaveType", leave.DEFAULT_LEAVE_TYPE),
        "startDate": fields["startDate"],
        "endDate": fields["endDate"],
        "days": fields.get("days", 15),
        "status": fields["status"],
        "source": fields.get("source", "employee"),
        "submittedAt": datetime.now(timezone.utc).isoformat(),
    }
    db.collection(leave.COLLECTION).document(rec["id"]).set(rec)
    return rec


def main():
    tmp = tempfile.mkdtemp(prefix="leave_smoke_")
    try:
        for name in ("employees.json", "stations.json"):
            shutil.copy(os.path.join(HERE, "mock_data", name), tmp)
        db = MockFirestoreClient(data_dir=tmp)

        employees = {d.id: d.to_dict()
                     for d in db.collection("employees").stream()}

        # A morning regular with a real home station in group 1, so the
        # group/schedule rules have something to bite on.
        guard = next(e for e in employees.values()
                     if e.get("type") == "regular"
                     and e.get("assignedShift") == "morning"
                     and (e.get("assignedStation") or "").strip() == "Monumento")
        other = next(e for e in employees.values()
                     if e.get("type") == "regular"
                     and e["id"] != guard["id"]
                     and (e.get("assignedStation") or "").strip() == "Tayuman")
        # Tayuman is in group 1 too — `other` has to be, for the pending-leave
        # generation check below. A guard from a DIFFERENT group is needed
        # separately, to prove one group's roster doesn't fence in another's.
        guard_group = leave.home_group(db, guard)
        far_guard = next(e for e in employees.values()
                         if (e.get("assignedStation") or "").strip()
                         and leave.home_group(db, e) not in (None, guard_group))

        # Fixed "today" so the test says the same thing every day it runs.
        today = date(2026, 8, 2)
        print(f"Guard: {guard['name']} ({guard['id']}) — Monumento/morning")
        print(f"Today (fixed): {today}\n")

        # --- Duration caps -------------------------------------------------
        print("Duration caps:")
        far = today + timedelta(days=30)
        allows("15-day Vacation / Personal is within cap",
               lambda: leave.validate_employee_request(
                   db, guard, "Vacation / Personal", far,
                   far + timedelta(days=14), today))
        refuses("16-day Vacation / Personal is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal", far,
                    far + timedelta(days=15), today),
                contains="at most 15 days")
        allows("105-day Maternity Leave is within its own cap",
               lambda: leave.validate_employee_request(
                   db, guard, "Maternity Leave", far,
                   far + timedelta(days=104), today))
        refuses("8-day Paternity Leave is refused (cap 7)",
                lambda: leave.validate_employee_request(
                    db, guard, "Paternity Leave", far,
                    far + timedelta(days=7), today),
                contains="at most 7 days")
        refuses("an unknown leave type is refused, not treated as Other",
                lambda: leave.validate_employee_request(
                    db, guard, "Sabbatical", far, far, today),
                contains="is not a leave type")

        # --- Minimum length ------------------------------------------------
        # A one-day "leave" is the wrong form: a special day-off request
        # already covers 1-3 individual days without spending one of the
        # two leaves a year.
        print("\nMinimum length:")
        refuses("a same-day start and end is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal", far, far, today),
                contains="at least 4 days")
        refuses(f"a {leave.MIN_LEAVE_DAYS - 1}-day leave is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal", far,
                    far + timedelta(days=leave.MIN_LEAVE_DAYS - 2), today),
                contains="special day-off request")
        allows(f"a {leave.MIN_LEAVE_DAYS}-day leave is accepted",
               lambda: leave.validate_employee_request(
                   db, guard, "Vacation / Personal", far,
                   far + timedelta(days=leave.MIN_LEAVE_DAYS - 1), today))
        refuses("the admin path enforces it too (not overridable)",
                lambda: leave.check_duration(
                    "Bereavement Leave", far, far),
                contains="at least 4 days")
        check("...so it never reaches the overridable blockers",
              not any(b["rule"] == "duration" for b in leave.admin_blockers(
                  db, guard, "Bereavement Leave", far, far, today)))
        check("over-cap leave still names the higher authority",
              "higher authority" in _detail(
                  lambda: leave.validate_employee_request(
                      db, guard, "Sick Leave", far,
                      far + timedelta(days=20), today)))

        # --- Lead time -----------------------------------------------------
        print("\nLead time:")
        refuses("a leave starting in 3 days is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal",
                    today + timedelta(days=3),
                    today + timedelta(days=10), today),
                contains="at least 7 days ahead")
        allows("a leave starting in exactly 7 days is accepted",
               lambda: leave.validate_employee_request(
                   db, guard, "Vacation / Personal",
                   today + timedelta(days=leave.MIN_LEAD_DAYS),
                   today + timedelta(days=leave.MIN_LEAD_DAYS + 5), today))
        refuses("an end date before the start date is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal", far,
                    far - timedelta(days=1), today),
                contains="cannot be before")

        # --- Schedule conflict ---------------------------------------------
        print("\nSchedule conflict (the user's Aug 1–15 example):")
        scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 8, 1), rotate=True)
        saved = 0
        for doc in scheduler.generate_group_schedules(
                db, group=1, start_date=date(2026, 8, 1), rotate=False):
            db.collection("schedules").document(doc["id"]).set(doc)
            saved += 1
        check("a group-1 schedule for Aug 1–15 exists", saved > 0,
              f"{saved} station rosters")

        refuses("leave over the existing Aug 1–15 roster is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal",
                    date(2026, 8, 11), date(2026, 8, 25), today),
                contains="schedule already covers")
        check("the refusal offers the earliest date that IS free",
              "August 16, 2026" in _detail(
                  lambda: leave.validate_employee_request(
                      db, guard, "Vacation / Personal",
                      date(2026, 8, 11), date(2026, 8, 25), today)))
        check("earliest_start clears the generated period",
              leave.earliest_start(db, guard, today) == date(2026, 8, 16),
              str(leave.earliest_start(db, guard, today)))
        allows("the same leave starting Aug 16 is accepted",
               lambda: leave.validate_employee_request(
                   db, guard, "Vacation / Personal",
                   date(2026, 8, 16), date(2026, 8, 30), today))
        check("a guard in another group is unaffected by group 1's roster",
              leave.earliest_start(db, far_guard, today)
              == today + timedelta(days=leave.MIN_LEAD_DAYS),
              f"{far_guard['assignedStation']} (group "
              f"{leave.home_group(db, far_guard)}): "
              f"{leave.earliest_start(db, far_guard, today)}")

        # --- Quota + cooldown ----------------------------------------------
        print("\nQuota and cooldown:")
        store(db, employeeId=guard["id"], startDate="2026-01-05",
              endDate="2026-01-19", status="approved", id="LV-JAN")
        cooldown = leave.cooldown_state(leave.employee_leaves(db, guard["id"]))
        check("cooldown runs 6 months from the leave's END date",
              cooldown["until"] == "2026-07-19",
              f"until {cooldown['until']}, next {cooldown['nextEligible']}")
        allows("filing in August, past the January leave's cooldown",
               lambda: leave.validate_employee_request(
                   db, guard, "Vacation / Personal",
                   date(2026, 8, 16), date(2026, 8, 30), today))

        # Second leave of the year: quota now full.
        store(db, employeeId=guard["id"], startDate="2026-08-16",
              endDate="2026-08-30", status="approved", id="LV-AUG")
        quota = leave.quota_state(leave.employee_leaves(db, guard["id"]), 2026)
        check("both 2026 leaves count against the quota",
              quota["used"] == 2 and quota["remaining"] == 0,
              f"used {quota['used']}/{quota['limit']}")
        refuses("a third leave in the same year is refused",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal",
                    date(2026, 10, 1), date(2026, 10, 10), today),
                contains="already used your 2 leaves")

        # Next year is a fresh quota, but the cooldown from the August
        # leave still has to run out first.
        jan = date(2027, 1, 5)
        refuses("January 2027 is a new quota but still inside the cooldown",
                lambda: leave.validate_employee_request(
                    db, guard, "Vacation / Personal",
                    date(2027, 1, 20), date(2027, 1, 30), jan),
                contains="can only be filed from")
        check("next eligible is the day after 6 months from Aug 30",
              leave.cooldown_state(leave.employee_leaves(db, guard["id"]))
              ["nextEligible"] == "2027-03-01",
              leave.cooldown_state(leave.employee_leaves(db, guard["id"]))
              ["nextEligible"])

        # --- One open request at a time ------------------------------------
        print("\nOpen requests:")
        store(db, employeeId=other["id"], startDate="2026-09-01",
              endDate="2026-09-10", status="pending", id="LV-PEND")
        refuses("a second request while one is pending is refused",
                lambda: leave.validate_employee_request(
                    db, other, "Vacation / Personal",
                    date(2026, 10, 1), date(2026, 10, 5), today),
                contains="awaiting a decision")
        store(db, employeeId=other["id"], startDate="2026-11-01",
              endDate="2026-11-05", status="denied", id="LV-DENIED")
        denied_quota = leave.quota_state(
            leave.employee_leaves(db, other["id"]), 2026)
        check("a denied leave holds no quota slot",
              denied_quota["used"] == 1, f"used {denied_quota['used']}")

        # --- Eligibility summary -------------------------------------------
        print("\nEligibility (what the guard app reads):")
        elig = leave.eligibility(db, guard, today)
        check("the guard is told they cannot file", elig["canFile"] is False)
        check("...and why, in one sentence",
              "leaves for 2026" in elig["reason"], elig["reason"])
        check("the picker is given the generated days to grey out",
              "2026-08-05" in elig["blockedDates"],
              f"{len(elig['blockedDates'])} blocked days")
        check("the catalogue ships with its caps",
              {t["name"]: t["maxDays"] for t in elig["leaveTypes"]}
              .get("Maternity Leave") == 105)

        # --- Admin override path -------------------------------------------
        print("\nAdmin override (Set On Leave):")
        blockers = leave.admin_blockers(
            db, guard, "Maternity Leave", date(2026, 12, 1),
            date(2027, 3, 15), today)
        rules = {b["rule"] for b in blockers}
        # The guard is both out of 2026 leaves AND inside the cooldown left
        # by the August one — the form has to name both, not just the first.
        check("the admin form is told exactly which rules break",
              rules == {"quota", "cooldown"}, str(sorted(rules)))
        check("...each with a sentence the admin can read out",
              all(b["message"] for b in blockers),
              " | ".join(b["message"] for b in blockers))
        check("the admin is NOT blocked by the 7-day lead time",
              not leave.admin_blockers(
                  db, other, "Sick Leave", today + timedelta(days=1),
                  today + timedelta(days=3), today))
        over_cap = leave.admin_blockers(
            db, other, "Paternity Leave", date(2026, 12, 1),
            date(2026, 12, 20), today)
        check("an over-cap admin leave is flagged for endorsement",
              any(b["rule"] == "duration" for b in over_cap),
              str([b["rule"] for b in over_cap]))

        # --- Duties an admin leave swallows --------------------------------
        print("\nDuties swallowed by an admin leave over a live roster:")
        impact = leave.coverage_impact(
            db, guard, date(2026, 8, 1), date(2026, 8, 15))
        check("the guard's published duties are returned for replacement",
              impact["affectedDuties"],
              f"{len(impact['affectedDuties'])} duties")
        check("every returned duty is inside the leave range",
              all("2026-08-01" <= d["date"] <= "2026-08-15"
                  for d in impact["affectedDuties"]))
        check("the impact names the shift's remaining headcount",
              impact["peerCount"] >= 0,
              f"{impact['peerCount']} peers on Monumento/morning")

        # --- Generation honours an approved leave --------------------------
        print("\nGeneration (Aug 16–30, the leave stored above):")
        approved, pending = scheduler.load_leaves(db, date(2026, 8, 16))
        check("load_leaves expands the range into this period's days",
              len(approved.get(guard["id"], [])) == 15,
              f"{len(approved.get(guard['id'], []))} days")
        check("...and clips it to the period",
              approved.get(guard["id"], [])[:1] == ["2026-08-16"]
              and approved.get(guard["id"], [])[-1:] == ["2026-08-30"])

        schedules = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 8, 16), rotate=False)

        own_duties, cover_duties = [], []
        for s in schedules:
            for day in s["days"]:
                for e in day["entries"]:
                    if e["employeeId"] != guard["id"]:
                        continue
                    (cover_duties if e.get("coveringFor") else own_duties
                     ).append((day["date"], s["stationName"], e["shift"]))

        check("the guard on leave works no day of the period",
              not own_duties and not cover_duties,
              f"own={len(own_duties)} cover={len(cover_duties)}: "
              f"{own_duties[:3]}")

        notes = schedules[0].get("rotationNotes", []) if schedules else []
        check("the roster carries a note naming the leave",
              any("on approved leave" in n and guard["name"] in n
                  for n in notes),
              next((n for n in notes if "approved leave" in n), "no note"))

        monumento = next((s for s in schedules
                          if s["stationName"] == "Monumento"), None)
        staffed = sum(1 for day in (monumento or {}).get("days", [])
                      for e in day["entries"] if e["shift"] == "Morning")
        check("Monumento's morning posts are still staffed by others",
              staffed > 0, f"{staffed} morning entries over the period")

        # --- A long leave is replaced by a REGULAR, not by relievers ------
        # The bug this covers: the guard stayed on the roster and their
        # post was covered day by day, so one row of the report read
        # "Miguel Aquino — Jasmine Dizon (8) · Nino Cruz (2) · Ramon
        # Santiago (2) · Liza Pascual (1)". A post is held by one guard
        # for the period, so a guard who cannot work it comes off the
        # roster and a regular takes it.
        print("\nA long leave takes the guard off the roster (rotate=True):")
        swapped = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 8, 16), rotate=True)
        on_roster = [1 for s in swapped for day in s["days"]
                     for e in day["entries"] if e["employeeId"] == guard["id"]]
        covering = {e["employeeName"] for s in swapped for day in s["days"]
                    for e in day["entries"]
                    if e.get("coveringFor") == guard["id"]}
        check("the guard on leave holds no post anywhere",
              not on_roster, f"{len(on_roster)} entries")
        check("...and NO reliever is spent covering them",
              not covering, ", ".join(sorted(covering)) or "none")

        swap_note = next((n for n in swapped[0].get("rotationNotes", [])
                          if guard["name"] in n and "off Monumento" in n), "")
        check("the roster names who took the post instead", bool(swap_note),
              swap_note or "no replacement note")
        check("...and the replacement is a regular, not a reliever",
              "post instead" in swap_note or "another regular" in swap_note,
              swap_note)

        # The replacement is a post-holder, not cover: the same name on
        # the same post every day, exactly like the guard they replaced.
        stand_in = swap_note.split("period. ")[-1].split(",")[0]
        stand_in_rows = [(day["date"], e["post"], e.get("isReliever"))
                         for s in swapped if s["stationName"] == "Monumento"
                         for day in s["days"] for e in day["entries"]
                         if e["employeeName"] == stand_in]
        check("the replacement holds one fixed post, never as a reliever",
              len(stand_in_rows) == scheduler.MAX_REGULAR_DAYS
              and len({r[1] for r in stand_in_rows}) == 1
              and not any(r[2] for r in stand_in_rows),
              f"{stand_in}: {len(stand_in_rows)} days on "
              f"{sorted({r[1] for r in stand_in_rows})}")

        mon_after = next(s for s in swapped if s["stationName"] == "Monumento")
        morning_after = {
            len([e for e in day["entries"] if e["shift"] == "Morning"])
            for day in mon_after["days"]}
        check("Monumento fields the same morning headcount every day",
              len(morning_after) == 1, f"{sorted(morning_after)}")

        # A leave the period only clips a couple of days off is NOT a
        # replacement case — it is a run of day-offs, and it replaces the
        # guard's ordinary two rather than stacking on top of them, so a
        # single bound reliever still covers the whole run.
        print("\nA leave clipped short by the period edge stays a day-off:")
        store(db, employeeId=other["id"], startDate="2026-08-29",
              endDate="2026-09-06", status="approved", id="LV-EDGE")
        edge = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 8, 16), rotate=True)
        edge_duties = [1 for s in edge for day in s["days"]
                       for e in day["entries"]
                       if e["employeeId"] == other["id"]
                       and not e.get("coveringFor")]
        edge_cover = {e["employeeName"] for s in edge for day in s["days"]
                      for e in day["entries"]
                      if e.get("coveringFor") == other["id"]}
        check("the guard keeps their post and works the rest of the period",
              len(edge_duties) == scheduler.MAX_REGULAR_DAYS,
              f"{len(edge_duties)} duties")
        check("...covered by ONE reliever, not a split across the roster",
              len(edge_cover) <= 1, ", ".join(sorted(edge_cover)) or "none")
        db.collection(leave.COLLECTION).document("LV-EDGE").delete()

        # A pending leave must NOT empty the post — only note it.
        print("\nGeneration with a PENDING leave (must not empty the post):")
        store(db, employeeId=other["id"], startDate="2026-08-16",
              endDate="2026-08-30", status="pending", id="LV-PEND2")
        s2 = scheduler.generate_group_schedules(
            db, group=1, start_date=date(2026, 8, 16), rotate=False)
        pending_duties = [1 for s in s2 for day in s["days"]
                          for e in day["entries"]
                          if e["employeeId"] == other["id"]
                          and not e.get("coveringFor")]
        check("a guard with a PENDING leave is still scheduled",
              len(pending_duties) > 0, f"{len(pending_duties)} duties")
        check("...and the roster warns the decision is still owed",
              any("pending leave request" in n
                  for n in (s2[0].get("rotationNotes", []) if s2 else [])))

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    passed = sum(1 for c in CHECKS if c)
    print(f"\n{passed}/{len(CHECKS)} checks passed")
    return 0 if passed == len(CHECKS) else 1


def _detail(fn):
    """The message a refusal came back with, for checks that care about
    the wording rather than the refusal itself."""
    try:
        fn()
    except leave.LeaveError as e:
        return e.detail
    return ""


if __name__ == "__main__":
    sys.exit(main())
