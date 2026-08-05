"""
Seed script: builds the full test workforce in Firestore according to the
scheduling rules, so you don't have to add ~500 people by hand.

Workforce model (per station, per bi-weekly period):
  * Regulars   — one per required post per shift, fixed station + shift
                 (13 days on, 2 off).
  * Relievers  — 4 per station; cover regular day-offs. Each period the
                 generator designates one of them the NIGHT reliever
                 (night-only for those 15 days); the rest cover
                 morning/afternoon.
  * Head guards — 2 fixed per station on 12h shifts:
                 day HG 0500-1700, night HG 1700-0500 (156h each).
  * Substitute head guards — a SHARED FLOATING POOL (not tied to one
                 station); each covers HG day-offs across a 5-station
                 window (their preferred stations).

Station staffing requirements are also written here (test values — edit
STATION_TIERS below or fix them in Firestore later):
  * major stations: 8 morning / 8 afternoon / 2 night  (18/day)
  * mid stations:   6 / 6 / 2                          (14/day)
  * small stations: 5 / 5 / 2                          (12/day)

Every employee gets 5 preferred stations: their own station plus its
neighbors along the line (rule: at least 5 preferred stations each).

Extra Firestore fields written for the future scheduler (the Flutter
Employee model simply ignores them):
  * assignedStation — station name, or null for floating HG substitutes
  * assignedShift   — 'morning' | 'afternoon' | 'night' for regulars,
                      'hgDay' | 'hgNight' for fixed head guards,
                      null for relievers and floating HG substitutes

It mirrors api.py's create_employee (same field names, username/password
format, counters/employee_counter sequence), writes straight to Firestore
in batches, and by default does NOT create Firebase Auth logins (pass
--with-auth if you want them; deleting from the UI works either way).

Re-runnable: previously seeded employees (recognized by their
@example.com email) are wiped first, so you never get duplicates.
Manually created employees are never touched.

Usage (from backend_python/):
    python seed_employees.py              # wipe old seed + full re-seed
    python seed_employees.py --no-wipe    # keep existing, only add
    python seed_employees.py --with-auth  # also create Auth logins (slow)
"""

import argparse
import random
import string
from datetime import datetime, timedelta, timezone

import firebase_init
import station_posts

# Via firebase_init so this script also works in offline mock mode.
auth = firebase_init.get_auth()
transactional = firebase_init.transactional

FIRST_NAMES = [
    "Juan", "Maria", "Jose", "Ana", "Pedro", "Rosa", "Carlo", "Liza",
    "Miguel", "Teresa", "Ramon", "Elena", "Andres", "Carmen", "Diego",
    "Sofia", "Marco", "Isabel", "Rafael", "Angela", "Nino", "Grace",
    "Paolo", "Cristina", "Emilio", "Bianca", "Victor", "Lorna", "Dante",
    "Marites", "Rico", "Jasmine", "Alvin", "Katrina", "Dennis", "Michelle",
    "Ernesto", "Lourdes", "Federico", "Vilma",
]

LAST_NAMES = [
    "Santos", "Reyes", "Cruz", "Bautista", "Ocampo", "Garcia", "Mendoza",
    "Torres", "Flores", "Villanueva", "Ramos", "Castillo", "Aquino",
    "Navarro", "Salazar", "Domingo", "Mercado", "Aguilar", "Delacruz",
    "Fernandez", "Pascual", "Santiago", "Rivera", "Tolentino", "Valdez",
    "Corpuz", "Manalo", "Padilla", "Soriano", "Velasco", "Yumul", "Zamora",
    "Lim", "Tan", "Uy", "Chua", "Dizon", "Enriquez", "Gutierrez", "Ibarra",
]

# (morning, afternoon, night) required posts per day — TEST VALUES.
# The head guard counts inside morning and night (station_posts.py), so
# major's 9 morning = the day head guard + 8 regulars, and night 3
# everywhere = the night head guard + 2 roving guards. The afternoon has
# no head guard of its own.
STATION_TIERS = {
    "major": (9, 8, 3),
    "mid": (7, 6, 3),
    "small": (6, 5, 3),
}
MAJOR_STATIONS = {
    "Monumento", "Central Terminal", "Carriedo", "Doroteo Jose",
    "EDSA", "Baclaran",
}
MID_STATIONS = {
    "Fernando Poe Jr. (FPJ)", "Balintawak", "5th Avenue", "Blumentritt",
    "United Nations (UN)", "Pedro Gil", "Gil Puyat", "Libertad",
    "Ninoy Aquino", "Dr. Santos",
}

RELIEVERS_PER_STATION = 4
FLOATING_SUB_HGS = 10  # shared pool covering all 25 stations' HG day-offs
PREFERRED_COUNT = 5


def init_firestore():
    return firebase_init.get_db()


def fetch_stations(db):
    """Stations sorted by ID, matching the group split order in the app."""
    stations = [doc.to_dict() for doc in db.collection("stations").stream()]
    stations.sort(key=lambda s: s.get("id", ""))
    return stations


def station_requirements(name):
    clean = name.strip()
    if clean in MAJOR_STATIONS:
        return STATION_TIERS["major"]
    if clean in MID_STATIONS:
        return STATION_TIERS["mid"]
    return STATION_TIERS["small"]


def update_station_requirements(db, stations):
    """Writes the per-shift setup to every station document: the required
    numbers, the default post per slot, and the daily total.

    Post lists the admin has already customised in Edit Station are left
    alone — only stations still on the defaults (or with no posts at all)
    are rewritten, so re-seeding the workforce never wipes a real setup.
    """
    batch = db.batch()
    for station in stations:
        m, a, n = station_requirements(station["name"])
        station["requiredMorning"] = m
        station["requiredAfternoon"] = a
        station["requiredNight"] = n
        station["requiredEmployees"] = m + a + n
        updates = {
            "requiredMorning": m,
            "requiredAfternoon": a,
            "requiredNight": n,
            "requiredEmployees": m + a + n,
        }
        existing = station.get("posts") or {}
        customised = any(
            list(existing.get(shift) or [])
            not in ([], station_posts.default_posts(
                shift, len(existing.get(shift) or [])))
            for shift in station_posts.SHIFT_KEYS
        )
        if not customised:
            updates["posts"] = {
                shift: station_posts.default_posts(shift, count)
                for shift, count in (("morning", m), ("afternoon", a),
                                     ("night", n))
            }
            station["posts"] = updates["posts"]
        batch.update(db.collection("stations").document(station["id"]),
                     updates)
    batch.commit()
    print(f"Updated shift requirements on {len(stations)} stations.")


def wipe_seeded_employees(db):
    """Deletes previously seeded employees (marked by their @example.com
    email). Manually created employees are left alone."""
    docs = list(db.collection("employees").stream())
    seeded = [d for d in docs
              if (d.to_dict().get("email") or "").endswith("@example.com")]
    for start in range(0, len(seeded), 450):
        batch = db.batch()
        for doc in seeded[start:start + 450]:
            batch.delete(doc.reference)
        batch.commit()
    print(f"Wiped {len(seeded)} previously seeded employees "
          f"({len(docs) - len(seeded)} manual ones kept).")


def reserve_sequence_block(db, count):
    """Reserves `count` numbers from counters/employee_counter in one
    transaction, so usernames never collide with UI-created employees."""
    counter_ref = db.collection("counters").document("employee_counter")

    @transactional
    def _reserve(transaction):
        snapshot = counter_ref.get(transaction=transaction)
        current = snapshot.get("value") if snapshot.exists else 0
        transaction.set(counter_ref, {"value": current + count})
        return current + 1

    return _reserve(db.transaction())


def generate_credentials(full_name, seq_number):
    """Same format as api.py: CLA001 / CLARISE001AB."""
    last_name = full_name.strip().split(" ")[-1].upper()
    seq_str = str(seq_number).zfill(3)
    username = f"{last_name[:3]}{seq_str}"
    random_letters = "".join(random.choices(string.ascii_uppercase, k=2))
    password = f"{last_name}{seq_str}{random_letters}"
    return username, password


def random_phone():
    return f"+63 9{random.randint(10, 99)}-{random.randint(100, 999)}-{random.randint(1000, 9999)}"


def random_date_joined():
    days_ago = random.randint(30, 3 * 365)
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).isoformat()


def unique_names(count):
    combos = [(f, l) for f in FIRST_NAMES for l in LAST_NAMES]
    if count > len(combos):
        raise SystemExit(
            f"Can only generate {len(combos)} unique names; asked for {count}."
        )
    random.shuffle(combos)
    return combos[:count]


def preferred_window(stations, center_index, size=PREFERRED_COUNT):
    """5 preferred stations: the employee's own station plus its neighbors
    along the line (window clamped at the ends), own station first."""
    start = max(0, min(center_index - size // 2, len(stations) - size))
    names = [s["name"].strip() for s in stations[start:start + size]]
    own = stations[center_index]["name"].strip()
    names.remove(own)
    return [own] + names


def build_workforce_slots(stations):
    """One slot per employee to create: (type, assignedStation,
    assignedShift, preferredStations)."""
    slots = []

    for index, station in enumerate(stations):
        name = station["name"].strip()
        prefs = preferred_window(stations, index)
        m, a, n = (station["requiredMorning"], station["requiredAfternoon"],
                   station["requiredNight"])

        # Regulars: one per required post, fixed shift. The morning and
        # night numbers include the head guard slot, which the station's
        # own head guards man (added below), so those two shifts need one
        # fewer regular than their number.
        for shift, count in (("morning", m), ("afternoon", a), ("night", n)):
            for _ in range(station_posts.regulars_needed(shift, count)):
                slots.append(("regular", name, shift, prefs))

        # Relievers: float between morning/afternoon of their station.
        for _ in range(RELIEVERS_PER_STATION):
            slots.append(("reliever", name, None, prefs))

        # Fixed head guards: 12h day + 12h night.
        slots.append(("headGuard", name, "hgDay", prefs))
        slots.append(("headGuard", name, "hgNight", prefs))

    # Floating substitute head guards: shared pool, each with a 5-station
    # window; windows are spread so all stations are covered by >=1 sub.
    span = len(stations) - PREFERRED_COUNT
    for j in range(FLOATING_SUB_HGS):
        start = round(j * span / max(FLOATING_SUB_HGS - 1, 1))
        window = [s["name"].strip()
                  for s in stations[start:start + PREFERRED_COUNT]]
        slots.append(("headGuard", None, None, window))

    return slots


def seed(with_auth, wipe):
    db = init_firestore()

    stations = fetch_stations(db)
    if not stations:
        raise SystemExit(
            "No stations found in Firestore — insert the 25 stations first."
        )
    print(f"Found {len(stations)} stations.")

    update_station_requirements(db, stations)
    if wipe:
        wipe_seeded_employees(db)

    slots = build_workforce_slots(stations)
    count = len(slots)
    print(f"Seeding {count} employees...")

    first_seq = reserve_sequence_block(db, count)
    names = unique_names(count)

    employees = []
    for i, (emp_type, assigned_station, assigned_shift, prefs) in enumerate(slots):
        seq_number = first_seq + i
        first, last = names[i]
        full_name = f"{first} {last}"
        username, password = generate_credentials(full_name, seq_number)

        employees.append({
            "id": username,
            "name": full_name,
            "phone": random_phone(),
            "email": f"{first.lower()}.{last.lower()}{seq_number}@example.com",
            "preferredStations": prefs,
            "type": emp_type,
            "assignedStation": assigned_station,
            "assignedShift": assigned_shift,
            "username": username,
            "password": password,
            "dateJoined": random_date_joined(),
            "isActive": True,
        })

    for start in range(0, len(employees), 450):
        batch = db.batch()
        for emp in employees[start:start + 450]:
            batch.set(db.collection("employees").document(emp["id"]), emp)
        batch.commit()
        print(f"  wrote employees {start + 1}-{min(start + 450, count)}")

    if with_auth:
        print("Creating Firebase Auth logins (this is the slow part)...")
        created = 0
        for emp in employees:
            try:
                auth.create_user(
                    email=f"{emp['username']}@schedulingsystem.local",
                    password=emp["password"],
                    uid=emp["username"],
                )
                created += 1
            except Exception as e:
                print(f"  auth failed for {emp['username']}: {e}")
        print(f"  created {created} auth users")

    # Summary
    totals = {"regular": 0, "reliever": 0, "headGuard": 0}
    for emp in employees:
        totals[emp["type"]] += 1

    print(f"\nDone. Inserted {count} employees: "
          f"{totals['regular']} regulars, {totals['reliever']} relievers, "
          f"{totals['headGuard']} head guards "
          f"(incl. {FLOATING_SUB_HGS} floating substitutes).")
    print("Per station: required M/A/N (head guard included) = "
          "regulars + relievers + fixed HGs")
    for station in stations:
        m, a, n = (station["requiredMorning"], station["requiredAfternoon"],
                   station["requiredNight"])
        regulars = sum(station_posts.regulars_needed(shift, count)
                       for shift, count in (("morning", m), ("afternoon", a),
                                            ("night", n)))
        print(f"  {station['id']}  {station['name'].strip()}: "
              f"{m}/{a}/{n} required = {regulars} regulars + "
              f"{RELIEVERS_PER_STATION} relievers + 2 HGs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed the test workforce.")
    parser.add_argument("--with-auth", action="store_true",
                        help="Also create Firebase Auth logins (slow)")
    parser.add_argument("--no-wipe", action="store_true",
                        help="Keep previously seeded employees")
    args = parser.parse_args()
    seed(args.with_auth, not args.no_wipe)
