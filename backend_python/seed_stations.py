"""
Seed script: creates the 25 real stations (mirrored from production) in
Firestore, since seed_employees.py refuses to run until stations exist.

Re-runnable: does nothing if stations already exist, unless --wipe is
passed to delete and recreate them.

Usage (from backend_python/):
    python seed_stations.py
    python seed_stations.py --wipe
"""

import argparse

import firebase_init
import station_posts
# Via firebase_init so this script also works in offline mock mode.
transactional = firebase_init.transactional

# Mirrors production's `stations` collection (STA001..STA025), north to
# south along the line -- order matters, it's what seed_employees.py uses
# to assign each employee's preferred-station "neighbors" window.
#
# (name, requiredMorning, requiredAfternoon, requiredNight) -- head guard
# INCLUDED in morning and night (station_posts.py): morning 9 = the day
# head guard + 8 others, night 3 = the night head guard + 2 roving. The
# afternoon has no head guard of its own, the day HG covers it.
STATIONS = [
    ("Monumento", 9, 8, 3),
    ("Abad Santos", 6, 5, 3),
    ("Fernando Poe Jr. (FPJ)", 7, 6, 3),
    ("Balintawak", 7, 6, 3),
    ("5th Avenue", 7, 6, 3),
    ("R. Papa", 6, 5, 3),
    ("Blumentritt", 7, 6, 3),
    ("Tayuman", 6, 5, 3),
    ("Bambang", 6, 5, 3),
    ("Doroteo Jose", 9, 8, 3),
    ("Carriedo", 9, 8, 3),
    ("Central Terminal", 9, 8, 3),
    ("United Nations (UN)", 7, 6, 3),
    ("Pedro Gil", 7, 6, 3),
    ("Quirino", 6, 5, 3),
    ("Vito Cruz", 6, 5, 3),
    ("Gil Puyat", 7, 6, 3),
    ("Libertad", 7, 6, 3),
    ("EDSA", 9, 8, 3),
    ("Baclaran", 9, 8, 3),
    ("Redemptorist-Aseana", 6, 5, 3),
    ("MIA Road", 6, 5, 3),
    ("Asia World", 6, 5, 3),
    ("Ninoy Aquino", 7, 6, 3),
    ("Dr. Santos", 7, 6, 3),
]


def next_station_sequence(db):
    """Same counters/station_counter transaction api.py's POST /stations
    uses, so IDs come out STA001.. and never collide with UI-created
    stations later."""
    counter_ref = db.collection("counters").document("station_counter")

    @transactional
    def _increment(transaction):
        snapshot = counter_ref.get(transaction=transaction)
        current = snapshot.get("value") if snapshot.exists else 0
        transaction.set(counter_ref, {"value": current + 1})
        return current + 1

    return _increment(db.transaction())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--wipe", action="store_true",
                         help="delete existing stations before seeding")
    args = parser.parse_args()

    db = firebase_init.get_db()

    existing = list(db.collection("stations").stream())
    if existing and not args.wipe:
        print(f"{len(existing)} stations already exist -- nothing to do "
              f"(pass --wipe to replace them).")
        return

    if existing:
        batch = db.batch()
        for doc in existing:
            batch.delete(doc.reference)
        batch.commit()
        print(f"Wiped {len(existing)} existing stations.")

    batch = db.batch()
    for name, m, a, n in STATIONS:
        seq = next_station_sequence(db)
        station_id = f"STA{str(seq).zfill(3)}"
        batch.set(db.collection("stations").document(station_id), {
            "id": station_id,
            "name": name,
            "requiredEmployees": m + a + n,
            "requiredMorning": m,
            "requiredAfternoon": a,
            "requiredNight": n,
            # Default post per slot; the day shifts leave their extra
            # slots unnamed for the admin to fill in Edit Station.
            "posts": {
                "morning": station_posts.default_posts("morning", m),
                "afternoon": station_posts.default_posts("afternoon", a),
                "night": station_posts.default_posts("night", n),
            },
            "isActive": True,
        })
    batch.commit()
    print(f"Seeded {len(STATIONS)} stations.")


if __name__ == "__main__":
    main()
