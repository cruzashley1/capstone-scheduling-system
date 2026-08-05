# models/leave.py
#
# Request bodies for the leave endpoints. An employee files a leave from
# the guard app's dashboard (a date range, a leave type, a title and a
# description); the admin approves or denies it from the Notifications
# screen's Leave Requests tab, or records one directly from Employee
# Details. Every rule behind these lives in leave.py.
from typing import List, Optional

from pydantic import BaseModel


class LeaveRequestCreateRequest(BaseModel):
    employeeId: str
    employeeName: str = ""
    employeeType: str = ""      # 'regular' | 'reliever' | 'headGuard'
    station: str = ""           # '' when unknown / floating
    leaveType: str              # one of leave.LEAVE_TYPES
    startDate: str              # ISO YYYY-MM-DD, inclusive
    endDate: str                # ISO YYYY-MM-DD, inclusive
    title: str
    body: str


class LeaveDecisionRequest(BaseModel):
    status: str                 # 'approved' | 'denied'
    adminNote: str = ""
    decidedBy: str = "admin"
    # Required only when approving a leave that runs past its type's cap:
    # the system has no supervisor account, so the endorsement is recorded
    # as the admin attesting to it rather than as a second login.
    supervisorName: str = ""
    supervisorConfirmed: bool = False


class AdminLeaveCreateRequest(BaseModel):
    """The admin's 'Set On Leave' form on Employee Details. Approved the
    moment it is saved — the admin is recording a decision, not asking
    for one."""
    leaveType: str
    startDate: str
    endDate: str
    title: str
    body: str
    createdBy: str = "admin"
    adminNote: str = ""
    # Set on the second submit, once the admin has seen the blockers the
    # first submit returned and named the supervisor who endorsed them.
    overrideRules: bool = False
    supervisorName: str = ""
    supervisorConfirmed: bool = False


class LeaveCancelRequest(BaseModel):
    cancelledBy: str = "admin"
    reason: str = ""
