-- Phase 6: account-type split + patients table
-- Author: Weichao
-- Date: 2026-04-27
--
-- This migration introduces the clinician/patient account split per the
-- 2026-04-26 UX/UI overhaul. Clinicians own a list of their patients; each
-- patient row is owned (and only visible to) the clinician that created it
-- via row-level security.
--
-- Run order:
--   1. Add account_type column to existing profiles table (defaults to
--      'patient' for legacy rows so nothing breaks).
--   2. Create patients table.
--   3. Index for clinician_id lookups.
--   4. Enable RLS and add the four CRUD policies.

------------------------------------------------------------------------
-- 1. profiles.account_type
------------------------------------------------------------------------

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS account_type text NOT NULL DEFAULT 'patient'
    CHECK (account_type IN ('clinician', 'patient'));

------------------------------------------------------------------------
-- 2. patients table
------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS patients (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clinician_id uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name         text        NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

------------------------------------------------------------------------
-- 3. Index for clinician_id (most common query pattern)
------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS patients_clinician_id_idx
    ON patients(clinician_id);

------------------------------------------------------------------------
-- 4. Row-level security
------------------------------------------------------------------------

ALTER TABLE patients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clinicians can read their own patients" ON patients;
CREATE POLICY "Clinicians can read their own patients"
    ON patients FOR SELECT
    USING (auth.uid() = clinician_id);

DROP POLICY IF EXISTS "Clinicians can insert patients for themselves" ON patients;
CREATE POLICY "Clinicians can insert patients for themselves"
    ON patients FOR INSERT
    WITH CHECK (auth.uid() = clinician_id);

DROP POLICY IF EXISTS "Clinicians can update their own patients" ON patients;
CREATE POLICY "Clinicians can update their own patients"
    ON patients FOR UPDATE
    USING (auth.uid() = clinician_id);

DROP POLICY IF EXISTS "Clinicians can delete their own patients" ON patients;
CREATE POLICY "Clinicians can delete their own patients"
    ON patients FOR DELETE
    USING (auth.uid() = clinician_id);

-- End of migration.
