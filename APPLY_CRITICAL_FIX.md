# CRITICAL FIX: Apply Migration to Fix Infinite Recursion

## Problem
The database is currently experiencing an infinite recursion error:
```
"infinite recursion detected in policy for relation 'profiles'"
```

This is **BLOCKING ALL LOGIN AND PROFILE LOADING**.

## Root Cause
Migration file `supabase/migrations/20260316190526_add_admin_role_system.sql` contains recursive policies on lines 229, 239, 249, and 260 that query the profiles table while evaluating profiles table policies:
```sql
(SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
```

## Solution
A comprehensive migration has been created at:
```
/tmp/cc-agent/64760170/project/CRITICAL_FIX_MIGRATION.sql
```

## How to Apply This Migration

### Option 1: Using Supabase Dashboard (Recommended)
1. Go to your Supabase project dashboard at https://epysecbkfhmgrcisefiy.supabase.co
2. Navigate to **SQL Editor**
3. Open the file `/tmp/cc-agent/64760170/project/CRITICAL_FIX_MIGRATION.sql`
4. Copy the entire contents
5. Paste into the SQL Editor
6. Click **Run** to execute the migration
7. Verify success - you should see green checkmarks

### Option 2: Using Supabase CLI (If Available)
```bash
cd /tmp/cc-agent/64760170/project
supabase db execute --file CRITICAL_FIX_MIGRATION.sql
```

### Option 3: Using psql (Direct Connection)
If you have database credentials:
```bash
psql "$DATABASE_URL" < /tmp/cc-agent/64760170/project/CRITICAL_FIX_MIGRATION.sql
```

## What This Migration Does

### 1. Fixes is_admin() Function
- Recreates as `STABLE SECURITY DEFINER` with `SET search_path = public`
- This breaks the recursion by running with elevated privileges
- The function no longer triggers RLS policies when called

### 2. Drops ALL Problematic Recursive Policies
Removes recursive policies from:
- `profiles` table (12 policies)
- `notes` table (8 policies)
- `unlocked_leads` table (5 policies)
- `payment_history` table (4 policies)

### 3. Creates Simple Non-Recursive Policies

#### Profiles Table:
- `profiles_select_policy`: Allow authenticated and anon users to view all profiles (USING true)
- `profiles_insert_policy`: Users can only insert their own profile (auth.uid() = id)
- `profiles_update_policy`: Users can only update their own profile (auth.uid() = id)

#### Notes Table:
- `notes_select_policy`: Everyone can view all notes
- `notes_insert_policy`: Users can create notes
- `notes_update_policy`: Users can update their own notes
- `notes_delete_policy`: Users can delete their own notes

#### Unlocked Leads Table:
- `unlocked_leads_select_policy`: Vendors can view their unlocks, note owners can view unlocks on their notes
- `unlocked_leads_insert_policy`: Vendors can create unlocked leads

#### Payment History Table:
- `payment_history_select_policy`: Users can view their own payment history
- `payment_history_insert_policy`: Users can insert their own payment records

### 4. Fixes user_type Column
- Updates constraint to allow 'client', 'vendor', and 'user' values
- Sets DEFAULT to 'user'
- Updates all NULL values to 'user'
- Re-applies NOT NULL constraint

### 5. Adds ALL Missing Profile Columns
Ensures all columns from TypeScript Profile type exist:
- intent
- area
- discovery_preference
- company_name
- service_category
- services_offered
- work_mode
- help_needed
- verified
- profession
- skills
- bio
- portfolio
- experience
- industry
- city
- post_visibility
- daily_request_limit
- last_active
- role
- looking_for
- updated_at

### 6. Creates updated_at Trigger
- Automatically updates the `updated_at` timestamp on profile updates

## After Applying the Migration

### Expected Results
1. Login should work immediately
2. Profile loading should work without errors
3. All profile data should be accessible
4. Admin functions will continue to work (using the fixed is_admin() function)

### Verification Steps
1. Try logging in to the application
2. Check that your profile loads correctly
3. Try updating your profile
4. Verify no console errors about infinite recursion

### If You Still Have Issues
Check the Supabase logs:
1. Go to Supabase Dashboard
2. Navigate to **Logs** > **Postgres Logs**
3. Look for any remaining RLS or recursion errors

## Admin Access Note
After this migration, admin-specific views will need to use the `is_admin()` function in application code rather than in RLS policies. The function is now safe to use because it's SECURITY DEFINER and doesn't trigger RLS recursion.

## Migration Timestamp
To add this as a proper migration file, name it:
```
supabase/migrations/20260316200000_fix_infinite_recursion_critical.sql
```

Then run:
```bash
supabase migration repair --status applied
```

## Rollback (If Needed)
If something goes wrong, you can rollback by:
1. Dropping all the new policies
2. Re-creating the original policies from `20260316190526_add_admin_role_system.sql`

However, this will bring back the infinite recursion error, so it's not recommended.
