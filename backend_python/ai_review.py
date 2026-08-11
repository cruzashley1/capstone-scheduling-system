"""
The AI replacement review, cached, audited and answerable.

Sits between the endpoint and ai_service: reads the stored review when
one is still valid, asks Gemini when it isn't, and records what was
asked, what came back, and — later — what the admin actually did about
it. Rows live in `ai_suggestions` (schema/003_ai_suggestions.sql).

WHY A STORED CACHE AND NOT A DICT

Two reasons, and the second is the one that decides it:

  * The free tier allows 20 requests per day per model. Keyed on the
    absence rather than on the request, the cost is one call per absence
    no matter how many times the admin reopens the screen while they
    decide — which is the difference between a daily allowance that is
    comfortable and one that is gone by lunchtime.

  * Render's free instance sleeps after inactivity and restarts on the
    next request. An in-memory cache would be empty most of the times it
    was consulted, which is exactly when quota is tightest.

WHY IT CAN GO STALE, AND HOW THAT IS CAUGHT

A review is only true of the shortlist that produced it, and shortlists
move: a candidate gets scheduled elsewhere and drops out, a colleague
volunteers and jumps to the top, somebody covers an absence overnight
and their cover load changes. Serving a recommendation against a
shortlist it never saw would be worse than serving nothing, because it
would look current.

So every row carries a fingerprint of the candidates and the numbers
they were ranked on. A changed fingerprint means the stored review
describes a world that no longer exists, and it is recomputed.

NOTHING HERE RAISES

The screen behind this already works without any of it. Every failure —
no AI configured, quota gone, a database that will not answer — returns
a review of None, and the admin gets the rule-based ranking they would
have got anyway.
"""

import hashlib
import json
from datetime import datetime, timezone

import ai_service
import replacements
import repositories


def suggestion_id(date_iso, absent_id, shift):
    """Deterministic per absence, so reopening the screen finds the
    existing row instead of stacking a second review of the same post.
    Mirrors how replacements builds its REP- ids."""
    slug = "".join(c for c in shift.upper() if c.isalnum()) or "SHIFT"
    return f"AIR-{date_iso.replace('-', '')}-{absent_id}-{slug}"


def fingerprint(context):
    """Digest of who was on the shortlist and what they were ranked on.

    Covers the ordered candidate ids plus the three inputs that can move
    underneath a stored review — workload, recent cover load and whether
    they volunteered. Deliberately NOT the whole context: the rationale
    does not stop being true because the post's station string was
    re-spaced, and a fingerprint that changes on cosmetic edits would
    spend quota re-deriving an identical answer.
    """
    material = [
        [c.get("id"), c.get("daysWorkedThisPeriod"),
         c.get("coversLast30Days"), c.get("volunteered")]
        for c in context.get("candidates", [])
    ]
    blob = json.dumps(material, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:32]


def _stored(db, doc_id):
    """The saved row, or None. A repository that will not answer is not
    allowed to take the screen down with it."""
    try:
        return repositories.from_db(db).ai_suggestions.get(doc_id)
    except Exception as e:
        print(f"ai_review: could not read {doc_id} ({type(e).__name__}: {e})")
        return None


def _save(db, doc_id, context, review, fp):
    try:
        repositories.from_db(db).ai_suggestions.upsert(doc_id, {
            "id": doc_id,
            "date": context["post"]["date"],
            "station": context["post"]["station"],
            "shift": context["post"]["shift"],
            "absentEmployeeId": context["absence"]["employeeId"],
            "shortlistFingerprint": fp,
            "candidateIds": [c["id"] for c in context["candidates"]],
            "model": review.get("model") or "",
            "promptVersion": review.get("promptVersion") or "",
            "review": review,
            "recommendedId": review["recommendedId"],
            "createdAt": datetime.now(timezone.utc).isoformat(),
            # Filled in by record_decision() if and when the admin acts.
            "assignedEmployeeId": None,
            "assignedAt": None,
        })
    except Exception as e:
        # A review that cannot be saved is still a perfectly good review.
        # It costs a repeat call next time and nothing else, so this must
        # not turn into a failed request.
        print(f"ai_review: could not save {doc_id} "
              f"({type(e).__name__}: {e}); serving it uncached")


def review_for(db, date_iso, station, shift, absent_id, candidates,
               window=None):
    """The AI review of one absence, from cache or freshly asked.

    Returns ``(review, source)`` where source is "cache", "fresh",
    "disabled" or "unavailable" — the endpoint passes it through so the
    app can tell "the AI has nothing to add" apart from "the AI was never
    asked", and so a demo can prove a call really happened.

    `candidates` is suggest()'s output. Never raises.
    """
    if not ai_service.is_enabled():
        return None, "disabled"

    context = replacements.build_ai_context(
        db, date_iso, station, shift, absent_id, candidates, window=window)
    if context is None:
        return None, "unavailable"

    doc_id = suggestion_id(date_iso, absent_id, shift)
    fp = fingerprint(context)

    row = _stored(db, doc_id)
    if row is not None and row.get("shortlistFingerprint") == fp:
        stored_review = row.get("review")
        if stored_review:
            return stored_review, "cache"

    review = ai_service.review_candidates(context)
    if review is None:
        return None, "unavailable"

    _save(db, doc_id, context, review, fp)
    return review, "fresh"


def record_decision(db, date_iso, station, shift, absent_id, assigned_id):
    """Stamps the review with who the admin actually assigned.

    This is the evaluation metric and the reason the table is worth
    having: comparing assigned_employee_id against recommended_id is the
    only honest answer to "is the AI any good", and no other record in
    the system can produce it.

    A no-op when there was never a review — an admin can assign a cover
    without the AI having been asked, and that is not a disagreement to
    be counted.
    """
    doc_id = suggestion_id(date_iso, absent_id, shift)
    try:
        if repositories.from_db(db).ai_suggestions.get(doc_id) is None:
            return
        repositories.from_db(db).ai_suggestions.update(doc_id, {
            "assignedEmployeeId": assigned_id,
            "assignedAt": datetime.now(timezone.utc).isoformat(),
        })
    except Exception as e:
        # Losing the metric must never cost the admin their assignment.
        print(f"ai_review: could not record the decision on {doc_id} "
              f"({type(e).__name__}: {e})")
