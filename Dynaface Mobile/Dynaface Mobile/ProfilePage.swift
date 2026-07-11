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
    @State private var showingGuide = false
    @State private var showingClinicians = false

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
                MenuRow(text: "My clinicians") { showingClinicians = true },
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
            .sheet(isPresented: $showingGuide) {
                OnboardingFlow(steps: guideSteps, onDismiss: { showingGuide = false })
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showingClinicians) {
                MyCliniciansView()
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

// MARK: - MyCliniciansView
//
// Patient-facing. Lists the clinicians this patient has connected to, lets
// them connect to a new one (via an invite code) or disconnect from an
// existing one. Backed by the patient's own `patients` rows (see InviteService).
// Disconnect is a soft-archive; the patient can reconnect later with a new code.
struct MyCliniciansView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var links: [ClinicianLink] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingConnect = false
    @State private var pendingDisconnect: ClinicianLink?

    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)

    private var patientAppUid: String? {
        if case .signedIn(let profile) = authService.authState { return profile.id }
        return nil
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle("My clinicians")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingConnect) {
                ConnectClinicianView { await load() }
                    .environmentObject(authService)
            }
            .alert("Disconnect?", isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }
            ), presenting: pendingDisconnect) { link in
                Button("Disconnect", role: .destructive) {
                    Task { await disconnect(link) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { link in
                Text("You'll no longer be connected to \(link.clinicianName). You can reconnect later with a new code.")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                Button {
                    showingConnect = true
                } label: {
                    Label("Connect with a clinician", systemImage: "plus.circle.fill")
                        .foregroundColor(accent)
                }
            }

            if links.isEmpty {
                Section {
                    Text("You're not connected with any clinician yet. Ask your clinician for an invite code, then tap \"Connect with a clinician\".")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Section("Connected") {
                    ForEach(links) { link in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.clinicianName).font(.body)
                                Text("Connected \(link.connectedAt, style: .date)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingDisconnect = link
                            } label: {
                                Text("Disconnect").font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundColor(.red)
                }
            }
        }
    }

    private func load() async {
        guard let patientAppUid else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            links = try await InviteService.myClinicians(patientAppUid: patientAppUid)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your clinicians: \(error.localizedDescription)"
        }
    }

    private func disconnect(_ link: ClinicianLink) async {
        do {
            try await InviteService.disconnect(link)
            links.removeAll { $0.id == link.id }
        } catch {
            errorMessage = "Couldn't disconnect: \(error.localizedDescription)"
        }
    }
}

// MARK: - ConnectClinicianView
//
// Patient enters an invite code to connect with the clinician who shared it.
// On success it calls `onConnected` (so the parent list refreshes) and dismisses.
struct ConnectClinicianView: View {
    let onConnected: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter the invite code your clinician gave you.")
                    .font(.subheadline).foregroundColor(.secondary)

                TextField("Invite code", text: $code)
                    .font(.system(.title2, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundColor(.red)
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        if isWorking { ProgressView().tint(.white) }
                        Text("Connect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(trimmedCode.isEmpty ? Color.gray : accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isWorking || trimmedCode.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Connect with a clinician")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await InviteService.redeem(code: trimmedCode)
            await onConnected()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview
#Preview {
    ProfilePage()
}
