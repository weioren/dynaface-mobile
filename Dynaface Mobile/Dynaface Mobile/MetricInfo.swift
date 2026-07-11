import Foundation

// Analysis metric formulas (D2), surfaced by the per-metric drop-down (U5).
//
// These match the actual backend computation in Alex's
// clinical_report_tool/clinical_facial_report.py (compute_landmark_metrics),
// not a guess. Shared conventions from that file:
//   - N = intercanthal distance (dist between the inner-eye landmarks) — the
//     normalizer for lengths; areas are normalized by N^2.
//   - Displacements are measured from the rest frame; image y grows downward,
//     so an upward move (brow/cheek) is (rest_y - current_y).
//   - "Peak" = the peak-effort frame; ratios/symmetries are per-frame then
//     aggregated. Some rows are proxies (noted) pending real landmarks.
//
// Still DRAFT wording pending Allie's clinical review — when her reviewed copy
// lands, this is the only file to edit. LaTeX uses raw string literals
// (#"..."#); stay within SwiftMath's math subset (\frac, subscripts, \sum,
// greek, \text{…}).

struct MetricVariable: Identifiable {
    let id = UUID()
    let symbol: String      // LaTeX for the symbol
    let meaning: String
}

struct MetricExplanation {
    let measures: String
    let latex: String
    let variables: [MetricVariable]
    let exampleLatex: String
}

enum MetricInfo {

    // MARK: Eye

    static let eyeClosureCompleteness = MetricExplanation(
        measures: "How completely the eyelid closes at the peak-closure frame, vs its resting opening (1 = fully closed).",
        latex: #"C = 1 - \frac{a}{a_{rest}}"#,
        variables: [
            MetricVariable(symbol: #"a"#, meaning: "eyelid aperture (mean upper-lid y minus mean lower-lid y) at peak closure"),
            MetricVariable(symbol: #"a_{rest}"#, meaning: "the same aperture at rest"),
        ],
        exampleLatex: #"C = 1 - \frac{2}{20} = 0.90"#
    )

    static let lagophthalmos = MetricExplanation(
        measures: "Residual eyelid opening left at peak closure (the fraction that fails to close) — the complement of closure completeness.",
        latex: #"L = \frac{a}{a_{rest}} = 1 - C"#,
        variables: [
            MetricVariable(symbol: #"a"#, meaning: "aperture at peak closure"),
            MetricVariable(symbol: #"a_{rest}"#, meaning: "aperture at rest"),
            MetricVariable(symbol: #"C"#, meaning: "eye closure completeness"),
        ],
        exampleLatex: #"L = 1 - 0.90 = 0.10"#
    )

    static let eyeAreaRatio = MetricExplanation(
        measures: "Ratio of the two eyes' open (palpebral-fissure) areas; oriented so the affected column reads below 1.",
        latex: #"R = \frac{A_L}{A_R}"#,
        variables: [
            MetricVariable(symbol: #"A_L"#, meaning: "polygon area of the left-eye landmarks (shoelace)"),
            MetricVariable(symbol: #"A_R"#, meaning: "polygon area of the right-eye landmarks"),
        ],
        exampleLatex: #"R = \frac{140}{200} = 0.70"#
    )

    static let closureSpeed = MetricExplanation(
        measures: "Peak speed of eyelid closing — the largest frame-to-frame drop in eye aperture.",
        latex: #"v = \max_t \left| \frac{a_t - a_{t-1}}{\Delta t} \right|"#,
        variables: [
            MetricVariable(symbol: #"a_t"#, meaning: "eye aperture at frame t"),
            MetricVariable(symbol: #"\Delta t"#, meaning: "time between frames"),
        ],
        exampleLatex: #"v = \frac{6}{0.033} \approx 180"#
    )

    // MARK: Synkinesis (all are movement / eye-closure ratios, clamped to 0..1)

    static let upperEyelidSynkinesis = MetricExplanation(
        measures: "Involuntary upper-eyelid movement during the task, relative to how well the eye closes.",
        latex: #"S = \frac{m_{upper}}{C}"#,
        variables: [
            MetricVariable(symbol: #"m_{upper}"#, meaning: "upper-eyelid displacement from rest, normalized by N"),
            MetricVariable(symbol: #"C"#, meaning: "eye closure completeness"),
        ],
        exampleLatex: #"S = \frac{0.12}{0.80} = 0.15"#
    )

    static let lowerEyelidSynkinesis = MetricExplanation(
        measures: "Involuntary lower-eyelid movement during the task, relative to eye closure.",
        latex: #"S = \frac{m_{lower}}{C}"#,
        variables: [
            MetricVariable(symbol: #"m_{lower}"#, meaning: "lower-eyelid displacement from rest, normalized by N"),
            MetricVariable(symbol: #"C"#, meaning: "eye closure completeness"),
        ],
        exampleLatex: #"S = \frac{0.08}{0.80} = 0.10"#
    )

    static let mouthMovementEyeClosure = MetricExplanation(
        measures: "Involuntary mouth movement during eye closure — smile magnitude relative to total eye closure.",
        latex: #"S = \frac{M}{C_R + C_L}"#,
        variables: [
            MetricVariable(symbol: #"M"#, meaning: "smile magnitude"),
            MetricVariable(symbol: #"C_R,\, C_L"#, meaning: "right / left eye closure completeness"),
        ],
        exampleLatex: #"S = \frac{0.30}{0.80 + 0.82} \approx 0.19"#
    )

    static let browEyeCoupling = MetricExplanation(
        measures: "Unintended brow lift coupled to mouth movement — brow elevation relative to smile magnitude.",
        latex: #"S = \frac{|E|}{M}"#,
        variables: [
            MetricVariable(symbol: #"E"#, meaning: "brow elevation (normalized)"),
            MetricVariable(symbol: #"M"#, meaning: "smile magnitude"),
        ],
        exampleLatex: #"S = \frac{0.20}{0.50} = 0.40"#
    )

    static let globalSynkinesis = MetricExplanation(
        measures: "Overall synkinesis — a weighted blend of the four measures above.",
        latex: #"\bar{S} = 0.30\,S_{up} + 0.30\,S_{low} + 0.25\,S_{me} + 0.15\,S_{be}"#,
        variables: [
            MetricVariable(symbol: #"S_{up},\, S_{low}"#, meaning: "upper / lower eyelid synkinesis"),
            MetricVariable(symbol: #"S_{me}"#, meaning: "mouth-movement-during-eye-closure synkinesis"),
            MetricVariable(symbol: #"S_{be}"#, meaning: "brow-eye coupling"),
        ],
        exampleLatex: #"\bar{S} = 0.30(0.15) + 0.30(0.10) + 0.25(0.19) + 0.15(0.40) \approx 0.18"#
    )

    // MARK: Smile

    static let smileSymmetryRatio = MetricExplanation(
        measures: "Right vs left mouth-corner excursion during the smile (1 = symmetric).",
        latex: #"\sigma = \frac{e_R}{e_L}"#,
        variables: [
            MetricVariable(symbol: #"e_R,\, e_L"#, meaning: "mouth-corner (commissure) excursion from rest, right / left"),
        ],
        exampleLatex: #"\sigma = \frac{6}{10} = 0.60"#
    )

    static let faiVectorDifference = MetricExplanation(
        measures: "Facial Asymmetry Index — the difference between the two sides' eye-to-mouth-corner distances.",
        latex: #"\mathrm{FAI} = \left| v_L - v_R \right|"#,
        variables: [
            MetricVariable(symbol: #"v_L,\, v_R"#, meaning: "distance from the eye center to the mouth corner (÷N), each side"),
        ],
        exampleLatex: #"\mathrm{FAI} = |0.42 - 0.30| = 0.12"#
    )

    static let dentalShow = MetricExplanation(
        measures: "Proxy for tooth show — vertical drop of the mouth center from rest (the backend uses this as a stand-in, not true dental show).",
        latex: #"D = \frac{|\, y_c - y_{c,rest} \,|}{N}"#,
        variables: [
            MetricVariable(symbol: #"y_c"#, meaning: "mouth-center y at peak"),
            MetricVariable(symbol: #"y_{c,rest}"#, meaning: "mouth-center y at rest"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"D = \frac{5}{60} \approx 0.08"#
    )

    static let smileVelocity = MetricExplanation(
        measures: "Average speed of the smile — mean frame-to-frame change in smile magnitude.",
        latex: #"v = \frac{1}{T}\sum_t \frac{M_t - M_{t-1}}{\Delta t}"#,
        variables: [
            MetricVariable(symbol: #"M_t"#, meaning: "smile magnitude at frame t"),
            MetricVariable(symbol: #"\Delta t"#, meaning: "time between frames"),
            MetricVariable(symbol: #"T"#, meaning: "number of frames"),
        ],
        exampleLatex: #"v \approx 0.8\ \text{/s}"#
    )

    static let smileMagnitude = MetricExplanation(
        measures: "Size of the smile — the larger of the two mouth-corner excursions, at its peak.",
        latex: #"M = \frac{\max(e_R, e_L)}{N}"#,
        variables: [
            MetricVariable(symbol: #"e_R,\, e_L"#, meaning: "mouth-corner excursion from rest, right / left"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"M = \frac{\max(9, 10)}{60} \approx 0.17"#
    )

    // MARK: Brow

    static let browElevation = MetricExplanation(
        measures: "How far the brow rises from rest at peak effort, normalized by intercanthal distance.",
        latex: #"E = \frac{\bar{y}_{rest} - \bar{y}}{N}"#,
        variables: [
            MetricVariable(symbol: #"\bar{y}_{rest}"#, meaning: "mean brow-landmark y at rest"),
            MetricVariable(symbol: #"\bar{y}"#, meaning: "mean brow-landmark y at peak (y grows downward, so a rise is positive)"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"E = \frac{130 - 100}{60} = 0.50"#
    )

    static let browSymmetry = MetricExplanation(
        measures: "Right vs left brow elevation (1 = symmetric).",
        latex: #"\sigma = \frac{|E_R|}{|E_L|}"#,
        variables: [
            MetricVariable(symbol: #"E_R,\, E_L"#, meaning: "per-side brow elevation (rest minus current mean y)"),
        ],
        exampleLatex: #"\sigma = \frac{0.30}{0.50} = 0.60"#
    )

    static let medialRecruitment = MetricExplanation(
        measures: "Movement of the inner (medial) brow points from rest, normalized by intercanthal distance.",
        latex: #"R_m = \frac{|\, \bar{y}_{med,rest} - \bar{y}_{med} \,|}{N}"#,
        variables: [
            MetricVariable(symbol: #"\bar{y}_{med}"#, meaning: "mean y of the 3 innermost brow points (per side), at peak"),
            MetricVariable(symbol: #"\bar{y}_{med,rest}"#, meaning: "the same at rest"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"R_m = \frac{12}{60} = 0.20"#
    )

    static let lateralRecruitment = MetricExplanation(
        measures: "Movement of the outer (lateral) brow points from rest, normalized by intercanthal distance.",
        latex: #"R_\ell = \frac{|\, \bar{y}_{lat,rest} - \bar{y}_{lat} \,|}{N}"#,
        variables: [
            MetricVariable(symbol: #"\bar{y}_{lat}"#, meaning: "mean y of the 3 outermost brow points (per side), at peak"),
            MetricVariable(symbol: #"\bar{y}_{lat,rest}"#, meaning: "the same at rest"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"R_\ell = \frac{18}{60} = 0.30"#
    )

    static let recruitmentRatio = MetricExplanation(
        measures: "Right brow's share of total brow movement (fallback when per-side medial/lateral isn't available).",
        latex: #"R = \frac{|E_R|}{|E_R| + |E_L|}"#,
        variables: [
            MetricVariable(symbol: #"E_R,\, E_L"#, meaning: "per-side brow elevation"),
        ],
        exampleLatex: #"R = \frac{0.30}{0.30 + 0.20} = 0.60"#
    )

    // MARK: Midface

    static let alarMovement = MetricExplanation(
        measures: "Displacement of the nostril rim (ala) from rest, per side, normalized by intercanthal distance.",
        latex: #"A = \frac{|\, p_{ala} - p_{ala}^{\,rest} \,|}{N}"#,
        variables: [
            MetricVariable(symbol: #"p_{ala}"#, meaning: "nostril landmark position at peak"),
            MetricVariable(symbol: #"p_{ala}^{\,rest}"#, meaning: "resting nostril position"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"A = \frac{9}{60} = 0.15"#
    )

    static let alarSymmetry = MetricExplanation(
        measures: "How stable the inter-alar (nostril-to-nostril) width stays vs rest (1 = unchanged).",
        latex: #"\sigma = 1 - \frac{|\, w - w_{rest} \,|}{w}"#,
        variables: [
            MetricVariable(symbol: #"w"#, meaning: "inter-alar width at peak (|left nostril x − right nostril x|)"),
            MetricVariable(symbol: #"w_{rest}"#, meaning: "inter-alar width at rest"),
        ],
        exampleLatex: #"\sigma = 1 - \frac{|62 - 60|}{62} \approx 0.97"#
    )

    static let cupidBowDeviation = MetricExplanation(
        measures: "Horizontal shift of the mouth center (cupid's bow) off the facial midline, signed (+ right, − left), normalized.",
        latex: #"\delta = \frac{x_c - x_{mid}}{N}"#,
        variables: [
            MetricVariable(symbol: #"x_c"#, meaning: "mouth-center x"),
            MetricVariable(symbol: #"x_{mid}"#, meaning: "facial-midline x (mean of the two eye centers)"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"\delta = \frac{+3}{60} = +0.05"#
    )

    static let dynamicCupidShift = MetricExplanation(
        measures: "Vertical shift of the mouth center from rest during the movement, normalized.",
        latex: #"\Delta = \frac{|\, y_c - y_{c,rest} \,|}{N}"#,
        variables: [
            MetricVariable(symbol: #"y_c"#, meaning: "mouth-center y at peak"),
            MetricVariable(symbol: #"y_{c,rest}"#, meaning: "mouth-center y at rest"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"\Delta = \frac{4}{60} \approx 0.07"#
    )

    static let upperLip2DArea = MetricExplanation(
        measures: "Left/right symmetry of the upper-lip area (1 = symmetric).",
        latex: #"\sigma = 1 - \frac{|A_L - A_R|}{A_L + A_R}"#,
        variables: [
            MetricVariable(symbol: #"A_L,\, A_R"#, meaning: "upper-lip polygon area either side of the midline (shoelace, ÷N²)"),
        ],
        exampleLatex: #"\sigma = 1 - \frac{|95 - 100|}{195} \approx 0.97"#
    )

    static let cheekElevation = MetricExplanation(
        measures: "Cheek lift per side — currently a proxy equal to brow elevation (no dedicated cheek landmarks yet).",
        latex: #"H = \frac{\bar{y}_{rest} - \bar{y}}{N}"#,
        variables: [
            MetricVariable(symbol: #"\bar{y}_{rest}"#, meaning: "mean brow-landmark y at rest (proxy source)"),
            MetricVariable(symbol: #"\bar{y}"#, meaning: "mean brow-landmark y at peak"),
            MetricVariable(symbol: #"N"#, meaning: "intercanthal distance"),
        ],
        exampleLatex: #"H = \frac{118 - 100}{60} = 0.30"#
    )

    static let midfaceContour = MetricExplanation(
        measures: "Left/right symmetry of the midface (mouth-region) area (1 = symmetric); a 2D proxy, not a volumetric measurement.",
        latex: #"\sigma = 1 - \frac{|A_L - A_R|}{A_L + A_R}"#,
        variables: [
            MetricVariable(symbol: #"A_L,\, A_R"#, meaning: "midface polygon area either side of the midline (shoelace, ÷N²)"),
        ],
        exampleLatex: #"\sigma = 1 - \frac{|48 - 52|}{100} = 0.96"#
    )

    // MARK: Lookup
    //
    // Maps each Analysis row label (including the single-value fallback variants
    // the mappers emit, e.g. "Brow Elevation (max)") to its explanation. Returns
    // nil for a label with no entry yet, which suppresses the drop-down for that
    // row. Keep in sync with the labels in AnalysisPresentation's *Detail mappers.
    static func forLabel(_ label: String) -> MetricExplanation? {
        switch label {
        // Eye
        case "Eye Closure Completeness":     return eyeClosureCompleteness
        case "Lagophthalmos (residual)":     return lagophthalmos
        case "Eye Area Ratio":               return eyeAreaRatio
        case "Closure Speed":                return closureSpeed
        // Synkinesis
        case "Upper Eyelid Synkinesis":      return upperEyelidSynkinesis
        case "Lower Eyelid Synkinesis":      return lowerEyelidSynkinesis
        case "Mouth Movement (eye closure)": return mouthMovementEyeClosure
        case "Brow-Eye Coupling":            return browEyeCoupling
        case "Global Synkinesis Score":      return globalSynkinesis
        // Smile
        case "Smile Symmetry Ratio":         return smileSymmetryRatio
        case "FAI / Vector Difference":      return faiVectorDifference
        case "Dental Show":                  return dentalShow
        case "Smile Velocity":               return smileVelocity
        case "Smile Magnitude":              return smileMagnitude
        // Brow
        case "Brow Elevation", "Brow Elevation (max)": return browElevation
        case "Brow Symmetry":                return browSymmetry
        case "Medial Recruitment":           return medialRecruitment
        case "Lateral Recruitment":          return lateralRecruitment
        case "Recruitment Ratio":            return recruitmentRatio
        // Midface
        case "Alar Movement", "Alar Movement (max)": return alarMovement
        case "Alar Symmetry":                return alarSymmetry
        case "Cupid's Bow Deviation":        return cupidBowDeviation
        case "Dynamic Cupid's Bow Shift":    return dynamicCupidShift
        case "Upper Lip 2D Area":            return upperLip2DArea
        case "Cheek Elevation", "Cheek Elevation (mean)": return cheekElevation
        case "Midface Contour":              return midfaceContour
        default:                             return nil
        }
    }
}
