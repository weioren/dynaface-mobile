import Foundation
import SwiftUI
import Supabase

// MARK: - App User Model (avoid clash with Supabase.User)
struct Profile: Codable, Identifiable {
    let id: String
    let email: String
    let username: String
    let createdAt: Date?
    let symptomsLocation: String?
    let symptomsArea: String?
    let diagnosis: String?

    enum CodingKeys: String, CodingKey {
        case id, email, username
        case createdAt = "created_at"
        case symptomsLocation = "symptoms_location"
        case symptomsArea = "symptoms_area"
        case diagnosis
    }
}

// MARK: - Authentication State
enum AuthState {
    case loading
    case signedIn(Profile)
    case signedOut
    case accountCreated(String) // New state for after account creation
    case error(String)
}

// MARK: - Authentication Errors
enum AuthError: Error, LocalizedError {
    case signUpFailed
    case signInFailed
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .signUpFailed:  return "Failed to create account"
        case .signInFailed:  return "Invalid email or password"
        case .userNotFound:  return "User profile not found"
        }
    }
}

// MARK: - Survey Responses Model
struct SurveyResponses {
    let symptomsLocation: String
    let symptomsArea: String
    let diagnosis: String
}



// MARK: - Authentication View Model
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var username = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var surveyResponses: SurveyResponses?

    var isSignUpValid: Bool {
        !email.isEmpty &&
        !username.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 6
    }

    var isSignInValid: Bool {
        !email.isEmpty && !password.isEmpty
    }
}

// MARK: - Authentication Service
@MainActor
final class AuthenticationService: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var isLoading = false
    
    // Store account creation data temporarily
    private var pendingUsername: String = ""
    private var pendingPassword: String = ""

    // Supabase configuration
    private let supabase = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.projectURL)!,
        supabaseKey: SupabaseConfig.anonKey
    )

    init() {
        Task { [weak self] in
            guard let self else { return }
            await self.supabase.auth.startAutoRefresh()   // <- add await
            await self.checkCurrentSession()
        }
    }

    // MARK: - Session Management
    func checkCurrentSession() async {
        do {
            // Throws if no session found (use this instead of optional-binding user)
            let session = try await supabase.auth.session
            try await loadProfile(for: session.user.id)
        } catch {
            authState = .signedOut
        }
    }

    private func loadProfile(for userId: UUID) async throws {
        let profile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value

        authState = .signedIn(profile)
    }

    // MARK: - Create Account (Step 1)
    func createAccount(email: String, username: String, password: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            print("Starting account creation for email: \(email)")
            
            // First, check if user already exists by trying to sign in
            do {
                let existingUser = try await supabase.auth.signIn(email: email, password: password)
                print("User already exists")
                authState = .error("An account with this email already exists. Please sign in instead.")
                return
            } catch {
                // User doesn't exist or wrong password, proceed with signup
                print("User doesn't exist, proceeding with signup")
            }
            
            // Store credentials for later use in profile completion
            pendingUsername = username
            pendingPassword = password
            
            // Try creating the auth user with minimal data
            do {
                let authResponse = try await supabase.auth.signUp(
                    email: email,
                    password: password
                )
                print("Auth user created with ID: \(authResponse.user.id)")
                
                // Set state to account created, which will trigger survey flow
                authState = .accountCreated(email)
                
            } catch {
                print("Supabase signup failed, trying alternative approach: \(error)")
                
                // If Supabase signup fails, we'll handle it during the profile completion step
                // For now, just proceed to survey
                authState = .accountCreated(email)
            }

        } catch {
            print("Account creation error: \(error)")
            authState = .error("Failed to create account. Please try again.")
        }
    }
    
    // MARK: - Complete Profile (Step 2 - after survey)
    func completeProfile(email: String, surveyResponses: SurveyResponses) async {
        isLoading = true
        defer { isLoading = false }

        do {
            print("Completing profile for email: \(email)")
            
            // Try to sign in first
            do {
                let authRes = try await supabase.auth.signIn(email: email, password: pendingPassword)
                print("Sign in successful, creating profile...")
                
                try await createUserProfile(
                    userId: authRes.user.id,
                    email: email,
                    username: pendingUsername,
                    surveyResponses: surveyResponses
                )
                print("Profile creation completed, loading profile...")
                
                // Clear stored credentials
                pendingUsername = ""
                pendingPassword = ""
                
                try await loadProfile(for: authRes.user.id)
                print("Profile completion successful")
                
            } catch {
                print("Sign in failed, attempting signup during profile completion: \(error)")
                
                // If sign in fails, try signup now (in case it failed earlier)
                do {
                    let authResponse = try await supabase.auth.signUp(
                        email: email,
                        password: pendingPassword
                    )
                    print("Delayed signup successful, ID: \(authResponse.user.id)")
                    
                    // Now sign in and create profile
                    let authRes = try await supabase.auth.signIn(email: email, password: pendingPassword)
                    try await createUserProfile(
                        userId: authRes.user.id,
                        email: email,
                        username: pendingUsername,
                        surveyResponses: surveyResponses
                    )
                    
                    // Clear stored credentials
                    pendingUsername = ""
                    pendingPassword = ""
                    
                    try await loadProfile(for: authRes.user.id)
                    print("Delayed profile completion successful")
                    
                } catch {
                    print("Both signup and signin failed: \(error)")
                    authState = .error("Failed to create account. Please try again or contact support.")
                }
            }

        } catch {
            print("Profile completion error: \(error)")
            authState = .error(error.localizedDescription)
        }
    }

    // MARK: - Create User Profile
    private func createUserProfile(userId: UUID, email: String, username: String, surveyResponses: SurveyResponses) async throws {
        struct ProfileInsert: Encodable {
            let id: String
            let email: String
            let username: String
            let symptoms_location: String
            let symptoms_area: String
            let diagnosis: String
        }

        let profileData = ProfileInsert(
            id: userId.uuidString,
            email: email,
            username: username,
            symptoms_location: surveyResponses.symptomsLocation,
            symptoms_area: surveyResponses.symptomsArea,
            diagnosis: surveyResponses.diagnosis
        )

        print("Creating profile with data: \(profileData)")
        
        do {
            try await supabase
                .from("profiles")
                .insert(profileData)
                .execute()
            print("Profile created successfully")
        } catch {
            print("Failed to create profile: \(error)")
            print("Error details: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let authRes = try await supabase.auth.signIn(email: email, password: password)
            try await loadProfile(for: authRes.user.id)
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    // MARK: - Sign Out
    func signOut() async {
        do { try await supabase.auth.signOut() } catch { }
        authState = .signedOut
    }

    // MARK: - Password Reset
    func resetPassword(email: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Make sure this URL is allowed in your project's Redirect URLs
            try await supabase.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "reva://password-reset")!
            )
        } catch {
            authState = .error(error.localizedDescription)
        }
    }
}
