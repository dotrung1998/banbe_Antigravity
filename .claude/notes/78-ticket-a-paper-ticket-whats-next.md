# 78 — Paper ticket, What's next strip, stub pager with tear, Event details sheet (2026-11-05)

Status: IMPLEMENTED (web + iOS), committed 7063475. Web: Playwright `tests/ticket-redesign.spec.js` green on chromium (43/43), webkit green after the last fixes (sheet group re-run 10/10; the full file once 42/43 before the Tab-trap fix), `npm run test:unit` green. iOS: `ConfirmedTicketUITests` 13/13, `TicketStatusTests` / `TicketCopyTests` / `DesignTokensTests` green. NOT device-checked (haptics, VoiceOver, real scans). No migration, no feature switch.

Visual reference only: `docs/prototypes/banbe_ticket_A_whatsnext_v2.html` (Ticket A + "What's next" v2). Nothing was copied from its code.

## What the screen is now
- One paper ticket: status header (wordmark + one-word status), the strip, event name + Date/Time/Area tiles, a perforation (two page-colour notches + dashed rule), and the stub (QR 200px on a 220px white box, 3-3 entry code in monospace).
- Tapping the event name or the "View event ›" pill opens the Event details sheet. "Open full event page" goes to Event Detail; its Back pill reads "Ticket" and returns to this same ticket (not Home).
- Action tiles (Wallet/PDF + Calendar), More options and the Gift/Wallet/receipt logic are note 77's, unchanged. The policy paragraph ("banbe does not collect money…") is word-for-word the old one, only collapsed under the actions ("About money and refunds"); still hidden for an expired hold.
- Removed on both platforms: the hold/verify countdown cards, "What happens next", the disputed and expired cards (their content is the strip), the "Your ticket is ready / You're in" celebration card, the loading-animation filler, the old "Next" block (place, Directions, host note now live in the sheet), the per-row attendee cards and "Download selected".

## The 9 strip cases (first match wins)
Shared rule `ticketCase` (web `src/lib/ticketStatus.js`, iOS `Lib/TicketStatus.swift`, vectors `tests/fixtures/ticket-status.json`). The caller derives `isPaid` / `checkedIn` / `daysUntil` with the existing helpers.

| # | key | Condition | Tone | QR | Tail | Link (existing action only) |
|---|---|---|---|---|---|---|
| 1 | cancelled | event cancelled, or booking `payment_state`/`status` cancelled | alert | void | – | Track refund (only if a refund claim exists; `loadMyRefunds` on demand) |
| 2 | expired | `payment_state` expired (or booking status expired) | alert | void | – | Reserve again |
| 3 | review | `disputed` | honey | lock | – | – |
| 4 | holding | `holding` | honey | lock | hold countdown | See payment details |
| 5 | awaiting | `pending_verification` | plum | lock | verify countdown (not when overdue) | Message host |
| 6 | ended | paid and `endedHoursAgo != null` | ink3 | past | – | View receipt (if one exists) |
| 7 | checkedIn | paid and checked in | moss, solid | in | – | View receipt (if one exists) |
| 8 | today | paid, 0 days in the venue zone | clay | ok | Nh / Nm to start | Directions |
| 9 | upcoming | paid, otherwise | mist | ok | – | Add to calendar |

Copy is the owner-approved table (2026-11-05): `src/lib/ticketCopy.js` ⇄ `Lib/TicketCopy.swift`, checked against `tests/fixtures/ticket-copy.json` (generated from the web module) by `tests/unit/ticketCopy.test.mjs` and `TicketCopyTests.swift`. Change copy in the JS, regenerate the fixture, port to Swift.
- "This booking was cancelled" (booking cancelled on a live event) does NOT carry the host-refund sentence; only "This event was cancelled" does.
- Awaiting host: the typical-wait text goes in the expanded area (too long for the tail); omitted when not loaded.

### Data gaps (nothing invented)
- No doors-open time on any platform → the mockup's "Doors open" case was dropped, and "arrive by 19:45", "doors open from 17:00", "code valid 24h after start", "replies within an hour", "no countdown while awaiting" were not carried over.
- Check-in time exists only per named ticket (`booking_attendees.checked_in_at`), so the checked-in strip shows no time.
- No client flag for a removed event (admin flow already hides it).

## QR safety rule
`lock`, `void` and `past` NEVER receive the admission token: a fixed decorative pattern (same LCG seed on web and iOS, not derived from any booking) blurred 6px at 35% opacity, a status label ("QR unlocks when the host confirms" / "Ended" / "Ticket void") and the code masked as `••• •••`. Only `ok` and `in` draw the real QR (`in` dimmed under a check). `ticketQrShowsToken`. Display only: check-in RPC, polling, gift, Wallet and receipt are untouched. An unmapped state is treated as void.

## Tokens
- One new colour: `plum` (awaiting host), light `#6B4E7C` / dark `#BBA2D0` (`--bb-plum`, `theme.js plum`, `Palette.plum`). `mist` = existing `--bb-question`, `moss` = existing `--bb-update` (aliases in `theme.js`; `Palette.question` / `.update` added on iOS with the same hex). Neutral = `ink3`. No `plumBg`: the tint is the tone at 13% over `block`.
- Contrast (measured, WCAG): tone text on its own 13% tint over block FAILS 4.5:1 in light for clay 3.70, honey 3.84, ink3 4.11, mist 4.15, moss 4.25 (alert 4.61, plum 4.78 pass; dark all ≥ 4.61). So ALL strip text is `ink` (≥ 11.9:1 on every tint) and the tone only paints the icon disc, the tint and the status dot. Disc vs tint ≥ 3.70, paper glyph on disc ≥ 4.81. Enforced by `designTokens.test.mjs` / `DesignTokensTests` through `stripTones` / `stripContrast` in `tests/fixtures/design-tokens.json`.

## Named tickets (migration 151)
- Swipe pager of stubs (scroll-snap on web, `scrollTargetBehavior(.paging)` on iOS) with dots, "n/m" and arrow keys (web). One stub for a single named ticket, no dots.
- Tear: only on a not-scanned → scanned change of a ticket already known as open, seen while the screen is open (never on load). The stub drops 12px and tilts -3.5° (0.16s), settles at 6px / -1.5° / 60% opacity with a zigzag top edge, stays visible, then the pager moves to the next unscanned ticket (~0.6s). Reduced Motion: opacity only, instant move. iOS adds a success haptic and a VoiceOver announcement.
- Per-ticket PDF and Download all moved into More options (`Download this ticket` follows the stub being shown).
- Checked in means ALL named tickets scanned (strip stays pre-check-in after the first scan; the QR of a scanned stub shows ✓). Single tickets keep the old rule exactly.
- Door poll: `doorWatchOpen` (`ticketStatus.js` / `TicketStatus.swift`, 14 shared vectors). Window is strictly start−3h … start+12h; named tickets poll while any is unscanned, stop when all are scanned, and stop at the window's end inside the tick (single tickets: unchanged). KNOWN: no end-to-end test can isolate the in-tick window check (the screen's other 6s polls re-render it and end the poll first); the rule itself is mutation-tested.

## Event details sheet
Web `src/screens/sheets/EventDetailsSheet.jsx`, iOS `Views/EventDetailsSheet.swift`. Real data only: cover (none → not drawn), title, Date/Time/Place tiles, About (`aboutSection`), Included chips, Host card + message button, Location (precise address + host note for a PAID ticket only, as before) + Directions, the existing refund paragraph. Distance only when located and ≤ 50 km. Sections without data are not drawn (test with a bare event). Web: dialog role, focus into the sheet and back to the clicked control (Safari does not focus a button on click), Tab cycled manually (WebKit's Tab skips buttons), Escape/scrim/close, Reduced Motion fades. iOS: `.sheet` with `.large` detent; its two actions run in `onDismiss` so navigation never races the dismissal. Message host → chat whose Back returns to the ticket (`chatBack == confirmed`; web `chatBackFn`, iOS `resolveChatBackTarget`), chat and Event Detail label it "Ticket".

## Files
- Shared: `ticketStatus.js`/`TicketStatus.swift`, `ticketCopy.js`/`TicketCopy.swift`, fixtures `ticket-status.json`, `ticket-copy.json`, `design-tokens.json` (plum, stripTones).
- Web: `src/screens/Confirmed.jsx`, `src/components/ticket/{PaperTicket,WhatsNextStrip,TicketQr,QrCode,TicketStubPager}.jsx`, `src/screens/sheets/EventDetailsSheet.jsx`, `EventDetail.jsx` (back label), `Chat.jsx` + `BanBeContext.jsx` (`chatBackFn`), `theme.js`, `index.css` (plum, `bbTear`, `.bb-snap`).
- iOS: `Views/ConfirmedView.swift`, `Views/Ticket/{PaperTicketView,WhatsNextStrip,TicketQrView,TicketStubPager}.swift`, `Views/EventDetailsSheet.swift`, `EventDetailView` / `MessagingViews` (back labels), `Components.swift` (`QRCodeImage.padding`), `BanbeTheme.swift`, `AppState+Data` (chat back target, fixture guard), `AppState+Payments` (fixture guard), `UITestFixtures.swift`. Run `xcodegen generate` after pulling.
- Tests: web `tests/ticket-redesign.spec.js` (first coverage of this screen; dev state setter + a mocked `booking_attendees`), `tests/unit/{ticketStatus,ticketCopy,designTokens}.test.mjs`; iOS `TicketStatusTests`, `TicketCopyTests`, `DesignTokensTests`, `ConfirmedTicketUITests`.

## Test ids
- Web: `confirmed-strip` (`data-case`) + `-toggle/-heading/-detail/-link/-panel`, `confirmed-status`, `confirmed-ticket`, `confirmed-ticket-title`, `confirmed-tile-date|time|area`, `ticket-qr` (`data-qr-mode`) + `-real/-placeholder/-label`, `confirmed-entry-code`, `confirmed-stub-pager`, `confirmed-stub-<n>` (`data-torn`, `data-tearing`) + `-dot-/-badge-/-name-<n>`, `confirmed-open-details`, `confirmed-view-event`, `confirmed-policy-toggle|text`, `confirmed-download-current|all`, `event-details-*`. Kept: `confirmed-pay`, `confirmed-more-button`, `confirmed-add-to-wallet|calendar`, `confirmed-hold-countdown`/`-verify-countdown` (now on the strip tail). Gone: `confirmed-what-next`, `-disputed`, `-expired-reserve` (the strip link is `confirmed-strip-link`), `-next`, `-directions`, `-host-note`, `-typical-wait`, per-row `confirmed-attendee-*`, `confirmed-download-selected`, `confirmed-ticket-reveal`, `confirmed-checkin-moment`.
- iOS: `confirmed.strip` + `.strip.toggle/.heading/.detail/.link`, `confirmed.status`, `confirmed.ticket`, `confirmed.tile.<id>`, `confirmed.openDetails`, `confirmed.viewEvent`, `ticket.qr` + `.real/.placeholder/.label`, `confirmed.entryCode`, `confirmed.stubPager`, `confirmed.stub.<n>` + `.dot/.badge/.name.<n>`, `confirmed.policyToggle|Text`, `confirmed.downloadCurrent|All`, `eventDetails.*`. Fixture: `-uiFixture shell.confirmed` with `-uiFixtureTicket <case>`, `-uiFixtureAttendees N`, `-uiFixtureScanned N`, `-uiFixtureScanAfter <s>` (simulated door scans).

## Gotchas
- SwiftUI: a container's `.accessibilityIdentifier` masks its children's ids unless it is its own element first (`.accessibilityElement(children: .contain)` BEFORE the identifier). Cost three red UI-test runs.
- Playwright: setting `eventKey` makes the app refetch the event's real row and the user's booking, which overwrite injected state ~300ms later; the spec sets the key first, waits for both responses, then injects. A slow attendee answer can also land after a simulated scan (the spec waits for none in flight). `page.clock.setFixedTime` pins `Date` only; `install()` also fakes `requestAnimationFrame`, which Playwright's stable-element check needs. `original_booking_id=eq.b-78` contains the substring `id=eq.b-78`.
- At accessibility text sizes the pinned action area took over a third of the screen: it now scrolls with the ticket there, tiles stack, the pill drops under the label (capped at accessibility1).

## Not verified / open
- Device: haptics, VoiceOver, real door scans, real Wallet, light/dark on hardware. Dynamic Type AX XXXL was checked on the simulator only.
- iOS door poll over time is not observable in a UI test; the shared `doorWatchOpen` vectors cover its rule.
- `NavigationUITests` (8 of 10) and `EventDetailCompactUITests` (3) fail on a clean HEAD too (live-backend / pre-existing). `NavigationUITests.testEventOpensTheOrganizerPage` passed once on clean HEAD and failed 3/3 on this branch with "card.bepnho not found" (it taps Home's card with no wait); the clean-HEAD re-runs were not finished, so it is UNPROVEN whether this is flakiness or caused by this work. `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` also fails (banbe.app links), untouched here.
- Existing quirks left alone: `openHeld` / `goReserveConfirmed` do not set `confirmedBack` (a stale back target can leak); a cold load of `/ticket` still goes to Home; the strip's calendar link on web scrolls to the calendar tile whose popover it opens.
- A check-in that happens outside the door window will not animate live (no poll).
