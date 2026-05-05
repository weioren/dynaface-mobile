-- ============================================================
-- Phase 6 — PR a: account types + patient roster
-- ============================================================
-- Date: 2026-04-28
--
-- Purpose: DB foundation for the clinician / patient account split.
-- This migration is PURELY ADDITIVE — no existing column, table, or
-- policy is modified or dropped. Existing Swift code paths (signup,
-- login, video upload, processing_jobs queries) keep working
-- unchanged after this migration runs.
--
-- Idempotent: safe to re-run.
--
-- Verify after running:
--   1. SELECT * FROM profiles LIMIT 1;
--      -- should show two new columns: account_type='patient', updated_at
--   2. \d patients
--      -- should show 7 columns + 2 indexes + RLS enabled
--   3. SELECT * FROM pg_policies WHERE tablename = 'patients';
--      -- should show 4 policies (no DELETE policy by design)
--   4. Existing app login + video upload should work unchanged.
-- ============================================================

-- ─── 1. profiles: add account_type ──────────────────────────

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS account_type text NOT NULL DEFAULT 'patient'
    CHECK (account_type IN ('clinician', 'patient'));

-- ─── 2. profiles: add updated_at ────────────────────────────

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- ─── 3. shared updated_at trigger function ──────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS profiles_set_updated_at ON profiles;
CREATE TRIGGER profiles_set_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── 4. patients table (clinician's roster) ─────────────────

CREATE TABLE IF NOT EXISTS patients (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clinician_id    uuid        NOT NULL,                       -- profiles.id (by convention)
    claimed_user_id uuid,                                       -- nullable; future patient-account linkage
    name            text        NOT NULL,
    archived_at     timestamptz,                                -- soft-delete; non-null hides via RLS
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS patients_clinician_id_idx
    ON patients(clinician_id);

CREATE INDEX IF NOT EXISTS patients_claimed_user_id_idx
    ON patients(claimed_user_id) WHERE claimed_user_id IS NOT NULL;

DROP TRIGGER IF EXISTS patients_set_updated_at ON patients;
CREATE TRIGGER patients_set_updated_at
    BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── 5. patients RLS ────────────────────────────────────────

ALTER TABLE patients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clinicians can read own patients" ON patients;
CREATE POLICY "Clinicians can read own patients"
    ON patients FOR SELECT
    USING (auth.uid() = clinician_id AND archived_at IS NULL);

DROP POLICY IF EXISTS "Patients can read own claimed record" ON patients;
CREATE POLICY "Patients can read own claimed record"
    ON patients FOR SELECT
    USING (auth.uid() = claimed_user_id AND archived_at IS NULL);

DROP POLICY IF EXISTS "Clinicians can insert own patients" ON patients;
CREATE POLICY "Clinicians can insert own patients"
    ON patients FOR INSERT
    WITH CHECK (auth.uid() = clinician_id);

DROP POLICY IF EXISTS "Clinicians can update own patients" ON patients;
CREATE POLICY "Clinicians can update own patients"
    ON patients FOR UPDATE
    USING (auth.uid() = clinician_id)
    WITH CHECK (auth.uid() = clinician_id);

-- Note: No DELETE policy. Hard delete is intentionally disabled for
-- medical-data audit hygiene. Soft-delete via UPDATE archived_at = now().

-- ─── End of migration ──────────────────────────────────────
