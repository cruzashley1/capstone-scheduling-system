# Deploying the Sched API to Render

The backend is a FastAPI app talking to Supabase Postgres. There is no
Firebase any more, so there are no service-account files to upload and no
Google credentials to configure — the only secret the server needs is the
Supabase connection string.

---

## Before you start

You need three things to hand:

1. **The GitHub repo pushed**, including the `supabase-migration` branch
   (or merged to `main` — see step 6).
2. **The Supabase session-pooler URI.** Supabase dashboard →
   *Project Settings* → *Database* → *Connection string* → **Session pooler**.
   It looks like:

   ```
   postgresql://postgres.abcdefghijklm:YOUR-PASSWORD@aws-0-ap-northeast-2.pooler.supabase.com:5432/postgres
   ```

   It **must** be the pooler host. The direct `db.<ref>.supabase.co` host is
   IPv6-only, and Render's free tier cannot reach it. This is the single most
   common way this deploy fails.
3. **A bootstrap admin password** you have chosen (any strong string).

---

## Option A — Blueprint (uses the committed `render.yaml`)

1. Render dashboard → **New** → **Blueprint**.
2. Connect the GitHub repo and pick the branch.
3. Render reads `backend_python/render.yaml` and shows one service,
   `sched-api`. It will prompt for the two values marked `sync: false`:
   - `SUPABASE_DB_URL` → paste the session-pooler URI
   - `ADMIN_BOOTSTRAP_PASSWORD` → your chosen password
4. **Apply**. First build takes 2–4 minutes.

## Option B — Create the Web Service by hand

Render dashboard → **New** → **Web Service** → connect the repo, then set:

| Field | Value |
|---|---|
| Root Directory | `backend_python` |
| Runtime | Python 3 |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `uvicorn api:app --host 0.0.0.0 --port $PORT` |
| Health Check Path | `/` |
| Instance Type | Free |

**Root Directory is not optional.** This repo has the Flutter app beside the
backend; without it Render looks for `requirements.txt` at the repo root,
finds nothing, and the build fails immediately.

Then add the environment variables under *Environment*:

| Key | Value |
|---|---|
| `DB_BACKEND` | `supabase` |
| `SUPABASE_DB_URL` | the session-pooler URI |
| `ADMIN_BOOTSTRAP_PASSWORD` | your chosen password |
| `SUPABASE_POOL_SIZE` | `5` |
| `PYTHON_VERSION` | `3.13.6` |

Do **not** set `USE_MOCK_DB`. It selects the offline JSON corpus, and
`mock_data/` is git-ignored, so it is not deployed — the server would start
and then fail on the first read.

---

## Why the start command looks like that

- `--host 0.0.0.0` — uvicorn defaults to `127.0.0.1`, which is reachable only
  from inside the container. Render's health check would never pass and the
  deploy would hang until it timed out.
- `--port $PORT` — Render assigns the port and it is not 8000. Hardcoding
  8000 fails the same way.
- No `--reload`. That is a development flag; it doubles memory and restarts
  on filesystem noise.

---

## What a healthy first deploy looks like

In the Render log:

```
==> Building...
==> Running 'uvicorn api:app --host 0.0.0.0 --port 10000'
Initializing database (backend: supabase)...
Database connected successfully! (backend: supabase)
INFO:     Uvicorn running on http://0.0.0.0:10000
==> Your service is live 🎉
```

Then check it from your machine:

```bash
curl https://sched-api.onrender.com/
curl https://sched-api.onrender.com/employees | head -c 400
```

`/employees` should return 573 records. If it does, the deploy is real —
that response goes all the way through the repository to Supabase.

---

## Troubleshooting

**`RuntimeError: DB_BACKEND is not set and USE_MOCK_DB is not on`**
You forgot `DB_BACKEND=supabase`. This error is deliberate: the app used to
fall back to Firestore here and fail much later, at the first login attempt,
which was far harder to diagnose. Set the variable and redeploy.

**`SUPABASE_DB_URL is not set`**
Same category. Add it under *Environment*.

**Build fails on `psycopg`**
You are not on the committed `requirements.txt`. It pins `psycopg-binary`,
which ships prebuilt wheels; plain `psycopg` would need `libpq` and a
compiler that the build image does not have.

**Connection times out / "network is unreachable"**
Almost certainly the direct database host instead of the session pooler.
Re-copy the URI from the **Session pooler** tab.

**First request after idle takes ~50 seconds**
Expected on the free tier — Render spins the instance down after 15 minutes
of inactivity. The app is fine; it is cold-starting. If a demo cannot absorb
that pause, hit the URL a minute beforehand to wake it.

**Login works locally but not deployed**
Check `DB_BACKEND=supabase` is actually set on the service. Without it the
auth switch falls through to the offline stand-in, which reads
`mock_data/_auth.json` — a file that does not exist on Render.

---

## Pointing the app at it (step 7)

`ApiService.baseUrl` takes the full origin at build time:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://sched-api.onrender.com
```

Use `API_BASE_URL`, not `API_HOST`. `API_HOST` is the LAN-development path
and hardcodes `http://` and `:8000`, so it cannot express an HTTPS origin on
port 443.

For Chrome during development:

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://sched-api.onrender.com
```

---

## Notes

- **CORS is currently `allow_origins=["*"]`** (`api.py`). Fine for a capstone
  demo and required if you serve Flutter web from a different origin. Narrow
  it to your real origins before anything resembling production.
- **The database is not created by the deploy.** The corpus is already in
  Supabase (7851 rows across 17 tables). `load_supabase.py` is a local tool
  and reads `mock_data/`, which is not deployed — never run it against
  production expecting it to work from Render.
- **Rotating the Supabase password** means updating `SUPABASE_DB_URL` on the
  service and redeploying; it is baked into the URI.
- **The old Firebase project can now be shut down.** Nothing reads it. Revoke
  the service-account key in the Firebase console — the local
  `firebase-service-account.json` was deleted, but the key itself stays valid
  until you revoke it.
