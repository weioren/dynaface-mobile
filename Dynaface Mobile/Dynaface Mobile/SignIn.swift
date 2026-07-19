import SwiftUI

struct SignIn: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSignUp = false
    @State private var showingResetSent = false

    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            ZStack {
                Color.white.ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                    }

                ScrollView {
                    VStack(spacing: 30 * heightScale) {
                        Text("Welcome Back")
                            .font(.system(size: 28 * widthScale, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.top, 60 * heightScale)

                        Text("Sign in to continue your progress")
                            .font(.system(size: 16 * widthScale))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        Spacer()
                            .frame(height: 60 * heightScale)

                        // Email
                        VStack(alignment: .leading, spacing: 8 * heightScale) {
                            Text("Email")
                                .font(.system(size: 14 * widthScale, weight: .medium))
                                .foregroundColor(.black)

                            TextField("Enter your email", text: $authViewModel.email)
                                .textFieldStyle(CustomTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(.emailAddress)
                        }
                        .padding(.horizontal, 20 * widthScale)

                        // Password
                        VStack(alignment: .leading, spacing: 8 * heightScale) {
                            Text("Password")
                                .font(.system(size: 14 * widthScale, weight: .medium))
                                .foregroundColor(.black)

                            SecureField("Enter your password", text: $authViewModel.password)
                                .textFieldStyle(CustomTextFieldStyle())
                                .textContentType(.password)
                        }
                        .padding(.horizontal, 20 * widthScale)

                        // Forgot Password
                        Button("Forgot Password?") {
                            Task { await sendPasswordReset() }
                        }
                        .font(.system(size: 14 * widthScale))
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 20 * widthScale)

                        // Sign In
                        Button(action: signIn) {
                            ZStack {
                                if authService.isLoading {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Sign In")
                                        .font(.system(size: 18 * widthScale, weight: .semibold))
                                }
                            }
                            .frame(width: 282 * widthScale, height: 48 * heightScale)
                        }
                        .frame(width: 282 * widthScale, height: 48 * heightScale)
                        .background(authViewModel.isSignInValid ? Color(red: 0.12, green: 0.29, blue: 0.64) : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(24 * widthScale)
                        .disabled(!authViewModel.isSignInValid || authService.isLoading)

                        // Sign Up Link
                        HStack {
                            Text("Don't have an account?")
                                .font(.system(size: 14 * widthScale))
                                .foregroundColor(.gray)

                            Button("Sign Up") {
                                showingSignUp = true
                            }
                            .font(.system(size: 14 * widthScale, weight: .medium))
                            .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                        }
                        .padding(.top, 20 * heightScale)

                        Spacer()
                            .frame(height: 60 * heightScale)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .alert("Error", isPresented: $showingAlert) { Button("OK") { authService.authError = nil } } message: { Text(alertMessage) }
        .alert("Check your email", isPresented: $showingResetSent) {
            Button("OK") {}
        } message: {
            Text("If an account exists for \(authViewModel.email), a password reset link has been sent. Check your inbox and spam.")
        }
        .onReceive(authService.$authError) { error in
            if let error {
                alertMessage = error
                showingAlert = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingSignUp) {
            NavigationStack { CreateAccountView() }
        }
    }

    private func signIn() {
        Task {
            await authService.signIn(email: authViewModel.email, password: authViewModel.password)
        }
    }

    /// Sends the reset link for whatever is in the Email field. Guards an empty
    /// or malformed address up front so Firebase isn't called with junk, then
    /// confirms on success (failures surface through the shared error alert).
    private func sendPasswordReset() async {
        hideKeyboard()
        guard authViewModel.isEmailValid else {
            alertMessage = "Enter your email address above, then tap Forgot Password."
            showingAlert = true
            return
        }
        if await authService.resetPassword(email: authViewModel.email) {
            showingResetSent = true
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Custom Text Field Style (unchanged)
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white)
            .cornerRadius(15)
            .shadow(radius: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.black.opacity(0.27), lineWidth: 0.5)
            )
    }
}

// MARK: - Preview
#Preview {
    NavigationStack { SignIn() }
        .environmentObject(AuthenticationService())
}
