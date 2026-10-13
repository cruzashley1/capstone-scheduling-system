# Schedule approval workflow

Assistant Security and Area Commander use the desktop app. Both oversee all
stations. Officials are accounts in `users`, separate from the `employees`
roster, so the scheduling engine never assigns them guard duties.

## Using the workflow

1. Sign in as admin and open **Settings > Company Info > Official Accounts**. Create an account for
   Assistant Security and another for Area Commander. Share the generated
   passwords; officials can change their password from **Profile**.
2. Generate and check schedules for **all active stations**, using the same
   start/end dates. Generation still works by station or group.
3. Open **Schedule Management > Period Approvals** (beside Delete), select
   the period, and check the readiness panel. It shows how many active stations
   are ready, names missing stations, and identifies incomplete schedules.
   **Submit for Approval** becomes available when the whole period is complete.
   Submission requires one complete schedule per active station and rejects
   missing days, empty schedules and undefined posts. The total follows the
   active station list rather than a fixed count.
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

For admins, **Notifications > Approval Alerts** is the tab immediately after
**Leave Requests**. Officials keep their **Approval Alerts** shortcut. The
inbox covers submissions, decisions, revisions and emergency amendments and
refreshes every 30 seconds while open. Approval alerts also contribute to the
admin's Notifications badge. Opening an alert displays the review screen with
loading feedback immediately; repeated taps cannot stack review screens.
The admin also sees decisions under **Period Approvals**.

## Official profiles

Officials have a desktop sidebar with their name, role and review stage.
**Profile** has three sections:

- **Account Overview** shows the official's full name, username, assigned role,
  all-station coverage and responsibilities. Officials can copy their username
  and edit their own full name; username and role cannot be changed here.
  New decisions use the updated name. Existing decisions retain their original
  names and timestamps.
- **My Decisions** lists only approvals and returns made by the signed-in
  account, newest first, with counts, filters, comments and links to the original
  submissions. The current submission status is shown separately from the
  official's recorded decision.
- **Security** contains password change, confirmation and visibility controls.
  Changing the password revokes other sessions and refreshes the current session.
  Password inputs clear on success or when leaving the Security section.

These profile changes require the updated backend's `PUT /account` route and
the rebuilt Flutter client. No additional SQL is needed after migration 005.
Period Approvals and Approval Alerts retain their existing screens and behavior.

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
flutter test --no-pub test/approval_navigation_test.dart test/navigation_layout_test.dart
flutter test --no-pub test/official_profile_test.dart
```

The tests cover sequential and concurrent decisions, full-period coverage,
role restrictions, guard visibility, return/resubmit, rollback on failed
publication, revision history, emergency replacements, official account
creation/login/password reset, desktop layouts and PDF export restrictions.
Profile tests also cover own-name updates, preserved approval names, role
restrictions, personal decision history, password validation and repeated clicks
while requests are pending.
Run the existing navigation/login/head-guard/settings tests when changing
shared session or desktop navigation code.
