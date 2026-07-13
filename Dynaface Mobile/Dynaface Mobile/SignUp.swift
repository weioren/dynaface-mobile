import SwiftUI

// MARK: - CreateAccountView
struct CreateAccountView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var authViewModel = AuthViewModel()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss

    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    @ViewBuilder
    private func passwordRule(_ text: String, _ met: Bool, _ w: CGFloat) -> some View {
        HStack(spacing: 6 * w) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13 * w))
                .foregroundColor(met ? .green : .gray)
            Text(text)
                .font(.system(size: 12 * w))
                .foregroundColor(met ? .black : .gray)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            ZStack {
                Color.white.ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                    }

                ScrollView {
                    VStack(spacing: 30 * h) {
                        Text("Create Account")
                            .font(.system(size: 28 * w, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.top, 60 * h)

                        Text("Join Dynaface Mobile to start your rehabilitation journey")
                            .font(.system(size: 16 * w))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        Spacer()
                            .frame(height: 40 * h)

                        // Email
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

                            // Disallowed domains show a red prompt; otherwise nudge
                            // toward Gmail, whose Firebase verification email reliably
                            // arrives (other providers often block or spam-filter it).
                            if !authViewModel.email.isEmpty && !authViewModel.isEmailAllowed {
                                Text("Please use a Gmail address to sign up.")
                                    .font(.system(size: 12 * w))
                                    .foregroundColor(.red)
                            } else if !authViewModel.email.lowercased().hasSuffix("@gmail.com") {
                                Text("We recommend a Gmail address so the verification email reaches you.")
                                    .font(.system(size: 12 * w))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 20 * w)

                        // Username
                        VStack(alignment: .leading, spacing: 8 * h) {
                            Text("Username")
                                .font(.system(size: 14 * w, weight: .medium))
                                .foregroundColor(.black)

                            TextField("Choose a username", text: $authViewModel.username)
                                .textFieldStyle(CustomTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(.username)
                        }
                        .padding(.horizontal, 20 * w)

                        // Account Type — clinician vs patient. Drives which
                        // survey flow runs after account creation. Persisted
                        // to profiles.account_type by AuthenticationService.
                        VStack(alignment: .leading, spacing: 8 * h) {
                            Text("I am a…")
                                .font(.system(size: 14 * w, weight: .medium))
                                .foregroundColor(.black)

                            Picker("Account type", selection: $authViewModel.accountType) {
                                ForEach(AccountType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(authViewModel.accountType.subtitle)
                                .font(.system(size: 12 * w))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 20 * w)

                        // Password
                        VStack(alignment: .leading, spacing: 8 * h) {
                            Text("Password")
                                .font(.system(size: 14 * w, weight: .medium))
                                .foregroundColor(.black)

                            SecureField("Create a password", text: $authViewModel.password)
                                .textFieldStyle(CustomTextFieldStyle())
                                .textContentType(.newPassword)

                            // Live password requirements — explains the greyed-out
                            // Create Account button.
                            if !authViewModel.password.isEmpty {
                                VStack(alignment: .leading, spacing: 4 * h) {
                                    passwordRule("At least 8 characters", authViewModel.hasMinLength, w)
                                    passwordRule("An uppercase letter", authViewModel.hasUpper, w)
                                    passwordRule("A lowercase letter", authViewModel.hasLower, w)
                                    passwordRule("A number", authViewModel.hasDigit, w)
                                    passwordRule("A special character", authViewModel.hasSpecial, w)
                                }
                                .padding(.top, 4 * h)
                            }
                        }
                        .padding(.horizontal, 20 * w)

                        // Confirm Password
                        VStack(alignment: .leading, spacing: 8 * h) {
                            Text("Confirm Password")
                                .font(.system(size: 14 * w, weight: .medium))
                                .foregroundColor(.black)

                            SecureField("Confirm your password", text: $authViewModel.confirmPassword)
                                .textFieldStyle(CustomTextFieldStyle())
                                .textContentType(.newPassword)
                        }
                        .padding(.horizontal, 20 * w)

                        // Create Account Button
                        Button(action: createAccount) {
                            ZStack {
                                if authService.isLoading {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Create Account")
                                        .font(.system(size: 18 * w, weight: .semibold))
                                }
                            }
                            .frame(width: 282 * w, height: 48 * h)
                        }
                        .frame(width: 282 * w, height: 48 * h)
                        .background(authViewModel.isSignUpValid ? Color(red: 0.12, green: 0.29, blue: 0.64) : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(24 * w)
                        .disabled(!authViewModel.isSignUpValid || authService.isLoading)

                        // Sign In Link
                        HStack {
                            Text("Already have an account?")
                                .font(.system(size: 14 * w))
                                .foregroundColor(.gray)

                            Button("Sign In") {
                                dismiss()
                            }
                            .font(.system(size: 14 * w, weight: .medium))
                            .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                        }
                        .padding(.top, 20 * h)

                        Spacer()
                            .frame(height: 60 * h)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .alert("Error", isPresented: $showingAlert) { Button("OK") { authService.authError = nil } } message: { Text(alertMessage) }
        .onReceive(authService.$authError) { error in
            if let error {
                alertMessage = error
                showingAlert = true
            }
        }
        .onReceive(authService.$authState) { state in
            if case .accountCreated = state {
                dismiss() // Close the sheet, app will show survey flow
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
    }

    private func createAccount() {
        Task {
            await authService.createAccount(
                email: authViewModel.email,
                username: authViewModel.username,
                password: authViewModel.password,
                accountType: authViewModel.accountType
            )
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - SignupVerificationGate
//
// Hard email-verification gate shown right after account creation (state
// .accountCreated). The verification email is already sent at signup; this
// screen blocks the rest of onboarding until the address is verified. It polls
// `emailVerified` so "Continue" enables shortly after the user taps the emailed
// link and returns; on Continue it hands off to the normal SurveyFlow.
struct SignupVerificationGate: View {
    let email: String
    let accountType: AccountType

    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)

    @EnvironmentObject var authService: AuthenticationService
    @State private var proceed = false
    @State private var resendConfirmation = false

    var body: some View {
        if proceed {
            SurveyFlow(email: email, accountType: accountType)
        } else {
            gate
        }
    }

    private var gate: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            VStack(spacing: 18 * h) {
                HStack {
                    Button("Cancel") { Task { await authService.cancelPendingSignup() } }
                        .font(.system(size: 16 * w))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 24 * w)
                .padding(.top, 14 * h)

                Spacer()

                Image(systemName: "envelope.badge")
                    .font(.system(size: 60 * w))
                    .foregroundColor(accent)

                Text("Verify your email")
                    .font(.system(size: 24 * w, weight: .bold))
                    .foregroundColor(.black)

                Text("We sent a verification link to \(email). Open it, then tap Continue.")
                    .font(.system(size: 16 * w))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40 * w)

                if authService.emailVerified {
                    Label("Email verified", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14 * w, weight: .semibold))
                        .foregroundColor(.green)
                } else if resendConfirmation {
                    Text("Verification email sent.")
                        .font(.system(size: 13 * w))
                        .foregroundColor(.gray)
                }

                Spacer()

                Button(action: { proceed = true }) {
                    Text("Continue")
                        .font(.system(size: 18 * w, weight: .semibold))
                        .frame(width: 282 * w, height: 48 * h)
                        .background(authService.emailVerified ? accent : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(24 * w)
                }
                .disabled(!authService.emailVerified)

                Button("Resend email") {
                    Task {
                        await authService.resendVerificationEmail()
                        resendConfirmation = true
                    }
                }
                .font(.system(size: 14 * w, weight: .medium))
                .foregroundColor(accent)
                .padding(.bottom, 40 * h)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
        .task {
            // Poll until verified so Continue enables shortly after the user
            // taps the emailed link and returns to the app.
            while !Task.isCancelled && !authService.emailVerified {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await authService.refreshEmailVerification()
            }
        }
    }
}

// MARK: - SurveyFlow (post-signup guide)
//
// Shown right after email verification. Both roles go straight to the
// role-specific OnboardingFlow — the symptom survey was removed. OnboardingFlow's
// `completeProfile` passes `nil` for SurveyResponses since the symptom fields are
// empty, and the auth service writes blank symptom columns; patients can fill
// these in later from Edit Profile.
struct SurveyFlow: View {
    let email: String
    let accountType: AccountType

    var body: some View {
        switch accountType {
        case .patient:
            OnboardingFlow(
                steps: patientOnboardingSteps,
                email: email,
                symptomsLocation: "",
                symptomsArea: "",
                diagnosis: ""
            )
        case .clinician:
            OnboardingFlow(
                steps: clinicianOnboardingSteps,
                email: email,
                symptomsLocation: "",
                symptomsArea: "",
                diagnosis: ""
            )
        }
    }
}

// MARK: - Onboarding walkthrough (post-signup)
//
// Replaces the old single "Congrats" finish screen. Walks each role through one
// complete usage flow — a swipeable card per feature — and finishes setup via
// completeProfile() on "Get started" (or "Skip"). Patient passes its survey
// answers; clinician passes nil (empty symptom strings).
struct OnboardingStep: Identifiable {
    let id = UUID()
    let icon: String          // SF Symbol name
    let title: String
    let detail: String
}

let clinicianOnboardingSteps: [OnboardingStep] = [
    OnboardingStep(icon: "person.badge.plus", title: "Add your patients",
                   detail: "Build and manage your patient list in one place."),
    OnboardingStep(icon: "video.fill", title: "Record assessments",
                   detail: "Capture guided facial exercises at each visit."),
    OnboardingStep(icon: "calendar", title: "Track the timeline",
                   detail: "Every assessment lands on the patient's timeline."),
    OnboardingStep(icon: "chart.bar.xaxis", title: "Review the analysis",
                   detail: "See a 5-domain facial-function breakdown for each visit."),
    OnboardingStep(icon: "arrow.left.arrow.right", title: "Compare over time",
                   detail: "Compare two assessments to track recovery."),
]

let patientOnboardingSteps: [OnboardingStep] = [
    OnboardingStep(icon: "video.fill", title: "Record your assessment",
                   detail: "Follow the guided facial exercises in a few minutes."),
    OnboardingStep(icon: "checkmark.seal", title: "Processed for you",
                   detail: "Your recording is analyzed automatically in the cloud."),
    OnboardingStep(icon: "calendar", title: "Track your timeline",
                   detail: "See every assessment over time in one place."),
    OnboardingStep(icon: "chart.bar.xaxis", title: "See your analysis",
                   detail: "Get your facial-function scores after each recording."),
    OnboardingStep(icon: "heart.text.square", title: "Your care team",
                   detail: "Your clinician reviews your progress and guides your care."),
]

struct OnboardingFlow: View {
    let steps: [OnboardingStep]
    // Signup context — left empty in review mode (replaying from Profile).
    var email: String = ""
    var symptomsLocation: String = ""
    var symptomsArea: String = ""
    var diagnosis: String = ""
    // When set, finishing (or "Close") dismisses instead of completing the
    // profile — used to replay the guide from the Profile screen.
    var onDismiss: (() -> Void)? = nil

    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)
    private var isReview: Bool { onDismiss != nil }

    @EnvironmentObject var authService: AuthenticationService
    @State private var page = 0
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(isReview ? "Close" : "Skip") { finish() }
                        .font(.system(size: 16 * w))
                        .foregroundColor(.gray)
                        .disabled(!isReview && authService.isLoading)
                }
                .padding(.horizontal, 24 * w)
                .padding(.top, 14 * h)

                TabView(selection: $page) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        cardView(step, w: w, h: h).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(action: advance) {
                    if !isReview && authService.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(page == steps.count - 1 ? (isReview ? "Done" : "Get started") : "Next")
                            .font(.system(size: 18 * w, weight: .semibold))
                    }
                }
                .frame(width: 282 * w, height: 48 * h)
                .background(accent)
                .cornerRadius(24 * w)
                .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)
                .foregroundColor(.white)
                .disabled(!isReview && authService.isLoading)
                .padding(.bottom, 40 * h)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
        .alert("Error", isPresented: $showingAlert) { Button("OK") { authService.authError = nil } } message: { Text(alertMessage) }
        .onReceive(authService.$authError) { error in
            if let error {
                alertMessage = error
                showingAlert = true
            }
        }
    }

    private func cardView(_ step: OnboardingStep, w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 22 * h) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 132 * w, height: 132 * w)
                Image(systemName: step.icon)
                    .font(.system(size: 54 * w))
                    .foregroundColor(accent)
            }
            Text(step.title)
                .font(.system(size: 24 * w, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
            Text(step.detail)
                .font(.system(size: 16 * w))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40 * w)
            Spacer()
            Spacer()
        }
        .padding()
    }

    private func advance() {
        if page < steps.count - 1 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    /// Review mode dismisses; signup mode writes the profile.
    private func finish() {
        if let onDismiss {
            onDismiss()
        } else {
            completeProfile()
        }
    }

    private func completeProfile() {
        // Patient passes its survey answers; clinician arrives with empty
        // strings → pass nil so blank symptom columns are written.
        let isPatientSurvey = !(symptomsLocation.isEmpty && symptomsArea.isEmpty && diagnosis.isEmpty)
        let responses: SurveyResponses? = isPatientSurvey
            ? SurveyResponses(symptomsLocation: symptomsLocation, symptomsArea: symptomsArea, diagnosis: diagnosis)
            : nil
        Task {
            await authService.completeProfile(email: email, surveyResponses: responses)
        }
    }
}

// MARK: - Previews
#Preview {
    OnboardingFlow(steps: patientOnboardingSteps).environmentObject(AuthenticationService())
}
