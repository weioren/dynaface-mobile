import Foundation
import Supabase

// MARK: - TimelineService
//
// Loads / inserts / updates rows on `timeline_events` for a single
// patient. One instance per `PatientDetailView` invocation — the
// service is scoped to a specific `patientId` so we don't have to
// pass it on every call.
//
// RLS contract (2026-05-08 migration):
//   - SELECT: clinicians see all; patient sees own
//   - INSERT: clinicians for any patient; patient for self only;
//             `created_by` must equal `auth.uid()`
//   - UPDATE: clinicians only (regardless of original creator)
//
// View hierarchy: PatientDetailView creates the service via
// @StateObject; TimelinePage and AddEditEventSheet read it via
// @EnvironmentObject so they share the same `events` list.

@MainActor
final class TimelineService: ObservableObject {

    @Published private(set) var events: [TimelineEvent] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Raw `processing_jobs.status` keyed by job_id, populated by
    /// `loadJobStatuses` after every `loadEvents()`. Lets the timeline
    /// render per-exercise + per-group processed/processing badges
    /// without each row issuing its own fetch. Missing keys are
    /// rendered as "Processing" client-side (default for in-flight jobs
    /// not yet present in the snapshot).
    @Published private(set) var jobStatusByJobId: [UUID: String] = [:]

    let patientId: UUID

    private let supabase = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.projectURL)!,
        supabaseKey:  SupabaseConfig.anonKey
    )

    init(patientId: UUID) {
        self.patientId = patientId
    }

    // MARK: - Read

    /// Pull every event for this patient, newest occurrence first.
    /// Follows up with `loadJobStatuses` so the timeline can render
    /// processed/processing badges in the same UI tick — both run on
    /// every pull-to-refresh, so a clinician watching a queued job
    /// can refresh to flip it to Processed.
    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [TimelineEvent] = try await supabase
                .from("timeline_events")
                .select()
                .eq("patient_id", value: patientId.uuidString)
                .order("occurred_at", ascending: false)
                .execute()
                .value
            self.events = rows
        } catch {
            errorMessage = "Couldn't load timeline: \(error.localizedDescription)"
            return
        }
        await loadJobStatuses()
    }

    /// Batched fetch of `processing_jobs.status` for every assessment
    /// event with a `jobId`. Failures are swallowed — the timeline
    /// still renders without badges and clinicians can pull-to-refresh.
    private func loadJobStatuses() async {
        let ids = events.compactMap(\.jobId)
        guard !ids.isEmpty else {
            jobStatusByJobId = [:]
            return
        }
        struct StatusRow: Decodable {
            let id: UUID
            let status: String?
        }
        do {
            let rows: [StatusRow] = try await supabase
                .from("processing_jobs")
                .select("id, status")
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            var map: [UUID: String] = [:]
            for r in rows { map[r.id] = r.status }
            jobStatusByJobId = map
        } catch {
            print("TimelineService.loadJobStatuses failed: \(error)")
        }
    }

    // MARK: - Write

    /// Insert a new event. `createdBy` is the signed-in user's
    /// profile id; RLS rejects mismatches so we forward whatever the
    /// caller passes (no client-side spoofing).
    func addEvent(
        type: TimelineEventType,
        occurredAt: Date,
        notes: String,
        createdBy: UUID
    ) async {
        isLoading = true
        defer { isLoading = false }

        struct EventInsert: Encodable {
            let patient_id: String
            let type: String
            let occurred_at: String   // YYYY-MM-DD per Postgres `date` column
            let notes: String
            let created_by: String
        }

        let payload = EventInsert(
            patient_id:  patientId.uuidString,
            type:        type.rawValue,
            occurred_at: Self.dateFormatter.string(from: occurredAt),
            notes:       notes,
            created_by:  createdBy.uuidString
        )

        do {
            let inserted: TimelineEvent = try await supabase
                .from("timeline_events")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            // Insert at top — newest occurrence usually beats existing.
            // A subsequent loadEvents() reorders cleanly.
            events.insert(inserted, at: 0)
            events.sort { $0.occurredAt > $1.occurredAt }
        } catch {
            print("TimelineService.addEvent failed: \(error)")
            errorMessage = "Couldn't add event: \(error.localizedDescription)"
        }
    }

    /// Insert an `assessment`-type event that links back to a
    /// processing_jobs row (so the row's tap-target can play the
    /// processed video). Called after an upload completes if the user
    /// opts in via the "Add to timeline?" confirmation alert.
    /// `exerciseNames` are comma-joined into the event's notes field.
    @discardableResult
    func addAssessmentEvent(
        jobId: UUID?,
        occurredAt: Date,
        exerciseNames: [String],
        createdBy: UUID
    ) async -> Bool {
        struct EventInsert: Encodable {
            let patient_id: String
            let type: String
            let occurred_at: String
            let notes: String
            let created_by: String
            let job_id: String?
        }

        let payload = EventInsert(
            patient_id:  patientId.uuidString,
            type:        TimelineEventType.assessment.rawValue,
            occurred_at: Self.dateFormatter.string(from: occurredAt),
            notes:       exerciseNames.joined(separator: ", "),
            created_by:  createdBy.uuidString,
            job_id:      jobId?.uuidString
        )

        do {
            let inserted: TimelineEvent = try await supabase
                .from("timeline_events")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            events.insert(inserted, at: 0)
            events.sort { $0.occurredAt > $1.occurredAt }
            return true
        } catch {
            print("TimelineService.addAssessmentEvent failed: \(error)")
            errorMessage = "Couldn't log assessment: \(error.localizedDescription)"
            return false
        }
    }

    /// Patch an existing event. Only clinicians will succeed (RLS).
    /// On success, the local copy is updated in place.
    func updateEvent(
        _ event: TimelineEvent,
        type: TimelineEventType,
        occurredAt: Date,
        notes: String
    ) async {
        isLoading = true
        defer { isLoading = false }

        struct EventPatch: Encodable {
            let type: String
            let occurred_at: String
            let notes: String
        }

        let patch = EventPatch(
            type:        type.rawValue,
            occurred_at: Self.dateFormatter.string(from: occurredAt),
            notes:       notes
        )

        do {
            let updated: TimelineEvent = try await supabase
                .from("timeline_events")
                .update(patch)
                .eq("id", value: event.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let idx = events.firstIndex(where: { $0.id == event.id }) {
                events[idx] = updated
            }
            events.sort { $0.occurredAt > $1.occurredAt }
        } catch {
            print("TimelineService.updateEvent failed: \(error)")
            errorMessage = "Couldn't update event: \(error.localizedDescription)"
        }
    }

    /// Delete a non-assessment event. Assessment rows are system-managed
    /// (linked to a processing_jobs row) and never deletable — guarded
    /// here client-side and by RLS (2026-06-15 migration). On success the
    /// local copy is removed.
    @discardableResult
    func deleteEvent(_ event: TimelineEvent) async -> Bool {
        guard event.type != .assessment else { return false }

        do {
            try await supabase
                .from("timeline_events")
                .delete()
                .eq("id", value: event.id.uuidString)
                .execute()
            events.removeAll { $0.id == event.id }
            return true
        } catch {
            print("TimelineService.deleteEvent failed: \(error)")
            errorMessage = "Couldn't delete event: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Helpers

    /// Postgres `date` column wants `YYYY-MM-DD`, no time component.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
