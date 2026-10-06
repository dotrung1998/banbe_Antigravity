# URL routing (browser back/forward + deep links) (2026-10-06)

## Status: WORKING (web); iOS n/a. Not committed.

The SPA still keeps its screen in `state.screen`; `src/lib/routes.js` (table) + `src/lib/useUrlSync.js` (hook, called from `Shell` in `App.jsx`) mirror it to the address bar both ways.

- **Every screen in `SCREENS` has a path**, e.g. `/map`, `/inbox`, `/profile`, `/event/<key>`, `/event/<key>/organizer`, `/u/<handle>`, `/org/<id>`, `/surveys/<id>`, `/host/dashboard`, `/refunds`, `/policy`. Id-bearing screens carry the id as a segment.
- **state -> URL**: `pushState` on screen/param change; `replaceState` while onboarding or when the guest guard bounces to `/login`, so Back doesn't trap.
- **Back/forward**: `popstate` -> `pathToRoute()` -> screen (via the existing opener, e.g. `openPublicProfile`, when data must be fetched).
- **Cold load on a deep link**: held (URL untouched) through splash/onboarding/login, applied once on Home with a session (`/policy` also applies signed-out). `/u`, `/org`, `/surveys`, `?org=` are skipped: BanBeContext's own shared-link boot code already handles them.
- **Screens that can't be rebuilt from a URL alone** (`reserve`, `chat`, `confirmed`, `refunded`, `documentView`, `attendance`) have a `needs`/`parent`: if their in-memory state is gone they fall back to the parent path (event, organizer, home, documents, dashboard).
- `/privacy` and `/data-deletion` stay standalone (`main.jsx`), outside the app shell.
- Verified with ad-hoc Playwright (deep link, popstate, back); the existing fast suite already failed on `main` before this change (Home never reached), so it couldn't be used as a regression check.
