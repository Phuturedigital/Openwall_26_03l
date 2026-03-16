/*
  # Fix Infinite Recursion in Profiles RLS and Add Missing Schema

  ## Critical Fixes

  ### 1. Fix Infinite Recursion in Profiles RLS Policies
  **Issue:** The admin policy has a recursive subquery:
  ```sql
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  ```
  This causes "infinite recursion detected in policy for relation 'profiles'" error
  because it queries profiles table while evaluating a profiles policy.

  **Solution:**
  - Drop ALL existing profiles policies to ensure clean slate
  - Create simple, non-recursive policies that use auth.uid() directly
  - Use a helper function `is_admin()` that is SECURITY DEFINER to break recursion

  ### 2. Add Missing Columns to Profiles Table
  - `user_type` column exists but may need default value fix
  - Replace `display_name` references with `full_name` (display_name doesn't exist)
  - Ensure all columns from Profile TypeScript type exist

  ### 3. Verify Tables and Functions
  - `notifications` table already exists (verified in migration 20251110140146)
  - `welcome_emails_sent` table already exists (verified in migration 20251110213905)
  - `log_user_activity` function already exists (verified in migration 20251110211422)

  ## Changes

  1. Drop all existing profiles RLS policies
  2. Create new non-recursive policies
  3. Ensure user_type column has proper default and NOT NULL constraint
  4. Add any missing columns from TypeScript Profile type
*/

-- =====================================================
-- STEP 1: Fix Infinite Recursion - Drop All Profiles Policies
-- =====================================================

-- Drop all existing policies on profiles table to ensure clean slate
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Users can delete own profile" ON profiles;

-- =====================================================
-- STEP 2: Add Missing Columns to Profiles
-- =====================================================

-- Ensure user_type has a default value to handle NOT NULL constraint
DO $$
BEGIN
  -- Check if user_type column needs default value fix
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'user_type'
  ) THEN
    -- Set default for existing NULL values
    UPDATE profiles SET user_type = 'user' WHERE user_type IS NULL;

    -- Ensure column has default
    ALTER TABLE profiles ALTER COLUMN user_type SET DEFAULT 'user';

    -- Ensure NOT NULL constraint (may already exist)
    BEGIN
      ALTER TABLE profiles ALTER COLUMN user_type SET NOT NULL;
    EXCEPTION WHEN others THEN
      -- Constraint might already exist, ignore error
      NULL;
    END;
  END IF;
END $$;

-- Add role column if it doesn't exist (should exist from admin migration)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'role'
  ) THEN
    ALTER TABLE profiles ADD COLUMN role text DEFAULT 'user' CHECK (role IN ('user', 'admin'));
    CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
  END IF;
END $$;

-- Add city column if missing (should exist from earlier migrations)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'city'
  ) THEN
    ALTER TABLE profiles ADD COLUMN city text;
  END IF;
END $$;

-- Add area column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'area'
  ) THEN
    ALTER TABLE profiles ADD COLUMN area text;
  END IF;
END $$;

-- Add verified column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'verified'
  ) THEN
    ALTER TABLE profiles ADD COLUMN verified boolean DEFAULT false;
  END IF;
END $$;

-- Add profession column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'profession'
  ) THEN
    ALTER TABLE profiles ADD COLUMN profession text;
  END IF;
END $$;

-- Add skills column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'skills'
  ) THEN
    ALTER TABLE profiles ADD COLUMN skills text[] DEFAULT '{}';
  END IF;
END $$;

-- Add bio column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'bio'
  ) THEN
    ALTER TABLE profiles ADD COLUMN bio text;
  END IF;
END $$;

-- Add portfolio column if missing (stored as JSONB for FileAttachment[])
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'portfolio'
  ) THEN
    ALTER TABLE profiles ADD COLUMN portfolio jsonb DEFAULT '[]';
  END IF;
END $$;

-- Add experience column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'experience'
  ) THEN
    ALTER TABLE profiles ADD COLUMN experience text;
  END IF;
END $$;

-- Add industry column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'industry'
  ) THEN
    ALTER TABLE profiles ADD COLUMN industry text;
  END IF;
END $$;

-- Add looking_for column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'looking_for'
  ) THEN
    ALTER TABLE profiles ADD COLUMN looking_for text[] DEFAULT '{}';
  END IF;
END $$;

-- Add post_visibility column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'post_visibility'
  ) THEN
    ALTER TABLE profiles ADD COLUMN post_visibility text DEFAULT 'public';
  END IF;
END $$;

-- Add last_active column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'last_active'
  ) THEN
    ALTER TABLE profiles ADD COLUMN last_active timestamptz DEFAULT now();
  END IF;
END $$;

-- Add intent column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'intent'
  ) THEN
    ALTER TABLE profiles ADD COLUMN intent text CHECK (intent IN ('offer_services', 'post_request'));
  END IF;
END $$;

-- Add discovery_preference column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'discovery_preference'
  ) THEN
    ALTER TABLE profiles ADD COLUMN discovery_preference text CHECK (discovery_preference IN ('be_discovered', 'find_others', 'both'));
  END IF;
END $$;

-- Add company_name column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'company_name'
  ) THEN
    ALTER TABLE profiles ADD COLUMN company_name text;
  END IF;
END $$;

-- Add service_category column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'service_category'
  ) THEN
    ALTER TABLE profiles ADD COLUMN service_category text;
  END IF;
END $$;

-- Add services_offered column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'services_offered'
  ) THEN
    ALTER TABLE profiles ADD COLUMN services_offered text;
  END IF;
END $$;

-- Add work_mode column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'work_mode'
  ) THEN
    ALTER TABLE profiles ADD COLUMN work_mode text CHECK (work_mode IN ('remote', 'on-site', 'both'));
  END IF;
END $$;

-- Add help_needed column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'help_needed'
  ) THEN
    ALTER TABLE profiles ADD COLUMN help_needed text;
  END IF;
END $$;

-- Add daily_request_limit column if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'daily_request_limit'
  ) THEN
    ALTER TABLE profiles ADD COLUMN daily_request_limit integer DEFAULT 5;
  END IF;
END $$;

-- =====================================================
-- STEP 3: Recreate is_admin() Function as SECURITY DEFINER
-- =====================================================

-- This function breaks the recursion by being SECURITY DEFINER
-- It runs with elevated privileges and doesn't trigger RLS policies
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role = 'admin'
  );
END;
$$;

-- =====================================================
-- STEP 4: Create New Non-Recursive Profiles Policies
-- =====================================================

-- Simple SELECT policy: All authenticated users can view all profiles
CREATE POLICY "profiles_select_all"
  ON profiles FOR SELECT
  TO authenticated
  USING (true);

-- Simple INSERT policy: Users can only insert their own profile
CREATE POLICY "profiles_insert_own"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Simple UPDATE policy: Users can only update their own profile
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- =====================================================
-- STEP 5: Update Welcome Email Function to Use full_name
-- =====================================================

-- Fix the welcome email function to use full_name instead of display_name
CREATE OR REPLACE FUNCTION send_welcome_email_on_verification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url text;
  v_service_role_key text;
  v_full_name text;
BEGIN
  -- Only send if email was just verified (changed from null to not null)
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN

    -- Get profile info for personalization (use full_name instead of display_name)
    SELECT full_name INTO v_full_name
    FROM profiles
    WHERE id = NEW.id;

    -- Get Supabase URL and service role key from environment
    v_supabase_url := current_setting('app.settings.supabase_url', true);
    v_service_role_key := current_setting('app.settings.service_role_key', true);

    -- Log that welcome email should be sent
    RAISE NOTICE 'Welcome email should be sent to: % (user_id: %, name: %)', NEW.email, NEW.id, v_full_name;

    -- If you have pg_net installed, uncomment this to actually send:
    /*
    PERFORM net.http_post(
      url := v_supabase_url || '/functions/v1/send-welcome-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      body := jsonb_build_object(
        'user_id', NEW.id,
        'email', NEW.email,
        'display_name', v_full_name
      )
    );
    */
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- Documentation
-- =====================================================

COMMENT ON POLICY "profiles_select_all" ON profiles IS
'Non-recursive policy: All authenticated users can view all profiles';

COMMENT ON POLICY "profiles_insert_own" ON profiles IS
'Non-recursive policy: Users can only insert their own profile';

COMMENT ON POLICY "profiles_update_own" ON profiles IS
'Non-recursive policy: Users can only update their own profile';

COMMENT ON FUNCTION is_admin() IS
'SECURITY DEFINER helper function to check admin status without triggering RLS recursion';
