"""Approval/account HTTP routes and enforcement on existing mutation routes."""
import functools
import os
import secrets
from datetime import date, timedelta
from typing import Optional

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

import schedule_approvals as approvals
import workflow_auth as sessions


class OfficialCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    username: str = Field(min_length=3, max_length=40, pattern=r"^[A-Za-z0-9_.-]+$")
    role: str


class OfficialUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    active: Optional[bool] = None


class PeriodRequest(BaseModel):
    startDate: str
    endDate: str
    preparedBy: str = Field(default="", max_length=120)
    stationId: Optional[str] = None


class DecisionRequest(BaseModel):
    action: str = "approve"
    comment: str = Field(default="", max_length=2000)
    version: int


def install(app, namespace):
    repo = namespace["repo"]
    auth = namespace["auth"]

    @app.middleware("http")
    async def authenticate_request(request: Request, call_next):
        path = request.url.path.rstrip("/") or "/"
        if request.method == "OPTIONS" or path in {
                "/", "/server-time", "/login", "/change-password", "/verify-password"}:
            return await call_next(request)
        # Preserve first-install bootstrap without exposing it once accounts
        # exist, and require the installer to supply a non-default password.
        if path == "/init-admin" and request.method == "POST" and os.getenv("ADMIN_BOOTSTRAP_PASSWORD"):
            users = await run_in_threadpool(repo.users.list)
            if not users:
                return await call_next(request)
        try:
            who = await run_in_threadpool(sessions.authenticate, repo, request.headers.get("authorization"))
            body = {}
            if request.method in {"POST", "PUT", "PATCH"} and request.headers.get("content-type", "").startswith("application/json"):
                try:
                    body = await request.json()
                except ValueError:
                    pass
            await run_in_threadpool(sessions.authorize_request, repo, who, request.method, path, body if isinstance(body, dict) else {})
        except HTTPException as exc:
            return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)
        token = sessions.actor_context.set(who)
        try:
            return await call_next(request)
        finally:
            sessions.actor_context.reset(token)

    @app.get("/account")
    def current_account():
        who = sessions.actor()
        return {"success": True, "username": who["username"], "name": who["name"], "role": who["role"]}

    @app.post("/logout")
    def logout():
        repo.auth_sessions.delete(sessions.actor()["sessionId"])
        return {"success": True}

    @app.get("/officials")
    def list_officials():
        sessions.actor("admin")
        return {"success": True, "users": [public_user(u) for u in repo.users.list() if u.get("role") in sessions.OFFICIAL_ROLES]}

    def public_user(user):
        return {key: user.get(key) for key in ("username", "name", "role", "active")}

    @app.post("/officials")
    def create_official(request: OfficialCreate):
        sessions.actor("admin")
        if request.role not in sessions.OFFICIAL_ROLES or not request.name.strip():
            raise HTTPException(400, "Choose an official role and enter the full name.")
        username = request.username.strip()
        if repo.users.get(username) or repo.employees.get(username):
            raise HTTPException(409, "That username is already in use.")
        password = secrets.token_urlsafe(12)
        try:
            auth.create_user(uid=username, email=f"{username}@sched.internal", password=password)
        except auth.UidAlreadyExistsError:
            raise HTTPException(409, "That username is already in use.") from None
        record = {"username": username, "name": request.name.strip(), "role": request.role, "active": True}
        try:
            repo.users.upsert(username, record)
        except Exception:
            auth.delete_user(username)
            raise
        return {"success": True, "user": public_user(record), "temporaryPassword": password}

    @app.put("/officials/{username}")
    def update_official(username: str, request: OfficialUpdate):
        sessions.actor("admin")
        user = repo.users.get(username)
        if not user or user.get("role") not in sessions.OFFICIAL_ROLES:
            raise HTTPException(404, "Official account not found.")
        fields = request.model_dump(exclude_none=True)
        if "name" in fields:
            fields["name"] = fields["name"].strip()
            if not fields["name"]:
                raise HTTPException(400, "Enter the full name.")
        repo.users.update(username, fields)
        if request.active is False:
            sessions.revoke_sessions(repo, username)
        return {"success": True}

    @app.post("/officials/{username}/reset-password")
    def reset_official_password(username: str):
        sessions.actor("admin")
        user = repo.users.get(username)
        if not user or user.get("role") not in sessions.OFFICIAL_ROLES:
            raise HTTPException(404, "Official account not found.")
        password = secrets.token_urlsafe(12)
        auth.update_user(username, password=password)
        sessions.revoke_sessions(repo, username)
        return {"success": True, "temporaryPassword": password}

    @app.get("/schedule-approvals")
    def list_approvals():
        sessions.actor("admin", *sessions.OFFICIAL_ROLES)
        records = sorted(repo.schedule_approvals.list(), key=lambda r: r["submittedAt"], reverse=True)
        return {"success": True, "approvals": [approvals.summary(r) for r in records]}

    @app.post("/schedule-approvals/submit")
    def submit_period(request: PeriodRequest):
        record = approvals.submit(repo, request.startDate, request.endDate, request.preparedBy,
                                  namespace["_schedule_publish_notifications"], namespace["_schedule_withdrawn_notifications"])
        return {"success": True, "approval": record}

    @app.get("/schedule-approvals/{approval_id}")
    def get_approval(approval_id: str):
        sessions.actor("admin", *sessions.OFFICIAL_ROLES)
        return {"success": True, "approval": approvals.get(repo, approval_id)}

    @app.post("/schedule-approvals/{approval_id}/decision")
    def decide_approval(approval_id: str, request: DecisionRequest):
        record = approvals.decide(repo, approval_id, request.action, request.comment, request.version,
                                  namespace["_schedule_publish_notifications"])
        return {"success": True, "approval": record}

    @app.post("/schedule-approvals/{approval_id}/revise")
    def revise_approval(approval_id: str, request: DecisionRequest):
        record = approvals.revise(repo, approval_id, request.comment, request.version,
                                  namespace["_schedule_withdrawn_notifications"])
        return {"success": True, "approval": record}

    @app.post("/schedule-report")
    def approved_report(request: PeriodRequest):
        return approvals.export_period(repo, request.startDate, request.endDate, request.stationId)

    @app.get("/workflow-notifications")
    def notifications():
        records = repo.workflow_notifications.find(username=sessions.actor()["username"])
        return {"success": True, "notifications": sorted(records, key=lambda n: n["createdAt"], reverse=True)[:100]}

    @app.post("/workflow-notifications/{notification_id}/read")
    def read_notification(notification_id: str):
        record = repo.workflow_notifications.get(notification_id)
        if not record or record["username"] != sessions.actor()["username"]:
            raise HTTPException(404, "Notification not found.")
        repo.workflow_notifications.update(notification_id, {"isRead": True})
        return {"success": True}

    def guard_existing(name, kwargs):
        if name in {"publish_schedule", "publish_all_schedules"}:
            raise HTTPException(409, "Direct publishing is disabled. Submit the whole period for Assistant Security and Area Commander approval.")
        if "schedule_id" in kwargs:
            record = repo.schedules.get(kwargs["schedule_id"])
            if record:
                approvals.assert_editable([record])
        if name == "delete_schedules":
            scope = kwargs.get("status", "all")
            approvals.assert_editable([s for s in repo.schedules.list() if scope == "all" or s.get("status") == scope])
        if name == "generate_schedules":
            req = kwargs["request"]
            try:
                end = (date.fromisoformat(req.startDate) + timedelta(days=14)).isoformat()
            except ValueError:
                raise HTTPException(400, "Use a valid start date.") from None
            approvals.assert_editable([s for s in repo.schedules.list() if s["startDate"] <= end and s["endDate"] >= req.startDate])
        if name in {"update_station", "delete_station"}:
            # A rename rewrites existing schedule headers. Deletion cascades.
            old = repo.stations.get(kwargs["station_id"])
            req = kwargs.get("request")
            if name == "delete_station" or (old and req and req.name and req.name != old.get("name")):
                approvals.assert_editable(repo.schedules.find(stationId=kwargs["station_id"]))

    def protected(endpoint):
        @functools.wraps(endpoint)
        def wrapped(**kwargs):
            with repo.workflow_transaction():
                guard_existing(endpoint.__name__, kwargs)
                return endpoint(**kwargs)
        return wrapped

    # Apply the same transaction to old and new write routes, including
    # replacement writes in repositories.from_db(). The connection context
    # follows every repository instance on this request's worker thread.
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        if (route.methods - {"GET", "HEAD"}) and route.path.startswith((
                "/schedules", "/schedule-approvals", "/schedule-report", "/stations", "/replacements/apply", "/officials")):
            route.dependant.call = protected(route.endpoint)
