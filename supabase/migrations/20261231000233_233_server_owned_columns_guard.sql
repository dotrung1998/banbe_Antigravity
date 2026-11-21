-- 233 — server-owned columns are no longer self-assignable through PostgREST.
--
-- Audit 2026-11-21 (Cloudflare security-audit):
--   * profiles_update_own (001:110-111) is a row policy, not a column policy.
--     Supabase's default table grant therefore let a signed-in account PATCH
--     its own can_manage_admins, phone_verified, attended_count, no_show_count,
--     referral_code, referred_by and created_at. The 121 admin-team RPCs check
--     can_manage_admins(), so an admin who did not have it could grant it to
--     themselves and then manage the admin team (121:334-339).
--   * organizers_update_own (001:118-119) likewise let a host set verified
--     and disputes_open directly. verified is the public "Đã xác minh" badge
--     (src/screens/OrganizerProfile.jsx:276), so a host could self-award it.
--   * messages_update_participant (064:20-22) checks thread membership only,
--     and the default UPDATE grant covers every column. Any participant could
--     PATCH another participant's message body or sender_id; the client only
--     ever writes read_at (src/state/BanBeContext.jsx:9674).
--   * The same insert policy let a participant insert kind='system', which the
--     UI renders as an official platform notice. Sanctioned system messages are
--     written by SECURITY DEFINER RPCs or the service role.
--
-- Fix: guard the client (authenticated/anon) write paths with BEFORE triggers.
-- SECURITY DEFINER RPCs and the service role run as their owner, so they are
-- deliberately unaffected (these are the only sanctioned writers). messages
-- gets a column-level UPDATE grant instead of a trigger, so read_at still works
-- and no other column is writable at all.
--
-- Rollback: supabase/rollbacks/20261231000233_233_revert_server_owned_columns_guard.sql
-- Tests:    supabase/tests/233_server_owned_columns/run.sh (throwaway stack only)

BEGIN;

-- ---------------------------------------------------------------------------
-- profiles: server-owned columns + the two sanctioned JSON fields.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profiles_guard_client_write()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  v_links jsonb;
BEGIN
  IF current_user::text IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      -- A client-created profile starts as an ordinary participant. The
      -- auth.users trigger creates real profiles as the definer, so it is
      -- not subject to this branch.
      NEW.role := 'participant';
      NEW.can_manage_admins := false;
      NEW.phone_verified := false;
      NEW.attended_count := 0;
      NEW.no_show_count := 0;
      NEW.referral_code := public.generate_referral_code();
      NEW.referred_by := NULL;
      NEW.created_at := now();
    ELSE
      -- Row policies already scope this to auth.uid() = id; pin the values
      -- that only a definer RPC may change.
      NEW.role := OLD.role;
      NEW.can_manage_admins := OLD.can_manage_admins;
      NEW.phone_verified := OLD.phone_verified;
      NEW.attended_count := OLD.attended_count;
      NEW.no_show_count := OLD.no_show_count;
      NEW.referral_code := OLD.referral_code;
      NEW.referred_by := OLD.referred_by;
      NEW.created_at := OLD.created_at;
    END IF;
  END IF;

  -- save_profile() already sanitizes; this closes the direct-PATCH path too.
  -- Split from INSERT so OLD is never referenced on an INSERT trigger.
  IF TG_OP = 'INSERT' THEN
    v_links := public.sanitize_social_links(NEW.social_links);
    IF v_links IS NULL THEN
      RAISE EXCEPTION 'INVALID_SOCIAL_LINKS' USING ERRCODE = 'check_violation';
    END IF;
    NEW.social_links := v_links;
  ELSIF NEW.social_links IS DISTINCT FROM OLD.social_links THEN
    v_links := public.sanitize_social_links(NEW.social_links);
    IF v_links IS NULL THEN
      RAISE EXCEPTION 'INVALID_SOCIAL_LINKS' USING ERRCODE = 'check_violation';
    END IF;
    NEW.social_links := v_links;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.profiles_guard_client_write() FROM PUBLIC;
DROP TRIGGER IF EXISTS profiles_guard_client_write ON public.profiles;
CREATE TRIGGER profiles_guard_client_write
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_guard_client_write();

-- ---------------------------------------------------------------------------
-- organizers: verification and dispute counters are platform-owned.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.organizers_guard_client_write()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  v_links jsonb;
BEGIN
  IF current_user::text IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      NEW.verified := false;
      NEW.disputes_open := 0;
    ELSE
      NEW.verified := OLD.verified;
      NEW.disputes_open := OLD.disputes_open;
    END IF;
  END IF;

  -- update_organizer_profile() already sanitizes; direct PATCH must too.
  IF TG_OP = 'INSERT' THEN
    v_links := public.sanitize_social_links(NEW.social_links);
    IF v_links IS NULL THEN
      RAISE EXCEPTION 'INVALID_SOCIAL_LINKS' USING ERRCODE = 'check_violation';
    END IF;
    NEW.social_links := v_links;
  ELSIF NEW.social_links IS DISTINCT FROM OLD.social_links THEN
    v_links := public.sanitize_social_links(NEW.social_links);
    IF v_links IS NULL THEN
      RAISE EXCEPTION 'INVALID_SOCIAL_LINKS' USING ERRCODE = 'check_violation';
    END IF;
    NEW.social_links := v_links;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.organizers_guard_client_write() FROM PUBLIC;
DROP TRIGGER IF EXISTS organizers_guard_client_write ON public.organizers;
CREATE TRIGGER organizers_guard_client_write
  BEFORE INSERT OR UPDATE ON public.organizers
  FOR EACH ROW EXECUTE FUNCTION public.organizers_guard_client_write();

-- ---------------------------------------------------------------------------
-- messages: read_at is the only column a participant may update.
-- ---------------------------------------------------------------------------
REVOKE UPDATE ON public.messages FROM authenticated, anon;
GRANT UPDATE (read_at) ON public.messages TO authenticated;

-- Direct clients may only create ordinary chat messages. System notices are
-- written by SECURITY DEFINER RPCs / the service role.
CREATE OR REPLACE FUNCTION public.messages_guard_client_insert()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF current_user::text IN ('authenticated', 'anon') AND NEW.kind IS DISTINCT FROM 'text' THEN
    NEW.kind := 'text';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.messages_guard_client_insert() FROM PUBLIC;
DROP TRIGGER IF EXISTS messages_guard_client_insert ON public.messages;
CREATE TRIGGER messages_guard_client_insert
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_guard_client_insert();

COMMIT;

-- Verification (throwaway stack, as a signed-in caller):
--   PATCH profiles?id=eq.<me> {"can_manage_admins":true}  -> stored value stays false
--   PATCH organizers?id=eq.<mine> {"verified":true}       -> stored value stays false
--   PATCH messages?id=eq.<other> {"body":"rewritten"}     -> 403 permission denied
--   PATCH messages?id=eq.<other> {"read_at":"..."}        -> 200
