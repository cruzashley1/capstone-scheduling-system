"""Data-access layer. See base.py for the interface and why it exists."""

from repositories.base import CollectionRepo, Repository
from repositories.document_repo import DocumentRepository

__all__ = ["CollectionRepo", "Repository", "DocumentRepository", "from_db"]


def from_db(db):
    """Wraps a Firestore-shaped handle in a Repository.

    For the modules that are handed a `db` rather than reaching for a
    global — `scheduler.generate_group_schedules(db, ...)`,
    `leave.employee_leaves(db, ...)` — and for testing_*.py, which builds
    its own handle. Keeps their signatures unchanged during the
    migration.
    """
    return DocumentRepository(db)
