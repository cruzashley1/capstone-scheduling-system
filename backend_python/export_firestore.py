"""
One-time export of Firestore into mock_data/*.json for offline development.

Run this ONCE against the real database (USE_MOCK_DB must be off), then set
USE_MOCK_DB=1 and develop against the snapshot forever after.

    python export_firestore.py

Cost: one Firestore read per document exported, charged once. The script
prints the total so you know what it spent. Re-run it only when you want a
fresh snapshot — every run costs reads again.

Auth accounts are seeded from the exported employee/user records, whose
passwords are already stored in Firestore, so offline login works immediately.
"""

import os
import sys

import atomic_write
import firebase_init

# Every collection the backend touches. Missing ones export as empty.
COLLECTIONS = [
    "users",
    "employees",
    "stations",
    "schedules",
    "counters",
    "attendance_reports",
    "replacements",
    "employee_notifications",
]

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mock_data")

# Admin passwords live only in Firebase Auth (hashed), so there is nothing in
# Firestore to seed an offline login from. Admin accounts therefore get this
# development password, matching the default /init-admin creates. It applies to
# mock mode only and never touches the real account.
DEV_ADMIN_PASSWORD = "adminpassword123"


def _write_json(path, payload):
    atomic_write.write_json(path, payload, default=str)


def export():
    if firebase_init.MOCK_MODE:
        sys.exit(
            "USE_MOCK_DB is set, so this would export the mock back onto itself.\n"
            "Unset it (or set USE_MOCK_DB=0) and re-run to snapshot real Firestore."
        )

    db = firebase_init.get_db()
    os.makedirs(DATA_DIR, exist_ok=True)

    total_reads = 0
    auth_users = {}
    fallback_accounts = []

    for name in COLLECTIONS:
        documents = {}
        for snapshot in db.collection(name).stream():
            documents[snapshot.id] = snapshot.to_dict()
        total_reads += len(documents)

        _write_json(os.path.join(DATA_DIR, f"{name}.json"), documents)
        print(f"  {name:<24} {len(documents):>5} documents")

        # Seed offline logins. Employee records carry their password in
        # Firestore; admin records don't (theirs is hashed inside Firebase
        # Auth), so those fall back to the development password.
        if name in ("employees", "users"):
            for doc_id, data in documents.items():
                password = data.get("password") or DEV_ADMIN_PASSWORD
                auth_users[doc_id] = {
                    "email": f"{doc_id}@schedulingsystem.local",
                    "password": password,
                }
                if not data.get("password"):
                    fallback_accounts.append(doc_id)

    _write_json(os.path.join(DATA_DIR, "_auth.json"), auth_users)
    print(f"  {'_auth (offline logins)':<24} {len(auth_users):>5} accounts")

    print(f"\nExported {total_reads} documents -> {DATA_DIR}")
    print(f"Firestore reads used: {total_reads} (one-time)")

    if fallback_accounts:
        print(f"\nNOTE: {len(fallback_accounts)} account(s) had no password stored in "
              "Firestore\n(admin passwords live only in Firebase Auth). Offline, sign "
              f"in to these\nwith '{DEV_ADMIN_PASSWORD}':")
        for uid in fallback_accounts:
            print(f"  {uid}")
        print("This password applies to mock mode only; the real account is unchanged.")
    print("\nNow set USE_MOCK_DB=1 in .env and restart uvicorn to develop offline.")


if __name__ == "__main__":
    export()
