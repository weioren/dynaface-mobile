-- ============================================================
-- Phase 9: assessment events on the timeline
-- ============================================================
-- Date: 2026-05-14
--
-- Background: an "assessment" is the act of recording one or more
-- exercises and uploading them. After the upload completes, the user
-- (clinician via the post-attribution confirmation, or patient via
-- a self-record confirmation) can elect to add an event of type
-- 'assessment' to the patient's timeline. The event keeps a link
-- back to the originating processing_jobs row so the user can tap
-- it to play the annotated video later.
--
-- Changes:
--   1. Add `job_id` column to timeline_events (nullable; only set on
--      assessment-type rows). FK to processing_jobs(id), ON DELETE SET
--      NULL so deleting a job doesn't drop the audit trail.
--   2. Extend the type CHECK constraint to allow 'assessment'.
--
-- RLS policies from 20260508 are unchanged — they already cover
-- whichever role inserts/reads, and the new type is just data.
--
-- Idempotent.
-- ============================================================

-- 1. New column
ALTER TABLE timeline_events
    ADD COLUMN IF NOT EXISTS job_id uuid REFERENCES processing_jobs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS timeline_events_job_id_idx
    ON timeline_events(job_id);

-- 2. Extend the type CHECK to include 'assessment'
ALTER TABLE timeline_events DROP CONSTRAINT IF EXISTS timeline_events_type_check;
ALTER TABLE timeline_events
    ADD CONSTRAINT timeline_events_type_check
    CHECK (type IN ('surgery','injection','clinic_visit','note','assessment'));

-- ─── End of migration ──────────────────────────────────────
