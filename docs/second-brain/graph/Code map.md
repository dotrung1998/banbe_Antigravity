---
tags: [code-graph]
---
# Code map — open this before grepping the repo

> Generated from `graphify-out/graph.json` (graph written 2026-11-21 21:31 UTC · repo HEAD `a0ed5486` · graphify base commit `a0ed5486`): **18,253 symbols**, 46,453 edges, 24 areas. Do not hand-edit — run `node scripts/second-brain-code-graph.mjs`
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
| AppState | 401 | 78 | [[graph/appstate|AppState]] |
| Web App Shell & Theme | 376 | 104 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| PressableButtonStyle | 254 | 34 | [[graph/pressablebuttonstyle|PressableButtonStyle]] |
| organizers | 250 | 87 | [[graph/organizers|organizers]] |
| SupabaseService | 247 | 27 | [[graph/supabaseservice|SupabaseService]] |
| MapExplore.jsx | 241 | 42 | [[graph/mapexplore-jsx|MapExplore.jsx]] |
| Screen | 234 | 24 | [[graph/screen|Screen]] |
| CreateEventView | 225 | 15 | [[graph/createeventview|CreateEventView]] |
| BanBeContext.jsx | 217 | 42 | [[graph/banbecontext-jsx|BanBeContext.jsx]] |
| Home.jsx | 215 | 43 | [[graph/home-jsx|Home.jsx]] |
| EventDetail.jsx | 208 | 30 | [[graph/eventdetail-jsx|EventDetail.jsx]] |
| iOS Shared UI & Navigation | 205 | 26 | [[graph/ios-shared-ui-navigation|iOS Shared UI & Navigation]] |
| CatalogEvent | 204 | 36 | [[graph/catalogevent|CatalogEvent]] |
| 20261212000165_165_rewards_badges_streaks.sql | 198 | 22 | [[graph/20261212000165-165-rewards-badges-streaks-sql|20261212000165_165_rewards_badges_streaks.sql]] |
| EventOnboarding.jsx | 175 | 19 | [[graph/eventonboarding-jsx|EventOnboarding.jsx]] |
| flagOn | 148 | 27 | [[graph/flagon|flagOn]] |
| HomeView | 147 | 12 | [[graph/homeview|HomeView]] |
| RewardsPayload | 108 | 6 | [[graph/rewardspayload|RewardsPayload]] |
| public.profiles | 103 | 24 | [[graph/public-profiles|public.profiles]] |
| EventDetailView | 98 | 4 | [[graph/eventdetailview|EventDetailView]] |
| 20261231000210_210_event_project_core.sql | 93 | 1 | [[graph/20261231000210-210-event-project-core-sql|20261231000210_210_event_project_core.sql]] |
| Components.swift | 92 | 12 | [[graph/components-swift|Components.swift]] |
| MapExploreView | 89 | 4 | [[graph/mapexploreview|MapExploreView]] |
| ViEn | 89 | 7 | [[graph/vien|ViEn]] |

## Hot files (highest coupling — read carefully before editing)

| File | Symbols | Degree | Area |
| --- | ---: | ---: | --- |
| `apps/ios/BanbeApp/State/AppState.swift` | 276 | 4189 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Data.swift` | 306 | 1437 | [[graph/appstate|AppState]] |
| `src/theme.js` | 46 | 1383 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/MapExploreView.swift` | 196 | 1135 | [[graph/mapexploreview|MapExploreView]] |
| `apps/ios/BanbeApp/Views/OnboardingViews.swift` | 191 | 1033 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Payments.swift` | 262 | 992 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/Views/Components.swift` | 133 | 923 | [[graph/components-swift|Components.swift]] |
| `apps/ios/BanbeApp/State/AppState+Reports.swift` | 59 | 900 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/Views/EventDetailView.swift` | 175 | 837 | [[graph/appstate|AppState]] |
| `src/state/BanBeContext.jsx` | 42 | 833 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/HomeView.swift` | 88 | 626 | [[graph/homeview|HomeView]] |
| `supabase/migrations/20260906000001_001_core_schema.sql` | 7 | 578 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/Views/OnboardingFlowViews.swift` | 100 | 500 | [[graph/catalogevent|CatalogEvent]] |
| `apps/ios/BanbeApp/State/AppState+Rewards.swift` | 138 | 497 | [[graph/rewardspayload|RewardsPayload]] |
| `apps/ios/BanbeApp/Models/CatalogEvent.swift` | 109 | 494 | [[graph/catalogevent|CatalogEvent]] |
| `package.json` | 70 | 494 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Models/EventProject.swift` | 123 | 487 | — |
| `apps/ios/BanbeApp/Views/HowBanbeWorksView.swift` | 83 | 486 | — |
| `apps/ios/BanbeApp/Lib/MapDiscovery.swift` | 83 | 467 | [[graph/mapexploreview|MapExploreView]] |
| `supabase/migrations/20261231000210_210_event_project_core.sql` | 94 | 428 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/Lib/OnboardingFlow.swift` | 99 | 425 | — |
| `src/components/project/ProjectUI.jsx` | 29 | 415 | — |
| `apps/ios/BanbeApp/Lib/ReportsPresentation.swift` | 70 | 406 | — |
| `apps/ios/BanbeAppUITests/UITestAuthHelpers.swift` | 8 | 399 | — |
| `apps/ios/BanbeApp/State/AppState+Surveys.swift` | 107 | 392 | [[graph/appstate|AppState]] |
| `src/screens/CreateEvent.jsx` | 39 | 391 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/Sheets.swift` | 60 | 373 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/Views/AccountView.swift` | 59 | 362 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Lib/EventRecipe.swift` | 78 | 351 | [[graph/createeventview|CreateEventView]] |
| `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` | 74 | 343 | [[graph/components-swift|Components.swift]] |

## Related notes

- [[Home]] · [[wiki/Project map]] · [[wiki/Conventions]] · [[Decisions]]
- Coverage: code structure only. Behaviour, status and history live in `.claude/notes/` and the wiki.
