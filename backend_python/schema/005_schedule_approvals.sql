-- Apply before deploying the approval workflow backend. Existing schedules
-- keep their publication state; no historical approval is fabricated.
BEGIN;
ALTER TABLE users ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE schedules ADD COLUMN IF NOT EXISTS approval_id TEXT;
ALTER TABLE schedules ADD COLUMN IF NOT EXISTS approval_status TEXT;
ALTER TABLE replacements ADD COLUMN IF NOT EXISTS applied_by TEXT;
ALTER TABLE replacements ADD COLUMN IF NOT EXISTS reason TEXT;

CREATE TABLE IF NOT EXISTS auth_sessions (
    id TEXT PRIMARY KEY, username TEXT NOT NULL, role TEXT NOT NULL,
    expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS auth_sessions_username_idx ON auth_sessions(username);
CREATE TABLE IF NOT EXISTS schedule_approvals (
    id TEXT PRIMARY KEY, start_date TEXT NOT NULL, end_date TEXT NOT NULL,
    revision INTEGER NOT NULL, status TEXT NOT NULL,
    version INTEGER NOT NULL, submitted_by TEXT NOT NULL,
    submitted_name TEXT NOT NULL, submitted_at TEXT NOT NULL,
    schedules JSONB NOT NULL, current_hashes JSONB NOT NULL,
    events JSONB NOT NULL, amendments JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS schedule_approvals_period_idx
    ON schedule_approvals(start_date, end_date);
CREATE TABLE IF NOT EXISTS workflow_notifications (
    id TEXT PRIMARY KEY, username TEXT NOT NULL, title TEXT NOT NULL,
    message TEXT NOT NULL, created_at TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE, approval_id TEXT
);
CREATE INDEX IF NOT EXISTS workflow_notifications_username_idx
    ON workflow_notifications(username);
ALTER TABLE auth_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_notifications ENABLE ROW LEVEL SECURITY;
COMMIT;
