import Foundation

// MARK: - Analysis metrics contract
//
// Mirrors the REAL `results.json` the backend writes to
// results/{user_id}/{job_id}/results.json (verified against a live GCP file).
// Field names are the backend's snake_case originals so the JSON decodes with
// no remapping. The UI never touches these types directly — the presentation
// mapper (AnalysisPresentation.swift) turns them into view models.
//
// The file carries far more than v1 needs (smile/brow/midface/temporal
// modules, 50+ per-frame fields). We only declare what Eye + Synkinesis use;
// unknown keys are ignored on decode, so adding modules later is non-breaking.
//
// NOTE: the JSON has NO clinical "affected side" — that is patient context,
// injected app-side (from profiles.symptoms_location) via AnalysisService.

struct FacialMetricsReport: Codable {
    let jobId: String?
    let userId: String?
    let inputObjectName: String?    // GCP file uses this key
    let videoPath: String?          // Supabase file uses this key (same meaning)
    let annotatedVideoPath: String?
    let resultsJsonPath: String?
    let generatedAt: Double?            // epoch seconds
    let summary: MetricsSummary
    let perFrame: [FrameMetrics]

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case userId = "user_id"
        case inputObjectName = "input_object_name"
        case videoPath = "video_path"
        case annotatedVideoPath = "annotated_video_path"
        case resultsJsonPath = "results_json_path"
        case generatedAt = "generated_at"
        case summary
        case perFrame = "per_frame"
    }
}

struct MetricsSummary: Codable {
    let eye: EyeSummary?
    let synkinesis: SynkinesisSummary?
    let global: GlobalSummary?
    // smile_module / brow_module / midface_module / temporal_dynamics exist in
    // the file but aren't decoded in v1 (Eye + Synkinesis only).

    enum CodingKeys: String, CodingKey {
        case eye = "eye_module"
        case synkinesis
        case global = "global_score"
    }
}

struct EyeSummary: Codable {
    let maxApertureL, maxApertureR: Double?
    let minApertureL, minApertureR: Double?
    let eyeClosureCompletenessL, eyeClosureCompletenessR: Double?
    let meanEyeAreaL, meanEyeAreaR: Double?
    let meanEyeRatio: Double?
    let meanEyeDiff: Double?
    let meanUpperRatioL, meanUpperRatioR: Double?
    let peakCloseVelocityL, peakCloseVelocityR: Double?

    enum CodingKeys: String, CodingKey {
        case maxApertureL = "max_aperture_l"
        case maxApertureR = "max_aperture_r"
        case minApertureL = "min_aperture_l"
        case minApertureR = "min_aperture_r"
        case eyeClosureCompletenessL = "eye_closure_completeness_l"
        case eyeClosureCompletenessR = "eye_closure_completeness_r"
        case meanEyeAreaL = "mean_eye_area_l"
        case meanEyeAreaR = "mean_eye_area_r"
        case meanEyeRatio = "mean_eye_ratio"
        case meanEyeDiff = "mean_eye_diff"
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

// Per-frame slice — only the fields v1 charts need. The file has 50+ per frame;
// extra keys are ignored. `frame` is a JSON float (1.0), so decode as Double.
struct FrameMetrics: Codable {
    let frame: Double?
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
