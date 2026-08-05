"""Structured notes the generator files against a run.

WHAT THESE ARE

Generation never fails on a staffing problem — it produces the best
roster the setup allows and files a note about anything it had to bend.
These notes are the only place those compromises are recorded: a post
nobody was assigned to, a station with no head guard, a day off no
reliever was free for. Ignore them and the schedule still publishes,
with the hole in it.

WHY THEY ARE STRUCTURED

They used to be a flat list of paragraph-long strings, all shown under
one "Station Rotation" heading whatever they were actually about. Each
note now carries the three things the admin reads for:

    subject   what it concerns  — "Ayala — Morning", or a guard's name
    problem   what happened     — one sentence, past tense
    fix       what to do        — one sentence, imperative; "" when
                                  nothing is owed (an FYI note)

plus a `category` (which heading it belongs under) and a `severity`
(how loudly to say it). `text` is the three joined back into the old
one-line form, so anything still reading the flat `rotationNotes` list —
saved schedules, the test scripts — keeps working unchanged.

CATEGORIES map one-to-one onto the sections the admin sees, and every
one of them corresponds to a different place the fix lives.
"""

# Heading a note is filed under. The value is the key; the UI owns the
# display title so it can be worded for the screen it appears on.
CATEGORY_ROTATION = "rotation"      # what the monthly rotation engine did
CATEGORY_STAFFING = "staffing"      # station number vs guards assigned
CATEGORY_HEAD_GUARD = "headGuard"   # the Head Guard post
CATEGORY_COVER = "cover"            # relievers standing in on day-offs
CATEGORY_ASSIGNMENT = "assignment"  # admin pins (Special Assignments)
CATEGORY_LEAVE = "leave"            # approved / pending leave
CATEGORY_REQUEST = "request"        # special day-off requests

# How loudly to say it.
#   INFO     nothing is wrong; this is what the generator decided.
#   WARNING  the roster generated, but a post or a person isn't right.
#   BLOCKER  somebody is missing from the roster altogether — the
#            schedule is wrong until this is fixed and it is regenerated.
SEVERITY_INFO = "info"
SEVERITY_WARNING = "warning"
SEVERITY_BLOCKER = "blocker"

_SEVERITY_RANK = {SEVERITY_BLOCKER: 0, SEVERITY_WARNING: 1, SEVERITY_INFO: 2}


def note(category, severity, subject, problem, fix="", station=None):
    """One note. `station` is the station name when the note is about a
    specific one, so the UI can link straight to it."""
    return {
        "category": category,
        "severity": severity,
        "subject": subject,
        "problem": problem,
        "fix": fix,
        "station": station,
        "text": _flatten(subject, problem, fix),
    }


def texts(notes):
    """The flat one-line form, for readers that predate the structure."""
    return [n["text"] for n in notes]


def worst_severity(notes):
    """The loudest severity present, or None for an empty list."""
    if not notes:
        return None
    return min((n["severity"] for n in notes), key=_severity_rank)


def _severity_rank(severity):
    return _SEVERITY_RANK.get(severity, len(_SEVERITY_RANK))


def _flatten(subject, problem, fix):
    line = f"{subject}: {problem}" if subject else problem
    return f"{line} {fix}".rstrip() if fix else line
