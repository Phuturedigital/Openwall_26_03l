/*
  # Add Admin Role System

  1. Schema Changes
    - Add `role` column to profiles table (default: 'user', options: 'user', 'admin')
    - Add `is_admin` helper function
    - Add admin-specific functions for user management

  2. Security
    - RLS policies allow admins to view all data
    - Modifications still respect ownership for safety

  3. Admin Functions
    - `is_admin()` - Check if current user is admin
    - `get_user_stats()` - View detailed user statistics
    - `update_user_role()` - Update user roles (admin only)
    - `get_platform_stats()` - View platform-wide statistics
    - `admin_search_notes()` - Search all notes across users
    - `get_all_users_admin()` - Get all users with stats
*/

-- Add role column to profiles
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

-- Function to check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role = 'admin'
  );
END;
$$;

-- Function to get all users (admin only)
CREATE OR REPLACE FUNCTION get_all_users_admin()
RETURNS TABLE (
  id uuid,
  full_name text,
  email text,
  phone text,
  company text,
  user_type text,
  role text,
  created_at timestamptz,
  updated_at timestamptz,
  total_notes bigint,
  total_unlocks bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.email,
    p.phone,
    p.company,
    p.user_type,
    p.role,
    p.created_at,
    p.updated_at,
    COALESCE((SELECT COUNT(*) FROM notes WHERE user_id = p.id), 0) as total_notes,
    COALESCE((SELECT COUNT(*) FROM unlocked_leads WHERE vendor_id = p.id), 0) as total_unlocks
  FROM profiles p
  ORDER BY p.created_at DESC;
END;
$$;

-- Function to get detailed user stats (admin only)
CREATE OR REPLACE FUNCTION get_user_stats(target_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT json_build_object(
    'user_id', p.id,
    'full_name', p.full_name,
    'email', p.email,
    'phone', p.phone,
    'company', p.company,
    'user_type', p.user_type,
    'role', p.role,
    'created_at', p.created_at,
    'total_notes', COALESCE((SELECT COUNT(*) FROM notes WHERE user_id = p.id), 0),
    'total_unlocks', COALESCE((SELECT COUNT(*) FROM unlocked_leads WHERE vendor_id = p.id), 0),
    'total_payments', COALESCE((SELECT SUM(amount) FROM payment_history WHERE user_id = p.id AND status = 'completed'), 0)
  ) INTO result
  FROM profiles p
  WHERE p.id = target_user_id;

  RETURN result;
END;
$$;

-- Function to update user role (admin only)
CREATE OR REPLACE FUNCTION update_user_role(target_user_id uuid, new_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  IF new_role NOT IN ('user', 'admin') THEN
    RAISE EXCEPTION 'Invalid role. Must be user or admin';
  END IF;

  UPDATE profiles
  SET role = new_role, updated_at = now()
  WHERE id = target_user_id;

  RETURN true;
END;
$$;

-- Function to get platform stats (admin only)
CREATE OR REPLACE FUNCTION get_platform_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT json_build_object(
    'total_users', (SELECT COUNT(*) FROM profiles),
    'new_users_today', (SELECT COUNT(*) FROM profiles WHERE created_at >= CURRENT_DATE),
    'new_users_week', (SELECT COUNT(*) FROM profiles WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'),
    'total_notes', (SELECT COUNT(*) FROM notes),
    'priority_notes', (SELECT COUNT(*) FROM notes WHERE is_priority = true),
    'total_unlocks', (SELECT COUNT(*) FROM unlocked_leads),
    'total_revenue', COALESCE((SELECT SUM(amount) FROM payment_history WHERE status = 'completed'), 0),
    'pending_payments', COALESCE((SELECT SUM(amount) FROM payment_history WHERE status = 'pending'), 0),
    'user_types', (SELECT json_object_agg(COALESCE(user_type, 'not_set'), count) FROM (SELECT COALESCE(user_type, 'not_set') as user_type, COUNT(*) as count FROM profiles GROUP BY user_type) types),
    'categories', (SELECT json_object_agg(COALESCE(category, 'not_set'), count) FROM (SELECT COALESCE(category, 'not_set') as category, COUNT(*) as count FROM notes GROUP BY category) cats)
  ) INTO result;

  RETURN result;
END;
$$;

-- Function to search notes across all users (admin only)
CREATE OR REPLACE FUNCTION admin_search_notes(search_term text DEFAULT NULL, limit_count int DEFAULT 50)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  user_name text,
  user_email text,
  title text,
  description text,
  location text,
  category text,
  budget text,
  is_priority boolean,
  created_at timestamptz,
  unlock_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.user_id,
    p.full_name as user_name,
    p.email as user_email,
    n.title,
    n.description,
    n.location,
    n.category,
    n.budget,
    n.is_priority,
    n.created_at,
    COALESCE((SELECT COUNT(*) FROM unlocked_leads WHERE note_id = n.id), 0) as unlock_count
  FROM notes n
  JOIN profiles p ON n.user_id = p.id
  WHERE
    (search_term IS NULL OR n.description ILIKE '%' || search_term || '%' OR n.title ILIKE '%' || search_term || '%')
  ORDER BY n.created_at DESC
  LIMIT limit_count;
END;
$$;

-- Add admin access to profiles (read all)
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
CREATE POLICY "Admins can view all profiles"
  ON profiles FOR SELECT
  TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    OR id = auth.uid()
  );

-- Add admin access to notes
DROP POLICY IF EXISTS "Admins can view all notes" ON notes;
CREATE POLICY "Admins can view all notes"
  ON notes FOR SELECT
  TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    OR user_id = auth.uid()
  );

-- Add admin access to unlocked_leads
DROP POLICY IF EXISTS "Admins can view all unlocked leads" ON unlocked_leads;
CREATE POLICY "Admins can view all unlocked leads"
  ON unlocked_leads FOR SELECT
  TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    OR vendor_id = auth.uid()
    OR EXISTS (SELECT 1 FROM notes WHERE notes.id = unlocked_leads.note_id AND notes.user_id = auth.uid())
  );

-- Add admin access to payment_history
DROP POLICY IF EXISTS "Admins can view all payment history" ON payment_history;
CREATE POLICY "Admins can view all payment history"
  ON payment_history FOR SELECT
  TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    OR user_id = auth.uid()
  );