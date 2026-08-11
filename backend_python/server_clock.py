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
`datetime.now()` and `date.today()` with one extra function call.

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
from datetime import date, datetime

ENV_VAR = "SCHED_FREEZE_NOW"


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
    """Local wall-clock time — what `datetime.now()` returned before."""
    return frozen_at() or datetime.now()


def today():
    """Local calendar date — what `date.today()` returned before."""
    pinned = frozen_at()
    return pinned.date() if pinned else date.today()
