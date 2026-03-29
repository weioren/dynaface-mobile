# Supabase Integration Setup Guide

This guide will help you complete the Supabase integration for your Reva app.

## Prerequisites

1. **Supabase Account**: Create an account at [supabase.com](https://supabase.com)
2. **New Project**: Create a new project in Supabase
3. **Xcode Project**: Make sure your Reva project is open in Xcode

## Step 1: Add Supabase Swift SDK

1. In Xcode, go to **File** > **Add Package Dependencies**
2. Enter the package URL: `https://github.com/supabase-community/supabase-swift.git`
3. Click **Add Package**
4. Select your Reva target and click **Add Package**

## Step 2: Get Your Supabase Credentials

1. Go to your Supabase project dashboard
2. Navigate to **Settings** > **API**
3. Copy your **Project URL** and **anon key**

## Step 3: Update Configuration

1. Open `Reva/SupabaseConfig.swift`
2. Replace the placeholder values:
   ```swift
   static let projectURL = "https://your-actual-project-id.supabase.co"
   static let anonKey = "your-actual-anon-key"
   ```

## Step 4: Create Database Table

Run this SQL in your Supabase **SQL Editor**:

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

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Create security policies
CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);
```

## Step 5: Test the Integration

1. **Build and Run** your app
2. **Create a new account** through the signup flow
3. **Complete the survey** questions
4. **Sign out** and **sign back in** to test persistence
5. **Check your Supabase dashboard** to see the user data

## What's Now Working

✅ **Account Creation**: Users can sign up with email/password + survey data  
✅ **Data Storage**: Survey responses stored in Supabase database  
✅ **Persistent Sign-in**: App remembers logged-in users between sessions  
✅ **Basic Security**: Row-level security on user data  
✅ **Survey Flow**: Proper data passing between survey pages  

## Troubleshooting

### Build Errors
- Make sure Supabase Swift SDK is properly added to your project
- Check that the package is linked to your target

### Authentication Errors
- Verify your Supabase URL and anon key are correct
- Check that the `users` table was created successfully
- Ensure RLS policies are in place

### Data Not Saving
- Check Supabase logs for any database errors
- Verify the table schema matches the User model
- Check that RLS policies allow the current user to insert data

## Next Steps

Once basic authentication is working, consider adding:
- Password reset functionality
- Email verification
- Input validation
- Offline handling
- Error retry logic

## Support

- [Supabase Documentation](https://supabase.com/docs)
- [Supabase Swift SDK](https://github.com/supabase-community/supabase-swift)
- [Supabase Community](https://github.com/supabase/supabase/discussions)
