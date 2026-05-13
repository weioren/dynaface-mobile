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
