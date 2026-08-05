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
