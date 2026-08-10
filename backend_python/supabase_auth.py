"""
Credentials in Supabase — the third implementation of the auth surface.

`firebase_admin.auth` is the original and `mock_auth.py` is the offline
stand-in; this is the one DB_BACKEND=supabase selects. All three expose
the same functions with the same signatures, so api.py's `auth.` calls
are unchanged and nothing above firebase_init.get_auth() knows which is
in use.

Why this file has to exist at all: authentication is the one part of the
backend that never went through the repository. api.py talks to
`firebase_init.verify_password` and to the module returned by
`get_auth()`, and both of those switched on USE_MOCK_DB — so a Supabase
deployment would still have been reading mock_data/_auth.json off local
disk, which exists on a development machine and nowhere else.

The store is `auth_accounts` (schema/002_auth_accounts.sql), which
mirrors _auth.json record for record. Nothing here returns a hash: the
functions answer with booleans and user records, so a credential cannot
escape through a caller that forgets to strip it.
"""

from datetime import datetime, timezone

from psycopg.errors import UniqueViolation

import passwords
from repositories.supabase_repo import get_pool

_TABLE = "auth_accounts"


class SupabaseAuthError(Exception):
    """Raised for the same situations the real Admin SDK rejects."""


# Named to match firebase_admin.auth and mock_auth so a caller can catch
# any backend's error with the same `except auth.UidAlreadyExistsError`.
class UidAlreadyExistsError(SupabaseAuthError):
    pass


class UserNotFoundError(SupabaseAuthError):
    pass


class UserRecord:
    def __init__(self, uid, email):
        self.uid = uid
        self.email = email


def _now():
    return datetime.now(timezone.utc).isoformat()


def _fetch(uid):
    with get_pool().connection() as conn:
        return conn.execute(
            f"SELECT uid, email, password_hash FROM {_TABLE} WHERE uid = %s",
            [uid]).fetchone()


def create_user(email=None, password=None, uid=None, **_kwargs):
    """Adds an account, refusing to overwrite an existing uid.

    The refusal is the point — api.py creates the Auth account before the
    employee record, so a silent overwrite here would hand an existing
    guard's login to a new hire.
    """
    try:
        with get_pool().connection() as conn:
            conn.execute(
                f"INSERT INTO {_TABLE} (uid, email, password_hash, updated_at) "
                f"VALUES (%s, %s, %s, %s)",
                [uid, email, passwords.hash_password(password), _now()])
    except UniqueViolation:
        raise UidAlreadyExistsError(
            f"The user with the provided uid already exists: {uid}") from None
    return UserRecord(uid, email)


def update_user(uid, password=None, email=None, **_kwargs):
    """Changes a password, an email, or both."""
    sets, params = ["updated_at = %s"], [_now()]
    if password is not None:
        sets.append("password_hash = %s")
        params.append(passwords.hash_password(password))
    if email is not None:
        sets.append("email = %s")
        params.append(email)

    with get_pool().connection() as conn, conn.cursor() as cur:
        cur.execute(
            f"UPDATE {_TABLE} SET {', '.join(sets)} WHERE uid = %s "
            f"RETURNING email",
            params + [uid])
        row = cur.fetchone()
        if row is None:
            raise UserNotFoundError(f"No user record found for uid: {uid}")
    return UserRecord(uid, row["email"])


def delete_user(uid, **_kwargs):
    with get_pool().connection() as conn, conn.cursor() as cur:
        cur.execute(f"DELETE FROM {_TABLE} WHERE uid = %s", [uid])
        if cur.rowcount == 0:
            raise UserNotFoundError(f"No user record found for uid: {uid}")


def get_user(uid, **_kwargs):
    row = _fetch(uid)
    if row is None:
        raise UserNotFoundError(f"No user record found for uid: {uid}")
    return UserRecord(uid, row["email"])


def verify_password(uid, password):
    """True when the credentials match. Never says which half was wrong.

    Mirrors mock_auth's self-upgrade: a record still holding a plain
    password verifies once and is rewritten as a hash. It should never
    fire — the loader refuses unhashed records — but the two backends
    behaving differently on the same input is worse than a branch that
    stays cold.
    """
    row = _fetch(uid)
    if row is None:
        return False

    stored = row["password_hash"]
    if not passwords.verify(password, stored):
        return False

    if not passwords.is_hashed(stored):
        with get_pool().connection() as conn:
            conn.execute(
                f"UPDATE {_TABLE} SET password_hash = %s, updated_at = %s "
                f"WHERE uid = %s",
                [passwords.hash_password(password), _now(), uid])
    return True


def upsert_user(uid, email, password):
    """Seeds an account without the already-exists guard.

    For the loader and for re-seeding from a snapshot: `password` may
    already be a hash, in which case it is stored as-is rather than
    hashed a second time — bcrypt over a bcrypt string is a valid hash
    of the wrong thing, and every affected login would fail.
    """
    stored = (password if passwords.is_hashed(password)
              else passwords.hash_password(password))
    with get_pool().connection() as conn:
        conn.execute(
            f"INSERT INTO {_TABLE} (uid, email, password_hash, updated_at) "
            f"VALUES (%s, %s, %s, %s) "
            f"ON CONFLICT (uid) DO UPDATE SET "
            f"email = EXCLUDED.email, "
            f"password_hash = EXCLUDED.password_hash, "
            f"updated_at = EXCLUDED.updated_at",
            [uid, email, stored, _now()])


def count():
    """How many accounts exist. For the loader's verification pass."""
    with get_pool().connection() as conn:
        return conn.execute(f"SELECT count(*) AS n FROM {_TABLE}").fetchone()["n"]
