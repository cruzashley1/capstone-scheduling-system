"""
Finds attendance reports that could not be filed under today's rules and
optionally deletes them.

These are leftovers from the head-guard reporting bug: when a head guard
was missing from the roster the app fell back to offering EVERY shift, so
a night head guard could file Morning and Afternoon reports — and, because
the station was resolved from their permanent `assignedStation` rather
than the schedule, often against a station they no longer worked at. Both
holes are closed (api.py's _assert_shift_is_reportable and
get_station_overview), but reports already written stay until removed.

A report is invalid when the head guard's own duty does not cover the
shift it was filed for:
    hgDay   -> Morning, Afternoon
    hgNight -> Night
Floating substitute head guards have no assignedShift and are rostered
under whichever post they stand in for, so their reports are left alone.

Runs against whatever firebase_init is configured for (USE_MOCK_DB=1
serves mock_data/*.json). Dry run by default:

    python cleanup_invalid_reports.py            # report only
    python cleanup_invalid_reports.py --delete   # actually remove them
"""

import sys

from firebase_init import get_db

ALLOWED_SHIFTS = {
    "hgDay": {"Morning", "Afternoon"},
    "hgNight": {"Night"},
}


def find_invalid(db):
    """Returns (doc_id, reason) for every report that breaks the rule."""
    employees = {}
    for doc in db.collection("employees").stream():
        data = doc.to_dict() or {}
        employees[data.get("id") or doc.id] = data

    invalid = []
    for doc in db.collection("attendance_reports").stream():
        report = doc.to_dict() or {}
        hg_id = report.get("headGuardId")
        title = (report.get("shiftTitle") or "").strip()
        shift = title.replace("Shift", "").strip()

        assigned = (employees.get(hg_id) or {}).get("assignedShift")
        allowed = ALLOWED_SHIFTS.get(assigned)
        if allowed is None:
            continue  # floating substitute, or employee no longer exists
        if shift in allowed:
            continue

        covers = ("Night only" if assigned == "hgNight"
                  else "Morning and Afternoon only")
        invalid.append((
            doc.id,
            f"{hg_id} ({assigned}, covers {covers}) filed "
            f"{title or '(no shift)'} for {report.get('date')} "
            f"at {report.get('station')}",
        ))
    return sorted(invalid)


def main():
    delete = "--delete" in sys.argv
    db = get_db()
    if db is None:
        print("Database not initialized.")
        return 1

    invalid = find_invalid(db)
    if not invalid:
        print("No invalid attendance reports found.")
        return 0

    print(f"{len(invalid)} invalid attendance report(s):\n")
    for doc_id, reason in invalid:
        print(f"  {doc_id}")
        print(f"      {reason}")

    if not delete:
        print("\nDry run — nothing deleted. Re-run with --delete to remove them.")
        return 0

    for doc_id, _ in invalid:
        db.collection("attendance_reports").document(doc_id).delete()
    print(f"\nDeleted {len(invalid)} report(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
