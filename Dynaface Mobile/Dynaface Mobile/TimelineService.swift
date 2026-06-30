import Foundation
import FirebaseFirestore

// MARK: - TimelineService
//
// Loads / inserts / updates documents in `timeline_events` for a single
// patient. One instance per `PatientDetailView` invocation — the service
// is scoped to a specific `patientId` so we don't have to pass it on
// every call. Document IDs are client-generated UUIDs (not Firestore
// auto-IDs — see PatientService for why), matching the old Supabase PK.
//
// Access contract (mirrors the old Supabase RLS, enforced by
// firestore.rules using request.auth.token.app_uid + a role lookup):
//   - read:  clinicians see all; patient sees own
//   - write: clinicians for any patient; patient for self only;
//            `created_by` must equal the caller's app_uid
//   - update: clinicians only (regardless of original creator)
//
// View hierarchy: PatientDetailView creates the service via
// @StateObject; TimelinePage and AddEditEventSheet read it via
// @EnvironmentObject so they share the same `events` list.

@MainActor
final class TimelineService: ObservableObject {

    @Published private(set) var events: [TimelineEvent] = []
    /// `processing_jobs.status` keyed by job_id, for the assessment-row badge
    /// (Processed / Processing / Failed). Filled by `loadEvents()` before the
    /// list is published (so the first render is correct) and refreshed by
    /// `loadJobStatuses()`. Reads are per-document — a single `documentID in
    /// [...]` list query is denied for patients (one unreadable id fails the
    /// whole query), which made every patient badge fall back to "Processing".
    @Published private(set) var jobStatusByJobId: [UUID: String] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let patientId: UUID

    private let db = Firestore.firestore()
    private let collectionName = "timeline_events"

    init(patientId: UUID) {
        self.patientId = patientId
    }

    // MARK: - Read

    /// Pull every event for this patient (newest first) AND each linked job's
    /// status, then publish both together. Fetching statuses BEFORE assigning
    /// `events` means the first render already has the right badge — without
    /// this, the list rendered with an empty status map and every assessment
    /// flashed "Processing" until `loadJobStatuses()` caught up.
    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("patient_id", isEqualTo: patientId.uuidString)
                .order(by: "occurred_at", descending: true)
                .getDocuments()
            let fetched = snapshot.documents.compactMap { decode(id: $0.documentID, data: $0.data()) }
            let statuses = await fetchJobStatuses(for: fetched)
            // Two @Published writes with no await between them coalesce into a
            // single render, so there's no empty-map frame.
            self.events = fetched
            self.jobStatusByJobId = statuses
        } catch {
            errorMessage = "Couldn't load timeline: \(error.localizedDescription)"
        }
    }

    /// Refresh just the status map for the already-loaded events (pull-to-refresh,
    /// or a re-appear after some jobs may have completed). The map is already
    /// populated by then, so this updates in place with no "Processing" flash.
    func loadJobStatuses() async {
        jobStatusByJobId = await fetchJobStatuses(for: events)
    }

    /// `status` for each assessment event's linked `processing_jobs` doc, keyed
    /// by job_id. PER-DOCUMENT `getDocument()` reads run in PARALLEL — not a
    /// `documentID in [...]` list query, which Firestore denies for patients if
    /// ANY matched doc fails the read rule (that made every patient badge fall
    /// back to "Processing"). A per-doc read is evaluated on its own and can
    /// satisfy attribution-based `allow read` rules; unreadable jobs are skipped.
    private func fetchJobStatuses(for events: [TimelineEvent]) async -> [UUID: String] {
        let jobIds = Set(events.compactMap(\.jobId))
        guard !jobIds.isEmpty else { return [:] }
        return await withTaskGroup(of: (UUID, String)?.self) { group in
            for jobId in jobIds {
                group.addTask {
                    let doc = try? await Firestore.firestore()
                        .collection("processing_jobs")
                        .document(jobId.uuidString)
                        .getDocument()
                    if let status = doc?.data()?["status"] as? String { return (jobId, status) }
                    return nil
                }
            }
            var map: [UUID: String] = [:]
            for await pair in group { if let pair { map[pair.0] = pair.1 } }
            return map
        }
    }

    // MARK: - Write

    /// Insert a new event. `createdBy` is the signed-in user's profile
    /// id; rules reject mismatches so we forward whatever the caller
    /// passes (no client-side spoofing).
    func addEvent(
        type: TimelineEventType,
        occurredAt: Date,
        notes: String,
        createdBy: UUID
    ) async {
        isLoading = true
        defer { isLoading = false }

        let newId = UUID()
        let now = Date()
        let normalizedDate = dateOnly(occurredAt)
        let data: [String: Any] = [
            "patient_id": patientId.uuidString,
            "type": type.rawValue,
            "occurred_at": Timestamp(date: normalizedDate),
            "notes": notes,
            "created_by": createdBy.uuidString,
            "created_at": FieldValue.serverTimestamp(),
            "updated_at": FieldValue.serverTimestamp(),
        ]

        do {
            try await db.collection(collectionName).document(newId.uuidString).setData(data)
            let inserted = TimelineEvent(
                id: newId,
                patientId: patientId,
                type: type,
                occurredAt: normalizedDate,
                notes: notes,
                createdBy: createdBy,
                createdAt: now,
                updatedAt: now,
                jobId: nil
            )
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
    /// processing_jobs document (so the row's tap-target can play the
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
        let newId = UUID()
        let now = Date()
        let normalizedDate = dateOnly(occurredAt)
        let notes = exerciseNames.joined(separator: ", ")

        var data: [String: Any] = [
            "patient_id": patientId.uuidString,
            "type": TimelineEventType.assessment.rawValue,
            "occurred_at": Timestamp(date: normalizedDate),
            "notes": notes,
            "created_by": createdBy.uuidString,
            "created_at": FieldValue.serverTimestamp(),
            "updated_at": FieldValue.serverTimestamp(),
        ]
        if let jobId {
            data["job_id"] = jobId.uuidString
        }

        do {
            try await db.collection(collectionName).document(newId.uuidString).setData(data)
            let inserted = TimelineEvent(
                id: newId,
                patientId: patientId,
                type: .assessment,
                occurredAt: normalizedDate,
                notes: notes,
                createdBy: createdBy,
                createdAt: now,
                updatedAt: now,
                jobId: jobId
            )
            events.insert(inserted, at: 0)
            events.sort { $0.occurredAt > $1.occurredAt }
            return true
        } catch {
            print("TimelineService.addAssessmentEvent failed: \(error)")
            errorMessage = "Couldn't log assessment: \(error.localizedDescription)"
            return false
        }
    }

    /// Patch an existing event. Only clinicians will succeed (rules).
    /// On success, the local copy is updated in place.
    func updateEvent(
        _ event: TimelineEvent,
        type: TimelineEventType,
        occurredAt: Date,
        notes: String
    ) async {
        isLoading = true
        defer { isLoading = false }

        let normalizedDate = dateOnly(occurredAt)
        let data: [String: Any] = [
            "type": type.rawValue,
            "occurred_at": Timestamp(date: normalizedDate),
            "notes": notes,
            "updated_at": FieldValue.serverTimestamp(),
        ]

        do {
            try await db.collection(collectionName).document(event.id.uuidString).updateData(data)
            if let idx = events.firstIndex(where: { $0.id == event.id }) {
                var updated = event
                updated.type = type
                updated.occurredAt = normalizedDate
                updated.notes = notes
                updated.updatedAt = Date()
                events[idx] = updated
            }
            events.sort { $0.occurredAt > $1.occurredAt }
        } catch {
            print("TimelineService.updateEvent failed: \(error)")
            errorMessage = "Couldn't update event: \(error.localizedDescription)"
        }
    }

    /// Delete a timeline event. For ASSESSMENT events this CASCADES: the
    /// linked processing_job and its attribution are deleted too, so the video
    /// + analysis are fully removed from the app (not just the timeline entry).
    /// NOTE: the results-bucket blobs (annotated.mp4 / results.json /
    /// peak_frame.png) can't be removed client-side — storage.rules block
    /// client writes to results/ — so a backend cleanup function should delete
    /// results/{uid}/{jobId}/ when the job doc is deleted.
    @discardableResult
    func deleteEvent(_ event: TimelineEvent) async -> Bool {
        if event.type == .assessment, let jobId = event.jobId {
            // Best-effort cascade; one failed piece shouldn't block the rest.
            try? await db.collection("processing_jobs").document(jobId.uuidString).delete()
            try? await db.collection("job_patient_attributions").document(jobId.uuidString).delete()
        }
        do {
            try await db.collection(collectionName).document(event.id.uuidString).delete()
            events.removeAll { $0.id == event.id }
            return true
        } catch {
            print("TimelineService.deleteEvent failed: \(error)")
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
            return false
        }
    }

    /// Delete every event in an assessment day-group (each one cascades).
    @discardableResult
    func deleteAssessmentGroup(_ groupEvents: [TimelineEvent]) async -> Bool {
        var allOK = true
        for event in groupEvents {
            if await deleteEvent(event) == false { allOK = false }
        }
        return allOK
    }

    // MARK: - Helpers

    /// Old Postgres `occurred_at` was a `date` column (no time-of-day).
    /// Normalize to midnight UTC so behavior matches now that it's a
    /// Firestore Timestamp.
    private func dateOnly(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }

    private func decode(id: String, data: [String: Any]) -> TimelineEvent? {
        guard
            let uuid = UUID(uuidString: id),
            let patientIdString = data["patient_id"] as? String,
            let patientId = UUID(uuidString: patientIdString),
            let typeRaw = data["type"] as? String,
            let type = TimelineEventType(rawValue: typeRaw),
            let notes = data["notes"] as? String,
            let createdByString = data["created_by"] as? String,
            let createdBy = UUID(uuidString: createdByString),
            let occurredAtTimestamp = data["occurred_at"] as? Timestamp
        else {
            return nil
        }
        let createdAt = (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updated_at"] as? Timestamp)?.dateValue() ?? createdAt
        let jobId = (data["job_id"] as? String).flatMap(UUID.init(uuidString:))

        return TimelineEvent(
            id: uuid,
            patientId: patientId,
            type: type,
            occurredAt: occurredAtTimestamp.dateValue(),
            notes: notes,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            jobId: jobId
        )
    }
}
