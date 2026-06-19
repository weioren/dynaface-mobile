import SwiftUI

// MARK: - CompareAssessmentSetupView
//
// Presented as a sheet from TimelinePage once the user has picked two
// Clinical Assessment day-groups. Lets them choose a single exercise
// that exists in both assessments and toggle two display options before
// pushing the (currently blank) results screen.
//
// Inputs are snapshots taken at sheet-launch time, so further changes
// to TimelineService while this sheet is open don't mutate the picker
// list mid-interaction.

struct CompareAssessmentSetupView: View {
    let patientName: String
    let firstDay: Date
    let firstEvents: [TimelineEvent]
    let secondDay: Date
    let secondEvents: [TimelineEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedExercise: String?
    @State private var showAnnotations: Bool = false
    @State private var keyImageOnly: Bool = false
    @State private var navigateToResults: Bool = false

    private let navy = Color(red: 0.12, green: 0.29, blue: 0.64)

    /// GMT-anchored medium date — matches the formatter the timeline's
    /// assessment-group card uses, so "Comparing X and Y" reads back
    /// the same date strings the user just tapped on.
    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    /// Exercises shared between the two assessments, ordered by the
    /// canonical `allExercises` sequence so the picker stays stable
    /// regardless of how Supabase happened to return the rows. Any
    /// shared titles that aren't in `allExercises` (e.g. legacy notes)
    /// are appended alphabetically at the end rather than dropped.
    private var sharedExercises: [String] {
        let firstTitles  = Set(firstEvents.map(\.notes))
        let secondTitles = Set(secondEvents.map(\.notes))
        let intersection = firstTitles.intersection(secondTitles)
        let canonical = allExercises.map(\.title)
        var ordered = canonical.filter { intersection.contains($0) }
        let extras = intersection.subtracting(ordered).sorted()
        ordered.append(contentsOf: extras)
        return ordered
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    exerciseSection
                    optionsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                compareButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $navigateToResults) {
                CompareAssessmentResultsView(
                    patientName: patientName,
                    exerciseTitle: selectedExercise ?? "",
                    firstDay: firstDay,
                    firstJobId: firstEvents.first { $0.notes == selectedExercise }?.jobId,
                    secondDay: secondDay,
                    secondJobId: secondEvents.first { $0.notes == selectedExercise }?.jobId,
                    showAnnotations: showAnnotations,
                    keyImageOnly: keyImageOnly
                )
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text(patientName)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text("Comparing \(Self.headerDateFormatter.string(from: firstDay)) and \(Self.headerDateFormatter.string(from: secondDay))")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which exercise would you like to compare")
                .font(.headline)
            if sharedExercises.isEmpty {
                Text("These two assessments have no exercises in common.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sharedExercises.enumerated()), id: \.element) { idx, title in
                        Button {
                            selectedExercise = title
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedExercise == title ? "largecircle.fill.circle" : "circle")
                                    .font(.title3)
                                    .foregroundColor(selectedExercise == title ? navy : Color.gray.opacity(0.6))
                                Text(title)
                                    .font(.body).foregroundColor(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if idx != sharedExercises.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    private var optionsSection: some View {
        VStack(spacing: 0) {
            Toggle("Show Dynaface annotations", isOn: $showAnnotations)
                .padding(.vertical, 8)
            Divider()
            Toggle("Key image only", isOn: $keyImageOnly)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private var compareButton: some View {
        let enabled = selectedExercise != nil
        return Button {
            navigateToResults = true
        } label: {
            Text("Compare")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(enabled ? navy : Color.gray.opacity(0.4))
                .cornerRadius(12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}
