# Supabase Trigger Setup for User Profiles

Run these SQL commands in your Supabase SQL Editor in the following order:

## 1. Create Temporary Table for Signup Data

```sql
-- Create table to temporarily store signup data
CREATE TABLE IF NOT EXISTS public.temp_user_signup (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    username TEXT NOT NULL,
    email TEXT NOT NULL,
    symptoms_location TEXT,
    symptoms_area TEXT,
    diagnosis TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed BOOLEAN DEFAULT FALSE
);

-- Enable RLS on temp table
ALTER TABLE public.temp_user_signup ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to insert temp data (during signup)
CREATE POLICY "Anonymous users can insert temp signup data" ON public.temp_user_signup
FOR INSERT TO anon
WITH CHECK (true);

-- Allow authenticated users to insert their own temp data
CREATE POLICY "Users can insert temp signup data" ON public.temp_user_signup
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Allow service role to read/write all temp data (for trigger processing)
CREATE POLICY "Service role can manage temp signup data" ON public.temp_user_signup
FOR ALL TO service_role
USING (true);
```

## 2. Create Trigger Function

```sql
-- Function to handle profile creation when user is inserted
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    signup_data RECORD;
BEGIN
    -- Get the signup data for this user
    SELECT * INTO signup_data
    FROM public.temp_user_signup
    WHERE user_id = NEW.id AND processed = FALSE
    LIMIT 1;

    -- Check if profile already exists
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.id) THEN
        -- Profile exists, update it with survey data if available
        IF signup_data IS NOT NULL THEN
            UPDATE public.profiles SET
                username = signup_data.username,
                symptoms_location = signup_data.symptoms_location,
                symptoms_area = signup_data.symptoms_area,
                diagnosis = signup_data.diagnosis
            WHERE id = NEW.id;

            -- Mark the temp data as processed
            UPDATE public.temp_user_signup
            SET processed = TRUE
            WHERE id = signup_data.id;
        END IF;
    ELSE
        -- Profile doesn't exist, create it
        IF signup_data IS NOT NULL THEN
            -- Create profile with survey data
            INSERT INTO public.profiles (
                id,
                email,
                username,
                symptoms_location,
                symptoms_area,
                diagnosis,
                created_at
            ) VALUES (
                NEW.id,
                signup_data.email,
                signup_data.username,
                signup_data.symptoms_location,
                signup_data.symptoms_area,
                signup_data.diagnosis,
                NOW()
            );

            -- Mark the temp data as processed
            UPDATE public.temp_user_signup
            SET processed = TRUE
            WHERE id = signup_data.id;
        ELSE
            -- Create basic profile without survey data
            INSERT INTO public.profiles (
                id,
                email,
                username,
                created_at
            ) VALUES (
                NEW.id,
                NEW.email,
                COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
                NOW()
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## 3. Create the Trigger

```sql
-- Create trigger that fires when a new user is inserted into auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

## 4. Update RLS Policies for Profiles Table

```sql
-- Drop existing policies
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;

-- Create new policies
CREATE POLICY "Users can insert own profile" ON public.profiles
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own profile" ON public.profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Allow service role full access (for trigger)
CREATE POLICY "Service role can manage profiles" ON public.profiles
FOR ALL TO service_role
USING (true);
```

## 5. Optional: Clean up old temp data

```sql
-- Function to clean up processed temp data (run this periodically)
CREATE OR REPLACE FUNCTION public.cleanup_temp_signup_data()
RETURNS VOID AS $$
BEGIN
    DELETE FROM public.temp_user_signup
    WHERE processed = TRUE
    AND created_at < NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;

-- You can call this function manually or set up a cron job
-- SELECT public.cleanup_temp_signup_data();
```

## Testing the Setup

After running all these commands:

1. Try signing up a new user through your app
2. The trigger should automatically create a profile in the `profiles` table
3. Check your Supabase dashboard to verify the profile was created with the survey data
4. The temp data should be marked as processed

## Troubleshooting

If the trigger doesn't work:

1. Check Supabase logs for any errors
2. Verify the trigger function was created successfully
3. Make sure RLS policies allow the trigger to insert into profiles
4. Test with a simple user creation (without survey data) first

## Alternative: Manual Profile Creation

If you prefer not to use triggers, you can modify your client code to:

1. Sign up the user
2. Wait for email confirmation (if required)
3. Have the user sign in
4. Then create the profile using the authenticated session

But the trigger approach is cleaner and more reliable.
