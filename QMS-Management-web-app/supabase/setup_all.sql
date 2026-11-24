-- =====================================================================
-- QMS Management: ONE-FILE SETUP for the Supabase SQL Editor
-- Supabase > SQL Editor > New query > paste this whole file > Run.
-- Run it ONCE on a new project. It is migrations 01 to 06 plus seed.sql,
-- in order (generated from supabase/migrations and supabase/seed.sql).
-- Then run setup_first_admin.sql with your own e-mail address.
-- =====================================================================


-- >>>>>>>>>> migrations/20261124090000_qms_01_schema.sql
-- =====================================================================
-- QMS Management tab: schema
-- Angels Resource Centres NPO, NPO Management System (Supabase / Postgres)
-- Source: QMS Management Tab Development Briefing; CR-2026-001;
--         QMS-SOP-GOV-001 Document Control Procedure v2.0
-- All writes go through the RPC functions in migration 02.
-- Tables are in public with the qms_ prefix so PostgREST exposes them.
-- =====================================================================

-- ---------- Types -----------------------------------------------------
create type public.qms_role as enum (
  'qms_admin',          -- Operations and Programme Systems Coordinator (QMS Administrator)
  'ceo',
  'hod',                -- needs a department (HR = HOD HR; REP = HOD Reports)
  'board_treasurer',
  'head_ops_systems',   -- system owner
  'programme_owner',    -- class 2 materials (needs a programme)
  'mentor',             -- needs a programme
  'staff'
);

create type public.qms_doc_type   as enum ('MAN','POL','MAP','SOP','GUI','FRM','TMP','REG','MAT','REC');
create type public.qms_doc_status as enum ('Draft','Submitted','In review','Returned','Approved','Obsolete');
create type public.qms_approver   as enum ('hod','ceo','board','board_treasurer','programme_owner');
create type public.qms_change_type as enum ('Minor','Major');
create type public.qms_step_kind  as enum ('Check','Approve');
create type public.qms_step_decision as enum ('Pending','Approved','Returned');

-- ---------- Who holds which role ---------------------------------------
-- If the NPO Management System already has a profiles/roles table, replace
-- this table with a view over it that returns the same columns.
create table public.qms_user_role (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        public.qms_role not null,
  department  text,          -- for hod and staff
  programme   text,          -- for mentor and programme_owner
  created_at  timestamptz not null default now(),
  unique (user_id, role, department, programme)
);
create index on public.qms_user_role (user_id);

-- ---------- Lists (maintained by the QMS Administrator) -----------------
create table public.qms_department (
  code text primary key,     -- e.g. OPS, FIN, HR, PR, REP, EXE, TD
  name text not null
);

create table public.qms_process (
  code        text primary key,   -- Level 2 process code, e.g. FIN-01, QMS-01
  name        text not null,
  department  text references public.qms_department(code)
);

create table public.qms_record_type (
  code              text primary key,
  name              text not null,
  retention_years   int  not null,
  retention_trigger text not null   -- e.g. 'after superseded', 'after last transaction'
);

create table public.qms_settings (
  key   text primary key,
  value jsonb not null,
  note  text
);

-- South African public holidays and the December closure (working-day maths)
create table public.qms_non_working_day (
  day    date primary key,
  reason text not null
);

-- ---------- Documents --------------------------------------------------
create table public.qms_document (
  id                    uuid primary key default gen_random_uuid(),
  code                  text unique,                 -- class 1: QMS-TYPE-DOMAIN-###
  previous_code         text,                        -- recoded documents
  title                 text not null,
  doc_class             smallint not null check (doc_class in (1,2,3)),
  doc_type              public.qms_doc_type not null,
  domain                text,
  department            text references public.qms_department(code),
  process               text references public.qms_process(code),
  programme             text,
  is_governance         boolean not null default false,  -- Board approves
  is_cross_department   boolean not null default false,  -- CEO approves
  owner_role            text not null,
  owner_user            uuid references auth.users(id),
  current_version_id    uuid,                        -- latest version (may be a draft)
  published_version_id  uuid,                        -- the one live approved version
  status                public.qms_doc_status not null default 'Draft',
  approved_date         date,
  next_review_date      date,
  visible_to            text[] not null default array['all_staff'],
       -- values: all_staff | dept:<code> | mentors | mentors:<programme> | hods | qms_group
  record_type           text references public.qms_record_type(code),
  retention_until       date,
  is_external           boolean not null default false,
  licence_note          text,                        -- class 2 outside materials
  withdrawn_reason      text,
  created_at            timestamptz not null default now(),
  created_by            uuid default auth.uid(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid default auth.uid(),
  constraint qms_title_no_version_marks
    check (title !~* '(\mrev ?\d|\mv\d+(\.\d+)?\M|\(\d+\)|- ?copy\M|\mfinal\s*(draft|version)?\s*$)')
);
create index on public.qms_document (doc_class, status);
create index on public.qms_document (department);
create index on public.qms_document (process);
create index on public.qms_document (next_review_date);

create table public.qms_version (
  id                    uuid primary key default gen_random_uuid(),
  document_id           uuid not null references public.qms_document(id) on delete restrict,
  draft_seq             int  not null,               -- shown as 0.<draft_seq> while a draft
  major                 int,                         -- set on approval
  minor                 int,
  version_no            text generated always as (
                          case when major is null then '0.' || draft_seq
                               else major || '.' || minor end) stored,
  status                public.qms_doc_status not null default 'Draft',
  source_path           text,                        -- storage: qms-drafts/<doc>/<version>/source.docx
  pdf_path              text,                        -- storage: qms-drafts/<doc>/<version>/preview.pdf
  published_pdf_path    text,                        -- storage: qms-published/<doc>/<version>.pdf
  pdf_sha256            text,
  change_summary        text,
  change_type           public.qms_change_type,
  change_request_id     uuid,
  is_significant        boolean not null default false,
  author_id             uuid references auth.users(id) default auth.uid(),
  submitted_by          uuid references auth.users(id),
  submitted_at          timestamptz,
  approved_by           uuid references auth.users(id),
  approved_at           timestamptz,
  board_resolution_path text,
  board_resolution_no   text,
  board_resolution_date date,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (document_id, draft_seq),
  constraint qms_no_self_approval check (approved_by is null
     or (approved_by is distinct from author_id and approved_by is distinct from submitted_by))
);
create index on public.qms_version (document_id);
create index on public.qms_version (status);

alter table public.qms_document
  add constraint qms_document_current_fk   foreign key (current_version_id)   references public.qms_version(id),
  add constraint qms_document_published_fk foreign key (published_version_id) references public.qms_version(id);

create table public.qms_approval_step (
  id                  uuid primary key default gen_random_uuid(),
  version_id          uuid not null references public.qms_version(id) on delete cascade,
  kind                public.qms_step_kind not null,
  required_role       public.qms_approver,          -- for Approve steps
  required_department text,                         -- for hod
  decision            public.qms_step_decision not null default 'Pending',
  comment             text,
  decided_by          uuid references auth.users(id),
  decided_at          timestamptz,
  created_at          timestamptz not null default now(),
  constraint qms_return_needs_comment
    check (decision <> 'Returned' or coalesce(length(trim(comment)),0) > 0)
);
create index on public.qms_approval_step (version_id);
create index on public.qms_approval_step (decision, required_role, required_department);

create table public.qms_change_request (
  id           uuid primary key default gen_random_uuid(),
  ref          text unique not null,                -- CR-yyyy-nnn
  title        text not null,
  significance text not null check (significance in ('Minor','Significant')),
  status       text not null default 'Logged'
               check (status in ('Logged','Assessed','Approved','Rejected','Implemented','Verified','Closed')),
  approved_by  uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  created_by   uuid default auth.uid()
);
alter table public.qms_version
  add constraint qms_version_cr_fk foreign key (change_request_id) references public.qms_change_request(id);

create table public.qms_review_extension (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references public.qms_document(id),
  old_date     date,
  new_date     date not null,
  reason       text not null check (length(trim(reason)) > 0),
  agreed_by    uuid not null references auth.users(id),
  created_at   timestamptz not null default now()
);

create table public.qms_acknowledgement (           -- Release 2
  id              uuid primary key default gen_random_uuid(),
  version_id      uuid not null references public.qms_version(id),
  user_id         uuid not null references auth.users(id),
  due_at          date not null,
  acknowledged_at timestamptz,
  unique (version_id, user_id)
);

-- Outbox read by the notification sender (Teams first, email fallback)
create table public.qms_notification (
  id          bigint generated always as identity primary key,
  event       text not null,
  recipient   uuid references auth.users(id),
  recipient_role public.qms_role,
  recipient_department text,
  subject_id  uuid,
  message     text not null,
  channel     text not null default 'teams',
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  error       text
);
create index on public.qms_notification (sent_at) where sent_at is null;

-- Insert-only audit log (R-16)
create table public.qms_audit_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  user_id     uuid default auth.uid(),
  action      text not null,
  table_name  text not null,
  record_id   text,
  version_no  text,
  before      jsonb,
  after       jsonb
);
create index on public.qms_audit_log (table_name, record_id);
create index on public.qms_audit_log (user_id, at);

-- Yearly sequences for system numbers (CR-yyyy-nnn and others)
create table public.qms_sequence (
  name  text not null,
  year  int  not null,
  last  int  not null default 0,
  primary key (name, year)
);


-- >>>>>>>>>> migrations/20261124090100_qms_02_functions.sql
-- =====================================================================
-- QMS Management tab: business rules as database functions
-- Every state change goes through these SECURITY DEFINER functions, so the
-- rules hold whatever screen or script calls them (briefing section 9).
-- Call from the app with supabase.rpc('qms_submit', { p_version_id }) etc.
-- =====================================================================

-- ---------- Role helpers ----------------------------------------------
create or replace function public.qms_has_role(p_role public.qms_role, p_department text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.qms_user_role r
    where r.user_id = auth.uid()
      and r.role = p_role
      and (p_department is null or r.department = p_department)
  );
$$;

create or replace function public.qms_user_has_role(p_user uuid, p_role public.qms_role, p_department text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.qms_user_role r
    where r.user_id = p_user and r.role = p_role
      and (p_department is null or r.department = p_department)
  );
$$;

-- QMS group = who may open the QMS Management tab (briefing section 3)
create or replace function public.qms_is_qms_group()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.qms_user_role r
    where r.user_id = auth.uid()
      and r.role in ('qms_admin','ceo','hod','board_treasurer','head_ops_systems')
  );
$$;

create or replace function public.qms_setting(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  select value from public.qms_settings where key = p_key;
$$;

-- ---------- Working days ------------------------------------------------
create or replace function public.qms_add_working_days(p_from date, p_days int)
returns date language plpgsql stable set search_path = public as $$
declare d date := p_from; n int := 0;
begin
  while n < p_days loop
    d := d + 1;
    if extract(isodow from d) < 6
       and not exists (select 1 from public.qms_non_working_day w where w.day = d) then
      n := n + 1;
    end if;
  end loop;
  return d;
end $$;

create or replace function public.qms_working_days_between(p_from date, p_to date)
returns int language sql stable set search_path = public as $$
  select count(*)::int from generate_series(p_from + 1, p_to, interval '1 day') g(d)
  where extract(isodow from g.d) < 6
    and not exists (select 1 from public.qms_non_working_day w where w.day = g.d::date);
$$;

-- ---------- Numbers ---------------------------------------------------
create or replace function public.qms_next_ref(p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare y int := extract(year from now())::int; n int;
begin
  insert into public.qms_sequence(name, year, last) values (p_name, y, 1)
  on conflict (name, year) do update set last = public.qms_sequence.last + 1
  returning last into n;
  return p_name || '-' || y || '-' || lpad(n::text, 3, '0');
end $$;

-- ---------- Audit trigger (all qms tables) ---------------------------------
create or replace function public.qms_audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_id text; v_ver text;
begin
  v_id := coalesce(
    case when tg_op = 'DELETE' then to_jsonb(old)->>'id' else to_jsonb(new)->>'id' end, '');
  if tg_table_name = 'qms_version' then
    v_ver := case when tg_op = 'DELETE' then old.version_no else new.version_no end;
  end if;
  insert into public.qms_audit_log(action, table_name, record_id, version_no, before, after)
  values (lower(tg_op), tg_table_name, v_id, v_ver,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['qms_document','qms_version','qms_approval_step','qms_change_request',
                           'qms_review_extension','qms_acknowledgement','qms_user_role','qms_settings']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.qms_audit_trigger()', t || '_audit', t);
  end loop;
end $$;

-- Audit log is insert-only, even for the service role (R-16)
create or replace function public.qms_audit_log_block()
returns trigger language plpgsql as $$
begin
  raise exception 'qms_audit_log is insert-only';
end $$;
create trigger qms_audit_log_no_update before update or delete on public.qms_audit_log
  for each row execute function public.qms_audit_log_block();
create trigger qms_audit_log_no_truncate before truncate on public.qms_audit_log
  for each statement execute function public.qms_audit_log_block();

-- updated_at
create or replace function public.qms_touch()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger qms_document_touch before update on public.qms_document for each row execute function public.qms_touch();
create trigger qms_version_touch  before update on public.qms_version  for each row execute function public.qms_touch();

-- Published or approved versions cannot be changed except by the functions below (R-10)
create or replace function public.qms_version_lock()
returns trigger language plpgsql as $$
begin
  if old.status in ('Approved','Obsolete') and current_setting('qms.allow_locked', true) is distinct from 'on' then
    raise exception 'Version % is % and cannot be edited; start a new version', old.version_no, old.status;
  end if;
  return new;
end $$;
create trigger qms_version_lock before update on public.qms_version for each row execute function public.qms_version_lock();

-- ---------- Notifications --------------------------------------------------
create or replace function public.qms_notify(p_event text, p_message text, p_subject uuid,
  p_user uuid default null, p_role public.qms_role default null, p_department text default null)
returns void language sql security definer set search_path = public as $$
  insert into public.qms_notification(event, recipient, recipient_role, recipient_department, subject_id, message)
  values (p_event, p_user, p_role, p_department, p_subject, p_message);
$$;

-- ---------- Approval matrix (QMS-SOP-GOV-001 section 6.5) --------------------
-- Returns the approver for a version, moving up a level when the author holds it (R-04).
create or replace function public.qms_route(p_version_id uuid,
  out approver public.qms_approver, out approver_department text)
language plpgsql stable security definer set search_path = public as $$
declare d public.qms_document; v public.qms_version;
begin
  select * into v from public.qms_version where id = p_version_id;
  select * into d from public.qms_document where id = v.document_id;

  if d.doc_class = 2 then
    approver := 'programme_owner'; approver_department := null; return;
  end if;

  if d.is_governance or d.doc_type = 'MAN' then
    approver := 'board';
  elsif d.department = 'HR' and d.doc_type = 'POL' then
    approver := 'ceo';
  elsif d.department = 'HR' then
    approver := 'hod'; approver_department := 'HR';
  elsif d.doc_type in ('POL','MAP') or d.is_cross_department then
    approver := 'ceo';
  else
    approver := 'hod'; approver_department := d.department;
  end if;

  -- The CEO wrote it: the Board Treasurer approves (except Board-level documents)
  if approver <> 'board' and public.qms_user_has_role(v.author_id, 'ceo') then
    approver := 'board_treasurer'; approver_department := null; return;
  end if;
  -- The HOD who must approve wrote or submitted it: the CEO approves
  if approver = 'hod' and (public.qms_user_has_role(v.author_id, 'hod', approver_department)
                        or public.qms_user_has_role(v.submitted_by, 'hod', approver_department)) then
    approver := 'ceo'; approver_department := null;
  end if;
end $$;

-- ---------- Create a document with its first draft ---------------------------
create or replace function public.qms_create_document(
  p_title text, p_doc_class smallint, p_doc_type public.qms_doc_type, p_department text,
  p_owner_role text, p_code text default null, p_domain text default null, p_process text default null,
  p_programme text default null, p_is_governance boolean default false,
  p_is_cross_department boolean default false, p_visible_to text[] default array['all_staff'],
  p_source_path text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_ver uuid;
begin
  if not (public.qms_has_role('qms_admin') or public.qms_has_role('ceo')
          or (p_doc_class = 1 and public.qms_has_role('hod', p_department))
          or (p_doc_class = 2 and public.qms_has_role('programme_owner'))) then
    raise exception 'Not allowed to create this document';
  end if;

  insert into public.qms_document(title, doc_class, doc_type, department, owner_role, owner_user, code,
         domain, process, programme, is_governance, is_cross_department, visible_to)
  values (p_title, p_doc_class, p_doc_type, p_department, p_owner_role, auth.uid(), p_code,
         p_domain, p_process, p_programme, p_is_governance, p_is_cross_department, p_visible_to)
  returning id into v_doc;

  insert into public.qms_version(document_id, draft_seq, source_path, author_id)
  values (v_doc, 1, p_source_path, auth.uid()) returning id into v_ver;

  update public.qms_document set current_version_id = v_ver where id = v_doc;
  return v_doc;
end $$;

-- ---------- Start a new draft (revision, or after a return) ----------------------
create or replace function public.qms_new_draft(p_document_id uuid, p_source_path text,
  p_change_summary text, p_is_significant boolean default false, p_change_request_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare d public.qms_document; v_ver uuid; v_seq int;
begin
  select * into d from public.qms_document where id = p_document_id for update;
  if not (public.qms_has_role('qms_admin') or public.qms_has_role('ceo')
          or public.qms_has_role('hod', d.department) or d.owner_user = auth.uid()) then
    raise exception 'Not allowed';
  end if;
  if exists (select 1 from public.qms_version where document_id = d.id
             and status in ('Draft','Submitted','In review')) then
    raise exception 'This document already has a draft in progress';
  end if;
  if coalesce(length(trim(p_change_summary)),0) = 0 then
    raise exception 'A change summary is required';
  end if;

  select coalesce(max(draft_seq),0) + 1 into v_seq from public.qms_version where document_id = d.id;
  insert into public.qms_version(document_id, draft_seq, source_path, change_summary,
         is_significant, change_request_id, author_id)
  values (d.id, v_seq, p_source_path, p_change_summary, p_is_significant, p_change_request_id, auth.uid())
  returning id into v_ver;

  update public.qms_document set current_version_id = v_ver,
         status = case when published_version_id is null then 'Draft' else status end
  where id = d.id;
  return v_ver;
end $$;

-- ---------- Submit (Draft or Returned -> Submitted) -----------------------------
create or replace function public.qms_submit(p_version_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v public.qms_version; d public.qms_document;
begin
  select * into v from public.qms_version where id = p_version_id for update;
  select * into d from public.qms_document where id = v.document_id for update;

  if not (public.qms_has_role('qms_admin') or public.qms_has_role('hod', d.department)
          or d.owner_user = auth.uid() or v.author_id = auth.uid()) then
    raise exception 'Not allowed to submit';
  end if;
  if v.status not in ('Draft','Returned') then
    raise exception 'Only a Draft or Returned version can be submitted (status is %)', v.status;
  end if;
  if v.source_path is null then
    raise exception 'Upload the Word file before submitting';
  end if;
  -- R-01: class 1 code format
  if d.doc_class = 1 and (d.code is null or d.code !~ '^QMS-(MAN|POL|MAP|SOP|GUI|FRM|TMP|REG)-[A-Z]{2,4}-[0-9]{3}$') then
    raise exception 'Class 1 documents need a code like QMS-SOP-GOV-001 before submission (code is %)', coalesce(d.code,'empty');
  end if;
  if d.doc_class = 1 and d.process is null then
    raise exception 'Class 1 documents need a process code';
  end if;
  -- R-13: significant change needs a change request
  if v.is_significant and v.change_request_id is null then
    raise exception 'A significant change needs a linked change request (QMS-SOP-GOV-010)';
  end if;
  if v.draft_seq > 1 and coalesce(length(trim(v.change_summary)),0) = 0 then
    raise exception 'A change summary is required';
  end if;

  update public.qms_version set status = 'Submitted', submitted_by = auth.uid(), submitted_at = now()
  where id = v.id;
  update public.qms_document set status = case when published_version_id is null then 'Submitted' else status end
  where id = d.id;

  insert into public.qms_approval_step(version_id, kind) values (v.id, 'Check');
  perform public.qms_notify('submitted',
    coalesce(d.code, d.title) || ' v' || v.version_no || ' submitted for checking.', v.id, null, 'qms_admin');
end $$;

-- ---------- QMS Administrator check: send for approval (Submitted -> In review) ----
create or replace function public.qms_send_for_approval(p_version_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v public.qms_version; d public.qms_document; r record;
begin
  if not public.qms_has_role('qms_admin') then raise exception 'Only the QMS Administrator sends for approval'; end if;
  select * into v from public.qms_version where id = p_version_id for update;
  select * into d from public.qms_document where id = v.document_id;
  if v.status <> 'Submitted' then raise exception 'Version is %, not Submitted', v.status; end if;

  update public.qms_approval_step set decision = 'Approved', decided_by = auth.uid(), decided_at = now()
  where version_id = v.id and kind = 'Check' and decision = 'Pending';

  select * into r from public.qms_route(v.id);
  insert into public.qms_approval_step(version_id, kind, required_role, required_department)
  values (v.id, 'Approve', r.approver, r.approver_department);

  update public.qms_version set status = 'In review' where id = v.id;
  update public.qms_document set status = case when published_version_id is null then 'In review' else status end
  where id = d.id;

  perform public.qms_notify('approval_requested',
    coalesce(d.code, d.title) || ' v' || v.version_no || ' is waiting for your approval.', v.id, null,
    case r.approver when 'board' then 'ceo'::public.qms_role
                    when 'board_treasurer' then 'board_treasurer'
                    when 'programme_owner' then 'programme_owner'
                    else r.approver::text::public.qms_role end,
    r.approver_department);
end $$;

-- ---------- Return (comment required, R-06) ---------------------------------
create or replace function public.qms_return(p_version_id uuid, p_comment text)
returns void language plpgsql security definer set search_path = public as $$
declare v public.qms_version; d public.qms_document; s public.qms_approval_step;
begin
  if coalesce(length(trim(p_comment)),0) = 0 then raise exception 'A comment is required to return a document'; end if;
  select * into v from public.qms_version where id = p_version_id for update;
  select * into d from public.qms_document where id = v.document_id;
  if v.status not in ('Submitted','In review') then raise exception 'Version is %', v.status; end if;

  select * into s from public.qms_approval_step
  where version_id = v.id and decision = 'Pending' order by created_at desc limit 1;

  if not (public.qms_has_role('qms_admin') or public.qms_can_decide(s.id)) then
    raise exception 'Not allowed to return this document';
  end if;

  update public.qms_approval_step set decision = 'Returned', comment = p_comment,
         decided_by = auth.uid(), decided_at = now()
  where id = s.id;
  update public.qms_version set status = 'Returned' where id = v.id;
  update public.qms_document set status = case when published_version_id is null then 'Returned' else status end
  where id = d.id;
  perform public.qms_notify('returned',
    coalesce(d.code, d.title) || ' v' || v.version_no || ' was returned: ' || p_comment, v.id, v.author_id);
end $$;

-- ---------- Can the signed-in user decide this approval step? (R-04, R-05) ------
create or replace function public.qms_can_decide(p_step_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare s public.qms_approval_step; v public.qms_version;
begin
  select * into s from public.qms_approval_step where id = p_step_id;
  if s.id is null or s.kind <> 'Approve' or s.decision <> 'Pending' then return false; end if;
  select * into v from public.qms_version where id = s.version_id;
  if auth.uid() in (v.author_id, v.submitted_by) then return false; end if;
  return case s.required_role
    when 'hod'             then public.qms_has_role('hod', s.required_department)
    when 'ceo'             then public.qms_has_role('ceo')
    when 'board'           then public.qms_has_role('ceo')      -- CEO uploads the Board resolution
    when 'board_treasurer' then public.qms_has_role('board_treasurer')
    when 'programme_owner' then public.qms_has_role('programme_owner')
  end;
end $$;

-- ---------- Approve (In review -> Approved; previous -> Obsolete) ----------------
create or replace function public.qms_approve(p_version_id uuid,
  p_change_type public.qms_change_type default 'Major',
  p_board_resolution_path text default null, p_board_resolution_no text default null,
  p_board_resolution_date date default null, p_next_review_date date default null)
returns text language plpgsql security definer set search_path = public as $$
declare v public.qms_version; d public.qms_document; s public.qms_approval_step;
        prev public.qms_version; v_major int; v_minor int; v_review date;
begin
  select * into v from public.qms_version where id = p_version_id for update;
  select * into d from public.qms_document where id = v.document_id for update;
  if v.status <> 'In review' then raise exception 'Version is %, not In review', v.status; end if;

  select * into s from public.qms_approval_step
  where version_id = v.id and kind = 'Approve' and decision = 'Pending' order by created_at desc limit 1;

  if auth.uid() in (v.author_id, v.submitted_by) then
    raise exception 'You cannot approve a document you wrote or submitted; it goes to the next level';
  end if;
  if not public.qms_can_decide(s.id) then raise exception 'You are not the approver for this document'; end if;

  -- R-07: Board-level documents need the signed resolution
  if s.required_role = 'board' and (p_board_resolution_path is null or p_board_resolution_no is null
                                     or p_board_resolution_date is null) then
    raise exception 'Upload the signed Board resolution with its number and date';
  end if;

  -- R-03: version number
  if d.published_version_id is null then
    v_major := 1; v_minor := 0;
  else
    select * into prev from public.qms_version where id = d.published_version_id;
    if p_change_type = 'Minor' then v_major := prev.major; v_minor := prev.minor + 1;
    else v_major := prev.major + 1; v_minor := 0; end if;
  end if;

  -- R-11: review date, default 12 months
  v_review := coalesce(p_next_review_date,
              (current_date + make_interval(months => coalesce((public.qms_setting('review_months'))::int, 12)))::date);

  perform set_config('qms.allow_locked', 'on', true);

  -- R-08: the previous live version becomes Obsolete in the same transaction
  if d.published_version_id is not null then
    update public.qms_version set status = 'Obsolete' where id = d.published_version_id;
  end if;

  update public.qms_approval_step set decision = 'Approved', decided_by = auth.uid(), decided_at = now()
  where id = s.id;

  update public.qms_version set status = 'Approved', major = v_major, minor = v_minor,
         change_type = p_change_type, approved_by = auth.uid(), approved_at = now(),
         board_resolution_path = p_board_resolution_path, board_resolution_no = p_board_resolution_no,
         board_resolution_date = p_board_resolution_date
  where id = v.id;

  update public.qms_document set status = 'Approved', published_version_id = v.id, current_version_id = v.id,
         approved_date = current_date, next_review_date = v_review,
         retention_until = null   -- set when superseded or withdrawn (section 11)
  where id = d.id;

  -- retention for the version just superseded: 5 years after superseded
  if prev.id is not null then
    perform public.qms_notify('superseded', coalesce(d.code, d.title) || ' v' || prev.version_no
      || ' superseded; keep until ' || (current_date + interval '5 years')::date, prev.id, null, 'qms_admin');
  end if;

  -- The qms-publish edge function picks this up: stamps the PDF Controlled and copies it to qms-published
  perform public.qms_notify('publish_pdf', 'Render and publish ' || coalesce(d.code, d.title) || ' v' || v_major || '.' || v_minor,
                            v.id, null, 'qms_admin');
  perform public.qms_notify('published',
    coalesce(d.code, d.title) || ' ' || d.title || ' v' || v_major || '.' || v_minor || ' is now in force.', d.id);

  return v_major || '.' || v_minor;
end $$;

-- ---------- Withdraw (QMS Administrator, reason required) ------------------------
create or replace function public.qms_withdraw(p_document_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d public.qms_document; v_years int;
begin
  if not public.qms_has_role('qms_admin') then raise exception 'Only the QMS Administrator withdraws documents'; end if;
  if coalesce(length(trim(p_reason)),0) = 0 then raise exception 'A reason is required'; end if;
  select * into d from public.qms_document where id = p_document_id for update;
  perform set_config('qms.allow_locked', 'on', true);
  update public.qms_version set status = 'Obsolete' where document_id = d.id and status = 'Approved';
  v_years := case d.doc_class when 3 then coalesce((select retention_years from public.qms_record_type where code = d.record_type), 5) else 5 end;
  update public.qms_document set status = 'Obsolete', published_version_id = null, withdrawn_reason = p_reason,
         retention_until = (current_date + make_interval(years => v_years))::date
  where id = d.id;
  perform public.qms_notify('withdrawn', coalesce(d.code, d.title) || ' has been withdrawn: ' || p_reason, d.id);
end $$;

-- ---------- Extend a review date (reason required, R-11) --------------------------
create or replace function public.qms_extend_review(p_document_id uuid, p_new_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d public.qms_document;
begin
  if not public.qms_has_role('qms_admin') then raise exception 'Only the QMS Administrator extends review dates'; end if;
  if coalesce(length(trim(p_reason)),0) = 0 then raise exception 'A reason is required'; end if;
  select * into d from public.qms_document where id = p_document_id for update;
  insert into public.qms_review_extension(document_id, old_date, new_date, reason, agreed_by)
  values (d.id, d.next_review_date, p_new_date, p_reason, auth.uid());
  update public.qms_document set next_review_date = p_new_date where id = d.id;
end $$;

-- ---------- Mark reviewed with no change (Release 2) -----------------------------
create or replace function public.qms_mark_reviewed(p_document_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.qms_document;
begin
  select * into d from public.qms_document where id = p_document_id for update;
  if not (public.qms_has_role('qms_admin') or public.qms_has_role('hod', d.department)) then
    raise exception 'Not allowed';
  end if;
  update public.qms_document set next_review_date = (current_date + interval '12 months')::date where id = d.id;
end $$;

-- ---------- Acknowledge a policy (Release 2) -------------------------------------
create or replace function public.qms_acknowledge(p_version_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.qms_acknowledgement set acknowledged_at = now()
  where version_id = p_version_id and user_id = auth.uid() and acknowledged_at is null;
  if not found then raise exception 'Nothing to acknowledge'; end if;
end $$;

-- ---------- Change request ------------------------------------------------
create or replace function public.qms_log_change_request(p_title text, p_significance text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.qms_is_qms_group() then raise exception 'Not allowed'; end if;
  insert into public.qms_change_request(ref, title, significance)
  values (public.qms_next_ref('CR'), p_title, p_significance) returning id into v_id;
  return v_id;
end $$;

-- ---------- Record the published PDF (called by the qms-publish edge function) ----
create or replace function public.qms_set_published_pdf(p_version_id uuid, p_path text, p_sha256 text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('qms.allow_locked', 'on', true);
  update public.qms_version set published_pdf_path = p_path, pdf_sha256 = p_sha256
  where id = p_version_id and status = 'Approved' and published_pdf_path is null;
  if not found then raise exception 'Version is not approved or already published'; end if;
end $$;
revoke execute on function public.qms_set_published_pdf(uuid, text, text) from public, anon, authenticated;

-- ---------- Can the signed-in user read this published document? (R-09, R-15) ----
create or replace function public.qms_can_read_document(p_document_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare d public.qms_document;
begin
  if public.qms_is_qms_group() then return true; end if;
  select * into d from public.qms_document where id = p_document_id;
  if d.published_version_id is null and d.doc_class <> 3 then return false; end if;
  return exists (
    select 1 from unnest(d.visible_to) vt
    where vt = 'all_staff' and public.qms_has_role('staff')
       or (vt like 'dept:%' and exists (select 1 from public.qms_user_role r
             where r.user_id = auth.uid() and r.department = substr(vt, 6)))
       or (vt = 'mentors' and public.qms_has_role('mentor') and d.doc_class <> 2)
       or (vt like 'mentors:%' and exists (select 1 from public.qms_user_role r
             where r.user_id = auth.uid() and r.role = 'mentor' and r.programme = substr(vt, 9)))
       or (d.doc_class = 2 and exists (select 1 from public.qms_user_role r
             where r.user_id = auth.uid() and r.role in ('mentor','programme_owner') and r.programme = d.programme)
           and (d.is_external = false or d.licence_note is not null))   -- R-14
  );
end $$;


-- >>>>>>>>>> migrations/20261124090200_qms_03_rls.sql
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


-- >>>>>>>>>> migrations/20261124090300_qms_04_storage.sql
-- =====================================================================
-- QMS Management tab: file storage (Supabase Storage)
-- qms-drafts    : Word originals, preview PDFs, Board resolutions. QMS group only.
-- qms-published : stamped Controlled PDFs written by the qms-publish edge function.
--                 Never read directly by the browser: the qms-download edge function
--                 checks access and returns a copy stamped "Uncontrolled copy".
-- Paths: <document_id>/<version_id>/<file>
-- Decision D-06 (system file store or SharePoint library) is still open; this uses
-- Supabase Storage. Swap the bucket calls if SharePoint is chosen.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('qms-drafts', 'qms-drafts', false, 26214400,
   array['application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/pdf']),
  ('qms-published', 'qms-published', false, 26214400, array['application/pdf'])
on conflict (id) do nothing;

-- Drafts: QMS group can read; HODs and the QMS Administrator upload; nobody overwrites
create policy qms_drafts_read on storage.objects for select to authenticated
  using (bucket_id = 'qms-drafts' and public.qms_is_qms_group());

create policy qms_drafts_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'qms-drafts'
              and (public.qms_has_role('qms_admin') or public.qms_has_role('hod')
                   or public.qms_has_role('ceo') or public.qms_has_role('programme_owner')));

-- No update or delete policies: a changed file is a new upload (new version folder).
-- qms-published has no policies for authenticated users at all: only the edge
-- functions (service role) read and write it.


-- >>>>>>>>>> migrations/20261124090400_qms_05_reminders.sql
-- =====================================================================
-- QMS Management tab: daily reminders and escalations (briefing section 7)
-- Writes rows to qms_notification; the qms-notify edge function sends them.
-- Schedule with pg_cron (enable it under Database > Extensions):
--   select cron.schedule('qms-reminders', '30 5 * * 1-5', $$select public.qms_run_reminders()$$);
--   (05:30 UTC = 07:30 South African time)
-- Safe to run more than once a day: each reminder is written once per day.
-- =====================================================================

create or replace function public.qms_run_reminders()
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
  v_check  int := coalesce((public.qms_setting('check_working_days'))::int, 5);
  v_nudge  int := coalesce((public.qms_setting('approval_nudge_days'))::int, 3);
  v_escal  int := coalesce((public.qms_setting('approval_escalate_days'))::int, 10);
  v_review int := coalesce((public.qms_setting('review_reminder_days'))::int, 30);
begin
  -- Skip weekends, public holidays and the December closure
  if extract(isodow from current_date) > 5
     or exists (select 1 from public.qms_non_working_day where day = current_date) then
    return 0;
  end if;

  -- 1. Check not done within 5 working days: QMS Administrator, then Head of Operations and Systems
  for r in select v.id, d.code, d.title, v.version_no,
                  public.qms_working_days_between(v.submitted_at::date, current_date) as wd
           from public.qms_version v join public.qms_document d on d.id = v.document_id
           where v.status = 'Submitted'
             and public.qms_working_days_between(v.submitted_at::date, current_date) >= v_check
  loop
    if not exists (select 1 from public.qms_notification where subject_id = r.id
                   and event = 'check_overdue' and created_at::date = current_date) then
      perform public.qms_notify('check_overdue', coalesce(r.code, r.title) || ' v' || r.version_no
        || ' has waited ' || r.wd || ' working days for checking.', r.id, null, 'qms_admin');
      perform public.qms_notify('check_overdue', coalesce(r.code, r.title) || ' v' || r.version_no
        || ' has waited ' || r.wd || ' working days for checking.', r.id, null, 'head_ops_systems');
      n := n + 2;
    end if;
  end loop;

  -- 2. Approval waiting: nudge every few days; escalate after 10 working days
  for r in select s.id, s.version_id, s.required_role, s.required_department, d.code, d.title, v.version_no,
                  public.qms_working_days_between(v.submitted_at::date, current_date) as wd
           from public.qms_approval_step s
           join public.qms_version v on v.id = s.version_id
           join public.qms_document d on d.id = v.document_id
           where s.kind = 'Approve' and s.decision = 'Pending'
  loop
    if r.wd >= v_nudge and r.wd % v_nudge = 0
       and not exists (select 1 from public.qms_notification where subject_id = r.version_id
                       and event = 'approval_reminder' and created_at::date = current_date) then
      perform public.qms_notify('approval_reminder', coalesce(r.code, r.title) || ' v' || r.version_no
        || ' is still waiting for your approval (' || r.wd || ' working days).', r.version_id, null,
        case r.required_role when 'board' then 'ceo'::public.qms_role
                             when 'board_treasurer' then 'board_treasurer'
                             when 'programme_owner' then 'programme_owner'
                             else r.required_role::text::public.qms_role end,
        r.required_department);
      n := n + 1;
    end if;
    if r.wd >= v_escal
       and not exists (select 1 from public.qms_notification where subject_id = r.version_id
                       and event = 'approval_escalation' and created_at::date = current_date) then
      perform public.qms_notify('approval_escalation', coalesce(r.code, r.title) || ' v' || r.version_no
        || ' has waited ' || r.wd || ' working days for approval.', r.version_id, null,
        case when r.required_role in ('ceo','board') then 'board_treasurer'::public.qms_role else 'ceo'::public.qms_role end);
      n := n + 1;
    end if;
  end loop;

  -- 3. Review due in 30 days (sent once), and overdue (weekly on Mondays)
  for r in select d.id, d.code, d.title, d.department, d.next_review_date, d.owner_user
           from public.qms_document d
           where d.status = 'Approved' and d.next_review_date = current_date + v_review
  loop
    perform public.qms_notify('review_due', coalesce(r.code, r.title) || ' is due for review on '
      || to_char(r.next_review_date, 'DD Mon YYYY') || '.', r.id, r.owner_user, 'hod', r.department);
    n := n + 1;
  end loop;

  if extract(isodow from current_date) = 1 then
    for r in select d.id, d.code, d.title, d.department, d.next_review_date, d.owner_user
             from public.qms_document d
             where d.status = 'Approved' and d.next_review_date < current_date
    loop
      perform public.qms_notify('review_overdue', coalesce(r.code, r.title) || ' passed its review date ('
        || to_char(r.next_review_date, 'DD Mon YYYY') || ').', r.id, r.owner_user, 'hod', r.department);
      perform public.qms_notify('review_overdue', coalesce(r.code, r.title) || ' passed its review date.',
        r.id, null, 'qms_admin');
      n := n + 2;
    end loop;
  end if;

  return n;
end $$;

revoke execute on function public.qms_run_reminders() from public, anon, authenticated;

-- Recipients for a notification (used by the qms-notify edge function)
create or replace function public.qms_notification_recipients(p_id bigint)
returns table(user_id uuid, email text) language sql stable security definer set search_path = public, auth as $$
  select u.id, u.email from public.qms_notification n
  join auth.users u on u.id = n.recipient
  where n.id = p_id
  union
  select distinct u.id, u.email from public.qms_notification n
  join public.qms_user_role r on r.role = n.recipient_role
       and (n.recipient_department is null or r.department = n.recipient_department)
  join auth.users u on u.id = r.user_id
  where n.id = p_id and n.recipient_role is not null
  union
  -- 'published' and 'withdrawn' go to everyone who can read the document
  select distinct u.id, u.email from public.qms_notification n
  join public.qms_document d on d.id = n.subject_id
  join public.qms_user_role r on
       ('all_staff' = any(d.visible_to) and r.role = 'staff')
    or ('dept:' || r.department = any(d.visible_to))
    or ('hods' = any(d.visible_to) and r.role = 'hod')
  join auth.users u on u.id = r.user_id
  where n.id = p_id and n.event in ('published','withdrawn') and n.recipient is null and n.recipient_role is null;
$$;
revoke execute on function public.qms_notification_recipients(bigint) from public, anon, authenticated;


-- >>>>>>>>>> migrations/20261124090500_qms_06_web_app.sql
-- =====================================================================
-- QMS Management tab: helpers for the web app (GitHub Pages front end)
-- * People and roles screen: list users with their roles, add a role by email
-- * Show e-mail addresses (not ids) in the approval trail and audit log
-- Nothing here changes the approval rules in migrations 01 to 05.
-- =====================================================================

-- True when called straight from the database (SQL Editor, psql, service role),
-- false when called through the API by a signed-in or anonymous user.
create or replace function public.qms_is_direct_db_call()
returns boolean language sql stable as $$
  select coalesce(current_setting('request.jwt.claim.role', true),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role') is null
      or coalesce(current_setting('request.jwt.claim.role', true),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role') = 'service_role';
$$;

-- People and their QMS roles (QMS Administrator and Head of Operations and Systems)
create or replace function public.qms_list_users()
returns table(user_id uuid, email text, roles jsonb)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not (public.qms_has_role('qms_admin') or public.qms_has_role('head_ops_systems')) then
    raise exception 'Only the QMS Administrator or Head of Operations and Systems manages roles';
  end if;
  return query
    select u.id, u.email::text,
           coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'role', r.role, 'department', r.department,
                                                         'programme', r.programme) order by r.role)
                     from public.qms_user_role r where r.user_id = u.id), '[]'::jsonb)
    from auth.users u order by u.email;
end $$;

-- Give someone a role by their sign-in e-mail. Run it once from the SQL Editor for the
-- first QMS Administrator; after that the People and roles screen uses it.
create or replace function public.qms_grant_role(p_email text, p_role public.qms_role,
  p_department text default null, p_programme text default null)
returns bigint language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid; v_id bigint;
begin
  if not (public.qms_is_direct_db_call() or public.qms_has_role('qms_admin') or public.qms_has_role('head_ops_systems')) then
    raise exception 'Only the QMS Administrator or Head of Operations and Systems manages roles';
  end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then
    raise exception 'No user signs in with %. Add them first under Authentication > Users in Supabase.', p_email;
  end if;
  if p_role in ('hod','staff') and p_department is null then raise exception 'Choose a department for this role'; end if;
  if p_role in ('mentor','programme_owner') and p_programme is null then raise exception 'Enter the programme for this role'; end if;
  insert into public.qms_user_role(user_id, role, department, programme)
  values (v_user, p_role, nullif(p_department,''), nullif(p_programme,''))
  on conflict (user_id, role, department, programme) do nothing
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.qms_revoke_role(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.qms_has_role('qms_admin') or public.qms_has_role('head_ops_systems')) then
    raise exception 'Only the QMS Administrator or Head of Operations and Systems manages roles';
  end if;
  if (select user_id from public.qms_user_role where id = p_id) = auth.uid()
     and (select role from public.qms_user_role where id = p_id) in ('qms_admin','head_ops_systems') then
    raise exception 'You cannot remove your own administrator role; ask the other administrator';
  end if;
  delete from public.qms_user_role where id = p_id;
end $$;

-- E-mail addresses for ids shown on screen (QMS group only)
create or replace function public.qms_user_emails(p_ids uuid[])
returns table(user_id uuid, email text)
language sql stable security definer set search_path = public, auth as $$
  select u.id, u.email::text from auth.users u
  where u.id = any(p_ids) and public.qms_is_qms_group();
$$;

-- The signed-in user's own roles (for the menu)
create or replace function public.qms_my_roles()
returns table(role public.qms_role, department text, programme text)
language sql stable security definer set search_path = public as $$
  select r.role, r.department, r.programme from public.qms_user_role r where r.user_id = auth.uid();
$$;

revoke execute on function public.qms_list_users(), public.qms_grant_role(text, public.qms_role, text, text),
  public.qms_revoke_role(bigint), public.qms_user_emails(uuid[]), public.qms_my_roles() from public, anon;
grant execute on function public.qms_list_users(), public.qms_grant_role(text, public.qms_role, text, text),
  public.qms_revoke_role(bigint), public.qms_user_emails(uuid[]), public.qms_my_roles(),
  public.qms_route(uuid) to authenticated;

-- Explicit API grants. Older Supabase projects grant these by default; newer projects can be
-- set not to expose new tables automatically, so grant what the app and edge functions need.
-- Row level security (migration 03) still decides which rows each person sees.
do $$
declare t text;
begin
  foreach t in array array['qms_user_role','qms_department','qms_process','qms_record_type','qms_settings',
    'qms_non_working_day','qms_document','qms_version','qms_approval_step','qms_change_request',
    'qms_review_extension','qms_acknowledgement','qms_notification','qms_audit_log']
  loop
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
grant all on public.qms_sequence to service_role;
grant usage, select on all sequences in schema public to service_role;
grant insert on public.qms_audit_log to service_role;       -- downloads are logged by qms-download
grant execute on all functions in schema public to service_role;


-- >>>>>>>>>> seed.sql
-- =====================================================================
-- QMS Management tab: starting lists and settings
-- Run after the migrations (supabase db reset runs seed.sql automatically).
-- Values in [square brackets] in notes are still to be decided.
-- =====================================================================

insert into public.qms_department (code, name) values
  ('GOV', 'Governance'),
  ('QMS', 'QMS'),
  ('OPS', 'Operations'),
  ('TD', 'Training and Development'),
  ('SG', 'Sustainability and Growth'),
  ('ME', 'M&E (outsourced)'),
  ('REP', 'Reports'),
  ('FIN', 'Finance'),
  ('HR', 'Human Resources'),
  ('PR', 'Marketing and PR'),
  ('EXE', 'Executive');

-- Level 2 processes from QMS-MAP-GOV-001 Process Map Register
insert into public.qms_process (code, name, department) values
  ('GOV-01', 'Policy Development and Approval', 'GOV'),
  ('GOV-02', 'Risk Management', 'GOV'),
  ('GOV-03', 'Board Reporting', 'GOV'),
  ('GOV-04', 'Annual Planning and Budgeting', 'GOV'),
  ('GOV-05', 'Communication (proposed)', 'GOV'),
  ('QMS-01', 'Document Control', 'QMS'),
  ('QMS-02', 'Internal Audit', 'QMS'),
  ('QMS-03', 'Continuous Improvement', 'QMS'),
  ('QMS-04', 'Client Reporting Quality Review', 'QMS'),
  ('QMS-05', 'Asset Management', 'QMS'),
  ('OPS-01', 'Project Start-Up', 'OPS'),
  ('OPS-02', 'Project Tracking', 'OPS'),
  ('OPS-03', 'Project Closure', 'OPS'),
  ('T&D-01', 'Beneficiary Journey', 'TD'),
  ('T&D-02', 'Mentor Management', 'TD'),
  ('T&D-03', 'Training Delivery', 'TD'),
  ('SG-01', 'Opportunity Management', 'SG'),
  ('SG-02', 'Client Handover', 'SG'),
  ('SG-03', 'Marketing', 'SG'),
  ('M&E-01', 'Framework Development', 'ME'),
  ('M&E-02', 'Quarterly Monitoring', 'ME'),
  ('M&E-03', 'Reporting: mentor quarterly programme reports', 'REP'),
  ('FIN-01', 'Payment Request (PR)', 'FIN'),
  ('FIN-02', 'Asset Payment Request (APR)', 'FIN'),
  ('FIN-03', 'Operational Payment Request (OPR)', 'FIN'),
  ('FIN-04', 'Internship Payment Request (IPR)', 'FIN'),
  ('FIN-05', 'Bursary Payment Request (BPR)', 'FIN'),
  ('FIN-06', 'Donations and Section 18A Receipts (proposed)', 'FIN'),
  ('FIN-07', 'Procurement', 'FIN'),
  ('FIN-08', 'Internship Travel (ITV)', 'FIN'),
  ('FIN-09', 'Bursary Travel (BTV)', 'FIN'),
  ('FIN-10', 'Internal Travel (TVT)', 'FIN'),
  ('FIN-11', 'Payroll', 'FIN'),
  ('FIN-12', 'Tax Compliance (VAT and PBO) (proposed)', 'FIN'),
  ('HR-01', 'Recruitment', 'HR'),
  ('HR-02', 'Onboarding', 'HR'),
  ('HR-03', 'Performance Management', 'HR'),
  ('HR-04', 'Remote Work', 'HR'),
  ('HR-05', 'Offboarding', 'HR');

-- Retention schedule from QMS-POL-INF-003 (100 = permanent; HR records follow HR-01-SCH-01)
insert into public.qms_record_type (code, name, retention_years, retention_trigger) values
  ('GOV-PERM', 'Constitution, certificates, SARS letters, Board minutes and resolutions', 100, 'permanent'),
  ('FIN-AFS', 'Annual financial statements, audit and NPO annual reports', 100, 'permanent'),
  ('FIN-ACC', 'Accounting records (ledgers, invoices, payment requests, bank statements, quotations, proofs of payment)', 7, 'end of financial year'),
  ('FIN-VAT', 'VAT records and returns', 7, 'date return submitted'),
  ('FIN-DON', 'Donation records and section 18A receipts', 7, 'end of tax year'),
  ('FIN-PAY', 'Payroll, PAYE, UIF and COIDA records', 7, 'end of tax year'),
  ('COM-CON', 'Client contracts and service agreements', 7, 'end of contract (contract term + 7 years)'),
  ('FIN-SUP', 'Supplier records and due diligence files', 7, 'last transaction'),
  ('OPS-BEN', 'Beneficiary application and programme records', 5, 'programme closure'),
  ('OPS-REP', 'Client reports and evidence packs', 7, 'end of contract (contract term + 7 years)'),
  ('OPS-SAT', 'Satisfaction survey raw responses', 2, 'end of cohort'),
  ('OPS-LRN', 'Accredited training and learner records (Angels copies)', 5, 'completion'),
  ('GOV-CMP', 'Complaints and feedback', 3, 'complaint closed'),
  ('GOV-FRD', 'Fraud, whistleblowing and investigation files', 5, 'matter closed'),
  ('INF-PAIA', 'PAIA requests and POPIA data subject requests', 5, 'request closed'),
  ('INF-BRE', 'Personal information breach records', 5, 'incident closed'),
  ('PR-CONS', 'Consent and marketing opt-out records', 1, 'consent withdrawn or contact removed'),
  ('QMS-REC', 'QMS records: audits, management reviews, corrective actions', 5, 'record closed'),
  ('QMS-SUP', 'Superseded controlled documents', 5, 'superseded'),
  ('FIN-TRV', 'Travel requests, bookings and claims', 7, 'end of financial year'),
  ('FIN-AST', 'Asset register and disposal records', 7, 'asset disposal (life of asset + 7 years)'),
  ('SYS-LOG', 'System audit logs', 3, 'log date [to confirm]');

insert into public.qms_settings (key, value, note) values
  ('review_months',            '12',  'Default review period after approval'),
  ('check_working_days',       '5',   'QMS Administrator check turnaround'),
  ('approval_nudge_days',      '3',   '[D-05] reminder to approver, repeated'),
  ('approval_escalate_days',   '10',  '[D-05] escalate to CEO (or Board Treasurer)'),
  ('review_reminder_days',     '30',  'Review-due reminder'),
  ('ack_working_days',         '10',  'Policy acknowledgement window (Release 2)'),
  ('superseded_retention_years','5',  'QMS-POL-INF-003: superseded controlled documents'),
  ('notification_retention_years','2','[to confirm]');

-- South African public holidays (Public Holidays Act; Sunday holidays move to Monday)
insert into public.qms_non_working_day (day, reason) values
  ('2026-12-16', 'Day of Reconciliation'),
  ('2026-12-25', 'Christmas Day'),
  ('2027-01-01', 'New Year''s Day'),
  ('2027-03-22', 'Human Rights Day (observed)'),
  ('2027-03-26', 'Good Friday'),
  ('2027-03-29', 'Family Day'),
  ('2027-04-27', 'Freedom Day'),
  ('2027-06-16', 'Youth Day'),
  ('2027-08-09', 'National Women''s Day'),
  ('2027-09-24', 'Heritage Day'),
  ('2027-12-16', 'Day of Reconciliation'),
  ('2027-12-27', 'Goodwill Day (observed)');

-- December office closure: add each closure day once the dates are set, e.g.
-- insert into public.qms_non_working_day (day, reason)
-- select d::date, 'December closure' from generate_series('[2026-12-14]'::date, '[2027-01-04]'::date, '1 day') d
-- on conflict (day) do nothing;

-- Roles: link each person's Supabase auth user to their QMS role(s). Use roles, not names.
-- insert into public.qms_user_role (user_id, role, department) values
--   ('<auth user id>', 'qms_admin',        'OPS'),
--   ('<auth user id>', 'ceo',              'EXE'),
--   ('<auth user id>', 'head_ops_systems', 'OPS'),
--   ('<auth user id>', 'hod',              'FIN'),   -- one row per HOD and department
--   ('<auth user id>', 'hod',              'REP'),   -- HOD Reports
--   ('<auth user id>', 'board_treasurer',  null);
-- Every staff member also gets ('<id>', 'staff', '<department>'); mentors get ('<id>', 'mentor', null, '<programme>').
-- Master Document Register starting list: the documents drafted in Batches 1 to 5.
-- All load as class 1 Drafts (none is approved yet). The QMS Administrator sets the
-- process code and uploads each Word file before submitting it. QMS-05 asset documents
-- keep their working codes in previous_code until recoded (decision D-11).
insert into public.qms_document (code, previous_code, title, doc_class, doc_type, domain, department, is_governance, owner_role, visible_to) values
  (null, 'QMS-05', 'Asset Management Procedure', 1, 'SOP', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05 Asset Management Procedure.docx (Draft)
  (null, 'QMS-05-FRM-01', 'Asset Purchase Request', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-01 Asset Purchase Request.docx (Draft)
  (null, 'QMS-05-FRM-02', 'Equipment Issue and Acknowledgement', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-02 Equipment Issue and Acknowledgement.docx (Draft)
  (null, 'QMS-05-FRM-03', 'Asset Return and Internal Transfer', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-03 Asset Return and Internal Transfer.docx (Draft)
  (null, 'QMS-05-FRM-04', 'Loss, Theft and Damage Report', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-04 Loss, Theft and Damage Report.docx (Draft)
  (null, 'QMS-05-FRM-05', 'Donation Received Record', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-05 Donation Received Record.docx (Draft)
  (null, 'QMS-05-FRM-06', 'Asset Donation or Transfer Certificate', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-06 Asset Donation or Transfer Certificate.docx (Draft)
  (null, 'QMS-05-FRM-07', 'Store Booking, Check-out and Return', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-07 Store Booking, Check-out and Return.docx (Draft)
  (null, 'QMS-05-FRM-08', 'Device Preparation and Pre-handover Check', 1, 'FRM', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-FRM-08 Device Preparation and Pre-handover Check.docx (Draft)
  (null, 'QMS-05-GUI-01', 'Staff Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-01 Staff Guide.docx (Draft)
  (null, 'QMS-05-GUI-02', 'Factotum Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-02 Factotum Guide.docx (Draft)
  (null, 'QMS-05-GUI-03', 'Asset Coordinator Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-03 Asset Coordinator Guide.docx (Draft)
  (null, 'QMS-05-GUI-04', 'Management Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-04 Management Guide.docx (Draft)
  (null, 'QMS-05-GUI-05', 'Department Asset Contact Guide', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-GUI-05 Department Asset Contact Guide.docx (Draft)
  (null, 'QMS-05-WF-01', 'Asset Management Workflows', 1, 'MAP', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-05-WF-01 Asset Management Workflows.docx (Draft)
  ('QMS-GUI-GOV-001', null, 'Staff Guide Document Control and QMS Management', 1, 'GUI', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-GUI-GOV-001_Staff_Guide_Document_Control_and_QMS_Management_Draft_0.2.docx (Draft 0.2)
  ('QMS-GUI-OPS-001', null, 'Staff Guide Travel Hub', 1, 'GUI', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-GUI-OPS-001_Staff_Guide_Travel_Hub_Draft_0.1.docx (Draft 0.1)
  ('QMS-MAN-GOV-001', null, 'Quality Management System Manual', 1, 'MAN', 'GOV', 'GOV', true, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-MAN-GOV-001_Quality_Management_System_Manual_v2.0_DRAFT.docx (v2.0 DRAFT)
  ('QMS-MAP-GOV-001', null, 'Process Map Register', 1, 'MAP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-MAP-GOV-001_Process_Map_Register_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-POL-FIN-002', null, 'Travel and Subsistence Policy', 1, 'POL', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-FIN-002_Travel_and_Subsistence_Policy_v2.0_DRAFT.docx (v2.0 DRAFT)
  ('QMS-POL-FIN-003', null, 'Asset Management Policy', 1, 'POL', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-FIN-003_Asset_Management_Policy_Draft_0.3.docx (Draft 0.3)
  ('QMS-POL-GOV-007', null, 'Code of Ethics and Conduct', 1, 'POL', 'GOV', 'GOV', true, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-GOV-007_Code_of_Ethics_and_Conduct_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-POL-GOV-008', null, 'Anti-Fraud Bribery and Corruption Policy', 1, 'POL', 'GOV', 'GOV', true, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-GOV-008_Anti-Fraud_Bribery_and_Corruption_Policy_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-POL-INF-003', null, 'Records Retention and Destruction Policy', 1, 'POL', 'INF', 'QMS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-POL-INF-003_Records_Retention_and_Destruction_Policy_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-REG-COM-001', null, 'Compliance Obligations Register', 1, 'REG', 'COM', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-COM-001_Compliance_Obligations_Register_v1.1_DRAFT.xlsx (v1.1 DRAFT)
  ('QMS-REG-GOV-008', null, 'Context and Interested Parties Register', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-008_Context_and_Interested_Parties_Register_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-GOV-009', null, 'Quality Objectives and KPI Plan', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-009_Quality_Objectives_and_KPI_Plan_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-GOV-010', null, 'Internal Audit Programme and Stage 1 Readiness', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-010_Internal_Audit_Programme_and_Stage_1_Readiness_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-GOV-011', null, 'Risk Incident and Corrective Action Register', 1, 'REG', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-GOV-011_Risk_Incident_and_Corrective_Action_Register_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-REG-INF-003', null, 'Systems and Operator Inventory', 1, 'REG', 'INF', 'QMS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-REG-INF-003_Systems_and_Operator_Inventory_v0.1_DRAFT.xlsx (v0.1 DRAFT)
  ('QMS-SOP-COM-008', null, 'NPO Act Statutory Compliance Procedure', 1, 'SOP', 'COM', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-COM-008_NPO_Act_Statutory_Compliance_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-COM-009', null, 'Terrorist-Financing Risk and Partner Due Diligence Procedure', 1, 'SOP', 'COM', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-COM-009_Terrorist-Financing_Risk_and_Partner_Due_Diligence_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-FIN-006', null, 'Donations and Section 18A Receipts Procedure', 1, 'SOP', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-FIN-006_Donations_and_Section_18A_Receipts_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-FIN-007', null, 'VAT Compliance Procedure', 1, 'SOP', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-FIN-007_VAT_Compliance_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-FIN-008', null, 'Payroll Administration and Statutory Compliance Procedure', 1, 'SOP', 'FIN', 'FIN', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-FIN-008_Payroll_Administration_and_Statutory_Compliance_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-001', null, 'Document Control Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-001_Document_Control_Procedure_v2.0_DRAFT.docx (v2.0 DRAFT)
  ('QMS-SOP-GOV-006', null, 'Complaints and Feedback Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-006_Complaints_and_Feedback_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-007', null, 'Client Report Quality Review Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-007_Client_Report_Quality_Review_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-008', null, 'Programme Design and Development Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-008_Programme_Design_and_Development_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-009', null, 'Communication Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-009_Communication_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-010', null, 'Change Management Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-010_Change_Management_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-011', null, 'Client and Beneficiary Satisfaction Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-011_Client_and_Beneficiary_Satisfaction_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-GOV-012', null, 'Knowledge Management Procedure', 1, 'SOP', 'GOV', 'GOV', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']),  -- QMS-SOP-GOV-012_Knowledge_Management_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)
  ('QMS-SOP-OPS-001', null, 'Client-Funded Programme Evidence Control Procedure', 1, 'SOP', 'OPS', 'OPS', false, 'Operations and Programme Systems Coordinator (QMS Administrator)', array['all_staff']);  -- QMS-SOP-OPS-001_Client-Funded_Programme_Evidence_Control_Procedure_v0.1_DRAFT.docx (v0.1 DRAFT)

-- First draft version for each seeded document (no file attached yet)
insert into public.qms_version (document_id, draft_seq, author_id)
select id, 1, null from public.qms_document where current_version_id is null;
update public.qms_document d set current_version_id = v.id
from public.qms_version v where v.document_id = d.id and d.current_version_id is null;
