-- ============================================================
-- Patients can read processing_jobs attributed to them
-- ============================================================
-- Date: 2026-06-04
--
-- Background: clinicians got a "read all processing_jobs" policy
-- (2026-05-14), but patients still only see jobs they uploaded
-- themselves (the dashboard-defined auth.uid() = user_id policy).
-- When a clinician records FOR a patient, the job's user_id is the
-- clinician and the link to the patient lives in
-- job_patient_attributions. Without a matching read policy the
-- patient's Videos / Timeline come back empty for clinician-recorded
-- assessments — this is the "patient can't see processed videos" bug.
--
-- Strategy: additive SELECT policy. RLS SELECT policies are OR'd, so
-- this only widens access; the existing self-read (auth.uid() =
-- user_id) and clinician read-all policies are untouched.
--
-- Pre-apply check (recommended): confirm the existing self-read
-- policy is PERMISSIVE and uniquely named so it composes correctly:
--     SELECT * FROM pg_policies WHERE tablename = 'processing_jobs';
--
-- Idempotent.
-- ============================================================

DROP POLICY IF EXISTS "Patients can read attributed processing_jobs" ON processing_jobs;
CREATE POLICY "Patients can read attributed processing_jobs"
    ON processing_jobs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.job_patient_attributions jpa
            WHERE jpa.job_id = processing_jobs.id
              AND jpa.patient_id = auth.uid()
        )
    );

-- ─── End of migration ──────────────────────────────────────
