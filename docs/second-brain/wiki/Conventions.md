# Conventions

How this project is built and checked. Mirrors the real scripts — if they change, change this page.

## Web

```bash
npm run dev            # Vite dev server
npm run build          # the one check that always needs to pass
npm run test:unit      # node --test, tests/unit/**/*.test.mjs
npx playwright test tests/public/<spec>.spec.js   # focused browser spec
```

## iOS

```bash
cd apps/ios && xcodegen generate     # after pulling; the .xcodeproj is generated, never committed
```

Unit tests can run on Linux; an Xcode build must be run on a Mac. "Built green for the simulator" ≠ "device-checked".

## Database

- New migration in `supabase/migrations/NNN_description.sql`, plus a rollback when the change is destructive.
- Apply with `supabase db push`; record the date and the result in the owning note **and**
  `.claude/notes/61-retention-run-production-log.md` when it is a production run.
- Never edit an applied migration; write a corrective one (migration 149 → 190 is the cautionary tale).

## Writing style for notes

- Sentence case titles that state the conclusion, not the topic.
- Dates `YYYY-MM-DD`; separate "what changed" from "what is verified".
- Keep the project's own status vocabulary: IMPLEMENTED LOCALLY / committed / pushed / APPLIED / device-verified.

## The checks that are easy to skip

- A web visual change you did not look at is unverified — say so.
- Playwright specs that already failed on the base commit stay listed as pre-existing, not "fixed".
- Payments, refunds and admin roles: read the note before touching the code. `02`, `16`, `54`, `76` are the landmines.
