"""
Smoke test for the server clock — the one place the backend asks what
time it is. Touches nothing and needs no database:

    python testing_server_clock.py

The problem it fixes: server_clock.now() was datetime.now(), the HOST's
local clock, and the host is a Render container running in UTC. Every
duty window in this system is written in the guards' local time — 0500H,
1700H, 2100H — so the server was policing a Philippine roster against a
clock eight hours behind it. A night head guard standing on post at
2100H was told their 1700H-0500H filing window was shut, because to the
server it was 1300H.

What is asserted:

    now()    is Manila's wall clock, whatever TZ the host is set to
    today()  rolls over at midnight in Manila, not midnight on the host
    a frozen SCHED_FREEZE_NOW is still handed back exactly as written,
             because the golden files depend on it
    now()    is still NAIVE — every caller compares it against a window
             built with datetime.combine(), and mixing naive with aware
             raises TypeError
"""

import os
import sys
import time as _time
from datetime import datetime, timedelta, timezone

import server_clock

PHT = timezone(timedelta(hours=8))
CHECKS = []


def check(label, ok, detail=""):
    CHECKS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f" — {detail}" if detail else ""))


def truth():
    """Manila's wall clock, worked out independently of the module."""
    return datetime.now(timezone.utc).astimezone(PHT).replace(tzinfo=None)


def main():
    os.environ.pop(server_clock.ENV_VAR, None)

    print("The running clock:")
    reading = server_clock.now()
    drift = abs((reading - truth()).total_seconds())
    check("now() reads Manila's wall clock", drift < 2,
          f"{reading} (off by {drift:.1f}s)")
    check("...and is naive, so it compares against datetime.combine()",
          reading.tzinfo is None)
    check("today() is Manila's calendar date",
          server_clock.today() == truth().date(),
          str(server_clock.today()))

    # The bug in one assertion: pretend the container is in UTC, the way
    # Render's is, and the reading must not move.
    print("\nWith the host forced to UTC (what Render actually runs):")
    had_tz = "TZ" in os.environ
    old_tz = os.environ.get("TZ")
    try:
        os.environ["TZ"] = "UTC"
        if hasattr(_time, "tzset"):
            _time.tzset()
        else:
            print("  NOTE  no time.tzset() on this platform (Windows) — the "
                  "host clock can't be moved from here, so the check below "
                  "proves the conversion rather than the immunity.")
        under_utc = server_clock.now()
        check("now() is unchanged — still Manila, not the host's zone",
              abs((under_utc - truth()).total_seconds()) < 2,
              f"{under_utc}")
        check("...and eight hours ahead of the host's own UTC reading",
              abs((under_utc - datetime.now(timezone.utc).replace(tzinfo=None))
                  .total_seconds() - 8 * 3600) < 2)
    finally:
        if had_tz:
            os.environ["TZ"] = old_tz
        else:
            os.environ.pop("TZ", None)
        if hasattr(_time, "tzset"):
            _time.tzset()

    print("\nFrozen, the way golden_capture.py runs it:")
    os.environ[server_clock.ENV_VAR] = "2026-08-10T09:00:00"
    try:
        check("now() is the pinned moment, untouched",
              server_clock.now() == datetime(2026, 8, 10, 9, 0, 0),
              str(server_clock.now()))
        check("today() is the pinned date",
              server_clock.today().isoformat() == "2026-08-10")
        os.environ[server_clock.ENV_VAR] = "not a datetime"
        try:
            server_clock.now()
            check("a malformed freeze raises rather than shrugging", False)
        except RuntimeError as exc:
            check("a malformed freeze raises rather than shrugging",
                  server_clock.ENV_VAR in str(exc))
    finally:
        os.environ.pop(server_clock.ENV_VAR, None)

    print("\nThe window that started this — HG Night, 1700H - 0500H:")
    # The exact comparison api.py's _assert_inside_duty_window makes.
    day = datetime(2026, 8, 11).date()
    start = datetime.combine(day, datetime.min.time()).replace(hour=17)
    end = start + timedelta(hours=12)
    on_post = datetime(2026, 8, 11, 21, 0)  # 2100H in Manila
    check("a head guard on post at 2100H is inside it",
          start <= on_post <= end)
    check("...and the naive server reading can be compared to it at all",
          isinstance(server_clock.now() - start, timedelta))

    passed = sum(1 for c in CHECKS if c)
    print(f"\n{passed}/{len(CHECKS)} checks passed")
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    sys.exit(main())
