"""
Repository over a Firestore-shaped client.

One implementation covers BOTH current backends — real Firestore and the
offline `mock_firestore.MockFirestoreClient` — because the mock was
written to impersonate Firestore's API. Whichever `firebase_init.get_db()`
returns, the calls below are the same.

This class is intentionally a thin translation and nothing more. It holds
no logic of its own, so landing it cannot change any response: that is
what makes it safe to introduce before Supabase exists, and what lets the
golden files prove the refactor was inert.
"""

from contextlib import contextmanager

import firebase_init
from repositories.base import (COLLECTIONS, CollectionRepo, Repository,
                               Transaction, TransactionCollection)


class DocumentCollectionRepo(CollectionRepo):
    def __init__(self, db, name):
        self._db = db
        self._name = name

    def list(self):
        # Left unsorted on purpose. Firestore's stream() order is
        # unspecified and the mock returns JSON insertion order; imposing
        # an order here would change /stations' response order, which the
        # golden files would (correctly) flag as a contract change.
        return [doc.to_dict() for doc in self._db.collection(self._name).stream()]

    def get(self, doc_id):
        snapshot = self._db.collection(self._name).document(doc_id).get()
        if not snapshot.exists:
            return None
        return snapshot.to_dict()

    def find(self, **filters):
        query = self._db.collection(self._name)
        for field, value in filters.items():
            query = query.where(field, "==", value)
        return [doc.to_dict() for doc in query.stream()]

    def upsert(self, doc_id, data):
        self._db.collection(self._name).document(doc_id).set(data)

    # Firestore rejects a batch of more than 500 writes. 400 leaves room
    # and matches the chunk size the notification writes already used.
    _BATCH_LIMIT = 400

    def upsert_many(self, records):
        collection = self._db.collection(self._name)
        items = list(records.items())
        for start in range(0, len(items), self._BATCH_LIMIT):
            batch = self._db.batch()
            for doc_id, data in items[start:start + self._BATCH_LIMIT]:
                batch.set(collection.document(doc_id), data)
            batch.commit()

    def update(self, doc_id, fields):
        self._db.collection(self._name).document(doc_id).update(fields)

    def delete(self, doc_id):
        self._db.collection(self._name).document(doc_id).delete()

    def update_where(self, filters, fields):
        query = self._db.collection(self._name)
        for field, value in filters.items():
            query = query.where(field, "==", value)
        docs = list(query.stream())
        for start in range(0, len(docs), self._BATCH_LIMIT):
            batch = self._db.batch()
            for doc in docs[start:start + self._BATCH_LIMIT]:
                batch.update(doc.reference, fields)
            batch.commit()
        return len(docs)


class DocumentTransactionCollection(TransactionCollection):
    """Queues writes onto the shared batch instead of committing them."""

    def __init__(self, transaction, db, name):
        self._tx = transaction
        self._db = db
        self._name = name

    def _collection(self):
        return self._db.collection(self._name)

    def upsert(self, doc_id, data):
        self._tx._queue().set(self._collection().document(doc_id), data)

    def update(self, doc_id, fields):
        self._tx._queue().update(self._collection().document(doc_id), fields)

    def delete(self, doc_id):
        self._tx._queue().delete(self._collection().document(doc_id))

    def _matching(self, filters):
        query = self._collection()
        for field, value in filters.items():
            query = query.where(field, "==", value)
        return list(query.stream())

    def update_where(self, filters, fields):
        docs = self._matching(filters)
        for doc in docs:
            self._tx._queue().update(doc.reference, fields)
        return len(docs)

    def delete_where(self, filters):
        docs = self._matching(filters)
        for doc in docs:
            self._tx._queue().delete(doc.reference)
        return len(docs)


class DocumentTransaction(Transaction):
    """One Firestore batch, committed only if the block finishes cleanly."""

    # Firestore's hard cap. Enforced here rather than left to fail at
    # commit so the error names the real problem, and so the mock — which
    # has no cap — refuses the same transactions the real backend would.
    MAX_WRITES = 500

    def __init__(self, db):
        self._db = db
        self._batch = db.batch()
        self._writes = 0
        self._collections = {}

    def _queue(self):
        """The batch, after counting one more write against the cap."""
        self._writes += 1
        if self._writes > self.MAX_WRITES:
            raise ValueError(
                f"transaction exceeds {self.MAX_WRITES} writes, which is "
                f"Firestore's per-batch limit. Splitting it would give up "
                f"the all-or-nothing guarantee this transaction exists "
                f"for, so it is refused instead.")
        return self._batch

    def collection(self, name):
        if name not in COLLECTIONS:
            raise KeyError(f"unknown collection {name!r}")
        if name not in self._collections:
            self._collections[name] = DocumentTransactionCollection(
                self, self._db, name)
        return self._collections[name]

    def _commit(self):
        # Committing an empty batch is a wasted round trip; a rename that
        # touched nothing should not talk to Firestore at all.
        if self._writes:
            self._batch.commit()


class DocumentRepository(Repository):
    def __init__(self, db):
        if db is None:
            raise ValueError("DocumentRepository needs a database handle")
        self._db = db
        self._repos = {}

    def collection(self, name):
        if name not in COLLECTIONS:
            raise KeyError(f"unknown collection {name!r}")
        if name not in self._repos:
            self._repos[name] = DocumentCollectionRepo(self._db, name)
        return self._repos[name]

    @contextmanager
    def transaction(self):
        """Yields a Transaction, committing it only on a clean exit.

        An exception propagates with nothing written: the batch is never
        committed, so Firestore never sees a partial fan-out.
        """
        tx = DocumentTransaction(self._db)
        yield tx
        tx._commit()

    def next_sequence(self, counter_name):
        """The Firestore transaction this replaces at the call sites.

        Unchanged in behaviour from the two copies that lived in api.py:
        read the counter inside a transaction, add one, write it back.
        Starting from 0 when the document is absent means the first value
        handed out is 1, which is what the existing counters assume.
        """
        counter_ref = (self._db.collection("counters").document(counter_name))
        transactional = firebase_init.transactional

        @transactional
        def _increment(transaction):
            snapshot = counter_ref.get(transaction=transaction)
            current = snapshot.get("value") if snapshot.exists else 0
            next_value = current + 1
            transaction.set(counter_ref, {"value": next_value})
            return next_value

        return _increment(self._db.transaction())

    @property
    def db(self):
        """The raw handle, for the call sites not yet migrated.

        Writes still go through `db.collection(...)`: they need batches,
        transactions and `doc.reference`, which this interface does not
        expose yet. This goes away when the write vocabulary lands.
        """
        return self._db
