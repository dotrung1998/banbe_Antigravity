-- Fix: populate auth_user_id for existing email_registrations and add the missing column if needed

-- 1. Ensure the column exists
ALTER TABLE public.email_registrations ADD COLUMN IF NOT EXISTS auth_user_id uuid;

-- 2. Backfill from auth.users for any rows that still have NULL
UPDATE public.email_registrations er
SET auth_user_id = u.id
FROM auth.users u
WHERE lower(u.email) = er.email
  AND er.auth_user_id IS NULL;

-- 3. Also backfill any auth users that are not yet in the registry
INSERT INTO public.email_registrations (email, role, auth_user_id)
SELECT
  lower(u.email),
  COALESCE(p.role, 'participant'),
  u.id
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE u.email IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.email_registrations er WHERE lower(er.email) = lower(u.email))
ON CONFLICT (email) DO UPDATE SET
  auth_user_id = EXCLUDED.auth_user_id,
  updated_at = now();
