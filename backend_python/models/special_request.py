# models/special_request.py
#
# Request bodies for the special day-off endpoints. An employee asks —
# ahead of time, before any schedule covers those days — for up to three
# specific dates off (a vacation, a family event, a medical appointment).
# The admin approves or denies the whole request from the Notifications
# screen's Special Requests tab, and an approved request forces those
# day-offs when the schedule for that period is later generated.
from typing import List

from pydantic import BaseModel


class SpecialRequestCreateRequest(BaseModel):
    employeeId: str
    employeeName: str
    employeeType: str   # 'regular' | 'reliever' | 'headGuard'
    station: str        # '' when unknown / floating
    dates: List[str]    # 1..3 ISO dates, YYYY-MM-DD, all still unscheduled
    title: str
    reason: str         # Vacation|Family Event|Medical|Personal|Other
    body: str


class SpecialRequestDecisionRequest(BaseModel):
    status: str              # 'approved' | 'denied'
    adminNote: str = ""
    decidedBy: str = "admin"
