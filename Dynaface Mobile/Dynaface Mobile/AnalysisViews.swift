import SwiftUI
import Charts
import UIKit

// MARK: - Analysis views (v1: Home + Eye + Synkinesis)
//
// All data arrives via AnalysisService (mock-backed in v1). Views render the
// view models produced by AnalysisPresentation; they hold no metric logic.

private let brandBlue = Color(red: 0.12, green: 0.29, blue: 0.64)

// MARK: - Home

struct AnalysisHomeView: View {
    @ObservedObject var service: AnalysisService
    @EnvironmentObject private var attributionService: JobAttributionService

    var body: some View {
        Group {
            if let report = service.report {
                content(report)
            } else if service.isLoading {
                ProgressView("Loading analysis…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .task {
            // Switch to the live Firebase source, then load.
            service.useFirebase(attribution: attributionService)
            await service.loadIfNeeded()
        }
        .alert(
            "Couldn't load analysis",
            isPresented: Binding(
                get: { service.errorMessage != nil },
                set: { if !$0 { service.errorMessage = nil } }
            ),
            presenting: service.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 50)).foregroundColor(.gray.opacity(0.5))
            Text("No analysis yet")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ report: FacialMetricsReport) -> some View {
        let home = AnalysisPresentation.homeModel(report, affected: service.affectedSide)
        ScrollView {
            VStack(spacing: 20) {
                ScoreGauge(score: home.globalScore, label: home.globalLabel)

                VStack(spacing: 10) {
                    ForEach(home.bars) { bar in
                        switch bar.domain {
                        case .eye:
                            NavigationLink {
                                EyeDetailView(model: AnalysisPresentation.eyeDetail(report, affected: service.affectedSide))
                            } label: { DomainBarRow(bar: bar, navigable: true) }
                            .buttonStyle(.plain)
                        case .synkinesis:
                            NavigationLink {
                                SynkinesisDetailView(model: AnalysisPresentation.synkDetail(report))
                            } label: { DomainBarRow(bar: bar, navigable: true) }
                            .buttonStyle(.plain)
                        case .smile:
                            NavigationLink {
                                SmileDetailView(model: AnalysisPresentation.smileDetail(report))
                            } label: { DomainBarRow(bar: bar, navigable: true) }
                            .buttonStyle(.plain)
                        case .brow:
                            NavigationLink {
                                BrowDetailView(model: AnalysisPresentation.browDetail(report, affected: service.affectedSide))
                            } label: { DomainBarRow(bar: bar, navigable: true) }
                            .buttonStyle(.plain)
                        case .midface:
                            NavigationLink {
                                MidfaceDetailView(model: AnalysisPresentation.midfaceDetail(report, affected: service.affectedSide))
                            } label: { DomainBarRow(bar: bar, navigable: true) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.06))
                .cornerRadius(16)

                Text("Preliminary — derived metrics for clinical review, not a validated score.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
    }
}

// MARK: - Shared components

private struct ScoreGauge: View {
    let score: Int
    let label: String
    private var fraction: Double { Double(max(0, min(100, score))) / 100 }
    private var color: Color { AnalysisPresentation.functionSeverity(score).color }

    var body: some View {
        VStack(spacing: 8) {
            Text("Global Facial Function")
                .font(.subheadline).foregroundColor(.secondary)
            ZStack {
                Circle().stroke(Color.gray.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(score)").font(.system(size: 44, weight: .bold))
                    Text("/ 100").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 170, height: 170)
            .padding(.vertical, 4)
            Text(label).font(.headline).foregroundColor(color)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
    }
}

private struct DomainBarRow: View {
    let bar: DomainBar
    let navigable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(bar.domain.title)
                .font(.subheadline).fontWeight(.medium)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.18))
                    Capsule().fill(bar.severity.color)
                        .frame(width: geo.size.width * CGFloat(bar.percent) / 100)
                }
            }
            .frame(height: 8)
            Text("\(bar.percent)%")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(bar.severity.color)
                .frame(width: 46, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption).foregroundColor(.secondary)
                .opacity(navigable ? 0.6 : 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct SeverityBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Metric formula drop-down (U5)

/// Chevron indicator for an expandable metric row; rotates when open.
private struct DisclosureChevron: View {
    let expanded: Bool
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption2)
            .foregroundColor(.secondary)
            .rotationEffect(.degrees(expanded ? 180 : 0))
    }
}

/// The expanded panel for a metric: what it measures, the LaTeX formula, a
/// bullet per variable, and a worked example. Content comes from MetricInfo (D2).
private struct FormulaPanel: View {
    let explanation: MetricExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(explanation.measures)
                .font(.footnote).foregroundColor(.secondary)
                .textSelection(.enabled)

            formulaRow(explanation.latex, fontSize: 18)

            if !explanation.variables.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(explanation.variables) { v in
                        HStack(alignment: .center, spacing: 8) {
                            Text("•").font(.footnote).foregroundColor(.secondary)
                            LaTeXView(latex: v.symbol, fontSize: 14)
                                .contextMenu { copyButton(v.symbol) }
                            Text(v.meaning).font(.footnote).foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("EXAMPLE")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                formulaRow(explanation.exampleLatex, fontSize: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.gray.opacity(0.10))
        .cornerRadius(10)
        .padding(.top, 6)
    }

    /// A LaTeX formula in a horizontal scroll — wide formulas never clip or
    /// misalign, and long-press copies the LaTeX source.
    private func formulaRow(_ latex: String, fontSize: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LaTeXView(latex: latex, fontSize: fontSize)
                .padding(.vertical, 2)
                .contextMenu { copyButton(latex) }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("Copy LaTeX", systemImage: "doc.on.doc")
        }
    }
}

private struct MetricRowView: View {
    let row: MetricRowVM
    @State private var expanded = false
    private var info: MetricExplanation? { MetricInfo.forLabel(row.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(row.label).font(.body)
                if info != nil { DisclosureChevron(expanded: expanded) }
                Spacer()
                Text(row.affected)
                    .fontWeight(.semibold)
                    .foregroundColor(row.severity?.color ?? .primary)
                if let normal = row.normal {
                    Text("|").foregroundColor(.secondary)
                    Text(normal).foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if info != nil { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            }

            if expanded, let info { FormulaPanel(explanation: info) }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Eye detail

struct EyeDetailView: View {
    let model: EyeDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    SeverityBadge(text: model.badgeText, color: model.badgeSeverity.color)
                }

                HStack(spacing: 12) {
                    EyeCard(title: model.affectedLabel, pct: model.affectedClosurePct)
                    EyeCard(title: model.normalLabel, pct: model.normalClosurePct)
                }

                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        MetricRowView(row: row)
                        if row.id != model.rows.last?.id { Divider() }
                    }
                }

                EyelidContribution(upper: model.upperContribution, lower: model.lowerContribution)

                Text("Eye Closure Over Time")
                    .font(.headline)
                    .padding(.top, 4)
                ClosureChart(affected: model.seriesAffected, normal: model.seriesNormal)
                    .frame(height: 180)
            }
            .padding()
        }
        .navigationTitle("Eye Function")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EyeCard: View {
    let title: String
    let pct: Int
    private var color: Color { AnalysisPresentation.functionSeverity(pct).color }
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 32)
            Image(systemName: "eye").foregroundColor(color).font(.title2)
            Text("\(pct)%").font(.system(size: 30, weight: .bold)).foregroundColor(color)
            Text("Closure").font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct EyelidContribution: View {
    let upper: Int
    let lower: Int
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .trim(from: 0, to: CGFloat(upper) / 100)
                    .stroke(Color(red: 0.20, green: 0.70, blue: 0.45), lineWidth: 12)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: CGFloat(upper) / 100, to: 1)
                    .stroke(Color(red: 0.95, green: 0.60, blue: 0.15), lineWidth: 12)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("Eyelid Contribution").font(.subheadline).fontWeight(.semibold)
                Label("Upper: \(upper)%", systemImage: "circle.fill")
                    .font(.caption).foregroundColor(Color(red: 0.20, green: 0.70, blue: 0.45))
                Label("Lower: \(lower)%", systemImage: "circle.fill")
                    .font(.caption).foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.15))
            }
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct ClosureChart: View {
    let affected: [ChartPoint]
    let normal: [ChartPoint]
    var body: some View {
        Chart {
            ForEach(normal) { p in
                LineMark(x: .value("Time", p.t), y: .value("Closure", p.v))
                    .foregroundStyle(by: .value("Eye", "Normal"))
            }
            ForEach(affected) { p in
                LineMark(x: .value("Time", p.t), y: .value("Closure", p.v))
                    .foregroundStyle(by: .value("Eye", "Affected"))
            }
        }
        .chartYScale(domain: 0...1)
        .chartForegroundStyleScale([
            "Affected": Color(red: 0.95, green: 0.60, blue: 0.15),
            "Normal": Color(red: 0.20, green: 0.70, blue: 0.45)
        ])
    }
}

// MARK: - Synkinesis detail

struct SynkinesisDetailView: View {
    let model: SynkDetailModel
    private var badgeColor: Color { AnalysisPresentation.synkSeverity(model.scoreValue).severity.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    SeverityBadge(text: model.badgeText, color: badgeColor)
                }

                SynkScaleBar(value: model.scoreValue)

                VStack(spacing: 0) {
                    ForEach(model.rows) { r in
                        SynkMetricRowView(row: r)
                        if r.id != model.rows.last?.id { Divider() }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Synkinesis")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SynkMetricRowView: View {
    let row: SynkRowVM
    @State private var expanded = false
    private var info: MetricExplanation? { MetricInfo.forLabel(row.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.label).font(.body)
                if info != nil { DisclosureChevron(expanded: expanded) }
                Spacer()
                Text(String(format: "%.2f", row.value))
                    .fontWeight(.semibold).foregroundColor(row.severity.color)
                Text(row.word.uppercased())
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(row.severity.color)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if info != nil { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            }
            // Per-row severity bar (matches the prototype's colored track
            // under each synkinesis metric).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.18))
                    Capsule().fill(row.severity.color)
                        .frame(width: geo.size.width * CGFloat(min(max(row.value, 0), 1)))
                }
            }
            .frame(height: 6)

            if expanded, let info { FormulaPanel(explanation: info) }
        }
        .padding(.vertical, 10)
    }
}

private struct SynkScaleBar: View {
    let value: Double
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.70, blue: 0.45),
                                 Color(red: 0.95, green: 0.60, blue: 0.15),
                                 Color(red: 0.85, green: 0.25, blue: 0.25)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 8)
                    .clipShape(Capsule())
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.gray.opacity(0.5)))
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * CGFloat(min(max(value, 0), 1)) - 8)
                }
            }
            .frame(height: 16)
            HStack {
                Text("Low"); Spacer(); Text("Moderate"); Spacer(); Text("High")
            }
            .font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Smile detail

struct SmileDetailView: View {
    let model: SmileDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    SeverityBadge(text: model.badgeText, color: model.badgeSeverity.color)
                }

                Text("Commissure Excursion")
                    .font(.headline)
                CompareBar(leftValue: model.commissureLeft, rightValue: model.commissureRight,
                           leftLabel: "Left", rightLabel: "Right")

                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        MetricRowView(row: row)
                        if row.id != model.rows.last?.id { Divider() }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Smile Function")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Brow detail

struct BrowDetailView: View {
    let model: BrowDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    SeverityBadge(text: model.badgeText, color: model.badgeSeverity.color)
                }

                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        DetailRowView(row: row)
                        if row.id != model.rows.last?.id { Divider() }
                    }
                }

                if !model.trend.isEmpty {
                    Text("Brow Elevation Over Time")
                        .font(.headline)
                        .padding(.top, 4)
                    TrendChart(points: model.trend)
                        .frame(height: 180)
                }

                if let note = model.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Brow Function")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Midface detail

struct MidfaceDetailView: View {
    let model: MidfaceDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    SeverityBadge(text: model.badgeText, color: model.badgeSeverity.color)
                }

                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        DetailRowView(row: row)
                        if row.id != model.rows.last?.id { Divider() }
                    }
                }

                Text(model.contourCaption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Midface + Lip")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared detail components

/// Two-tone left/right comparison bar (e.g. commissure excursion).
private struct CompareBar: View {
    let leftValue: Double
    let rightValue: Double
    let leftLabel: String
    let rightLabel: String

    private let leftColor = Color(red: 0.20, green: 0.70, blue: 0.45)
    private let rightColor = Color(red: 0.95, green: 0.60, blue: 0.15)

    var body: some View {
        let total = max(leftValue + rightValue, 0.0001)
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    leftColor.frame(width: geo.size.width * CGFloat(leftValue / total))
                    rightColor
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack {
                Text("\(leftLabel) \(String(format: "%.1f", leftValue))")
                    .font(.caption).foregroundColor(leftColor)
                Spacer()
                Text("\(rightLabel) \(String(format: "%.1f", rightValue))")
                    .font(.caption).foregroundColor(rightColor)
            }
        }
    }
}

/// Renders a Brow/Midface detail row that's either a single value or a
/// two-tone affected | normal compare bar.
private struct DetailRowView: View {
    let row: DetailRow
    var body: some View {
        switch row {
        case .single(let r):  MetricRowView(row: r)
        case .compare(let r): CompareRowView(row: r)
        }
    }
}

/// Affected | normal comparison row: label + both values on top, a
/// proportional orange/green bar below (matches the prototype's per-side rows).
private struct CompareRowView: View {
    let row: CompareRowVM
    private let affColor = Color(red: 0.95, green: 0.60, blue: 0.15)   // affected
    private let normColor = Color(red: 0.20, green: 0.70, blue: 0.45)  // normal
    @State private var expanded = false
    private var info: MetricExplanation? { MetricInfo.forLabel(row.label) }

    var body: some View {
        let total = max(row.affectedValue + row.normalValue, 0.0001)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.label).font(.body)
                if info != nil { DisclosureChevron(expanded: expanded) }
                Spacer()
                Text(row.affectedText).fontWeight(.semibold).foregroundColor(affColor)
                Text("|").foregroundColor(.secondary)
                Text(row.normalText).fontWeight(.semibold).foregroundColor(normColor)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if info != nil { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    affColor.frame(width: geo.size.width * CGFloat(row.affectedValue / total))
                    normColor
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            if expanded, let info { FormulaPanel(explanation: info) }
        }
        .padding(.vertical, 10)
    }
}

/// Single-series line chart with an auto y-scale (brow elevation trend).
private struct TrendChart: View {
    let points: [ChartPoint]
    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Time", p.t), y: .value("Value", p.v))
                .foregroundStyle(brandBlue)
        }
    }
}
