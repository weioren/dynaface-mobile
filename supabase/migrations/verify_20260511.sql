-- ============================================================
-- Verification script for 20260511_job_patient_attributions.sql
-- ============================================================
-- Run this in Supabase SQL Editor after applying the migration.
-- Each query should return rows showing the expected state.
-- ============================================================

-- 1. Table exists with correct columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'job_patient_attributions'
ORDER BY ordinal_position;
-- Expected: 4 rows
--   job_id        | uuid        | NO  | (null)
--   patient_id    | uuid        | NO  | (null)
--   attributed_by | uuid        | NO  | (null)
--   attributed_at | timestamptz | NO  | now()

-- 2. Foreign key + primary key constraints exist
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'job_patient_attributions'::regclass;
-- Expected: 2 rows
--   job_patient_attributions_pkey       | p  (primary key)
--   job_patient_attributions_job_id_fkey| f  (foreign key)

-- 3. Indexes exist
SELECT indexname FROM pg_indexes
WHERE tablename = 'job_patient_attributions';
-- Expected: 2 rows
--   job_patient_attributions_pkey
--   job_patient_attributions_patient_id_idx

-- 4. RLS is enabled
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname = 'job_patient_attributions';
-- Expected: relrowsecurity = true

-- 5. All 5 policies exist
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'job_patient_attributions'
ORDER BY policyname;
-- Expected: 5 rows
--   Clinicians can delete attributions    | DELETE
--   Clinicians can insert attributions    | INSERT
--   Clinicians can read all attributions  | SELECT
--   Clinicians can update attributions    | UPDATE
--   Patients can insert self-attributions | INSERT
--   Patients can read own attributions    | SELECT
