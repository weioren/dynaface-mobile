import Foundation

// MARK: - Metrics data source (front/back separation seam)
//
// The Analysis UI depends only on this protocol, never on Supabase/GCP. v1
// runs on MockMetricsProvider (fixtures shaped exactly like Alex's contract).
// When the GCP pipeline is ready, implement GCPMetricsProvider (fetch
// results/{uid}/{job_id}/metrics.json) and swap the injected instance — the
// contract, mapper, and views don't change.

protocol MetricsProviding {
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport
}

// MARK: - Mock provider (v1)

struct MockMetricsProvider: MetricsProviding {
    func report(forJob jobId: UUID) async throws -> FacialMetricsReport { Self.sample }
    func latestReport(forPatient patientId: UUID) async throws -> FacialMetricsReport { Self.sample }

    /// Fixture whose values mirror the Oren prototype (affected = left eye).
    static let sample: FacialMetricsReport = FacialMetricsReport(
        meta: MetricsMeta(
            jobId: "mock-job",
            userId: "mock-user",
            assessmentDate: Date(),
            exerciseName: "Blinking",
            nReference: 142.7,
            affectedSide: "left",
            schemaVersion: "1.0",
            mirrored: false
        ),
        perFrame: sampleFrames(),
        summary: MetricsSummary(
            eye: EyeSummary(
                maxApertureL: 0.181, maxApertureR: 0.184,
                minApertureL: 0.034, minApertureR: 0.000,
                eyeClosureCompletenessL: 0.81, eyeClosureCompletenessR: 1.00,
                meanEyeRatio: 0.82,
                meanUpperRatioL: 0.68, meanUpperRatioR: 0.71,
                peakCloseVelocityL: -1.8, peakCloseVelocityR: -2.1
            ),
            synkinesis: SynkinesisSummary(
                meanSynkScore: 0.56, maxSynkScore: 0.63,
                meanSynkUpperEyelid: 0.82, meanSynkLowerEyelid: 0.71,
                meanSynkMouthEye: 0.56, meanBrowEyeCoupling: 0.43
            ),
            global: GlobalSummary(current: 72, baseline: 64, mean: 68, max: 74, min: 60)
        )
    )

    private static func sampleFrames() -> [FrameMetrics] {
        (0..<16).map { i in
            let t = Double(i) * 0.1
            let progress = min(1.0, Double(i) / 8.0) // closure ramps over first 8 frames
            return FrameMetrics(
                frame: i,
                timeSec: t,
                eyeClosureCompletenessR: progress * 1.00, // right = normal
                eyeClosureCompletenessL: progress * 0.81, // left = affected
                synkScore: progress * 0.56
            )
        }
    }
}

// MARK: - GCP provider (stub, not used in v1)

struct GCPMetricsProvider: MetricsProviding {
    // TODO: fetch results/{uid}/{job_id}/metrics.json (Supabase signed URL now,
    // GCS by userID+jobNumber after migration). Reuse the signed-URL resolver
    // pattern from PatientVideoTabs.swift. Decode into FacialMetricsReport.
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
    private let provider: MetricsProviding

    /// Affected side comes from the loaded report's meta (backend or
    /// iOS-injected from the patient profile); defaults to unknown.
    var affectedSide: AffectedSide { AffectedSide(report?.meta.affectedSide) }

    init(patientId: UUID,
         provider: MetricsProviding = MockMetricsProvider()) {
        self.patientId = patientId
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
