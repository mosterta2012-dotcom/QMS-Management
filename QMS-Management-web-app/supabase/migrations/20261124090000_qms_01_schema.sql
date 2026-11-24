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
