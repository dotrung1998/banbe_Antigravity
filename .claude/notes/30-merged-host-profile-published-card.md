# 30 — Merged host profile + published share card (web)

Status: IMPLEMENTED (web `src/**` only; iOS done separately). Build passes (`npx vite build`); not browser-tested end to end. Migration 155 must be applied (`supabase db push`) before the published card does anything — until then the sheet silently shows/edits the default card and "Save card" fails with a toast.

## What changed
- **Two host profiles merged into one (OrganizerProfile, `/org/<id>`).** The old `Organizer` screen (`screen:'organizer'`, `/event/<key>/organizer`) is deleted (`src/screens/Organizer.jsx`, its App.jsx entry, `goOrganizer`, `backToOrganizer`).
  - "Message <host>" (`data-testid="organizer-message"`) now lives on EventDetail, under the "Người tổ chức" row.
  - The Organizer photo grid (labels "Photos by X" / "posted by the organizer", 2-col grid, `openPhoto` viewer, per-photo `eventId`, liked heart) replaced OrganizerProfile's old 3-col thumbnails. `loadOrganizerPhotos` now takes an **organizer id** (not an event key); `organizerProfilePhotos` state and the photo query in `loadOrganizerProfileExtras` were removed.
  - The "Open in the banbe app" banner (shared `?org=` link only) moved onto OrganizerProfile.
- **Event -> organizer id resolution:** `openOrganizerOfEvent(eventKey, back='event')` (BanBeContext, next to `openOrganizerProfile`): `realEventsById[key].organizerId`, else a one-row `events.organizer_id` lookup (this also covers seeded demo-catalogue events, which carry no organizer id client-side), else a toast and stay put. Shared `?org=<eventKey>` boot link resolves the same way in a mount effect. Old `/event/<key>/organizer` URLs go through the same function (back = home).
- **Back behaviour / no loop:** profile opened from an event has `organizerProfileBack:'event'`; `goEvent`/`goEventFromStory` treat that profile as a pass-through (keep `eventBackScreen`), exactly as the old 'organizer' screen was. A profile reached from elsewhere (Home, Pulse, /org link, Dashboard) is a real back target for events opened from it. Chat fallbacks (`chatBack`, `chatBackFn`, `openChatFor` login return, `/event/<key>/chat` parent in routes.js) now point at `event`.
- **Published share card** (`src/screens/sheets/ProfileShareSheet.jsx`, props `kind` 'member'|'host', `publishId` handle|organizer id, `isOwner`): sheet fetches `get_published_share_card` on open. Non-owner = read-only card + Download/Copy link/Share only. Owner = editor starting from the published style; "Save card" shows only when draft != published, calls `publish_share_card`, then draft becomes the published value. localStorage `shareCardStyle.v1` is no longer read or written (no draft persistence). Picked photo is cropped to 392x600 and JPEG-compressed (quality stepped down until < 300k chars) before publishing; server cap is 400000.
- Ownership: OrganizerProfile `org.id === myOrganizerId || myOrganizerIds.includes(org.id)`; PublicProfile handle === `s.user.handle` (case-insens.); Account rows always owner.

## Files
`src/state/BanBeContext.jsx`, `src/lib/routes.js`, `src/App.jsx`, `src/screens/{OrganizerProfile,EventDetail,PublicProfile,Account}.jsx`, `src/screens/sheets/ProfileShareSheet.jsx`; deleted `src/screens/Organizer.jsx`; `tests/navigation-and-events.spec.js` (screen label only).

## Caveats
- Photo is stored as a data URL inside jsonb (`profiles.share_card` / `organizers.share_card`), returned with every get; fine at <=~300KB but not a media pipeline.
- Tests still broken/needing rework: `tests/chat-photo.spec.js` and `tests/story-viewer.spec.js` land on `/?org=phong302` and click `organizer-message` on the old Organizer screen (now on EventDetail); `tests/navigation-and-events.spec.js` "shared ?org= link" test now needs the demo event's organizer to exist in the DB to resolve.
- `toggleFollow` (local per-event-key following) is now unused by any screen; left in BanBeContext. Stale comments mentioning "Organizer.jsx" remain in a few BanBeContext spots.
