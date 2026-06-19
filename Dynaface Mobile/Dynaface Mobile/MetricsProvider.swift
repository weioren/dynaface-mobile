import Foundation
import Supabase

// MARK: - Metrics data source (front/back separation seam)
//
// The Analysis UI depends only on this protocol, never on a specific backend.
//   - MockMetricsProvider: decodes a bundled sample results.json (offline /
//     preview / fallback).
//   - SupabaseMetricsProvider: the live path — finds the patient's latest
//     completed job, signs the results.json URL in the `results` bucket,
//     fetches and decodes it. (The same file exists in GCS, but the app has
//     no GCP/Firebase auth yet and the objects aren't public, so Supabase is
//     the reachable source today. A GCS provider is a drop-in later.)
//
// The contract, mapper, and views are identical across providers.

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
            summary: MetricsSummary(eye: nil, synkinesis: nil, global: nil),
            perFrame: []
        )
    }()
}

// MARK: - Supabase provider (live)

struct SupabaseMetricsProvider: MetricsProviding {
    let supabase: SupabaseClient
    let attributionService: JobAttributionService

    func report(forJob jobId: UUID) async throws -> FacialMetricsReport {
        let job: PatientJobRow = try await supabase
            .from("processing_jobs")
            .select()
            .eq("id", value: jobId.uuidString)
            .single()
            .execute()
            .value
        return try await fetchAndDecode(job)
    }

    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport {
        // Newest-first union of self-recorded + attributed completed jobs.
        let jobs = try await fetchAllJobs(
            forPatient: patientId,
            supabase: supabase,
            attributionService: attributionService,
            onlyCompleted: true
        )
        var lastError: Error?
        for job in jobs {
            do { return try await fetchAndDecode(job) }
            catch { lastError = error; continue }
        }
        throw lastError ?? NSError(
            domain: "SupabaseMetricsProvider", code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No completed analysis found for this patient yet."]
        )
    }

    private func fetchAndDecode(_ job: PatientJobRow) async throws -> FacialMetricsReport {
        let url = try await signedResultsJSONURL(for: job, supabase: supabase)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(FacialMetricsReport.self, from: data)
    }
}

/// Resolve a signed URL for a job's `results.json` in the `results` bucket.
/// The worker writes lowercase `{user_id}/{job_id}/results.json`, while
/// `UUID.uuidString` is uppercase — so we try the worker's own directory
/// (from output_video_path) and lowercase ids first, uppercase as fallback.
func signedResultsJSONURL(
    for job: PatientJobRow,
    supabase: SupabaseClient,
    resultsBucket: String = "results"
) async throws -> URL {
    var candidates: [String] = []
    func add(_ p: String) { if !p.isEmpty && !candidates.contains(p) { candidates.append(p) } }

    // 1. Sibling of the worker-written annotated path (authoritative, lowercase).
    if let out = job.output_video_path ?? job.output_csv_path, !out.isEmpty {
        let prefix = "\(resultsBucket)/"
        let norm = out.hasPrefix(prefix) ? String(out.dropFirst(prefix.count)) : out
        let dir = (norm as NSString).deletingLastPathComponent
        add("\(dir)/results.json")
    }
    // 2. Constructed from ids (lowercase first, then uppercase).
    if let uid = job.user_id {
        add("\(uid.uuidString.lowercased())/\(job.id.uuidString.lowercased())/results.json")
        add("\(uid.uuidString)/\(job.id.uuidString)/results.json")
    }

    var lastError: Error?
    for path in candidates {
        do {
            return try await supabase.storage
                .from(resultsBucket)
                .createSignedURL(path: path, expiresIn: 3600)
        } catch {
            lastError = error
            continue
        }
    }
    throw lastError ?? NSError(
        domain: "SupabaseMetricsProvider", code: 404,
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

    /// Switch to the live Supabase source. Called from the view once the
    /// SupabaseClient + attribution service are available in the environment.
    func useSupabase(_ supabase: SupabaseClient, attribution: JobAttributionService) {
        provider = SupabaseMetricsProvider(supabase: supabase, attributionService: attribution)
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
