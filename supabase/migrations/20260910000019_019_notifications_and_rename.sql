-- Migration: in-app notifications, and a guarded way to change display_name
-- that tells organizers when one of their guests renames themselves.
--
-- Renaming after signup previously meant a direct UPDATE on profiles, which
-- is silent — an organizer messaging "Anh Minh" has no way to know "Anh Minh"
-- is now showing up as someone else's name. rename_display_name() does the
-- update itself and, in the same transaction, writes one notification row
-- per organizer this guest has an actual booking history with.
--
-- Email delivery for that notification happens outside the database (SQL
-- cannot send email); the API route that calls this RPC re-derives the same
-- recipient list itself from the DB afterwards rather than trusting the
-- client, and sends the email. This migration only owns the durable,
-- authoritative part: the profile update and the in-app notification rows.

-- ---------------------------------------------------------------------------
-- 1. notifications: a small per-user inbox. Only the recipient can read or
--    mark their own rows read; nothing but a SECURITY DEFINER function (or
--    the service role) may insert, so a client can't forge a notification
--    into someone else's inbox.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL,
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_recipient_created_idx
  ON public.notifications (recipient_id, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
CREATE POLICY "notifications_select_own" ON public.notifications
  FOR SELECT TO authenticated USING (auth.uid() = recipient_id);

DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
CREATE POLICY "notifications_update_own" ON public.notifications
  FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);

-- ---------------------------------------------------------------------------
-- 2. rename_display_name(): updates the caller's own name, then notifies
--    every organizer this guest has ever booked with (owner_id and user_id
--    are both checked — an organizer profile can be claimed by either).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rename_display_name(p_new_name text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_clean text := trim(p_new_name);
  v_old_name text;
  v_notified int := 0;
  r record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF v_clean = '' OR length(v_clean) > 60 THEN RAISE EXCEPTION 'INVALID_NAME'; END IF;

  SELECT display_name INTO v_old_name FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  UPDATE public.profiles SET display_name = v_clean WHERE id = v_uid;

  IF v_old_name IS NOT NULL AND v_old_name <> '' AND v_old_name <> v_clean THEN
    FOR r IN
      SELECT DISTINCT target_id FROM (
        SELECT o.owner_id AS target_id
        FROM public.bookings b
        JOIN public.events e ON e.id = b.event_id
        JOIN public.organizers o ON o.id = e.organizer_id
        WHERE b.user_id = v_uid AND o.owner_id IS NOT NULL AND o.owner_id <> v_uid
        UNION
        SELECT o.user_id AS target_id
        FROM public.bookings b
        JOIN public.events e ON e.id = b.event_id
        JOIN public.organizers o ON o.id = e.organizer_id
        WHERE b.user_id = v_uid AND o.user_id IS NOT NULL AND o.user_id <> v_uid
      ) targets
    LOOP
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        r.target_id,
        'guest_renamed',
        'Một khách đã đổi tên',
        v_old_name || ' đã đổi tên thành ' || v_clean || '.',
        jsonb_build_object('old_name', v_old_name, 'new_name', v_clean, 'guest_id', v_uid)
      );
      v_notified := v_notified + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('old_name', v_old_name, 'new_name', v_clean, 'notified', v_notified);
END;
$$;

REVOKE ALL ON FUNCTION public.rename_display_name(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rename_display_name(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.rename_display_name(text) TO authenticated;
