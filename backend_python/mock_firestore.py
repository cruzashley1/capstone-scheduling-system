"""
Offline, file-backed stand-in for the Firestore client.

Development mode swaps this in for the real client so testing and debugging
cost zero Firestore reads (the free tier allows 50k/day, and a single
`collection("employees").stream()` burns one read per employee).

Data lives in mock_data/<collection>.json as {doc_id: {...fields}}. Writes are
mirrored back to disk immediately, so anything created through the API survives
a restart.

This implements the subset of the Firestore API the backend actually uses:
documents, ==-style queries, batches and transactions. Behaviour deliberately
mirrors the real client (including raising on update() of a missing document)
so bugs surface here rather than in production.
"""

import copy
import json
import os
import threading
from contextlib import contextmanager

import atomic_write

DEFAULT_DATA_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "mock_data"
)


# --- Storage ---------------------------------------------------------------

class _Store:
    """Holds every collection in memory and mirrors writes back to disk."""

    def __init__(self, data_dir):
        self.data_dir = data_dir
        self._lock = threading.RLock()
        self._collections = {}
        self._defer_depth = 0
        self._pending = set()
        self._load()

    def _path(self, name):
        return os.path.join(self.data_dir, f"{name}.json")

    def _load(self):
        os.makedirs(self.data_dir, exist_ok=True)
        for entry in sorted(os.listdir(self.data_dir)):
            if not entry.endswith(".json"):
                continue
            name = entry[: -len(".json")]
            with open(self._path(name), "r", encoding="utf-8") as fh:
                self._collections[name] = json.load(fh)

    def documents(self, name):
        with self._lock:
            return self._collections.setdefault(name, {})

    def flush(self, name):
        """Writes a collection out atomically, so a crash mid-write can't
        leave a truncated JSON file behind.

        Inside a batch or a transaction the write is deferred to the end of
        the commit. A batch applies its buffered writes one document at a
        time, and every one of those used to rewrite the whole collection
        file: saving a rotation placement rewrote a 300KB file once per
        guard in the group, a few hundred times over. That is slow, and on
        Windows it hands an antivirus scanner a few hundred chances to be
        holding the file open at the exact moment of the rename."""
        with self._lock:
            if self._defer_depth:
                self._pending.add(name)
                return
            self._write(name)

    def _write(self, name):
        atomic_write.write_json(self._path(name),
                                self._collections.setdefault(name, {}))

    @contextmanager
    def deferred_flush(self):
        """Collapses every flush inside the block into one write per
        collection, done when the outermost block exits."""
        with self._lock:
            self._defer_depth += 1
            try:
                yield
            finally:
                self._defer_depth -= 1
                if not self._defer_depth:
                    pending, self._pending = self._pending, set()
                    # Written even when the block failed part-way: the
                    # in-memory collections already carry those writes, so
                    # skipping them would leave disk behind memory.
                    for name in sorted(pending):
                        self._write(name)

    @property
    def lock(self):
        return self._lock


# --- Field paths -----------------------------------------------------------

def _read_field(data, path):
    """Resolves a dotted field path ("a.b") the way Firestore does."""
    current = data
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            raise KeyError(path)
        current = current[part]
    return current


def _write_field(data, path, value):
    parts = path.split(".")
    current = data
    for part in parts[:-1]:
        nxt = current.get(part)
        if not isinstance(nxt, dict):
            nxt = {}
            current[part] = nxt
        current = nxt
    current[parts[-1]] = value


# --- Snapshots -------------------------------------------------------------

class MockDocumentSnapshot:
    def __init__(self, reference, data):
        self.reference = reference
        self.id = reference.id
        self._data = data

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return copy.deepcopy(self._data) if self._data is not None else None

    def get(self, field_path):
        """Matches the real client: raises KeyError when the field is absent."""
        if self._data is None:
            raise KeyError(field_path)
        return copy.deepcopy(_read_field(self._data, field_path))


# --- Documents -------------------------------------------------------------

class MockDocumentReference:
    def __init__(self, store, collection_id, document_id):
        self._store = store
        self.collection_id = collection_id
        self.id = document_id

    @property
    def path(self):
        return f"{self.collection_id}/{self.id}"

    def _raw(self):
        return self._store.documents(self.collection_id).get(self.id)

    def get(self, transaction=None):
        # Reads inside a transaction see that transaction's pending writes,
        # mirroring read-your-own-writes in the real client.
        if transaction is not None:
            pending = transaction.pending_state(self)
            if pending is not _NO_PENDING:
                return MockDocumentSnapshot(self, pending)
        return MockDocumentSnapshot(self, copy.deepcopy(self._raw()))

    def set(self, data, merge=False):
        with self._store.lock:
            docs = self._store.documents(self.collection_id)
            if merge and self.id in docs:
                merged = copy.deepcopy(docs[self.id])
                for path, value in data.items():
                    _write_field(merged, path, copy.deepcopy(value))
                docs[self.id] = merged
            else:
                docs[self.id] = copy.deepcopy(data)
            self._store.flush(self.collection_id)

    def update(self, updates):
        with self._store.lock:
            docs = self._store.documents(self.collection_id)
            if self.id not in docs:
                raise KeyError(
                    f"No document to update: {self.path}"
                )
            current = docs[self.id]
            for path, value in updates.items():
                _write_field(current, path, copy.deepcopy(value))
            self._store.flush(self.collection_id)

    def delete(self):
        with self._store.lock:
            docs = self._store.documents(self.collection_id)
            docs.pop(self.id, None)
            self._store.flush(self.collection_id)

    def __eq__(self, other):
        return (isinstance(other, MockDocumentReference)
                and other.path == self.path)

    def __hash__(self):
        return hash(self.path)


# --- Queries ---------------------------------------------------------------

def _matches(value, op, target):
    try:
        if op == "==":
            return value == target
        if op == "!=":
            return value != target
        if op == "<":
            return value < target
        if op == "<=":
            return value <= target
        if op == ">":
            return value > target
        if op == ">=":
            return value >= target
        if op == "in":
            return value in target
        if op == "not-in":
            return value not in target
        if op == "array_contains":
            return isinstance(value, list) and target in value
        if op == "array_contains_any":
            return isinstance(value, list) and any(v in value for v in target)
    except TypeError:
        # Mismatched types never match in Firestore rather than erroring.
        return False
    raise NotImplementedError(f"Unsupported query operator: {op}")


class MockQuery:
    def __init__(self, store, collection_id, filters=None):
        self._store = store
        self.collection_id = collection_id
        self._filters = list(filters or [])

    def where(self, field, op, value):
        return MockQuery(self._store, self.collection_id,
                         self._filters + [(field, op, value)])

    def stream(self):
        with self._store.lock:
            items = list(self._store.documents(self.collection_id).items())
        for doc_id, data in items:
            keep = True
            for field, op, target in self._filters:
                try:
                    actual = _read_field(data, field)
                except KeyError:
                    # Firestore excludes documents missing the filtered field.
                    keep = False
                    break
                if not _matches(actual, op, target):
                    keep = False
                    break
            if keep:
                ref = MockDocumentReference(self._store, self.collection_id, doc_id)
                yield MockDocumentSnapshot(ref, copy.deepcopy(data))

    def get(self):
        return list(self.stream())


class MockCollectionReference(MockQuery):
    def document(self, document_id):
        return MockDocumentReference(self._store, self.collection_id, document_id)


# --- Batches ---------------------------------------------------------------

class MockWriteBatch:
    """Buffers writes and applies them on commit, like the real batch."""

    def __init__(self, store):
        self._store = store
        self._ops = []

    def set(self, reference, data, merge=False):
        self._ops.append(("set", reference, copy.deepcopy(data), merge))

    def update(self, reference, updates):
        self._ops.append(("update", reference, copy.deepcopy(updates), None))

    def delete(self, reference):
        self._ops.append(("delete", reference, None, None))

    def commit(self):
        with self._store.deferred_flush():
            for op, reference, payload, merge in self._ops:
                if op == "set":
                    reference.set(payload, merge=merge)
                elif op == "update":
                    reference.update(payload)
                else:
                    reference.delete()
        self._ops = []


# --- Transactions ----------------------------------------------------------

_NO_PENDING = object()


class MockTransaction:
    """Buffers writes until commit and lets reads see its own pending writes."""

    def __init__(self, store):
        self._store = store
        self._ops = []
        self._pending = {}

    def pending_state(self, reference):
        return self._pending.get(reference.path, _NO_PENDING)

    def set(self, reference, data, merge=False):
        self._ops.append(("set", reference, copy.deepcopy(data), merge))
        if merge and self._pending.get(reference.path):
            merged = copy.deepcopy(self._pending[reference.path])
            for path, value in data.items():
                _write_field(merged, path, copy.deepcopy(value))
            self._pending[reference.path] = merged
        else:
            self._pending[reference.path] = copy.deepcopy(data)

    def update(self, reference, updates):
        self._ops.append(("update", reference, copy.deepcopy(updates), None))
        base = self._pending.get(reference.path)
        if base is _NO_PENDING or base is None:
            snapshot = reference.get()
            base = snapshot.to_dict() or {}
        else:
            base = copy.deepcopy(base)
        for path, value in updates.items():
            _write_field(base, path, copy.deepcopy(value))
        self._pending[reference.path] = base

    def delete(self, reference):
        self._ops.append(("delete", reference, None, None))
        self._pending[reference.path] = None

    def _commit(self):
        with self._store.deferred_flush():
            for op, reference, payload, merge in self._ops:
                if op == "set":
                    reference.set(payload, merge=merge)
                elif op == "update":
                    reference.update(payload)
                else:
                    reference.delete()
        self._ops = []
        self._pending = {}

    def _rollback(self):
        self._ops = []
        self._pending = {}


# --- Client ----------------------------------------------------------------

class MockFirestoreClient:
    def __init__(self, data_dir=None):
        self._store = _Store(data_dir or DEFAULT_DATA_DIR)

    def collection(self, name):
        return MockCollectionReference(self._store, name)

    def batch(self):
        return MockWriteBatch(self._store)

    def transaction(self):
        return MockTransaction(self._store)


def transactional(func):
    """Stand-in for firestore.transactional.

    The single-process mock has no contention, so there is nothing to retry:
    run the body once and commit, rolling back if it raises.
    """
    def wrapper(transaction, *args, **kwargs):
        try:
            result = func(transaction, *args, **kwargs)
        except Exception:
            transaction._rollback()
            raise
        transaction._commit()
        return result

    return wrapper
