import Foundation

// DRAFT — pending Allie clinical review (D2).
//
// One `MetricExplanation` per Analysis metric, surfaced by the per-metric
// drop-down (U5): a plain-language description, the formula in LaTeX, a bullet
// list explaining each variable, and a basic worked example. Content is seeded
// from the D1 formula doc (with the "peak frame, not global average" correction
// baked in) and will be replaced by Allie's reviewed wording — when that lands,
// this is the ONLY file to edit.
//
// LaTeX uses raw string literals (#"..."#) so backslashes stay literal. Stay
// within SwiftMath's math subset (fractions, subscripts, roots, sums, greek,
// \text{…}).

struct MetricVariable: Identifiable {
    let id = UUID()
    let symbol: String      // LaTeX for the symbol, e.g. #"\bar{y}_{peak}"#
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
        measures: "How completely the eyelid closes at maximum effort, as a fraction of the resting opening.",
        latex: #"C = 1 - \frac{a_{closed}}{a_{rest}}"#,
        variables: [
            MetricVariable(symbol: #"a_{rest}"#, meaning: "palpebral aperture at rest"),
            MetricVariable(symbol: #"a_{closed}"#, meaning: "aperture at the peak-closure frame"),
        ],
        exampleLatex: #"C = 1 - \frac{2}{20} = 0.90"#
    )

    static let lagophthalmos = MetricExplanation(
        measures: "Residual eyelid opening left at maximum closure — the gap that fails to close.",
        latex: #"L = \frac{a_{closed}}{a_{rest}} = 1 - C"#,
        variables: [
            MetricVariable(symbol: #"a_{closed}"#, meaning: "aperture at peak closure"),
            MetricVariable(symbol: #"a_{rest}"#, meaning: "aperture at rest"),
            MetricVariable(symbol: #"C"#, meaning: "closure completeness"),
        ],
        exampleLatex: #"L = \frac{2}{20} = 0.10"#
    )

    static let eyeAreaRatio = MetricExplanation(
        measures: "Ratio of the affected eye's open area to the normal eye's, oriented so the affected side reads below 1.",
        latex: #"R = \frac{A_{aff}}{A_{norm}}"#,
        variables: [
            MetricVariable(symbol: #"A_{aff}"#, meaning: "palpebral-fissure area, affected side"),
            MetricVariable(symbol: #"A_{norm}"#, meaning: "palpebral-fissure area, normal side"),
        ],
        exampleLatex: #"R = \frac{140}{200} = 0.70"#
    )

    static let closureSpeed = MetricExplanation(
        measures: "Peak downward velocity of the upper eyelid during a closure.",
        latex: #"v = \max\left|\frac{\Delta y_{lid}}{\Delta t}\right|"#,
        variables: [
            MetricVariable(symbol: #"\Delta y_{lid}"#, meaning: "vertical lid displacement between frames"),
            MetricVariable(symbol: #"\Delta t"#, meaning: "frame interval"),
        ],
        exampleLatex: #"v = \frac{6}{0.033} \approx 180"#
    )

    // MARK: Synkinesis

    static let upperEyelidSynkinesis = MetricExplanation(
        measures: "Involuntary upper-eyelid narrowing that occurs while performing a mouth movement.",
        latex: #"S = \frac{|\Delta a_{eye}|}{a_{rest}}"#,
        variables: [
            MetricVariable(symbol: #"\Delta a_{eye}"#, meaning: "eye-aperture change during the mouth task"),
            MetricVariable(symbol: #"a_{rest}"#, meaning: "resting aperture"),
        ],
        exampleLatex: #"S = \frac{3}{20} = 0.15"#
    )

    static let lowerEyelidSynkinesis = MetricExplanation(
        measures: "Involuntary lower-eyelid movement that occurs while performing a mouth movement.",
        latex: #"S = \frac{|\Delta y_{lower}|}{N}"#,
        variables: [
            MetricVariable(symbol: #"\Delta y_{lower}"#, meaning: "lower-lid displacement during the mouth task"),
            MetricVariable(symbol: #"N"#, meaning: "inter-canthal distance (normalizer)"),
        ],
        exampleLatex: #"S = \frac{3}{60} = 0.05"#
    )

    static let mouthMovementEyeClosure = MetricExplanation(
        measures: "Involuntary mouth-corner movement that occurs while closing the eyes.",
        latex: #"S = \frac{|\Delta d_{mouth}|}{N}"#,
        variables: [
            MetricVariable(symbol: #"\Delta d_{mouth}"#, meaning: "commissure displacement during eye closure"),
            MetricVariable(symbol: #"N"#, meaning: "inter-canthal distance (normalizer)"),
        ],
        exampleLatex: #"S = \frac{5}{60} \approx 0.08"#
    )

    static let browEyeCoupling = MetricExplanation(
        measures: "How strongly brow motion is coupled to eye-closure motion (unintended linkage).",
        latex: #"\rho = \mathrm{corr}(b_t,\, e_t)"#,
        variables: [
            MetricVariable(symbol: #"b_t"#, meaning: "per-frame brow position"),
            MetricVariable(symbol: #"e_t"#, meaning: "per-frame eye aperture"),
        ],
        exampleLatex: #"\rho = 0.42"#
    )

    static let globalSynkinesis = MetricExplanation(
        measures: "Overall synkinesis — the mean of the individual synkinesis measures.",
        latex: #"\bar{S} = \frac{1}{n}\sum_{i=1}^{n} S_i"#,
        variables: [
            MetricVariable(symbol: #"S_i"#, meaning: "each component synkinesis score"),
            MetricVariable(symbol: #"n"#, meaning: "number of components"),
        ],
        exampleLatex: #"\bar{S} = \frac{0.15+0.05+0.08+0.42}{4} \approx 0.18"#
    )

    // MARK: Smile

    static let smileSymmetryRatio = MetricExplanation(
        measures: "Symmetry of mouth-corner excursion between the two sides during a smile (1 = symmetric).",
        latex: #"\sigma = \frac{\min(e_L, e_R)}{\max(e_L, e_R)}"#,
        variables: [
            MetricVariable(symbol: #"e_L,\, e_R"#, meaning: "commissure excursion on each side"),
        ],
        exampleLatex: #"\sigma = \frac{6}{10} = 0.60"#
    )

    static let faiVectorDifference = MetricExplanation(
        measures: "Facial Asymmetry Index — the difference between the left and right smile displacement vectors.",
        latex: #"\mathrm{FAI} = \left|\, \vec{s}_L - \vec{s}_R \,\right|"#,
        variables: [
            MetricVariable(symbol: #"\vec{s}_L,\, \vec{s}_R"#, meaning: "smile displacement vector (mm) per side"),
        ],
        exampleLatex: #"\mathrm{FAI} = |8 - 4| = 4\ \text{mm}"#
    )

    static let dentalShow = MetricExplanation(
        measures: "Maximum vertical tooth show during the smile.",
        latex: #"D = \max_t\, d_{show}(t)"#,
        variables: [
            MetricVariable(symbol: #"d_{show}(t)"#, meaning: "visible tooth height at frame t"),
        ],
        exampleLatex: #"D = 5\ \text{mm}"#
    )

    static let smileVelocity = MetricExplanation(
        measures: "Average speed of mouth-corner movement while forming the smile.",
        latex: #"v = \frac{1}{n}\sum_t \frac{\Delta d_t}{\Delta t}"#,
        variables: [
            MetricVariable(symbol: #"\Delta d_t"#, meaning: "commissure displacement per frame"),
            MetricVariable(symbol: #"\Delta t"#, meaning: "frame interval"),
        ],
        exampleLatex: #"v \approx 45\ \text{mm/s}"#
    )

    static let smileMagnitude = MetricExplanation(
        measures: "Overall size of the smile — peak combined mouth-corner excursion.",
        latex: #"M = \max_t\, \big(e_L(t) + e_R(t)\big)"#,
        variables: [
            MetricVariable(symbol: #"e_L,\, e_R"#, meaning: "per-side commissure excursion"),
        ],
        exampleLatex: #"M = 10 + 9 = 19"#
    )

    // MARK: Brow

    static let browElevation = MetricExplanation(
        measures: "How high the brow raises from rest at peak effort, normalized by inter-canthal distance.",
        latex: #"E = \frac{\bar{y}_{rest} - \bar{y}_{peak}}{N}"#,
        variables: [
            MetricVariable(symbol: #"\bar{y}_{rest}"#, meaning: "mean brow-landmark height at rest"),
            MetricVariable(symbol: #"\bar{y}_{peak}"#, meaning: "mean brow-landmark height at peak (image y grows downward)"),
            MetricVariable(symbol: #"N"#, meaning: "inter-canthal distance (normalizer)"),
        ],
        exampleLatex: #"E = \frac{130 - 100}{60} = 0.50"#
    )

    static let browSymmetry = MetricExplanation(
        measures: "Symmetry of brow elevation between the two sides (1 = symmetric).",
        latex: #"\sigma = \frac{\min(E_L, E_R)}{\max(E_L, E_R)}"#,
        variables: [
            MetricVariable(symbol: #"E_L,\, E_R"#, meaning: "brow elevation per side"),
        ],
        exampleLatex: #"\sigma = \frac{0.3}{0.5} = 0.60"#
    )

    static let medialRecruitment = MetricExplanation(
        measures: "Share of brow elevation coming from the medial (inner) brow points.",
        latex: #"R_m = \frac{\Delta y_{medial}}{\Delta y_{brow}}"#,
        variables: [
            MetricVariable(symbol: #"\Delta y_{medial}"#, meaning: "displacement of the medial brow points"),
            MetricVariable(symbol: #"\Delta y_{brow}"#, meaning: "total brow displacement"),
        ],
        exampleLatex: #"R_m = \frac{12}{30} = 0.40"#
    )

    static let lateralRecruitment = MetricExplanation(
        measures: "Share of brow elevation coming from the lateral (outer) brow points.",
        latex: #"R_\ell = \frac{\Delta y_{lateral}}{\Delta y_{brow}}"#,
        variables: [
            MetricVariable(symbol: #"\Delta y_{lateral}"#, meaning: "displacement of the lateral brow points"),
            MetricVariable(symbol: #"\Delta y_{brow}"#, meaning: "total brow displacement"),
        ],
        exampleLatex: #"R_\ell = \frac{18}{30} = 0.60"#
    )

    static let recruitmentRatio = MetricExplanation(
        measures: "Balance of medial vs lateral brow recruitment during elevation.",
        latex: #"R = \frac{\Delta y_{medial}}{\Delta y_{lateral}}"#,
        variables: [
            MetricVariable(symbol: #"\Delta y_{medial}"#, meaning: "medial brow-point displacement"),
            MetricVariable(symbol: #"\Delta y_{lateral}"#, meaning: "lateral brow-point displacement"),
        ],
        exampleLatex: #"R = \frac{12}{18} \approx 0.67"#
    )

    // MARK: Midface

    static let alarMovement = MetricExplanation(
        measures: "Peak displacement of the nostril rim (ala) during the exercise, normalized by inter-canthal distance.",
        latex: #"A = \frac{\max_t\, |p_{ala}(t) - p_{ala}^{\,rest}|}{N}"#,
        variables: [
            MetricVariable(symbol: #"p_{ala}(t)"#, meaning: "ala landmark position at frame t"),
            MetricVariable(symbol: #"p_{ala}^{\,rest}"#, meaning: "resting ala position"),
            MetricVariable(symbol: #"N"#, meaning: "inter-canthal distance (normalizer)"),
        ],
        exampleLatex: #"A = \frac{9}{60} = 0.15"#
    )

    static let alarSymmetry = MetricExplanation(
        measures: "Symmetry of nostril-rim movement between the two sides.",
        latex: #"\sigma = \frac{\min(A_L, A_R)}{\max(A_L, A_R)}"#,
        variables: [
            MetricVariable(symbol: #"A_L,\, A_R"#, meaning: "alar movement per side"),
        ],
        exampleLatex: #"\sigma = \frac{0.12}{0.15} = 0.80"#
    )

    static let cupidBowDeviation = MetricExplanation(
        measures: "Horizontal deviation of the cupid's-bow midpoint from the facial midline (signed: + right, − left).",
        latex: #"\delta = x_{cupid} - x_{mid}"#,
        variables: [
            MetricVariable(symbol: #"x_{cupid}"#, meaning: "cupid's-bow midpoint x-coordinate"),
            MetricVariable(symbol: #"x_{mid}"#, meaning: "facial-midline x-coordinate"),
        ],
        exampleLatex: #"\delta = +3\ \text{(toward right)}"#
    )

    static let dynamicCupidShift = MetricExplanation(
        measures: "Average horizontal shift of the cupid's bow across the movement (per-frame).",
        latex: #"\bar{\delta} = \frac{1}{n}\sum_t \big(x_{cupid}(t) - x_{mid}\big)"#,
        variables: [
            MetricVariable(symbol: #"x_{cupid}(t)"#, meaning: "cupid's-bow x at frame t"),
            MetricVariable(symbol: #"x_{mid}"#, meaning: "facial-midline x"),
            MetricVariable(symbol: #"n"#, meaning: "number of frames"),
        ],
        exampleLatex: #"\bar{\delta} \approx 1.5"#
    )

    static let upperLip2DArea = MetricExplanation(
        measures: "Symmetry of the upper-lip area between the two halves (polygon area via the shoelace formula).",
        latex: #"A = \tfrac{1}{2}\left|\sum_i (x_i y_{i+1} - x_{i+1} y_i)\right|,\quad \sigma = \frac{\min(A_L, A_R)}{\max(A_L, A_R)}"#,
        variables: [
            MetricVariable(symbol: #"(x_i, y_i)"#, meaning: "upper-lip contour landmarks"),
            MetricVariable(symbol: #"A_L,\, A_R"#, meaning: "upper-lip half-areas"),
        ],
        exampleLatex: #"\sigma = \frac{95}{100} = 0.95"#
    )

    static let cheekElevation = MetricExplanation(
        measures: "Mean upward cheek movement per side during the smile, normalized by inter-canthal distance.",
        latex: #"H = \frac{\bar{y}_{rest} - \bar{y}_{peak}}{N}"#,
        variables: [
            MetricVariable(symbol: #"\bar{y}_{rest}"#, meaning: "mean cheek-landmark height at rest"),
            MetricVariable(symbol: #"\bar{y}_{peak}"#, meaning: "mean cheek-landmark height at peak"),
            MetricVariable(symbol: #"N"#, meaning: "inter-canthal distance (normalizer)"),
        ],
        exampleLatex: #"H = \frac{118 - 100}{60} = 0.30"#
    )

    static let midfaceContour = MetricExplanation(
        measures: "Left/right symmetry of the midface contour (1 = symmetric); a 2D proxy, not a volumetric measurement.",
        latex: #"\sigma = 1 - \frac{|C_L - C_R|}{C_L + C_R}"#,
        variables: [
            MetricVariable(symbol: #"C_L,\, C_R"#, meaning: "midface contour extent per side"),
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
