"""
Pydantic request models for the Special Assignment endpoints.

A "special assignment" is a manual override that pins one employee to one
station for a single ROTATION CYCLE (a calendar month, the same unit
rotation.py already keys its shuffle on). Anything the admin pins is
honoured by every schedule generated inside that month, and stops
applying by itself the moment the month rolls over — the documents are
keyed by cycle, so there is no expiry job to run.

See models/schedule.py for the generator-side request models.
"""

from typing import List, Optional

from pydantic import BaseModel

# Shifts an employee may be pinned to, by employee type. Relievers float
# across morning/afternoon posts by design, so they are pinned to a
# station only — never to a shift.
SHIFTS_BY_TYPE = {
    "regular": {"morning", "afternoon", "night"},
    "headGuard": {"hgDay", "hgNight"},
    "reliever": set(),
}


class SpecialAssignmentEntry(BaseModel):
    employeeId: str
    # None is valid for relievers, and means "keep whatever shift the
    # employee's own record already carries" for everyone else.
    shift: Optional[str] = None


class SpecialAssignmentSaveRequest(BaseModel):
    """Replaces the full set of pins for one station in one cycle.

    The dialog sends the list it wants to end up with rather than
    individual add/remove calls, so a save is idempotent and the admin
    can add, drop and re-shift people in a single commit.
    """
    cycleId: str            # "202607"
    assignments: List[SpecialAssignmentEntry] = []


def validate_shift(employee_type: str, shift: Optional[str]) -> Optional[str]:
    """Returns the shift to store, or raises ValueError.

    Rejecting an impossible pairing here (a head guard pinned to
    "morning", say) matters more than it looks: scheduler.py sorts staff
    into its shift buckets by exact string match and silently ignores
    anyone who fits none of them, so an unvalidated shift would produce a
    guard who is pinned to a station and yet appears nowhere in the
    generated schedule.
    """
    allowed = SHIFTS_BY_TYPE.get(employee_type, set())

    if not allowed:
        # Relievers: a shift is meaningless, so drop it rather than
        # failing the save — the UI doesn't offer one for them.
        return None

    if shift is None:
        raise ValueError(
            f"a {employee_type} must be pinned to one of: "
            f"{', '.join(sorted(allowed))}"
        )

    if shift not in allowed:
        raise ValueError(
            f"shift '{shift}' is not valid for a {employee_type} "
            f"(expected one of: {', '.join(sorted(allowed))})"
        )

    return shift
