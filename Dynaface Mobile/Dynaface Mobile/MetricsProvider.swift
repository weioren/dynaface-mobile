import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - Metrics data source (front/back separation seam)
//
// The Analysis UI depends only on this protocol, never on a specific backend.
//   - MockMetricsProvider: decodes a bundled sample results.json (offline /
//     preview / fallback).
//   - FirebaseMetricsProvider: the live path — finds the patient's latest
//     completed job in Firestore, resolves the results.json download URL in
//     the GCS `results` bucket, fetches and decodes it.
//
// The contract, mapper, and views are identical across providers — only the
// data source differs (this file is the only Firebase-coupled piece of the
// Analysis module; everything else is backend-agnostic).

protocol MetricsProviding {
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport
}

// MARK: - Mock provider — decodes a bundled sample results.json

struct MockMetricsProvider: MetricsProviding {
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport { Self.sample }
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport { Self.sample }

    static let sample: FacialMetricsReport = {
        if let url = Bundle.main.url(forResource: "sample_results", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let report = try? JSONDecoder().decode(FacialMetricsReport.self, from: data) {
            return report
        }
        return FacialMetricsReport(
            jobId: nil, userId: nil, inputObjectName: nil, videoPath: nil,
            annotatedVideoPath: nil, resultsJsonPath: nil, generatedAt: nil,
            summary: MetricsSummary(eye: nil, synkinesis: nil, global: nil,
                                    smile: nil, brow: nil, midface: nil),
            perFrame: []
        )
    }()
}

// MARK: - Firebase provider (live)
//
// Job discovery reuses the exact same Firestore union (self-recorded +
// attributed completed jobs) the Processed tab uses (`fetchAllJobs` in
// PatientVideoTabs.swift), then reads `results/{user_id}/{job_id}/results.json`
// from the GCS results bucket via FirebaseStorage `downloadURL()` (gated by
// storage.rules). Drops in behind the protocol exactly where the old Supabase
// provider sat.

struct FirebaseMetricsProvider: MetricsProviding {
    let attributionService: JobAttributionService

    func report(forJob jobId: UUID) async throws -> FacialMetricsReport {
        let snapshot = try await Firestore.firestore()
            .collection("processing_jobs")
            .document(jobId.uuidString)
            .getDocument()
        guard let data = snapshot.data(),
              let job = decodeJobRow(id: jobId.uuidString, data: data) else {
            throw NSError(
                domain: "FirebaseMetricsProvider", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Job \(jobId) not found."]
            )
        }
        return try await fetchAndDecode(job)
    }

    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport {
        // Newest-first union of self-recorded + attributed completed jobs.
        let jobs = try await fetchAllJobs(
            forPatient: patientId,
            attributionService: attributionService,
            onlyCompleted: true
        )
        var lastError: Error?
        for job in jobs {
            do { return try await fetchAndDecode(job) }
            catch { lastError = error; continue }
        }
        throw lastError ?? NSError(
            domain: "FirebaseMetricsProvider", code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No completed analysis found for this patient yet."]
        )
    }

    private func fetchAndDecode(_ job: PatientJobRow) async throws -> FacialMetricsReport {
        let url = try await resultsJSONDownloadURL(for: job)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(FacialMetricsReport.self, from: data)
    }
}

/// Resolve a download URL for a job's `results.json` in the GCS results bucket.
/// Mirrors `signedProcessedVideoURL` (PatientVideoTabs.swift): the worker writes
/// `results/{user_id}/{job_id}/results.json` next to `annotated.mp4`, so derive
/// the directory from the stored output path, with a canonical fallback.
/// `downloadURL()` returns an authenticated HTTPS URL; storage.rules gate access.
func resultsJSONDownloadURL(for job: PatientJobRow) async throws -> URL {
    var candidates: [String] = []
    func add(_ p: String) { if !p.isEmpty && !candidates.contains(p) { candidates.append(p) } }

    // 1. Sibling of the worker-written output path (authoritative — same dir).
    if let out = job.output_video_path ?? job.output_csv_path, !out.isEmpty {
        let dir = (out as NSString).deletingLastPathComponent
        add("\(dir)/results.json")
    }
    // 2. Canonical convention fallback.
    if let uid = job.user_id {
        add("results/\(uid.uuidString)/\(job.id.uuidString)/results.json")
    }

    let storage = Storage.storage(url: FirebaseConfig.resultsBucketURL)
    var lastError: Error?
    for path in candidates {
        do {
            return try await storage.reference(withPath: path).downloadURL()
        } catch {
            lastError = error
            continue
        }
    }
    throw lastError ?? NSError(
        domain: "FirebaseMetricsProvider", code: 404,
        userInfo: [NSLocalizedDescriptionKey: "results.json not found for job \(job.id)."]
    )
}

// MARK: - Analysis service

@MainActor
final class AnalysisService: ObservableObject {
    @Published private(set) var report: FacialMetricsReport?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let patientId: UUID
    /// Clinical affected side — injected from the patient profile
    /// (results.json carries no clinical side). Defaults to unknown until
    /// wired from profiles.symptoms_location.
    var affectedSide: AffectedSide
    private var provider: MetricsProviding

    init(patientId: UUID,
         affectedSide: AffectedSide = .unknown,
         provider: MetricsProviding = MockMetricsProvider()) {
        self.patientId = patientId
        self.affectedSide = affectedSide
        self.provider = provider
    }

    /// Switch to the live Firebase source. Called from the view once the
    /// attribution service is available in the environment.
    func useFirebase(attribution: JobAttributionService) {
        provider = FirebaseMetricsProvider(attributionService: attribution)
    }

    func loadIfNeeded() async {
        if report == nil { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            report = try await provider.latestReport(forPatient: patientId)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load analysis: \(error.localizedDescription)"
        }
    }
}
