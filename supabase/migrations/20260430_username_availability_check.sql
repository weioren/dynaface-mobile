-- ============================================================
-- Phase 6 follow-up: username availability pre-check
-- ============================================================
-- Date: 2026-04-30
--
-- Background: SignUp and EditProfile UIs need to detect username
-- duplicates BEFORE attempting auth.signUp / profiles UPDATE so the
-- error message can be friendly ("Username has been registered")
-- and we avoid orphan auth.users rows on signup conflicts.
--
-- This migration adds a SECURITY DEFINER function callable by anon
-- and authenticated roles. It bypasses profiles RLS to do a global
-- existence check (lowercased + trimmed match).
--
-- No UNIQUE constraint added on profiles.username yet (per user
-- decision — global uniqueness deferred). Race conditions are
-- acceptable for MVP — the pre-check + insert is best-effort.
-- Add UNIQUE later if duplicate signups become a real problem.
--
-- Idempotent.

CREATE OR REPLACE FUNCTION public.is_username_available(name text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE LOWER(username) = LOWER(TRIM(name))
    )
$$;

GRANT EXECUTE ON FUNCTION public.is_username_available(text) TO anon, authenticated;

-- ─── End of migration ──────────────────────────────────────
