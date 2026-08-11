-- =====================================================================
-- Sched — AI replacement reviews
--
-- Apply after 002_auth_accounts.sql. Re-runnable, and it touches no data.
--
-- THE SERVER WILL NOT START WITHOUT THIS TABLE once `ai_suggestions` is
-- in repositories/base.py COLLECTIONS: supabase_repo checks every
-- collection has a table at startup and refuses to boot naming the ones
-- that don't. Run this before deploying that change, not after.
-- =====================================================================


-- ---------------------------------------------------------------------
-- What a row is
--
-- One Gemini review of one absence: the shortlist it was shown, what it
-- recommended, and — later — who the admin actually assigned.
--
-- It is three things at once, and each of them alone would have earned a
-- table:
--
--   A CACHE.  The free tier allows 20 requests per day per model. An
--             admin reopens the Find Replacement screen repeatedly while
--             deciding, and Render's free instance sleeps and restarts
--             often enough that an in-memory cache would be empty most
--             of the time. Keyed on the absence rather than the request,
--             so the cost is one call per absence and not one per open.
--
--   AN AUDIT TRAIL.  A recommendation that changed a duty roster should
--             be answerable for months later: which model, which prompt,
--             which candidates it was choosing between.
--
--   AN EVALUATION.  assigned_employee_id is written back by
--             /replacements/apply. Comparing it against recommended_id
--             is the only honest measure of whether the AI is any good:
--             how often the admin agreed. Nothing else in the system can
--             answer that question.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ai_suggestions (
    -- "AIR-20260814-AGU645-MORNING". Deterministic from the absence, so
    -- re-opening the screen finds the existing row instead of stacking a
    -- second review of the same post. Mirrors how replacements builds
    -- "REP-20260715-AQU861-MORNING".
    id                    TEXT PRIMARY KEY,

    -- The post being covered. Duplicated out of the id because an id is
    -- for lookups and these are for reading, filtering and indexing.
    date                  TEXT NOT NULL,
    station               TEXT NOT NULL,
    shift                 TEXT NOT NULL,
    absent_employee_id    TEXT NOT NULL,

    -- Digest of the candidate ids and their ranking inputs, in order.
    --
    -- This is what makes the cache safe rather than merely fast. A review
    -- is only valid for the shortlist that produced it, and that
    -- shortlist moves: a guard gets scheduled elsewhere and drops out, a
    -- colleague volunteers and jumps to the top, somebody covers an
    -- absence overnight and their cover load changes. Serving yesterday's
    -- recommendation against today's candidates would be worse than
    -- serving nothing, because it would look current. A changed
    -- fingerprint means the row is stale and the review is recomputed.
    shortlist_fingerprint TEXT NOT NULL,

    -- Everyone the model was choosing between, in the order it saw them.
    -- The fingerprint proves staleness; this says who was actually on the
    -- list, which is the question an audit asks.
    candidate_ids         JSONB NOT NULL,

    -- Which model answered and under which prompt wording. Both move:
    -- the model falls back down a chain as per-model quota runs out, and
    -- PROMPT_VERSION is bumped whenever the instruction text changes. A
    -- stored answer with neither is an opinion with no provenance.
    model                 TEXT NOT NULL,
    prompt_version        TEXT NOT NULL,

    -- The validated review as served: recommendedId, confidence,
    -- rationale, risk, runnerUpId, runnerUpTradeoff. Whole, because the
    -- audit question is "what did it say", not "what did we show".
    review                JSONB NOT NULL,

    -- Lifted out of `review` so agreement can be measured in SQL without
    -- unpacking JSON. Always equals review->>'recommendedId'.
    recommended_id        TEXT NOT NULL,

    created_at            TEXT NOT NULL,

    -- Written back by /replacements/apply. NULL means the admin has not
    -- decided yet — NOT that they disagreed, which is why this is
    -- nullable and not defaulted to anything.
    assigned_employee_id  TEXT,
    assigned_at           TEXT
);

-- The cache lookup: every read is by id, and every read happens while an
-- admin waits on a screen.
CREATE INDEX IF NOT EXISTS ai_suggestions_date_idx
    ON ai_suggestions (date);

-- "How often did the admin take the recommendation" — the evaluation
-- query, over decided rows only.
CREATE INDEX IF NOT EXISTS ai_suggestions_assigned_idx
    ON ai_suggestions (assigned_employee_id)
    WHERE assigned_employee_id IS NOT NULL;

-- Same reasoning as the other 17.
ALTER TABLE ai_suggestions ENABLE ROW LEVEL SECURITY;
