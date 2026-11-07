-- Migration: fix a real, confirmed production bug in 113/114 — pgcrypto
-- functions (gen_random_bytes, digest) live in the `extensions` schema on
-- Supabase, never `public`. Both migrations called them unqualified,
-- which only surfaces where Postgres has to resolve the function
-- immediately: a table's DEFAULT expression (114's `surveys.public_id`,
-- fixed directly in that file since it never successfully applied) and,
-- LATENT until actually called, two SECURITY DEFINER functions in 113
-- that DID already apply to the remote database:
-- `create_event_invites()` and `redeem_event_invite_token()`. Confirmed
-- live via a real `supabase db push` run:
--   ERROR: function gen_random_bytes(integer) does not exist (SQLSTATE 42883)
-- Fix: extend each function's own `SET search_path` to include
-- `extensions` — `ALTER FUNCTION ... SET search_path` changes only that
-- configuration, not the function body, so there is zero risk of
-- retyping either function incorrectly. `create_event_invites` is the
-- one that actually calls gen_random_bytes/digest; `redeem_event_invite_
-- token` doesn't call either directly but is fixed the same way for
-- consistency and because it's the function most likely to be extended
-- to need them later (token re-verification logic).
ALTER FUNCTION public.create_event_invites(text, text[])
  SET search_path = public, extensions;

ALTER FUNCTION public.redeem_event_invite_token(text)
  SET search_path = public, auth, extensions;
