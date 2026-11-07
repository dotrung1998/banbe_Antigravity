-- Task 1 (mandatory login + consent): proof of consent per user, matching
-- banbe_User_Policy.md's B1/B3 PDPL consent requirement. Two plain nullable
-- columns — no new RLS needed, `profiles_update_own`
-- (20260906000001_001_core_schema.sql:111) already scopes a self-UPDATE to
-- `auth.uid() = id`, which is all writing these needs.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS policy_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS policy_version text;
