import SwiftUI

@main
struct RevaApp: App {
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

    var body: some View {
        Group {
            switch authService.authState {
            case .loading:
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)

            case .signedIn:
                Dashboard() // your existing screen

            case .signedOut:
                AuthSelector()
                
            case .accountCreated(let email):
                SurveyFlow(email: email)

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


// MARK: - Notification Extension
extension Notification.Name {
    static let recordingCompleted = Notification.Name("recordingCompleted")
}
