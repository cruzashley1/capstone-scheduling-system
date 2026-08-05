"""
Offline stand-in for firebase_admin.auth plus the Identity Toolkit
password check, so development mode needs no network at all.

Accounts live in mock_data/_auth.json as {uid: {email, password}}.

Passwords are stored in plain text. That is acceptable only because this file
never holds real credentials: it is seeded from the generated development
passwords and is git-ignored. Never point this at production data.
"""

import json
import os
import threading

import atomic_write
from mock_firestore import DEFAULT_DATA_DIR

_AUTH_FILE = os.path.join(DEFAULT_DATA_DIR, "_auth.json")
_lock = threading.RLock()
_users = None


class MockAuthError(Exception):
    """Raised for the same situations the real Admin SDK rejects."""


# Named to match firebase_admin.auth so callers can catch either module's
# errors with the same `except auth.UidAlreadyExistsError` clause.
class UidAlreadyExistsError(MockAuthError):
    pass


class UserNotFoundError(MockAuthError):
    pass


def _load():
    global _users
    if _users is None:
        os.makedirs(DEFAULT_DATA_DIR, exist_ok=True)
        if os.path.exists(_AUTH_FILE):
            with open(_AUTH_FILE, "r", encoding="utf-8") as fh:
                _users = json.load(fh)
        else:
            _users = {}
    return _users


def _flush():
    atomic_write.write_json(_AUTH_FILE, _users)


class MockUserRecord:
    def __init__(self, uid, email):
        self.uid = uid
        self.email = email


def create_user(email=None, password=None, uid=None, **_kwargs):
    with _lock:
        users = _load()
        if uid in users:
            raise UidAlreadyExistsError(
                f"The user with the provided uid already exists: {uid}")
        users[uid] = {"email": email, "password": password}
        _flush()
    return MockUserRecord(uid, email)


def update_user(uid, password=None, email=None, **_kwargs):
    with _lock:
        users = _load()
        if uid not in users:
            raise UserNotFoundError(f"No user record found for uid: {uid}")
        if password is not None:
            users[uid]["password"] = password
        if email is not None:
            users[uid]["email"] = email
        _flush()
    return MockUserRecord(uid, users[uid]["email"])


def delete_user(uid, **_kwargs):
    with _lock:
        users = _load()
        if uid not in users:
            raise UserNotFoundError(f"No user record found for uid: {uid}")
        del users[uid]
        _flush()


def get_user(uid, **_kwargs):
    with _lock:
        users = _load()
        if uid not in users:
            raise UserNotFoundError(f"No user record found for uid: {uid}")
        return MockUserRecord(uid, users[uid]["email"])


def verify_password(uid, password):
    """Local equivalent of the Identity Toolkit signInWithPassword call.
    Returns True when the credentials match."""
    with _lock:
        users = _load()
        record = users.get(uid)
        return record is not None and record.get("password") == password


def upsert_user(uid, email, password):
    """Used by the exporter to seed accounts without tripping the
    already-exists guard in create_user()."""
    with _lock:
        users = _load()
        users[uid] = {"email": email, "password": password}
        _flush()
