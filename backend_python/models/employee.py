"""
Pydantic request models for the Employee endpoints.

Moved out of api.py during the models/ folder reorganization.
No behavior change - these are the exact same classes/function that
used to live directly in api.py.
"""

from typing import List, Optional
from pydantic import BaseModel


class EmployeeCreateRequest(BaseModel):
    name: str
    mobileNo: str
    role: str  # 'Regular Employee' | 'Reliever Employee' | 'Head Guard'
    email: Optional[str] = None
    preferredStations: List[str] = []


class EmployeeUpdateRequest(BaseModel):
    # All optional — only the fields the admin actually changed are sent.
    # username/password/dateJoined are intentionally excluded: they're
    # generated once at creation and shouldn't be editable here.
    name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    preferredStations: Optional[List[str]] = None
    type: Optional[str] = None  # 'regular' | 'reliever' | 'headGuard'
    isActive: Optional[bool] = None


# Maps the role string coming from the Flutter dropdown to the value
# the Flutter Employee model's `EmployeeType` enum expects (must match
# `enum EmployeeType { regular, reliever, headGuard }` exactly).
def _role_to_type(role: str) -> str:
    mapping = {
        "Regular Employee": "regular",
        "Reliever Employee": "reliever",
        "Head Guard": "headGuard",
    }
    return mapping.get(role, "regular")