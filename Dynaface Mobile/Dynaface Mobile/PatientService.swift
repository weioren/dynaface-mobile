import Foundation
import Supabase

// MARK: - PatientService
//
// Owns the clinician's patient list. Reads from / writes to the Supabase
// `patients` table created by the 2026-04-28 migration. RLS guarantees a
// clinician only sees rows they created — `clinician_id` is still passed
// explicitly on writes so the policy passes.
//
// View hierarchy: ClinicianRootView creates one instance with @StateObject;
// children reach it via @EnvironmentObject.

@MainActor
final class PatientService: ObservableObject {

    @Published private(set) var patients: [Patient] = []
    @Published private(set) var patientProfiles: [PatientCandidate] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.projectURL)!,
        supabaseKey:  SupabaseConfig.anonKey
    )

    // MARK: - Patient profiles (drives PatientListPage)

    /// Pulls every patient-role profile, newest first. Visibility relies
    /// on the 2026-04-29 RLS policy that lets any clinician read profiles
    /// where account_type='patient'.
    func loadAllPatientProfiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [PatientCandidate] = try await supabase
                .from("profiles")
                .select("id,username,email,created_at")
                .eq("account_type", value: "patient")
                .order("created_at", ascending: false)
                .execute()
                .value
            self.patientProfiles = rows
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
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

    // MARK: - Read

    /// Pulls every (non-archived) patient visible to the signed-in
    /// clinician, newest first. After the
    /// `20260428_open_patients_read_to_all_clinicians` migration, any
    /// clinician account sees the full shared roster — RLS still blocks
    /// non-clinician (patient) accounts from reading the table at all.
    func loadAllPatients() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [Patient] = try await supabase
                .from("patients")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            self.patients = rows
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            print("PatientService.loadAllPatients failed: \(error)")
            errorMessage = "Couldn't load patients: \(error.localizedDescription)"
        }
    }

    // MARK: - Write

    /// Inserts a new patient row for the given clinician and prepends it
    /// to the local list on success. Errors surface via `errorMessage`.
    func addPatient(name: String, clinicianId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        struct PatientInsert: Encodable {
            let clinician_id: String
            let name: String
        }

        do {
            let inserted: Patient = try await supabase
                .from("patients")
                .insert(PatientInsert(
                    clinician_id: clinicianId.uuidString,
                    name: name
                ))
                .select()
                .single()
                .execute()
                .value
            patients.insert(inserted, at: 0)
        } catch {
            print("PatientService.addPatient failed: \(error)")
            errorMessage = "Couldn't add patient: \(error.localizedDescription)"
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

    /// Looks up patient-role profiles matching the query (ILIKE on
    /// username OR email). Drives the AddPatientSheet search UI.
    /// Visibility relies on the 2026-04-29 RLS policy that lets any
    /// clinician read profiles where account_type='patient'.
    /// Returns [] on empty input or any error (errors are logged, not
    /// surfaced — empty-result UX handles both cases).
    func searchPatientProfiles(matching query: String) async -> [PatientCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let pattern = "*\(trimmed)*"
        do {
            let rows: [PatientCandidate] = try await supabase
                .from("profiles")
                .select("id,username,email")
                .eq("account_type", value: "patient")
                .or("username.ilike.\(pattern),email.ilike.\(pattern)")
                .limit(50)
                .execute()
                .value
            return rows
        } catch {
            print("PatientService.searchPatientProfiles failed: \(error)")
            return []
        }
    }

    /// Inserts a new patient row linked to an existing patient-role
    /// profile via `claimed_user_id`. The displayed name is taken from
    /// the candidate's username. Errors surface via `errorMessage`
    /// (e.g. unique-index violation if this profile is already on
    /// someone's roster).
    func addPatientFromProfile(_ candidate: PatientCandidate, clinicianId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        struct PatientInsert: Encodable {
            let clinician_id: String
            let claimed_user_id: String
            let name: String
        }

        do {
            let inserted: Patient = try await supabase
                .from("patients")
                .insert(PatientInsert(
                    clinician_id:    clinicianId.uuidString,
                    claimed_user_id: candidate.id.uuidString,
                    name:            candidate.username
                ))
                .select()
                .single()
                .execute()
                .value
            patients.insert(inserted, at: 0)
        } catch {
            print("PatientService.addPatientFromProfile failed: \(error)")
            errorMessage = "Couldn't add patient: \(error.localizedDescription)"
        }
    }
}
