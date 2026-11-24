# QMS Management tab: build pack for the NPO Management System

**For:** Head of Operations and Systems (System Developer)
**From:** Operations and Programme Systems Coordinator (QMS Administrator)
**Prepared by:** [Name] · 24 Nov 2026 · Draft 0.1

This pack adds the **QMS Management** tab (below Document Control) to the NPO Management System on Supabase. The database side is done: tables, the approval rules, row level security, storage, reminders and tests. A working web app for the screens is now included (next section). What remains for the NPO Management System is linking roles to your existing users and deployment.

| Read first | Link |
|---|---|
| Development briefing (full spec, 14 sections) | https://claude.ai/artifact/Hs7DkErsJeSzo4zPWcxru1 |
| Clickable prototype of the screens | https://claude.ai/artifact/9Ny7UuY4vA5aqBGXCBGxRt |
| Change request | CR-2026-001 (Batch 5) |
| Procedure the tab enforces | QMS-SOP-GOV-001 Document Control Procedure v2.0 |

## The web app (GitHub Pages)

This repository now holds a working web app for the QMS Management tab: `index.html`, `config.js` and the `app/` folder. GitHub Pages publishes it at **https://&lt;your-github-name&gt;.github.io/QMS-Management/**.

* **Demo mode (works straight away).** While `config.js` is empty the site runs on sample data kept in your own browser. The yellow bar lets you act as the QMS Administrator, CEO, an HOD, the Board Treasurer, a staff member or a mentor, so you can walk through the whole approval flow. Nothing is shared or saved online.
* **Live mode.** Put the Supabase Project URL and anon key in `config.js` and the same site signs people in and works on the real database. All rules are enforced by the database (row level security and the `qms_` functions), so the anon key is safe to publish. **Never put the service_role key in `config.js`.**

| Screen | Who sees it |
|---|---|
| Document Control (library of approved documents, download stamped "Uncontrolled copy") | Everyone signed in |
| Documents (Master Document Register, new document, details, upload, submit, new version, withdraw) | QMS group |
| Approvals (my approvals; QMS Administrator check queue; Board resolution upload) | QMS group |
| Audit log (filter, export CSV) | QMS Administrator, CEO, Board Treasurer, Head of Operations and Systems |
| People and roles | QMS Administrator, Head of Operations and Systems |

### 1. Switch on GitHub Pages

1. Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Delete `.github/workflows/jekyll-gh-pages.yml` if it is still there (open it → ⋯ → Delete file). Only `static.yml` should publish.
3. **Actions** tab: wait for "Deploy QMS Management web app to Pages" to turn green (about 1 minute). Open the link it shows.

### 2. Go live with Supabase (about 20 minutes, no command line)

1. **Create the project.** supabase.com → New project (region: South Africa (Cape Town) if offered, otherwise the nearest one). Keep the database password safe.
2. **Create the database.** SQL Editor → New query → paste all of `supabase/setup_all.sql` → Run. It should finish with "Success". (It is migrations 01 to 06 plus `seed.sql`: 11 departments, 39 processes, the retention schedule, settings, public holidays and the 44 documents from Batches 1 to 5.)
3. **Add people.** Authentication → Users → Add user → Create new user, tick *Auto Confirm User*. One per person, work e-mail and a temporary password.
4. **Give the first roles.** SQL Editor → paste `supabase/setup_first_admin.sql`, change the e-mail addresses, Run. After this, the QMS Administrator gives the other roles in the app (People and roles).
5. **Point sign-in links at the site.** Authentication → URL Configuration → Site URL = your GitHub Pages address; add the same address under Redirect URLs.
6. **Connect the site.** Project Settings → API (or Data API): copy the **Project URL** and the **anon public** key. In GitHub open `config.js` → ✏️ Edit → paste both values between the quotes → Commit changes. Pages republishes in about a minute.
7. **Edge functions (controlled PDFs and downloads).** Edge Functions → Deploy a new function → *Via editor*. Create three functions with these exact names and paste the matching file:
   * `qms-publish` ← `supabase/functions/qms-publish/index.ts` (stamps the approved PDF "Controlled" and publishes it; the app calls it after each approval)
   * `qms-download` ← `supabase/functions/qms-download/index.ts` (gives staff the PDF stamped "Uncontrolled copy" with the date)
   * `qms-notify` ← `supabase/functions/qms-notify/index.ts` (optional: Teams or e-mail notifications)

   Each file is self-contained, so it can be pasted as is. Optional secrets (Edge Functions → Secrets): `APP_URL` and `APP_ORIGIN` = your Pages address; `TEAMS_WEBHOOK_URL` or `RESEND_API_KEY` + `MAIL_FROM` for notifications; `QMS_FUNCTION_SECRET` for the scheduler. Developers can use the CLI instead (step 5 under "Setup steps" below).
8. **Optional: reminders.** Database → Extensions: enable `pg_cron` and `pg_net`, then run `supabase/setup_schedule.sql` with your project ref and secret.
9. **Test.** Sign in as the QMS Administrator. Open a document, Edit details (code and process), Upload files (Word + PDF), Submit, Send for approval. Sign in as the approver and approve. The document appears in Document Control. Then walk through `docs/qms-management/tests/acceptance.feature` T-01 to T-12.

### Checked before hand-over (24 Nov 2026)

* `supabase/tests/qms_release1_test.sql` run on PostgreSQL 16 with Supabase-style `auth` and `storage` schemas: T-01 to T-12, R-01/R-02, reminders and the new People-and-roles checks (W-01 to W-04) all pass. `setup_all.sql` was also run on an empty database.
* Edge functions type-check with Deno.
* The web app was walked through end to end in demo mode in Chromium: create/edit, upload, submit, check, approve (HOD and Board resolution), library, download, audit log, roles, and staff blocked from QMS screens.
* Not tested here: a real Supabase project (needs your account). Steps 2 to 9 above are the live test.

## What is in the pack

```
supabase/
  migrations/
    20261124090000_qms_01_schema.sql      tables, types, indexes
    20261124090100_qms_02_functions.sql   the rules: create, submit, route, return, approve, withdraw, audit
    20261124090200_qms_03_rls.sql         row level security, column limits, views for the screens
    20261124090300_qms_04_storage.sql     buckets qms-drafts and qms-published
    20261124090400_qms_05_reminders.sql   daily reminders and escalations
  seed.sql                                departments, 39 processes, retention schedule, settings,
                                          SA public holidays, and the 44 documents from Batches 1 to 5
  tests/qms_release1_test.sql             T-01 to T-12 plus rule and reminder checks (rolls back)
  functions/
    qms-publish/   stamps the approved PDF "Controlled", stores it and its SHA-256 hash
    qms-download/  checks access, returns the PDF stamped "Uncontrolled copy" with the date
    qms-notify/    sends waiting notifications (Teams first, email fallback)
    _shared/
src/lib/qms/
  types.ts         TypeScript types for the tables and views
  api.ts           supabase-js wrappers the screens call (one function per action)
docs/qms-management/
  SPEC.md                    rules and approval matrix in one page
  CLAUDE_CODE_PROMPT.md      paste into Claude Code to build the screens in this repo
  tests/acceptance.feature   T-01 to T-20 as plain-English test scripts
```

Copy the folders into the repo root. If the repo already has `supabase/migrations`, keep the file names: they sort after existing migrations by date.

Added for the web app:

```
index.html, config.js, app/          the web app published by GitHub Pages
supabase/setup_all.sql               migrations 01-06 + seed in one file for the SQL Editor
supabase/setup_first_admin.sql       give the first people their roles by e-mail
supabase/setup_schedule.sql          optional reminders and notifications (pg_cron)
supabase/migrations/..._qms_06_web_app.sql   People and roles, e-mails in the trail, API grants
docs/qms-documents/                  the QMS Word and Excel drafts that were in the upload
```

## How the rules are enforced

All status changes go through database functions (`supabase.rpc('qms_approve', …)`), not table updates. App users cannot update `status`, version numbers or approvals directly (column grants), and drafts never leave the QMS group (row level security). So a screen bug cannot break a rule; the screen just shows the error message the database returns. Examples:

- Nobody approves their own document; the step moves up (HOD → CEO; CEO → Board Treasurer).
- Return needs a comment. Governance policies and the QMS Manual need the signed Board resolution.
- Approving 1.1 makes 1.0 Obsolete in the same transaction.
- Every change is written to `qms_audit_log`, which cannot be edited or deleted.

## Setup steps

1. **Branch.** `git checkout -b feature/qms-management`
2. **Check for name clashes.** The pack uses the `qms_` prefix in `public`. If Document Control already has tables, see "Existing Document Control" below.
3. **Apply locally.**
   ```bash
   supabase start
   supabase db reset          # runs migrations + seed.sql
   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -v ON_ERROR_STOP=1 -f supabase/tests/qms_release1_test.sql
   ```
   Every test prints `NOTICE: T-xx pass`. The test rolls back, so nothing is left behind.
4. **Link roles to users.** `qms_user_role` holds who is QMS Administrator, CEO, HOD (per department), Board Treasurer, Head of Operations and Systems, staff and mentors. If the system already keeps roles (for example a `profiles` table or Entra groups), either fill this table from them with a trigger, or replace the table with a view that returns the same columns (`user_id, role, department, programme`). Use roles, not names.
5. **Edge functions.**
   ```bash
   supabase secrets set QMS_FUNCTION_SECRET=<long random string> APP_URL=<https://npo.system.url> APP_ORIGIN=<same>
   supabase secrets set TEAMS_WEBHOOK_URL=<Teams Workflows webhook>   # or RESEND_API_KEY + MAIL_FROM, or connect your existing sender
   supabase functions deploy qms-download
   supabase functions deploy qms-publish --no-verify-jwt
   supabase functions deploy qms-notify  --no-verify-jwt
   ```
   `qms-publish` and `qms-notify` check the `x-qms-secret` header; `qms-publish` also accepts a signed-in member of the QMS group (the web app calls it after each approval). Each function file is self-contained (no `_shared` import), so it can also be pasted into the Supabase dashboard editor.
6. **Schedule** (Database → Extensions: enable `pg_cron` and `pg_net`):
   ```sql
   select cron.schedule('qms-reminders', '30 5 * * 1-5', $$select public.qms_run_reminders()$$);   -- 07:30 SA time
   select cron.schedule('qms-jobs', '*/5 * * * *', $$
     select net.http_post(url := '<project-url>/functions/v1/qms-publish', headers := '{"x-qms-secret":"<secret>"}'::jsonb);
     select net.http_post(url := '<project-url>/functions/v1/qms-notify',  headers := '{"x-qms-secret":"<secret>"}'::jsonb);
   $$);
   ```
   Keep the secret in Supabase Vault rather than in the job text if you prefer.
7. **December closure.** Add the closure days to `qms_non_working_day` (example in `seed.sql`) so reminders and working-day counts skip them.
8. **Build the screens** with `docs/qms-management/CLAUDE_CODE_PROMPT.md` and `src/lib/qms/api.ts`.
9. **Push to staging**: `supabase db push`, then user acceptance testing with the QMS Administrator (T-01 to T-12 in `acceptance.feature`).

## Uploading a document (how the files work)

The owner uploads the **Word file and a PDF of it** (Word: File → Save as PDF) for each draft: `api.uploadDraftFiles()`. On approval, `qms-publish` stamps that PDF "CONTROLLED DOCUMENT | code | version | approved date" on every page and saves it to `qms-published`. Staff download through `qms-download`, which stamps "Uncontrolled copy when printed or downloaded" and the date. Converting Word to PDF on the server is not needed for Release 1.

## Existing Document Control

The briefing says to add columns to the existing Document Control tables rather than replace them. This pack creates its own `qms_document` table so it can be tested on its own. Two ways to join them:

- **Recommended:** make `qms_document` the table behind both tabs, and move the 129 existing Document Control rows into it in Phase 3 (migration steps are in the briefing, section 12).
- **Or:** keep the existing table and add the `qms_` columns to it; then point the foreign keys in migration 01 at it.

## Open decisions that affect the build

| No. | Decision | Who | In the pack |
|---|---|---|---|
| D-01 | Release 1 date (asked: before the December closure) | Head of Operations and Systems | — |
| D-02 | Who approves class 2 programme materials | CEO | `programme_owner` role for now |
| D-05 | Reminder and escalation days | Head of Operations and Systems, CEO | `qms_settings` (3 and 10) |
| D-06 | File store: Supabase Storage or SharePoint | Head of Operations and Systems | Supabase Storage |
| D-11 | Recode the QMS-05 asset documents to QMS-TYPE-DOMAIN-### | QMS Administrator | Seeded with `previous_code`; they cannot be submitted until recoded |

Values in [square brackets] anywhere in the pack are still to be decided.

**Contact for process questions:** Operations and Programme Systems Coordinator (QMS Administrator).
