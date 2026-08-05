"""
Firestore data model for the Schedulr scheduling engine.

Your actual stack is Flutter -> FastAPI -> Firestore (confirmed from
api.py / main.py), NOT a SQL database - this replaces the earlier
SQLAlchemy draft, which wrongly assumed tables/foreign keys/unique
constraints that don't exist in Firestore.

Two corrections from our earlier discussion, based on your plan doc
and existing api.py:
  1. Preferred stations are OPTIONAL, not a minimum of 5.
     EmployeeCreateRequest already defaults preferredStations to [].
  2. Station capacity needs a PER-SHIFT breakdown (morning/afternoon/
     night), not one flat requiredEmployees number - your Monumento /
     Abad Santos example needs this to generate shifts later.
     NOTE: create_station() and StationCreateRequest in api.py will
     need a small update to match this - not changed in this file.

Style note: field names stay camelCase to match what's already in
api.py / Firestore (preferredStations, isActive, dateJoined, etc.)
rather than switching to snake_case.

--------------------------------------------------------------------
COLLECTIONS ALREADY LIVE (from api.py) - shown for reference only,
not redefined here:
  employees/{username}
  stations/{stationId}
  users/{username}
  counters/{counterName}

NEW COLLECTIONS FOR THE SCHEDULING ENGINE:
  rotation_cycles/{cycleId}
  station_rotation_assignments/{assignmentId}
  schedule_periods/{periodId}
  duty_assignments/{dutyId}
  day_offs/{dayOffId}

--------------------------------------------------------------------
KEY DESIGN CHOICE - deterministic document IDs instead of DB constraints.

Firestore can't enforce "one shift per employee per day" the way a SQL
UniqueConstraint can. Instead, the ID itself is built from the fields
that must be unique, so a second write to the same ID just overwrites
the first instead of creating a duplicate:

  rotation_cycles:              "{year}{month:02d}"        -> "202607"
  schedule_periods:              "{stationId}_{startDate}"  -> "STA001_2026-07-01"
  station_rotation_assignments:  "{cycleId}_{employeeId}"   -> "202607_CLA001"
  duty_assignments:              "{employeeId}_{workDate}"  -> "CLA001_2026-07-03"
  day_offs:                      "{employeeId}_{offDate}"   -> "CLA001_2026-07-05"

--------------------------------------------------------------------
RULES FIRESTORE CANNOT ENFORCE - these must be checked in your FastAPI
service functions before writing, not in this file:
  - At least 2 employees with stayed=True per station per rotation cycle
  - Reliever total working days should land in the 10-13 range
  - Reliever is never assigned to the "night" shiftName
  - Head guard station only ever has 2 primaries + 1 substitute at a time

--------------------------------------------------------------------
FIRESTORE INDEXES YOU'LL NEED BEFORE PHASE 3 (Head Guard scheduler):
  - Composite index on duty_assignments: (stationId, workDate)
      -> needed to pull "everyone working at Station X between date A and B"
  - Composite index on duty_assignments: (employeeId, workDate)
      -> needed to pull "this employee's full schedule for a period"
  Firestore will actually throw a "requires an index" error with a
  direct console link the first time you run a query that needs one -
  that's normal, just click the link it gives you.
"""

from datetime import date, datetime
from enum import Enum
from typing import List, Optional

from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class ShiftName(str, Enum):
    MORNING = "morning"        # 05:00 - 14:00 (early-start variant: 04:30)
    AFTERNOON = "afternoon"    # 14:00 - 23:30
    NIGHT = "night"            # 21:00 - 05:00


class StationRole(str, Enum):
    """
    An employee's function *within a specific station* for the current
    rotation cycle - independent of their global employee `type`
    (regular / reliever / headGuard already used in api.py). E.g. a
    headGuard's StationRole says whether they're one of the 2 fixed
    primaries or the 3rd, not-station-counted substitute.
    """
    HG_MORNING_PRIMARY = "hg_morning_primary"   # fixed, 156h/cycle
    HG_NIGHT_PRIMARY = "hg_night_primary"       # fixed, 156h/cycle
    HG_SUBSTITUTE = "hg_substitute"             # covers HG day-offs only, 48h/cycle
    REGULAR_FIXED = "regular_fixed"
    RELIEVER_FLOAT = "reliever_float"           # AM/PM only, never night


class AssignmentSource(str, Enum):
    AUTO_GENERATED = "auto_generated"
    MANUAL_OVERRIDE = "manual_override"


# ---------------------------------------------------------------------------
# stations/{stationId}  -- proposed updated shape (per-shift breakdown)
# ---------------------------------------------------------------------------

class StationShiftRequirements(BaseModel):
    morning: int
    afternoon: int
    night: int

    @property
    def total(self) -> int:
        return self.morning + self.afternoon + self.night


class StationDocument(BaseModel):
    """
    Proposed replacement for the current flat `requiredEmployees: int`.
    Migration note: existing station docs only have the old flat field,
    so you'll want either a one-time migration script or a fallback in
    your read code when you switch over.
    """
    id: str
    name: str
    requiredEmployees: StationShiftRequirements
    group: Optional[int] = None   # 1, 2, or 3 - matches your rotation-group split
    isActive: bool = True


# ---------------------------------------------------------------------------
# rotation_cycles/{cycleId}
# ---------------------------------------------------------------------------

class RotationCycleDocument(BaseModel):
    id: str                  # "{year}{month:02d}" e.g. "202607"
    monthStart: date         # first day of the month
    createdAt: Optional[datetime] = None


def build_rotation_cycle_id(month_start: date) -> str:
    return f"{month_start.year}{month_start.month:02d}"


# ---------------------------------------------------------------------------
# station_rotation_assignments/{assignmentId}
# ---------------------------------------------------------------------------

class StationRotationAssignmentDocument(BaseModel):
    id: str                   # "{cycleId}_{employeeId}"
    rotationCycleId: str
    stationId: str
    employeeId: str
    stationRole: StationRole
    stayed: bool = False      # True = did NOT rotate away this cycle


def build_rotation_assignment_id(cycle_id: str, employee_id: str) -> str:
    return f"{cycle_id}_{employee_id}"


# ---------------------------------------------------------------------------
# schedule_periods/{periodId}
# ---------------------------------------------------------------------------

class SchedulePeriodDocument(BaseModel):
    id: str                   # "{stationId}_{startDate}"
    rotationCycleId: str
    stationId: str
    startDate: date
    endDate: date              # startDate + 14 days


def build_schedule_period_id(station_id: str, start_date: date) -> str:
    return f"{station_id}_{start_date.isoformat()}"


# ---------------------------------------------------------------------------
# duty_assignments/{dutyId}
# ---------------------------------------------------------------------------

class DutyAssignmentDocument(BaseModel):
    id: str                    # "{employeeId}_{workDate}"
    schedulePeriodId: str
    employeeId: str
    stationId: str
    shiftName: ShiftName
    workDate: date
    isEarlyStart: bool = False         # the 04:30 variant
    isSubstitute: bool = False
    coveringForEmployeeId: Optional[str] = None
    source: AssignmentSource = AssignmentSource.AUTO_GENERATED
    isLocked: bool = False             # True once manually overridden


def build_duty_assignment_id(employee_id: str, work_date: date) -> str:
    return f"{employee_id}_{work_date.isoformat()}"


# ---------------------------------------------------------------------------
# day_offs/{dayOffId}
# ---------------------------------------------------------------------------

class DayOffDocument(BaseModel):
    id: str                     # "{employeeId}_{offDate}"
    schedulePeriodId: str
    employeeId: str
    offDate: date
    coveredByEmployeeId: Optional[str] = None


# ---------------------------------------------------------------------------
# Request model for POST /schedules/generate (used by api.py / scheduler.py,
# which store one denormalized doc per station in `schedules/` — the
# normalized collections above are reserved for the later rotation engine).
# ---------------------------------------------------------------------------

class ScheduleGenerateRequest(BaseModel):
    group: int          # 1, 2 or 3 (station groups 1-8 / 9-17 / 18-25)
    startDate: str      # "YYYY-MM-DD", first day of the 15-day period
    overwrite: bool = False  # replace an existing overlapping schedule
    rotate: bool = True      # apply the monthly station rotation (rotation.py)

    # Single-station generation. When set, the whole group is still worked
    # out in memory (rotation placement, the shared reliever pool and the
    # floating head-guard substitutes are group-wide facts) but only this
    # station's document is saved, and only its own overlapping schedule
    # is replaced. Sibling stations keep whatever they already have.
    # `group` is ignored when this is set — it's derived from the station.
    stationId: Optional[str] = None


class SchedulePostUpdateRequest(BaseModel):
    """PUT /schedules/{id}/posts — renames one guard's post across the
    whole schedule (their own entries + entries covering their day-offs).
    How the admin clears the Undefined placeholders before publishing."""
    employeeId: str
    post: str           # e.g. "SW Platform", "SE Platform", "Roving", "Ladder"


class ScheduleEmployeeAddRequest(BaseModel):
    """POST /schedules/{id}/employees — manually rosters one guard onto an
    already-generated schedule, for the gaps the generator leaves behind
    (a station short a body, a late transfer, a guard the pool missed).

    The guard is given an own-duty entry on every day of the period except
    `offDates`. Only valid on unpublished schedules — a published one has
    already been announced to its guards, so it must be unpublished first.
    """
    employeeId: str
    shift: str               # "Morning"|"Afternoon"|"Night"|"HG Day"|"HG Night"
    post: str                # forced to "Head Guard" on the HG shifts
    offDates: List[str] = []  # ISO "YYYY-MM-DD", must fall inside the period


class ScheduleAssignmentUpdateRequest(BaseModel):
    """PUT /schedules/{id}/assignment — rewrites one roster row of a
    generated schedule: who holds it, the post they man, the window they
    man it for, their day-offs, and who relieves them on those days.

    This is what Schedule Detail's Edit Assignment dialog saves. It is a
    FULL statement of the row: every field left null keeps whatever the
    row already has, and `relieverId: null` means "nobody relieves this
    guard", not "leave the reliever alone".

    The row's shift decides which roles are legal on either side, and the
    server re-checks all of it — the dialog only filters the pickers.
    """
    employeeId: str                       # who holds the row right now
    newEmployeeId: Optional[str] = None   # swap target; null = keep them
    post: Optional[str] = None            # ignored on the HG rows
    timeIn: Optional[str] = None          # "HH:MM" / "0500" / "0500H"
    timeOut: Optional[str] = None
    offDates: Optional[List[str]] = None  # null = keep the current ones
    relieverId: Optional[str] = None      # null = no reliever on this row


def build_day_off_id(employee_id: str, off_date: date) -> str:
    return f"{employee_id}_{off_date.isoformat()}"