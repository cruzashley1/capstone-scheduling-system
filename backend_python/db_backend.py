"""
The single place that decides which database answers.

    DB_BACKEND=mock         mock_data/*.json, offline, 0 network calls
    DB_BACKEND=supabase     Supabase Postgres

`firestore` was the third option and is gone with the rest of Firebase.

Unset, this follows USE_MOCK_DB=1 to `mock`, so every existing script and
DEV_MODE.md instruction keeps working untouched. Unset AND without
USE_MOCK_DB, it RAISES rather than guessing — see active_backend().
"""

import os

from dotenv import load_dotenv

import db_init

load_dotenv()

MOCK = "mock"
SUPABASE = "supabase"

VALID = (MOCK, SUPABASE)


def active_backend():
    """Which backend is selected, as one of VALID.

    The unset-and-not-mock case is a hard error, and that is the whole
    point of this function on a deployed server. It used to mean
    `firestore`, so a Render instance that forgot DB_BACKEND would boot
    perfectly, serve reads, and then fail at the first login when
    firebase_admin looked for a service account that is not deployed —
    a silent misconfiguration that surfaces as a user-facing bug hours
    later. There is no Firestore to fall back to now, so refusing to
    start is both honest and the earliest possible failure.
    """
    chosen = os.getenv("DB_BACKEND", "").strip().lower()

    if not chosen:
        if db_init.MOCK_MODE:
            return MOCK
        raise RuntimeError(
            "DB_BACKEND is not set and USE_MOCK_DB is not on, so there is "
            "no backend to use. Set DB_BACKEND=supabase in the deployment "
            f"environment, or DB_BACKEND=mock for offline work. "
            f"Valid values: {', '.join(VALID)}.")

    if chosen not in VALID:
        raise ValueError(
            f"DB_BACKEND={chosen!r} is not one of {', '.join(VALID)}")
    return chosen


class _SupabaseHandle:
    """What api.py stores in `db` when Supabase is the backend.

    `db` used to be the Firestore client. No runtime module calls a
    method on it any more — `db.collection(` is 0 across api.py,
    scheduler.py, rotation.py, leave.py and replacements.py — but it is
    still passed around and still guards ~40 endpoints with
    `if db is None: raise 500`, so it has to be something.

    Something, but not a MockFirestoreClient: that would read the whole
    mock_data corpus into memory to serve nobody, and on Render the
    directory is not deployed at all. This is the honest object — it
    names the backend and does nothing else.
    """

    def __repr__(self):
        return "<supabase>"


def get_db_handle():
    """The value api.py's lifespan puts in `db`.

    The mock still hands back a real client, because its repository is
    built from it. Supabase opens its own connection pool and needs none,
    so it gets the sentinel above rather than a client it would never
    call.
    """
    if active_backend() == SUPABASE:
        return _SupabaseHandle()
    return db_init.get_db()


def get_repository(db=None):
    """The Repository for the active backend.

    `db` is the Firestore-shaped handle from `db_init.get_db()`. It is
    required for the document backend and ignored by Supabase, which
    opens its own connection.
    """
    if active_backend() == SUPABASE:
        from repositories.supabase_repo import SupabaseRepository

        return SupabaseRepository()

    from repositories import DocumentRepository

    if db is None:
        db = db_init.get_db()
    return DocumentRepository(db)
