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
