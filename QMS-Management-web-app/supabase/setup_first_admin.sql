-- =====================================================================
-- QMS Management: give the first people their roles (SQL Editor)
-- 1. Supabase > Authentication > Users > Add user (tick "Auto Confirm User")
--    for each person, with their work e-mail and a temporary password.
-- 2. Replace the e-mail addresses below, delete lines you do not need, then Run.
-- After this, the QMS Administrator gives further roles in the web app
-- (People and roles). Use roles, not names.
-- Departments: GOV QMS OPS TD SG ME REP FIN HR PR EXE
-- =====================================================================
select public.qms_grant_role('qms.administrator@your-domain', 'qms_admin', 'OPS');
select public.qms_grant_role('qms.administrator@your-domain', 'staff', 'OPS');

-- select public.qms_grant_role('head.ops@your-domain',  'head_ops_systems', 'OPS');
-- select public.qms_grant_role('head.ops@your-domain',  'hod', 'OPS');
-- select public.qms_grant_role('ceo@your-domain',       'ceo', 'EXE');
-- select public.qms_grant_role('hod.finance@your-domain','hod', 'FIN');
-- select public.qms_grant_role('hod.hr@your-domain',    'hod', 'HR');
-- select public.qms_grant_role('hod.reports@your-domain','hod', 'REP');
-- select public.qms_grant_role('treasurer@your-domain', 'board_treasurer');
-- select public.qms_grant_role('staff.member@your-domain', 'staff', 'OPS');
-- select public.qms_grant_role('mentor@your-domain', 'mentor', null, 'Scatec E4C');

-- Check:
select u.email, r.role, r.department, r.programme
from public.qms_user_role r join auth.users u on u.id = r.user_id order by u.email;
