import SwiftUI
import PhotosUI

// MARK: - ProfilePage
struct ProfilePage: View {
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    @EnvironmentObject var authService: AuthenticationService
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showingEditProfile = false
    @State private var showingDeleteAccount = false
    @State private var showingGuide = false

    // MARK: - Menu data model
    //
    // Role-conditional menu rows. Using `text` as the id (instead of UUID())
    // keeps each row's identity stable across renders so ForEach doesn't
    // rebuild every cell on each pass.
    private struct MenuRow: Identifiable {
        var id: String { text }
        let text: String
        let action: () -> Void
    }

    /// Returns the menu rows for the given account type. Sign-out is rendered
    /// separately (red styling) below this list, not as a row here.
    private func menuItems(for accountType: AccountType) -> [MenuRow] {
        let edit     = MenuRow(text: "Edit profile") { showingEditProfile = true }
        let guide    = MenuRow(text: "Guide") { showingGuide = true }
        let upcoming = MenuRow(text: "Upcoming appointments") { /* stub — button only */ }

        switch accountType {
        case .patient:
            return [
                edit,
                guide,
            ]
        case .clinician:
            return [
                edit,
                MenuRow(text: "My patients") {
                    // Dashboard is the same instance the user is already in — the
                    // UserDefaults("selectedTab") path only fires on Dashboard's
                    // onAppear, so use NotificationCenter to switch tabs live.
                    NotificationCenter.default.post(name: .navigateToPatientsTab, object: nil)
                },
                upcoming,
                guide,
            ]
        }
    }

    /// Steps for the replayable "How it works" guide, chosen by role.
    private var guideSteps: [OnboardingStep] {
        if case .signedIn(let profile) = authService.authState,
           profile.accountType == .clinician {
            return clinicianOnboardingSteps
        }
        return patientOnboardingSteps
    }

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            ScrollView {
                VStack(spacing: 30 * heightScale) {
                // Profile header section
                VStack(spacing: 20 * heightScale) {
                    // Profile picture with photo picker
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100 * widthScale, height: 100 * heightScale)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .foregroundColor(.white)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black, lineWidth: 1)
                                    )
                                    .frame(width: 100 * widthScale, height: 100 * heightScale)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 20 * widthScale))
                                    )
                            }
                        }
                    }
                    .onChange(of: selectedPhoto) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                profileImage = image
                            }
                        }
                    }

                    // Username + role display
                    if case .signedIn(let profile) = authService.authState {
                        Text(profile.username)
                            .font(.system(size: 20 * widthScale, weight: .bold))
                            .foregroundColor(.black)

                        Text(profile.accountType.displayName)
                            .font(.system(size: 14 * widthScale, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 20 * heightScale)
                .padding(.horizontal, 30 * widthScale)
                .frame(maxWidth: .infinity)
                .background(Color(red: 30/255, green: 75/255, blue: 162/255).opacity(0.18))
                .cornerRadius(17 * widthScale)

                // Menu items — rendered by role; Sign out is a separate sibling below.
                VStack(spacing: 20 * heightScale) {
                    if case .signedIn(let profile) = authService.authState {
                        ForEach(menuItems(for: profile.accountType)) { item in
                            ProfileMenuItem(
                                text: item.text,
                                widthScale: widthScale,
                                heightScale: heightScale,
                                action: item.action
                            )
                        }
                    }

                    // Sign out button
                    Button(action: {
                        Task {
                            await authService.signOut()
                        }
                    }) {
                        HStack {
                            Text("Sign out")
                                .font(.system(size: 18 * widthScale))
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "arrow.right.square")
                                .foregroundColor(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10 * widthScale)
                    }

                    // Delete account — permanent, so it sits below Sign out and
                    // opens a sheet that requires typing DELETE and the password.
                    Button(action: { showingDeleteAccount = true }) {
                        HStack {
                            Text("Delete account")
                                .font(.system(size: 18 * widthScale))
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.10))
                        .cornerRadius(10 * widthScale)
                    }
                }

            }
            .padding(.horizontal, 30 * widthScale)
            .padding(.top, 40 * heightScale)
            .padding(.bottom, 40 * heightScale)
            .frame(maxWidth: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .sheet(isPresented: $showingEditProfile) {
                EditProfilePage()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showingDeleteAccount) {
                DeleteAccountSheet()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showingGuide) {
                OnboardingFlow(steps: guideSteps, onDismiss: { showingGuide = false })
                    .environmentObject(authService)
            }
        }
    }
}

// Helper view for profile menu items
struct ProfileMenuItem: View {
    let text: String
    let widthScale: CGFloat
    let heightScale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 18 * widthScale))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10 * widthScale)
        }
    }
}

// MARK: - Edit Profile Page
struct EditProfilePage: View {
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var username: String = ""
    @State private var symptomsLocation: String = ""
    @State private var symptomsArea: String = ""
    @State private var diagnosis: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    /// Client-side username validation — non-empty + length ≤ 32 (no global
    /// uniqueness constraint at the DB layer for now).
    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isUsernameValid: Bool {
        !trimmedUsername.isEmpty && trimmedUsername.count <= 32
    }
    /// Clinicians don't see the symptom / diagnosis fields.
    private var isClinician: Bool {
        if case .signedIn(let profile) = authService.authState {
            return profile.accountType == .clinician
        }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            NavigationView {
                ScrollView {
                    VStack(spacing: 20 * heightScale) {
                        // Form fields — Email is always disabled. Username is
                        // editable for both roles. Symptom/diagnosis fields are
                        // visible and editable only for patients.
                        VStack(spacing: 15 * heightScale) {
                            VStack(alignment: .leading, spacing: 4) {
                                FormField(title: "Email", text: $email, widthScale: widthScale, isDisabled: true)
                                Text("Contact support to change email.")
                                    .font(.system(size: 12 * widthScale))
                                    .foregroundColor(.gray)
                            }
                            FormField(title: "Username", text: $username, widthScale: widthScale, isDisabled: false)
                            if !isClinician {
                                FormField(title: "Symptoms Location", text: $symptomsLocation, widthScale: widthScale, isDisabled: false)
                                FormField(title: "Symptoms Area", text: $symptomsArea, widthScale: widthScale, isDisabled: false)
                                FormField(title: "Diagnosis", text: $diagnosis, widthScale: widthScale, isDisabled: false)
                            }
                        }

                        // Save button — shows a spinner while loading; greys out and disabled when invalid.
                        Button(action: {
                            Task { await saveProfile() }
                        }) {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Save Changes")
                                        .font(.system(size: 18 * widthScale))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(height: 44 * heightScale)
                            .frame(maxWidth: .infinity)
                            .background(
                                isUsernameValid
                                    ? Color(red: 0.12, green: 0.29, blue: 0.64)
                                    : Color.gray
                            )
                            .cornerRadius(49 * widthScale)
                            .shadow(
                                color: Color.black.opacity(0.25),
                                radius: 4 * widthScale,
                                x: 0, y: 4 * heightScale
                            )
                        }
                        .disabled(isLoading || !isUsernameValid)
                        .padding(.top, 20 * heightScale)

                        Spacer()
                    }
                    .padding(.horizontal, 30 * widthScale)
                    .padding(.top, 20 * heightScale)
                }
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            dismiss()
                        }
                    }
                }
                .alert(
                    "Couldn't save",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    ),
                    presenting: errorMessage
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { msg in
                    Text(msg)
                }
            }
        }
        .onAppear {
            loadProfileData()
        }
    }

    private func loadProfileData() {
        if case .signedIn(let profile) = authService.authState {
            email = profile.email
            username = profile.username
            symptomsLocation = profile.symptomsLocation ?? ""
            symptomsArea = profile.symptomsArea ?? ""
            diagnosis = profile.diagnosis ?? ""
        }
    }

    private func saveProfile() async {
        guard isUsernameValid else { return }
        isLoading = true
        defer { isLoading = false }

        // Build a role-scoped patch — clinicians update only username; patients
        // also send symptom + diagnosis. Empty strings get written through, so
        // clearing a field is supported.
        var patch = AuthenticationService.ProfilePatch(username: trimmedUsername)
        if !isClinician {
            patch.symptoms_location = symptomsLocation
            patch.symptoms_area     = symptomsArea
            patch.diagnosis         = diagnosis
        }

        do {
            try await authService.updateProfile(patch: patch)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Helper view for form fields
struct FormField: View {
    let title: String
    @Binding var text: String
    let widthScale: CGFloat
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16 * widthScale, weight: .medium))
                .foregroundColor(.black)

            TextField(title, text: $text)
                .font(.system(size: 16 * widthScale))
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10 * widthScale)
                .disabled(isDisabled)
                .foregroundColor(isDisabled ? .gray : .black)
        }
    }
}

// MARK: - DeleteAccountSheet
//
// Permanent account deletion. Two-factor by design: the user types DELETE to
// confirm intent, then enters their password, which `AuthenticationService
// .deleteAccount` uses to re-authenticate. The `delete_account` Cloud Function
// separately requires a verified email, then erases every Firestore document
// and Storage blob for the account before removing the Auth user.
//
// On success the service signs out, so RootContainer swaps to the login screen
// and this sheet goes away with the rest of the signed-in UI.
struct DeleteAccountSheet: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var confirmation = ""
    @State private var password = ""

    private let requiredPhrase = "DELETE"

    private var canDelete: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).uppercased() == requiredPhrase
            && !password.isEmpty
            && !authService.isLoading
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text("Deleting your account permanently removes your profile, every assessment you recorded, and all of their videos, analyses, and results. You cannot recover them.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type DELETE to confirm")
                            .font(.footnote).foregroundColor(.secondary)
                        TextField("DELETE", text: $confirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm your password")
                            .font(.footnote).foregroundColor(.secondary)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    if let error = authService.authError {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }

                    Button {
                        Task { await deleteAccount() }
                    } label: {
                        HStack(spacing: 8) {
                            if authService.isLoading { ProgressView().tint(.white) }
                            Text("Delete my account")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canDelete ? Color.red : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canDelete)

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        authService.authError = nil
                        dismiss()
                    }
                    .disabled(authService.isLoading)
                }
            }
        }
    }

    private func deleteAccount() async {
        // On success the service signs out and the whole signed-in tree is
        // replaced, so there is nothing to dismiss here.
        _ = await authService.deleteAccount(password: password)
    }
}

// MARK: - Preview
#Preview {
    ProfilePage()
}
