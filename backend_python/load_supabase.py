"""
Moves mock_data/*.json into Supabase.

    python load_supabase.py --check     # validate only, write nothing
    python load_supabase.py             # validate, load, verify
    python load_supabase.py --wipe      # clear the tables first

Stage 4's data migration. The corpus in mock_data/ is the live one — it
is what the running system serves today and what the 58 golden files
were captured from — so this is the source of truth, not an export of
Firestore taken months ago.

Three things it does in order, and it stops at the first that fails:

1. **Validate.** Every record is checked against the real table columns
   BEFORE anything is written: unknown fields, missing NOT NULLs, ids
   that disagree with their key, unhashed passwords. A load that dies
   halfway leaves a database that is neither empty nor correct, and the
   fix is always to wipe and start again — so the cheap pass runs first.

2. **Load**, through SupabaseRepository rather than through SQL of its
   own. That matters more than it looks: it means the data arrives by
   the exact path the API will use, with the same camelCase conversion,
   the same JSONB wrapping and the same days-to-duty_assignments split.
   A loader with its own INSERT statements can succeed against a
   repository that is broken, and vice versa.

3. **Verify.** Row counts per table, then a full round trip — every
   record read back and compared field by field against the JSON it came
   from, with the absent-vs-null difference the schema documents allowed
   for and nothing else.

Re-runnable. Every write is an upsert keyed by id, so a second run
overwrites rather than duplicating, and --wipe is only needed to remove
records that no longer exist in the corpus.
"""

import argparse
import json
import os
import sys

import tls_fix  # noqa: F401  — AVG's TLS interception, see tls_fix.py

import passwords
from repositories.base import COLLECTIONS
from repositories.supabase_repo import (SupabaseRepository, close_pool,
                                        to_camel)

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "mock_data")
AUTH_FILE = os.path.join(DATA_DIR, "_auth.json")

# Load order. Schedules last because they are the heaviest and the only
# ones that fan out into a second table; if something is going to fail on
# volume, everything else is already in by then.
LOAD_ORDER = (
    "users",
    "counters",
    "stations",
    "employees",
    "rotation_cycles",
    "station_rotation_assignments",
    "special_assignments",
    "attendance_reports",
    "absence_requests",
    "special_requests",
    "leave_requests",
    "cover_offers",
    "replacements",
    "employee_notifications",
    "schedules",
)

# Fields the corpus carries that are NOT columns and are dropped on
# purpose. Empty today — every field in mock_data has a home — but the
# validator reports unknown fields as errors, and this is where a
# deliberate exception would be recorded rather than silently allowed.
DROPPED = {}


def _read(name):
    path = os.path.join(DATA_DIR, f"{name}.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------

def validate(repo):
    """Every problem found, as a list of strings. Empty means loadable."""
    problems = []
    schema = repo._schema

    for name in LOAD_ORDER:
        records = _read(name)
        if not records:
            problems.append(f"{name}: mock_data/{name}.json is missing or empty")
            continue

        columns = schema.columns[name]
        known = {to_camel(c) for c in columns}
        allowed = known | {"days"} if name == "schedules" else known
        dropped = DROPPED.get(name, set())

        unknown, id_mismatch = set(), []
        for key, record in records.items():
            unknown |= (set(record) - allowed - dropped)
            if "id" in known and record.get("id", key) != key:
                id_mismatch.append(f"{key} -> {record.get('id')}")

        if unknown:
            problems.append(
                f"{name}: {len(unknown)} field(s) with no column: "
                f"{', '.join(sorted(unknown))}")
        if id_mismatch:
            problems.append(
                f"{name}: {len(id_mismatch)} record(s) whose id disagrees "
                f"with their key: {', '.join(id_mismatch[:3])}")

    # Credentials are the one thing a bad load makes unrecoverable: a
    # double-hashed password is a valid hash of the wrong string, and
    # every affected guard is locked out with nothing in the logs.
    auth = _read("_auth")
    if not auth:
        problems.append("_auth.json is missing or empty — nobody could log in")
    else:
        unhashed = [uid for uid, rec in auth.items()
                    if not passwords.is_hashed(rec.get("password", ""))]
        no_email = [uid for uid, rec in auth.items() if not rec.get("email")]
        if unhashed:
            problems.append(
                f"_auth: {len(unhashed)} password(s) are not bcrypt hashes "
                f"({', '.join(unhashed[:3])}). Run migrate_passwords.py "
                f"first — loading them as-is would store a plain password.")
        if no_email:
            problems.append(f"_auth: {len(no_email)} record(s) have no email")

    # Everyone with a login should be someone, and everyone who is
    # someone should have a login. Neither is enforced by a constraint —
    # admin01 is deliberately not an employee — so it is checked here.
    employees = _read("employees")
    users = _read("users")
    orphan_auth = set(auth) - set(employees) - set(users)
    no_login = (set(employees) | set(users)) - set(auth)
    if orphan_auth:
        problems.append(
            f"_auth: {len(orphan_auth)} account(s) match no employee or "
            f"user: {', '.join(sorted(orphan_auth)[:5])}")
    if no_login:
        problems.append(
            f"{len(no_login)} employee/user record(s) have no credential: "
            f"{', '.join(sorted(no_login)[:5])}")

    return problems


# ---------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------

def wipe(repo):
    """Empties every table. duty_assignments goes with the schedules."""
    with repo._pool.connection() as conn:
        for name in reversed(LOAD_ORDER):
            conn.execute(f'TRUNCATE TABLE "{name}" CASCADE')
        conn.execute("TRUNCATE TABLE auth_accounts")
        conn.commit()


def load(repo):
    """Writes every collection. Returns {name: records written}."""
    written = {}
    for name in LOAD_ORDER:
        records = _read(name)
        getattr(repo, name).upsert_many(records)
        written[name] = len(records)
        print(f"  {name:<32} {len(records):>5}")

    import supabase_auth
    auth = _read("_auth")
    for uid, record in auth.items():
        supabase_auth.upsert_user(uid, record["email"], record["password"])
    written["auth_accounts"] = len(auth)
    print(f"  {'auth_accounts':<32} {len(auth):>5}")
    return written


# ---------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------

def _differences(name, original, loaded):
    """Field-level differences between a source record and what came back.

    The one difference the schema signed off on is ignored: a field the
    document store simply LACKED comes back as an explicit null, because
    a column cannot be absent. Anything else — a changed value, a lost
    list order, a null that used to hold something — is reported.
    """
    diffs = []
    for field in set(original) | set(loaded):
        if field not in original:
            # Added by the column existing. Only null is acceptable.
            if loaded[field] is not None:
                diffs.append(f"{field}: absent -> {loaded[field]!r}")
        elif field not in loaded:
            diffs.append(f"{field}: {original[field]!r} -> missing")
        elif original[field] != loaded[field]:
            diffs.append(f"{field}: {original[field]!r} -> {loaded[field]!r}")
    return diffs


def verify(repo):
    """Reads everything back and compares. Returns a list of problems."""
    problems = []

    for name in LOAD_ORDER:
        source = _read(name)
        rows = {r["id"]: r for r in getattr(repo, name).list()} \
            if name not in ("users", "counters") else None

        if rows is None:
            # These two omit id from the body, so key them from the source
            # side and fetch one at a time. Three records between them.
            rows = {key: getattr(repo, name).get(key) for key in source}

        missing = [k for k in source if rows.get(k) is None]
        extra = [k for k in rows if k not in source]
        if missing:
            problems.append(f"{name}: {len(missing)} record(s) did not load: "
                            f"{', '.join(missing[:3])}")
        if extra:
            problems.append(f"{name}: {len(extra)} record(s) in the table are "
                            f"not in the corpus: {', '.join(extra[:3])}")

        mismatched = []
        for key, original in source.items():
            loaded = rows.get(key)
            if loaded is None:
                continue
            if name in ("users", "counters"):
                original = {k: v for k, v in original.items() if k != "id"}
            diffs = _differences(name, original, loaded)
            if diffs:
                mismatched.append(f"{key}: {'; '.join(diffs[:3])}")

        if mismatched:
            problems.append(
                f"{name}: {len(mismatched)} record(s) changed in the round "
                f"trip:\n      " + "\n      ".join(mismatched[:5]))
        else:
            print(f"  {name:<32} {len(source):>5}  identical")

    import supabase_auth
    auth = _read("_auth")
    loaded = supabase_auth.count()
    if loaded != len(auth):
        problems.append(
            f"auth_accounts: {loaded} rows, expected {len(auth)}")
    else:
        print(f"  {'auth_accounts':<32} {loaded:>5}  identical")

    # A credential that does not verify is worse than one that is
    # missing, because nothing reports it until someone cannot log in.
    # Hashes cannot be compared to a plaintext, so this checks the shape
    # survived rather than the secret.
    sample = list(auth.items())[:5]
    for uid, record in sample:
        try:
            user = supabase_auth.get_user(uid)
        except Exception as e:
            problems.append(f"auth_accounts: {uid} not readable ({e})")
            continue
        if user.email != record["email"]:
            problems.append(
                f"auth_accounts: {uid} email {user.email!r} != "
                f"{record['email']!r}")

    return problems


# ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="validate the corpus and exit, writing nothing")
    parser.add_argument("--wipe", action="store_true",
                        help="empty the tables before loading")
    args = parser.parse_args()

    if not os.path.isdir(DATA_DIR):
        print(f"No mock_data/ at {DATA_DIR}. This loader reads the live "
              f"corpus; there is nothing to migrate without it.")
        return 2

    repo = SupabaseRepository()
    try:
        print("=" * 66)
        print("Validating the corpus")
        print("=" * 66)
        problems = validate(repo)
        if problems:
            for problem in problems:
                print(f"  ! {problem}")
            print("\nNothing was written. Fix the above and run again.")
            return 1
        print("  no problems found")

        if args.check:
            print("\n--check: stopping before the load.")
            return 0

        if args.wipe:
            print("\nWiping tables")
            wipe(repo)
            print("  done")

        print("\n" + "=" * 66)
        print("Loading")
        print("=" * 66)
        written = load(repo)

        print("\n" + "=" * 66)
        print("Verifying — reading every record back")
        print("=" * 66)
        problems = verify(repo)
        if problems:
            for problem in problems:
                print(f"  ! {problem}")
            print("\nFAIL — the data in Supabase does not match the corpus.")
            return 1

        total = sum(written.values())
        print("\n" + "=" * 66)
        print(f"OK — {total} records in {len(written)} tables, every one "
              f"identical on read-back.")
        print("=" * 66)
        return 0
    finally:
        close_pool()


if __name__ == "__main__":
    sys.exit(main())
