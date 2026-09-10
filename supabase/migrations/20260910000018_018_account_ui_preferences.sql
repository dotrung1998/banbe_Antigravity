-- Migration: let language & theme follow the signed-in account, not just the
-- browser. Until now these were kept in localStorage only, so a different
-- device or browser (or a cleared one) always fell back to the defaults —
-- which is what made the choice look like it "resets".
--
-- `prefs_saved` distinguishes "this account has an explicit preference" from
-- "still on the column default": on first sign-in for an account with no
-- saved preference yet, the client pushes up whatever this browser currently
-- has (e.g. just picked during onboarding) instead of silently discarding it;
-- every sign-in after that pulls the saved value down.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS theme text NOT NULL DEFAULT 'light' CHECK (theme IN ('light', 'dark')),
  ADD COLUMN IF NOT EXISTS prefs_saved boolean NOT NULL DEFAULT false;
