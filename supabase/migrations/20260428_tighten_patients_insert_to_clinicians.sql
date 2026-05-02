-- ============================================================
-- Phase 6 follow-up: tighten patients INSERT to clinicians only
-- ============================================================
-- Date: 2026-04-28
--
-- Background: the original INSERT policy on `patients` only checked
-- `auth.uid() = clinician_id`. That blocks one user from inserting
-- under another's id, but it does NOT prevent a patient-type account
-- from inserting a row with their own id as clinician_id. The app UI
-- doesn't expose that path (patient accounts have no "Patients" tab),
-- but the DB layer was open to direct API calls.
--
-- This migration adds an account_type check so only clinician accounts
-- can insert patient rows. Same pattern as the SELECT policy from the
-- previous follow-up migration.
--
-- Idempotent.

DROP POLICY IF EXISTS "Clinicians can insert own patients" ON patients;
DROP POLICY IF EXISTS "Clinicians can insert patients" ON patients;

CREATE POLICY "Clinicians can insert patients"
    ON patients FOR INSERT
    WITH CHECK (
        auth.uid() = clinician_id
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
              AND account_type = 'clinician'
        )
    );

-- Same hardening for UPDATE: only clinician accounts can update,
-- and only the row's own creator.
DROP POLICY IF EXISTS "Clinicians can update own patients" ON patients;
CREATE POLICY "Clinicians can update own patients"
    ON patients FOR UPDATE
    USING (
        auth.uid() = clinician_id
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
              AND account_type = 'clinician'
        )
    )
    WITH CHECK (
        auth.uid() = clinician_id
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
              AND account_type = 'clinician'
        )
    );

-- ─── End of migration ──────────────────────────────────────
