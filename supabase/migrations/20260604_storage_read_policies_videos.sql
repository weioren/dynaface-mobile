-- ============================================================
-- Storage read policies: raw + processed videos
-- ============================================================
-- Date: 2026-06-04
--
-- Background: the iOS client builds short-lived signed URLs to play
-- videos, and createSignedURL is gated by storage.objects RLS. The
-- `results` bucket already lets the uploader read their processed
-- output, but:
--   - patients can't read videos a clinician recorded for them
--     (the object's path prefix is the clinician's uid, not the
--     patient's), and
--   - the `raw-videos` bucket has no read policy at all, so the
--     patient "Original" segment never resolves.
--
-- Object path convention (set by VideoUploadService and the worker):
--     {uploader_uid}/{job_id}/<file>
--   so (storage.foldername(name))[1] = uploader uid
--      (storage.foldername(name))[2] = job id
--
-- Access granted (additive / permissive, OR'd with any existing
-- policy on storage.objects):
--   - clinicians: read all (mirrors the processing_jobs read-all)
--   - uploader:   read their own objects
--   - attributed patient: read objects for jobs attributed to them
--
-- Idempotent. Note: storage.objects RLS is already enabled by
-- Supabase. If `supabase db push` lacks privileges on
-- storage.objects, run this in the dashboard SQL editor instead.
-- ============================================================

-- raw-videos bucket (the "Original" recordings)
DROP POLICY IF EXISTS "Read raw-videos: clinician, owner, or attributed patient" ON storage.objects;
CREATE POLICY "Read raw-videos: clinician, owner, or attributed patient"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'raw-videos'
        AND (
            public.is_clinician(auth.uid())
            OR (storage.foldername(name))[1] = auth.uid()::text
            OR EXISTS (
                SELECT 1 FROM public.job_patient_attributions jpa
                WHERE jpa.patient_id = auth.uid()
                  AND jpa.job_id::text = (storage.foldername(name))[2]
            )
        )
    );

-- results bucket (the "Analyzed" / processed output)
DROP POLICY IF EXISTS "Read results: clinician, owner, or attributed patient" ON storage.objects;
CREATE POLICY "Read results: clinician, owner, or attributed patient"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'results'
        AND (
            public.is_clinician(auth.uid())
            OR (storage.foldername(name))[1] = auth.uid()::text
            OR EXISTS (
                SELECT 1 FROM public.job_patient_attributions jpa
                WHERE jpa.patient_id = auth.uid()
                  AND jpa.job_id::text = (storage.foldername(name))[2]
            )
        )
    );

-- ─── End of migration ──────────────────────────────────────
