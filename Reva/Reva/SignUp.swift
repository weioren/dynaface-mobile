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

                        Text("Join Reva to start your rehabilitation journey")
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

                        // Password
                        VStack(alignment: .leading, spacing: 8 * h) {
                            Text("Password")
                                .font(.system(size: 14 * w, weight: .medium))
                                .foregroundColor(.black)

                            SecureField("Create a password", text: $authViewModel.password)
                                .textFieldStyle(CustomTextFieldStyle())
                                .textContentType(.newPassword)
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
        .alert("Error", isPresented: $showingAlert) { Button("OK") { } } message: { Text(alertMessage) }
        .onReceive(authService.$authState) { state in
            switch state {
            case .error(let message):
                alertMessage = message
                showingAlert = true
            case .accountCreated:
                dismiss() // Close the sheet, app will show survey flow
            default:
                break
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
                password: authViewModel.password
            )
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - SurveyFlow
struct SurveyFlow: View {
    let email: String
    
    var body: some View {
        NavigationStack {
            FirstPage(email: email)
        }
    }
}

// MARK: - RootView (kept for compatibility)
struct RootView: View {
    var body: some View {
        NavigationStack {
            FirstPage(email: "")
        }
    }
}

// MARK: - FirstPage
struct FirstPage: View {
    let email: String
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            ZStack {
                Text("Welcome to Reva")
                    .font(Font.custom("Inter", size: 26 * widthScale))
                    .bold()
                    .foregroundColor(.black)
                    .offset(x: 0, y: -275 * heightScale)

                Text("Just 3 quick questions to get started!")
                    .font(Font.custom("Inter", size: 24 * widthScale))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: geometry.size.width - (40 * widthScale))
                    .offset(x: -1.5 * widthScale, y: -150 * heightScale)

                NavigationLink(destination: SecondPage(email: email)) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                            .frame(width: 297 * widthScale, height: 60 * heightScale)
                            .cornerRadius(49 * widthScale)
                            .shadow(color: Color.black.opacity(0.25), radius: 4 * widthScale, x: 0, y: 4 * heightScale)
                        Text("Take Survey")
                            .font(Font.custom("Inter", size: 24 * widthScale))
                            .foregroundColor(.white)
                    }
                }
                .offset(x: -0.5 * widthScale, y: -23.5 * heightScale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
    }
}

// MARK: - SecondPage
struct SecondPage: View {
    let email: String
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            ZStack {
                VStack(spacing: 16 * heightScale) {
                    Rectangle()
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                        .frame(width: 349 * widthScale, height: 20 * heightScale)
                        .cornerRadius(49 * widthScale)
                        .offset(x: -1.5 * widthScale, y: -52 * heightScale)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * widthScale, x: 0, y: 4 * heightScale)

                    Rectangle()
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.65))
                        .frame(width: 100 * widthScale, height: 20 * widthScale)
                        .cornerRadius(49 * widthScale)
                        .offset(x: -125 * widthScale, y: -88 * heightScale)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * widthScale, x: 0, y: 4 * heightScale)

                    Text("Where do you experience your symptoms?")
                        .font(Font.custom("Inter", size: 24 * widthScale))
                        .foregroundColor(.black)
                        .padding(.bottom, 50 * heightScale)

                    NavigationLink(destination: ThirdPage(email: email, symptomsLocation: "Left Side")) { choice("Left Side", widthScale, heightScale) }
                    NavigationLink(destination: ThirdPage(email: email, symptomsLocation: "Right Side")) { choice("Right Side", widthScale, heightScale) }
                    NavigationLink(destination: ThirdPage(email: email, symptomsLocation: "Both Sides")) { choice("Both Sides", widthScale, heightScale) }
                    NavigationLink(destination: ThirdPage(email: email, symptomsLocation: "Unsure")) { choice("Unsure", widthScale, heightScale) }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
    }

    private func choice(_ text: String, _ w: CGFloat, _ h: CGFloat) -> some View {
        Text(text)
            .frame(width: 235 * w, height: 80 * h)
            .background(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
            .foregroundColor(.black)
            .cornerRadius(15 * w)
    }
}

// MARK: - ThirdPage
struct ThirdPage: View {
    let email: String
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    let symptomsLocation: String

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            ZStack {
                VStack(spacing: 16 * h) {
                    Rectangle()
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                        .frame(width: 349 * w, height: 20 * h)
                        .cornerRadius(49 * w)
                        .offset(x: -1.5 * w, y: -52 * h)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)

                    Rectangle()
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.65))
                        .frame(width: 200 * w, height: 20 * h)
                        .cornerRadius(49 * w)
                        .offset(x: -75 * w, y: -88 * h)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)

                    Text("Which part of the face do you experience your symptoms?")
                        .font(Font.custom("Inter", size: 24 * w))
                        .foregroundColor(.black)
                        .padding(.bottom, 50 * h)

                    NavigationLink(destination: FourthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: "Upper Face")) { choice("Upper Face", w, h) }
                    NavigationLink(destination: FourthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: "Lower Face")) { choice("Lower Face", w, h) }
                    NavigationLink(destination: FourthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: "Both")) { choice("Both", w, h) }
                    NavigationLink(destination: FourthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: "Unsure")) { choice("Unsure", w, h) }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
    }

    private func choice(_ text: String, _ w: CGFloat, _ h: CGFloat) -> some View {
        Text(text)
            .frame(width: 235 * w, height: 80 * h)
            .background(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
            .foregroundColor(.black)
            .cornerRadius(15 * w)
    }
}

// MARK: - FourthPage
struct FourthPage: View {
    let email: String
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    let symptomsLocation: String
    let symptomsArea: String

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            ZStack {
                VStack(spacing: 16 * h) {
                    Rectangle()
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                        .frame(width: 349 * w, height: 20 * h)
                        .cornerRadius(49 * w)
                        .offset(x: -1.5 * w, y: -52 * h)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)

                    Rectangle()
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.65))
                        .frame(width: 300 * w, height: 20 * h)
                        .cornerRadius(49 * w)
                        .offset(x: -28 * w, y: -88 * h)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)

                    Text("Have you ever received an official diagnosis?")
                        .font(Font.custom("Inter", size: 24 * w))
                        .foregroundColor(.black)
                        .padding(.bottom, 50 * h)

                    NavigationLink(destination: FifthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: symptomsArea, diagnosis: "Bell's Palsy")) { choice("Bell's Palsy", w, h) }
                    NavigationLink(destination: FifthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: symptomsArea, diagnosis: "From Injury")) { choice("From Injury", w, h) }
                    NavigationLink(destination: FifthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: symptomsArea, diagnosis: "From Surgery")) { choice("From Surgery", w, h) }
                    NavigationLink(destination: FifthPage(email: email, symptomsLocation: symptomsLocation, symptomsArea: symptomsArea, diagnosis: "Unsure")) { choice("Unsure", w, h) }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
    }

    private func choice(_ text: String, _ w: CGFloat, _ h: CGFloat) -> some View {
        Text(text)
            .frame(width: 235 * w, height: 80 * h)
            .background(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
            .foregroundColor(.black)
            .cornerRadius(15 * w)
    }
}

// MARK: - FifthPage
struct FifthPage: View {
    let email: String
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    let symptomsLocation: String
    let symptomsArea: String
    let diagnosis: String
    
    @EnvironmentObject var authService: AuthenticationService
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / baseWidth
            let h = geometry.size.height / baseHeight

            ZStack {
                Text("Congrats! Here's how Reva can help you:")
                    .font(Font.custom("Inter", size: 24 * w))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .offset(x: -1.5 * w, y: -217.5 * h)
                    .frame(maxWidth: geometry.size.width - (40 * w))

                VStack(spacing: 40 * h) {
                    featureRow(iconName: "Icon_SignUp_Guided Tutorials", text: "Guided tutorials", w: w, h: h, iconSize: 60)
                    featureRow(iconName: "Icon_SignUp_Feedback", text: "Feedback from physicians", w: w, h: h, iconSize: 55)
                    featureRow(iconName: "Icon_SignUp_Routine", text: "Develop a practice routine", w: w, h: h, iconSize: 70)
                }
                .padding()
                .offset(x: 20 * w, y: 20 * h)

                Button(action: completeProfile) {
                    if authService.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Complete Setup")
                            .font(.system(size: 18 * w))
                    }
                }
                .frame(width: 282 * w, height: 48 * h)
                .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                .cornerRadius(24 * w)
                .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)
                .foregroundColor(.white)
                .disabled(authService.isLoading)
                .offset(y: 275 * h)

                Group {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 349 * w, height: 20 * h)
                        .background(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                        .cornerRadius(49 * w)
                        .offset(x: -1.5 * w, y: -322 * h)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)

                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 350 * w, height: 20 * h)
                        .background(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.65))
                        .cornerRadius(49 * w)
                        .offset(x: 0 * w, y: -322 * h)
                        .shadow(color: Color.black.opacity(0.25), radius: 4 * w, x: 0, y: 4 * h)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.white)
        }
        .alert("Error", isPresented: $showingAlert) { Button("OK") { } } message: { Text(alertMessage) }
        .onReceive(authService.$authState) { state in
            if case .error(let message) = state {
                alertMessage = message
                showingAlert = true
            }
        }
    }
    
    private func completeProfile() {
        Task {
            await authService.completeProfile(
                email: email,
                surveyResponses: SurveyResponses(
                    symptomsLocation: symptomsLocation,
                    symptomsArea: symptomsArea,
                    diagnosis: diagnosis
                )
            )
        }
    }

    private func featureRow(iconName: String, text: String, w: CGFloat, h: CGFloat, iconSize: CGFloat) -> some View {
        HStack {
            Rectangle()
                .frame(width: 85 * w, height: 85 * h)
                .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                .cornerRadius(15 * w)
                .overlay(
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize * w, height: iconSize * h)
                )

            Text(text)
                .foregroundColor(.black)
                .font(.system(size: 18 * w))
                .offset(x: 15 * w)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - Previews
#Preview {
    RootView().environmentObject(AuthenticationService())
}
