---
tags: [code-graph]
---
# Code map — open this before grepping the repo

> Generated from `graphify-out/graph.json` (graph written 2026-11-27 13:08 UTC · repo HEAD `a2f15119` · graphify base commit `a2f15119`): **17,009 symbols**, 44,294 edges, 26 areas. Do not hand-edit — run `node scripts/second-brain-code-graph.mjs`
>
> **Fresh:** the graph was written after the current HEAD commit, so it includes the committed code.

## Three hops, no repo scan

1. Match the task to an **Area** below (or open the graph view and look for the cluster).
2. Open the area note. Read **Start with** and **Key symbols**.
3. Open that `file:line`. Only then search the repo — and if the graph had no answer, add it to `raw/inbox/`.

If a file disagrees with a note, the file wins: the graph is stale. Refresh with `graphify update .` then this script. Freshness check: graph commit vs `git rev-parse --short HEAD`.

**One file, one area.** Every file is listed under exactly one area — the one holding most of its symbols — so a `file:line` has a single home. The script checks this and refuses to write a map where a file sits in two areas; `areas.json` pins up to three files per area, and its `label` field is a hand-fixed name a refresh will not undo.

## Areas

| Area | Symbols | Files | Open |
| --- | ---: | ---: | --- |
| AppState | 802 | 30 | [[graph/appstate|AppState]] |
| Web App Shell & Theme | 486 | 95 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| App data (iOS) | 306 | 1 | [[graph/app-data-ios|App data (iOS)]] |
| MapExploreView | 278 | 5 | [[graph/mapexploreview|MapExploreView]] |
| Create event (web) | 269 | 33 | [[graph/create-event-web|Create event (web)]] |
| AppState+Payments.swift | 262 | 1 | [[graph/appstate-payments-swift|AppState+Payments.swift]] |
| Schema & migrations (SQL) | 258 | 64 | [[graph/schema-migrations-sql|Schema & migrations (SQL)]] |
| Components.swift | 244 | 11 | [[graph/components-swift|Components.swift]] |
| HomeShellV5Views.swift | 235 | 4 | [[graph/homeshellv5views-swift|HomeShellV5Views.swift]] |
| EventDetail.jsx | 218 | 29 | [[graph/eventdetail-jsx|EventDetail.jsx]] |
| CreateEventView | 216 | 3 | [[graph/createeventview|CreateEventView]] |
| Rewards schema (SQL) | 196 | 19 | [[graph/rewards-schema-sql|Rewards schema (SQL)]] |
| Home.jsx | 184 | 27 | [[graph/home-jsx|Home.jsx]] |
| EventDetailView | 175 | 1 | [[graph/eventdetailview|EventDetailView]] |
| Secondary screens (iOS) | 159 | 15 | [[graph/secondary-screens-ios|Secondary screens (iOS)]] |
| MapExplore.jsx | 148 | 19 | [[graph/mapexplore-jsx|MapExplore.jsx]] |
| AccountView | 145 | 7 | [[graph/accountview|AccountView]] |
| OnboardingFlowState | 140 | 2 | [[graph/onboardingflowstate|OnboardingFlowState]] |
| AppState+Rewards.swift | 138 | 1 | [[graph/appstate-rewards-swift|AppState+Rewards.swift]] |
| Project Tasks & Day-of (iOS) | 123 | 1 | [[graph/project-tasks-day-of-ios|Project Tasks & Day-of (iOS)]] |
| Inbox & notifications (iOS) | 110 | 3 | [[graph/inbox-notifications-ios|Inbox & notifications (iOS)]] |
| Tour, calendar & sharing (web) | 107 | 10 | [[graph/tour-calendar-sharing-web|Tour, calendar & sharing (web)]] |
| BanBeContext.jsx | 102 | 14 | [[graph/banbecontext-jsx|BanBeContext.jsx]] |
| Browse rules (iOS) | 96 | 2 | [[graph/browse-rules-ios|Browse rules (iOS)]] |
| IslandSettings.jsx | 67 | 13 | [[graph/islandsettings-jsx|IslandSettings.jsx]] |
| Event data & notifications (web) | 56 | 4 | [[graph/event-data-notifications-web|Event data & notifications (web)]] |

## Hot files (highest coupling — read carefully before editing)

| File | Symbols | Degree | Area |
| --- | ---: | ---: | --- |
| `apps/ios/BanbeApp/State/AppState.swift` | 276 | 4181 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Data.swift` | 306 | 1437 | [[graph/app-data-ios|App data (iOS)]] |
| `src/theme.js` | 46 | 1384 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/MapExploreView.swift` | 196 | 1130 | [[graph/mapexploreview|MapExploreView]] |
| `apps/ios/BanbeApp/Views/OnboardingViews.swift` | 191 | 1028 | [[graph/createeventview|CreateEventView]] |
| `apps/ios/BanbeApp/State/AppState+Payments.swift` | 262 | 992 | [[graph/appstate-payments-swift|AppState+Payments.swift]] |
| `apps/ios/BanbeApp/Views/Components.swift` | 133 | 912 | [[graph/components-swift|Components.swift]] |
| `apps/ios/BanbeApp/State/AppState+Reports.swift` | 59 | 900 | — |
| `apps/ios/BanbeApp/Views/EventDetailView.swift` | 175 | 832 | [[graph/eventdetailview|EventDetailView]] |
| `src/state/BanBeContext.jsx` | 42 | 826 | [[graph/banbecontext-jsx|BanBeContext.jsx]] |
| `apps/ios/BanbeApp/Views/HomeView.swift` | 88 | 622 | [[graph/homeshellv5views-swift|HomeShellV5Views.swift]] |
| `supabase/migrations/20260906000001_001_core_schema.sql` | 7 | 578 | [[graph/schema-migrations-sql|Schema & migrations (SQL)]] |
| `apps/ios/BanbeApp/Models/CatalogEvent.swift` | 109 | 493 | — |
| `apps/ios/BanbeApp/State/AppState+Rewards.swift` | 138 | 493 | [[graph/appstate-rewards-swift|AppState+Rewards.swift]] |
| `apps/ios/BanbeApp/Views/OnboardingFlowViews.swift` | 100 | 493 | — |
| `apps/ios/BanbeApp/Models/EventProject.swift` | 123 | 487 | [[graph/project-tasks-day-of-ios|Project Tasks & Day-of (iOS)]] |
| `apps/ios/BanbeApp/Views/HowBanbeWorksView.swift` | 83 | 486 | — |
| `apps/ios/BanbeApp/Lib/MapDiscovery.swift` | 83 | 467 | — |
| `supabase/migrations/20261231000210_210_event_project_core.sql` | 94 | 428 | — |
| `apps/ios/BanbeApp/Lib/OnboardingFlow.swift` | 99 | 412 | [[graph/onboardingflowstate|OnboardingFlowState]] |
| `src/components/project/ProjectUI.jsx` | 29 | 408 | — |
| `apps/ios/BanbeApp/Lib/ReportsPresentation.swift` | 70 | 406 | — |
| `src/App.jsx` | 57 | 406 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeAppUITests/UITestAuthHelpers.swift` | 8 | 399 | — |
| `apps/ios/BanbeApp/State/AppState+Surveys.swift` | 107 | 392 | — |
| `src/screens/CreateEvent.jsx` | 39 | 385 | [[graph/create-event-web|Create event (web)]] |
| `apps/ios/BanbeApp/Views/Sheets.swift` | 60 | 369 | — |
| `apps/ios/BanbeApp/Views/AccountView.swift` | 59 | 361 | [[graph/accountview|AccountView]] |
| `apps/ios/BanbeApp/Lib/EventRecipe.swift` | 78 | 351 | — |
| `apps/ios/BanbeApp/Views/ConfirmedView.swift` | 81 | 340 | — |

`—` means the file's community is smaller than the map's cut, so no area note owns it: open the file directly. It is not a second home for another area — a file is only ever listed under one.

## Related notes

- [[Home]] · [[wiki/Project map]] · [[wiki/Conventions]] · [[Decisions]]
- Coverage: code structure only. Behaviour, status and history live in `.claude/notes/` and the wiki.
