# D1 + Better Auth spike

Local-only proof for the migration assessment in
`docs/cloudflare-d1-better-auth-migration.md`. It is **not** wired into banbe:
production still uses Supabase Auth/RLS/RPC and iOS still talks to Supabase.

What it proves, on the real Workers runtime (`workerd`) and a local D1 database:

- Better Auth 1.7 stores users, sessions and password hashes in D1 through the
  native `database: env.DB` binding.
- The session is read on every tenant request with
  `auth.api.getSession({ headers })`; `session.user.id` is the only user id used
  in SQL. D1 has no RLS, so this is the pattern every ported query must follow.
- Two accounts cannot list or delete each other's rows, and a SQL-injection
  string is stored as text (the query uses `bind()` placeholders).
- Sign-out invalidates the session server-side.

## Commands

```bash
npm run cf:auth:migrate   # applies migrations 0001/0002 to the LOCAL D1
npm run cf:auth:verify    # starts wrangler dev, runs both accounts, stops it
```

For manual exploration:

```bash
npx wrangler dev \
  --config cloudflare/auth-spike/wrangler.jsonc \
  --local --ip 127.0.0.1 --port 8788 \
  --var BETTER_AUTH_SECRET:dev-only-32-character-secret-change-me
```

`BETTER_AUTH_SECRET` must be at least 32 characters. Never put a real secret in
`wrangler.jsonc`; in a deployed Worker use `wrangler secret put`.

## Deploying this spike (not done)

1. `wrangler d1 create banbe-auth-spike` and replace the placeholder
   `database_id`.
2. Set `BETTER_AUTH_URL` to the Worker origin.
3. `wrangler secret put BETTER_AUTH_SECRET`.
4. Apply migrations with `--remote`, then deploy.

Do not point a real banbe domain at this Worker. It has no banbe tables, no
bookings/payments, no RLS/RPC parity and no iOS client.
