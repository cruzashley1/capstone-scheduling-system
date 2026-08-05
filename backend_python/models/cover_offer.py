# models/cover_offer.py
# Request body for the cover-availability endpoints: an employee who is
# on a rest day volunteers to cover a shift that day, with the shift
# times and stations they'd prefer to be deployed to. The offer boosts
# their ranking in the replacement suggestions for that date (see
# replacements.suggest); it is not an assignment on its own.
from typing import List
from pydantic import BaseModel


class CoverOfferCreateRequest(BaseModel):
    employeeId: str
    employeeName: str
    employeeType: str          # 'regular' | 'reliever' | 'headGuard'
    date: str                  # ISO rest-day date the offer is for, YYYY-MM-DD
    # Shift labels the guard is willing to work, in the same vocabulary the
    # schedule uses: 'Morning' | 'Afternoon' | 'Night' for regulars and
    # relievers, 'HG Day' | 'HG Night' for head guards. Empty = any shift.
    preferredShifts: List[str] = []
    # Station names the guard wants to be deployed to. Empty = any station.
    preferredStations: List[str] = []
