"""
Repository over a Firestore-shaped client.

One implementation covers BOTH current backends — real Firestore and the
offline `mock_firestore.MockFirestoreClient` — because the mock was
written to impersonate Firestore's API. Whichever `firebase_init.get_db()
returns, the calls below are the same.

This class is intentionally a thin translation and nothing more. It holds
no logic of its own, so landing it cannot change any response: that is
what makes it safe to introduce before Supabase exists, and what lets the
golden files prove the refactor was inert.
"""

from repositories.base import CollectionRepo, Repository


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


class DocumentRepository(Repository):
    def __init__(self, db):
        if db is None:
            raise ValueError("DocumentRepository needs a database handle")
        self._db = db
        self._stations = DocumentCollectionRepo(db, "stations")
        self._employees = DocumentCollectionRepo(db, "employees")

    @property
    def stations(self):
        return self._stations

    @property
    def employees(self):
        return self._employees

    @property
    def db(self):
        """The raw handle, for the call sites not yet migrated.

        Everything still using `db.collection(...)` keeps working while
        the migration proceeds collection by collection. This goes away
        when the last one moves across.
        """
        return self._db
