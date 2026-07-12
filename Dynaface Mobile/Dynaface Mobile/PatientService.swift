import Foundation
import FirebaseFirestore
import FirebaseAuth

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
            // Lowercased to match the app_uid casing used by redeem_invite and the
            // patient-side "My clinicians" query (Firestore == is case-sensitive),
            // so a clinician-linked patient can see + disconnect this link too.
            "claimed_user_id": candidate.id.uuidString.lowercased(),
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

// MARK: - ClinicianLink
//
// A patient-side view of one clinician they've connected to, backed by a
// `patients` row whose `claimed_user_id` is this patient. `documentId` is the
// raw Firestore doc id (kept as-is — the redeem function writes lowercase
// UUIDs, so round-tripping through Swift's UPPERCASE `UUID.uuidString` would
// miss the doc on disconnect).
struct ClinicianLink: Identifiable, Hashable {
    let documentId: String
    let clinicianName: String
    let connectedAt: Date

    var id: String { documentId }
}

// MARK: - InviteSummary
//
// Clinician-side view of one of their own `patient_invites` rows, for the
// "your invite codes" history list. Status is derived: used if it's been
// redeemed, else expired past its TTL, else active.
struct InviteSummary: Identifiable, Hashable {
    enum Status { case active, used, expired }

    let code: String
    let createdAt: Date
    let expiresAt: Date?
    let redeemedByName: String?
    let redeemedAt: Date?

    var id: String { code }

    var status: Status {
        if redeemedAt != nil || redeemedByName != nil { return .used }
        if let expiresAt, expiresAt < Date() { return .expired }
        return .active
    }
}

// MARK: - InviteError
enum InviteError: LocalizedError {
    case notSignedIn
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:          return "You need to be signed in."
        case .badResponse:          return "Unexpected response from the server."
        case .server(let message):  return message
        }
    }
}

// MARK: - InviteService
//
// Stateless helpers for the patient<->clinician invite / opt-in flow (Phase 1:
// invite code). Kept as static funcs (no ObservableObject / @EnvironmentObject)
// because the patient side (ProfilePage) is NOT inside the clinician's
// PatientService environment — views own their own loading/error @State.
//
// Clinician creates an invite client-side (firestore.rules lets a clinician
// write their own `patient_invites` row). A patient redeems it through the
// `redeem_invite` Cloud Function (Admin SDK) because rules forbid a patient
// from creating a `patients` row. Disconnect is a client-side soft-archive
// the relaxed `patients` update rule permits.
enum InviteService {

    /// Unambiguous alphabet — no 0/O/1/I/L, to avoid transcription errors.
    private static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private static let codeLength = 6
    private static let inviteTTL: TimeInterval = 14 * 24 * 60 * 60  // 14 days

    private static var db: Firestore { Firestore.firestore() }

    // MARK: Clinician — create / revoke an invite

    /// Generates a unique short code, writes `patient_invites/{code}`, and
    /// returns it for the clinician to share. `patientName` is an optional
    /// note for the clinician's own reference (not required to redeem).
    static func createInvite(clinicianId: String, clinicianName: String, patientName: String?) async throws -> String {
        let invites = db.collection("patient_invites")

        // Retry on the (astronomically unlikely) code collision so we never
        // overwrite another clinician's live invite.
        for _ in 0..<6 {
            let code = randomCode()
            let ref = invites.document(code)
            if try await ref.getDocument().exists { continue }

            var data: [String: Any] = [
                "clinician_id": clinicianId,
                "clinician_name": clinicianName,
                "created_at": FieldValue.serverTimestamp(),
                "expires_at": Timestamp(date: Date().addingTimeInterval(inviteTTL)),
            ]
            let note = (patientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { data["patient_name"] = note }

            try await ref.setData(data)
            return code
        }
        throw InviteError.server("Couldn't generate a code. Please try again.")
    }

    /// Revokes an unredeemed invite the clinician created.
    static func revokeInvite(code: String) async throws {
        try await db.collection("patient_invites").document(code).delete()
    }

    /// Loads the codes this clinician has generated, newest first, for the
    /// history list. Query pins `clinician_id == caller`, which is exactly what
    /// the scoped `list` rule allows (the collection can't be enumerated).
    static func myInvites(clinicianAppUid: String) async throws -> [InviteSummary] {
        let snapshot = try await db.collection("patient_invites")
            .whereField("clinician_id", isEqualTo: clinicianAppUid)
            .getDocuments()
        return snapshot.documents
            .map { decodeInviteSummary(id: $0.documentID, data: $0.data()) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Patient — redeem an invite

    /// POSTs the code to the `redeem_invite` Cloud Function with the patient's
    /// ID token. Returns the connected clinician's name on success; throws
    /// `InviteError.server` carrying the function's specific message
    /// (invalid / expired / already-used) on failure.
    @discardableResult
    static func redeem(code: String) async throws -> String {
        guard let user = Auth.auth().currentUser else { throw InviteError.notSignedIn }
        guard let url = URL(string: FirebaseConfig.redeemInviteFunctionURL) else {
            throw InviteError.badResponse
        }
        let idToken = try await user.getIDToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InviteError.badResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(http.statusCode) else {
            let message = (json?["error"] as? String) ?? "Couldn't connect with that code."
            throw InviteError.server(message)
        }
        return (json?["clinician_name"] as? String) ?? "your clinician"
    }

    // MARK: Patient — manage connections

    /// Loads the clinicians this patient is actively connected to (their own
    /// non-archived `patients` rows). `patientAppUid` is the patient's
    /// `profile.id` (app_uid).
    static func myClinicians(patientAppUid: String) async throws -> [ClinicianLink] {
        let snapshot = try await db.collection("patients")
            .whereField("claimed_user_id", isEqualTo: patientAppUid)
            .getDocuments()
        return snapshot.documents
            .compactMap { decodeLink(id: $0.documentID, data: $0.data()) }
            .sorted { $0.connectedAt > $1.connectedAt }
    }

    /// Disconnects from a clinician by archiving the patient's own `patients`
    /// row (soft delete). firestore.rules lets the linked patient change only
    /// `archived_at` / `updated_at`.
    static func disconnect(_ link: ClinicianLink) async throws {
        try await db.collection("patients").document(link.documentId).updateData([
            "archived_at": FieldValue.serverTimestamp(),
            "updated_at": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: Helpers

    private static func randomCode() -> String {
        String((0..<codeLength).map { _ in codeAlphabet.randomElement()! })
    }

    private static func decodeLink(id: String, data: [String: Any]) -> ClinicianLink? {
        // Active links only — an archived row is a disconnected clinician.
        guard (data["archived_at"] as? Timestamp) == nil else { return nil }
        let name = (data["clinician_name"] as? String) ?? "Your clinician"
        let connectedAt = (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
        return ClinicianLink(documentId: id, clinicianName: name, connectedAt: connectedAt)
    }

    private static func decodeInviteSummary(id: String, data: [String: Any]) -> InviteSummary {
        InviteSummary(
            code: id,
            createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date(),
            expiresAt: (data["expires_at"] as? Timestamp)?.dateValue(),
            redeemedByName: data["redeemed_by_name"] as? String,
            redeemedAt: (data["redeemed_at"] as? Timestamp)?.dateValue()
        )
    }
}
