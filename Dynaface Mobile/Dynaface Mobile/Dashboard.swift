import SwiftUI

struct Dashboard: View {
    @EnvironmentObject var authService: AuthenticationService

    // Single source of truth for the patient list (clinician-only feature).
    // Created here so it persists for the lifetime of the Dashboard regardless
    // of which tab is currently selected.
    @StateObject private var patientService = PatientService()

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

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                ExercisesPage()
                    .tabItem {
                        Image(systemName: "dumbbell.fill")
                        Text("Exercise")
                    }
                    .tag(0)

                ExerciseHistoryPage()
                    .tabItem {
                        Image(systemName: "video.fill")
                        Text("History")
                    }
                    .tag(1)

                UploadVideoPage()
                    .tabItem {
                        Image(systemName: "square.and.arrow.up")
                        Text("Upload")
                    }
                    .tag(2)

                // [Phase 6] Clinician-only "Patients" tab. Only attached
                // when accountType == .clinician so patients see the
                // same 4-tab layout as before.
                if isClinician {
                    PatientListPage()
                        .tabItem {
                            Image(systemName: "person.3.fill")
                            Text("Patients")
                        }
                        .tag(3)
                }

                ProfilePage()
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(isClinician ? 4 : 3)
            }
            .environmentObject(patientService)
            .onReceive(NotificationCenter.default.publisher(for: .assessmentCompleted)) { _ in
                withAnimation { selectedTab = 1 }
            }
            // [Gap 4] ProfilePage 的 "My patients" 行 deep-link 进来。
            // isClinician guard 防止 patient 模式下意外触发(他们不该有这个 tab)。
            .onReceive(NotificationCenter.default.publisher(for: .navigateToPatientsTab)) { _ in
                guard isClinician else { return }
                withAnimation { selectedTab = 3 }
            }
            .navigationBarHidden(true)
        }
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
