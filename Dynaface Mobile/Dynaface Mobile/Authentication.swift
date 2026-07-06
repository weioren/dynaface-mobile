import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - App User Model (avoid clash with FirebaseAuth.User)
//
// `id` is NOT the Firebase Auth UID. It's a separate, client-style UUID
// string ("app_uid") minted once by the `create_profile` Cloud Function at
// signup and stored as a custom claim on the Firebase ID token (see
// AuthenticationService.completeProfile). This keeps `profile.id` a UUID
// string exactly like the old Supabase `profiles.id`, so every other file
// in the app that does `UUID(uuidString: profile.id)` keeps working
// unchanged. The Firestore document ID for `profiles/{app_uid}` IS this id.
struct Profile: Identifiable {
    let id: String
    let email: String
    let username: String
    let createdAt: Date?
    let symptomsLocation: String?
    let symptomsArea: String?
    let diagnosis: String?
    let accountType: AccountType

    /// Manual decode from a Firestore document (id = document ID, data =
    /// document fields). Defensive on `account_type` the same way the old
    /// Supabase decoder was — falls back to `.patient` if missing/invalid.
    init?(id: String, data: [String: Any]) {
        guard
            let email = data["email"] as? String,
            let username = data["username"] as? String
        else {
            return nil
        }
        self.id = id
        self.email = email
        self.username = username
        self.createdAt = (data["created_at"] as? Timestamp)?.dateValue()
        self.symptomsLocation = data["symptoms_location"] as? String
        self.symptomsArea = data["symptoms_area"] as? String
        self.diagnosis = data["diagnosis"] as? String
        if let raw = data["account_type"] as? String, let type = AccountType(rawValue: raw) {
            self.accountType = type
        } else {
            self.accountType = .patient
        }
    }
}

// MARK: - Authentication State
enum AuthState {
    case loading
    case signedIn(Profile)
    case signedOut
    /// Phase 1 of signup completed (Firebase auth user created). The view
    /// layer reads `accountType` to decide whether to show the patient
    /// symptom survey or jump straight to the clinician welcome page.
    case accountCreated(email: String, accountType: AccountType)
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

    // Password strength — new signups must include an uppercase, a lowercase, a
    // number, and a special character, and be at least 8 chars. Sign-in is NOT
    // re-checked (existing accounts keep whatever they have).
    var hasMinLength: Bool { password.count >= 8 }
    var hasUpper: Bool { password.rangeOfCharacter(from: .uppercaseLetters) != nil }
    var hasLower: Bool { password.rangeOfCharacter(from: .lowercaseLetters) != nil }
    var hasDigit: Bool { password.rangeOfCharacter(from: .decimalDigits) != nil }
    var hasSpecial: Bool {
        password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_-+=[]{}|;:,.<>?/~`")) != nil
    }
    var isPasswordStrong: Bool {
        hasMinLength && hasUpper && hasLower && hasDigit && hasSpecial
    }

    // Email allow-list — signups must use a .edu / academic address or a common
    // consumer provider (blocks throwaway / uncommon domains). Client-side gate;
    // extend by editing `allowedEmailDomains`.
    private static let allowedEmailDomains: Set<String> = [
        "gmail.com", "googlemail.com",
        "outlook.com", "hotmail.com", "live.com", "msn.com",
        "yahoo.com", "ymail.com",
        "icloud.com", "me.com", "mac.com",
        "aol.com", "proton.me", "protonmail.com"
    ]

    var isEmailAllowed: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = e.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = String(parts[1])
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        // Academic — check the trailing domain labels (not a loose substring),
        // so a spoof like "foo.edu.evil.com" is NOT accepted.
        let labels = domain.split(separator: ".").map(String.init)
        if labels.last == "edu" { return true }                 // x.edu, mail.jhu.edu
        if labels.count >= 2 {
            let secondLevel = labels[labels.count - 2]
            if secondLevel == "edu" || secondLevel == "ac" { return true }  // x.edu.au, x.ac.uk
        }
        return AuthViewModel.allowedEmailDomains.contains(domain)
    }

    var isSignUpValid: Bool {
        isEmailAllowed &&
        !username.isEmpty &&
        password == confirmPassword &&
        isPasswordStrong
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
    /// Transient auth error surfaced inline (an alert) on the sign-in /
    /// sign-up forms. Replaces the old global `.error` state that took over
    /// the whole UI and stranded the user. Cleared at the start of each
    /// attempt and when the form's alert is dismissed.
    @Published var authError: String?

    // Store account creation data temporarily across the two-step signup flow
    private var pendingUsername: String = ""
    private var pendingPassword: String = ""
    private var pendingAccountType: AccountType = .patient

    private let db = Firestore.firestore()

    init() {
        Task { [weak self] in
            guard let self else { return }
            await self.checkCurrentSession()
        }
    }

    // MARK: - Session Management
    //
    // Firebase Auth manages its own token refresh, so unlike the old
    // Supabase setup there's no manual `startAutoRefresh()` step.
    func checkCurrentSession() async {
        guard let user = Auth.auth().currentUser else {
            authState = .signedOut
            return
        }
        do {
            let tokenResult = try await user.getIDTokenResult()
            guard let appUid = tokenResult.claims["app_uid"] as? String else {
                // Signed in to Firebase but never finished profile setup
                // (no app_uid claim yet) — treat like signed out.
                authState = .signedOut
                return
            }
            try await loadProfile(for: appUid)
        } catch {
            authState = .signedOut
        }
    }

    // MARK: - Username Availability
    //
    // Firestore has no server-side ILIKE/RPC, so this is an exact-match
    // query against a lowercased `username_lower` field maintained
    // alongside `username` on every write. Fails open (returns true) on
    // a transient query error so a network blip doesn't block legitimate
    // signups — same trade-off the old Supabase RPC made.
    func isUsernameAvailable(_ username: String) async -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let snapshot = try await db.collection("profiles")
                .whereField("username_lower", isEqualTo: trimmed.lowercased())
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.isEmpty
        } catch {
            print("isUsernameAvailable query failed: \(error)")
            return true   // fail open
        }
    }

    private func loadProfile(for appUid: String) async throws {
        let snapshot = try await db.collection("profiles").document(appUid).getDocument()
        guard let data = snapshot.data(), let profile = Profile(id: appUid, data: data) else {
            throw AuthError.userNotFound
        }
        authState = .signedIn(profile)
    }

    // MARK: - Update Profile
    //
    // Partial update against `profiles/{app_uid}` — only the fields the
    // caller populates are written. Mirrors the old Supabase RLS contract:
    // a user may only update their own profile (enforced by
    // firestore.rules using request.auth.token.app_uid).
    struct ProfilePatch {
        var username: String?
        var symptoms_location: String?
        var symptoms_area: String?
        var diagnosis: String?
    }

    func updateProfile(patch: ProfilePatch) async throws {
        guard case .signedIn(let current) = authState else {
            throw AuthError.userNotFound
        }

        // If username is being changed, pre-check availability before
        // issuing the update so the user gets a friendly error.
        if let newUsername = patch.username {
            let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() != current.username.lowercased() {
                let available = await isUsernameAvailable(trimmed)
                if !available {
                    throw AuthError.usernameAlreadyTaken
                }
            }
        }

        var update: [String: Any] = [:]
        if let username = patch.username {
            update["username"] = username
            update["username_lower"] = username.lowercased()
        }
        if let v = patch.symptoms_location { update["symptoms_location"] = v }
        if let v = patch.symptoms_area { update["symptoms_area"] = v }
        if let v = patch.diagnosis { update["diagnosis"] = v }

        guard !update.isEmpty else { return }

        try await db.collection("profiles").document(current.id).updateData(update)

        // Re-fetch so authState reflects the updated values.
        try await loadProfile(for: current.id)
    }

    // MARK: - Create Account (Step 1)
    func createAccount(email: String, username: String, password: String, accountType: AccountType) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        print("Starting account creation for email: \(email), accountType: \(accountType.rawValue)")

        // Clear any stale session from a previous attempt
        try? Auth.auth().signOut()

        // Pre-check username availability BEFORE any auth side
        // effect — avoids orphan Firebase Auth users when username conflicts.
        let usernameOK = await isUsernameAvailable(username)
        if !usernameOK {
            authError = "Username has been registered"
            return
        }

        // Store credentials for later use in profile completion
        pendingUsername = username
        pendingPassword = password
        pendingAccountType = accountType

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("Firebase auth user created with UID: \(result.user.uid)")
            authState = .accountCreated(email: email, accountType: accountType)
        } catch {
            print("Firebase signup failed: \(error)")
            clearPendingSignupState()
            authError = signUpErrorMessage(for: error)
        }
    }

    // MARK: - Complete Profile (Step 2 - after survey)
    //
    // For patients, `surveyResponses` carries their symptom answers from
    // the survey flow. For clinicians, `surveyResponses` is `nil` (they
    // skipped the survey) and the symptom fields get blank strings.
    //
    // Unlike the old Supabase version, Firebase's `createUser` already
    // signs the user in, so there's no "try sign in, fall back to sign up"
    // dance needed here — we just call the `create_profile` Cloud Function
    // with the current user's ID token.
    func completeProfile(email: String, surveyResponses: SurveyResponses?) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        guard let user = Auth.auth().currentUser else {
            // Broken session (no Firebase user) — recover to the auth selector.
            authError = "Failed to create account. Please try again or contact support."
            authState = .signedOut
            return
        }

        do {
            print("Completing profile for email: \(email), accountType: \(pendingAccountType.rawValue)")
            let idToken = try await user.getIDToken()
            let appUid = try await callCreateProfile(
                idToken: idToken,
                email: email,
                username: pendingUsername,
                accountType: pendingAccountType,
                surveyResponses: surveyResponses
            )

            // Force a token refresh so the new `app_uid` custom claim set
            // by create_profile is reflected locally before anything reads it.
            _ = try await user.getIDToken(forcingRefresh: true)

            clearPendingSignupState()
            try await loadProfile(for: appUid)
            print("Profile completion successful")
        } catch {
            print("Profile completion error: \(error)")
            // Stay on the survey (.accountCreated) so the user can retry submit.
            authError = completeProfileErrorMessage(for: error)
        }
    }

    private func clearPendingSignupState() {
        pendingUsername = ""
        pendingPassword = ""
        pendingAccountType = .patient
    }

    // MARK: - Error messages
    //
    // Map raw Firebase / network errors to a clear, user-facing line so the
    // signup alerts say what actually went wrong instead of a generic
    // "Failed to create account". FirebaseAuth surfaces its AuthErrorCode as a
    // stable integer on the NSError (matching the code is more robust than
    // scanning the localized message text, which can be reworded/localized).
    private func signUpErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 17007: return "Email has been registered"            // emailAlreadyInUse
        case 17008: return "That email address looks invalid"     // invalidEmail
        case 17026: return "Password is too weak"                 // weakPassword
        case 17020: return "No connection. Check your network and try again."  // networkError
        default:
            if nsError.domain == NSURLErrorDomain {
                return "No connection. Check your network and try again."
            }
            return "Couldn't create the account: \(error.localizedDescription)"
        }
    }

    private func completeProfileErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain || nsError.code == 17020 {  // network
            return "No connection. Check your network and try again."
        }
        // Errors thrown by callCreateProfile carry the function's response text.
        if nsError.domain == "create_profile" {
            if nsError.localizedDescription.lowercased().contains("username") {
                return "Username has been registered"
            }
            return "Couldn't finish setup: \(nsError.localizedDescription)"
        }
        return "Couldn't finish setup. Please try again or contact support."
    }

    // MARK: - create_profile Cloud Function call
    //
    // Server-side (Admin SDK) profile creation. Bypasses Firestore rules
    // entirely (this is the one and only place a profile doc is created),
    // generates the `app_uid`, and sets it as a custom claim on the
    // Firebase user. See dynaface-mobile/gcp-backend/create_profile/main.py.
    private func callCreateProfile(
        idToken: String,
        email: String,
        username: String,
        accountType: AccountType,
        surveyResponses: SurveyResponses?
    ) async throws -> String {
        guard let url = URL(string: FirebaseConfig.createProfileFunctionURL) else {
            throw AuthError.signUpFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "email": email,
            "username": username,
            "account_type": accountType.rawValue,
            "symptoms_location": surveyResponses?.symptomsLocation ?? "",
            "symptoms_area": surveyResponses?.symptomsArea ?? "",
            "diagnosis": surveyResponses?.diagnosis ?? "",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(
                domain: "create_profile",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create profile: \(text)"]
            )
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let appUid = json["app_uid"] as? String
        else {
            throw NSError(
                domain: "create_profile",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Malformed create_profile response"]
            )
        }
        return appUid
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let tokenResult = try await result.user.getIDTokenResult()
            guard let appUid = tokenResult.claims["app_uid"] as? String else {
                // Signed in to Firebase but profile setup never finished —
                // drop the half-session and surface the message on the form.
                try? Auth.auth().signOut()
                authError = "This account hasn't finished setup. Please contact support."
                return
            }
            try await loadProfile(for: appUid)
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Sign Out
    func signOut() async {
        try? Auth.auth().signOut()
        authState = .signedOut
    }

    // MARK: - Password Reset
    //
    // Firebase sends its own templated reset email; the continuation/action
    // URL is configured in the Firebase console (Auth > Templates) rather
    // than passed per-call like Supabase's `redirectTo`.
    func resetPassword(email: String) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            authError = error.localizedDescription
        }
    }
}
