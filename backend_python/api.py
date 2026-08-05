import os
import random
import string
from collections import Counter
from datetime import datetime, time, timedelta, timezone
from typing import List, Optional
from dotenv import load_dotenv
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

import firebase_init
import passwords
# Resolved through firebase_init so development mode can swap in the offline
# stand-ins (see USE_MOCK_DB in firebase_init.py).
auth = firebase_init.get_auth()

# Chooses the repository for the active backend. Firestore and the mock are
# still reached through `db` below; `repo` is the seam Supabase will arrive
# on, and collections move onto it one at a time (see repositories/base.py).
import db_backend

from models.employee import EmployeeCreateRequest, EmployeeUpdateRequest, _role_to_type
from models.station import (HEAD_GUARD_POST, StationCreateRequest,
                            StationPosts, StationPostTimes,
                            StationUpdateRequest)
from models.auth import LoginRequest, ChangePasswordRequest, ConfirmStationsRequest
from models.schedule import (ScheduleAssignmentUpdateRequest,
                             ScheduleEmployeeAddRequest,
                             ScheduleGenerateRequest,
                             SchedulePostUpdateRequest)
from models.attendance import AttendanceReportCreateRequest
from models.absence import (AbsenceRequestCreateRequest,
                            AbsenceRequestDecisionRequest)
from models.special_request import (SpecialRequestCreateRequest,
                                    SpecialRequestDecisionRequest)
from models.leave import (AdminLeaveCreateRequest, LeaveCancelRequest,
                          LeaveDecisionRequest, LeaveRequestCreateRequest)
from models.replacement import ReplacementApplyRequest
from models.cover_offer import CoverOfferCreateRequest
from models.special_assignment import (SpecialAssignmentSaveRequest,
                                       validate_shift)
import scheduler
import rotation
import station_pools
import station_posts
import replacements
import leave

# 1. Load the environment variables from .env
load_dotenv()

# Global variable for the database
db = None


class _RepositoryProxy:
    """Resolves the repository from whatever `db` currently holds.

    `repo` cannot simply be assigned next to `db` in lifespan, because
    lifespan is not the only way into this module: testing_*.py imports
    api and calls the endpoint functions directly, setting `api.db`
    itself (see testing_station_rename.py, testing_special_conflict.py).
    A repository bound once at startup would still be None there, and
    every migrated call site would fail with an AttributeError on None —
    which is exactly what happened, and which the golden files could not
    catch because they go through a running server.

    Resolving on access keeps the two in step however api.py is entered,
    and rebuilds only when `db` itself is swapped.
    """

    _bound = None  # (db_handle, repository)

    def __getattr__(self, name):
        if db is None:
            raise RuntimeError(
                "Database not initialized — set api.db before using api.repo")
        if _RepositoryProxy._bound is None or _RepositoryProxy._bound[0] is not db:
            _RepositoryProxy._bound = (db, db_backend.get_repository(db))
        return getattr(_RepositoryProxy._bound[1], name)


# The repository over that same database. Collections that have been
# migrated are read through this; the rest still use `db` directly.
repo = _RepositoryProxy()

# 2. Fetch the secret key safely
FIREBASE_WEB_API_KEY = os.getenv("FIREBASE_WEB_API_KEY")

if not FIREBASE_WEB_API_KEY:
    print("⚠️ WARNING: Firebase Web API Key not found in .env file!")

@asynccontextmanager
async def lifespan(app: FastAPI):
    global db
    print("Initializing Firebase...")
    try:
        # `repo` needs no assignment here — it resolves from `db` on use,
        # so it cannot go stale or stay unset on the paths that skip
        # lifespan entirely.
        db = firebase_init.get_db()
        print(f"Firebase connected successfully! "
              f"(backend: {db_backend.active_backend()})")
    except Exception as e:
        print(f"CRITICAL: Firebase failed to initialize: {e}")
    
    yield

# Initialize FastAPI with the lifespan handler
app = FastAPI(lifespan=lifespan)

# --- CORS Middleware Setup ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        
    allow_credentials=True,
    allow_methods=["*"],        
    allow_headers=["*"],        
)

# --- Data Models ---
# NOTE: EmployeeCreateRequest, EmployeeUpdateRequest, StationCreateRequest,
# and LoginRequest now live in models/employee.py, models/station.py, and
# models/auth.py (imported above).

# --- Routes ---
@app.get("/")
def root():
    return {"message": "Python backend is running"}


@app.get("/server-time")
def get_server_time():
    """The authoritative clock. Every duty-time decision in the app —
    which duty day a night head guard is on, whether an attendance report
    is inside its shift window, whether an emergency absence is still
    inside its cut-off — has to be settled against this rather than the
    device clock, which the user can simply change.

    `now` is the server's LOCAL wall clock, because that is what the
    schedules and shift windows (0500H, 1700H, ...) are expressed in. The
    app stores the offset between this and its own clock and applies it
    from then on, so it needs one call, not one per check."""
    now = datetime.now()
    return {
        "success": True,
        "now": now.isoformat(timespec="milliseconds"),
        "epochMs": int(now.timestamp() * 1000),
    }

@app.post("/init-admin")
def initialize_admin():
    """Run this endpoint ONCE to generate the default admin account."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    username = "admin01"
    # Read from the environment so the bootstrap credential is not a
    # constant sitting in a source file (and in git history). .env is
    # git-ignored; the fallback keeps existing development setups and
    # DEV_MODE.md working, and is announced loudly when it is used.
    password = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "").strip()
    if not password:
        password = "adminpassword123"
        print("⚠️  ADMIN_BOOTSTRAP_PASSWORD is not set — creating the admin "
              "with the documented development default. Set it in .env "
              "before deploying.")
    masked_email = f"{username}@schedulingsystem.local"
    
    try:
        # 1. Create the user in Firebase Auth
        user_record = auth.create_user(
            email=masked_email,
            password=password,
            uid=username 
        )
        
        # 2. Save their role in Firestore
        repo.users.upsert(username, {
            "username": username,
            "role": "admin",
            "active": True
        })
        
        return {"message": f"Success! Admin account '{username}' created."}
    
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to create admin: {str(e)}")

@app.post("/login")
def login(request: LoginRequest):
    """Handles login by talking to the Firebase Auth REST API."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    # Verifies against Firebase Auth (or the offline store in mock mode);
    # the masked-email trick lives inside firebase_init.verify_password.
    if not firebase_init.verify_password(request.username, request.password):
        raise HTTPException(status_code=401, detail="Invalid username or password")
        
    # If Auth succeeds, fetch the user's role from Firestore
    try:
        # 1. First, check the 'users' collection (for Admin)
        user_data = repo.users.get(request.username)
        if user_data is not None:
            return {
                "message": "Login successful",
                "role": user_data.get("role", "regular"), # Admins use the 'role' key
                "mustChangePassword": False # Admins are never forced to change
            }

        # 2. Next, check the 'employees' collection (for Guards/Staff)
        emp_data = repo.employees.get(request.username)
        if emp_data is not None:
            return {
                "message": "Login successful",
                "role": emp_data.get("type", "regular"), # Employees use the 'type' key
                # Employees must replace their auto-generated password before
                # entering the app. Older records without the flag default to
                # True because they are still on their generated password.
                "mustChangePassword": emp_data.get("mustChangePassword", True),
                # After the password change, employees confirm their preferred
                # stations once. Older records without the flag default to True
                # so every existing employee is prompted to confirm the
                # preferences already stored on their record.
                "mustSelectStations": emp_data.get("mustSelectStations", True),
                # Sent so the onboarding picker can open pre-selected with the
                # preferences already on the record.
                "preferredStations": emp_data.get("preferredStations", []),
            }

        # 3. If they aren't in either collection, throw an error
        raise HTTPException(status_code=404, detail="User role not found in database")
        
    except HTTPException:
        raise # Rethrow the 404 so it doesn't get caught by the block below
    except Exception as e:
        raise HTTPException(status_code=500, detail="Database error while fetching role")


@app.post("/verify-password")
def verify_password(request: LoginRequest):
    """Re-checks a user's own password without logging them in.

    Used to gate Developer mode in admin Settings: turning the device-time
    override ON has to be re-authenticated, because that override is the
    one thing that can move duty windows off the server clock. Returns
    401 on a wrong password rather than leaking whether the account
    exists, and never returns the stored password."""
    if not firebase_init.verify_password(request.username, request.password):
        raise HTTPException(status_code=401, detail="Password is incorrect.")
    return {"success": True}


@app.post("/change-password")
def change_password(request: ChangePasswordRequest):
    """Lets an employee replace their auto-generated password. Verifies the
    current password against Firebase Auth first, then updates both the
    Auth user and the Firestore record (which clears mustChangePassword)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    new_password = request.newPassword.strip()
    if len(new_password) < 8:
        raise HTTPException(status_code=400, detail="New password must be at least 8 characters.")
    if new_password == request.currentPassword:
        raise HTTPException(status_code=400, detail="New password must be different from the current one.")

    # Re-verify the current password the same way /login does
    if not firebase_init.verify_password(request.username, request.currentPassword):
        raise HTTPException(status_code=401, detail="Current password is incorrect.")

    try:
        # Update the real login credential in Firebase Auth
        auth.update_user(request.username, password=new_password)

        # The record keeps only the mask — the new password lives in
        # Firebase Auth (or the hashed mock store) and nowhere else.
        # Clearing the flag sends the next login straight to the dashboard.
        employee_ref = db.collection("employees").document(request.username)
        if employee_ref.get().exists:
            employee_ref.update({
                "password": passwords.MASK,
                "mustChangePassword": False,
            })

        return {"success": True, "message": "Password updated successfully."}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to change password: {str(e)}")


@app.post("/confirm-stations")
def confirm_stations(request: ConfirmStationsRequest):
    """Saves the employee's confirmed preferred stations during onboarding
    and clears the mustSelectStations flag so the picker is shown only once.
    Returns the updated employee record."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        employee_ref = db.collection("employees").document(request.username)
        if not employee_ref.get().exists:
            raise HTTPException(status_code=404, detail="Employee not found.")

        employee_ref.update({
            "preferredStations": request.preferredStations,
            "mustSelectStations": False,
        })

        return {"success": True, "employee": employee_ref.get().to_dict()}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to save preferred stations: {str(e)}")


# --- Employee Registration ---

def _get_next_sequence_number() -> int:
    """
    Atomically increments a counter stored at counters/employee_counter.
    Using a transaction (instead of just counting existing employees)
    means the number keeps climbing even if employees are later deleted,
    so two people can never end up with the same username/password.
    """
    return repo.next_sequence("employee_counter")


def _generate_credentials(full_name: str, seq_number: int):
    """
    username: first 3 letters of last name + 3-digit sequence  -> CLA001
    password: full last name + 3-digit sequence + 2 random letters -> CLARISE001AB
    """
    last_name = full_name.strip().split(" ")[-1].upper()
    seq_str = str(seq_number).zfill(3)
    username = f"{last_name[:3]}{seq_str}"
    random_letters = "".join(random.choices(string.ascii_uppercase, k=2))
    password = f"{last_name}{seq_str}{random_letters}"
    return username, password


@app.post("/employees")
def create_employee(request: EmployeeCreateRequest):
    """Registers a new employee: generates credentials, creates their
    Firebase Auth login, and saves the record to Firestore."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        seq_number = _get_next_sequence_number()
        username, password = _generate_credentials(request.name, seq_number)
        masked_email = f"{username}@schedulingsystem.local"

        # Create the login so this employee can sign in later using the
        # same masked-email trick as the admin account.
        auth.create_user(email=masked_email, password=password, uid=username)

        employee_data = {
            "id": username,
            "name": request.name,
            "phone": request.mobileNo,
            "email": request.email or "",
            "preferredStations": request.preferredStations,
            "type": _role_to_type(request.role),
            "username": username,
            # The record never keeps the password itself — only Firebase
            # Auth (or the hashed mock store) holds a verifiable copy.
            # The generated password is returned once, below, which is
            # what the "share these login details" dialog displays.
            "password": passwords.MASK,
            "dateJoined": datetime.now(timezone.utc).isoformat(),
            "isActive": True,
            # Forces the first-login password change before the employee
            # can reach their dashboard.
            "mustChangePassword": True,
            # After the password change, the employee confirms their preferred
            # stations once before reaching the dashboard.
            "mustSelectStations": True,
        }

        db.collection("employees").document(username).set(employee_data)

        # The one and only time the generated password is readable. The
        # admin shares it with the guard, who must replace it on first
        # login (mustChangePassword). It is not persisted anywhere in
        # readable form, so it cannot be looked up again — only reset.
        return {"success": True,
                "employee": {**employee_data, "password": password}}

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to create employee: {str(e)}")


@app.put("/employees/{employee_id}")
def update_employee(employee_id: str, request: EmployeeUpdateRequest):
    """Updates only the fields provided. username/password/dateJoined
    are never touched here — those are set once at creation."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    updates = {k: v for k, v in request.dict().items() if v is not None}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided to update")

    try:
        doc_ref = db.collection("employees").document(employee_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404, detail="Employee not found")

        doc_ref.update(updates)
        updated_doc = doc_ref.get().to_dict()
        return {"success": True, "employee": updated_doc}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to update employee: {str(e)}")


@app.post("/employees/{employee_id}/reset-password")
def reset_employee_password(employee_id: str):
    """Issues a NEW password for an employee and returns it once.

    This replaces looking a password up. Hashes cannot be reversed, so
    when a guard forgets theirs the admin does not read the old one —
    they mint a new one, read it out, and the guard is forced to replace
    it on their next login just like a freshly created account.

    The returned password is not stored anywhere in readable form. If the
    admin closes the dialog without noting it down, the fix is to reset
    again, not to look it up.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    employee = repo.employees.get(employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    new_password = passwords.generate_password()

    try:
        # The credential store first: if this fails the employee keeps
        # their old password, rather than being locked out by a record
        # that says the password changed when it did not.
        auth.update_user(employee_id, password=new_password)
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to reset the login for {employee_id}: {str(e)}")

    db.collection("employees").document(employee_id).update({
        "password": passwords.MASK,
        # Same first-login rule a new account gets: the guard replaces
        # the issued password before reaching their dashboard.
        "mustChangePassword": True,
    })

    return {
        "success": True,
        "employeeId": employee_id,
        "name": employee.get("name", ""),
        "username": employee.get("username", employee_id),
        "password": new_password,
        "message": "Share this password with the employee. "
                   "It will not be shown again.",
    }


@app.delete("/employees/{employee_id}")
def delete_employee(employee_id: str):
    """Deletes an employee's Firestore record and their Firebase Auth login."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        db.collection("employees").document(employee_id).delete()

        # Also remove their login so they can't sign in anymore.
        # Safe to ignore if the auth user was already missing.
        try:
            auth.delete_user(employee_id)
        except Exception:
            pass

        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to delete employee: {str(e)}")


@app.get("/employees")
def get_employees():
    """Returns every employee, used by the Employee List screen."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        employees = repo.employees.list()
        return {"success": True, "employees": employees}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch employees: {str(e)}")


@app.get("/employees/{employee_id}")
def get_employee(employee_id: str):
    """Returns one employee's record, used by the guard-facing profile
    and dashboard screens after login."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        employee = repo.employees.get(employee_id)
        if employee is None:
            raise HTTPException(status_code=404, detail="Employee not found")
        return {"success": True, "employee": employee}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch employee: {str(e)}")


@app.get("/employees/{employee_id}/schedule")
def get_employee_schedule(employee_id: str):
    """Returns the employee's own shifts pulled out of every PUBLISHED
    schedule (guards never see unpublished drafts), plus the periods of
    the schedules they appear in so the app can mark rest days.

    One period per DATE RANGE, not per schedule document. A reliever is
    topped up towards their 12 days across the stations within reach of
    their own (scheduler._plan_group_cover), so one 15-day period now
    puts them in several stations' documents at once. Returned raw, that
    read as several overlapping periods: the admin's View Schedule dialog
    drew a separate 15-row table per station, each showing the two days
    worked there and thirteen "Day Off"s, and the guard's own schedule
    screen listed every upcoming date once per station. Merging them
    restores one period covering the fortnight, with `stationNames`
    naming every station worked in it — the per-day station still rides
    on each shift.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        shifts, appearances = [], []
        for schedule in repo.schedules.find(status="published"):
            appears = False
            for day in schedule.get("days", []):
                for entry in day.get("entries", []):
                    if entry.get("employeeId") != employee_id:
                        continue
                    appears = True
                    shifts.append({
                        "date": day.get("date"),
                        "scheduleId": schedule.get("id"),
                        "stationId": schedule.get("stationId"),
                        "stationName": schedule.get("stationName"),
                        "shift": entry.get("shift"),
                        # This guard's own duty window off the station's
                        # stagger ladder. The app prefers it over the
                        # shift's base hours, so a guard on the third
                        # morning post reads 0700H - 1600H rather than
                        # everyone's 0500H. Null on schedules generated
                        # before posts carried times.
                        "timeIn": entry.get("timeIn"),
                        "timeOut": entry.get("timeOut"),
                        "isReliever": entry.get("isReliever", False),
                        "coveringFor": entry.get("coveringFor"),
                    })
            if appears:
                appearances.append(schedule)

        shifts.sort(key=lambda s: s.get("date", ""))

        # Days worked per schedule document, so the merged period can name
        # the station the guard actually spent the period at rather than
        # whichever document happened to be read first.
        days_at = Counter(s.get("scheduleId") for s in shifts)

        by_range = {}
        for schedule in appearances:
            key = (schedule.get("startDate"), schedule.get("endDate"))
            by_range.setdefault(key, []).append(schedule)

        periods = []
        for (start, end), covering in sorted(by_range.items(),
                                             key=lambda kv: kv[0][0] or ""):
            # Busiest station first. It leads `stationNames`, and it is
            # what the scalar stationName / stationId / scheduleId report,
            # since those predate roaming and every caller reads them as
            # "the station for this period".
            covering.sort(key=lambda s: (-days_at[s.get("id")],
                                         s.get("stationName") or ""))
            periods.append({
                "scheduleId": covering[0].get("id"),
                "stationId": covering[0].get("stationId"),
                "stationName": covering[0].get("stationName"),
                "startDate": start,
                "endDate": end,
                "stationNames": [s.get("stationName") for s in covering],
                "scheduleIds": [s.get("id") for s in covering],
            })
        return {"success": True, "shifts": shifts, "periods": periods}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch employee schedule: {str(e)}")


@app.get("/employees/{employee_id}/station-overview")
def get_station_overview(employee_id: str, date: Optional[str] = None):
    """A day's roster for the employee's station, built from the published
    schedule covering that day — used by the Head Guard dashboard. Returns
    who is on duty, and who is off (with their next duty).

    `date` (YYYY-MM-DD) defaults to today. The phone passes an explicit
    date for the after-midnight tail of an overnight duty: a night head
    guard on post at 0200H is still working YESTERDAY's roster, and that
    is the one they report on (see DutyClock.activeDutyDate)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    emp = repo.employees.get(employee_id)
    if emp is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    if date is None:
        date_iso = datetime.now().date().isoformat()
    else:
        try:
            date_iso = datetime.strptime(date, "%Y-%m-%d").date().isoformat()
        except ValueError:
            raise HTTPException(status_code=400,
                                detail="date must be YYYY-MM-DD")
    station = (emp.get("assignedStation") or "").strip()

    try:
        published = repo.schedules.find(status="published")
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch schedules: {str(e)}")

    active = [s for s in published
              if s.get("startDate", "") <= date_iso <= s.get("endDate", "")]

    # Which station's roster this employee actually belongs to.
    #
    # `assignedStation` is only their PERMANENT posting. The monthly
    # rotation engine (rotation.py) moves guards to a different station
    # for the cycle, so it must not be consulted first: doing so handed a
    # rotated head guard the roster of a station they no longer work at,
    # where they don't appear at all — which locked them out of their own
    # attendance report, and before that let them file one against the
    # wrong station's guards entirely.
    #
    # Resolution order, most specific first:
    #   1. the schedule that rosters them on this date  — where they work
    #   2. the schedule that rosters them anywhere this period — their
    #      rotated station on a rest day
    #   3. their permanent assignedStation — not rotated/scheduled at all
    def _rosters_employee(schedule, on_date=None):
        for day in schedule.get("days", []):
            if on_date is not None and day.get("date") != on_date:
                continue
            if any(e.get("employeeId") == employee_id
                   for e in day.get("entries", [])):
                return True
        return False

    target = next((s for s in active if _rosters_employee(s, date_iso)), None)
    if target is None:
        target = next((s for s in active if _rosters_employee(s)), None)
    if target is None and station:
        target = next((s for s in active
                       if (s.get("stationName") or "").strip() == station), None)

    if target is None:
        return {"success": True, "overview": {
            "stationName": station or None,
            "date": date_iso,
            "hasSchedule": False,
            "onDuty": [],
            "dayOff": [],
        }}

    entries_by_date = {}
    names = {}  # employeeId -> employeeName, everyone in the schedule
    for day in target.get("days", []):
        entries_by_date[day.get("date")] = day.get("entries", [])
        for e in day.get("entries", []):
            names[e.get("employeeId")] = e.get("employeeName")

    shift_order = {"Morning": 0, "Afternoon": 1, "Night": 2,
                   "HG Day": 3, "HG Night": 4}
    on_duty = sorted(
        ({"employeeId": e.get("employeeId"),
          "employeeName": e.get("employeeName"),
          "shift": e.get("shift"),
          "post": e.get("post"),
          "timeIn": e.get("timeIn"),
          "timeOut": e.get("timeOut"),
          "isReliever": e.get("isReliever", False),
          "coveringFor": e.get("coveringFor")}
         for e in entries_by_date.get(date_iso, [])),
        key=lambda e: (shift_order.get(e["shift"], 9), e["employeeName"] or ""))

    on_duty_ids = {e["employeeId"] for e in on_duty}
    day_off = []
    for emp_id, name in names.items():
        if emp_id in on_duty_ids:
            continue
        next_date = next_shift = None
        for date_str in sorted(entries_by_date):
            if date_str <= date_iso:
                continue
            entry = next((e for e in entries_by_date[date_str]
                          if e.get("employeeId") == emp_id), None)
            if entry:
                next_date, next_shift = date_str, entry.get("shift")
                break
        day_off.append({"employeeId": emp_id, "employeeName": name,
                        "nextDutyDate": next_date, "nextShift": next_shift})
    day_off.sort(key=lambda e: (e["nextDutyDate"] or "9999",
                                e["employeeName"] or ""))

    return {"success": True, "overview": {
        "stationName": (target.get("stationName") or "").strip(),
        "date": date_iso,
        "hasSchedule": True,
        "onDuty": on_duty,
        "dayOff": day_off,
    }}


# --- Station Registration ---

def _get_next_station_sequence_number() -> int:
    """
    Same atomic-counter approach as _get_next_sequence_number(), but
    stored separately at counters/station_counter so employee and
    station numbering never collide or skip each other's counts.
    """
    return repo.next_sequence("station_counter")


def _validate_station_shape(required, posts):
    """Shared rules for the per-shift station setup.

    `required` is {shift: int} and `posts` is {shift: [names]}. Raises on
    anything structurally wrong; a post list SHORTER than its required
    number is deliberately allowed — those slots generate as Undefined
    and the admin is warned in Edit Station rather than blocked.
    """
    for shift, count in required.items():
        if count < 0:
            raise HTTPException(
                status_code=400,
                detail=f"{shift} required number cannot be negative")
    if sum(required.values()) <= 0:
        raise HTTPException(
            status_code=400,
            detail="A station needs at least one required post across the "
                   "three shifts")

    for shift, names in posts.items():
        count = required.get(shift, 0)
        if len(names) > count:
            raise HTTPException(
                status_code=400,
                detail=f"{shift} has {len(names)} posts but only asks for "
                       f"{count} — remove a post or raise the number")
        hg = names.count(HEAD_GUARD_POST)
        # The day head guard's 12-hour duty already covers the afternoon,
        # so an afternoon Head Guard post would double-book the role.
        if shift == "afternoon" and hg:
            raise HTTPException(
                status_code=400,
                detail="The afternoon has no Head Guard post — the day head "
                       "guard's 12-hour duty already covers it")
        if hg > 1:
            raise HTTPException(
                status_code=400,
                detail=f"{shift} can only have one Head Guard post")
        if hg and names[0] != HEAD_GUARD_POST:
            raise HTTPException(
                status_code=400,
                detail=f"The Head Guard must be the first {shift} post")
        if count and shift in ("morning", "night") and not hg:
            raise HTTPException(
                status_code=400,
                detail=f"The {shift} shift must keep its Head Guard post")


def _resolve_station_times(posts, post_times):
    """The `postTimes` to save, one window per entry in `posts`.

    Whatever the client sent is run back through the stagger ladder
    (station_posts.normalize_post_times), so the stored windows are always
    self-consistent with the post lists: slots left on `auto` are
    recomputed from their position, hand-pinned ones are kept, and the
    head guard's fixed 12-hour duty always wins. A station saved with no
    times at all is timed entirely by the ladder.
    """
    post_times = post_times or {}
    return {
        shift: station_posts.normalize_post_times(
            shift, posts.get(shift, []) or [], post_times.get(shift) or [])
        for shift in ("morning", "afternoon", "night")
    }


@app.post("/stations")
def create_station(request: StationCreateRequest):
    """Registers a new station with an auto-generated sequential ID
    (e.g. STA001) and saves it to Firestore.

    The station is configured per shift: a required number and the named
    posts making it up, for morning / afternoon / night. requiredEmployees
    is derived (the daily total) for the screens that show one number."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    required = {
        "morning": request.requiredMorning,
        "afternoon": request.requiredAfternoon,
        "night": request.requiredNight,
    }
    posts = (request.posts or StationPosts()).cleaned()
    _validate_station_shape(required, posts)
    post_times = _resolve_station_times(
        posts, (request.postTimes or StationPostTimes()).cleaned())

    try:
        seq_number = _get_next_station_sequence_number()
        station_id = f"STA{str(seq_number).zfill(3)}"

        station_data = {
            "id": station_id,
            "name": request.name,
            "requiredMorning": required["morning"],
            "requiredAfternoon": required["afternoon"],
            "requiredNight": required["night"],
            "requiredEmployees": sum(required.values()),
            "posts": posts,
            "postTimes": post_times,
            "isActive": True,
        }

        db.collection("stations").document(station_id).set(station_data)

        return {"success": True, "station": station_data}

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to create station: {str(e)}")


@app.put("/stations/{station_id}")
def update_station(station_id: str, request: StationUpdateRequest):
    """Updates only the fields provided (name, the per-shift required
    numbers and/or the per-shift post lists). The station ID is generated
    once at creation and never changes.

    Shift numbers and posts are validated against the station's resulting
    state, not just the payload, so updating one shift can't leave another
    inconsistent."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    updates = {k: v for k, v in request.dict().items() if v is not None}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided to update")

    if "posts" in updates:
        updates["posts"] = request.posts.cleaned()
    if "postTimes" in updates:
        updates["postTimes"] = request.postTimes.cleaned()

    try:
        doc_ref = db.collection("stations").document(station_id)
        snapshot = doc_ref.get()
        if not snapshot.exists:
            raise HTTPException(status_code=404, detail="Station not found")

        current = snapshot.to_dict() or {}
        previous_name = current.get("name", "")

        # Validate the station as it will look AFTER the merge, so a
        # payload that only touches one shift can't leave another one
        # inconsistent (e.g. dropping morning to 3 while 6 posts remain).
        if any(k in updates for k in
               ("requiredMorning", "requiredAfternoon", "requiredNight",
                "posts", "postTimes")):
            required = {
                shift: updates.get(field, current.get(field, 0) or 0)
                for shift, field in (("morning", "requiredMorning"),
                                     ("afternoon", "requiredAfternoon"),
                                     ("night", "requiredNight"))
            }
            existing_posts = current.get("posts") or {}
            posts = {
                shift: list((updates.get("posts") or {}).get(
                    shift, existing_posts.get(shift, []) or []))
                for shift in ("morning", "afternoon", "night")
            }
            _validate_station_shape(required, posts)
            # The headline total the station cards and dashboard read is
            # always derived — never sent by the client.
            updates["requiredEmployees"] = sum(required.values())

            # Times are re-derived against the post lists as they will
            # look AFTER the merge, so an edit that only renames a post
            # still re-staggers the slots around it — and a station that
            # has never been timed picks up the ladder here.
            existing_times = current.get("postTimes") or {}
            updates["postTimes"] = _resolve_station_times(
                posts,
                {shift: list((updates.get("postTimes") or {}).get(
                    shift, existing_times.get(shift, []) or []))
                 for shift in ("morning", "afternoon", "night")})

        doc_ref.update(updates)

        # Keep the denormalized stationName on existing schedules in sync
        # so Schedule Management and Station Detail keep matching up.
        if "name" in updates:
            batch = db.batch()
            for doc in (db.collection("schedules")
                        .where("stationId", "==", station_id).stream()):
                batch.update(doc.reference, {"stationName": updates["name"]})

            # Employees and special assignments point at a station by NAME
            # (that's the key scheduler.py buckets its staff by), so a
            # rename that only touched schedules used to strand every
            # guard posted here: their assignedStation would name a
            # station that no longer exists and they'd drop out of the
            # next generated schedule entirely.
            for doc in (db.collection("employees")
                        .where("assignedStation", "==", previous_name).stream()):
                batch.update(doc.reference,
                             {"assignedStation": updates["name"]})
            for doc in (db.collection(SPECIAL_ASSIGNMENTS)
                        .where("stationId", "==", station_id).stream()):
                batch.update(doc.reference, {"stationName": updates["name"]})
            batch.commit()

        return {"success": True, "station": doc_ref.get().to_dict()}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to update station: {str(e)}")


@app.delete("/stations/{station_id}")
def delete_station(station_id: str):
    """Deletes a station and every schedule that was generated for it,
    so orphaned schedules never show up in Schedule Management."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("stations").document(station_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404, detail="Station not found")

        batch = db.batch()
        for doc in (db.collection("schedules")
                    .where("stationId", "==", station_id).stream()):
            batch.delete(doc.reference)
        # Pins outlive the schedules they influenced, so they have to go
        # too — a leftover pin would keep naming a deleted station.
        for doc in (db.collection(SPECIAL_ASSIGNMENTS)
                    .where("stationId", "==", station_id).stream()):
            batch.delete(doc.reference)
        batch.delete(doc_ref)
        batch.commit()

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to delete station: {str(e)}")


@app.get("/stations")
def get_stations():
    """Returns every station, used by the Station Management screen."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        stations = repo.stations.list()
        return {"success": True, "stations": stations}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch stations: {str(e)}")


@app.get("/stations/pools")
def get_station_pools():
    """Station -> personnel that can possibly be deployed there.

    Per station: `preferred` guards picked it themselves (assigned or in
    their preferredStations); `adjacent` guards are reachable only via
    the group-adjacency exception rule (one group over, never two). The
    index is built on demand from live data — nothing is persisted, so it
    can never go stale when preferences change."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        stations = repo.stations.list()
        employees = [emp for emp in repo.employees.list()
                     if emp.get("isActive", True)]
        pools = station_pools.build_station_pools(stations, employees)
        station_id_of = {s["name"].strip(): s.get("id", "") for s in stations}

        def brief(emp):
            return {"id": emp["id"], "name": emp.get("name", ""),
                    "type": emp.get("type", "")}

        payload = sorted(
            (
                {
                    "stationId": station_id_of.get(name, ""),
                    "stationName": name,
                    "group": pool["group"],
                    "preferredCount": len(pool["preferred"]),
                    "adjacentCount": len(pool["adjacent"]),
                    "preferred": [brief(e) for e in pool["preferred"]],
                    "adjacent": [brief(e) for e in pool["adjacent"]],
                }
                for name, pool in pools.items()
            ),
            key=lambda p: p["stationId"],
        )
        return {"success": True, "pools": payload}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to build station pools: {str(e)}")


# --- Special Assignments ---
#
# A pin from Station Management: "this guard works THIS station for THIS
# month, whatever the rotation engine would otherwise have decided".
# Documents are keyed {cycleId}_{employeeId}, which buys two things for
# free — one employee can never hold two pins in the same month, and
# re-pinning them somewhere else is a plain overwrite rather than a
# delete-then-create that could half-fail.

SPECIAL_ASSIGNMENTS = "special_assignments"


@app.get("/special-assignments")
def get_special_assignments(cycleId: Optional[str] = None):
    """Returns every pin, or just one cycle's when cycleId is given.

    Station Management asks for a whole cycle at once so it can badge
    each card with a count and warn when a guard the admin is about to
    pin is already pinned somewhere else that month.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        filters = {"rotationCycleId": cycleId} if cycleId else {}
        return {"success": True,
                "specialAssignments": repo.special_assignments.find(**filters)}
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to fetch special assignments: {str(e)}")


@app.get("/special-assignments/duty-status")
def get_duty_status(cycleId: str):
    """Where every employee is already rostered during one cycle's month.

    Declared under /special-assignments rather than /employees because
    "/employees/{employee_id}" would swallow the path, and because this
    only exists for the Special Assignments picker: pinning someone who
    is already on another station's saved schedule for these dates is
    exactly what strands that station's roster, so the picker says so up
    front instead of letting the admin find out at generation time.

    Returns {employeeId: [{stationId, stationName, startDate, endDate,
    status, isReliever}]} — one entry per schedule they appear in.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    if not (len(cycleId) == 6 and cycleId.isdigit()):
        raise HTTPException(status_code=400,
                            detail="cycleId must look like '202607'")

    year, month = int(cycleId[:4]), int(cycleId[4:])
    if not 1 <= month <= 12:
        raise HTTPException(status_code=400,
                            detail="cycleId must name a real month")
    month_start = datetime(year, month, 1).date()
    # Day 0 of the next month is the last day of this one.
    month_end = (datetime(year + month // 12, month % 12 + 1, 1)
                 - timedelta(days=1)).date()
    start_iso, end_iso = month_start.isoformat(), month_end.isoformat()

    try:
        duty = {}
        for schedule in repo.schedules.list():
            if (schedule.get("endDate", "") < start_iso
                    or schedule.get("startDate", "") > end_iso):
                continue

            # One row per employee per schedule, not per shift — the
            # picker shows where they are, not how many days they work.
            seen = {}
            for day in schedule.get("days", []):
                for entry in day.get("entries", []):
                    emp_id = entry.get("employeeId")
                    if not emp_id:
                        continue
                    # A guard who mans a post here outranks one who only
                    # ever covered a day off: "assigned to" beats "helped
                    # out at" when the picker has one line to say it in.
                    if not entry.get("isReliever"):
                        seen[emp_id] = False
                    else:
                        seen.setdefault(emp_id, True)

            for emp_id, is_reliever in seen.items():
                duty.setdefault(emp_id, []).append({
                    "stationId": schedule.get("stationId"),
                    "stationName": schedule.get("stationName"),
                    "startDate": schedule.get("startDate"),
                    "endDate": schedule.get("endDate"),
                    "status": schedule.get("status", "unpublished"),
                    "isReliever": is_reliever,
                })

        for entries in duty.values():
            entries.sort(key=lambda e: (e["startDate"], e["stationName"] or ""))
        return {"success": True, "dutyStatus": duty}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to build duty status: {str(e)}")


@app.put("/stations/{station_id}/special-assignments")
def save_station_special_assignments(station_id: str,
                                     request: SpecialAssignmentSaveRequest):
    """Replaces this station's pins for one cycle with the list supplied.

    Everything is validated before anything is written, so a rejected
    employee in the middle of the list can't leave the station holding a
    half-applied set of pins.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    cycle_id = request.cycleId.strip()
    if not (len(cycle_id) == 6 and cycle_id.isdigit()):
        raise HTTPException(status_code=400,
                            detail="cycleId must look like '202607'")

    station = repo.stations.get(station_id)
    if station is None:
        raise HTTPException(status_code=404, detail="Station not found")
    station_name = (station.get("name") or "").strip()

    seen = set()
    for entry in request.assignments:
        if entry.employeeId in seen:
            raise HTTPException(
                status_code=400,
                detail=f"{entry.employeeId} appears twice in the list")
        seen.add(entry.employeeId)

    # Validate every employee up front, collecting what we'll write.
    resolved = []
    for entry in request.assignments:
        emp = repo.employees.get(entry.employeeId)
        if emp is None:
            raise HTTPException(status_code=404,
                                detail=f"Employee {entry.employeeId} not found")
        if not emp.get("isActive", True):
            raise HTTPException(
                status_code=400,
                detail=f"{emp.get('name', entry.employeeId)} is inactive and "
                       f"cannot be assigned.")
        try:
            shift = validate_shift(emp.get("type", "regular"), entry.shift)
        except ValueError as e:
            raise HTTPException(
                status_code=400,
                detail=f"{emp.get('name', entry.employeeId)}: {str(e)}")
        resolved.append((emp, shift))

    try:
        existing = {doc.id: doc for doc in
                    db.collection(SPECIAL_ASSIGNMENTS)
                    .where("rotationCycleId", "==", cycle_id).stream()}

        batch = db.batch()

        # Drop the pins this station used to hold that aren't in the new
        # list. Scoped to this station so saving Monumento never touches
        # a pin belonging to Abad Santos.
        keep = {f"{cycle_id}_{emp['id']}" for emp, _ in resolved}
        for doc_id, doc in existing.items():
            data = doc.to_dict()
            if data.get("stationId") == station_id and doc_id not in keep:
                batch.delete(doc.reference)

        moved = []
        saved = []
        notify = []  # (emp, shift) pairs whose pin is new or changed
        for emp, shift in resolved:
            doc_id = f"{cycle_id}_{emp['id']}"
            prior = existing.get(doc_id)
            if prior is None:
                notify.append((emp, shift))
            else:
                prior_data = prior.to_dict()
                if prior_data.get("stationId") not in (None, station_id):
                    # Same doc ID, different station: the overwrite below
                    # relocates them, which is what the admin asked for,
                    # but it silently empties a post elsewhere so it's
                    # worth saying out loud.
                    moved.append(
                        f"{emp.get('name', emp['id'])} was pinned to "
                        f"{prior_data.get('stationName')} this cycle and has "
                        f"been moved here.")
                    notify.append((emp, shift))
                elif prior_data.get("shift") != shift:
                    notify.append((emp, shift))

            record = {
                "id": doc_id,
                "rotationCycleId": cycle_id,
                "employeeId": emp["id"],
                "employeeName": emp.get("name", ""),
                "employeeType": emp.get("type", "regular"),
                "stationId": station_id,
                "stationName": station_name,
                "shift": shift,
                "homeStation": (emp.get("assignedStation") or "").strip() or None,
                "createdAt": datetime.now(timezone.utc).isoformat(),
            }
            batch.set(db.collection(SPECIAL_ASSIGNMENTS).document(doc_id),
                      record)
            saved.append(record)

        # Tell each newly pinned (or re-shifted / relocated) guard about
        # it in their Alerts tab. The deterministic ID means saving the
        # same pin twice refreshes one notification instead of stacking
        # duplicates.
        cycle_start = datetime(int(cycle_id[:4]), int(cycle_id[4:]), 1)
        cycle_name = cycle_start.strftime("%B %Y")
        now_iso = datetime.now(timezone.utc).isoformat()
        shift_labels = {
            "morning": "Morning shift (0500H - 1400H)",
            "afternoon": "Afternoon shift (1400H - 2330H)",
            "night": "Night shift (2100H - 0500H)",
            "hgDay": "HG Day shift (0500H - 1700H)",
            "hgNight": "HG Night shift (1700H - 0500H)",
        }
        for emp, shift in notify:
            duty = shift_labels.get(
                shift, "floating reliever duty (morning/afternoon posts)")
            home = (emp.get("assignedStation") or "").strip()
            message = (f"You have been specially assigned to {station_name} "
                       f"for {cycle_name} — {duty}. This overrides your "
                       f"regular rotation for the cycle"
                       + (f"; you return to {home} when it ends" if home
                          else "")
                       + ". Please review your schedule once it is "
                         "published.")
            notification = {
                "id": f"NTF-SA-{cycle_id}-{emp['id']}",
                "employeeId": emp["id"],
                "type": "schedule",
                "title": "Special Assignment",
                "message": message,
                "date": cycle_start.date().isoformat(),
                "createdAt": now_iso,
                "isRead": False,
            }
            batch.set(db.collection("employee_notifications")
                      .document(notification["id"]), notification)

        batch.commit()

        return {"success": True, "specialAssignments": saved, "notes": moved}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to save special assignments: {str(e)}")


# --- Schedules ---

def _resolve_station_group(station_id):
    """(station dict, group number) for a single-station generation run.

    The group is derived from the station's position in the id-sorted
    station list, exactly the way scheduler.generate_group_schedules
    slices GROUP_RANGES — so a station can never be generated under a
    different group than the one a full group run would place it in."""
    stations = station_pools.sort_stations(repo.stations.list())
    for index, station in enumerate(stations):
        if station.get("id") != station_id:
            continue
        for group, (lo, hi) in station_pools.GROUP_RANGES.items():
            if lo <= index < hi:
                return station, group
        raise HTTPException(
            status_code=400,
            detail=f"Station '{station.get('name', station_id)}' sits outside "
                   f"the configured station groups (position {index + 1}).")
    raise HTTPException(status_code=404,
                        detail=f"Station '{station_id}' not found")


def _cycle_ids_for_period(start):
    """The rotation cycle(s) a 15-day period starting `start` touches —
    the same set scheduler.generate_group_schedules loads pins for."""
    end = start + timedelta(days=scheduler.PERIOD_DAYS - 1)
    first = rotation.build_cycle_id(start)
    last = rotation.build_cycle_id(end)
    return [first] if first == last else [first, last]


def _stale_pin_rosters(start, end_iso, keep_doc_ids):
    """Saved schedules this run will NOT replace that still roster a guard
    who is pinned to a DIFFERENT station this cycle.

    A pin relocates a guard for the whole month, but generation only ever
    writes the documents it was asked for — a by-station run keeps just
    that station's, and even a group run leaves the other groups alone.
    So the roster the guard was pulled OFF stays on disk exactly as it
    was, and the guard ends up on two stations' schedules for the same
    dates. That is the double-booking to catch before anything is saved.

    Returns a list of (schedule dict, [guard names]) worth reporting.
    """
    pins = {}
    for cycle_id in _cycle_ids_for_period(start):
        for data in repo.special_assignments.find(rotationCycleId=cycle_id):
            pins[data["employeeId"]] = data
    if not pins:
        return []

    start_iso = start.isoformat()
    stale = []
    # `id` mirrors the document id on every schedule — they are written as
    # `.document(schedule["id"]).set(schedule)` — so filtering on the field
    # is the same test as filtering on doc.id was.
    for schedule in repo.schedules.list():
        if schedule.get("id") in keep_doc_ids:
            continue  # this run replaces it, so it can't go stale
        if (schedule.get("endDate", "") < start_iso
                or schedule.get("startDate", "") > end_iso):
            continue  # different dates entirely — not a clash

        misplaced = {}
        for day in schedule.get("days", []):
            for entry in day.get("entries", []):
                pin = pins.get(entry.get("employeeId"))
                if pin and pin.get("stationId") != schedule.get("stationId"):
                    misplaced[entry["employeeId"]] = (
                        entry.get("employeeName") or entry["employeeId"],
                        pin.get("stationName", ""))
        if misplaced:
            stale.append((schedule, misplaced))
    return stale


@app.post("/schedules/generate")
def generate_schedules(request: ScheduleGenerateRequest):
    """Generates the bi-weekly (15-day) schedule for every station in the
    given group and saves each one to `schedules/` as unpublished.
    Re-generating the same group + start date overwrites the previous
    result (deterministic document IDs).

    With `stationId` set it generates for that one station instead: the
    group is still worked out in full (rotation placement, the shared
    reliever pool and the floating head-guard substitutes only make sense
    group-wide) but only that station's document is saved, and only its
    own overlapping schedule is replaced."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        start = datetime.strptime(request.startDate, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400,
                            detail="startDate must be YYYY-MM-DD")

    single_station = None
    group = request.group
    if request.stationId:
        single_station, group = _resolve_station_group(request.stationId)

    # Double-generation guard: reject when this group already has a
    # schedule whose 15-day period overlaps the requested one, unless the
    # caller explicitly asked to overwrite (then the old docs are removed
    # first, so stations never end up with two schedules for one date).
    # A single-station run only ever looks at — and only ever deletes —
    # that station's own documents.
    start_iso = start.isoformat()
    end_iso = (start + timedelta(days=scheduler.PERIOD_DAYS - 1)).isoformat()
    try:
        query = db.collection("schedules")
        query = (query.where("stationId", "==", request.stationId)
                 if single_station else query.where("group", "==", group))
        existing = list(query.stream())
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to check existing schedules: {str(e)}")

    conflicts = [
        doc for doc in existing
        if not (doc.to_dict().get("endDate", "") < start_iso
                or doc.to_dict().get("startDate", "") > end_iso)
    ]
    if conflicts and not request.overwrite:
        periods = sorted({
            f"{d.to_dict().get('startDate')} to {d.to_dict().get('endDate')}"
            for d in conflicts
        })
        subject = (f"{single_station.get('name', request.stationId)}"
                   if single_station else f"Group {group}")
        raise HTTPException(
            status_code=409,
            detail=f"{subject} already has a generated schedule "
                   f"covering {', '.join(periods)}.")

    # A pin moves a guard for the whole month, but this run only rewrites
    # the documents it was asked for. Anything else still holding that
    # guard for these dates would leave them rostered at two stations at
    # once, so stop here and name what has to be regenerated rather than
    # writing a schedule that is already known to contradict another.
    try:
        stale = _stale_pin_rosters(start, end_iso, {d.id for d in conflicts})
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to check special assignments against existing "
                   f"schedules: {str(e)}")

    if stale:
        lines = []
        for schedule, misplaced in stale:
            who = ", ".join(
                f"{name} (pinned to {pinned_to})"
                for name, pinned_to in sorted(misplaced.values()))
            published = schedule.get("status") == "published"
            lines.append(
                f"{schedule.get('stationName')} "
                f"({schedule.get('startDate')} to {schedule.get('endDate')}"
                f"{', PUBLISHED' if published else ''}) still rosters {who}.")
        anything_published = any(
            s.get("status") == "published" for s, _ in stale)
        # A dict detail so the app can tell this apart from the plain
        # "this period already has a schedule" 409 — that one is fixed by
        # regenerating with overwrite, and this one is not.
        raise HTTPException(
            status_code=409,
            detail={
                "code": "special_assignment_clash",
                "message":
                    "Special assignments have moved guards who are still on "
                    "another station's saved schedule for these dates:\n"
                    + "\n".join(f"• {line}" for line in lines)
                    + "\n\nRegenerate "
                    + ("those stations" if len(stale) > 1 else "that station")
                    + " first — or generate the whole group — so nobody is "
                      "rostered in two places at once."
                    + (" A published schedule comes back unpublished when it "
                       "is regenerated, so review and re-publish it to notify "
                       "its guards of the change." if anything_published
                       else ""),
                "stations": [
                    {"stationId": s.get("stationId"),
                     "stationName": s.get("stationName"),
                     "startDate": s.get("startDate"),
                     "endDate": s.get("endDate"),
                     "status": s.get("status", "unpublished")}
                    for s, _ in stale
                ],
            })

    try:
        schedules = scheduler.generate_group_schedules(
            db, group, start, rotate=request.rotate)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Schedule generation failed: {str(e)}")

    # Keep only the requested station. The rest of the group was needed to
    # get this one right (shared relievers, shared substitutes) but is
    # thrown away unsaved, so sibling stations keep their current rosters.
    if single_station:
        schedules = [s for s in schedules
                     if s.get("stationId") == request.stationId]
        if not schedules:
            raise HTTPException(
                status_code=500,
                detail=f"Generation produced no schedule for "
                       f"'{single_station.get('name', request.stationId)}'.")

    try:
        batch = db.batch()
        for doc in conflicts:
            batch.delete(doc.reference)
        for schedule in schedules:
            batch.set(db.collection("schedules").document(schedule["id"]),
                      schedule)
        batch.commit()
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save schedules: {str(e)}")

    return {
        "success": True,
        "schedules": schedules,
        # Everything the generator had to bend to produce this roster,
        # tagged by category and severity so the admin screen can group
        # them (schedule_notes.py). Same list on every station's doc.
        "scheduleNotes": schedules[0].get("scheduleNotes", []) if schedules else [],
        # The same notes as flat one-liners, for readers that predate the
        # structured form.
        "rotationNotes": schedules[0].get("rotationNotes", []) if schedules else [],
    }


@app.get("/schedules")
def get_schedules():
    """Returns every stored schedule, used by Schedule Management."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        schedules = sorted(repo.schedules.list(),
                           key=lambda s: s.get("createdAt", ""), reverse=True)
        return {"success": True, "schedules": schedules}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch schedules: {str(e)}")


def _is_empty_schedule(schedule):
    """True when no day carries a single entry — the signature of a
    station whose personnel pool was empty at generation time (e.g. every
    guard still references a deleted/renamed station). Publishing one
    would leave Station Management showing 0 guards for a station whose
    schedule is nominally out."""
    return not any(day.get("entries") for day in schedule.get("days", []))


def _undefined_post_guards(schedule):
    """Distinct guards still on the Undefined placeholder post. A
    schedule can't go out while any post reads Undefined — the admin
    names every post first (Schedule Detail > tap a row)."""
    return {
        entry.get("employeeName") or entry.get("employeeId", "?")
        for day in schedule.get("days", [])
        for entry in day.get("entries", [])
        if entry.get("post") == scheduler.POST_UNDEFINED
    }


def _pretty_date(date_iso):
    """'2026-08-01' -> 'Aug 01, 2026', for notification copy."""
    try:
        return datetime.strptime(date_iso, "%Y-%m-%d").strftime("%b %d, %Y")
    except (ValueError, TypeError):
        return date_iso or "?"


def _schedule_employee_ids(schedule):
    """Every distinct guard appearing anywhere in the schedule, in the
    order they first show up."""
    seen = []
    for day in schedule.get("days", []):
        for entry in day.get("entries", []):
            emp_id = entry.get("employeeId")
            if emp_id and emp_id not in seen:
                seen.append(emp_id)
    return seen


def _schedule_notifications(schedule, *, kind, title, body):
    """One notification per guard in the schedule. Deterministic IDs
    (schedule + employee) so re-publishing refreshes the existing notice
    instead of stacking duplicates — and so a withdrawal *replaces* the
    guard's "New Schedule Published" notice rather than sitting next to
    an alert that now points at a schedule which no longer exists."""
    now_iso = datetime.now(timezone.utc).isoformat()
    start = schedule.get("startDate", "")
    return [
        {
            "id": f"NTF-SCH-{schedule.get('id', 'X')}-{emp_id}",
            "employeeId": emp_id,
            "type": kind,
            "title": title,
            "message": body,
            "date": start,
            "createdAt": now_iso,
            "isRead": False,
        }
        for emp_id in _schedule_employee_ids(schedule)
    ]


def _schedule_publish_notifications(schedule):
    """The 'your new schedule is out' alert — the flowchart's "notify
    employees" step, which happens at publish time since guards never
    see unpublished drafts."""
    station = (schedule.get("stationName") or "your station").strip()
    start, end = schedule.get("startDate", ""), schedule.get("endDate", "")
    return _schedule_notifications(
        schedule,
        kind="schedule",
        title="New Schedule Published",
        body=f"Your duty schedule for {station} covering "
             f"{_pretty_date(start)} to {_pretty_date(end)} has been "
             "published. Open the Schedule tab to review your assigned "
             "shifts and rest days.",
    )


def _schedule_withdrawn_notifications(schedule):
    """The counterpart alert, sent when a PUBLISHED schedule is deleted.
    Guards were told to report for these shifts, so they have to be told
    just as plainly that the shifts are off. Marked urgent (red in the
    Alerts tab) because a guard who misses it turns up for duty that no
    longer exists. Unpublished drafts never reach guards, so deleting
    one stays silent."""
    station = (schedule.get("stationName") or "your station").strip()
    start, end = schedule.get("startDate", ""), schedule.get("endDate", "")
    return _schedule_notifications(
        schedule,
        kind="urgent",
        title="Schedule Withdrawn",
        body=f"Your duty schedule for {station} covering "
             f"{_pretty_date(start)} to {_pretty_date(end)} has been "
             "withdrawn and is no longer in effect. Do not report for "
             "those shifts — wait for the replacement schedule, and check "
             "with your head guard if you are unsure.",
    )


def _notified_count(schedule):
    """How many guards a withdrawal alert reaches — 0 for a draft, since
    guards were never told about it in the first place."""
    if schedule.get("status") != "published":
        return 0
    return len(_schedule_employee_ids(schedule))


def _write_notifications(notifications):
    """Batch-writes notification docs, chunked under Firestore's
    500-writes-per-batch limit."""
    for i in range(0, len(notifications), 400):
        batch = db.batch()
        for n in notifications[i:i + 400]:
            batch.set(db.collection("employee_notifications")
                      .document(n["id"]), n)
        batch.commit()


@app.post("/schedules/{schedule_id}/publish")
def publish_schedule(schedule_id: str):
    """Marks one schedule as published and notifies every guard in it
    (Alerts tab) that their new schedule is out."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("schedules").document(schedule_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Schedule not found")
        schedule = snap.to_dict()
        if _is_empty_schedule(schedule):
            raise HTTPException(
                status_code=400,
                detail=f"The schedule for "
                       f"{schedule.get('stationName', 'this station')} has "
                       "no guards assigned on any day, so there is nothing "
                       "to publish. Check the generation notes — the "
                       "station's guards may still reference an old station "
                       "name — then re-generate.")
        undefined = _undefined_post_guards(schedule)
        if undefined:
            sample = ", ".join(sorted(undefined)[:3])
            raise HTTPException(
                status_code=400,
                detail=f"{len(undefined)} guard(s) still have an Undefined "
                       f"post ({sample}{'…' if len(undefined) > 3 else ''}). "
                       "Assign every post before publishing.")
        doc_ref.update({"status": "published"})
        # Only the unpublished -> published transition announces; hitting
        # publish twice shouldn't re-alert everyone.
        if schedule.get("status") != "published":
            _write_notifications(_schedule_publish_notifications(schedule))
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to publish schedule: {str(e)}")


@app.post("/schedules/{schedule_id}/unpublish")
def unpublish_schedule(schedule_id: str):
    """Reverts one schedule back to unpublished."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("schedules").document(schedule_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404, detail="Schedule not found")
        doc_ref.update({"status": "unpublished"})
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to unpublish schedule: {str(e)}")


def _reject_if_published(schedule, action: str):
    """Roster edits stop at publish time.

    Every guard in a published schedule has already been notified of the
    assignment they are holding, so changing it underneath them leaves
    them working off a roster nobody told them about. The admin
    unpublishes, edits, then publishes again — the publish is also what
    re-notifies everyone about what changed.
    """
    if schedule.get("status") == "published":
        raise HTTPException(
            status_code=400,
            detail="This schedule is already published and its guards have "
                   f"been notified. Unpublish it first, {action}, then "
                   "publish again.")


@app.put("/schedules/{schedule_id}/posts")
def update_schedule_post(schedule_id: str, request: SchedulePostUpdateRequest):
    """Renames one guard's post across the whole schedule — their own
    entries plus any entry covering their day-offs (the cover mans the
    same spot). This is how the admin clears the Undefined placeholders
    that block publishing."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    post = request.post.strip()
    if not post:
        raise HTTPException(status_code=400, detail="post must not be empty")

    try:
        doc_ref = db.collection("schedules").document(schedule_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Schedule not found")
        schedule = snap.to_dict()
        _reject_if_published(schedule, "change the post")

        own_entries = [
            e for day in schedule.get("days", [])
            for e in day.get("entries", [])
            if e.get("employeeId") == request.employeeId
            and not e.get("coveringFor")
        ]
        if not own_entries:
            raise HTTPException(status_code=404,
                                detail="Employee not found in this schedule")
        if any((e.get("shift") or "").startswith("HG") for e in own_entries):
            raise HTTPException(status_code=400,
                                detail="The Head Guard post cannot be changed")

        for day in schedule.get("days", []):
            for entry in day.get("entries", []):
                is_own = (entry.get("employeeId") == request.employeeId
                          and not entry.get("coveringFor"))
                if is_own or entry.get("coveringFor") == request.employeeId:
                    entry["post"] = post

        doc_ref.update({"days": schedule["days"]})
        return {"success": True, "post": post}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to update post: {str(e)}")


# Shift labels an entry may carry, mapped to the employee `type` allowed
# to work them. The HG shifts are head-guard-only and always man the
# Head Guard post; the rest are for regulars and relievers.
_ADDABLE_SHIFTS = {
    "Morning": ("regular", "reliever"),
    "Afternoon": ("regular", "reliever"),
    "Night": ("regular", "reliever"),
    "HG Day": ("headGuard",),
    "HG Night": ("headGuard",),
}

# Same ceiling the Schedule Detail edit dialog enforces.
_MAX_OFF_DATES = 5


def _period_dates(schedule):
    """The schedule's day dates in order, as ISO strings."""
    return [day.get("date") for day in schedule.get("days", [])
            if day.get("date")]


def _existing_commitments(employee_id, start_iso, end_iso, exclude_id):
    """{dateIso: stationName} for every OTHER schedule that already has
    this guard on duty inside the period.

    The generator refuses to double-book across stations
    (scheduler._load_period_commitments); a manual add has to honour the
    same invariant or the guard is rostered two places at once."""
    booked = {}
    for data in repo.schedules.list():
        if data.get("id") == exclude_id:
            continue
        if (data.get("endDate", "") < start_iso
                or data.get("startDate", "") > end_iso):
            continue
        station = data.get("stationName") or data.get("stationId") or "?"
        for day in data.get("days", []):
            for entry in day.get("entries", []):
                if entry.get("employeeId") == employee_id:
                    booked[day.get("date")] = station
    return booked


@app.post("/schedules/{schedule_id}/employees")
def add_schedule_employee(schedule_id: str,
                          request: ScheduleEmployeeAddRequest):
    """Manually adds one guard to an unpublished schedule.

    Fills the gaps the generator can leave behind — a station short a
    body, a late transfer, a guard whose station name didn't match the
    pool. The guard gets an own-duty entry on every day of the period
    except their day-offs, so they show up in Schedule Detail's shift
    table exactly like a generated guard does.

    Published schedules are rejected: their guards have already been
    notified, so the admin unpublishes, adds, then re-publishes.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    shift = request.shift.strip()
    if shift not in _ADDABLE_SHIFTS:
        raise HTTPException(
            status_code=400,
            detail=f"shift must be one of {', '.join(_ADDABLE_SHIFTS)}")

    # The HG shifts always man the Head Guard post — the same rule
    # update_schedule_post enforces when renaming.
    is_head_guard = shift.startswith("HG")
    post = (scheduler.POST_HEAD_GUARD if is_head_guard
            else request.post.strip())
    if not post:
        raise HTTPException(status_code=400, detail="post must not be empty")

    try:
        doc_ref = db.collection("schedules").document(schedule_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Schedule not found")
        schedule = snap.to_dict()

        _reject_if_published(schedule, "add the guard")

        dates = _period_dates(schedule)
        if not dates:
            raise HTTPException(status_code=400,
                                detail="This schedule has no days to add to.")

        employee = repo.employees.get(request.employeeId)
        if employee is None:
            raise HTTPException(status_code=404, detail="Employee not found")
        if not employee.get("isActive", True):
            raise HTTPException(
                status_code=400,
                detail=f"{employee.get('name', request.employeeId)} is "
                       "inactive and cannot be rostered.")

        allowed_types = _ADDABLE_SHIFTS[shift]
        if employee.get("type") not in allowed_types:
            raise HTTPException(
                status_code=400,
                detail=f"{employee.get('name', request.employeeId)} is a "
                       f"{employee.get('type', 'guard')} and cannot work the "
                       f"{shift} shift.")

        already = any(
            entry.get("employeeId") == request.employeeId
            for day in schedule.get("days", [])
            for entry in day.get("entries", []))
        # Covers relievers too: someone already covering day-offs here is
        # committed on those dates and can't also hold a fixed post.
        if already:
            raise HTTPException(
                status_code=409,
                detail=f"{employee.get('name', request.employeeId)} already "
                       "appears on this schedule, on their own post or as a "
                       "reliever. Open Schedule Detail to adjust their "
                       "assignment instead.")

        off_dates = {d.strip() for d in request.offDates if d.strip()}
        if len(off_dates) > _MAX_OFF_DATES:
            raise HTTPException(
                status_code=400,
                detail=f"At most {_MAX_OFF_DATES} day-offs may be set here.")
        outside = sorted(off_dates - set(dates))
        if outside:
            raise HTTPException(
                status_code=400,
                detail=f"Day-off {', '.join(outside)} falls outside this "
                       f"schedule's period "
                       f"({schedule.get('startDate')} to "
                       f"{schedule.get('endDate')}).")

        work_dates = [d for d in dates if d not in off_dates]
        if not work_dates:
            raise HTTPException(
                status_code=400,
                detail="Every day of the period is marked as a day-off — "
                       "there is nothing to roster.")

        # Never let a manual add double-book someone another station is
        # already counting on.
        clashes = _existing_commitments(
            request.employeeId,
            schedule.get("startDate", ""),
            schedule.get("endDate", ""),
            schedule_id)
        overlap = sorted(set(work_dates) & set(clashes))
        if overlap:
            station = clashes[overlap[0]]
            sample = ", ".join(overlap[:3])
            raise HTTPException(
                status_code=409,
                detail=f"{employee.get('name', request.employeeId)} is "
                       f"already on duty at {station} on {sample}"
                       f"{'…' if len(overlap) > 3 else ''}. "
                       "Mark those dates as day-offs here, or pick another "
                       "guard.")

        station_id = schedule.get("stationId", schedule_id)

        # Give the hand-added guard the same duty window the station's
        # setup gives that post, so they sit on the stagger ladder with
        # everyone else instead of defaulting to the shift's base hours.
        station = repo.stations.get(station_id)
        window = station_posts.window_for_post(station or {},
                                               shift, post) or {}

        added = 0
        for index, day in enumerate(schedule.get("days", [])):
            if day.get("date") not in work_dates:
                continue
            day.setdefault("entries", []).append({
                "id": f"{station_id}_manual_{request.employeeId}_{index}",
                "employeeId": request.employeeId,
                "employeeName": employee.get("name", ""),
                "shift": shift,
                "post": post,
                "timeIn": window.get("start"),
                "timeOut": window.get("end"),
                "isReliever": False,
                "coveringFor": None,
                "isSpecial": False,
                "borrowedFrom": None,
                # Flags the row as admin-added rather than generated, so a
                # re-generation diff can tell the two apart.
                "isManual": True,
            })
            added += 1

        doc_ref.update({"days": schedule["days"]})
        return {
            "success": True,
            "employeeName": employee.get("name", ""),
            "daysAdded": added,
            "offDates": sorted(off_dates),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to add employee: {str(e)}")


# Who may hold each roster row, and who may cover its day-offs, by the
# row's shift label: (holder type, cover type).
#
# The HG rows are head-guard-only on BOTH sides. A reliever cannot man
# the Head Guard post, which is why the generator covers a head guard's
# day-off from the floating substitute head-guard pool
# (scheduler.sub_hg_tracker) rather than from the reliever pool — a hand
# edit has to honour the same rule or the post goes to someone who isn't
# allowed to stand it.
_ROW_ROLES = {
    "Morning": ("regular", "reliever"),
    "Afternoon": ("regular", "reliever"),
    "Night": ("regular", "reliever"),
    "HG Day": ("headGuard", "headGuard"),
    "HG Night": ("headGuard", "headGuard"),
}

_ROLE_LABELS = {
    "regular": "regular guard",
    "reliever": "reliever",
    "headGuard": "head guard",
}


def _role_label(employee_type):
    return _ROLE_LABELS.get(employee_type, employee_type or "guard")


def _load_rosterable_guard(employee_id):
    """The employee document, refusing anyone who can't be put on duty."""
    employee = repo.employees.get(employee_id)
    if employee is None:
        raise HTTPException(status_code=404,
                            detail=f"Employee {employee_id} not found")
    if not employee.get("isActive", True):
        raise HTTPException(
            status_code=400,
            detail=f"{employee.get('name', employee_id)} is inactive and "
                   "cannot be rostered.")
    return employee


def _normalize_hhmm(value, field):
    """'05:00' / '0500' / '0500H' -> '05:00'. None/blank passes through as
    None so the caller can fall back to the row's current window."""
    if value is None:
        return None
    digits = "".join(c for c in str(value) if c.isdigit())
    if not digits:
        return None
    if len(digits) != 4:
        raise HTTPException(status_code=400,
                            detail=f"{field} must be a time like 0500 or 05:00")
    hour, minute = int(digits[:2]), int(digits[2:])
    if hour > 23 or minute > 59:
        raise HTTPException(status_code=400, detail=f"{field} is not a time")
    return f"{hour:02d}:{minute:02d}"


@app.put("/schedules/{schedule_id}/assignment")
def update_schedule_assignment(schedule_id: str,
                               request: ScheduleAssignmentUpdateRequest):
    """Rewrites one roster row — the save behind Schedule Detail's Edit
    Assignment dialog.

    The row is rebuilt from scratch across the whole period: the holder
    gets an own-duty entry on every working day, the reliever (if any)
    gets a covering entry on every day-off, and the outgoing guard's
    entries are dropped. Covers the outgoing guard was providing for
    OTHER guards move to whoever holds the row now, so nobody is left
    uncovered by a swap.

    Published schedules are rejected: their guards are already working
    off this roster, so it is unpublished, edited, then published again.

    Roles are enforced here, not just in the dialog: a Head Guard row can
    only be held and covered by head guards, the shift rows only by
    regulars and relievers respectively, and nobody can hold a row while
    already committed on this or another station's schedule for the same
    period.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("schedules").document(schedule_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Schedule not found")
        schedule = snap.to_dict()
        _reject_if_published(schedule, "edit the assignment")

        days = schedule.get("days", [])
        dates = _period_dates(schedule)
        if not dates:
            raise HTTPException(status_code=400,
                                detail="This schedule has no days to edit.")

        # --- the row being edited -------------------------------------
        own = [entry for day in days for entry in day.get("entries", [])
               if entry.get("employeeId") == request.employeeId
               and not entry.get("coveringFor")]
        if not own:
            raise HTTPException(
                status_code=404,
                detail="That guard no longer holds a row on this schedule. "
                       "Reload the schedule and try again.")

        template = own[0]
        shift = (template.get("shift") or "").strip()
        if shift not in _ROW_ROLES:
            raise HTTPException(
                status_code=400,
                detail=f"This row's shift ({shift or 'unknown'}) cannot be "
                       "edited here.")
        holder_type, cover_type = _ROW_ROLES[shift]
        is_head_guard = shift.startswith("HG")

        start_iso = schedule.get("startDate", "")
        end_iso = schedule.get("endDate", "")

        # --- who holds it ---------------------------------------------
        target_id = (request.newEmployeeId or request.employeeId).strip()
        swapping = target_id != request.employeeId
        if swapping:
            guard = _load_rosterable_guard(target_id)
            if guard.get("type") != holder_type:
                raise HTTPException(
                    status_code=400,
                    detail=f"{guard.get('name', target_id)} is a "
                           f"{_role_label(guard.get('type'))}. The {shift} "
                           f"post can only be held by a "
                           f"{_role_label(holder_type)}.")
            clash_here = any(
                entry.get("employeeId") == target_id
                for day in days for entry in day.get("entries", []))
            if clash_here:
                raise HTTPException(
                    status_code=409,
                    detail=f"{guard.get('name', target_id)} is already on "
                           "this schedule — on their own post or as a "
                           "reliever. One guard cannot hold two slots in the "
                           "same period.")
        else:
            guard = repo.employees.get(target_id) or {}
        target_name = guard.get("name") or template.get("employeeName", "")

        # --- post ------------------------------------------------------
        if is_head_guard:
            post = scheduler.POST_HEAD_GUARD
        else:
            post = (request.post
                    if request.post is not None
                    else template.get("post") or "").strip()
            if not post:
                raise HTTPException(status_code=400,
                                    detail="post must not be empty")
            if post == scheduler.POST_HEAD_GUARD:
                raise HTTPException(
                    status_code=400,
                    detail="The Head Guard post belongs to the station's head "
                           "guards and cannot be given to a shift guard.")

        # --- duty window ----------------------------------------------
        time_in = (_normalize_hhmm(request.timeIn, "timeIn")
                   or template.get("timeIn"))
        time_out = (_normalize_hhmm(request.timeOut, "timeOut")
                    or template.get("timeOut"))

        # --- day-offs --------------------------------------------------
        if request.offDates is None:
            on_duty_now = {day.get("date") for day in days
                           for entry in day.get("entries", [])
                           if entry.get("employeeId") == request.employeeId
                           and not entry.get("coveringFor")}
            off_dates = {d for d in dates if d not in on_duty_now}
        else:
            off_dates = {d.strip() for d in request.offDates if d.strip()}
        if len(off_dates) > _MAX_OFF_DATES:
            raise HTTPException(
                status_code=400,
                detail=f"At most {_MAX_OFF_DATES} day-offs may be set here.")
        outside = sorted(off_dates - set(dates))
        if outside:
            raise HTTPException(
                status_code=400,
                detail=f"Day-off {', '.join(outside)} falls outside this "
                       f"schedule's period ({start_iso} to {end_iso}).")
        work_dates = [d for d in dates if d not in off_dates]
        if not work_dates:
            raise HTTPException(
                status_code=400,
                detail="Every day of the period is marked as a day-off — "
                       "there is nothing to roster.")

        if swapping:
            clashes = _existing_commitments(
                target_id, start_iso, end_iso, schedule_id)
            overlap = sorted(set(work_dates) & set(clashes))
            if overlap:
                raise HTTPException(
                    status_code=409,
                    detail=f"{target_name} is already on duty at "
                           f"{clashes[overlap[0]]} on {', '.join(overlap[:3])}"
                           f"{'…' if len(overlap) > 3 else ''}. Pick another "
                           "guard, or mark those dates as day-offs here.")

        # --- reliever --------------------------------------------------
        reliever_id = (request.relieverId or "").strip() or None
        reliever = None
        if reliever_id:
            if reliever_id == target_id:
                raise HTTPException(
                    status_code=400,
                    detail=f"{target_name} cannot relieve themselves — a "
                           "guard's day-off has to be covered by someone "
                           "else.")
            reliever = _load_rosterable_guard(reliever_id)
            # Whoever is ALREADY covering this row keeps their place, role
            # rule or not. The generator covers a night day-off with an
            # on-duty night regular when no reliever is free (the internal
            # switch in scheduler._build_station_schedule), and an admin
            # editing that row's post shouldn't have their save refused
            # over a cover they never touched. The rule still bites on
            # anyone newly put in the slot.
            already_covering = any(
                entry.get("employeeId") == reliever_id
                and entry.get("coveringFor") == request.employeeId
                for day in days for entry in day.get("entries", []))
            if reliever.get("type") != cover_type and not already_covering:
                raise HTTPException(
                    status_code=400,
                    detail=f"{reliever.get('name', reliever_id)} is a "
                           f"{_role_label(reliever.get('type'))}. A {shift} "
                           f"day-off can only be covered by a "
                           f"{_role_label(cover_type)}.")
            holds_own_row = any(
                entry.get("employeeId") == reliever_id
                and not entry.get("coveringFor")
                and entry.get("employeeId") != request.employeeId
                for day in days for entry in day.get("entries", []))
            if holds_own_row and not already_covering:
                raise HTTPException(
                    status_code=409,
                    detail=f"{reliever.get('name', reliever_id)} already holds "
                           "their own post on this schedule and cannot also be "
                           "the reliever for this one.")
            if off_dates:
                rel_clashes = _existing_commitments(
                    reliever_id, start_iso, end_iso, schedule_id)
                rel_overlap = sorted(off_dates & set(rel_clashes))
                if rel_overlap:
                    raise HTTPException(
                        status_code=409,
                        detail=f"{reliever.get('name', reliever_id)} is "
                               f"already on duty at "
                               f"{rel_clashes[rel_overlap[0]]} on "
                               f"{', '.join(rel_overlap[:3])}"
                               f"{'…' if len(rel_overlap) > 3 else ''} and "
                               "cannot cover those day-offs.")

        # --- rewrite the row across the period -------------------------
        station_id = schedule.get("stationId", schedule_id)
        # Only the reliever pool flags isReliever. A substitute head guard
        # covering an HG row is a head guard standing in, which is how the
        # generator writes it too (scheduler covers HG day-offs without
        # setting the flag).
        cover_is_reliever = bool(
            reliever and reliever.get("type") == "reliever")

        for index, day in enumerate(days):
            date_iso = day.get("date")
            kept = []
            for entry in day.get("entries", []):
                is_own = (entry.get("employeeId") == request.employeeId
                          and not entry.get("coveringFor"))
                covers_row = entry.get("coveringFor") == request.employeeId
                if is_own or covers_row:
                    continue
                # The outgoing guard may have been covering somebody
                # else's day-off. That duty belongs to the row, so it
                # follows the row to its new holder rather than vanishing
                # and leaving that guard uncovered.
                if entry.get("employeeId") == request.employeeId:
                    entry["employeeId"] = target_id
                    entry["employeeName"] = target_name
                kept.append(entry)

            if date_iso in off_dates:
                if reliever_id:
                    kept.append({
                        "id": f"{station_id}_cover_{reliever_id}_{index}",
                        "employeeId": reliever_id,
                        "employeeName": reliever.get("name", ""),
                        "shift": shift,
                        "post": post,
                        "timeIn": time_in,
                        "timeOut": time_out,
                        "isReliever": cover_is_reliever,
                        "coveringFor": target_id,
                        "isSpecial": False,
                        "borrowedFrom": None,
                        "isManual": True,
                    })
            else:
                kept.append({
                    "id": f"{station_id}_edit_{target_id}_{index}",
                    "employeeId": target_id,
                    "employeeName": target_name,
                    "shift": shift,
                    "post": post,
                    "timeIn": time_in,
                    "timeOut": time_out,
                    "isReliever": False,
                    "coveringFor": None,
                    "isSpecial": template.get("isSpecial", False),
                    "borrowedFrom": template.get("borrowedFrom"),
                    "isManual": True,
                })
            day["entries"] = kept

        doc_ref.update({"days": days})
        return {
            "success": True,
            "employeeId": target_id,
            "employeeName": target_name,
            "shift": shift,
            "post": post,
            "timeIn": time_in,
            "timeOut": time_out,
            "offDates": sorted(off_dates),
            "relieverId": reliever_id,
            "relieverName": (reliever or {}).get("name"),
            "daysOnDuty": len(work_dates),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to update assignment: {str(e)}")


@app.delete("/schedules/{schedule_id}")
def delete_schedule(schedule_id: str):
    """Deletes one schedule permanently, alerting its guards first if it
    had already been published."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("schedules").document(schedule_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Schedule not found")
        schedule = snap.to_dict()
        doc_ref.delete()
        if schedule.get("status") == "published":
            _write_notifications(_schedule_withdrawn_notifications(schedule))
        return {"success": True, "notified": _notified_count(schedule)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to delete schedule: {str(e)}")


@app.delete("/schedules")
def delete_schedules(status: str = "all"):
    """Bulk-deletes schedules — every unpublished draft, every published
    one, or all of them. `status` is one of unpublished/published/all.
    Guards on a published schedule get a 'Schedule Withdrawn' alert;
    drafts they never saw are deleted silently."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    scope = (status or "all").strip().lower()
    if scope not in ("unpublished", "published", "all"):
        raise HTTPException(
            status_code=400,
            detail="status must be one of: unpublished, published, all")

    try:
        col = db.collection("schedules")
        docs = list(col.stream() if scope == "all"
                    else col.where("status", "==", scope).stream())

        # Collect the alerts before deleting — once the docs are gone
        # there is no way to tell who was on them.
        notifications = []
        for doc in docs:
            data = doc.to_dict()
            if data.get("status") == "published":
                notifications.extend(_schedule_withdrawn_notifications(data))

        # Firestore caps a batch at 500 writes, so commit in chunks.
        for start in range(0, len(docs), 400):
            batch = db.batch()
            for doc in docs[start:start + 400]:
                batch.delete(doc.reference)
            batch.commit()

        _write_notifications(notifications)
        return {"success": True, "deleted": len(docs),
                "notified": len(notifications)}
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to delete schedules: {str(e)}")


# --- Attendance Reports (Phase 3: absence handling) ---

# Which plain shifts each head guard duty is allowed to report on. A day
# head guard works 0600H-1800H, straddling Morning and Afternoon; a night
# head guard works 1800H-0600H and covers Night alone. Neither can ever
# file for the other's shifts.
HG_REPORTABLE_SHIFTS = {
    "hgDay": {"MORNING", "AFTERNOON"},
    "hgNight": {"NIGHT"},
}

# Head guard duty windows as (start_hour, end_hour) on the report's date;
# hgNight's end lands on the NEXT day. Must stay in step with
# shiftTimeRanges in lib/models/guard_shift.dart, which is what the phone
# shows and gates on.
HG_DUTY_WINDOWS = {
    "hgDay": (time(5, 0), time(17, 0)),
    "hgNight": (time(17, 0), time(5, 0)),
}

# Absorbs clock skew and the round trip between the phone deciding the
# window is still open and this request landing. The phone's gate is the
# real boundary; this one only has to stop a report filed nowhere near
# the duty.
HG_DUTY_WINDOW_GRACE = timedelta(minutes=5)


def _assert_inside_duty_window(head_guard_id, report_date, shift_title):
    """Rejects a report filed outside the head guard's own duty window.

    The phone gates on ServerClock (this server's clock), so a guard
    can't open the window by changing their device clock — but the phone
    is not where the rule can be trusted, so it is repeated here.

    Skipped for a floating substitute head guard (no assignedShift) and
    when the employee can't be read: neither is a reason to lose a
    legitimate report."""
    try:
        employee = repo.employees.get(head_guard_id)
    except Exception:
        return
    if employee is None:
        return

    window = HG_DUTY_WINDOWS.get(employee.get("assignedShift"))
    if window is None:
        return

    try:
        day = datetime.strptime(report_date, "%Y-%m-%d").date()
    except ValueError:
        return  # already validated by the caller

    start_t, end_t = window
    start = datetime.combine(day, start_t)
    end = datetime.combine(day, end_t)
    if end <= start:  # HG Night runs past midnight
        end += timedelta(days=1)

    now = datetime.now()
    if start - HG_DUTY_WINDOW_GRACE <= now <= end + HG_DUTY_WINDOW_GRACE:
        return

    raise HTTPException(
        status_code=400,
        detail=f"The {shift_title} report can only be filed while on post "
               f"({start.strftime('%H%M')}H - {end.strftime('%H%M')}H). "
               f"Ask the admin to file it for you if you missed the window.")


def _assert_shift_is_reportable(head_guard_id, shift_slug, shift_title):
    """Rejects a report filed for a shift the head guard's own duty does
    not cover — the server-side half of the same rule the phone enforces
    in headguard_report_screen.dart, so a UI regression can't put a night
    head guard's name on a Morning report.

    Only fixed head guards carry an assignedShift. A floating substitute
    head guard has none (they're rostered under whichever post they stand
    in for), so there is nothing to check and the report goes through."""
    try:
        employee = repo.employees.get(head_guard_id)
    except Exception:
        return  # Lookup trouble must not block a legitimate report.
    if employee is None:
        return

    assigned = employee.get("assignedShift")
    allowed = HG_REPORTABLE_SHIFTS.get(assigned)
    if allowed is None or shift_slug in allowed:
        return

    covers = ("the Night shift only" if assigned == "hgNight"
              else "the Morning and Afternoon shifts only")
    raise HTTPException(
        status_code=400,
        detail=f"This head guard covers {covers}, so they cannot file the "
               f"{shift_title}.")


@app.post("/attendance-reports")
def submit_attendance_report(request: AttendanceReportCreateRequest):
    """Saves the attendance report a Head Guard submitted for one shift
    of their station (the day HG files Morning and Afternoon separately;
    the night HG files Night, and nothing else — enforced by
    _assert_shift_is_reportable). The document ID is deterministic
    (date + head guard + shift), and a report that already exists is
    rejected with 409 — submissions are final and can't be redone.
    New reports are unread, which is what drives the admin
    Notifications screen."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    if not request.records:
        raise HTTPException(status_code=400,
                            detail="Report must contain at least one record")

    try:
        datetime.strptime(request.date, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")

    # 'Morning Shift' -> 'MORNING', so each shift gets its own document.
    shift_slug = "".join(
        c for c in request.shiftTitle.upper().replace("SHIFT", "").strip()
        if c.isalnum()) or "SHIFT"
    report_id = (f"RPT-{request.date.replace('-', '')}-"
                 f"{request.headGuardId}-{shift_slug}")

    _assert_shift_is_reportable(request.headGuardId, shift_slug,
                                request.shiftTitle)
    _assert_inside_duty_window(request.headGuardId, request.date,
                               request.shiftTitle)

    try:
        if repo.attendance_reports.get(report_id) is not None:
            raise HTTPException(
                status_code=409,
                detail=f"The {request.shiftTitle} report for {request.date} "
                       "has already been submitted. Reports cannot be "
                       "submitted twice.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to check existing report: {str(e)}")

    report_data = {
        "id": report_id,
        "headGuardId": request.headGuardId,
        "headGuardName": request.headGuardName,
        "station": request.station,
        "shiftTitle": request.shiftTitle,
        "date": request.date,
        "submittedAt": datetime.now(timezone.utc).isoformat(),
        "isRead": False,
        "records": [r.dict() for r in request.records],
    }

    try:
        db.collection("attendance_reports").document(report_id).set(report_data)
        return {"success": True, "report": report_data}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save attendance report: {str(e)}")


@app.get("/attendance-reports")
def get_attendance_reports():
    """Returns every submitted attendance report, newest first — feeds
    the admin Notifications, Submitted Reports, and Absent Today
    screens."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        reports = sorted(repo.attendance_reports.list(),
                         key=lambda r: r.get("submittedAt", ""), reverse=True)
        return {"success": True, "reports": reports}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch attendance reports: {str(e)}")


@app.post("/attendance-reports/{report_id}/read")
def mark_attendance_report_read(report_id: str):
    """Marks one report as read (admin opened its notification)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("attendance_reports").document(report_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404, detail="Report not found")
        doc_ref.update({"isRead": True})
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark report read: {str(e)}")


@app.post("/attendance-reports/read-all")
def mark_all_attendance_reports_read():
    """Marks every unread report as read ('Mark all as read')."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        docs = list(db.collection("attendance_reports")
                    .where("isRead", "==", False).stream())
        batch = db.batch()
        for doc in docs:
            batch.update(doc.reference, {"isRead": True})
        batch.commit()
        return {"success": True, "updated": len(docs)}
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark reports read: {str(e)}")


# --- Replacements (Phase 3: absence handling) ---

@app.get("/replacements")
def get_replacements():
    """Returns every admin-applied replacement (the audit docs written
    by /replacements/apply), oldest first — feeds the Schedule Report's
    Absence & Substitution Log."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        records = sorted(repo.replacements.list(),
                         key=lambda r: (r.get("date", ""),
                                        r.get("appliedAt", "")))
        return {"success": True, "replacements": records}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch replacements: {str(e)}")


@app.get("/replacements/suggest")
def suggest_replacements(date: str, station: str, shift: str,
                         absentEmployeeId: str):
    """Rule-based replacement suggestions for one absence (replaces the
    flowchart's AI box): only employees with NO schedule conflict on
    that date and who are eligible for the post's shift type, ranked by
    station familiarity, type match, and lighter workload."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")

    try:
        candidates = replacements.suggest(
            db, date, station.strip(), shift, absentEmployeeId)
        return {"success": True, "candidates": candidates}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to suggest replacements: {str(e)}")


@app.post("/replacements/apply")
def apply_replacement(request: ReplacementApplyRequest):
    """Commits the admin's chosen replacement: rewrites the schedule
    entry (replacement covers the absentee), stamps the attendance
    report record as replaced, saves an audit doc, and notifies the
    chosen employee that their schedule changed."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        record = replacements.apply_replacement(db, request)
        return {"success": True, "replacement": record}
    except ValueError as e:      # replacement now has a conflict
        raise HTTPException(status_code=409, detail=str(e))
    except LookupError as e:     # schedule/entry/employee not found
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to apply replacement: {str(e)}")


# --- Employee notifications (guard app Alerts tab) ---

@app.get("/employees/{employee_id}/notifications")
def get_employee_notifications(employee_id: str):
    """Returns this employee's notifications, newest first — currently
    the schedule-update notices written when they're chosen to cover an
    absent colleague."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        notifications = sorted(
            repo.employee_notifications.find(employeeId=employee_id),
            key=lambda n: n.get("createdAt", ""), reverse=True)
        return {"success": True, "notifications": notifications}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch notifications: {str(e)}")


@app.post("/notifications/{notification_id}/read")
def mark_notification_read(notification_id: str):
    """Marks one employee notification as read."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("employee_notifications").document(
            notification_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404, detail="Notification not found")
        doc_ref.update({"isRead": True})
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark notification read: {str(e)}")


@app.post("/employees/{employee_id}/notifications/read-all")
def mark_all_notifications_read(employee_id: str):
    """Marks every unread notification for this employee as read."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        docs = list(db.collection("employee_notifications")
                    .where("employeeId", "==", employee_id)
                    .where("isRead", "==", False).stream())
        batch = db.batch()
        for doc in docs:
            batch.update(doc.reference, {"isRead": True})
        batch.commit()
        return {"success": True, "updated": len(docs)}
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark notifications read: {str(e)}")


# --- Absence requests (employee-filed emergency absences) ---

def _absence_pretty_date(date_iso):
    """'2026-07-24' -> 'July 24, 2026' for the notification text; falls
    back to the raw string if it isn't a real date."""
    try:
        return datetime.strptime(date_iso, "%Y-%m-%d").strftime("%B %d, %Y")
    except (ValueError, TypeError):
        return date_iso or "the requested date"


# Philippine Standard Time. Fixed +8 with no DST since 1978, so a plain
# offset is exact and needs no tzdata — and it keeps the cutoff below
# anchored to the guards' local time whatever timezone the server runs in.
_PHT = timezone(timedelta(hours=8))

# Time-in (hour, minute) per shift, on the duty date itself. Mirrors
# shiftTimeRanges in lib/models/guard_shift.dart — keep the two in step.
_SHIFT_START_TIMES = {
    "morning shift": (5, 0),      # 0500H - 1400H
    "afternoon shift": (14, 0),   # 1400H - 2330H
    "night shift": (21, 0),       # 2100H - 0500H
    "hg day shift": (5, 0),       # 0500H - 1700H
    "hg night shift": (17, 0),    # 1700H - 0500H
}

# How long before time-in an emergency absence stops being fileable.
# Mirrors DutyClock.absenceCutoff in lib/services/duty_clock.dart.
_ABSENCE_CUTOFF = timedelta(hours=1)

# Time-out (hour, minute) per shift, and whether it lands on the day AFTER
# the duty date. Mirrors shiftTimeRanges in lib/models/guard_shift.dart —
# keep the two in step.
_SHIFT_END_TIMES = {
    "morning shift": ((14, 0), False),     # 0500H - 1400H
    "afternoon shift": ((23, 30), False),  # 1400H - 2330H
    "night shift": ((5, 0), True),         # 2100H - 0500H
    "hg day shift": ((17, 0), False),      # 0500H - 1700H
    "hg night shift": ((5, 0), True),      # 1700H - 0500H
}


def _duty_has_ended(date_str: str, shift_title: str) -> bool:
    """True once the duty's time-out has passed in Philippine time.

    An absence is a request NOT to report — it can't be filed after the
    duty is already stood, or the record would be falsified after the
    fact. Unknown shift titles fall back to the end of the calendar day,
    which is the permissive read: better to accept a late request than to
    block a real emergency because a shift wasn't in the table."""
    try:
        duty_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        return False

    end = _SHIFT_END_TIMES.get(shift_title.strip().lower())
    if end is None:
        end_at = datetime.combine(
            duty_date + timedelta(days=1), datetime.min.time(), tzinfo=_PHT)
    else:
        (hour, minute), next_day = end
        day = duty_date + timedelta(days=1) if next_day else duty_date
        end_at = datetime(day.year, day.month, day.day, hour, minute,
                          tzinfo=_PHT)

    return datetime.now(_PHT) >= end_at


def _absence_cutoff_passed(date_str: str, shift_title: str) -> bool:
    """True once the lock-out window before time-in has begun, in
    Philippine time.

    A guard an hour away from their post has to be counted on to report:
    past this point there is no time left to find a replacement, so the
    emergency goes to the head guard on the ground instead of through an
    app request. Because the cut-off sits an hour before time-in, this
    also covers a duty already running and one already stood.

    Unknown shift titles return False and fall through to the
    duty-has-ended check — the permissive read, so a shift missing from
    the table can't block a real emergency."""
    try:
        duty_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        return False

    start = _SHIFT_START_TIMES.get(shift_title.strip().lower())
    if start is None:
        return False

    hour, minute = start
    start_at = datetime(duty_date.year, duty_date.month, duty_date.day,
                        hour, minute, tzinfo=_PHT)
    return datetime.now(_PHT) >= start_at - _ABSENCE_CUTOFF


@app.post("/absence-requests")
def submit_absence_request(request: AbsenceRequestCreateRequest):
    """Files one emergency absence request from the guard app (sick /
    injury / important occasion). A guard may file only ONCE per date:
    any existing request for that date — pending, approved OR denied —
    rejects a second one with 409, so a decision can't be re-litigated by
    re-filing. Filing closes an hour before time-in, so a duty about to
    start, one already running and one already stood are all rejected.
    New requests are unread, which is what drives the admin
    Notifications screen."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        datetime.strptime(request.date, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")

    # The guard app closes the form an hour before time-in; this is the
    # authoritative check, so a stale screen can't slip one through.
    if _absence_cutoff_passed(request.date, request.shiftTitle):
        raise HTTPException(
            status_code=400,
            detail=("Emergency absence requests close 1 hour before your "
                    "time-in. Report this to your head guard directly."))

    if _duty_has_ended(request.date, request.shiftTitle):
        raise HTTPException(
            status_code=400,
            detail=("That duty has already ended — an absence can only be "
                    "filed before your shift times out."))

    title = request.title.strip()
    body = request.body.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title must not be empty")
    if not body:
        raise HTTPException(status_code=400, detail="body must not be empty")

    # One request per guard per date, whatever its status — a guard can't
    # file again for a date they've already requested (even once it's been
    # approved or denied), so a decision can't be re-litigated by re-filing.
    try:
        existing = repo.absence_requests.find(
            employeeId=request.employeeId.strip())
        prior = next((rec for rec in existing
                      if rec.get("date") == request.date), None)
        if prior is not None:
            status = prior.get("status", "pending")
            phrase = {
                "pending": "already have a pending absence request",
                "approved": "already have an approved absence",
                "denied": "already filed an absence request (it was denied)",
            }.get(status, "already have an absence request")
            raise HTTPException(
                status_code=409,
                detail=f"You {phrase} for {request.date}.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to check existing absence requests: {str(e)}")

    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    request_id = (f"ABR-{request.date.replace('-', '')}-"
                  f"{request.employeeId.strip()}-{suffix}")

    request_data = {
        "id": request_id,
        "employeeId": request.employeeId.strip(),
        "employeeName": request.employeeName.strip(),
        "employeeType": request.employeeType.strip(),
        "station": request.station.strip(),
        "shiftTitle": request.shiftTitle.strip(),
        "date": request.date,
        "title": title,
        "reason": request.reason.strip() or "Other",
        "body": body,
        "status": "pending",
        "submittedAt": datetime.now(timezone.utc).isoformat(),
        "decidedAt": None,
        "decidedBy": None,
        "adminNote": "",
        "isRead": False,
    }

    try:
        db.collection("absence_requests").document(request_id).set(request_data)
        return {"success": True, "request": request_data}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save absence request: {str(e)}")


@app.get("/absence-requests")
def get_absence_requests():
    """Returns every filed absence request, newest first — feeds the
    admin Notifications screen's absence tab."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        requests = sorted(repo.absence_requests.list(),
                          key=lambda r: r.get("submittedAt", ""), reverse=True)
        return {"success": True, "requests": requests}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch absence requests: {str(e)}")


@app.get("/employees/{employee_id}/absence-requests")
def get_employee_absence_requests(employee_id: str):
    """Returns one guard's own absence requests, newest first — the
    history list shown under the filing form in the guard app."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        requests = sorted(repo.absence_requests.find(employeeId=employee_id),
                          key=lambda r: r.get("submittedAt", ""), reverse=True)
        return {"success": True, "requests": requests}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch absence requests: {str(e)}")


@app.post("/absence-requests/{request_id}/decision")
def decide_absence_request(request_id: str,
                           request: AbsenceRequestDecisionRequest):
    """Records the admin's approve/deny decision. Decisions are final —
    a request that was already decided is rejected with 409 — and the
    guard is told the outcome through their Alerts tab."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    status = request.status.strip().lower()
    if status not in ("approved", "denied"):
        raise HTTPException(status_code=400,
                            detail="status must be 'approved' or 'denied'")

    try:
        doc_ref = db.collection("absence_requests").document(request_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404,
                                detail="Absence request not found")
        absence = snap.to_dict()
        if absence.get("status") != "pending":
            raise HTTPException(
                status_code=409,
                detail=f"This request has already been "
                       f"{absence.get('status', 'decided')}.")

        note = request.adminNote.strip()
        decided_at = datetime.now(timezone.utc).isoformat()
        absence.update({
            "status": status,
            "decidedAt": decided_at,
            "decidedBy": request.decidedBy.strip() or "admin",
            "adminNote": note,
            # deciding it counts as reading it — the admin just opened it.
            "isRead": True,
        })
        doc_ref.update({
            "status": absence["status"],
            "decidedAt": absence["decidedAt"],
            "decidedBy": absence["decidedBy"],
            "adminNote": absence["adminNote"],
            "isRead": True,
        })

        # Tell the guard the outcome in the Alerts tab. 'schedule' and
        # 'announcement' are the two non-urgent types the Flutter
        # EmployeeNotification model understands.
        pretty = _absence_pretty_date(absence.get("date", ""))
        message = f"Your absence request for {pretty} was {status}."
        if note:
            message += f" Admin note: {note}"
        _write_notifications([{
            "id": f"NTF-{request_id}-DECISION",
            "employeeId": absence.get("employeeId", ""),
            "type": "schedule" if status == "approved" else "announcement",
            "title": ("Absence Request Approved" if status == "approved"
                      else "Absence Request Denied"),
            "message": message,
            "date": absence.get("date", ""),
            "createdAt": decided_at,
            "isRead": False,
        }])
        return {"success": True, "request": absence}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to decide absence request: {str(e)}")


@app.post("/absence-requests/{request_id}/read")
def mark_absence_request_read(request_id: str):
    """Marks one absence request as read (admin opened it)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("absence_requests").document(request_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404,
                                detail="Absence request not found")
        doc_ref.update({"isRead": True})
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark request read: {str(e)}")


# --- Cover offers (employee volunteers to cover on a rest day) ---
#
# A guard on a rest day says "I'm available to cover a shift today" and
# names the shift times and stations they'd prefer. The offer does not
# assign them to anything — it boosts their ranking in the replacement
# suggestions for that date (replacements.suggest), so the admin sees a
# willing volunteer at the top when a colleague is absent. One offer per
# guard per date, keyed COV-{date}-{employeeId}; re-submitting updates the
# preferences, and withdrawing deletes the doc.

# Shift labels each role is actually allowed to work — a preference outside
# this set can never be matched to a post, so it's dropped on the way in.
_COVER_SHIFTS_BY_TYPE = {
    "regular": ("Morning", "Afternoon", "Night"),
    "reliever": ("Morning", "Afternoon", "Night"),
    "headGuard": ("HG Day", "HG Night"),
}


def _employee_duty_dates(employee_id):
    """ISO dates this employee already has a duty entry on, across every
    PUBLISHED schedule — the days they can't volunteer to cover because
    they're already working them."""
    dates = set()
    for schedule in repo.schedules.find(status="published"):
        for day in schedule.get("days", []):
            if any(e.get("employeeId") == employee_id
                   for e in day.get("entries", [])):
                dates.add(day.get("date"))
    return dates


@app.post("/cover-offers")
def submit_cover_offer(request: CoverOfferCreateRequest):
    """Files (or updates) one guard's offer to cover a shift on a rest day.
    Rejected when the date is in the past or the guard is already on duty
    that day. The document ID is deterministic (date + guard), so editing
    the preferences overwrites the same offer rather than stacking."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    employee_id = request.employeeId.strip()
    if not employee_id:
        raise HTTPException(status_code=400, detail="employeeId is required")

    try:
        offer_day = datetime.strptime(request.date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")

    if offer_day < datetime.now().date():
        raise HTTPException(
            status_code=400,
            detail="You can only offer to cover today or an upcoming rest day.")

    # Can't volunteer for a day you're already rostered to work.
    if request.date in _employee_duty_dates(employee_id):
        raise HTTPException(
            status_code=409,
            detail="You are already on duty that day, so there is nothing "
                   "to cover.")

    # Keep only shift labels this role can actually be posted to, preserving
    # the order the app sent them in.
    allowed = _COVER_SHIFTS_BY_TYPE.get(
        request.employeeType.strip(),
        ("Morning", "Afternoon", "Night"))
    shifts = [s for s in request.preferredShifts if s in allowed]
    stations = [s.strip() for s in request.preferredStations if s.strip()]

    offer_id = f"COV-{request.date.replace('-', '')}-{employee_id}"
    now_iso = datetime.now(timezone.utc).isoformat()

    doc_ref = db.collection("cover_offers").document(offer_id)
    existing = doc_ref.get()
    # A fulfilled offer (the guard was already assigned to cover) is locked —
    # re-opening it would let them re-volunteer for a post they now hold.
    if existing.exists and existing.to_dict().get("status") == "fulfilled":
        raise HTTPException(
            status_code=409,
            detail="You have already been assigned to cover that day.")

    offer = {
        "id": offer_id,
        "employeeId": employee_id,
        "employeeName": request.employeeName.strip(),
        "employeeType": request.employeeType.strip(),
        "date": request.date,
        "preferredShifts": shifts,
        "preferredStations": stations,
        "status": "active",
        "createdAt": (existing.to_dict().get("createdAt")
                      if existing.exists else now_iso),
        "updatedAt": now_iso,
        "fulfilledAt": None,
    }

    try:
        doc_ref.set(offer)
        return {"success": True, "offer": offer}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save cover offer: {str(e)}")


@app.get("/employees/{employee_id}/cover-offers")
def get_employee_cover_offers(employee_id: str):
    """This guard's own cover offers, newest date first — drives the
    availability card and the rest-day badges in the schedule."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        offers = sorted(repo.cover_offers.find(employeeId=employee_id),
                        key=lambda o: o.get("date", ""), reverse=True)
        return {"success": True, "offers": offers}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch cover offers: {str(e)}")


@app.get("/cover-offers")
def get_cover_offers(date: Optional[str] = None, status: Optional[str] = None):
    """Every guard who volunteered to work on one date — the admin side of
    the offer form. Defaults to today; `status` narrows it (usually
    "active", i.e. still standing / not yet assigned to cover). Feeds the
    Volunteer Employee tab on Employees Availability."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    date_iso = date or datetime.now().date().isoformat()
    try:
        datetime.strptime(date_iso, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")

    try:
        offers = repo.cover_offers.find(date=date_iso)
        if status:
            offers = [o for o in offers
                      if o.get("status", "active") == status]
        offers.sort(key=lambda o: o.get("employeeName", ""))
        return {"success": True, "date": date_iso, "offers": offers}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch cover offers: {str(e)}")


@app.delete("/cover-offers/{offer_id}")
def withdraw_cover_offer(offer_id: str):
    """Withdraws an offer the guard no longer wants to stand by. A
    fulfilled offer (already assigned) can't be withdrawn from here."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("cover_offers").document(offer_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Cover offer not found")
        if snap.to_dict().get("status") == "fulfilled":
            raise HTTPException(
                status_code=409,
                detail="You have already been assigned to cover that day, so "
                       "the offer can no longer be withdrawn.")
        doc_ref.delete()
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to withdraw cover offer: {str(e)}")


# --- Special day-off requests (employee-filed, ahead of the schedule) ---

# How far ahead a guard may request a day off before it exists on any
# schedule, and the most dates one request may carry.
SPECIAL_REQUEST_HORIZON_DAYS = 60
SPECIAL_REQUEST_MAX_DATES = 3


def _special_pretty_dates(dates):
    """'2026-08-12', '2026-08-15' -> 'August 12, 2026 and August 15, 2026'
    for the decision notification text."""
    pretty = [_absence_pretty_date(d) for d in dates]
    if not pretty:
        return "the requested dates"
    if len(pretty) == 1:
        return pretty[0]
    return ", ".join(pretty[:-1]) + f" and {pretty[-1]}"


def _scheduled_dates_for_group(group):
    """Every ISO date already covered by a generated schedule for `group`
    — the days a guard in that group can no longer request off, because a
    roster for them already exists. `group` None (floating personnel with
    no resolvable home group) falls back to every group's schedules, so a
    floating guard can't request a day some station already booked them
    for."""
    covered = set()
    for s in repo.schedules.list():
        if group is not None and s.get("group") != group:
            continue
        start, end = s.get("startDate"), s.get("endDate")
        if not start or not end:
            continue
        try:
            d = datetime.strptime(start, "%Y-%m-%d").date()
            last = datetime.strptime(end, "%Y-%m-%d").date()
        except ValueError:
            continue
        while d <= last:
            covered.add(d.isoformat())
            d += timedelta(days=1)
    return covered


def _employee_home_group(employee):
    """Resolves the group whose schedules govern this employee, via the
    same station->group rule the scheduler uses. None when it can't be
    resolved (floating personnel with no assigned/preferred station)."""
    try:
        stations = repo.stations.list()
        group_of = station_pools.station_groups(stations)
        return station_pools.home_group(employee, group_of)
    except Exception:
        return None


def _special_request_window(employee):
    """The bounds the guard app's date picker needs: the earliest and
    latest selectable day, plus the days inside that window it must grey
    out (already scheduled for the employee's group)."""
    today = datetime.now().date()
    min_date = today + timedelta(days=1)               # strictly future
    max_date = today + timedelta(days=SPECIAL_REQUEST_HORIZON_DAYS)
    scheduled = _scheduled_dates_for_group(_employee_home_group(employee))
    blocked = sorted(
        d for d in scheduled if min_date.isoformat() <= d <= max_date.isoformat()
    )
    return min_date, max_date, blocked


def _employee_special_dates(employee_id, statuses=None):
    """ISO dates this employee already has a special request for. Limited
    to `statuses` when given (e.g. only pending/approved block a re-file);
    all statuses otherwise."""
    taken = {}
    for r in repo.special_requests.find(employeeId=employee_id):
        if statuses is not None and r.get("status") not in statuses:
            continue
        for d in r.get("dates", []):
            taken[d] = r.get("status", "pending")
    return taken


@app.post("/special-requests")
def submit_special_request(request: SpecialRequestCreateRequest):
    """Files one special day-off request (1..3 future, still-unscheduled
    dates sharing one title/reason). The whole request is approved or
    denied as a unit. A date the guard already has a pending or approved
    request for is rejected — a denied date, by contrast, may be filed
    again, since plans change and the day is still unscheduled."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    employee_id = request.employeeId.strip()
    if not employee_id:
        raise HTTPException(status_code=400, detail="employeeId is required")

    title = request.title.strip()
    body = request.body.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title must not be empty")
    if not body:
        raise HTTPException(status_code=400, detail="body must not be empty")

    # Normalise + validate the dates: de-duplicated, each a real ISO date.
    raw_dates = []
    for d in request.dates:
        d = (d or "").strip()
        if not d or d in raw_dates:
            continue
        try:
            datetime.strptime(d, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(status_code=400,
                                detail=f"{d} is not a valid YYYY-MM-DD date")
        raw_dates.append(d)
    if not raw_dates:
        raise HTTPException(status_code=400,
                            detail="Select at least one date to request off.")
    if len(raw_dates) > SPECIAL_REQUEST_MAX_DATES:
        raise HTTPException(
            status_code=400,
            detail=f"You can request at most {SPECIAL_REQUEST_MAX_DATES} "
                   f"dates in one request.")
    dates = sorted(raw_dates)

    # Resolve the employee so the window (and its group) is computed against
    # a real record; fall back to the request's own fields if not found.
    employee = repo.employees.get(employee_id) or {
        "id": employee_id,
        "assignedStation": request.station.strip(),
    }

    today = datetime.now().date()
    min_iso = (today + timedelta(days=1)).isoformat()
    max_iso = (today + timedelta(days=SPECIAL_REQUEST_HORIZON_DAYS)).isoformat()
    for d in dates:
        if d < min_iso:
            raise HTTPException(
                status_code=400,
                detail=f"{d} is in the past or today — pick an upcoming day.")
        if d > max_iso:
            raise HTTPException(
                status_code=400,
                detail=f"{d} is more than {SPECIAL_REQUEST_HORIZON_DAYS} days "
                       f"out — requests only reach {max_iso}.")

    # Reject any date that already has a generated schedule for this group:
    # a day off can only be requested before the roster exists.
    scheduled = _scheduled_dates_for_group(_employee_home_group(employee))
    clashes = [d for d in dates if d in scheduled]
    if clashes:
        raise HTTPException(
            status_code=409,
            detail=f"A schedule already exists for {_special_pretty_dates(clashes)}"
                   f" — that day can no longer be requested off.")

    # Only a pending or approved request blocks a date; denied ones don't.
    taken = _employee_special_dates(employee_id, statuses=("pending", "approved"))
    dupes = [d for d in dates if d in taken]
    if dupes:
        raise HTTPException(
            status_code=409,
            detail=f"You already have a request covering "
                   f"{_special_pretty_dates(dupes)}.")

    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    request_id = f"SPR-{dates[0].replace('-', '')}-{employee_id}-{suffix}"

    request_data = {
        "id": request_id,
        "employeeId": employee_id,
        "employeeName": request.employeeName.strip(),
        "employeeType": request.employeeType.strip(),
        "station": request.station.strip(),
        "dates": dates,
        "title": title,
        "reason": request.reason.strip() or "Other",
        "body": body,
        "status": "pending",
        "submittedAt": datetime.now(timezone.utc).isoformat(),
        "decidedAt": None,
        "decidedBy": None,
        "adminNote": "",
        "isRead": False,
    }

    try:
        db.collection("special_requests").document(request_id).set(request_data)
        return {"success": True, "request": request_data}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save special request: {str(e)}")


@app.get("/special-requests")
def get_special_requests():
    """Every filed special request, newest first — feeds the admin
    Notifications screen's Special Requests tab."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        requests = sorted(repo.special_requests.list(),
                          key=lambda r: r.get("submittedAt", ""), reverse=True)
        return {"success": True, "requests": requests}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch special requests: {str(e)}")


@app.get("/employees/{employee_id}/special-requests")
def get_employee_special_requests(employee_id: str):
    """One guard's own special requests, newest first — the history list
    shown under the filing form."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        requests = sorted(repo.special_requests.find(employeeId=employee_id),
                          key=lambda r: r.get("submittedAt", ""), reverse=True)
        return {"success": True, "requests": requests}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch special requests: {str(e)}")


@app.get("/employees/{employee_id}/special-request-window")
def get_special_request_window(employee_id: str):
    """Bounds + exclusions the guard app's date picker needs: the earliest
    and latest selectable day, the days already scheduled (greyed out), and
    the dates this guard has already requested (pending/approved)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        employee = repo.employees.get(employee_id) or {"id": employee_id}
        min_date, max_date, blocked = _special_request_window(employee)
        requested = sorted(
            _employee_special_dates(employee_id, statuses=("pending", "approved")))
        return {
            "success": True,
            "minDate": min_date.isoformat(),
            "maxDate": max_date.isoformat(),
            "maxDates": SPECIAL_REQUEST_MAX_DATES,
            "blockedDates": blocked,
            "requestedDates": requested,
        }
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to build request window: {str(e)}")


@app.post("/special-requests/{request_id}/decision")
def decide_special_request(request_id: str,
                           request: SpecialRequestDecisionRequest):
    """Records the admin's approve/deny decision on the whole request.
    Decisions are final (a decided request 409s), and the guard is told
    the outcome in their Alerts tab. An approved request forces its
    day-offs the next time that period's schedule is generated."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    status = request.status.strip().lower()
    if status not in ("approved", "denied"):
        raise HTTPException(status_code=400,
                            detail="status must be 'approved' or 'denied'")

    try:
        doc_ref = db.collection("special_requests").document(request_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404,
                                detail="Special request not found")
        special = snap.to_dict()
        if special.get("status") != "pending":
            raise HTTPException(
                status_code=409,
                detail=f"This request has already been "
                       f"{special.get('status', 'decided')}.")

        note = request.adminNote.strip()
        decided_at = datetime.now(timezone.utc).isoformat()
        special.update({
            "status": status,
            "decidedAt": decided_at,
            "decidedBy": request.decidedBy.strip() or "admin",
            "adminNote": note,
            "isRead": True,
        })
        doc_ref.update({
            "status": special["status"],
            "decidedAt": special["decidedAt"],
            "decidedBy": special["decidedBy"],
            "adminNote": special["adminNote"],
            "isRead": True,
        })

        pretty = _special_pretty_dates(special.get("dates", []))
        message = f"Your special day-off request for {pretty} was {status}."
        if note:
            message += f" Admin note: {note}"
        _write_notifications([{
            "id": f"NTF-{request_id}-DECISION",
            "employeeId": special.get("employeeId", ""),
            "type": "schedule" if status == "approved" else "announcement",
            "title": ("Special Request Approved" if status == "approved"
                      else "Special Request Denied"),
            "message": message,
            "date": (special.get("dates") or [""])[0],
            "createdAt": decided_at,
            "isRead": False,
        }])
        return {"success": True, "request": special}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to decide special request: {str(e)}")


@app.post("/special-requests/{request_id}/read")
def mark_special_request_read(request_id: str):
    """Marks one special request as read (admin opened it)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection("special_requests").document(request_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404,
                                detail="Special request not found")
        doc_ref.update({"isRead": True})
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark request read: {str(e)}")


@app.post("/schedules/publish-all")
def publish_all_schedules():
    """Marks every unpublished schedule as published and notifies each
    guard appearing in them."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        docs = list(db.collection("schedules")
                    .where("status", "==", "unpublished").stream())
        # Schedules with Undefined posts stay unpublished — the admin
        # has to name every post first. Empty schedules (no guards on any
        # day) stay unpublished too: publishing one would just disconnect
        # Station Management from Schedule Management. The rest go out.
        ready, skipped, skipped_empty = [], [], []
        for doc in docs:
            data = doc.to_dict()
            name = (data.get("stationName") or data.get("id", "?")).strip()
            if _is_empty_schedule(data):
                skipped_empty.append(name)
            elif _undefined_post_guards(data):
                skipped.append(name)
            else:
                ready.append(doc)

        batch = db.batch()
        for doc in ready:
            batch.update(doc.reference, {"status": "published"})
        batch.commit()

        notifications = []
        for doc in ready:
            notifications.extend(
                _schedule_publish_notifications(doc.to_dict()))
        _write_notifications(notifications)
        return {"success": True, "published": len(ready),
                "skippedUndefined": sorted(skipped),
                "skippedEmpty": sorted(skipped_empty)}
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to publish schedules: {str(e)}")


# --- Employee leave ------------------------------------------------------
# Two ways in: a guard files one from the app's dashboard (status
# 'pending', the admin decides), or the admin records one directly from
# Employee Details (status 'approved' on save). Every rule — duration
# caps per leave type, the 7-day lead time, the schedule conflict, the
# 2-per-year quota and the 6-month cooldown — is decided in leave.py, so
# the endpoints below only translate its refusals into HTTP.

def _leave_employee(employee_id, fallback=None):
    """The employee record the rules are evaluated against. Falls back to
    the fields the caller sent so a request can still be filed for an
    employee the collection has lost track of."""
    employee = repo.employees.get(employee_id)
    if employee is not None:
        return employee
    if fallback is None:
        raise HTTPException(status_code=404, detail="Employee not found")
    return fallback


def _leave_http(err: leave.LeaveError):
    """A rules refusal as an HTTPException, keeping the blockers list so
    the admin form knows which override to offer."""
    detail = err.detail
    if err.blockers:
        return HTTPException(status_code=err.status,
                             detail={"message": detail,
                                     "blockers": err.blockers})
    return HTTPException(status_code=err.status, detail=detail)


def _leave_id(prefix, start_iso, employee_id):
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    return f"{prefix}-{start_iso.replace('-', '')}-{employee_id}-{suffix}"


def _leave_notification(record, *, title, message, notif_type):
    _write_notifications([{
        "id": f"NTF-{record['id']}-{notif_type.upper()}",
        "employeeId": record.get("employeeId", ""),
        "type": "schedule" if notif_type == "approved" else "announcement",
        "title": title,
        "message": message,
        "date": record.get("startDate", ""),
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "isRead": False,
    }])


@app.get("/leave-types")
def get_leave_types():
    """The leave catalogue and each type's day cap — the guard app's and
    the admin form's dropdown, so neither hardcodes the caps."""
    return {
        "success": True,
        "leaveTypes": [{"name": name, "maxDays": cap}
                       for name, cap in leave.LEAVE_TYPES.items()],
        "defaultLeaveType": leave.DEFAULT_LEAVE_TYPE,
        "minLeaveDays": leave.MIN_LEAVE_DAYS,
        "minLeadDays": leave.MIN_LEAD_DAYS,
        "leavesPerYear": leave.LEAVES_PER_YEAR,
        "cooldownMonths": leave.COOLDOWN_MONTHS,
    }


@app.get("/employees/{employee_id}/leave-window")
def get_leave_window(employee_id: str):
    """Everything the guard app's leave form needs before anything is
    typed: whether this employee may file at all (and why not), the
    earliest day they could start, the days already rostered, and where
    they stand on quota and cooldown."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        employee = _leave_employee(employee_id)
        return {"success": True, **leave.eligibility(db, employee)}
    except leave.LeaveError as e:
        raise _leave_http(e)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to build leave window: {str(e)}")


@app.post("/leave-requests")
def submit_leave_request(request: LeaveRequestCreateRequest):
    """Files one leave request from the guard app. Lands as 'pending' —
    the guard is told approval takes 2-3 days — and every rule is
    enforced here rather than trusted from the client."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    employee_id = request.employeeId.strip()
    if not employee_id:
        raise HTTPException(status_code=400, detail="employeeId is required")

    title = request.title.strip()
    body = request.body.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title must not be empty")
    if not body:
        raise HTTPException(status_code=400,
                            detail="Describe the reason for your leave.")

    employee = _leave_employee(employee_id, fallback={
        "id": employee_id,
        "name": request.employeeName.strip(),
        "type": request.employeeType.strip() or "regular",
        "assignedStation": request.station.strip(),
    })

    try:
        start = leave.parse_date(request.startDate, "startDate")
        end = leave.parse_date(request.endDate, "endDate")
        leave_type = leave.validate_employee_request(
            db, employee, request.leaveType, start, end)
    except leave.LeaveError as e:
        raise _leave_http(e)

    record = leave.new_record(
        request_id=_leave_id("LVR", start.isoformat(), employee_id),
        employee=employee,
        leave_type=leave_type,
        start=start,
        end=end,
        title=title,
        body=body,
        source="employee",
        status="pending",
        now_iso=datetime.now(timezone.utc).isoformat(),
    )

    try:
        db.collection(leave.COLLECTION).document(record["id"]).set(record)
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save leave request: {str(e)}")

    # The guard's own receipt, in the same Alerts inbox the decision will
    # land in — so "did it actually go through?" has an answer that
    # outlives the confirmation dialog. Written after the save and never
    # allowed to fail the call: the request IS filed at this point, and a
    # missing alert must not report it as an error.
    try:
        pretty = leave.pretty_range(record["startDate"], record["endDate"])
        _leave_notification(
            record,
            title="Leave Request Sent",
            message=(f"Your {record['leaveType']} for {pretty} "
                     f"({record['days']} days) was sent to the admin. "
                     f"Approval may take at least 2-3 days — the decision "
                     f"will appear here."),
            notif_type="submitted")
    except Exception:
        pass

    return {"success": True, "request": record}


@app.get("/leave-requests")
def get_leave_requests():
    """Every leave record, newest first — feeds the admin Notifications
    tab and the Leave Report."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        docs = db.collection(leave.COLLECTION).stream()
        requests = sorted((doc.to_dict() for doc in docs),
                          key=lambda r: r.get("submittedAt", ""), reverse=True)
        for r in requests:
            r["phase"] = leave.phase_of(r)
        return {"success": True, "requests": requests}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch leave requests: {str(e)}")


@app.get("/employees/{employee_id}/leave-requests")
def get_employee_leave_requests(employee_id: str):
    """One employee's leave history, newest first — the list under the
    guard app's filing form and on Employee Details."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        requests = leave.employee_leaves(db, employee_id)
        requests.sort(key=lambda r: r.get("submittedAt", ""), reverse=True)
        for r in requests:
            r["phase"] = leave.phase_of(r)
        return {"success": True, "requests": requests}
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch leave requests: {str(e)}")


@app.get("/leaves/active")
def get_active_leaves(date: Optional[str] = None):
    """{employeeId: leave} for every approved leave covering the given
    day (today by default) — how the employee list and Employee Details
    show 'On Leave' without walking each employee's history."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        on = leave.parse_date(date, "date") if date else None
        return {"success": True, "leaves": leave.active_leaves(db, on)}
    except leave.LeaveError as e:
        raise _leave_http(e)
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to fetch active leaves: {str(e)}")


@app.get("/leave-requests/{request_id}/impact")
def get_leave_impact(request_id: str):
    """What approving this leave costs the roster — the duties it
    swallows and how thin it leaves the employee's shift. Read by the
    approval dialog so nobody approves a 15-day leave blind."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        snap = db.collection(leave.COLLECTION).document(request_id).get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Leave request not found")
        record = snap.to_dict()
        employee = _leave_employee(record.get("employeeId", ""), fallback={
            "id": record.get("employeeId", ""),
            "name": record.get("employeeName", ""),
            "assignedStation": record.get("station", ""),
        })
        impact = leave.coverage_impact(
            db, employee,
            leave.parse_date(record.get("startDate"), "startDate"),
            leave.parse_date(record.get("endDate"), "endDate"))
        cap = leave.cap_for(record.get("leaveType", ""))
        return {
            "success": True,
            "impact": impact,
            "cap": cap,
            "overCap": record.get("days", 0) > cap,
        }
    except leave.LeaveError as e:
        raise _leave_http(e)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to build leave impact: {str(e)}")


@app.post("/leave-requests/{request_id}/decision")
def decide_leave_request(request_id: str, request: LeaveDecisionRequest):
    """Records the admin's approve/deny decision. Decisions are final (a
    decided request 409s).

    Approving a leave that runs past its type's cap needs the endorsement
    of a higher authority. The system has no supervisor account, so the
    endorsement is recorded as the admin naming the supervisor they
    cleared it with — refused outright if that is left blank, and stored
    on the record so the leave report can show who authorised it."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    status = request.status.strip().lower()
    if status not in ("approved", "denied"):
        raise HTTPException(status_code=400,
                            detail="status must be 'approved' or 'denied'")

    try:
        doc_ref = db.collection(leave.COLLECTION).document(request_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Leave request not found")
        record = snap.to_dict()
        if record.get("status") != "pending":
            raise HTTPException(
                status_code=409,
                detail=f"This leave request has already been "
                       f"{record.get('status', 'decided')}.")

        cap = leave.cap_for(record.get("leaveType", ""))
        over_cap = record.get("days", 0) > cap
        supervisor = request.supervisorName.strip()
        if status == "approved" and over_cap:
            if not (request.supervisorConfirmed and supervisor):
                raise HTTPException(
                    status_code=400,
                    detail={
                        "message":
                            f"This {record.get('days')}-day leave runs past "
                            f"the {cap}-day cap for "
                            f"{record.get('leaveType')}. Approving it without "
                            f"proper consent from the higher authority will "
                            f"result to heavy penalty — name the supervisor "
                            f"who endorsed it and confirm before approving.",
                        "requiresEndorsement": True,
                        "cap": cap,
                        "days": record.get("days"),
                    })

        note = request.adminNote.strip()
        decided_at = datetime.now(timezone.utc).isoformat()
        updates = {
            "status": status,
            "decidedAt": decided_at,
            "decidedBy": request.decidedBy.strip() or "admin",
            "adminNote": note,
            "supervisorName": supervisor,
            "isRead": True,
        }
        record.update(updates)
        doc_ref.update(updates)

        pretty = leave.pretty_range(record.get("startDate", ""),
                                    record.get("endDate", ""))
        message = (f"Your {record.get('leaveType')} for {pretty} "
                   f"({record.get('days')} days) was {status}.")
        if supervisor:
            message += f" Endorsed by {supervisor}."
        if note:
            message += f" Admin note: {note}"
        _leave_notification(
            record,
            title="Leave Approved" if status == "approved" else "Leave Denied",
            message=message,
            notif_type=status)

        return {"success": True, "request": record}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to decide leave request: {str(e)}")


@app.post("/leave-requests/{request_id}/read")
def mark_leave_request_read(request_id: str):
    """Marks one leave request as read (admin opened it)."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection(leave.COLLECTION).document(request_id)
        if not doc_ref.get().exists:
            raise HTTPException(status_code=404, detail="Leave request not found")
        doc_ref.update({"isRead": True})
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to mark leave request read: {str(e)}")


@app.delete("/leave-requests/{request_id}")
def withdraw_leave_request(request_id: str):
    """The guard withdrawing their own request before it is decided. Only
    a pending one can go: once approved it is the admin's to cancel, and
    withdrawing releases the year's quota slot it was holding."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection(leave.COLLECTION).document(request_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Leave request not found")
        record = snap.to_dict()
        if record.get("status") != "pending":
            raise HTTPException(
                status_code=409,
                detail=f"This leave has already been "
                       f"{record.get('status', 'decided')} and can no longer "
                       f"be withdrawn.")
        doc_ref.delete()
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to withdraw leave request: {str(e)}")


@app.post("/leave-requests/{request_id}/cancel")
def cancel_leave(request_id: str, request: LeaveCancelRequest):
    """The admin cancelling an approved leave — the employee comes off
    'On Leave' and the days go back to the roster. Kept as a 'cancelled'
    record rather than deleted, so the report still shows it happened,
    and the quota slot it held is released."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    try:
        doc_ref = db.collection(leave.COLLECTION).document(request_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Leave request not found")
        record = snap.to_dict()
        if record.get("status") not in ("approved", "pending"):
            raise HTTPException(
                status_code=409,
                detail=f"A {record.get('status')} leave cannot be cancelled.")

        reason = request.reason.strip()
        updates = {
            "status": "cancelled",
            "cancelledAt": datetime.now(timezone.utc).isoformat(),
            "cancelledBy": request.cancelledBy.strip() or "admin",
            "cancelReason": reason,
        }
        record.update(updates)
        doc_ref.update(updates)

        message = (f"Your {record.get('leaveType')} for "
                   f"{leave.pretty_range(record.get('startDate', ''), record.get('endDate', ''))} "
                   f"was cancelled.")
        if reason:
            message += f" Reason: {reason}"
        _leave_notification(record, title="Leave Cancelled",
                            message=message, notif_type="cancelled")
        return {"success": True, "request": record}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
                            detail=f"Failed to cancel leave: {str(e)}")


@app.post("/employees/{employee_id}/leave")
def set_employee_on_leave(employee_id: str, request: AdminLeaveCreateRequest):
    """The admin's 'Set On Leave' form on Employee Details. Saved as
    approved — the admin is recording a decision, not asking for one.

    The 7-day lead time is skipped (the leave has already been agreed)
    and a schedule conflict does NOT refuse the save: the duties the
    leave swallows come back in `affectedDuties` so they can be handed to
    Find Replacement rather than quietly going unmanned. The quota,
    cooldown, overlap and duration caps still apply — the first submit
    returns them as `blockers`, and only a second submit naming the
    endorsing supervisor may proceed past them."""
    if db is None:
        raise HTTPException(status_code=500, detail="Database not initialized")

    title = request.title.strip()
    body = request.body.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title must not be empty")
    if not body:
        raise HTTPException(status_code=400,
                            detail="Describe the reason for this leave.")

    employee = _leave_employee(employee_id)

    try:
        start = leave.parse_date(request.startDate, "startDate")
        end = leave.parse_date(request.endDate, "endDate")
        leave_type = leave.normalise_type(request.leaveType)
        # Length is checked before the overridable rules on purpose: too
        # short is the wrong form, not something a supervisor can endorse.
        leave.check_duration(leave_type, start, end)
    except leave.LeaveError as e:
        raise _leave_http(e)

    blockers = leave.admin_blockers(db, employee, leave_type, start, end)
    supervisor = request.supervisorName.strip()
    if blockers:
        if not request.overrideRules:
            raise HTTPException(status_code=409, detail={
                "message": "This leave breaks the leave rules. Approving it "
                           "without proper consent from the higher authority "
                           "will result to heavy penalty.",
                "blockers": blockers,
                "requiresEndorsement": True,
            })
        if not (request.supervisorConfirmed and supervisor):
            raise HTTPException(status_code=400, detail={
                "message": "Name the supervisor who endorsed this leave and "
                           "confirm before overriding the rules.",
                "blockers": blockers,
                "requiresEndorsement": True,
            })

    impact = leave.coverage_impact(db, employee, start, end)
    record = leave.new_record(
        request_id=_leave_id("LVA", start.isoformat(), employee_id),
        employee=employee,
        leave_type=leave_type,
        start=start,
        end=end,
        title=title,
        body=body,
        source="admin",
        status="approved",
        now_iso=datetime.now(timezone.utc).isoformat(),
        decided_by=request.createdBy.strip() or "admin",
        admin_note=request.adminNote.strip(),
        supervisor_name=supervisor,
        overrides=blockers,
        affected=impact["affectedDuties"],
    )

    try:
        db.collection(leave.COLLECTION).document(record["id"]).set(record)
    except Exception as e:
        raise HTTPException(status_code=500,
                            detail=f"Failed to save leave: {str(e)}")

    pretty = leave.pretty_range(record["startDate"], record["endDate"])
    _leave_notification(
        record,
        title="You have been placed on leave",
        message=f"You are on {leave_type} from {pretty} "
                f"({record['days']} days). {title}",
        notif_type="approved")

    return {"success": True, "request": record, "impact": impact}