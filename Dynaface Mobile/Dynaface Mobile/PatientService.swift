import Foundation
import Supabase

// MARK: - PatientService
//
// Owns the clinician's patient list. Reads from / writes to the Supabase
// `patients` table. RLS on the table guarantees a clinician only ever sees
// rows they themselves created — `clinician_id` is still passed explicitly
// on writes for clarity (and so the policy passes).
//
// View hierarchy: ClinicianRootView creates one instance with `@StateObject`,
// children reach it via `@EnvironmentObject`.

@MainActor
final class PatientService: ObservableObject {

    @Published private(set) var patients: [Patient] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.projectURL)!,
        supabaseKey:  SupabaseConfig.anonKey
    )

    // MARK: - Read

    /// Pulls all patients owned by the given clinician, newest first.
    /// On error, populates `errorMessage` and leaves the previous list intact.
    func loadPatients(for clinicianId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [Patient] = try await supabase
                .from("patients")
                .select()
                .eq("clinician_id", value: clinicianId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.patients = rows
        } catch {
            print("PatientService.loadPatients failed: \(error)")
            errorMessage = "Couldn't load patients: \(error.localizedDescription)"
        }
    }

    // MARK: - Write

    /// Inserts a patient row for the given clinician and prepends the new
    /// row to the local list on success.
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

    // MARK: - Search (client-side)

    /// Case-insensitive substring match on `name`. Empty query returns the
    /// full list. Done client-side because the typical patient-list size
    /// (a single clinician's patients) is small enough that round-tripping
    /// to Postgres for every keystroke is unnecessary overhead.
    func searchedPatients(matching query: String) -> [Patient] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return patients }
        return patients.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
