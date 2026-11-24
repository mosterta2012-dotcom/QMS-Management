-- =====================================================================
-- OPTIONAL: daily reminders and Teams/e-mail notifications.
-- The web app works without this; it publishes approved PDFs itself.
-- Needs: Database > Extensions > enable pg_cron and pg_net,
-- and the qms-notify edge function deployed with its secrets (README step 6).
-- Replace <project-ref> and <secret> (same as QMS_FUNCTION_SECRET), then Run.
-- =====================================================================
select cron.schedule('qms-reminders', '30 5 * * 1-5', $$select public.qms_run_reminders()$$);   -- 07:30 SA time
select cron.schedule('qms-jobs', '*/5 * * * *', $$
  select net.http_post(url := 'https://<project-ref>.supabase.co/functions/v1/qms-publish', headers := '{"x-qms-secret":"<secret>"}'::jsonb);
  select net.http_post(url := 'https://<project-ref>.supabase.co/functions/v1/qms-notify',  headers := '{"x-qms-secret":"<secret>"}'::jsonb);
$$);
