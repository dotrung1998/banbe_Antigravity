---
tags: [code-graph]
---
# Code map — open this before grepping the repo

> Generated from `graphify-out/graph.json` (graph written 2026-11-20 20:26 UTC · repo HEAD `3eb810eb` · graphify base commit `3eb810eb`): **17,910 symbols**, 46,003 edges, 24 areas. Do not hand-edit — run `node scripts/second-brain-code-graph.mjs`
>
> **Fresh:** the graph was written after the current HEAD commit, so it includes the committed code.

## Three hops, no repo scan

1. Match the task to an **Area** below (or open the graph view and look for the cluster).
2. Open the area note. Read **Start with** and **Key symbols**.
3. Open that `file:line`. Only then search the repo — and if the graph had no answer, add it to `raw/inbox/`.

If a file disagrees with a note, the file wins: the graph is stale. Refresh with `graphify update .` then this script. Freshness check: graph commit vs `git rev-parse --short HEAD`.

## Areas

| Area | Symbols | Files | Open |
| --- | ---: | ---: | --- |
| Web App Shell & Theme | 471 | 121 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| MapExplore.jsx | 334 | 54 | [[graph/mapexplore-jsx|MapExplore.jsx]] |
| AppState | 315 | 58 | [[graph/appstate|AppState]] |
| MapExploreView | 266 | 25 | [[graph/mapexploreview|MapExploreView]] |
| iOS Create Event Form | 219 | 41 | [[graph/ios-create-event-form|iOS Create Event Form]] |
| EventDetail.jsx | 214 | 34 | [[graph/eventdetail-jsx|EventDetail.jsx]] |
| PressableButtonStyle | 202 | 28 | [[graph/pressablebuttonstyle|PressableButtonStyle]] |
| iOS Shared UI & Navigation | 199 | 27 | [[graph/ios-shared-ui-navigation|iOS Shared UI & Navigation]] |
| Screen | 190 | 26 | [[graph/screen|Screen]] |
| ProjectUI.jsx | 177 | 23 | [[graph/projectui-jsx|ProjectUI.jsx]] |
| CreateEventView | 175 | 9 | [[graph/createeventview|CreateEventView]] |
| organizers | 166 | 59 | [[graph/organizers|organizers]] |
| bookings | 162 | 59 | [[graph/bookings|bookings]] |
| 20261212000165_165_rewards_badges_streaks.sql | 148 | 17 | [[graph/20261212000165-165-rewards-badges-streaks-sql|20261212000165_165_rewards_badges_streaks.sql]] |
| public.profiles | 127 | 27 | [[graph/public-profiles|public.profiles]] |
| ViEn | 126 | 8 | [[graph/vien|ViEn]] |
| SupabaseService | 121 | 33 | [[graph/supabaseservice|SupabaseService]] |
| auth.users | 115 | 20 | [[graph/auth-users|auth.users]] |
| Confirmed.jsx | 115 | 22 | [[graph/confirmed-jsx|Confirmed.jsx]] |
| RewardsPayload | 114 | 6 | [[graph/rewardspayload|RewardsPayload]] |
| Components.swift | 108 | 11 | [[graph/components-swift|Components.swift]] |
| AccountGroup.jsx | 94 | 22 | [[graph/accountgroup-jsx|AccountGroup.jsx]] |
| EventDetailView | 94 | 4 | [[graph/eventdetailview|EventDetailView]] |
| 20261231000210_210_event_project_core.sql | 93 | 1 | [[graph/20261231000210-210-event-project-core-sql|20261231000210_210_event_project_core.sql]] |

## Hot files (highest coupling — read carefully before editing)

| File | Symbols | Degree | Area |
| --- | ---: | ---: | --- |
| `apps/ios/BanbeApp/State/AppState.swift` | 276 | 4188 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Data.swift` | 306 | 1437 | [[graph/appstate|AppState]] |
| `src/theme.js` | 46 | 1383 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/MapExploreView.swift` | 196 | 1136 | [[graph/mapexploreview|MapExploreView]] |
| `apps/ios/BanbeApp/Views/OnboardingViews.swift` | 191 | 1034 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Payments.swift` | 262 | 994 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/Views/Components.swift` | 133 | 926 | [[graph/components-swift|Components.swift]] |
| `apps/ios/BanbeApp/State/AppState+Reports.swift` | 59 | 900 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Views/EventDetailView.swift` | 175 | 834 | [[graph/appstate|AppState]] |
| `src/state/BanBeContext.jsx` | 41 | 828 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/HomeView.swift` | 88 | 624 | [[graph/components-swift|Components.swift]] |
| `supabase/migrations/20260906000001_001_core_schema.sql` | 7 | 578 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/Views/OnboardingFlowViews.swift` | 100 | 500 | [[graph/pressablebuttonstyle|PressableButtonStyle]] |
| `apps/ios/BanbeApp/Models/CatalogEvent.swift` | 109 | 498 | — |
| `apps/ios/BanbeApp/State/AppState+Rewards.swift` | 138 | 497 | [[graph/rewardspayload|RewardsPayload]] |
| `apps/ios/BanbeApp/Models/EventProject.swift` | 123 | 488 | — |
| `apps/ios/BanbeApp/Views/HowBanbeWorksView.swift` | 83 | 486 | [[graph/mapexploreview|MapExploreView]] |
| `apps/ios/BanbeApp/Lib/MapDiscovery.swift` | 83 | 470 | — |
| `package.json` | 58 | 462 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `supabase/migrations/20261231000210_210_event_project_core.sql` | 94 | 428 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/Lib/OnboardingFlow.swift` | 99 | 425 | — |
| `src/components/project/ProjectUI.jsx` | 29 | 409 | [[graph/projectui-jsx|ProjectUI.jsx]] |
| `apps/ios/BanbeApp/Lib/ReportsPresentation.swift` | 70 | 406 | — |
| `apps/ios/BanbeAppUITests/UITestAuthHelpers.swift` | 8 | 399 | — |
| `apps/ios/BanbeApp/State/AppState+Surveys.swift` | 107 | 392 | [[graph/appstate|AppState]] |
| `src/screens/CreateEvent.jsx` | 39 | 391 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/Sheets.swift` | 60 | 373 | [[graph/pressablebuttonstyle|PressableButtonStyle]] |
| `apps/ios/BanbeApp/Views/AccountView.swift` | 59 | 361 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Lib/EventRecipe.swift` | 78 | 351 | — |
| `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` | 74 | 350 | [[graph/mapexploreview|MapExploreView]] |

## Related notes

- [[Home]] · [[wiki/Project map]] · [[wiki/Conventions]] · [[Decisions]]
- Coverage: code structure only. Behaviour, status and history live in `.claude/notes/` and the wiki.
