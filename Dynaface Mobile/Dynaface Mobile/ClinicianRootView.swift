import SwiftUI

// MARK: - ClinicianRootView
//
// Root view for accounts with `accountType == .clinician`. Two top-level
// tabs per Oren's UX/UI diagram (2026-04-26): a patient list (with search +
// add) and a clinician-flavored editable profile.
//
// Owns a single `PatientService` instance shared with children via
// `@EnvironmentObject`.

struct ClinicianRootView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var patientService = PatientService()
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                PatientListPage()
                    .tabItem {
                        Image(systemName: "person.3.fill")
                        Text("Patients")
                    }
                    .tag(0)

                ClinicianMyProfile()
                    .tabItem {
                        Image(systemName: "person.crop.circle.fill")
                        Text("Profile")
                    }
                    .tag(1)
            }
            .navigationBarHidden(true)
        }
        .environmentObject(patientService)
        .task {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard
            case .signedIn(let profile) = authService.authState,
            let clinicianId = UUID(uuidString: profile.id)
        else { return }
        await patientService.loadPatients(for: clinicianId)
    }
}

// MARK: - Preview
#Preview {
    ClinicianRootView()
        .environmentObject(AuthenticationService())
}
