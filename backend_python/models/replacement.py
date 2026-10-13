# models/replacement.py
# Request bodies for the replacement endpoints: reviewing the suggested
# candidates, and committing the one the admin picked.
from typing import Optional
from pydantic import BaseModel, Field


class AiReviewRequest(BaseModel):
    """POST /replacements/ai-review — the same four values that identify
    the absence to /replacements/suggest.

    A body rather than query parameters, because the method is what keeps
    this endpoint out of the golden capture: golden_capture.py records GET
    responses, and a GET here would be swept in and pin a model's wording
    as a contract.
    """
    date: str                    # ISO date of the absence, YYYY-MM-DD
    station: str                 # station name (as stored on schedules)
    shift: str                   # 'Morning' | 'Afternoon' | 'Night' | 'HG Day' | 'HG Night'
    absentEmployeeId: str


class ReplacementApplyRequest(BaseModel):
    reason: str = Field(default="", max_length=2000)
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
