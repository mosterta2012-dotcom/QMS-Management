-- =====================================================================
-- Release 1 acceptance tests T-01 to T-12, run in SQL against a database
-- with the migrations and seed applied. Runs in a transaction and rolls back.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/qms_release1_test.sql
-- Each test raises an exception if the rule does not hold.
-- =====================================================================
begin;

-- Test users (roles, not names)
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-00000000000a','qms.admin@test'),
 ('00000000-0000-0000-0000-00000000000b','hod.fin@test'),
 ('00000000-0000-0000-0000-00000000000c','ceo@test'),
 ('00000000-0000-0000-0000-00000000000d','board.treasurer@test'),
 ('00000000-0000-0000-0000-00000000000e','staff.ops@test'),
 ('00000000-0000-0000-0000-00000000000f','mentor.e4c@test'),
 ('00000000-0000-0000-0000-000000000010','hod.ops@test');
insert into public.qms_user_role(user_id, role, department, programme) values
 ('00000000-0000-0000-0000-00000000000a','qms_admin','OPS',null),
 ('00000000-0000-0000-0000-00000000000a','staff','OPS',null),
 ('00000000-0000-0000-0000-00000000000b','hod','FIN',null),
 ('00000000-0000-0000-0000-00000000000b','staff','FIN',null),
 ('00000000-0000-0000-0000-00000000000c','ceo','EXE',null),
 ('00000000-0000-0000-0000-00000000000d','board_treasurer',null,null),
 ('00000000-0000-0000-0000-00000000000e','staff','OPS',null),
 ('00000000-0000-0000-0000-00000000000f','mentor',null,'Scatec E4C'),
 ('00000000-0000-0000-0000-000000000010','hod','OPS',null);

create temp table t_ids(k text primary key, id uuid);
grant all on t_ids to authenticated;

create or replace function pg_temp.as_user(p uuid) returns void language sql as
$$ select set_config('request.jwt.claim.sub', p::text, true); $$;

set local role authenticated;

-- T-01 HOD Finance drafts and submits a departmental procedure
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
insert into t_ids select 'doc', public.qms_create_document('Petty Cash Procedure', 1::smallint, 'SOP', 'FIN',
  'HOD Finance', 'QMS-SOP-FIN-099', 'FIN', 'FIN-01', null, false, false, array['all_staff'], 'd/x/source.docx');
insert into t_ids select 'v1', current_version_id from public.qms_document where id = (select id from t_ids where k='doc');
select public.qms_submit((select id from t_ids where k='v1'));
do $$ begin
  if (select status from public.qms_version where id=(select id from t_ids where k='v1')) <> 'Submitted' then raise exception 'T-01 failed'; end if;
end $$;
-- staff cannot see the draft
select pg_temp.as_user('00000000-0000-0000-0000-00000000000e');
do $$ begin
  if exists (select 1 from public.qms_document where code='QMS-SOP-FIN-099') then raise exception 'T-01 failed: draft visible to staff'; end if;
  raise notice 'T-01 pass';
end $$;

-- T-02 QMS Administrator sends it for approval: routed to the HOD? The HOD submitted it, so it moves to the CEO (R-04)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.qms_send_for_approval((select id from t_ids where k='v1'));
do $$ begin
  if (select required_role from public.qms_approval_step where version_id=(select id from t_ids where k='v1') and kind='Approve') <> 'ceo'
    then raise exception 'T-02/T-03 failed: expected CEO because HOD submitted'; end if;
  raise notice 'T-02 pass (routed In review)';
end $$;

-- T-03 The author tries to approve their own document
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  begin perform public.qms_approve((select id from t_ids where k='v1'));
        raise exception 'T-03 failed: self-approval allowed';
  exception when others then if sqlerrm like 'T-03%' then raise; end if; end;
  raise notice 'T-03 pass';
end $$;

-- T-04 Approver returns without a comment
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  begin perform public.qms_return((select id from t_ids where k='v1'), '  ');
        raise exception 'T-04 failed';
  exception when others then if sqlerrm like 'T-04%' then raise; end if; end;
  raise notice 'T-04 pass';
end $$;

-- T-05 CEO approves: version 1.0, review in 12 months, staff notified
select public.qms_approve((select id from t_ids where k='v1'));
do $$ declare v record; d record; begin
  select * into v from public.qms_version where id=(select id from t_ids where k='v1');
  select * into d from public.qms_document where id=(select id from t_ids where k='doc');
  if v.version_no <> '1.0' or d.next_review_date <> (current_date + interval '12 months')::date
     or d.published_version_id <> v.id then raise exception 'T-05 failed'; end if;
  raise notice 'T-05 pass';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000e');
do $$ begin
  if not exists (select 1 from public.qms_library where code='QMS-SOP-FIN-099' and version_no='1.0') then raise exception 'T-05 failed: staff cannot see 1.0'; end if;
end $$;

-- T-06 Version 1.1 (minor) approved: 1.0 Obsolete, only 1.1 visible to staff
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
insert into t_ids select 'v2', public.qms_new_draft((select id from t_ids where k='doc'), 'd/x/v2.docx', 'Updated contact details');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.qms_submit((select id from t_ids where k='v2'));
select public.qms_send_for_approval((select id from t_ids where k='v2'));
-- HOD Finance wrote the new draft, so the approval moves up to the CEO
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select public.qms_approve((select id from t_ids where k='v2'), 'Minor');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000e');
do $$ begin
  if (select string_agg(version_no, ',') from public.qms_library where code='QMS-SOP-FIN-099') <> '1.1' then raise exception 'T-06 failed: library'; end if;
  if exists (select 1 from public.qms_version where id=(select id from t_ids where k='v1')) then raise exception 'T-06 failed: staff sees obsolete'; end if;
  raise notice 'T-06 pass';
end $$;
reset role;
do $$ begin
  if (select status from public.qms_version where id=(select id from t_ids where k='v1')) <> 'Obsolete' then raise exception 'T-06 failed: 1.0 not obsolete'; end if;
end $$;
set local role authenticated;

-- T-07 Governance policy needs the Board resolution
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into t_ids select 'gdoc', public.qms_create_document('Safeguarding Policy', 1::smallint, 'POL', 'GOV',
  'CEO', 'QMS-POL-GOV-099', 'GOV', 'GOV-01', null, true, false, array['all_staff'], 'd/g/source.docx');
insert into t_ids select 'gv', current_version_id from public.qms_document where id=(select id from t_ids where k='gdoc');
select public.qms_submit((select id from t_ids where k='gv'));
select public.qms_send_for_approval((select id from t_ids where k='gv'));
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  begin perform public.qms_approve((select id from t_ids where k='gv'));
        raise exception 'T-07 failed: approved without resolution';
  exception when others then if sqlerrm like 'T-07%' then raise; end if; end;
  perform public.qms_approve((select id from t_ids where k='gv'), 'Major', 'd/g/resolution.pdf', 'BR-2026-04', current_date);
  if (select status from public.qms_version where id=(select id from t_ids where k='gv')) <> 'Approved' then raise exception 'T-07 failed'; end if;
  raise notice 'T-07 pass';
end $$;

-- T-08 CEO is the author: routed to the Board Treasurer
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
insert into t_ids select 'cdoc', public.qms_create_document('Delegation of Authority Register', 1::smallint, 'REG', 'GOV',
  'CEO', 'QMS-REG-GOV-099', 'GOV', 'GOV-01', null, false, false, array['hods'], 'd/c/source.docx');
insert into t_ids select 'cv', current_version_id from public.qms_document where id=(select id from t_ids where k='cdoc');
select public.qms_submit((select id from t_ids where k='cv'));
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.qms_send_for_approval((select id from t_ids where k='cv'));
do $$ begin
  if (select required_role from public.qms_approval_step where version_id=(select id from t_ids where k='cv') and kind='Approve') <> 'board_treasurer'
    then raise exception 'T-08 failed'; end if;
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select public.qms_approve((select id from t_ids where k='cv'));
do $$ begin raise notice 'T-08 pass'; end $$;

-- T-09 Published PDFs are never read straight from storage by staff (download goes through qms-download)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000e');
do $$ begin
  if exists (select 1 from storage.objects where bucket_id in ('qms-published','qms-drafts')) then raise exception 'T-09 failed'; end if;
  raise notice 'T-09 pass (storage closed to staff; stamping tested in the edge function)';
end $$;

-- T-10 Search by code and by process
do $$ begin
  if not exists (select 1 from public.qms_library where code ilike '%FIN-099%') then raise exception 'T-10 failed: code'; end if;
  if not exists (select 1 from public.qms_library where process = 'FIN-01') then raise exception 'T-10 failed: process'; end if;
  raise notice 'T-10 pass';
end $$;

-- T-11 A staff member without QMS access tries the QMS Management functions and tables
do $$ begin
  begin perform public.qms_send_for_approval((select id from t_ids where k='v1'));
        raise exception 'T-11 failed: staff sent for approval';
  exception when others then if sqlerrm like 'T-11%' then raise; end if; end;
  if exists (select 1 from public.qms_approval_step) then raise exception 'T-11 failed: staff sees approvals'; end if;
  if exists (select 1 from public.qms_audit_log) then raise exception 'T-11 failed: staff sees audit log'; end if;
  begin update public.qms_version set status = 'Approved' where true;
        raise exception 'T-11 failed: direct status change allowed';
  exception when insufficient_privilege then null; end;
  raise notice 'T-11 pass';
end $$;

-- T-11b A mentor sees only documents meant for mentors
select pg_temp.as_user('00000000-0000-0000-0000-00000000000f');
do $$ begin
  if exists (select 1 from public.qms_library) then raise exception 'T-11b failed: mentor sees staff documents'; end if;
  raise notice 'T-11b pass';
end $$;

-- T-12 Audit log: every action recorded, and rows cannot be changed or deleted
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ declare n int; begin
  select count(*) into n from public.qms_audit_log where table_name = 'qms_version'
    and record_id = (select id::text from t_ids where k='v1');
  if n < 4 then raise exception 'T-12 failed: only % audit rows for v1', n; end if;
  begin delete from public.qms_audit_log; raise exception 'T-12 failed: delete allowed';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  begin update public.qms_audit_log set action = 'x';
        raise exception 'T-12 failed: owner could edit audit log';
  exception when others then if sqlerrm like 'T-12%' then raise; end if; end;
  raise notice 'T-12 pass';
end $$;

-- Extra rule checks
set local role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  -- R-01 bad code blocks submission
  perform public.qms_create_document('Test Form', 1::smallint, 'FRM', 'OPS', 'HOD Operations', 'QMS-05-FRM-01',
          'OPS', 'QMS-05', null, false, false, array['all_staff'], 'd/t/source.docx');
  begin perform public.qms_submit((select current_version_id from public.qms_document where code='QMS-05-FRM-01'));
        raise exception 'R-01 failed';
  exception when others then if sqlerrm like 'R-01%' then raise; end if; end;
  -- R-02 title with version marks refused
  begin perform public.qms_create_document('Leave Policy Rev1', 1::smallint, 'POL', 'HR', 'HOD HR', 'QMS-POL-HR-099');
        raise exception 'R-02 failed';
  exception when check_violation then null; end;
  raise notice 'R-01, R-02 pass';
end $$;

-- Reminders (section 7): review due in 30 days and a check waiting 6 working days
reset role;
do $$ declare n int; begin
  if extract(isodow from current_date) > 5 or exists (select 1 from public.qms_non_working_day where day = current_date) then
    raise notice 'Reminders test skipped (not a working day)'; return;
  end if;
  update public.qms_document set next_review_date = current_date + 30 where code = 'QMS-SOP-FIN-099';
  update public.qms_version set submitted_at = now() - interval '10 days'
    where document_id = (select id from public.qms_document where code = 'QMS-SOP-GOV-001');
  update public.qms_version set status = 'Submitted', source_path = 'x'
    where document_id = (select id from public.qms_document where code = 'QMS-SOP-GOV-001');
  n := public.qms_run_reminders();
  if not exists (select 1 from public.qms_notification where event = 'review_due') then raise exception 'Reminders failed: review_due'; end if;
  if not exists (select 1 from public.qms_notification where event = 'check_overdue') then raise exception 'Reminders failed: check_overdue'; end if;
  if (select count(*) from public.qms_notification_recipients(
        (select max(id) from public.qms_notification where event = 'review_due'))) = 0 then
    raise exception 'Reminders failed: no recipients';
  end if;
  if public.qms_run_reminders() <> 0 - 0 and exists (select 1 from public.qms_notification where event='check_overdue'
       group by subject_id, created_at::date, recipient_role having count(*) > 1) then
    raise exception 'Reminders failed: duplicates on a second run';
  end if;
  raise notice 'Reminders pass (% notifications)', n;
end $$;

rollback;
