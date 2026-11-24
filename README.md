# QMS Management tab: build pack for the NPO Management System

**For:** Head of Operations and Systems (System Developer)
**From:** Operations and Programme Systems Coordinator (QMS Administrator)
**Prepared by:** [Name] · 24 Nov 2026 · Draft 0.1

This pack adds the **QMS Management** tab (below Document Control) to the NPO Management System on Supabase. The database side is done: tables, the approval rules, row level security, storage, reminders and tests. Your part is the screens, linking roles to your existing users, and deployment.

| Read first | Link |
|---|---|
| Development briefing (full spec, 14 sections) | https://claude.ai/artifact/Hs7DkErsJeSzo4zPWcxru1 |
| Clickable prototype of the screens | https://claude.ai/artifact/9Ny7UuY4vA5aqBGXCBGxRt |
| Change request | CR-2026-001 (Batch 5) |
| Procedure the tab enforces | QMS-SOP-GOV-001 Document Control Procedure v2.0 |

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
   `qms-publish` and `qms-notify` check the `x-qms-secret` header instead of a user token.
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
