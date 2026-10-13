# Schedule approval workflow

Assistant Security and Area Commander use the desktop app. Both oversee all
stations. Officials are accounts in `users`, separate from the `employees`
roster, so the scheduling engine never assigns them guard duties.

## Using the workflow

1. Sign in as admin and open **Official Accounts**. Create an account for
   Assistant Security and another for Area Commander. Share the generated
   passwords; officials can change their password from **Profile**.
2. Generate and check schedules for **all active stations**, using the same
   start/end dates. Generation still works by station or group.
3. Open **Period Approvals**, select the period, and choose **Submit for
   Approval**. Submission requires one complete schedule per active station
   and rejects missing days, empty schedules and undefined posts.
4. Assistant Security opens **Review & Decide**, checks the station rosters
   and scheduling notes, then approves or returns the period with a comment.
   **View Every Day's Assignments** shows the exact daily duties.
5. After Assistant Security approves, Area Commander can approve or return
   the same submission. Final approval publishes every station together and
   notifies its guards. Officials cannot edit assignments or publish directly.
6. The admin can export one station or the entire approved period from
   **Reports**. Every export checks the backend again, uses the current
   authorized roster, and prints the actual reviewers, approval times in
   Philippine time, submission reference and revision number.

**Approval Alerts** is the inbox for submissions, decisions, revisions and
emergency amendments. It refreshes every 30 seconds while the app is open.
The admin also sees decisions under **Period Approvals**.

## Revisions and emergencies

Pending and approved schedules cannot be edited, overwritten by generation,
deleted, or changed through a station rename/deletion. The admin uses
**Start Revision** with a reason to withdraw the entire period, unlock its
drafts and notify guards if it was published. After correcting the drafts,
the admin submits again; both officials must approve the new submission.
Returning a submission requires a comment and unlocks the drafts directly.

An emergency replacement on a published schedule takes effect immediately.
The existing replacement checks still apply. The admin enters the reason;
the system records the authenticated admin, time, reason, replacement and
before/after duties. Both officials receive an alert. The original submitted
rosters and decisions remain unchanged in history. Updated PDFs identify the
period's emergency amendments separately from the original approvals.

Each submission is a preserved snapshot. The backend compares the current
rosters with the reviewed version before a decision or export. Stale
decisions, duplicate clicks and unexpected schedule changes are refused.
Final publication, notifications and the decision commit together. PostgreSQL
uses a transaction and a shared advisory lock across backend workers for
schedule changes; the offline backend serializes writes and rolls back failed
operations in memory.

## Deploying this change

The implementation does **not** apply SQL to Supabase automatically.

1. Apply [schema/005_schedule_approvals.sql](schema/005_schedule_approvals.sql)
   to the same Supabase project as migrations 001–004, **before** starting the
   updated backend. It adds approval history, session and notification tables,
   official display names, schedule approval references and replacement audit
   fields. It does not create accounts or alter existing publication states.
2. Deploy the updated backend and rebuild the Flutter clients. Update the
   desktop app and guard/head-guard clients together: authenticated requests
   now carry a session token, so older clients cannot call protected routes.
3. Sign in again. Old locally saved username/role sessions have no token and
   return to the login screen. Tokens last seven days; password changes,
   official password resets and deactivation revoke previous sessions.
4. Create the official accounts, then follow the workflow above.

Existing published schedules stay available to their guards. They carry no
fabricated approval and cannot be exported as an approved report. To put one
through the new workflow, submit its complete period; submission withdraws
its existing publication until both officials approve. Existing PDFs already
exported are unaffected.

The existing signatory settings now apply to **leave reports**. Schedule
reports obtain approval names from the authenticated decisions. The admin's
Prepared By name is captured when the period is submitted.

## Local validation

The backend integration suite uses synthetic data and credentials in temporary
workspace directories and never changes `mock_data` or Supabase:

```powershell
cd backend_python
.\.venv\Scripts\python.exe testing_schedule_approvals.py
```

Flutter workflow tests mock the API and PDF sharing:

```powershell
cd scheduling_system
flutter test --no-pub test/approval_workflow_test.dart
```

The tests cover sequential and concurrent decisions, full-period coverage,
role restrictions, guard visibility, return/resubmit, rollback on failed
publication, revision history, emergency replacements, official account
creation/login/password reset, desktop layouts and PDF export restrictions.
Run the existing navigation/login/head-guard/settings tests when changing
shared session or desktop navigation code.
