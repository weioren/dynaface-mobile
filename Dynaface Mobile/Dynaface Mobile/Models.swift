import Foundation

// MARK: - AccountType
//
// The clinician/patient split introduced in Phase 6. Persisted on the
// `profiles.account_type` column in Supabase. Legacy rows default to
// `.patient` so existing accounts keep working without a backfill.

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

    /// One-line description shown under each option in the SignUp picker.
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
// A patient record owned by exactly one clinician (the row's `clinician_id`).
// Row-level security on the Supabase `patients` table guarantees a clinician
// only ever sees patients they themselves created, so client-side scoping
// is by-design redundant — but we still pass `clinicianId` in mutations to
// keep the writes explicit.

struct Patient: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var clinicianId: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case clinicianId = "clinician_id"
        case createdAt   = "created_at"
    }
}
