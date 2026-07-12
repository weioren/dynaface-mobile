import Foundation
import FirebaseFirestore

// MARK: - PatientService
//
// Owns the clinician's patient list. Reads from / writes to the
// `patients` Firestore collection. Document IDs are client-generated
// UUIDs (NOT Firestore auto-IDs — auto-IDs aren't UUID-formatted, which
// would break every `Patient.id: UUID` consumer downstream), mirroring
// the old Supabase primary key. Rules guarantee a clinician only sees
// rows they created — `clinician_id` is still passed explicitly on
// writes so the rule has something to check against.
//
// View hierarchy: ClinicianRootView creates one instance with @StateObject;
// children reach it via @EnvironmentObject.

@MainActor
final class PatientService: ObservableObject {

    @Published private(set) var patients: [Patient] = []
    @Published private(set) var patientProfiles: [PatientCandidate] = []
    @Published private(set) var roster: [PatientRef] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()

    // MARK: - Patient profiles (drives PatientListPage)

    /// Pulls every patient-role profile, newest first. Visibility relies
    /// on the firestore.rules policy that lets any clinician read profiles
    /// where account_type == "patient".
    func loadAllPatientProfiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("profiles")
                .whereField("account_type", isEqualTo: "patient")
                .order(by: "created_at", descending: true)
                .getDocuments()
            self.patientProfiles = snapshot.documents.compactMap {
                decodeCandidate(id: $0.documentID, data: $0.data())
            }
            rebuildRoster()
        } catch is CancellationError {
            return
        } catch {
            print("PatientService.loadAllPatientProfiles failed: \(error)")
            errorMessage = "Couldn't load patients: \(error.localizedDescription)"
        }
    }

    /// Case-insensitive substring match on username OR email. Empty
    /// query returns the full list. Client-side because the patient
    /// roster is small enough that round-tripping per keystroke is wasteful.
    func searchedPatientProfiles(matching query: String) -> [PatientCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return patientProfiles }
        return patientProfiles.filter {
            $0.username.localizedCaseInsensitiveContains(trimmed)
                || $0.email.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Unified roster (registered profiles ∪ unregistered patients)

    /// Rebuilds the merged roster shown on PatientListPage:
    ///   - every registered patient-role profile
    ///   - every clinician-created, non-archived `patients` row NOT yet
    ///     linked to a profile (claimed rows are represented by their
    ///     profile, so they're skipped to avoid duplicates)
    /// Sorted newest-first so a just-created patient shows at the top.
    func rebuildRoster() {
        let registered = patientProfiles.map(PatientRef.init(profile:))
        let unregistered = patients
            .filter { $0.claimedUserId == nil && $0.archivedAt == nil }
            .map(PatientRef.init(patient:))
        roster = (registered + unregistered).sorted { $0.createdAt > $1.createdAt }
    }

    /// Case-insensitive substring match on display name OR email over the
    /// merged roster. Empty query returns the full roster.
    func searchedRoster(matching query: String) -> [PatientRef] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return roster }
        return roster.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.email?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    // MARK: - Read

    /// Pulls every (non-archived) patient visible to the signed-in
    /// clinician, newest first. Any clinician account sees the full
    /// shared roster — rules still block non-clinician (patient) accounts
    /// from reading the collection at all.
    func loadAllPatients() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("patients")
                .order(by: "created_at", descending: true)
                .getDocuments()
            self.patients = snapshot.documents.compactMap {
                decodePatient(id: $0.documentID, data: $0.data())
            }
            rebuildRoster()
        } catch is CancellationError {
            return
        } catch {
            print("PatientService.loadAllPatients failed: \(error)")
            errorMessage = "Couldn't load patients: \(error.localizedDescription)"
        }
    }

    // MARK: - Write

    /// Inserts a new patient row for the given clinician and prepends it
    /// to the local list on success. Returns the inserted row so callers
    /// can immediately select it; nil on failure. Errors surface via
    /// `errorMessage`.
    @discardableResult
    func addPatient(name: String, clinicianId: UUID) async -> Patient? {
        isLoading = true
        defer { isLoading = false }

        let newId = UUID()
        let now = Date()
        let data: [String: Any] = [
            "clinician_id": clinicianId.uuidString,
            "name": name,
            "created_at": FieldValue.serverTimestamp(),
            "updated_at": FieldValue.serverTimestamp(),
        ]

        do {
            try await db.collection("patients").document(newId.uuidString).setData(data)
            let inserted = Patient(
                id: newId,
                name: name,
                clinicianId: clinicianId,
                claimedUserId: nil,
                archivedAt: nil,
                createdAt: now,
                updatedAt: now
            )
            patients.insert(inserted, at: 0)
            rebuildRoster()
            return inserted
        } catch {
            print("PatientService.addPatient failed: \(error)")
            errorMessage = "Couldn't add patient: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Search existing roster (client-side)

    /// Case-insensitive substring match on `name`. Empty query returns
    /// the full list. Done client-side because a single clinician's
    /// roster is small enough that round-tripping per keystroke is wasteful.
    func searchedPatients(matching query: String) -> [Patient] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return patients }
        return patients.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Search patient profiles (server-side)

    /// Looks up patient-role profiles matching the query (case-insensitive
    /// substring on username OR email). Drives the AddPatientSheet search
    /// UI, which may be presented without `loadAllPatientProfiles` having
    /// run first — so this always does its own fresh fetch rather than
    /// filtering `patientProfiles`, then filters client-side since
    /// Firestore has no ILIKE/full-text search. Returns [] on empty input
    /// or any error (errors are logged, not surfaced — empty-result UX
    /// handles both cases).
    func searchPatientProfiles(matching query: String) async -> [PatientCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        do {
            let snapshot = try await db.collection("profiles")
                .whereField("account_type", isEqualTo: "patient")
                .limit(to: 200)
                .getDocuments()
            let all = snapshot.documents.compactMap { decodeCandidate(id: $0.documentID, data: $0.data()) }
            return all.filter {
                $0.username.localizedCaseInsensitiveContains(trimmed)
                    || $0.email.localizedCaseInsensitiveContains(trimmed)
            }
        } catch {
            print("PatientService.searchPatientProfiles failed: \(error)")
            return []
        }
    }

    /// Inserts a new patient row linked to an existing patient-role
    /// profile via `claimed_user_id`. The displayed name is taken from
    /// the candidate's username. Errors surface via `errorMessage`.
    func addPatientFromProfile(_ candidate: PatientCandidate, clinicianId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        let newId = UUID()
        let now = Date()
        let data: [String: Any] = [
            "clinician_id": clinicianId.uuidString,
            "claimed_user_id": candidate.id.uuidString,
            "name": candidate.username,
            "created_at": FieldValue.serverTimestamp(),
            "updated_at": FieldValue.serverTimestamp(),
        ]

        do {
            try await db.collection("patients").document(newId.uuidString).setData(data)
            let inserted = Patient(
                id: newId,
                name: candidate.username,
                clinicianId: clinicianId,
                claimedUserId: candidate.id,
                archivedAt: nil,
                createdAt: now,
                updatedAt: now
            )
            patients.insert(inserted, at: 0)
            rebuildRoster()
        } catch {
            print("PatientService.addPatientFromProfile failed: \(error)")
            errorMessage = "Couldn't add patient: \(error.localizedDescription)"
        }
    }

    // MARK: - Decode helpers

    private func decodePatient(id: String, data: [String: Any]) -> Patient? {
        guard
            let uuid = UUID(uuidString: id),
            let name = data["name"] as? String,
            let clinicianIdString = data["clinician_id"] as? String,
            let clinicianId = UUID(uuidString: clinicianIdString)
        else {
            return nil
        }
        let claimedUserId = (data["claimed_user_id"] as? String).flatMap(UUID.init(uuidString:))
        let archivedAt = (data["archived_at"] as? Timestamp)?.dateValue()
        let createdAt = (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updated_at"] as? Timestamp)?.dateValue() ?? Date()
        return Patient(
            id: uuid,
            name: name,
            clinicianId: clinicianId,
            claimedUserId: claimedUserId,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeCandidate(id: String, data: [String: Any]) -> PatientCandidate? {
        guard
            let uuid = UUID(uuidString: id),
            let username = data["username"] as? String,
            let email = data["email"] as? String
        else {
            return nil
        }
        let createdAt = (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
        return PatientCandidate(id: uuid, username: username, email: email, createdAt: createdAt)
    }
}

