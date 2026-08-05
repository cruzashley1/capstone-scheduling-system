# models/absence.py
# Request bodies for the emergency absence-request endpoints: a guard
# (head guard, regular or reliever) files that they cannot report for
# duty, and the admin approves or denies it from the Notifications
# screen.
from pydantic import BaseModel


class AbsenceRequestCreateRequest(BaseModel):
    employeeId: str
    employeeName: str
    employeeType: str   # 'regular' | 'reliever' | 'headGuard'
    station: str        # '' when unknown
    shiftTitle: str     # '' when unknown / rest day
    date: str           # ISO date of the absence, YYYY-MM-DD
    title: str
    reason: str         # Sick|Injury|Family Emergency|Important Occasion|Other
    body: str


class AbsenceRequestDecisionRequest(BaseModel):
    status: str              # 'approved' | 'denied'
    adminNote: str = ""
    decidedBy: str = "admin"
