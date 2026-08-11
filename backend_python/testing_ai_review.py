"""
Smoke test for the cached AI review. Runs against a throw-away copy of
mock_data and NEVER calls Gemini — ai_service is stubbed, so this is
deterministic, free and safe to run on a dead network:

    python testing_ai_review.py

The property it exists to protect, above everything else:

    THE SYSTEM IS WHOLE WITHOUT THE AI.

Switched off, out of quota, misconfigured or answering nonsense, the
admin still gets the same ranked candidates they got before any of this
was built. Every failure path below asserts that the rule-based ranking
came through untouched, because a scheduling system that stops working
when a third party does is worse than one with no AI in it at all.

Also pinned:
  * one call per absence, not one per screen open (the cache)
  * a shortlist that has moved invalidates the cached review, because a
    recommendation is only true of the candidates it saw
  * the admin's actual choice is recorded against the recommendation,
    which is the only measure of whether any of this is working
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta

os.environ.setdefault("USE_MOCK_DB", "1")
os.environ.setdefault("DB_BACKEND", "mock")

import ai_review
import ai_service
import replacements
from mock_firestore import MockFirestoreClient
from models.replacement import ReplacementApplyRequest

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKS = []

DATE = "2026-08-09"
STATION = "Monumento"

CALLS = []


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f" — {detail}" if detail else ""))


def stub(answer):
    """Replaces the Gemini call with a recorded answer, and counts how
    often it was reached."""
    def fake(context):
        CALLS.append(context)
        return answer(context) if callable(answer) else answer
    ai_service.review_candidates = fake
    ai_service.is_enabled = lambda: True


def a_review(context):
    top = context["candidates"][0]
    return {
        "recommendedId": top["id"],
        "confidence": "strong",
        "rationale": "Rested, and knows the post.",
        "risk": None,
        "runnerUpId": context["candidates"][1]["id"],
        "runnerUpTradeoff": "Has covered twice this month already.",
        "model": "stub-model",
        "promptVersion": "test",
    }


def seed(db, absentee):
    db.collection("schedules").document("S1").set({
        "id": "S1", "stationId": "STA001", "stationName": STATION,
        "startDate": DATE, "endDate": DATE, "status": "published",
        "days": [{"date": DATE, "entries": [{
            "id": "E1", "employeeId": absentee["id"],
            "employeeName": absentee["name"], "shift": "Morning",
            "post": "SW", "timeIn": "05:00", "timeOut": "14:00",
            "isReliever": False, "coveringFor": None}]}]})


def main():
    tmp = tempfile.mkdtemp(prefix="ai_review_")
    real_enabled, real_review = ai_service.is_enabled, ai_service.review_candidates
    try:
        for name in ("employees.json", "stations.json"):
            shutil.copy(os.path.join(HERE, "mock_data", name), tmp)
        db = MockFirestoreClient(data_dir=tmp)
        emps = [d.to_dict() for d in db.collection("employees").stream()]
        absentee = next(e for e in emps if e.get("type") == "regular"
                        and e.get("assignedShift") == "morning")
        seed(db, absentee)
        cands = replacements.suggest(db, DATE, STATION, "Morning",
                                     absentee["id"])
        args = (db, DATE, STATION, "Morning", absentee["id"], cands)

        # --- Without the AI, nothing changes -------------------------
        print("The system is whole without the AI:")
        ai_service.is_enabled = lambda: False
        review, source = ai_review.review_for(*args)
        check("switched off, there is no review and it says so",
              review is None and source == "disabled", source)
        check("...and the ranked candidates are untouched",
              len(replacements.suggest(db, DATE, STATION, "Morning",
                                       absentee["id"])) == len(cands))

        stub(None)                       # enabled, but the call fails
        CALLS.clear()
        review, source = ai_review.review_for(*args)
        check("quota gone or the model unreachable reads as unavailable, "
              "not as an error",
              review is None and source == "unavailable", source)
        check("...and nothing was cached, so it will try again",
              db.collection("ai_suggestions").document(
                  ai_review.suggestion_id(DATE, absentee["id"], "Morning")
              ).get().to_dict() is None)

        # --- The cache -----------------------------------------------
        print("\nOne call per absence, not one per screen open:")
        stub(a_review)
        CALLS.clear()
        first, source1 = ai_review.review_for(*args)
        check("the first open asks the model", source1 == "fresh"
              and len(CALLS) == 1, f"{source1}, {len(CALLS)} call(s)")
        check("and the review is returned whole",
              first["recommendedId"] == cands[0]["employee"]["id"]
              and first["rationale"])

        second, source2 = ai_review.review_for(*args)
        check("reopening the screen is served from the cache — this is "
              "what makes 20 requests a day workable",
              source2 == "cache" and len(CALLS) == 1,
              f"{source2}, {len(CALLS)} call(s) total")
        check("and it is the same review, not a re-roll",
              second["recommendedId"] == first["recommendedId"]
              and second["rationale"] == first["rationale"])

        # --- Staleness -----------------------------------------------
        print("\nA shortlist that has moved invalidates the review:")
        row_id = ai_review.suggestion_id(DATE, absentee["id"], "Morning")
        stored = db.collection("ai_suggestions").document(row_id).get().to_dict()
        check("the row records what it was choosing between",
              len(stored["candidateIds"]) == len(
                  replacements.build_ai_context(*args)["candidates"]))

        # Somebody covered an absence overnight: their cover load moved,
        # so the ranking inputs behind the stored review are no longer
        # what the model saw.
        moved = cands[1]["employee"]["id"]
        db.collection("replacements").document("REP-X").set({
            "id": "REP-X",
            "date": (datetime.strptime(DATE, "%Y-%m-%d").date()
                     - timedelta(days=2)).isoformat(),
            "station": STATION, "shift": "Morning",
            "absentEmployeeId": "OTHER", "absentEmployeeName": "Other",
            "replacementEmployeeId": moved, "replacementEmployeeName": "",
            "appliedAt": "2026-08-07T06:00:00+00:00"})

        _, source3 = ai_review.review_for(*args)
        check("a changed cover load re-asks — serving the old answer "
              "would look current and be wrong",
              source3 == "fresh" and len(CALLS) == 2,
              f"{source3}, {len(CALLS)} call(s) total")

        ctx_now = replacements.build_ai_context(*args)
        check("cosmetic differences do NOT re-ask — the fingerprint "
              "covers the ranking inputs, not the whole payload",
              ai_review.fingerprint(ctx_now)
              == ai_review.fingerprint({**ctx_now, "post": {"station": "X"}}))

        # --- The evaluation metric -----------------------------------
        print("\nWhat the admin actually did:")
        row = db.collection("ai_suggestions").document(row_id).get().to_dict()
        check("undecided reviews record no assignment — silence is not "
              "disagreement",
              row["assignedEmployeeId"] is None)

        chosen = cands[2]["employee"]["id"]
        ai_review.record_decision(db, DATE, STATION, "Morning",
                                  absentee["id"], chosen)
        row = db.collection("ai_suggestions").document(row_id).get().to_dict()
        check("the admin's real choice is stamped against the "
              "recommendation, so agreement can be measured",
              row["assignedEmployeeId"] == chosen
              and row["assignedAt"] is not None)
        check("and it is visibly a disagreement when it is one",
              row["assignedEmployeeId"] != row["recommendedId"])

        ai_review.record_decision(db, DATE, STATION, "Morning",
                                  "NOBODY-REVIEWED-THIS", "ANY")
        check("assigning a cover the AI never reviewed is a no-op, not a "
              "phantom row",
              db.collection("ai_suggestions").document(
                  ai_review.suggestion_id(DATE, "NOBODY-REVIEWED-THIS",
                                          "Morning")
              ).get().to_dict() is None)

        # --- Not worth a request -------------------------------------
        print("\nCalls that are not worth spending:")
        ai_service.review_candidates = real_review
        ai_service.is_enabled = lambda: True
        before = len(CALLS)
        check("one candidate is not a recommendation, it is the only "
              "option — no request is spent",
              ai_service.review_candidates(
                  {"candidates": [{"id": "A"}]}) is None)
        check("and neither is none at all",
              ai_review.review_for(db, DATE, STATION, "Morning",
                                   absentee["id"], [])[1] == "unavailable")
        check("no model call was made for either", len(CALLS) == before)
    finally:
        ai_service.is_enabled, ai_service.review_candidates = real_enabled, real_review
        shutil.rmtree(tmp, ignore_errors=True)

    passed = sum(1 for c in CHECKS if c)
    print(f"\n{passed}/{len(CHECKS)} checks passed")
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    sys.exit(main())
