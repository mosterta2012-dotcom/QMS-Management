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
