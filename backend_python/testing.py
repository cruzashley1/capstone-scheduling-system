"""
testing.py

Standalone test harness for services/scheduler.py. Does NOT touch
Firestore, Firebase, or api.py - it only exercises the pure scheduling
functions with made-up employee IDs, so you can see exactly what a
generated bi-weekly schedule looks like and catch logic errors before
this ever gets wired into a real endpoint.

Run it with:
    python testing.py
"""

from datetime import date
from collections import defaultdict

from models.schedule import ShiftName, build_schedule_period_id
from services.scheduler import generate_station_schedule, RELIEVER_MIN_DAYS, RELIEVER_MAX_DAYS

PERIOD_START = date(2026, 7, 1)  # 1st half of the bi-weekly cycle (day 1-15)


def make_employee_ids(prefix: str, count: int):
    return [f"{prefix}{str(i + 1).zfill(3)}" for i in range(count)]


# ---------------------------------------------------------------------------
# Station definitions straight from schedule.docx
# ---------------------------------------------------------------------------

STATIONS = {
    "STA_MONUMENTO": {
        "name": "Monumento",
        "requirements": {"morning": 8, "afternoon": 8, "night": 3},
        # Reliever pool sized so total capacity (n * 13) comfortably
        # covers the gaps this station will generate - see printed
        # math below for the real number.
        "reliever_count": 3,
    },
    "STA_ABAD_SANTOS": {
        "name": "Abad Santos",
        "requirements": {"morning": 5, "afternoon": 5, "night": 3},
        "reliever_count": 2,
    },
}


def build_roster(station_id: str, reqs: dict, reliever_count: int):
    head_guards = {
        "morning": f"{station_id}_HG_M",
        "night": f"{station_id}_HG_N",
        "substitute": f"{station_id}_HG_SUB",
    }
    regulars_by_shift = {
        ShiftName.MORNING: make_employee_ids(f"{station_id}_REG_AM_", reqs["morning"]),
        ShiftName.AFTERNOON: make_employee_ids(f"{station_id}_REG_PM_", reqs["afternoon"]),
        ShiftName.NIGHT: make_employee_ids(f"{station_id}_REG_NT_", reqs["night"]),
    }
    relievers = make_employee_ids(f"{station_id}_REL_", reliever_count)
    return head_guards, regulars_by_shift, relievers


# ---------------------------------------------------------------------------
# Rule checks - each returns (passed: bool, message: str)
# ---------------------------------------------------------------------------

def check_daily_coverage(station_id, reqs, duties, days):
    """On every day, the number of people covering morning/afternoon/
    night (regular OR reliever standing in) must equal the required
    count - this is the number that matters to the doc, since the
    reliever's whole job is to keep this number constant."""
    failures = []
    by_day_shift = defaultdict(set)
    for duty in duties:
        # Head guards are leadership on top of the station's required
        # headcount, not part of it (per schedule.docx: the substitute
        # HG "isn't part of the station" - same logic applies to the
        # 2 primaries versus the required-employees count).
        if "_HG_" in duty.employeeId:
            continue
        by_day_shift[(duty.workDate, duty.shiftName.value)].add(duty.employeeId)

    for d in days:
        for shift_key, required in reqs.items():
            covering = by_day_shift.get((d, shift_key), set())
            if len(covering) != required:
                failures.append(
                    f"{d} {shift_key}: covered by {len(covering)}, need {required}"
                )
    if failures:
        return False, f"[{station_id}] daily coverage FAILED:\n    " + "\n    ".join(failures[:10])
    return True, f"[{station_id}] daily coverage OK - every morning/afternoon/night hit its required headcount all 15 days"


def check_head_guard_hours(station_id, duties):
    """Each HG primary should log 13 workdays x 12h = 156h; the
    substitute should log exactly 4 workdays x 12h = 48h."""
    hg_days = defaultdict(int)
    for duty in duties:
        if "_HG_" in duty.employeeId:
            hg_days[duty.employeeId] += 1

    problems = []
    for emp_id, days_worked in hg_days.items():
        hours = days_worked * 12
        if emp_id.endswith("_SUB"):
            if hours != 48:
                problems.append(f"{emp_id}: {hours}h (expected 48h)")
        else:
            if hours != 156:
                problems.append(f"{emp_id}: {hours}h (expected 156h)")

    if problems:
        return False, f"[{station_id}] head guard hours FAILED: " + ", ".join(problems)
    return True, f"[{station_id}] head guard hours OK - 156h/156h primaries, 48h substitute"


def check_reliever_range(station_id, duties, reliever_ids):
    days_worked = defaultdict(int)
    for duty in duties:
        if duty.employeeId in reliever_ids:
            days_worked[duty.employeeId] += 1

    problems = []
    for r in reliever_ids:
        n = days_worked.get(r, 0)
        if not (RELIEVER_MIN_DAYS <= n <= RELIEVER_MAX_DAYS):
            problems.append(f"{r}: {n} days (target {RELIEVER_MIN_DAYS}-{RELIEVER_MAX_DAYS})")

    if problems:
        return False, f"[{station_id}] reliever day-count FAILED: " + ", ".join(problems)
    return True, f"[{station_id}] reliever day-count OK - all relievers within {RELIEVER_MIN_DAYS}-{RELIEVER_MAX_DAYS} days"


def check_no_double_booking(station_id, duties):
    seen = defaultdict(list)
    for duty in duties:
        seen[(duty.employeeId, duty.workDate)].append(duty.shiftName.value)

    problems = [f"{emp} on {d}: {shifts}" for (emp, d), shifts in seen.items() if len(shifts) > 1]
    if problems:
        return False, f"[{station_id}] double-booking FAILED: " + ", ".join(problems)
    return True, f"[{station_id}] no employee double-booked on the same day"


def check_reliever_never_night(station_id, duties, reliever_ids):
    violations = [
        f"{d.employeeId} on {d.workDate}"
        for d in duties
        if d.employeeId in reliever_ids and d.shiftName == ShiftName.NIGHT
    ]
    if violations:
        return False, f"[{station_id}] reliever-never-night FAILED: " + ", ".join(violations)
    return True, f"[{station_id}] no reliever ever assigned to a night shift"


# ---------------------------------------------------------------------------
# Main run
# ---------------------------------------------------------------------------

def run_station(station_id: str, config: dict):
    print("=" * 78)
    print(f"STATION: {config['name']}  ({station_id})")
    print("=" * 78)

    head_guards, regulars_by_shift, relievers = build_roster(
        station_id, config["requirements"], config["reliever_count"]
    )
    period_id = build_schedule_period_id(station_id, PERIOD_START)

    result = generate_station_schedule(
        station_id=station_id,
        schedule_period_id=period_id,
        period_start=PERIOD_START,
        head_guards=head_guards,
        regulars_by_shift=regulars_by_shift,
        reliever_employee_ids=relievers,
    )

    duties = result["duty_assignments"]
    day_offs = result["day_offs"]
    engine_warnings = result["warnings"]

    print(f"\nGenerated {len(duties)} duty assignments and {len(day_offs)} day-offs "
          f"for a {config['requirements']} station over 15 days.\n")

    days = [PERIOD_START.fromordinal(PERIOD_START.toordinal() + i) for i in range(15)]

    checks = [
        check_daily_coverage(station_id, config["requirements"], duties, days),
        check_head_guard_hours(station_id, duties),
        check_reliever_range(station_id, duties, relievers),
        check_no_double_booking(station_id, duties),
        check_reliever_never_night(station_id, duties, relievers),
    ]

    print("--- Rule checks ---")
    all_passed = True
    for passed, message in checks:
        print(("✅ " if passed else "❌ ") + message)
        all_passed = all_passed and passed

    if engine_warnings:
        print("\n--- Engine warnings (things the algorithm flagged on its own) ---")
        for w in engine_warnings:
            print("⚠️  " + w)

    print(f"\n--- Sample day (day 6: {days[5]}) full roster ---")
    for duty in sorted(duties, key=lambda d: (d.shiftName.value, d.employeeId)):
        if duty.workDate == days[5]:
            tag = f" (sub for {duty.coveringForEmployeeId})" if duty.isSubstitute else ""
            print(f"  {duty.shiftName.value:10s} {duty.employeeId}{tag}")

    return all_passed


if __name__ == "__main__":
    overall = True
    for station_id, config in STATIONS.items():
        overall = run_station(station_id, config) and overall
        print()

    print("=" * 78)
    print("OVERALL RESULT:", "✅ ALL CHECKS PASSED" if overall else "❌ SOME CHECKS FAILED - see above")
    print("=" * 78)