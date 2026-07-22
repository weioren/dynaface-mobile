import SwiftUI

struct SignIn: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false

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

                        // Forgot Password opens its own screen rather than
                        // reusing the sign-in email field.
                        Button("Forgot Password?") {
                            authService.authError = nil
                            showingForgotPassword = true
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
        .onReceive(authService.$authError) { error in
            // The reset screen shows its own inline error, so don't also queue an
            // alert behind the sheet.
            if let error, !showingForgotPassword {
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
        .sheet(isPresented: $showingForgotPassword) {
            NavigationStack { ForgotPasswordView() }
        }
    }

    private func signIn() {
        Task {
            await authService.signIn(email: authViewModel.email, password: authViewModel.password)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - ForgotPasswordView
//
// Its own screen, opened from Sign In, so the reset flow no longer piggybacks on
// the sign-in email field. Two states: enter the address, then a confirmation
// laid out exactly like SignupVerificationGate so both emailed-link flows look
// the same.
struct ForgotPasswordView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    // Reused purely for its email validation.
    @StateObject private var authViewModel = AuthViewModel()
    @State private var sent = false
    @State private var resendConfirmation = false

    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            if sent {
                sentView(w: w, h: h)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.white)
            } else {
                formView(w: w, h: h)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.white)
            }
        }
        // The confirmation is a full-bleed screen like the signup gate, so the
        // navigation chrome only belongs on the form step.
        .navigationTitle(sent ? "" : "Reset password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(sent ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(authService.isLoading)
            }
        }
    }

    // MARK: Step 1, enter the address

    private func formView(w: CGFloat, h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18 * h) {
            Text("Enter the email you signed up with. We'll send you a link to choose a new password.")
                .font(.system(size: 16 * w))
                .foregroundColor(.gray)
                .padding(.top, 24 * h)

            VStack(alignment: .leading, spacing: 8 * h) {
                Text("Email")
                    .font(.system(size: 14 * w, weight: .medium))
                    .foregroundColor(.black)

                TextField("Enter your email", text: $authViewModel.email)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.emailAddress)
            }

            if let error = authService.authError {
                Text(error)
                    .font(.system(size: 12 * w))
                    .foregroundColor(.red)
            }

            Button(action: { Task { await send() } }) {
                Group {
                    if authService.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send reset link")
                            .font(.system(size: 18 * w, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48 * h)
                .background(authViewModel.isEmailValid ? accent : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(24 * w)
            }
            .disabled(!authViewModel.isEmailValid || authService.isLoading)

            Spacer()
        }
        .padding(.horizontal, 24 * w)
    }

    // MARK: Step 2, confirmation mirroring SignupVerificationGate

    private func sentView(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 18 * h) {
            Spacer()

            Image(systemName: "envelope.badge")
                .font(.system(size: 60 * w))
                .foregroundColor(accent)

            Text("Check your email")
                .font(.system(size: 24 * w, weight: .bold))
                .foregroundColor(.black)

            Text("If an account exists for \(authViewModel.email), we sent a password reset link. Open it to choose a new password, and check your spam folder.")
                .font(.system(size: 16 * w))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40 * w)

            if resendConfirmation {
                Text("Reset email sent.")
                    .font(.system(size: 13 * w))
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Text("Back to sign in")
                    .font(.system(size: 18 * w, weight: .semibold))
                    .frame(width: 282 * w, height: 48 * h)
                    .background(accent)
                    .foregroundColor(.white)
                    .cornerRadius(24 * w)
            }

            Button("Resend email") {
                Task {
                    if await authService.resetPassword(email: authViewModel.email) {
                        resendConfirmation = true
                    }
                }
            }
            .font(.system(size: 14 * w, weight: .medium))
            .foregroundColor(accent)
            .disabled(authService.isLoading)
            .padding(.bottom, 40 * h)
        }
    }

    private func send() async {
        authService.authError = nil
        if await authService.resetPassword(email: authViewModel.email) {
            sent = true
        }
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
