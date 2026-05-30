import SwiftUI
import PhotosUI

// MARK: - ProfilePage
struct ProfilePage: View {
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    @EnvironmentObject var authService: AuthenticationService
    @AppStorage("videoUploadsEnabled") private var videoUploadsEnabled = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showingEditProfile = false
    @State private var navigateToMyCare = false

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
        let faq      = MenuRow(text: "FAQ") { /* TODO: FAQ */ }
        let upcoming = MenuRow(text: "Upcoming appointments") { /* stub — button only */ }

        switch accountType {
        case .patient:
            return [
                edit,
                // "My care" pushes the patient's own PatientDetailView
                // (timeline section in V1). The actual navigation is wired
                // through a hidden NavigationLink below the menu VStack —
                // we just flip the flag here.
                MenuRow(text: "My care") { navigateToMyCare = true },
                MenuRow(text: "My progress")         { /* TODO */ },
                MenuRow(text: "My past evaluations") { /* TODO */ },
                upcoming,
                faq,
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
                faq,
            ]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cloud video upload")
                                .font(.system(size: 18 * widthScale))
                                .foregroundColor(.black)
                            Text(videoUploadsEnabled ? "Processed videos will be uploaded to Supabase." : "Uploads are disabled. Videos stay local only.")
                                .font(.system(size: 12 * widthScale))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: $videoUploadsEnabled)
                            .labelsHidden()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10 * widthScale)

                    if case .signedIn(let profile) = authService.authState {
                        ForEach(menuItems(for: profile.accountType)) { item in
                            ProfileMenuItem(
                                text: item.text,
                                widthScale: widthScale,
                                heightScale: heightScale,
                                action: item.action
                            )
                        }

                        // Hidden NavigationLink: triggered when patient taps
                        // "My care" (which sets navigateToMyCare = true).
                        // Pushes the patient's own PatientDetailView so they
                        // see their own timeline. Clinicians never reach this
                        // path (no "My care" row in their menu).
                        if profile.accountType == .patient,
                           let myUUID = UUID(uuidString: profile.id) {
                            NavigationLink(isActive: $navigateToMyCare) {
                                PatientDetailView(
                                    displayName: profile.username,
                                    patientId: myUUID
                                )
                            } label: {
                                EmptyView()
                            }
                            .hidden()
                            .frame(width: 0, height: 0)
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
                }

                Spacer()
            }
            .padding(.horizontal, 30 * widthScale)
            .padding(.top, 40 * heightScale)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .sheet(isPresented: $showingEditProfile) {
                EditProfilePage()
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

// MARK: - Preview
#Preview {
    ProfilePage()
}
