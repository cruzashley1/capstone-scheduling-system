"""Authenticated sessions and role checks for the approval workflow."""
import hashlib
import secrets
from contextvars import ContextVar
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

OFFICIAL_ROLES = {"assistantSecurity", "areaCommander"}
actor_context = ContextVar("request_actor", default=None)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def issue_session(repo, username, role):
    raw = secrets.token_urlsafe(32)
    key = hashlib.sha256(raw.encode()).hexdigest()
    repo.auth_sessions.upsert(key, {
        "id": key, "username": username, "role": role,
        "expiresAt": (datetime.now(timezone.utc) + timedelta(days=7)).isoformat(),
    })
    return raw


def revoke_sessions(repo, username):
    repo.auth_sessions.delete_many([
        s["id"] for s in repo.auth_sessions.find(username=username)])


def authenticate(repo, header):
    if not header or not header.startswith("Bearer "):
        raise HTTPException(401, "Please sign in again.")
    key = hashlib.sha256(header[7:].encode()).hexdigest()
    session = repo.auth_sessions.get(key)
    if not session or session["expiresAt"] <= now_iso():
        raise HTTPException(401, "Your session has expired. Please sign in again.")
    username = session["username"]
    record = repo.users.get(username)
    if record is not None:
        role = record.get("role")
        active = record.get("active", True)
    else:
        record = repo.employees.get(username) or {}
        role = record.get("type")
        active = record.get("isActive", True)
    if not record or not active or role != session["role"]:
        raise HTTPException(401, "This account is no longer active. Please sign in again.")
    return {"username": username, "role": role,
            "name": record.get("name") or username, "sessionId": key}


def actor(*roles):
    value = actor_context.get()
    if value is None:
        raise HTTPException(401, "Please sign in again.")
    if roles and value["role"] not in roles:
        raise HTTPException(403, "Your role cannot perform this action.")
    return value


def authorize_request(repo, who, method, path, body):
    """Officials have only review access; guard routes retain their own scope."""
    role, username = who["role"], who["username"]
    if path in {"/account", "/logout"} or path.startswith("/workflow-notifications"):
        return
    if role == "admin":
        return
    if role in OFFICIAL_ROLES:
        if path == "/schedule-approvals" and method == "GET":
            return
        if path.startswith("/schedule-approvals/"):
            if method == "GET" or (method == "POST" and path.endswith("/decision")):
                return
        raise HTTPException(403, "Officials can review schedules and manage their own profile only.")
    if method == "GET" and (path in {"/stations", "/leave-types"}
            or path == f"/employees/{username}"
            or path.startswith(f"/employees/{username}/")):
        return
    if method == "GET" and path == "/attendance-reports" and role == "headGuard":
        return  # The endpoint returns only reports submitted by this head guard.
    if method == "PUT" and path == f"/employees/{username}" and set(body) <= {"preferredStations"}:
        return
    if method == "POST" and path == f"/employees/{username}/notifications/read-all":
        return
    if method == "POST" and path.startswith("/notifications/") and path.endswith("/read"):
        record = repo.employee_notifications.get(path.split("/")[2]) or {}
        if record.get("employeeId") == username:
            return
    if method == "POST" and path == "/confirm-stations" and body.get("username") == username:
        return
    if method == "POST" and path in {"/absence-requests", "/leave-requests", "/special-requests", "/cover-offers"}:
        if body.get("employeeId") == username:
            return
    if method == "POST" and path == "/attendance-reports" and role == "headGuard":
        if body.get("headGuardId") == username:
            return
    if method == "DELETE" and path.startswith(("/cover-offers/", "/leave-requests/")):
        collection = repo.cover_offers if path.startswith("/cover-offers/") else repo.leave_requests
        record = collection.get(path.split("/")[2]) or {}
        if record.get("employeeId") == username:
            return
    raise HTTPException(403, "Your role cannot access this action.")
