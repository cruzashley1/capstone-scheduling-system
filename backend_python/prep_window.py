"""
The preparation window — the hour a replacement gets before they stand
the post.

WHY THIS EXISTS. Assigning a cover used to hand the absent guard's duty
over unchanged: a 0500H - 1700H post stayed 0500H - 1700H, so a guard
told at 0900H that they were covering it was, on paper, already four
hours late for a duty they had not heard about. Nobody walks out of
their house and onto a post. There is a uniform to put on, food to
bring, and a commute to make.

So a cover that is assigned once the post is already running does not
inherit the post's hours. It gets its own:

    time-in   one hour from the moment the admin assigns it, which is
              the moment the guard is told. That hour is theirs to get
              ready and travel in, and they are expected to be AT the
              station when it runs out.

    time-out  the post's own time-out plus two hours — the hour of prep
              the duty lost at the front, and one hour of extension on
              top of it.

              0500H - 1700H, assigned at 0900H  ->  1000H - 1900H

WHEN IT DOES NOTHING. A cover assigned with time to spare keeps the
post's real hours. An absence approved two days out, or at 0300H for an
0500H post, does not need a preparation window — the guard already has
one. The rule is `max(the post's own time-in, an hour from now)`, so the
adjustment only appears when the notice is genuinely short.

WHAT IT IS NOT. It is not rounded, softened, or negotiable: exactly one
hour from the assignment, to the minute. An 0917H assignment produces a
1017H time-in and a schedule that says 1017H, because the guard's hour
is the thing being protected and a tidier number would come out of it.

THE DAY OFFSET. A duty window is stored as a bare "HH:MM" pair, with an
end at or before the start meaning "times out tomorrow". That is enough
for every generated post, whose time-in is always on its own duty date —
but not for a cover assigned in the small hours of the morning against
an overnight post. An HG Night post (1700H - 0500H) covered at 0230H
times in at 0330H the NEXT day, and "03:30" alone would put it a full
24 hours early. `dayOffset` carries that: how many days after the duty
date the time-in falls, 0 for everything the generator writes.

This is the Python side. services/prep_window.dart mirrors it so the
admin can see the hours before committing to them; the two must agree,
and this file is the one that decides, because it runs at the instant
the assignment is made.
"""

from datetime import datetime, timedelta, timezone

import station_posts

# Philippine Standard Time, matching replacements.py and api.py. The
# preparation window is measured on the guards' own clock — an hour of
# commuting is an hour where they live, whatever timezone the server
# happens to run in.
_PHT = timezone(timedelta(hours=8))

MINUTES_PER_DAY = 24 * 60

# The hour handed to the guard: uniform, food, and the commute. Also the
# notice the notification quotes, so the two can never drift apart.
PREP_MINUTES = 60

# The extension on the far end, on top of the hour the duty lost at the
# front. Together these are the "+2h" the post's time-out moves by.
EXTENSION_MINUTES = 60


def _instant(date_iso, minutes):
    """The moment `minutes` into `date_iso`, on the guards' clock."""
    day = datetime.strptime(date_iso, "%Y-%m-%d")
    return datetime(day.year, day.month, day.day,
                    tzinfo=_PHT) + timedelta(minutes=minutes)


def _length(start, end):
    """Window length in minutes, reading end <= start as an overnight
    post — the same rule the stored "HH:MM" pair carries everywhere."""
    span = (end - start) % MINUTES_PER_DAY
    return span or MINUTES_PER_DAY


def _minutes_of(moment):
    return moment.hour * 60 + moment.minute


def military_range(time_in, time_out):
    """'05:00', '17:00' -> '0500H - 1700H'. Empty when either side is
    unreadable, so a caller can drop the phrase rather than print half of
    a window."""
    start = station_posts.parse_hhmm(time_in)
    end = station_posts.parse_hhmm(time_out)
    if start is None or end is None:
        return ""
    return (f"{station_posts.format_military(start)} - "
            f"{station_posts.format_military(end)}")


def adjust(date_iso, time_in, time_out, now=None):
    """The hours a replacement assigned RIGHT NOW would actually stand.

    `time_in`/`time_out` are the post's own window ("HH:MM"), as
    replacements.cover_window() reads it off the absent guard's schedule
    entry. `now` is the instant of the assignment, defaulting to the
    server clock.

    Returns::

        {
          "adjusted":       True once the preparation hour moved anything,
          "timeIn":         "10:00",   the hours to stamp on the entry
          "timeOut":        "19:00",
          "dayOffset":      0,         days after `date_iso` time-in falls
          "originalTimeIn": "05:00",   the post's own hours, kept so the
          "originalTimeOut":"17:00",   log can show what changed
          "startsAt":       ISO instant of the new time-in
          "endsAt":         ISO instant of the new time-out
          "prepMinutes":    60,
          "range":          "1000H - 1900H",
          "originalRange":  "0500H - 1700H",
        }

    None when there is nothing to reason about — an unreadable date, or a
    post with no hours on file anywhere. Callers treat that the way they
    treated it before this existed: leave the entry's times alone.
    """
    try:
        start = station_posts.parse_hhmm(time_in)
        end = station_posts.parse_hhmm(time_out)
        starts_at = _instant(date_iso, start) if start is not None else None
    except (ValueError, TypeError):
        return None
    if start is None or end is None or starts_at is None:
        return None

    ends_at = starts_at + timedelta(minutes=_length(start, end))

    original = {
        "originalTimeIn": station_posts.format_hhmm(start),
        "originalTimeOut": station_posts.format_hhmm(end),
        "originalRange": military_range(time_in, time_out),
        "prepMinutes": PREP_MINUTES,
    }

    now = (now or datetime.now(_PHT)).astimezone(_PHT)
    # Never less than a full hour: the stored window has no seconds, so a
    # 0917:30 assignment rounds its time-in UP to 1018H rather than
    # quietly shaving half a minute off the guard's hour.
    report_at = (now + timedelta(minutes=PREP_MINUTES)).replace(
        second=0, microsecond=0)
    if now.second or now.microsecond:
        report_at += timedelta(minutes=1)

    # There is already time to prepare — an absence approved days ahead,
    # or early enough in the morning. The post keeps its real hours.
    if report_at <= starts_at:
        return dict(original,
                    adjusted=False,
                    timeIn=original["originalTimeIn"],
                    timeOut=original["originalTimeOut"],
                    dayOffset=0,
                    startsAt=starts_at.isoformat(),
                    endsAt=ends_at.isoformat(),
                    range=original["originalRange"])

    new_end = ends_at + timedelta(
        minutes=PREP_MINUTES + EXTENSION_MINUTES)
    new_start_minutes = _minutes_of(report_at)
    new_end_minutes = _minutes_of(new_end)

    return dict(
        original,
        adjusted=True,
        timeIn=station_posts.format_hhmm(new_start_minutes),
        timeOut=station_posts.format_hhmm(new_end_minutes),
        dayOffset=(report_at.date() - starts_at.date()).days,
        startsAt=report_at.isoformat(),
        endsAt=new_end.isoformat(),
        range=f"{station_posts.format_military(new_start_minutes)} - "
              f"{station_posts.format_military(new_end_minutes)}",
    )
