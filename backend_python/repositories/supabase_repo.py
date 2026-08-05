"""
Repository over Supabase. Not implemented yet — this is the shape the
migration fills in, kept beside the working implementation so the
interface has a second reader from the start.

Three things every method here will have to honour:

1. **camelCase out.** Columns are snake_case (`assigned_station`),
   because Postgres folds unquoted identifiers to lowercase and
   `assignedStation` would silently become `assignedstation`, arriving in
   Flutter as null. Convert at this boundary with `to_camel()`; a column
   name must never reach a response.

2. **Order is part of the contract.** Postgres does not promise row order
   without an ORDER BY, so `list()` and `find()` must pin one explicitly
   to stay byte-identical to what the golden files recorded. Whatever
   order the document backend produces is the target.

3. **Missing fields are excluded, not null.** Firestore drops documents
   that lack a filtered field, and mock_firestore.py copies that. A
   Postgres column is either NULL or a value, so `find()` has to
   reproduce the exclusion deliberately — `WHERE col = %s` already does
   for NULL, but anything stored as an explicit JSON null will not match
   the old behaviour without care.

The heavier work lands here too: `days` becomes real `duty_assignments`
rows, and this layer reassembles the nested JSON the API returns, so
neither api.py nor Flutter learns that the storage changed.
"""

from repositories.base import COLLECTIONS, CollectionRepo, Repository


def to_camel(name):
    """assigned_station -> assignedStation."""
    head, *rest = name.split("_")
    return head + "".join(word[:1].upper() + word[1:] for word in rest)


def to_snake(name):
    """assignedStation -> assigned_station."""
    out = []
    for char in name:
        if char.isupper():
            out.append("_")
            out.append(char.lower())
        else:
            out.append(char)
    return "".join(out)


def row_to_json(row):
    """One Postgres row as an API-shaped dict."""
    return {to_camel(key): value for key, value in row.items()}


class SupabaseCollectionRepo(CollectionRepo):
    def __init__(self, client, table):
        self._client = client
        self._table = table

    def list(self):
        raise NotImplementedError("Supabase backend not implemented yet")

    def get(self, doc_id):
        raise NotImplementedError("Supabase backend not implemented yet")

    def find(self, **filters):
        raise NotImplementedError("Supabase backend not implemented yet")


class SupabaseRepository(Repository):
    def __init__(self, client=None):
        self._client = client

    def collection(self, name):
        if name not in COLLECTIONS:
            raise KeyError(f"unknown collection {name!r}")
        return SupabaseCollectionRepo(self._client, name)
