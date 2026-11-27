---
tags: [code-graph]
---
# Code map — open this before grepping the repo

> Generated from `graphify-out/graph.json` (graph written 2026-11-26 21:30 UTC · repo HEAD `084a27a7` · graphify base commit `084a27a7`): **18,646 symbols**, 47,034 edges, 24 areas. Do not hand-edit — run `node scripts/second-brain-code-graph.mjs`
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
| Web App Shell & Theme | 404 | 110 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| AppState | 310 | 63 | [[graph/appstate|AppState]] |
| SupabaseService | 273 | 27 | [[graph/supabaseservice|SupabaseService]] |
| EventDetail.jsx | 269 | 47 | [[graph/eventdetail-jsx|EventDetail.jsx]] |
| MapExplore.jsx | 247 | 47 | [[graph/mapexplore-jsx|MapExplore.jsx]] |
| organizers | 235 | 87 | [[graph/organizers|organizers]] |
| Screen | 216 | 29 | [[graph/screen|Screen]] |
| iOS Shared UI & Navigation | 210 | 28 | [[graph/ios-shared-ui-navigation|iOS Shared UI & Navigation]] |
| BanBeContext.jsx | 209 | 44 | [[graph/banbecontext-jsx|BanBeContext.jsx]] |
| CreateEventView | 198 | 13 | [[graph/createeventview|CreateEventView]] |
| 20261212000165_165_rewards_badges_streaks.sql | 184 | 22 | [[graph/20261212000165-165-rewards-badges-streaks-sql|20261212000165_165_rewards_badges_streaks.sql]] |
| MapExploreView | 179 | 17 | [[graph/mapexploreview|MapExploreView]] |
| EventOnboarding.jsx | 173 | 18 | [[graph/eventonboarding-jsx|EventOnboarding.jsx]] |
| EventDetailView | 171 | 13 | [[graph/eventdetailview|EventDetailView]] |
| Home.jsx | 171 | 28 | [[graph/home-jsx|Home.jsx]] |
| flagOn | 158 | 23 | [[graph/flagon|flagOn]] |
| PublicProfile.jsx | 131 | 18 | [[graph/publicprofile-jsx|PublicProfile.jsx]] |
| EventRecipe | 124 | 17 | [[graph/eventrecipe|EventRecipe]] |
| HomeHeroSection | 119 | 16 | [[graph/homeherosection|HomeHeroSection]] |
| AppNotification | 116 | 7 | [[graph/appnotification|AppNotification]] |
| RewardsPayload | 114 | 7 | [[graph/rewardspayload|RewardsPayload]] |
| Components.swift | 111 | 14 | [[graph/components-swift|Components.swift]] |
| ref_node_assert | 109 | 26 | [[graph/ref-node-assert|ref_node_assert]] |
| EventPlanActions.jsx | 106 | 18 | [[graph/eventplanactions-jsx|EventPlanActions.jsx]] |

## Hot files (highest coupling — read carefully before editing)

| File | Symbols | Degree | Area |
| --- | ---: | ---: | --- |
| `apps/ios/BanbeApp/State/AppState.swift` | 276 | 4191 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/State/AppState+Data.swift` | 306 | 1437 | [[graph/supabaseservice|SupabaseService]] |
| `src/theme.js` | 46 | 1389 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/MapExploreView.swift` | 196 | 1135 | [[graph/mapexploreview|MapExploreView]] |
| `apps/ios/BanbeApp/Views/OnboardingViews.swift` | 191 | 1033 | [[graph/eventrecipe|EventRecipe]] |
| `apps/ios/BanbeApp/State/AppState+Payments.swift` | 262 | 992 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/Views/Components.swift` | 133 | 914 | [[graph/components-swift|Components.swift]] |
| `apps/ios/BanbeApp/State/AppState+Reports.swift` | 59 | 903 | [[graph/eventrecipe|EventRecipe]] |
| `src/state/BanBeContext.jsx` | 42 | 852 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/EventDetailView.swift` | 175 | 838 | [[graph/appstate|AppState]] |
| `apps/ios/BanbeApp/Views/HomeView.swift` | 88 | 624 | [[graph/mapexploreview|MapExploreView]] |
| `supabase/migrations/20260906000001_001_core_schema.sql` | 7 | 578 | [[graph/organizers|organizers]] |
| `apps/ios/BanbeApp/State/AppState+Rewards.swift` | 138 | 496 | [[graph/rewardspayload|RewardsPayload]] |
| `package.json` | 70 | 496 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Models/CatalogEvent.swift` | 109 | 495 | [[graph/supabaseservice|SupabaseService]] |
| `apps/ios/BanbeApp/Views/OnboardingFlowViews.swift` | 100 | 495 | [[graph/components-swift|Components.swift]] |
| `apps/ios/BanbeApp/Models/EventProject.swift` | 123 | 487 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Views/HowBanbeWorksView.swift` | 83 | 486 | — |
| `apps/ios/BanbeApp/Lib/MapDiscovery.swift` | 83 | 469 | [[graph/eventrecipe|EventRecipe]] |
| `supabase/migrations/20261231000210_210_event_project_core.sql` | 94 | 428 | [[graph/organizers|organizers]] |
| `src/components/project/ProjectUI.jsx` | 29 | 415 | — |
| `apps/ios/BanbeApp/Lib/OnboardingFlow.swift` | 99 | 414 | — |
| `src/App.jsx` | 57 | 408 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Lib/ReportsPresentation.swift` | 70 | 406 | — |
| `apps/ios/BanbeAppUITests/UITestAuthHelpers.swift` | 8 | 399 | — |
| `apps/ios/BanbeApp/State/AppState+Surveys.swift` | 107 | 392 | [[graph/appstate|AppState]] |
| `src/screens/CreateEvent.jsx` | 39 | 391 | [[graph/web-app-shell-theme|Web App Shell & Theme]] |
| `apps/ios/BanbeApp/Views/Sheets.swift` | 60 | 372 | — |
| `apps/ios/BanbeApp/Views/AccountView.swift` | 59 | 362 | [[graph/screen|Screen]] |
| `apps/ios/BanbeApp/Lib/EventRecipe.swift` | 78 | 343 | [[graph/eventrecipe|EventRecipe]] |

## Related notes

- [[Home]] · [[wiki/Project map]] · [[wiki/Conventions]] · [[Decisions]]
- Coverage: code structure only. Behaviour, status and history live in `.claude/notes/` and the wiki.
