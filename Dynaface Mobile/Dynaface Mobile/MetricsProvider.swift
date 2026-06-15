import Foundation

// MARK: - Metrics data source (front/back separation seam)
//
// The Analysis UI depends only on this protocol, never on Supabase/GCP. v1
// runs on MockMetricsProvider, which decodes a REAL backend results.json
// bundled as a sample resource — so the UI runs on real data shape + values
// and the decode path is validated end to end. When the live provider is
// ready, fetch results/{user_id}/{job_id}/results.json and decode it the same
// way; the contract, mapper, and views don't change.

protocol MetricsProviding {
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport
}

// MARK: - Mock provider (v1) — decodes a bundled real results.json

struct MockMetricsProvider: MetricsProviding {
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport { Self.sample }
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport { Self.sample }

    static let sample: FacialMetricsReport = {
        if let url = Bundle.main.url(forResource: "sample_results", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let report = try? JSONDecoder().decode(FacialMetricsReport.self, from: data) {
            return report
        }
        // Safe empty fallback if the sample resource is missing.
        return FacialMetricsReport(
            jobId: nil, userId: nil, inputObjectName: nil,
            annotatedVideoPath: nil, resultsJsonPath: nil, generatedAt: nil,
            summary: MetricsSummary(eye: nil, synkinesis: nil, global: nil),
            perFrame: []
        )
    }()
}

// MARK: - GCP / live provider (stub, not used in v1)

struct GCPMetricsProvider: MetricsProviding {
    // TODO: fetch results/{user_id}/{job_id}/results.json (Supabase signed URL
    // now, GCS by userID+jobNumber after migration) and decode into
    // FacialMetricsReport. Reuse the signed-URL resolver from PatientVideoTabs.
    enum NotReady: Error { case backendPending }
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport { throw NotReady.backendPending }
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport { throw NotReady.backendPending }
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
    let affectedSide: AffectedSide
    private let provider: MetricsProviding

    init(patientId: UUID,
         affectedSide: AffectedSide = .unknown,
         provider: MetricsProviding = MockMetricsProvider()) {
        self.patientId = patientId
        self.affectedSide = affectedSide
        self.provider = provider
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
