# supabase/drafts — NOT IN THE MIGRATION CHAIN

Nothing in this directory is applied by `supabase db push`, `supabase db reset` or `supabase start`: the CLI reads
`supabase/migrations/*.sql` only (`supabase/config.toml` has `schema_paths = []` and seeds only `./seed.sql`), and the
repo CI (`.github/workflows/playwright.yml`) never touches `supabase/`. File names are prefixed
`DRAFT_NOT_IN_CHAIN_` and carry no timestamp, so even moving one into `migrations/` by accident would not give it a
valid version. To promote a draft: review, get the activation conditions in its header met, then `git mv` it to
`supabase/migrations/<next-timestamp>_<n>_<name>.sql` in its own commit.

Local syntax/RLS check (throwaway container only, never production): `supabase/_localtest/17_rewards_partner_draft_run.sh`.
