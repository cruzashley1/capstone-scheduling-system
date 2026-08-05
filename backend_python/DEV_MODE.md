# Offline development mode

Testing against real Firestore burns the free tier's 50k reads/day fast — one
`GET /employees` costs ~430 reads, so a few dozen page refreshes can drain a
day's quota. Development mode serves the same data from local JSON instead, at
zero Firebase reads.

```
[ DEVELOPMENT ]  Flutter -> Python :8000 -> mock_data/*.json      0 reads
[ PRODUCTION  ]  Flutter -> Python :8000 -> Firestore
```

## One-time setup

Export a snapshot of the real database. This is the only step that costs reads
(one per document, charged once). Leave `USE_MOCK_DB=1` in `.env` — a shell
variable overrides it, so you never have to edit the file:

```powershell
# PowerShell, in backend_python/
$env:USE_MOCK_DB = "0"; python export_firestore.py; $env:USE_MOCK_DB = ""
```

The export refuses to run in mock mode, which is a safety check, not an error —
it would otherwise export the mock onto itself. Then start the server as usual:

```bash
uvicorn api:app --reload --port 8000
```

If `mock_data/` is empty, **every login returns 401** — the startup banner
confirms where data would be read from, not that any exists. Check that
`mock_data/` has JSON files in it before assuming credentials are wrong.

You'll see `[MOCK MODE] Firestore served from ... - 0 Firebase reads.` at
startup. Flutter needs no changes — same host, same port, same endpoints.

## Day-to-day

- **Writes persist.** Employees you create, passwords you change and schedules
  you generate are saved to `mock_data/` and survive restarts.
- **Login works offline.** `mock_data/_auth.json` holds one bcrypt hash per
  account. Records written before hashing landed still verify and are
  upgraded in place on the next successful login; `migrate_passwords.py`
  converts them all in one pass.
- **Admin signs in with the `/init-admin` bootstrap password offline**,
  regardless of the real admin password. That password comes from
  `ADMIN_BOOTSTRAP_PASSWORD` in `.env`, falling back to the documented
  development default when unset. Admin passwords are hashed inside Firebase
  Auth and never stored in Firestore, so there is nothing to export. The real
  account is unaffected.
- **Passwords cannot be read back.** `_auth.json` stores hashes and the
  `password` field on an employee record is a mask, so a forgotten password
  is replaced rather than looked up — Employee Detail → Password → **Reset**,
  which issues a new one and shows it once.
- **To start clean**, delete `mock_data/` and re-run `export_firestore.py`
  (costs reads again), or restore the folder from a copy you kept.
- **To go back to real Firestore**, set `USE_MOCK_DB=0` and restart.

Keep a zipped copy of `mock_data/` after the first export. Restoring from it is
free; re-exporting is not.

## Before deploying

Always run a final pass with `USE_MOCK_DB=0` against real Firestore. The mock
mirrors Firestore's behaviour closely — including rejecting `update()` on a
missing document and excluding documents that lack a filtered field — but it is
still a stand-in, and real Firestore is the thing that has to work.

## How it works

Everything routes through `firebase_init.py`, which is the only file that knows
which mode is active:

| | Real | Mock |
|---|---|---|
| `get_db()` | `firestore.client()` | `mock_firestore.MockFirestoreClient` |
| `get_auth()` | `firebase_admin.auth` | `mock_auth` |
| `transactional` | `firestore.transactional` | `mock_firestore.transactional` |
| `verify_password()` | Identity Toolkit REST | `mock_data/_auth.json` |

`api.py`, `scheduler.py` and `replacements.py` are mode-agnostic — they call
`db.collection(...)` and never learn which backend answered.

`mock_firestore.py` implements the subset of the Firestore API this backend
uses: documents, chained `where()` filters, `stream()`, batches, and
transactions. It does **not** implement `order_by`, `limit`, subcollections or
`add()` with auto-generated IDs. If you add one of those to the backend, extend
the mock at the same time or it will raise `AttributeError` in dev mode.

## Security note

`mock_data/` holds real employee records (names, emails, phone numbers), and
`.env` and `firebase-service-account.json` hold live credentials. All three
are git-ignored — keep them that way. So is `golden/`, which holds the same
employee records in recorded API responses.

Passwords are no longer among the readable contents: `_auth.json` stores
bcrypt hashes and employee records store a mask. See `passwords.py`.
