import SwiftUI

struct Dashboard: View {
    @EnvironmentObject var authService: AuthenticationService

    // Single source of truth for the patient list (clinician-only feature).
    // Created here so it persists for the lifetime of the Dashboard regardless
    // of which tab is currently selected.
    @StateObject private var patientService = PatientService()

    // Cross-cutting service for the job_patient_attributions junction
    // table. Lives at Dashboard scope so both the post-upload attribution
    // sheet (PracticePage) and the patient-scoped History/Processed tabs
    // (PatientDetailView) share one instance.
    @StateObject private var attributionService = JobAttributionService()

    @State private var selectedTab = 0

    /// Whether the signed-in user is a clinician. Drives the optional
    /// "Patients" tab. Falls back to `false` (no extra tab) for any state
    /// where there isn't a signed-in profile yet (loading / signedOut / error).
    private var isClinician: Bool {
        if case .signedIn(let profile) = authService.authState {
            return profile.accountType == .clinician
        }
        return false
    }

    /// The signed-in patient's own profile id (nil for clinician / signed out).
    private var patientId: UUID? {
        if case .signedIn(let profile) = authService.authState,
           profile.accountType == .patient {
            return UUID(uuidString: profile.id)
        }
        return nil
    }

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // Exercise is the leftmost tab for both roles — clinicians
                // need to start a recording fast without first picking a
                // patient (attribution happens in the post-upload sheet).
                ExercisesPage()
                    .tabItem {
                        Image(systemName: "dumbbell.fill")
                        Text("Exercise")
                    }
                    .tag(0)

                // [Phase 8] Clinicians see Patient List in tag 1; patients
                // see History/Processed instead. Each patient's per-patient
                // History/Processed lives inside PatientDetailView for the
                // clinician, so the dashboard doesn't need those tabs.
                if isClinician {
                    PatientListPage()
                        .tabItem {
                            Image(systemName: "person.3.fill")
                            Text("Patients")
                        }
                        .tag(1)
                } else {
                    if let patientId {
                        PatientTimelineTab(patientId: patientId)
                            .tabItem {
                                Image(systemName: "calendar")
                                Text("Timeline")
                            }
                            .tag(1)
                    }

                    PatientVideosTab()
                        .tabItem {
                            Image(systemName: "video.fill")
                            Text("Videos")
                        }
                        .tag(2)
                }

                ProfilePage()
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(isClinician ? 2 : 3)
            }
            .environmentObject(patientService)
            .environmentObject(attributionService)
            .onReceive(NotificationCenter.default.publisher(for: .assessmentCompleted)) { _ in
                // Patient → History tab (their freshly-uploaded clip).
                // Clinician → Patients tab (where they'd browse the patient
                // they just attributed the upload to). Both happen to be
                // tag 1 under the current layout.
                withAnimation { selectedTab = 1 }
            }
            // [Gap 4] ProfilePage's "My patients" row deep-links here.
            // isClinician guard prevents accidental fires in patient mode
            // (they don't have this tab).
            .onReceive(NotificationCenter.default.publisher(for: .navigateToPatientsTab)) { _ in
                guard isClinician else { return }
                withAnimation { selectedTab = 1 }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Check if we should navigate to a specific tab
            if let tabToSelect = UserDefaults.standard.object(forKey: "selectedTab") as? Int {
                selectedTab = tabToSelect
                UserDefaults.standard.removeObject(forKey: "selectedTab")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    Dashboard()
        .environmentObject(AuthenticationService())
}
