-- =====================================================================
-- QMS Management tab: row level security
-- Reads are filtered by role. Direct writes are refused for app users;
-- every change goes through the functions in migration 02 (briefing s.11:
-- server-side checks on every call; screens only hide what the server refuses).
-- =====================================================================

alter table public.qms_user_role        enable row level security;
alter table public.qms_department       enable row level security;
alter table public.qms_process          enable row level security;
alter table public.qms_record_type      enable row level security;
alter table public.qms_settings         enable row level security;
alter table public.qms_non_working_day  enable row level security;
alter table public.qms_document         enable row level security;
alter table public.qms_version          enable row level security;
alter table public.qms_approval_step    enable row level security;
alter table public.qms_change_request   enable row level security;
alter table public.qms_review_extension enable row level security;
alter table public.qms_acknowledgement  enable row level security;
alter table public.qms_notification     enable row level security;
alter table public.qms_audit_log        enable row level security;
alter table public.qms_sequence         enable row level security;

-- Lists: everyone signed in can read; QMS Administrator maintains
create policy qms_lists_read on public.qms_department      for select to authenticated using (true);
create policy qms_lists_read on public.qms_process         for select to authenticated using (true);
create policy qms_lists_read on public.qms_record_type     for select to authenticated using (true);
create policy qms_lists_read on public.qms_non_working_day for select to authenticated using (true);
create policy qms_lists_write on public.qms_department      for all to authenticated
  using (public.qms_has_role('qms_admin')) with check (public.qms_has_role('qms_admin'));
create policy qms_lists_write on public.qms_process         for all to authenticated
  using (public.qms_has_role('qms_admin')) with check (public.qms_has_role('qms_admin'));
create policy qms_lists_write on public.qms_record_type     for all to authenticated
  using (public.qms_has_role('qms_admin')) with check (public.qms_has_role('qms_admin'));
create policy qms_lists_write on public.qms_non_working_day for all to authenticated
  using (public.qms_has_role('qms_admin')) with check (public.qms_has_role('qms_admin'));

create policy qms_settings_read  on public.qms_settings for select to authenticated using (public.qms_is_qms_group());
create policy qms_settings_write on public.qms_settings for update to authenticated
  using (public.qms_has_role('qms_admin')) with check (public.qms_has_role('qms_admin'));

-- Roles: a user sees their own; QMS group sees all; Head of Operations and Systems
-- with the QMS Administrator changes access (logged by the audit trigger)
create policy qms_roles_read on public.qms_user_role for select to authenticated
  using (user_id = auth.uid() or public.qms_is_qms_group());
create policy qms_roles_write on public.qms_user_role for all to authenticated
  using (public.qms_has_role('head_ops_systems') or public.qms_has_role('qms_admin'))
  with check (public.qms_has_role('head_ops_systems') or public.qms_has_role('qms_admin'));

-- Documents: QMS group sees all; others only what is published and visible to them
create policy qms_document_read on public.qms_document for select to authenticated
  using (public.qms_can_read_document(id));

-- Metadata edits by the QMS Administrator (code, visible_to, owner, process, review date ...)
create policy qms_document_admin_update on public.qms_document for update to authenticated
  using (public.qms_has_role('qms_admin')) with check (public.qms_has_role('qms_admin'));

-- Versions: drafts never leave the QMS group (R-09); others see only the live version
create policy qms_version_read on public.qms_version for select to authenticated
  using (
    public.qms_is_qms_group()
    or (status = 'Approved'
        and exists (select 1 from public.qms_document d
                    where d.id = document_id and d.published_version_id = qms_version.id
                      and public.qms_can_read_document(d.id)))
  );

-- Owner may attach the uploaded file paths to their own draft
create policy qms_version_draft_files on public.qms_version for update to authenticated
  using (status in ('Draft','Returned') and (author_id = auth.uid() or public.qms_has_role('qms_admin')))
  with check (status in ('Draft','Returned'));

create policy qms_steps_read on public.qms_approval_step for select to authenticated
  using (public.qms_is_qms_group());

create policy qms_cr_read on public.qms_change_request for select to authenticated
  using (public.qms_is_qms_group());

create policy qms_ext_read on public.qms_review_extension for select to authenticated
  using (public.qms_is_qms_group());

create policy qms_ack_read on public.qms_acknowledgement for select to authenticated
  using (user_id = auth.uid() or public.qms_is_qms_group());

create policy qms_notification_read on public.qms_notification for select to authenticated
  using (recipient = auth.uid() or public.qms_has_role('qms_admin'));

create policy qms_audit_read on public.qms_audit_log for select to authenticated
  using (public.qms_has_role('qms_admin') or public.qms_has_role('ceo')
         or public.qms_has_role('board_treasurer') or public.qms_has_role('head_ops_systems'));

-- No insert/update/delete policies on the other tables: app users change them only through the functions.
revoke all on public.qms_audit_log from anon, authenticated;
grant select on public.qms_audit_log to authenticated;
revoke all on public.qms_sequence from anon, authenticated;

-- Functions: signed-in users only
revoke execute on all functions in schema public from anon;
grant execute on function
  public.qms_create_document(text, smallint, public.qms_doc_type, text, text, text, text, text, text, boolean, boolean, text[], text),
  public.qms_new_draft(uuid, text, text, boolean, uuid),
  public.qms_submit(uuid),
  public.qms_send_for_approval(uuid),
  public.qms_return(uuid, text),
  public.qms_approve(uuid, public.qms_change_type, text, text, date, date),
  public.qms_withdraw(uuid, text),
  public.qms_extend_review(uuid, date, text),
  public.qms_mark_reviewed(uuid),
  public.qms_acknowledge(uuid),
  public.qms_log_change_request(text, text),
  public.qms_can_decide(uuid),
  public.qms_can_read_document(uuid),
  public.qms_is_qms_group(),
  public.qms_has_role(public.qms_role, text)
to authenticated;

-- ---------- Handy views for the screens ----------------------------------------
-- My approvals (screen 3)
create or replace view public.qms_my_approvals with (security_invoker = true) as
select s.id as step_id, v.id as version_id, d.id as document_id, d.code, d.title, d.doc_type,
       d.department, v.version_no, v.submitted_at, s.required_role, s.required_department,
       public.qms_working_days_between(v.submitted_at::date, current_date) as working_days_waiting
from public.qms_approval_step s
join public.qms_version v on v.id = s.version_id
join public.qms_document d on d.id = v.document_id
where s.kind = 'Approve' and s.decision = 'Pending' and public.qms_can_decide(s.id);

-- Check queue for the QMS Administrator
create or replace view public.qms_check_queue with (security_invoker = true) as
select v.id as version_id, d.id as document_id, d.code, d.title, d.department, v.version_no,
       v.submitted_at, public.qms_add_working_days(v.submitted_at::date, 5) as check_due
from public.qms_version v join public.qms_document d on d.id = v.document_id
where v.status = 'Submitted';

-- Reviews due in 30 days or overdue (screen 8)
create or replace view public.qms_reviews_due with (security_invoker = true) as
select d.id, d.code, d.title, d.department, d.owner_role, d.next_review_date,
       (d.next_review_date < current_date) as overdue
from public.qms_document d
where d.status = 'Approved' and d.next_review_date <= current_date + 30;

-- Library (Document Control): what the signed-in user may read
create or replace view public.qms_library with (security_invoker = true) as
select d.id, d.code, d.title, d.doc_class, d.doc_type, d.department, d.process, d.programme,
       v.version_no, d.approved_date, d.next_review_date, v.published_pdf_path,
       (d.doc_class = 1) as controlled
from public.qms_document d
join public.qms_version v on v.id = d.published_version_id
where v.status = 'Approved';

grant select on public.qms_my_approvals, public.qms_check_queue, public.qms_reviews_due, public.qms_library to authenticated;

-- ---------- Column-level write limits -------------------------------------------
-- Supabase grants all table privileges to authenticated by default; narrow them so a
-- policy that allows an UPDATE cannot be used to change status, versions or approvals.
revoke insert, update, delete on all tables in schema public from anon;
revoke insert, update, delete on
  public.qms_document, public.qms_version, public.qms_approval_step, public.qms_change_request,
  public.qms_review_extension, public.qms_acknowledgement, public.qms_notification, public.qms_settings
from authenticated;

grant update (code, previous_code, title, domain, department, process, programme, owner_role, owner_user,
              visible_to, is_governance, is_cross_department, record_type, is_external, licence_note)
  on public.qms_document to authenticated;          -- policy limits this to the QMS Administrator
grant update (source_path, pdf_path, change_summary, is_significant, change_request_id)
  on public.qms_version to authenticated;           -- policy limits this to the author's own draft
grant update (value) on public.qms_settings to authenticated;
