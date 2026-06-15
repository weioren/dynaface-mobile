import SwiftUI
import Charts

// MARK: - Analysis views (v1: Home + Eye + Synkinesis)
//
// All data arrives via AnalysisService (mock-backed in v1). Views render the
// view models produced by AnalysisPresentation; they hold no metric logic.

private let brandBlue = Color(red: 0.12, green: 0.29, blue: 0.64)

// MARK: - Home

struct AnalysisHomeView: View {
    @ObservedObject var service: AnalysisService
    @EnvironmentObject private var authService: AuthenticationService
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
            // Switch to the live Supabase source (env objects available here),
            // then load. Falls back to whatever provider was injected.
            service.useSupabase(authService.supabaseClient, attribution: attributionService)
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
                        default:
                            DomainBarRow(bar: bar, navigable: false)
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

private struct MetricRowView: View {
    let row: MetricRowVM
    var body: some View {
        HStack {
            Text(row.label).font(.body)
            Spacer()
            Text(row.affected)
                .fontWeight(.semibold)
                .foregroundColor(row.severity?.color ?? .primary)
            if let normal = row.normal {
                Text("|").foregroundColor(.secondary)
                Text(normal).foregroundColor(.secondary)
            }
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
                        HStack {
                            Text(r.label).font(.body)
                            Spacer()
                            Text(String(format: "%.2f", r.value))
                                .fontWeight(.semibold).foregroundColor(r.severity.color)
                            Text(r.word.uppercased())
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundColor(r.severity.color)
                        }
                        .padding(.vertical, 10)
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
