"""
Smoke test for the payload the AI reviewer reasons over. Runs against a
throw-away copy of mock_data, so nothing real is touched, and never
calls Gemini:

    python testing_ai_context.py

build_ai_context() is the seam between the rules and the model. Its job
is to hand over the guards suggest() already cleared, plus the two
things suggest() cannot see — how often each candidate has recently been
pulled in to cover somebody, and why the absent guard is out — and to
hand over nothing else.

What is pinned here:

  * the shortlist is capped, but the payload still states the honest
    total, so a top-12 of 60 cannot read as "these are the only options"
  * coversLast30Days counts the guard who COVERED, not the one who was
    absent, over a real 30-day window
  * the absence reason is picked up when one was filed, and its absence
    is an ordinary None rather than a crash
  * no personal data rides along — the payload is job attributes and ids
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta

os.environ.setdefault("USE_MOCK_DB", "1")
os.environ.setdefault("DB_BACKEND", "mock")

import replacements
from mock_firestore import MockFirestoreClient

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKS = []

DATE = "2026-08-09"
STATION = "Monumento"

# Fields that must never reach a third-party API. Checked against every
# candidate dict rather than trusted to review, because this payload is
# the one place employee records leave the building.
FORBIDDEN = ("password", "passwordHash", "address", "phone", "contact",
             "email", "birthdate", "sss", "philhealth")


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f" — {detail}" if detail else ""))


def seed_schedule(db, entries, start=DATE, end=DATE):
    db.collection("schedules").document("SCHED-TEST").set({
        "id": "SCHED-TEST",
        "stationId": "STA001",
        "stationName": STATION,
        "startDate": start,
        "endDate": end,
        "status": "published",
        "days": [{"date": DATE, "entries": entries}],
    })


def entry(employee, shift, time_in="05:00", time_out="14:00"):
    return {
        "id": f"E-{employee['id']}",
        "employeeId": employee["id"],
        "employeeName": employee.get("name", ""),
        "shift": shift,
        "post": "SW Platform",
        "timeIn": time_in,
        "timeOut": time_out,
        "isReliever": employee.get("type") == "reliever",
        "coveringFor": None,
    }


def seed_cover(db, doc_id, covered_by, days_ago):
    """One past replacement record — somebody was pulled in to cover."""
    when = (datetime.strptime(DATE, "%Y-%m-%d").date()
            - timedelta(days=days_ago)).isoformat()
    db.collection("replacements").document(doc_id).set({
        "id": doc_id,
        "date": when,
        "station": STATION,
        "shift": "Morning",
        "absentEmployeeId": "SOMEBODY-ELSE",
        "absentEmployeeName": "Somebody Else",
        "replacementEmployeeId": covered_by,
        "replacementEmployeeName": "",
        "appliedAt": f"{when}T06:00:00+00:00",
    })


def main():
    tmp = tempfile.mkdtemp(prefix="ai_context_")
    try:
        for name in ("employees.json", "stations.json"):
            shutil.copy(os.path.join(HERE, "mock_data", name), tmp)
        db = MockFirestoreClient(data_dir=tmp)

        employees = [d.to_dict() for d in db.collection("employees").stream()]
        absentee = next(e for e in employees
                        if e.get("type") == "regular"
                        and e.get("assignedShift") == "morning")
        seed_schedule(db, [entry(absentee, "Morning")])

        candidates = replacements.suggest(
            db, DATE, STATION, "Morning", absentee["id"])
        print(f"Absent:     {absentee['name']} ({absentee['id']})")
        print(f"Eligible:   {len(candidates)} candidates\n")

        # --- The shortlist -------------------------------------------
        print("The shortlist:")
        context = replacements.build_ai_context(
            db, DATE, STATION, "Morning", absentee["id"], candidates)

        check("it is capped at AI_SHORTLIST_LIMIT",
              len(context["candidates"]) == replacements.AI_SHORTLIST_LIMIT,
              f"{len(context['candidates'])} sent")
        check("but the payload states the honest total, so a top-12 of "
              "many cannot read as the whole field",
              context["candidateCount"] == len(candidates),
              f"candidateCount={context['candidateCount']}")
        check("the cap preserves suggest()'s order",
              [c["id"] for c in context["candidates"]]
              == [c["employee"]["id"] for c in candidates[:12]])
        check("a custom limit is honoured",
              len(replacements.build_ai_context(
                  db, DATE, STATION, "Morning", absentee["id"],
                  candidates, limit=3)["candidates"]) == 3)
        check("no candidates means no context — there is no choice to "
              "make, so no call is worth spending",
              replacements.build_ai_context(
                  db, DATE, STATION, "Morning", absentee["id"], []) is None)

        # --- The post ------------------------------------------------
        print("\nThe post being covered:")
        check("it carries the staggered window off the schedule entry, in "
              "the military form every screen shows",
              context["post"]["timeIn"] == "0500H"
              and context["post"]["timeOut"] == "1400H",
              f"{context['post']['timeIn']}-{context['post']['timeOut']}")
        check("and names the date, station and shift",
              (context["post"]["date"], context["post"]["station"],
               context["post"]["shift"]) == (DATE, STATION, "Morning"))
        check("the absent guard is identified",
              context["absence"]["employeeId"] == absentee["id"]
              and context["absence"]["employeeName"] == absentee["name"])

        # --- Cover history -------------------------------------------
        print("\nRecent cover load — the thing the 0-100 score cannot see:")
        first = candidates[0]["employee"]["id"]
        second = candidates[1]["employee"]["id"]
        seed_cover(db, "REP-A", first, days_ago=3)
        seed_cover(db, "REP-B", first, days_ago=20)
        seed_cover(db, "REP-C", first, days_ago=45)   # outside the window
        seed_cover(db, "REP-D", second, days_ago=1)

        context = replacements.build_ai_context(
            db, DATE, STATION, "Morning", absentee["id"], candidates)
        by_id = {c["id"]: c for c in context["candidates"]}

        check("covers inside the 30-day window are counted",
              by_id[first]["coversLast30Days"] == 2,
              f"{by_id[first]['coversLast30Days']} (expected 2 of 3)")
        check("one 45 days old is not — a guard who carried the load two "
              "months ago is not still being credited for it",
              by_id[first]["coversLast30Days"] == 2)
        check("counted per guard, not pooled",
              by_id[second]["coversLast30Days"] == 1)
        check("a guard who has covered nothing reads 0, not missing",
              all(isinstance(c["coversLast30Days"], int)
                  for c in context["candidates"]))

        # The absentee of a past cover must never be credited with it.
        seed_cover(db, "REP-E", "SOMEBODY-ELSE", days_ago=2)
        counts = replacements._cover_counts(db, DATE)
        check("it counts who COVERED, not who was absent",
              counts.get("SOMEBODY-ELSE") == 1
              and all(k != absentee["id"] or v > 0
                      for k, v in counts.items()),
              "the absentee on a record is not credited with covering it")

        # --- The absence reason --------------------------------------
        print("\nWhy the guard is out:")
        check("None when no request was filed — an admin can mark "
              "somebody absent straight off the attendance report",
              context["absence"]["reason"] is None)

        db.collection("absence_requests").document("ABS-1").set({
            "id": "ABS-1", "employeeId": absentee["id"], "date": DATE,
            "reason": "Injury", "status": "pending",
        })
        db.collection("absence_requests").document("ABS-2").set({
            "id": "ABS-2", "employeeId": absentee["id"],
            "date": "2026-07-01", "reason": "Sick", "status": "approved",
        })
        context = replacements.build_ai_context(
            db, DATE, STATION, "Morning", absentee["id"], candidates)
        check("the reason is picked up from the request for THAT date",
              context["absence"]["reason"] == "Injury",
              context["absence"]["reason"])

        # --- What must not travel ------------------------------------
        print("\nWhat is not sent:")
        blob = json.dumps(context).lower()
        leaked = [f for f in FORBIDDEN if f.lower() in blob]
        check("no personal data rides along — the payload is job "
              "attributes and ids",
              not leaked, f"leaked: {leaked}" if leaked else "")

        expected = {"id", "name", "type", "assignedStation", "assignedShift",
                    "daysWorkedThisPeriod", "coversLast30Days", "volunteered",
                    "ruleScore", "reasons"}
        extra = set(context["candidates"][0]) - expected
        check("each candidate carries exactly the ranking fields",
              not extra, f"unexpected: {extra}" if extra else "")
        check("the payload is JSON-serialisable as sent",
              isinstance(json.dumps(context), str))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    passed = sum(1 for c in CHECKS if c)
    print(f"\n{passed}/{len(CHECKS)} checks passed")
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    sys.exit(main())
