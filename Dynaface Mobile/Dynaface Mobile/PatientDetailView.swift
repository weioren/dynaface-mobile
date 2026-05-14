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
            Picker("View", selection: $selectedTab) {
                ForEach(SubTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

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
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Dashboard sets .navigationBarHidden(true) on the outer
        // NavigationView. On iOS 16/17 a pushed destination inherits
        // the hidden state and the back chevron disappears with it.
        // Force the bar visible here so back-navigation always works.
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            // Single toolbar owned by PatientDetailView so the
            // NavigationLink back button never gets clobbered by child
            // views adding their own `.toolbar { ... }` (the previous
            // setup did and broke back-navigation on push).
            if selectedTab == .timeline {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddEvent = true } label: {
                        Label("Add event", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                }
            }
        }
    }
}
