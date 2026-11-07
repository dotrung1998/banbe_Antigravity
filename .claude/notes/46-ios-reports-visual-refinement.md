# 46 — iOS Metrics & Reports visual refinement pass (2026-10-18)

Status: IMPLEMENTED LOCALLY (iOS only), NOT committed. Builds on note 43. No backend, RPC, migration or web change. Same single `get_account_kpis` payload. On-device look is still to be checked by the owner on their own iPhone; only a light simulator pass was done here, by request.

## What changed (visual)
- **Hero** (`ReportPrimaryCard`): a warmer, layered surface (`reportHeroCard()`): the field fill with a wash of the screen's own Reports accent (moss, the same as the header icon and Account row), 24pt radius and a soft lift in light mode. The value uses a 46pt scaled rounded font. Under it is a one-line **meaning** (the RPC's own definition), then **daily bars** (`ReportDailyBars`) and a **stat strip** (`ReportSeriesStats`: peak, active days, daily average).
- **Dashboard chart** `ReportDailyBars`: no axes or grid. Every day that reaches the peak value is drawn full-strength (equal heights never look different). Only the first of them, the day the stat strip names, carries the value label. Zero days stay as faint stubs. The first and last day labels sit under the plot. Data is prominent, labels are secondary, and the meaning is visible without interaction (Apple chart guidance).
- **KPI tiles**: title + glyph, a bigger rounded value, one line of meaning, and a sparkline only for a real series with activity. The overview is now a `Grid` (not `LazyVGrid`), so tiles in a row share one height. It drops to one column at accessibility sizes.
- **Needs attention**: a section count badge, a tinted icon tile, a state badge in words, a prominent amount, the message, and an explicit action line ("See overdue claims →"). The surface tint is calm honey for queues (`pending`) and red alert only for overdue/urgent. The leading rule is kept, so state never relies on colour alone.
- **Trend cards**: the same daily bars and stat strip as the hero, plus a glyph and the meaning line.
- **All metrics**: one grouped card with a glyph per row and inset dividers.
- **Range picker**: chips sit in one segmented capsule track. The identifiers are unchanged.
- **Skeleton**: its footprint is resized to match the new layout (hero 300, tiles 150).

## Behaviour fix
Tapping the host **"Refunds overdue"** attention card used to open a details sheet with no rows, because that metric is a bare count. `ReportAttentionItem.opens`/`targetKey` now sends it to `refunds_owed`, whose rows carry the per-claim overdue flag. This only happens when owed rows exist; otherwise the card opens itself and the action reads "Open details". The accessibility identifier is still `reports.attention.refunds_overdue`.

## New pure logic (`Lib/ReportsPresentation.swift`)
- `meaning(_:role:T:)`: one line per (role, key), taken from migration 097's SQL. Unknown keys fall back to "In this range"/"Right now". The payment amount is never called "revenue".
- `symbol(for:)`: a decoration glyph per metric, hidden from VoiceOver.
- `dailyAverageText`: series total ÷ every day in the range (zero days included). "1.7/day", "1,7/ngày", "417K₫/day".
- `attentionAction`: what tapping actually shows.

## Intentionally NOT changed (data truthfulness)
- No deltas, growth badges, targets, benchmarks, readiness scores or AI summaries. There is no prior-period query.
- Point-in-time metrics (saved, upcoming, published, refunds, reviews, disputes, backlog age) are never charted.
- No weekday or weekly grouping. Partial weeks and uneven weekday counts in a 30-day range would distort the bars, and small counts make "busiest day" noise.
- No average-per-seat figure, even though seats and payment amount come from the same CTE. The number would be precise but easy to misread (free events, fees), so it's left to a product decision.
- No check-in-vs-seat ratio. The two use different populations (check-ins of bookings made before the range).
- Admin still shows the backlog **above** the hero (a note 43 decision; the admin's job is the queue). Host and personal follow hero → KPI → attention → breakdown → trends → all metrics.
- **Exports are untouched.** `ReportTrendChart`/`ReportChartView` (detail sheet and the "Save chart image" PNG), the CSV/JSON/PDF writers and `AppState+Reports.swift` were not edited. `ReportsExportGoldenTests` 5/5 still pass.
- Insight cards (share ring and distribution bar) are unchanged apart from inheriting the section spacing.

## Files
- `apps/ios/BanbeApp/Lib/ReportsPresentation.swift`: `opens`/`targetKey`, meaning, symbol, daily average, attention action.
- `apps/ios/BanbeApp/Views/ReportsDashboardComponents.swift`: hero surface, glyph, section count, `ReportDailyBars`, `ReportSeriesStats`, and the hero, KPI, attention and trend cards rewritten; skeleton resized.
- `apps/ios/BanbeApp/Views/ReportsView.swift`: role passed to cards, overview `Grid`, attention opens `targetKey`, grouped "All metrics" card, segmented range track.
- `apps/ios/BanbeAppTests/ReportsPresentationTests.swift`: +3 tests.

## Tests run (iPhone 17e simulator, smallest installed)
- `ReportsPresentationTests` 19/19 (3 new: role-aware meaning + fallback + no "revenue"; daily average EN/VI/money; overdue → owed claims and its bare-count fallback).
- `ReportsExportGoldenTests` 5/5, so exports are byte-identical.
- `ReportsAndOnboardingUITests`: the 5 Reports tests pass (personal, host overdue ordering, admin backlog-first, export menu, loading/error/stale/empty).
- Kept light by request: the full unit and UI suites, the onboarding UI tests, AX5 Dynamic Type and VoiceOver were NOT re-run. Screenshots: a few fixture shots only (see the session). **Owner to check on device:** EN/VI, light/dark, largest text, the peak label not clipping at the top of the bars, and the 2-column tile heights.
