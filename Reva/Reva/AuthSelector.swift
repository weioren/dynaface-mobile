import SwiftUI

struct AuthSelector: View {
    @EnvironmentObject var authService: AuthenticationService  // <-- use shared instance
    @State private var showingSignIn = false
    @State private var showingSignUp = false

    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 40 * heightScale) {
                    Text("Reva")
                        .font(.system(size: 48 * widthScale, weight: .bold))
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                        .padding(.top, 100 * heightScale)

                    Text("Your facial rehabilitation companion")
                        .font(.system(size: 18 * widthScale))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    Spacer()

                    Button(action: { showingSignIn = true }) {
                        Text("Sign In")
                            .font(.system(size: 18 * widthScale, weight: .semibold))
                            .frame(width: 282 * widthScale, height: 48 * heightScale)
                            .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                            .foregroundColor(.white)
                            .cornerRadius(24 * widthScale)
                    }

                    Button(action: { showingSignUp = true }) {
                        Text("Create Account")
                            .font(.system(size: 18 * widthScale, weight: .semibold))
                            .frame(width: 282 * widthScale, height: 48 * heightScale)
                            .background(Color.white)
                            .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                            .cornerRadius(24 * widthScale)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24 * widthScale)
                                    .stroke(Color(red: 0.12, green: 0.29, blue: 0.64), lineWidth: 2)
                            )
                    }

                    Spacer()
                }
                .padding(.horizontal, 20 * widthScale)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack { SignIn() }          // inherits envObject
        }
        .sheet(isPresented: $showingSignUp) {
            NavigationStack { CreateAccountView() }
        }
    }
}

// MARK: - Preview
#Preview {
    AuthSelector()
        .environmentObject(AuthenticationService())
}
