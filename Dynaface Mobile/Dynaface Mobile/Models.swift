import Foundation

// MARK: - AccountType
//
// Persisted on the `profiles.account_type` column in Supabase
// (added by the 2026-04-28 migration). Legacy rows default to
// `.patient` so existing accounts keep working unchanged.

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case clinician
    case patient

    var id: String { rawValue }

    /// Display name for picker UI / labels.
    var displayName: String {
        switch self {
        case .clinician: return "Clinician"
        case .patient:   return "Patient"
        }
    }

    /// One-line description shown under the SignUp picker.
    var subtitle: String {
        switch self {
        case .clinician:
            return "I'm a healthcare provider managing patients."
        case .patient:
            return "I'm using this app to track my own care."
        }
    }
}

// MARK: - Patient
//
// A patient record owned by a clinician (the row's `clinician_id`).
// Row-level security on the Supabase `patients` table guarantees a
// clinician only sees rows they themselves created. `claimed_user_id`
// is a future bridge to a self-registered patient profile.

struct Patient: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var clinicianId: UUID
    var claimedUserId: UUID?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case clinicianId    = "clinician_id"
        case claimedUserId  = "claimed_user_id"
        case archivedAt     = "archived_at"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }
}

// MARK: - PatientCandidate
//
// A patient-role profile (`profiles.account_type='patient'`). Used as
// the row model for the clinician's Patients list view, which shows
// every self-registered patient account.

struct PatientCandidate: Identifiable, Hashable, Codable {
    let id: UUID
    let username: String
    let email: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case createdAt = "created_at"
    }
}

// MARK: - PatientRef
//
// Unified row model for the clinician's Patients list. Two sources map
// into one namespace:
//   - registered:   a `profiles` patient account (id = profiles.id)
//   - unregistered: a clinician-created `patients` row not yet linked to
//                   an account (id = patients.id), clinician-visible only.
// `id` is the key used downstream for timeline / attribution / videos.

struct PatientRef: Identifiable, Hashable {
    enum Kind { case registered, unregistered }
    let id: UUID
    let displayName: String
    let email: String?
    let kind: Kind
    let createdAt: Date

    init(profile: PatientCandidate) {
        self.id = profile.id
        self.displayName = profile.username
        self.email = profile.email
        self.kind = .registered
        self.createdAt = profile.createdAt
    }

    init(patient: Patient) {
        self.id = patient.id
        self.displayName = patient.name
        self.email = nil
        self.kind = .unregistered
        self.createdAt = patient.createdAt
    }
}

// MARK: - TimelineEventType
//
// The clinical event categories the timeline supports in V1. Stored as
// a snake_case string in `timeline_events.type`; matched by a CHECK
// constraint in the 2026-05-08 migration. Adding cases later requires
// updating that CHECK constraint at the same time.

enum TimelineEventType: String, Codable, CaseIterable, Identifiable {
    case surgery
    case injection
    case clinicVisit  = "clinic_visit"
    case note
    /// Auto-generated when an upload completes and the user opts to log
    /// it on the timeline (links back to processing_jobs via job_id).
    case assessment

    var id: String { rawValue }

    /// User-pickable cases for AddEditEventSheet. Meeting decision: the
    /// timeline supports only Assessment / Surgery / Clinic visit.
    /// `assessment` is system-managed; Injection / Note stay in the enum so
    /// existing rows still decode, but they're no longer pickable.
    static var manualCases: [TimelineEventType] {
        [.surgery, .clinicVisit]
    }

    /// Title shown on the picker and on event row badges.
    var displayName: String {
        switch self {
        case .surgery:      return "Surgery"
        case .injection:    return "Injection"
        case .clinicVisit:  return "Clinic visit"
        case .note:         return "Note"
        case .assessment:   return "Assessment"
        }
    }

    /// SF Symbol used for the type badge.
    var symbolName: String {
        switch self {
        case .surgery:      return "scissors"
        case .injection:    return "syringe.fill"
        case .clinicVisit:  return "stethoscope"
        case .note:         return "note.text"
        case .assessment:   return "video.fill"
        }
    }
}

// MARK: - TimelineEvent
//
// A single row in the patient's care journey. Lives on the
// `timeline_events` table. Both clinicians and the owning patient can
// insert; only clinicians can update (per 2026-05-08 RLS). `notes` is
// always non-nil — empty string when the type alone is the entire payload.

struct TimelineEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var patientId: UUID
    var type: TimelineEventType
    var occurredAt: Date          // date-only column on the server
    var notes: String
    let createdBy: UUID
    let createdAt: Date
    var updatedAt: Date
    /// Set only on `assessment`-type rows. Links back to the
    /// processing_jobs row that triggered this timeline entry, so the
    /// row tap can open the processed video.
    var jobId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, type, notes
        case patientId  = "patient_id"
        case occurredAt = "occurred_at"
        case createdBy  = "created_by"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
        case jobId      = "job_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        patientId = try c.decode(UUID.self, forKey: .patientId)
        type      = try c.decode(TimelineEventType.self, forKey: .type)
        notes     = try c.decode(String.self, forKey: .notes)
        createdBy = try c.decode(UUID.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        jobId     = try c.decodeIfPresent(UUID.self, forKey: .jobId)

        // occurred_at is a Postgres `date` column → "2026-05-10",
        // not a timestamptz, so the SDK's ISO 8601 decoder can't
        // parse it. Decode as string and convert manually.
        let dateString = try c.decode(String.self, forKey: .occurredAt)
        guard let parsed = Self.dateOnlyFormatter.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .occurredAt, in: c,
                debugDescription: "Expected yyyy-MM-dd, got \(dateString)"
            )
        }
        occurredAt = parsed
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - JobPatientAttribution
//
// A row on the `job_patient_attributions` junction table (added by
// the 2026-05-11 migration). Used to say "this processing_jobs row
// belongs to patient X" without modifying the processing_jobs table
// or Alex's worker. RLS guarantees a clinician sees all rows while
// a patient sees only attributions about themselves.

struct JobPatientAttribution: Identifiable, Hashable, Codable {
    let jobId: UUID
    let patientId: UUID
    let attributedBy: UUID
    let attributedAt: Date

    /// Identifiable conformance — `job_id` is the table's PK.
    var id: UUID { jobId }

    enum CodingKeys: String, CodingKey {
        case jobId        = "job_id"
        case patientId    = "patient_id"
        case attributedBy = "attributed_by"
        case attributedAt = "attributed_at"
    }
}
