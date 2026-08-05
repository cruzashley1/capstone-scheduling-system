"""
Leave rules engine — the one place every leave rule is decided.

A leave record lives in `leave_requests` and reaches that collection two
ways: filed by an employee from the guard app, or recorded by the admin
from Employee Details. Once approved it keeps the employee off the
roster for its whole date range (see scheduler.load_leaves), and a leave
long enough to swallow a generated period takes their post off them for
it — another regular holds it, rather than a string of relievers filling
in day by day (scheduler._excuse_long_leave).

The rules, all enforced here rather than scattered through api.py:

  * DURATION — every leave type carries its own cap (LEAVE_TYPES). An
    employee can never file over the cap; only the admin can create an
    over-cap leave, and only with a supervisor endorsement recorded on
    the document.
  * LEAD TIME — an employee's leave must start at least MIN_LEAD_DAYS
    ahead AND after the last day any schedule already covers for their
    group. The admin's own form skips the lead time (they are recording
    something already agreed) but still sees the conflicts.
  * CONFLICT — an employee may only ask for days no schedule covers yet.
    The admin MAY record leave over published duties; those duties are
    returned by affected_duties() so they can be handed to the existing
    Find Replacement flow instead of quietly going unmanned.
  * QUOTA — LEAVES_PER_YEAR open (pending or approved) leaves per
    calendar year, counted by the leave's start date.
  * COOLDOWN — COOLDOWN_MONTHS measured from the END date of the last
    approved leave: the clock starts when they return to work, so a long
    leave can't be used to shorten the wait for the next one.

Anything the admin overrides is recorded on the document together with
the supervisor who endorsed it, so the leave report can always show who
authorised what.
"""

import calendar
from datetime import date, datetime, timedelta

import repositories
import station_pools

COLLECTION = "leave_requests"

# Leave types and the longest single leave each one allows, in calendar
# days. Vacation/Sick/Other sit at the 15-day company allowance; the rest
# follow the statutory Philippine entitlements they are named after.
# Going past a cap is not forbidden outright — it needs the endorsement
# of a higher authority, which only the admin can record.
LEAVE_TYPES = {
    "Vacation / Personal": 15,
    "Sick Leave": 15,
    "Maternity Leave": 105,
    "Paternity Leave": 7,
    "Solo Parent Leave": 7,
    "Bereavement Leave": 5,
    "Other": 15,
}
DEFAULT_LEAVE_TYPE = "Vacation / Personal"

MIN_LEAD_DAYS = 7        # earliest an employee-filed leave may start
MAX_HORIZON_DAYS = 365   # furthest ahead a leave may be filed
LEAVES_PER_YEAR = 2      # open leaves per calendar year, by start date
COOLDOWN_MONTHS = 6      # from the END of the last approved leave

# The shortest thing that counts as leave. A one-day "leave" would burn
# one of only two yearly slots on what a special day-off request already
# covers for free (that form takes 1-3 individual days), so anything that
# short is refused and pointed at the right form instead. Set to 4 so the
# two never overlap; raising or lowering it is a one-line change here and
# every rule below follows.
MIN_LEAVE_DAYS = 4

# A leave in one of these states holds a slot: it blocks overlapping
# dates, counts against the yearly quota and keeps a second filing out.
# 'denied' and 'cancelled' release everything they were holding.
OPEN_STATUSES = ("pending", "approved")


class LeaveError(Exception):
    """A rule refused the request. `status` is the HTTP status api.py
    should raise with; `blockers` names the rules that failed, so the
    admin form can offer the supervisor-endorsed override for exactly
    those and nothing else."""

    def __init__(self, detail, status=400, blockers=None):
        super().__init__(detail)
        self.detail = detail
        self.status = status
        self.blockers = blockers or []


# ── dates ────────────────────────────────────────────────

def parse_date(iso, field="date"):
    try:
        return datetime.strptime((iso or "").strip(), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        raise LeaveError(f"{field} must be a valid YYYY-MM-DD date")


def day_count(start, end):
    """Calendar days, both ends inclusive — Aug 16-30 is 15 days, which
    is how the company counts a leave and how the employee reads it."""
    return (end - start).days + 1


def date_range(start, end):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def iso_range(start, end):
    return [d.isoformat() for d in date_range(start, end)]


def add_months(d, months):
    """Calendar-month arithmetic that clamps to the end of a short month,
    so Aug 30 + 6 months lands on Feb 28 rather than overflowing."""
    month = d.month - 1 + months
    year = d.year + month // 12
    month = month % 12 + 1
    return date(year, month, min(d.day, calendar.monthrange(year, month)[1]))


def pretty_date(iso):
    """'2026-08-16' -> 'August 16, 2026' for notification and error text."""
    try:
        return datetime.strptime(iso, "%Y-%m-%d").strftime("%B %d, %Y")
    except (ValueError, TypeError):
        return iso or "the requested date"


def pretty_range(start_iso, end_iso):
    if start_iso == end_iso:
        return pretty_date(start_iso)
    return f"{pretty_date(start_iso)} to {pretty_date(end_iso)}"


# ── catalogue ────────────────────────────────────────────

def cap_for(leave_type):
    return LEAVE_TYPES.get(leave_type, LEAVE_TYPES["Other"])


def check_duration(leave_type, start, end):
    """The length rules, shared by both ways a leave is created.

    Deliberately NOT part of the admin's overridable blockers: a leave
    shorter than MIN_LEAVE_DAYS isn't a matter for a higher authority,
    it's the wrong form — so it is refused outright on both paths. Going
    OVER a cap is the opposite: allowed, but only with an endorsement,
    which is why that half is reported rather than raised here for the
    admin (see admin_blockers)."""
    if end < start:
        raise LeaveError("The leave's end date cannot be before its start date.")

    days = day_count(start, end)
    if days < MIN_LEAVE_DAYS:
        raise LeaveError(
            f"A leave has to run at least {MIN_LEAVE_DAYS} days — this one is "
            f"{days} day{'' if days == 1 else 's'}. For {MIN_LEAVE_DAYS - 1} "
            f"day{'' if MIN_LEAVE_DAYS - 1 == 1 else 's'} or fewer, file a "
            f"special day-off request instead.")
    return days


def normalise_type(leave_type):
    """Accepts a leave type case-insensitively and returns the catalogue
    spelling. Unknown types are refused rather than silently treated as
    'Other' — a typo would otherwise buy a different cap."""
    wanted = (leave_type or "").strip().casefold()
    if not wanted:
        raise LeaveError("leaveType is required")
    for name in LEAVE_TYPES:
        if name.casefold() == wanted:
            return name
    raise LeaveError(
        f"'{leave_type}' is not a leave type. Choose one of: "
        + ", ".join(LEAVE_TYPES))


# ── stored leaves ────────────────────────────────────────

def employee_leaves(db, employee_id, statuses=None):
    """One employee's leave records, oldest first. `statuses` filters to
    e.g. OPEN_STATUSES when only the slot-holding ones matter."""
    out = []
    for rec in repositories.from_db(db).leave_requests.find(
            employeeId=employee_id):
        if statuses is not None and rec.get("status") not in statuses:
            continue
        out.append(rec)
    out.sort(key=lambda r: r.get("startDate", ""))
    return out


def overlapping(leaves, start, end, exclude_id=None):
    """The stored leaves whose range touches [start, end]."""
    start_iso, end_iso = start.isoformat(), end.isoformat()
    return [r for r in leaves
            if r.get("id") != exclude_id
            and r.get("startDate", "") <= end_iso
            and r.get("endDate", "") >= start_iso]


def quota_state(leaves, year):
    """How many of the year's leaves are already spoken for. Counted by
    START date, so a leave straddling New Year belongs to the year it
    begins in and can't be double-counted."""
    used = [r for r in leaves
            if r.get("status") in OPEN_STATUSES
            and r.get("startDate", "")[:4] == str(year)]
    return {
        "year": year,
        "limit": LEAVES_PER_YEAR,
        "used": len(used),
        "remaining": max(0, LEAVES_PER_YEAR - len(used)),
        "leaveIds": [r.get("id") for r in used],
    }


def cooldown_state(leaves):
    """The cooldown left over from the last APPROVED leave: the last day
    still blocked, and the first day a new leave may be filed.

    Measured from the leave's end date — the day they return to work —
    so a 105-day maternity leave doesn't earn an earlier next turn than
    a 15-day one. Pending leaves impose nothing: nothing is owed until a
    leave is actually granted."""
    approved = [r for r in leaves if r.get("status") == "approved"
                and r.get("endDate")]
    if not approved:
        return {"lastLeaveEnd": None, "until": None, "nextEligible": None}
    last_end = max(r["endDate"] for r in approved)
    until = add_months(parse_date(last_end, "endDate"), COOLDOWN_MONTHS)
    return {
        "lastLeaveEnd": last_end,
        "until": until.isoformat(),
        "nextEligible": (until + timedelta(days=1)).isoformat(),
    }


# ── schedule awareness ───────────────────────────────────

def scheduled_dates_for_group(db, group):
    """Every ISO date already covered by a generated schedule for
    `group` — the days a leave can no longer be requested for, because a
    roster naming this employee already exists.

    `group` None (floating personnel with no resolvable home group) falls
    back to every group's schedules, so a floating guard can't book leave
    over a day some station already rostered them for."""
    covered = set()
    for s in repositories.from_db(db).schedules.list():
        if group is not None and s.get("group") != group:
            continue
        start, end = s.get("startDate"), s.get("endDate")
        if not start or not end:
            continue
        try:
            first = datetime.strptime(start, "%Y-%m-%d").date()
            last = datetime.strptime(end, "%Y-%m-%d").date()
        except ValueError:
            continue
        covered.update(iso_range(first, last))
    return covered


def home_group(db, employee):
    """The group whose schedules govern this employee, via the same
    station->group rule the scheduler uses. None when it can't be
    resolved (floating personnel with no assigned/preferred station)."""
    try:
        stations = repositories.from_db(db).stations.list()
        return station_pools.home_group(
            employee, station_pools.station_groups(stations))
    except Exception:
        return None


def earliest_start(db, employee, today=None):
    """The first day an employee-filed leave may begin: at least
    MIN_LEAD_DAYS out, and past whatever the roster already covers.

    Walks forward through the scheduled days rather than jumping to the
    end of them, so a gap between two generated periods is offered
    instead of being skipped."""
    today = today or date.today()
    scheduled = scheduled_dates_for_group(db, home_group(db, employee))
    candidate = today + timedelta(days=MIN_LEAD_DAYS)
    limit = today + timedelta(days=MAX_HORIZON_DAYS)
    while candidate.isoformat() in scheduled and candidate <= limit:
        candidate += timedelta(days=1)
    return candidate


def affected_duties(db, employee_id, start, end):
    """The published/unpublished duty entries this leave would swallow.

    Always empty for an employee-filed leave — the conflict rule keeps
    those on unscheduled days — but the admin may record leave straight
    over a live roster, and every entry returned here is a post that
    needs a replacement rather than a post that quietly goes unmanned."""
    start_iso, end_iso = start.isoformat(), end.isoformat()
    hits = []
    for s in repositories.from_db(db).schedules.list():
        if (s.get("endDate", "") < start_iso
                or s.get("startDate", "") > end_iso):
            continue
        for day in s.get("days", []):
            iso = day.get("date", "")
            if not (start_iso <= iso <= end_iso):
                continue
            for entry in day.get("entries", []):
                if entry.get("employeeId") != employee_id:
                    continue
                hits.append({
                    "date": iso,
                    "scheduleId": s.get("id"),
                    "scheduleStatus": s.get("status", "unpublished"),
                    "stationName": s.get("stationName", ""),
                    "shift": entry.get("shift", ""),
                    "post": entry.get("post", ""),
                    "entryId": entry.get("id"),
                    # A duty they were only covering for someone else is
                    # a lighter loss than their own post — the original
                    # absentee is still the one who owes that shift.
                    "coveringFor": entry.get("coveringFor"),
                })
    hits.sort(key=lambda h: (h["date"], h["stationName"]))
    return hits


def coverage_impact(db, employee, start, end):
    """What approving this leave costs the roster, for the confirmation
    dialog: the duties it swallows outright, and how thin it leaves the
    employee's own shift at their own station.

    `peerCount` is the honest proxy for the leaves that land on days no
    schedule exists for yet — nothing can be counted post by post before
    generation, but 'the last night guard at this station' is exactly
    the case an admin must not approve blind."""
    emp_id = employee.get("id", "")
    station = (employee.get("assignedStation") or "").strip()
    shift = employee.get("assignedShift")

    peers = 0
    if station and shift:
        for other in repositories.from_db(db).employees.list():
            if other.get("id") == emp_id or not other.get("isActive", True):
                continue
            if ((other.get("assignedStation") or "").strip() == station
                    and other.get("assignedShift") == shift):
                peers += 1

    duties = affected_duties(db, emp_id, start, end)
    return {
        "employeeId": emp_id,
        "employeeName": employee.get("name", emp_id),
        "station": station,
        "shift": shift,
        "days": day_count(start, end),
        "peerCount": peers,
        "affectedDuties": duties,
        "publishedDutyCount": sum(
            1 for d in duties if d["scheduleStatus"] == "published"),
        # The shift loses its last other body — every day of this leave
        # falls on the reliever pool.
        "leavesShiftBare": bool(station and shift and peers == 0),
    }


# ── eligibility ──────────────────────────────────────────

def eligibility(db, employee, today=None):
    """Everything the guard app's leave form needs before the employee
    types anything: whether they may file at all, the earliest day they
    could start, and which days inside the horizon are already rostered
    and so unselectable."""
    today = today or date.today()
    employee_id = employee.get("id", "")
    leaves = employee_leaves(db, employee_id)
    quota = quota_state(leaves, today.year)
    cooldown = cooldown_state(leaves)
    earliest = earliest_start(db, employee, today)

    pending = [r for r in leaves if r.get("status") == "pending"]
    active = [r for r in leaves if r.get("status") == "approved"
              and r.get("endDate", "") >= today.isoformat()]

    can_file, reason = True, ""
    if pending:
        can_file = False
        reason = ("You already have a leave request awaiting a decision. "
                  "Wait for it to be decided, or cancel it first.")
    elif quota["remaining"] <= 0:
        can_file = False
        reason = (f"You have already used your {LEAVES_PER_YEAR} leaves for "
                  f"{today.year}. The next one can be filed in "
                  f"{today.year + 1}.")
    elif cooldown["nextEligible"] and cooldown["nextEligible"] > today.isoformat():
        can_file = False
        reason = (f"Your last leave ended on "
                  f"{pretty_date(cooldown['lastLeaveEnd'])}. A new leave can "
                  f"be filed from {pretty_date(cooldown['nextEligible'])} — "
                  f"{COOLDOWN_MONTHS} months after it ended.")

    horizon = today + timedelta(days=MAX_HORIZON_DAYS)
    scheduled = scheduled_dates_for_group(db, home_group(db, employee))
    blocked = sorted(d for d in scheduled
                     if today.isoformat() <= d <= horizon.isoformat())

    return {
        "canFile": can_file,
        "reason": reason,
        "earliestStart": earliest.isoformat(),
        "maxDate": horizon.isoformat(),
        "minLeadDays": MIN_LEAD_DAYS,
        "leaveTypes": [{"name": n, "maxDays": c} for n, c in LEAVE_TYPES.items()],
        "defaultLeaveType": DEFAULT_LEAVE_TYPE,
        "minLeaveDays": MIN_LEAVE_DAYS,
        "quota": quota,
        "cooldown": cooldown,
        "blockedDates": blocked,
        "pendingRequestId": pending[0].get("id") if pending else None,
        "activeLeave": active[0] if active else None,
    }


def validate_employee_request(db, employee, leave_type, start, end, today=None):
    """Every rule an employee-filed leave has to clear. Raises LeaveError
    on the first failure, ordered so the message names the thing they can
    actually act on — being out of quota is worth saying before quibbling
    about which days are already rostered."""
    today = today or date.today()
    employee_id = employee.get("id", "")
    leave_type = normalise_type(leave_type)

    days = check_duration(leave_type, start, end)
    cap = cap_for(leave_type)
    if days > cap:
        raise LeaveError(
            f"A {leave_type} may run at most {cap} day"
            f"{'' if cap == 1 else 's'}. This request is {days} days — a "
            f"longer leave needs the consent of a higher authority and has "
            f"to be recorded by the admin.")

    leaves = employee_leaves(db, employee_id)

    if any(r.get("status") == "pending" for r in leaves):
        raise LeaveError(
            "You already have a leave request awaiting a decision. Wait for "
            "it to be decided, or cancel it before filing another.",
            status=409)

    clash = overlapping(
        [r for r in leaves if r.get("status") in OPEN_STATUSES], start, end)
    if clash:
        raise LeaveError(
            f"You already have a leave covering "
            f"{pretty_range(clash[0]['startDate'], clash[0]['endDate'])}.",
            status=409)

    quota = quota_state(leaves, start.year)
    if quota["remaining"] <= 0:
        raise LeaveError(
            f"You have already used your {LEAVES_PER_YEAR} leaves for "
            f"{start.year}.", status=409)

    cooldown = cooldown_state(leaves)
    if cooldown["nextEligible"] and cooldown["nextEligible"] > today.isoformat():
        raise LeaveError(
            f"Your last leave ended on "
            f"{pretty_date(cooldown['lastLeaveEnd'])}. A new leave can only "
            f"be filed from {pretty_date(cooldown['nextEligible'])}, "
            f"{COOLDOWN_MONTHS} months after it ended.", status=409)

    lead_floor = today + timedelta(days=MIN_LEAD_DAYS)
    if start < lead_floor:
        raise LeaveError(
            f"A leave has to be filed at least {MIN_LEAD_DAYS} days ahead. "
            f"The earliest date you can start is "
            f"{pretty_date(lead_floor.isoformat())}.")

    if start > today + timedelta(days=MAX_HORIZON_DAYS):
        raise LeaveError(
            f"Leave can only be filed up to {MAX_HORIZON_DAYS} days ahead.")

    scheduled = scheduled_dates_for_group(db, home_group(db, employee))
    clashes = sorted(d for d in iso_range(start, end) if d in scheduled)
    if clashes:
        raise LeaveError(
            f"A schedule already covers "
            f"{pretty_range(clashes[0], clashes[-1])}, so those days can no "
            f"longer be taken as leave. The earliest date you can start is "
            f"{pretty_date(earliest_start(db, employee, today).isoformat())}.",
            status=409)

    return leave_type


def admin_blockers(db, employee, leave_type, start, end, today=None,
                   exclude_id=None):
    """The rules an admin-recorded leave breaks, as a list rather than an
    exception — the admin form is allowed to proceed past any of them,
    but only by naming the supervisor who endorsed it.

    Deliberately does NOT include the lead time (the admin is recording
    something already agreed) or the schedule conflict (handled as
    replacements, not as a refusal)."""
    today = today or date.today()
    leaves = employee_leaves(db, employee.get("id", ""))
    blockers = []

    days = day_count(start, end)
    cap = cap_for(leave_type)
    if days > cap:
        blockers.append({
            "rule": "duration",
            "message": f"{days} days exceeds the {cap}-day cap for "
                       f"{leave_type}.",
        })

    quota = quota_state(leaves, start.year)
    if quota["remaining"] <= 0:
        blockers.append({
            "rule": "quota",
            "message": f"{employee.get('name', 'This employee')} has already "
                       f"used their {LEAVES_PER_YEAR} leaves for {start.year}.",
        })

    cooldown = cooldown_state(leaves)
    if cooldown["nextEligible"] and cooldown["nextEligible"] > today.isoformat():
        blockers.append({
            "rule": "cooldown",
            "message": f"Their last leave ended on "
                       f"{pretty_date(cooldown['lastLeaveEnd'])}; the "
                       f"{COOLDOWN_MONTHS}-month cooldown runs to "
                       f"{pretty_date(cooldown['until'])}.",
        })

    clash = overlapping(
        [r for r in leaves if r.get("status") in OPEN_STATUSES],
        start, end, exclude_id=exclude_id)
    if clash:
        blockers.append({
            "rule": "overlap",
            "message": f"They already have a leave covering "
                       f"{pretty_range(clash[0]['startDate'], clash[0]['endDate'])}.",
        })

    return blockers


# ── records ──────────────────────────────────────────────

def new_record(*, request_id, employee, leave_type, start, end, title, body,
               source, status, now_iso, decided_by=None, admin_note="",
               supervisor_name="", overrides=(), affected=()):
    """One leave document. `source` separates a guard-filed request from
    an admin-recorded one, and `overrides` records which rules were
    waived so the report can show the endorsement behind them."""
    return {
        "id": request_id,
        "employeeId": employee.get("id", ""),
        "employeeName": employee.get("name", ""),
        "employeeType": employee.get("type", "regular"),
        "station": (employee.get("assignedStation") or "").strip(),
        "leaveType": leave_type,
        "startDate": start.isoformat(),
        "endDate": end.isoformat(),
        "days": day_count(start, end),
        "title": title,
        "body": body,
        "source": source,                  # 'employee' | 'admin'
        "status": status,                  # pending | approved | denied | cancelled
        "submittedAt": now_iso,
        "decidedAt": now_iso if status == "approved" else None,
        "decidedBy": decided_by,
        "adminNote": admin_note,
        # Who at the higher authority endorsed this, when it went past a
        # cap or waived a rule. Empty on an ordinary within-the-rules leave.
        "supervisorName": supervisor_name,
        "overriddenRules": [b["rule"] for b in overrides],
        "overrideNotes": [b["message"] for b in overrides],
        "affectedDuties": list(affected),
        "isRead": status != "pending",
    }


def phase_of(record, today=None):
    """Where an approved leave stands relative to today — what the
    'On Leave' badge and the report's status column read from."""
    today = (today or date.today()).isoformat()
    status = record.get("status")
    if status != "approved":
        return status or "pending"
    if record.get("endDate", "") < today:
        return "completed"
    if record.get("startDate", "") > today:
        return "upcoming"
    return "active"


def active_leaves(db, on_date=None):
    """{employeeId: leave} for every approved leave covering `on_date` —
    what the employee list and Employee Details read to show On Leave
    without loading each employee's history."""
    iso = (on_date or date.today()).isoformat()
    out = {}
    for rec in repositories.from_db(db).leave_requests.list():
        if rec.get("status") != "approved":
            continue
        if rec.get("startDate", "") <= iso <= rec.get("endDate", ""):
            out[rec.get("employeeId", "")] = rec
    return out
