"""Data-access layer. See base.py for the interface and why it exists."""

from repositories.base import CollectionRepo, Repository
from repositories.document_repo import DocumentRepository

__all__ = ["CollectionRepo", "Repository", "DocumentRepository", "from_db"]


def from_db(db):
    """The Repository for the active backend, for callers holding a `db`.

    For the modules that are handed a handle rather than reaching for a
    global — `scheduler.generate_group_schedules(db, ...)`,
    `leave.employee_leaves(db, ...)` — and for testing_*.py, which builds
    its own. Keeps their signatures unchanged.

    It must ask db_backend rather than construct a DocumentRepository,
    which is what it did at first. That was invisible while both
    backends were Firestore-shaped and became 21 broken call sites the
    moment one was not: every leave endpoint returned 500 with
    "'_SupabaseHandle' object has no attribute 'collection'", because
    the handle was wrapped in a repository that speaks Firestore no
    matter what DB_BACKEND says.

    The import is deferred because db_backend imports db_init,
    which this package's document_repo also imports — at module level
    the three would close a cycle.
    """
    import db_backend

    return db_backend.get_repository(db)
