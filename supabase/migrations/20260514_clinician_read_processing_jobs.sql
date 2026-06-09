-- ============================================================
-- Phase 8 follow-up: clinicians can read all processing_jobs
-- ============================================================
-- Date: 2026-05-14
--
-- Background: the existing `processing_jobs` table (created in the
-- Supabase dashboard before any migration tracking) has RLS that
-- only exposes rows to the user_id that owns them. That worked when
-- everyone was browsing their own uploads, but with Phase 8 a
-- clinician needs to open a patient's PatientDetailView and see:
--   - jobs the patient self-recorded (processing_jobs.user_id = patient.id)
--   - jobs the clinician uploaded and attributed to the patient
--     (processing_jobs.id IN job_patient_attributions.job_id WHERE patient_id = patient.id)
-- Without this policy the History/Processed tabs come back empty
-- for the clinician even though the timeline tab works fine
-- (timeline_events already has the equivalent clinician policy).
--
-- Strategy: piggy-back on the existing `is_clinician(uid)` helper
-- (added 2026-04-29). New SELECT policy is purely additive — patient
-- self-read continues to work via whichever policy currently allows
-- it (auth.uid() = user_id, most likely).
--
-- Idempotent.
-- ============================================================

DROP POLICY IF EXISTS "Clinicians can read all processing_jobs" ON processing_jobs;
CREATE POLICY "Clinicians can read all processing_jobs"
    ON processing_jobs FOR SELECT
    USING (public.is_clinician(auth.uid()));

-- ─── End of migration ──────────────────────────────────────
