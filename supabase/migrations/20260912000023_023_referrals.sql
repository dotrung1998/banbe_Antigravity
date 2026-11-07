-- Migration: referral codes — every account gets one automatically, and a
-- new signup can redeem someone else's to record who invited them.
--
-- This is deliberately just an attribution ledger (who invited whom), not a
-- rewards/credits system — there's nothing elsewhere in the schema resembling
-- credits or discounts to hang a reward on, and bolting one on here would be
-- guessing at product decisions nobody's asked for yet. What it does give:
-- a stable, shareable code per user, and a durable record of who joined
-- through whose link, which any future rewards feature would need anyway.

-- ---------------------------------------------------------------------------
-- 1. profiles.referral_code / referred_by
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code text,
  ADD COLUMN IF NOT EXISTS referred_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_referral_code_key ON public.profiles (referral_code);

-- Readable, unambiguous 7-char codes (no 0/O/1/I) — short enough to type by
-- hand off a screen, long enough that guessing one isn't practical.
CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_attempt int := 0;
BEGIN
  LOOP
    v_code := '';
    FOR i IN 1..7 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    v_attempt := v_attempt + 1;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = v_code) OR v_attempt > 20;
  END LOOP;
  RETURN v_code;
END;
$$;

-- Backfill existing accounts so nobody signed up before this migration is
-- left without a shareable link.
UPDATE public.profiles SET referral_code = public.generate_referral_code() WHERE referral_code IS NULL;

-- ---------------------------------------------------------------------------
-- 2. handle_new_user(): unchanged behavior, plus stamping a fresh code.
--    Same body as migration 016, the current definition — see that file for
--    why role is always 'participant' regardless of client-supplied metadata.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale, role, referral_code)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
      COALESCE(NEW.phone, ''),
      'vi',
      'participant',
      public.generate_referral_code()
    )
    ON CONFLICT (id) DO NOTHING;

    IF NEW.email IS NOT NULL THEN
      INSERT INTO public.email_registrations (email, role, auth_user_id)
      VALUES (lower(NEW.email), 'participant', NEW.id)
      ON CONFLICT (email) DO UPDATE SET
        auth_user_id = EXCLUDED.auth_user_id,
        updated_at = now();
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. redeem_referral(): called once, right after a brand-new account's first
--    sign-in, with whatever code was in the link they followed. Silently a
--    no-op for anything that isn't a clean "new account, valid code, not
--    yourself, not already set" — this is attribution, not a security
--    boundary, so it fails quiet rather than raising on every edge case.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.redeem_referral(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text := upper(trim(p_code));
  v_referrer_id uuid;
  v_already uuid;
  v_new_name text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF v_code = '' THEN RETURN jsonb_build_object('success', false, 'error', 'CODE_REQUIRED'); END IF;

  SELECT referred_by INTO v_already FROM public.profiles WHERE id = v_uid;
  IF v_already IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_REFERRED');
  END IF;

  SELECT id INTO v_referrer_id FROM public.profiles WHERE referral_code = v_code;
  IF v_referrer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'CODE_NOT_FOUND');
  END IF;
  IF v_referrer_id = v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_REFER_SELF');
  END IF;

  UPDATE public.profiles SET referred_by = v_referrer_id WHERE id = v_uid;

  SELECT NULLIF(trim(display_name), '') INTO v_new_name FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.notifications (recipient_id, kind, title, body, data)
  VALUES (
    v_referrer_id,
    'referral_joined',
    'Một người bạn vừa tham gia banbe',
    COALESCE(v_new_name, 'Một người bạn bạn đã mời') || ' vừa tham gia banbe qua lời mời của bạn.',
    jsonb_build_object('new_user_id', v_uid, 'new_user_name', v_new_name)
  );

  RETURN jsonb_build_object('success', true, 'referrer_id', v_referrer_id);
END;
$$;

REVOKE ALL ON FUNCTION public.redeem_referral(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.redeem_referral(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.redeem_referral(text) TO authenticated;
