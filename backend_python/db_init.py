"""
Bootstrap for the offline document backend, and the auth switch.

This is what firebase_init.py became once Firebase was retired. There is
no real Firestore client any more, no `firebase_admin` import, no service
account and no Identity Toolkit call. Two switches survive, because they
were never really about Firebase:

    get_db()    the offline mock_firestore client — DB_BACKEND=mock only.
                Supabase never calls it; db_backend hands out a sentinel.
    get_auth()  the auth module: supabase_auth, or mock_auth offline.

mock_firestore.py stays, and is NOT Firebase. It is a local JSON store
written to impersonate the Firestore API, which is exactly what lets
DocumentRepository and the six testing_*.py suites keep running offline
at zero cost. Retiring the vendor did not retire the offline corpus.

USE_MOCK_DB still selects offline mode. What it no longer does is select
*Firestore* when it is absent — see db_backend.active_backend(), which
now refuses to guess rather than falling back to a backend that is gone.
"""

import os

from dotenv import load_dotenv

load_dotenv()

MOCK_MODE = os.getenv("USE_MOCK_DB", "").strip().lower() in ("1", "true", "yes", "on")

import mock_firestore  # noqa: E402  — no longer conditional; nothing to guard

# Re-exported because DocumentRepository builds its transactions from it.
# It used to be firestore.transactional in real mode; the mock's version
# is the only one left.
transactional = mock_firestore.transactional

_mock_db = None


def get_db():
    """The offline Firestore-shaped client backing DB_BACKEND=mock.

    Unconditional now. The real-Firestore branch this used to choose
    between is deleted, so the only document store left is the local one.
    """
    global _mock_db

    if _mock_db is None:
        _mock_db = mock_firestore.MockFirestoreClient()
        print(f"[MOCK MODE] documents served from {mock_firestore.DEFAULT_DATA_DIR}")
    return _mock_db


def _supabase_selected():
    """True when DB_BACKEND picks Supabase.

    Read straight from the environment rather than through
    db_backend.active_backend(), because db_backend imports THIS module
    at its top level and asking it here at import time would close the
    circle. The parsing is the same one db_backend does, and
    db_backend.VALID still rejects a misspelling loudly.
    """
    return os.getenv("DB_BACKEND", "").strip().lower() == "supabase"


def get_auth():
    """Returns the auth module to use: supabase_auth when DB_BACKEND says
    so, otherwise the offline stand-in. Both expose create_user /
    update_user / delete_user / get_user / verify_password with the same
    signatures, so api.py's `auth.` calls do not know the difference.

    Supabase is checked FIRST and deliberately outranks USE_MOCK_DB.
    Running Supabase alongside USE_MOCK_DB=1 is a normal configuration,
    so letting MOCK_MODE win here would quietly send every login back to
    the local JSON file this switch exists to leave behind.
    """
    if _supabase_selected():
        import supabase_auth

        return supabase_auth

    import mock_auth

    return mock_auth


def verify_password(username, password):
    """Checks a username/password pair, returning True on success.

    Supabase checks the auth_accounts table; offline mode checks
    mock_data/_auth.json. Both compare bcrypt hashes via passwords.py —
    the Identity Toolkit round trip this used to make is gone with the
    rest of Firebase.
    """
    return get_auth().verify_password(username, password)
