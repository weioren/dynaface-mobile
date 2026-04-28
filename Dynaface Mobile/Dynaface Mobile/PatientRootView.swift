import SwiftUI

// MARK: - PatientRootView
//
// Root view for accounts with `accountType == .patient`. Two top-level
// tabs per Oren's UX/UI diagram (2026-04-26): "My care" — which lands
// directly inside the patient detail view scoped to their own data — and
// the patient-flavored editable profile.
//
// Patient accounts don't have a patient list (they only ever see their
// own data). For V1, the "My care" tab pushes a `PatientDetailPlaceholder`
// constructed from the signed-in profile. Alex's PR will replace it with
// the real `PatientDetailView`.

struct PatientRootView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                myCareTab
                    .tabItem {
                        Image(systemName: "heart.text.square.fill")
                        Text("My care")
                    }
                    .tag(0)

                PatientMyProfile()
                    .tabItem {
                        Image(systemName: "person.crop.circle.fill")
                        Text("Profile")
                    }
                    .tag(1)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var myCareTab: some View {
        if case .signedIn(let profile) = authService.authState {
            // Synthesize a Patient value so we can reuse PatientDetailPlaceholder.
            // Alex's PatientDetailView will likely take a generic identifier
            // and fetch its own scope, so this synthetic value is a V1 stop-gap.
            let id = UUID(uuidString: profile.id) ?? UUID()
            let synthetic = Patient(
                id: id,
                name: profile.username,
                clinicianId: id,
                createdAt: profile.createdAt ?? Date()
            )
            NavigationStack {
                PatientDetailPlaceholder(patient: synthetic)
            }
        } else {
            Text("Not signed in.")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
#Preview {
    PatientRootView()
        .environmentObject(AuthenticationService())
}
