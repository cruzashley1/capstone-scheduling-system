# models/replacement.py
# Request body for POST /replacements/apply — the admin picked one of
# the suggested candidates and is committing the schedule change.
from typing import Optional
from pydantic import BaseModel


class ReplacementApplyRequest(BaseModel):
    date: str                    # ISO date of the absence, YYYY-MM-DD
    station: str                 # station name (as stored on schedules)
    shift: str                   # 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | 'HG Night'
    absentEmployeeId: str
    absentEmployeeName: Optional[str] = None
    replacementEmployeeId: str
    reportId: Optional[str] = None   # stamps that report's record directly
    # When set, this replacement is the "cover" step of approving an
    # emergency absence request: applying it also flips that request to
    # 'approved' (approval can't finish without a cover).
    absenceRequestId: Optional[str] = None
