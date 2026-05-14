import SwiftUI

// MARK: - PatientDetailView
//
// Host view for a single patient's detail screen. Hosts three
// sub-tabs at the top of the page:
//
//   1. Timeline   — clinical events log (surgery, injection, etc.)
//   2. History    — every recording uploaded for this patient
//   3. Processed  — annotated/completed videos for this patient
//
// Two entry points:
//   - Clinician taps a row in PatientListPage → push with that
//     patient's PatientCandidate.
//   - Patient opens "My care" from the Profile menu → push with their
//     own profile id and username so the same view renders for both
//     roles.
//
// TimelineService is owned here as @StateObject — scoped to this
// patient, lives for the lifetime of the screen, and is injected into
// TimelinePage / AddEditEventSheet via @EnvironmentObject so the events
// list stays consistent across child views.

struct PatientDetailView: View {
    enum SubTab: Int, Hashable, CaseIterable {
        case timeline, history, processed

        var title: String {
            switch self {
            case .timeline:  return "Timeline"
            case .history:   return "History"
            case .processed: return "Processed"
            }
        }
    }

    let displayName: String
    let patientId: UUID

    @StateObject private var timelineService: TimelineService
    @State private var selectedTab: SubTab = .timeline
    @State private var showingAddEvent = false

    init(displayName: String, patientId: UUID) {
        self.displayName = displayName
        self.patientId   = patientId
        _timelineService = StateObject(wrappedValue: TimelineService(patientId: patientId))
    }

    /// Convenience for the clinician path — pushed from
    /// PatientListPage where the row binds a PatientCandidate.
    init(patient: PatientCandidate) {
        self.init(displayName: patient.username, patientId: patient.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row: segmented picker + an inline "+" for Timeline.
            // Putting the action button HERE (not in `.toolbar`) avoids
            // composing nested .toolbar modifiers with the parent
            // NavigationLink, which was causing the back chevron and the
            // tab UI to freeze on push.
            HStack(spacing: 8) {
                Picker("View", selection: $selectedTab) {
                    ForEach(SubTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .timeline {
                    Button { showingAddEvent = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                    }
                    .accessibilityLabel("Add event")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Group {
                switch selectedTab {
                case .timeline:
                    TimelinePage(showingAddSheet: $showingAddEvent)
                        .environmentObject(timelineService)
                case .history:
                    PatientHistoryTab(patientId: patientId)
                case .processed:
                    PatientProcessedTab(patientId: patientId)
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Dashboard sets .navigationBarHidden(true) on the outer
        // NavigationView. Force the bar visible here so the
        // NavigationLink back chevron renders correctly.
        .toolbar(.visible, for: .navigationBar)
    }
}
