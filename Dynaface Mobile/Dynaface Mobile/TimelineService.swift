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
    /// (Processed / Processing / Failed). Populated by `loadJobStatuses()` via
    /// per-document reads — a single `documentID in [...]` list query is denied
    /// for patients (one unreadable id fails the whole query), which made every
    /// patient badge fall back to "Processing".
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

    /// Pull every event for this patient, newest occurrence first.
    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("patient_id", isEqualTo: patientId.uuidString)
                .order(by: "occurred_at", descending: true)
                .getDocuments()
            self.events = snapshot.documents.compactMap { decode(id: $0.documentID, data: $0.data()) }
        } catch {
            errorMessage = "Couldn't load timeline: \(error.localizedDescription)"
        }
    }

    /// Pull `status` for each assessment event's linked `processing_jobs` doc,
    /// keyed by job_id for the row badge. Uses PER-DOCUMENT `getDocument()`
    /// reads (not one `documentID in [...]` list query): a list query is denied
    /// for patients if ANY matched doc fails the read rule, which made every
    /// patient badge fall back to "Processing". A per-doc read is evaluated on
    /// its own and can satisfy attribution-based `allow read` rules, so
    /// readable jobs populate and unreadable ones are simply skipped. Non-fatal.
    func loadJobStatuses() async {
        let jobIds = Set(events.compactMap(\.jobId))
        guard !jobIds.isEmpty else {
            jobStatusByJobId = [:]
            return
        }
        var map: [UUID: String] = [:]
        for jobId in jobIds {
            do {
                let doc = try await db.collection("processing_jobs")
                    .document(jobId.uuidString).getDocument()
                if let status = doc.data()?["status"] as? String {
                    map[jobId] = status
                }
            } catch {
                print("[TimelineStatus] job \(jobId.uuidString) read FAILED: \(error.localizedDescription)")
            }
        }
        jobStatusByJobId = map
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

    /// Delete a non-assessment event. Assessment rows are system-managed
    /// (linked to a processing_jobs doc) and never deletable — guarded here
    /// client-side and by firestore.rules. On success the local copy is removed.
    @discardableResult
    func deleteEvent(_ event: TimelineEvent) async -> Bool {
        guard event.type != .assessment else { return false }
        do {
            try await db.collection(collectionName).document(event.id.uuidString).delete()
            events.removeAll { $0.id == event.id }
            return true
        } catch {
            print("TimelineService.deleteEvent failed: \(error)")
            errorMessage = "Couldn't delete event: \(error.localizedDescription)"
            return false
        }
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
