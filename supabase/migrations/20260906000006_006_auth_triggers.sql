-- Migration: Auth Triggers & Phone OTP Profile Requirements

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
        COALESCE(NEW.phone, ''),
        'vi'
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

CREATE OR REPLACE FUNCTION sync_phone_verification()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.phone_confirmed_at IS NOT NULL THEN
    UPDATE profiles SET phone = COALESCE(NEW.phone, phone), phone_verified = true WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_phone_confirmed ON auth.users;
CREATE TRIGGER on_auth_phone_confirmed
AFTER UPDATE OF phone_confirmed_at ON auth.users
FOR EACH ROW WHEN (NEW.phone_confirmed_at IS NOT NULL) EXECUTE FUNCTION sync_phone_verification();

CREATE OR REPLACE FUNCTION verify_phone_otp(p_user_id uuid, p_phone text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    UPDATE profiles
    SET phone = p_phone, phone_verified = true
    WHERE id = p_user_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION verify_phone_otp FROM anon;
GRANT EXECUTE ON FUNCTION verify_phone_otp TO authenticated;
