"""
services/scheduler.py

Firestore-free scheduling engine for a single station's bi-weekly
(15-day) duty roster. Implements the 3-phase build order from your
schedule.docx:

    Phase 1 - Head Guards    (2 primaries + 1 substitute)
    Phase 2 - Regular employees (fixed shift/station)
    Phase 3 - Relievers      (float into regular day-off gaps,
                               morning/afternoon only, never night)

This module never touches Firestore - it takes plain employee dicts in
and returns DutyAssignmentDocument / DayOffDocument objects (from
models/schedule.py) out. That's what makes it unit-testable in
testing.py before it's ever wired into an api.py endpoint.

==========================================================================
ASSUMPTIONS MADE - please confirm or correct these, since schedule.docx
didn't spell them out:

1. Head guard 12h shifts = HG_MORNING (0500-1700) and HG_NIGHT
   (1700-0500), together covering the full 24h. That matches "2 head
   guards responsible for morning and night" + "12 hours x 13 days,
   2 day off" = 156h each, and 12h x 4 substitute-days = 48h.

2. Regular employees also work 13 days / 2 days off per 15-day period.
   Your doc states 13/2 explicitly for head guards only - I mirrored it
   for regulars since no other number was given anywhere.

3. Relievers only ever fill MORNING and AFTERNOON gaps, per your "strict
   rule" that they never work night. Night-shift day-offs are therefore
   NOT auto-filled by this engine - they show up in `warnings` so you can
   decide how those get covered (an extra night regular on overtime? a
   bigger night headcount buffer?). This is the single biggest open
   question in the whole design - see the "Reliever engine" section of
   testing.py's output.

4. Reliever day-off count isn't specified. Relievers get day-offs only
   as needed to land inside your 10-13 total-worked-days target, not on
   a fixed schedule like head guards/regulars.

5. This module schedules ONE station's ONE 15-day period at a time. The
   monthly rotation/shuffle engine (moving employees between stations,
   guaranteeing >=2 "stayed" per station, respecting the group-1/group-2/
   group-3 preferred-station split from your diagram) is a separate,
   higher-level piece not built yet - flagged at the end of testing.py.
==========================================================================
"""

from datetime import date, timedelta
from typing import Dict, List, Tuple

from models.schedule import (
    ShiftName,
    StationRole,
    AssignmentSource,
    DutyAssignmentDocument,
    DayOffDocument,
    build_duty_assignment_id,
    build_day_off_id,
)

PERIOD_LENGTH_DAYS = 15
HEAD_GUARD_DAYS_OFF = 2
REGULAR_DAYS_OFF = 2
RELIEVER_MIN_DAYS = 10
RELIEVER_MAX_DAYS = 13


def period_dates(period_start: date) -> List[date]:
    return [period_start + timedelta(days=i) for i in range(PERIOD_LENGTH_DAYS)]


def _days_off_for(all_days: List[date], person_index: int, count: int = 2, spread: int = 7) -> List[date]:
    """Pick day-offs for one person out of a roster, using a unique
    offset per person_index so different people's off-days land on
    different days instead of clustering (a real bug the first version
    of this function had - see testing.py run history). The `spread`
    gap between an individual's own off-days keeps their two days off
    from sitting back-to-back."""
    n = len(all_days)
    first = person_index % n
    chosen = {first}
    idx = first
    while len(chosen) < count:
        idx = (idx + spread) % n
        chosen.add(idx)
    return sorted(all_days[i] for i in chosen)


# ---------------------------------------------------------------------------
# Phase 1: Head Guards
# ---------------------------------------------------------------------------

def schedule_head_guards(
    station_id: str,
    schedule_period_id: str,
    period_start: date,
    hg_morning_id: str,
    hg_night_id: str,
    hg_substitute_id: str,
) -> Tuple[List[DutyAssignmentDocument], List[DayOffDocument], List[str]]:
    """Builds the head-guard roster for one station/period.

    Returns (duty_assignments, day_offs, warnings).
    """
    days = period_dates(period_start)
    duties: List[DutyAssignmentDocument] = []
    day_offs: List[DayOffDocument] = []
    warnings: List[str] = []

    morning_offs = set(_days_off_for(days, person_index=2, count=HEAD_GUARD_DAYS_OFF))
    night_offset = 2 + len(days) // 2  # start on the opposite side of the period
    night_offs = set(_days_off_for(days, person_index=night_offset, count=HEAD_GUARD_DAYS_OFF))
    # Guaranteed collision-free rather than just "probably far enough
    # apart": if the two sets still overlap, nudge the night offset by
    # one day at a time until they don't (bounded by len(days) so it
    # can't loop forever).
    nudge = 0
    while morning_offs & night_offs and nudge < len(days):
        nudge += 1
        night_offs = set(_days_off_for(days, person_index=night_offset + nudge, count=HEAD_GUARD_DAYS_OFF))
    offs = {hg_morning_id: morning_offs, hg_night_id: night_offs}

    if offs[hg_morning_id] & offs[hg_night_id]:
        warnings.append(
            f"Station {station_id}: HG_MORNING and HG_NIGHT day-offs collide on "
            f"{sorted(offs[hg_morning_id] & offs[hg_night_id])} - the substitute "
            f"can only cover one primary at a time."
        )

    for primary_id, role, shift in (
        (hg_morning_id, StationRole.HG_MORNING_PRIMARY, ShiftName.MORNING),
        (hg_night_id, StationRole.HG_NIGHT_PRIMARY, ShiftName.NIGHT),
    ):
        for d in days:
            if d in offs[primary_id]:
                day_offs.append(DayOffDocument(
                    id=build_day_off_id(primary_id, d),
                    schedulePeriodId=schedule_period_id,
                    employeeId=primary_id,
                    offDate=d,
                    coveredByEmployeeId=hg_substitute_id,
                ))
                duties.append(DutyAssignmentDocument(
                    id=build_duty_assignment_id(hg_substitute_id, d),
                    schedulePeriodId=schedule_period_id,
                    employeeId=hg_substitute_id,
                    stationId=station_id,
                    shiftName=shift,
                    workDate=d,
                    isSubstitute=True,
                    coveringForEmployeeId=primary_id,
                    source=AssignmentSource.AUTO_GENERATED,
                ))
            else:
                duties.append(DutyAssignmentDocument(
                    id=build_duty_assignment_id(primary_id, d),
                    schedulePeriodId=schedule_period_id,
                    employeeId=primary_id,
                    stationId=station_id,
                    shiftName=shift,
                    workDate=d,
                    source=AssignmentSource.AUTO_GENERATED,
                ))

    sub_worked_days = sum(1 for do in day_offs)
    if sub_worked_days != 4:
        warnings.append(
            f"Station {station_id}: HG substitute worked {sub_worked_days} days, "
            f"expected exactly 4 (2 offs x 2 primaries) for the 48h rule."
        )

    return duties, day_offs, warnings


# ---------------------------------------------------------------------------
# Phase 2: Regular employees
# ---------------------------------------------------------------------------

def schedule_regular_employees(
    station_id: str,
    schedule_period_id: str,
    period_start: date,
    shift_name: ShiftName,
    regular_employee_ids: List[str],
) -> Tuple[List[DutyAssignmentDocument], List[DayOffDocument], Dict[date, List[str]], List[str]]:
    """Builds the fixed roster for one shift (morning/afternoon/night) at
    one station. Each regular employee gets REGULAR_DAYS_OFF days off,
    staggered so the station isn't short-staffed by more than one person
    on any given day.

    Returns (duty_assignments, day_offs, gaps_by_date, warnings), where
    gaps_by_date maps a date -> list of employee_ids who are off that day
    (i.e. exactly what phase 3 / relievers need to fill).
    """
    days = period_dates(period_start)
    duties: List[DutyAssignmentDocument] = []
    day_offs: List[DayOffDocument] = []
    gaps_by_date: Dict[date, List[str]] = {d: [] for d in days}
    warnings: List[str] = []

    for i, emp_id in enumerate(regular_employee_ids):
        off_days = set(_days_off_for(days, person_index=i, count=REGULAR_DAYS_OFF))
        for d in days:
            if d in off_days:
                day_offs.append(DayOffDocument(
                    id=build_day_off_id(emp_id, d),
                    schedulePeriodId=schedule_period_id,
                    employeeId=emp_id,
                    offDate=d,
                ))
                gaps_by_date[d].append(emp_id)
            else:
                duties.append(DutyAssignmentDocument(
                    id=build_duty_assignment_id(emp_id, d),
                    schedulePeriodId=schedule_period_id,
                    employeeId=emp_id,
                    stationId=station_id,
                    shiftName=shift_name,
                    workDate=d,
                    source=AssignmentSource.AUTO_GENERATED,
                ))

    n = max(len(regular_employee_ids), 1)
    for d, off_list in gaps_by_date.items():
        if len(off_list) > max(1, n // 4):
            warnings.append(
                f"Station {station_id} {shift_name.value} on {d}: {len(off_list)} of "
                f"{n} regulars off at once ({off_list}) - may need more than one "
                f"reliever covering that shift that day."
            )

    return duties, day_offs, gaps_by_date, warnings


# ---------------------------------------------------------------------------
# Phase 3: Relievers
# ---------------------------------------------------------------------------

def schedule_relievers(
    station_id: str,
    schedule_period_id: str,
    gaps_by_shift: Dict[ShiftName, Dict[date, List[str]]],
    reliever_employee_ids: List[str],
) -> Tuple[List[DutyAssignmentDocument], List[DayOffDocument], List[str]]:
    """Fills MORNING/AFTERNOON regular-day-off gaps with relievers, never
    NIGHT (per the strict rule). Balances load across relievers so each
    one lands between RELIEVER_MIN_DAYS and RELIEVER_MAX_DAYS worked.

    `gaps_by_shift` = {ShiftName.MORNING: gaps_by_date, ShiftName.AFTERNOON: gaps_by_date, ...}
    (as returned by schedule_regular_employees for each shift).

    Returns (duty_assignments, day_offs, warnings).
    """
    duties: List[DutyAssignmentDocument] = []
    day_offs: List[DayOffDocument] = []
    warnings: List[str] = []

    if not reliever_employee_ids:
        total_gaps = sum(
            len(covering) for shift, gaps in gaps_by_shift.items()
            if shift != ShiftName.NIGHT
            for covering in gaps.values()
        )
        if total_gaps:
            warnings.append(
                f"Station {station_id}: {total_gaps} morning/afternoon gaps but no "
                f"relievers assigned to this station."
            )
        return duties, day_offs, warnings

    worked_days: Dict[str, int] = {r: 0 for r in reliever_employee_ids}
    assigned_today: Dict[date, set] = {}

    # Flatten every coverable (date, shift, covering_employee_id) gap and
    # walk through it in date order so early days aren't starved.
    flat_gaps: List[Tuple[date, ShiftName, str]] = []
    for shift, gaps_by_date in gaps_by_shift.items():
        if shift == ShiftName.NIGHT:
            continue  # reliever strict rule - never night
        for d, covering_list in gaps_by_date.items():
            for covering_emp_id in covering_list:
                flat_gaps.append((d, shift, covering_emp_id))
    flat_gaps.sort(key=lambda g: g[0])

    # A night regular's day-off leaves a hole nobody in this phase can
    # fill, because relievers never work nights. That used to be a bare
    # `continue`: the post went unmanned, the schedule published, and
    # nothing anywhere said so — the one outcome this engine is not
    # allowed to produce, since it never refuses a staffing problem and
    # a note is therefore the ONLY way an admin learns of one.
    #
    # Said once for the station rather than once per date. Three night
    # regulars on a 15-day period generate a run of these, and fifteen
    # near-identical lines would bury the morning and afternoon warnings
    # that need individual attention.
    night_gaps = gaps_by_shift.get(ShiftName.NIGHT) or {}
    short_dates = sorted(d for d, covering in night_gaps.items() if covering)
    if short_dates:
        shown = ", ".join(str(d) for d in short_dates[:5])
        more = f" (+{len(short_dates) - 5} more)" if len(short_dates) > 5 else ""
        warnings.append(
            f"Station {station_id}: the night shift is short on "
            f"{len(short_dates)} of the period's days — {shown}{more}. "
            f"Relievers never cover nights, so a night regular's day-off "
            f"can only be absorbed by another night regular: this station "
            f"needs more night regulars than its required headcount, not "
            f"more relievers."
        )

    for d, shift, covering_emp_id in flat_gaps:
        assigned_today.setdefault(d, set())
        # pick the reliever with the fewest worked days so far who isn't
        # already working this station on this date and hasn't hit the cap
        candidates = [
            r for r in reliever_employee_ids
            if r not in assigned_today[d] and worked_days[r] < RELIEVER_MAX_DAYS
        ]
        if not candidates:
            warnings.append(
                f"Station {station_id}: no available reliever for {shift.value} on "
                f"{d} (covering {covering_emp_id}) - all relievers maxed out or "
                f"already working that day."
            )
            continue

        chosen = min(candidates, key=lambda r: worked_days[r])
        worked_days[chosen] += 1
        assigned_today[d].add(chosen)

        duties.append(DutyAssignmentDocument(
            id=build_duty_assignment_id(chosen, d),
            schedulePeriodId=schedule_period_id,
            employeeId=chosen,
            stationId=station_id,
            shiftName=shift,
            workDate=d,
            isSubstitute=True,
            coveringForEmployeeId=covering_emp_id,
            source=AssignmentSource.AUTO_GENERATED,
        ))

    for r, days_worked in worked_days.items():
        if days_worked == 0:
            warnings.append(f"Station {station_id}: reliever {r} was never used this period.")
        elif days_worked < RELIEVER_MIN_DAYS:
            warnings.append(
                f"Station {station_id}: reliever {r} only worked {days_worked} days "
                f"(target {RELIEVER_MIN_DAYS}-{RELIEVER_MAX_DAYS})."
            )

    return duties, day_offs, warnings


# ---------------------------------------------------------------------------
# Orchestration: run all 3 phases for one station
# ---------------------------------------------------------------------------

def generate_station_schedule(
    station_id: str,
    schedule_period_id: str,
    period_start: date,
    head_guards: Dict[str, str],       # {"morning": id, "night": id, "substitute": id}
    regulars_by_shift: Dict[ShiftName, List[str]],
    reliever_employee_ids: List[str],
) -> Dict:
    """Runs phases 1-3 in order for a single station and returns
    everything together, plus a combined warnings list."""
    all_duties: List[DutyAssignmentDocument] = []
    all_day_offs: List[DayOffDocument] = []
    all_warnings: List[str] = []

    hg_duties, hg_offs, hg_warnings = schedule_head_guards(
        station_id, schedule_period_id, period_start,
        head_guards["morning"], head_guards["night"], head_guards["substitute"],
    )
    all_duties += hg_duties
    all_day_offs += hg_offs
    all_warnings += hg_warnings

    gaps_by_shift: Dict[ShiftName, Dict[date, List[str]]] = {}
    for shift, emp_ids in regulars_by_shift.items():
        reg_duties, reg_offs, gaps, reg_warnings = schedule_regular_employees(
            station_id, schedule_period_id, period_start, shift, emp_ids,
        )
        all_duties += reg_duties
        all_day_offs += reg_offs
        all_warnings += reg_warnings
        gaps_by_shift[shift] = gaps

    rel_duties, rel_offs, rel_warnings = schedule_relievers(
        station_id, schedule_period_id, gaps_by_shift, reliever_employee_ids,
    )
    all_duties += rel_duties
    all_day_offs += rel_offs
    all_warnings += rel_warnings

    return {
        "duty_assignments": all_duties,
        "day_offs": all_day_offs,
        "warnings": all_warnings,
    }