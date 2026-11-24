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
