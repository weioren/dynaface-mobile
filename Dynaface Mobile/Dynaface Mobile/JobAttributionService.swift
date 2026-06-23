import Foundation
import FirebaseFirestore

// MARK: - JobAttributionService
//
// Owns the `job_patient_attributions` Firestore collection. Maps a
// `processing_jobs` document id (an uploaded recording) to a patient
// profile, independent of who actually uploaded the video. This is how we
// attribute a clinician-recorded video to the patient it concerns without
// touching the upload pipeline or the worker.
//
// Doc ID = job id (mirrors the old Postgres table's `job_id` primary key),
// so `.set()` is naturally an upsert — re-attributing is idempotent.
//
// Access contract (mirrors the old Supabase RLS, enforced now by
// firestore.rules using request.auth.token.app_uid + a role lookup on
// profiles/{app_uid}):
//   - read:  clinicians see all; patients see only their own
//   - write: clinicians for any patient; patients for themselves only;
//            attributed_by must match the caller's app_uid
//   - delete: clinicians only
//
// View hierarchy: injected at app root as an @EnvironmentObject so any
// screen that creates / inspects attributions shares one instance.

@MainActor
final class JobAttributionService: ObservableObject {

    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let collectionName = "job_patient_attributions"

    // MARK: - Read

    /// Returns the set of `processing_jobs` ids explicitly attributed to a
    /// given patient via the junction collection. Self-recorded jobs (where
    /// `processing_jobs.user_id` already equals the patient's profile id)
    /// are NOT included — callers handle that side of the union themselves.
    func loadAttributedJobIds(forPatient patientId: UUID) async -> Set<UUID> {
        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("patient_id", isEqualTo: patientId.uuidString)
                .getDocuments()
            return Set(snapshot.documents.compactMap { UUID(uuidString: $0.documentID) })
        } catch is CancellationError {
            return []
        } catch {
            errorMessage = "Couldn't load attributions: \(error.localizedDescription)"
            return []
        }
    }

    /// Fetch the single attribution row for a job, if one exists. Used to
    /// power "attributed to: <name>" badges in lists.
    func loadAttribution(forJob jobId: UUID) async -> JobPatientAttribution? {
        do {
            let snapshot = try await db.collection(collectionName).document(jobId.uuidString).getDocument()
            guard let data = snapshot.data() else { return nil }
            return decode(jobId: jobId, data: data)
        } catch is CancellationError {
            return nil
        } catch {
            print("JobAttributionService.loadAttribution failed: \(error)")
            return nil
        }
    }

    // MARK: - Write

    /// Attribute a job to a patient. `attributedBy` is the signed-in
    /// user's profile id — rules reject mismatches so we forward whatever
    /// the caller passes (no client-side spoofing). Doc ID = job_id, so
    /// this is naturally idempotent ("upsert").
    @discardableResult
    func attribute(
        jobId: UUID,
        patientId: UUID,
        attributedBy: UUID
    ) async -> Bool {
        let data: [String: Any] = [
            "patient_id": patientId.uuidString,
            "attributed_by": attributedBy.uuidString,
            "attributed_at": FieldValue.serverTimestamp(),
        ]
        do {
            try await db.collection(collectionName).document(jobId.uuidString).setData(data)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("JobAttributionService.attribute failed: \(error)")
            errorMessage = "Couldn't attribute recording: \(error.localizedDescription)"
            return false
        }
    }

    /// Remove a job's attribution (effectively "unattributed").
    /// Clinician-only at the rules level.
    @discardableResult
    func removeAttribution(jobId: UUID) async -> Bool {
        do {
            try await db.collection(collectionName).document(jobId.uuidString).delete()
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("JobAttributionService.removeAttribution failed: \(error)")
            errorMessage = "Couldn't remove attribution: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Decode

    private func decode(jobId: UUID, data: [String: Any]) -> JobPatientAttribution? {
        guard
            let patientIdString = data["patient_id"] as? String,
            let patientId = UUID(uuidString: patientIdString),
            let attributedByString = data["attributed_by"] as? String,
            let attributedBy = UUID(uuidString: attributedByString)
        else {
            return nil
        }
        let attributedAt = (data["attributed_at"] as? Timestamp)?.dateValue() ?? Date()
        return JobPatientAttribution(
            jobId: jobId,
            patientId: patientId,
            attributedBy: attributedBy,
            attributedAt: attributedAt
        )
    }
}
