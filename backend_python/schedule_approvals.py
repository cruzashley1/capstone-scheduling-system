"""Period-wide, sequential approvals. Call mutations in workflow_transaction()."""
import copy
import hashlib
import json
from datetime import date, timedelta
from uuid import uuid4

from fastapi import HTTPException
from workflow_auth import actor, now_iso, OFFICIAL_ROLES

PENDING = {"pending_assistant", "pending_commander"}
LOCKED = PENDING | {"approved"}


def fingerprint(schedule):
    # Normalize only the roster being approved. Publication and workflow
    # metadata can change without changing what the officials reviewed.
    content = {k: schedule.get(k) for k in
               ("id", "stationId", "stationName", "startDate", "endDate", "days")}
    return hashlib.sha256(json.dumps(content, sort_keys=True, ensure_ascii=False,
                                    separators=(",", ":")).encode()).hexdigest()


def event(action, who, comment=""):
    return {"action": action, "username": who["username"], "name": who["name"],
            "role": who["role"], "at": now_iso(), "comment": comment.strip()}


def notify(repo, approval, title, message, roles=None):
    for user in repo.users.list():
        if user.get("active", True) and user.get("role") in (roles or (OFFICIAL_ROLES | {"admin"})):
            key = uuid4().hex
            repo.workflow_notifications.upsert(key, {
                "id": key, "username": user["username"], "title": title,
                "message": message, "createdAt": now_iso(), "isRead": False,
                "approvalId": approval["id"],
            })


def summary(record):
    return {**{k: v for k, v in record.items() if k not in {"schedules", "currentHashes"}},
            "stationCount": len(record["schedules"]),
            "stations": [s["stationName"] for s in record["schedules"]]}


def get(repo, approval_id):
    record = repo.schedule_approvals.get(approval_id)
    if not record:
        raise HTTPException(404, "Approval submission not found.")
    return record


def period_schedules(repo, start, end):
    return sorted(repo.schedules.find(startDate=start, endDate=end),
                  key=lambda s: s.get("stationName", ""))


def validate_period(repo, schedules, start, end):
    try:
        first, last = date.fromisoformat(start), date.fromisoformat(end)
    except ValueError:
        raise HTTPException(400, "Use valid YYYY-MM-DD period dates.") from None
    if last < first or (last - first).days > 31:
        raise HTTPException(400, "Invalid schedule period.")
    stations = [s for s in repo.stations.list() if s.get("isActive", True)]
    expected = {s["id"] for s in stations}
    present = [s["stationId"] for s in schedules]
    missing = [s.get("name", s["id"]) for s in stations if s["id"] not in present]
    if missing:
        raise HTTPException(409, "Generate this exact period for all active stations first. Missing: " + ", ".join(missing))
    if not schedules or not expected or len(present) != len(set(present)):
        raise HTTPException(409, "The period must contain exactly one schedule per active station.")
    if set(present) != expected:
        raise HTTPException(409, "The period includes an inactive or removed station. Correct its schedules first.")
    dates = {(first + timedelta(days=n)).isoformat() for n in range((last - first).days + 1)}
    for s in schedules:
        days = s.get("days", [])
        if len(days) != len(dates) or {d["date"] for d in days} != dates or any(not d.get("entries") for d in days):
            raise HTTPException(409, f"{s['stationName']} has missing or empty days. Complete the roster first.")
        if any(not e.get("post") or e["post"] == "Undefined" for d in days for e in d["entries"]):
            raise HTTPException(409, f"{s['stationName']} has undefined posts. Assign every post first.")


def submit(repo, start, end, prepared_by, publish_notices, withdrawal_notices):
    who = actor("admin")
    schedules = period_schedules(repo, start, end)
    validate_period(repo, schedules, start, end)
    previous = repo.schedule_approvals.find(startDate=start, endDate=end)
    if any(r["status"] in LOCKED for r in previous):
        raise HTTPException(409, "This period is already submitted or approved. Start a revision first.")
    accounts = repo.users.list()
    for role in OFFICIAL_ROLES:
        if not any(u.get("role") == role and u.get("active", True) for u in accounts):
            raise HTTPException(409, "Create an active account for both official roles before submitting.")
    key = uuid4().hex
    record = {"id": key, "startDate": start, "endDate": end,
              "revision": max((r["revision"] for r in previous), default=0) + 1,
              "version": 1, "status": "pending_assistant", "submittedBy": who["username"],
              "submittedName": prepared_by.strip() or who["name"], "submittedAt": now_iso(),
              "schedules": copy.deepcopy(schedules),
              "currentHashes": {s["id"]: fingerprint(s) for s in schedules},
              "events": [event("submitted", who)], "amendments": []}
    repo.schedule_approvals.upsert(key, record)
    for s in schedules:
        # Legacy published records must also pass review before an official export.
        if s.get("status") == "published":
            repo.employee_notifications.upsert_many({n["id"]: n for n in withdrawal_notices(s)})
        repo.schedules.update(s["id"], {"approvalId": key,
                              "approvalStatus": record["status"], "status": "unpublished"})
    notify(repo, record, "Schedule awaiting Assistant Security", f"{start} to {end}: {len(schedules)} stations submitted for review.", {"assistantSecurity"})
    return summary(record)


def current_schedules(repo, record):
    schedules = period_schedules(repo, record["startDate"], record["endDate"])
    if {s["id"] for s in schedules} != set(record["currentHashes"]):
        raise HTTPException(409, "The schedules in this period have changed. Start a revision and submit again.")
    for s in schedules:
        if s.get("approvalId") != record["id"] or fingerprint(s) != record["currentHashes"][s["id"]]:
            raise HTTPException(409, "The roster differs from the reviewed version. Start a revision and submit again.")
    return schedules


def decide(repo, approval_id, action, comment, version, publish_notices):
    who = actor(*OFFICIAL_ROLES)
    record = get(repo, approval_id)
    expected = "pending_assistant" if who["role"] == "assistantSecurity" else "pending_commander"
    if record["status"] != expected or record["version"] != version:
        raise HTTPException(409, "This submission is not awaiting your decision. Refresh to see its current status.")
    if action not in {"approve", "return"}:
        raise HTTPException(400, "Choose approve or return.")
    if action == "return" and not comment.strip():
        raise HTTPException(400, "Explain what the admin needs to revise.")
    schedules = current_schedules(repo, record)
    if action == "approve":
        validate_period(repo, schedules, record["startDate"], record["endDate"])
    record["events"].append(event(action, who, comment))
    record["version"] += 1
    record["status"] = ("returned" if action == "return" else
                        "pending_commander" if who["role"] == "assistantSecurity" else "approved")
    for s in schedules:
        fields = {"approvalStatus": record["status"]}
        if record["status"] == "approved":
            fields["status"] = "published"
            repo.employee_notifications.upsert_many({n["id"]: n for n in publish_notices(s)})
        repo.schedules.update(s["id"], fields)
    repo.schedule_approvals.upsert(approval_id, record)
    title = {"returned": "Schedule returned for revision", "pending_commander": "Schedule awaiting Area Commander", "approved": "Schedule approved and published"}[record["status"]]
    notify(repo, record, title, f"{record['startDate']} to {record['endDate']}. {comment.strip()}")
    return summary(record)


def revise(repo, approval_id, comment, version, withdrawal_notices):
    who = actor("admin")
    record = get(repo, approval_id)
    if record["status"] not in LOCKED or record["version"] != version:
        raise HTTPException(409, "This submission has already changed. Refresh before starting a revision.")
    if not comment.strip():
        raise HTTPException(400, "Enter the reason for revising this period.")
    for snapshot in record["schedules"]:
        s = repo.schedules.get(snapshot["id"])
        if not s or s.get("approvalId") != record["id"]:
            continue
        if s.get("status") == "published":
            repo.employee_notifications.upsert_many({n["id"]: n for n in withdrawal_notices(s)})
        repo.schedules.update(s["id"], {"status": "unpublished", "approvalStatus": "draft", "approvalId": None})
    record["status"] = "withdrawn"
    record["version"] += 1
    record["events"].append(event("withdrawn_for_revision", who, comment))
    repo.schedule_approvals.upsert(approval_id, record)
    notify(repo, record, "Schedule withdrawn for revision", comment.strip())
    return summary(record)


def assert_editable(schedules):
    if any(s.get("approvalStatus") in LOCKED for s in schedules):
        raise HTTPException(409, "This period is locked for review or already approved. Use Start Revision in Period Approvals first.")


def record_emergency(repo, before, replacement, reason):
    who = actor("admin")
    after = repo.schedules.get(before["id"])
    approval_id = before.get("approvalId")
    if not approval_id:
        return  # Legacy roster still has the existing replacement audit.
    record = get(repo, approval_id)
    if record["status"] != "approved":
        raise HTTPException(409, "Emergency amendments require a published, approved schedule.")
    amendment = {"id": uuid4().hex, **event("emergency_replacement", who, reason),
                 "replacement": replacement, "scheduleId": before["id"],
                 "before": [d for d in before["days"] if d["date"] == replacement["date"]],
                 "after": [d for d in after["days"] if d["date"] == replacement["date"]]}
    record["amendments"].append(amendment)
    record["currentHashes"][after["id"]] = fingerprint(after)
    record["version"] += 1
    repo.schedule_approvals.upsert(approval_id, record)
    notify(repo, record, "Emergency schedule amendment", f"{replacement['station']} · {replacement['date']}: {replacement['absentEmployeeName']} replaced by {replacement['replacementEmployeeName']}. {reason}", OFFICIAL_ROLES)


def export_period(repo, start, end, station_id=None):
    actor("admin")
    records = [r for r in repo.schedule_approvals.find(startDate=start, endDate=end) if r["status"] == "approved"]
    if len(records) != 1:
        raise HTTPException(409, "Both officials must approve this period before printing or exporting.")
    record = records[0]
    schedules = current_schedules(repo, record)
    if any(s.get("status") != "published" for s in schedules):
        raise HTTPException(409, "This period is no longer published.")
    if station_id:
        schedules = [s for s in schedules if s["stationId"] == station_id]
        if not schedules:
            raise HTTPException(404, "Station not found in the approved period.")
    ids = {s["id"] for s in schedules}
    replacements = [r for r in repo.replacements.list() if r.get("scheduleId") in ids
                    and start <= r.get("date", "") <= end]
    return {"success": True, "schedules": schedules, "approval": summary(record),
            "replacements": replacements}
