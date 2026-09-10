-- Migration: Persist email-to-role mappings so deleted accounts cannot re-register with a different role

CREATE TABLE IF NOT EXISTS public.email_registrations (
  email text PRIMARY KEY,
  role text NOT NULL DEFAULT 'participant',
  auth_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Backfill existing auth users. Neither source of "role" is guaranteed: a
-- profile row may not exist yet, and raw_user_meta_data may carry no
-- account_type (or an empty one) for an account that signed up before that
-- field existed — so always fall back to 'participant' rather than leaving
-- the NOT NULL column with nothing to write.
INSERT INTO public.email_registrations (email, role, auth_user_id)
SELECT
  lower(email),
  COALESCE(
    p.role,
    NULLIF(trim(u.raw_user_meta_data->>'account_type'), ''),
    'participant'
  ),
  u.id
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE u.email IS NOT NULL
ON CONFLICT (email) DO UPDATE SET
  role = EXCLUDED.role,
  auth_user_id = EXCLUDED.auth_user_id,
  updated_at = now();

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
        COALESCE(NEW.phone, ''),
        'vi',
        CASE trim(NEW.raw_user_meta_data->>'account_type')
          WHEN 'organizer' THEN 'organizer'
          WHEN 'admin' THEN 'admin'
          ELSE 'participant'
        END
    )
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.email_registrations (email, role, auth_user_id)
    VALUES (
        lower(NEW.email),
        CASE trim(NEW.raw_user_meta_data->>'account_type')
          WHEN 'organizer' THEN 'organizer'
          WHEN 'admin' THEN 'admin'
          ELSE 'participant'
        END,
        NEW.id
    )
    ON CONFLICT (email) DO UPDATE SET
      role = EXCLUDED.role,
      auth_user_id = EXCLUDED.auth_user_id,
      updated_at = now();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();
