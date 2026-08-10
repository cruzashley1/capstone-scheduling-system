"""
The single place that decides which database answers.

`firebase_init.py` already switches between real Firestore and the
offline mock on USE_MOCK_DB. That switch stays exactly as it is — it is
what makes development cost zero Firestore reads. This module sits one
level up and chooses the REPOSITORY, which is the switch Supabase will
need, because Supabase cannot be swapped in at the Firestore-client level
(see repositories/base.py).

    DB_BACKEND=firestore    real Firestore
    DB_BACKEND=mock         mock_data/*.json, 0 reads
    DB_BACKEND=supabase     Supabase (not implemented yet)

Unset, it follows USE_MOCK_DB, so every existing script, .env and
DEV_MODE.md instruction keeps working untouched:

    USE_MOCK_DB=1  ->  mock
    USE_MOCK_DB=0  ->  firestore
"""

import os

from dotenv import load_dotenv

import firebase_init

load_dotenv()

FIRESTORE = "firestore"
MOCK = "mock"
SUPABASE = "supabase"

VALID = (FIRESTORE, MOCK, SUPABASE)


def active_backend():
    """Which backend is selected, as one of VALID."""
    chosen = os.getenv("DB_BACKEND", "").strip().lower()
    if not chosen:
        return MOCK if firebase_init.MOCK_MODE else FIRESTORE
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

    Firestore and the mock still hand back a real client, because their
    repository is built from it. Supabase opens its own connection and
    needs none, so it gets the sentinel above rather than a client it
    would never call.
    """
    if active_backend() == SUPABASE:
        return _SupabaseHandle()
    return firebase_init.get_db()


def get_repository(db=None):
    """The Repository for the active backend.

    `db` is the Firestore-shaped handle from `firebase_init.get_db()`.
    It is required for the document backends and ignored by Supabase,
    which opens its own connection.
    """
    backend = active_backend()

    if backend == SUPABASE:
        from repositories.supabase_repo import SupabaseRepository

        return SupabaseRepository()

    from repositories import DocumentRepository

    if db is None:
        db = firebase_init.get_db()
    return DocumentRepository(db)
