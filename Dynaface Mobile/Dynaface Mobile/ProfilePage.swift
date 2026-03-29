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

                    // Username display
                    if case .signedIn(let profile) = authService.authState {
                        Text(profile.username)
                            .font(.system(size: 20 * widthScale, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.vertical, 20 * heightScale)
                .padding(.horizontal, 30 * widthScale)
                .frame(maxWidth: .infinity)
                .background(Color(red: 30/255, green: 75/255, blue: 162/255).opacity(0.18))
                .cornerRadius(17 * widthScale)

                // Menu items
                VStack(spacing: 20 * heightScale) {
                    ProfileMenuItem(text: "Edit profile", widthScale: widthScale, heightScale: heightScale) {
                        showingEditProfile = true
                    }

                    ProfileMenuItem(text: "My progress", widthScale: widthScale, heightScale: heightScale) {
                        // My progress action
                    }

                    ProfileMenuItem(text: "My past evaluations", widthScale: widthScale, heightScale: heightScale) {
                        // My past evaluations action
                    }

                    ProfileMenuItem(text: "Upcoming appointments", widthScale: widthScale, heightScale: heightScale) {
                        // Upcoming appointments action
                    }

                    ProfileMenuItem(text: "FAQ", widthScale: widthScale, heightScale: heightScale) {
                        // FAQ action
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

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            NavigationView {
                ScrollView {
                    VStack(spacing: 20 * heightScale) {
                        // Form fields
                        VStack(spacing: 15 * heightScale) {
                            FormField(title: "Email", text: $email, widthScale: widthScale, isDisabled: true)
                            FormField(title: "Username", text: $username, widthScale: widthScale, isDisabled: true)
                            FormField(title: "Symptoms Location", text: $symptomsLocation, widthScale: widthScale, isDisabled: true)
                            FormField(title: "Symptoms Area", text: $symptomsArea, widthScale: widthScale, isDisabled: true)
                            FormField(title: "Diagnosis", text: $diagnosis, widthScale: widthScale, isDisabled: true)
                        }

                        // Save button
                        Button(action: {
                            // Save profile changes
                            Task {
                                await saveProfile()
                            }
                        }) {
                            Text("Save Changes")
                                .font(.system(size: 18 * widthScale))
                                .foregroundColor(.white)
                                .frame(height: 44 * heightScale)
                                .frame(maxWidth: .infinity)
                                .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                                .cornerRadius(49 * widthScale)
                                .shadow(
                                    color: Color.black.opacity(0.25),
                                    radius: 4 * widthScale,
                                    x: 0, y: 4 * heightScale
                                )
                        }
                        .disabled(isLoading)
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
        // Note: For now this is a placeholder. In a real app, you'd want to
        // update the profile data in Supabase and refresh the auth state
        isLoading = true

        // Simulate API call
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        isLoading = false
        dismiss()
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
