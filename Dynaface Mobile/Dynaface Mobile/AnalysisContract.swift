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
    let smile: SmileSummary?
    let brow: BrowSummary?
    let midface: MidfaceSummary?
    // temporal_dynamics also exists in the file but isn't decoded yet.

    enum CodingKeys: String, CodingKey {
        case eye = "eye_module"
        case synkinesis
        case global = "global_score"
        case smile = "smile_module"
        case brow = "brow_module"
        case midface = "midface_module"
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

struct SmileSummary: Codable {
    let maxCommissureExcL, maxCommissureExcR: Double?
    let maxSmileMagnitude: Double?
    let meanSmileSymmetry: Double?
    let meanSmileVelocity, maxSmileVelocity: Double?
    let maxDentalShow: Double?
    let maxSmileVectorL, maxSmileVectorR: Double?
    let meanFai: Double?

    enum CodingKeys: String, CodingKey {
        case maxCommissureExcL = "max_commissure_exc_l"
        case maxCommissureExcR = "max_commissure_exc_r"
        case maxSmileMagnitude = "max_smile_magnitude"
        case meanSmileSymmetry = "mean_smile_symmetry"
        case meanSmileVelocity = "mean_smile_velocity"
        case maxSmileVelocity = "max_smile_velocity"
        case maxDentalShow = "max_dental_show"
        case maxSmileVectorL = "max_smile_vector_l"
        case maxSmileVectorR = "max_smile_vector_r"
        case meanFai = "mean_fai"
    }
}

// The worker now emits per-side (`*_l`/`*_r`) values for brow + midface, plus
// medial/lateral recruitment and midface_contour — so the affected-vs-normal
// compare bars render real two-tone values. The legacy single fields are kept
// for the home-screen composite scores. All optional → older results.json
// (pre-per-side) still decodes.
struct BrowSummary: Codable {
    let maxBrowElevation: Double?
    let meanBrowSymmetry: Double?
    let meanRecruitmentRatio: Double?
    // Per-side additions
    let maxBrowElevationL, maxBrowElevationR: Double?
    let medialRecruitmentL, medialRecruitmentR: Double?
    let lateralRecruitmentL, lateralRecruitmentR: Double?

    enum CodingKeys: String, CodingKey {
        case maxBrowElevation = "max_brow_elevation"
        case meanBrowSymmetry = "mean_brow_symmetry"
        case meanRecruitmentRatio = "mean_recruitment_ratio"
        case maxBrowElevationL = "max_brow_elevation_l"
        case maxBrowElevationR = "max_brow_elevation_r"
        case medialRecruitmentL = "medial_recruitment_l"
        case medialRecruitmentR = "medial_recruitment_r"
        case lateralRecruitmentL = "lateral_recruitment_l"
        case lateralRecruitmentR = "lateral_recruitment_r"
    }
}

struct MidfaceSummary: Codable {
    let maxAlarMovement: Double?
    let meanAlarSymmetry: Double?
    let meanCheekElevation: Double?
    let meanMidfaceArea: Double?
    let meanDynamicShift: Double?
    // Per-side + derived additions
    let maxAlarMovementL, maxAlarMovementR: Double?
    let meanCheekElevationL, meanCheekElevationR: Double?
    let maxCupidBowDeviation: Double?          // signed: + = toward right
    let upperLipAreaL, upperLipAreaR: Double?
    let upperLipSymmetry: Double?
    let midfaceAreaL, midfaceAreaR: Double?
    let midfaceContour: Double?

    enum CodingKeys: String, CodingKey {
        case maxAlarMovement = "max_alar_movement"
        case meanAlarSymmetry = "mean_alar_symmetry"
        case meanCheekElevation = "mean_cheek_elevation"
        case meanMidfaceArea = "mean_midface_area"
        case meanDynamicShift = "mean_dynamic_shift"
        case maxAlarMovementL = "max_alar_movement_l"
        case maxAlarMovementR = "max_alar_movement_r"
        case meanCheekElevationL = "mean_cheek_elevation_l"
        case meanCheekElevationR = "mean_cheek_elevation_r"
        case maxCupidBowDeviation = "max_cupid_bow_deviation"
        case upperLipAreaL = "upper_lip_area_l"
        case upperLipAreaR = "upper_lip_area_r"
        case upperLipSymmetry = "upper_lip_symmetry"
        case midfaceAreaL = "midface_area_l"
        case midfaceAreaR = "midface_area_r"
        case midfaceContour = "midface_contour"
    }
}

// Per-frame slice — only the fields v1 charts need. The file has 50+ per frame;
// extra keys are ignored. `frame` is a JSON float (1.0), so decode as Double.
struct FrameMetrics: Codable {
    let frame: Double?
    let timeSec: Double?
    let eyeClosureCompletenessR: Double?
    let eyeClosureCompletenessL: Double?
    let synkScore: Double?
    let browElevation: Double?       // drives the Brow Elevation trend chart
    let browElevationL, browElevationR: Double?
    let cupidBowDeviation: Double?   // midface: max abs over frames = "deviation"
    let alarMovementL, alarMovementR: Double?
    let cheekElevationL, cheekElevationR: Double?

    enum CodingKeys: String, CodingKey {
        case frame
        case timeSec = "time_sec"
        case eyeClosureCompletenessR = "eye_closure_completeness_r"
        case eyeClosureCompletenessL = "eye_closure_completeness_l"
        case synkScore = "synk_score"
        case browElevation = "brow_elevation"
        case browElevationL = "brow_elevation_l"
        case browElevationR = "brow_elevation_r"
        case cupidBowDeviation = "cupid_bow_deviation"
        case alarMovementL = "alar_movement_l"
        case alarMovementR = "alar_movement_r"
        case cheekElevationL = "cheek_elevation_l"
        case cheekElevationR = "cheek_elevation_r"
    }
}
