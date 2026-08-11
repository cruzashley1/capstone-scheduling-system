"""
The one place the server asks what time it is.

WHY THIS EXISTS

Several read endpoints answer relative to "today": the leave window's
bounds, the special-request window, a station overview's roster, the
default date for cover offers. Their responses are correct and different
every morning, which is fine for the app and fatal for the golden files —
`golden_capture.py compare` recorded them on one date and re-runs them on
another, so it reports differences the calendar caused and the code did
not.

A net that fails every day for reasons nobody can act on stops being
read, and then it is not a net. Freezing the clock for the duration of a
capture and a comparison makes those endpoints deterministic without
masking their contents, which is the alternative and a much worse one:
masking a station overview would blank all 46 of its fields and leave the
file asserting nothing.

    SCHED_FREEZE_NOW=2026-08-10T09:00:00   # capture and compare both

Unset — which is every deployment and every ordinary dev run — these are
the Philippine wall clock (see below) with one extra function call.

WHICH WALL CLOCK

Philippine time, always — never the host's.

Every duty window in this system is written in the guards' local time:
0500H, 1700H, 2100H. `datetime.now()` returns the HOST's local time, and
the host is a Render container, which runs in UTC. That put the server
eight hours behind the roster it was policing: at 2100H in Manila the
server believed it was 1300H, so a night head guard standing on post was
told their 1700H-0500H filing window was closed, the leave and
special-request windows opened and shut on the wrong day, and "today's"
roster rolled over at 0800H local.

Doing this here rather than with a TZ environment variable on the host
keeps the rule in the repository, where it survives a redeploy onto a new
service and is the same on a developer's laptop as in production.

WHAT IS AND IS NOT FROZEN

Only the naive local clock: `now()` and `today()`, the two that decide
what a response SAYS. Write timestamps stay on `datetime.now(timezone.utc)`
at their call sites, deliberately. They record when something actually
happened, a frozen one would be a lie in stored data rather than a
convenience in a test, and they never reach a golden file — the ones that
do already differ between two calls in the same run and are masked as
volatile.

A MALFORMED VALUE IS AN ERROR, NOT A SHRUG

If SCHED_FREEZE_NOW is set but unreadable this raises. Ignoring it would
mean a capture silently running on the real clock and a comparison
silently failing against it, which is precisely the confusion this module
was written to end.
"""

import os
from datetime import datetime, timedelta, timezone

ENV_VAR = "SCHED_FREEZE_NOW"

# Philippine Standard Time. Fixed +8 with no DST since 1978, so a plain
# offset is exact and needs no tzdata installed in the container. Matches
# _PHT in api.py, prep_window.py and replacements.py.
PHT = timezone(timedelta(hours=8))


def frozen_at():
    """The pinned moment, or None when the clock is running.

    Read per call rather than cached at import, so a test can freeze and
    unfreeze around a block without reloading the module.
    """
    raw = os.getenv(ENV_VAR, "").strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        raise RuntimeError(
            f"{ENV_VAR}={raw!r} is not an ISO datetime. Use e.g. "
            f"2026-08-10T09:00:00. Unset it to run on the real clock."
        ) from None


def now():
    """The Philippine wall clock, as a NAIVE datetime.

    Naive on purpose: every caller compares it against a window built with
    `datetime.combine(some_date, time(17, 0))`, which is naive too, and
    mixing the two raises. The tzinfo is stripped after the conversion, so
    the reading is Manila's even though the value carries no zone.

    A frozen value is returned exactly as written — a test that pins
    2026-08-10T09:00:00 means 0900H in Manila, not 0900H somewhere else.
    """
    pinned = frozen_at()
    if pinned is not None:
        return pinned
    return datetime.now(PHT).replace(tzinfo=None)


def today():
    """The Philippine calendar date. Rolls over at midnight in Manila, not
    at midnight wherever the container happens to be running."""
    return now().date()
