"""
One-time migration: move every station onto the per-shift post setup.

Two things change in the station documents:

  1. The head guard now counts INSIDE the shift number.
     Before, requiredMorning/Afternoon/Night counted regulars only and
     the station's two head guards sat outside the numbers. Now Morning 9
     means "the day head guard plus 8 others" and Night 3 means "the night
     head guard plus 2 roving". So this script adds 1 to Morning and 1 to
     Night. Afternoon is left alone — it has no head guard of its own,
     because the day HG's 12-hour duty already covers it.

  2. Each shift gets a `posts` list, one entry per slot.
     Defaults reproduce exactly what the generator used to hand out, so
     regenerating right after this migration produces the same rosters:
        morning   Head Guard, SW Platform, SE Platform, Roving, then
                  unnamed slots
        afternoon SW Platform, SE Platform, Roving, then unnamed slots
        night     Head Guard, then Roving for every remaining slot
     An unnamed slot is an empty string — it generates as "Undefined",
     exactly like the 4th+ morning guard did before. Name them in
     Edit Station (that's the amber warning you'll see there).

Where the numbers come from: the station's own requiredMorning/Afternoon/
Night if it has them, otherwise a count of the guards actually assigned
to that station (older documents only carry the flat requiredEmployees).
Either way the result is the staffing the generator has been producing,
so migrating changes no rosters — verified by generating a group before
and after and diffing every entry.

`requiredEmployees` is rewritten as the daily total of the three shifts.
Note this makes each station's headline number go UP by 2 — that's the
two head guards finally being counted, and it makes the "x / y Employees"
badge on the station cards honest: the x side always counted head guards.

Re-runnable: stations that already carry a `posts` map are skipped
unless --force is passed.

Usage (from backend_python/):
    python migrate_station_posts.py            # apply
    python migrate_station_posts.py --dry-run  # show what would change
    python migrate_station_posts.py --force    # redo already-migrated ones
"""

import argparse

# firebase_init runs the AVG/TLS workaround before it touches
# firebase_admin, so importing it is all this script needs.
import firebase_init
import scheduler
import station_posts

build_posts = station_posts.default_posts


def staffing_by_station(db):
    """What the employee records actually put at each station, keyed by
    station name: {name: {"morning": n, "afternoon": n, "night": n,
    "hgDay": n, "hgNight": n}}.

    Used for stations whose document never carried a shift breakdown (old
    docs with only requiredEmployees). Counting the guards really posted
    there isn't a guess — it's the staffing the generator has been
    producing all along.
    """
    counts = {}
    for doc in db.collection("employees").stream():
        emp = doc.to_dict()
        if not emp.get("isActive", True):
            continue
        name = (emp.get("assignedStation") or "").strip()
        if not name:
            continue
        shift = emp.get("assignedShift")
        emp_type = emp.get("type")
        bucket = counts.setdefault(name, {"morning": 0, "afternoon": 0,
                                          "night": 0, "hgDay": 0,
                                          "hgNight": 0})
        if emp_type == "regular" and shift in ("morning", "afternoon",
                                               "night"):
            bucket[shift] += 1
        elif emp_type == "headGuard" and shift in ("hgDay", "hgNight"):
            bucket[shift] += 1
    return counts


def migrate(dry_run, force):
    db = firebase_init.get_db()

    stations = [doc.to_dict() for doc in db.collection("stations").stream()]
    stations.sort(key=lambda s: s.get("id", ""))
    if not stations:
        raise SystemExit("No stations found in Firestore.")

    # Fallback source for stations whose document has no shift breakdown.
    staffing = staffing_by_station(db)

    changed = 0
    skipped = 0
    batch = db.batch()

    for station in stations:
        station_id = station.get("id")
        name = (station.get("name") or "").strip()

        if station.get("posts") and not force:
            skipped += 1
            print(f"  {station_id}  {name}: already migrated, skipped")
            continue

        old_m = int(station.get("requiredMorning") or 0)
        old_a = int(station.get("requiredAfternoon") or 0)
        old_n = int(station.get("requiredNight") or 0)

        source = "shift breakdown"

        # A station that never had a shift breakdown (an old document with
        # only requiredEmployees) is read off the guards actually posted
        # there instead — that IS the staffing the generator has been
        # producing, so nothing about the rosters changes.
        if old_m + old_a + old_n <= 0:
            actual = staffing.get(name)
            if not actual or sum(actual.values()) == 0:
                skipped += 1
                print(f"  {station_id}  {name}: no shift breakdown and no "
                      f"guards assigned here — set it up in Edit Station")
                continue
            old_m, old_a, old_n = (actual["morning"], actual["afternoon"],
                                   actual["night"])
            source = "guards assigned here"
            if not actual["hgDay"] or not actual["hgNight"]:
                print(f"  {station_id}  {name}: WARNING no "
                      f"{'day' if not actual['hgDay'] else 'night'} head "
                      f"guard is assigned here — the slot is still reserved, "
                      f"and generation will report it as unmanned")

        # The head guards join their shift's count.
        #
        # Night is clamped first: the old generator hard-capped night at
        # scheduler.MAX_NIGHT_REGULARS roving guards no matter what the
        # station document asked for, so a doc saying 3 was really only
        # ever staffing 2. The cap now comes from this number instead, and
        # carrying the doc's unused 3 across would quietly put an extra
        # guard on nights. Migrating the EFFECTIVE staffing keeps the
        # rosters identical; raise the number in Edit Station to actually
        # add a rover.
        capped_n = min(old_n, scheduler.MAX_NIGHT_REGULARS)
        new_m = old_m + 1
        new_a = old_a
        new_n = capped_n + 1
        if capped_n != old_n:
            print(f"  {station_id}  {name}: night asked for {old_n} but the "
                  f"old cap only ever staffed {capped_n} — migrating the "
                  f"{capped_n} that were actually working")

        updates = {
            "requiredMorning": new_m,
            "requiredAfternoon": new_a,
            "requiredNight": new_n,
            "requiredEmployees": new_m + new_a + new_n,
            "posts": {
                "morning": build_posts("morning", new_m),
                "afternoon": build_posts("afternoon", new_a),
                "night": build_posts("night", new_n),
            },
        }

        unnamed = sum(1 for shift in updates["posts"].values()
                      for post in shift if not post)
        print(f"  {station_id}  {name}: "
              f"{old_m}/{old_a}/{old_n} -> {new_m}/{new_a}/{new_n} "
              f"(total {updates['requiredEmployees']}, from {source}), "
              f"{unnamed} post(s) left unnamed")

        if not dry_run:
            batch.update(db.collection("stations").document(station_id),
                         updates)
        changed += 1

    if dry_run:
        print(f"\nDry run: {changed} station(s) would change, "
              f"{skipped} skipped.")
        return

    if changed:
        batch.commit()
    print(f"\nMigrated {changed} station(s), {skipped} skipped.")
    print("Next: name the unnamed posts in Edit Station, then regenerate "
          "the schedules you want on the new setup.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="show what would change without writing")
    parser.add_argument("--force", action="store_true",
                        help="re-migrate stations that already have posts")
    args = parser.parse_args()
    migrate(args.dry_run, args.force)
