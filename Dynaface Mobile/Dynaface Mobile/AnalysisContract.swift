import Foundation

// MARK: - Analysis raw metrics contract
//
// This is the "seam" between the iOS Analysis UI and the backend (Alex's
// pipeline, migrating Supabase -> GCP). It mirrors the field names in Alex's
// "Metric Calculations" document EXACTLY (snake_case), so the JSON the GCP
// Cloud Run job writes to results/{uid}/{job_id}/metrics.json decodes here
// with no remapping. The UI never touches these types directly — the
// presentation mapper (AnalysisPresentation.swift) turns them into view models.
//
// v1 only consumes the Eye + Synkinesis slices (+ global). Other modules'
// fields are intentionally omitted from these structs; decoding ignores
// unknown keys, so adding them later is non-breaking.

struct FacialMetricsReport: Codable {
    let meta: MetricsMeta
    let perFrame: [FrameMetrics]
    let summary: MetricsSummary

    enum CodingKeys: String, CodingKey {
        case meta
        case perFrame = "per_frame"
        case summary
    }
}

struct MetricsMeta: Codable {
    let jobId: String
    let userId: String?
    let assessmentDate: Date?
    let exerciseName: String?
    let nReference: Double?
    /// May be absent from the backend payload — the iOS layer injects the
    /// clinical side from the patient profile (symptoms_location).
    let affectedSide: String?
    /// Optional future-proofing (per expert rec): contract version, and a
    /// capture-mirroring flag so a front-camera mirror fix is a config flip.
    let schemaVersion: String?
    let mirrored: Bool?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case userId = "user_id"
        case assessmentDate = "assessment_date"
        case exerciseName = "exercise_name"
        case nReference = "n_reference"
        case affectedSide = "affected_side"
        case schemaVersion = "schema_version"
        case mirrored
    }
}

// Per-frame slice — only the fields v1 charts need. The real file carries all
// 36 metrics per frame; extra keys are ignored on decode.
struct FrameMetrics: Codable {
    let frame: Int?
    let timeSec: Double?
    let eyeClosureCompletenessR: Double?
    let eyeClosureCompletenessL: Double?
    let synkScore: Double?

    enum CodingKeys: String, CodingKey {
        case frame
        case timeSec = "time_sec"
        case eyeClosureCompletenessR = "eye_closure_completeness_r"
        case eyeClosureCompletenessL = "eye_closure_completeness_l"
        case synkScore = "synk_score"
    }
}

struct MetricsSummary: Codable {
    let eye: EyeSummary?
    let synkinesis: SynkinesisSummary?
    let global: GlobalSummary?
}

struct EyeSummary: Codable {
    let maxApertureL, maxApertureR: Double?
    let minApertureL, minApertureR: Double?
    let eyeClosureCompletenessL, eyeClosureCompletenessR: Double?
    let meanEyeRatio: Double?
    let meanUpperRatioL, meanUpperRatioR: Double?
    let peakCloseVelocityL, peakCloseVelocityR: Double?

    enum CodingKeys: String, CodingKey {
        case maxApertureL = "max_aperture_l"
        case maxApertureR = "max_aperture_r"
        case minApertureL = "min_aperture_l"
        case minApertureR = "min_aperture_r"
        case eyeClosureCompletenessL = "eye_closure_completeness_l"
        case eyeClosureCompletenessR = "eye_closure_completeness_r"
        case meanEyeRatio = "mean_eye_ratio"
        case meanUpperRatioL = "mean_upper_ratio_l"
        case meanUpperRatioR = "mean_upper_ratio_r"
        case peakCloseVelocityL = "peak_close_velocity_l"
        case peakCloseVelocityR = "peak_close_velocity_r"
    }
}

struct SynkinesisSummary: Codable {
    let meanSynkScore, maxSynkScore: Double?
    let meanSynkUpperEyelid, meanSynkLowerEyelid: Double?
    let meanSynkMouthEye, meanBrowEyeCoupling: Double?

    enum CodingKeys: String, CodingKey {
        case meanSynkScore = "mean_synk_score"
        case maxSynkScore = "max_synk_score"
        case meanSynkUpperEyelid = "mean_synk_upper_eyelid"
        case meanSynkLowerEyelid = "mean_synk_lower_eyelid"
        case meanSynkMouthEye = "mean_synk_mouth_eye"
        case meanBrowEyeCoupling = "mean_brow_eye_coupling"
    }
}

struct GlobalSummary: Codable {
    let current, baseline, mean, max, min: Double?
}
