# Rewards Phase 0 — manual UI checks (web + iOS)

Run these against a LOCAL or STAGING backend that has migration 177 applied (never production before the release
plan says so). Use a test account that has passed the account gate (phone + DOB).

Path (web): sign in → **Account** → **Rewards & badges** (`/profile/rewards`). Path (iOS): **Account** tab → **Phần thưởng & huy hiệu / Rewards & badges**.
Also reachable from the Home header streak/coin capsule.

## A. Time-zone picker (needs migration 177)

| # | Action | Expected |
|---|---|---|
| A1 | Open Rewards with a brand-new account | Section "Múi giờ cho chuỗi ngày / Time zone for streak days" sits above "How earning works". Picker shows **Việt Nam (UTC+7)**; caption "Defaults to Vietnam time…". Nothing was auto-assigned (no row in `reward_user_settings`). |
| A2 | Device set to a US zone (e.g. America/Chicago) and open the picker | That entry is labelled "(suggested from your device)". It is NOT selected. |
| A3 | Choose **US – Eastern** | Picker shows Eastern; caption "The change to America/New_York takes effect from the next day." Streak number and "Today's counted" unchanged. "How earning works" still names `Asia/Ho_Chi_Minh` until the next day. |
| A4 | Choose Vietnam again before the next day | Pending change cancelled, caption back to default, and a later change is still allowed (cancel is free). |
| A5 | Pick Eastern, then Pacific (before it takes effect) | Replaces the request; counts as one change. |
| A6 | After it takes effect (next local day), reopen | Streak line says "Days and months follow the America/New_York time zone"; picker shows Eastern; streak not reset. |
| A7 | Make 2 effective changes within 30 days, then try a 3rd | Picker is disabled (or, if forced, error "You changed your time zone twice in the last 30 days"). No change stored. |
| A8 | Switch language VI ↔ EN | All new strings translate; no raw keys. |
| A9 | Airplane mode, change zone | Error "Network error. Nothing was changed."; picker returns to the old value after reload. |
| A10 | Sign out / sign in as another account | The other account sees its own zone; no flash of the previous account's zone. |

## B. "Old" Rewards must still work (no regression)

| # | Action | Expected |
|---|---|---|
| B1 | Against a server WITHOUT 177 (e.g. old local DB at 176): open Rewards | Page loads; the time-zone section is **absent**; no error banner; balance, streak, badges, history, catalog, rules all render as before. |
| B2 | Home header | 🔥 streak and coin buttons show the same numbers as the Rewards page. |
| B3 | Redeem an affordable item (needs coins) | Confirmation dialog → success "Unlocked!"; balance drops by the price once; "Use" appears; repeating/double-tapping never charges twice. |
| B4 | Item you cannot afford | Disabled with "N more needed". |
| B5 | Save an event (heart) on a fresh favourite | Streak shows 1 / "Today's counted"; saving again the same day changes nothing. |
| B6 | Existing user with prior streak/coins (legacy rows) | Numbers identical before and after 177 is applied; "attendance cap this month" count unchanged. |
| B7 | Old installed iOS build against a server WITH 177 | Rewards screen works; the build ignores the extra `timezone_settings` key; no time-zone section (expected: the section only exists in the new build). |
| B8 | Old cached web bundle against a server WITH 177 | Same as B7. |

## C. Not covered by automated tests (do these on a real device)
Picker rendering/layout on small phones and dark mode, VoiceOver label of the picker, Dynamic Type at largest size, iOS menu picker dismissal, and the real midnight rollover in a non-VN zone.
