-- Keep the email registry linked to the current Auth user.
-- This lets login distinguish active, deleted, and never-registered emails
-- without relying on the Auth Admin user-list endpoint.

CREATE TABLE IF NOT EXISTS public.email_registrations (
  email text PRIMARY KEY,
  role text NOT NULL DEFAULT 'participant',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.email_registrations
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

UPDATE public.email_registrations er
SET auth_user_id = au.id
FROM auth.users au
WHERE lower(au.email) = er.email
  AND er.auth_user_id IS DISTINCT FROM au.id;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
      auth_user_id = EXCLUDED.auth_user_id,
      updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION handle_deleted_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.email_registrations
  SET auth_user_id = NULL, updated_at = now()
  WHERE auth_user_id = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;
CREATE TRIGGER on_auth_user_deleted
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_deleted_user();