# 101 — Web Dynamic Island toasts (dynaura)

**Status: IMPLEMENTED AND RUNTIME-VERIFIED LOCALLY (web). Migration 232 APPLIED to the linked project on
2026-11-20, switch `island_toasts` ON.** The deployed web bundle is not updated yet, so production shows nothing new
until the current code is deployed. Not checked on a real iPhone/Safari/Home Screen or in Xcode yet.

## What it is

A Dynamic-Island-style notification pill for the **web app**, sourced from
[dynaura](https://dynaura.ashutoshswamy.in/) `0.2.2` (MIT, zero dependencies, React 18/19). Installed as a normal
dependency (`package.json`), stylesheet is `dynaura/styles-no-font.css` (the island uses the app's own `--bb-face`,
not the library's Google Font).

**The physical limit, stated plainly:** iOS does not let a web page draw inside the real Dynamic Island. The island
is a native surface owned by iOS (and a true Live Activity needs ActivityKit in a native app, plus push). dynaura
draws a web-native pill in the same place, with the same spring-morph, and banbe positions it over the app column:

- **Safari tab:** top of the page, under the browser chrome. It cannot overlap the physical Island there.
- **Home Screen app:** top of the app. On iOS 26 the page starts below the system status area, so the pill sits just
  below the Island, not inside it.
- **Desktop:** inside the app's 415 px phone frame, under its fake status bar.

The app deliberately still has **no web app manifest / PWA meta** (`index.html`'s comment): adding that markup makes
iOS 26 pick the legacy Home Screen frame with an unpaintable strip at the bottom (WebKit 313800/316008). iOS 26
already opens Home Screen sites as web apps without it.

## Feature switch

`island_toasts` — migration `20261231000232_232_island_toasts_switch.sql`, seeded **OFF**, `OFF_UNLESS_SET` in both
clients. Admin row: Account › Admin › Feature switches › Notifications & retention. iOS shows the row but ignores the
flag (native surfaces are separate).

While ON: `src/App.jsx` mounts one `IslandHost` (the single dynaura `<Toaster>`) and renders `IslandToasts` instead of
the old `ToastStack`. Every proactive in-app notification (`state.toasts`, the existing poll) now rises on the island
one at a time, keeps its existing 8-second clock (`markToastVisible`), opens the same notification on tap, and still
obeys the person's muted kinds. Turning the switch off returns the card stack immediately.

## Styles a person can choose

Account › Notifications › **Dynamic Island toasts** (`/settings/island`, `src/screens/IslandSettings.jsx`), saved per
browser in `localStorage` (`banbe.island.v1`, `src/lib/islandPrefs.js`):

- **8 themes:** Midnight, Warm paper, Frosted, Clay, Deep moss, Plum, High contrast, Mono.
- **Position:** top (default) / bottom.
- **Detail:** full description / title only.
- **Motion:** spring / calm.
- **Swipe to dismiss**, **haptic on show** (Android only; iOS Safari has no `navigator.vibrate`).
- Live preview on every change, plus an explicit “Preview on the island” button.

## Admin demo

Account › Admin › Review & moderation › **Dynamic Island demo** (`/admin/island-toasts`,
`src/screens/AdminIslandDemo.jsx`, `src/lib/islandCases.js`). 23 cases in 7 groups, one tap each, on sample copy and
nothing saved: compact success, confirmation + action, reminder, message, payout, retry/two actions, undo, sticky,
dispute, promise morph, progress, update-in-place, live timer, live wave, ticket card, host card, custom body, avatar
group, typing, long copy, queue, confetti, offline. The demo has its own theme picker (per-toast CSS variables) so an
admin can show a style without changing their saved preference, plus Clear all.

## Files

- `src/lib/islandPrefs.js` — themes, normalization, per-browser store, `islandEnabled`.
- `src/lib/islandNotifications.js` — real notification kind → island state + whether it gets an “Open” button.
- `src/lib/islandCases.js` — the demo's case catalogue (data only).
- `src/lib/useIslandPrefs.js` — `useSyncExternalStore` bridge.
- `src/components/island/IslandHost.jsx` — one Toaster, live theme/position/swipe/haptics.
- `src/components/island/IslandToasts.jsx` — notification queue → island bridge.
- `src/components/island/IslandThemeSwatches.jsx` — shared swatches, static preview, honest-limit note.
- `src/screens/IslandSettings.jsx`, `src/screens/AdminIslandDemo.jsx`.
- `src/index.css` (placement over the app column + desktop frame + frosted variant), `src/main.jsx` (stylesheet).
- `tests/unit/island.test.mjs`.

## Checks actually run

- `npm run test:unit` — **1054/1054 pass**, including `tests/unit/island.test.mjs` and the flag-category parity test.
- `npm run build` — **exit 0**. The only output was pre-existing warnings in `Reserve.jsx`/`Rewards.jsx` and chunk-size
  notices; no build errors.
- **Local runtime pass (2026-11-20):** Chromium/Playwright drove the dev server at `http://localhost:5199` with all
  Supabase REST requests intercepted in the browser. The switch was forced on only through the existing DEV setter
  (`window.__banbeDevSet`). This browser pass itself wrote nothing; migration 232 and the flag change happened
  separately afterwards (see “Applied 2026-11-20”).
  - `/admin/island-toasts`: found **7 groups and exactly 23 case buttons**; fired all 23 one by one. Every case rendered,
    one island/root at a time, no old card stack, no stacked or ghost island after each Clear all. Promise success,
    progress/update late timers, queue, live/sticky and card cases were each waited out after their timers. Per-case
    theme overrides (plum, glass) applied. Console/network clean.
  - `/settings/island`: all **8 style swatches** applied to both the inline preview and the live island (`--dynaura-bg`,
    glass class); content full/title-only; position top/bottom (real bounding boxes); motion calm/spring (root attribute
    and real 320/700 ms duration); haptics on/off (patched `navigator.vibrate` call count); swipe on dismisses and swipe
    off snaps back. Saved `{theme:'plum', position:'bottom', detail:'title', motion:'calm', swipe:false, haptics:false}`
    persisted across a reload and restored both UI and root attributes. Switch off unmounted the island and showed the
    off screen. Console/network clean.
  - Switch on with an app `new_message` toast (not a demo case): island appeared, old stack absent; clicking the title opened Chat,
    loaded the notification's `thread_id=eq.thread-1` messages and PATCHed `notifications?id=eq.click-1`; the toast
    auto-dismissed in **8497 ms**. Switch off: card stack appeared and dismissed; switch on again: island replaced it.
    Console/network clean.
  - Notification poll with a fake user: muted `event_announcement` stayed silent, `payment_confirmed` showed and
    auto-dismissed. Console/network clean.
  - The only error captured was in the temporary test harness, which mocked `get_my_dispute_chats` as `{}` while the
    real RPC returns an array; the Chat screen's `.find` then threw. The harness was corrected; no app error remained.
    The temporary verifiers were removed after the runs and were never part of the unit suite.
  - **Real admin feature-switch row (browser, mocked REST):** opened `/admin/features` → Notifications & retention.
    The `island_toasts` row started OFF and the queued toast rendered in the card stack. Clicking the actual
    `admin-flag-island_toasts-switch` called `admin_set_feature_flag(island_toasts, true)`, the row showed ON, the
    island showed `SWITCH_ROW_TOAST`, and the card stack was gone. Clicking it again called the RPC with `false`, the
    island unmounted, and the card stack returned. Console/network clean.
  - **After applying 232:** `get_feature_flags()` returned `island_toasts: true`; the running app read that linked
    endpoint and its admin row showed ON, with a test toast on the island. The fake-admin session's unrelated REST was
    mocked (a fake authenticated user otherwise gets 401s); the flag endpoint itself was real. Console/network clean.
  - **This browser pass used mocks and wrote nothing.** Migration 232 was applied separately afterwards through the
    linked SQL endpoint; see the 2026-11-20 production log in note 61. The migration was not applied with `db push`
    because the deliberately-held 182–184 would have gone with it.
- Not run: real iPhone Safari/Home Screen visual check, `xcodegen`, Xcode build, or any on-device native check. The
  iOS edits are flag-list/row parity only, required by `tests/unit/featureFlagCategories.test.mjs`.
- Not visually reviewed: the local pass checked DOM behavior, geometry and styles, not screenshots on a physical iPhone.
  Do the iPhone pass in the section above before rollout.

## Applied 2026-11-20

- **Migration 232** (`20261231000232_232_island_toasts_switch.sql`) was executed against the linked project through
  `supabase db query --linked`; its `supabase_migrations.schema_migrations` row was recorded as `232_island_toasts_switch`.
  It was **not** `db push`: that would also have applied the deliberately-held 182–184. Those three are still pending.
- **Switch is ON:** `app_feature_flags.island_toasts = true`, `get_feature_flags()` returns true. The ops update wrote
  an audit row with `admin_id NULL` (there was no admin browser session; it is not an admin-UI change).
- The **deployed web bundle** does not contain the island code yet; deploy the current web code before expecting it in
  production. The local dev app reads the linked project and did show it.
- Rollback if needed: set `island_toasts` false (card stack returns immediately) or run
  `supabase/rollbacks/20261231000232_232_revert_island_toasts_switch.sql` to drop the switch.

## Before/while turning it on

1. On an iPhone: Safari tab, then Share → Add to Home Screen. Check success, warning, error, a card and a live
   activity; check each of the 8 styles; check Reduce Motion and a light/dark app theme.
2. If anything looks off, turn the switch off — the card stack returns with no deployment.

## Known limits

- Not a Live Activity: nothing appears on the Lock Screen, and the real Island's own compact/expanded states are not
  driven. This is a web overlay only.
- The iPhone app ignores the flag and keeps its native notifications.
- haptics is a no-op on iPhone web; the settings row says so.
- dynaura's `linear()` spring is Safari 17.2+; on the project's Safari 16.2 floor the CSS falls back to its bounce
  curve with identical states. `color-mix()` is already part of the 16.2 floor.
- The island is `z-index: 2147483647`, but a native `<dialog>` sheet is in the browser's top layer and paints above
  it; notifications stay behind an open sheet, as the old card stack did.
