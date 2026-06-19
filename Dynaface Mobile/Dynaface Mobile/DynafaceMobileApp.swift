import SwiftUI
import FirebaseCore

@main
struct DynafaceMobileApp: App {
    @StateObject private var authService = AuthenticationService()

    init() {
        FirebaseApp.configure()
    }

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

    var body: some View {
        Group {
            if skipAuth {
                Dashboard()
            } else {
                switch authService.authState {
                case .loading:
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)

                case .signedIn:
                    Dashboard()

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
}


// MARK: - Notification Extension
extension Notification.Name {
    static let recordingCompleted = Notification.Name("recordingCompleted")
}
