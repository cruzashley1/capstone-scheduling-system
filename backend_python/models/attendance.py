# models/attendance.py
# Request bodies for the attendance-report endpoints (Phase 3 absence
# handling): a Head Guard submits the attendance for their station's
# shift, and the admin reads it from the Notifications screen.
from typing import List
from pydantic import BaseModel


class AttendanceRecordIn(BaseModel):
    employeeId: str
    name: str
    shift: str          # 'Morning' | 'Afternoon' | 'Night' | ...
    time: str           # display string, e.g. '0600H - 1400H'
    isPresent: bool
    isReliever: bool = False


class AttendanceReportCreateRequest(BaseModel):
    headGuardId: str
    headGuardName: str
    station: str
    shiftTitle: str     # e.g. 'Day Shift' / 'Night Shift'
    date: str           # ISO date the attendance is for, YYYY-MM-DD
    records: List[AttendanceRecordIn]
