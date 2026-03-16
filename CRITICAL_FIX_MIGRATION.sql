/*
  # CRITICAL FIX: Infinite Recursion Error in Profiles RLS
  
  This migration fixes the blocking infinite recursion error:
  "infinite recursion detected in policy for relation 'profiles'"
  
  Root cause: Lines 229, 239, 249, 260 in migration 20260316190526_add_admin_role_system.sql
  have recursive subqueries: (SELECT role FROM profiles WHERE id = auth.uid())
  
  This creates infinite recursion because the policies query the profiles table
  while evaluating profiles policies.
  
  ## Changes:
  1. Recreate is_admin() function as SECURITY DEFINER with STABLE and search_path
  2. Drop all problematic recursive policies on profiles, notes, unlocked_leads, payment_history
  3. Create simple non-recursive policies on profiles
  4. Fix user_type column to have DEFAULT 'user'
  5. Update NULL user_type values to 'user'
  6. Add all missing profile columns from TypeScript Profile type
  7. Recreate non-recursive policies for notes, unlocked_leads, payment_history
*/

-- =====================================================
-- STEP 1: Fix is_admin() Function (CRITICAL)
-- =====================================================

-- Recreate is_admin() as STABLE SECURITY DEFINER with proper search_path
-- This breaks the recursion by running with elevated privileges
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role = 'admin'
  );
$$;

-- Add comment
COMMENT ON FUNCTION is_admin() IS 
'STABLE SECURITY DEFINER function to check admin status without triggering RLS recursion';

-- =====================================================
-- STEP 2: Drop ALL Problematic Recursive Policies
-- =====================================================

-- Drop profiles policies (all of them)
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;
DROP POLICY IF EXISTS "profiles_select_all" ON profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
DROP POLICY IF EXISTS "Users can delete own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view public profile info" ON profiles;

-- Drop notes policies (the recursive admin ones)
DROP POLICY IF EXISTS "Admins can view all notes" ON notes;
DROP POLICY IF EXISTS "Public can view all notes" ON notes;
DROP POLICY IF EXISTS "Users can view all notes" ON notes;
DROP POLICY IF EXISTS "Users can create notes" ON notes;
DROP POLICY IF EXISTS "Users can update their own notes" ON notes;
DROP POLICY IF EXISTS "Users can delete their own notes" ON notes;
DROP POLICY IF EXISTS "Users can update notes" ON notes;
DROP POLICY IF EXISTS "Users can delete notes" ON notes;

-- Drop unlocked_leads policies (the recursive admin ones)
DROP POLICY IF EXISTS "Admins can view all unlocked leads" ON unlocked_leads;
DROP POLICY IF EXISTS "Users can view relevant unlocked leads" ON unlocked_leads;
DROP POLICY IF EXISTS "Vendors can view unlocked leads" ON unlocked_leads;
DROP POLICY IF EXISTS "Vendors can create unlocked leads" ON unlocked_leads;
DROP POLICY IF EXISTS "Users can create unlocked leads" ON unlocked_leads;

-- Drop payment_history policies (the recursive admin ones)
DROP POLICY IF EXISTS "Admins can view all payment history" ON payment_history;
DROP POLICY IF EXISTS "Users can view their own payment history" ON payment_history;
DROP POLICY IF EXISTS "Users can insert their own payment history" ON payment_history;
DROP POLICY IF EXISTS "Users can view payment history" ON payment_history;

-- =====================================================
-- STEP 3: Fix user_type Column Schema
-- =====================================================

-- Update constraint to allow 'user' value
DO $$
BEGIN
  -- Drop old constraint if exists
  ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_user_type_check;
  
  -- Add new constraint that allows 'client', 'vendor', and 'user'
  ALTER TABLE profiles ADD CONSTRAINT profiles_user_type_check
    CHECK (user_type IN ('client', 'vendor', 'user'));
END $$;

-- Set default value for user_type
ALTER TABLE profiles ALTER COLUMN user_type SET DEFAULT 'user';

-- Temporarily allow NULL to update existing records
ALTER TABLE profiles ALTER COLUMN user_type DROP NOT NULL;

-- Update all NULL user_type values to 'user'
UPDATE profiles SET user_type = 'user' WHERE user_type IS NULL;

-- Re-apply NOT NULL constraint
ALTER TABLE profiles ALTER COLUMN user_type SET NOT NULL;

-- =====================================================
-- STEP 4: Add ALL Missing Profile Columns
-- =====================================================

-- Add intent column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'intent'
  ) THEN
    ALTER TABLE profiles ADD COLUMN intent text;
  END IF;
END $$;

-- Add area column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'area'
  ) THEN
    ALTER TABLE profiles ADD COLUMN area text;
  END IF;
END $$;

-- Add discovery_preference column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'discovery_preference'
  ) THEN
    ALTER TABLE profiles ADD COLUMN discovery_preference text;
  END IF;
END $$;

-- Add company_name column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'company_name'
  ) THEN
    ALTER TABLE profiles ADD COLUMN company_name text;
  END IF;
END $$;

-- Add service_category column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'service_category'
  ) THEN
    ALTER TABLE profiles ADD COLUMN service_category text;
  END IF;
END $$;

-- Add services_offered column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'services_offered'
  ) THEN
    ALTER TABLE profiles ADD COLUMN services_offered text;
  END IF;
END $$;

-- Add work_mode column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'work_mode'
  ) THEN
    ALTER TABLE profiles ADD COLUMN work_mode text;
  END IF;
END $$;

-- Add help_needed column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'help_needed'
  ) THEN
    ALTER TABLE profiles ADD COLUMN help_needed text;
  END IF;
END $$;

-- Add verified column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'verified'
  ) THEN
    ALTER TABLE profiles ADD COLUMN verified boolean DEFAULT false;
  END IF;
END $$;

-- Add profession column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'profession'
  ) THEN
    ALTER TABLE profiles ADD COLUMN profession text;
  END IF;
END $$;

-- Add skills column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'skills'
  ) THEN
    ALTER TABLE profiles ADD COLUMN skills text[] DEFAULT '{}';
  END IF;
END $$;

-- Add bio column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'bio'
  ) THEN
    ALTER TABLE profiles ADD COLUMN bio text;
  END IF;
END $$;

-- Add portfolio column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'portfolio'
  ) THEN
    ALTER TABLE profiles ADD COLUMN portfolio jsonb DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- Add experience column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'experience'
  ) THEN
    ALTER TABLE profiles ADD COLUMN experience text;
  END IF;
END $$;

-- Add industry column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'industry'
  ) THEN
    ALTER TABLE profiles ADD COLUMN industry text;
  END IF;
END $$;

-- Add city column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'city'
  ) THEN
    ALTER TABLE profiles ADD COLUMN city text;
  END IF;
END $$;

-- Add post_visibility column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'post_visibility'
  ) THEN
    ALTER TABLE profiles ADD COLUMN post_visibility text DEFAULT 'public';
  END IF;
END $$;

-- Add daily_request_limit column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'daily_request_limit'
  ) THEN
    ALTER TABLE profiles ADD COLUMN daily_request_limit integer DEFAULT 10;
  END IF;
END $$;

-- Add last_active column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'last_active'
  ) THEN
    ALTER TABLE profiles ADD COLUMN last_active timestamptz DEFAULT now();
  END IF;
END $$;

-- Add role column (if missing - should exist from admin migration)
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

-- Add looking_for column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'looking_for'
  ) THEN
    ALTER TABLE profiles ADD COLUMN looking_for text[] DEFAULT '{}';
  END IF;
END $$;

-- Add updated_at column (if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE profiles ADD COLUMN updated_at timestamptz DEFAULT now();
  END IF;
END $$;

-- =====================================================
-- STEP 5: Create Simple Non-Recursive Policies on Profiles
-- =====================================================

-- Allow authenticated AND anon users to view all profiles
CREATE POLICY "profiles_select_policy"
  ON profiles FOR SELECT
  TO authenticated, anon
  USING (true);

-- Allow authenticated users to insert only their own profile
CREATE POLICY "profiles_insert_policy"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Allow authenticated users to update only their own profile
CREATE POLICY "profiles_update_policy"
  ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Add policy comments
COMMENT ON POLICY "profiles_select_policy" ON profiles IS
'Non-recursive: Allow all authenticated and anon users to view all profiles';

COMMENT ON POLICY "profiles_insert_policy" ON profiles IS
'Non-recursive: Users can only insert their own profile';

COMMENT ON POLICY "profiles_update_policy" ON profiles IS
'Non-recursive: Users can only update their own profile';

-- =====================================================
-- STEP 6: Recreate Non-Recursive Policies for Notes
-- =====================================================

-- Allow everyone (authenticated and anon) to view all notes
CREATE POLICY "notes_select_policy"
  ON notes FOR SELECT
  TO authenticated, anon
  USING (true);

-- Allow authenticated users to create notes
CREATE POLICY "notes_insert_policy"
  ON notes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own notes
CREATE POLICY "notes_update_policy"
  ON notes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own notes
CREATE POLICY "notes_delete_policy"
  ON notes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- =====================================================
-- STEP 7: Recreate Non-Recursive Policies for Unlocked Leads
-- =====================================================

-- Allow vendors to view their unlocked leads and note owners to view unlocks on their notes
CREATE POLICY "unlocked_leads_select_policy"
  ON unlocked_leads FOR SELECT
  TO authenticated
  USING (
    auth.uid() = vendor_id
    OR EXISTS (
      SELECT 1 FROM notes
      WHERE notes.id = unlocked_leads.note_id
      AND notes.user_id = auth.uid()
    )
  );

-- Allow vendors to create unlocked leads
CREATE POLICY "unlocked_leads_insert_policy"
  ON unlocked_leads FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = vendor_id);

-- =====================================================
-- STEP 8: Recreate Non-Recursive Policies for Payment History
-- =====================================================

-- Allow users to view their own payment history
CREATE POLICY "payment_history_select_policy"
  ON payment_history FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Allow users to insert their own payment records
CREATE POLICY "payment_history_insert_policy"
  ON payment_history FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- =====================================================
-- STEP 9: Create updated_at Trigger
-- =====================================================

-- Create or replace the update_updated_at function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS set_updated_at ON profiles;

-- Create the trigger
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- Verification Comments
-- =====================================================

COMMENT ON TABLE profiles IS 
'User profiles table with non-recursive RLS policies. All columns from TypeScript Profile type are present.';

COMMENT ON POLICY "notes_select_policy" ON notes IS
'Non-recursive: Allow all users to view all notes';

COMMENT ON POLICY "unlocked_leads_select_policy" ON unlocked_leads IS
'Non-recursive: Vendors can view their unlocks, note owners can view unlocks on their notes';

COMMENT ON POLICY "payment_history_select_policy" ON payment_history IS
'Non-recursive: Users can view their own payment history';
