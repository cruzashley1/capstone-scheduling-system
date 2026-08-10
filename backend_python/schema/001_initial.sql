-- =====================================================================
-- Sched — initial Supabase/Postgres schema
--
-- Stage 4 of the migration. Nothing here runs automatically; review it,
-- then apply it to the Supabase project by hand (SQL Editor, or psql
-- against SUPABASE_DB_URL). It is written to be re-runnable: every
-- object uses IF NOT EXISTS, and the file ends without touching data.
--
-- The rule this schema serves: API RESPONSE SHAPES MUST NOT CHANGE.
-- Flutter reads these endpoints through api_service.dart, and 58 golden
-- files hold the current bytes. Every choice below is subordinate to
-- that, which is why some of it looks less "correct" than a greenfield
-- design would. The deviations are called out where they occur.
--
-- Conventions
--   * snake_case columns. Postgres folds unquoted identifiers to
--     lowercase, so assignedStation would silently become
--     assignedstation and reach Flutter as null. The repository converts
--     at the boundary (to_camel / to_snake in supabase_repo.py).
--   * TEXT primary keys. Ids are already meaningful strings the app
--     round-trips — AGU460, STA027, ABR-20260728-AGU666-9TAL — and
--     changing them to surrogate integers would change responses.
--   * Reads are ORDER BY id. Measured against the golden files: id
--     order reproduces 54 of 58 responses exactly, and the 4 that move
--     (/employees, /special-assignments x2, /stations/pools) move by
--     ordering only, never content. That is why no insertion-order
--     sequence column exists here.
-- =====================================================================


-- ---------------------------------------------------------------------
-- DECISION 1: timestamps and dates stay TEXT
--
-- Every timestamp in the corpus is already an ISO-8601 string, e.g.
-- "2026-07-28T03:38:11.078203+00:00", and every date is "2026-07-28".
-- The API hands these straight to Flutter.
--
-- Storing them as timestamptz/date would make Postgres the authority on
-- rendering, and it does not render the way Python does: microseconds
-- are trimmed when zero and the offset prints as "+00" rather than
-- "+00:00". Reconstructing the exact byte string on the way out is
-- fiddly and would break the goldens on the records where it guesses
-- wrong.
--
-- The cost of TEXT is no date arithmetic in SQL. That costs nothing
-- today: all 34 filters in the backend are equality (see base.py), and
-- every date comparison happens in Python. ISO-8601 also sorts
-- correctly as text, so ORDER BY still behaves.
--
-- Revisit only behind a deliberate re-baseline, never as a side effect.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- DECISION 2: nested lists stay JSONB, except schedule days
--
-- posts, post_times, schedule_notes, records, preferred_stations and
-- friends are read and written whole, never filtered on, and their
-- ORDER and DUPLICATES are meaningful — a station's afternoon posts are
-- ["Roving", "Roving", "Roving"], three real posts, not a set. JSONB
-- preserves both exactly and round-trips to Python lists unchanged.
--
-- schedules.days is the one exception, decomposed into duty_assignments
-- below, because it is the only nested structure the app queries INTO
-- (who is on duty, where, when) rather than just rendering.
-- ---------------------------------------------------------------------


-- =====================================================================
-- Core reference data
-- =====================================================================

CREATE TABLE IF NOT EXISTS stations (
    id                  TEXT PRIMARY KEY,          -- "STA027"
    name                TEXT NOT NULL,             -- "Fernando Poe Jr."
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    required_employees  INTEGER NOT NULL DEFAULT 0,
    required_morning    INTEGER NOT NULL DEFAULT 0,
    required_afternoon  INTEGER NOT NULL DEFAULT 0,
    required_night      INTEGER NOT NULL DEFAULT 0,

    -- {"morning": ["Head Guard", "SW Platform", ...], "afternoon": [...],
    --  "night": [...]}  — one entry per required slot, order significant,
    --  duplicates significant.
    posts               JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- {"morning": [{"start": "05:00", "end": "17:00", "auto": true}, ...]}
    -- Present on only 4 of 25 stations today; absent means "derive the
    -- times from the shift" — so NULL here is meaningful, not missing.
    post_times          JSONB
);

-- Stations join by NAME from employees.assigned_station and by ID from
-- schedules.station_id. That asymmetry is load-bearing and predates this
-- migration; renaming a station must go through the rename transaction
-- that updates both, never a delete + re-create.
CREATE UNIQUE INDEX IF NOT EXISTS stations_name_key ON stations (name);


CREATE TABLE IF NOT EXISTS employees (
    id                    TEXT PRIMARY KEY,        -- "AGU460"
    name                  TEXT NOT NULL,
    username              TEXT NOT NULL,
    email                 TEXT NOT NULL,
    phone                 TEXT,
    type                  TEXT NOT NULL,           -- regular | reliever | headGuard
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,
    date_joined           TEXT NOT NULL,

    -- bcrypt hash. The API never returns this: /employees masks it as
    -- "••••••••" and admins reset rather than read it.
    password              TEXT NOT NULL,

    -- The permanent posting only. The CURRENT station comes from the
    -- published schedule, never from this column.
    assigned_station      TEXT,
    assigned_shift        TEXT,

    preferred_stations    JSONB NOT NULL DEFAULT '[]'::jsonb,

    must_change_password  BOOLEAN,
    must_select_stations  BOOLEAN
);

CREATE INDEX IF NOT EXISTS employees_assigned_station_idx
    ON employees (assigned_station);   -- station rename fans out on this
CREATE INDEX IF NOT EXISTS employees_type_idx ON employees (type);


CREATE TABLE IF NOT EXISTS users (
    -- Admin console logins. NOTE: this table's rows do NOT carry an "id"
    -- field in the API response today, and neither does counters. Every
    -- other table does. row_to_json() must therefore drop the primary key
    -- for these two, or /login gains a field it never had.
    id       TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    role     TEXT NOT NULL,            -- "admin"
    active   BOOLEAN NOT NULL DEFAULT TRUE,
    password TEXT
);


CREATE TABLE IF NOT EXISTS counters (
    -- next_sequence() drives this: one statement, atomic, no transaction.
    --   INSERT INTO counters (id, value) VALUES (%s, 1)
    --   ON CONFLICT (id) DO UPDATE SET value = counters.value + 1
    --   RETURNING value
    -- See the "id" note on users above — no id in the response.
    id    TEXT PRIMARY KEY,            -- "employee_counter", "station_counter"
    value INTEGER NOT NULL DEFAULT 0
);


-- =====================================================================
-- Rotation
-- =====================================================================

CREATE TABLE IF NOT EXISTS rotation_cycles (
    id          TEXT PRIMARY KEY,      -- "202607"
    month_start TEXT NOT NULL,         -- "2026-07-01"
    created_at  TEXT NOT NULL
);


CREATE TABLE IF NOT EXISTS station_rotation_assignments (
    id                TEXT PRIMARY KEY,   -- "202607_AGU797"
    rotation_cycle_id TEXT NOT NULL,
    employee_id       TEXT NOT NULL,
    station_id        TEXT NOT NULL,
    station_name      TEXT NOT NULL,
    "group"           INTEGER NOT NULL,   -- quoted: GROUP is reserved
    station_role      TEXT NOT NULL,      -- "regular_fixed", ...
    special           BOOLEAN NOT NULL DEFAULT FALSE,
    stayed            BOOLEAN NOT NULL DEFAULT FALSE,

    -- Absent on 507 of 1257 rows today, not false. See the absent-vs-null
    -- note at the bottom of this file.
    deployed          BOOLEAN,
    preferred         BOOLEAN
);

-- rotation.py filters on (rotation_cycle_id, group) and deletes on the
-- same pair.
CREATE INDEX IF NOT EXISTS sra_cycle_group_idx
    ON station_rotation_assignments (rotation_cycle_id, "group");
CREATE INDEX IF NOT EXISTS sra_employee_idx
    ON station_rotation_assignments (employee_id);


CREATE TABLE IF NOT EXISTS special_assignments (
    id                TEXT PRIMARY KEY,  -- "202607_RIV464"
    rotation_cycle_id TEXT NOT NULL,
    employee_id       TEXT NOT NULL,
    employee_name     TEXT NOT NULL,
    employee_type     TEXT NOT NULL,
    station_id        TEXT NOT NULL,
    station_name      TEXT NOT NULL,
    shift             TEXT NOT NULL,     -- "afternoon"
    home_station      TEXT,              -- null for relievers
    created_at        TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS special_assignments_cycle_idx
    ON special_assignments (rotation_cycle_id);
CREATE INDEX IF NOT EXISTS special_assignments_station_idx
    ON special_assignments (station_id);   -- station delete fans out here


-- =====================================================================
-- Schedules — and the one real decomposition
-- =====================================================================

CREATE TABLE IF NOT EXISTS schedules (
    id                  TEXT PRIMARY KEY,   -- "STA027_2026-08-04"
    station_id          TEXT NOT NULL,
    station_name        TEXT NOT NULL,
    "group"             INTEGER NOT NULL,
    start_date          TEXT NOT NULL,      -- "2026-08-04"
    end_date            TEXT NOT NULL,      -- "2026-08-18"
    status              TEXT NOT NULL,      -- published | unpublished
    rotated             BOOLEAN NOT NULL DEFAULT FALSE,
    rotation_cycle_id   TEXT,
    uncovered_posts     INTEGER NOT NULL DEFAULT 0,
    created_at          TEXT NOT NULL,

    -- Generator output, rendered not queried. schedule_notes[] carries
    -- {category, severity, subject, problem, fix, station, text} and the
    -- flat `text` is what testing_*.py asserts on, so the shape here must
    -- stay in lockstep with schedule_notes.py and schedule_note.dart.
    rotation_notes      JSONB NOT NULL DEFAULT '[]'::jsonb,
    schedule_notes      JSONB NOT NULL DEFAULT '[]'::jsonb,
    special_assignments JSONB NOT NULL DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS schedules_status_idx  ON schedules (status);
CREATE INDEX IF NOT EXISTS schedules_station_idx ON schedules (station_id);
CREATE INDEX IF NOT EXISTS schedules_group_idx   ON schedules ("group");


-- ---------------------------------------------------------------------
-- DECISION 3: schedules.days becomes duty_assignments
--
-- Today a schedule document embeds:
--     days: [ {date, entries: [ {id, employeeId, post, shift, ...} ]} ]
-- 15 days per schedule, ~230 entries each. The repository reassembles
-- exactly that JSON on read, so neither api.py nor Flutter learns the
-- storage changed.
--
-- Why the composite primary key: entry ids look like "STA027_0_1" —
-- stationId, day index, sequence. They do NOT encode the period. Two
-- schedules for the same station in different fortnights therefore
-- generate the SAME entry ids. It has not collided yet only because the
-- corpus holds a single period per station; the next generated cycle
-- would collide immediately. (schedule_id, id) makes that impossible.
--
-- Why day_index and position exist: entry order within a day is part of
-- the rendered contract, and the ids sort wrong as text — "STA027_0_10"
-- lands between "_0_1" and "_0_2". Reads MUST be
-- ORDER BY day_index, position, never ORDER BY id.
--
-- Why day_date is stored per row and NOT trusted for reconstruction: a
-- day with zero entries produces zero rows, so rebuilding `days` from
-- these rows alone would silently drop empty days and shorten the
-- fortnight. Reconstruction must generate all dates from
-- schedules.start_date..end_date and left-join the rows into them —
-- this is what _period_dates() is for. testing_station_rename.py
-- exercises a schedule that is empty on every day, so this is a tested
-- path, not a hypothetical one.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS duty_assignments (
    schedule_id    TEXT    NOT NULL
                   REFERENCES schedules (id) ON DELETE CASCADE,
    id             TEXT    NOT NULL,        -- "STA027_0_1", unique per schedule
    day_index      INTEGER NOT NULL,        -- 0..14
    day_date       TEXT    NOT NULL,        -- "2026-08-04"
    position       INTEGER NOT NULL,        -- order within the day

    employee_id    TEXT    NOT NULL,
    employee_name  TEXT    NOT NULL,
    shift          TEXT    NOT NULL,        -- Morning | Afternoon | Night
    post           TEXT    NOT NULL,        -- "SW Platform"
    time_in        TEXT    NOT NULL,        -- "05:00"
    time_out       TEXT    NOT NULL,        -- "14:00"
    is_reliever    BOOLEAN NOT NULL DEFAULT FALSE,
    is_special     BOOLEAN NOT NULL DEFAULT FALSE,
    covering_for   TEXT,                    -- employee id, or NULL
    borrowed_from  TEXT,                    -- station name, or NULL

    PRIMARY KEY (schedule_id, id),
    UNIQUE (schedule_id, day_index, position)
);

-- ON DELETE CASCADE is deliberate: deleting a schedule must take its
-- duties with it. The bulk schedule delete already accepted being
-- non-atomic (delete_many chunks by hand), and the cascade keeps it from
-- leaving orphaned duties behind.

CREATE INDEX IF NOT EXISTS duty_schedule_order_idx
    ON duty_assignments (schedule_id, day_index, position);
CREATE INDEX IF NOT EXISTS duty_employee_idx
    ON duty_assignments (employee_id);
CREATE INDEX IF NOT EXISTS duty_employee_date_idx
    ON duty_assignments (employee_id, day_date);


-- =====================================================================
-- Requests, reports and notifications
-- =====================================================================

CREATE TABLE IF NOT EXISTS attendance_reports (
    id              TEXT PRIMARY KEY,   -- "RPT-20260716-AQU862-MORNING"
    date            TEXT NOT NULL,
    station         TEXT NOT NULL,
    shift_title     TEXT NOT NULL,      -- "Morning Shift", "HG Night Shift"
    head_guard_id   TEXT NOT NULL,
    head_guard_name TEXT NOT NULL,
    submitted_at    TEXT NOT NULL,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,

    -- [{employeeId, name, shift, time, isPresent, isReliever,
    --   replacedById?, replacedByName?, replacedAt?}]
    -- Rewritten whole when a replacement is applied.
    records         JSONB NOT NULL DEFAULT '[]'::jsonb
);

-- replacements.py filters on date, and on (date, station).
CREATE INDEX IF NOT EXISTS attendance_date_idx    ON attendance_reports (date);
CREATE INDEX IF NOT EXISTS attendance_date_station_idx
    ON attendance_reports (date, station);
CREATE INDEX IF NOT EXISTS attendance_is_read_idx ON attendance_reports (is_read);


CREATE TABLE IF NOT EXISTS absence_requests (
    id             TEXT PRIMARY KEY,    -- "ABR-20260728-AGU666-9TAL"
    employee_id    TEXT NOT NULL,
    employee_name  TEXT NOT NULL,
    employee_type  TEXT NOT NULL,
    station        TEXT NOT NULL,
    date           TEXT NOT NULL,
    shift_title    TEXT NOT NULL,
    title          TEXT NOT NULL,
    reason         TEXT NOT NULL,
    body           TEXT NOT NULL,
    status         TEXT NOT NULL,       -- pending | approved | declined
    submitted_at   TEXT NOT NULL,
    decided_at     TEXT,
    decided_by     TEXT,
    admin_note     TEXT,
    is_read        BOOLEAN NOT NULL DEFAULT FALSE,
    covered_by_id   TEXT,
    covered_by_name TEXT
);

CREATE INDEX IF NOT EXISTS absence_employee_idx ON absence_requests (employee_id);
CREATE INDEX IF NOT EXISTS absence_date_idx     ON absence_requests (date);


CREATE TABLE IF NOT EXISTS special_requests (
    id            TEXT PRIMARY KEY,     -- "SPR-20260810-AGU666-2F7L"
    employee_id   TEXT NOT NULL,
    employee_name TEXT NOT NULL,
    employee_type TEXT NOT NULL,
    station       TEXT NOT NULL,
    dates         JSONB NOT NULL DEFAULT '[]'::jsonb,  -- ["2026-08-10", ...]
    title         TEXT NOT NULL,
    reason        TEXT NOT NULL,
    body          TEXT NOT NULL,
    status        TEXT NOT NULL,
    submitted_at  TEXT NOT NULL,
    decided_at    TEXT,
    decided_by    TEXT,
    admin_note    TEXT,
    is_read       BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS special_requests_employee_idx
    ON special_requests (employee_id);


CREATE TABLE IF NOT EXISTS leave_requests (
    id             TEXT PRIMARY KEY,    -- "LVA-20260901-AGU552-N1P9"
    employee_id    TEXT NOT NULL,
    employee_name  TEXT NOT NULL,
    employee_type  TEXT NOT NULL,
    station        TEXT NOT NULL,
    leave_type     TEXT NOT NULL,       -- "Sick Leave", ...
    start_date     TEXT NOT NULL,
    end_date       TEXT NOT NULL,
    days           INTEGER NOT NULL,
    title          TEXT NOT NULL,
    body           TEXT NOT NULL,
    status         TEXT NOT NULL,
    source         TEXT NOT NULL,       -- "admin" | "employee"
    submitted_at   TEXT NOT NULL,
    decided_at     TEXT,
    decided_by     TEXT,
    admin_note     TEXT,
    supervisor_name TEXT,
    is_read        BOOLEAN NOT NULL DEFAULT FALSE,

    cancelled_at   TEXT,
    cancelled_by   TEXT,
    cancel_reason  TEXT,

    affected_duties  JSONB NOT NULL DEFAULT '[]'::jsonb,
    overridden_rules JSONB NOT NULL DEFAULT '[]'::jsonb,
    override_notes   JSONB NOT NULL DEFAULT '[]'::jsonb
);

-- The 6-month cooldown counts from leave END and gates the FILING date,
-- so lookups go by employee and then sort by start_date in Python.
CREATE INDEX IF NOT EXISTS leave_employee_idx ON leave_requests (employee_id);


CREATE TABLE IF NOT EXISTS cover_offers (
    id                 TEXT PRIMARY KEY,  -- "COV-20260728-AGU460"
    employee_id        TEXT NOT NULL,
    employee_name      TEXT NOT NULL,
    employee_type      TEXT NOT NULL,
    date               TEXT NOT NULL,
    status             TEXT NOT NULL,     -- active | fulfilled | withdrawn
    preferred_shifts   JSONB NOT NULL DEFAULT '[]'::jsonb,
    preferred_stations JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    fulfilled_at       TEXT,
    fulfilled_shift    TEXT,
    fulfilled_station  TEXT
);

CREATE INDEX IF NOT EXISTS cover_offers_employee_idx ON cover_offers (employee_id);
CREATE INDEX IF NOT EXISTS cover_offers_date_idx     ON cover_offers (date);


CREATE TABLE IF NOT EXISTS replacements (
    id                      TEXT PRIMARY KEY,  -- "REP-20260715-AQU861-MORNING"
    schedule_id             TEXT NOT NULL,
    date                    TEXT NOT NULL,
    station                 TEXT NOT NULL,
    shift                   TEXT NOT NULL,
    absent_employee_id      TEXT NOT NULL,
    absent_employee_name    TEXT NOT NULL,
    replacement_employee_id TEXT NOT NULL,
    replacement_employee_name TEXT NOT NULL,
    applied_at              TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS replacements_date_idx     ON replacements (date);
CREATE INDEX IF NOT EXISTS replacements_schedule_idx ON replacements (schedule_id);


CREATE TABLE IF NOT EXISTS employee_notifications (
    id          TEXT PRIMARY KEY,      -- "NTF-20260715-MEN859-MORNING"
    employee_id TEXT NOT NULL,
    date        TEXT NOT NULL,
    type        TEXT NOT NULL,         -- "urgent", ...
    title       TEXT NOT NULL,
    message     TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    is_read     BOOLEAN NOT NULL DEFAULT FALSE
);

-- Mark-all-read updates on (employee_id, is_read) and reports the count.
CREATE INDEX IF NOT EXISTS notifications_employee_idx
    ON employee_notifications (employee_id);
CREATE INDEX IF NOT EXISTS notifications_employee_unread_idx
    ON employee_notifications (employee_id, is_read);


-- =====================================================================
-- Deliberately NOT here
-- =====================================================================
--
-- FOREIGN KEYS beyond duty_assignments -> schedules. The document store
-- never enforced referential integrity, and the data reflects that:
-- employees.assigned_station holds a station NAME, schedules.station_id
-- holds an ID, and station_rotation_assignments carries both. Adding FKs
-- now would reject rows the current backend accepts and turn the data
-- migration into a debugging session. Add them later, once the data is
-- known clean, as their own reviewed change.
--
-- NOT NULL on the absent-vs-null columns. See below.


-- =====================================================================
-- Row level security
-- =====================================================================
--
-- Enabled on every table, with NO policies, which denies everything by
-- default. That is the intent, not an oversight.
--
-- It costs this backend nothing. Measured, not assumed: the session
-- pooler connects as `postgres`, and that role carries rolbypassrls, so
-- RLS never applies to a query from api.py. It is also the table owner,
-- which bypasses RLS a second way absent FORCE ROW LEVEL SECURITY.
--
-- What it buys: Supabase publishes a PostgREST endpoint for this project
-- whether or not anything uses it, and the anon key is a publishable
-- value. Without RLS that endpoint serves all 572 employee rows to
-- anyone holding it. With RLS and no policies it serves nothing.
--
-- So the earlier reasoning here — "the backend bypasses it, therefore it
-- is dead configuration" — was only half true. Bypassed by US is not the
-- same as bypassed by EVERYONE.
--
-- If the Flutter app is ever pointed straight at Supabase, policies have
-- to be written before anything will read; empty results, not errors,
-- are the symptom to expect.
-- =====================================================================

ALTER TABLE stations                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                        ENABLE ROW LEVEL SECURITY;
ALTER TABLE counters                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE rotation_cycles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE station_rotation_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE special_assignments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE duty_assignments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_reports           ENABLE ROW LEVEL SECURITY;
ALTER TABLE absence_requests             ENABLE ROW LEVEL SECURITY;
ALTER TABLE special_requests             ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests               ENABLE ROW LEVEL SECURITY;
ALTER TABLE cover_offers                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE replacements                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_notifications       ENABLE ROW LEVEL SECURITY;


-- =====================================================================
-- Known consequence: absent fields become explicit nulls
-- =====================================================================
--
-- The document store lets a record simply LACK a field. A column cannot:
-- it is either NULL or a value. So records that omit a field today will
-- come back carrying it as null, and these responses will differ:
--
--   employees.must_change_password   absent on 547 of 572
--   employees.must_select_stations   absent on 554 of 572
--   employees.assigned_shift         absent on   3 of 572
--   employees.assigned_station       absent on   3 of 572
--   station_rotation_assignments.deployed/preferred  absent on 507 of 1257
--   absence_requests.covered_by_id/name              absent on   4 of 9
--   cover_offers.fulfilled_shift/station             absent on   3 of 4
--   leave_requests.cancelled_at/by, cancel_reason    absent on   6 of 7
--   stations.post_times                              absent on  21 of 25
--
-- This is safe for the app and must not be "fixed" by stripping nulls in
-- the serialiser: Dart's jsonDecode builds a Map, and map['x'] returns
-- null whether the key is absent or explicitly null, so Flutter cannot
-- tell the difference. Stripping nulls would instead break the 130
-- employees whose assigned_shift is an EXPLICIT null today.
--
-- It IS a golden-file change, so expect a reviewed re-baseline showing
-- only added `"field": null` lines — plus the 4 ordering-only diffs
-- already measured. Any other movement is a real bug.
--
-- Filtering is unaffected: `WHERE col = %s` excludes NULL rows already,
-- which is exactly the Firestore behaviour find() must reproduce.
-- Note also that find() with NO filters must behave like list() —
-- api.py:1055 calls find(**{}) when no cycle is given.
-- =====================================================================
