"""
One-off migration: hash the stored passwords, and strip the readable
copies off the employee records.

Two things are converted:

1. `mock_data/_auth.json` — every plain-text `password` becomes a bcrypt
   hash. Records already hashed are left alone, so re-running is safe.
2. The `password` field on each employee — replaced with the mask. This
   field was only ever a readable copy for the admin screens; the
   credential that actually gets checked lives in Firebase Auth (or, in
   development, in _auth.json). Removing it loses nothing that can still
   be verified.

Nobody is locked out. The hash in _auth.json is computed FROM the
existing plain-text password, so every current password keeps working —
what changes is that the stored form can no longer be read back.

    python migrate_passwords.py            # report only, writes nothing
    python migrate_passwords.py --apply    # perform the migration

Run it in the mode you want to convert: USE_MOCK_DB=1 rewrites
mock_data/, USE_MOCK_DB=0 rewrites Firestore. Real Firebase Auth is not
touched in either case — it already hashes, and its records need no
migration.
"""

import argparse
import json
import os
import sys

import firebase_init
import passwords
from mock_firestore import DEFAULT_DATA_DIR

AUTH_FILE = os.path.join(DEFAULT_DATA_DIR, "_auth.json")


def migrate_auth_file(apply):
    """Hashes the plain-text passwords in mock_data/_auth.json."""
    if not os.path.exists(AUTH_FILE):
        print(f"_auth.json  not found at {AUTH_FILE} — skipping "
              "(nothing to migrate in real-Firebase mode).")
        return 0, 0

    with open(AUTH_FILE, encoding="utf-8") as fh:
        users = json.load(fh)

    already, converted = 0, 0
    for uid, record in users.items():
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
        import atomic_write

        atomic_write.write_json(AUTH_FILE, users)

    print(f"_auth.json  {len(users)} accounts: "
          f"{converted} to hash, {already} already hashed")
    return converted, already


def migrate_employee_records(db, apply):
    """Replaces the readable `password` copy on employees with the mask."""
    docs = list(db.collection("employees").stream())
    readable = []
    for doc in docs:
        data = doc.to_dict() or {}
        stored = data.get("password")
        if stored and stored != passwords.MASK:
            readable.append(doc.id)

    if apply and readable:
        batch = db.batch()
        for index, employee_id in enumerate(readable, start=1):
            batch.update(db.collection("employees").document(employee_id),
                         {"password": passwords.MASK})
            # Firestore caps a batch at 500 writes.
            if index % 400 == 0:
                batch.commit()
                batch = db.batch()
        batch.commit()

    print(f"employees   {len(docs)} records: "
          f"{len(readable)} carrying a readable password")
    return len(readable)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="perform the migration (default: report only)")
    args = parser.parse_args()

    mode = "mock_data/" if firebase_init.MOCK_MODE else "REAL FIRESTORE"
    print(f"Target: {mode}")
    print(f"Action: {'APPLY' if args.apply else 'report only'}\n")

    db = firebase_init.get_db()

    to_hash, _ = migrate_auth_file(args.apply)
    readable = migrate_employee_records(db, args.apply)

    print()
    if not args.apply:
        if to_hash or readable:
            print("Nothing was written. Re-run with --apply to migrate.")
        else:
            print("Already migrated — nothing to do.")
        return 0

    print("Done. Every existing password still works: the hashes were "
          "computed from them.\nWhat changed is that the stored form can "
          "no longer be read back.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
