-- ============================================================
-- Allow deleting non-assessment timeline events
-- ============================================================
-- Date: 2026-06-15
--
-- Background: the 2026-05-08 migration intentionally shipped no DELETE
-- policy on timeline_events (audit hygiene). Per the 6/14 meeting,
-- patients (and clinicians) should be able to remove manual entries
-- they no longer want — but ONLY non-assessment rows. Assessment events
-- are system-generated (linked to a processing_jobs row) and must stay
-- non-deletable so the assessment audit trail is preserved.
--
-- Access granted (additive; assessment rows are excluded by the
-- `type <> 'assessment'` guard in every clause):
--   - patient:   delete their own non-assessment events
--   - clinician: delete any non-assessment event
-- The UI gates this behind an extra confirmation popup.
--
-- Idempotent.
-- ============================================================

DROP POLICY IF EXISTS "Patients can delete own non-assessment events" ON timeline_events;
CREATE POLICY "Patients can delete own non-assessment events"
    ON timeline_events FOR DELETE
    USING (
        auth.uid() = patient_id
        AND type <> 'assessment'
    );

DROP POLICY IF EXISTS "Clinicians can delete non-assessment events" ON timeline_events;
CREATE POLICY "Clinicians can delete non-assessment events"
    ON timeline_events FOR DELETE
    USING (
        public.is_clinician(auth.uid())
        AND type <> 'assessment'
    );

-- ─── End of migration ──────────────────────────────────────
