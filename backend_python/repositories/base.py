"""
The data-access interface the rest of the backend talks to.

Today `api.py`, `scheduler.py` and `leave.py` reach the database through
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


class Repository(ABC):
    """The set of collections the backend can reach.

    Grows one attribute at a time as each collection is migrated. Only
    `stations` is defined so far; the rest of the backend still goes
    through `db.collection(...)` directly and is unaffected.
    """

    @property
    @abstractmethod
    def stations(self):
        """CollectionRepo for stations."""

    @property
    @abstractmethod
    def employees(self):
        """CollectionRepo for employees."""
