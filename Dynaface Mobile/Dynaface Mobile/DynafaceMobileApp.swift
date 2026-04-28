import SwiftUI

@main
struct DynafaceMobileApp: App {
    @StateObject private var authService = AuthenticationService()

    var body: some Scene {
        WindowGroup {
            RootContainer()
                .environmentObject(authService) // share ONE instance
                .preferredColorScheme(.light)
                .task {
                    await authService.checkCurrentSession()
                }
        }
    }
}

struct RootContainer: View {
    @EnvironmentObject var authService: AuthenticationService

    // [Phase 1] DEV ONLY: set to true to skip login and go straight to Dashboard
    private let skipAuth = false

    // [Phase 6] DEV ONLY: when non-nil, bypasses auth state and renders the
    // matching root view directly. Useful for previewing Clinician / Patient
    // UI without going through real auth + Supabase. Leave as `nil` for
    // production builds.
    private let mockAccountType: AccountType? = nil

    var body: some View {
        Group {
            if let mockAccountType {
                rootView(for: mockAccountType)
            } else if skipAuth {
                Dashboard()
            } else {
                switch authService.authState {
                case .loading:
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)

                case .signedIn(let profile):
                    rootView(for: profile.accountType)

                case .signedOut:
                    AuthSelector()

                case .accountCreated(let email, let accountType):
                    SurveyFlow(email: email, accountType: accountType)

                case .error(let message):
                    VStack(spacing: 12) {
                        Text("Error").font(.title).foregroundColor(.red)
                        Text(message).foregroundColor(.gray)
                        Button("Try Again") {
                            Task { await authService.checkCurrentSession() }
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                }
            }
        }
    }

    /// Picks the right root container per account type. Patient accounts
    /// without an `account_type` column on their legacy profile fall through
    /// to `.patient` (the migration default), which is the current de-facto
    /// behavior.
    @ViewBuilder
    private func rootView(for accountType: AccountType) -> some View {
        switch accountType {
        case .clinician:
            ClinicianRootView()
        case .patient:
            PatientRootView()
        }
    }
}


// MARK: - Notification Extension
extension Notification.Name {
    static let recordingCompleted = Notification.Name("recordingCompleted")
}
