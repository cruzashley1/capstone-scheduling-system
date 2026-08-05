"""
Pydantic request model for auth-related endpoints.

Split out of api.py alongside the employee.py / station.py move.
"""

from typing import List

from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str


class ChangePasswordRequest(BaseModel):
    username: str
    currentPassword: str
    newPassword: str


class ConfirmStationsRequest(BaseModel):
    """Sent once during onboarding when the employee confirms/edits the
    preferred stations shown to them after their first password change."""
    username: str
    preferredStations: List[str] = []