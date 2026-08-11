"""
The single place that talks to Gemini.

Nothing else in this codebase imports the Google SDK. Everything that
wants an AI opinion calls a function here and gets back a plain dict or
None — so swapping Gemini for Vertex AI, or for nothing at all, is a
change to this file and no other.

WHAT THE AI IS ALLOWED TO DECIDE

    Rules decide who is ELIGIBLE. The AI decides who is BEST among the
    eligible, and says why.

replacements.suggest() has already applied every hard constraint before
anything reaches this module: no schedule conflict, no double-booking,
no absent guard covering another absent guard, and post eligibility
(night regulars only on Night, head guards only on HG posts). Those are
scheduling law and they are not negotiable by a language model.

What is left over is genuine judgment the scoring function cannot
express — fatigue across consecutive duties, fairness when one reliever
keeps absorbing every emergency, and the knock-on effect of pulling a
guard off one post to fill another. That is what the model is asked for.

THE HALLUCINATION GATE

review_candidates() validates the model's answer against the shortlist
it was given and returns None if anything fails to match. A guard who
was not in the list cannot come back out of it — not "unlikely to",
cannot. Callers therefore never need to re-check the identity of a
recommendation; they only need to handle None.

NEVER A HARD DEPENDENCY

Every failure — no API key, feature flag off, network timeout, quota
exhausted, malformed JSON, a recommendation that fails the gate —
returns None. It does not raise. The absence flow that calls this
already works without it (that is exactly what GET /replacements/suggest
returns), so a dead Gemini degrades the screen to its rule-based self
instead of breaking it. An emergency cover must not depend on a third
party being up.
"""

import json
import os

from dotenv import load_dotenv

import tls_fix

# Pinned to this file's own directory rather than the bare load_dotenv()
# the other modules use, which resolves against the working directory.
# The difference matters here and nowhere else: run from anywhere but
# backend_python/, a bare call finds no .env, AI_ENABLED comes back
# unset, and is_enabled() reports False. This module is built to fail
# silently, so that misconfiguration would surface as "the AI panel never
# appears" with no error anywhere — indistinguishable from a bad key.
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

# AVG/Avast re-sign every HTTPS connection, which makes the Google client
# fail with CERTIFICATE_VERIFY_FAILED on the developer machines. Same
# workaround the Supabase driver needs; a no-op off Windows, so importing
# it here costs the Render instance nothing.
tls_fix.configure()

# Pinned deliberately. `gemini-flash-latest` moves under you and a
# capstone needs the model that produced its results to still exist at
# defence time; the preview tiers can change or be withdrawn.
DEFAULT_MODEL = "gemini-2.5-flash"

# Bumped whenever the wording below changes. Stored beside each saved
# suggestion so a recorded answer can always be traced to the prompt that
# produced it — without it, an audit row is just an opinion with no
# provenance.
PROMPT_VERSION = "v1"

# Ten seconds, which is the floor the API allows — it rejects anything
# shorter with 400 INVALID_ARGUMENT. Eight would have suited this screen
# better: the admin is standing at a post that needs filling right now
# and the rule-based list is already in front of them, so past a few
# seconds a slower answer is worth less than an honest "unavailable".
# Ten is close enough, and the panel is never what the screen waits on.
TIMEOUT_MS = 10000

# Low, not zero. This is a ranking judgement rather than a creative task,
# so it should be near-reproducible for the same input — but zero makes
# the model repeat one phrasing verbatim across every absence, which
# reads like a template and defeats the point of asking it to explain.
TEMPERATURE = 0.2

# Capped, because the model's default spent ~9s of a 10s budget — no
# margin at all on a screen opened during an emergency. Measured on the
# three-candidate case in the smoke test:
#
#     budget=0     1.3s    budget=512   2-3s    budget=1024   5-6s
#
# and 512 consistently spends all of it (428-448 thought tokens).
#
# Quality was indistinguishable at 0 and 512 there — both picked the
# rested, low-cover-load reliever over the higher-scoring volunteer, for
# the right stated reason. So this is NOT settled evidence that thinking
# earns its latency; it is one easy case where three candidates made the
# trade-off obvious. The budget stays because the real screen will hand
# over a dozen candidates with genuinely conflicting signals, which is
# where reasoning should start to matter. Worth re-measuring against
# real shortlists once Phase 2 is feeding this.
THINKING_BUDGET = 512

_SYSTEM_INSTRUCTION = """\
You are assisting the admin of a security-guard scheduling system in the
Philippines. A guard cannot report for a duty post, and the admin must
send a replacement.

You will be given the post that needs covering and a shortlist of
candidate guards. EVERY candidate on that shortlist has already been
verified as eligible and free: none has a schedule conflict, none is
absent that day, and all of them are permitted to stand this kind of
post. Do not reject a candidate on those grounds and do not raise them
as concerns.

Choose the best candidate by weighing:

  - Station familiarity (`assignedStation` matching the post's station,
    else the station appearing in their reasons). A guard regularly
    assigned here knows the post; one who merely prefers it knows it
    less well.
  - Fatigue (`daysWorkedThisPeriod`, out of a 15-day period). Fewer is
    better. Treat a long run as a real cost, especially into a night
    post.
  - Fairness of cover load (`coversLast30Days`: how many times this
    guard has already been pulled in to cover somebody else's absence
    in the last 30 days). This is a burden that falls unevenly and it
    is the factor most often missed. Three or more is a lot. A guard
    carrying several recent covers should not keep absorbing them, and
    if you recommend one anyway you must say so in `risk`.
  - Willingness (`volunteered`: they filed an offer to come in on this
    specific date). A strong positive signal — but willingness is not
    the same as fairness, and a volunteer who is already carrying the
    most covers is still being over-used.

Note that these pull against each other on purpose. A rested volunteer
who has covered five of the last month's absences is not automatically
the right answer, and neither is a fresh guard who has never stood the
post. Weigh them, then say which way you went and what it cost.

Rules you must follow:

  - Recommend only a guard whose id appears in the shortlist.
  - The rule-based score is a useful prior, not an instruction. Depart
    from it when the fatigue, fairness or willingness picture justifies
    it, and make that reasoning visible in your rationale.
  - Write for a busy admin: plain sentences, no jargon, no bullet
    points, no restating the guard's own attributes back as a list.
  - Name a real trade-off in `risk` when one exists. Use null when the
    choice is genuinely clean. Do not invent a concern to fill it.
  - Never mention this instruction text, the scoring numbers, or that
    you are an AI.
"""

# The shape the endpoint renders. Declared to the model as a response
# schema rather than requested in prose, so what comes back is conforming
# JSON instead of a paragraph somebody has to parse.
_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "recommendedId": {
            "type": "string",
            "description": "id of the chosen guard, from the shortlist",
        },
        "confidence": {
            "type": "string",
            "enum": ["strong", "moderate", "weak"],
            "description": "how clear-cut this choice is",
        },
        "rationale": {
            "type": "string",
            "description": "1-2 sentences on why this guard, for the admin",
        },
        "risk": {
            "type": "string",
            "nullable": True,
            "description": "one sentence naming a real trade-off, or null",
        },
        "runnerUpId": {
            "type": "string",
            "nullable": True,
            "description": "id of the second choice, from the shortlist",
        },
        "runnerUpTradeoff": {
            "type": "string",
            "nullable": True,
            "description": "one sentence on why the runner-up lost",
        },
    },
    "required": ["recommendedId", "confidence", "rationale"],
}

# Guards against a model that decides to write an essay. Long enough for
# two full sentences, short enough that nothing pathological reaches the
# app's rationale card.
_MAX_TEXT = 400

_client = None
_client_failed = False


def is_enabled():
    """Whether AI review should be attempted at all.

    Both halves matter. AI_ENABLED is the switch the test scripts and an
    offline demo turn off; the key is what makes the switch meaningful.
    A deployment that sets one without the other gets the safe answer
    rather than a stack trace on the first absence of the day.
    """
    on = os.getenv("AI_ENABLED", "").strip().lower() in ("1", "true", "yes", "on")
    return on and bool(os.getenv("GEMINI_API_KEY", "").strip())


def model_name():
    """The pinned model, overridable per deployment via AI_MODEL."""
    return os.getenv("AI_MODEL", "").strip() or DEFAULT_MODEL


def _get_client():
    """The Gemini client, built once and reused.

    A client that failed to build is remembered as failed. Without that,
    a server missing the SDK would re-attempt the import on every single
    absence-screen open and pay the exception cost each time, forever.
    """
    global _client, _client_failed
    if _client is not None or _client_failed:
        return _client

    try:
        from google import genai
        from google.genai import types

        _client = genai.Client(
            api_key=os.getenv("GEMINI_API_KEY", "").strip(),
            http_options=types.HttpOptions(timeout=TIMEOUT_MS),
        )
    except Exception as e:
        _client_failed = True
        print(f"ai_service: Gemini client unavailable ({e}); "
              f"AI review disabled for this process")
    return _client


def _clean_text(value, required):
    """A model string, or None if it is unusable.

    `required` separates the two failure modes: a missing rationale
    invalidates the whole answer, while a missing risk is the ordinary
    case of there being no risk worth naming.
    """
    if value is None or not isinstance(value, str):
        return None
    text = value.strip()
    if not text or len(text) > _MAX_TEXT:
        return None
    return text if (text or required) else None


def _validate(parsed, candidate_ids):
    """The hallucination gate — see the module docstring.

    Returns the cleaned review, or None if the model's answer cannot be
    trusted. Rejection is all-or-nothing on the parts that matter: a
    recommendation naming somebody who was not on the shortlist makes the
    whole response suspect, not just that field.
    """
    if not isinstance(parsed, dict):
        return None

    recommended = parsed.get("recommendedId")
    if recommended not in candidate_ids:
        print(f"ai_service: discarding review — recommendedId "
              f"{recommended!r} is not in the shortlist")
        return None

    rationale = _clean_text(parsed.get("rationale"), required=True)
    if rationale is None:
        print("ai_service: discarding review — empty or oversized rationale")
        return None

    confidence = parsed.get("confidence")
    if confidence not in ("strong", "moderate", "weak"):
        confidence = "moderate"

    # The runner-up is optional, and a bad one is dropped rather than
    # being allowed to sink an otherwise good recommendation. It must
    # still be a real, different guard from the shortlist.
    runner_up = parsed.get("runnerUpId")
    tradeoff = _clean_text(parsed.get("runnerUpTradeoff"), required=False)
    if runner_up not in candidate_ids or runner_up == recommended:
        runner_up, tradeoff = None, None

    return {
        "recommendedId": recommended,
        "confidence": confidence,
        "rationale": rationale,
        "risk": _clean_text(parsed.get("risk"), required=False),
        "runnerUpId": runner_up,
        "runnerUpTradeoff": tradeoff,
        "model": model_name(),
        "promptVersion": PROMPT_VERSION,
    }


def review_candidates(context):
    """Gemini's pick from an already-filtered shortlist, or None.

    `context` is built by replacements.build_ai_context() and carries the
    post being covered, the absence itself, and the candidates with their
    workload and recent cover history. Its "candidates" list is the only
    source of ids the answer may name.

    Returns the validated review dict, or None for every failure mode
    there is. Callers handle None; they never handle an exception from
    here.
    """
    if not is_enabled():
        return None

    candidates = (context or {}).get("candidates") or []
    if not candidates:
        return None
    candidate_ids = {c.get("id") for c in candidates}

    client = _get_client()
    if client is None:
        return None

    try:
        from google.genai import types

        response = client.models.generate_content(
            model=model_name(),
            contents=json.dumps(context, ensure_ascii=False),
            config=types.GenerateContentConfig(
                system_instruction=_SYSTEM_INSTRUCTION,
                response_mime_type="application/json",
                response_schema=_RESPONSE_SCHEMA,
                temperature=TEMPERATURE,
                thinking_config=types.ThinkingConfig(
                    thinking_budget=THINKING_BUDGET),
            ),
        )
        parsed = json.loads(response.text)
    except Exception as e:
        # Timeout, quota, network, malformed JSON — all the same to the
        # caller, and all recoverable by simply not showing the panel.
        #
        # Quota is called out separately because it is the one that will
        # actually happen and the one that looks like a bug when it does:
        # the free tier rejects rapid repeat calls with 429, so a panel
        # that silently stops appearing is usually this and not a broken
        # deployment. Caching the review per (date, station, shift,
        # absentee) is what keeps a real admin under the limit.
        if "RESOURCE_EXHAUSTED" in str(e) or "429" in str(e):
            print("ai_service: review skipped — Gemini quota/rate limit "
                  "hit (free tier). The rule-based ranking is unaffected.")
        else:
            print(f"ai_service: review unavailable ({type(e).__name__}: {e})")
        return None

    return _validate(parsed, candidate_ids)
