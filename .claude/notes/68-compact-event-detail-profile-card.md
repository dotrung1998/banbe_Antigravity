# 68 — Compact Event Detail + profile identity card (web + iOS)

Status: IMPLEMENTED (web + iOS), 2026-10-31. No migration. Not device-verified; checked in the iOS simulator (iPhone 17
Pro, light + dark) and in Chromium at 390×844 (light + dark).

## Why
An on-device review (dark mode) found both screens loose: Event Detail repeated the host, had tall uneven tiles, drew a
"full" clay bar at 0 seats, listed type facts as bare rows, used gaps from 4 to 32 (the code comment claimed 28), and put
the ticket code on the CTA line. The personal profile left half the screen empty, showed "Admin" twice, and centred a
narrow column on a flat palette fill.

## Shared scale
- Spacing: web `SPACE` (`src/theme.js`) ⇄ iOS `BanbeTheme.Space` = 4 / 8 / 12 / 16 / 24. Sections are 24 apart and
  8–12 inside.
- Type on both screens:
  - 26 display: title, price, name.
  - 17 semibold: section heads, host name, stat values.
  - 15: body and values.
  - 13: labels and meta.
- On iOS, Dynamic Type styles carry the type scale (`.subheadline` / `.footnote` / `.headline`).

## Event Detail (`src/screens/EventDetail.jsx`, `Views/EventDetailView.swift`)
Pure rules live in `src/lib/eventDetailPresentation.js` ⇄ `Lib/EventDetailPresentation.swift`. The shared fixture is
`tests/fixtures/event-detail-presentation.json`.

- **Host once.** The track-record line (`event-track-record` / `event.trackRecord`) is gone. The old Host card is now one
  row:
  - 40pt avatar, name (wraps to two lines), "Joined 2026 · 1 event" and a chevron.
  - The whole row opens the host profile (`event-organizer-row` / `event.organizer`).
  - A 44pt Message icon button sits beside it (`organizer-message` / `event.messageHost`).
  - The "View profile" text button is gone. Web keeps `event-organizer-profile` on the chevron; iOS `event.viewProfile`
    is retired (no test used it).
- **Header.**
  - Pills: category, then minimum age as an outlined pill (`event-type-fact-min_age` / `event.typeFact.min_age`), then
    invite-only.
  - Next come the title and calendar pill.
  - Then price on the left with one status pill on the right (`event-seat-status` / `event.seatStatus`).
- **Seat status (`seatStatus`).**
  - "You're going" when the viewer holds a ticket (bar state `ticket`).
  - "Sold out" when sold out, and also when 0 seats are left but the row isn't marked sold out yet. This used to show a
    100% clay bar.
  - "N left": honey when ≤ 20% of capacity (never above 2 seats for tiny tables), otherwise neutral.
  - The 4pt bar shows only for open/few, and is clay only when few.
- **Tiles.** Value first, label under it, `surface2` fill (= the light `block`), no hairline, equal heights.
  - iOS used to put the venue-time note inside the time tile, which made every tile taller. The note is now one quiet
    line under the row on both platforms.
  - iOS also ported web's `viewerTimeNote` (`SchedulePresentation.viewerTimeNote`). The old iOS note repeated the
    venue time the tile already showed.
  - iOS gained the `event.fact.where` id, which it never had.
  - At accessibility sizes the tiles stack one per row (`ViewThatFits`).
- **Type facts (`splitFacts`).**
  - Alcohol and dietary become icon chips.
  - Per-type facts (lineup, artists, brands…) become an aligned label/value grid.
  - Required alcohol and minimum age always show for all 5 types (unit-tested).
- **About (`aboutSection`).**
  - The description (else the intro's first paragraph) is clamped to 3 lines. "Read more" expands it in place, because
    the sheet never showed the description.
  - The included line follows.
  - "More ›" on the heading opens the About & Included sheet; `event-included-section` / `event.includedSection` stays
    on that heading.
  - Never a heading with nothing under it. That was the old intro-only empty block; iOS also treated `intro == ""` as an
    intro.
- **Ticket CTA.** "View your ticket" with "Code X" as a quiet second line.
  - Web: `event-ticket-code`.
  - iOS: new `InkButton(subtitle:)`.
- **Hero.** Height is 320 (was 400) on both platforms, so Date/Time/Place, the Host row and the CTA fit a 6.1" phone.
  The zoom/close regression UI tests (note 47) still pass.

## Profile (`src/screens/PublicProfile.jsx`, `Views/PublicProfileView.swift`)
Pure rules live in `src/lib/profileCard.js` ⇄ `Lib/ProfileCard.swift`. The shared fixture is
`tests/fixtures/profile-card.json`.

- **"Admin, Admin" root cause.** This was data, not code: `banbetestadmin`'s `profiles.interests` is
  `["Admin","Admin"]`. `dedupeChips` drops repeats (case- and space-insensitive) and anything already on the card (the
  role, the bio, the name). The DB row was not changed.
- **No role in `get_public_profile`.** The public page never shows the admin role. `roleLabel` gives "Host · Founder of
  {org}" while organizer mode is on, else "Member". It is one line, with no separate chip.
- **Card.** Left-aligned and full width with a 16pt gutter.
  - 80pt avatar: a clay→gold (`attn`) ring around the 72pt photo.
  - The name at 26 wraps and never truncates. Then the role, then `@handle · city`, then the bio.
  - The stats strip sits inside the card with hairlines.
- **Surface.** `surface2`, plus the person's `profile_theme` colour at 18%, plus a clay glow at 10% in the charm corner,
  plus a 1px fg@6% inner hairline.
  - The old fill was the palette at 80→30%, where ink text on the "ink" palette failed contrast.
  - `profileCard.test.mjs` checks ink and ink2 for ≥ 4.5:1 on every palette × theme. ink3 fails on the dark tint (~3.8),
    so card secondary text is ink2.
  - iOS `ProfilePalette` now uses the exact web hex values.
- **Charm.** The owner's chosen anchor and size are respected.
  - Web reserves the text column via `KeychainFrame`'s `reserveRight`.
  - iOS uses `.leading` layout with outset 20 (gutter on the charm side).
  - Reduce Motion and the VoiceOver label are unchanged (the existing implementation).
- **Stats (`profileStats`, hidden when there are fewer than 2).**
  - A host shows Hosted + Followers (public `get_public_profile` data), then Badges for the owner while the `rewards`
    switch is on, else Since (`hosting_since_year`).
  - A member who owns the profile sees Upcoming + Badges.
  - A member visitor sees no strip. There is no public data, so a "Joined" or attended count would need a migration (not
    done).
- **Owner actions.** QR, Edit profile and Edit charm are equal 44pt pills outside the card. Visitors get QR only. Back and
  Share are now 44pt and Back has an id (`public-profile-back` / `publicProfile.back`).
- **Below the card, 24 apart.**
  - About: long intro + social links. These moved out of the card.
  - Interests & teams: de-duplicated chips + team badges.
  - Upcoming (`upcomingEvents`): the person's own hosted events still ahead (public), plus, for the owner only, the
    events they're going to. A visitor never sees bookings. The owner's empty state is "Nothing coming up yet ·
    Browse events ›".
  - Then credited events.
- **Share image unchanged.** The shared image is the separate 340×520 `ProfileShareCard` (canvas / ImageRenderer) and
  never included this on-screen card, so it is untouched.
- **Known gaps.**
  - A visitor's view of a member with little content still ends early: there is nothing more to show without new data.
  - The iOS glow is always top-trailing; web follows the charm side.

## Tests
- **Unit:**
  - `tests/unit/eventDetailPresentation.test.mjs` ⇄ `BanbeAppTests/EventDetailPresentationTests.swift`. Includes the
    regression "0 left but not sold out ⇒ sold out, no bar".
  - `tests/unit/profileCard.test.mjs` ⇄ `BanbeAppTests/ProfileCardTests.swift`. Includes the regression "Admin, Admin ⇒
    one chip", contrast, and palette parity.
- **Web e2e:** `tests/event-detail-compact.spec.js` and `tests/public-profile-card.spec.js`, both 390×844, light + dark.
  - They run signed OUT through the new `guestToHome` helper in `tests/helpers.js`, because the shared signed-in test
    account is held at the DOB account gate (`setupToHome` times out).
  - The profile spec uses `/u/banbetestadmin` via client-side navigation.
- **iOS UI:**
  - `EventDetailCompactUITests` (`shell.event`).
  - `PublicProfileCardUITests` (new DEBUG fixture `shell.publicProfile`, synthetic own host profile).
  - `EventTypesUITests.testEventDetailFactsPerType`, `ReviewRetentionUITests` and the ShellFixture zoom/close tests
    still pass.
- **Pre-existing failures, not from this work:**
  - `NavigationUITests.testFeedOpensAnEventAndComesBack` and `testEventOpensTheOrganizerPage` fail in `launchToHome`.
    A signed-out launch now lands on the guest Welcome screen (notes 44/49), not `screen.home`.
  - The web `event-detail-intro-included.spec.js` fails at `setupToHome` (the DOB gate).
- **Run `xcodegen generate` after pulling.** There are new Swift files.
