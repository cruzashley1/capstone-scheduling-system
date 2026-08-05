"""
The data-access interface the rest of the backend talks to.

Today `api.py`, `scheduler.py` and the rest reach the database through
`db.collection("stations").stream()` — Firestore's own vocabulary. That
works for two backends because `mock_firestore.py` deliberately
impersonates Firestore, so both sides speak the same dialect.

Supabase does not. There is no `.collection()` and no `.stream()`; it is
PostgREST over SQL. So the switch can no longer live inside
`firebase_init.py` alone — the backend has to ask for what it WANTS
("every station") rather than for how Firestore happens to provide it.
That is what this interface is: the seam where the two dialects meet.

Rules for anything added here:

* Methods return plain dicts in the API's camelCase, never driver
  objects. A `DocumentSnapshot` leaking out would tie the caller back to
  Firestore and undo the point.
* Implementations must be behaviour-preserving, including ordering.
  Sorting "to be helpful" changes response order, which is part of the
  contract the golden files hold — see golden_capture.py.
* Absent records are returned as None, not raised. Every current caller
  checks `.exists` and decides its own status code.
"""

from abc import ABC, abstractmethod

# Every collection the backend reads. Doubles as the whitelist behind
# `repo.<name>`, so a typo raises AttributeError naming the collection
# instead of silently building a query against nothing.
COLLECTIONS = (
    "stations",
    "employees",
    "schedules",
    "attendance_reports",
    "special_assignments",
    "employee_notifications",
    "absence_requests",
    "special_requests",
    "cover_offers",
    "station_rotation_assignments",
    "rotation_cycles",
    "leave_requests",
    "replacements",
    "users",
    "counters",
)


class CollectionRepo(ABC):
    """Read access to one collection/table of documents."""

    @abstractmethod
    def list(self):
        """Every record, as a list of dicts.

        Order is whatever the backend returns, deliberately unsorted —
        callers that care already sort for themselves (scheduler sorts by
        id, station_pools.sort_stations imposes the group order).
        """

    @abstractmethod
    def get(self, doc_id):
        """One record as a dict, or None when it does not exist."""

    @abstractmethod
    def find(self, **filters):
        """Records where every named field equals the given value.

        Equality only, because equality is all this backend has ever
        used: all 34 `.where(...)` calls across api.py, scheduler.py,
        rotation.py, leave.py and replacements.py pass "==". Adding
        ranges or ordering before something needs them would be
        speculative, and every method here has to be implemented twice.

        Note the inherited Firestore behaviour, which the Supabase
        implementation has to reproduce: a document that LACKS the
        filtered field is excluded, rather than treated as null. See
        DEV_MODE.md — mock_firestore.py copies this too.
        """


class Repository(ABC):
    """The set of collections the backend can reach.

    Collections are reached as attributes — `repo.schedules`,
    `repo.employees` — which resolve through `collection()` below. That
    is done with __getattr__ rather than fifteen near-identical property
    declarations per implementation; the COLLECTIONS whitelist keeps a
    typo loud instead of silently returning something empty.
    """

    @abstractmethod
    def collection(self, name):
        """The CollectionRepo for `name`."""

    def __getattr__(self, name):
        if name in COLLECTIONS:
            return self.collection(name)
        raise AttributeError(
            f"{type(self).__name__} has no attribute {name!r}. "
            f"Known collections: {', '.join(COLLECTIONS)}")
