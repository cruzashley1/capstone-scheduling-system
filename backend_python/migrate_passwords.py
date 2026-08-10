"""
Repairs passwords in the mock_data corpus: hashes any that are still
plain text, and masks the readable copies on employee records.

    python migrate_passwords.py            # report only, writes nothing
    python migrate_passwords.py --apply    # perform the repair

Two things are converted:

1. `mock_data/_auth.json` — every plain-text `password` becomes a bcrypt
   hash. Records already hashed are left alone, so re-running is safe.
2. The `password` field on each employee in `mock_data/employees.json` —
   replaced with the mask. That field was only ever a readable copy for
   the admin screens; the credential that actually gets checked lives in
   _auth.json, and after loading, in Supabase's auth_accounts table.

Nobody is locked out. Each hash is computed FROM the existing plain-text
password, so every current password keeps working — what changes is that
the stored form can no longer be read back.

This has already been run against the current corpus: all 574 accounts
are hashed and all 573 employee records carry the mask. It survives as
the repair tool `load_supabase.py` names when its validator refuses to
load an unhashed corpus, which is the one situation where it is needed
again — a re-imported or hand-edited mock_data.

It operates on the JSON FILES and knows nothing about a backend. That is
deliberate: the corpus is what gets loaded into Supabase, so it must be
correct BEFORE the loader runs, and a tool that needed a working backend
to fix the input to that backend would be circular. It previously went
through firebase_init and rewrote employees via db.collection(); nothing
here talks to a database any more.
"""

import argparse
import json
import os
import sys

import atomic_write
import passwords

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "mock_data")
AUTH_FILE = os.path.join(DATA_DIR, "_auth.json")
EMPLOYEES_FILE = os.path.join(DATA_DIR, "employees.json")


def _load(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def migrate_auth_file(apply):
    """Hashes the plain-text passwords in mock_data/_auth.json."""
    users = _load(AUTH_FILE)
    if users is None:
        print(f"_auth.json    not found at {AUTH_FILE} — skipping")
        return 0

    already, converted = 0, 0
    for record in users.values():
        stored = record.get("password")
        if stored is None:
            continue
        if passwords.is_hashed(stored):
            already += 1
            continue
        if apply:
            record["password"] = passwords.hash_password(stored)
        converted += 1

    if apply and converted:
        atomic_write.write_json(AUTH_FILE, users)

    print(f"_auth.json    {len(users)} accounts: "
          f"{converted} to hash, {already} already hashed")
    return converted


def migrate_employee_records(apply):
    """Replaces the readable `password` copy on employees with the mask."""
    employees = _load(EMPLOYEES_FILE)
    if employees is None:
        print(f"employees     not found at {EMPLOYEES_FILE} — skipping")
        return 0

    readable = [eid for eid, data in employees.items()
                if data.get("password")
                and data.get("password") != passwords.MASK]

    if apply and readable:
        for employee_id in readable:
            employees[employee_id]["password"] = passwords.MASK
        atomic_write.write_json(EMPLOYEES_FILE, employees)

    print(f"employees     {len(employees)} records: "
          f"{len(readable)} carrying a readable password")
    return len(readable)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="perform the repair (default: report only)")
    args = parser.parse_args()

    print(f"Target: {DATA_DIR}")
    print(f"Action: {'APPLY' if args.apply else 'report only'}\n")

    to_hash = migrate_auth_file(args.apply)
    readable = migrate_employee_records(args.apply)

    print()
    if not args.apply:
        if to_hash or readable:
            print("Nothing was written. Re-run with --apply to repair.")
        else:
            print("Already migrated — nothing to do.")
        return 0

    print("Done. Every existing password still works: the hashes were "
          "computed from them.\nWhat changed is that the stored form can "
          "no longer be read back.\n\nRe-run load_supabase.py to push the "
          "repaired corpus to Supabase.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
