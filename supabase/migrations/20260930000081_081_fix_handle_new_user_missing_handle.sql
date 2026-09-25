-- Migration: fix handle_new_user() never setting profiles.handle, and
-- backfill any row it already broke.
--
-- Migration 079 (public_profile_card_and_avatars) added `profiles.handle`
-- as NOT NULL and backfilled every row that existed AT THAT TIME. It never
-- touched handle_new_user() (last redefined by migration 040), which still
-- INSERTs a profiles row with no `handle` column at all. Two real,
-- confirmed symptoms since:
--   1. Brand-new signups fail outright: the INSERT violates the NOT NULL
--      constraint, the trigger raises, the whole `auth.users` insert rolls
--      back with it — surfaced client-side as "Database error creating new
--      user."
--   2. At least one existing account (id 8a4eb34e-aeb8-48cb-a7ea-a9e3239491a8,
--      confirmed via a live PostgREST error: `23502 null value in column
--      "handle" of relation "profiles" violates not-null constraint`) has a
--      profiles row with `handle IS NULL` despite the constraint — created
--      after 079 shipped, before this fix, via some path that produced a
--      profiles row without going through 079's one-time backfill. Every
--      UPDATE to that row (not just ones touching `handle` — Postgres
--      re-validates NOT NULL against the whole resulting row on any UPDATE)
--      has been failing ever since, which is the actual root cause of the
--      "Không thể đổi chế độ tổ chức lúc này" organizer-toggle report:
--      set_organizer_mode()'s own `UPDATE profiles SET role = ...` for that
--      account hits this exact constraint violation.

-- 1. Backfill: identical formula to 079's own backfill, so every row this
--    bug produced (or any other still-NULL row) gets the same stable,
--    collision-safe synthetic handle a pre-existing account would have
--    gotten from 079 itself.
UPDATE profiles SET handle = 'u' || replace(id::text, '-', '')::text
WHERE handle IS NULL;
UPDATE profiles SET handle = left(handle, 13) WHERE length(handle) > 13;

-- 2. handle_new_user(): now sets handle on INSERT, same formula, so this
--    can never recur for a new signup. Everything else unchanged from
--    migration 040's version.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := CASE WHEN lower(COALESCE(NEW.email, '')) = 'banbetestadmin@gmail.com'
                       THEN 'admin' ELSE 'participant' END;
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale, role, referral_code, handle)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
      COALESCE(NEW.phone, ''),
      'vi',
      v_role,
      public.generate_referral_code(),
      left('u' || replace(NEW.id::text, '-', ''), 13)
    )
    ON CONFLICT (id) DO NOTHING;

    IF NEW.email IS NOT NULL THEN
      INSERT INTO public.email_registrations (email, role, auth_user_id)
      VALUES (lower(NEW.email), v_role, NEW.id)
      ON CONFLICT (email) DO UPDATE SET
        auth_user_id = EXCLUDED.auth_user_id,
        updated_at = now();
    END IF;
    RETURN NEW;
END;
$$;
