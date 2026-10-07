-- Migration 163: ensure_my_organizer()
--
-- ROOT CAUSE of "Missing organizer profile": an `organizers` row has only
-- ever been created lazily inside create_event_draft() (migrations 007/012/
-- 112, "IF NOT FOUND THEN INSERT INTO organizers"). set_organizer_mode()
-- (016/017/082/103) only flips profiles.role, so an account with Organizer
-- Mode ON that has not yet created an event owns no organizer, and the Host
-- card (gated on myOrganizerId / myOrganizerIds) has nothing to show.
--
-- This additive RPC creates the owner's default organizer on demand.
--  * auth.uid() only (no user id parameter); authenticated only, never anon.
--  * idempotent + serialised per user (advisory xact lock) -> concurrent
--    calls create exactly ONE organizer.
--  * returns the existing id (created:false) if the user already OWNS one.
--    Mere organizer_members (team) membership never counts and never
--    creates ownership.
--  * requires organizer mode on (role organizer, or admin whose
--    organizer_mode_enabled is not false). Roles are never changed.
--  * nothing is published; verified stays false.
--  * default name = display name + localized "Events" suffix (editable);
--    blank / email-like / phone-like display names fall back to a neutral
--    name. Never derived from email, phone or handle.

CREATE OR REPLACE FUNCTION public.ensure_my_organizer()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_role    text;
  v_enabled boolean;
  v_name_in text;
  v_locale  text;
  v_vi      boolean;
  v_name    text;
  v_id      text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- One ensure at a time per user: the second caller waits, then sees the
  -- row the first one committed and returns created:false.
  PERFORM pg_advisory_xact_lock(hashtextextended('ensure_my_organizer:' || v_uid::text, 0));

  SELECT o.id, o.name INTO v_id, v_name
  FROM public.organizers o
  WHERE o.owner_id = v_uid OR o.user_id = v_uid
  ORDER BY o.created_at ASC, o.id ASC
  LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'organizerId', v_id, 'created', false, 'name', v_name);
  END IF;

  SELECT p.role, COALESCE(p.organizer_mode_enabled, true), p.display_name, p.locale::text
    INTO v_role, v_enabled, v_name_in, v_locale
  FROM public.profiles p WHERE p.id = v_uid;

  IF v_role IS NULL OR NOT (v_role = 'organizer' OR (v_role = 'admin' AND v_enabled)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ORGANIZER_MODE_REQUIRED');
  END IF;

  v_vi := COALESCE(v_locale, 'en') = 'vi';
  v_name_in := btrim(COALESCE(v_name_in, ''));
  IF v_name_in = '' OR position('@' IN v_name_in) > 0 OR v_name_in ~ '^[0-9+()\s.-]+$' THEN
    v_name := CASE WHEN v_vi THEN 'Sự kiện của tôi' ELSE 'My events' END;
  ELSE
    v_name := left(v_name_in, 60) || CASE WHEN v_vi THEN ' Sự kiện' ELSE ' Events' END;
  END IF;

  v_id := 'org_' || substr(md5(gen_random_uuid()::text), 1, 8);
  INSERT INTO public.organizers (id, owner_id, user_id, name)
  VALUES (v_id, v_uid, v_uid, v_name);

  RETURN jsonb_build_object('success', true, 'organizerId', v_id, 'created', true, 'name', v_name);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_organizer() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_my_organizer() FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_organizer() TO authenticated;
