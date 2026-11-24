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
