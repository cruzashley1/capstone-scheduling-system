-- =====================================================================
-- Sched — the preparation window
--
-- Apply after 003_ai_suggestions.sql. Re-runnable, and it touches no
-- data: every column is added nullable or with a default, so existing
-- duty rows and replacement records are left exactly as they are.
--
-- RUN THIS BEFORE DEPLOYING the prep_window change. Without it,
-- POST /replacements/apply fails on the write: supabase_repo's
-- _write_days refuses to insert a schedule entry carrying a field
-- duty_assignments has no column for, rather than dropping it silently.
-- =====================================================================


-- ---------------------------------------------------------------------
-- What this is for
--
-- A cover assigned at short notice does not inherit the absent guard's
-- hours. Nobody walks out of their house straight onto a post — there is
-- a uniform to put on, food to bring, and a commute to make — so the
-- duty slides: time-in an hour from the assignment, time-out two hours
-- past the post's own (the hour lost at the front, plus an hour of
-- extension).
--
--     0500H - 1700H, assigned at 0900H  ->  1000H - 1900H
--
-- time_in / time_out already hold the hours the guard actually stands.
-- What was missing is the hours the POST runs, which the schedule and
-- the Absence & Substitution Log both have to be able to show alongside
-- them — otherwise a report says a 0500H post ran until 1900H and
-- nobody can tell why.
--
-- See backend_python/prep_window.py.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- duty_assignments
--
-- day_offset is the one field here that is not documentation. A duty
-- window is a bare "HH:MM" pair, with an end at or before the start
-- meaning "times out tomorrow" — enough for every generated post, whose
-- time-in is always on its own duty date. A cover assigned at 0230H
-- against an HG Night post (1700H - 0500H) times in at 0330H the NEXT
-- day, and "03:30" alone would place it a full 24 hours early.
-- ---------------------------------------------------------------------

ALTER TABLE duty_assignments
    ADD COLUMN IF NOT EXISTS original_time_in  TEXT,     -- "05:00"
    ADD COLUMN IF NOT EXISTS original_time_out TEXT,     -- "17:00"
    ADD COLUMN IF NOT EXISTS day_offset        INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS prep_minutes      INTEGER;  -- 60


-- ---------------------------------------------------------------------
-- replacements
--
-- The audit record grows the same pair of windows. The log reads its
-- TIME column from here rather than from the shift name, which since
-- the preparation window can no longer be trusted to describe what the
-- cover actually stood.
--
-- report_at is the instant the guard was told to be AT the station —
-- the far end of their preparation hour, and the one timestamp that
-- says when the notice actually ran out.
-- ---------------------------------------------------------------------

ALTER TABLE replacements
    ADD COLUMN IF NOT EXISTS time_in           TEXT,     -- "10:00"
    ADD COLUMN IF NOT EXISTS time_out          TEXT,     -- "19:00"
    ADD COLUMN IF NOT EXISTS original_time_in  TEXT,     -- "05:00"
    ADD COLUMN IF NOT EXISTS original_time_out TEXT,     -- "17:00"
    ADD COLUMN IF NOT EXISTS prep_adjusted     BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS prep_minutes      INTEGER,
    ADD COLUMN IF NOT EXISTS report_at         TEXT;     -- ISO instant


-- ---------------------------------------------------------------------
-- Why nothing is backfilled
--
-- Every row that already exists predates the rule, and there is no
-- honest value to give it. A replacement applied last month was NOT
-- given a preparation hour, so writing one in would make the log claim
-- something that did not happen. They stay NULL, and supabase_repo
-- leaves the fields off those documents entirely — see _OMIT_WHEN_UNSET
-- — so the responses stay byte-identical to the golden files.
-- ---------------------------------------------------------------------
