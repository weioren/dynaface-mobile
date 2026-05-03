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
    let accountType: AccountType

    enum CodingKeys: String, CodingKey {
        case id, email, username
        case createdAt = "created_at"
        case symptomsLocation = "symptoms_location"
        case symptomsArea = "symptoms_area"
        case diagnosis
        case accountType = "account_type"
    }

    /// Defensive decoder. Falls back to `.patient` if `account_type` is
    /// missing from the response (shouldn't happen post-migration since
    /// the column has a NOT NULL DEFAULT, but cheap insurance against
    /// any Supabase API quirks).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id               = try c.decode(String.self, forKey: .id)
        self.email            = try c.decode(String.self, forKey: .email)
        self.username         = try c.decode(String.self, forKey: .username)
        self.createdAt        = try c.decodeIfPresent(Date.self,   forKey: .createdAt)
        self.symptomsLocation = try c.decodeIfPresent(String.self, forKey: .symptomsLocation)
        self.symptomsArea     = try c.decodeIfPresent(String.self, forKey: .symptomsArea)
        self.diagnosis        = try c.decodeIfPresent(String.self, forKey: .diagnosis)
        self.accountType      = (try? c.decode(AccountType.self, forKey: .accountType)) ?? .patient
    }
}

// MARK: - Authentication State
enum AuthState {
    case loading
    case signedIn(Profile)
    case signedOut
    /// Phase 1 of signup completed (Supabase auth user created). The view
    /// layer reads `accountType` to decide whether to show the patient
    /// symptom survey or jump straight to the clinician welcome page.
    case accountCreated(email: String, accountType: AccountType)
    case error(String)
}

// MARK: - Authentication Errors
enum AuthError: Error, LocalizedError {
    case signUpFailed
    case signInFailed
    case userNotFound
    case usernameAlreadyTaken

    var errorDescription: String? {
        switch self {
        case .signUpFailed:          return "Failed to create account"
        case .signInFailed:          return "Invalid email or password"
        case .userNotFound:          return "User profile not found"
        case .usernameAlreadyTaken:  return "Username has been registered"
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
    @Published var accountType: AccountType = .clinician
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
    
    // Store account creation data temporarily across the two-step signup flow
    private var pendingUsername: String = ""
    private var pendingPassword: String = ""
    private var pendingAccountType: AccountType = .patient

    // Supabase configuration
    private let supabase = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.projectURL)!,
        supabaseKey: SupabaseConfig.anonKey
    )

    var supabaseClient: SupabaseClient {
        supabase
    }

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

    // MARK: - Username Availability
    //
    // Pre-check via SECURITY DEFINER RPC `is_username_available(name)`.
    // Anon-callable so we can use it during signup before any auth user
    // exists. Lowercased + trimmed match server-side.
    //
    // Fails open (returns true) on RPC error so a transient network blip
    // doesn't block legitimate signups. Race conditions still possible
    // since profiles.username has no UNIQUE constraint — acceptable for MVP.
    func isUsernameAvailable(_ username: String) async -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let available: Bool = try await supabase
                .rpc("is_username_available", params: ["name": trimmed])
                .execute()
                .value
            return available
        } catch {
            print("isUsernameAvailable RPC failed: \(error)")
            return true   // fail open
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

    // MARK: - Update Profile
    //
    // Partial PATCH against `profiles`. JSONEncoder skips nil keys so
    // callers only populate the columns they want to overwrite. After
    // the network call we re-run loadProfile so authState carries the
    // fresh values everywhere (ProfilePage username header, etc.).
    //
    // Relies on the existing RLS policy "Enable update for users based
    // on user_id" (cmd=UPDATE, auth.uid() = id).
    struct ProfilePatch: Encodable {
        var username: String?
        var symptoms_location: String?
        var symptoms_area: String?
        var diagnosis: String?
    }

    func updateProfile(patch: ProfilePatch) async throws {
        guard case .signedIn(let current) = authState else {
            throw AuthError.userNotFound
        }
        // Don't crash on a malformed id — bail with the same error the
        // rest of the codebase uses for "no live profile".
        guard let uuid = UUID(uuidString: current.id) else {
            throw AuthError.userNotFound
        }

        // [Gap 5b] If username is being changed, pre-check availability
        // before issuing the UPDATE so the user gets a friendly error.
        if let newUsername = patch.username {
            let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() != current.username.lowercased() {
                let available = await isUsernameAvailable(trimmed)
                if !available {
                    throw AuthError.usernameAlreadyTaken
                }
            }
        }

        try await supabase
            .from("profiles")
            .update(patch)
            .eq("id", value: uuid.uuidString)
            .execute()

        // Re-fetch so authState reflects the updated row.
        try await loadProfile(for: uuid)
    }

    // MARK: - Create Account (Step 1)
    func createAccount(email: String, username: String, password: String, accountType: AccountType) async {
        isLoading = true
        defer { isLoading = false }

        do {
            print("Starting account creation for email: \(email), accountType: \(accountType.rawValue)")

            // [Gap 5b] Pre-check username availability BEFORE any auth side
            // effect — avoids orphan auth.users rows when username conflicts.
            let usernameOK = await isUsernameAvailable(username)
            if !usernameOK {
                authState = .error("Username has been registered")
                return
            }

            // First, check if user already exists by trying to sign in
            do {
                let existingUser = try await supabase.auth.signIn(email: email, password: password)
                print("User already exists")
                authState = .error("Email has been registered")
                return
            } catch {
                // User doesn't exist or wrong password, proceed with signup
                print("User doesn't exist, proceeding with signup")
            }

            // Store credentials for later use in profile completion
            pendingUsername = username
            pendingPassword = password
            pendingAccountType = accountType

            // Try creating the auth user with minimal data
            do {
                let authResponse = try await supabase.auth.signUp(
                    email: email,
                    password: password
                )
                print("Auth user created with ID: \(authResponse.user.id)")

                // Set state to account created, which will trigger survey flow
                authState = .accountCreated(email: email, accountType: accountType)

            } catch {
                print("Supabase signup failed: \(error)")

                // [Gap 5b] Detect Supabase's "user already registered" error
                // explicitly — wrong-password signIn above fails into this branch
                // (catches as generic error), so the real email-taken signal
                // surfaces here on signUp.
                let msg = error.localizedDescription.lowercased()
                if msg.contains("already") || msg.contains("registered") || msg.contains("exists") {
                    authState = .error("Email has been registered")
                    return
                }

                // Existing fallback: still proceed to survey for other failures
                // (network glitch, etc.) — completeProfile retries signUp.
                authState = .accountCreated(email: email, accountType: accountType)
            }

        } catch {
            print("Account creation error: \(error)")
            authState = .error("Failed to create account. Please try again.")
        }
    }
    
    // MARK: - Complete Profile (Step 2 - after survey)
    //
    // For patients, `surveyResponses` carries their symptom answers from
    // the survey flow. For clinicians, `surveyResponses` is `nil` (they
    // skipped the survey) and the symptom columns get blank strings on
    // insert. The chosen account type is read from `pendingAccountType`,
    // stashed in `createAccount(...)`.
    func completeProfile(email: String, surveyResponses: SurveyResponses?) async {
        isLoading = true
        defer { isLoading = false }

        do {
            print("Completing profile for email: \(email), accountType: \(pendingAccountType.rawValue)")

            // Try to sign in first
            do {
                let authRes = try await supabase.auth.signIn(email: email, password: pendingPassword)
                print("Sign in successful, creating profile...")

                try await createUserProfile(
                    userId: authRes.user.id,
                    email: email,
                    username: pendingUsername,
                    accountType: pendingAccountType,
                    surveyResponses: surveyResponses
                )
                print("Profile creation completed, loading profile...")

                clearPendingSignupState()

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
                        accountType: pendingAccountType,
                        surveyResponses: surveyResponses
                    )

                    clearPendingSignupState()

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

    private func clearPendingSignupState() {
        pendingUsername = ""
        pendingPassword = ""
        pendingAccountType = .patient
    }

    // MARK: - Create User Profile
    private func createUserProfile(
        userId: UUID,
        email: String,
        username: String,
        accountType: AccountType,
        surveyResponses: SurveyResponses?
    ) async throws {
        struct ProfileInsert: Encodable {
            let id: String
            let email: String
            let username: String
            let account_type: String
            let symptoms_location: String
            let symptoms_area: String
            let diagnosis: String
        }

        let profileData = ProfileInsert(
            id: userId.uuidString,
            email: email,
            username: username,
            account_type: accountType.rawValue,
            symptoms_location: surveyResponses?.symptomsLocation ?? "",
            symptoms_area:    surveyResponses?.symptomsArea    ?? "",
            diagnosis:        surveyResponses?.diagnosis       ?? ""
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
