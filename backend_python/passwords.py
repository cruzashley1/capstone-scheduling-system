"""
Password hashing.

Before this, a password existed in plain text in two places: the
`password` field copied onto every employee record, and — in development
mode only — `mock_data/_auth.json`. Real Firebase Auth already hashed the
credential it actually checks, so production was never storing plain-text
logins; the exposure was the readable copies kept alongside them, which
existed so the admin screens could display a guard's password.

Those copies are gone. A password is now stored only as a bcrypt hash,
and a hash cannot be turned back into the password it came from, which is
the entire point. The admin issues a NEW password instead of reading the
old one — see /employees/{id}/reset-password.

bcrypt with a per-password random salt, cost 12: slow enough that
guessing at scale is impractical, fast enough that a login is not
noticeably delayed.
"""

import random
import string

import bcrypt

# Work factor. Each +1 doubles the time to check one password. 12 is the
# usual default and takes roughly a quarter-second here — raise it if
# hardware gets faster, but never lower it for existing hashes, which
# carry their own cost inside the hash string.
ROUNDS = 12

# What the API returns in place of a password it can no longer read. The
# field stays a string so the response shape does not change; it simply
# never carries a real credential again.
MASK = "•" * 8


def hash_password(plain):
    """A bcrypt hash of `plain`, as a str safe to store as JSON/text."""
    if plain is None:
        raise ValueError("cannot hash a null password")
    salt = bcrypt.gensalt(rounds=ROUNDS)
    return bcrypt.hashpw(plain.encode("utf-8"), salt).decode("ascii")


def is_hashed(value):
    """Whether `value` is already a bcrypt hash rather than a password.

    Lets the login path accept records written before this change and
    upgrade them in place, so nothing has to be migrated before the app
    keeps working. bcrypt hashes always start with $2 and are 60 chars.
    """
    return (isinstance(value, str)
            and value.startswith("$2")
            and len(value) == 60)


def verify(plain, stored):
    """Whether `plain` is the password behind `stored`.

    Accepts a legacy plain-text `stored` value so a half-migrated data
    set still logs in; callers that can persist an upgrade should check
    `is_hashed(stored)` and re-store the hash on success.
    """
    if not isinstance(plain, str) or not isinstance(stored, str) or not stored:
        return False
    if is_hashed(stored):
        try:
            return bcrypt.checkpw(plain.encode("utf-8"), stored.encode("ascii"))
        except ValueError:
            return False
    # Legacy plain-text record. Compared in constant time so this path
    # does not leak the password's length or content through timing.
    return _constant_time_equals(plain, stored)


def _constant_time_equals(left, right):
    import hmac

    return hmac.compare_digest(left.encode("utf-8"), right.encode("utf-8"))


def generate_password(length=10):
    """A fresh random password, for resets.

    Uses `secrets` rather than `random`, which is seeded predictably and
    is fine for the sequence-based credentials at signup but not for
    something issued on demand. Ambiguous characters (0/O, 1/l/I) are
    left out because these get read aloud and copied by hand.
    """
    import secrets

    alphabet = ("ABCDEFGHJKMNPQRSTUVWXYZ"
                "abcdefghijkmnpqrstuvwxyz"
                "23456789")
    return "".join(secrets.choice(alphabet) for _ in range(length))
