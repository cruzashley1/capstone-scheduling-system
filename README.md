# Sched — Security Guard Duty Scheduling System

Sched builds and runs the duty roster for a security agency deployed across
a rail line: **573 guards across 25 stations**, rostered in **15-day
(bi-weekly) periods**, with the day-to-day churn — absences, covers, leave,
day-off requests — handled inside the same system that produced the roster.

The problem it replaces is a spreadsheet. Somebody had to decide who stands
which post, on which day, at which station; keep a guard's rest days honest;
find a warm body when someone calls in sick at 0400H; and remember that a
leave filed in March means a post is unmanned in April. Sched does that
generation and that follow-up, and — importantly — never silently drops a
person or a post: anything it had to bend is filed as a **note** the admin
can read and act on.

```
  Flutter app  ──HTTP/JSON──▶  FastAPI (Python)  ──▶  Supabase Postgres
  admin · head guard · guard      scheduling engine        21 tables
                                  + Gemini (advisory)
```

---

## Who uses it, and what they can do

The same codebase serves admin, Assistant Security, Area Commander, head guard, regular guard and reliever accounts; login decides which UI opens.

### Admin — the scheduling office
Runs as a desktop/web app with a full sidebar.

| Area | What it does |
|---|---|
| **Dashboard** | Live counts for today — on duty, absent, available, unassigned — each one tappable into the list behind it |
| **Security Management** | The employee roster: add, edit, deactivate, reset passwords, set assigned station/shift and preferred stations |
| **Station Management** | The 25 stations and, per station, the **per-shift post setup** — how many guards each shift takes and the named post filling each slot |
| **Generate Schedule** | Runs the engine for a station group (or one station) over a 15-day period, shows the roster with its notes, then saves drafts for period-wide approval |
| **Schedule Management** | Published and draft schedules: edit drafts, add an employee, re-post, and submit complete periods for approval |
| **Notifications** | Everything guards filed — absence requests, leave requests, special day-off requests, submitted attendance reports — with approve/deny in place |
| **Find Replacement** | Ranked, conflict-free candidates for an absence, with an optional AI second opinion; committing one rewrites the schedule and notifies the guard |
| **Reports** | Approved schedule PDFs (per station or whole period), with recorded reviewer names and dates; yearly leave reports retain configurable signatories |
| **Settings** | Company/profile details, password change, developer switches |

### Assistant Security and Area Commander (schedule reviewers)

Both use a desktop review screen for all stations. The admin submits one
complete period through **Period Approvals**. Assistant Security approves
first, then Area Commander. The final decision automatically publishes every
station and unlocks schedule PDF export. Either official can return the
submission with revision comments.

The admin creates their accounts in **Official Accounts**. Submitted rosters,
decisions and emergency amendments are preserved in history. Emergency
replacements take effect immediately and notify both officials; routine
revisions require both approvals again.

Deployment requires migration **005** and updated clients. See
[Schedule approval setup and usage](backend_python/SCHEDULE_APPROVALS.md).

### Head Guard — the station supervisor
Mobile layout, scoped to their own station.

- **Station Overview** — today's roster for their station, post by post
- **Attendance Report** — files present/absent **per shift**; the day HG (0500H–1700H) files Morning *and* Afternoon, the night HG (1700H–0500H) files Night only, and neither can file for the other's shifts. One submission per shift, then it locks
- **Schedule**, **Alerts**, **Profile** — as below

### Security Guard — regular and reliever
Mobile layout, scoped to themselves.

- **Dashboard** — today's duty card: station, post, time-in/time-out
- **Schedule** — their own 15-day roster, rest days included
- **Emergency absence** — file sick/injury/occasion against a duty. Closes one hour before time-in; one filing per date, whatever the decision, so nothing gets re-litigated by re-filing
- **Leave request** — with the rules enforced server-side (below)
- **Special day-off request** — up to 3 upcoming days that no schedule covers yet; approved, they are forced off when that period generates
- **Cover offer** — "I'm available" on a rest day, with preferred shifts/stations. Not an assignment: it boosts them to the top of the admin's replacement list
- **Alerts** — decisions, cover assignments, schedule changes
- **Profile** — details, change password

---

## The scheduling engine

Generation is three stages, each in its own module, each documented in its own
file header.

### 1. Station setup drives everything — [`station_posts.py`](backend_python/station_posts.py)

A station declares, **per shift**, a required headcount and the named post
filling each slot, with a duty window per slot:

```
requiredMorning: 9    posts.morning: ["Head Guard", "SW Platform", "SE Platform", "Roving", …]
requiredAfternoon: 8  posts.afternoon: ["SW Platform", "SE Platform", "Roving", …]
requiredNight: 3      posts.night: ["Head Guard", "Roving", "Roving"]
```

That number is authoritative in **both** directions: a shift rosters exactly
as many guards as it has posts, so surplus regulars sit the period out
(reported by name) and unmanned posts are reported as holes.

**The stagger ladder.** Posts are not all manned at once. Each shift has a
base window and slots are handed out in rungs of two, each rung starting two
hours later, so cover never drops to one guard while others rotate off:

```
MORNING (base 05:00–14:00)
  Head Guard    05:00–17:00   ← fixed 12h duty, outside the ladder
  SW Platform   05:00–14:00 ┐ rung 0
  SE Platform   05:00–14:00 ┘
  Roving        07:00–16:00 ┐ rung 1
  Ladder        07:00–16:00 ┘
  Concourse     09:00–18:00   rung 2
```

The duty *length* never changes — only the start slides.

**Head guards** count inside their shift's number: the day HG mans the first
Morning slot (0500H–1700H, running well into the afternoon) and the night HG
the first Night slot (1700H–0500H). The **afternoon therefore has no head
guard of its own**.

### 2. Monthly placement — [`placement.py`](backend_python/placement.py) · [`rotation.py`](backend_python/rotation.py)

Placement asks *what does this station need, and who best fills it* — not
*who works here and where do we move them*. Guards list preferred stations,
but stations have fixed sizes, so preference is steered as a **share**, drawn
per cycle so consecutive cycles don't reshuffle to the same quota:

- regular / head guard — **85–90%** land on a station they listed
- reliever — **60–75%**
- a guard who listed nothing is still deployable, at a tenth of the pull

Where the two pull against each other, headcount wins: a post is never left
unmanned to protect a preference. Each station also keeps a few **anchors** —
guards who were already there, so somebody knows the place — and anchor duty
itself rotates.

Stations sit in **three groups along the line**, and a guard may be deployed
one group over but never two:

```
Group 1 ↔ Group 2 ↔ Group 3      (never Group 1 ↔ Group 3)
```

Placement is computed **once per calendar month per group** and reused by both
of that month's generation runs.

### 3. The 15-day roster — [`scheduler.py`](backend_python/scheduler.py)

- Regulars work their fixed station + shift, **13 days on / 2 off**, with
  day-offs staggered so daily coverage stays even
- **Relievers cover day-offs**, and the *same* reliever covers a guard's whole
  run of day-offs — the roster reads `Miguel Aquino — Maria Santos`, not a
  different name against each date. Work is packed onto as few relievers as
  the station's roster slots allow, so the ones who do work land near their
  12 days. Once their own station is covered they top up at the nearest
  station with work left (never more than 4 stops away, which keeps the group
  rule satisfied automatically)
- **Night** is capped at roving night posts plus the night HG; each station
  has one night reliever for the period, and the night pass runs before the
  day pass so it isn't left with nobody
- **Long approved leave** takes a guard off the roster entirely and their post
  is held by another *regular* for the whole period — not a string of
  relievers filling in day by day
- **Head guard gaps** are held by floating substitute head guards, who have no
  home station and are not rotated

### Generation never fails — it files notes — [`schedule_notes.py`](backend_python/schedule_notes.py)

A staffing problem does not abort the run. It produces the best roster the
setup allows and files a structured note carrying three things:

```
subject   what it concerns   "Ayala — Morning"
problem   what happened      one sentence, past tense
fix       what to do         one sentence, imperative
```

filed under a category (rotation · staffing · head guard · cover · assignment
· leave · request) and a severity — **info** (this is what it decided),
**warning** (a post or a person isn't right), **blocker** (somebody is missing
altogether; the schedule is wrong until it's fixed and regenerated). An unnamed
post slot generates as `Undefined`, which is allowed but **blocks publishing**.

---

## Absence, covers and the two windows

The daily flow: a head guard files attendance → an absence appears on the
admin dashboard → the admin opens **Find Replacement** → picks a guard → the
schedule is rewritten and the guard is notified.

**Who is eligible is decided by rules, not by AI** —
[`replacements.py`](backend_python/replacements.py):

1. **Hard filter — conflicts.** Anyone already in any schedule entry that
   date, anyone reported absent, and the absent guard themselves are out
2. **Hard filter — post eligibility.** Morning/Afternoon: relievers or
   regulars fixed to that shift. Night: night regulars only (relievers never
   work nights). HG posts: head guards only
3. **Ranking.** Survivors are scored 0–100 with readable reasons — station
   familiarity (assigned > preferred), type match, lighter 15-day workload.
   A guard who filed a cover offer for that date rises to the top

**The AI sits on top, never in place of it** —
[`ai_service.py`](backend_python/ai_service.py) ·
[`ai_review.py`](backend_python/ai_review.py). Gemini is handed the
already-filtered shortlist and asked who is *best* and why — fatigue across
consecutive duties, fairness when one reliever keeps absorbing every
emergency. Its answer is validated against the shortlist it was given
(a guard who was not in the list cannot come back out of it), cached per
absence and audited. **Every** failure — no key, quota gone, timeout, bad
JSON, failed validation — returns nothing and the screen degrades to its
rule-based self. An emergency cover must not depend on a third party being up.

**The cover window** closes at the post's time-out. Once the duty is over
there is nobody to send, and the backend refuses with 409 so a stale screen
can't slip one through.

**The preparation window** — [`prep_window.py`](backend_python/prep_window.py)
— re-times a duty assigned on short notice. Nobody walks out of their house
straight onto a post:

```
time-in    exactly one hour from the moment the admin assigns it
time-out   the post's own time-out + 2 hours

0500H–1700H post, assigned at 0900H  →  1000H–1900H
```

Assigned with time to spare, the post keeps its real hours — the rule is
`max(the post's own time-in, an hour from now)`, so the adjustment only
appears when the notice is genuinely short. It is not rounded or negotiable:
an 0917H assignment produces a 1017H time-in.

---

## Leave — [`leave.py`](backend_python/leave.py)

Every leave rule lives in one module, whether the leave was filed by a guard
or recorded by the admin.

| Rule | What it enforces |
|---|---|
| **Duration** | Per-type caps — Vacation/Personal, Sick, Other **15d**; Maternity **105d**; Paternity **7d**; Solo Parent **7d**; Bereavement **5d**. Over-cap needs an admin with a recorded supervisor endorsement |
| **Lead time** | A guard's leave must start ≥ **7 days** out *and* after the last day any schedule already covers for their group |
| **Conflict** | A guard may only ask for days no schedule covers yet. The admin *may* record leave over published duties — those duties are returned so they can go through Find Replacement instead of quietly going unmanned |
| **Quota** | **2** open (pending or approved) leaves per calendar year |
| **Cooldown** | **6 months** measured from the **end** of the last approved leave, so a long leave can't shorten the wait for the next |

Anything the admin overrides is recorded on the document with the endorsing
supervisor, so the leave report can always show who authorised what.

---

## Time is Philippine time — [`server_clock.py`](backend_python/server_clock.py)

Every duty window in this system is written in the guards' local clock:
0500H, 1700H, 2100H. The server runs in UTC on Render, which put it eight
hours behind the roster it was policing — a night head guard on post was told
their filing window was closed, and "today's" roster rolled over at 0800H
local. So the server asks `server_clock`, never `datetime.now()`, and the app
settles duty decisions against the server clock rather than the device clock,
so changing a phone's time can't buy a guard anything.

The clock can be frozen (`SCHED_FREEZE_NOW`) so date-sensitive responses stay
deterministic for the golden-file comparison.

---

## Repository layout

```
prototype/
├─ backend_python/            FastAPI + the scheduling engine
│  ├─ api.py                  71 HTTP endpoints
│  ├─ scheduler.py            15-day roster generation
│  ├─ rotation.py             monthly cycle, idempotency
│  ├─ placement.py            demand-driven station placement
│  ├─ station_posts.py        per-shift posts + the stagger ladder
│  ├─ station_pools.py        3 groups, adjacency rule, line order
│  ├─ replacements.py         eligibility + ranking + apply
│  ├─ ai_service.py           the only file that talks to Gemini
│  ├─ ai_review.py            cached, audited AI review
│  ├─ leave.py                every leave rule
│  ├─ prep_window.py          the hour before the post
│  ├─ server_clock.py         Philippine time, freezable
│  ├─ schedule_notes.py       structured generator notes
│  ├─ repositories/           document_repo (mock) | supabase_repo
│  ├─ models/                 Pydantic request models
│  ├─ schema/                 SQL migrations, 001–004
│  ├─ golden/                 58 recorded GET responses
│  ├─ testing_*.py            offline suites
│  ├─ DEV_MODE.md             offline vs Supabase, in detail
│  └─ RENDER.md               deployment, in detail
└─ scheduling_system/         Flutter app (Android · Windows · web)
   ├─ lib/screens/            admin · headguardui/ · securityguardui/
   ├─ lib/services/           api_service, server_clock, duty_clock,
   │                          cover_window, prep_window, session
   ├─ lib/models/             mirrors the API shapes
   └─ config/                 local.json · render.json (API origin)
```

---

## Data

21 Postgres tables ([`schema/`](backend_python/schema/)): `stations`,
`employees`, `users`, `counters`, `rotation_cycles`,
`station_rotation_assignments`, `special_assignments`, `schedules`,
`duty_assignments`, `attendance_reports`, `absence_requests`,
`special_requests`, `leave_requests`, `cover_offers`, `replacements`,
`employee_notifications`, `auth_accounts`, `ai_suggestions`, `auth_sessions`,
`schedule_approvals`, `workflow_notifications`.

Credentials live in **`auth_accounts`**, never on the employee record.
Passwords are **bcrypt** hashes and cannot be read back — a forgotten password
is *replaced*, not looked up (Employee Detail → Password → Reset, which shows
the new one once). The `password` field on an employee record is a mask.

---

## Running it

### Backend

```bash
cd backend_python
pip install -r requirements.txt

# offline — serves everything from mock_data/*.json, no network, writes persist
USE_MOCK_DB=1 uvicorn api:app --reload --port 8000

# against Supabase Postgres
DB_BACKEND=supabase uvicorn api:app --reload --port 8000
```

`DB_BACKEND` is the switch (`mock` | `supabase`). With neither it set nor
`USE_MOCK_DB`, the app **refuses to start** — deliberately, at the earliest
and loudest place. `SUPABASE_DB_URL` must be the **session-pooler** URI; the
direct `db.<ref>.supabase.co` host is IPv6-only and unreachable from Render's
free tier. See [DEV_MODE.md](backend_python/DEV_MODE.md).

### App

The API origin is passed at build time and lives in `config/*.json`, so it is
set in one place rather than retyped:

```bash
cd scheduling_system
flutter pub get

flutter run --dart-define-from-file=config/render.json   # deployed API
flutter run --dart-define-from-file=config/local.json    # uvicorn on this machine
```

Use `API_BASE_URL` (a full origin), not `API_HOST` — the latter hardcodes
`http://` and `:8000` and cannot express an HTTPS origin. In Android Studio,
put `--dart-define-from-file=config/render.json` in the run configuration's
*Additional run args*.

Ships as a sideloaded APK for guards and a zipped Windows folder for the
admin — no app store, so debug signing is fine.

### Deployment

FastAPI on Render (free tier) against Supabase in `ap-northeast-2`. Root
directory `backend_python`, start command
`uvicorn api:app --host 0.0.0.0 --port $PORT`. Full walkthrough and
troubleshooting in [RENDER.md](backend_python/RENDER.md).

---

## Testing

Four gates, which together cover reads, writes, the repository layer and the
response contract. Any one alone leaves a hole.

```bash
USE_MOCK_DB=1 python testing_leave.py     # + the other offline suites
python testing_supabase_repo.py           # repository layer   → 58/58
python golden_capture.py compare          # read contract      → 58/58
python testing_supabase_api.py            # writes (mutates!)  → 33/33
```

The offline suites cover the scheduling logic itself — placement, rotation,
leave, replacement windows, prep window, station rename, special requests and
their conflicts, the server clock, and the AI context and review.

**The golden files** are 58 recorded GET responses, byte-compared after every
change to the data layer. They are date-sensitive by nature (leave windows and
duty status move with the calendar), which is why the server clock can be
frozen — a net that fails every day for reasons nobody can act on stops being
read, and then it is not a net.

---

## Notes and cautions

- **`mock_data/` cannot be regenerated.** It is the live corpus *and* the
  source `load_supabase.py` reads. Keep a zipped backup — restoring from a
  copy is the only recovery there is
- **Rename stations via Edit Station, never delete and re-create.** Stations
  join by *name* in employee and rotation records but by *id* in schedules,
  so a delete + re-create silently orphans the roster
- **CORS is `allow_origins=["*"]`.** Fine for a demo; narrow it before
  anything resembling production
- **`mock_data/`, `.env` and `golden/` are git-ignored** and must stay that
  way — they hold real employee records and the database connection string
- **First request after idle takes ~50s** on Render's free tier. The instance
  is cold-starting, not broken
