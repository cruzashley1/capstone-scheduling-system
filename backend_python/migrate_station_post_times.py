"""
One-time migration: give every station's posts a duty window.

Posts used to have no times of their own — every guard on a shift was
shown that shift's hours, looked up from the shift name. Now each slot
carries the window it is manned for, staggered so the station keeps cover
while guards rotate off:

    MORNING (base 0500H - 1400H)
      1. Head Guard     0500H - 1700H   <- fixed 12h duty, off the ladder
      2. SW Platform    0500H - 1400H
      3. SE Platform    0500H - 1400H
      4. Roving         0700H - 1600H
      5. Ladder         0700H - 1600H

Regular posts are handed out in PAIRS: the first two sit on the shift's
base window, the next two start two hours later, and so on. NIGHT is not
staggered — it runs the
night head guard plus roving guards, so every night post keeps the base
window. station_posts.py owns the rule; this script just applies it.

Two shift windows also change here, which is why this is a migration
rather than a pure back-fill:

    afternoon  1400H - 2330H  ->  1400H - 2300H
    night      2100H - 0500H  ->  2100H - 0600H

Existing SCHEDULES are not touched. A schedule generated before this
carries no times on its entries and the app falls back to the shift's
base window for it, exactly as it behaved before — so published rosters
keep reading the way their guards were told. Regenerate a period to put
it on the staggered times.

Re-runnable: stations that already carry a `postTimes` map are skipped
unless --force is passed. Running it with --force is safe — it re-derives
every `auto` slot from the ladder and leaves hand-pinned windows alone.

Usage (from backend_python/):
    python migrate_station_post_times.py            # apply
    python migrate_station_post_times.py --dry-run  # show what would change
    python migrate_station_post_times.py --force    # redo already-migrated
"""

import argparse

# firebase_init runs the AVG/TLS workaround before it touches
# firebase_admin, so importing it is all this script needs.
import firebase_init
import station_posts


def _describe(shift_key, posts, windows):
    """One line per slot, for the console."""
    lines = []
    for index, (post, window) in enumerate(zip(posts, windows), start=1):
        start = station_posts.parse_hhmm(window["start"])
        end = station_posts.parse_hhmm(window["end"])
        if not window.get("auto", True):
            flag = "  [pinned]"
        elif (post != station_posts.HEAD_GUARD
                and station_posts.overruns_next_shift(shift_key, start)):
            flag = "  <- starts inside the next shift"
        else:
            flag = ""
        lines.append(
            f"        {index}. {(post or '(unnamed)'):<16}"
            f"{station_posts.format_military(start)} - "
            f"{station_posts.format_military(end)}{flag}")
    return lines


def migrate(dry_run, force, verbose):
    db = firebase_init.get_db()

    stations = [doc.to_dict() for doc in db.collection("stations").stream()]
    stations.sort(key=lambda s: s.get("id", ""))
    if not stations:
        raise SystemExit("No stations found in Firestore.")

    changed = 0
    skipped = 0
    overrunning = 0
    batch = db.batch()

    for station in stations:
        station_id = station.get("id")
        name = (station.get("name") or "").strip()

        if station.get("postTimes") and not force:
            skipped += 1
            print(f"  {station_id}  {name}: already has post times, skipped")
            continue

        posts = station.get("posts") or {}
        if not any(posts.get(key) for key in station_posts.SHIFT_KEYS):
            skipped += 1
            print(f"  {station_id}  {name}: no posts configured — run "
                  f"migrate_station_posts.py first, or set it up in "
                  f"Edit Station")
            continue

        # Existing windows are fed back in so a --force run keeps whatever
        # the admin pinned by hand and only re-derives the auto slots.
        existing = station.get("postTimes") or {}
        post_times = {
            key: station_posts.normalize_post_times(
                key, posts.get(key) or [], existing.get(key) or [])
            for key in station_posts.SHIFT_KEYS
        }

        station_overruns = sum(
            1
            for key in station_posts.SHIFT_KEYS
            for post, window in zip(posts.get(key) or [], post_times[key])
            if post != station_posts.HEAD_GUARD
            and station_posts.overruns_next_shift(
                key, station_posts.parse_hhmm(window["start"]))
        )
        overrunning += station_overruns

        slots = sum(len(post_times[key]) for key in station_posts.SHIFT_KEYS)
        note = (f", {station_overruns} starting inside the next shift"
                if station_overruns else "")
        print(f"  {station_id}  {name}: {slots} slot(s) timed{note}")

        if verbose:
            for key in station_posts.SHIFT_KEYS:
                if not posts.get(key):
                    continue
                print(f"      {key}")
                for line in _describe(key, posts[key], post_times[key]):
                    print(line)

        if not dry_run:
            batch.update(db.collection("stations").document(station_id),
                         {"postTimes": post_times})
        changed += 1

    if dry_run:
        print(f"\nDry run: {changed} station(s) would change, "
              f"{skipped} skipped.")
    else:
        if changed:
            batch.commit()
        print(f"\nTimed {changed} station(s), {skipped} skipped.")

    if overrunning:
        print(f"\n{overrunning} post(s) now start after the following shift "
              f"has already come on — a shift with many posts climbs that "
              f"far. Edit Station flags these; pin an earlier time there if "
              f"it isn't what you want.")
    if not dry_run and changed:
        print("Existing schedules are unchanged and still read their "
              "shift's base hours. Regenerate a period to put it on the "
              "staggered times.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="show what would change without writing")
    parser.add_argument("--force", action="store_true",
                        help="re-derive stations that already have times")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="print every slot's window")
    args = parser.parse_args()
    migrate(args.dry_run, args.force, args.verbose)
