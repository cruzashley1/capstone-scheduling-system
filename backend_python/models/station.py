"""
Pydantic request models for the Station endpoints.

A station is configured per shift, not by one flat headcount: each of
morning / afternoon / night carries its own required number AND the list
of named posts that number is made of (Head Guard, Ladder, Roving, SE
Platform, SW Platform, or anything the admin types).

Head guard rule baked into the shape:
  * Every station has two head guards on 12-hour duties. The day HG
    covers morning and runs into the afternoon; the night HG covers the
    night.
  * So "Head Guard" is the first post of MORNING and NIGHT, and the
    AFTERNOON list has no head guard at all — the day HG is still on
    duty for it.
  * The head guard counts INSIDE its shift's required number:
    morning 7 = Head Guard + 6 others, night 3 = Head Guard + 2 Roving.

Each post also carries the duty WINDOW that slot is manned for, sent as
`postTimes` alongside `posts`. The windows are staggered: the first two
regular posts of a shift sit on its base window and every one after that
starts two hours later, so cover is kept while guards rotate off. See
station_posts.py — it owns the ladder, and api.py normalizes whatever the
client sends through it before saving.

`requiredEmployees` is no longer sent by the client — api.py derives it
as morning + afternoon + night so the older screens that show one
headline number keep working.
"""

from typing import List, Optional

from pydantic import BaseModel

HEAD_GUARD_POST = "Head Guard"

SHIFT_KEYS = ("morning", "afternoon", "night")


class PostTime(BaseModel):
    """One slot's duty window.

    `auto` False means the admin overrode this slot by hand, so the
    stagger ladder must leave it alone when posts are added or removed
    around it. Times are "HH:MM"; api.py re-normalizes them anyway, so a
    malformed one falls back to the ladder rather than being rejected.
    """
    start: str = ""
    end: str = ""
    auto: bool = True


class StationPosts(BaseModel):
    """One entry per slot, in the order the generator hands them out, so
    a shift's list is as long as its required number.

    An empty string is a slot the admin hasn't named yet: it generates as
    "Undefined", which is allowed (Edit Station warns about it) but still
    blocks publishing. Empties are never dropped — removing one would
    shift every post after it onto the wrong guard.
    """
    morning: List[str] = []
    afternoon: List[str] = []
    night: List[str] = []

    def cleaned(self) -> dict:
        return {
            key: [(p or "").strip() for p in getattr(self, key)]
            for key in SHIFT_KEYS
        }


class StationPostTimes(BaseModel):
    """`posts`' companion: one window per slot, aligned by index."""
    morning: List[PostTime] = []
    afternoon: List[PostTime] = []
    night: List[PostTime] = []

    def cleaned(self) -> dict:
        return {
            key: [t.dict() for t in getattr(self, key)]
            for key in SHIFT_KEYS
        }


class StationCreateRequest(BaseModel):
    name: str
    requiredMorning: int
    requiredAfternoon: int
    requiredNight: int
    posts: Optional[StationPosts] = None
    # Omit to let the stagger ladder time every slot for you.
    postTimes: Optional[StationPostTimes] = None


class StationUpdateRequest(BaseModel):
    # Renaming stays supported by the API (it also re-points employees,
    # schedules and pins at the new name) even though Edit Station no
    # longer exposes the field.
    name: Optional[str] = None
    requiredMorning: Optional[int] = None
    requiredAfternoon: Optional[int] = None
    requiredNight: Optional[int] = None
    posts: Optional[StationPosts] = None
    postTimes: Optional[StationPostTimes] = None
