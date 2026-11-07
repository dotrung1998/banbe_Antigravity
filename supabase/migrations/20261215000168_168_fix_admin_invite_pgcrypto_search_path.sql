-- Migration: fix create_admin_invite() / redeem_admin_invite_token() (121).
-- Both call gen_random_bytes()/digest() unqualified, but pgcrypto lives in the
-- `extensions` schema on Supabase and these functions' search_path excluded it,
-- so every call failed with `function gen_random_bytes(integer) does not exist`
-- (SQLSTATE 42883) and the iOS/web Admin Team "Invite" showed the generic
-- "Could not send the invite". Same bug 115 fixed for 113's event-invite
-- functions. ALTER FUNCTION ... SET search_path changes only the function's
-- configuration, not its body.
ALTER FUNCTION public.create_admin_invite(text)
  SET search_path = public, auth, extensions;

ALTER FUNCTION public.redeem_admin_invite_token(text)
  SET search_path = public, auth, extensions;
