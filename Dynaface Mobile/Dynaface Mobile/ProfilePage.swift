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

    // MARK: - Menu data model
    //
    // 角色相关菜单项。id 用 text 而不是 UUID(),保证每次 render 同一项 ID 稳定,
    // ForEach 不会把所有行当新元素重建。
    private struct MenuRow: Identifiable {
        var id: String { text }
        let text: String
        let action: () -> Void
    }

    /// 按角色返回菜单项。Sign out 单独渲染(红色样式),不在这里。
    private func menuItems(for accountType: AccountType) -> [MenuRow] {
        let edit     = MenuRow(text: "Edit profile") { showingEditProfile = true }
        let faq      = MenuRow(text: "FAQ") { /* TODO: FAQ */ }
        let upcoming = MenuRow(text: "Upcoming appointments") { /* stub — button only */ }

        switch accountType {
        case .patient:
            return [
                edit,
                MenuRow(text: "My progress")         { /* TODO */ },
                MenuRow(text: "My past evaluations") { /* TODO */ },
                upcoming,
                faq,
            ]
        case .clinician:
            return [
                edit,
                MenuRow(text: "My patients") {
                    // Dashboard 是同一个实例 — UserDefaults 路径只走 onAppear,
                    // 这里走 NotificationCenter 走通。
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

                // Menu items — 按角色渲染,Sign out 单独
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

    /// Username 客户端校验 — 非空 + 长度 ≤ 32(无全局唯一约束)。
    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isUsernameValid: Bool {
        !trimmedUsername.isEmpty && trimmedUsername.count <= 32
    }
    /// Clinician 看不到 symptom / diagnosis 字段。
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
                        // Form fields — Email 永远 disabled,Username 双角色都可改,
                        // Symptom/Diagnosis 仅 patient 可见且可改。
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

                        // Save button — isLoading 时显示 spinner; 校验失败时变灰禁用
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

        // Build a role-scoped patch — clinician 只更新 username,patient 把
        // symptom + diagnosis 一起带上(空串也会写过去,清空字段是可行的)。
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
