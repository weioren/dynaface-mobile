import SwiftUI

// MARK: - ClinicianMyProfile
//
// Clinician-flavored profile page. V1 displays read-only fields (username
// and email) plus a sign-out button. The "Editable" requirement from
// Oren's UX/UI diagram is recognized but defers actual write paths until
// `AuthenticationService.updateProfile(...)` exists — currently the auth
// service only inserts on first profile creation, no update path. Adding
// that update method is on the Phase 7 follow-up; for V1 we surface the
// fields that already exist and gate the textfields with disabled state
// so the layout doesn't change when editing comes online.

struct ClinicianMyProfile: View {
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
                        labeledRow("Role",  value: AccountType.clinician.displayName)
                    }

                    Section("Practice details") {
                        Text("Title, department, and contact details will be editable here once profile updates are wired up.")
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
    ClinicianMyProfile()
        .environmentObject(AuthenticationService())
}
