# Offline development mode

Development serves the whole API from local JSON instead of the real
database, so day-to-day work costs nothing and needs no network.

```
[ OFFLINE ]     Flutter -> Python :8000 -> mock_data/*.json
[ DEPLOYED ]    Flutter -> Python :8000 -> Supabase Postgres
```

> **Rewritten 2026-08-10, after the Supabase migration and the Firebase
> retirement.** Firestore is gone: there is no real-Firestore mode, no
> `firebase_admin`, and no service account. `mock_data/` is unaffected —
> it was never Firebase, only a local store shaped like it.

## Choosing a backend

`DB_BACKEND` is the switch:

| Value | What answers |
|---|---|
| `mock` | `mock_data/*.json`, offline, no network |
| `supabase` | Supabase Postgres, via the session pooler |

```bash
# offline (the default for local work, via USE_MOCK_DB=1 in .env)
uvicorn api:app --reload --port 8000

# against Supabase
DB_BACKEND=supabase uvicorn api:app --reload --port 8000
```

Left unset, `DB_BACKEND` follows `USE_MOCK_DB=1` to `mock`, which is why
every existing script and command still works untouched. Unset *and*
without `USE_MOCK_DB`, the app **refuses to start**:

```
RuntimeError: DB_BACKEND is not set and USE_MOCK_DB is not on, so there
is no backend to use.
```

That is deliberate. This case used to mean "real Firestore", so a
deployed server that forgot the variable would boot happily and then fail
at the first login, when it went looking for a service account that is not
deployed. There is nothing to fall back to now, so it fails at startup
instead — the earliest and loudest place.

If `mock_data/` is empty, **every login returns 401**. The startup banner
says where data *would* come from, not that any exists.

## Day-to-day

- **Writes persist.** Employees you create, passwords you change and
  schedules you generate are saved to `mock_data/` and survive restarts.
- **Login works offline.** `mock_data/_auth.json` holds one bcrypt hash
  per account; `migrate_passwords.py` converts any stragglers in one pass.
- **Admin signs in with the `/init-admin` bootstrap password offline**,
  from `ADMIN_BOOTSTRAP_PASSWORD` in `.env`.
- **Passwords cannot be read back.** `_auth.json` stores hashes and the
  `password` field on an employee record is a mask, so a forgotten
  password is replaced rather than looked up — Employee Detail → Password
  → **Reset**, which issues a new one and shows it once.
- **`mock_data/` cannot be regenerated.** `export_firestore.py` is
  deleted and there is nothing left to export from. It is the live corpus
  *and* the source `load_supabase.py` reads. **Keep a zipped backup** —
  restoring from a copy is the only recovery there is.

## Before deploying

Run all four gates. Together they cover reads, writes, the repository
layer and the response contract; any one alone leaves a hole.

```bash
# 1. the offline suites — scheduling logic, unaffected by backend
USE_MOCK_DB=1 python testing_leave.py          # and the other five

# 2. the repository against the real project (writes ZZTEST rows, cleans up)
python testing_supabase_repo.py                # expect 58/58

# 3. reads: byte-identical responses
DB_BACKEND=supabase uvicorn api:app --port 8000 &
python golden_capture.py compare               # expect 58/58

# 4. writes: MUTATES the database, restores the corpus afterwards
python testing_supabase_api.py                 # expect 33/33
```

Point `golden_capture.py compare` at the **Supabase** server. The goldens
were re-baselined against Supabase on 2026-08-10, so comparing them to
the mock backend now fails by design, on ~1636 known differences.

The golden files are also date-sensitive — leave windows and duty status
move with the clock — so a comparison run weeks later reports differences
the calendar caused. To isolate a real backend change, run both backends
on the same minute and diff those against each other.

Deployment itself is in **RENDER.md**.

## How it works

Everything routes through `db_init.py`, the only file that knows which
credential store is active:

| | Offline | Supabase |
|---|---|---|
| `get_db()` | `mock_firestore.MockFirestoreClient` | *(unused — `db_backend` hands out a sentinel)* |
| `get_auth()` | `mock_auth` | `supabase_auth` |
| `verify_password()` | `mock_data/_auth.json` | `auth_accounts` table |

`db_backend.py` sits one level up and picks the **repository**, which is
the seam that actually matters: `DocumentRepository` over the mock, or
`SupabaseRepository` over Postgres. `api.py`, `scheduler.py` and
`replacements.py` go through `repo` and never learn which answered.

`mock_firestore.py` implements the subset of the Firestore API this
backend uses: documents, chained `where()` filters, `stream()`, batches
and transactions. It does **not** implement `order_by`, `limit`,
subcollections or `add()` with auto-generated IDs. It is a local JSON
store that happens to wear a Firestore-shaped interface — keeping it cost
nothing when Firebase was retired, and it is what the six offline suites
run against.

## Security note

`mock_data/` holds real employee records (names, emails, phone numbers),
and `.env` holds the Supabase connection string. Both are git-ignored —
keep them that way. So is `golden/`, which holds the same employee
records inside recorded API responses.

Passwords are not among the readable contents: `_auth.json` stores bcrypt
hashes and employee records store a mask. See `passwords.py`.

`firebase-service-account.json` is deleted. The key it held stays valid
until it is revoked in the Firebase console — do that when you shut the
old project down.
