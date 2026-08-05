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

    # --- writes -------------------------------------------------------
    #
    # The guiding rule for everything below: name the INTENT, not the
    # mechanism. Firestore has batches and document references; Postgres
    # has transactions and no references at all. An interface shaped like
    # `batch()` and `doc.reference` would force Supabase to imitate
    # Firestore's machinery and undo the point of this layer.
    #
    # Said at the right altitude, the awkward cases collapse. The station
    # rename fans a query out into a batch of per-document updates today:
    #
    #     for doc in db.collection("employees")
    #                  .where("assignedStation", "==", old).stream():
    #         batch.update(doc.reference, {"assignedStation": new})
    #
    # As intent that is one call — `update_where({...}, {...})` — which
    # Firestore implements as query-then-batch and Postgres implements as
    # a single UPDATE ... WHERE.
    #
    # Added as call sites need them, not before; each one costs two
    # implementations. Still planned: delete_where(), for the station
    # delete's fan-out across schedules and pins.

    @abstractmethod
    def upsert(self, doc_id, data, merge=False):
        """Writes `data` at `doc_id`, creating the record if absent.

        Mirrors Firestore's .set(): by default it REPLACES the record, so
        fields missing from `data` are dropped. `merge=True` keeps them
        and writes only the given fields — which is what saving a
        rotation cycle wants, since it rewrites three fields of a record
        that may carry others.

        Both halves are meaningful in Postgres too:
        INSERT ... ON CONFLICT (id) DO UPDATE SET, over every column or
        only the given ones.
        """

    @abstractmethod
    def upsert_many(self, records):
        """Upserts many records at once, given {doc_id: data}.

        The bulk notification writes go through here — publishing a
        schedule can notify a few hundred guards. Firestore needs those
        chunked under its 500-write batch cap; Postgres does one
        multi-row INSERT ... ON CONFLICT. Callers should not have to know
        which, or what the cap is, so the chunking lives in the
        implementation.
        """

    @abstractmethod
    def update(self, doc_id, fields):
        """Merges `fields` into the record at `doc_id`.

        Partial, unlike upsert: untouched fields survive. Mirrors
        Firestore's .update(), which RAISES when the document is absent
        rather than creating it — callers rely on that, so the Supabase
        implementation must not silently turn a missing row into an
        insert.
        """

    @abstractmethod
    def delete(self, doc_id):
        """Removes the record at `doc_id`.

        Deleting something already absent is not an error, matching
        Firestore's .delete() — the withdraw-offer path relies on being
        safe to retry.
        """

    @abstractmethod
    def delete_many(self, doc_ids):
        """Removes every listed record. Returns how many were asked for.

        Explicitly NOT a transaction, and not `delete_where({})` either.
        The bulk schedule delete this exists for already accepted being
        non-atomic — it chunked by hand and said so — because clearing
        every schedule can exceed any batch limit and there is nothing to
        keep consistent with. Taking ids rather than a filter keeps
        "delete everything" from being one forgotten argument away.
        """

    @abstractmethod
    def update_where(self, filters, fields):
        """Merges `fields` into every record matching `filters`.

        Returns how many were updated, which the mark-all-read endpoints
        report back to the app.

        This is the method that keeps `doc.reference` off the interface.
        Firestore implements it as query-then-batch, and the readable
        version of the same thing in Postgres is a single statement:

            UPDATE <table> SET ... WHERE ...

        The station rename will use this too, once employees move.
        """


class _CollectionAccess(ABC):
    """Reaches collections as attributes — `x.schedules`, `x.employees` —
    resolving through `collection()`.

    __getattr__ rather than fifteen near-identical property declarations
    per implementation; the COLLECTIONS whitelist keeps a typo loud
    instead of silently returning something empty. Shared by Repository
    and Transaction so both read the same at the call site.
    """

    @abstractmethod
    def collection(self, name):
        """The per-collection accessor for `name`."""

    def __getattr__(self, name):
        if name in COLLECTIONS:
            return self.collection(name)
        raise AttributeError(
            f"{type(self).__name__} has no attribute {name!r}. "
            f"Known collections: {', '.join(COLLECTIONS)}")


class TransactionCollection(ABC):
    """The writes available inside a transaction, for one collection.

    Same names and meanings as CollectionRepo's writes; the difference is
    that nothing lands until the transaction commits. There are no reads
    here — every current caller reads what it needs first and then
    writes, and Firestore's batches are write-only anyway.
    """

    @abstractmethod
    def upsert(self, doc_id, data, merge=False):
        """Queues a record write. `merge` as on CollectionRepo.upsert."""

    @abstractmethod
    def update(self, doc_id, fields):
        """Queues a partial merge."""

    @abstractmethod
    def delete(self, doc_id):
        """Queues a removal."""

    @abstractmethod
    def update_where(self, filters, fields):
        """Queues a merge into every matching record. Returns the count.

        The matching happens NOW — the query runs immediately and only
        the writes wait for the commit. That is how Firestore works
        (batches cannot read), and it matches what the call sites did by
        hand: query first, then batch the updates.
        """

    @abstractmethod
    def delete_where(self, filters):
        """Queues a removal of every matching record. Returns the count."""


class Transaction(_CollectionAccess):
    """Writes across collections that land together or not at all.

    The reason this exists: five call sites open a Firestore batch, write
    to two or three collections, and commit once. Renaming a station
    touches schedules, employees and pins; deleting one removes the
    station, its schedules and its pins. Half of either is a broken
    database — an employee whose assignedStation names a station that no
    longer exists drops out of the next generated schedule entirely.

    Used as a context manager, committing only on a clean exit:

        with repo.transaction() as tx:
            tx.schedules.update_where({"stationId": sid}, {...})
            tx.employees.update_where({"assignedStation": old}, {...})

    Raising inside the block writes nothing at all.

    Firestore implements this as a batch, Postgres as BEGIN/COMMIT.
    Firestore caps a batch at 500 writes, so implementations must refuse
    an oversized transaction loudly rather than silently splitting it —
    a split transaction is the exact thing this class exists to prevent.
    """


class Repository(_CollectionAccess):
    """The set of collections the backend can reach."""

    @abstractmethod
    def transaction(self):
        """A context manager yielding a Transaction."""

    @abstractmethod
    def next_sequence(self, counter_name):
        """Atomically increments a counter and returns its new value.

        The clearest example of naming intent over mechanism. Today this
        is a Firestore transaction that reads the counter, adds one and
        writes it back — three steps that must not interleave with
        another caller, or two employees get the same username.

        Exposing "transaction" would push that dance onto every backend.
        Postgres does the whole thing in one statement:

            INSERT INTO counters (id, value) VALUES (%s, 1)
            ON CONFLICT (id) DO UPDATE SET value = counters.value + 1
            RETURNING value

        so the interface asks for the next number and lets each backend
        reach it however it can.
        """
