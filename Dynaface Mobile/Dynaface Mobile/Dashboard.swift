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
    @State private var emailBannerDismissed = false
    @State private var resendConfirmation = false

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

    // Non-blocking "verify your email" prompt shown at the top of the app while
    // the signed-in user's email is unverified. The verification mail is sent at
    // signup (AuthenticationService.createAccount); this just nudges + resends.
    private var emailVerificationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verify your email")
                    .font(.footnote).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(resendConfirmation ? "Verification email sent." : "Check your inbox to confirm your address.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            Button("Resend") {
                Task {
                    await authService.resendVerificationEmail()
                    resendConfirmation = true
                }
            }
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.white)
            Button {
                emailBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.12, green: 0.29, blue: 0.64))
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
        .safeAreaInset(edge: .top) {
            if !authService.emailVerified && !emailBannerDismissed {
                emailVerificationBanner
            }
        }
        .task {
            // Re-check verification (e.g. the user clicked the emailed link
            // out-of-app) so the banner clears itself.
            await authService.refreshEmailVerification()
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
