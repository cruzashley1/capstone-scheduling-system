"""
Repository over Supabase (Postgres), the second implementation of the
interface in base.py.

The job is narrow and strict: behave exactly like DocumentRepository, so
that flipping DB_BACKEND changes where the data lives and nothing else.
58 golden files hold the current responses and six testing_*.py suites
hold the current behaviour; both must stay green across the switch.

Four things this layer owes the rest of the backend:

1. **camelCase out, snake_case in.** Columns are snake_case because
   Postgres folds unquoted identifiers to lowercase, so `assignedStation`
   would become `assignedstation` and arrive in Flutter as null. The
   conversion happens here and nowhere else — a column name must never
   reach a response, and api.py must never learn a column name.

2. **Order is part of the contract.** Postgres promises no row order
   without ORDER BY. Reads pin `ORDER BY id`, which was measured against
   the golden files rather than assumed: id order reproduces 54 of 58
   exactly, and the 4 that move do so by ordering only.

3. **`days` is reassembled.** Schedules store their duty entries in the
   `duty_assignments` table, and this layer rebuilds the nested
   `days: [{date, entries: [...]}]` structure on read and takes it apart
   on write. Neither api.py nor Flutter learns that the storage changed.

4. **Firestore's error semantics.** `update()` raises on a missing
   record, `delete()` does not. The 404 paths depend on the first and the
   retry-safe withdraw path depends on the second.

What this layer deliberately does NOT do is cap a transaction. The
document backend refuses past 500 writes because Firestore's batches
break there; Postgres has no such limit, and inventing one would refuse
transactions that are perfectly safe.
"""

import atexit
import os
import threading
from contextlib import contextmanager
from contextvars import ContextVar
from datetime import date, timedelta

from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool

from repositories.base import (COLLECTIONS, CollectionRepo, Repository,
                               Transaction, TransactionCollection)

# Collections whose records do NOT carry an "id" field in the response.
# Every other collection stores its own id in the document body, so
# returning the primary key reproduces it; for these two, returning it
# would ADD a field that /login and the counters have never had.
_ID_OMITTED = frozenset({"users", "counters"})

# Columns added AFTER the response shapes were frozen by the golden
# files, mapped to the value that means "this document never had the
# field". A row still sitting at that value is returned WITHOUT the key,
# rather than with an explicit null, and the difference is the whole
# point: Postgres gives every row every column, so a plain ALTER TABLE
# would add `"originalTimeIn": null` to all 3,400 duty entries and to
# every replacement record written before the rule existed.
#
# That is not a cosmetic difference. Those responses are the contract
# api_service.dart reads, the golden files are how a change to them gets
# noticed, and a field nobody set is a field the document does not have.
# The document backend has always answered that way; this keeps the two
# saying the same thing.
#
# Keyed by the camelCase name, because that is the form the document
# carries by the time this runs.
_OMIT_WHEN_UNSET = {
    "users": {"name": None},
    "schedules": {"approvalId": None, "approvalStatus": None},
    "duty_assignments": {
        "originalTimeIn": None,
        "originalTimeOut": None,
        "dayOffset": 0,
        "prepMinutes": None,
    },
    "replacements": {
        "appliedBy": None,
        "reason": None,
        "timeIn": None,
        "timeOut": None,
        "originalTimeIn": None,
        "originalTimeOut": None,
        "prepAdjusted": False,
        "prepMinutes": None,
        "reportAt": None,
    },
}

_workflow_connection = ContextVar("workflow_connection", default=None)


@contextmanager
def _connection(pool):
    active = _workflow_connection.get()
    if active is not None:
        yield active
    else:
        with pool.connection() as conn:
            yield conn

# The table that holds what schedules.days used to hold inline. Not in
# COLLECTIONS on purpose — it is storage, not vocabulary, and no caller
# outside this module may reach it.
_DUTY_TABLE = "duty_assignments"

# The columns of duty_assignments that describe the ROW rather than the
# entry. They are stripped on the way out; the remaining columns are
# exactly the 11 keys an entry has always had.
_DUTY_INTERNAL = ("schedule_id", "day_index", "day_date", "position")

# What a duty row gets for a column it does not carry. Only NOT NULL
# columns need an answer: the rest take None, which is what their absence
# means. day_offset is on the list because one re-timed entry puts the
# column into the INSERT for every entry of that schedule, and the other
# 3,400 of them do not carry it.
_DUTY_DEFAULTS = {"day_offset": 0}


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


def _period_dates(start_iso, end_iso):
    """Every date from start to end inclusive, as ISO strings.

    Reconstruction generates the day list from the schedule's own
    start/end rather than from the duty rows, because a day with no
    entries produces no rows — rebuilding from rows alone would silently
    drop empty days and shorten the fortnight. testing_station_rename.py
    exercises a schedule that is empty on every single day.
    """
    first = date.fromisoformat(start_iso)
    last = date.fromisoformat(end_iso)
    out = []
    while first <= last:
        out.append(first.isoformat())
        first += timedelta(days=1)
    return out


# ---------------------------------------------------------------------
# Connection pool
# ---------------------------------------------------------------------
#
# api.py's endpoints are sync `def`, so FastAPI runs them in a thread
# pool and several can be in flight at once. One shared connection would
# serialise them and corrupt psycopg's protocol state; a connection per
# request would pay Supabase's pooler handshake every time.
#
# `check` matters more than it looks: Supabase's session pooler drops
# idle connections, and on Render's free tier the service itself sleeps.
# Without a liveness check the first request after a quiet spell fails on
# a dead socket that the pool still believes is good.

_pool = None
_pool_lock = threading.Lock()


def get_pool():
    """The process-wide connection pool, opened on first use."""
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                url = os.getenv("SUPABASE_DB_URL")
                if not url:
                    raise RuntimeError(
                        "SUPABASE_DB_URL is not set. DB_BACKEND=supabase "
                        "needs the session-pooler connection string from "
                        "the Supabase dashboard (Project Settings > "
                        "Database > Connection string > Session pooler). "
                        "The direct host is IPv6-only.")
                _pool = ConnectionPool(
                    url,
                    min_size=1,
                    max_size=int(os.getenv("SUPABASE_POOL_SIZE", "5")),
                    kwargs={"row_factory": dict_row},
                    check=ConnectionPool.check_connection,
                    open=True,
                )
                # Without this, a script that finishes its work exits
                # into psycopg's "couldn't stop thread ... within 5.0
                # seconds" warnings, because the pool's workers outlive
                # main(). Harmless, but it makes every clean run look
                # like it failed.
                atexit.register(close_pool)
    return _pool


def close_pool():
    """Shuts the pool down. For tests and clean process exit."""
    global _pool
    with _pool_lock:
        if _pool is not None:
            _pool.close()
            _pool = None


# ---------------------------------------------------------------------
# Schema reflection
# ---------------------------------------------------------------------
#
# The alternative was hardcoding the column lists here, in a second place
# that has to agree with schema/001_initial.sql forever. Reading them
# from the database costs one query per process and cannot drift.

class _Schema:
    """Column names and JSONB columns, per table, read once."""

    def __init__(self, pool):
        self.columns = {}     # table -> (col, ...) in DDL order
        self._jsonb = {}      # table -> frozenset of jsonb columns
        self._by_camel = {}   # table -> {camelCaseKey: column}
        with pool.connection() as conn:
            rows = conn.execute("""
                SELECT table_name, column_name, data_type
                  FROM information_schema.columns
                 WHERE table_schema = 'public'
                 ORDER BY table_name, ordinal_position
            """).fetchall()

        grouped = {}
        for row in rows:
            grouped.setdefault(row["table_name"], []).append(row)

        for table, cols in grouped.items():
            self.columns[table] = tuple(c["column_name"] for c in cols)
            self._jsonb[table] = frozenset(
                c["column_name"] for c in cols if c["data_type"] == "jsonb")
            self._by_camel[table] = {
                to_camel(c["column_name"]): c["column_name"] for c in cols}

        missing = [t for t in COLLECTIONS if t not in self.columns]
        if missing or _DUTY_TABLE not in self.columns:
            missing = missing + ([] if _DUTY_TABLE in self.columns
                                 else [_DUTY_TABLE])
            raise RuntimeError(
                f"Supabase is missing table(s): {', '.join(missing)}. "
                f"Apply schema migrations 001 through 005 to the project first.")

    def column(self, table, key):
        """The column a camelCase API field maps to.

        Raises rather than dropping the field. A silently ignored write
        is the worst failure mode available here — the response would
        look fine and the data would not be there.
        """
        try:
            return self._by_camel[table][key]
        except KeyError:
            raise KeyError(
                f"{table} has no field {key!r}. Known fields: "
                f"{', '.join(sorted(self._by_camel[table]))}") from None

    def bind(self, table, column, value):
        """A value ready for a placeholder, wrapped if the column is JSONB.

        psycopg maps a Python list to a Postgres ARRAY by default, which
        a jsonb column rejects. Everything bound for a jsonb column is
        wrapped explicitly, dicts included, so neither shape depends on
        the driver's guess.
        """
        if column in self._jsonb[table]:
            return Jsonb(value)
        return value


_schema = None
_schema_lock = threading.Lock()


def get_schema(pool):
    global _schema
    if _schema is None:
        with _schema_lock:
            if _schema is None:
                _schema = _Schema(pool)
    return _schema


# ---------------------------------------------------------------------
# SQL building
# ---------------------------------------------------------------------
#
# Identifiers go through sql.Identifier rather than f-strings: it quotes
# them, which is what makes the `group` column work at all — GROUP is
# reserved, and `SET group = %s` is a syntax error.

def _ident(name):
    return sql.Identifier(name)


def _drop_unset(table, document):
    """`document` without the late-addition fields it never set.

    In place, and returns it. See _OMIT_WHEN_UNSET.
    """
    for key, unset in _OMIT_WHEN_UNSET.get(table, {}).items():
        value = document.get(key)
        if value is None or value == unset:
            document.pop(key, None)
    return document


def _row_out(table, row):
    """One Postgres row as the dict the API has always returned."""
    out = {to_camel(key): value for key, value in row.items()}
    if table in _ID_OMITTED:
        out.pop("id", None)
    return _drop_unset(table, out)


def _where(schema, table, filters):
    """(SQL fragment, params) for an equality filter set.

    `col = %s` already excludes rows where the column is NULL, which is
    exactly the Firestore behaviour find() has to reproduce: a document
    that LACKS the filtered field is not a match.
    """
    if not filters:
        return sql.SQL(""), []
    clauses, params = [], []
    for key, value in filters.items():
        column = schema.column(table, key)
        clauses.append(sql.SQL("{} = %s").format(_ident(column)))
        params.append(schema.bind(table, column, value))
    return (sql.SQL(" WHERE ") + sql.SQL(" AND ").join(clauses)), params


def _assignments(schema, table, fields):
    """(SET fragment, params) for a partial write."""
    parts, params = [], []
    for key, value in fields.items():
        column = schema.column(table, key)
        parts.append(sql.SQL("{} = %s").format(_ident(column)))
        params.append(schema.bind(table, column, value))
    return sql.SQL(", ").join(parts), params


def _conflict_clause(schema, table, columns, merge):
    """The ON CONFLICT action for an upsert over `columns`.

    merge=False mirrors Firestore's .set(): the record is REPLACED, so a
    column absent from the data goes back to its default rather than
    keeping the value it happened to have. `SET col = DEFAULT` says that
    in one statement, with no read first.

    merge=True touches only the given columns.

    Shared by upsert() and upsert_many() because they must agree. They
    did not at first — upsert_many only ever set the given columns, so
    re-importing a record that had LOST a field left the old value in
    place. The document backend's upsert_many is `batch.set(doc, data)`
    with no merge flag, which replaces; one corpus record with no
    assignedShift is what surfaced the difference.
    """
    updates = [sql.SQL("{0} = EXCLUDED.{0}").format(_ident(c))
               for c in columns if c != "id"]
    if not merge:
        untouched = [c for c in schema.columns[table]
                     if c not in columns and c != "id"]
        updates += [sql.SQL("{} = DEFAULT").format(_ident(c))
                    for c in untouched]

    # A record of nothing but its id has nothing to set, and an empty
    # SET is a syntax error. DO NOTHING says the same thing legally.
    if not updates:
        return sql.SQL("DO NOTHING")
    return sql.SQL("DO UPDATE SET ") + sql.SQL(", ").join(updates)


def _upsert_sql(schema, table, data, merge):
    """(statement, params) for one INSERT ... ON CONFLICT."""
    columns = [schema.column(table, key) for key in data]
    params = [schema.bind(table, col, value)
              for col, value in zip(columns, data.values())]
    conflict = _conflict_clause(schema, table, columns, merge)

    statement = sql.SQL(
        "INSERT INTO {table} ({cols}) VALUES ({vals}) "
        "ON CONFLICT (id) {conflict}"
    ).format(
        table=_ident(table),
        cols=sql.SQL(", ").join(_ident(c) for c in columns),
        vals=sql.SQL(", ").join([sql.Placeholder()] * len(columns)),
        conflict=conflict,
    )
    return statement, params


# Postgres refuses a statement with more than 65535 bound parameters.
# Chunking lives here rather than at the call sites, which is what the
# interface promises: "callers should not have to know which, or what the
# cap is". Left well clear of the limit so a wide table cannot creep up
# on it — 1895 notifications at 8 columns is one statement either way.
_MAX_PARAMS = 30000


def _in_chunks(rows, columns):
    """`rows` split so no single statement exceeds the parameter cap."""
    per_row = max(len(columns), 1)
    size = max(1, _MAX_PARAMS // per_row)
    for start in range(0, len(rows), size):
        yield rows[start:start + size]


def _with_id(doc_id, data):
    """`data` guaranteed to carry its own id, without mutating the caller's.

    Callers pass the id separately and usually also inside the record;
    the primary key has to be set either way.
    """
    if data.get("id") == doc_id:
        return data
    merged = dict(data)
    merged["id"] = doc_id
    return merged


# ---------------------------------------------------------------------
# Schedule days <-> duty_assignments
# ---------------------------------------------------------------------

def _split_days(schedule_id, days):
    """`days` flattened into duty_assignments rows.

    day_index and position are recorded explicitly because entry order
    within a day is part of the rendered contract and the ids sort wrong
    as text — "STA027_0_10" lands between "_0_1" and "_0_2".
    """
    rows = []
    for day_index, day in enumerate(days or []):
        for position, entry in enumerate(day.get("entries") or []):
            row = {
                "schedule_id": schedule_id,
                "day_index": day_index,
                "day_date": day.get("date"),
                "position": position,
            }
            for key, value in entry.items():
                row[to_snake(key)] = value
            rows.append(row)
    return rows


def _write_days(cursor, schema, schedule_id, days):
    """Replaces every duty row for one schedule.

    Delete-then-insert rather than a diff: a regenerated schedule shares
    almost no entry ids with the one it replaces, so a diff would be more
    code for the same writes. Inside a transaction this is atomic; on its
    own it is one statement pair against a single schedule.
    """
    cursor.execute(
        sql.SQL("DELETE FROM {} WHERE schedule_id = %s").format(
            _ident(_DUTY_TABLE)),
        [schedule_id])

    rows = _split_days(schedule_id, days)
    if not rows:
        return

    # The UNION of every row's keys, not the first row's. Entries within
    # one schedule no longer all carry the same fields: applying a
    # replacement re-times a SINGLE entry and stamps the preparation
    # window onto it alone (see prep_window.py). Reading the column list
    # off rows[0] dropped those fields on the floor whenever the adjusted
    # entry was not the first of the fortnight, which is almost always.
    columns = []
    for row in rows:
        for column in row:
            if column not in columns:
                columns.append(column)

    unknown = [c for c in columns if c not in schema.columns[_DUTY_TABLE]]
    if unknown:
        raise KeyError(
            f"schedule entries carry unknown field(s) {unknown}; "
            f"{_DUTY_TABLE} would drop them silently")

    template = sql.SQL("({})").format(
        sql.SQL(", ").join([sql.Placeholder()] * len(columns)))

    for batch in _in_chunks(rows, columns):
        params = []
        for row in batch:
            params.extend(
                schema.bind(_DUTY_TABLE, c,
                            row.get(c, _DUTY_DEFAULTS.get(c)))
                for c in columns)
        cursor.execute(
            sql.SQL("INSERT INTO {table} ({cols}) VALUES {vals}").format(
                table=_ident(_DUTY_TABLE),
                cols=sql.SQL(", ").join(_ident(c) for c in columns),
                vals=sql.SQL(", ").join([template] * len(batch)),
            ),
            params)


def _attach_days(cursor, schedules):
    """Puts `days` back onto schedule dicts, in place, and returns them.

    One query for every schedule in the result rather than one per
    schedule: /schedules reads all 16 at once and the per-schedule
    version would be 17 round trips to Supabase instead of 2.
    """
    if not schedules:
        return schedules

    ids = [s["id"] for s in schedules]
    cursor.execute(
        sql.SQL("SELECT * FROM {} WHERE schedule_id = ANY(%s) "
                "ORDER BY schedule_id, day_index, position").format(
                    _ident(_DUTY_TABLE)),
        [ids])

    grouped = {}
    for row in cursor.fetchall():
        entry = _drop_unset(_DUTY_TABLE, {to_camel(k): v for k, v in
                                          row.items()
                                          if k not in _DUTY_INTERNAL})
        grouped.setdefault(row["schedule_id"], {}).setdefault(
            row["day_index"], []).append(entry)

    for schedule in schedules:
        by_index = grouped.get(schedule["id"], {})
        dates = _period_dates(schedule["startDate"], schedule["endDate"])
        schedule["days"] = [
            {"date": day_date, "entries": by_index.get(index, [])}
            for index, day_date in enumerate(dates)]
    return schedules


# ---------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------

class SupabaseCollectionRepo(CollectionRepo):
    """One table, reached with its own connection per call.

    Each method borrows a pooled connection and returns it, so nothing
    here holds state between calls. Writes commit on their own; the
    all-or-nothing case is what transaction() is for.
    """

    def __init__(self, pool, schema, table):
        self._pool = pool
        self._schema = schema
        self._table = table

    # --- reads --------------------------------------------------------

    def _select(self, filters=None):
        where, params = _where(self._schema, self._table, filters or {})
        statement = sql.SQL("SELECT * FROM {}").format(_ident(self._table))
        statement = statement + where + sql.SQL(" ORDER BY id")
        with _connection(self._pool) as conn, conn.cursor() as cur:
            cur.execute(statement, params)
            rows = [_row_out(self._table, r) for r in cur.fetchall()]
            return self._hydrate(cur, rows)

    def _hydrate(self, cursor, rows):
        """Hook for tables whose records are assembled from more than one
        table. Only schedules needs it."""
        return rows

    def list(self):
        return self._select()

    def get(self, doc_id):
        rows = self._select({"id": doc_id})
        return rows[0] if rows else None

    def find(self, **filters):
        # find() with no filters must behave like list() — api.py calls
        # find(**{}) when no cycle is given.
        return self._select(filters)

    # --- writes -------------------------------------------------------

    def upsert(self, doc_id, data, merge=False):
        data = _with_id(doc_id, data)
        statement, params = _upsert_sql(self._schema, self._table, data, merge)
        with _connection(self._pool) as conn, conn.cursor() as cur:
            cur.execute(statement, params)

    def upsert_many(self, records):
        # Grouped by column set, because the records need not agree on
        # which fields they carry and one INSERT has one column list.
        # No 500-write cap to work around here.
        #
        # REPLACES, like the document backend's batch.set(doc, data):
        # a record that omits a field resets that column rather than
        # leaving whatever was there before.
        if not records:
            return
        groups = {}
        for doc_id, data in records.items():
            data = _with_id(doc_id, data)
            groups.setdefault(tuple(data), []).append(data)

        with _connection(self._pool) as conn, conn.cursor() as cur:
            for keys, batch in groups.items():
                columns = [self._schema.column(self._table, k) for k in keys]
                conflict = _conflict_clause(
                    self._schema, self._table, columns, merge=False)
                template = sql.SQL("({})").format(
                    sql.SQL(", ").join([sql.Placeholder()] * len(columns)))
                for rows in _in_chunks(batch, columns):
                    params = []
                    for data in rows:
                        params.extend(
                            self._schema.bind(self._table, col, data[key])
                            for col, key in zip(columns, keys))
                    cur.execute(
                        sql.SQL("INSERT INTO {table} ({cols}) VALUES {vals} "
                                "ON CONFLICT (id) {conflict}").format(
                                    table=_ident(self._table),
                                    cols=sql.SQL(", ").join(
                                        _ident(c) for c in columns),
                                    vals=sql.SQL(", ").join(
                                        [template] * len(rows)),
                                    conflict=conflict),
                        params)

    def update(self, doc_id, fields):
        with _connection(self._pool) as conn, conn.cursor() as cur:
            _update_one(cur, self._schema, self._table, doc_id, fields)

    def delete(self, doc_id):
        with _connection(self._pool) as conn, conn.cursor() as cur:
            cur.execute(
                sql.SQL("DELETE FROM {} WHERE id = %s").format(
                    _ident(self._table)),
                [doc_id])

    def delete_many(self, doc_ids):
        doc_ids = list(doc_ids)
        if doc_ids:
            with _connection(self._pool) as conn, conn.cursor() as cur:
                cur.execute(
                    sql.SQL("DELETE FROM {} WHERE id = ANY(%s)").format(
                        _ident(self._table)),
                    [doc_ids])
        # The count asked for, not the count found — same as the document
        # backend, which cannot tell the difference either.
        return len(doc_ids)

    def update_where(self, filters, fields):
        with _connection(self._pool) as conn, conn.cursor() as cur:
            return _update_where(cur, self._schema, self._table,
                                 filters, fields)


def _update_one(cursor, schema, table, doc_id, fields):
    """UPDATE ... WHERE id, raising when nothing matched.

    Firestore's .update() fails on a missing document and mock_firestore
    copies that with a KeyError; the 404 paths in api.py are built on it.
    An ON CONFLICT-style insert here would turn "not found" into a
    half-populated row that violates NOT NULL a moment later.
    """
    if not fields:
        return
    sets, params = _assignments(schema, table, fields)
    cursor.execute(
        sql.SQL("UPDATE {} SET {} WHERE id = %s").format(
            _ident(table), sets),
        params + [doc_id])
    if cursor.rowcount == 0:
        raise KeyError(f"No document to update: {table}/{doc_id}")


def _update_where(cursor, schema, table, filters, fields):
    """UPDATE ... WHERE <filters>, returning the row count.

    The method that keeps document references off the interface: what
    Firestore does as query-then-batch is one statement here, and it is
    already atomic on its own.
    """
    if not fields:
        return 0
    sets, set_params = _assignments(schema, table, fields)
    where, where_params = _where(schema, table, filters)
    cursor.execute(
        sql.SQL("UPDATE {} SET {}").format(_ident(table), sets) + where,
        set_params + where_params)
    return cursor.rowcount


class SupabaseSchedulesRepo(SupabaseCollectionRepo):
    """Schedules, whose `days` lives in duty_assignments.

    Every read reassembles it and every write takes it apart, so the
    decomposition is invisible above this class — api.py still receives
    the nested structure it always has.
    """

    def _hydrate(self, cursor, rows):
        return _attach_days(cursor, rows)

    def upsert(self, doc_id, data, merge=False):
        data = _with_id(doc_id, data)
        days = data.get("days")
        # merge=True without days must leave the existing duties alone;
        # a replace with no days really does mean "no duties".
        touches_days = "days" in data or not merge
        data = {k: v for k, v in data.items() if k != "days"}

        statement, params = _upsert_sql(self._schema, self._table, data, merge)
        with _connection(self._pool) as conn, conn.cursor() as cur:
            with conn.transaction():
                cur.execute(statement, params)
                if touches_days:
                    _write_days(cur, self._schema, doc_id, days)

    def upsert_many(self, records):
        for doc_id, data in records.items():
            self.upsert(doc_id, data)

    def update(self, doc_id, fields):
        days = fields.get("days")
        touches_days = "days" in fields
        fields = {k: v for k, v in fields.items() if k != "days"}
        with _connection(self._pool) as conn, conn.cursor() as cur:
            with conn.transaction():
                if fields:
                    _update_one(cur, self._schema, self._table, doc_id, fields)
                elif touches_days and not _exists(cur, self._table, doc_id):
                    raise KeyError(
                        f"No document to update: {self._table}/{doc_id}")
                if touches_days:
                    _write_days(cur, self._schema, doc_id, days)


def _exists(cursor, table, doc_id):
    cursor.execute(
        sql.SQL("SELECT 1 FROM {} WHERE id = %s").format(_ident(table)),
        [doc_id])
    return cursor.fetchone() is not None


# ---------------------------------------------------------------------
# Transactions
# ---------------------------------------------------------------------

class SupabaseTransactionCollection(TransactionCollection):
    """Writes on the transaction's connection, landing only at COMMIT.

    Unlike the document backend nothing is queued: the statements run
    immediately, inside an open BEGIN, and the rollback on an exception
    is what makes them all-or-nothing. That also means update_where's
    matching happens now, which is the documented behaviour.
    """

    def __init__(self, cursor, schema, table):
        self._cursor = cursor
        self._schema = schema
        self._table = table

    def upsert(self, doc_id, data, merge=False):
        data = _with_id(doc_id, data)
        days = data.get("days")
        schedules = self._table == "schedules"
        touches_days = schedules and ("days" in data or not merge)
        if schedules:
            data = {k: v for k, v in data.items() if k != "days"}

        statement, params = _upsert_sql(self._schema, self._table, data, merge)
        self._cursor.execute(statement, params)
        if touches_days:
            _write_days(self._cursor, self._schema, doc_id, days)

    def update(self, doc_id, fields):
        _update_one(self._cursor, self._schema, self._table, doc_id, fields)

    def delete(self, doc_id):
        # duty_assignments goes with it: the foreign key is ON DELETE
        # CASCADE precisely so a deleted schedule cannot leave orphans.
        self._cursor.execute(
            sql.SQL("DELETE FROM {} WHERE id = %s").format(
                _ident(self._table)),
            [doc_id])

    def update_where(self, filters, fields):
        return _update_where(self._cursor, self._schema, self._table,
                             filters, fields)

    def delete_where(self, filters):
        where, params = _where(self._schema, self._table, filters)
        self._cursor.execute(
            sql.SQL("DELETE FROM {}").format(_ident(self._table)) + where,
            params)
        return self._cursor.rowcount


class SupabaseTransaction(Transaction):
    """One BEGIN/COMMIT, shared by every collection reached through it."""

    def __init__(self, cursor, schema):
        self._cursor = cursor
        self._schema = schema
        self._collections = {}

    def collection(self, name):
        if name not in COLLECTIONS:
            raise KeyError(f"unknown collection {name!r}")
        if name not in self._collections:
            self._collections[name] = SupabaseTransactionCollection(
                self._cursor, self._schema, name)
        return self._collections[name]


class SupabaseRepository(Repository):
    def __init__(self, pool=None):
        self._pool = pool or get_pool()
        self._schema = get_schema(self._pool)
        self._repos = {}

    def collection(self, name):
        if name not in COLLECTIONS:
            raise KeyError(f"unknown collection {name!r}")
        if name not in self._repos:
            cls = (SupabaseSchedulesRepo if name == "schedules"
                   else SupabaseCollectionRepo)
            self._repos[name] = cls(self._pool, self._schema, name)
        return self._repos[name]

    @contextmanager
    def workflow_transaction(self):
        """One transaction across reads/writes, serialized across API workers.

        Generation, decisions, revisions and emergency replacements all use
        this lock, so a reviewed roster cannot change during final approval.
        """
        if _workflow_connection.get() is not None:
            yield
            return
        with self._pool.connection() as conn, conn.transaction():
            conn.execute("SELECT pg_advisory_xact_lock(837214005)")
            token = _workflow_connection.set(conn)
            try:
                yield
            finally:
                _workflow_connection.reset(token)

    @contextmanager
    def transaction(self):
        """Yields a Transaction, committing only on a clean exit.

        An exception rolls the whole thing back, so a half-finished
        station rename — schedules renamed, employees not — cannot reach
        the database.
        """
        with _connection(self._pool) as conn, conn.cursor() as cur:
            with conn.transaction():
                yield SupabaseTransaction(cur, self._schema)

    def next_sequence(self, counter_name):
        """The counter increment, as one statement.

        Atomic because it is single: two callers cannot both read 976 and
        both write 977, which is what would hand two new employees the
        same username. Starting at 1 matches the existing counters.
        """
        with _connection(self._pool) as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO counters (id, value) VALUES (%s, 1) "
                "ON CONFLICT (id) DO UPDATE SET value = counters.value + 1 "
                "RETURNING value",
                [counter_name])
            return cur.fetchone()["value"]
