-- =====================================================================
-- Sched — credentials
--
-- Apply after 001_initial.sql. Re-runnable, and it touches no data.
--
-- 001 created the 16 tables the API serves. It did NOT create anywhere
-- for a password to live, because passwords were never in Firestore:
-- they are in Firebase Auth, and in development in mock_data/_auth.json
-- as {uid: {email, password}} with 574 bcrypt hashes.
--
-- That gap is invisible until DB_BACKEND=supabase, at which point
-- authentication is the one thing still reaching for a local JSON file.
-- It works on a laptop and fails on Render, where mock_data/ does not
-- exist — the whole corpus is git-ignored.
--
-- So credentials get their own table, mirroring _auth.json exactly.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Why a separate table rather than employees.password
--
-- employees.password already exists and already holds something: the
-- literal mask "••••••••". The API returns it that way — an admin resets
-- a password, never reads one — and the golden files record the mask.
--
-- Putting real bcrypt hashes in that column would make /employees one
-- serialiser slip away from publishing 573 credentials, and would need
-- the mask re-applied on the way out to keep the response identical.
-- A column that must be scrubbed before every response is a column in
-- the wrong table.
--
-- Here, nothing serialises auth_accounts. There is no repository
-- collection for it and no endpoint reads it; supabase_auth.py is the
-- only module that opens it, and it returns booleans, not rows. The
-- hashes cannot leak through a response shape because they are not in
-- one.
--
-- It also keeps admin01 in one place. The admin has a credential but is
-- not an employee — under the reuse plan the hash would go to
-- users.password and every auth path would need to try two tables.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auth_accounts (
    -- Matches employees.id, or "admin01" for the console login. Not a
    -- foreign key: the admin has no employees row, and an FK would also
    -- decide deletion order for a table whose whole job is to be
    -- checkable before anything else is loaded.
    uid           TEXT PRIMARY KEY,

    -- The masked address the Identity Toolkit sign-in was built around,
    -- "AGU460@schedulingsystem.local". Kept because get_user() returns
    -- it and because it is what a future real-Auth import would key on.
    email         TEXT NOT NULL,

    -- bcrypt, "$2b$12$...". Never a plain password: everything that
    -- writes here goes through passwords.hash_password() first, and the
    -- loader refuses to import a record that is not already hashed.
    password_hash TEXT NOT NULL,

    updated_at    TEXT NOT NULL
);

-- All 574 addresses are distinct today, and sign-in treats the address
-- as the identity, so a duplicate would make one of two accounts
-- unreachable rather than merely untidy.
CREATE UNIQUE INDEX IF NOT EXISTS auth_accounts_email_key
    ON auth_accounts (email);

-- Same reasoning as the other 16, and more pointed here: this is the one
-- table where a readable anon endpoint would hand out the hash set.
ALTER TABLE auth_accounts ENABLE ROW LEVEL SECURITY;
