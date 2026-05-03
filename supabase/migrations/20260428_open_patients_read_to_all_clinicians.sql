-- ============================================================
-- Phase 6 follow-up: open patients SELECT to all clinicians
-- ============================================================
-- Date: 2026-04-28
--
-- Background: the original 2026-04-28 migration scoped patient
-- visibility per clinician (`auth.uid() = clinician_id`). For V1
-- internal testing, we want any clinician account to see the full
-- shared patient roster — clinically a patient might be referred
-- between clinicians, and forcing per-clinician isolation makes
-- testing harder.
--
-- This migration replaces the SELECT policy. INSERT / UPDATE
-- policies stay unchanged: only the creating clinician can edit
-- or archive their own patients (data-integrity guard).
--
-- Patient accounts continue to see only their own claimed record.
--
-- Idempotent (DROP IF EXISTS before each CREATE).

-- Replace the per-clinician SELECT policy with a shared one
DROP POLICY IF EXISTS "Clinicians can read own patients" ON patients;
DROP POLICY IF EXISTS "Clinicians can read all patients" ON patients;

CREATE POLICY "Clinicians can read all patients"
    ON patients FOR SELECT
    USING (
        archived_at IS NULL
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
              AND account_type = 'clinician'
        )
    );

-- Patient self-claim policy is unchanged (left in place by the
-- earlier migration). Re-asserted here for clarity.
DROP POLICY IF EXISTS "Patients can read own claimed record" ON patients;
CREATE POLICY "Patients can read own claimed record"
    ON patients FOR SELECT
    USING (auth.uid() = claimed_user_id AND archived_at IS NULL);

-- INSERT / UPDATE policies are intentionally unchanged: a clinician
-- can only insert patients with their own id as clinician_id, and
-- can only update patients they themselves created. This protects
-- against accidental cross-clinician edits.

-- ─── End of migration ──────────────────────────────────────
