/*
  # Add Missing Columns to Notes Table

  1. Changes
    - Add `status` column with values: 'open', 'in_progress', 'fulfilled', 'deleted'
    - Add `fulfilled_by` column to track who fulfilled the note
    - Add `fulfilled_at` column to track when the note was fulfilled
    - Add `prio` column (boolean) to replace `is_priority`
    - Add `body` column to store the main content (replacing `description`)
    - Add `area` column for more specific location info
    - Add `work_mode` column for remote/on-site/both preferences
    - Add `city` column if it doesn't exist
    - Add indexes for better query performance

  2. Data Migration
    - Copy `description` to `body` for existing records
    - Copy `is_priority` to `prio` for existing records
    - Set default status to 'open' for existing records

  3. Security
    - Update RLS policies if needed
*/

-- Add status column with constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'status'
  ) THEN
    ALTER TABLE notes ADD COLUMN status text DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'fulfilled', 'deleted'));
  END IF;
END $$;

-- Add fulfilled tracking columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'fulfilled_by'
  ) THEN
    ALTER TABLE notes ADD COLUMN fulfilled_by uuid REFERENCES profiles(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'fulfilled_at'
  ) THEN
    ALTER TABLE notes ADD COLUMN fulfilled_at timestamptz;
  END IF;
END $$;

-- Add prio column (boolean for priority)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'prio'
  ) THEN
    ALTER TABLE notes ADD COLUMN prio boolean DEFAULT false;
    -- Copy data from is_priority if it exists
    UPDATE notes SET prio = is_priority WHERE is_priority IS NOT NULL;
  END IF;
END $$;

-- Add body column (main content)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'body'
  ) THEN
    ALTER TABLE notes ADD COLUMN body text NOT NULL DEFAULT '';
    -- Copy data from description if it exists
    UPDATE notes SET body = description WHERE description IS NOT NULL;
  END IF;
END $$;

-- Add area column for specific location
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'area'
  ) THEN
    ALTER TABLE notes ADD COLUMN area text;
  END IF;
END $$;

-- Add work_mode column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'work_mode'
  ) THEN
    ALTER TABLE notes ADD COLUMN work_mode text CHECK (work_mode IN ('remote', 'on-site', 'both'));
  END IF;
END $$;

-- Add city column if it doesn't exist (it might already exist as 'location')
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'city'
  ) THEN
    ALTER TABLE notes ADD COLUMN city text;
    -- Copy data from location if it exists
    UPDATE notes SET city = location WHERE location IS NOT NULL;
  END IF;
END $$;

-- Add files column for attachments (jsonb array)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'files'
  ) THEN
    ALTER TABLE notes ADD COLUMN files jsonb DEFAULT '[]'::jsonb;
    -- Copy data from attachments if it exists
    UPDATE notes SET files = attachments WHERE attachments IS NOT NULL;
  END IF;
END $$;

-- Add daily_request tracking columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'daily_request_count'
  ) THEN
    ALTER TABLE notes ADD COLUMN daily_request_count integer DEFAULT 0;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notes' AND column_name = 'last_request_reset'
  ) THEN
    ALTER TABLE notes ADD COLUMN last_request_reset timestamptz DEFAULT now();
  END IF;
END $$;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_notes_status ON notes(status) WHERE status != 'deleted';
CREATE INDEX IF NOT EXISTS idx_notes_city ON notes(city) WHERE city IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notes_prio ON notes(prio) WHERE prio = true;
CREATE INDEX IF NOT EXISTS idx_notes_category ON notes(category) WHERE category IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);

-- Create composite index for common queries
CREATE INDEX IF NOT EXISTS idx_notes_city_status_prio ON notes(city, status, prio DESC, created_at DESC) 
  WHERE status NOT IN ('deleted', 'fulfilled');
