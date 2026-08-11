"""
Rule-based replacement suggestion for absent guards (Phase 3).

This module answered the flowchart's "AI suggest suitable replacement"
box on its own for a long time, with a deterministic ranking function
and no AI at all. The AI now sits on top of it rather than in place of
it, and the split is the point:

    suggest()           decides who is ELIGIBLE — the hard rules below,
                        which no model gets to renegotiate.
    build_ai_context()  packages the survivors for ai_service, which
                        decides who is BEST among them and says why.

Everything in this file still works, and still answers
GET /replacements/suggest, with the AI switched off or unreachable.

The deterministic ranking:

  1. HARD FILTER — schedule conflicts (flowchart: "should be no
     conflict schedule"): anyone who already appears in ANY schedule
     entry on that date is excluded, along with anyone reported absent
     that day and the absent employee themselves.
  2. HARD FILTER — post eligibility, mirroring scheduler.py's rules:
       * Morning/Afternoon posts: relievers, or regulars fixed to that
         same shift.
       * Night posts: night-shift regulars only (relievers never work
         nights).
       * HG Day / HG Night posts: head guards only.
  3. RANKING — the survivors are scored 0-100 with human-readable
     reasons: station familiarity (assigned > preferred), type match
     for the post, and a lighter 15-day workload scores higher.

apply_replacement() then performs the admin's "update the schedule"
step: the absent guard's entry in the stored schedule is rewritten to
the chosen replacement (marked coveringFor=absentee), the attendance
report record is stamped replacedBy*, an audit doc is written to
`replacements/`, and a notification for the chosen guard is written to
`employee_notifications/` (shown in the guard app's Alerts tab).

THE COVER WINDOW closes at the post's time-out — see cover_window().
"""

from datetime import datetime, timedelta, timezone

import repositories
import station_posts

DAY_SHIFTS = ("Morning", "Afternoon")
HG_SHIFTS = ("HG Day", "HG Night")

# Philippine Standard Time. Fixed +8 with no DST, so a plain offset is
# exact and needs no tzdata — and it keeps the cover window below anchored
# to the guards' own clock whatever timezone the server runs in. Mirrors
# api.py's _PHT.
_PHT = timezone(timedelta(hours=8))


def _covering(schedules, date_iso):
    """Schedules whose 15-day period includes the date."""
    return [s for s in schedules
            if s.get("startDate", "") <= date_iso <= s.get("endDate", "")]


def _busy_ids(schedules, date_iso):
    """Everyone already assigned somewhere on that date (any station)."""
    busy = set()
    for schedule in schedules:
        for day in schedule.get("days", []):
            if day.get("date") == date_iso:
                for entry in day.get("entries", []):
                    busy.add(entry.get("employeeId"))
    return busy


def _absent_ids(db, date_iso):
    """Everyone reported absent on that date — an absent guard can't
    cover another absent guard's post."""
    ids = set()
    for report in repositories.from_db(db).attendance_reports.find(
            date=date_iso):
        for rec in report.get("records", []):
            if not rec.get("isPresent", True):
                ids.add(rec.get("employeeId"))
    return ids


# ---------------------------------------------------------------------
# The cover window
#
# A replacement is somebody sent to STAND a post. Once the post has timed
# out there is nothing left to stand, so the window closes there: past
# time-out, assigning a cover would rewrite a duty that is already
# history, tell a guard to report for a shift that finished hours ago,
# and leave the schedule disagreeing with what happened on the ground.
#
# It closes at time-out, not at time-in: a guard going absent mid-shift
# is exactly the case this flow exists for, and the rest of the post is
# still worth manning.
# ---------------------------------------------------------------------

def _entry_window(schedules, date_iso, station, shift, employee_id):
    """The ("HH:MM", "HH:MM") duty window of the post `employee_id` mans
    on that date, straight off their own schedule entry.

    Posts are staggered per station (station_posts' ladder), so two guards
    on the same Morning shift can time out four hours apart — the entry's
    own window is the only honest answer. None when the guard has no entry
    that day, or the entry predates posts carrying times.
    """
    fallback = None
    for sched in schedules:
        if station and (sched.get("stationName") or "").strip() != station:
            continue
        for day in sched.get("days", []):
            if day.get("date") != date_iso:
                continue
            for entry in day.get("entries", []):
                if entry.get("employeeId") != employee_id:
                    continue
                start, end = entry.get("timeIn"), entry.get("timeOut")
                if not (start and end):
                    continue
                if entry.get("shift") == shift:
                    return start, end
                # A shift-label mismatch is tolerated the same way
                # apply_replacement tolerates it — kept only if no
                # exactly-matching entry turns up.
                fallback = fallback or (start, end)
    return fallback


def _base_window(shift):
    """A shift label's un-staggered hours, for a post with none of its
    own. None on a label the system doesn't know."""
    hg = station_posts.HG_SHIFT_WINDOWS.get(shift)
    if hg is not None:
        return hg
    key = station_posts.SHIFT_LABEL_KEYS.get(shift)
    return station_posts.SHIFT_WINDOWS.get(key) if key else None


def cover_window(db, date_iso, station, shift, absent_id, schedules=None):
    """When the post being covered runs, and the instant it times out.

    Returns ``{"endsAt", "timeIn", "timeOut", "shift"}``. `endsAt` is an
    ISO instant in Philippine time — deterministic, derived from the
    schedule alone, with the clock comparison left to is_closed(). That
    split is deliberate: it keeps GET /replacements/suggest returning the
    same thing all day, and puts the "has it passed" decision in one
    place that both the API and the admin app answer from.

    None only when `date_iso` can't be read as a date.
    """
    try:
        duty_date = datetime.strptime(date_iso, "%Y-%m-%d").date()
    except ValueError:
        return None

    if schedules is None:
        schedules = repositories.from_db(db).schedules.list()
    window = _entry_window(_covering(schedules, date_iso), date_iso,
                           (station or "").strip(), shift, absent_id)
    window = window or _base_window(shift)

    start = station_posts.parse_hhmm(window[0]) if window else None
    end = station_posts.parse_hhmm(window[1]) if window else None

    if start is None or end is None:
        # No readable hours for this post anywhere. Fall back to the end
        # of the calendar day, matching api.py's _duty_has_ended: the
        # permissive read, so a shift missing from the table can't block
        # a cover that is still genuinely needed.
        ends_at = datetime.combine(duty_date + timedelta(days=1),
                                   datetime.min.time(), tzinfo=_PHT)
        return {"endsAt": ends_at.isoformat(), "timeIn": None,
                "timeOut": None, "shift": shift}

    # An overnight post (Night 2100H-0500H, HG Night 1700H-0500H) times
    # out on the day AFTER the duty date.
    day = duty_date + timedelta(days=1) if end <= start else duty_date
    ends_at = datetime(day.year, day.month, day.day, end // 60, end % 60,
                       tzinfo=_PHT)
    return {
        "endsAt": ends_at.isoformat(),
        "timeIn": station_posts.format_hhmm(start),
        "timeOut": station_posts.format_hhmm(end),
        "shift": shift,
    }


def is_closed(window, now=None):
    """True once the post in `window` has timed out. An unreadable window
    is treated as open — see cover_window's permissive fallback."""
    if not window or not window.get("endsAt"):
        return False
    return (now or datetime.now(_PHT)) >= datetime.fromisoformat(
        window["endsAt"])


def closed_reason(window, station, shift, date_iso):
    """Why the admin can't assign anyone — worded so they know it's the
    clock refusing, not a missing candidate."""
    time_out = window.get("timeOut") if window else None
    stood = (f"timed out at "
             f"{station_posts.format_military(station_posts.parse_hhmm(time_out))} "
             if time_out else "ended ")
    return (f"The {shift} post at {station} on {date_iso} {stood}— that "
            f"duty is over, so a replacement can no longer be assigned to "
            f"it.")


def _days_worked(schedules, employee_id):
    """Distinct duty dates this employee already has in the schedules
    covering the period — used to prefer less-loaded candidates."""
    dates = set()
    for schedule in schedules:
        for day in schedule.get("days", []):
            if any(e.get("employeeId") == employee_id
                   for e in day.get("entries", [])):
                dates.add(day.get("date"))
    return len(dates)


def _is_eligible(emp, shift):
    """Mirrors scheduler.py's coverage rules for each post type."""
    etype = emp.get("type")
    if shift in HG_SHIFTS:
        return etype == "headGuard"
    if shift == "Night":
        return etype == "regular" and emp.get("assignedShift") == "night"
    if shift in DAY_SHIFTS:
        return (etype == "reliever"
                or (etype == "regular"
                    and emp.get("assignedShift") == shift.lower()))
    return False


def _score(emp, station, shift, days_worked):
    """0-100 suitability score + the reasons shown in the app."""
    score, reasons = 0, []
    etype = emp.get("type")
    assigned = (emp.get("assignedStation") or "").strip()

    if assigned == station:
        score += 35
        reasons.append("Regularly assigned to this station")
    elif station in [p.strip() for p in emp.get("preferredStations", [])]:
        score += 20
        reasons.append("Prefers this station")

    if shift in DAY_SHIFTS:
        if etype == "reliever":
            score += 25
            reasons.append("Reliever — floats to cover day-shift posts")
        else:
            score += 15
            reasons.append(f"Regular {shift.lower()}-shift guard")
    elif shift == "Night":
        score += 25
        reasons.append("Night-shift regular (relievers never cover nights)")
    else:  # HG Day / HG Night
        score += 25
        reasons.append("Head guard")
        if not assigned:
            score += 10
            reasons.append("Floating substitute head guard")

    # Lighter 15-day workload scores higher (0-10 points).
    load = min(days_worked, 13)
    score += round(10 * (1 - load / 13))
    reasons.append(f"Free on this date — {days_worked} duty "
                   f"day{'s' if days_worked != 1 else ''} this period")

    return min(score, 100), reasons


def _active_offers(db, date_iso):
    """{employeeId: offer} for every still-active cover offer on this date —
    guards who volunteered on their rest day to come in. A fulfilled or
    withdrawn offer is ignored."""
    offers = {}
    for offer in repositories.from_db(db).cover_offers.find(date=date_iso):
        if offer.get("status", "active") == "active":
            offers[offer.get("employeeId")] = offer
    return offers


def _volunteer_boost(offer, station, shift):
    """Extra points + reasons for a guard who volunteered to cover this
    date. Volunteering at all is the big signal; matching the post's shift
    and station on top of that ranks the keenest, best-fit volunteers
    first. Returns (bonus, reasons)."""
    bonus, reasons = 40, ["✋ Volunteered to cover this day"]

    wanted_shifts = offer.get("preferredShifts") or []
    if not wanted_shifts or shift in wanted_shifts:
        bonus += 15
        reasons.append(f"Available for the {shift} shift")

    wanted_stations = [s.strip() for s in (offer.get("preferredStations") or [])]
    if not wanted_stations or station in wanted_stations:
        bonus += 15
        reasons.append("Wants to be deployed to this station")

    return bonus, reasons


def suggest(db, date_iso, station, shift, absent_id, schedules=None):
    """Returns ranked, conflict-free replacement candidates. Guards who
    volunteered to cover this date (active cover offers) are boosted and
    always sort above non-volunteers, so a willing colleague sits at the
    top of the admin's list.

    Deliberately clock-free: whether the post has already timed out is
    cover_window()'s question, asked alongside this one, so the ranking
    itself stays the same all day.
    """
    if schedules is None:
        schedules = repositories.from_db(db).schedules.list()
    covering = _covering(schedules, date_iso)
    busy = _busy_ids(covering, date_iso)
    absent_today = _absent_ids(db, date_iso)
    offers = _active_offers(db, date_iso)

    candidates = []
    for emp in repositories.from_db(db).employees.list():
        emp_id = emp.get("id")
        if (emp_id == absent_id
                or not emp.get("isActive", True)
                or not _is_eligible(emp, shift)
                or emp_id in busy          # schedule conflict
                or emp_id in absent_today):
            continue
        days_worked = _days_worked(covering, emp_id)
        score, reasons = _score(emp, station, shift, days_worked)

        # A volunteer's reasons lead with the offer, then the base ones.
        offer = offers.get(emp_id)
        volunteered = offer is not None
        if volunteered:
            bonus, offer_reasons = _volunteer_boost(offer, station, shift)
            score = min(score + bonus, 100)
            reasons = offer_reasons + reasons

        candidates.append({
            "employee": emp,
            "score": score,
            "reasons": reasons,
            "daysWorkedThisPeriod": days_worked,
            "volunteered": volunteered,
        })

    # Volunteers first (they raised their hand for this exact day), then by
    # score, then name for a stable order.
    candidates.sort(key=lambda c: (not c["volunteered"], -c["score"],
                                   c["employee"].get("name", "")))
    return candidates


# ---------------------------------------------------------------------
# Context for the AI review
#
# suggest() above has already done the part that must not be delegated:
# every hard rule is applied, and what survives is a list of guards who
# may lawfully stand this post. build_ai_context() packages that list for
# ai_service.review_candidates(), which re-ranks it on the judgement
# _score() cannot express and writes the rationale the admin reads.
#
# Two things this deliberately adds that suggest() does not compute:
#
#   coversLast30Days  how often each candidate has ALREADY been pulled in
#                     to cover somebody else's absence. Cover load falls
#                     unevenly — a willing reliever gets asked again
#                     precisely because they said yes last time — and
#                     nothing in the 0-100 score can see it, because the
#                     score only looks at the current 15-day period.
#
#   the absence reason  Injury reads differently from Family Emergency
#                     when the same post may need covering again
#                     tomorrow.
#
# What it deliberately leaves out is everything not needed to rank a
# guard for a post: no addresses, no phone numbers, no credentials. The
# payload is job attributes and ids.
# ---------------------------------------------------------------------

# How many candidates are handed over. A Morning post at a big station
# can survive filtering with sixty names, and sending all of them costs
# latency and quota to rank people nobody would pick. The admin still
# sees the full ranked list underneath — this cap is what the AI reads,
# not what the screen shows.
AI_SHORTLIST_LIMIT = 12

# The window for "recently". Long enough that a pattern of repeated
# covering is visible, short enough that a guard who carried the load two
# months ago is not still being credited for it.
COVER_HISTORY_DAYS = 30


def _cover_counts(db, date_iso, days=COVER_HISTORY_DAYS):
    """{employeeId: absences they have covered in the `days` before
    `date_iso`}, from the audit records apply_replacement() writes.

    Counted from `replacements/` rather than from the schedules, and the
    difference matters: a schedule entry only says who stood the post,
    while a replacement record says somebody was PULLED IN to stand it.
    The second is the burden worth spreading.
    """
    try:
        start = (datetime.strptime(date_iso, "%Y-%m-%d").date()
                 - timedelta(days=days)).isoformat()
    except ValueError:
        return {}

    counts = {}
    for record in repositories.from_db(db).replacements.list():
        # ISO dates compare correctly as plain strings.
        covered_on = record.get("date", "")
        if start <= covered_on <= date_iso:
            emp_id = record.get("replacementEmployeeId")
            if emp_id:
                counts[emp_id] = counts.get(emp_id, 0) + 1
    return counts


def _military(hhmm):
    """"05:00" -> "0500H", the form every screen shows. None passes
    through — a post with no readable hours has no time to state."""
    if not hhmm:
        return None
    minutes = station_posts.parse_hhmm(hhmm)
    return station_posts.format_military(minutes) if minutes is not None else None


def _absence_reason(db, date_iso, absent_id):
    """The reason the absent guard gave, when they filed a request.

    None is an ordinary answer, not a failure: an admin can mark somebody
    absent from the attendance report without any request existing.
    """
    for record in repositories.from_db(db).absence_requests.find(
            employeeId=absent_id):
        if record.get("date") == date_iso:
            return record.get("reason") or None
    return None


def build_ai_context(db, date_iso, station, shift, absent_id, candidates,
                     window=None, limit=AI_SHORTLIST_LIMIT):
    """The payload ai_service.review_candidates() reasons over.

    `candidates` is suggest()'s output, already ranked. Returns None when
    there is nothing to review — no candidates means there is no choice
    to make, and asking anyway would spend a call to be told so.
    """
    if not candidates:
        return None

    repo = repositories.from_db(db)
    shortlist = candidates[:limit]
    covers = _cover_counts(db, date_iso)

    absent = repo.employees.get(absent_id) or {}
    if window is None:
        window = cover_window(db, date_iso, station, shift, absent_id)

    return {
        "post": {
            "date": date_iso,
            "station": station,
            "shift": shift,
            # Military, not the "05:00" stored form the window carries.
            # Whatever the model writes is read by an admin next to
            # screens that all say 0500H, and a rationale quoting "05:00"
            # would be the only place in the app that doesn't.
            "timeIn": _military((window or {}).get("timeIn")),
            "timeOut": _military((window or {}).get("timeOut")),
        },
        "absence": {
            "employeeId": absent_id,
            "employeeName": absent.get("name", ""),
            "type": absent.get("type", ""),
            "reason": _absence_reason(db, date_iso, absent_id),
        },
        # `candidateCount` is the honest total, so the model knows the
        # shortlist is a top-N and not the whole field — without it, a
        # cap of 12 out of 60 reads as "these are the only options".
        "candidateCount": len(candidates),
        "candidates": [
            {
                "id": c["employee"].get("id"),
                "name": c["employee"].get("name", ""),
                "type": c["employee"].get("type", ""),
                "assignedStation": (c["employee"].get("assignedStation")
                                    or "").strip(),
                "assignedShift": c["employee"].get("assignedShift") or "",
                "daysWorkedThisPeriod": c["daysWorkedThisPeriod"],
                "coversLast30Days": covers.get(c["employee"].get("id"), 0),
                "volunteered": c["volunteered"],
                "ruleScore": c["score"],
                "reasons": c["reasons"],
            }
            for c in shortlist
        ],
    }


def _shift_slug(shift):
    return "".join(c for c in shift.upper() if c.isalnum()) or "SHIFT"


def apply_replacement(db, req):
    """Rewrites the schedule entry, stamps the report record, writes the
    audit + notification docs. Raises ValueError for a schedule conflict
    (409) and LookupError when something can't be found (404)."""
    date_iso = req.date
    station = req.station.strip()
    shift = req.shift
    repo = repositories.from_db(db)

    rep = repo.employees.get(req.replacementEmployeeId)
    if rep is None:
        raise LookupError("Replacement employee not found")

    covering = [s for s in repo.schedules.list()
                if s.get("startDate", "") <= date_iso <= s.get("endDate", "")]

    # The post has to still be standing. This is the authoritative check —
    # the admin screens hide the button once the window shuts, but a
    # screen left open since yesterday would otherwise still post here.
    window = cover_window(db, date_iso, station, shift, req.absentEmployeeId,
                          schedules=covering)
    if is_closed(window):
        raise ValueError(closed_reason(window, station, shift, date_iso))

    # Re-check the no-conflict rule right before writing, in case the
    # suggestion list went stale while the admin was deciding.
    if req.replacementEmployeeId in _busy_ids(covering, date_iso):
        raise ValueError(
            f"{rep.get('name', req.replacementEmployeeId)} is already "
            f"scheduled on {date_iso} — pick someone without a conflict.")

    # The station's schedule covering that date (published wins).
    target = None
    for sched in covering:
        if (sched.get("stationName") or "").strip() == station:
            if target is None or sched.get("status") == "published":
                target = sched
    if target is None:
        raise LookupError(
            f"No schedule for {station} covers {date_iso}")

    sched = target
    replaced_entry = False
    for day in sched.get("days", []):
        if day.get("date") != date_iso:
            continue
        entries = day.get("entries", [])
        match = next((e for e in entries
                      if e.get("employeeId") == req.absentEmployeeId
                      and e.get("shift") == shift), None)
        if match is None:  # tolerate a shift-label mismatch
            match = next((e for e in entries
                          if e.get("employeeId") == req.absentEmployeeId),
                         None)
        if match is not None:
            match["employeeId"] = rep["id"]
            match["employeeName"] = rep.get("name", "")
            match["isReliever"] = rep.get("type") == "reliever"
            match["coveringFor"] = req.absentEmployeeId
            replaced_entry = True
    if not replaced_entry:
        raise LookupError(
            f"{req.absentEmployeeId} has no entry on {date_iso} in the "
            f"{station} schedule")
    repo.schedules.update(sched["id"], {"days": sched["days"]})

    applied_at = datetime.now(timezone.utc).isoformat()
    absent_name = req.absentEmployeeName or req.absentEmployeeId
    slug = _shift_slug(shift)

    # Audit trail — one doc per covered absence, deterministic ID so a
    # re-apply overwrites instead of duplicating.
    record = {
        "id": f"REP-{date_iso.replace('-', '')}-"
              f"{req.absentEmployeeId}-{slug}",
        "date": date_iso,
        "station": station,
        "shift": shift,
        "scheduleId": sched.get("id"),
        "absentEmployeeId": req.absentEmployeeId,
        "absentEmployeeName": absent_name,
        "replacementEmployeeId": rep["id"],
        "replacementEmployeeName": rep.get("name", ""),
        "appliedAt": applied_at,
    }
    repo.replacements.upsert(record["id"], record)

    # Stamp the attendance report record(s) so the admin screens show
    # "Replaced by ..." instead of offering the button again.
    if req.reportId:
        report_ids = [req.reportId]
    else:
        report_ids = [r["id"] for r in repo.attendance_reports.find(
            date=date_iso, station=station)]
    for report_id in report_ids:
        data = repo.attendance_reports.get(report_id)
        if data is None:
            continue
        changed = False
        for rec in data.get("records", []):
            if (rec.get("employeeId") == req.absentEmployeeId
                    and not rec.get("isPresent", True)):
                rec["replacedById"] = rep["id"]
                rec["replacedByName"] = rep.get("name", "")
                rec["replacedAt"] = applied_at
                changed = True
        if changed:
            repo.attendance_reports.update(
                report_id, {"records": data["records"]})

    # Flowchart's last box: notify the employee the schedule changed.
    notification = {
        "id": f"NTF-{date_iso.replace('-', '')}-{rep['id']}-{slug}",
        "employeeId": rep["id"],
        "type": "urgent",
        "title": "Sudden Duty Call",
        "message": f"{absent_name} is unable to report for the {shift} "
                   f"shift at {station} on {date_iso}. You have been "
                   "assigned to cover this post — please review your "
                   "updated schedule.",
        "date": date_iso,
        "createdAt": applied_at,
        "isRead": False,
    }
    repositories.from_db(db).employee_notifications.upsert(
        notification["id"], notification)

    # If the chosen guard volunteered for this day, close their offer so it
    # stops re-suggesting them and their availability card shows "assigned".
    offer_id = f"COV-{date_iso.replace('-', '')}-{rep['id']}"
    offer = repo.cover_offers.get(offer_id)
    if offer is not None and offer.get("status") != "fulfilled":
        repo.cover_offers.update(offer_id, {
            "status": "fulfilled",
            "fulfilledAt": applied_at,
            "fulfilledStation": station,
            "fulfilledShift": shift,
        })

    # Approval flow: this replacement is the "cover" step of approving an
    # emergency absence request. Now that a cover exists, flip the request
    # to 'approved' and tell the absent guard it was granted + covered.
    absence_id = getattr(req, "absenceRequestId", None)
    if absence_id:
        absence = repo.absence_requests.get(absence_id)
        # Only decide a still-pending request — never overturn a prior
        # decision, and stay idempotent if apply is retried.
        if absence is not None and absence.get("status") == "pending":
            repo.absence_requests.update(absence_id, {
                "status": "approved",
                "decidedAt": applied_at,
                "decidedBy": "admin",
                "coveredById": rep["id"],
                "coveredByName": rep.get("name", ""),
                "isRead": True,
            })
            repo.employee_notifications.upsert(
                f"NTF-{absence_id}-DECISION", {
                    "id": f"NTF-{absence_id}-DECISION",
                    "employeeId": req.absentEmployeeId,
                    "type": "schedule",
                    "title": "Absence Request Approved",
                    "message": f"Your absence for {date_iso} was approved — "
                               f"{rep.get('name', 'a colleague')} will cover "
                               f"your {shift} post at {station}.",
                    "date": date_iso,
                    "createdAt": applied_at,
                    "isRead": False,
                })

    return record
