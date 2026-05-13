import Foundation
import Supabase

// MARK: - JobAttributionService
//
// Owns the `job_patient_attributions` junction table. The table maps
// a `processing_jobs.id` (an uploaded recording) to a patient profile,
// independent of who actually uploaded the video. This is how we
// attribute a clinician-recorded video to the patient it concerns
// without touching Alex's upload pipeline or the worker.
//
// RLS contract (2026-05-11 migration):
//   - SELECT: clinicians see all; patients see only own
//   - INSERT: clinicians for any patient; patients for self only;
//             attributed_by must match auth.uid()
//   - UPDATE: clinicians only
//   - DELETE: clinicians only ("un-attribute" = leave row out)
//
// View hierarchy: injected at app root as an @EnvironmentObject so
// any screen that creates / inspects attributions (PatientDetailView's
// History+Processed tabs, the post-upload "attribute to patient"
// sheet on PracticePage) shares one instance.

@MainActor
final class JobAttributionService: ObservableObject {

    @Published var errorMessage: String?

    private let supabase = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.projectURL)!,
        supabaseKey:  SupabaseConfig.anonKey
    )

    // MARK: - Read

    /// Returns the set of `processing_jobs.id` values explicitly
    /// attributed to a given patient via the junction table.
    /// Self-recorded jobs (where `processing_jobs.user_id` already
    /// equals the patient's profile id) are NOT included — callers
    /// handle that side of the union themselves.
    func loadAttributedJobIds(forPatient patientId: UUID) async -> Set<UUID> {
        do {
            let rows: [JobPatientAttribution] = try await supabase
                .from("job_patient_attributions")
                .select("*")
                .eq("patient_id", value: patientId.uuidString)
                .execute()
                .value
            return Set(rows.map(\.jobId))
        } catch is CancellationError {
            return []
        } catch let urlError as URLError where urlError.code == .cancelled {
            return []
        } catch {
            print("JobAttributionService.loadAttributedJobIds failed: \(error)")
            errorMessage = "Couldn't load attributions: \(error.localizedDescription)"
            return []
        }
    }

    /// Fetch the single attribution row for a job, if one exists.
    /// Used to power "attributed to: <name>" badges in lists.
    func loadAttribution(forJob jobId: UUID) async -> JobPatientAttribution? {
        do {
            let rows: [JobPatientAttribution] = try await supabase
                .from("job_patient_attributions")
                .select("*")
                .eq("job_id", value: jobId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch is CancellationError {
            return nil
        } catch let urlError as URLError where urlError.code == .cancelled {
            return nil
        } catch {
            print("JobAttributionService.loadAttribution failed: \(error)")
            return nil
        }
    }

    // MARK: - Write

    /// Attribute a job to a patient. `attributedBy` is the signed-in
    /// user's profile id — RLS rejects mismatches so we forward
    /// whatever the caller passes (no client-side spoofing).
    /// Upsert semantics so re-attributing is idempotent (PK = job_id).
    @discardableResult
    func attribute(
        jobId: UUID,
        patientId: UUID,
        attributedBy: UUID
    ) async -> Bool {
        struct AttributionInsert: Encodable {
            let job_id: String
            let patient_id: String
            let attributed_by: String
        }

        let payload = AttributionInsert(
            job_id:        jobId.uuidString,
            patient_id:    patientId.uuidString,
            attributed_by: attributedBy.uuidString
        )

        do {
            _ = try await supabase
                .from("job_patient_attributions")
                .upsert(payload, onConflict: "job_id")
                .execute()
            return true
        } catch is CancellationError {
            return false
        } catch let urlError as URLError where urlError.code == .cancelled {
            return false
        } catch {
            print("JobAttributionService.attribute failed: \(error)")
            errorMessage = "Couldn't attribute recording: \(error.localizedDescription)"
            return false
        }
    }

    /// Remove a job's attribution (effectively "unattributed").
    /// Clinician-only at the RLS level.
    @discardableResult
    func removeAttribution(jobId: UUID) async -> Bool {
        do {
            _ = try await supabase
                .from("job_patient_attributions")
                .delete()
                .eq("job_id", value: jobId.uuidString)
                .execute()
            return true
        } catch is CancellationError {
            return false
        } catch let urlError as URLError where urlError.code == .cancelled {
            return false
        } catch {
            print("JobAttributionService.removeAttribution failed: \(error)")
            errorMessage = "Couldn't remove attribution: \(error.localizedDescription)"
            return false
        }
    }
}
