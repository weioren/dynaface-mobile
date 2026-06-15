import SwiftUI

// MARK: - Analysis presentation layer
//
// Pure-function mapper: turns Alex's raw metrics (FacialMetricsReport) into
// view models the Analysis screens render. ALL UI-only policy lives here —
// domain composite scores, severity thresholds/colors, affected-vs-normal
// column selection, unit/label formatting. The contract stays raw; tuning a
// threshold or a score weight never touches the backend or the views.
//
// v1 covers Eye + Synkinesis detail; the other three domains appear on the
// home screen as placeholder bars only.

// MARK: Shared enums

enum AffectedSide {
    case left, right, both, unknown

    init(_ raw: String?) {
        let s = (raw ?? "").lowercased()
        if s.contains("left") { self = .left }
        else if s.contains("right") { self = .right }
        else if s.contains("both") { self = .both }
        else { self = .unknown }
    }

    /// Whether to frame the two eye columns as Affected/Normal (true) or as
    /// neutral Left/Right (false, for both/unsure).
    var hasAffectedFraming: Bool { self == .left || self == .right }
}

enum MetricSeverity {
    case normal, caution, alert

    var color: Color {
        switch self {
        case .normal:  return Color(red: 0.20, green: 0.70, blue: 0.45) // green
        case .caution: return Color(red: 0.95, green: 0.60, blue: 0.15) // orange
        case .alert:   return Color(red: 0.85, green: 0.25, blue: 0.25) // red
        }
    }
}

enum AnalysisDomain: String, CaseIterable, Identifiable {
    case eye, smile, brow, synkinesis, midface
    var id: String { rawValue }

    var title: String {
        switch self {
        case .eye:        return "Eye Function"
        case .smile:      return "Smile Function"
        case .brow:       return "Brow Function"
        case .synkinesis: return "Synkinesis"
        case .midface:    return "Midface"
        }
    }

    /// v1 ships detail pages only for Eye + Synkinesis.
    var hasDetailV1: Bool { self == .eye || self == .synkinesis }

    /// Synkinesis is a severity score (higher = worse); functional domains are
    /// the opposite (higher = better).
    var isSeverity: Bool { self == .synkinesis }
}

// MARK: Home view models

struct DomainBar: Identifiable {
    let domain: AnalysisDomain
    let percent: Int            // 0...100
    let severity: MetricSeverity
    var id: String { domain.id }
}

struct AnalysisHomeModel {
    let globalScore: Int        // 0...100
    let globalLabel: String
    let bars: [DomainBar]
}

// MARK: Detail view models

struct ChartPoint: Identifiable {
    let id = UUID()
    let t: Double
    let v: Double
}

struct MetricRowVM: Identifiable {
    let id = UUID()
    let label: String
    let affected: String
    let normal: String?        // nil => single-value row
    let severity: MetricSeverity?
}

struct EyeDetailModel {
    let badgeText: String       // e.g. "76 Moderate"
    let badgeSeverity: MetricSeverity
    let affectedLabel: String   // "Left Eye (Affected)" / "Left Eye"
    let affectedClosurePct: Int
    let normalLabel: String
    let normalClosurePct: Int
    let rows: [MetricRowVM]
    let upperContribution: Int  // eyelid contribution donut
    let lowerContribution: Int
    let seriesAffected: [ChartPoint]
    let seriesNormal: [ChartPoint]
}

struct SynkRowVM: Identifiable {
    let id = UUID()
    let label: String
    let value: Double           // 0...1
    let word: String            // Low / Moderate / High
    let severity: MetricSeverity
}

struct SynkDetailModel {
    let badgeText: String       // "0.56 — Moderate"
    let scoreValue: Double      // 0...1, drives the scale marker
    let rows: [SynkRowVM]
}

// MARK: - Mapper

enum AnalysisPresentation {

    // Placeholder bar values for domains without a v1 formula (Smile/Brow/Midface).
    // Mocked to the prototype's home values; replaced once those domains ship.
    private static let placeholderPercents: [AnalysisDomain: Int] =
        [.smile: 72, .brow: 63, .midface: 64]

    // MARK: Home

    static func homeModel(_ report: FacialMetricsReport) -> AnalysisHomeModel {
        let eye = report.summary.eye
        let synk = report.summary.synkinesis
        let affected = AffectedSide(report.meta.affectedSide)

        let eyePct = eyeScore(eye: eye, synk: synk, affected: affected)
        let synkVal = synk?.meanSynkScore ?? 0
        let synkPct = Int((synkVal * 100).rounded())

        var bars: [DomainBar] = []
        for domain in AnalysisDomain.allCases {
            switch domain {
            case .eye:
                bars.append(DomainBar(domain: .eye, percent: eyePct, severity: functionSeverity(eyePct)))
            case .synkinesis:
                bars.append(DomainBar(domain: .synkinesis, percent: synkPct, severity: synkSeverity(synkVal).severity))
            default:
                let p = placeholderPercents[domain] ?? 0
                bars.append(DomainBar(domain: domain, percent: p, severity: functionSeverity(p)))
            }
        }

        let global = Int((report.summary.global?.current ?? 0).rounded())
        return AnalysisHomeModel(globalScore: global, globalLabel: globalLabel(global), bars: bars)
    }

    // MARK: Eye detail

    static func eyeDetail(_ report: FacialMetricsReport, affected: AffectedSide) -> EyeDetailModel {
        let eye = report.summary.eye
        let synk = report.summary.synkinesis

        // Resolve which raw side feeds the "affected" vs "normal" column.
        let affectedIsLeft = (affected != .right) // left/both/unknown default to L-as-affected column
        let ccAffected = (affectedIsLeft ? eye?.eyeClosureCompletenessL : eye?.eyeClosureCompletenessR) ?? 0
        let ccNormal   = (affectedIsLeft ? eye?.eyeClosureCompletenessR : eye?.eyeClosureCompletenessL) ?? 0
        let velAffected = abs((affectedIsLeft ? eye?.peakCloseVelocityL : eye?.peakCloseVelocityR) ?? 0)
        let velNormal   = abs((affectedIsLeft ? eye?.peakCloseVelocityR : eye?.peakCloseVelocityL) ?? 0)
        let upperAffected = (affectedIsLeft ? eye?.meanUpperRatioL : eye?.meanUpperRatioR) ?? 0.5

        // eye_ratio = area_l / area_r. Orient so the affected column reads < 1.
        let rawRatio = eye?.meanEyeRatio ?? 1
        let affectedRatio = affectedIsLeft ? rawRatio : (rawRatio == 0 ? 0 : 1 / rawRatio)

        let score = eyeScore(eye: eye, synk: synk, affected: affected)
        let sev = functionSeverity(score)

        let affLabel = affected.hasAffectedFraming
            ? "\(affectedIsLeft ? "Left" : "Right") Eye (Affected)"
            : "Left Eye"
        let normLabel = affected.hasAffectedFraming
            ? "\(affectedIsLeft ? "Right" : "Left") Eye (Normal)"
            : "Right Eye"

        let rows: [MetricRowVM] = [
            MetricRowVM(label: "Eye Closure Completeness",
                        affected: pct(ccAffected), normal: pct(ccNormal),
                        severity: functionSeverity(Int((ccAffected * 100).rounded()))),
            // Lagophthalmos shown as residual opening at max closure (% of rest).
            MetricRowVM(label: "Lagophthalmos (residual)",
                        affected: pct(1 - ccAffected), normal: pct(1 - ccNormal),
                        severity: (1 - ccAffected) > 0.15 ? .alert : .normal),
            MetricRowVM(label: "Eye Area Ratio",
                        affected: num(affectedRatio), normal: "1.0",
                        severity: abs(affectedRatio - 1) > 0.15 ? .caution : .normal),
            MetricRowVM(label: "Closure Speed",
                        affected: speed(velAffected), normal: speed(velNormal),
                        severity: nil),
        ]

        let upperPct = Int((upperAffected * 100).rounded())

        return EyeDetailModel(
            badgeText: "\(score) \(severityWord(sev))",
            badgeSeverity: sev,
            affectedLabel: affLabel,
            affectedClosurePct: Int((ccAffected * 100).rounded()),
            normalLabel: normLabel,
            normalClosurePct: Int((ccNormal * 100).rounded()),
            rows: rows,
            upperContribution: upperPct,
            lowerContribution: 100 - upperPct,
            seriesAffected: series(report) { affectedIsLeft ? $0.eyeClosureCompletenessL : $0.eyeClosureCompletenessR },
            seriesNormal: series(report) { affectedIsLeft ? $0.eyeClosureCompletenessR : $0.eyeClosureCompletenessL }
        )
    }

    // MARK: Synkinesis detail

    static func synkDetail(_ report: FacialMetricsReport) -> SynkDetailModel {
        let s = report.summary.synkinesis
        let score = s?.meanSynkScore ?? 0
        let (word, _) = synkSeverity(score)

        func row(_ label: String, _ v: Double?) -> SynkRowVM {
            let value = v ?? 0
            let (w, sev) = synkSeverity(value)
            return SynkRowVM(label: label, value: value, word: w, severity: sev)
        }

        return SynkDetailModel(
            badgeText: "\(num(score)) — \(word)",
            scoreValue: score,
            rows: [
                row("Upper Eyelid Synkinesis", s?.meanSynkUpperEyelid),
                row("Lower Eyelid Synkinesis", s?.meanSynkLowerEyelid),
                row("Mouth Movement (eye closure)", s?.meanSynkMouthEye),
                row("Brow-Eye Coupling", s?.meanBrowEyeCoupling),
                row("Global Synkinesis Score", s?.meanSynkScore),
            ]
        )
    }

    // MARK: - Scores & thresholds (v1-provisional; clinically uncalibrated)

    /// Eye composite 0-100. Per expert recommendation, ANCHORED ON THE
    /// AFFECTED side (not a two-eye average, so a weak affected eye isn't
    /// masked by a healthy one): closure_affected + closure_symmetry +
    /// area_symmetry − eyelid-synkinesis penalty. v1-provisional weights.
    static func eyeScore(eye: EyeSummary?, synk: SynkinesisSummary?, affected: AffectedSide) -> Int {
        let ratio = eye?.meanEyeRatio ?? 1
        let ccl = eye?.eyeClosureCompletenessL ?? 0
        let ccr = eye?.eyeClosureCompletenessR ?? 0
        let su = synk?.meanSynkUpperEyelid ?? 0
        let sl = synk?.meanSynkLowerEyelid ?? 0

        // Affected-side closure is the clinically dominant term;
        // both/unknown -> the worse (lower) side.
        let closureAffected: Double
        switch affected {
        case .left:  closureAffected = ccl
        case .right: closureAffected = ccr
        default:     closureAffected = min(ccl, ccr)
        }
        let closureSymmetry = 1 - min(abs(ccl - ccr), 1)
        let areaSymmetry = 1 - min(abs(ratio - 1), 1)
        let eyelidSynk = 0.5 * su + 0.5 * sl

        let raw = 0.55 * closureAffected
                + 0.25 * closureSymmetry
                + 0.20 * areaSymmetry
                - 0.15 * eyelidSynk
        return Int((max(0, min(1, raw)) * 100).rounded())
    }

    /// Functional-domain color: higher % is better.
    static func functionSeverity(_ pct: Int) -> MetricSeverity {
        if pct >= 80 { return .normal }
        if pct >= 60 { return .caution }
        return .alert
    }

    /// Synkinesis 0-1 banding (higher = worse). Reproduces prototype labels.
    static func synkSeverity(_ v: Double) -> (word: String, severity: MetricSeverity) {
        if v < 0.40 { return ("Low", .normal) }
        if v < 0.70 { return ("Moderate", .caution) }
        return ("High", .alert)
    }

    private static func severityWord(_ s: MetricSeverity) -> String {
        switch s {
        case .normal:  return "Normal"
        case .caution: return "Moderate"
        case .alert:   return "Impaired"
        }
    }

    private static func globalLabel(_ score: Int) -> String {
        if score >= 80 { return "Normal Function" }
        if score >= 50 { return "Moderate Dysfunction" }
        return "Severe Dysfunction"
    }

    // MARK: - Formatting helpers

    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    private static func num(_ v: Double) -> String { String(format: "%.2f", v) }
    private static func speed(_ v: Double) -> String { String(format: "%.1f /s", v) }

    private static func series(_ report: FacialMetricsReport,
                               _ pick: (FrameMetrics) -> Double?) -> [ChartPoint] {
        report.perFrame.compactMap { f in
            guard let t = f.timeSec, let v = pick(f) else { return nil }
            return ChartPoint(t: t, v: v)
        }
    }
}
