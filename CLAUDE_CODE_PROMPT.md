# Prompt for Claude Code: build the QMS Management tab screens

Paste everything below the line into Claude Code, run from the root of the NPO Management System repo, after copying this pack in.

---

You are adding the **QMS Management** tab to this app (Supabase backend). The database, rules, storage and edge functions are already written in this repo:

- `supabase/migrations/*_qms_0*.sql`: tables, rules (as RPC functions), RLS, storage, reminders
- `supabase/tests/qms_release1_test.sql`: SQL acceptance tests
- `src/lib/qms/api.ts` and `types.ts`: supabase-js wrappers for every action
- `docs/qms-management/SPEC.md`: rules summary
- Full spec: https://claude.ai/artifact/Hs7DkErsJeSzo4zPWcxru1 · screens: https://claude.ai/artifact/9Ny7UuY4vA5aqBGXCBGxRt

**Before writing code:**

1. Read the app's structure: framework, router, sidebar/menu component, how the Supabase client is created, how the signed-in user and their role are loaded, the existing Document Control tab, shared UI components (tables, badges, dialogs, file upload, toasts).
2. Check whether Document Control already has database tables. If it does, tell me and propose how to join them to `qms_document` before changing anything (see README "Existing Document Control").
3. Check how users and roles are stored today. Propose how to fill `qms_user_role` from them (trigger or view). Do not hard-code people's names or emails anywhere.
4. Show me the plan (files to add or change) and wait for my go-ahead.

**Then build Release 1 only**, following the app's existing patterns and components:

1. **Menu:** add "QMS Management" directly below "Document Control". Show it only when `api.isQmsGroup()` is true. Also guard the route (redirect if false); the database refuses anyway.
2. **Documents** (screen 1): table of `api.listDocuments()` with search (code, title, process) and filters (type, department, status, class). Status as plain-word badges from `STATUS_BADGE`. "New document" button for the QMS Administrator and HODs → form calling `api.createDocument()`, then `api.uploadDraftFiles()` (Word + PDF).
3. **Document details** (screen 2): fields, Visible to, version history, approval trail (`api.getDocument()`). Buttons by status: Upload files, Submit (`submit`), Send for approval (QMS Administrator, `sendForApproval`), Return (comment required, `returnDoc`), Start new version (`newDraft` with a change summary), Withdraw (QMS Administrator, reason required).
4. **Approvals** (screen 3): `api.myApprovals()` plus, for the QMS Administrator, `api.checkQueue()`. Open the preview PDF (signed URL from `qms-drafts`). Approve (choose Minor or Major when a version is already live) or Return with a required comment.
5. **Board resolution** (screen 4): on a Board-level document waiting for the CEO, upload the signed resolution with number and date → `api.approveWithBoardResolution()`.
6. **Document Control library** (screen 5): switch the existing list to `api.library()` for published documents: Controlled badge, code, version, approved date; Download button calls the `qms-download` edge function with the user's access token.
7. **Audit log** (screen 6): `api.auditLog()` with filters; export to CSV.

**Rules for the UI:**

- Never update `qms_document.status`, `qms_version.status` or approval rows directly; always call the api functions. Show the database error message to the user as it is (they are written in plain words).
- Dates as 24 Nov 2026. Plain words on buttons and badges. No names of people in code, seed data or tests: use roles.
- Do not add Release 2 screens (Overview counters, Reviews due, Acknowledgements, Registers, Audits, Change log) yet; leave menu space for them.

**Done when:**

- `supabase db reset` then `psql … -f supabase/tests/qms_release1_test.sql` prints a pass for every test.
- I can walk through `docs/qms-management/tests/acceptance.feature` T-01 to T-12 in the browser with test users in each role.
- Lint and type checks pass. Commit on a branch `feature/qms-management` and open a pull request describing what changed and anything left in [square brackets].
