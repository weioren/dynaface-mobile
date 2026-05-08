import SwiftUI

// MARK: - PatientDetailView
//
// Host view for a single patient's detail screen. V1 contains only
// the Timeline section. Future iterations (Alex's worker pipeline will
// surface annotated videos here, plus an Analysis section) attach
// alongside the timeline.
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
    let displayName: String
    let patientId: UUID

    @StateObject private var timelineService: TimelineService

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
        TimelinePage()
            .environmentObject(timelineService)
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            // Dashboard sets .navigationBarHidden(true) on the outer
            // NavigationView. On iOS 16/17 a pushed destination inherits
            // the hidden state and the back chevron disappears with it.
            // Force the bar visible here so back-navigation always works.
            .toolbar(.visible, for: .navigationBar)
    }
}
