-- Repair accounts that signed up as organizers/admins but were recorded as
-- participants because the account_type metadata was dropped on the
-- email-link flow, or the profile row pre-dated the metadata
-- (handle_new_user uses ON CONFLICT (id) DO NOTHING, so a pre-existing
-- participant profile kept its old role).

-- 1. Promote profiles whose auth metadata says organizer/admin.
UPDATE public.profiles p
SET role = m.role
FROM (
  SELECT u.id,
         CASE trim(u.raw_user_meta_data->>'account_type')
           WHEN 'organizer' THEN 'organizer'
           WHEN 'admin' THEN 'admin'
         END AS role
  FROM auth.users u
) m
WHERE p.id = m.id
  AND m.role IS NOT NULL
  AND p.role = 'participant';

-- 2. Keep the email registry in sync by promoting registry rows whose linked
-- profile is an organizer/admin, so role-mismatch checks stop blocking them.
UPDATE public.email_registrations er
SET role = p.role,
    updated_at = now()
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
WHERE er.auth_user_id = u.id
  AND er.role = 'participant'
  AND p.role IN ('organizer', 'admin');