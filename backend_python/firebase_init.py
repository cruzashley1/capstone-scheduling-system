"""
Shared Firebase Admin bootstrap for every script in this folder.

Set USE_MOCK_DB=1 (in .env or the environment) to run fully offline against
mock_data/*.json instead of Firebase. Development mode then costs zero
Firestore reads, which matters because the free tier caps at 50k/day and a
single employees.stream() spends one read per employee.

Every module reaches Firebase through this file, so the switch happens here
and nowhere else.
"""

import os

from dotenv import load_dotenv

load_dotenv()

MOCK_MODE = os.getenv("USE_MOCK_DB", "").strip().lower() in ("1", "true", "yes", "on")

_app = None
_mock_db = None

if not MOCK_MODE:
    import tls_fix

    # Must run before firebase_admin/grpc are imported, otherwise antivirus
    # HTTPS scanning (AVG) breaks the Firestore connection (see tls_fix.py).
    tls_fix.configure()

    import firebase_admin
    from firebase_admin import credentials, firestore

    transactional = firestore.transactional
else:
    import mock_firestore

    transactional = mock_firestore.transactional


def get_db():
    """Returns a Firestore client — the real one, or the offline mock when
    USE_MOCK_DB is set. Also usable for auth calls via get_auth()."""
    global _app, _mock_db

    if MOCK_MODE:
        if _mock_db is None:
            _mock_db = mock_firestore.MockFirestoreClient()
            print(f"[MOCK MODE] Firestore served from {mock_firestore.DEFAULT_DATA_DIR}"
                  " - 0 Firebase reads.")
        return _mock_db

    if _app is None:
        cred_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "firebase-service-account.json"
        )
        cred = credentials.Certificate(cred_path)
        _app = firebase_admin.initialize_app(cred)

    return firestore.client()


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
    """Returns the auth module to use: firebase_admin.auth normally, the
    offline stand-in in mock mode, or supabase_auth when DB_BACKEND says
    so. All three expose create_user / update_user / delete_user with the
    same signatures.

    Supabase is checked FIRST and deliberately outranks USE_MOCK_DB.
    Running Supabase alongside USE_MOCK_DB=1 is the normal configuration
    — it is what keeps firebase_admin from being imported at all — so
    letting MOCK_MODE win here would quietly send every login back to
    the local JSON file this switch exists to leave behind.
    """
    if _supabase_selected():
        import supabase_auth

        return supabase_auth

    if MOCK_MODE:
        import mock_auth

        return mock_auth

    from firebase_admin import auth

    return auth


def identity_toolkit_url(endpoint, api_key):
    """Builds an Identity Toolkit REST URL for `endpoint` (e.g.
    "accounts:signInWithPassword"). Password sign-in isn't covered by the
    Admin SDK, so callers hit this REST API directly with `requests`."""
    return f"https://identitytoolkit.googleapis.com/v1/{endpoint}?key={api_key}"


def verify_password(username, password):
    """Checks a username/password pair, returning True on success.

    Wraps the masked-email sign-in so callers don't repeat it: real mode posts
    to Identity Toolkit, mock mode checks mock_data/_auth.json locally, and
    Supabase checks the auth_accounts table.
    """
    if _supabase_selected():
        import supabase_auth

        return supabase_auth.verify_password(username, password)

    if MOCK_MODE:
        import mock_auth

        return mock_auth.verify_password(username, password)

    import requests

    api_key = os.getenv("FIREBASE_WEB_API_KEY")
    response = requests.post(
        identity_toolkit_url("accounts:signInWithPassword", api_key),
        json={
            "email": f"{username}@schedulingsystem.local",
            "password": password,
            "returnSecureToken": True,
        },
    )
    return response.status_code == 200
