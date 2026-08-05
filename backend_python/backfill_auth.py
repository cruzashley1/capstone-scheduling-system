"""
Backfill script: creates Firebase Auth logins for employees that already
exist in Firestore but were seeded without --with-auth, so they could
never sign in.

For every doc in the employees collection:
  * missing Auth user  -> create it (masked email, stored password,
    uid = username), same scheme as api.py's create_employee
  * existing Auth user -> reset its password to the one stored in
    Firestore, so the credentials shown in the admin UI always work

Safe to re-run any time; it only syncs Auth with what Firestore says.

Usage (from backend_python/):
    python backfill_auth.py
"""

import firebase_init

# Via firebase_init so this script also works in offline mock mode.
auth = firebase_init.get_auth()


def main():
    db = firebase_init.get_db()

    docs = list(db.collection("employees").stream())
    print(f"Found {len(docs)} employees in Firestore.")

    created = updated = skipped = failed = 0
    for i, doc in enumerate(docs, 1):
        emp = doc.to_dict()
        username = emp.get("username") or doc.id
        password = emp.get("password")
        if not password:
            print(f"  [{i}] {username}: no password stored, skipping")
            skipped += 1
            continue

        masked_email = f"{username}@schedulingsystem.local"
        try:
            auth.create_user(email=masked_email, password=password,
                             uid=username)
            created += 1
        except auth.UidAlreadyExistsError:
            try:
                auth.update_user(username, password=password)
                updated += 1
            except Exception as e:
                print(f"  [{i}] {username}: update failed: {e}")
                failed += 1
        except Exception as e:
            print(f"  [{i}] {username}: create failed: {e}")
            failed += 1

        if i % 50 == 0:
            print(f"  ...{i}/{len(docs)} processed")

    print(f"\nDone. {created} created, {updated} passwords synced, "
          f"{skipped} skipped, {failed} failed.")


if __name__ == "__main__":
    main()
