"""
Rule-based replacement suggestion for absent guards (Phase 3).

Replaces the flowchart's "AI suggest suitable replacement" box with a
deterministic, explainable ranking function — same outcome, no AI:

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
"""

from datetime import datetime, timezone

DAY_SHIFTS = ("Morning", "Afternoon")
HG_SHIFTS = ("HG Day", "HG Night")


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
    docs = db.collection("attendance_reports").where(
        "date", "==", date_iso).stream()
    for doc in docs:
        for rec in doc.to_dict().get("records", []):
            if not rec.get("isPresent", True):
                ids.add(rec.get("employeeId"))
    return ids


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
    for doc in (db.collection("cover_offers")
                .where("date", "==", date_iso).stream()):
        offer = doc.to_dict()
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


def suggest(db, date_iso, station, shift, absent_id):
    """Returns ranked, conflict-free replacement candidates. Guards who
    volunteered to cover this date (active cover offers) are boosted and
    always sort above non-volunteers, so a willing colleague sits at the
    top of the admin's list."""
    schedules = [d.to_dict() for d in db.collection("schedules").stream()]
    covering = _covering(schedules, date_iso)
    busy = _busy_ids(covering, date_iso)
    absent_today = _absent_ids(db, date_iso)
    offers = _active_offers(db, date_iso)

    candidates = []
    for doc in db.collection("employees").stream():
        emp = doc.to_dict()
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


def _shift_slug(shift):
    return "".join(c for c in shift.upper() if c.isalnum()) or "SHIFT"


def apply_replacement(db, req):
    """Rewrites the schedule entry, stamps the report record, writes the
    audit + notification docs. Raises ValueError for a schedule conflict
    (409) and LookupError when something can't be found (404)."""
    date_iso = req.date
    station = req.station.strip()
    shift = req.shift

    rep_doc = db.collection("employees").document(
        req.replacementEmployeeId).get()
    if not rep_doc.exists:
        raise LookupError("Replacement employee not found")
    rep = rep_doc.to_dict()

    snapshots = list(db.collection("schedules").stream())
    covering = [(s, s.to_dict()) for s in snapshots
                if s.to_dict().get("startDate", "") <= date_iso
                <= s.to_dict().get("endDate", "")]

    # Re-check the no-conflict rule right before writing, in case the
    # suggestion list went stale while the admin was deciding.
    if req.replacementEmployeeId in _busy_ids(
            [s for _, s in covering], date_iso):
        raise ValueError(
            f"{rep.get('name', req.replacementEmployeeId)} is already "
            f"scheduled on {date_iso} — pick someone without a conflict.")

    # The station's schedule covering that date (published wins).
    target = None
    for snap, sched in covering:
        if (sched.get("stationName") or "").strip() == station:
            if target is None or sched.get("status") == "published":
                target = (snap, sched)
    if target is None:
        raise LookupError(
            f"No schedule for {station} covers {date_iso}")

    snap, sched = target
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
    snap.reference.update({"days": sched["days"]})

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
    db.collection("replacements").document(record["id"]).set(record)

    # Stamp the attendance report record(s) so the admin screens show
    # "Replaced by ..." instead of offering the button again.
    if req.reportId:
        report_refs = [
            db.collection("attendance_reports").document(req.reportId)]
    else:
        report_refs = [d.reference for d in
                       db.collection("attendance_reports")
                       .where("date", "==", date_iso)
                       .where("station", "==", station).stream()]
    for ref in report_refs:
        snap = ref.get()
        if not snap.exists:
            continue
        data = snap.to_dict()
        changed = False
        for rec in data.get("records", []):
            if (rec.get("employeeId") == req.absentEmployeeId
                    and not rec.get("isPresent", True)):
                rec["replacedById"] = rep["id"]
                rec["replacedByName"] = rep.get("name", "")
                rec["replacedAt"] = applied_at
                changed = True
        if changed:
            ref.update({"records": data["records"]})

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
    db.collection("employee_notifications").document(
        notification["id"]).set(notification)

    # If the chosen guard volunteered for this day, close their offer so it
    # stops re-suggesting them and their availability card shows "assigned".
    offer_ref = db.collection("cover_offers").document(
        f"COV-{date_iso.replace('-', '')}-{rep['id']}")
    offer_snap = offer_ref.get()
    if offer_snap.exists and offer_snap.to_dict().get("status") != "fulfilled":
        offer_ref.update({
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
        abs_ref = db.collection("absence_requests").document(absence_id)
        abs_snap = abs_ref.get()
        # Only decide a still-pending request — never overturn a prior
        # decision, and stay idempotent if apply is retried.
        if abs_snap.exists and abs_snap.to_dict().get("status") == "pending":
            abs_ref.update({
                "status": "approved",
                "decidedAt": applied_at,
                "decidedBy": "admin",
                "coveredById": rep["id"],
                "coveredByName": rep.get("name", ""),
                "isRead": True,
            })
            db.collection("employee_notifications").document(
                f"NTF-{absence_id}-DECISION").set({
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
