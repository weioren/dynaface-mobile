-- ============================================================
-- Phase 6 follow-up: clinician search of patient profiles
-- ============================================================
-- Date: 2026-04-29
--
-- Background: AddPatientSheet now searches existing patient-role
-- accounts (profiles.account_type='patient') and lets a clinician
-- claim them onto their roster. The current SELECT policy on
-- profiles only lets a user read their own row, so the search
-- request comes back empty for any account other than auth.uid().
--
-- This migration:
--   1. Adds a SECURITY DEFINER helper `public.is_clinician(uid)`
--      so we can check the caller's account_type from inside a
--      profiles policy without recursing into profiles' own RLS.
--   2. Adds a SELECT policy on profiles letting any clinician
--      read every patient-role profile.
--   3. Replaces the non-unique partial index on
--      patients.claimed_user_id with a UNIQUE partial index so
--      the same patient profile can't be claimed twice.
--
-- Idempotent.
-- ============================================================

-- 1. Helper function (bypasses RLS via SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.is_clinician(uid uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = uid AND account_type = 'clinician'
  )
$$;

-- 2. SELECT policy: clinicians can read all patient profiles
DROP POLICY IF EXISTS "Clinicians can read patient profiles" ON profiles;
CREATE POLICY "Clinicians can read patient profiles"
    ON profiles FOR SELECT
    USING (
        account_type = 'patient'
        AND public.is_clinician(auth.uid())
    );

-- 3. Replace non-unique partial index with UNIQUE partial index
--    so a given patient profile can only be on one clinician's roster.
DROP INDEX IF EXISTS patients_claimed_user_id_idx;
CREATE UNIQUE INDEX IF NOT EXISTS patients_claimed_user_id_idx
    ON patients(claimed_user_id) WHERE claimed_user_id IS NOT NULL;

-- ─── End of migration ──────────────────────────────────────
