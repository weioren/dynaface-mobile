import SwiftUI

// MARK: - PatientMyProfile
//
// Patient-flavored profile page. Surfaces the symptom answers captured in
// the SurveyFlow during signup (paralysis side, affected area, diagnosis)
// alongside username and email. Like ClinicianMyProfile, fields are
// read-only in V1 — actual editing comes online once
// `AuthenticationService.updateProfile(...)` lands.

struct PatientMyProfile: View {
    @EnvironmentObject var authService: AuthenticationService

    private var profile: Profile? {
        if case .signedIn(let p) = authService.authState { return p }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let profile {
                    Section("Account") {
                        labeledRow("Name",  value: profile.username)
                        labeledRow("Email", value: profile.email)
                        labeledRow("Role",  value: AccountType.patient.displayName)
                    }

                    Section("Clinical context") {
                        labeledRow("Affected side", value: profile.symptomsLocation ?? "—")
                        labeledRow("Affected area", value: profile.symptomsArea ?? "—")
                        labeledRow("Diagnosis",     value: profile.diagnosis ?? "—")
                    }

                    Section {
                        Text("These answers came from the survey during signup. Editing them will be available once profile updates are wired up.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Section {
                        Button(role: .destructive) {
                            Task { await authService.signOut() }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Sign out").fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                } else {
                    Text("Not signed in.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Profile")
        }
    }

    // MARK: - Helpers

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Preview
#Preview {
    PatientMyProfile()
        .environmentObject(AuthenticationService())
}
