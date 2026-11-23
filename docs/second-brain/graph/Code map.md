---
tags: [code-graph]
---
# Code map — open this before grepping the repo

> Generated from `graphify-out/graph.json` (graph written 2026-11-23 10:23 UTC · repo HEAD `a6699b1d` · graphify base commit `a6699b1d`): **18,441 symbols**, 46,719 edges, 24 areas. Do not hand-edit — run `node scripts/second-brain-code-graph.mjs`
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
| AppState | 476 | 78 | [[graph/appstate|AppState]] |
| Web App Shell & Theme | 403 | 109 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| PressableButtonStyle | 311 | 37 | [[graph/pressablebuttonstyle|PressableButtonStyle]] |
| Home.jsx | 255 | 48 | [[graph/home-jsx|Home.jsx]] |
| MapExplore.jsx | 226 | 40 | [[graph/mapexplore-jsx|MapExplore.jsx]] |
| iOS Shared UI & Navigation | 220 | 31 | [[graph/ios-shared-ui-navigation|iOS Shared UI & Navigation]] |
| EventDetail.jsx | 213 | 30 | [[graph/eventdetail-jsx|EventDetail.jsx]] |
| organizers | 206 | 77 | [[graph/organizers|organizers]] |
| CreateEventView | 191 | 11 | [[graph/createeventview|CreateEventView]] |
| SupabaseService | 189 | 12 | [[graph/supabaseservice|SupabaseService]] |
| 20261212000165_165_rewards_badges_streaks.sql | 188 | 22 | [[graph/20261212000165-165-rewards-badges-streaks-sql|20261212000165_165_rewards_badges_streaks.sql]] |
| EventDetailView | 186 | 13 | [[graph/eventdetailview|EventDetailView]] |
| BanBeContext.jsx | 181 | 37 | [[graph/banbecontext-jsx|BanBeContext.jsx]] |
| Screen | 163 | 17 | [[graph/screen|Screen]] |
| flagOn | 143 | 33 | [[graph/flagon|flagOn]] |
| MapExploreView | 135 | 11 | [[graph/mapexploreview|MapExploreView]] |
| ref_node_assert | 130 | 28 | [[graph/ref-node-assert|ref_node_assert]] |
| public.profiles | 127 | 28 | [[graph/public-profiles|public.profiles]] |
| ReportMetricPresentation group | 125 | 7 | [[graph/reportmetricpresentation-group|ReportMetricPresentation group]] |
| ViEn | 118 | 10 | [[graph/vien|ViEn]] |
| RewardsPayload | 112 | 5 | [[graph/rewardspayload|RewardsPayload]] |
| HomeView | 104 | 12 | [[graph/homeview|HomeView]] |
| PublicProfile.jsx | 100 | 14 | [[graph/publicprofile-jsx|PublicProfile.jsx]] |
| IslandSettings.jsx | 93 | 24 | [[graph/islandsettings-jsx|IslandSettings.jsx]] |

## Hot files (highest coupling — read carefully before editing)

| File | Symbols | Degree | Area |
| --- | ---: | ---: | --- |
| `apps/ios/BanbeApp/State/AppState.swift` | 276 | 4189 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Data.swift` | 306 | 1437 | [[graph/appstate|AppState]] |
| `src/theme.js` | 46 | 1383 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/MapExploreView.swift` | 196 | 1135 | [[graph/mapexploreview|MapExploreView]] |
| `apps/ios/BanbeApp/Views/OnboardingViews.swift` | 191 | 1033 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Payments.swift` | 262 | 993 | [[graph/supabaseservice|SupabaseService]] |
| `apps/ios/BanbeApp/Views/Components.swift` | 133 | 927 | [[graph/homeview|HomeView]] |
| `apps/ios/BanbeApp/State/AppState+Reports.swift` | 59 | 900 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Views/EventDetailView.swift` | 175 | 839 | [[graph/appstate|AppState]] |
| `src/state/BanBeContext.jsx` | 42 | 833 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/HomeView.swift` | 88 | 626 | [[graph/homeview|HomeView]] |
| `supabase/migrations/20260906000001_001_core_schema.sql` | 7 | 578 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/Views/OnboardingFlowViews.swift` | 100 | 500 | [[graph/eventdetailview|EventDetailView]] |
| `apps/ios/BanbeApp/Models/CatalogEvent.swift` | 109 | 498 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Rewards.swift` | 138 | 497 | [[graph/rewardspayload|RewardsPayload]] |
| `package.json` | 70 | 495 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Models/EventProject.swift` | 123 | 487 | — |
| `apps/ios/BanbeApp/Views/HowBanbeWorksView.swift` | 83 | 486 | — |
| `apps/ios/BanbeApp/Lib/MapDiscovery.swift` | 83 | 467 | [[graph/reportmetricpresentation-group|ReportMetricPresentation group]] |
| `supabase/migrations/20261231000210_210_event_project_core.sql` | 94 | 428 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/Lib/OnboardingFlow.swift` | 99 | 425 | — |
| `src/components/project/ProjectUI.jsx` | 29 | 409 | — |
| `apps/ios/BanbeApp/Lib/ReportsPresentation.swift` | 70 | 406 | — |
| `apps/ios/BanbeAppUITests/UITestAuthHelpers.swift` | 8 | 399 | — |
| `apps/ios/BanbeApp/State/AppState+Surveys.swift` | 107 | 392 | [[graph/appstate|AppState]] |
| `src/screens/CreateEvent.jsx` | 39 | 391 | [[graph/banbecontext-jsx|BanBeContext.jsx]] |
| `apps/ios/BanbeApp/Views/Sheets.swift` | 60 | 373 | [[graph/pressablebuttonstyle|PressableButtonStyle]] |
| `apps/ios/BanbeApp/Views/AccountView.swift` | 59 | 362 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Lib/EventRecipe.swift` | 78 | 351 | [[graph/createeventview|CreateEventView]] |
| `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` | 74 | 346 | [[graph/eventdetailview|EventDetailView]] |

## Related notes

- [[Home]] · [[wiki/Project map]] · [[wiki/Conventions]] · [[Decisions]]
- Coverage: code structure only. Behaviour, status and history live in `.claude/notes/` and the wiki.
