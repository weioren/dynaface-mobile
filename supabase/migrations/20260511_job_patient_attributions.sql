-- ============================================================
-- Phase 8: job-to-patient attributions
-- ============================================================
-- Date: 2026-05-11
--
-- Background: processing_jobs.user_id captures who recorded a
-- video, but in the hospital flow a clinician records on behalf
-- of a patient — the patient is NOT the uploader. We need a way
-- to ask "which patient does this job belong to?" without
-- modifying Alex's worker or the existing upload pipeline.
--
-- Design: a thin junction table mapping a job to a patient
-- profile. Inserts happen from the iOS side after upload
-- (clinician picks the patient, or the patient is auto-set when
-- a patient account self-records).
--
-- Resolution rule used by the client:
--   effective_patient_id =
--       COALESCE(attribution.patient_id, processing_jobs.user_id)
--   where the fallback only counts when user_id is a patient
--   account (profiles.account_type = 'patient').
--
-- patient_id is uuid (not a FK) for the same reason as
-- timeline_events.patient_id — Alex's parallel patients table
-- may surface non-self-registered patients later.
--
-- Idempotent.
-- ============================================================

-- 1. Table
CREATE TABLE IF NOT EXISTS job_patient_attributions (
    job_id        uuid        PRIMARY KEY REFERENCES processing_jobs(id) ON DELETE CASCADE,
    patient_id    uuid        NOT NULL,                                       -- profiles.id of the patient
    attributed_by uuid        NOT NULL,                                       -- profiles.id of who set the attribution
    attributed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS job_patient_attributions_patient_id_idx
    ON job_patient_attributions(patient_id);

-- 2. RLS
ALTER TABLE job_patient_attributions ENABLE ROW LEVEL SECURITY;

-- SELECT: clinicians see all attributions; patients see only
-- attributions about themselves.
DROP POLICY IF EXISTS "Clinicians can read all attributions" ON job_patient_attributions;
CREATE POLICY "Clinicians can read all attributions"
    ON job_patient_attributions FOR SELECT
    USING (public.is_clinician(auth.uid()));

DROP POLICY IF EXISTS "Patients can read own attributions" ON job_patient_attributions;
CREATE POLICY "Patients can read own attributions"
    ON job_patient_attributions FOR SELECT
    USING (auth.uid() = patient_id);

-- INSERT: clinicians can attribute any job to any patient
-- (attributed_by must match auth.uid() so the audit field is
-- truthful). Patients can attribute a job to themselves only.
DROP POLICY IF EXISTS "Clinicians can insert attributions" ON job_patient_attributions;
CREATE POLICY "Clinicians can insert attributions"
    ON job_patient_attributions FOR INSERT
    WITH CHECK (
        public.is_clinician(auth.uid())
        AND auth.uid() = attributed_by
    );

DROP POLICY IF EXISTS "Patients can insert self-attributions" ON job_patient_attributions;
CREATE POLICY "Patients can insert self-attributions"
    ON job_patient_attributions FOR INSERT
    WITH CHECK (
        auth.uid() = patient_id
        AND auth.uid() = attributed_by
    );

-- UPDATE: clinicians can re-attribute (e.g. fix a wrong pick).
-- Patients cannot re-attribute existing rows.
DROP POLICY IF EXISTS "Clinicians can update attributions" ON job_patient_attributions;
CREATE POLICY "Clinicians can update attributions"
    ON job_patient_attributions FOR UPDATE
    USING (public.is_clinician(auth.uid()))
    WITH CHECK (public.is_clinician(auth.uid()));

-- DELETE: clinicians can remove an attribution (mark as
-- unattributed). Patients cannot.
DROP POLICY IF EXISTS "Clinicians can delete attributions" ON job_patient_attributions;
CREATE POLICY "Clinicians can delete attributions"
    ON job_patient_attributions FOR DELETE
    USING (public.is_clinician(auth.uid()));

-- ─── End of migration ──────────────────────────────────────
