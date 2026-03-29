# Supabase Authentication Setup

This document outlines the steps to integrate Supabase authentication into the Reva app.

## Prerequisites

1. Create a Supabase account at [supabase.com](https://supabase.com)
2. Create a new project in Supabase

## Setup Steps

### 1. Install Supabase Swift SDK

Add the Supabase Swift SDK to your project using Swift Package Manager:

```
https://github.com/supabase-community/supabase-swift.git
```

### 2. Configure Supabase Project

1. Go to your Supabase project dashboard
2. Navigate to Settings > API
3. Copy your project URL and anon key

### 3. Update Authentication.swift

Replace the placeholder values in `Authentication.swift`:

```swift
private let supabaseURL = "YOUR_SUPABASE_URL"
private let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
```

With your actual Supabase credentials:

```swift
private let supabaseURL = "https://your-project-id.supabase.co"
private let supabaseAnonKey = "your-anon-key"
```

### 4. Create Database Tables

In your Supabase dashboard, create the following tables:

#### Users Table
```sql
CREATE TABLE users (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT NOT NULL,
  username TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  symptoms_location TEXT,
  symptoms_area TEXT,
  diagnosis TEXT
);

-- Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);
```

### 5. Implement Supabase Integration

Update the `Authentication.swift` methods to use Supabase:

#### Sign Up Implementation
```swift
func signUp(email: String, username: String, password: String, surveyResponses: SurveyResponses) async {
    await MainActor.run {
        isLoading = true
    }
    
    do {
        // 1. Create user account in Supabase Auth
        let authResponse = try await supabase.auth.signUp(
            email: email,
            password: password
        )
        
        guard let user = authResponse.user else {
            throw AuthError.signUpFailed
        }
        
        // 2. Store user profile in database
        let userProfile = [
            "id": user.id.uuidString,
            "email": email,
            "username": username,
            "symptoms_location": surveyResponses.symptomsLocation,
            "symptoms_area": surveyResponses.symptomsArea,
            "diagnosis": surveyResponses.diagnosis
        ]
        
        try await supabase.database
            .from("users")
            .insert(userProfile)
            .execute()
        
        // 3. Create local user object
        let localUser = User(
            id: user.id.uuidString,
            email: email,
            username: username,
            createdAt: Date(),
            symptomsLocation: surveyResponses.symptomsLocation,
            symptomsArea: surveyResponses.symptomsArea,
            diagnosis: surveyResponses.diagnosis
        )
        
        await MainActor.run {
            authState = .signedIn(localUser)
            isLoading = false
        }
        
    } catch {
        await MainActor.run {
            authState = .error(error.localizedDescription)
            isLoading = false
        }
    }
}
```

#### Sign In Implementation
```swift
func signIn(email: String, password: String) async {
    await MainActor.run {
        isLoading = true
    }
    
    do {
        // 1. Authenticate with Supabase
        let authResponse = try await supabase.auth.signIn(
            email: email,
            password: password
        )
        
        guard let user = authResponse.user else {
            throw AuthError.signInFailed
        }
        
        // 2. Fetch user profile from database
        let response = try await supabase.database
            .from("users")
            .select()
            .eq("id", value: user.id.uuidString)
            .single()
            .execute()
        
        let userData = response.decoded(to: User.self)
        
        await MainActor.run {
            authState = .signedIn(userData)
            isLoading = false
        }
        
    } catch {
        await MainActor.run {
            authState = .error(error.localizedDescription)
            isLoading = false
        }
    }
}
```

### 6. Environment Configuration

For production, consider using environment variables or a configuration file to store your Supabase credentials securely.

### 7. Testing

1. Test the sign-up flow with the survey
2. Test the sign-in flow
3. Test session persistence
4. Test sign-out functionality

## Security Considerations

1. Enable Row Level Security (RLS) on all tables
2. Use appropriate policies to control data access
3. Validate user input on both client and server
4. Use HTTPS for all API calls
5. Store sensitive data securely

## Error Handling

Implement proper error handling for common scenarios:
- Network connectivity issues
- Invalid credentials
- Email already exists
- Password requirements not met
- Server errors

## Next Steps

1. Implement password reset functionality
2. Add email verification
3. Implement social authentication (Google, Apple)
4. Add user profile management
5. Implement data synchronization for offline support 