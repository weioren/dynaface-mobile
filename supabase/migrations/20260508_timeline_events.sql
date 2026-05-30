-- ============================================================
-- Phase 7: timeline events for patient detail view
-- ============================================================
-- Date: 2026-05-08
--
-- Background: patient detail view's first section is a Timeline that
-- lists clinical interventions (surgery, injection, clinic visit) and
-- free-form notes. Both roles can add events; only clinicians can edit
-- them after creation. No hard delete (soft-archive only via UPDATE if
-- it ever ships, but V1 has no archive UI).
--
-- patient_id is a uuid that points at a profiles.id with
-- account_type='patient'. We deliberately do NOT add a foreign key to
-- profiles — Alex's patients-table flow may eventually surface non-
-- self-registered patients, and we want timeline events to keep working
-- even if their owning profile is later archived.
--
-- Idempotent.
-- ============================================================

-- 1. Table
CREATE TABLE IF NOT EXISTS timeline_events (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id   uuid        NOT NULL,                                -- profiles.id of the patient
    type         text        NOT NULL CHECK (type IN ('surgery','injection','clinic_visit','note')),
    occurred_at  date        NOT NULL,                                -- when the event happened (clinic dates, not timestamp)
    notes        text        NOT NULL DEFAULT '',                     -- free-form description; empty if only the type matters
    created_by   uuid        NOT NULL,                                -- profiles.id of the user who added the event
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS timeline_events_patient_id_idx
    ON timeline_events(patient_id);

CREATE INDEX IF NOT EXISTS timeline_events_patient_id_occurred_at_idx
    ON timeline_events(patient_id, occurred_at DESC);

-- Reuse the shared updated_at trigger function added in 20260428.
DROP TRIGGER IF EXISTS timeline_events_set_updated_at ON timeline_events;
CREATE TRIGGER timeline_events_set_updated_at
    BEFORE UPDATE ON timeline_events
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2. RLS
ALTER TABLE timeline_events ENABLE ROW LEVEL SECURITY;

-- SELECT: clinicians can read all events; patients can read their own.
DROP POLICY IF EXISTS "Clinicians can read all timeline events" ON timeline_events;
CREATE POLICY "Clinicians can read all timeline events"
    ON timeline_events FOR SELECT
    USING (public.is_clinician(auth.uid()));

DROP POLICY IF EXISTS "Patients can read own timeline events" ON timeline_events;
CREATE POLICY "Patients can read own timeline events"
    ON timeline_events FOR SELECT
    USING (auth.uid() = patient_id);

-- INSERT: clinicians can add events for any patient; patients can add
-- events only for themselves. created_by must match auth.uid() so an
-- event can never be falsely attributed.
DROP POLICY IF EXISTS "Clinicians can insert timeline events" ON timeline_events;
CREATE POLICY "Clinicians can insert timeline events"
    ON timeline_events FOR INSERT
    WITH CHECK (
        public.is_clinician(auth.uid())
        AND auth.uid() = created_by
    );

DROP POLICY IF EXISTS "Patients can insert own timeline events" ON timeline_events;
CREATE POLICY "Patients can insert own timeline events"
    ON timeline_events FOR INSERT
    WITH CHECK (
        auth.uid() = patient_id
        AND auth.uid() = created_by
    );

-- UPDATE: only clinicians, regardless of who originally created the
-- event. Patients can't fix their own typos in V1; they ask the
-- clinician to edit.
DROP POLICY IF EXISTS "Clinicians can update timeline events" ON timeline_events;
CREATE POLICY "Clinicians can update timeline events"
    ON timeline_events FOR UPDATE
    USING (public.is_clinician(auth.uid()))
    WITH CHECK (public.is_clinician(auth.uid()));

-- No DELETE policy — hard delete intentionally disabled.

-- ─── End of migration ──────────────────────────────────────
