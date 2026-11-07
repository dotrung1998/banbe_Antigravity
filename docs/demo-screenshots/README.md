# Banbe iOS Screenshot Catalog

Generated: 2026-09-23T17:07:46Z

Simulator: **banbe-screenshot-catalog**, iOS **27.0**

Regenerate with:

```
bash scripts/capture_ios_catalog.sh
```

## 01-onboarding-auth

| Screenshot | Screen/state | Role | Note |
|---|---|---|---|
| ![Splash](01-onboarding-auth/01-splash.png) `01-splash.png` | Splash | goer | First launch mark/wordmark before onboarding starts. |
| ![Language picker](01-onboarding-auth/02-language-pick.png) `02-language-pick.png` | Language picker | goer | First onboarding step — Vietnamese/English. |
| ![Theme picker](01-onboarding-auth/03-theme-pick.png) `03-theme-pick.png` | Theme picker | goer | Second onboarding step — light/dark. |
| ![Account, freshly signed in](01-onboarding-auth/05-account-after-onboarding.png) `05-account-after-onboarding.png` | Account, freshly signed in | goer | First Account view right after onboarding/login completes. |

## 02-home-discovery

| Screenshot | Screen/state | Role | Note |
|---|---|---|---|
| ![Home feed](02-home-discovery/01-home-feed.png) `01-home-feed.png` | Home feed | goer | The event catalogue, default area/filter. |
| ![Home, category filter applied](02-home-discovery/02-home-filters.png) `02-home-filters.png` | Home, category filter applied | goer | Music-only filter narrowing the feed. |
| ![Going](02-home-discovery/03-going-list.png) `03-going-list.png` | Going | goer | Events the account is currently attending. |
| ![Saved](02-home-discovery/04-saved-list.png) `04-saved-list.png` | Saved | goer | Events the account has favorited. |
| ![Completed events](02-home-discovery/05-completed-list.png) `05-completed-list.png` | Completed events | goer | Events that have already ended. |
| ![Event Detail](02-home-discovery/06-event-detail.png) `06-event-detail.png` | Event Detail | goer | Reached from Home — includes the "Open in map" action. |
| ![Event Detail → Map Explore](02-home-discovery/07-event-detail-open-in-map.png) `07-event-detail-open-in-map.png` | Event Detail → Map Explore | goer | Landing on Map Explore centered on the event just viewed. |
| ![Map Explore, event card](02-home-discovery/08-map-explore-event-sheet.png) `08-map-explore-event-sheet.png` | Map Explore, event card | goer | The selected-pin info card/sheet. |

## 04-messaging

| Screenshot | Screen/state | Role | Note |
|---|---|---|---|
| ![Inbox](04-messaging/01-inbox.png) `01-inbox.png` | Inbox | goer | Conversation list — whatever mix of read/unread the account currently has. |
| ![Inbox, Archived](04-messaging/02-inbox-archived.png) `02-inbox-archived.png` | Inbox, Archived | goer | The archived-conversations view. |
| ![Chat thread](04-messaging/03-chat-thread.png) `03-chat-thread.png` | Chat thread | goer | An open conversation. |
| ![Chat, image attachment](04-messaging/06-chat-image-attachment.png) `06-chat-image-attachment.png` | Chat, image attachment | goer | A photo message inline in the thread. |

## 05-notifications

| Screenshot | Screen/state | Role | Note |
|---|---|---|---|
| ![Notification list](05-notifications/01-list.png) `01-list.png` | Notification list | goer | Whatever notifications currently exist for the account. |
| ![Notifications, search](05-notifications/02-search.png) `02-search.png` | Notifications, search | goer | The search field open, matching Inbox's own control. |
| ![Notifications, selection mode](05-notifications/03-selection-mode.png) `03-selection-mode.png` | Notifications, selection mode | goer | Select all / Cancel controls active. |

## 07-organizer

| Screenshot | Screen/state | Role | Note |
|---|---|---|---|
| ![Verification queue](07-organizer/01-verification-queue.png) `01-verification-queue.png` | Verification queue | host | Bookings awaiting payment verification. |

## 08-account-settings

| Screenshot | Screen/state | Role | Note |
|---|---|---|---|
| ![Account](08-account-settings/01-account.png) `01-account.png` | Account | goer | Signed-in Account screen. |
| ![App preferences](08-account-settings/02-app-preferences.png) `02-app-preferences.png` | App preferences | goer | Language + theme, renamed from "Language & appearance". |
| ![Receipts](08-account-settings/03-documents-receipts.png) `03-documents-receipts.png` | Receipts | goer | The guest's own receipts. |
| ![Security](08-account-settings/04-security.png) `04-security.png` | Security | goer | Account security settings. |

## Not captured yet

- **03-booking-payment — Reserve flow, holding a seat, payment details/transfer, awaiting verification, confirmed ticket/QR, cancelled/declined booking**: Every state in this group requires actually reserving/paying for a real seat on the shared fast-suite test account. That would mutate shared fixture state other existing UI/Playwright suites depend on, which this ticket's "do not alter production data" rules out, and there is no read-only path to reach these states.
- **07-organizer — Organizer dashboard, Check-in/Attendance**: Only reachable through DashboardView.swift/AttendanceView's own entry point on the Dashboard, which was outside this ticket's allowed read scope — no verified stable accessibility-identifier path exists to them from Account.
- **07-organizer — Refund queue**: No refund-queue screen or accessibility identifier was found within this ticket's read scope; not implemented as a reachable flow here.
- **— — Any state gated on the shared test account's CURRENT data (an unread thread, an active story, a chat image attachment, a non-empty notification list, organizer enrollment)**: Captured opportunistically when ScreenshotCatalogTests.swift ran — if that state did not exist on the account at run time, the flow was skipped (see this run's xcresult for the exact SKIPPED activity note) rather than faked. Re-run the suite after that state exists on the account to pick it up.

> Screenshots are produced by `BanbeAppUITests/ScreenshotCatalogTests.swift` running against deterministic onboarding fixtures (Groups A/B) and, for anything requiring a signed-in session, the same dedicated shared test account (`doqanh0906+banbe-fast-suite-shared@gmail.com`) `EventDetailOpenInMapUITests`/`MapExploreSelectionUITests` already use — never live production user data.
