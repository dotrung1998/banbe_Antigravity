import { createContext, useContext, useEffect, useMemo, useState, useCallback, useRef } from 'react';
import { EVENTS, findEvent, isCosmeticCatalogMatch, haversineKm } from '../data/events.js';
import { supabase, getAuthRedirectUrl } from '../lib/supabase.js';
import { requestAuthEmail, requestPasswordSignup, requestPasswordReset } from '../lib/authEmail.js';
import { renderPaymentDocument, formatVnd } from '../lib/paymentDocument.js';
import { buildVietQrPayload } from '../lib/vietqr.js';
import { msUntil, liveEventOverrides, thisWeekendWindow, formatVnEventDate } from '../lib/countdown.js';
import { normalizeProofFile, normalizeImageForUpload, AVATAR_UPLOAD_BUDGET, EVENT_PHOTO_UPLOAD_BUDGET } from '../lib/proofUpload.js';
import { POLICY_VERSION } from '../lib/policy.js';
import { refundClaimPresentation } from '../lib/refundPresentation.js';
import { buildLocationTree, eventMatchesLocation, locationShortLabel, migrateLegacyAreaKey, LOCATION_ALL } from '../lib/locationTree.js';
import { surveyPublicUrl } from '../lib/surveyLink.js';
import { metricLabel } from '../lib/reportMetricLabels.js';
import { useAccountGate } from '../lib/accountGate.js';
import { normalizeForSave as normalizeEventPrefsForSave, isMissingFunctionError as isEventPrefsFnMissing, everyone as everyoneCriteria, normalizeCriteria, criteriaIsEveryone } from '../lib/eventPrefs.js';
import { useEnsureOrganizer } from '../lib/useEnsureOrganizer.js';
import { uploadViaMediaApi, deleteViaMediaApi, reconcileEventViaMediaApi } from '../lib/mediaUpload.js';
import { publicEventPhotoUrl, organizerAvatarPublicUrl, withR2Columns, isChatGreetingColumnMissing, chatGreetingColumnList, isMissingColumnError } from '../lib/mediaUrls.js';

/** Media-API upload with the current session token. Resolves `{provider:'supabase'}`
 * when the caller must use the legacy path; throws MediaUploadError only after bytes were PUT. */
function reconcileEventMediaFireAndForget(eventId) {
  (async () => {
    const accessToken = (await supabase.auth.getSession())?.data?.session?.access_token || null;
    await reconcileEventViaMediaApi({ eventId, accessToken });
  })().catch(() => {});
}

async function tryMediaApiUpload(args) {
  let accessToken = null;
  try { accessToken = (await supabase.auth.getSession())?.data?.session?.access_token || null; } catch { /* legacy path */ }
  return uploadViaMediaApi({ ...args, accessToken });
}

const BanBeCtx = createContext(null);

/**
 * Canonical real-`events`-row -> plain-data shape, shared by loadWeekendEvents
 * and loadRealEventsById (retention roadmap follow-up — one lookup/shape
 * for "Cuối tuần này" AND the Saved/Going/Completed lists, not three
 * separate ad-hoc ones). Deliberately data-only, no baked-in Vietnamese/
 * English text — callers format bilingual labels at render time with their
 * own T(), the same way weekendList already does in Home.jsx, so this
 * never has to know which language is active.
 */
function shapeRealEvent(row, extra = {}) {
  return {
    key: row.id,
    name: row.name,
    area: row.area || '',
    // Real-event-maps-link fix pass (2026-09-28) — `lat`/`lng` were never
    // fetched here at all (missing from REAL_EVENT_ROW_COLUMNS below),
    // even though migration 094 has stored them on real events since
    // 2026-10-08. `shapeRealEventAsCurEvent` then hardcoded `lat: null,
    // lng: null` regardless — the combination meant a real event's own
    // Event Detail page could never show a working "open in Google Maps"
    // link, even for an event with a genuinely confirmed pin.
    lat: row.lat ?? null,
    lng: row.lng ?? null,
    catKey: row.cat_key || 'all',
    catLabel: row.cat_label || '',
    startsAt: row.starts_at || null,
    priceVnd: row.price_vnd || 0,
    seatsRemaining: row.seats_remaining,
    soldOut: row.seats_remaining != null && row.seats_remaining <= 0,
    status: row.status,
    cancelledAt: row.cancelled_at || null,
    visibility: row.visibility,
    approval: row.approval || '',
    organizerId: row.organizer_id,
    photoUrl: resolveCoverUrl(row.cover_image, extra.photoUrl, row.cover_r2_ref),
    organizerName: extra.organizerName || '',
    // TASK 3 (event creation validation pass) — AdminEvents.jsx's own
    // detailed review section. `organizerType`/`organizerVerified`/
    // `organizerHasTaxCode` are ONLY ever populated by loadPendingEvents'
    // own admin-only organizer join (migration 109's own comment: these
    // are self-declared, `verified` specifically has no real write path
    // anywhere in this schema — never render it as "verified registration").
    organizerType: extra.organizerType || 'individual',
    organizerVerified: !!extra.organizerVerified,
    organizerHasTaxCode: !!extra.organizerHasTaxCode,
    withdrawalReason: row.withdrawal_reason || '',
    withdrawnAt: row.withdrawn_at || null,
    followedHost: !!extra.followedHost,
    isReal: true,
    // Event review queue (retention/admin follow-up) — carried through so
    // Dashboard.jsx can show a rejected/pending event's own real status
    // without a second query.
    description: row.description || '',
    priceCents: row.price_cents || 0,
    capacity: row.capacity,
    eventDate: row.event_date || null,
    eventTime: row.event_time || null,
    submittedAt: row.submitted_at || null,
    reviewedAt: row.reviewed_at || null,
    rejectionReason: row.rejection_reason || '',
    // Real cover/gallery + structured "Bao gồm" (migration 087).
    coverImage: row.cover_image || '',
    coverR2Ref: row.cover_r2_ref || '',
    included: row.included || '',
    includedItems: Array.isArray(row.included_items) ? row.included_items : [],
    // "Giới thiệu sự kiện" (migration 088) — a separate, longer editorial
    // description, never the same field as the short `description`/
    // "Mô tả" or `included_items`/"Bao gồm" above.
    intro: row.intro || '',
    // Address-autocomplete fix pass (2026-09-28, migration 105) — lets
    // goEditEvent pre-fill a verified address (and show it as already
    // confirmed) instead of making the host re-search an address that
    // was already resolved on a previous submit.
    addressLine: row.address_line || '',
    city: row.city || '',
    postalCode: row.postal_code || '',
    addressVerified: !!row.address_verified,
    // Location hierarchy (migration 112) — additive, nullable. Read by
    // src/lib/locationTree.js to build the area picker's tree and to match
    // events against a selected node; `area`/`city` above keep their
    // existing meaning unchanged.
    countryCode: row.country_code || '',
    stateProvince: row.state_province || '',
    neighborhood: row.neighborhood || '',
    // Keyword-search fix (migration 108) — free-text keywords a search on
    // Map matches against, in addition to name/district. Defaults to the
    // event's own category label(s) at create/resubmit time when a host
    // leaves the field blank — never silently empty.
    keywords: Array.isArray(row.keywords) ? row.keywords : [],
    // Host-set opening message for "Message host" (migration 156).
    chatGreeting: row.chat_greeting || '',
    chatGreetingEn: row.chat_greeting_en || '',
  };
}

// Keyword-search fix (migration 108) — re-enabled 2026-09-29 after
// confirming (a live, read-only query against the real database, not
// assumed) that migration 108 has actually been deployed: the `keywords`
// column exists and is populated. See this constant's own git history for
// why it was briefly reverted — requesting a column that doesn't exist yet
// fails the ENTIRE query, not just that field.
// TASK 3 (event creation validation pass) — `approval`/`withdrawal_reason`/
// `withdrawn_at` added for AdminEvents.jsx's own detailed review section
// (booking-approval mode + withdrawal history); additive, same table, no
// new join, so every other existing reader of this constant is unaffected.
const REAL_EVENT_ROW_COLUMNS_BASE = 'id, name, cat_key, cat_label, area, lat, lng, starts_at, price_vnd, price_cents, capacity, seats_remaining, status, cancelled_at, visibility, approval, organizer_id, description, event_date, event_time, submitted_at, reviewed_at, rejection_reason, withdrawal_reason, withdrawn_at, cover_image, included, included_items, intro, address_line, city, postal_code, address_verified, keywords, country_code, state_province, neighborhood';
// `cover_r2_ref` exists only after migration 153 — see withR2Columns (mediaUrls.js).
// Per-user thread_preferences read (star/archive + the per-participant
// "Delete" timestamp). `deleted_at` exists only after migration 156 — on a DB
// without it this retries once without it and remembers for the session.
let threadDeletedAtColumnMissing = false;
async function fetchThreadPrefRows(uid, threadIds) {
  const run = (cols) => supabase.from('thread_preferences').select(cols).eq('user_id', uid).in('thread_id', threadIds);
  if (!threadDeletedAtColumnMissing) {
    const res = await run('thread_id, starred, archived, deleted_at');
    if (!isMissingColumnError(res.error) && !/deleted_at/i.test(res.error?.message || '')) return res;
    threadDeletedAtColumnMissing = true;
  }
  return run('thread_id, starred, archived');
}
// A thread is hidden for me when I deleted it and nothing newer has arrived.
const isThreadDeletedForMe = (deletedAt, lastMessageAt) => !!deletedAt && (!lastMessageAt || new Date(lastMessageAt) <= new Date(deletedAt));

// `chat_greeting`/`chat_greeting_en` exist only after migrations 156/157 —
// withR2Columns flips the flag when the DB rejects them, then retries.
const realEventColumns = (withR2) => {
  let cols = REAL_EVENT_ROW_COLUMNS_BASE;
  for (const c of chatGreetingColumnList()) cols += `, ${c}`;
  return withR2 ? `${cols}, cover_r2_ref` : cols;
};

/** A real event's own selected `cover_image` (migration 087) resolved to a
 * public URL, falling back to `fallbackUrl` (the first `event_photos` row
 * by sort_order) only when no cover was ever explicitly chosen. Root-cause
 * fix: the fallback alone doesn't track which upload the host actually
 * picked as the cover (its own sort_order can be anything, since a host
 * can set ANY staged photo as cover) — this is what makes the card,
 * EventDetail and the admin review queue all show the SAME chosen cover
 * instead of whichever photo happens to sort first. */
export function resolveCoverUrl(coverImagePath, fallbackUrl, coverR2Ref, variant = 'card') {
  if (!coverImagePath && !coverR2Ref) return fallbackUrl || null;
  // Strict invite-only events (migration 113) — a private-bucket path
  // can't be resolved synchronously (createSignedUrl is a network call);
  // every call site that can actually reach one (EventDetail, CreateEvent
  // preview) uses resolveEventPhotoUrlAsync below instead. Discovery
  // surfaces that call this SYNC helper (Home cards, Organizer profile,
  // Pulse) never legitimately hold a private-bucket path in the first
  // place, since invite-only events are excluded from all of them — this
  // is a defensive fallback, not the real gate.
  if (coverImagePath?.startsWith('event-photos-private/')) return fallbackUrl || null;
  return publicEventPhotoUrl(coverImagePath, coverR2Ref, variant) || fallbackUrl || null;
}

/** Async counterpart of resolveCoverUrl — the ONLY correct way to resolve
 * an 'event-photos-private/…' storage_path (a real network call, signed
 * and RLS-checked via is_event_host()/has_event_invite_access()/
 * is_platform_admin(), migration 113). Public paths still resolve via the
 * cheap synchronous getPublicUrl() building block. 1-hour signed URL —
 * long enough for one screen visit, short enough that a leaked link
 * (screenshot, cached tab) doesn't stay valid indefinitely. */
export async function resolveEventPhotoUrlAsync(storagePath, r2Ref, variant = 'card') {
  if (!storagePath && !r2Ref) return null;
  if (storagePath?.startsWith('event-photos-private/')) {
    const relative = storagePath.replace(/^event-photos-private\//, '');
    const { data, error } = await supabase.storage.from('event-photos-private').createSignedUrl(relative, 3600);
    if (error) { if (import.meta.env?.DEV) console.warn('resolveEventPhotoUrlAsync signed-url failed:', error); return null; }
    return data.signedUrl;
  }
  return publicEventPhotoUrl(storagePath, r2Ref, variant);
}

/** event_photos rows for `eventIds` -> { [event_id]: first public photo URL },
 * same batching + bucket-name-doubling defensive strip loadNotifications'
 * own eventPhotoByEventId uses (see that function's comment). Shared here
 * so loadWeekendEvents, loadRealEventsById and MapExplore's own
 * fetchLiveEvents don't each reimplement it. */
export async function firstPhotoUrlByEvent(eventIds) {
  if (!eventIds.length) return {};
  const { data } = await withR2Columns(withR2 => supabase
    .from('event_photos').select(withR2 ? 'event_id, storage_path, r2_ref, sort_order' : 'event_id, storage_path, sort_order')
    .in('event_id', eventIds).order('sort_order', { ascending: true }));
  const byEvent = {};
  for (const p of data || []) {
    if (byEvent[p.event_id]) continue;
    byEvent[p.event_id] = await resolveEventPhotoUrlAsync(p.storage_path, p.r2_ref, 'card');
  }
  return byEvent;
}

/** Merges `get_photo_engagement`/ranking-RPC rows into the canonical
 * `photoEngagement` map (see its own state comment) — a plain object merge,
 * never a full replace, so a batch covering ONE screen's photos never wipes
 * out engagement already loaded for another screen's. */
function mergePhotoEngagement(existing, rows) {
  if (!rows || !rows.length) return existing;
  const next = { ...existing };
  for (const r of rows) {
    const id = r.photo_id;
    if (!id) continue;
    const prev = next[id];
    next[id] = {
      likeCount: r.like_count ?? prev?.likeCount ?? 0,
      shareCount: r.share_count ?? prev?.shareCount ?? 0,
      likedByMe: r.liked_by_me ?? prev?.likedByMe ?? false,
    };
  }
  return next;
}

/**
 * Blocker fix (retention roadmap follow-up) — `findEvent()` (data/events.js)
 * falls back to `EVENTS[0]` for any key not in the static demo catalogue,
 * which `curEvent` (below) used unconditionally: opening a REAL, host-
 * created event (goer taps a save/weekend card, or a direct link) silently
 * rendered a WRONG demo event's name/price/photo/description, with only
 * the date and cancelled/ended flags corrected via liveEventOverrides —
 * confusing and simply incorrect, not an "honest placeholder." This builds
 * a CatalogEvent-shaped object from the same canonical realEventsById row
 * shapeRealEvent already produces instead: every FACTUAL field (name,
 * price, area, seats, cancelled/ended, invite-only) is real; every
 * DECORATIVE field this app has no real-data source for yet (long
 * description, included list, organizer bio/trust stats, extra gallery
 * photos) is an honest empty string/neutral default, never invented.
 */
export function shapeRealEventAsCurEvent(real) {
  const startsAt = real.startsAt ? new Date(real.startsAt) : null;
  const { weekdayShort, dayMonth, dayLong, time } = startsAt ? formatVnEventDate(startsAt) : {};
  const endedHoursAgo = real.status === 'ended' && startsAt ? Math.max(0, Math.round((Date.now() - startsAt.getTime()) / 3600000)) : null;
  return {
    key: real.key, catKey: real.catKey, cat: real.catLabel || '', cat2Key: null, catDisplay: real.catLabel || '',
    name: real.name, img: real.photoUrl || '', lat: real.lat ?? null, lng: real.lng ?? null,
    meta: [real.catLabel, real.area].filter(Boolean).join(' ▪︎ '),
    // Venue/address parity fix (task 2, then reworked per user follow-up
    // 2026-09-29) — first pass surfaced the raw street address here, but
    // that reads differently from every demo event's own "district ▪︎ live
    // km ▪︎ long date ▪︎ time" line and broke the shared `stripKm()` live-
    // distance injection (no " ▪︎ X,X km" segment for it to find). Now
    // built in the exact same shape the static catalogue's own `where`
    // uses (`data/events.js`'s ROWS mapping) — district + a live-km
    // placeholder segment (stripKm replaces the number once a real
    // distance is computable, or strips the whole segment if not — same
    // contract as every other event) + the long-form Vietnamese date/time.
    // The verified street address is still real data (never fabricated,
    // never copied from a demo event) but is exposed via `mapsUrl(ev)`'s
    // own real lat/lng, not spelled out in this label — matching how the
    // demo events (which also have no street-level text) present theirs.
    where: [real.area, startsAt ? '0,0 km từ bạn' : null, dayLong, time].filter(Boolean).join(' ▪︎ '),
    when: startsAt ? `${weekdayShort}, ${dayMonth} ▪︎ ${time}` : '',
    price: real.priceVnd ? formatVnd(real.priceVnd) : 'Miễn phí',
    seats: real.seatsRemaining != null ? String(real.seatsRemaining) : '',
    seatsLong: real.soldOut ? 'Hết chỗ' : (real.seatsRemaining != null ? real.seatsRemaining + ' chỗ trống' : ''),
    urgent: real.seatsRemaining != null && real.seatsRemaining <= 5,
    desc: real.description || '', included: real.included || '', includedItems: real.includedItems || [], intro: real.intro || '',
    host: real.organizerName || '', hostShort: real.organizerName || '', greeting: real.chatGreeting || '',
    gallery: [], orgGallery: [], orgName: real.organizerName || '', orgIg: '', orgDesc: '',
    orgSince: '', orgCount: 0, orgTrusted: false,
    cancelled: real.status === 'cancelled', cancelledHoursAgo: null, endedHoursAgo,
    soldOut: real.soldOut, inviteOnly: real.visibility === 'invite',
    until: null, untilLabel: '', startDate: startsAt,
    palette: 'concrete', isRealFallback: true,
  };
}

// The one place a "?ref=CODE" link is ever read from — runs once at module
// load (before React even mounts), so it survives however many redirects
// onboarding takes before someone actually finishes signing up. Stashed in
// localStorage (not component state) for the same reason: the code has to
// outlive a full page reload if that happens mid-flow, and the referral
// isn't redeemed until claimPendingReferralAndWelcome() runs, well after
// this. The query param is stripped from the visible URL immediately so it
// doesn't linger if the page gets shared or bookmarked from here.
// One purchase-form row per ticket; ticket 1 defaults to the buyer's name.
const makeAttendeeDrafts = (qty, firstName = '') =>
  Array.from({ length: Math.max(1, Math.min(6, qty || 1)) }, (_, i) => ({ name: i === 0 ? (firstName || '') : '', dob: '' }));

// A ticket PDF's "Open in banbe" link: https://<origin>/?claim=ATT-… (or a
// CLAIM- gift code). Read once at module load like "?ref=" below, parked in
// sessionStorage so it survives the sign-in detour, and consumed by the
// effect that opens the import sheet once there is a signed-in user.
const PENDING_CLAIM_KEY = 'banbe.pendingClaim';
if (typeof window !== 'undefined') {
  const params = new URLSearchParams(window.location.search);
  const claim = params.get('claim');
  if (claim && /^[A-Za-z0-9-]{6,40}$/.test(claim)) {
    try { sessionStorage.setItem(PENDING_CLAIM_KEY, claim.toUpperCase()); } catch { /* private browsing */ }
    params.delete('claim');
    const rest = params.toString();
    window.history.replaceState({}, '', window.location.pathname + (rest ? `?${rest}` : ''));
  }
}

const REFERRAL_STORAGE_KEY = 'banbe.pendingReferral';
if (typeof window !== 'undefined') {
  const params = new URLSearchParams(window.location.search);
  const ref = params.get('ref');
  if (ref && /^[A-Za-z0-9]{4,12}$/.test(ref)) {
    try { localStorage.setItem(REFERRAL_STORAGE_KEY, ref.toUpperCase()); } catch { /* private browsing, etc. */ }
    params.delete('ref');
    const rest = params.toString();
    window.history.replaceState({}, '', window.location.pathname + (rest ? `?${rest}` : ''));
  }
}

// A shared photo's "?org=<eventKey>" link, read once at module load the same
// way "?ref=" is above. Unlike a referral this isn't stashed for later — it
// routes straight to that event's organizer profile below, so the param is consumed
// here and stripped from the visible URL.
let sharedOrgEventKey = null;
if (typeof window !== 'undefined') {
  const params = new URLSearchParams(window.location.search);
  const org = params.get('org');
  if (org && EVENTS.some(e => e.key === org)) {
    sharedOrgEventKey = org;
    params.delete('org');
    const rest = params.toString();
    window.history.replaceState({}, '', window.location.pathname + (rest ? `?${rest}` : ''));
  }
}

// TASK D (2026-10-01 UX foundation pass) — the universal-link fallback:
// https://banbe.app/u/<handle> resolves via a plain SPA path (vercel.json
// has no server-side routing beyond the catch-all rewrite to index.html —
// see .claude/notes), so this app itself must recognize the path at boot,
// same "read once at module load, before React mounts" pattern as
// sharedOrgEventKey above. Works signed OUT too (get_public_profile() is
// granted to anon, migration 079) — a shared profile link must open
// something real without forcing a login wall first.
let sharedProfileHandle = null;
if (typeof window !== 'undefined') {
  const m = window.location.pathname.match(/^\/u\/([a-z0-9_]{3,24})\/?$/i);
  if (m) sharedProfileHandle = m[1].toLowerCase();
}

// Personal-vs-organizer hierarchy pass (2026-09-27) — the organizer
// profile's own universal-link sibling: https://banbe.app/org/<organizer_id>.
// A separate path from /u/<handle> on purpose (never that query param
// either — "?org=" above is already claimed for a shared EVENT's key, a
// naming trap this deliberately avoids) since organizer.id is its own
// free-form text slug (e.g. 'org_001'), not a personal handle. Same
// "read once at module load, before React mounts" pattern as both blocks
// above.
let sharedOrganizerId = null;
if (typeof window !== 'undefined') {
  const m = window.location.pathname.match(/^\/org\/([a-zA-Z0-9_-]{1,40})\/?$/);
  if (m) sharedOrganizerId = m[1];
}

// Interest surveys (Slice B) — the dedicated browser route,
// /surveys/<publicId>, read the SAME way as /u/<handle> and /org/<id>
// above: a real path (not a query param — audited against this repo's own
// existing precedent for a path-based deep link, since the SPA's catch-all
// vercel.json rewrite already serves index.html for any unknown path, so
// this JS still runs and still sees the real pathname on direct load AND
// refresh). Works signed out (get_survey_public is granted to anon) —
// responding still requires signing in, enforced by submit_survey_response
// itself, not by hiding the read-only preview behind a login wall first.
let sharedSurveyPublicId = null;
if (typeof window !== 'undefined') {
  const m = window.location.pathname.match(/^\/surveys\/([A-Za-z0-9_-]{1,64})\/?$/);
  if (m) sharedSurveyPublicId = m[1];
}

// Every screen a signed-out visitor may ever legitimately be on. Anything
// else while `!user` gets redirected to 'login' by the guard effect below
// — the enforcement point for "no guest browsing of any screen" (Task 1).
// Organizer Team pass (2026-09-27, Stage 2) — 'publicProfile' was
// missing here despite get_public_profile() being anon-granted and its
// own doc comments already claiming signed-out support (a pre-existing
// gap flagged, out of scope, in the prior ticket's own report) — now
// directly in scope: "tap a member card to open their personal public
// profile" must work for a signed-out Team page visitor too.
const GUEST_ALLOWED_SCREENS = new Set(['splash', 'langPick', 'themePick', 'login', 'resetPassword', 'policy', 'organizerProfile', 'organizerTeam', 'publicProfile', 'surveyPublic']);
// Account extension (2026-09-27, Stage 1) — the internal, organizer-mode-
// gated management screens: real event creation/editing, the organizer
// management dashboard, and event check-in. Deliberately EXCLUDES
// verifications/payout/documents/refund-queue screens, which the ticket's
// own "don't hide urgent host duties" rule keeps reachable regardless of
// organizerMode (those stay gated on `canHost` alone, unchanged).
const HOST_ONLY_SCREENS = new Set(['dashboard', 'create', 'attendance']);

const initialState = {
  screen: 'splash',
  // Whether the checkbox on Login.jsx has been ticked this session — reset
  // whenever Login mounts fresh; gates submitCurrentForm alongside the
  // existing email/password validity checks.
  policyConsent: false,
  // True only for a brand-new OAuth profile with no policy_accepted_at yet
  // (syncUser()) — Policy.jsx renders as a mandatory, no-back-out gate
  // instead of the ordinary "view the policy" screen while this is set.
  policyGateActive: false,
  // Task 4 (migration 056): one-time, account-level opt-in — mirrors
  // profiles.auto_email_documents, loaded in syncUser() like locale/theme.
  autoEmailDocuments: false,
  // Event preferences + onboarding (note 34, migration 162). Loaded once per
  // signed-in session by loadEventPreferences() once the account gate has
  // cleared; reset on sign-out/account switch. eventPrefs is null until
  // loaded (or when nothing was ever answered); eventPrefsVersion bumps on
  // every save (the For You refresh key); eventPrefsReturnScreen makes Back /
  // "Save and go back" land on that screen instead of the Account group.
  eventPrefs: null,
  eventPrefsVersion: 0,
  eventPrefsLoaded: false,
  needsSettingsOnboarding: false,
  needsPreferencesOnboarding: false,
  eventOnboardingIsNewAccount: false,
  eventPrefsReturnScreen: null,
  // BUG 4 (07-notifications.md's 2026-09-18 follow-up): the "•••" menu's
  // "Tắt loại thông báo này" action — filtered client-side only (see
  // loadNotifications()/the toast poll), no insert-side change to any of
  // the ~15 RPCs that write a notifications row.
  mutedNotificationKinds: [],
  // True only when Login was reached by force (the mandatory post-splash/
  // post-onboarding gate, or the guard effect catching an unauthenticated
  // screen change) rather than a deliberate "sign in to do X" prompt that
  // already has a real screen to fall back to — hides the Back link, since
  // there's nowhere legitimate for it to go.
  authMandatory: false,
  // Set once by the auth bootstrap effect's first resolution (real session
  // present or genuinely absent) — the guard effect waits for this so a
  // slow session check can't get misread as "signed out" and bounce a
  // returning user to Login before their restored session even arrives.
  sessionChecked: false,
  // Splash completion-gating fix (2026-09-30) — set once by Splash.jsx's
  // `message` listener when the logomotion iframe reports it has finished
  // one real animation cycle (`logomotion-complete`, distinct from the
  // pre-existing `logomotion-ready` asset-load signal — see
  // `public/logomotion/logomotion2309.html`'s own doc comment). The splash
  // auto-advance effect below waits on this instead of only ever firing on
  // a fixed timer.
  logomotionComplete: false,
  // Account regression fix pass (2026-09-27) — Item 3's real login race:
  // onAuthStateChange sets `screen` away from 'login' the instant a session
  // arrives, but `user` itself isn't set until syncUser's own async
  // profile/favorites fetches resolve. The mandatory-login guard effect
  // (below) reacts on every render, so it could see `sessionChecked && !user
  // && screen no longer 'login'` in that gap and immediately bounce back to
  // 'login' — leaving a freshly-authenticated session stuck there forever,
  // since nothing later re-opens it once user does arrive. This flag covers
  // that gap: set the instant a session is seen, cleared only once syncUser
  // has actually populated (or failed to populate) `user`.
  authSyncing: false,
  // Whether this browser has already been through language/theme
  // onboarding once (i.e. localStorage had a saved preferences record) —
  // read by the splash timer to decide whether to route into 'langPick'
  // or straight to 'home'/'login'. Overridden at init from that check.
  hasOnboarded: false,
  mode: 'goer',
  hasHosted: false,
  eventKey: 'bepnho',
  eventBackScreen: 'home',
  // The "Going"/"Saved" cards on Account open a filtered list of events —
  // always entered from (and returned to) Account, so there's no need for
  // a whole back-stack, just which filter is showing.
  eventListMode: 'going',
  // Which screen to return to from Inbox/Dashboard — both are reachable
  // from more than one place (Home's message icon vs Account's "Messages"
  // row; Home's host-page link vs Account's "Hosting" card), so a single
  // hardcoded back target sends at least one of those callers somewhere
  // it didn't come from.
  inboxBack: 'home',
  dashboardBack: 'home',
  loading: false,
  filter: 'all',
  // Home's second, independent chip row (12-home-filters.md) — multi-select,
  // AND-combined with `filter`/`area` above, not folded into either.
  filterAttending: false,
  filterSaved: false,
  filterSoldOut: false,
  // 2026-09-21 follow-up — rounds out the chip set (07-notifications.md).
  // notAttending/notSaved existed briefly then were removed the same day
  // per a follow-up ticket (redundant inverses cluttering the row).
  filterNotConfirmed: false,
  filterUpcoming: false,
  filterEnded: false,
  // Home "For You" gold-star chip (34-onboarding-for-you-criteria.md). Only ever
  // true while Home has >=1 matching event; Home auto-resets it otherwise.
  filterForYou: false,
  // Host reservation criteria (migration 162): criteria cache by event id,
  // the guest eligibility pre-check, and the create-flow retry target.
  eventCriteriaByKey: {},
  eligibilityByKey: {},
  createCriteriaRetryEventId: null,
  // Reserve.jsx's Name field, ONLY used for the empty-display_name case
  // (08-payment-documents.md/01-hold-payment.md's 2026-09-17 follow-up #6):
  // once a real profiles.display_name exists it's shown read-only from
  // s.user.name instead, never free-typed. formEmail is gone entirely — the
  // email field is always a read-only display of s.user.email now.
  formName: '',
  reserveNameSaving: false,
  reserveNameError: '',
  chatDraft: '',
  chatBack: 'event',
  shared: false,
  // Never pre-seeded: a brand-new, unregistered visitor should see only the
  // public event feed, not a "Your events" shelf built from placeholder
  // demo activity. Once signed in, these are replaced by that account's
  // real bookings (see the effect that loads them below).
  attending: [],
  tickets: {},
  myOrgEventKeys: [],
  myOrganizerIds: [],
  // Refund-discoverability investigation (2026-10-?? pass) — real bug
  // found: loadMyEvents() used to silently collapse `myOrganizerIds` to
  // `[]` on a FAILED organizers query (no `error` check at all), which is
  // indistinguishable from "genuinely owns zero organizers" to every
  // reader of `myOrganizerIds` — including loadRefundQueue's own gate,
  // which then permanently (until the next loadMyEvents call) reported an
  // empty refund queue for a host who actually owns organizers, with NO
  // visible error anywhere. 'idle' before the first call ever runs,
  // 'loading' while in flight, 'loaded' only after a GENUINE success
  // (including a real zero-organizer result), 'error' when the query
  // itself failed — callers that need to tell "confirmed none" apart from
  // "don't know yet" (loadRefundQueue, diagnostics) read this, never infer
  // it from `myOrganizerIds.length` alone.
  myOrganizerIdsStatus: 'idle',
  // ensure_my_organizer (migration 163) wiring — see lib/useEnsureOrganizer.js.
  ensureOrganizerStatus: 'idle', ensureOrganizerError: '',
  // Distinct from refundQueueLoading (in flight) — a transport error or
  // RPC success:false, surfaced in Verifications.jsx instead of silently
  // rendering as an empty queue ("do not show failed loading as empty").
  refundQueueError: '',
  // Dev-diagnostics only (point 2 of this ticket) — the exact reason
  // loadRefundQueue took the branch it took, one of: 'ok' |
  // 'awaiting-organizer-discovery' | 'organizer-discovery-failed' |
  // 'no-organizers' | 'rpc-error' | 'decode-error' | 'skipped-stale'.
  refundQueueGateReason: '',
  // Point 1 (new diagnostics) — structured, safe fields only (code/message/
  // details/hint/decode-stage text — never a token, bank detail or full
  // response payload), shown in the opt-in diagnostics panel.
  refundQueueErrorDetail: null,
  // Part B audit (2026-09-28) — Dashboard-identity-mismatch fix. Every
  // owned organizer row's events are (correctly, deliberately) still
  // unioned into `myOrgEventKeys` above — that flat list is the real
  // per-event OWNERSHIP gate used elsewhere (openNotification's/
  // openVerificationDetail's dual-role-account check, myRealOrgKeys'
  // review queue) and must keep covering every organizer this account
  // owns, not just one. But Dashboard's "Sự kiện sắp tới/đã qua" shelf
  // renders under ONE branded organizer header (`myOrganizerId`, the
  // deterministic earliest-created "primary" org — see the org fetch
  // above), and used to list every event in the flat `myOrgEventKeys`
  // union regardless of which of the account's several organizer rows
  // actually owned it — so an account seeded (migration 020) with, say,
  // Vườn Sau AND Phở Khuya AND Compound Garment showed all three
  // organizers' events under Vườn Sau's own header, while each event's
  // OWN EventDetail "Ghé <organizer>" correctly resolved its real,
  // per-event organizer_id join (never wrong — no bad FK here). This map
  // (event id -> its real organizer_id) lets Dashboard.jsx additionally
  // filter its branded shelf down to just the currently-shown organizer,
  // without narrowing the ownership gate itself.
  myOrgEventOrganizerId: {},
  // Stage 1 (2026-09-27 nav/discovery pass) — Account > Tổ chức's host
  // card own "Tổ chức từ <year> ▪︎ <N> sự kiện" line, same published-
  // events-only rule (status IN live/ended) as get_public_profile's
  // event_count/hosting_since_year (migration 091) — real event rows by
  // organizer_id, never a stored/static total. null count means "not
  // loaded yet"; 0 is a real, honest zero.
  myOrgPublishedEventCount: null,
  myOrgHostingSinceYear: null,
  // STAGE D (2026-09-25) — EventDetail's real gallery: one event's own
  // event_photos rows (see loadEventPhotos below).
  eventPhotos: [],
  eventPhotosLoading: false,
  // STAGE B (2026-09-25) — Organizer.jsx's real photo library: real
  // event_photos rows across all of an organizer's own events, scoped by
  // ownership (see loadOrganizerPhotos below).
  organizerPhotos: [],
  organizerPhotosLoading: false,
  // STAGE C (2026-09-25) — Dashboard's real "add photo" upload flow.
  eventPhotoUploadBusy: {}, eventPhotoUploaded: {}, eventPhotoUploadError: '',
  // Retention roadmap P1 — Home's "Cuối tuần này" section (see
  // loadWeekendEvents below): real live+public events, never the static
  // demo catalogue.
  weekendEvents: [],
  weekendEventsLoading: false,
  // Discovery-bug fix (2026-10-01) — Home's "Tất cả"/category feed itself
  // is STATIC-catalogue-only (`EVENTS` from data/events.js); a real,
  // admin-approved event with no static counterpart had no surface to ever
  // appear on other than the date-scoped weekend strip or a personal
  // saved/attending list. This is that missing general-purpose real-events
  // feed, merged into Home's main `feed` (see loadDiscoveryEvents below).
  discoveryEvents: [],
  discoveryEventsLoading: false,

  // ---- payments & documents (supabase migration 024) ----
  // banbe still never touches the money. These carry the details a guest
  // needs to transfer directly to the organizer, and the paperwork both
  // sides keep afterwards.
  paymentBookings: [],
  paymentsLoading: false,
  paymentBookingId: null,
  paymentCopied: '',
  paymentProofUploading: false,
  paymentProofError: '',
  paymentBack: 'profile',
  billingName: '', billingAddress: '', billingPhone: '', billingTaxCode: '',
  billingSaving: false, billingSaved: false, billingError: '',
  payoutBankName: '', payoutAccountName: '', payoutAccountNo: '', payoutMomo: '',
  payoutNote: '', payoutAddress: '', payoutTaxCode: '',
  payoutSaving: false, payoutSaved: false, payoutError: '',
  documents: [],
  documentsLoading: false,
  documentsError: '',
  // Which of the two Account rows opened the list, and from which side.
  documentsKind: 'invoice',
  documentsRole: 'guest',
  documentId: null,
  // Bug 2 (15-organizer-checkin.md follow-up): which screen opened the
  // viewer — 'documents' (the Receipts/Invoices list, the old fixed
  // behavior) or 'confirmed' (the ticket screen's own "Xem Receipt").
  // backFromDocument() reads this instead of a single hardcoded target.
  documentBack: 'documents',
  // Sub-section-of-a-group back-navigation fix (2026-09-29) — same idea as
  // documentBack above, but for the LIST screen itself: which screen
  // opened it (defaults to 'accountGroup', its only real entry point
  // today — see openDocuments' own comment). backFromDocuments() reads
  // this instead of a single hardcoded 'profile'.
  documentsBack: 'accountGroup',
  // Same documentBack/paymentBack pattern, extended (07-notifications.md's
  // 2026-09-18 follow-up) so every screen openNotification() can route to
  // remembers "opened from Notifications" and returns there specifically —
  // not Home, not wherever else. Each defaults to this screen's own
  // previous fixed behavior (unchanged for every non-notification entry
  // point) unless a caller opts in with a different `back` value.
  attendanceBack: 'dashboard',
  verificationsBack: 'profile',
  confirmedBack: 'home',
  // Signed URL for the current document's uploaded file (migration 056) —
  // '' while loading/absent (a legacy, pre-upload document has no
  // file_path at all and falls back to the old rendered-HTML viewer).
  documentFileUrl: '',
  documentUploadError: '',
  documentUploading: false,
  // How many buyers are currently holding a seat on this account's own
  // events, and how soon the nearest one lapses — the organizer half of the
  // Home countdown banners. null until loadOrganizerHoldingSummary() runs.
  organizerHoldingSummary: null,

  // ---- two-phase payment state machine (migrations 026/027) ----
  // PHASE 1 'holding' runs a countdown; PHASE 2 'pending_verification' has
  // no countdown at all — the seat is frozen until someone verifies it.
  paymentTxnId: '',
  paymentProofFile: null,
  paymentSubmitting: false,
  paymentSubmitError: '',
  // 14-organizer-checkin.md: the guest's rate-limited nudge while awaiting
  // the organizer's confirm window.
  nudgeSending: false,
  nudgeError: '',
  // 15-organizer-checkin.md follow-up: the guest's "Xem Receipt" button on
  // Confirmed.jsx — null while unchecked, a payment_documents row once one
  // is found, or `false` once checked and confirmed to not exist yet.
  receiptDoc: undefined,
  receiptRequestSending: false,
  receiptRequestError: '',
  receiptRequestSent: false,
  // The organizer's verification queue, and the admin dispute desk.
  verifications: [],
  verificationsLoading: false,
  verificationBusy: '',
  // Flow 2 (host refund -> guest confirmation): organizer's own refund
  // queue (owed/disputed claims only — host_marked_sent/guest_confirmed
  // aren't "active" anymore) and one guest-side claim for whichever
  // booking PaymentDetails.jsx is currently showing.
  refundQueue: [],
  refundQueueLoading: false,
  refundActionBusy: '',
  paymentRefundClaim: null,
  // Set by openNotification()'s refund_confirmed/_disputed/_overdue
  // branches — highlights the one claim the organizer tapped from a
  // notification, same idea as verificationsFocusBookingId just below but
  // a separate field (refundQueue isn't filtered by it, only scrolled/
  // flashed to, since a queue this small has no need to hide the rest).
  refundQueueFocusClaimId: null,
  // Refund MVP — goer's own saved refund destinations (many, migration 074).
  refundDestinations: [],
  refundDestinationBusy: false,
  refundDestinationError: '',
  refundDestinationsReordering: false,
  // Refund MVP — the goer's own persistent "Refunds" list (product rule A),
  // independent of any one booking/notification.
  myRefunds: [],
  myRefundsLoading: false,
  myRefundsBack: 'profile',
  refundAccountsBack: 'profile',
  // Set when RefundAccounts was opened FROM a specific refund claim's
  // "Thêm tài khoản mới" (Payment & refund accounts CTA) — on successful
  // save, the goer is returned straight to that claim with the new
  // account auto-selected, instead of staying on the accounts list.
  refundAccountsReturnToClaimId: null,
  refundAccountsReturnToBookingId: null,
  // Refund MVP — host's per-event Refund Center (Attendance's own new
  // "Hoàn tiền" section): owed/disputed claims for ONE event, each already
  // carrying its OWN recipient snapshot (never a live destinations join)
  // and a computed `eligible` flag.
  refundCenterClaims: [],
  refundCenterLoading: false,
  refundCenterError: '',
  refundCenterSelected: [],
  refundBatchBusy: false,
  refundBatchInFlight: false,
  refundBatchError: '',
  refundBatchResult: null,
  refundResendBusy: '',
  refundResendInFlight: new Set(),
  // 14-organizer-checkin.md: set by openVerificationDetail() (Attendance's
  // "Check payment" button) — narrows the queue below to exactly one
  // booking instead of the full list, whether it's the only pending item
  // or buried far down in it.
  verificationsFocusBookingId: null,
  // Refund-discoverability fix — a dedicated "Refunds" entry (same screen,
  // same data, no new backend/state) sets this so Verifications.jsx scrolls
  // straight to the "Hoàn tiền" section on open, instead of landing at the
  // top of the payment-verification list the shared route is normally
  // labeled for. Self-clears once applied (mirrors refundQueueFocusClaimId's
  // own one-shot pattern just below).
  verificationsScrollToRefunds: false,
  disputes: [],
  disputesLoading: false,
  disputeBusy: '',
  disputeEmailError: '',
  // The temporary dispute chat — one per escalated booking, purged after
  // resolve_dispute() closes it out. Keyed separately from the ordinary
  // chat (state.chatMessages) since it's a different table entirely.
  disputeChatBookingId: null,
  disputeChatMessages: [],
  disputeChatLoading: false,
  disputeChatDraft: '',
  disputeChatError: '',
  // resolved_at/purge_after off the dispute_threads row itself — read-only,
  // drives the retention countdown label (DisputeChatPanel.jsx) instead of
  // a delete button, since dispute_messages must survive until the 72h
  // purge (05-notify-retention.md). null for an open/unresolved thread.
  disputeChatThread: null,
  // 'payment' | 'refund' — which kind of dispute disputeChat* is currently
  // showing. Two different lifecycles behind two different RPCs (banbe rules
  // on a payment dispute; a refund dispute just settles between the two
  // parties), so the panel's own copy and read-only state both branch on it.
  disputeChatKind: null,
  // The REFUND half of the same panel: set alongside disputeChatBookingId =
  // null so exactly one of the two is ever the active chat, and a poll for
  // the other one can't stomp the visible thread (the panel gates its
  // rendered messages on which key is set).
  disputeChatRefundClaimId: null,
  // The yellow "dispute" section pinned at the top of Messages (Inbox.jsx) —
  // one entry per live dispute chat this account is a party to, from
  // get_my_dispute_chats (migration 129). Includes refund disputes, which
  // until now had no chat of their own at all.
  disputeChats: [],
  disputeChatsLoading: false,
  disputeChatsError: '',
  // Which of those entries is expanded into its chat inline. null = all
  // collapsed. Screen-local UI state (Inbox.jsx owns the same kind of thing
  // in useState), just hoisted so a "jump to this chat" button elsewhere —
  // the payment/refund screens' yellow entry, a dispute_message
  // notification — can expand the right one on arrival.
  openDisputeChatThreadId: null,
  auditTrail: [],
  auditBookingId: null,
  // pay-proof storage path -> signed viewable URL, for whichever rows
  // Verifications/Disputes last loaded — see signProofUrls.
  proofUrls: {},
  located: null,
  askingLocation: false,
  userCoords: null,
  user: null,
  accountType: 'participant',
  organizerMode: false,
  organizerModeError: '',
  organizerModeBusy: false,
  editNameValue: '',
  editNameError: '',
  editNameSaving: false,
  // TASK 4 (Reserve→edit-name pass) — where goEditName() was actually
  // called from; see its own comment.
  editNameReturnScreen: 'profile',
  // TASK D (2026-10-01 UX foundation pass) — shareable profile card.
  editProfileHandle: '', editProfileName: '', editProfileBio: '', editProfileCity: '',
  editProfileInterests: '', editProfileTheme: 'default', editProfileError: '', editProfileBusy: false,
  // Organizer Team pass (2026-09-27, Stage 3) — a separate long-form
  // "Giới thiệu" (never overwrites the short bio above) + optional
  // social links, both validated server-side (sanitize_social_links,
  // migration 102) regardless of what this form lets through.
  editProfileIntroLong: '', editProfileLinks: [], editProfileLinksOpen: false,
  // Personal-vs-organizer hierarchy pass (2026-09-27) — this screen is now
  // PERSONAL-ONLY (own display_name, own QR/edit — never an organizer
  // edit/guest-preview affordance; see PublicProfile.jsx's own comment).
  publicProfile: null, publicProfileLoading: false, publicProfileError: '', publicProfileBack: 'profile', publicProfileHandle: '',
  profileLinkCopiedFlash: false,
  // The organizer's own, separate public profile — a standalone screen,
  // reachable by organizer id (never the owner's personal handle) so a
  // shared /org/<id> link works without knowing who owns it.
  organizerProfile: null, organizerProfileLoading: false, organizerProfileError: '', organizerProfileBack: 'profile', organizerProfileId: '',
  organizerProfileUpcoming: [], organizerProfileExtrasLoadedFor: '',
  // Interest surveys (Slice B) — the public/browser+in-app response
  // screen. `surveyPublic` is exactly get_survey_public()'s return shape
  // (never raw table rows) so the public route can never expose more than
  // that RPC's own allowlisted fields.
  // Section 5 — "Help Shape Upcoming Events". Source-of-discovery pass —
  // loaded by its OWN `loadHomeSurveyDiscovery()`/`loadMoreHomeSurveyDiscovery()`,
  // reading `get_public_survey_discovery()` (migration 120) directly, no
  // longer built inside `loadHomeStories()` from `stories` rows — every
  // PUBLISHED eligible public survey is discoverable, whether or not it was
  // ever explicitly shared to a story. One row per DISTINCT survey id
  // (never collapsed by organizer).
  homeSurveyDiscovery: [],
  // Visibility-investigation fix — distinct loading/error states so a real
  // query/decode failure is never silently indistinguishable from "no
  // public surveys right now". Loading starts true so the very first paint
  // doesn't flash "nothing here" either.
  homeSurveyDiscoveryLoading: true,
  homeSurveyDiscoveryError: '',
  homeSurveyDiscoveryLoadingMore: false,
  // Real "more exist on the server" signal (keyset pagination) — distinct
  // from the loaded array's own `.length`, so a preview-row cap on Home is
  // never confused with the true total.
  homeSurveyDiscoveryHasMore: false,
  // Compact Home discovery pass — collapsed by default (the section takes
  // too much vertical space once many hosts publish). Lives in BanBeContext
  // state, not local component state, so it survives Home re-rendering
  // around a trip into the survey modal and back; reset to false on
  // logout (see `logout()` below) and on a signed-out loadHomeStories()
  // call so a new account never inherits a stale previous user's choice.
  homeSurveyDiscoveryExpanded: false,
  surveyPublic: null, surveyPublicLoading: false, surveyPublicError: '', surveyPublicBack: 'home', surveyPublicId: '',
  // The signed-in respondent's own current answer (or null if none yet) —
  // loaded separately since get_survey_public is anon-reachable and must
  // never carry any one respondent's data.
  mySurveyResponse: null, mySurveyResponseLoading: false,
  // Draft answers, sessionStorage-backed (keyed by public_id) so they
  // survive a sign-in round trip — "preserve entered answers through
  // auth," the task's own explicit requirement for the browser page.
  surveyDraft: { interestLevel: null, dateOptions: [], groupSize: null, locationOptions: [], budgetOption: null, activities: [], freeText: '', contactConsent: false },
  surveyResponseSubmitting: false, surveyResponseError: '', surveyResponseSuccess: false,
  // Already-answered respondents land on a read-only summary first ("You
  // Have Already Responded") rather than a fresh-looking editable form —
  // this flips it open. Reset on every fresh load (goSurveyPublic/
  // openSurveyStoryModal) so re-opening never silently starts in edit mode.
  surveyEditMode: false,
  // Section 2 — survey answered inside a story's "Answer Survey" popup
  // instead of the full-page/browser route. `surveyAsModal` is read by
  // SurveyPublic.jsx to render itself as the modal's content (no page
  // chrome) vs. the full standalone screen; `storySurveyModalPublicId`
  // is what App.jsx mounts the modal wrapper on, and what StoryViewer.jsx
  // watches to pause its own auto-advance while it's open — see
  // openSurveyStoryModal/closeSurveyStoryModal below.
  surveyAsModal: false, storySurveyModalPublicId: null,
  // Section 3 — lightweight, non-banbe-account respondent email
  // verification (outside-banbe audience), reusing the existing OTP-by-
  // email mechanism (api/auth send_email_code, mode: 'respond') rather than
  // a parallel auth system. Never labels anything "verified" until
  // supabase.auth.verifyOtp() itself actually succeeds.
  surveyRespondStep: 'idle', surveyRespondEmail: '', surveyRespondCode: '',
  surveyRespondSending: false, surveyRespondError: '', surveyRespondIsNewAccount: false,
  surveyRespondConsent: false,
  // Host management (Hosting -> Surveys & Event Ideas).
  mySurveys: [], mySurveysLoading: false, mySurveyCreateBusy: false, mySurveyCreateError: '',
  // Slice C — suggested event drafts generated server-side from closed
  // surveys' responses (migration 143, survey_event_candidates).
  mySurveyCandidates: [], mySurveyCandidatesLoading: false, mySurveyCandidatesError: '', mySurveyCandidatesBusySurveyId: null,
  // Task 4 — "Share To Story": an explicit preview-then-Publish step, never
  // an automatic post (task's own "show a preview and require explicit
  // Publish; no automatic posting" rule).
  surveyShareToStoryTarget: null, surveyShareToStoryBusy: false, surveyShareToStoryError: '',
  // Account extension (2026-09-27, Stage 3) — one role-scoped KPI
  // dashboard, reached from a "Số liệu & báo cáo" row on each visible
  // Account tab. `reportsScope` is 'personal'|'host'|'admin' (never
  // inferred from `organizerMode`/`accountType` inside the screen itself —
  // set explicitly by whichever row opened it, so the RPC call's own
  // scope always matches what the user actually tapped). `reportsRangeDays`
  // is 7/30/90 or 'custom' (paired with reportsCustomStart/End, plain
  // 'YYYY-MM-DD' strings from a native date input). `reportsExpanded` is a
  // Set of metric keys currently expanded — starts empty (every card
  // collapsed) per the ticket's own "compact collapsible card" ask.
  reportsScope: 'personal', reportsOrganizerId: '', reportsBack: 'profile',
  reportsRangeDays: 30, reportsCustomStart: '', reportsCustomEnd: '',
  reportsData: null, reportsLoading: false, reportsError: '',
  reportsExpanded: new Set(),
  reportsExportBusy: '',
  // Organizer Team pass (2026-09-27, Stage 1) — real, opt-in organizer
  // membership (organizer_members, migration 098). `myOrganizerInvites`
  // is this account's OWN pending invites (any organizer); `myTeamMemberships`
  // is this account's own ACCEPTED memberships, each with its own
  // `public_visible` switch; `orgTeamRoster` is the FULL roster (every
  // status) for whichever organizer the owner is currently managing in
  // Dashboard — never fetched for an organizer this account doesn't own.
  myOrganizerInvites: [], myTeamMemberships: [], orgTeamRoster: [], orgTeamRosterLoading: false,
  // Admin Team pass (2026-10-02, migration 121) — see that migration's own
  // doc comment for the full RBAC model. `canManageAdmins` is a plain
  // profile column read back on sync, never client-derived/assumed.
  canManageAdmins: false, myAdminInvite: null,
  adminRoster: [], adminInvites: [], adminTeamLoading: false,
  adminInviteEmailDraft: '', adminInviteBusy: false, adminInviteError: '',
  adminInviteConfirmEmail: null, revokeAdminInviteConfirmId: null, revokeAdminConfirmId: null,
  orgTeamInviteHandle: '', orgTeamInviteRole: '', orgTeamInviteError: '', orgTeamInviteBusy: false,
  // Organizer Team pass (2026-09-27, Stage 2) — the public Team page
  // (get_organizer_team) and this account's own pending event-credit
  // invites ("did I really help organize this event" — never inferred
  // from bookings/check-ins).
  organizerTeam: null, organizerTeamLoading: false, organizerTeamError: '', organizerTeamBack: 'organizerProfile', organizerTeamOrganizerId: '',
  myEventCredits: [], myConfirmedEventCredits: [], orgEventCreditAssignBusy: '',
  // TASK E (2026-10-01 UX foundation pass) — Banbe Pulse.
  eventOrgStats: {},
  pulseDaily: [], pulseWeekly: [], pulseOpen: false, pulseTab: 'daily', pulseOrganizerSheet: null,
  pulseDailyLoading: false, pulseWeeklyLoading: false,
  // Account deletion (Task 2, Account/Settings pass) — a self-contained
  // sheet's worth of wizard state, mirrored on iOS (AppState.swift). Step
  // is a plain string enum, not a `Screen`, since this never needs a route/
  // deep-link/back-swipe of its own — it's always opened from and closed
  // back to the `preferences` AccountGroup screen.
  deleteAccountOpen: false, deleteAccountStep: 'intro', // 'intro' | 'reason' | 'confirm' | 'submitting' | 'done'
  deleteAccountReasonCode: '', deleteAccountReasonText: '',
  deleteAccountPhraseInput: '', deleteAccountReauthSent: false, deleteAccountReauthCode: '',
  deleteAccountReauthVerified: false, deleteAccountReauthBusy: false, deleteAccountReauthError: '',
  deleteAccountSubmitting: false, deleteAccountError: '', deleteAccountOAuthProvider: null,
  // 2026-09-25 fix pass — third Pulse tab: individual event photos ranked
  // by real engagement (photo_likes/photo_shares, migration 083), a
  // separate ranking from the event-level one above — never merged into
  // the same signals/list. Like/share counts and this user's own liked
  // state for these SAME photo ids now live in the canonical
  // `photoEngagement` map (see its own comment) — not a separate
  // Pulse-only copy, so a like/share here or on EventDetail/Organizer/
  // PhotoViewer is immediately visible in both places.
  pulsePhotos: [], pulsePhotosLoading: false, pulsePhotoSheet: null,
  notifications: [],
  unreadNotifications: 0,
  // Inbox tab badge (BottomTabBar.jsx) — count of messages where
  // read_at IS NULL and sender_id isn't me, across every thread I'm a
  // participant in (guest or organizer side). Refreshed by its own poll —
  // see the effect near loadInboxThreads.
  unreadMessages: 0,
  // Batch-fetched by loadNotifications() alongside `notifications` itself —
  // avatarSourceFor() (src/lib/notifications.js) reads these three lookup
  // tables instead of a join per row. Keyed by id, not by notification —
  // several notifications about the same booking/event share one entry.
  notificationBookingById: {},
  notificationEventPhotoByEventId: {},
  notificationAvatarByUserId: {},
  // Ephemeral in-app toasts, surfaced proactively (see the polling effect
  // near loadNotifications) — separate from `notifications` itself, which
  // stays the permanent, pull-based inbox (Notifications.jsx). Each entry:
  // { id, notification, leaving }. `leaving` drives the exit animation
  // before pushToast's own timeout actually removes it from this array.
  toasts: [],
  // Set by openNotification() for a 'dispute_message' notification —
  // DisputeChatPanel.jsx reads this itself (rather than every parent
  // screen threading a prop through) to scroll to and briefly highlight
  // `messageId`, or just scroll to the bottom if it's null (an older
  // notification row from before migration 050 added message_id). Cleared
  // once DisputeChatPanel has actually applied it.
  chatHighlight: null,
  // Set by openNotification()'s 'receipt_requested' branch — the same
  // scroll-to-and-highlight idea as chatHighlight above, but for
  // Attendance.jsx's per-guest "Upload receipt" control instead of a chat
  // message. Cleared once Attendance.jsx has applied it.
  attendanceHighlightBookingId: null,
  // This account's own shareable code — null until signed in and loaded.
  referralCode: null,
  referralShared: false,
  authMode: 'login',
  authReturnScreen: 'home',
  authBackScreen: 'home',
  // 'code' (email a one-time code) or 'password' — a per-tab choice, not
  // persisted; every account can use either, regardless of which one it was
  // created with (password sign-up still confirms via an emailed code).
  authMethod: 'code',
  loginEmail: '',
  loginNickname: '',
  loginPhoneNumber: '',
  loginCode: '',
  loginEmailCode: '',
  loginPassword: '',
  loginPasswordConfirm: '',
  // Which supabase.auth.verifyOtp `type` the pending emailed code should be
  // verified as — set when the code is requested, since the login/signup
  // tab could in principle change before the code is entered.
  pendingEmailMode: null,
  resetRequested: false,
  // Account > Security: setting this account's own password while already
  // signed in (the Login screen's fields are a separate, signed-out flow).
  securityPassword: '',
  securityPasswordConfirm: '',
  securityBusy: false,
  securityError: '',
  securitySaved: false,
  securityResetSent: false,
  newPassword: '',
  newPasswordConfirm: '',
  resetPasswordBusy: false,
  resetPasswordError: '',
  loginSent: false,
  loginSentVia: null,
  payMode: 'now',
  qty: 1,
  // Per-attendee tickets (migration 151): one { name, dob } per ticket on the
  // purchase form, the named tickets of the booking on screen, and tickets
  // other accounts imported into this one (migration 152).
  attendeeDrafts: [{ name: '', dob: '' }],
  bookingAttendees: [],
  importedTickets: [],
  importedTicketOpen: null,
  importOpen: false, importCode: '', importBusy: false, importError: '', importNotice: '',
  lang: 'vi',
  theme: 'light',
  area: 'all',
  createName: '',
  createCats: [],
  createPalette: 'concrete',
  createSent: false,
  createError: '',
  createDesc: '',
  createLoc: '',
  // Address-autocomplete fix pass (2026-09-28) — replaces the old single-
  // shot "type free text, tap Confirm, get ONE geocode result" flow.
  // `createLoc` is now purely the live search box's own text; a selected
  // suggestion's DECOMPOSED fields live separately below so the concise
  // location line can show the district alone while the full address is
  // still available for validation/re-editing. `createLocConfirmed` is
  // the same trust gate migration 094 introduced for lat/lng (never
  // silently trusting free text), now doubling as the RPCs' own
  // `p_address_verified` — see submitCreateEvent's own comment. There is
  // no more "skip" — publishing now REQUIRES a verified address (this
  // ticket's own explicit requirement), so an unresolved location simply
  // blocks submit with a clear inline message instead.
  createLat: null,
  createLng: null,
  createLocLabel: '',
  createAddressLine: '',
  createDistrict: '',
  createCity: '',
  createPostalCode: '',
  // Location hierarchy (migration 112) — captured from the confirmed
  // Nominatim suggestion (shapeAddressSuggestion) alongside the fields
  // above and sent as the RPCs' own optional p_country_code/
  // p_state_province/p_neighborhood. Empty = "unknown", sent as NULL.
  createCountryCode: '',
  createStateProvince: '',
  createNeighborhood: '',
  createLocConfirmed: false,
  createAddressSuggestions: [],
  createAddressSearching: false,
  createAddressSearchError: '',
  // Date/time picker fix (Stage B, 2026-09-26) — two canonical native-input
  // values (`<input type="date">`'s own "yyyy-mm-dd", `<input type="time">`'s
  // own "HH:mm") REPLACE the old single free-text `createDate` field this
  // used to be, which relied on a hand-rolled "dd.mm ▪︎ HH:mm" regex parse
  // AND a hardcoded "2026-" year prefix — silently wrong for any other year
  // and impossible to validate against "today" without re-parsing. Combined
  // into starts_at server-side exactly the same way (migration 087/088's
  // `(p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'`).
  createEventDate: '',
  createEventTime: '',
  createPrice: '',
  createSeats: '',
  // Strict invite-only events (migration 113) — 'public' | 'invite'.
  // Deliberately separate from `events.approval` (instant/manual, not yet
  // exposed in this form): visibility is who can even see/book the event;
  // approval is whether a booking still needs the host's manual OK. An
  // invite-only event is not auto-approved by being private — set_event_
  // visibility() never touches `approval`, and admin review (085) still
  // applies to every event regardless of visibility.
  createVisibility: 'public',
  // Host reservation criteria (migration 162). createCriteria is the form value;
  // createCriteriaLoaded is what the event had when editing started;
  // createCriteriaLoad: 'ready' | 'loading' | 'failed' | 'unsupported'.
  createCriteria: { version: 1, mode: 'everyone' },
  createCriteriaLoaded: { version: 1, mode: 'everyone' },
  createCriteriaLoad: 'ready',
  createPhotos: 0,
  // Real cover/gallery + structured "Bao gồm" (migration 087) — the actual
  // picked File objects live in CreateEvent.jsx's OWN local component state
  // (never serialized into this global store — a File isn't something this
  // app persists/replays), previews only. `createIncludedItems`: up to 3
  // { label, detail } items, validated the same way (length/count) the
  // server does — client-side is a UX nicety, the RPC is the real gate.
  createIncludedItems: [],
  // Keyword-search fix (migration 108) — free-text, comma-separated
  // keywords so an event surfaces in Map's search box beyond a literal
  // name/district match. Left blank, createSubmit defaults it to the
  // event's own selected category labels (never silently empty).
  createKeywords: '',
  // Host's optional opening message for "Message host" (events.chat_greeting, migration 156).
  createChatGreeting: '',
  createChatGreetingEn: '',
  createMediaError: '',
  // "Giới thiệu sự kiện" (migration 088) — a separate, longer host-written
  // editorial description, never conflated with createDesc ("Mô tả") or
  // createIncludedItems ("Bao gồm"). Plain text with blank-line paragraph
  // breaks only, never rendered as HTML.
  createIntro: '',
  // Event review queue — set while CreateEvent.jsx is editing/resubmitting
  // an existing (previously rejected) event rather than creating a new
  // one; createSubmit() branches on this. Cleared on a fresh "create" nav.
  createEditEventId: null,
  // Stage 1 — the real root screen/tab dock + was tapped from (or
  // 'dashboard' for goEditEvent's own entry); createBack() reads this
  // instead of hard-routing to a fixed screen. null until goCreate/
  // goEditEvent set it.
  createOriginScreen: null,
  // Admin-only "Sự kiện chờ duyệt" queue (event review queue follow-up).
  adminEvents: [],
  adminEventsLoading: false,
  adminEventBusy: '',
  // TASK 5 (Account badges pass) — count-only sibling of `adminEvents`,
  // powering the "adminReview" group-card badge without loading the full
  // queue on every Account mount; see loadPendingEventsCount()'s own comment.
  pendingEventsCount: 0,
  adminEventError: '',
  orgRegName: '',
  orgRegIg: '',
  orgRegDesc: '',
  // Organizer Team pass (2026-09-27, Stage 3) — separate long-form intro
  // + optional social links for the ORGANIZER (never overwrites
  // orgRegDesc/organizers.about above).
  orgRegIntroLong: '', orgRegLinks: [], orgRegLinksOpen: false,
  // Host tab's own profile card (Stage D, 2026-09-26) — this account's
  // organizer row id + its real avatar_path (migration 090). Only one
  // organizer per account is supported (same standing assumption
  // create_event_draft's own `ORDER BY created_at LIMIT 1` already makes —
  // nothing else in this codebase supports multi-organizer accounts
  // either).
  myOrganizerId: null,
  myOrganizerAvatarPath: '',
  myOrganizerAvatarR2Ref: '',
  orgProfileSaving: false,
  orgProfileError: '',
  orgProfileSaved: false,
  // iPhone fix pass (2026-09-26) — Account's own Cá nhân/Tổ chức tab, lifted
  // out of Account.jsx's local component state into the global store.
  // Local state used to reset to 'personal' every time Account.jsx
  // unmounted (any navigation away and back — Preferences, the new public-
  // profile link, even the pre-existing EditProfile flow — remounts it,
  // since screen switching is a plain `SCREENS[state.screen]` conditional
  // render, not a persistent tree), silently losing whichever tab a host
  // was actually on.
  accountTab: 'personal',
  accountGroupKey: null,
  guideKey: null,
  following: [],
  refunds: {},
  gaveTicket: false,
  areaAsking: false,
  holdDeadline: null,
  now: Date.now(),
  favorites: [],
  // Canonical real-event cache, keyed by real `events.id` (retention
  // roadmap follow-up — see loadRealEventsById below). `undefined` (key
  // absent) = not yet requested/still loading; `null` = requested but the
  // row doesn't exist or RLS denied it (an honest "unavailable", never
  // silently dropped); an object = the shaped real row. Shared by Home's
  // "Sự kiện của bạn" strip, EventList's Saved/Going/Completed lists and
  // the weekend section — one lookup, not three copies of the same query.
  realEventsById: {},
  // Withdrawal (migration 107) + resubmission-limit surfacing — see
  // withdrawEventSubmission/loadResubmissionStatus below.
  withdrawEventBusy: false,
  withdrawEventError: '',
  resubmissionStatusByEvent: {},
  invited: [],
  orgVerifyRequested: false,
  attendanceEventKey: null,
  attendanceGuests: [],
  attendanceLoading: false,
  // { url, organizer, eventKey } while a gallery photo is open in the viewer.
  photoViewer: null,
  // Snapshot of MapExplore.jsx's own local state (camera center/zoom, sheet
  // detent, filters, selected event, list scroll position), saved right
  // before navigating to Event Detail from the in-map preview card's CTA so
  // MapExplore can restore it instead of re-initializing from scratch on
  // return — App.jsx's Shell unmounts/remounts the whole screen component
  // on every `screen` change, so this has to live up here to survive that.
  // Explicitly cleared (not just left stale) on an intentional exit via the
  // "← Đóng" button, so reopening the map from Home later starts fresh.
  mapExploreState: null,
  // Photo identity/engagement fix (real event_photos.id, not a URL) —
  // canonical, keyed by event_photos.id, shared by EventDetail's/
  // Organizer's photo grids, the full-screen PhotoViewer AND Banbe Pulse's
  // photo tab — the ONE source of truth for a real photo's like/share
  // counts and this user's own liked state, so no two surfaces can ever
  // disagree after a toggle/refetch. { [photoId]: { likeCount, shareCount,
  // likedByMe } }. `photoEngagementBusy` guards a double tap/racing toggle
  // per photo id, same pattern the old Pulse-only togglePulsePhotoLike used.
  photoEngagement: {}, photoEngagementBusy: {},
  photoShared: false,
  // True when this visit arrived on a shared "?org=" link, which is the only
  // time the organizer page offers to open the native app instead.
  arrivedFromSharedLink: false,
  scanningQr: false,
  qrScanError: '',
  reasonPrompt: null,
  reasonPromptBusy: false,
  reasonPromptError: '',
  chatThreadId: null,
  chatMessages: [],
  // The other participant's display name for the Chat header (host name
  // when a guest is viewing, guest name when the organizer is viewing) —
  // set once per openThread()/openChatFor() call, since it depends on which
  // side of the thread the signed-in account is on, not just the event.
  chatOtherName: '',
  // "Draft" conversation (migration 156 pass): a goer tapped "Message <host>"
  // and no threads row exists yet. `chatDraftOrganizerId` is the organizer the
  // row will be inserted for at the FIRST real send (ensureChatThread) —
  // opening and backing out writes nothing, so nothing shows in the inbox.
  chatDraftOrganizerId: null,
  // Host's opening message (events.chat_greeting, or a catalogue event's
  // hardcoded greeting) — display-only first bubble in Chat.jsx, never a
  // messages row.
  chatGreeting: '',
  chatGreetingEn: '',
  // Event key the greeting applies to (guest side only); null = show none.
  chatGreetingFor: null,
  // Id of the first unread (read_at IS NULL, not sent by me) message at the
  // moment this thread was opened — drives the "— Chưa đọc —" divider in
  // Chat.jsx. Computed once per open (see loadChatMessages's `computeDivider`
  // option) and never recomputed by the 4s poll, so it doesn't chase newly-
  // read messages around while the thread stays open.
  chatUnreadDividerId: null,
  // Task 5 (2026-09-22 twelfth follow-up) — set by sendChatViewerReply()
  // right when a reply/reaction sent FROM ChatPhotoViewer lands, so Chat.jsx
  // (already mounted underneath — the viewer is an overlay, not a separate
  // screen) can scroll that exact message into view and clear the flag;
  // chatFocusComposer only true for a typed reply (not a one-tap quick
  // reaction), so a reaction never force-opens the keyboard.
  chatScrollToMessageId: null,
  chatFocusComposer: false,
  // path -> signed URL (10min), for chat message attachments — same
  // pattern as `proofUrls`/signProofUrls (chat-attachments is a private
  // bucket, see supabase/migrations/065).
  chatAttachmentUrls: {},
  // { messageId, attachmentPath, url, width, height, senderLabel, originRect,
  //   forwardOpen } while a chat photo is open in its own dedicated
  // fullscreen viewer (07-notifications.md follow-up) — deliberately a
  // SEPARATE piece of state from `photoViewer` above, per this ticket's own
  // instruction not to confuse a chat attachment with an event-gallery
  // photo (different action set: Save/Share/Forward, not Like/Save event).
  chatPhotoViewer: null,
  // Active (unexpired) stories, grouped by organizer, loaded by
  // loadHomeStories() — [{ organizerId, orgName, orgImg, storyIds: [...],
  // stories: [{id, mediaPath, url, width, height, createdAt}], allViewed }].
  homeStories: [],
  // { organizerId, index, stories: [...] } while the fullscreen story
  // progression viewer is open. A separate concept from chatPhotoViewer/
  // photoViewer (14-photo-viewer.md) — its own dismiss/back semantics.
  storyViewer: null,
  // Task 4C (2026-09-22 follow-up) — set only by goEventFromStory(), holds
  // the exact StoryViewer position to restore when backFromEvent() returns
  // from an event opened via a story's own card/CTA.
  storyReturnSnapshot: null,
  // BUG 3 fix (2026-09-22 follow-up) — true only while the currently-open
  // Event Detail was reached via goEventFromStory(); the single source of
  // truth EventDetail.jsx's back-label override and backFromEvent()'s own
  // routing both read, rather than each inferring it independently.
  eventBackIsStory: false,
  // The story's own host name at the moment goEventFromStory() was called
  // — read by EventDetail.jsx's back-label override ("Tin của <host>").
  storyReturnHostName: null,
  // { file, url } while the "create a story" camera/picker preview
  // (Retake / Use Photo) is open, from Account.
  storyCreatePreview: null,
  storyCreateBusy: false,
  // TASK 1 (dock "+" menu pass) — one-shot "open this picker" requests;
  // StoryCreateOverlay.jsx clicks its hidden input then resets the flag.
  storyLibraryPickerOpen: false,
  storyCameraPickerOpen: false,
  // Ids of stories this account has already recorded a view for THIS
  // SESSION — local optimism so the ring subdues immediately on close,
  // without waiting for a re-fetch. Reconciled against real story_views
  // rows on every loadHomeStories() anyway.
  storyViewedIds: [],
  inboxThreads: [],
  // Per-participant star/archive state for a thread (thread_preferences,
  // migration 065) — keyed by threadId: { starred, archived }. NOT stored
  // on `threads` itself since a guest and the organizer on the same thread
  // need independent state (one side archiving shouldn't hide it from the
  // other). Loaded alongside inboxThreads.
  inboxThreadPrefs: {},
  // 'active' | 'archived' — which Inbox.jsx is currently showing (Task 1b).
  inboxView: 'active',
  calAdded: false,
  // Bug 3 (15-organizer-checkin.md follow-up): the event key the calendar
  // picker sheet is currently open for, or null when closed.
  calendarPickerFor: null,
  booking: null,
  reserveError: '',
  // The real events row's own status/starts_at for whichever event is
  // currently open — null until fetched, or once no matching row exists
  // (a purely local/preview event). Kept separate from the static demo
  // catalogue (data/events.js) rather than merged into it, so curEvent can
  // layer a live ended/cancelled read on top without ever inventing cosmetic
  // fields (photos, description, …) the row doesn't have.
  liveEvent: null,
  // 2026-09-21 follow-up (see 07-notifications.md) — same idea as
  // `liveEvent` above, but BATCHED across every catalogue key Home might
  // show at once (its own "Sự kiện của bạn" strip + the new "Sắp diễn ra"/
  // "Đã kết thúc" filters), rather than one row for whichever single event
  // is currently open. Keyed by catalogue key (== events.slug). Fixes a
  // real bug: `EVENTS`' own `endedHoursAgo` (src/data/events.js) is a
  // hardcoded number baked in at module-load time (e.g. `phokhuya: {
  // endedHoursAgo: 10 }`) that never increases as real time passes — the
  // "Clears after 48h" caption was checking against that frozen number, so
  // an event could sit at "10 hours ago" forever and never actually clear.
  homeLiveEvents: {},
};

// toggleHomeFilter()'s key -> state-field map (Home.jsx's HOME_EXTRA_FILTERS,
// 07-notifications.md's 2026-09-21 follow-up) — module scope since it's
// static, not recreated every render.
const HOME_FILTER_STATE_KEY = {
  attending: 'filterAttending', notConfirmed: 'filterNotConfirmed',
  saved: 'filterSaved',
  soldOut: 'filterSoldOut', upcoming: 'filterUpcoming', ended: 'filterEnded',
};

// Location hierarchy (2026-09-30, migration 112) — the old hardcoded
// `AREAS` table (6 fixed keys, each a hand-rolled `e.meta.includes(...)`
// predicate) is replaced by the data-driven tree in src/lib/locationTree.js.
// `s.area` now holds a location node id ('all' | 'loc:VN|a:Bình Thạnh' | …);
// an old key ('q1', 'thaodien', …) is migrated by migrateLegacyAreaKey().

// Predefined reasons — an organizer reversing a check-in or cancelling a paid
// booking must pick one of these (no free text) so the guest's notification
// always says something concrete.
export const UNDO_CHECKIN_REASONS = [
  { key: 'wrong_person', vi: 'Nhầm người', en: 'Wrong person' },
  { key: 'tapped_by_mistake', vi: 'Bấm nhầm', en: 'Tapped by mistake' },
  { key: 'not_arrived', vi: 'Khách chưa thực sự có mặt', en: "Guest hasn't actually arrived" },
  { key: 'other', vi: 'Khác', en: 'Other' },
];
export const CANCEL_BOOKING_REASONS = [
  { key: 'event_changed', vi: 'Sự kiện đổi lịch hoặc huỷ', en: 'Event rescheduled or cancelled' },
  { key: 'payment_incomplete', vi: 'Không thanh toán đúng hạn', en: 'Payment not completed in time' },
  { key: 'policy_violation', vi: 'Vi phạm quy định', en: 'Policy violation' },
  { key: 'other', vi: 'Khác', en: 'Other' },
];
// 14-organizer-checkin.md (Bug 2b): "Có nhận khách này không?" ▪︎ "Từ chối".
export const REJECT_GUEST_REASONS = [
  { key: 'no_seats_left', vi: 'Hết chỗ thật sự', en: 'Actually out of seats' },
  { key: 'payment_mismatch', vi: 'Không khớp với sao kê', en: "Doesn't match the statement" },
  { key: 'suspected_fraud', vi: 'Nghi ngờ gian lận', en: 'Suspected fraud' },
  { key: 'other', vi: 'Khác', en: 'Other' },
];

// Shared by the splash timer and finishOnboarding() (Task 1 — no guest
// browsing of any screen): decides where to land once onboarding/splash is
// done — 'home' (or the shared-org-link target) if actually signed in,
// otherwise the mandatory Login gate. authReturnScreen preserves the
// intended destination so signing in lands there instead of always Home;
// authMandatory hides Login's own Back link, since there's nowhere
// legitimate to go back to from a forced gate like this one.
// Refund MVP (product rule A5) — "the route must survive app relaunch and
// refresh": this SPA has no URL router at all (every screen is in-memory
// `state.screen`), so a plain reload always restarts at splash/home. Rather
// than build a general router for this one ticket, the two new refund
// screens specifically persist themselves here (openRefundAccounts/
// openMyRefunds) and are restored on the next cold start, same idea as the
// existing `banbe.preferences` localStorage convention.
const RESTORABLE_SCREENS = new Set(['refundAccounts', 'myRefunds']);

function postAuthDestination(prev) {
  let lastScreen = null;
  try { lastScreen = localStorage.getItem('banbe.lastScreen'); } catch { /* private browsing */ }
  const restored = prev.user && lastScreen && RESTORABLE_SCREENS.has(lastScreen) ? lastScreen : null;
  const target = restored || (prev.arrivedFromSharedLink ? 'organizerProfile' : 'home');
  // !prev.sessionChecked means the async getSession()/profile fetch hasn't
  // resolved yet — prev.user being null here doesn't mean signed-out, just
  // "not confirmed yet" (e.g. a fast click through langPick/themePick can
  // race ahead of that network round trip even for an already-authenticated
  // account). Only the blanket guard effect gets to call someone
  // signed-out, and only once sessionChecked is actually true — this just
  // goes to `target` optimistically in the meantime and lets that guard
  // correct course (bounce to Login) the moment it knows for sure.
  if (prev.user || !prev.sessionChecked) return { screen: target };
  return {
    screen: 'login', authMode: 'login', authMandatory: true,
    authReturnScreen: target, authBackScreen: target,
  };
}

// TASK 1 (2026-09-22 nineteenth follow-up) — ONE canonical kind -> required-
// target mapping, consulted by BOTH loadNotifications()'s proactive prune
// AND openNotification()'s reactive tap handling (via targetIsGone() below)
// instead of two independently-drifting ad-hoc checks. Every kind that
// references a single real row it can't function without gets an entry
// here; a kind with NO entry either navigates to a LIST (missing one row
// just means it doesn't show up there, not "tap does nothing" —
// booking_requested/payment_awaiting_verification/payment_verification_nudge),
// targets an EVENT (never hard-deleted anywhere in this schema —
// booking_cancelled/booking_declined/hold_expired), or is purely
// informational with no destination by design (guest_renamed; new_message,
// since no code path anywhere deletes a `threads` row itself). See
// 07-notifications.md for the full kind -> outcome table this mirrors.
// `payment_confirmed`/`payment_document_uploaded`/`_replaced` are
// DELIBERATELY excluded — their own openBookingConfirmed()/
// openDocumentFromNotification() calls already fetch the FULL target row
// (not just its existence) since the destination screen needs that data
// too, so a second, redundant existence-only check here would be N+1.
const NOTIFICATION_TARGET_FIELD = {
  hold_created: { field: 'booking_id', table: 'bookings' },
  dispute_message: { field: 'booking_id', table: 'bookings' },
  receipt_requested: { field: 'booking_id', table: 'bookings' },
  checked_in: { field: 'booking_id', table: 'bookings' },
  checkin_undone: { field: 'booking_id', table: 'bookings' },
  dispute_resolved: { field: 'booking_id', table: 'bookings' },
  payment_disputed: { field: 'booking_id', table: 'bookings' },
  payment_needs_info: { field: 'booking_id', table: 'bookings' },
  payment_document_expiring_1d: { field: 'document_id', table: 'documents' },
  // Flow 2 (host refund -> guest confirmation) — refund_claims is never
  // hard-deleted anywhere in this codebase (ON DELETE CASCADE from
  // bookings only, and no RPC ever deletes a bookings row either — same
  // "no confirmed real trigger" reasoning 07-notifications.md already
  // documents for booking_id-keyed kinds above), so this is defensive
  // coverage rather than a known repro, same as those.
  refund_marked_sent: { field: 'claim_id', table: 'refund_claims' },
  refund_confirmed: { field: 'claim_id', table: 'refund_claims' },
  refund_disputed: { field: 'claim_id', table: 'refund_claims' },
  refund_overdue: { field: 'claim_id', table: 'refund_claims' },
  // Event review queue — the event itself is never hard-deleted by any RPC
  // in this schema, but registered anyway for the same defensive reason
  // the refund_* kinds above are (no known repro, just consistent coverage).
  event_approved: { field: 'event_id', table: 'events' },
  event_rejected: { field: 'event_id', table: 'events' },
};
const NOTIFICATION_TABLE_NAME = { bookings: 'bookings', documents: 'payment_documents', refund_claims: 'refund_claims', events: 'events' };

// RLS safety (both call sites below): `bookings`/`payment_documents` both
// scope their guest-facing SELECT to `auth.uid() = user_id`, and an
// organizer-recipient kind's booking is on their OWN event — the same
// reasoning already established for dispute_message/receipt_requested's
// organizer branches. The notification's recipient is that same owning
// user by construction (the RPC that inserts the notification is the one
// that set ownership on the target row), so RLS can never spuriously deny
// an existing row to its own recipient — an empty result is unambiguous.
async function targetIsGone(n) {
  const spec = NOTIFICATION_TARGET_FIELD[n.kind];
  const targetId = spec && n.data?.[spec.field];
  if (!spec || !targetId) return false;
  const { data } = await supabase.from(NOTIFICATION_TABLE_NAME[spec.table]).select('id').eq('id', targetId).maybeSingle();
  return !data;
}

// TASK 1 (cancel_booking response handling) — the exact five typed
// outcomes cancel_booking() (supabase/migrations/20260924000069_069_refund_lifecycle.sql)
// can return, mapped to a specific, user-visible Vietnamese message each —
// never the one-size-fits-all "Không thể huỷ vé. Vui lòng thử lại." this
// replaces for that RPC's own typed failures.
function cancelBookingErrorMessage(code, T) {
  switch (code) {
    case 'AUTH_REQUIRED':
      return T('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.', 'Your session has expired. Please sign in again.');
    case 'BOOKING_NOT_FOUND':
      return T('Không tìm thấy vé này. Vé có thể đã bị xoá.', 'This booking could not be found. It may have been deleted.');
    case 'NOT_AUTHORIZED':
      return T('Bạn không có quyền huỷ vé này.', "You don't have permission to cancel this booking.");
    case 'BOOKING_CANNOT_BE_CANCELLED':
      return T('Vé này không thể huỷ vì đã bị huỷ, hết hạn hoặc khách đã check-in.', "This booking can't be cancelled: it's already cancelled, expired, or the guest already checked in.");
    default:
      return code
        ? T(`Không thể huỷ vé: ${code}`, `Could not cancel the booking: ${code}`)
        : T('Không thể huỷ vé. Vui lòng thử lại.', 'Could not cancel the booking. Please try again.');
  }
}

export function BanBeProvider({ children }) {
  const [state, setStateRaw] = useState(() => {
    try {
      const raw = localStorage.getItem('banbe.preferences');
      const saved = JSON.parse(raw || '{}');
      return {
        ...initialState,
        lang: saved.lang === 'en' ? 'en' : 'vi',
        theme: saved.theme === 'dark' ? 'dark' : 'light',
        // Remember only the yes/no decision, never the coordinates
        // themselves — matches what the location sheet promises ("not
        // stored"). A fresh position is requested again each session below.
        located: saved.located === true ? true : saved.located === false ? false : null,
        // A saved preferences record means this browser has been through
        // onboarding (language/theme) before — that part is skipped on a
        // revisit, but the splash itself always shows now (Task 2) and
        // `screen` always starts 'splash' regardless (initialState's
        // default) — `hasOnboarded` is just what the splash timer below
        // reads to decide whether to route into 'langPick' or straight to
        // 'home'/'login'.
        hasOnboarded: raw !== null,
        // A shared "?org=" link is an explicit deep link someone tapped to
        // see one specific organizer right away — sitting it through the
        // splash/onboarding sequence first would defeat the point of a
        // fast-opening share preview, so this bypasses both entirely and
        // opens straight on the organizer profile (same as before Task 2's
        // splash change). The organizer id isn't known synchronously — the
        // mount effect below resolves it from the event key. The blanket
        // guard still applies from here if it turns out there's no session
        // once that resolves.
        ...(sharedOrgEventKey ? { eventKey: sharedOrgEventKey, arrivedFromSharedLink: true, screen: 'organizerProfile', organizerProfileLoading: true, organizerProfileBack: 'home' } : {}),
        // Same reasoning, for a shared /u/<handle> profile link — the
        // actual data fetch happens in the mount effect below (needs
        // `supabase.rpc`, not available at this synchronous init point).
        ...(sharedProfileHandle ? { screen: 'publicProfile', publicProfileHandle: sharedProfileHandle, publicProfileLoading: true, publicProfileBack: 'home' } : {}),
        // Same reasoning, for a shared /org/<id> organizer link.
        ...(sharedOrganizerId ? { screen: 'organizerProfile', organizerProfileId: sharedOrganizerId, organizerProfileLoading: true, organizerProfileBack: 'home' } : {}),
        // Same reasoning, for a shared /surveys/<publicId> link.
        ...(sharedSurveyPublicId ? { screen: 'surveyPublic', surveyPublicId: sharedSurveyPublicId, surveyPublicLoading: true, surveyPublicBack: 'home' } : {}),
      };
    } catch {
      return initialState;
    }
  });
  const s = state;
  // TASK D (2026-10-01 UX foundation pass) — fires the real get_public_profile()
  // fetch for a shared /u/<handle> link's already-set initial screen (the
  // synchronous state initializer above can only set the screen/loading
  // flag, not await an RPC). Runs at most once — sharedProfileHandle is a
  // module-level value read once at load, never reassigned afterward.
  useEffect(() => {
    if (!sharedProfileHandle) return;
    let active = true;
    supabase.rpc('get_public_profile', { p_handle: sharedProfileHandle }).then(({ data, error }) => {
      if (!active) return;
      if (error || data?.success === false) {
        setStateRaw(prev => ({ ...prev, publicProfileLoading: false, publicProfileError: T('Không tìm thấy hồ sơ này.', "This profile couldn't be found.") }));
        return;
      }
      setStateRaw(prev => ({ ...prev, publicProfile: data, publicProfileLoading: false }));
    });
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Merged host profile — a shared "?org=<eventKey>" link used to open the
  // retired Organizer screen. It now opens the organizer profile of that
  // event's organizer; the id comes from the `events` row (the same lookup
  // loadOrganizerPhotos used), then the core RPC, same as the effect below.
  useEffect(() => {
    if (!sharedOrgEventKey) return;
    let active = true;
    const fail = () => setStateRaw(prev => ({ ...prev, organizerProfileLoading: false, organizerProfileError: T('Không tìm thấy tổ chức này.', "This organizer couldn't be found.") }));
    (async () => {
      const { data: evRow } = await supabase.from('events').select('organizer_id').eq('id', sharedOrgEventKey).maybeSingle();
      if (!active) return;
      const orgId = evRow?.organizer_id;
      if (!orgId) { fail(); return; }
      setStateRaw(prev => ({ ...prev, organizerProfileId: orgId }));
      const { data, error } = await supabase.rpc('get_organizer_profile', { p_organizer_id: orgId });
      if (!active) return;
      if (error || data?.success === false) { fail(); return; }
      setStateRaw(prev => ({ ...prev, organizerProfile: data, organizerProfileLoading: false }));
    })();
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Same reasoning, for a shared /org/<id> organizer link's already-set
  // initial screen — the OrganizerProfile screen's own mount effect
  // separately fetches the upcoming-events/photos "extras" regardless of
  // entry path (deep link or in-app navigation), so this only needs the
  // core RPC, same as the /u/<handle> effect above only fetches core.
  useEffect(() => {
    if (!sharedOrganizerId) return;
    let active = true;
    supabase.rpc('get_organizer_profile', { p_organizer_id: sharedOrganizerId }).then(({ data, error }) => {
      if (!active) return;
      if (error || data?.success === false) {
        setStateRaw(prev => ({ ...prev, organizerProfileLoading: false, organizerProfileError: T('Không tìm thấy tổ chức này.', "This organizer couldn't be found.") }));
        return;
      }
      setStateRaw(prev => ({ ...prev, organizerProfile: data, organizerProfileLoading: false }));
    });
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Same reasoning, for a shared /surveys/<publicId> link's already-set
  // initial screen — inlined here (rather than calling the loadSurveyPublic
  // action defined later in this same component) since this effect must
  // run on mount regardless of declaration order, and this file's other
  // two shared-link effects above already establish "call supabase.rpc
  // directly in a one-time mount effect" as the pattern for this exact
  // situation.
  useEffect(() => {
    if (!sharedSurveyPublicId) return;
    let active = true;
    supabase.rpc('get_survey_public', { p_public_id: sharedSurveyPublicId }).then(({ data, error }) => {
      if (!active) return;
      if (error || data?.success === false) {
        setStateRaw(prev => ({ ...prev, surveyPublicLoading: false, surveyPublicError: T('Không tìm thấy khảo sát này.', "This survey couldn't be found.") }));
        return;
      }
      setStateRaw(prev => ({ ...prev, surveyPublic: data, surveyPublicLoading: false }));
    });
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const prefsRef = useRef({ lang: state.lang, theme: state.theme });
  // BUG 1 (2026-09-22 fourteenth follow-up) — see markThreadMessagesRead()'s
  // own comment: the timestamp of the most recent successful
  // messages.read_at write, read by loadInboxThreads() and the dock
  // badge's own poll to discard a response whose REQUEST started before
  // this write committed, instead of letting an out-of-order stale
  // response silently revert a just-read thread back to unread.
  const lastReadWriteAtRef = useRef(0);
  // In-flight lazy thread insert (ensureChatThread) — see openChatFor.
  const chatThreadCreateRef = useRef(null);
  // BUG 1 fix (2026-09-22 follow-up) — real bug, confirmed by reading:
  // loadHomeStories() used to list `s.storyViewedIds` as a useCallback
  // dependency (to merge it into the freshly-fetched viewedSet), which
  // means its FUNCTION IDENTITY changed on every single viewStoryTick()
  // call. Home.jsx's `useEffect(() => loadHomeStories(), [s.user?.id,
  // loadHomeStories])` (and Account.jsx's own copy) re-fires on every
  // identity change — so watching a 2nd/3rd story mid-viewer re-triggered
  // a full server refetch WHILE the viewer was still open. Two overlapping
  // refetches can resolve out of order: an OLDER one (closed over an
  // OLDER, smaller storyViewedIds) resolving AFTER a NEWER one silently
  // reverted the just-recorded story back to unviewed — the ring going
  // bright again with no visible cause, worse under real network latency
  // than on a fast local dev server (why this slipped past web Playwright
  // runs but showed up on a real device). Fixed by reading storyViewedIds
  // through a ref instead of a dependency, so loadHomeStories' identity
  // stays stable across ordinary story-viewing and Home/Account's mount
  // effect only actually re-runs for a real user change.
  const storyViewedIdsRef = useRef(state.storyViewedIds);

  // BUG 2 (2026-10-06 fix pass) — same "an async refetch can resolve out of
  // order" family as storyViewedIdsRef just above, applied to organizer
  // mode: `syncUser()` (below) unconditionally overwrote `organizerMode`/
  // `accountType`/`mode` from a fresh `profiles.role` read on EVERY
  // `onAuthStateChange` event with a session — not just sign-in.
  // supabase-js reliably refires that callback for a background token
  // refresh (its own auto-refresh timer, and — far more readily on mobile
  // Safari than desktop, which is why this reproduces on a real iPhone and
  // not in local dev — session recovery on tab/app visibility regain). If
  // one of those refires while `applyOrganizerMode`'s own RPC call is still
  // in flight, its SELECT can read `profiles.role` from BEFORE that RPC's
  // UPDATE has committed, then `syncUser()`'s own `set()` — landing AFTER
  // the toggle's own optimistic update — silently reverts organizerMode/
  // accountType back to the pre-toggle value with no error of its own,
  // exactly matching "switch stays on" (with `applyOrganizerMode`'s own
  // error, if the RPC itself also genuinely failed, showing alongside it).
  // Read via a ref (not `state.organizerModeBusy` directly) for the same
  // reason `storyViewedIdsRef` exists: `syncUser` is defined once inside an
  // effect with `[set]` deps, so a plain closure over state would be stale.
  //
  // BUG (2026-10-08 fix pass) — this ref used to be set ONLY from the
  // `useEffect` below, mirroring `state.organizerModeBusy` a render (and a
  // full effect-flush) AFTER `applyOrganizerMode`'s own `set({
  // organizerModeBusy: true, ... })` call — a real, if narrow, window where
  // `syncUser()` could still read `organizerModeBusyRef.current === false`
  // even though a toggle had already, synchronously, committed to
  // proceeding. `applyOrganizerMode` now also sets this ref DIRECTLY,
  // synchronously, at the instant it accepts a call (see its own comment)
  // — this is the confirmed fix for "toggle off works for an instant, then
  // flips back on": the ref is now authoritative from the very first line
  // of the call, not from whenever React gets around to committing state.
  // The effect stays as a safety net (e.g. if `organizerModeBusy` is ever
  // set from somewhere other than `applyOrganizerMode` in the future).
  const organizerModeBusyRef = useRef(false);
  useEffect(() => {
    organizerModeBusyRef.current = state.organizerModeBusy;
  }, [state.organizerModeBusy]);

  // Stage 1 (retention roadmap P0, real favorites) — which account's
  // favorites are currently loaded/loading, so syncUser's re-fires (token
  // refresh, tab refocus) don't reload/clear on every call, while a real
  // account switch still does. See syncUser's own comment above.
  const favoritesUidRef = useRef(null);
  // Dedupe rapid repeat taps on the same event's save toggle — see
  // toggleFav's own comment.
  const favToggleInFlightRef = useRef(new Set());

  useEffect(() => {
    prefsRef.current = { lang: state.lang, theme: state.theme };
  }, [state.lang, state.theme]);
  useEffect(() => {
    storyViewedIdsRef.current = state.storyViewedIds;
  }, [state.storyViewedIds]);

  const set = useCallback((partial) => {
    setStateRaw(prev => ({ ...prev, ...(typeof partial === 'function' ? partial(prev) : partial) }));
  }, []);

  useEffect(() => {
    localStorage.setItem('banbe.preferences', JSON.stringify({ lang: state.lang, theme: state.theme, located: state.located }));
  }, [state.lang, state.theme, state.located]);

  useEffect(() => {
    const id = setInterval(() => {
      setStateRaw(prev => (
        // Gated on ANY holding booking, not just the single one the
        // currently-open screen happens to be looking at — a hold made on
        // event A must still tick (and get forfeited) while sitting on
        // event B's EventDetail, where prev.booking is B's, not A's.
        (prev.holdDeadline || prev.booking?.payment_state === 'holding'
          || (prev.paymentBookings || []).some(b => b.payment_state === 'holding'))
          ? { ...prev, now: Date.now() } : prev
      ));
    }, 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let active = true;
    const syncUser = async (user) => {
      if (!active) return;
      if (!user) {
        favoritesUidRef.current = null;
        set({ user: null, referralCode: null, sessionChecked: true, favorites: [], authSyncing: false });
        return;
      }
      // Stage 1 (retention roadmap P0) — real `favorites` rows, keyed by
      // (user_id, event_id), not the local-only array this used to be.
      // Guarded by a plain ref (not state, so it's read synchronously
      // before this async function's first await) so: (a) a token-refresh
      // re-firing of onAuthStateChange for the SAME account (see
      // organizerModeBusyRef's own comment on why that happens) doesn't
      // re-clear/reload favorites on every refresh — no flash; (b) a
      // genuine account switch (this uid differs from the last one loaded)
      // DOES clear the previous account's rows before the new account's
      // own load resolves, so they never leak across accounts.
      if (favoritesUidRef.current !== user.id) {
        favoritesUidRef.current = user.id;
        set({ favorites: [] });
        const { data: favRows, error: favError } = await supabase
          .from('favorites').select('event_id').eq('user_id', user.id);
        if (favError) console.warn('Failed to load favorites:', favError);
        // Only apply if no later account switch has already moved the ref
        // on — a stale response from a login this account has since left
        // must not resurrect its favorites.
        if (favoritesUidRef.current === user.id) set({ favorites: (favRows || []).map(r => r.event_id) });
      }
      const { data: profile } = await supabase
        .from('profiles')
        .select('role, locale, theme, prefs_saved, display_name, referral_code, policy_accepted_at, policy_version, auto_email_documents, muted_notification_kinds, handle, avatar_url, bio, city, interests, profile_theme, intro_long, social_links, organizer_mode_enabled, can_manage_admins')
        .eq('id', user.id)
        .maybeSingle();
      const role =
        profile?.role ||
        user.user_metadata?.account_type ||
        user.raw_user_meta_data?.account_type ||
        'participant';
      // Account regression fix pass (2026-09-27), Item 3 — the actual bug:
      // this used to be `role === 'organizer' || role === 'admin'`, which
      // forced an admin's organizerMode to `true` on EVERY sync
      // regardless of their own toggle — the real reason the switch
      // looked permanently stuck on. `role === 'admin'` alone is
      // eligibility (canHost, computed separately below from this same
      // field), never the CURRENT preference; for an admin specifically,
      // that preference now lives in its own column
      // (organizer_mode_enabled, migration 103), defaulting to true so an
      // admin who has never touched the toggle keeps seeing the host UI
      // exactly as before this fix.
      const canHostNow = role === 'organizer' || (role === 'admin' && profile?.organizer_mode_enabled !== false);
      const displayName = (profile?.display_name || '').trim() || user.user_metadata?.display_name || '';
      // BUG 2 (2026-10-06 fix pass) — see organizerModeBusyRef's own
      // comment above: skip the role-derived fields entirely while a
      // toggle is in flight, so this refetch (which can legitimately read
      // profiles.role from BEFORE that toggle's own UPDATE has committed)
      // never overwrites the toggle's own more-recent optimistic/confirmed
      // state. Every OTHER field this query fetched (display name,
      // avatar, referral code, …) still applies normally — only the three
      // organizer-mode fields are held back.
      const roleFields = organizerModeBusyRef.current
        ? {}
        : { accountType: role, organizerMode: canHostNow, mode: canHostNow ? 'host' : 'goer' };
      if (organizerModeBusyRef.current) {
        console.warn('[organizerMode] syncUser() skipped role fields — a toggle is in flight', { roleOnServer: role });
      } else {
        console.info('[organizerMode] WRITE source=syncUser', { new: canHostNow, role });
      }
      set({
        // TASK D (2026-10-01 UX foundation pass) — the shareable-profile
        // fields, loaded alongside everything else this same query already
        // fetched rather than a second round trip.
        user: {
          ...user, name: displayName,
          handle: profile?.handle || null, avatarUrl: profile?.avatar_url || null,
          bio: profile?.bio || '', city: profile?.city || '',
          interests: profile?.interests || [], profileTheme: profile?.profile_theme || 'default',
          introLong: profile?.intro_long || '', socialLinks: profile?.social_links || [],
        },
        ...roleFields,
        canManageAdmins: profile?.can_manage_admins === true,
        referralCode: profile?.referral_code || null, sessionChecked: true,
        autoEmailDocuments: profile?.auto_email_documents === true,
        mutedNotificationKinds: profile?.muted_notification_kinds || [],
        authSyncing: false,
      });

      // Proof-of-consent bookkeeping (Task 1, migration 055,
      // banbe_User_Policy.md B1/B3). For an 'email'-provider session
      // (password/emailed-code, or a legacy row predating this column
      // entirely), the ONLY way to ever reach one at all is through
      // Login.jsx's mandatory, unticked-by-default consent checkbox
      // (submitCurrentForm is disabled until it's checked) — so any such
      // profile with no recorded consent yet just passed through that
      // gate, and can be stamped unconditionally.
      //
      // An OAuth session (note 10 — Google/Facebook) is different: nothing
      // client-side ran a submit function first, so a brand-new profile
      // here genuinely has never seen the policy. This used to try to gate
      // the OAuth *button* itself on a localStorage-stashed "was it ticked
      // before the redirect" flag — that was fragile (storage partitioning,
      // a cleared/blocked store, or simply losing the value across the
      // full-page round trip could all silently sign a real user back out
      // for no reason they could see) and, worse, required showing the
      // checkbox on the Login tab too just so it had somewhere to render,
      // regressing note 09's Signup-only fix. Fixed: consent for a new
      // OAuth profile is handled entirely AFTER the redirect, right here —
      // route to a mandatory one-time Policy screen (acceptPolicyGate()
      // stamps consent and continues) instead of trying to verify intent
      // before the fact. A *returning* OAuth sign-in never reaches this
      // block at all (its profile already has policy_accepted_at), so it's
      // exactly as frictionless as password login.
      if (profile && !profile.policy_accepted_at) {
        const provider = user.app_metadata?.provider;
        if (!provider || provider === 'email') {
          const { error } = await supabase
            .from('profiles')
            .update({ policy_accepted_at: new Date().toISOString(), policy_version: POLICY_VERSION })
            .eq('id', user.id);
          if (error) console.warn('Failed to record policy consent:', error);
        } else {
          set({ policyGateActive: true, screen: 'policy' });
          return;
        }
      }

      // The account's actual host page name — Account's "Hosting" card used
      // to always fall back to the generic "Bếp Nhỏ" placeholder here,
      // because orgRegName is otherwise only ever filled in locally while
      // filling out the create-event form, never restored for an organizer
      // returning on a new session.
      // Part B audit (2026-09-28) — real bug found while investigating the
      // "Jazz Ở Gác"/"Vườn Sau" organizer-identity report: an owner who
      // genuinely owns MORE THAN ONE organizers row (only ever produced by
      // migration 020's seed, which assigns each of its ~20 demo events'
      // organizer uniformly at random among just 3 test accounts — a real
      // production user's own create-event flow always reuses their one
      // existing organizer row, never inserts a second) used to hit this
      // query with no ORDER BY at all. `.limit(1).maybeSingle()` on an
      // unordered result is whichever row Postgres feels like returning —
      // it can differ between page loads, and independently of
      // `loadMyEvents`' OWN unordered `.in('organizer_id', organizerIds)`
      // events query (below) picking `myOrgEventKeys[0]` for header
      // branding — so the two could each resolve to a DIFFERENT one of the
      // owner's organizer rows, showing one org's name next to another
      // org's event photo. Not a database FK error (every event's own
      // organizer_id is correct — see .claude/notes for the full audit);
      // ordering deterministically here (earliest-created = the owner's
      // "primary" organizer) makes this identity stable and self-consistent
      // across reloads instead of silently random.
      // Hardening (2026-09-28) — migration 020's whole seed batch shares one
      // literal `created_at` (all rows from the same statement), so
      // `.order('created_at')` alone doesn't actually break ties by SQL
      // semantics — it happened to come back stable in manual testing, but
      // that's physical row order, an implementation detail Postgres never
      // promises to preserve (a VACUUM FULL/rewrite could reshuffle it).
      // `.order('id')` as an explicit secondary key makes the "primary
      // organizer" pick genuinely deterministic, not just observed-stable.
      const { data: org } = await withR2Columns(withR2 => supabase
        .from('organizers')
        .select(withR2 ? 'id, name, about, avatar_path, avatar_r2_ref, intro_long, social_links' : 'id, name, about, avatar_path, intro_long, social_links')
        .or(`owner_id.eq.${user.id},user_id.eq.${user.id}`)
        .order('created_at', { ascending: true })
        .order('id', { ascending: true })
        .limit(1)
        .maybeSingle());
      if (org?.name) {
        set({
          orgRegName: org.name, orgRegDesc: org.about || '', hasHosted: true,
          orgRegIntroLong: org.intro_long || '', orgRegLinks: org.social_links || [],
          myOrganizerId: org.id, myOrganizerAvatarPath: org.avatar_path || '', myOrganizerAvatarR2Ref: org.avatar_r2_ref || '',
        });
      }

      // Language & theme follow the account once it has a saved preference,
      // so signing in on any device restores them instead of falling back to
      // this browser's own (possibly never-set) local copy.
      if (profile?.prefs_saved) {
        set(prev => ({
          lang: profile.locale === 'en' ? 'en' : 'vi',
          theme: profile.theme === 'dark' ? 'dark' : 'light',
          screen: ['splash', 'langPick', 'themePick'].includes(prev.screen) ? 'home' : prev.screen,
        }));
      } else if (profile) {
        // First time this account is seen with no saved preference yet:
        // capture whatever this browser currently has (e.g. picked just now
        // during onboarding, or as a signed-out guest) as the account's
        // preference going forward, instead of silently leaving it unset.
        const { lang, theme } = prefsRef.current;
        const { error } = await supabase
          .from('profiles')
          .update({ locale: lang, theme, prefs_saved: true })
          .eq('id', user.id);
        if (error) console.warn('Failed to save initial preferences to account:', error);
      }
    };
    supabase.auth.getSession().then(({ data }) => syncUser(data.session?.user));
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active && session?.user) {
        // A password-reset link lands here as a real session too — but it
        // must go to the "choose a new password" screen, never straight
        // into whatever authReturnScreen was pending.
        set(prev => ({
          screen: _event === 'PASSWORD_RECOVERY' ? 'resetPassword' : (prev.screen === 'login' ? prev.authReturnScreen : prev.screen),
          loginSent: false,
          loginSentVia: null,
          authSyncing: true,
        }));
        syncUser(session.user);
      }
      if (active && !session) set({ user: null, sessionChecked: true });
    });
    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, [set]);

  // Task 1 — no guest browsing of any screen: the single, centralized
  // enforcement point, rather than auditing every one of this file's many
  // `set({ screen: ... })` call sites individually. Catches cases the
  // targeted fixes (finishOnboarding, the splash timer, logout) don't —
  // e.g. goHome()'s plain `set({ screen: 'home' })`, callable from
  // anywhere, previously had no auth check at all. Waits for
  // `sessionChecked` so a slow-resolving session restore can't get
  // misread as "signed out" and bounce a returning user before their
  // session even arrives — the splash screen's own ~2.6s already covers
  // this in the common case, but this effect can fire independently of
  // splash (e.g. a stray screen change right as sessionChecked settles).
  useEffect(() => {
    if (s.sessionChecked && !s.user && !s.authSyncing && !GUEST_ALLOWED_SCREENS.has(s.screen)) {
      set({
        screen: 'login', authMode: 'login', authMandatory: true,
        authReturnScreen: s.screen, authBackScreen: s.screen,
      });
    }
  }, [s.sessionChecked, s.user, s.authSyncing, s.screen, set]);

  useEffect(() => {
    if (!s.user?.id) return;
    let active = true;
    (async () => {
      const { data: event } = await supabase.from('events').select('id').eq('slug', s.eventKey).maybeSingle();
      if (!event) { if (active) set({ booking: null, holdDeadline: null }); return; }
      const { data: booking } = await supabase.from('bookings').select('*').eq('event_id', event.id).eq('user_id', s.user.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
      // Always set (even to null) — this used to only update on a hit, so
      // navigating from a booked event to one you have no booking for kept
      // showing the previous event's stale booking/countdown.
      if (active) set({ booking: booking || null, holdDeadline: booking?.expires_at ? new Date(booking.expires_at).getTime() : null });
    })();
    return () => { active = false; };
  }, [set, s.user?.id, s.eventKey]);

  // The real events row's own status/starts_at for whichever event is
  // currently open — unlike the booking fetch above, this runs for every
  // visitor (signed in or not), since "has this event ended/been cancelled"
  // is public information, not something tied to an account. Every one of
  // the 20 demo events also has a real row (seeded to match the frontend's
  // static STATUS overrides), so this resolves for those too — it's only a
  // pure client-side preview (e.g. the create-event flow) that has no row
  // and falls back to the static catalogue untouched.
  useEffect(() => {
    let active = true;
    (async () => {
      const { data } = await supabase.from('events')
        .select('status, starts_at, cancelled_at, cancel_reason')
        .eq('slug', s.eventKey).maybeSingle();
      if (active) set({ liveEvent: data || null });
    })();
    return () => { active = false; };
  }, [set, s.eventKey]);

  // 2026-09-21 follow-up — the batched counterpart of the single-event
  // fetch just above, for Home's "Sự kiện của bạn" strip (real 48h-after-
  // ended expiry, see `homeLiveEvents`'s own doc comment) and its new
  // "Sắp diễn ra"/"Đã kết thúc" filter chips. Public information, same as
  // the single-event fetch — runs for every visitor, no `s.user?.id` gate.
  const loadHomeLiveEvents = useCallback(async () => {
    const { data } = await supabase.from('events')
      .select('slug, status, starts_at, cancelled_at, cancel_reason')
      .in('slug', EVENTS.map(e => e.key));
    const map = {};
    for (const row of data || []) map[row.slug] = row;
    set({ homeLiveEvents: map });
  }, [set]);

  // Notification banner fix pass (2026-09-30 third) — named constant, per
  // this ticket's own instruction (was a bare 2200ms magic number). The
  // clock now starts when the banner ACTUALLY becomes visible
  // (`markToastVisible`, called by ToastStack.jsx's own per-toast mount
  // effect), not at enqueue time — a toast pushed while >VISIBLE_COUNT are
  // already shown and sitting behind "Xem thêm" doesn't silently burn its
  // reading window before anyone's even seen it.
  const TOAST_DURATION_MS = 8000;
  // Real per-id timer bookkeeping — deliberately NOT React state (a timer
  // handle isn't serializable/renderable data): id -> { timeoutId,
  // remainingMs, startedAt, paused, started }. `started` guards
  // markToastVisible from re-arming an already-running timer on a re-render
  // (e.g. "Xem thêm" expanding the visible set doesn't touch already-shown
  // toasts).
  const toastTimersRef = useRef({});

  const clearToastTimer = useCallback((id) => {
    const timer = toastTimersRef.current[id];
    if (timer?.timeoutId) clearTimeout(timer.timeoutId);
    delete toastTimersRef.current[id];
  }, []);

  // A toast auto-dismisses in two steps: `leaving: true` swaps it to the
  // exit animation (banbeToastOut, index.css), then a second timeout actually
  // drops it from the array once that animation has had time to finish.
  const finishToastDismiss = useCallback((id) => {
    delete toastTimersRef.current[id];
    set(prev => ({ toasts: prev.toasts.map(t => (t.id === id ? { ...t, leaving: true } : t)) }));
    setTimeout(() => {
      set(prev => ({ toasts: prev.toasts.filter(t => t.id !== id) }));
    }, 280);
  }, [set]);

  // Pause on interaction (pointerenter/touchstart on the toast element,
  // ToastStack.jsx) — a real timer pause, not just visual: the pending
  // setTimeout is cancelled and its remaining budget recorded, not merely
  // hidden behind a CSS state.
  const pauseToastTimer = useCallback((id) => {
    const timer = toastTimersRef.current[id];
    if (!timer || timer.paused) return;
    clearTimeout(timer.timeoutId);
    timer.timeoutId = null;
    timer.remainingMs = Math.max(0, timer.remainingMs - (Date.now() - timer.startedAt));
    timer.paused = true;
  }, []);

  // Resume once interaction ends — reset convention (a fresh full window is
  // NOT given; the remaining budget from when the pointer entered resumes
  // counting down), documented here since the ticket left the choice open.
  const resumeToastTimer = useCallback((id) => {
    const timer = toastTimersRef.current[id];
    if (!timer || !timer.paused) return;
    timer.paused = false;
    timer.startedAt = Date.now();
    timer.timeoutId = setTimeout(() => finishToastDismiss(id), timer.remainingMs);
  }, [finishToastDismiss]);

  // Called by ToastStack.jsx's own per-toast mount effect — the moment a
  // toast is actually painted on screen (not merely appended to the queue).
  // Idempotent: a toast already ticking (e.g. re-rendered by an unrelated
  // state change) is left alone, never restarted from a fresh 8s.
  const markToastVisible = useCallback((id) => {
    if (toastTimersRef.current[id]) return;
    toastTimersRef.current[id] = {
      timeoutId: setTimeout(() => finishToastDismiss(id), TOAST_DURATION_MS),
      remainingMs: TOAST_DURATION_MS,
      startedAt: Date.now(),
      paused: false,
    };
  }, [finishToastDismiss]);

  // Carries the source `notification` row (not just its title/body) so
  // ToastStack.jsx can tap it open — see openNotification/dismissToast.
  // Queue/dedup by stable id (notification.id) — a new arrival for the SAME
  // notification currently visible (and not already leaving) is dropped
  // rather than replacing/resetting the visible banner mid-read; a
  // genuinely different notification queues normally, unbounded (ToastStack
  // caps what's ever VISIBLE at once via VISIBLE_COUNT/"Xem thêm", this
  // queue itself is not artificially capped).
  const pushToast = useCallback((notification) => {
    const notifId = notification?.id;
    set(prev => {
      if (notifId != null && prev.toasts.some(t => t.notification?.id === notifId && !t.leaving)) {
        return {}; // already shown/queued for this exact notification — no-op, don't touch it
      }
      const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      return { toasts: [...prev.toasts, { id, notification, leaving: false }] };
    });
  }, [set]);

  // Tapping a toast shouldn't sit around for its own auto-dismiss timer —
  // it's already been acted on. Fires the same 'leaving' exit animation
  // immediately rather than yanking it out with no transition at all.
  // Cancels the pending auto-dismiss timer FIRST (synchronously) so a race
  // with openNotification's own async work can never let the banner vanish
  // out from under an in-flight tap before it resolves.
  const dismissToast = useCallback((id) => {
    clearToastTimer(id);
    set(prev => ({ toasts: prev.toasts.map(t => (t.id === id ? { ...t, leaving: true } : t)) }));
    setTimeout(() => {
      set(prev => ({ toasts: prev.toasts.filter(t => t.id !== id) }));
    }, 280);
  }, [set, clearToastTimer]);

  // "Tắt tất cả" (ToastStack.jsx) — clears the whole local toast queue at
  // once. Same local-only contract as dismissToast: this NEVER touches
  // `notifications`/`read_at` — the bell inbox's unread state (and its
  // badge count) is a completely separate, server-backed concept that a
  // toast is only ever an ephemeral, client-side echo of.
  const dismissAllToasts = useCallback(() => {
    set(prev => {
      prev.toasts.forEach(t => clearToastTimer(t.id));
      return { toasts: prev.toasts.map(t => ({ ...t, leaving: true })) };
    });
    setTimeout(() => {
      set(prev => ({ toasts: prev.toasts.filter(t => !t.leaving) }));
    }, 280);
  }, [set, clearToastTimer]);

  // Real event assignment for the signed-in account: which of the catalogue
  // events they're attending (from actual bookings) and which they organize
  // (from owning the organizer row events.organizer_id points at). The
  // frontend catalogue (src/data/events.js) still supplies all the cosmetic
  // detail — photos, galleries, descriptions — that the database rows don't
  // duplicate; this only resolves *which* catalogue keys are genuinely
  // "mine", by real id, instead of from placeholder demo state.
  //
  // `attending`/`tickets` REPLACE on every call, they do not merge with
  // whatever was there before — mirrors AppState+Data.swift's loadMyEvents()
  // (`attending = going`, a plain assignment). This used to union new
  // results into the previous array instead, which meant a booking that
  // stopped qualifying (e.g. an admin resolving a dispute as "Mở lại chỗ" /
  // "return to pool", `resolve_dispute()` setting `status='expired'` —
  // outside this filter, supabase/migrations/20260914000047_...sql:80-83)
  // could never leave `attending` for the rest of that session: the guest
  // kept seeing the event under "Going" even after losing the ticket, no
  // matter how many times this ran, because every re-run only ever added to
  // the set, never removed a stale key the fresh query no longer returned.
  //
  // Defined here (above the toast poll below, which now also calls it on a
  // fresh 'booking_declined' notification) rather than further down where
  // it originally sat — a const referenced inside an effect defined above
  // its own declaration is a temporal-dead-zone ReferenceError in JS, not
  // just a lint nit, since the effect's dependency array evaluates
  // `loadMyEvents` on every render, not only when the effect itself runs.
  const loadMyEvents = useCallback(async (uid) => {
    if (!uid) return;
    set({ myOrganizerIdsStatus: 'loading' });
    const [{ data: bookings }, { data: organizers, error: organizersError }] = await Promise.all([
      supabase
        .from('bookings')
        .select('event_id, qty, status')
        .eq('user_id', uid)
        .in('status', ['pending', 'confirmed', 'attended']),
      supabase
        .from('organizers')
        .select('id')
        .or(`owner_id.eq.${uid},user_id.eq.${uid}`),
    ]);

    const attending = [...new Set((bookings || []).map(b => b.event_id))];
    const tickets = Object.fromEntries((bookings || []).map(b => [b.event_id, b.qty]));
    set({ attending, tickets });

    // Real bug, confirmed by reading: this used to write `myOrganizerIds:
    // []` unconditionally, with no `error` check at all — a genuinely
    // FAILED query (RLS hiccup, network blip, transient 5xx) collapsed to
    // the exact same `[]` as "really owns zero organizers," and every
    // downstream reader (loadRefundQueue's own gate, foremost) had no way
    // to tell the two apart. A failed lookup must never be reported as a
    // confirmed empty result.
    if (organizersError) {
      if (import.meta.env?.DEV) {
        console.warn('loadMyEvents: organizers lookup failed, myOrganizerIds NOT overwritten:', { code: organizersError.code, message: organizersError.message, userId: uid });
      }
      set({ myOrganizerIdsStatus: 'error' });
      return;
    }

    const organizerIds = (organizers || []).map(o => o.id);
    set({ myOrganizerIds: organizerIds, myOrganizerIdsStatus: 'loaded' });
    if (organizerIds.length) {
      const { data: events } = await supabase.from('events').select('id, organizer_id').in('organizer_id', organizerIds);
      set({
        myOrgEventKeys: (events || []).map(e => e.id),
        // See myOrgEventOrganizerId's own doc comment (initialState) —
        // Dashboard.jsx's branded shelf filters on this; the ownership
        // gate above (myOrgEventKeys) stays the full union on purpose.
        myOrgEventOrganizerId: Object.fromEntries((events || []).map(e => [e.id, e.organizer_id])),
      });
    } else {
      set({ myOrgEventKeys: [], myOrgEventOrganizerId: {} });
    }
  }, [set]);

  /** STAGE D (2026-09-25) — EventDetail's own real photo gallery, one
   * event's `event_photos` rows (not the whole organizer's — that's
   * `loadOrganizerPhotos` below). Replaces the static demo `ev.gallery`
   * render. `event_photos` itself is openly readable (migration 001), so
   * this needs no extra scoping beyond the event id itself — a viewer who
   * can already reach this event's page (real `events` RLS already
   * gated that) can see its real photos too. */
  /** Photo identity/engagement fix — real per-photo like/share counts +
   * this user's own liked state for ANY set of real event_photos ids
   * (migration 086's get_photo_engagement, a general-purpose read path
   * Pulse's own top-20-only ranking RPC can't serve). Merges into the
   * canonical `photoEngagement` map rather than replacing it, so loading
   * one screen's photos never drops another screen's already-loaded rows.
   * Fire-and-forget from the gallery loaders below — the photo grid itself
   * renders from `eventPhotos`/`organizerPhotos` immediately; engagement
   * (like counts, liked-heart badges) fills in a moment later. */
  const loadPhotoEngagement = useCallback(async (photoIds) => {
    const ids = [...new Set((photoIds || []).filter(Boolean))];
    if (!ids.length) return;
    const { data, error } = await supabase.rpc('get_photo_engagement', { p_photo_ids: ids });
    if (error || data?.success === false) {
      if (import.meta.env?.DEV) console.warn('loadPhotoEngagement failed:', error, data);
      return;
    }
    set(prev => ({ photoEngagement: mergePhotoEngagement(prev.photoEngagement, data.items || []) }));
  }, [set]);

  const loadEventPhotos = useCallback(async (eventId) => {
    set({ eventPhotosLoading: true });
    const { data, error } = await withR2Columns(withR2 => supabase
      .from('event_photos').select(withR2 ? 'id, storage_path, r2_ref, sort_order' : 'id, storage_path, sort_order')
      .eq('event_id', eventId).order('sort_order', { ascending: true }));
    if (error) { if (import.meta.env?.DEV) console.warn('loadEventPhotos failed:', error); }
    // Strict invite-only events (migration 113) — resolve each row's
    // display URL HERE (already async) rather than at every render-time
    // consumer (EventDetail.jsx, CreateEvent.jsx's edit-seed effect),
    // which is what lets an invite-only event's private-bucket photos
    // resolve via a real signed URL instead of a broken/blocked public one.
    const rows = data || [];
    const withUrls = await Promise.all(rows.map(async p => ({ ...p, url: await resolveEventPhotoUrlAsync(p.storage_path, p.r2_ref, 'full') })));
    set({ eventPhotos: withUrls, eventPhotosLoading: false });
    loadPhotoEngagement(rows.map(p => p.id));
  }, [set, loadPhotoEngagement]);

  /** STAGE B (2026-09-25) — the organizer's real photo library (now shown
   * on OrganizerProfile.jsx — the old Organizer.jsx screen was merged into
   * it, and this takes an organizer id instead of an event key), replacing
   * the static demo `orgGallery` render. Two-step, both steps riding
   * EXISTING RLS rather than a new RPC: `events` itself already lets the
   * owner see every one of their own rows regardless of status (draft
   * included — Task 1's own "ended must stay in the owner's library"
   * rule, and then some) while a non-owner only ever sees
   * live/ended/cancelled (084's fix) — so restricting to `status='live'
   * AND visibility='public'` for a NON-owner here is what keeps the
   * PUBLIC grid to live+public only, per this ticket's own rule 3;
   * `event_photos` itself has always been openly readable
   * (`event_photos_select_public: USING (true)`, migration 001) — nothing
   * there was ever scoped by event status, so this function is the actual
   * enforcement point for "which events' photos," not a new RLS grant. */
  const loadOrganizerPhotos = useCallback(async (organizerId) => {
    set({ organizerPhotosLoading: true });
    if (!organizerId) { set({ organizerPhotos: [], organizerPhotosLoading: false }); return; }
    const isOwner = s.myOrganizerIds.includes(organizerId);
    let eventsQuery = supabase.from('events').select('id').eq('organizer_id', organizerId);
    if (!isOwner) eventsQuery = eventsQuery.eq('status', 'live').eq('visibility', 'public');
    const { data: orgEvents } = await eventsQuery;
    const eventIds = (orgEvents || []).map(e => e.id);
    if (!eventIds.length) { set({ organizerPhotos: [], organizerPhotosLoading: false }); return; }
    const { data: photos, error } = await withR2Columns(withR2 => supabase
      .from('event_photos').select(withR2 ? 'id, event_id, storage_path, r2_ref, sort_order' : 'id, event_id, storage_path, sort_order')
      .in('event_id', eventIds).order('sort_order', { ascending: true }));
    if (error) { if (import.meta.env?.DEV) console.warn('loadOrganizerPhotos failed:', error); }
    set({ organizerPhotos: photos || [], organizerPhotosLoading: false });
    loadPhotoEngagement((photos || []).map(p => p.id));
  }, [set, s.myOrganizerIds, loadPhotoEngagement]);

  /**
   * Retention roadmap P1 ("Cuối tuần này") — a compact Home section built
   * entirely from real `events` rows for the applicable Sat/Sun window
   * (thisWeekendWindow, Asia/Ho_Chi_Minh — see countdown.js), never the
   * static demo catalogue. `status='live' AND visibility='public'` is the
   * same public-eligibility rule loadOrganizerPhotos' own non-owner branch
   * and MapExplore's fetchLiveEvents already use — drafts, invite-only and
   * cancelled/ended rows are excluded by construction, not filtered after
   * the fact. A sold-out event still appears (excluded from BOOKING, not
   * from DISCOVERY — the caller renders it non-bookable via seats_remaining)
   * per the roadmap's own instruction not to hide it outright.
   *
   * Sort: followed organizers' events first (real `follows` rows, not the
   * local-only per-event-key `following` array Organizer.jsx's UI toggle
   * uses), then chronological by starts_at — nothing else. Explicitly not
   * an engagement/popularity ranking: no photo-like count, no paid/sponsored
   * flag (none exists yet), no goc_pulse_ranked() score feeds into this at
   * all, so a host can't buy or like their way up this particular list.
   */
  const loadWeekendEvents = useCallback(async () => {
    set({ weekendEventsLoading: true });
    const { start, end } = thisWeekendWindow();
    const { data: rows, error } = await withR2Columns(withR2 => supabase
      .from('events')
      .select(realEventColumns(withR2))
      .eq('status', 'live')
      .eq('visibility', 'public')
      .gte('starts_at', start)
      .lte('starts_at', end)
      .order('starts_at', { ascending: true }));
    if (error) {
      console.warn('Failed to load weekend events:', error);
      set({ weekendEvents: [], weekendEventsLoading: false });
      return;
    }
    const events = rows || [];
    const eventIds = events.map(e => e.id);
    const organizerIds = [...new Set(events.map(e => e.organizer_id).filter(Boolean))];

    const [photoUrlByEvent, orgsRes, followsRes] = await Promise.all([
      firstPhotoUrlByEvent(eventIds),
      organizerIds.length
        ? supabase.from('organizers').select('id, name').in('id', organizerIds)
        : Promise.resolve({ data: [] }),
      // Anonymous/signed-out visitors have no followed hosts — an empty
      // Set falls every event through to the chronological tiebreak below.
      s.user
        ? supabase.from('follows').select('organizer_id').eq('user_id', s.user.id)
        : Promise.resolve({ data: [] }),
    ]);

    const orgNameById = Object.fromEntries((orgsRes.data || []).map(o => [o.id, o.name]));
    const followedOrgIds = new Set((followsRes.data || []).map(f => f.organizer_id));

    const shaped = events.map(e => {
      const real = shapeRealEvent(e, {
        photoUrl: photoUrlByEvent[e.id],
        organizerName: orgNameById[e.organizer_id],
        followedHost: followedOrgIds.has(e.organizer_id),
      });
      const startsAt = real.startsAt ? new Date(real.startsAt) : null;
      const { weekdayShort, dayMonth, time } = startsAt ? formatVnEventDate(startsAt) : {};
      return {
        ...real,
        when: startsAt ? `${weekdayShort}, ${dayMonth} ▪︎ ${time}` : '',
        priceLabel: real.priceVnd ? formatVnd(real.priceVnd) : null, // null -> caller shows "Miễn phí"/"Free"
      };
    }).sort((a, b) => {
      if (a.followedHost !== b.followedHost) return a.followedHost ? -1 : 1;
      return 0; // stable: both already starts_at-ascending from the query above
    });

    // Same canonical rows just fetched — feeds the shared realEventsById
    // cache too so a card that's ALSO saved/attending doesn't trigger a
    // second, redundant loadRealEventsById() fetch for the same id.
    set(prev => ({
      weekendEvents: shaped, weekendEventsLoading: false,
      realEventsById: { ...prev.realEventsById, ...Object.fromEntries(shaped.map(e => [e.key, e])) },
    }));
  }, [set, s.user]);

  /**
   * Discovery-bug fix — the general-purpose counterpart to
   * loadWeekendEvents above: EVERY real live/public (or publicly-visible
   * cancelled/ended, per 084) event, not scoped to any date window. This
   * is what makes an admin-approved real event actually show up in Home's
   * main "Tất cả"/category feed regardless of whether it also happens to
   * fall in this weekend's window or exists in the static demo catalogue.
   * `status IN ('live','cancelled','ended')` (not just 'live') — Home's
   * own filter chips (Upcoming/Ended) and cancelled-dimming already expect
   * to see those too, same as the static catalogue does; 'draft'/'review'
   * stay excluded (owner-only, same as ever). Capped at 300, soonest
   * first — a discovery feed, not an unbounded export; revisit with real
   * pagination if this app's event volume ever makes that cap bite.
   */
  const loadDiscoveryEvents = useCallback(async () => {
    set({ discoveryEventsLoading: true });
    const { data: rows, error } = await withR2Columns(withR2 => supabase
      .from('events')
      .select(realEventColumns(withR2))
      .eq('visibility', 'public')
      .in('status', ['live', 'cancelled', 'ended'])
      .order('starts_at', { ascending: true })
      .limit(300));
    if (error) {
      console.warn('Failed to load discovery events:', error);
      set({ discoveryEvents: [], discoveryEventsLoading: false });
      return;
    }
    const events = rows || [];
    const eventIds = events.map(e => e.id);
    const organizerIds = [...new Set(events.map(e => e.organizer_id).filter(Boolean))];
    const [photoUrlByEvent, orgsRes] = await Promise.all([
      firstPhotoUrlByEvent(eventIds),
      organizerIds.length
        ? supabase.from('organizers').select('id, name').in('id', organizerIds)
        : Promise.resolve({ data: [] }),
    ]);
    const orgNameById = Object.fromEntries((orgsRes.data || []).map(o => [o.id, o.name]));
    const shaped = events.map(e => shapeRealEvent(e, {
      photoUrl: photoUrlByEvent[e.id],
      organizerName: orgNameById[e.organizer_id],
    }));
    set(prev => ({
      discoveryEvents: shaped, discoveryEventsLoading: false,
      realEventsById: { ...prev.realEventsById, ...Object.fromEntries(shaped.map(e => [e.key, e])) },
    }));
  }, [set]);

  // Dedupe concurrent loadRealEventsById() calls for the same id (e.g. Home
  // and EventList both mounting) — see toggleFav's own in-flight-dedupe
  // reasoning for why a ref, not state.
  const realEventsInFlightRef = useRef(new Set());

  // createSubmit's own synchronous submit-in-flight guard (task 1) — a ref,
  // not state, for the same reason: a repeated tap fires its second click
  // handler before React has re-rendered the button with a "busy" state,
  // so only a synchronously-readable value stops it.
  const createSubmitInFlightRef = useRef(false);

  /**
   * The canonical real-event lookup by id, shared by Home's "Sự kiện của
   * bạn" strip and EventList's Saved/Going/Completed lists for any saved/
   * attending/invited event that isn't in the static demo catalogue (a
   * real, host-created event) — see shapeRealEvent's own comment. Never
   * invents a fallback: an id that isn't returned (deleted, or RLS denies
   * it — e.g. a draft/invite-only event this account no longer has
   * standing to see) is cached as `null`, an explicit "unavailable", so
   * the caller can render that honestly instead of the row just vanishing.
   */
  const loadRealEventsById = useCallback(async (ids) => {
    const wanted = [...new Set(ids)].filter(id => !(id in s.realEventsById) && !realEventsInFlightRef.current.has(id));
    if (!wanted.length) return;
    wanted.forEach(id => realEventsInFlightRef.current.add(id));
    const { data: rows, error } = await withR2Columns(withR2 => supabase.from('events').select(realEventColumns(withR2)).in('id', wanted));
    if (error) {
      console.warn('Failed to load real events by id:', error);
      wanted.forEach(id => realEventsInFlightRef.current.delete(id));
      return;
    }
    const found = rows || [];
    const foundIds = new Set(found.map(r => r.id));
    const organizerIds = [...new Set(found.map(r => r.organizer_id).filter(Boolean))];
    const [photoUrlByEvent, orgsRes] = await Promise.all([
      firstPhotoUrlByEvent(found.map(r => r.id)),
      organizerIds.length ? supabase.from('organizers').select('id, name').in('id', organizerIds) : Promise.resolve({ data: [] }),
    ]);
    const orgNameById = Object.fromEntries((orgsRes.data || []).map(o => [o.id, o.name]));
    const shapedById = {};
    for (const row of found) {
      shapedById[row.id] = shapeRealEvent(row, { photoUrl: photoUrlByEvent[row.id], organizerName: orgNameById[row.organizer_id] });
    }
    for (const id of wanted) if (!foundIds.has(id)) shapedById[id] = null;
    set(prev => ({ realEventsById: { ...prev.realEventsById, ...shapedById } }));
    wanted.forEach(id => realEventsInFlightRef.current.delete(id));
  }, [set, s.realEventsById]);

  // Unread count for the notification bell, refreshed on login AND on a
  // 5s poll thereafter (matching this app's existing poll conventions —
  // DisputeChatPanel's 4s, PaymentDetails' 6s — since there is no realtime
  // subscription anywhere in this codebase; see 03-dispute-chat.md). The
  // poll is also what makes every event type that already writes a
  // `notifications` row (booking confirmed, dispute resolved, a dispute
  // chat message, etc. — see 07-notifications.md) actually surface as a
  // toast while the app is open, instead of sitting invisible until
  // someone happens to open the bell screen.
  useEffect(() => {
    if (!s.user?.id) { set({ notifications: [], unreadNotifications: 0, toasts: [] }); return; }
    let active = true;
    // Captured synchronously, before the first fetch even goes out — a
    // notification created while that first request is still in flight
    // still has to toast, since the person genuinely hasn't seen it yet.
    // Diffing against "whatever the previous poll happened to return"
    // instead (this used to) has exactly that race: a row landing in the
    // gap between mount and the first response arriving would already be
    // present on that very first poll and so get silently marked "already
    // seen," never toasting at all. Comparing each row's own `created_at`
    // against a fixed point captured before any request starts has no such
    // gap. `toastedIds` then guards against toasting the same row twice
    // across polls once it has been shown.
    const sessionStart = new Date();
    const toastedIds = new Set();
    const poll = async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('recipient_id', s.user.id)
        .order('created_at', { ascending: false })
        .limit(50);
      if (!active || error) return;
      // Filtered client-side, not queried server-side —
      // muted_notification_kinds (062) exists purely for this, so a muted
      // kind neither shows in the list nor toasts (BUG 4).
      const rows = (data || []).filter(n => !s.mutedNotificationKinds.includes(n.kind));
      let attendingStale = false;
      // reject_pending_guest() ('booking_declined') and cancel_booking()
      // ('booking_cancelled') are two separate RPCs — different code,
      // different notification kind — but both mean the exact same thing
      // from this poll's point of view: a booking that may already be
      // sitting in s.attending/s.tickets (the "Going" tag) or in s.booking
      // (EventDetail's own "View Ticket" vs "Reserve" bar) just stopped
      // being real. Treated as one shared category here rather than
      // hardcoding just the one kind each fix happened to be written for.
      const CANCELLATION_KINDS = new Set(['booking_declined', 'booking_cancelled']);
      for (const n of rows) {
        if (!toastedIds.has(n.id) && new Date(n.created_at) > sessionStart) {
          toastedIds.add(n.id);
          pushToast(n);
          // Nothing else refreshes s.attending/s.tickets outside of
          // loadMyEvents()'s own sign-in-mount effect or goGoingList()
          // opening the Going tab (80423dd) — a guest whose booking just
          // got declined/cancelled while already looking at Home would
          // keep seeing "Going" indefinitely otherwise. This poll already
          // runs every 5s regardless of whether the toast is tapped, so
          // it's the one place that can catch this without a real
          // realtime subscription (none exist anywhere in this codebase,
          // see 03-dispute-chat.md).
          if (CANCELLATION_KINDS.has(n.kind)) {
            attendingStale = true;
            // EventDetail.jsx's own "Xem vé của bạn"/"View your ticket" bar
            // reads straight off the single top-level s.booking object
            // (whichever booking was last loaded into it), not off
            // paymentBookings/a fresh per-event query — it has no poll or
            // mount effect of its own. If that's the exact booking that
            // just got declined/cancelled, patch it in place so the bar
            // flips to "Reserve" on the very next render.
            if (n.data?.booking_id) {
              set(prev => (prev.booking?.id === n.data.booking_id
                ? { booking: { ...prev.booking, status: 'cancelled' } }
                : {}));
            }
          }
          // Admin Team pass (2026-10-02, migration 121) — revoke_admin()'s
          // own doc comment: "revocation must invalidate admin access, not
          // merely hide a tab until next login." Same proactive, not
          // tap-gated pattern as booking_declined's Going-tag fix above —
          // this poll already runs every 5s regardless of whether the
          // toast is tapped, so a revoked admin loses the Admin tab (and
          // whatever RLS-backed data it showed) within one cycle, not at
          // next sign-in.
          if (n.kind === 'admin_access_revoked') {
            set(prev => ({
              accountType: 'participant', canManageAdmins: false,
              accountTab: prev.accountTab === 'admin' ? 'personal' : prev.accountTab,
            }));
          }
        }
      }
      set({ notifications: rows, unreadNotifications: rows.filter(n => !n.read_at).length });
      if (attendingStale) loadMyEvents(s.user.id);
    };
    poll();
    const interval = setInterval(poll, 5000);
    return () => { active = false; clearInterval(interval); };
  }, [set, s.user?.id, s.mutedNotificationKinds, pushToast, loadMyEvents]);

  useEffect(() => {
    if (!s.user?.id) return;
    let active = true;
    (async () => { if (active) await loadMyEvents(s.user.id); })();
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.user?.id]);

  // Real conversations for the signed-in account, on either side: as the
  // guest (threads.guest_id = me) and as the organizer (threads.organizer_id
  // owned by me). Replaces the old local-only `chats` object.
  const loadInboxThreads = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return set({ inboxThreads: [] });
    // BUG 1 (2026-09-22 fourteenth follow-up) — stamped BEFORE any query
    // below fires, so it reflects when this REQUEST started, not when it
    // resolves — see lastReadWriteAtRef's own comment.
    const requestStartedAt = Date.now();

    const [{ data: asGuest }, { data: myOrgs }] = await Promise.all([
      supabase.from('threads').select('id, event_id, guest_id, organizer_id').eq('guest_id', uid),
      supabase.from('organizers').select('id').or(`owner_id.eq.${uid},user_id.eq.${uid}`),
    ]);

    const orgIds = (myOrgs || []).map(o => o.id);
    let asHost = [];
    if (orgIds.length) {
      const { data } = await supabase.from('threads').select('id, event_id, guest_id, organizer_id').in('organizer_id', orgIds);
      asHost = data || [];
    }
    const seen = new Set();
    const allThreads = [...(asGuest || []), ...asHost].filter(t => (seen.has(t.id) ? false : (seen.add(t.id), true)));
    if (!allThreads.length) return set({ inboxThreads: [] });

    const threadIds = allThreads.map(t => t.id);
    const { data: msgs } = await supabase
      .from('messages')
      .select('thread_id, body, sender_id, created_at, read_at')
      .in('thread_id', threadIds)
      .order('created_at', { ascending: false });
    const lastByThread = {};
    // Task 3 (2026-09-21 follow-up) — same unread signal the dock badge's
    // own poll uses (read_at IS NULL, not sent by me), reused here per-row
    // instead of a second computation, so Inbox.jsx can bold an unread row.
    const unreadThreadIds = new Set();
    for (const m of msgs || []) {
      if (!lastByThread[m.thread_id]) lastByThread[m.thread_id] = m;
      if (!m.read_at && m.sender_id !== uid) unreadThreadIds.add(m.thread_id);
    }

    // Task 2 (2026-09-21 follow-up) — per-participant star/archive state.
    const { data: prefRows } = await fetchThreadPrefRows(uid, threadIds);
    const prefsByThread = Object.fromEntries((prefRows || []).map(p => [p.thread_id, { starred: p.starred, archived: p.archived }]));
    const deletedAtByThread = Object.fromEntries((prefRows || []).filter(p => p.deleted_at).map(p => [p.thread_id, p.deleted_at]));

    // Merged-avatar badge (Inbox.jsx): the OTHER participant's own photo —
    // the guest's profiles.avatar_url when I'm the organizer, or the
    // organizer's owner/user profile avatar_url when I'm the guest. Reuses
    // the notification redesign's own `profiles.avatar_url` source (no new
    // column), joined through `organizers.owner_id`/`user_id` for the host
    // side since `organizers` itself has no avatar column.
    const orgIds2 = [...new Set(allThreads.map(t => t.organizer_id).filter(Boolean))];
    let orgOwnerByOrgId = {};
    let orgNameByOrgId = {};
    if (orgIds2.length) {
      const { data: orgRows } = await supabase.from('organizers').select('id, name, owner_id, user_id').in('id', orgIds2);
      orgOwnerByOrgId = Object.fromEntries((orgRows || []).map(o => [o.id, o.owner_id || o.user_id]));
      orgNameByOrgId = Object.fromEntries((orgRows || []).map(o => [o.id, o.name]));
    }

    const guestIds = [...new Set(allThreads.filter(t => t.guest_id !== uid).map(t => t.guest_id).filter(Boolean))];
    const avatarUserIds = [...new Set([...guestIds, ...Object.values(orgOwnerByOrgId).filter(Boolean)])];
    let guestNames = {};
    let avatarByUserId = {};
    if (avatarUserIds.length) {
      const { data: profiles } = await supabase.from('profiles').select('id, display_name, avatar_url').in('id', avatarUserIds);
      guestNames = Object.fromEntries((profiles || []).map(p => [p.id, p.display_name]));
      avatarByUserId = Object.fromEntries((profiles || []).filter(p => p.avatar_url).map(p => [p.id, p.avatar_url]));
    }

    // Message-host pass: a thread with zero messages (a goer opened "Message
    // <host>" under the old create-on-open behaviour and left) never shows,
    // and neither does one I deleted unless a newer message arrived since.
    const visibleThreads = allThreads.filter(t => {
      const last = lastByThread[t.id];
      return !!last && !isThreadDeletedForMe(deletedAtByThread[t.id], last.created_at);
    });
    const rows = visibleThreads.map(t => {
      // findEvent() falls back to EVENTS[0] (demo host "Bếp Nhỏ") for any key
      // that isn't a catalogue event, so a real event's host name/photo must
      // come from the database (the thread's own organizer), never from it.
      const isCatalog = EVENTS.some(e => e.key === t.event_id);
      const ev = isCatalog ? findEvent(t.event_id) : { orgName: '', img: '' };
      const last = lastByThread[t.id];
      const iAmGuest = t.guest_id === uid;
      const name = iAmGuest ? (orgNameByOrgId[t.organizer_id] || ev.orgName) : ((guestNames[t.guest_id] || '').trim() || 'Khách');
      const otherAvatarUrl = iAmGuest ? avatarByUserId[orgOwnerByOrgId[t.organizer_id]] : avatarByUserId[t.guest_id];
      return {
        threadId: t.id,
        eventKey: t.event_id,
        name,
        img: ev.img,
        otherAvatarUrl: otherAvatarUrl || null,
        snippet: last ? ((last.sender_id === uid ? 'Bạn: ' : '') + last.body) : '',
        lastAt: last?.created_at || null,
        unread: unreadThreadIds.has(t.id),
      };
    }).sort((a, b) => new Date(b.lastAt || 0) - new Date(a.lastAt || 0));

    // BUG 1 (2026-09-22 fourteenth follow-up) — this request's own messages
    // query (above) could have started before a mark-read committed and
    // resolved after, in which case `unreadThreadIds` here reflects the
    // stale, pre-write state; applying it would revert that thread's row
    // back to unread. Discarding it here is safe: `markThreadMessagesRead()`
    // already patched `inboxThreads` directly, and any genuinely NEW
    // incoming message triggers its own later poll/open that isn't stale.
    if (requestStartedAt < lastReadWriteAtRef.current) return;
    set({ inboxThreads: rows, inboxThreadPrefs: prefsByThread });
  }, [set, s.user?.id]);

  // Task 2 (2026-09-21 follow-up) — swipe-left "Star"/"Archive" actions.
  // Upserts into thread_preferences (migration 065), scoped by RLS to
  // `user_id = auth.uid()` so a guest and the organizer on the same thread
  // always get independent state — one side archiving a thread never
  // changes what the other side's own Inbox shows for it.
  const toggleThreadStar = useCallback(async (threadId) => {
    const uid = s.user?.id;
    if (!uid) return;
    const current = s.inboxThreadPrefs[threadId] || { starred: false, archived: false };
    const next = { ...current, starred: !current.starred };
    set(prev => ({ inboxThreadPrefs: { ...prev.inboxThreadPrefs, [threadId]: next } }));
    const { error } = await supabase.from('thread_preferences').upsert({ thread_id: threadId, user_id: uid, ...next });
    if (error) {
      console.warn('toggleThreadStar failed:', error);
      set(prev => ({ inboxThreadPrefs: { ...prev.inboxThreadPrefs, [threadId]: current } }));
    }
  }, [set, s.user?.id, s.inboxThreadPrefs]);
  const archiveThread = useCallback(async (threadId) => {
    const uid = s.user?.id;
    if (!uid) return;
    const current = s.inboxThreadPrefs[threadId] || { starred: false, archived: false };
    const next = { ...current, archived: true };
    set(prev => ({ inboxThreadPrefs: { ...prev.inboxThreadPrefs, [threadId]: next } }));
    const { error } = await supabase.from('thread_preferences').upsert({ thread_id: threadId, user_id: uid, ...next });
    if (error) {
      console.warn('archiveThread failed:', error);
      set(prev => ({ inboxThreadPrefs: { ...prev.inboxThreadPrefs, [threadId]: current } }));
    }
  }, [set, s.user?.id, s.inboxThreadPrefs]);
  const unarchiveThread = useCallback(async (threadId) => {
    const uid = s.user?.id;
    if (!uid) return;
    const current = s.inboxThreadPrefs[threadId] || { starred: false, archived: false };
    const next = { ...current, archived: false };
    set(prev => ({ inboxThreadPrefs: { ...prev.inboxThreadPrefs, [threadId]: next } }));
    const { error } = await supabase.from('thread_preferences').upsert({ thread_id: threadId, user_id: uid, ...next });
    if (error) {
      console.warn('unarchiveThread failed:', error);
      set(prev => ({ inboxThreadPrefs: { ...prev.inboxThreadPrefs, [threadId]: current } }));
    }
  }, [set, s.user?.id, s.inboxThreadPrefs]);
  // Message-host pass — "Delete" from the Inbox row menu (active or archived
  // view). Hides the conversation for ME only: thread_preferences.deleted_at
  // (migration 156); the other participant keeps it, and a message newer than
  // deleted_at brings it back (see loadInboxThreads). Stamped with the
  // thread's last message time rather than the local clock so client/server
  // clock skew can't hide a brand-new reply or resurrect the thread at once.
  const deleteThreadForMe = useCallback(async (threadId) => {
    const uid = s.user?.id;
    if (!uid) return;
    const row = s.inboxThreads.find(t => t.threadId === threadId);
    const deletedAt = row?.lastAt ? new Date(row.lastAt).toISOString() : new Date().toISOString();
    const prevThreads = s.inboxThreads;
    set(prev => ({ inboxThreads: prev.inboxThreads.filter(t => t.threadId !== threadId), unreadMessages: row?.unread ? Math.max(0, prev.unreadMessages - 1) : prev.unreadMessages }));
    const current = s.inboxThreadPrefs[threadId] || { starred: false, archived: false };
    const { error } = await supabase.from('thread_preferences').upsert({ thread_id: threadId, user_id: uid, ...current, deleted_at: deletedAt });
    if (error) {
      // Column missing (migration 156 not applied) or any other failure — warn and restore.
      console.warn('deleteThreadForMe failed:', error);
      set({ inboxThreads: prevThreads });
    }
  }, [set, s.user?.id, s.inboxThreads, s.inboxThreadPrefs]);
  const setInboxView = useCallback((view) => set({ inboxView: view }), [set]);

  // Task 1b — "Give feedback" (app_feedback, migration 065). No existing
  // generic feedback table (confirmed via grep before adding this one).
  const submitFeedback = useCallback(async (body, isBugReport) => {
    const uid = s.user?.id;
    if (!uid) return { success: false };
    const { error } = await supabase.from('app_feedback').insert({ user_id: uid, body: body.trim(), is_bug_report: !!isBugReport });
    if (error) {
      console.warn('submitFeedback failed:', error);
      return { success: false };
    }
    return { success: true };
  }, [s.user?.id]);

  // Inbox tab badge (BottomTabBar.jsx) — mirrors unreadNotifications' own
  // poll (this app has no realtime subscription anywhere to hook into
  // instead, see 03-dispute-chat.md), reusing loadInboxThreads' exact
  // thread-scoping (guest_id = me, or organizer_id owned by me) rather than
  // inventing a new join.
  //
  // 2026-09-21 follow-up: counts CONVERSATIONS with at least one unread
  // message, not raw unread message count — matches how most messaging apps
  // show an unread badge (a 5-message thread counts once), and keeps this
  // badge meaningfully small enough that BottomTabBar.jsx no longer caps it
  // at "9+" the way the Notifications bell does.
  useEffect(() => {
    const uid = s.user?.id;
    if (!uid) { set({ unreadMessages: 0 }); return; }
    let active = true;
    const poll = async () => {
      // BUG 1 (2026-09-22 fourteenth follow-up) — stamped before any query
      // below fires — see lastReadWriteAtRef's own comment, and
      // loadInboxThreads()'s identical guard just above.
      const requestStartedAt = Date.now();
      const [{ data: asGuest }, { data: myOrgs }] = await Promise.all([
        supabase.from('threads').select('id').eq('guest_id', uid),
        supabase.from('organizers').select('id').or(`owner_id.eq.${uid},user_id.eq.${uid}`),
      ]);
      const orgIds = (myOrgs || []).map(o => o.id);
      let asHost = [];
      if (orgIds.length) {
        const { data } = await supabase.from('threads').select('id').in('organizer_id', orgIds);
        asHost = data || [];
      }
      const threadIds = [...new Set([...(asGuest || []), ...asHost].map(t => t.id))];
      if (!active || requestStartedAt < lastReadWriteAtRef.current) return;
      if (!threadIds.length) { set({ unreadMessages: 0 }); return; }
      // BUG (2026-09-22 sixteenth follow-up) — same NULL-unsafe `.neq()`
      // fix as markThreadMessagesRead() above, so a system message
      // (sender_id IS NULL) counts toward this badge too.
      const { data: unreadRows } = await supabase
        .from('messages')
        .select('thread_id, created_at')
        .in('thread_id', threadIds)
        .is('read_at', null)
        .or(`sender_id.is.null,sender_id.neq.${uid}`);
      // Threads I deleted (migration 156) don't count until something newer arrives.
      const { data: prefRows } = await fetchThreadPrefRows(uid, threadIds);
      const deletedAt = Object.fromEntries((prefRows || []).filter(p => p.deleted_at).map(p => [p.thread_id, p.deleted_at]));
      const counted = (unreadRows || []).filter(r => !isThreadDeletedForMe(deletedAt[r.thread_id], r.created_at));
      if (active && requestStartedAt >= lastReadWriteAtRef.current) {
        set({ unreadMessages: new Set(counted.map(r => r.thread_id)).size });
      }
    };
    poll();
    const interval = setInterval(poll, 5000);
    return () => { active = false; clearInterval(interval); };
  }, [set, s.user?.id]);

  // Completion-gating fix (2026-09-30) — this used to be the ONLY way
  // Splash ever auto-advanced, a flat 2.6s timer with no relationship to
  // the logomotion animation's own real length. It's now a bounded
  // FALLBACK (bumped 2.6s -> 6s, past the animation's real expected
  // duration) so a WebView/iframe load failure or missing asset can't
  // strand the user on Splash forever — the real gate is the
  // `s.logomotionComplete` effect right below, which normally fires
  // first and clears this timer before it ever runs.
  const splashTimer = useRef(null);
  const splashAdvance = useCallback(() => {
    setStateRaw(prev => {
      if (prev.screen !== 'splash') return prev;
      // First-ever visit still goes through language/theme regardless of
      // auth — the mandatory-login gate applies once that's done
      // (finishOnboarding), not before.
      if (!prev.hasOnboarded) return { ...prev, screen: 'langPick' };
      return { ...prev, ...postAuthDestination(prev) };
    });
  }, []);
  useEffect(() => {
    splashTimer.current = setTimeout(splashAdvance, 6000);
    return () => clearTimeout(splashTimer.current);
  }, [splashAdvance]);
  // Completion-gating fix (2026-09-30) — advances as soon as the
  // logomotion iframe reports one real completed animation cycle, instead
  // of only ever on the fixed timer above. Reduce Motion doesn't need its
  // own branch here — Splash.jsx's `prefers-reduced-motion` check makes
  // the iframe itself fire `logomotion-complete` immediately in that case
  // (see `logomotion2309.html`'s `prefersReducedMotion()`).
  //
  // 1.0s completed-motion dwell (2026-09-30, second pass) — on the NORMAL
  // (non-Reduce-Motion) path only, hold on the already-completed final
  // frame (the iframe already does this by removing its ticker, unchanged
  // here) for one extra named second before advancing. Started at the
  // exact moment the real completion signal fires, not from mount/asset-
  // ready/bootstrap-done. `sessionCheckedRef` mirrors `s.sessionChecked`
  // so the dwell's own timeout callback (which only runs once, later)
  // reads the LATEST readiness value instead of a stale one captured when
  // the effect first ran — whichever of {dwell, sessionChecked} finishes
  // last is what actually calls `splashAdvance` (`splashAdvance` itself is
  // idempotent — it's a no-op once `screen !== 'splash'` — so both call
  // sites can safely fire speculatively). Reduce Motion is detected here
  // via `matchMedia` (native, not the iframe's own signal) and skips the
  // dwell entirely, advancing immediately exactly as before this pass.
  const splashDwellTimer = useRef(null);
  const splashDwellDone = useRef(false);
  const sessionCheckedRef = useRef(s.sessionChecked);
  useEffect(() => { sessionCheckedRef.current = s.sessionChecked; }, [s.sessionChecked]);
  useEffect(() => {
    if (!s.sessionChecked) return;
    if (splashDwellDone.current) splashAdvance();
  }, [s.sessionChecked, splashAdvance]);
  useEffect(() => {
    if (!s.logomotionComplete) return;
    clearTimeout(splashTimer.current);
    const reduceMotion = typeof window !== 'undefined' && window.matchMedia
      && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduceMotion) { splashAdvance(); return undefined; }
    splashDwellTimer.current = setTimeout(() => {
      splashDwellDone.current = true;
      if (sessionCheckedRef.current) splashAdvance();
    }, 1000);
    return () => clearTimeout(splashDwellTimer.current);
  }, [s.logomotionComplete, splashAdvance]);
  const notifyLogomotionComplete = useCallback(() => set({ logomotionComplete: true }), [set]);
  const dismissSplash = useCallback(() => {
    clearTimeout(splashTimer.current);
    clearTimeout(splashDwellTimer.current);
    set(prev => {
      if (prev.screen !== 'splash') return {};
      if (!prev.hasOnboarded) return { screen: 'langPick' };
      return postAuthDestination(prev);
    });
  }, [set]);

  // Once signed in, language & theme are account preferences, not just this
  // browser's — persist every change so it follows the account anywhere.
  const persistAccountPreference = useCallback((patch) => {
    if (!s.user?.id) return;
    supabase
      .from('profiles')
      .update({ ...patch, prefs_saved: true })
      .eq('id', s.user.id)
      .then(({ error }) => {
        if (error) console.warn('Failed to save preferences to account:', error);
      });
  }, [s.user?.id]);

  const pickVi = useCallback(() => { set({ lang: 'vi', screen: 'themePick' }); persistAccountPreference({ locale: 'vi' }); }, [set, persistAccountPreference]);
  const pickEn = useCallback(() => { set({ lang: 'en', screen: 'themePick' }); persistAccountPreference({ locale: 'en' }); }, [set, persistAccountPreference]);
  const pickLight = useCallback(() => { set({ theme: 'light' }); persistAccountPreference({ theme: 'light' }); }, [set, persistAccountPreference]);
  const pickDark = useCallback(() => { set({ theme: 'dark' }); persistAccountPreference({ theme: 'dark' }); }, [set, persistAccountPreference]);
  // Task 1: no guest browsing of any screen — lands on the mandatory Login
  // gate instead of Home when not actually signed in, preserving where the
  // shared-org-link case wanted to go (postAuthDestination).
  const finishOnboarding = useCallback(() => set(prev => postAuthDestination(prev)), [set]);

  const EN = s.lang === 'en';
  const T = useCallback((vi, en) => (EN ? en : vi), [EN]);
  const toggleTheme = useCallback(() => {
    const next = s.theme === 'dark' ? 'light' : 'dark';
    set({ theme: next });
    persistAccountPreference({ theme: next });
  }, [set, s.theme, persistAccountPreference]);
  const pickTheme = useCallback((theme) => { set({ theme }); persistAccountPreference({ theme }); }, [set, persistAccountPreference]);

  // Task 1's consent checkbox (Login.jsx) — unticked by default, gates
  // submitCurrentForm alongside the existing email/password validity
  // checks. Recorded server-side in syncUser() once a session exists,
  // never here (this is only ever the transient, pre-session UI state).
  const togglePolicyConsent = useCallback(() => set(prev => ({ policyConsent: !prev.policyConsent })), [set]);
  const openPolicy = useCallback(() => set(prev => ({ screen: 'policy', policyBackScreen: prev.screen })), [set]);
  const backFromPolicy = useCallback(() => set(prev => ({ screen: prev.policyBackScreen || 'login' })), [set]);

  // The "I agree" button Policy.jsx shows only while policyGateActive
  // (syncUser()'s post-OAuth-redirect consent gate for a brand-new
  // Google/Facebook profile — see note 10). Stamps consent for real, then
  // hands off to the exact same postAuthDestination() every other sign-in
  // path uses, so this doesn't need its own bespoke "where do I go now".
  const acceptPolicyGate = useCallback(async () => {
    if (!s.user?.id) return;
    const { error } = await supabase
      .from('profiles')
      .update({ policy_accepted_at: new Date().toISOString(), policy_version: POLICY_VERSION })
      .eq('id', s.user.id);
    if (error) { console.warn('Failed to record policy consent:', error); return; }
    set(prev => ({ policyGateActive: false, ...postAuthDestination(prev) }));
  }, [set, s.user?.id]);
  // Tapping a photo in either gallery ("Hình ảnh" on an event, "Ảnh của X"
  // on an organizer page) opens it larger, over a dimmed backdrop, with the
  // whole gallery loaded in behind it so left/right swipes can move through
  // the rest without closing and reopening the viewer.
  // navigator.vibrate is the web's only haptic and iOS Safari doesn't
  // implement it, so this is a no-op there — the native app does it
  // properly (see AppState.openPhoto).
  // originRect: the tapped thumbnail's getBoundingClientRect() at click
  // time — where PhotoViewer's dismiss animation shrinks back to (see
  // 14-photo-viewer.md). Copied into a plain object immediately; a live
  // DOMRect is a view onto layout that can change/go stale, and this one
  // only ever needs to be read back later, never re-measured.
  // `gallery` is now an array of { id, url, eventId } — the real
  // event_photos.id and its OWN owning event id, not just a bare URL. This
  // is the identity fix (17-ux-foundation-release.md's own trace found
  // PhotoViewer only ever knew a photo's URL, never its real database row —
  // the root cause of every like/save/share mismatch with Pulse). Every
  // caller (EventDetail/Organizer grids) now passes its own fetched
  // `event_photos` rows shaped this way instead of a plain URL list — see
  // those screens' own gallery-building code.
  const openPhoto = useCallback((gallery, index, organizer, originRect) => {
    try { navigator.vibrate?.(8); } catch { /* unsupported — no haptic, no harm */ }
    const rect = originRect
      ? { top: originRect.top, left: originRect.left, width: originRect.width, height: originRect.height }
      : null;
    set({ photoViewer: { gallery, index, organizer, originRect: rect } });
  }, [set]);
  const closePhoto = useCallback(() => set({ photoViewer: null }), [set]);
  const showPhotoAt = useCallback((index) => set(prev => {
    if (!prev.photoViewer) return {};
    const clamped = Math.max(0, Math.min(index, prev.photoViewer.gallery.length - 1));
    return { photoViewer: { ...prev.photoViewer, index: clamped } };
  }), [set]);

  /** Real, server-enforced like toggle for ANY real photo (migration 083's
   * toggle_photo_like RPC) — the ONE like path for EventDetail's/
   * Organizer's grids, the full-screen PhotoViewer AND Pulse's photo tab
   * (replaces the old per-surface `togglePulsePhotoLike`, folded in here).
   * Optimistic with rollback on failure; `photoEngagementBusy` blocks a
   * double tap/racing toggle on the same photo id, same guard shape the
   * Pulse-only version already had. */
  const togglePhotoLike = useCallback(async (photoId) => {
    if (!s.user?.id) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'profile' });
    if (s.photoEngagementBusy[photoId]) return;
    const cur = s.photoEngagement[photoId] || { likeCount: 0, shareCount: 0, likedByMe: false };
    const wasLiked = cur.likedByMe;
    const delta = wasLiked ? -1 : 1;
    // Computed ONCE, up front, and reused for both the optimistic write and
    // the later reconciliation — rather than re-reading `prev.photoEngagement`
    // a second time inside the post-await `set()` call. The two `set()`
    // calls straddle a real network await, and re-deriving from `prev` at
    // that point turned out to race a concurrent render pass and silently
    // drop the optimistic count bump (confirmed live: `prev` inside the
    // second call's updater still reflected the PRE-toggle entry even
    // though the first call had already committed and painted the liked
    // heart) — closing over the value we already know is correct sidesteps
    // that entirely instead of trusting a second, unnecessary state read.
    const optimistic = { ...cur, likedByMe: !wasLiked, likeCount: Math.max(0, cur.likeCount + delta) };
    set(prev => ({
      photoEngagement: { ...prev.photoEngagement, [photoId]: optimistic },
      photoEngagementBusy: { ...prev.photoEngagementBusy, [photoId]: true },
    }));
    const { data, error } = await supabase.rpc('toggle_photo_like', { p_event_photo_id: photoId });
    if (error) {
      console.warn('togglePhotoLike failed:', error);
      set(prev => ({
        photoEngagement: { ...prev.photoEngagement, [photoId]: cur },
        photoEngagementBusy: { ...prev.photoEngagementBusy, [photoId]: false },
      }));
      return;
    }
    // Reconcile against the RPC's own authoritative boolean — it toggles
    // whatever the SERVER's current row state actually is, which can
    // legitimately differ from this client's optimistic guess (e.g. a like
    // from a different session this client never saw yet). Only the
    // boolean is corrected; the count stays the one we already applied
    // optimistically (see the comment above `optimistic`).
    set(prev => ({
      photoEngagement: { ...prev.photoEngagement, [photoId]: { ...optimistic, likedByMe: data } },
      photoEngagementBusy: { ...prev.photoEngagementBusy, [photoId]: false },
    }));
  }, [set, s.user?.id, s.photoEngagementBusy, s.photoEngagement]);

  /** Real share tracking for ANY real photo (migration 083's
   * log_photo_share RPC) — logged ONLY once the share genuinely completes:
   * `navigator.share()`'s own promise resolving (rejects on cancel, caught
   * below and never logged), or a copy-link write actually succeeding.
   * Never logged just from opening the share affordance. Link carries
   * `pid` (the real event_photos id) through `/api/photo-share`, which
   * resolves the real photo/event/organizer server-side. `item` is
   * `{ photo_id, organizer_name }` — the same shape Pulse's ranked photo
   * rows already have; EventDetail/Organizer/PhotoViewer construct it from
   * their own gallery entry. */
  const sharePhoto = useCallback(async (item) => {
    const photoId = item.photo_id;
    const url = `https://banbe-two.vercel.app/api/photo-share?pid=${encodeURIComponent(photoId)}`;
    const title = T(`Ảnh từ ${item.organizer_name} trên banbe`, `A photo from ${item.organizer_name} on banbe`);
    const text = T('Xem ảnh này trên banbe:', 'Check out this photo on banbe:');
    const done = () => {
      set({ photoShared: true });
      setTimeout(() => set({ photoShared: false }), 1800);
    };
    const logShare = async (channel) => {
      const { error } = await supabase.rpc('log_photo_share', { p_event_photo_id: photoId, p_channel: channel });
      if (error) { if (import.meta.env?.DEV) console.warn('log_photo_share failed:', error); return; }
      set(prev => ({
        photoEngagement: {
          ...prev.photoEngagement,
          [photoId]: {
            ...(prev.photoEngagement[photoId] || { likeCount: 0, likedByMe: false, shareCount: 0 }),
            shareCount: (prev.photoEngagement[photoId]?.shareCount || 0) + 1,
          },
        },
      }));
    };
    if (navigator.share) {
      try { await navigator.share({ title, text, url }); await logShare('native'); } catch { /* cancelled — not a completed share, nothing to log */ }
      done();
    } else if (navigator.clipboard) {
      try { await navigator.clipboard.writeText(url); await logShare('copy'); } catch { /* clipboard write denied */ }
      done();
    } else { done(); }
  }, [set, T]);

  // ---- payments & documents ----
  // The one rule the whole feature is built around: banbe is not a payment
  // processor and never becomes one here. Money moves directly between the
  // two people. What the app owns is telling the guest where to send it,
  // letting them show they did, letting the organizer confirm it, and
  // giving both sides a document afterwards.

  /** Every booking this account holds, with the organizer's payment details attached. */
  const loadPaymentBookings = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return set({ paymentBookings: [], paymentsLoading: false });
    set({ paymentsLoading: true });
    const { data, error } = await supabase
      .from('bookings')
      .select(`id, qty, total_vnd, code, status, expires_at, paid_marked_at, paid_method,
               proof_path, proof_uploaded_at, created_at, event_id,
               payment_state, payment_ref, hold_expires_at, transaction_id, verify_due_at, dispute_reason, cancel_reason, nudge_count,
               events(id, key, name, event_date, event_time, area, organizer_id,
                      organizers(id, name, pay_methods, bank_name, bank_account_name,
                                 bank_account_no, momo_phone, pay_note, pay_qr_path))`)
      .eq('user_id', uid)
      .order('created_at', { ascending: false });
    if (error) {
      console.warn('loadPaymentBookings failed:', error);
      return set({ paymentsLoading: false, paymentBookings: [] });
    }
    set({ paymentsLoading: false, paymentBookings: data || [] });
  }, [set, s.user?.id]);

  const openPaymentDetails = useCallback((bookingId, back = 'profile') => {
    set({ screen: 'paymentDetails', paymentBookingId: bookingId, paymentBack: back, paymentProofError: '' });
  }, [set]);
  // A rejected/cancelled booking is over — going back to whatever screen
  // sent the guest here (often the ticket/profile screen, which can itself
  // still be mid-transition off a now-dead timer UI) is exactly the
  // "lingering countdown before actually leaving" this was fixed for.
  // Straight to Home instead, every time, for this one terminal state.
  const backFromPaymentDetails = useCallback(() => set(prev => {
    const b = prev.paymentBookings.find(x => x.id === prev.paymentBookingId);
    // Bug 3 (15-organizer-checkin.md follow-up): a confirmed booking is as
    // terminal here as a cancelled one — the "Paid" card's own button (not
    // this back path) is how a guest reaches their ticket now, so leaving
    // via back should land on Home directly too, same reasoning as the
    // cancelled case above.
    const isTerminal = b?.payment_state === 'cancelled' || b?.payment_state === 'confirmed';
    return { screen: isTerminal ? 'home' : (prev.paymentBack || 'profile') };
  }), [set]);
  const backFromBilling = useCallback(() => set({ screen: 'paymentDetails' }), [set]);

  /** Copy-to-clipboard with a short "copied" flash, keyed by field. */
  const copyPayField = useCallback((field, value) => {
    const flash = () => {
      set({ paymentCopied: field });
      setTimeout(() => set(prev => (prev.paymentCopied === field ? { paymentCopied: '' } : {})), 1600);
    };
    if (navigator.clipboard) navigator.clipboard.writeText(String(value)).then(flash, flash);
    else flash();
  }, [set]);

  /**
   * The guest's "I've transferred" evidence. Note what this deliberately
   * does NOT do: mark the booking paid. Only the organizer, who can see
   * their own account, gets to say money arrived.
   */
  const uploadPaymentProof = useCallback(async (bookingId, file) => {
    if (!bookingId || !file) return;
    set({ paymentProofUploading: true, paymentProofError: '' });
    try {
      // Re-encodes anything outside the bucket's allowed image/jpeg,
      // image/png, image/webp, application/pdf (HEIC, GIF, BMP, a renamed
      // file with no MIME type at all, …) to a JPEG it will actually accept
      // — see proofUpload.js for why this beats rejecting those up front.
      const { blob, ext, contentType } = await normalizeProofFile(file);
      // The path's first segment is the booking id — that is exactly what
      // the bucket's RLS policies split on, so a file can only ever land
      // under a booking the uploader owns.
      const path = `${bookingId}/proof-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('pay-proof').upload(path, blob, { upsert: true, contentType });
      if (upErr) throw upErr;
      const { data, error } = await supabase.rpc('mark_payment_proof', { p_booking: bookingId, p_path: path, p_note: '' });
      if (error) throw error;
      if (data && data.success === false) throw new Error(data.error || 'PROOF_FAILED');
      set({ paymentProofUploading: false });
      await loadPaymentBookings();
    } catch (e) {
      console.warn('uploadPaymentProof failed:', e);
      set({
        paymentProofUploading: false,
        paymentProofError: e.message === 'CONVERT_FAILED'
          ? T('Không đọc được ảnh này. Thử một ảnh hoặc file khác.', "Couldn't read that file. Try a different photo or file.")
          : T('Không gửi được ảnh xác nhận. Thử lại nhé.', "Couldn't send that confirmation. Please try again."),
      });
    }
  }, [set, T, loadPaymentBookings]);

  /**
   * PHASE 1 -> PHASE 2. Uploads the proof, then calls submit_payment_proof,
   * which is what actually freezes the countdown server-side. The client
   * never decides this: a frozen timer that only exists in React state would
   * unfreeze on reload and the seat would be swept.
   */
  const submitPaymentProof = useCallback(async (bookingId, file, transactionId) => {
    const txn = String(transactionId || '').trim();
    if (!bookingId || !file || !txn) {
      return set({ paymentSubmitError: T('Cần cả mã giao dịch và ảnh biên lai.',
                                         'Both a transaction ID and a receipt image are required.') });
    }
    set({ paymentSubmitting: true, paymentSubmitError: '' });
    try {
      // Re-encodes anything outside the bucket's allowed image/jpeg,
      // image/png, image/webp, application/pdf (HEIC, GIF, BMP, a renamed
      // file with no MIME type at all, …) to a JPEG it will actually accept
      // — see proofUpload.js for why this beats rejecting those up front.
      // This is exactly what made an arbitrary test image fail to upload:
      // the bucket's storage RLS/allowlist silently rejected it, which
      // surfaced here only as the generic "Couldn't submit" fallback below.
      const { blob, ext, contentType } = await normalizeProofFile(file);
      const path = `${bookingId}/proof-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('pay-proof').upload(path, blob, { upsert: true, contentType });
      if (upErr) throw upErr;

      // The organizer's PHASE 2 response window — 60 minutes, not the
      // buyer's own PHASE 1 hold (30 minutes, hold_seats()'s hold_minutes).
      // These are two independent clocks on two different people; picking
      // the wrong one here silently gave the organizer a 15-minute window
      // instead of the intended 60.
      const { data, error } = await supabase.rpc('submit_payment_proof', {
        p_booking: bookingId, p_transaction_id: txn, p_proof_path: path,
        p_ip: null, p_user_agent: navigator.userAgent, p_sla_minutes: 60,
      });
      if (error) throw error;
      if (data?.success === false) {
        const message = {
          HOLD_EXPIRED_AND_SOLD_OUT: T('Rất tiếc, chỗ đã hết trong lúc chờ thanh toán. Hãy liên hệ người tổ chức để được hoàn tiền.',
                                       'Sorry — the seat sold out while this was pending. Contact the organizer for a refund.'),
          TRANSACTION_ID_REQUIRED: T('Cần mã giao dịch.', 'A transaction ID is required.'),
          PROOF_REQUIRED: T('Cần ảnh biên lai.', 'A receipt image is required.'),
        }[data.error] || T('Chưa gửi được. Thử lại nhé.', "Couldn't submit. Please try again.");
        throw new Error(message);
      }
      set({ paymentSubmitting: false, paymentTxnId: '' });
      // Patch `paymentBookings` in place FIRST, before the refetch below —
      // PaymentDetails derives `booking` straight from this array on every
      // render, so an immediate patch means the very next render (including
      // one after navigating away and straight back in, which remounts
      // PaymentDetails and fires its own loadPaymentBookings() again) can
      // never race an in-flight fetch and land on stale 'holding' data; it
      // already has the right phase before any network round trip returns.
      set(prev => ({
        paymentBookings: prev.paymentBookings.map(b => (b.id === bookingId
          ? { ...b, payment_state: 'pending_verification', transaction_id: txn, proof_path: path, verify_due_at: data?.verify_due_at || null }
          : b)),
      }));
      await loadPaymentBookings();
      // The ticket screen (Confirmed) keeps its own copy of this booking in
      // top-level state, set whenever it was reserved or last reopened — not
      // refreshed by loadPaymentBookings() above. Without this, submitting
      // proof here left that screen showing a PHASE 1 countdown for a
      // booking that had just been frozen into PHASE 2 until something else
      // happened to reload it.
      set(prev => (prev.booking?.id === bookingId
        ? { booking: { ...prev.booking, payment_state: 'pending_verification', transaction_id: txn, verify_due_at: data?.verify_due_at || null } }
        : {}));
      return data;
    } catch (e) {
      console.warn('submitPaymentProof failed:', e);
      const message = e.message === 'CONVERT_FAILED'
        ? T('Không đọc được ảnh này. Thử một ảnh hoặc file khác.', "Couldn't read that file. Try a different photo or file.")
        : e.message || T('Chưa gửi được. Thử lại nhé.', "Couldn't submit. Please try again.");
      set({ paymentSubmitting: false, paymentSubmitError: message });
    }
  }, [set, T, loadPaymentBookings]);

  const paymentTxnType = useCallback((e) => set({ paymentTxnId: e.target.value, paymentSubmitError: '' }), [set]);

  /**
   * 14-organizer-checkin.md (Bug 1 follow-up): the guest's ONE actionable
   * control while awaiting the organizer's confirm window — nudges the
   * organizer via the same in-app toast + bell notification every other
   * event in this lifecycle already uses (this app has no real push infra,
   * see 07-notifications.md). Rate-limited server-side to 2 uses per hold
   * (nudge_organizer() RPC, migration 059) — the button disables itself
   * once `nudge_count` reaches that, not just a client-side debounce that
   * would reset on reload.
   */
  const nudgeOrganizer = useCallback(async (bookingId) => {
    set({ nudgeSending: true, nudgeError: '' });
    const { data, error } = await supabase.rpc('nudge_organizer', { p_booking: bookingId });
    if (error || !data?.success) {
      set({
        nudgeSending: false,
        nudgeError: data?.error === 'NUDGE_LIMIT_REACHED'
          ? T('Bạn đã nhắc tối đa 2 lần cho lượt giữ chỗ này.', "You've already nudged the max 2 times for this hold.")
          : T('Không gửi được lời nhắc. Thử lại nhé.', "Couldn't send the nudge. Please try again."),
      });
      return;
    }
    set(prev => ({
      nudgeSending: false,
      paymentBookings: prev.paymentBookings.map(b => (b.id === bookingId ? { ...b, nudge_count: data.nudge_count } : b)),
    }));
  }, [set, T]);

  // 15-organizer-checkin.md follow-up: Confirmed.jsx's "Xem Receipt" needs
  // to know, per booking, whether a live payment_documents receipt already
  // exists before deciding whether tapping it opens that file or sends a
  // request instead.
  const loadReceiptStatus = useCallback(async (bookingId) => {
    const { data } = await supabase
      .from('payment_documents')
      .select('*')
      .eq('booking_id', bookingId).eq('kind', 'receipt').is('superseded_at', null)
      .maybeSingle();
    set({ receiptDoc: data || false });
  }, [set]);

  const requestReceipt = useCallback(async (bookingId) => {
    set({ receiptRequestSending: true, receiptRequestError: '' });
    const { data, error } = await supabase.rpc('request_receipt', { p_booking: bookingId });
    if (error || !data?.success) {
      set({
        receiptRequestSending: false,
        receiptRequestError: data?.error === 'ALREADY_REQUESTED_RECENTLY'
          ? T('Bạn vừa yêu cầu gần đây, hãy đợi người tổ chức phản hồi.', "You already asked recently, give the organizer a little time to respond.")
          : T('Không gửi được yêu cầu. Thử lại nhé.', "Couldn't send the request. Please try again."),
      });
      return;
    }
    set({ receiptRequestSending: false, receiptRequestSent: true });
  }, [set, T]);

  /**
   * The dynamic VietQR payload for a booking, or null when the organizer
   * hasn't given us a bank account we can build one from. Returns the raw
   * EMVCo string; the screen renders it with the same qrcode lib the ticket
   * QR already uses.
   */
  const vietQrFor = useCallback((booking) => {
    const org = booking?.events?.organizers;
    if (!org?.bank_account_no || !org?.bank_name) return null;
    try {
      return buildVietQrPayload({
        bank: org.bank_name,
        accountNumber: org.bank_account_no,
        amountVnd: booking.total_vnd,
        memo: booking.payment_ref || booking.code || '',
      });
    } catch (e) {
      // An unrecognised bank name is an organizer data problem, not a crash:
      // the screen falls back to showing the account details as text.
      console.warn('VietQR unavailable:', e.message);
      return null;
    }
  }, []);

  // ---- organizer verification queue ----
  // Guarded here, not just by the organizer-mode-gated UI that links here
  // (Home's banner, Account's "Awaiting verification" row) — this is the
  // one place that actually decides whether the screen opens at all, so a
  // participant navigating here by any other means (a stale link, a replayed
  // notification, …) still can't land on what is meant to be an
  // organizer-only management screen. RLS already limits what data such a
  // request could ever read (a participant only ever owns their own booking
  // row), but this keeps them from seeing the screen's organizer-framed
  // copy and action buttons ("Money received"/"Can't find it") over their
  // own payment at all, not just from acting on it.
  const openVerifications = useCallback((back = 'profile') => {
    if (!(s.organizerMode || s.accountType === 'admin' || s.hasHosted)) return;
    set({ screen: 'verifications', verifications: [], verificationsLoading: true, verificationsFocusBookingId: null, verificationsBack: back });
  }, [set, s.organizerMode, s.accountType, s.hasHosted]);
  const backFromVerifications = useCallback(() => set(prev => ({ screen: prev.verificationsBack || 'profile' })), [set]);
  /** Refund-discoverability fix — a dedicated "Refunds" row/entry point.
   * Calls the EXACT SAME openVerifications() above (same gate, same screen,
   * same data loaders) and only additionally sets a one-shot scroll flag —
   * no duplicated backend/state logic, no second refund surface. */
  const openVerificationsRefunds = useCallback((back = 'profile') => {
    openVerifications(back);
    set({ verificationsScrollToRefunds: true });
  }, [openVerifications, set]);

  /**
   * 14-organizer-checkin.md: Attendance's "Check payment" — jumps straight
   * to this one booking's own row in Verifications, whether it's the only
   * pending item or buried far down a long queue, instead of leaving the
   * organizer to scroll and find it. Same event-ownership guard as bug 1's
   * openNotification() fix (myOrgEventKeys, not just the account-wide
   * organizerMode/hasHosted check) since this is reachable from a bell
   * notification tap too, not just Attendance's own (already-scoped) list.
   */
  const openVerificationDetail = useCallback((bookingId, eventKey, back = 'profile') => {
    if (eventKey && !s.myOrgEventKeys.includes(eventKey)) return;
    if (!(s.organizerMode || s.accountType === 'admin' || s.hasHosted)) return;
    set({ screen: 'verifications', verifications: [], verificationsLoading: true, verificationsFocusBookingId: bookingId, verificationsBack: back });
  }, [set, s.organizerMode, s.accountType, s.hasHosted, s.myOrgEventKeys]);

  /**
   * Signs every given 'pay-proof' path in one batched call and merges the
   * result into state.proofUrls (path -> viewable URL, 10 minutes — long
   * enough for one review pass, short enough not to matter if it leaks into
   * a log somewhere). Verifications.jsx and Disputes.jsx both call this
   * with whatever proof_path values their list just loaded — this is what
   * an organizer/admin actually needs to inspect the receipt before ruling
   * on it, which nothing rendered before this.
   */
  const signProofUrls = useCallback(async (paths) => {
    const wanted = [...new Set((paths || []).filter(Boolean))];
    if (!wanted.length) return;
    const { data, error } = await supabase.storage.from('pay-proof').createSignedUrls(wanted, 600);
    if (error) {
      console.warn('signProofUrls failed:', error);
      return;
    }
    set(prev => ({
      proofUrls: (data || []).reduce((acc, row) => {
        if (row.path && row.signedUrl && !row.error) acc[row.path] = row.signedUrl;
        return acc;
      }, { ...prev.proofUrls }),
    }));
  }, [set]);

  const loadVerifications = useCallback(async () => {
    if (!s.user?.id) return set({ verifications: [], verificationsLoading: false });
    // v_pending_verifications has no organizer filter of its own — it
    // relies on bookings' RLS, which is an OR of bookings_select_guest
    // (auth.uid() = user_id) and bookings_select_host (organizes the
    // event). That means a plain guest's OWN pending_verification booking
    // comes back too (via the guest policy), and got miscounted here as an
    // organizer-facing "awaiting your OK" item — the Home banner then
    // showed a guest the organizer-phrased card for their own booking.
    // Scope explicitly to organizer_id, same established pattern as
    // loadOrganizerHoldingSummary/loadDocuments below; admins alone see
    // every organizer's queue (bookings_select_admin RLS exists for this).
    if (s.accountType !== 'admin' && !s.myOrganizerIds.length) {
      return set({ verifications: [], verificationsLoading: false });
    }
    set({ verificationsLoading: true });
    let query = supabase
      .from('v_pending_verifications')
      .select('*')
      .order('proof_submitted_at', { ascending: true });
    if (s.accountType !== 'admin') query = query.in('organizer_id', s.myOrganizerIds);
    const { data, error } = await query;
    if (error) {
      console.warn('loadVerifications failed:', error);
      return set({ verifications: [], verificationsLoading: false });
    }
    set({ verifications: data || [], verificationsLoading: false });
    await signProofUrls((data || []).map(v => v.proof_path));
  }, [set, s.user?.id, s.accountType, s.myOrganizerIds, signProofUrls]);

  /**
   * The PHASE 1 counterpart of loadVerifications — how many buyers are
   * currently holding a seat on the organizer's own events, and how soon the
   * nearest one lapses. v_pending_verifications only ever covers PHASE 2, so
   * this reads bookings directly; bookings_select_host already scopes an
   * organizer to their own events' rows, same as it does everywhere else.
   */
  const loadOrganizerHoldingSummary = useCallback(async () => {
    if (!s.myOrganizerIds.length) return set({ organizerHoldingSummary: null });
    const { data, error, count } = await supabase
      .from('bookings')
      .select('hold_expires_at, events!inner(organizer_id)', { count: 'exact' })
      .eq('payment_state', 'holding')
      .neq('status', 'cancelled')
      // A hold whose deadline has passed (or was cleared) is not a held seat.
      .gt('hold_expires_at', new Date().toISOString())
      .in('events.organizer_id', s.myOrganizerIds)
      .order('hold_expires_at', { ascending: true })
      .limit(1);
    if (error) {
      console.warn('loadOrganizerHoldingSummary failed:', error);
      return set({ organizerHoldingSummary: null });
    }
    if (!count) return set({ organizerHoldingSummary: null });
    set({ organizerHoldingSummary: { count, soonestHoldExpiresAt: data?.[0]?.hold_expires_at || null } });
  }, [set, s.myOrganizerIds]);

  const approvePayment = useCallback(async (bookingId) => {
    set({ verificationBusy: bookingId });
    try {
      const { data, error } = await supabase.rpc('verify_payment', {
        p_booking: bookingId, p_via: 'organizer', p_actor_kind: 'organizer', p_meta: {},
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('approvePayment failed:', e);
    }
    set({ verificationBusy: '' });
    await loadVerifications();
  }, [set, loadVerifications]);

  /**
   * "Can't find it" — informational, not a verdict. reject_payment() (as of
   * migration 032) never touches payment_state; it only records the reason
   * and messages the guest, so this alone never puts banbe in the picture
   * or moves the booking into the admin dispute queue. See escalateDispute
   * below for the separate, explicit action that actually does that.
   */
  const rejectPayment = useCallback(async (bookingId, reason) => {
    set({ verificationBusy: bookingId });
    try {
      const { data, error } = await supabase.rpc('reject_payment', {
        p_booking: bookingId, p_reason: reason || '',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('rejectPayment failed:', e);
    }
    set({ verificationBusy: '' });
    await loadVerifications();
  }, [set, loadVerifications]);

  /**
   * The one deliberate action that actually brings banbe in — an organizer
   * reaches for this only once they and the guest genuinely can't resolve a
   * payment between themselves. Unlike rejectPayment, this does move the
   * booking to payment_state = 'disputed' and into the admin-only
   * v_disputes queue.
   */
  const escalateDispute = useCallback(async (bookingId, reason) => {
    set({ verificationBusy: bookingId });
    try {
      const { data, error } = await supabase.rpc('escalate_payment_dispute', {
        p_booking: bookingId, p_reason: reason || '',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('escalateDispute failed:', e);
    }
    set({ verificationBusy: '' });
    await loadVerifications();
  }, [set, loadVerifications]);

  // ---- Flow 2: host refund -> guest confirmation ----
  //
  // TASK A (2026-09-30 pass) — this queue used to be an entirely SEPARATE
  // implementation from Attendance's Refund Center: its own client-composed
  // query (refund_claims -> bookings -> events -> profiles, all joined in
  // JS) with no recipient-snapshot check at all, which is the actual cause
  // of "TDK404 / 80.000đ / Mark refund sent" surviving here even after the
  // Attendance screen was fixed — two independent copies of "what's
  // actionable," only one of which got fixed. Fixed: this now calls the
  // exact same get_host_refund_claims() RPC (migration 077/078) Attendance
  // uses, just with no p_event_id (NULL = every claim across every event
  // this host runs), and the exact same refundClaimPresentation() mapper —
  // no more separate eligibility logic to drift out of sync.
  const refundQueueSeq = useRef(0);
  const loadRefundQueue = useCallback(async () => {
    // Investigation fix — this gate used to read ONLY `myOrganizerIds.
    // length`, which is `[]` in THREE different situations: genuinely owns
    // no organizer, organizer discovery hasn't run/finished yet, and
    // organizer discovery FAILED (see loadMyEvents' own fix above). Only
    // the first of those three is a real "nothing to show" — the other two
    // must not silently report the same empty queue with no error, because
    // they can resolve to a non-empty queue the moment discovery actually
    // completes (and, for 'error', never self-correct without a retry).
    if (s.accountType !== 'admin') {
      if (s.myOrganizerIdsStatus === 'idle' || s.myOrganizerIdsStatus === 'loading') {
        // Don't flip refundQueueLoading off here — this is "not ready to
        // check yet," not "checked and empty." The effect that calls this
        // (Verifications.jsx) re-fires once myOrganizerIdsStatus changes,
        // since it's part of this callback's own dependency array below.
        set({ refundQueueGateReason: 'awaiting-organizer-discovery' });
        return;
      }
      if (s.myOrganizerIdsStatus === 'error') {
        set({ refundQueue: [], refundQueueLoading: false, refundQueueError: T('Không thể xác định các sự kiện bạn tổ chức. Vui lòng thử lại.', 'Could not determine which events you organize. Please try again.'), refundQueueGateReason: 'organizer-discovery-failed' });
        return;
      }
      if (!s.myOrganizerIds.length) {
        set({ refundQueue: [], refundQueueLoading: false, refundQueueError: '', refundQueueGateReason: 'no-organizers' });
        return;
      }
    }
    const seq = ++refundQueueSeq.current;
    set({ refundQueueLoading: true, refundQueueError: '', refundQueueErrorDetail: null });
    // Point 1 (new diagnostics) — distinguish TRANSPORT (a thrown exception
    // — network failure, etc.) from the normal `{data, error}` resolution
    // supabase-js's own .rpc() returns for a Postgres-side error (what
    // actually happens here — PostgREST reports the function's own SQL
    // error as a resolved `error`, never a throw) — captured separately so
    // the diagnostics panel can show exactly which stage failed, never
    // collapsing both into the same generic text.
    let data, error, transportError;
    try {
      ({ data, error } = await supabase.rpc('get_host_refund_claims', { p_event_id: null }));
    } catch (e) {
      transportError = e;
    }
    // Only the newest call may ever write refundQueue — a slower, older
    // in-flight call (a poll tick that started before this one) landing
    // late must never overwrite what a more recent call already applied.
    if (seq !== refundQueueSeq.current) { set({ refundQueueGateReason: 'skipped-stale' }); return; }
    if (transportError) {
      if (import.meta.env?.DEV) console.warn('loadRefundQueue transport failed:', transportError);
      set({
        refundQueueLoading: false, refundQueueGateReason: 'transport-error',
        refundQueueError: T('Không thể kết nối để tải danh sách hoàn tiền. Vui lòng thử lại.', 'Could not connect to load the refund queue. Please try again.'),
        refundQueueErrorDetail: { stage: 'transport', message: String(transportError?.message || transportError) },
      });
      return;
    }
    if (error || data?.success === false) {
      if (import.meta.env?.DEV) {
        console.warn('loadRefundQueue failed:', { code: error?.code, message: error?.message, details: error?.details, hint: error?.hint, rpcError: data?.error, userId: s.user?.id });
      }
      set({
        refundQueueLoading: false, refundQueueGateReason: 'rpc-error',
        refundQueueError: T('Không thể tải danh sách hoàn tiền. Vui lòng thử lại.', 'Could not load the refund queue. Please try again.'),
        refundQueueErrorDetail: {
          stage: error ? 'rpc-transport-level-error' : 'rpc-business-result',
          code: error?.code || null, message: error?.message || data?.error || null,
          details: error?.details || null, hint: error?.hint || null,
        },
      });
      return;
    }
    let enriched;
    try {
      const claims = data.claims || [];
      enriched = claims.map(c => ({
        ...c,
        guestName: c.guest_name || T('Khách', 'Guest'),
        eventName: c.event_name || '',
        eventId: c.event_id || null,
        destination: c.recipient_snapshot || null,
        ...refundClaimPresentation(c),
      }));
    } catch (decodeError) {
      if (import.meta.env?.DEV) console.warn('loadRefundQueue decode failed:', decodeError);
      set({
        refundQueueLoading: false, refundQueueGateReason: 'decode-error',
        refundQueueError: T('Không thể hiển thị danh sách hoàn tiền. Vui lòng thử lại.', 'Could not display the refund queue. Please try again.'),
        refundQueueErrorDetail: { stage: 'decode', message: String(decodeError?.message || decodeError) },
      });
      return;
    }
    set({ refundQueue: enriched, refundQueueLoading: false, refundQueueError: '', refundQueueErrorDetail: null, refundQueueGateReason: 'ok' });
  }, [set, T, s.accountType, s.myOrganizerIds.length, s.myOrganizerIdsStatus, s.user?.id]);

  // ---- the yellow "dispute" section pinned at the top of Messages ----
  //
  // Declared up here rather than beside loadDisputeChat further down because
  // markRefundSent() and disputeRefund() (both just below) list
  // loadDisputeChats in their dependency arrays, and those arrays are
  // evaluated during render — a `const` declared after either one would still
  // be in its temporal dead zone there.

  /** Every dispute chat this account is a party to, open ones first, plus the
   *  ones still inside their 7-day post-conclusion window. One RPC rather than
   *  a client-side join: get_my_dispute_chats (migration 129) does its own
   *  guest/organizer/admin scoping, and the same row shape feeds both an open
   *  chat and a "dispute over, disappears in N days" one. */
  const loadDisputeChats = useCallback(async () => {
    set({ disputeChatsLoading: true, disputeChatsError: '' });
    const { data, error } = await supabase.rpc('get_my_dispute_chats');
    if (error) {
      console.warn('loadDisputeChats failed:', error);
      return set({ disputeChats: [], disputeChatsLoading: false, disputeChatsError: T('Không tải được danh sách tranh chấp.', "Couldn't load disputes.") });
    }
    set({ disputeChats: data || [], disputeChatsLoading: false });
  }, [set, T]);

  /** Expand/collapse one entry of the pinned Messages section. */
  const toggleDisputeChat = useCallback((threadId) => {
    set(prev => ({ openDisputeChatThreadId: prev.openDisputeChatThreadId === threadId ? null : threadId }));
  }, [set]);

  /** "Open this chat" from the yellow entry on a payment/refund screen, or
   *  from a dispute_message notification: go to Messages and expand exactly
   *  that thread. Archived view is force-reset first — the dispute section
   *  only exists in the active list, so landing there would show nothing. */
  const openDisputeChatInInbox = useCallback((threadId) => {
    set({ screen: 'inbox', inboxView: 'active', openDisputeChatThreadId: threadId });
    loadDisputeChats();
  }, [set, loadDisputeChats]);

  /** Host's "Đã hoàn tiền" — owed -> host_marked_sent. Shared by
   * Verifications.jsx's own refund queue AND Attendance.jsx's "Hoàn lại lần
   * nữa". TASK C — mark_refund_sent() (migration 078) now returns the
   * complete canonical claim on every path (fresh transition AND an
   * idempotent repeat tap), which is patched directly into both local
   * queues BY ID before the full canonical refetch lands — the card can
   * never bounce back to "Mark refund sent" between the mutation
   * succeeding and that refetch completing, because it's no longer
   * showing stale pre-mutation data in that window. REFUND_DESTINATION_
   * REQUIRED is this RPC's stable business code for "no valid recipient
   * snapshot yet" (renamed from NO_DESTINATION_SELECTED, migration 078). */
  const markRefundSent = useCallback(async (claimId, note = '', proofFile = null) => {
    if (s.refundActionBusy === claimId) return false; // already in flight — no double-submit
    set({ refundActionBusy: claimId, refundBatchError: '' });
    let ok = false;
    try {
      // Optional transfer receipt (migration 128): upload under the claim's
      // own folder, then pass the path to the RPC.
      let proofPath = null;
      if (proofFile) {
        const { blob, ext, contentType } = await normalizeProofFile(proofFile);
        proofPath = `${claimId}/refund-${Date.now()}.${ext}`;
        const { error: upErr } = await supabase.storage.from('refund-proof').upload(proofPath, blob, { upsert: true, contentType });
        if (upErr) throw upErr;
      }
      const { data, error } = await supabase.rpc('mark_refund_sent', { p_claim_id: claimId, p_note: note || '', p_proof_path: proofPath });
      if (error) throw error;
      if (data?.success === false) {
        set({
          refundBatchError: data.error === 'REFUND_DESTINATION_REQUIRED'
            ? T('Chưa thể đánh dấu đã hoàn tiền. Khách cần chọn tài khoản nhận trước.', 'Cannot mark this refund sent yet: the guest needs to choose a destination first.')
            : T('Không thể cập nhật lúc này. Vui lòng thử lại.', 'Could not update right now. Please try again.'),
        });
      } else {
        ok = true;
        const canonical = data.claim;
        if (canonical) {
          // Patch the exact server-confirmed claim into both queues by id
          // right away — never a merge of a stale local array, just this
          // one row's now-authoritative fields.
          const patch = (c) => (c.id === canonical.id ? { ...c, ...canonical, ...refundClaimPresentation(canonical) } : c);
          set(prev => ({
            // Never strip the claim out here — Verifications.jsx's own
            // activeRows/pendingRows split (by status) is what moves it
            // into the non-actionable "Đang chờ xác nhận" section; this
            // patch only ever needs to update the ONE row by id.
            refundQueue: prev.refundQueue.map(patch),
            refundCenterClaims: prev.refundCenterClaims.map(patch),
          }));
        }
      }
    } catch (e) {
      if (import.meta.env?.DEV) {
        console.warn('markRefundSent failed:', { code: e?.code, message: e?.message, details: e?.details, hint: e?.hint, claimId, userId: s.user?.id });
      }
      set({ refundBatchError: T('Không thể cập nhật lúc này. Vui lòng thử lại.', 'Could not update right now. Please try again.') });
    }
    set({ refundActionBusy: '' });
    // Backstop canonical refetch — reconciles anything the direct-by-id
    // patch above can't (e.g. removing it from Attendance's own
    // refundCenterSelected). Both loaders' own seq guards mean a stale
    // response from either can never clobber a fresher one.
    await loadRefundQueue();
    // A refund dispute CONCLUDES the moment the host re-sends the money
    // (claim leaves 'disputed', migration 129), which is what starts the
    // temporary chat's 7-day countdown. Refresh the pinned Messages entry so
    // it flips to its concluded/read-only state now rather than on the next
    // unrelated poll.
    await loadDisputeChats();
    return ok;
  }, [set, T, loadRefundQueue, loadDisputeChats, s.refundActionBusy, s.user?.id]);

  /**
   * The guest's own single refund claim for whatever booking
   * PaymentDetails.jsx is currently showing — fetched by booking id
   * (normal load) or re-fetched by its own claim id after an action below
   * (so a stale concurrent poll response, keyed by the OLD booking id,
   * can't overwrite a state change that already landed — see this
   * function's own guard below).
   */
  const loadPaymentRefundClaim = useCallback(async (id, { byClaimId = false } = {}) => {
    if (!id) return set({ paymentRefundClaim: null });
    const query = supabase.from('refund_claims').select('id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, guest_confirmed_at, note, created_at, refund_due_at, disputed_at, host_response_due_at, transfer_reference, resend_reference, resend_bank_name, resend_transferred_at, resend_note, selected_destination_id, recipient_snapshot, proof_path');
    const { data, error } = byClaimId
      ? await query.eq('id', id).maybeSingle()
      : await query.or(`booking_id.eq.${id},reservation_id.eq.${id}`).order('created_at', { ascending: false }).limit(1).maybeSingle();
    if (error) {
      console.warn('loadPaymentRefundClaim failed:', error);
      return;
    }
    // Stale-poll guard (this ticket's own explicit lesson from Flow 1): a
    // response for a booking the guest has since navigated away from must
    // never clobber whatever's current now.
    set(prev => (prev.paymentBookingId === (data?.booking_id || data?.reservation_id || prev.paymentBookingId)
      ? { paymentRefundClaim: data || null } : {}));
  }, [set]);

  /** Guest's "Đã nhận tiền" — host_marked_sent -> guest_confirmed. */
  const confirmRefundReceived = useCallback(async (claimId) => {
    set({ refundActionBusy: claimId });
    // Optimistic local patch first (this ticket's own explicit ask), then
    // reconciled by the real RPC result — never the other way around, so a
    // failed RPC doesn't leave the UI lying about what actually happened.
    set(prev => (prev.paymentRefundClaim?.id === claimId
      ? { paymentRefundClaim: { ...prev.paymentRefundClaim, status: 'guest_confirmed', guest_confirmed_at: new Date().toISOString() } }
      : {}));
    let result;
    try {
      const { data, error } = await supabase.rpc('confirm_refund_received', { p_claim_id: claimId });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      result = data;
    } catch (e) {
      console.warn('confirmRefundReceived failed:', e);
    }
    set({ refundActionBusy: '' });
    await loadPaymentRefundClaim(claimId, { byClaimId: true });
    return result;
  }, [set, loadPaymentRefundClaim]);

  /** Guest's "Chưa nhận được" — owed/host_marked_sent -> disputed. */
  const disputeRefund = useCallback(async (claimId, reason = '') => {
    set({ refundActionBusy: claimId });
    set(prev => (prev.paymentRefundClaim?.id === claimId
      ? { paymentRefundClaim: { ...prev.paymentRefundClaim, status: 'disputed' } }
      : {}));
    let result;
    try {
      const { data, error } = await supabase.rpc('dispute_refund', { p_claim_id: claimId, p_reason: reason || '' });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      result = data;
    } catch (e) {
      console.warn('disputeRefund failed:', e);
    }
    set({ refundActionBusy: '' });
    await loadPaymentRefundClaim(claimId, { byClaimId: true });
    // dispute_refund() opened the temporary chat server-side (migration 129),
    // so the goer's own pinned Messages entry has to appear immediately —
    // this is the moment they land on the chat they're about to be asked
    // about, and a stale empty list would read as "nothing happened".
    await loadDisputeChats();
    return result;
  }, [set, loadPaymentRefundClaim, loadDisputeChats]);

  // ---- Refund MVP: goer's own refund destinations (many, migration 074) ----

  /** All of the signed-in goer's own saved refund_destinations rows. */
  const loadRefundDestinations = useCallback(async () => {
    if (!s.user?.id) return set({ refundDestinations: [] });
    const { data, error } = await supabase
      .from('refund_destinations')
      .select('id, user_id, label, bank_name, account_number, account_holder_name, transfer_note, is_default, position, confirmed_at, updated_at')
      .eq('user_id', s.user.id)
      .order('position', { ascending: true });
    if (error) {
      console.warn('loadRefundDestinations failed:', error);
      return;
    }
    // TASK B point 5 — never let a plain refetch (a screen mount effect,
    // pull-to-refresh, etc.) land mid-drag and overwrite the optimistic/
    // authoritative order reorderRefundDestinations() is actively managing.
    set(prev => (prev.refundDestinationsReordering ? {} : { refundDestinations: data || [] }));
  }, [set, s.user?.id]);

  /** Goer drags an account to a new position (TASK B) — transaction-safe,
   * ownership-checked server-side (reorder_refund_destinations(),
   * migration 075), which also makes position 0 the new default
   * automatically. Never a client-only reorder: always reconciled against
   * the real server order right after. */
  /**
   * TASK B — was: optimistic reorder, then an UNCONDITIONAL separate
   * loadRefundDestinations() fetch to find out what actually got
   * persisted. That second network round trip is exactly the shape of bug
   * that produces a "snap back"/white reload: nothing stopped a stray
   * mount-effect refetch (or the routine one this same function's own
   * reload triggered) from landing with pre-reorder positions and
   * clobbering the just-applied optimistic order, and refetching via
   * `loadRefundDestinations()` has no "keep current rows, don't blank the
   * list" guard of its own.
   *
   * Fixed: the RPC (migration 076) now returns the canonical saved rows in
   * its own response — this never fetches again on success, so there is no
   * second request left to race. `refundDestinationsReordering` blocks a
   * concurrent loadRefundDestinations() call (e.g. a stray mount effect)
   * from overwriting the optimistic/authoritative order while this is in
   * flight. On failure, the array is restored to exactly what it was
   * before the drag (never silently left half-reordered), and a friendly
   * error is shown — never a second, later snap-back.
   */
  const reorderRefundDestinations = useCallback(async (orderedIds) => {
    const previous = s.refundDestinations;
    const byId = Object.fromEntries(previous.map(d => [d.id, d]));
    const optimistic = orderedIds.map((id, i) => byId[id] && { ...byId[id], position: i, is_default: i === 0 }).filter(Boolean);
    if (optimistic.length !== previous.length) return; // stale id set — never apply a partial/mismatched reorder
    set({ refundDestinations: optimistic, refundDestinationsReordering: true, refundDestinationError: '' });
    try {
      const { data, error } = await supabase.rpc('reorder_refund_destinations', { p_ordered_ids: orderedIds });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      // The RPC's own response is now authoritative — no second fetch.
      set({ refundDestinations: data.destinations || optimistic, refundDestinationsReordering: false });
    } catch (e) {
      // Full diagnostic (code/message/details/hint + what was sent) only in
      // dev — never shown raw to the user, per this ticket's B3.
      if (import.meta.env?.DEV) {
        console.warn('reorderRefundDestinations failed:', { code: e?.code, message: e?.message, details: e?.details, hint: e?.hint, orderedIds, userId: s.user?.id });
      }
      set({
        refundDestinations: previous,
        refundDestinationsReordering: false,
        refundDestinationError: T('Chưa thể lưu thứ tự. Vui lòng thử lại.', "Couldn't save the order. Please try again."),
      });
    }
  }, [set, T, s.refundDestinations, s.user?.id]);

  /**
   * Goer adds (`id` omitted) or edits (`id` given) one of their own refund
   * bank accounts. `confirmed` must be true (an explicit checkbox/step in
   * the UI) or the server refuses to save (save_refund_destination()'s own
   * CONFIRMATION_REQUIRED gate).
   */
  const saveRefundDestination = useCallback(async ({ id = null, label = '', bankName, accountNumber, accountHolderName, transferNote = '', setDefault = false, confirmed = false }) => {
    set({ refundDestinationBusy: true, refundDestinationError: '' });
    let newId = null;
    try {
      const { data, error } = await supabase.rpc('save_refund_destination', {
        p_id: id, p_label: label || null, p_bank_name: bankName, p_account_number: accountNumber, p_account_holder_name: accountHolderName,
        p_transfer_note: transferNote || null, p_set_default: !!setDefault, p_confirmed: !!confirmed,
      });
      if (error) throw error;
      if (data?.success === false) {
        set({
          refundDestinationBusy: false,
          refundDestinationError: data.error === 'CONFIRMATION_REQUIRED'
            ? T('Vui lòng xác nhận thông tin trước khi lưu.', 'Please confirm the details before saving.')
            : T('Hiện chưa thể thực hiện. Vui lòng thử lại sau.', "This isn't available right now. Please try again later."),
        });
        return null;
      }
      newId = data.id;
    } catch (e) {
      console.warn('saveRefundDestination failed:', e);
      set({ refundDestinationBusy: false, refundDestinationError: T('Hiện chưa thể thực hiện. Vui lòng thử lại sau.', "This isn't available right now. Please try again later.") });
      return null;
    }
    set({ refundDestinationBusy: false });
    await loadRefundDestinations();
    return newId;
  }, [set, T, loadRefundDestinations]);

  const deleteRefundDestination = useCallback(async (id) => {
    set({ refundDestinationBusy: true, refundDestinationError: '' });
    let ok = false;
    try {
      const { data, error } = await supabase.rpc('delete_refund_destination', { p_id: id });
      if (error) throw error;
      ok = data?.success !== false;
    } catch (e) {
      console.warn('deleteRefundDestination failed:', e);
      set({ refundDestinationError: T('Hiện chưa thể thực hiện. Vui lòng thử lại sau.', "This isn't available right now. Please try again later.") });
    }
    set({ refundDestinationBusy: false });
    await loadRefundDestinations();
    return ok;
  }, [set, T, loadRefundDestinations]);

  const setDefaultRefundDestination = useCallback(async (id) => {
    try {
      const { data, error } = await supabase.rpc('set_default_refund_destination', { p_id: id });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('setDefaultRefundDestination failed:', e);
    }
    await loadRefundDestinations();
  }, [loadRefundDestinations]);

  /** Goer's explicit confirmation of which saved account a SPECIFIC claim
   * should be refunded into — snapshots the recipient onto the claim
   * itself server-side (select_refund_destination(), migration 074), so a
   * later edit/delete of the account never changes what's already
   * selected for this claim. */
  const selectRefundDestinationForClaim = useCallback(async (claimId, destinationId) => {
    set({ refundDestinationBusy: true, refundDestinationError: '' });
    let ok = false;
    try {
      const { data, error } = await supabase.rpc('select_refund_destination', { p_claim_id: claimId, p_destination_id: destinationId });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      ok = true;
    } catch (e) {
      console.warn('selectRefundDestinationForClaim failed:', e);
      set({ refundDestinationError: T('Hiện chưa thể thực hiện. Vui lòng thử lại sau.', "This isn't available right now. Please try again later.") });
    }
    set({ refundDestinationBusy: false });
    if (ok) await loadPaymentRefundClaim(claimId, { byClaimId: true });
    return ok;
  }, [set, T, loadPaymentRefundClaim]);

  /** All of the goer's own active refund claims (owed/host_marked_sent/
   * disputed) — the persistent "Refunds" list (product rule A), independent
   * of any one booking/notification. */
  const loadMyRefunds = useCallback(async () => {
    if (!s.user?.id) return set({ myRefunds: [], myRefundsLoading: false });
    set({ myRefundsLoading: true });
    const { data: bookings } = await supabase.from('bookings').select('id, event_id').eq('user_id', s.user.id);
    const bookingIds = (bookings || []).map(b => b.id);
    if (!bookingIds.length) return set({ myRefunds: [], myRefundsLoading: false });
    const { data: claims, error } = await supabase
      .from('refund_claims')
      .select('id, booking_id, reservation_id, amount_vnd, status, host_marked_at, disputed_at, host_response_due_at, refund_due_at, created_at')
      .or(bookingIds.map(id => `booking_id.eq.${id}`).join(','))
      .in('status', ['owed', 'host_marked_sent', 'disputed'])
      .order('created_at', { ascending: false });
    if (error) {
      console.warn('loadMyRefunds failed:', error);
      return set({ myRefunds: [], myRefundsLoading: false });
    }
    const bookingById = Object.fromEntries((bookings || []).map(b => [b.id, b]));
    const eventIds = [...new Set((claims || []).map(c => bookingById[c.booking_id || c.reservation_id]?.event_id).filter(Boolean))];
    let eventById = {};
    if (eventIds.length) {
      const { data: events } = await supabase.from('events').select('id, name').in('id', eventIds);
      eventById = Object.fromEntries((events || []).map(e => [e.id, e]));
    }
    const enriched = (claims || []).map(c => {
      const b = bookingById[c.booking_id || c.reservation_id];
      return { ...c, bookingId: b?.id, eventKey: b?.event_id, eventName: eventById[b?.event_id]?.name || '' };
    });
    set({ myRefunds: enriched, myRefundsLoading: false });
  }, [set, s.user?.id]);

  // TASK A point 8 — "equivalent browser back/history behavior": pushes a
  // real history entry when opening either screen, so the browser's own
  // back button (and, on mobile Safari, its own edge-swipe-back gesture)
  // returns here too, not just this app's in-view back link. Consumed
  // (via history.back()) whenever THIS app leaves the screen on its own —
  // see consumeRefundHistoryEntry() below — so a later stray forward-swipe
  // never resurrects a route we already left.
  const consumeRefundHistoryEntry = (kind) => {
    try {
      if (window.history.state?.bbScreen === kind) window.history.back();
    } catch { /* unsupported */ }
  };

  const openRefundAccounts = useCallback((back = 'profile', { returnToClaimId = null, returnToBookingId = null } = {}) => {
    set({ screen: 'refundAccounts', refundAccountsBack: back, refundAccountsReturnToClaimId: returnToClaimId, refundAccountsReturnToBookingId: returnToBookingId });
    try { localStorage.setItem('banbe.lastScreen', 'refundAccounts'); } catch { /* private browsing */ }
    try { window.history.pushState({ bbScreen: 'refundAccounts' }, ''); } catch { /* unsupported */ }
  }, [set]);
  const backFromRefundAccounts = useCallback(() => {
    set(prev => ({ screen: prev.refundAccountsBack || 'profile', refundAccountsReturnToClaimId: null, refundAccountsReturnToBookingId: null }));
    try { localStorage.removeItem('banbe.lastScreen'); } catch { /* private browsing */ }
    consumeRefundHistoryEntry('refundAccounts');
  }, [set]);

  const openMyRefunds = useCallback((back = 'profile') => {
    set({ screen: 'myRefunds', myRefundsBack: back });
    try { localStorage.setItem('banbe.lastScreen', 'myRefunds'); } catch { /* private browsing */ }
    try { window.history.pushState({ bbScreen: 'myRefunds' }, ''); } catch { /* unsupported */ }
    loadMyRefunds();
  }, [set, loadMyRefunds]);
  const backFromMyRefunds = useCallback(() => {
    set(prev => ({ screen: prev.myRefundsBack || 'profile' }));
    try { localStorage.removeItem('banbe.lastScreen'); } catch { /* private browsing */ }
    consumeRefundHistoryEntry('myRefunds');
  }, [set]);

  // The actual browser-back/edge-swipe-back handler — performs the exact
  // same transition backFromRefundAccounts()/backFromMyRefunds() do. Reads
  // `prev.screen` at fire time: if this app already left the screen on its
  // own (the two functions above), that screen no longer matches and this
  // is correctly a no-op rather than a second, conflicting transition.
  useEffect(() => {
    const onPopState = () => {
      set(prev => {
        // TASK A7 (2026-10-03 fix pass) — Pulse is a modal sheet, not a
        // screen; checked first since it can be open over ANY screen
        // (including refundAccounts/myRefunds themselves) and must close
        // without also triggering either of those screens' own back
        // transition in the same pop.
        if (prev.pulseOpen) {
          return { pulseOpen: false, pulseOrganizerSheet: null };
        }
        if (prev.screen === 'refundAccounts') {
          try { localStorage.removeItem('banbe.lastScreen'); } catch { /* private browsing */ }
          return { screen: prev.refundAccountsBack || 'profile', refundAccountsReturnToClaimId: null, refundAccountsReturnToBookingId: null };
        }
        if (prev.screen === 'myRefunds') {
          try { localStorage.removeItem('banbe.lastScreen'); } catch { /* private browsing */ }
          return { screen: prev.myRefundsBack || 'profile' };
        }
        return {};
      });
    };
    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, [set]);

  // ---- Refund MVP: host's per-event Refund Center (Attendance's own new
  // "Hoàn tiền" section) ----

  /** Owed/disputed (+ resolved, for the progress summary) refund claims for
   * one event. Recipient info comes straight from each claim's OWN
   * `recipient_snapshot`/`selected_destination_id` (migration 074) — never
   * a live join against refund_destinations — so a guest editing/adding
   * accounts elsewhere can never race this list into a wrong/missing
   * recipient or a transient "ineligible" flicker.
   *
   * BUG FIX (root cause of the "0đ / disappearing / reappearing" report):
   * this function used to unconditionally reset refundCenterSelected to []
   * on every call — including the routine 6s poll. A host mid-review with
   * rows selected would have that selection silently wiped by the next
   * background poll tick, collapsing the review screen's own "N khách ▪︎
   * tổng X₫" to 0 selected / 0₫ and disabling the confirm CTA — not any
   * actual mutation of `amount_vnd` on a claim, which is never written by
   * anything client-side and is never touched by any RPC except as an
   * unmodified read-back. Fixed by PRESERVING selection across reloads,
   * pruned only to ids that still exist and are still eligible. */
  /**
   * TASK A (2026-09-29 pass) — was: two client-composed queries (this
   * event's bookings, then refund_claims via a client-built `.or(booking_id
   * .eq...)` string) plus a JS-side "drop rows whose booking isn't in
   * bookingById" filter. That JS filter is a UI-level bandaid, not a real
   * fix — it can only discard what already got fetched, and the actual
   * ownership/identity chain (claim -> booking -> event -> organizer) lived
   * in three unsynchronized places (RLS, the client bookingIds prefetch,
   * the client filter). A ghost row could still slip through any gap
   * between those three.
   *
   * Fixed: get_host_refund_claims() (migration 077) does the entire
   * canonical join server-side with INNER JOINs — a row can only ever come
   * back if claim -> booking -> THIS event -> an organizer the caller owns
   * all resolve in one query. There is no client-side "is this valid?"
   * check left to get out of sync, because an invalid row structurally
   * cannot be returned.
   */
  const refundCenterSeq = useRef(0);
  const loadRefundCenter = useCallback(async (eventKey) => {
    if (!eventKey) return set({ refundCenterClaims: [], refundCenterLoading: false, refundCenterError: '' });
    const seq = ++refundCenterSeq.current;
    set({ refundCenterLoading: true });
    const { data, error } = await supabase.rpc('get_host_refund_claims', { p_event_id: eventKey });
    // Only the newest call may write refundCenterClaims — a slower older
    // in-flight poll tick landing late must never overwrite a fresher one.
    if (seq !== refundCenterSeq.current) return;
    if (error || data?.success === false) {
      // A transient fetch error must never clobber an already-populated
      // list — leave refundCenterClaims exactly as it was. Full diagnostic
      // logged only in dev — never surfaced raw to the user. `refundCenterError`
      // only shows when there's NOTHING already on screen to fall back to
      // (set below, read in Attendance.jsx) — "do not show failed loading
      // as empty" applies to the FIRST load, not every background poll hiccup.
      if (import.meta.env?.DEV) {
        console.warn('loadRefundCenter failed:', { code: error?.code, message: error?.message, details: error?.details, hint: error?.hint, rpcError: data?.error, eventKey, userId: s.user?.id });
      }
      set(prev => ({
        refundCenterLoading: false,
        refundCenterError: prev.refundCenterClaims.length ? '' : T('Không thể tải Refund Center. Vui lòng thử lại.', 'Could not load the Refund Center. Please try again.'),
      }));
      return;
    }
    const claims = data.claims || [];
    // TASK B — one shared presentation mapper (refundClaimPresentation),
    // also used by loadRefundQueue() below, so "what's actionable" can
    // never drift between the two screens again.
    const enriched = claims.map(c => ({
      ...c,
      guestName: c.guest_name || T('Khách', 'Guest'),
      destination: c.recipient_snapshot || null,
      ...refundClaimPresentation(c),
    }));
    const eligibleIds = new Set(enriched.filter(c => c.eligible).map(c => c.id));
    set(prev => ({
      refundCenterClaims: enriched,
      refundCenterLoading: false,
      refundCenterError: '',
      refundCenterSelected: prev.refundCenterSelected.filter(id => eligibleIds.has(id)),
    }));
  }, [set, T, s.user?.id]);

  const toggleRefundCenterSelect = useCallback((claimId) => {
    set(prev => ({
      refundCenterSelected: prev.refundCenterSelected.includes(claimId)
        ? prev.refundCenterSelected.filter(id => id !== claimId)
        : [...prev.refundCenterSelected, claimId],
    }));
  }, [set]);

  const selectAllEligibleRefundCenter = useCallback(() => {
    set(prev => ({ refundCenterSelected: prev.refundCenterClaims.filter(c => c.eligible).map(c => c.id) }));
  }, [set]);

  const clearRefundCenterSelection = useCallback(() => set({ refundCenterSelected: [] }), [set]);

  /** Host's "Xác nhận đã chuyển tiền" — one real, atomic batch, not just a
   * client-side loop of individual mark_refund_sent calls. Guarded by
   * `refundBatchInFlight` (not just `refundBatchBusy`) so a double-tap on
   * the CTA can never fire the RPC twice. */
  const confirmRefundBatch = useCallback(async (eventKey, note = '') => {
    if (s.refundBatchInFlight) return null;
    const claimIds = s.refundCenterSelected;
    if (!claimIds.length) return null;
    set({ refundBatchBusy: true, refundBatchInFlight: true, refundBatchError: '', refundBatchResult: null });
    let result = null;
    try {
      const { data, error } = await supabase.rpc('create_and_confirm_refund_batch', { p_claim_ids: claimIds, p_note: note || '' });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      result = data;
    } catch (e) {
      console.warn('confirmRefundBatch failed:', e);
      set({ refundBatchBusy: false, refundBatchInFlight: false, refundBatchError: T('Không thể cập nhật lúc này. Vui lòng thử lại.', 'Could not update right now. Please try again.') });
      return null;
    }
    // Server result is the sole source of truth from here — no local
    // amount/status patch, only a full canonical reload.
    set({ refundBatchBusy: false, refundBatchInFlight: false, refundBatchResult: result });
    await loadRefundCenter(eventKey);
    return result;
  }, [set, T, s.refundCenterSelected, s.refundBatchInFlight, loadRefundCenter]);

  /** Host's "Gửi lại thông tin chuyển khoản" on a disputed claim — resends
   * transfer proof without changing status. `refundResendInFlight` (a Set,
   * keyed by claim id) disables only that row's own CTA, not the whole
   * screen, and blocks a double-submit on the same claim. */
  const resendRefundTransferInfo = useCallback(async (eventKey, claimId, { reference = '', bankName = '', transferredAt = null, note = '' } = {}) => {
    if (s.refundResendInFlight.has(claimId)) return false;
    set(prev => ({ refundResendBusy: claimId, refundResendInFlight: new Set(prev.refundResendInFlight).add(claimId) }));
    let ok = false;
    try {
      const { data, error } = await supabase.rpc('resend_refund_transfer_info', {
        p_claim_id: claimId, p_reference: reference || '', p_bank_name: bankName || '',
        p_transferred_at: transferredAt || null, p_note: note || '',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      ok = true;
    } catch (e) {
      console.warn('resendRefundTransferInfo failed:', e);
    }
    set(prev => {
      const next = new Set(prev.refundResendInFlight);
      next.delete(claimId);
      return { refundResendBusy: '', refundResendInFlight: next };
    });
    await loadRefundCenter(eventKey);
    return ok;
  }, [set, s.refundResendInFlight, loadRefundCenter]);

  // ---- admin dispute desk ----
  const openDisputes = useCallback(() => {
    set({ screen: 'disputes', disputes: [], disputesLoading: true });
  }, [set]);

  const loadDisputes = useCallback(async () => {
    set({ disputesLoading: true });
    const { data, error } = await supabase
      .from('v_disputes').select('*').order('disputed_at', { ascending: false });
    if (error) {
      console.warn('loadDisputes failed:', error);
      return set({ disputes: [], disputesLoading: false });
    }
    set({ disputes: data || [], disputesLoading: false });
    await signProofUrls((data || []).map(d => d.proof_path));
  }, [set, signProofUrls]);

  /**
   * resolve_dispute (the RPC) only flips database state — payment
   * confirmed/expired, the dispute thread marked resolved and scheduled for
   * purge, one note left in the guest's ordinary chat. The confirmation
   * email itself (with the transcript PDF and the receipt image attached)
   * is a separate step, api/dispute-resolved-email.js — best-effort here:
   * if it fails, the database resolution already stands and an admin can
   * see disputeEmailError and retry rather than the whole action rolling
   * back or silently never emailing anyone.
   */
  const resolveDispute = useCallback(async (bookingId, uphold, note, reasonCategory) => {
    set({ disputeBusy: bookingId, disputeEmailError: '' });
    try {
      const { data, error } = await supabase.rpc('resolve_dispute', {
        p_booking: bookingId, p_uphold: !!uphold, p_resolution: note || '',
        // Anonymized quality-review input (see dispute_resolution_stats,
        // migration 047) — never shown to guest/organizer, only feeds the
        // admin-only aggregate insights view. Falls back to 'other' rather
        // than block a resolution the admin actually wants to make now.
        p_reason_category: reasonCategory || 'other',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('resolveDispute failed:', e);
    }
    // The DB resolution above is the part the admin is actually waiting on
    // — it must update the screen (disputeBusy cleared, the row moved to
    // "Resolved") regardless of what happens next. The confirmation email
    // (api/dispute-resolved-email.js: puppeteer-core + @sparticuz/chromium,
    // never load-tested end-to-end — see 05-notify-retention.md) used to be
    // awaited INSIDE this same try block, ahead of these two lines: a slow
    // cold start or a hung request there silently blocked every visible
    // sign that the resolution had already succeeded, reading as "the
    // button does nothing" even though the dispute really was resolved.
    set({ disputeBusy: '' });
    await loadDisputes();

    sendDisputeResolvedEmail(bookingId);
  }, [set, loadDisputes]);

  /** Fire-and-forget half of resolveDispute — see the comment there. */
  const sendDisputeResolvedEmail = useCallback(async (bookingId) => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) return;
      const res = await fetch('/api/dispute-resolved-email', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ bookingId }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        set({ disputeEmailError: body.error || `HTTP_${res.status}` });
      }
    } catch (e) {
      console.warn('sendDisputeResolvedEmail failed:', e);
      set({ disputeEmailError: e.message || 'NETWORK_ERROR' });
    }
  }, [set]);

  /** The T1/T2/T3 trail for one booking — what a dispute is actually argued on. */
  const loadAuditTrail = useCallback(async (bookingId) => {
    set({ auditBookingId: bookingId, auditTrail: [] });
    const { data } = await supabase
      .from('payment_audit_log').select('*')
      .eq('booking_id', bookingId).order('at', { ascending: true });
    set({ auditTrail: data || [] });
  }, [set]);

  // ---- admin event review queue (event submission -> review -> publish) ----
  // Separate desk from the payment/dispute one above — an admin reviewing a
  // NEW EVENT SUBMISSION is not the same job as one verifying a payment or
  // ruling on a dispute, even though both are gated the same way
  // (is_platform_admin(), migration 026/085).
  const openAdminEvents = useCallback(() => {
    set({ screen: 'adminEvents', adminEvents: [], adminEventsLoading: true, adminEventError: '' });
  }, [set]);

  /**
   * `events_select_admin` (migration 085) is what actually makes this
   * return every organizer's pending rows, not just this account's own —
   * a direct `.from('events')` read, same pattern v_pending_verifications/
   * v_disputes establish for the other two admin queues, just without a
   * dedicated view (no evidence/PII join complex enough to warrant one).
   */
  // TASK 5 (Account badges pass) — a lightweight COUNT-only sibling to
  // loadPendingEvents() above, for the "adminReview" group-card badge
  // (Account.jsx). Deliberately does NOT reuse loadPendingEvents() itself:
  // that fetches full event rows + first-photo lookups for the review
  // list UI, which is too heavy to run just to show a number on every
  // Account mount. Same `events_select_admin` RLS (migration 085) backs
  // both, so this stays authorized/consistent with the real queue.
  const loadPendingEventsCount = useCallback(async () => {
    const { count, error } = await supabase
      .from('events')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'review');
    // Honest-failure handling — a query failure must not leave a stale
    // positive count on screen implying there's still something to review
    // when the real state is simply unknown.
    if (error) { console.warn('loadPendingEventsCount failed:', error); set({ pendingEventsCount: 0 }); return; }
    set({ pendingEventsCount: count || 0 });
  }, [set]);

  const loadPendingEvents = useCallback(async () => {
    set({ adminEventsLoading: true, adminEventError: '' });
    // TASK 3 (event creation validation pass) — organizer_type/verified/
    // tax_code added for the admin review detail section. Per migration
    // 109's own comment, `verified` has no real write path anywhere in
    // this schema and `organizer_type` is purely self-declared — this
    // query only reads them, it never implies either is admin-confirmed.
    // Never joins bank_name/bank_account_no/momo_phone or any other
    // payout/banking field — those stay out of every review/public query.
    const { data, error } = await withR2Columns(withR2 => supabase
      .from('events')
      .select(`${realEventColumns(withR2)}, organizers(name, organizer_type, verified, tax_code)`)
      .eq('status', 'review')
      .order('submitted_at', { ascending: true }));
    if (error) {
      console.warn('loadPendingEvents failed:', error);
      set({ adminEvents: [], adminEventsLoading: false, adminEventError: error.message });
      return;
    }
    const rows = data || [];
    const photoUrlByEvent = await firstPhotoUrlByEvent(rows.map(r => r.id));
    const shaped = rows.map(r => shapeRealEvent(r, {
      photoUrl: photoUrlByEvent[r.id],
      organizerName: r.organizers?.name,
      organizerType: r.organizers?.organizer_type,
      organizerVerified: r.organizers?.verified,
      organizerHasTaxCode: !!(r.organizers?.tax_code || '').trim(),
    }));
    set({ adminEvents: shaped, adminEventsLoading: false });
  }, [set]);

  /**
   * admin_review_event (migration 085) does the actual admin-gated,
   * race-safe (row-locked, status-checked) transition — this just calls it
   * and refreshes the queue. A rejection with no reason is blocked
   * server-side (REASON_REQUIRED) as well as here, so a direct RPC call
   * bypassing this UI can't skip it either.
   */
  const reviewEvent = useCallback(async (eventId, approve, reason) => {
    if (!approve && !(reason || '').trim()) {
      set({ adminEventError: 'REASON_REQUIRED' });
      return false;
    }
    set({ adminEventBusy: eventId, adminEventError: '' });
    let ok = false;
    try {
      const { data, error } = await supabase.rpc('admin_review_event', {
        p_event_id: eventId, p_approve: !!approve, p_reason: reason || '',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      ok = true;
    } catch (e) {
      console.warn('reviewEvent failed:', e);
      set({ adminEventError: e.message || 'REVIEW_FAILED' });
    }
    set({ adminEventBusy: '' });
    // Public discovery (Home's weekend section, EventList, MapExplore) only
    // ever queries `status = 'live'` rows — nothing else needs to be
    // "refreshed" client-side for an approval to become visible there; the
    // very next real fetch already reflects the server-confirmed state.
    // This just refreshes the admin's OWN queue view.
    // TASK 5 (Account badges pass) — the adminReview group-card badge
    // reads pendingEventsCount, not adminEvents.length, so it needs its
    // own refresh here too, same as the full queue does.
    if (ok) { await loadPendingEvents(); await loadPendingEventsCount(); }
    return ok;
  }, [set, loadPendingEvents, loadPendingEventsCount]);

  // ---- the temporary dispute chat (guest <-> organizer, while escalated) ----
  /**
   * escalate_payment_dispute() opens this thread server-side; this just
   * reads it back. RLS on dispute_threads/dispute_messages already limits
   * this to the guest, the event's organizer, or an admin — the same three
   * parties who could ever see a dispute at all.
   */
  const loadDisputeChat = useCallback(async (bookingId, _retried = false) => {
    set({ disputeChatBookingId: bookingId, disputeChatRefundClaimId: null, disputeChatKind: 'payment', disputeChatMessages: [], disputeChatLoading: true, disputeChatError: '', disputeChatThread: null });
    const { data: thread, error: threadError } = await supabase
      .from('dispute_threads').select('id, resolved_at, purge_after').eq('booking_id', bookingId).maybeSingle();
    if (threadError || !thread) {
      console.warn('loadDisputeChat failed:', threadError);
      // A denied-by-RLS row (a stale organizer_id/guest_id on this
      // dispute_threads row no longer matches this account — the ART10025
      // symptom) and a genuinely missing thread both read as "no data"
      // here. resolve_dispute()'s own repair only fires once a dispute is
      // closed, and reject_payment()/escalate_payment_dispute() refuse to
      // run again once payment_state = 'disputed' — so this is the one
      // place left that can reach a currently-open, mislinked thread.
      // resync_dispute_thread() has no state restriction and is safe to
      // call speculatively; if it fixes nothing, the retry just fails the
      // same way and disputeChatError still gets set below.
      if (!_retried) {
        const { data: resync } = await supabase.rpc('resync_dispute_thread', { p_booking: bookingId });
        if (resync?.success) return loadDisputeChat(bookingId, true);
      }
      return set({
        disputeChatLoading: false,
        disputeChatError: threadError ? T('Không tải được đoạn chat. Thử lại nhé.', "Couldn't load this chat. Please try again.") : '',
      });
    }
    const { data: messages, error } = await supabase
      .from('dispute_messages').select('*')
      .eq('dispute_thread_id', thread.id).order('created_at', { ascending: true });
    if (error) {
      console.warn('loadDisputeChat messages failed:', error);
      return set({
        disputeChatLoading: false,
        disputeChatError: T('Không tải được tin nhắn. Thử lại nhé.', "Couldn't load messages. Please try again."),
      });
    }
    set({
      disputeChatMessages: messages || [], disputeChatLoading: false,
      disputeChatThread: { resolvedAt: thread.resolved_at, purgeAfter: thread.purge_after },
    });
  }, [set, T]);

  const disputeChatDraftType = useCallback((e) => set({ disputeChatDraft: e.target.value }), [set]);

  const sendDisputeMessage = useCallback(async (bookingId) => {
    const body = s.disputeChatDraft.trim();
    if (!body) return;
    set({ disputeChatDraft: '', disputeChatError: '' });
    const { data, error } = await supabase.rpc('send_dispute_message', { p_booking: bookingId, p_body: body });
    if (error || data?.success === false) {
      console.warn('sendDisputeMessage failed:', error || data?.error);
      // Previously silent — a NOT_AUTHORIZED/NOT_DISPUTED from a
      // stale/mislinked dispute_threads row looked identical to a
      // successful send that just hadn't shown up yet.
      set({
        disputeChatDraft: body,
        disputeChatError: T('Chưa gửi được. Thử lại nhé.', "Couldn't send. Please try again."),
      });
      return;
    }
    await loadDisputeChat(bookingId);
  }, [set, s.disputeChatDraft, loadDisputeChat, T]);

  // ---- the refund-dispute chat (goer <-> organizer, while a refund dispute
  // is open) ----
  //
  // Same two tables as loadDisputeChat above, keyed by refund_claims.id
  // instead of bookings.id (migration 129) — dispute_refund() opens the
  // thread server-side, this just reads it back. No resync fallback like the
  // payment path's: there is no equivalent of the stale organizer_id repair
  // resync_dispute_thread() exists for, and dispute_refund() is the only
  // writer, so a missing row here means "not disputed".
  const loadRefundDisputeChat = useCallback(async (claimId) => {
    set({
      disputeChatBookingId: null, disputeChatRefundClaimId: claimId, disputeChatKind: 'refund',
      disputeChatMessages: [], disputeChatLoading: true, disputeChatError: '', disputeChatThread: null,
    });
    const { data: thread, error: threadError } = await supabase
      .from('dispute_threads').select('id, resolved_at, purge_after').eq('refund_claim_id', claimId).maybeSingle();
    if (threadError || !thread) {
      console.warn('loadRefundDisputeChat failed:', threadError);
      return set({
        disputeChatLoading: false,
        disputeChatError: threadError ? T('Không tải được đoạn chat. Thử lại nhé.', "Couldn't load this chat. Please try again.") : '',
      });
    }
    const { data: messages, error } = await supabase
      .from('dispute_messages').select('*')
      .eq('dispute_thread_id', thread.id).order('created_at', { ascending: true });
    if (error) {
      console.warn('loadRefundDisputeChat messages failed:', error);
      return set({
        disputeChatLoading: false,
        disputeChatError: T('Không tải được tin nhắn. Thử lại nhé.', "Couldn't load messages. Please try again."),
      });
    }
    set({
      disputeChatMessages: messages || [], disputeChatLoading: false,
      disputeChatThread: { resolvedAt: thread.resolved_at, purgeAfter: thread.purge_after },
    });
  }, [set, T]);

  const sendRefundDisputeMessage = useCallback(async (claimId) => {
    const body = s.disputeChatDraft.trim();
    if (!body) return;
    set({ disputeChatDraft: '', disputeChatError: '' });
    const { data, error } = await supabase.rpc('send_refund_dispute_message', { p_refund_claim_id: claimId, p_body: body });
    if (error || data?.success === false) {
      console.warn('sendRefundDisputeMessage failed:', error || data?.error);
      set({
        disputeChatDraft: body,
        disputeChatError: data?.error === 'DISPUTE_RESOLVED'
          ? T('Tranh chấp này đã kết thúc nên không còn gửi được.', "This dispute has ended, so it's no longer open.")
          : T('Chưa gửi được. Thử lại nhé.', "Couldn't send. Please try again."),
      });
      return;
    }
    await loadRefundDisputeChat(claimId);
    // The pinned Messages entry shows the last message, so it has to
    // refresh too or the collapsed row keeps claiming an old snippet.
    await loadDisputeChats();
  }, [set, s.disputeChatDraft, loadRefundDisputeChat, loadDisputeChats, T]);

  // ---- billing identity (the buyer block on every document) ----
  const openBilling = useCallback(async () => {
    set({ screen: 'billing', billingError: '', billingSaved: false });
    const uid = s.user?.id;
    if (!uid) return;
    const { data } = await supabase
      .from('profiles')
      .select('display_name, phone, billing_name, billing_address, billing_phone, billing_tax_code')
      .eq('id', uid).maybeSingle();
    if (!data) return;
    set({
      billingName: data.billing_name || data.display_name || '',
      billingAddress: data.billing_address || '',
      billingPhone: data.billing_phone || data.phone || '',
      billingTaxCode: data.billing_tax_code || '',
    });
  }, [set, s.user?.id]);

  const billingNameType = useCallback((e) => set({ billingName: e.target.value, billingSaved: false }), [set]);
  const billingAddressType = useCallback((e) => set({ billingAddress: e.target.value, billingSaved: false }), [set]);
  const billingPhoneType = useCallback((e) => set({ billingPhone: e.target.value, billingSaved: false }), [set]);
  const billingTaxCodeType = useCallback((e) => set({ billingTaxCode: e.target.value, billingSaved: false }), [set]);

  const saveBillingDetails = useCallback(async () => {
    set({ billingSaving: true, billingError: '', billingSaved: false });
    try {
      const { data, error } = await supabase.rpc('save_billing_details', {
        p_name: s.billingName, p_address: s.billingAddress,
        p_phone: s.billingPhone, p_tax_code: s.billingTaxCode,
      });
      if (error) throw error;
      if (data && data.success === false) throw new Error(data.error || 'SAVE_FAILED');
      set({ billingSaving: false, billingSaved: true });
    } catch (e) {
      console.warn('saveBillingDetails failed:', e);
      set({ billingSaving: false, billingError: T('Chưa lưu được. Thử lại nhé.', "Couldn't save. Please try again.") });
    }
  }, [set, T, s.billingName, s.billingAddress, s.billingPhone, s.billingTaxCode]);

  // ---- payout details (where the organizer wants to be paid) ----
  const openPayout = useCallback(async () => {
    set({ screen: 'payout', payoutError: '', payoutSaved: false });
    const orgId = s.myOrganizerIds[0];
    if (!orgId) return;
    const { data } = await supabase
      .from('organizers')
      .select('bank_name, bank_account_name, bank_account_no, momo_phone, pay_note, billing_address, tax_code')
      .eq('id', orgId).maybeSingle();
    if (!data) return;
    set({
      payoutBankName: data.bank_name || '', payoutAccountName: data.bank_account_name || '',
      payoutAccountNo: data.bank_account_no || '', payoutMomo: data.momo_phone || '',
      payoutNote: data.pay_note || '', payoutAddress: data.billing_address || '',
      payoutTaxCode: data.tax_code || '',
    });
  }, [set, s.myOrganizerIds]);

  const payoutField = useCallback((key) => (e) => set({ [key]: e.target.value, payoutSaved: false }), [set]);

  const savePayoutDetails = useCallback(async () => {
    const orgId = s.myOrganizerIds[0];
    if (!orgId) return set({ payoutError: T('Chưa có trang tổ chức.', 'No host page yet.') });
    set({ payoutSaving: true, payoutError: '', payoutSaved: false });
    try {
      const { data, error } = await supabase.rpc('save_organizer_payment', {
        p_organizer: orgId,
        p_bank_name: s.payoutBankName, p_bank_account_name: s.payoutAccountName,
        p_bank_account_no: s.payoutAccountNo, p_momo_phone: s.payoutMomo,
        p_pay_note: s.payoutNote, p_billing_address: s.payoutAddress, p_tax_code: s.payoutTaxCode,
      });
      if (error) throw error;
      if (data && data.success === false) throw new Error(data.error || 'SAVE_FAILED');
      set({ payoutSaving: false, payoutSaved: true });
    } catch (e) {
      console.warn('savePayoutDetails failed:', e);
      set({ payoutSaving: false, payoutError: T('Chưa lưu được. Thử lại nhé.', "Couldn't save. Please try again.") });
    }
  }, [set, T, s.myOrganizerIds, s.payoutBankName, s.payoutAccountName, s.payoutAccountNo,
      s.payoutMomo, s.payoutNote, s.payoutAddress, s.payoutTaxCode]);

  // ---- the documents themselves ----
  // Sub-section-of-a-group back-navigation fix (2026-09-29) — mirrors the
  // same fix on iOS (AppState.swift's `documentsListBack`): every current
  // caller of openDocuments (AccountGroup.jsx's Invoices/Receipts rows) is
  // reached FROM the "payments" AccountGroup page, so `backFromDocuments`
  // hardcoding `screen: 'profile'` skipped a level, landing on Account's
  // root instead of back on Payments & documents. `back` records the real
  // origin, defaulting to 'accountGroup' since that's this screen's only
  // real entry point today.
  const openDocuments = useCallback((kind, role = 'guest', back = 'accountGroup') => {
    set({ screen: 'documents', documentsKind: kind, documentsRole: role, documents: [], documentsError: '', documentsBack: back });
  }, [set]);

  const loadDocuments = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return set({ documents: [], documentsLoading: false });
    set({ documentsLoading: true, documentsError: '' });

    // Documents are organizer-uploaded now (migration 056). Lists BOTH the
    // live document (superseded_at IS NULL) AND any still-live superseded
    // copy (purge_after > now(), Task 5's 24h soft-delete grace window) —
    // until this pass, that old copy was only ever surfaced as a bare count
    // on Attendance ("Phiên bản hiện tại (2) · ..."), with no way for
    // either the organizer or the guest to actually open it before it's
    // gone for good (08-payment-documents.md's 2026-09-17 follow-up #7).
    // RLS (`payment_documents_select_guest`/`_host`, 024) doesn't gate on
    // superseded_at at all, so this is purely a query-filter change, not an
    // access-control one. Once purge_after passes, the row (and its
    // storage object) is hard-deleted by the purge cron and simply stops
    // matching this query — no separate hide-it step needed here.
    //
    // `events(...)` embeds via the event_id FK — the `event` jsonb column is
    // only ever populated for a legacy structured invoice; an uploaded raw
    // receipt/invoice (migration 056's upload_payment_document()) leaves it
    // at its '{}' default and only ever sets event_id, confirmed live
    // (08-payment-documents.md's 2026-09-17 follow-up #4). Named `events`
    // (bare table name, not `event:events(...)`) both because that's what a
    // text FK embed on this schema is confirmed to need (same follow-up's
    // `organizers` embed note) and because an `event:` alias would collide
    // with the existing jsonb column's key in the same row.
    const nowIso = new Date().toISOString();
    let query = supabase.from('payment_documents').select('*, events(name, starts_at, event_date, event_time)').eq('kind', s.documentsKind).or(`superseded_at.is.null,purge_after.gt.${nowIso}`);
    if (s.documentsRole === 'host') {
      // An organizer is usually also a goer, so filtering by RLS alone would
      // mix their own tickets into the list of documents they issued.
      if (!s.myOrganizerIds.length) return set({ documentsLoading: false, documents: [] });
      query = query.in('organizer_id', s.myOrganizerIds);
    } else {
      query = query.eq('user_id', uid);
    }
    const { data, error } = await query.order('issued_at', { ascending: false });
    if (error) {
      console.warn('loadDocuments failed:', error);
      return set({ documentsLoading: false, documents: [], documentsError: T('Chưa tải được danh sách.', "Couldn't load the list.") });
    }
    set({ documentsLoading: false, documents: data || [] });
  }, [set, T, s.user?.id, s.documentsKind, s.documentsRole, s.myOrganizerIds]);

  const openDocument = useCallback((id, backTo = 'documents') => set({ screen: 'documentView', documentId: id, documentBack: backTo }), [set]);
  const backFromDocument = useCallback(() => set(prev => ({ screen: prev.documentBack || 'documents' })), [set]);
  const backFromDocuments = useCallback(() => set(prev => ({ screen: prev.documentsBack || 'profile' })), [set]);

  const currentDocument = useMemo(
    () => s.documents.find(d => d.id === s.documentId) || null,
    [s.documents, s.documentId],
  );

  /**
   * The organizer's replacement for the old auto-generation: uploads a real
   * file (PDF/image) to the private 'payment-documents' bucket, then
   * upload_payment_document() (migration 056) records it, supersedes
   * whatever live document of that kind existed for this booking (only
   * when `reason` is given — the RPC itself enforces that a reason is
   * required exactly when there's something to replace), and inserts the
   * in-app notification. The email (Task 4's opt-in, Task 6's always-sent
   * replacement notice) is a separate, best-effort call to /api/notify —
   * same "client calls it right after its own action succeeds" pattern
   * claimPendingReferralAndWelcome() already uses, not part of this
   * transaction.
   */
  const uploadPaymentDocument = useCallback(async (bookingId, kind, file, reason = '') => {
    if (!bookingId || !file) return { success: false, error: 'FILE_REQUIRED' };
    try {
      const { blob, ext, contentType } = await normalizeProofFile(file);
      const path = `${bookingId}/${kind}-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('payment-documents').upload(path, blob, { upsert: true, contentType });
      if (upErr) throw upErr;

      const trimmedReason = reason.trim();
      const { data: doc, error } = await supabase.rpc('upload_payment_document', {
        p_booking: bookingId, p_kind: kind, p_file_path: path, p_upload_reason: trimmedReason || null,
      });
      if (error) throw error;

      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: trimmedReason ? 'document_replaced' : 'document_uploaded', documentId: doc.id }),
        }).catch(() => {});
      }
      return { success: true, doc };
    } catch (e) {
      console.warn('uploadPaymentDocument failed:', e);
      // upload_payment_document() (056) raises one of these exact codes as
      // its exception message — propagate whichever one it actually was
      // instead of collapsing every failure into the same generic
      // "Couldn't upload" (08-payment-documents.md's 2026-09-17 follow-up
      // #5: this is exactly what made a plain REASON_REQUIRED — the
      // Attendance upload button never sending a reason — indistinguishable
      // from a real failure).
      const KNOWN_CODES = ['REASON_REQUIRED', 'FILE_REQUIRED', 'AUTH_REQUIRED', 'NOT_AUTHORIZED', 'INVALID_PATH', 'BOOKING_NOT_FOUND'];
      return { success: false, error: KNOWN_CODES.includes(e.message) ? e.message : 'UPLOAD_FAILED' };
    }
  }, []);

  // Deep-links a bell notification ('payment_document_uploaded'/'_replaced')
  // straight to the document it's about, without needing the full
  // Documents list loaded first — fetches the one row RLS allows this
  // account to see and opens the viewer on it. `role` defaults to 'guest'
  // (the notification case) but Attendance's own "view this receipt" taps
  // (08-payment-documents.md's 2026-09-17 follow-up #7 — BUG 1: a live and
  // a still-live superseded copy are both now individually tappable there,
  // not just counted) pass 'host' so DocumentView's organizer-only controls
  // render correctly.
  const openDocumentFromNotification = useCallback(async (documentId, backTo = 'documents', role = 'guest') => {
    const { data, error } = await supabase.from('payment_documents').select('*').eq('id', documentId).maybeSingle();
    // 2026-09-19 follow-up: `data: null` with no error is unambiguous here
    // — payment_documents' RLS (`_select_guest`: `auth.uid() = user_id`)
    // can never spuriously deny this row to its own notification's
    // recipient, so an empty result really does mean the row is gone
    // (the 24h/12-month purge cron, or a manual cleanup like the one that
    // triggered this fix — every payment_documents row got deleted mid-
    // session, orphaning any payment_document_uploaded/_replaced/
    // receipt_requested notification pointing at one). A genuine fetch
    // error (network/transient) is NOT treated as stale — only a clean
    // not-found is. Returned (not just a silent `return`) so
    // openNotification() can tell its caller the target was missing and
    // react instead of doing nothing — this function has other callers
    // (Confirmed.jsx's "Xem Receipt", Attendance.jsx's per-receipt rows)
    // that don't come from a notification and can just ignore this.
    if (error) { console.warn('openDocumentFromNotification failed:', error); return { success: false, notFound: false }; }
    if (!data) return { success: false, notFound: true };
    set({ documents: [data], documentId: data.id, documentsKind: data.kind, documentsRole: role, screen: 'documentView', documentBack: backTo });
    return { success: true };
  }, [set]);

  // Keeps documentFileUrl pointed at whichever document is open — a signed
  // URL, not a public one, since the bucket is private (RLS-scoped to the
  // booking's guest/organizer, migration 056). Re-signs whenever the open
  // document changes; a legacy document with no file_path just clears it,
  // which is what tells DocumentView.jsx to fall back to the old rendered-
  // HTML viewer instead.
  useEffect(() => {
    const path = currentDocument?.file_path;
    if (!path) { set({ documentFileUrl: '' }); return; }
    let active = true;
    supabase.storage.from('payment-documents').createSignedUrl(path, 600).then(({ data, error }) => {
      if (!active) return;
      if (error) { console.warn('document signed URL failed:', error); set({ documentFileUrl: '' }); return; }
      set({ documentFileUrl: data?.signedUrl || '' });
    });
    return () => { active = false; };
  }, [currentDocument?.file_path, set]);

  const toggleAutoEmailDocuments = useCallback(() => {
    set(prev => ({ autoEmailDocuments: !prev.autoEmailDocuments }));
    persistAccountPreference({ auto_email_documents: !s.autoEmailDocuments });
  }, [set, s.autoEmailDocuments, persistAccountPreference]);

  /**
   * Hands the rendered document to the browser's own print dialog, which is
   * also its "Save as PDF". Generating a PDF in-page would mean shipping a
   * PDF library and hand-laying the Vietnamese diacritics into it; the print
   * pipeline already renders the exact same HTML the viewer just looked at.
   */
  const downloadDocument = useCallback((doc) => {
    if (!doc) return;
    const html = renderPaymentDocument(doc, { lang: s.lang, origin: window.location.origin });
    const w = window.open('', '_blank');
    if (!w) return;
    w.document.write(html);
    w.document.close();
    // Let the wordmark land before the dialog freezes the page, or the
    // saved PDF has a broken-image box where the logo should be.
    w.addEventListener('load', () => setTimeout(() => w.print(), 120));
  }, [s.lang]);

  const openPreferences = useCallback(() => set({ screen: 'preferences' }), [set]);

  // ---- Event preferences + onboarding (note 34, migration 162) ----
  // Every read/write goes through owner-scoped SECURITY DEFINER RPCs. A project
  // without migration 162 simply owes nothing (no gate, no preferences); a
  // flaky read never traps the user in onboarding.
  const eventPrefsUidRef = useRef(null);
  const eventPrefsGate = useAccountGate();
  const resetEventPrefsState = useCallback(() => set({
    eventPrefs: null, eventPrefsVersion: 0, eventPrefsLoaded: false,
    needsSettingsOnboarding: false, needsPreferencesOnboarding: false,
    eventOnboardingIsNewAccount: false, eventPrefsReturnScreen: null,
    filterForYou: false, eligibilityByKey: {},
  }), [set]);

  const loadEventPreferences = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return;
    eventPrefsUidRef.current = uid;
    try {
      const { data, error } = await supabase.rpc('get_my_event_preferences');
      if (eventPrefsUidRef.current !== uid) return; // signed out / switched account meanwhile
      if (error) {
        if (isEventPrefsFnMissing(error)) set({ needsSettingsOnboarding: false, needsPreferencesOnboarding: false, eventPrefsLoaded: true });
        else { console.warn('loadEventPreferences failed:', error); set({ needsSettingsOnboarding: false, needsPreferencesOnboarding: false }); }
        return;
      }
      if (data?.success !== true) { set({ eventPrefsLoaded: true }); return; }
      set({
        eventPrefs: data.preferences && typeof data.preferences === 'object' ? data.preferences : null,
        eventPrefsVersion: data.preferences_version || 0,
        needsSettingsOnboarding: data.needs_settings_step === true,
        needsPreferencesOnboarding: data.needs_preferences_step === true,
        eventOnboardingIsNewAccount: data.is_new_account === true,
        eventPrefsLoaded: true,
      });
    } catch (e) {
      console.warn('loadEventPreferences failed:', e);
      if (eventPrefsUidRef.current === uid) set({ needsSettingsOnboarding: false, needsPreferencesOnboarding: false });
    }
  }, [s.user?.id, set]);

  // Load once per signed-in session, after the account gate and profile sync
  // have settled; reset when the user leaves or a different account arrives.
  useEffect(() => {
    const uid = s.user?.id || null;
    if (eventPrefsUidRef.current && eventPrefsUidRef.current !== uid) {
      eventPrefsUidRef.current = null;
      resetEventPrefsState();
    }
    if (!uid || eventPrefsUidRef.current === uid) return;
    if (eventPrefsGate.gate !== 'ready' || s.authSyncing || s.policyGateActive) return;
    loadEventPreferences();
  }, [s.user?.id, s.authSyncing, s.policyGateActive, eventPrefsGate.gate, loadEventPreferences, resetEventPrefsState]);

  /** Opens Account > Event preferences. `returnTo` (a screen name) makes Back / "Save and go back" land there; omit for the normal Account entry. */
  const openEventPreferences = useCallback((returnTo = null) => set({ eventPrefsReturnScreen: returnTo || null, screen: 'eventPreferences' }), [set]);

  /** Account > Event preferences (and the onboarding questions). Resolves true on success. */
  const saveEventPreferences = useCallback(async (prefs) => {
    const body = normalizeEventPrefsForSave(prefs);
    try {
      const { data, error } = await supabase.rpc('save_my_event_preferences', { p_preferences: body });
      if (error || data?.success !== true) { if (error) console.warn('saveEventPreferences failed:', error); return false; }
      set(prev => ({ eventPrefs: body, eventPrefsVersion: data.preferences_version || (prev.eventPrefsVersion + 1) }));
      return true;
    } catch (e) { console.warn('saveEventPreferences failed:', e); return false; }
  }, [set]);

  /** Marks the settings-review step done. Never writes any setting itself. */
  const completeSettingsOnboarding = useCallback(async () => {
    try {
      const { data, error } = await supabase.rpc('complete_settings_onboarding');
      if (error && isEventPrefsFnMissing(error)) { set({ needsSettingsOnboarding: false }); return true; }
      if (error || data?.success !== true) { if (error) console.warn('completeSettingsOnboarding failed:', error); return false; }
      set({ needsSettingsOnboarding: false });
      return true;
    } catch (e) { console.warn('completeSettingsOnboarding failed:', e); return false; }
  }, [set]);

  /** Finishes the five-question step. null = skipped everything (marker only). */
  const completePreferencesOnboarding = useCallback(async (prefsOrNull) => {
    const body = prefsOrNull ? normalizeEventPrefsForSave(prefsOrNull) : null;
    try {
      const { data, error } = await supabase.rpc('complete_preferences_onboarding', { p_preferences: body });
      if (error && isEventPrefsFnMissing(error)) { set({ needsPreferencesOnboarding: false }); return true; }
      if (error || data?.success !== true) { if (error) console.warn('completePreferencesOnboarding failed:', error); return false; }
      set(prev => ({
        needsPreferencesOnboarding: false,
        ...(body ? { eventPrefs: body, eventPrefsVersion: data.preferences_version || (prev.eventPrefsVersion + 1) } : {}),
      }));
      return true;
    } catch (e) { console.warn('completePreferencesOnboarding failed:', e); return false; }
  }, [set]);
  const openSecurity = useCallback(() => set({
    screen: 'security', securityPassword: '', securityPasswordConfirm: '',
    securityError: '', securitySaved: false, securityResetSent: false,
  }), [set]);

  // Account IA pass (2026-09-27) — ONE shared child screen for every
  // grouped Account entry card (team/activity/payments/preferences on Cá
  // nhân, hostOps on Tổ chức, adminReview on Admin), keyed by
  // `accountGroupKey` — never a separate screen per group (that would be
  // 6 near-identical files on each platform for what's really one layout:
  // a title + back-to-Account + a handful of existing rows, relocated,
  // never rebuilt). `accountTab` itself is untouched, so returning to
  // 'profile' lands back on whichever tab was already showing.
  const openAccountGroup = useCallback((key) => set({ screen: 'accountGroup', accountGroupKey: key }), [set]);

  const trStatus = useCallback((str) => {
    if (!EN) return str;
    return String(str)
      .replace(/Còn (\d+) chỗ/g, '$1 seats left')
      .replace(/Còn (\d+) ngày/g, 'In $1 days')
      .replace(/Hôm nay/g, 'Today').replace(/Ngày mai/g, 'Tomorrow')
      .replace(/(\d+) giờ trước/g, '$1h ago').replace(/(\d+) ngày trước/g, '$1d ago')
      .replace(/1 giờ trước/g, '1h ago').replace(/1 ngày trước/g, '1d ago')
      .replace(/Hết chỗ/g, 'Sold out').replace(/Đã hủy/g, 'Cancelled')
      .replace(/Đã hoàn tiền/g, 'Refunded').replace(/Đã diễn ra/g, 'Ended')
      .replace(/Đang giữ/g, 'On hold').replace(/Đã thanh toán/g, 'Paid')
      .replace(/Đã lưu/g, 'Saved').replace(/Đang tham gia/g, 'Going')
      .replace(/Trả để xác nhận/g, 'Pay to confirm')
      .replace(/(\d+) vé/g, '$1 tix')
      .replace(/Miễn phí/g, 'Free')
      .replace(/ km từ bạn/g, ' km away')
      .replace(/từ bạn/g, 'away')
      .replace(/Thời trang/g, 'Fashion')
      .replace(/Phòng tranh/g, 'Gallery')
      .replace(/^Nhạc$/g, 'Music').replace(/ ▪︎ Nhạc/g, ' ▪︎ Music');
  }, [EN]);

  const located = s.located === true;
  // With no location permission, the km segment is stripped out entirely (we
  // don't show the demo's placeholder number as if it meant something). Once
  // the user has shared their location, pass the event in too and its
  // baked-in placeholder distance is swapped for the real, computed one as
  // soon as a fresh position is available.
  //
  // BUG 2 fix (2026-09-22 follow-up) — real bug, confirmed by reading: the
  // `km == null` branch used to `return str` UNCHANGED, meaning any time
  // `located` was true but a real distance genuinely wasn't available yet
  // (userCoords still null while `getCurrentPosition` is in flight or timed
  // out, or an event with no lat/lng), the catalogue's baked-in placeholder
  // km number stayed visible looking exactly like a live value — exactly
  // the "invented/static fallback" this ticket says must never show. The
  // stripped string is now the fallback in every case a live distance can't
  // be computed, not only when permission was never granted at all.
  const stripKm = useCallback((str, ev) => {
    const stripped = str.replace(/ ▪︎ \d+[.,]\d+ km(?: từ bạn| away)?/g, '');
    if (!located) return stripped;
    const km = ev ? haversineKm(s.userCoords, ev) : null;
    if (km == null) return stripped;
    return str.replace(/\d+[.,]\d+(?= km)/, km.toFixed(1).replace('.', ','));
  }, [located, s.userCoords]);

  // Blocker fix (retention roadmap follow-up) — see shapeRealEventAsCurEvent's
  // own comment: a real, host-created event (not one of the 20 static demo
  // ones) resolves through the canonical realEventsById cache instead of
  // findEvent()'s own `|| EVENTS[0]` fallback, which used to substitute a
  // WRONG demo event's name/price/photo/description in its place.
  const isCatalogEventKey = useMemo(() => EVENTS.some(e => e.key === s.eventKey), [s.eventKey]);
  useEffect(() => {
    if (!isCatalogEventKey && s.eventKey) loadRealEventsById([s.eventKey]);
  }, [isCatalogEventKey, s.eventKey, loadRealEventsById]);
  const curEvent = useMemo(() => {
    if (!isCatalogEventKey) {
      const real = s.realEventsById[s.eventKey];
      // Still loading, or genuinely unavailable (deleted/RLS-denied) — an
      // honest, mostly-empty placeholder rather than a wrong demo event's
      // cosmetic content. `key` stays the real one so isSaved/toggleFav
      // and the "unavailable" UI can still key off the right id.
      if (!real) return { ...EVENTS[0], key: s.eventKey, name: real === null ? T('Sự kiện không khả dụng', 'Event unavailable') : '', img: '', price: '', desc: '', included: '', orgName: '', gallery: [], isRealFallback: true, unavailable: real === null };
      return shapeRealEventAsCurEvent(real);
    }
    const base = findEvent(s.eventKey);
    const overrides = liveEventOverrides(s.liveEvent, base);
    return overrides ? { ...base, ...overrides } : base;
  }, [s.eventKey, s.liveEvent, isCatalogEventKey, s.realEventsById, T]);
  const palette = curEvent.palette;

  const isSaved = useCallback((k) => s.favorites.includes(k), [s.favorites]);
  // 2026-09-21 follow-up (Home filters, see 07-notifications.md) —
  // narrowed from `s.attending.includes(k)` (any booking that merely HOLDS
  // A SEAT: status IN pending/confirmed/attended — the canonical "Going"
  // set note 04/12-home-filters.md deliberately chose for seat-holding
  // purposes) to genuinely PAID/confirmed only (`payment_state ===
  // 'confirmed'`, which a free/instant-confirm booking also gets
  // immediately — 053_hold_seats_guest_notification.sql). Requested
  // explicitly this pass so the new "Chưa xác nhận" filter (still holding
  // a seat but NOT yet confirmed) is meaningful against "Attending" —
  // otherwise the two would overlap. `isGoing` has exactly one consumer
  // (Home.jsx) confirmed by repo-wide grep before narrowing it, so this
  // doesn't ripple into Account.jsx's/EventList.jsx's own "Going" count,
  // which read `s.attending` directly and are UNCHANGED (still seat-
  // holding, not payment-scoped — out of this ticket's scope).
  const isGoing = useCallback((k) => s.paymentBookings.some(b => b.event_id === k && b.payment_state === 'confirmed'), [s.paymentBookings]);
  // The new "Chưa xác nhận" filter's own predicate — has an active
  // (non-cancelled/expired) booking for this event that ISN'T confirmed
  // yet: still `holding` (paid nothing so far) or `pending_verification`
  // (proof submitted, awaiting the organizer). Reuses the same
  // `s.paymentBookings` Home already loads — no new query.
  const isAwaitingConfirmation = useCallback((k) => s.paymentBookings.some(b =>
    b.event_id === k && ['pending', 'confirmed', 'attended'].includes(b.status) && ['holding', 'pending_verification'].includes(b.payment_state)
  ), [s.paymentBookings]);
  // Stage 1 (retention roadmap P0) — persists to the real `favorites`
  // table (owner-only RLS, 003_social_chat.sql), replacing what used to be
  // local-only React state. Optimistic (UI flips immediately, same as
  // before) with a server-failure rollback, guarded two ways: (1)
  // favToggleInFlightRef ignores a repeat tap on the same event while its
  // own request is still in flight, so a fast double-tap can't fire two
  // opposite writes for the same row; (2) the rollback only applies if
  // `s.user` is still this same account by the time the request settles,
  // so a fast logout/login in between can't have it clobber the new
  // account's own favorites.
  const toggleFav = useCallback((k) => {
    if (favToggleInFlightRef.current.has(k)) return;
    const wasSaved = s.favorites.includes(k);
    set(prev => ({ favorites: wasSaved ? prev.favorites.filter(x => x !== k) : [...prev.favorites, k] }));
    if (!s.user) return; // signed-out guest: local-only, same as before this ticket
    const uid = s.user.id;
    favToggleInFlightRef.current.add(k);
    (async () => {
      try {
        const { error } = wasSaved
          ? await supabase.from('favorites').delete().eq('user_id', uid).eq('event_id', k)
          : await supabase.from('favorites').upsert({ user_id: uid, event_id: k }, { onConflict: 'user_id,event_id' });
        if (error) throw error;
      } catch (error) {
        console.warn('Failed to persist favorite toggle:', error);
        set(prev => (prev.user?.id === uid ? {
          favorites: wasSaved ? [...new Set([...prev.favorites, k])] : prev.favorites.filter(x => x !== k),
        } : prev));
      } finally {
        favToggleInFlightRef.current.delete(k);
      }
    })();
  }, [set, s.favorites, s.user]);
  // 2026-09-21 follow-up (stories, 07-notifications.md) — REAL bug found
  // while wiring stories' audience: this was local-only React state, keyed
  // by event key, never written to the real `follows(user_id, organizer_id)`
  // table (003_social_chat.sql) at all. Local `following` (by event key)
  // stays as the optimistic UI toggle Organizer.jsx already reads — no
  // visual change requested — but now ALSO persists to `follows`, resolved
  // via the event's real organizer_id (same events-table lookup
  // openChatFor() already does), best-effort: a demo-catalogue event with
  // no real DB row silently only updates local state, same as before.
  const toggleFollow = useCallback(async (k) => {
    const wasFollowing = s.following.includes(k);
    set(prev => ({ following: wasFollowing ? prev.following.filter(x => x !== k) : [...prev.following, k] }));
    if (!s.user) return;
    const { data: event } = await supabase.from('events').select('organizer_id').eq('id', k).maybeSingle();
    if (!event?.organizer_id) return; // demo-catalogue event, no real DB row — local toggle only
    if (wasFollowing) {
      await supabase.from('follows').delete().eq('user_id', s.user.id).eq('organizer_id', event.organizer_id);
    } else {
      await supabase.from('follows').insert({ user_id: s.user.id, organizer_id: event.organizer_id }, { onConflict: 'user_id,organizer_id' });
    }
  }, [set, s.following, s.user]);

  // ============ Stories (Task 3, 07-notifications.md) ============
  // RLS (migration 066) already does every access check that matters here —
  // an unfiltered SELECT on `stories` only ever returns active rows the
  // signed-in account is actually permitted to see (own, co-owned organizer,
  // or a followed organizer) — so this just groups+signs what comes back,
  // no client-side re-filtering.
  //
  // Source-of-discovery pass — Section 5's own "Help Shape Upcoming Events"
  // no longer lives in this function at all (see `loadHomeSurveyDiscovery()`
  // below, which reads `get_public_survey_discovery()`, migration 120,
  // directly — every published, currently-open public survey, whether or
  // not it was ever shared to a story). This function now only builds the
  // ordinary follow/ownership-gated per-organizer story ring.
  const loadHomeStories = useCallback(async () => {
    if (!s.user) return set({ homeStories: [] });
    const { data: rows, error } = await supabase
      .from('stories')
      .select('id, organizer_id, author_id, media_path, media_type, width, height, created_at, expires_at, kind, event_id, survey_id')
      .order('created_at', { ascending: true });
    if (error) {
      if (import.meta.env?.DEV) console.warn('loadHomeStories failed:', { code: error.code, message: error.message });
      return;
    }
    if (!rows?.length) return set({ homeStories: [] });

    const { data: followRows } = await supabase.from('follows').select('organizer_id').eq('user_id', s.user.id);
    const followedOrgIds = new Set((followRows || []).map(f => f.organizer_id));
    const isMineOrFollowed = (organizerId) => s.myOrganizerIds.includes(organizerId) || followedOrgIds.has(organizerId);

    const ownRows = rows.filter(r => isMineOrFollowed(r.organizer_id));

    const orgIds = [...new Set(rows.map(r => r.organizer_id))];
    const { data: orgRows } = await withR2Columns(withR2 => supabase.from('organizers').select(withR2 ? 'id, name, owner_id, user_id, avatar_path, avatar_r2_ref' : 'id, name, owner_id, user_id, avatar_path').in('id', orgIds));
    const orgById = Object.fromEntries((orgRows || []).map(o => [o.id, o]));
    // Avatar pass — real, confirmed bug: `get_survey_card()` (migration 117)
    // returns no avatar field at all (see note 21's own "not done this pass"
    // list), so `SurveyShareCard` (StoryViewer.jsx) always passed
    // `hostAvatarUrl: undefined`, rendering the blank placeholder for EVERY
    // survey story, not just ones missing a real photo. Resolved
    // client-side instead of widening that RPC: this query already fetches
    // each story's own `organizers` row (for `orgName`) — its real
    // `avatar_path`, resolved through the SAME public-bucket URL helper
    // `organizer-photos` avatars already use elsewhere (Account.jsx/
    // Dashboard.jsx/OrganizerProfile.jsx/SurveysHosting.jsx's own
    // `organizerAvatarUrl`), travels alongside it on the story item itself.
    const orgAvatarUrlById = Object.fromEntries(
      (orgRows || []).filter(o => o.avatar_path || o.avatar_r2_ref).map(o => [o.id, organizerAvatarPublicUrl(o.avatar_path, o.avatar_r2_ref, 'thumb')])
    );

    const { data: viewRows } = await supabase.from('story_views').select('story_id').eq('viewer_id', s.user.id).in('story_id', ownRows.map(r => r.id));
    const viewedSet = new Set([...(viewRows || []).map(v => v.story_id), ...storyViewedIdsRef.current]);

    // Task 4 (2026-09-22 follow-up) — an event_share story's `media_path`
    // is deliberately empty (it renders as an event card, not a photo — see
    // migration 068's own comment), so only real media rows are worth a
    // signed-URL round trip. A survey_share row's media_path is equally
    // always empty (migration 117's own INSERT), same reasoning.
    const mediaPaths = ownRows.filter(r => r.kind === 'media' && r.media_path).map(r => r.media_path);
    const { data: signed } = mediaPaths.length
      ? await supabase.storage.from('stories').createSignedUrls(mediaPaths, 600)
      : { data: [] };
    const urlByPath = Object.fromEntries((signed || []).filter(r => r.signedUrl && !r.error).map(r => [r.path, r.signedUrl]));

    // One get_survey_card() per distinct survey referenced by the STORY
    // RING only now (`ownRows` — mine/followed) — Section 5's own discovery
    // no longer needs this at all, since `get_public_survey_discovery()`
    // already returns everything a discovery row needs directly.
    const surveyIds = [...new Set(ownRows.filter(r => r.kind === 'survey_share' && r.survey_id).map(r => r.survey_id))];
    const surveyCardEntries = await Promise.all(surveyIds.map(async (id) => {
      const { data } = await supabase.rpc('get_survey_card', { p_survey_id: id });
      return [id, data?.success ? data : null];
    }));
    const surveyCardById = Object.fromEntries(surveyCardEntries);

    const byOrg = {};
    for (const r of ownRows) {
      const org = orgById[r.organizer_id];
      if (!org) continue;
      if (!byOrg[r.organizer_id]) byOrg[r.organizer_id] = { organizerId: r.organizer_id, orgName: org.name, stories: [] };
      const isEventShare = r.kind === 'event_share';
      // BUG 2 fix (2026-09-22 follow-up) — two real bugs here, confirmed by
      // reading:
      // 1. `findEvent()` (src/data/events.js) falls back to `EVENTS[0]` for
      //    ANY unmatched key, "so a screen always has something to render"
      //    — exactly the wrong behavior here, since it means a genuinely
      //    bad/missing event_id silently showed a random WRONG event
      //    instead of the "no longer available" state this card already
      //    has ready for that case. Matched directly against `EVENTS`
      //    instead (no fallback), same fix 07-notifications.md's own
      //    2026-09-18 notification-avatar entry already applied for the
      //    identical reason.
      // 2. The snapshot read `ev.dayLong`/`ev.time`/`ev.area` — none of
      //    which exist on a catalogue event (confirmed against the actual
      //    object literal in events.js: the real fields are `when`
      //    (combined date+time) and `where`/`locationLabel`) — silently
      //    rendering "undefined" text. The event's own cover image
      //    (`ev.img`) was already correct and DID load; only the
      //    date/time/location line was blank.
      const evRaw = isEventShare ? EVENTS.find(e => e.key === r.event_id) : null;
      // 2026-09-25 fix pass (Task 0 audit) — this snapshot is rebuilt fresh
      // every time `loadHomeStories()` runs (not frozen at share-creation
      // time), so it needs the same live-date merge every other screen
      // uses — it used to read the raw static catalogue's own `ev.when`
      // directly, same frozen-month bug class as the others this pass
      // fixed.
      const overrides = evRaw ? liveEventOverrides(s.homeLiveEvents[evRaw.key], evRaw) : null;
      const ev = evRaw && overrides ? { ...evRaw, ...overrides } : evRaw;
      byOrg[r.organizer_id].stories.push({
        id: r.id, mediaPath: r.media_path, url: urlByPath[r.media_path] || null,
        width: r.width, height: r.height, createdAt: r.created_at, viewed: viewedSet.has(r.id),
        kind: r.kind || 'media',
        // BUG 2 (2026-09-22 tenth follow-up) — `lat`/`lng` added so the
        // event-share card can show a live distance via the SAME canonical
        // `distanceLabel()`/`haversineKm()` MapExplore and Event Detail
        // already use, instead of showing none at all (its previous state).
        eventSnapshot: isEventShare && ev ? { eventKey: ev.key, img: ev.img, name: ev.name, when: ev.when, where: ev.where, lat: ev.lat, lng: ev.lng } : null,
        // A survey_share row read LIVE via get_survey_card (never frozen at
        // share time) — `null` (RPC failed/survey deleted mid-session) is a
        // real, renderable state: SurveyShareCard shows "no longer
        // available" for it, same honesty rule as a missing eventSnapshot.
        surveySnapshot: r.kind === 'survey_share' ? (surveyCardById[r.survey_id] || null) : null,
        hostAvatarUrl: orgAvatarUrlById[r.organizer_id] || null,
      });
    }
    const groups = Object.values(byOrg).map(g => ({ ...g, allViewed: g.stories.every(st => st.viewed) }));
    // The signed-in account's own active story appears first, per this
    // ticket's own instruction.
    groups.sort((a, b) => {
      const aMine = s.myOrganizerIds.includes(a.organizerId) ? 0 : 1;
      const bMine = s.myOrganizerIds.includes(b.organizerId) ? 0 : 1;
      return aMine - bMine;
    });

    set({ homeStories: groups });
  }, [set, s.user, s.myOrganizerIds]);

  // ============ Section 5 — Home survey discovery (source-of-discovery
  // pass, migration 120) ============
  // Replaces the old `stories`/`survey_share`-row-based feed entirely:
  // PUBLISHING an eligible public survey makes it discoverable, whether or
  // not it was ever explicitly shared to a story — that remains a separate,
  // optional action (Share To Story). Reads `get_public_survey_discovery()`
  // directly, an authenticated-only, allowlisted-field RPC — never the raw
  // `surveys` table, and never respondent data. Keyset-paginated
  // (created_at, id) DESC — `surveyDiscoveryCursorRef` holds the next
  // page's cursor outside React state (no re-render needed just to remember
  // it), reset on every fresh load.
  const surveyDiscoveryCursorRef = useRef({ createdAt: null, id: null });
  const SURVEY_DISCOVERY_INITIAL_PAGE = 3;
  const SURVEY_DISCOVERY_PAGE = 10;

  const fetchSurveyDiscoveryPage = useCallback(async (limit) => {
    const { createdAt, id } = surveyDiscoveryCursorRef.current;
    const { data, error } = await supabase.rpc('get_public_survey_discovery', {
      p_cursor_created_at: createdAt, p_cursor_id: id, p_limit: limit,
    });
    if (error || data?.success === false) throw new Error(data?.error || error?.message || 'unknown');
    const cards = (data.surveys || []).map(row => ({
      survey_id: row.survey_id, public_id: row.public_id, title: row.title, organizer_id: row.organizer_id,
      host_name: row.host_name || '', closes_at: row.closes_at, created_at: row.created_at,
      // Avatar pass — same public-bucket resolver (`organizer-photos`,
      // synchronous `getPublicUrl`) every other organizer avatar in this
      // app already uses — no signing, no extra network call.
      host_avatar_url: row.host_avatar_path ? (organizerAvatarPublicUrl(row.host_avatar_path, row.host_avatar_r2_ref, 'thumb') || null) : null,
    }));
    return { cards, hasMore: !!data.has_more };
  }, []);

  // Stale-async-result guard (task's own "reject stale async results") —
  // bumped on every fresh call; a slower, older in-flight request landing
  // after a newer one (or after account change) must never overwrite what
  // the newer one already applied. Same token idiom already used elsewhere
  // in this codebase for the identical class of race (e.g. `refundQueueSeq`
  // above).
  const surveyDiscoverySeq = useRef(0);

  const loadHomeSurveyDiscovery = useCallback(async () => {
    if (!s.user) {
      surveyDiscoveryCursorRef.current = { createdAt: null, id: null };
      return set({
        homeSurveyDiscovery: [], homeSurveyDiscoveryLoading: false, homeSurveyDiscoveryError: '',
        homeSurveyDiscoveryHasMore: false, homeSurveyDiscoveryExpanded: false,
      });
    }
    const seq = ++surveyDiscoverySeq.current;
    surveyDiscoveryCursorRef.current = { createdAt: null, id: null };
    set({ homeSurveyDiscoveryLoading: true, homeSurveyDiscoveryError: '' });
    try {
      const { cards, hasMore } = await fetchSurveyDiscoveryPage(SURVEY_DISCOVERY_INITIAL_PAGE);
      if (seq !== surveyDiscoverySeq.current) return;
      if (cards.length) {
        const last = cards[cards.length - 1];
        surveyDiscoveryCursorRef.current = { createdAt: last.created_at, id: last.survey_id };
      }
      set({ homeSurveyDiscovery: cards, homeSurveyDiscoveryHasMore: hasMore, homeSurveyDiscoveryLoading: false, homeSurveyDiscoveryError: '' });
    } catch (e) {
      if (seq !== surveyDiscoverySeq.current) return;
      if (import.meta.env?.DEV) console.warn('loadHomeSurveyDiscovery failed:', e);
      set({ homeSurveyDiscoveryLoading: false, homeSurveyDiscoveryError: T('Không thể tải khảo sát công khai. Vui lòng thử lại.', 'Could not load public surveys. Please try again.') });
    }
  }, [set, s.user, T, fetchSurveyDiscoveryPage]);

  // "Show More" — appends the next page without disturbing rows already
  // rendered (preserves Home's own scroll position).
  const loadMoreHomeSurveyDiscovery = useCallback(async () => {
    if (s.homeSurveyDiscoveryLoadingMore || !s.homeSurveyDiscoveryHasMore) return;
    const seq = surveyDiscoverySeq.current;
    set({ homeSurveyDiscoveryLoadingMore: true });
    try {
      const { cards, hasMore } = await fetchSurveyDiscoveryPage(SURVEY_DISCOVERY_PAGE);
      if (seq !== surveyDiscoverySeq.current) return;
      if (cards.length) {
        const last = cards[cards.length - 1];
        surveyDiscoveryCursorRef.current = { createdAt: last.created_at, id: last.survey_id };
      }
      set(prev => ({
        homeSurveyDiscovery: [...prev.homeSurveyDiscovery, ...cards],
        homeSurveyDiscoveryHasMore: hasMore, homeSurveyDiscoveryLoadingMore: false,
      }));
    } catch (e) {
      if (seq !== surveyDiscoverySeq.current) return;
      if (import.meta.env?.DEV) console.warn('loadMoreHomeSurveyDiscovery failed:', e);
      set({ homeSurveyDiscoveryLoadingMore: false, homeSurveyDiscoveryError: T('Không thể tải thêm khảo sát. Vui lòng thử lại.', 'Could not load more surveys. Please try again.') });
    }
  }, [set, s.homeSurveyDiscoveryLoadingMore, s.homeSurveyDiscoveryHasMore, T, fetchSurveyDiscoveryPage]);

  // Records a real story_views row (idempotent — PK on story_id+viewer_id,
  // an upsert never duplicates a re-view) and updates local state
  // immediately so the ring subdues without waiting on a re-fetch.
  // BUG 1 fix (2026-09-22 follow-up) — real bug, confirmed by reading:
  // this used to update ONLY `storyViewedIds` (a flat id list nothing else
  // reads at render time) and left `s.homeStories`' own per-story `viewed`/
  // per-group `allViewed` fields untouched — those are what the ring
  // actually renders (Home's story row, Account's own avatar), and they
  // were only ever recomputed on the NEXT full `loadHomeStories()` fetch.
  // So a ring stayed bright after every story in a group had genuinely
  // been watched, until an unrelated reload happened to run. Fixed by also
  // updating the matching story/group in `homeStories` in this SAME
  // optimistic write, before the `story_views` upsert even resolves —
  // Home's row and Account's ring read the same `s.homeStories` array, so
  // one recomputation fixes both surfaces at once.
  const viewStoryTick = useCallback((storyId) => {
    if (!storyId || !s.user) return;
    set(prev => ({
      storyViewedIds: prev.storyViewedIds.includes(storyId) ? prev.storyViewedIds : [...prev.storyViewedIds, storyId],
      homeStories: prev.homeStories.map(g => {
        if (!g.stories.some(st => st.id === storyId)) return g;
        const stories = g.stories.map(st => st.id === storyId ? { ...st, viewed: true } : st);
        return { ...g, stories, allViewed: stories.every(st => st.viewed) };
      }),
    }));
    supabase.from('story_views').upsert({ story_id: storyId, viewer_id: s.user.id }, { onConflict: 'story_id,viewer_id' })
      .then(({ error }) => { if (error) console.warn('viewStoryTick failed:', error); });
  }, [set, s.user]);

  // BUG 5 fix (2026-09-22 follow-up) — StoryViewer now stores the FULL
  // ordered global deck (`groups`, the same array + order as Home's own
  // story row / Account's own-story-first sort — `s.homeStories` itself,
  // not a re-derived copy) plus a `groupIndex` (which host) and
  // `storyIndex` (which of that host's stories) — an "Instagram-style
  // deck," not a single organizer's stories in isolation. Groups with zero
  // stories are filtered out up front so storyNext/storyPrev never have to
  // special-case an empty one mid-navigation.
  // Task 1 (2026-09-22 twelfth follow-up) — `originRect` is the tapped
  // ring's own screen rect (Home.jsx's onClick, `getBoundingClientRect()`),
  // stored on `storyViewer` itself so it rides along through every
  // storyNext/storyPrev/storyNextHost/storyPrevHost update below (all of
  // them spread `...v`, never touching this field) — StoryViewer.jsx reads
  // it once, on open, for the expand-from-ring entrance. Dismissing back
  // toward a ring is a SEPARATE live DOM lookup at dismiss time (see that
  // file's shrinkToRing()), not this stored value, since PRODUCT CHANGE 3
  // lets the user drift to a different host before dismissing — this only
  // ever needs to capture where the OPEN animation started from.
  // ---- TASK E (2026-10-01 UX foundation pass) — Banbe Pulse ----
  // A permanent, system-generated ring entry — deliberately NOT a real row
  // in `stories` (that table hard-expires everything in 24h, both by
  // column default and RLS predicate; a synthetic client-side entry sidesteps
  // that schema entirely rather than special-casing it, per this ticket's
  // own "not authored as a normal 24h user story" rule).
  // 2026-10-03 fix pass — real bug: a single shared counter meant calling
  // loadPulse('daily') then loadPulse('weekly') right after (exactly what
  // openPulseViewer does on every open) silently DROPPED the daily
  // response almost every time — by the time it arrived, the weekly
  // call's own increment had already moved pulseSeq past it, so the
  // "stale response" guard discarded a perfectly fresh, correctly-ordered
  // response for a DIFFERENT tab. Fixed: one counter per period, so daily
  // and weekly can never race each other, only their own prior in-flight
  // call.
  const pulseSeqRef = useRef({ daily: 0, weekly: 0 });
  const loadPulse = useCallback(async (period) => {
    const seq = ++pulseSeqRef.current[period];
    set(period === 'weekly' ? { pulseWeeklyLoading: true } : { pulseDailyLoading: true });
    const { data, error } = await supabase.rpc('goc_pulse_ranked', { p_period: period });
    if (seq !== pulseSeqRef.current[period]) return; // stale response guard — only THIS period's newer call may win
    if (error || data?.success === false) {
      if (import.meta.env?.DEV) console.warn('loadPulse failed:', error, data);
      set(period === 'weekly' ? { pulseWeeklyLoading: false } : { pulseDailyLoading: false });
      return;
    }
    set(period === 'weekly'
      ? { pulseWeekly: data.items || [], pulseWeeklyLoading: false }
      : { pulseDaily: data.items || [], pulseDailyLoading: false });
  }, [set]);
  // 2026-09-25 fix pass — the third Pulse tab's own ranking, loaded
  // alongside daily/weekly on every open (same "never leave stale data
  // sitting there" rule as loadPulse above). Fixed at the 'daily' window —
  // the ticket asks for one photo-ranking tab, not a second period toggle
  // layered underneath it; 'daily' matches the event tabs' own default.
  const pulsePhotoSeqRef = useRef(0);
  const loadPulsePhotos = useCallback(async () => {
    const seq = ++pulsePhotoSeqRef.current;
    set({ pulsePhotosLoading: true });
    const { data, error } = await supabase.rpc('get_pulse_photo_ranked', { p_period: 'daily' });
    if (seq !== pulsePhotoSeqRef.current) return; // stale response guard, same pattern as loadPulse
    if (error || data?.success === false) {
      if (import.meta.env?.DEV) console.warn('loadPulsePhotos failed:', error, data);
      set({ pulsePhotosLoading: false });
      return;
    }
    const items = data.items || [];
    // 2026-09-25 fix pass (photo viewer task) — the signed-in user's OWN
    // like state for every photo in this batch, fetched in the SAME pass
    // as the ranking itself (one extra query, own-row-only per
    // `photo_likes_select_own`) and merged into the CANONICAL
    // `photoEngagement` map (see its own state comment) TOGETHER with
    // `pulsePhotos` below — never as a separate, later `set()` — so there
    // is no render in between where a liked photo would flash as
    // "not liked" before this resolves. This is also what keeps this tab's
    // counts/liked-state identical to whatever EventDetail/Organizer/
    // PhotoViewer already show for the same photo id.
    let likedIds = new Set();
    if (s.user?.id && items.length) {
      const { data: likedRows, error: likedErr } = await supabase
        .from('photo_likes').select('event_photo_id')
        .eq('user_id', s.user.id).in('event_photo_id', items.map(i => i.photo_id));
      if (seq !== pulsePhotoSeqRef.current) return;
      if (likedErr) { if (import.meta.env?.DEV) console.warn('loadPulsePhotos like-state failed:', likedErr); }
      else likedIds = new Set((likedRows || []).map(r => r.event_photo_id));
    }
    const engagementRows = items.map(i => ({
      photo_id: i.photo_id, like_count: i.like_count, share_count: i.share_count, liked_by_me: likedIds.has(i.photo_id),
    }));
    set(prev => ({
      pulsePhotos: items, pulsePhotosLoading: false,
      photoEngagement: mergePhotoEngagement(prev.photoEngagement, engagementRows),
    }));
  }, [set, s.user?.id]);
  const openPulseViewer = useCallback(() => {
    // Never leave a previous session's rank sitting there indefinitely
    // (rule A5) — cleared before the fresh fetch, not just overwritten
    // once it lands, so the loading state (not stale data) is what shows
    // in the gap.
    set({ pulseOpen: true, pulseTab: 'daily', pulseDaily: [], pulseWeekly: [], pulsePhotos: [] });
    loadPulse('daily');
    loadPulse('weekly');
    loadPulsePhotos();
    try { window.history.pushState({ bbSheet: 'pulse' }, ''); } catch { /* unsupported */ }
  }, [set, loadPulse, loadPulsePhotos]);
  // TASK A7 — the browser's own back button closes Pulse instead of
  // navigating the screen underneath it away, matching what a modal sheet
  // should do; consumed (history.back()) whenever the app itself closes
  // Pulse first, so a stray forward-swipe can't resurrect the sheet.
  const closePulseViewer = useCallback(() => {
    set({ pulseOpen: false, pulseOrganizerSheet: null });
    try { if (window.history.state?.bbSheet === 'pulse') window.history.back(); } catch { /* unsupported */ }
  }, [set]);
  const setPulseTab = useCallback((tab) => set({ pulseTab: tab }), [set]);
  const openPulseOrganizerSheet = useCallback((item) => {
    set({ pulseOrganizerSheet: item });
    // `following` isn't part of the RPC row — hydrate it from `follows` so the
    // button reflects (and toggles) the real state.
    if (!s.user?.id || !item?.organizer_id) return;
    supabase.from('follows').select('organizer_id')
      .eq('user_id', s.user.id).eq('organizer_id', item.organizer_id).limit(1)
      .then(({ data }) => {
        set(prev => (prev.pulseOrganizerSheet?.organizer_id === item.organizer_id
          ? { pulseOrganizerSheet: { ...prev.pulseOrganizerSheet, following: !!data?.length } }
          : {}));
      });
  }, [set, s.user?.id]);
  const closePulseOrganizerSheet = useCallback(() => set({ pulseOrganizerSheet: null }), [set]);
  /** Follow straight from the Pulse organizer sheet — same plain optimistic
   * table write as toggleFollowOrganizer (TASK D), just patching the
   * lighter Pulse item shape instead of a full public-profile object. */
  const followPulseOrganizer = useCallback(async (organizerId) => {
    if (!s.user?.id) return;
    const wasFollowing = !!s.pulseOrganizerSheet?.following;
    const patch = (following) => set(prev => ({
      pulseOrganizerSheet: prev.pulseOrganizerSheet ? { ...prev.pulseOrganizerSheet, following } : null,
    }));
    patch(!wasFollowing);
    const { error } = wasFollowing
      ? await supabase.from('follows').delete().eq('user_id', s.user.id).eq('organizer_id', organizerId)
      : await supabase.from('follows').insert({ user_id: s.user.id, organizer_id: organizerId });
    if (error) {
      console.warn('followPulseOrganizer failed:', error);
      patch(wasFollowing);
    }
  }, [set, s.user?.id, s.pulseOrganizerSheet?.following]);

  // 2026-09-25 fix pass — the ranked-photo popup: photo + organizer
  // identity/verified badge + a "view event" action, per this ticket's own
  // spec. Opened from a tap on a `pulsePhotos` row, closed either
  // explicitly or by the "view event" action itself.
  const openPulsePhotoSheet = useCallback((item) => set({ pulsePhotoSheet: item }), [set]);
  const closePulsePhotoSheet = useCallback(() => set({ pulsePhotoSheet: null }), [set]);

  // The Pulse-only `togglePulsePhotoLike`/`sharePulsePhoto` that used to
  // live here are gone — folded into the canonical `togglePhotoLike`/
  // `sharePhoto` (defined next to `openPhoto` above), which every surface
  // showing a real photo (EventDetail/Organizer grids, PhotoViewer, and
  // this Pulse tab) now calls identically, reading/writing the SAME
  // `photoEngagement` map. See A.3/A.6/A.8 of the photo-interactions fix.

  const openStoryViewer = useCallback((organizerId, originRect) => {
    const groups = s.homeStories.filter(g => g.stories.length > 0);
    const groupIndex = groups.findIndex(g => g.organizerId === organizerId);
    if (groupIndex === -1) return;
    set({ storyViewer: { groups, groupIndex, storyIndex: 0, originRect: originRect || null } });
    viewStoryTick(groups[groupIndex].stories[0].id);
  }, [s.homeStories, set, viewStoryTick]);
  const closeStoryViewer = useCallback(() => set({ storyViewer: null }), [set]);
  // Auto-advance / manual "next": within the current host's stories first;
  // at that host's last story, the first active story of the NEXT host
  // with any stories left; at the very last host's last story, dismiss.
  const storyNext = useCallback(() => {
    set(prev => {
      const v = prev.storyViewer;
      if (!v) return {};
      const group = v.groups[v.groupIndex];
      if (v.storyIndex + 1 < group.stories.length) {
        return { storyViewer: { ...v, storyIndex: v.storyIndex + 1 } };
      }
      for (let gi = v.groupIndex + 1; gi < v.groups.length; gi++) {
        if (v.groups[gi].stories.length > 0) return { storyViewer: { ...v, groupIndex: gi, storyIndex: 0 } };
      }
      return { storyViewer: null };
    });
  }, [set]);
  // Manual "previous": within the current host first; at that host's FIRST
  // story, the previous host's LAST story; at the very first host's first
  // story, a no-op (nothing before the start of the deck).
  const storyPrev = useCallback(() => {
    set(prev => {
      const v = prev.storyViewer;
      if (!v) return {};
      if (v.storyIndex > 0) return { storyViewer: { ...v, storyIndex: v.storyIndex - 1 } };
      for (let gi = v.groupIndex - 1; gi >= 0; gi--) {
        if (v.groups[gi].stories.length > 0) return { storyViewer: { ...v, groupIndex: gi, storyIndex: v.groups[gi].stories.length - 1 } };
      }
      return {};
    });
  }, [set]);
  // PRODUCT CHANGE 3 (2026-09-22 tenth follow-up) — the horizontal
  // DRAG/swipe gesture must move between HOST GROUPS only, never between
  // individual posts of the SAME host (that's still exclusively the
  // timer's/tap-zones' job, via `storyNext`/`storyPrev` above, unchanged).
  // `storyNextHost`/`storyPrevHost` are a SEPARATE pair of functions, only
  // ever called from StoryViewer.jsx's horizontal-drag commit branch — a
  // deliberate split, not a parameterized single function, so the two
  // gestures' semantics can never accidentally re-merge.
  //
  // "next host's current/first UNSEEN story" — resumes at whichever story
  // in that host hasn't been watched yet, or its first story if none have.
  const storyNextHost = useCallback(() => {
    set(prev => {
      const v = prev.storyViewer;
      if (!v) return {};
      for (let gi = v.groupIndex + 1; gi < v.groups.length; gi++) {
        if (v.groups[gi].stories.length === 0) continue;
        const idx = v.groups[gi].stories.findIndex(st => !st.viewed);
        return { storyViewer: { ...v, groupIndex: gi, storyIndex: idx === -1 ? 0 : idx } };
      }
      // No next host — StoryViewer.jsx's own gesture handler is what
      // decides what happens here (BUG 4: reveal Home instead of
      // advancing), so this is intentionally a no-op, not a dismiss.
      return {};
    });
  }, [set]);
  // "previous host's appropriate current/last-viewed story" — resumes at
  // the LAST story in that host the viewer had already reached (so
  // swiping back lands where they left off, not at the start again); if
  // none were viewed yet, its final story (mirrors `storyPrev`'s own
  // "enter a host from its last story" convention above).
  const storyPrevHost = useCallback(() => {
    set(prev => {
      const v = prev.storyViewer;
      if (!v) return {};
      for (let gi = v.groupIndex - 1; gi >= 0; gi--) {
        const g = v.groups[gi];
        if (g.stories.length === 0) continue;
        let lastViewed = -1;
        g.stories.forEach((st, i) => { if (st.viewed) lastViewed = i; });
        return { storyViewer: { ...v, groupIndex: gi, storyIndex: lastViewed !== -1 ? lastViewed : g.stories.length - 1 } };
      }
      // No previous host — nothing to do; the gesture always springs back
      // in this case (see BUG 4's own "beginning of the deck" symmetry).
      return {};
    });
  }, [set]);
  // Called by StoryViewer.jsx whenever the shown (groupIndex, storyIndex)
  // pair changes, including the very first one — marks that specific story
  // viewed, separate from openStoryViewer's own initial call so
  // storyNext/storyPrev don't need to duplicate the same view-recording
  // logic at every one of their several return points.
  const markStoryViewedAt = useCallback(() => {
    const v = s.storyViewer;
    const story = v?.groups?.[v.groupIndex]?.stories?.[v.storyIndex];
    if (story) viewStoryTick(story.id);
  }, [s.storyViewer, viewStoryTick]);

  // Creation — reuses the same camera/picker + Retake/Use Photo preview
  // flow Chat.jsx's attach menu already established (Task 4).
  const pickStoryFile = useCallback((file) => {
    if (!file) return;
    set({ storyCreatePreview: { file, url: URL.createObjectURL(file) } });
  }, [set]);
  const cancelStoryCreate = useCallback(() => {
    set(prev => { if (prev.storyCreatePreview) URL.revokeObjectURL(prev.storyCreatePreview.url); return { storyCreatePreview: null }; });
  }, [set]);
  // TASK 1 (dock "+" menu pass) — trigger flags for the SAME story
  // creation pipeline above, so a screen other than Account (namely the
  // dock "+" menu, which is mounted globally in App.jsx/Shell, not inside
  // any one screen) can open the picker/camera without owning a second
  // file input or upload path. StoryCreateOverlay.jsx (mounted once,
  // globally, alongside DockCreateButton) watches these and clicks its own
  // hidden inputs; Account.jsx's own "Đăng story" menu sets the same flags.
  const openStoryLibraryPicker = useCallback(() => set({ storyLibraryPickerOpen: true }), [set]);
  const openStoryCameraPicker = useCallback(() => set({ storyCameraPickerOpen: true }), [set]);
  // Consumed by StoryCreateOverlay.jsx right after it clicks its hidden
  // input, so a request is always one-shot (never stays "stuck open").
  const closeStoryPickerRequests = useCallback(() => set({ storyLibraryPickerOpen: false, storyCameraPickerOpen: false }), [set]);
  const publishStory = useCallback(async () => {
    const preview = s.storyCreatePreview;
    const orgId = s.myOrganizerIds[0];
    if (!preview || !orgId || !s.user) return { success: false };
    set({ storyCreateBusy: true });
    try {
      const { blob, ext, contentType, width, height } = await normalizeProofFile(preview.file);
      const path = `${orgId}/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('stories').upload(path, blob, { contentType });
      if (upErr) throw upErr;
      const { error } = await supabase.from('stories').insert({
        organizer_id: orgId, author_id: s.user.id, media_path: path, media_type: contentType,
        width: width || null, height: height || null,
      });
      if (error) throw error;
      URL.revokeObjectURL(preview.url);
      set({ storyCreatePreview: null, storyCreateBusy: false });
      loadHomeStories();
      return { success: true };
    } catch (e) {
      console.warn('publishStory failed:', e);
      set({ storyCreateBusy: false });
      return { success: false };
    }
  }, [s.storyCreatePreview, s.myOrganizerIds, s.user, loadHomeStories]);

  // Task 2.3a (2026-09-22 follow-up) — "Post to Story" from the chat photo
  // viewer. Reuses the SAME stories schema/storage/RLS/24h-lifecycle
  // publishStory() already writes to (Task 4 of this ticket requires this
  // be the identical Story type, not a parallel one) — the only real
  // difference is the source bytes come from an already-uploaded chat
  // attachment's signed URL instead of a freshly-picked local file.
  // `postToStoryConfirm` gates an explicit review step (ticket: "must open
  // a review step before publish; do not immediately publish by accidental
  // tap") and `storyCreateBusy` doubles as the double-tap guard here too —
  // a second tap while the first upload/insert is still in flight is a
  // no-op, not a second Story row.
  const openPostToStoryConfirm = useCallback(() => set(prev => ({ chatPhotoViewer: prev.chatPhotoViewer ? { ...prev.chatPhotoViewer, postToStoryConfirm: true } : null })), [set]);
  const closePostToStoryConfirm = useCallback(() => set(prev => ({ chatPhotoViewer: prev.chatPhotoViewer ? { ...prev.chatPhotoViewer, postToStoryConfirm: false } : null })), [set]);
  const postChatPhotoToStory = useCallback(async () => {
    const item = s.chatPhotoViewer;
    const orgId = s.myOrganizerIds[0];
    if (!item?.url || !orgId || !s.user || s.storyCreateBusy) return { success: false };
    set({ storyCreateBusy: true });
    try {
      const res = await fetch(item.url);
      if (!res.ok) throw new Error('fetch failed');
      const blob = await res.blob();
      const ext = (item.attachmentPath || '').split('.').pop() || 'jpg';
      const contentType = blob.type || 'image/jpeg';
      const path = `${orgId}/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('stories').upload(path, blob, { contentType });
      if (upErr) throw upErr;
      const { error } = await supabase.from('stories').insert({
        organizer_id: orgId, author_id: s.user.id, media_path: path, media_type: contentType,
        width: item.width || null, height: item.height || null,
      });
      if (error) throw error;
      set(prev => ({ storyCreateBusy: false, chatPhotoViewer: prev.chatPhotoViewer ? { ...prev.chatPhotoViewer, postToStoryConfirm: false } : null }));
      loadHomeStories();
      return { success: true };
    } catch (e) {
      console.warn('postChatPhotoToStory failed:', e);
      set({ storyCreateBusy: false });
      return { success: false };
    }
  }, [s.chatPhotoViewer, s.myOrganizerIds, s.user, s.storyCreateBusy, loadHomeStories]);

  // Task 4 (2026-09-22 follow-up) — "Share event to Story", Event Detail.
  // The ownership check is NOT done here — `create_event_share_story()`
  // (migration 068, SECURITY DEFINER) re-verifies the real
  // event -> organizer -> owner_id/user_id relationship server-side before
  // writing anything, exactly per this ticket's "do not trust an event id
  // passed from the client" instruction; `s.myOrgEventKeys` gating the
  // button's visibility (EventDetail.jsx) is a UI nicety, not the security
  // boundary.
  const createEventShareStory = useCallback(async (eventKey) => {
    if (!eventKey || s.storyCreateBusy) return { success: false };
    set({ storyCreateBusy: true });
    try {
      const { error } = await supabase.rpc('create_event_share_story', { p_event_id: eventKey });
      if (error) throw error;
      set({ storyCreateBusy: false });
      loadHomeStories();
      return { success: true };
    } catch (e) {
      console.warn('createEventShareStory failed:', e);
      set({ storyCreateBusy: false });
      return { success: false };
    }
  }, [s.storyCreateBusy, loadHomeStories]);

  // Location hierarchy — ONE tree for the area sheet, built from the same
  // browsable discovery set the old AreaSheet counted (static demo events
  // that aren't cancelled/ended/invite-only + real live public events), so
  // a node's count still matches what Home's feed actually shows for it.
  // Never built from (or applied to) this account's own tickets/bookings.
  const locationTree = useMemo(() => buildLocationTree([
    ...EVENTS.filter(e => !e.cancelled && e.endedHoursAgo == null && !e.inviteOnly),
    ...(s.discoveryEvents || []).filter(e => e.status === 'live' && e.visibility === 'public'),
  ]), [s.discoveryEvents]);
  // Same { key, label, match } shape every existing `curArea` consumer
  // already reads (Home header/empty-state, Home feed + weekend strip,
  // MapExplore) — `match` is the one shared "event is in the selected node
  // or any of its descendants" check, `label` a short header label.
  const curAreaKey = migrateLegacyAreaKey(s.area);
  const curArea = useMemo(() => ({
    key: curAreaKey,
    label: locationShortLabel(curAreaKey, s.lang),
    match: (e) => eventMatchesLocation(e, curAreaKey),
  }), [curAreaKey, s.lang]);

  // ---- organizer mode ----
  // Any account can host: organizer mode is a switch on the profile, so
  // sign-up and sign-in never have to know which "type" of account this is.
  const canHost = s.organizerMode || s.accountType === 'admin' || s.hasHosted;
  // TASK B (2026-10-03 fix pass) — root cause of "organizer mode appears on
  // by default and cannot be turned off": this used to also clear
  // `hasHosted: false` on every toggle-off. `hasHosted` is a real,
  // independently re-derived FACT ("does this account genuinely own an
  // organizer row") — re-queried on every syncUser() call regardless of
  // this toggle (see the `organizers` lookup a few hundred lines up), so
  // clobbering it here was always overwritten back to `true` on the very
  // next resync anyway. Combined with `toggleOrganizerMode` targeting
  // `!canHost` (eligibility) instead of `!organizerMode` (current
  // preference) below, a real host with `hasHosted: true` could never
  // toggle organizerMode back to `true` once it was `false` — `canHost`
  // stays `true` forever (hasHosted alone makes it true), so `!canHost` is
  // always `false`, and every tap just re-applied "off" to an already-off
  // preference. Fixed: `applyOrganizerMode` never touches `hasHosted` at
  // all — that field means "eligible to host," permanently true once
  // real, and organizerMode is a completely separate, freely-togglable
  // preference on top of it.
  const applyOrganizerMode = useCallback(async (enabled) => {
    // Account regression fix pass (2026-09-27), Item 3 — this used to
    // `return` here unconditionally for an admin, before ever calling the
    // RPC: no request, no error, just nothing happening — "the switch
    // looks stuck." Fixed at the root (set_organizer_mode, migration 103,
    // now writes a SEPARATE organizer_mode_enabled column for an admin
    // rather than refusing to touch anything), so an admin now goes
    // through the exact same call below as everyone else; only the
    // optimistic `accountType` write differs (never flips an admin away
    // from 'admin').
    // TASK 2 (2026-10-05 fix pass) — see toggleOrganizerMode's own comment:
    // the actual guard against a double-tap/double-click firing two
    // overlapping requests (both reading the same stale `s.organizerMode`
    // before the first one's optimistic flip has re-rendered), which could
    // let the SECOND response's rollback stomp the first call's already-
    // successful result and surface "Vui lòng thử lại" for a change that
    // had, in fact, already gone through.
    // BUG (2026-10-08 fix pass) — the actual, atomic re-entrancy guard is
    // the ref, checked-and-set synchronously right here, before any state
    // update — closes the exact gap `organizerModeBusyRef`'s own doc
    // comment (above) describes, and also covers item 4 (no duplicate
    // submissions from one tap): two rapid calls both reach this line
    // before either's own `set()` has re-rendered, but only the first
    // ever sees the ref still `false`.
    if (organizerModeBusyRef.current) return;
    organizerModeBusyRef.current = true;
    const wasAdmin = s.accountType === 'admin';
    const rollback = { organizerMode: s.organizerMode, accountType: s.accountType };
    console.info('[organizerMode] WRITE source=toggle-optimistic', { old: s.organizerMode, new: enabled });
    set({
      organizerMode: enabled,
      accountType: wasAdmin ? 'admin' : (enabled ? 'organizer' : 'participant'),
      mode: enabled ? 'host' : 'goer', organizerModeError: '', organizerModeBusy: true,
    });
    // BUG 2 (2026-10-06 fix pass) — full request/response trace, dev
    // console only, never the access token itself (just whether a session
    // exists) or any personal data — this ticket's own explicit ask for
    // "auth session, RPC name and parameters, PostgREST/SQL code/message,
    // returned business code, and subsequent profile refresh."
    const { data: sessionData } = await supabase.auth.getSession();
    console.info('[organizerMode] request', {
      hasSession: !!sessionData?.session,
      expiresAt: sessionData?.session?.expires_at ?? null,
      rpc: 'set_organizer_mode', params: { p_enabled: enabled },
    });
    const { data, error } = await supabase.rpc('set_organizer_mode', { p_enabled: enabled });
    console.info('[organizerMode] response', { data, error: error ? { code: error.code, message: error.message } : null });
    if (error) {
      // Rolling back in silence is what makes the switch look like it "turns
      // itself back off" — always say why it went back. TASK 2: logs the
      // structured PostgrestError fields (code/message/details/hint) the
      // supabase-js client already exposes, not just the object's default
      // string form — this is the one place a real device's actual failure
      // (not reproducible here) could otherwise never be diagnosed from.
      console.warn('Organizer mode update failed:', { code: error.code, message: error.message, details: error.details, hint: error.hint });
      const notMigrated = error.code === 'PGRST202';
      // A stale/expired access token is a known, actionable cause distinct
      // from a genuine server rejection — PostgREST surfaces it as PGRST301
      // (or a plain 401 on some paths). Every other code still gets the
      // generic string: this RPC has never been observed to raise anything
      // else, so claiming a more specific cause for those would be a guess.
      const sessionExpired = error.code === 'PGRST301' || error.code === '401';
      console.info('[organizerMode] WRITE source=toggle-rpc-rollback', { old: enabled, new: rollback.organizerMode });
      organizerModeBusyRef.current = false;
      return set({
        ...rollback,
        mode: rollback.organizerMode ? 'host' : 'goer',
        organizerModeBusy: false,
        organizerModeError: notMigrated
          ? T('Máy chủ chưa cài đặt chế độ tổ chức. Hãy chạy các migration Supabase còn thiếu.', 'Organizer mode is not installed on the server yet. Apply the pending Supabase migrations.')
          : sessionExpired
          ? T('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi thử lại.', 'Your session has expired. Please sign in again and retry.')
          : T('Không thể đổi chế độ tổ chức lúc này. Vui lòng thử lại.', 'We could not change organizer mode right now. Please try again.'),
      });
    }
    organizerModeBusyRef.current = false;
    if (data) {
      // set_organizer_mode (migration 103) now returns jsonb
      // { role, organizer_mode } instead of a bare role string — the only
      // way to represent "still admin, but host UI now off" at all.
      const confirmed = data.organizer_mode === true;
      console.info('[organizerMode] WRITE source=toggle-rpc-success', { old: enabled, new: confirmed, role: data.role });
      // Account extension (2026-09-27, Stage 1) — "back navigation if user
      // turns OFF while inside an organizer screen": the Tổ chức tab and
      // every host-only management screen are gone the instant this
      // resolves `confirmed: false`, so a user sitting inside one (or on
      // Account's own Tổ chức tab) needs to land somewhere real, not on a
      // now-unreachable screen. Cá nhân is always visible, so it's the one
      // safe landing spot. `hasHosted`/eligibility data is untouched —
      // this only ever redirects, never deletes anything.
      set(prev => ({
        accountType: data.role, organizerMode: confirmed, organizerModeError: '', organizerModeBusy: false,
        ...(!confirmed && HOST_ONLY_SCREENS.has(prev.screen) ? { screen: 'profile', accountTab: 'personal' } : {}),
        ...(!confirmed && prev.accountTab === 'host' ? { accountTab: 'personal' } : {}),
      }));
    } else {
      set({ organizerModeBusy: false });
    }
  }, [set, s.accountType, s.organizerMode, s.organizerModeBusy, T]);
  const enableOrganizerMode = useCallback(() => applyOrganizerMode(true), [applyOrganizerMode]);
  // TASK B — the actual toggle target is the CURRENT preference
  // (organizerMode), never eligibility (canHost) — see applyOrganizerMode's
  // own doc comment above for why using canHost here was the root cause of
  // "cannot be turned off/back on."
  const toggleOrganizerMode = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'profile' });
    if (s.organizerModeBusy || organizerModeBusyRef.current) return;
    applyOrganizerMode(!s.organizerMode);
  }, [set, s.user, s.organizerMode, s.organizerModeBusy, applyOrganizerMode]);
  const retryEnsureOrganizer = useEnsureOrganizer({ s, set, supabase, loadMyEvents });

  // ---- navigation ----
  const goHome = useCallback(() => set({ screen: 'home' }), [set]);
  const goMapExplore = useCallback(() => set({ screen: 'mapExplore' }), [set]);
  const backFromMapExplore = useCallback(() => set({ screen: 'home' }), [set]);
  // Plain setter, not map-specific logic — MapExplore.jsx owns deciding
  // *when* to save (right before its CTA navigates to Event Detail) and
  // when to clear (its own "← Đóng" wrapper), this just holds the snapshot
  // across the unmount/remount that switching `screen` away and back causes.
  const setMapExploreState = useCallback((snapshot) => set({ mapExploreState: snapshot }), [set]);

  // Home quick event search (2026-09-27) — reuses the EXISTING MapExplore
  // list/filter/event-detail experience (region/status filters, real
  // events already loaded there) rather than building a second search
  // index or screen — the only genuinely missing piece was a by-name text
  // filter (see MapExplore.jsx's own `searchQuery`). `focusSearch: true`
  // is read once at MapExplore's mount (the same one-shot `restoredRef`
  // pattern its own bug-2 snapshot restore already uses) to autofocus the
  // input immediately.
  const openEventSearch = useCallback(() => set({ screen: 'mapExplore', mapExploreState: { focusSearch: true } }), [set]);
  // "Open in Map" (Event Detail, home-entry only) — the reverse direction of
  // MapExplore.jsx's own openEventDetail(): that one snapshots the map's
  // live state right before leaving for Event Detail; this one builds a
  // snapshot FROM SCRATCH (there's no live MapExplore instance this
  // session necessarily) using just the event's own lat/lng, so the map
  // mounts already centered/zoomed on this pin with its info card showing
  // — reusing MapExplore's own restored-snapshot mechanism (`selectedId` +
  // `cameraCenter`/`cameraZoom`) rather than a second, parallel "open on
  // this event" code path. `0.01`-ish zoom feel matches `selectEvent`'s own
  // `zoomSpan`-equivalent (zoom 15.5) for a focused single-pin view.
  const openEventOnMap = useCallback((ev) => {
    // `singleEventFocus: true` — MapExplore.jsx's own doc comment on this
    // flag (Task 7, 2026-09-21 follow-up): the tight `cameraZoom: 15.5`
    // here is only meant for the visual camera, never for the bounds the
    // freshness poll loads `events` from.
    setMapExploreState({ cameraCenter: { lat: ev.lat, lng: ev.lng }, cameraZoom: 15.5, selectedId: ev.key, singleEventFocus: true });
    set({ screen: 'mapExplore' });
  }, [set, setMapExploreState]);
  const goProfile = useCallback(() => set({ screen: 'profile' }), [set]);
  const goInbox = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'inbox', authBackScreen: 'home' });
    // Reached from both Home (message icon) and Account ("Messages" row) —
    // remember whichever it was so the way back matches the way in, instead
    // of always landing on Home regardless of where the tap came from.
    set(prev => ({ screen: 'inbox', inboxBack: prev.screen === 'profile' ? 'profile' : 'home', inboxView: 'active' }));
    loadInboxThreads();
  }, [set, s.user, loadInboxThreads]);
  const backFromInbox = useCallback(() => set(prev => ({ screen: prev.inboxBack || 'home' })), [set]);
  // Event Detail is reached from several different sections (the home feed,
  // an organizer dashboard, an organizer profile, the create-event preview),
  // so remember whichever one we came from — its own back arrow used to be
  // hardcoded to Home, which is what made "back" feel like it always
  // returned to the very start regardless of where you'd drilled in from.
  // An organizer profile that was itself opened FROM an event (its back is
  // 'event') is a pass-through, exactly like "event" itself already is:
  // entering an event from it keeps whatever back target brought us into
  // this event/organizer cluster in the first place.
  //
  // Pointing back at the organizer profile instead is what trapped the two
  // screens in an inescapable loop (back when this was the separate
  // Organizer screen, and the same shape applies to the merged profile): the
  // profile's back re-opens whichever event is current, so event's back would
  // go to the profile, the profile's back would come straight back to the
  // same event, forever, with no way to reach Home. A profile reached from
  // anywhere else (Home, Pulse, a /org/<id> link, Dashboard) has its own real
  // back target, so there the event's back may safely point at the profile.
  const goEvent = useCallback((key) => set(prev => ({
    screen: 'event',
    eventKey: key,
    // A chat opened from this event ("Message host" -> "Details") also passes
    // through: its own back already returns to the event, so recording 'chat'
    // here made event <-> chat ping-pong forever.
    eventBackScreen: (prev.screen === 'event'
      || (prev.screen === 'organizerProfile' && prev.organizerProfileBack === 'event')
      || (prev.screen === 'chat' && !['inbox', 'notifications', 'paymentDetails'].includes(prev.chatBack)))
      ? prev.eventBackScreen
      : prev.screen,
    // A fresh, non-story-originated event open invalidates any pending
    // story-return snapshot/back-label — see goEventFromStory()'s own
    // comment. BUG 3 fix (2026-09-22 follow-up): also clears
    // `eventBackIsStory` — without this, opening a SECOND, ordinary event
    // (e.g. from Home) right after returning-but-not-yet-backing-out of a
    // story-opened one would incorrectly keep labelling/routing "back" as
    // if it still led to a story.
    eventBackIsStory: false,
    storyReturnSnapshot: null,
    storyReturnHostName: null,
  })), [set]);
  // BUG 3 fix (2026-09-22 follow-up) — real bug, confirmed by reading: the
  // back PILL always read `BACK_LABELS[eventBackScreen]` (EventDetail.jsx),
  // which for a story-opened event resolves to "banbe"/"Home" (whatever
  // `eventBackScreen` — really just "which screen was showing underneath
  // the story overlay" — happened to be), while tapping it actually
  // reopened StoryViewer (via the `storyReturnSnapshot` check below) —
  // visibly contradictory, exactly this ticket's own bug report. Fixed
  // with a dedicated `eventBackIsStory` flag (the "documentBack/
  // paymentDetailsBackTarget style" this ticket asks for) that both the
  // label AND the routing check below, so there's exactly one source of
  // truth for "this Event Detail's back target is a story" instead of
  // inferring it implicitly from whether a snapshot happens to be present.
  const backFromEvent = useCallback(() => set(prev => (
    prev.eventBackIsStory && prev.storyReturnSnapshot
      ? { screen: prev.eventBackScreen || 'home', storyViewer: prev.storyReturnSnapshot, storyReturnSnapshot: null, eventBackIsStory: false, storyReturnHostName: null }
      : { screen: prev.eventBackScreen || 'home', eventBackIsStory: false, storyReturnSnapshot: null, storyReturnHostName: null }
  )), [set]);
  // Task 4C / BUG 3 (2026-09-22 follow-up) — tapping an event-share story's
  // card/CTA. `screen` was never changed while the story overlay was up
  // (it renders independently of `screen` — see App.jsx), so `prev.screen`
  // here is already whichever screen the story was opened from
  // (Home/Profile), exactly the value goEvent()'s own eventBackScreen
  // logic already wants — reused verbatim rather than inventing a second
  // back-target concept. `storyReturnSnapshot` remembers the exact viewer
  // position (full deck + group/story index) so backFromEvent() above can
  // reopen it exactly where it was, not restarted; `storyReturnHostName`
  // is read by EventDetail.jsx's own back-label override so it can say
  // "Story"/the host's name instead of "banbe"/"Home".
  const goEventFromStory = useCallback((key) => set(prev => {
    const currentGroup = prev.storyViewer?.groups?.[prev.storyViewer.groupIndex];
    return {
      screen: 'event',
      eventKey: key,
      eventBackScreen: (prev.screen === 'event' || (prev.screen === 'organizerProfile' && prev.organizerProfileBack === 'event')) ? prev.eventBackScreen : prev.screen,
      eventBackIsStory: true,
      storyReturnSnapshot: prev.storyViewer,
      storyReturnHostName: currentGroup?.orgName || null,
      storyViewer: null,
    };
  }), [set]);
  const goReserve = useCallback(() => set(s.user ? { screen: 'reserve', attendeeDrafts: makeAttendeeDrafts(s.qty, s.user.name) } : { screen: 'login', authMode: 'login', authReturnScreen: 'reserve', authBackScreen: 'event' }), [set, s.user, s.qty]);
  const backToEvent = useCallback(() => set({ screen: 'event' }), [set]);
  const goLogin = useCallback(() => set({ screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'home' }), [set]);
  // `back` is only honored when it's really a screen name — several call
  // sites (ActionCenter's onOpenDashboard) wire this straight to an
  // onClick, which would otherwise hand it the click event instead.
  const goDashboard = useCallback((back) => set({ screen: 'dashboard', ...(typeof back === 'string' ? { dashboardBack: back } : {}) }), [set]);
  const goCreate = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'create', authBackScreen: 'hostIntro' });
    if (!canHost) enableOrganizerMode();
    // A fresh "create a new event" entry, distinct from goEditEvent's own
    // resubmission entry — always clears any prior edit target so this
    // never accidentally resubmits over a different event.
    // Stage 1 (2026-09-27 nav/discovery pass) — `createOriginScreen`
    // records EXACTLY which root screen/tab dock + was tapped from
    // (Home, Map, Inbox, Account, …), so createBack (below) can return
    // there instead of hard-routing to a fixed 'dashboard'/'hostIntro' —
    // that screen's own scroll/map-camera state is preserved for free by
    // App.jsx's existing per-screen `scrollPositions` keying, as long as
    // the screen key it returns to actually matches where the user was.
    // Stage 3 — never carry a previous session's confirmed coordinates
    // into an unrelated fresh event, even if `createLoc`'s TEXT happens to
    // still read the same from before this reset.
    // TASK 3 (event creation validation pass) — "Create another event"
    // (the post-submission chooser, CreateEvent.jsx) reuses this SAME
    // function, and unlike every previous caller (always arriving here
    // from a genuinely different screen), it can now fire while the
    // 'create' screen is ALREADY showing — no unmount, so nothing else
    // would otherwise clear the previous event's own name/description/
    // date/price/seats/included items/intro/keywords. Reset all of them
    // here, not just the address/edit-id fields this already cleared, so
    // "Create another" truly starts blank rather than pre-filled with the
    // event that was just submitted.
    set(prev => ({
      screen: 'create', mode: 'host', createEditEventId: null, createSent: false, createError: '', createOriginScreen: prev.screen,
      createName: '', createCats: [], createDesc: '',
      createLoc: '', createLat: null, createLng: null, createLocLabel: '', createLocConfirmed: false,
      createAddressLine: '', createDistrict: '', createCity: '', createPostalCode: '',
      createCountryCode: '', createStateProvince: '', createNeighborhood: '',
      createAddressSuggestions: [], createAddressSearching: false, createAddressSearchError: '',
      createEventDate: '', createEventTime: '', createPrice: '', createSeats: '',
      createIncludedItems: [], createIntro: '', createKeywords: '', createChatGreeting: '', createChatGreetingEn: '', createVisibility: 'public',
      createCriteria: everyoneCriteria(), createCriteriaLoaded: everyoneCriteria(), createCriteriaLoad: 'ready', createCriteriaRetryEventId: null,
    }));
  }, [set, s.user, canHost, enableOrganizerMode]);
  const openHeld = useCallback(() => set({ screen: 'confirmed' }), [set]);
  const goHostIntro = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'hostIntro', authBackScreen: 'profile' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'hostIntro' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  // Stage 1 fix — this used to hard-route to 'dashboard'/'hostIntro'
  // regardless of where + was actually tapped from (Home, Map, Inbox,
  // Account, …), so backing out of Create always landed on Dashboard
  // instead of the real originating tab. `createOriginScreen` (set by
  // goCreate/goEditEvent) is now the real source of truth; the old
  // hasHosted-based guess only remains as a fallback for any entry point
  // that predates this field.
  const createBack = useCallback(() => set(prev => ({ screen: prev.createOriginScreen || (prev.hasHosted ? 'dashboard' : 'hostIntro') })), [set]);

  // The "Going"/"Saved" cards on Account — always opened from (and closed
  // back to) Account, so unlike Inbox/Dashboard there's no other entry point
  // to remember.
  // The heading of whichever list is showing. Shared so the back pill on an
  // event opened from one can name it too — before this existed that pill
  // fell through to its "banbe" default and claimed it went Home, while
  // actually (and correctly) returning to the list.
  const eventListTitle = useMemo(() => ({
    going: T('Đang tham gia', 'Going'),
    saved: T('Đã lưu', 'Saved'),
    completed: T('Sự kiện đã hoàn thành', 'Completed events'),
  }[s.eventListMode] || T('Đang tham gia', 'Going')), [s.eventListMode, T]);

  // Re-fetches on every open, not just once at sign-in: this is the one
  // place a guest actually looks to check what they're still holding a
  // ticket for, and nothing else invalidates `attending` in between (no
  // realtime subscription, no polling — same "nothing pushes to this
  // client" situation as the dispute chat's own 4s poll, see
  // DisputeChatPanel.jsx). Without this, a dispute resolved against the
  // guest by an admin in a different session/tab never clears their
  // already-open app's "Going" list until they reload the whole page.
  const goGoingList = useCallback(() => {
    set({ screen: 'eventList', eventListMode: 'going' });
    if (s.user?.id) loadMyEvents(s.user.id);
  }, [set, s.user?.id, loadMyEvents]);
  const goSavedList = useCallback(() => set({ screen: 'eventList', eventListMode: 'saved' }), [set]);
  const goCompletedList = useCallback(() => set({ screen: 'eventList', eventListMode: 'completed' }), [set]);
  const backFromEventList = useCallback(() => set({ screen: 'profile' }), [set]);

  // ---- roles ----
  // Reached from both Home's "Your host page" link and Account's "Hosting"
  // card — `back` says which one so the dashboard's back arrow returns
  // there instead of always landing on Home.
  const switchToHost = useCallback((back = 'home') => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'dashboard', authBackScreen: 'home' });
    if (!canHost) enableOrganizerMode();
    set({ mode: 'host', screen: 'dashboard', dashboardBack: back });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const backFromDashboard = useCallback(() => set(prev => ({ screen: prev.dashboardBack || 'home' })), [set]);
  const switchToGoer = useCallback(() => set({ mode: 'goer', screen: 'home' }), [set]);
  const becomeHost = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'hostIntro', authBackScreen: 'profile' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'hostIntro' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const logout = useCallback(async () => {
    await supabase.auth.signOut();
    try { navigator.serviceWorker?.controller?.postMessage('banbe-clear-storage-cache'); } catch { /* no SW — nothing cached */ }
    // Roles belong to the account that just left; leaving them behind would
    // leak the previous user's hosting state into the next sign-in. Lands
    // on Login, not Home — Task 1: no guest browsing after signing out.
    // Stage 1 (retention roadmap P0) — belt-and-suspenders alongside
    // syncUser's own `!user` branch (the auth listener that clears
    // `favorites`/favoritesUidRef): sets it here too so the very next
    // render, before that listener has necessarily fired, never shows this
    // account's saves.
    favoritesUidRef.current = null;
    set({
      user: null, accountType: 'participant', organizerMode: false, hasHosted: false, mode: 'goer',
      screen: 'login', authMode: 'login', authMandatory: true, authReturnScreen: 'home', authBackScreen: 'home',
      // TASK 4 (Reserve→edit-name pass) — same belt-and-suspenders spirit
      // as authReturnScreen/authBackScreen above.
      editNameReturnScreen: 'profile',
      // TASK 5 (Account badges pass) — admin-only cache; a non-admin (or
      // the next account signing in) must never see a stale prior count.
      pendingEventsCount: 0,
      referralCode: null, orgRegName: '', favorites: [],
      homeSurveyDiscoveryExpanded: false,
      // TASK A point 8 — every refund-related cache belongs to the account
      // that just left; leaving it in state risks the next sign-in (on the
      // same device/session, without a full page reload) briefly rendering
      // the PREVIOUS user's queues/destinations/claims before its own first
      // load completes.
      refundCenterClaims: [], refundCenterSelected: [], refundQueue: [], refundDestinations: [],
      myRefunds: [], paymentRefundClaim: null, attendanceGuests: [],
    });
  }, [set]);
  // (Defined after `logout` — a const used in a deps array before its
  // declaration is a TDZ crash that blanks the whole app.)
  // "Decline" on the policy gate: no consent is recorded; the session is signed out
  // and the flag cleared so the next ordinary read of the policy isn't a gate.
  const declinePolicyGate = useCallback(async () => {
    set({ policyGateActive: false });
    await logout();
  }, [set, logout]);

  // ---- display name ----
  // TASK 4 (Reserve→edit-name pass) — captures the CALLER's screen (e.g.
  // 'reserve', still holding its own event id/qty/hold state — none of
  // that is touched by this flow, it's global BanBeContext state) so
  // save/back return to wherever this was actually opened from, not
  // always 'profile'. Account.jsx's own "Đổi tên" entry still returns to
  // Account because `s.screen` there IS 'profile' when this runs. Mirrors
  // the existing authReturnScreen/authBackScreen pattern.
  const goEditName = useCallback(() => set({ screen: 'editName', editNameReturnScreen: s.screen, editNameValue: s.user?.name || '', editNameError: '' }), [set, s.screen, s.user?.name]);
  const editNameType = useCallback((e) => set({ editNameValue: e.target.value }), [set]);
  const saveDisplayName = useCallback(async () => {
    const newName = s.editNameValue.trim();
    if (!newName) return set({ editNameError: T('Hãy nhập tên hiển thị.', 'Please enter a display name.') });
    if (newName === s.user?.name) return set({ screen: s.editNameReturnScreen });

    set({ editNameSaving: true, editNameError: '' });
    const oldName = s.user?.name || '';
    const { data, error } = await supabase.rpc('rename_display_name', { p_new_name: newName });
    if (error) {
      set({ editNameSaving: false, editNameError: T('Không thể đổi tên lúc này. Vui lòng thử lại.', 'We could not change your name right now. Please try again.') });
      return;
    }
    set({ editNameSaving: false, user: { ...s.user, name: data?.new_name || newName }, screen: s.editNameReturnScreen });

    // The in-app notification rows are already written by the RPC above —
    // this only dispatches the email side, and re-derives its own recipient
    // list server-side rather than trusting anything from this client.
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: 'name_change', oldName, newName: data?.new_name || newName }),
        }).catch(() => {});
      }
    } catch { /* best-effort email dispatch; the in-app notification already landed */ }
  }, [set, s.editNameValue, s.editNameReturnScreen, s.user, T]);

  // ---- TASK D (2026-10-01 UX foundation pass) — shareable profile card ----
  const openEditProfile = useCallback(() => set({
    screen: 'editProfile',
    editProfileHandle: s.user?.handle || '', editProfileName: s.user?.name || '',
    editProfileBio: s.user?.bio || '', editProfileCity: s.user?.city || '',
    editProfileInterests: (s.user?.interests || []).join(', '), editProfileTheme: s.user?.profileTheme || 'default',
    editProfileIntroLong: s.user?.introLong || '', editProfileLinks: s.user?.socialLinks || [], editProfileLinksOpen: false,
    editProfileError: '', editProfileBusy: false,
  }), [set, s.user]);
  const backFromEditProfile = useCallback(() => set({ screen: 'profile' }), [set]);

  const editProfileIntroLongType = useCallback((e) => set({ editProfileIntroLong: e.target.value }), [set]);
  const toggleEditProfileLinksOpen = useCallback(() => set(prev => ({ editProfileLinksOpen: !prev.editProfileLinksOpen })), [set]);
  const addEditProfileLink = useCallback(() => set(prev => ({
    editProfileLinks: [...prev.editProfileLinks, { platform: 'website', url: '' }],
  })), [set]);
  const setEditProfileLink = useCallback((index, field, value) => set(prev => ({
    editProfileLinks: prev.editProfileLinks.map((l, i) => i === index ? { ...l, [field]: value } : l),
  })), [set]);
  const removeEditProfileLink = useCallback((index) => set(prev => ({
    editProfileLinks: prev.editProfileLinks.filter((_, i) => i !== index),
  })), [set]);

  const saveProfileFields = useCallback(async (avatarUrlOverride) => {
    set({ editProfileBusy: true, editProfileError: '' });
    const interests = s.editProfileInterests.split(',').map(x => x.trim()).filter(Boolean);
    const links = s.editProfileLinks.filter(l => l.url.trim());
    const { data, error } = await supabase.rpc('save_profile', {
      p_handle: s.editProfileHandle, p_display_name: s.editProfileName, p_bio: s.editProfileBio,
      p_city: s.editProfileCity, p_interests: interests, p_theme: s.editProfileTheme,
      p_avatar_url: avatarUrlOverride ?? null,
      p_intro_long: s.editProfileIntroLong, p_social_links: links,
    });
    if (error || data?.success === false) {
      const code = data?.error;
      set({
        editProfileBusy: false,
        editProfileError: code === 'HANDLE_TAKEN' ? T('Tên người dùng này đã có người dùng.', 'That handle is already taken.')
          : code === 'INVALID_HANDLE' ? T('Tên người dùng chỉ gồm chữ thường, số, dấu gạch dưới (3-24 ký tự).', 'Handle must be lowercase letters/numbers/underscore, 3-24 characters.')
          : code === 'INVALID_NAME' ? T('Vui lòng nhập tên hiển thị.', 'Please enter a display name.')
          : code === 'INTRO_TOO_LONG' ? T('Giới thiệu quá dài (tối đa 4000 ký tự).', 'Intro is too long (4000 characters max).')
          : code === 'INVALID_LINKS' ? T('Một liên kết không hợp lệ. Chỉ chấp nhận đường dẫn https://.', 'One of the links is invalid. Only https:// links are accepted.')
          : T('Không thể lưu lúc này. Vui lòng thử lại.', 'Could not save right now. Please try again.'),
      });
      return false;
    }
    set(prev => ({
      editProfileBusy: false, screen: 'profile',
      user: {
        ...prev.user, name: s.editProfileName, handle: data.handle, bio: s.editProfileBio, city: s.editProfileCity,
        interests, profileTheme: s.editProfileTheme, avatarUrl: avatarUrlOverride ?? prev.user?.avatarUrl,
        introLong: s.editProfileIntroLong, socialLinks: links,
      },
    }));
    return true;
  }, [set, s.editProfileHandle, s.editProfileName, s.editProfileBio, s.editProfileCity, s.editProfileInterests, s.editProfileTheme, s.editProfileIntroLong, s.editProfileLinks, T]);

  /** Owner-only avatar upload — validated client-side (type/size) before
   * ever reaching Storage; the bucket's own RLS (avatars_owner_write,
   * migration 079) additionally enforces the path is under this user's own
   * id, so even a bypassed client check can't write anywhere else. */
  const uploadAvatar = useCallback(async (file) => {
    if (!s.user?.id) return null;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      set({ editProfileError: T('Ảnh phải là JPEG, PNG hoặc WebP.', 'Image must be JPEG, PNG, or WebP.') });
      return null;
    }
    if (file.size > 5 * 1024 * 1024) {
      set({ editProfileError: T('Ảnh tối đa 5MB.', 'Image must be under 5MB.') });
      return null;
    }
    set({ editProfileBusy: true, editProfileError: '' });
    let blob = file, ext = (file.name.split('.').pop() || 'jpg').toLowerCase(), contentType = file.type;
    try {
      const normalized = await normalizeImageForUpload(file, AVATAR_UPLOAD_BUDGET);
      ({ blob, ext, contentType } = normalized);
    } catch {
      // CONVERT_FAILED — upload the original rather than block the user.
    }
    const path = `${s.user.id}/${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from('avatars').upload(path, blob, { upsert: true, contentType, cacheControl: '31536000' });
    if (error) {
      console.warn('uploadAvatar failed:', error);
      set({ editProfileBusy: false, editProfileError: T('Không thể tải ảnh lên. Vui lòng thử lại.', 'Could not upload the image. Please try again.') });
      return null;
    }
    const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
    set({ editProfileBusy: false });
    return pub?.publicUrl || null;
  }, [set, s.user?.id, T]);

  const removeAvatar = useCallback(async () => {
    await saveProfileFields('');
  }, [saveProfileFields]);

  /** STAGE C (2026-09-25) — the real "add a photo to one of my own events"
   * flow this app never had: same upload shape as `uploadAvatar` above
   * (client-side type/size guard, then Storage, then a table row), but the
   * table row is what actually matters here — `event_photos_insert_own`
   * (migration 001) is the real enforcement, checking THIS event's
   * organizer is owned by the caller, not merely that the caller owns
   * *some* organizer (all `event_photos_host_insert`, the bucket policy,
   * checks) — so this can't be pointed at an event this account doesn't
   * own even though the bucket policy alone wouldn't have stopped it.
   * Deliberately callable for an event of ANY status (draft/live/ended/
   * cancelled) — Task 1's own "ended must stay in the library" rule
   * implies a host should be able to add a recap photo to an event after
   * it's over, not just while it's live. */
  const uploadEventPhoto = useCallback(async (eventId, file) => {
    if (!s.user?.id) return false;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      set({ eventPhotoUploadError: T('Ảnh phải là JPEG, PNG hoặc WebP.', 'Image must be JPEG, PNG, or WebP.') });
      return false;
    }
    if (file.size > 50 * 1024 * 1024) { // the bucket's own limit, migration 005
      set({ eventPhotoUploadError: T('Ảnh tối đa 50MB.', 'Image must be under 50MB.') });
      return false;
    }
    set(prev => ({ eventPhotoUploadBusy: { ...prev.eventPhotoUploadBusy, [eventId]: true }, eventPhotoUploadError: '' }));
    // Strict invite-only events (migration 113) — same bucket-routing
    // decision as reconcileEventMedia; a recap photo added to an
    // invite-only event after the fact must not land in the public bucket.
    const bucketId = s.realEventsById[eventId]?.visibility === 'invite' ? 'event-photos-private' : 'event-photos';
    // R2 media API first; `provider:'supabase'` (flag off / ineligible / any init failure) falls through to the legacy path below.
    try {
      const viaApi = await tryMediaApiUpload({ kind: 'event_photo', eventId, file, sortOrder: 0 });
      if (viaApi.provider === 'r2') {
        set(prev => ({
          eventPhotoUploadBusy: { ...prev.eventPhotoUploadBusy, [eventId]: false },
          eventPhotoUploaded: { ...prev.eventPhotoUploaded, [eventId]: true },
        }));
        setTimeout(() => set(prev => ({ eventPhotoUploaded: { ...prev.eventPhotoUploaded, [eventId]: false } })), 1800);
        return true;
      }
    } catch (err) {
      console.warn('uploadEventPhoto media api failed after upload:', err?.code || 'error');
      set(prev => ({ eventPhotoUploadBusy: { ...prev.eventPhotoUploadBusy, [eventId]: false }, eventPhotoUploadError: T('Không thể lưu ảnh. Vui lòng thử lại.', 'Could not save the photo. Please try again.') }));
      return false;
    }
    let blob = file, ext = (file.name.split('.').pop() || 'jpg').toLowerCase(), contentType = file.type;
    try {
      const normalized = await normalizeImageForUpload(file, EVENT_PHOTO_UPLOAD_BUDGET);
      ({ blob, ext, contentType } = normalized);
    } catch {
      // CONVERT_FAILED — upload the original rather than block the host.
    }
    const path = `${eventId}/${Date.now()}.${ext}`;
    const { error: upErr } = await supabase.storage.from(bucketId).upload(path, blob, { upsert: true, contentType, cacheControl: '31536000' });
    if (upErr) {
      console.warn('uploadEventPhoto storage failed:', upErr);
      set(prev => ({ eventPhotoUploadBusy: { ...prev.eventPhotoUploadBusy, [eventId]: false }, eventPhotoUploadError: T('Không thể tải ảnh lên. Vui lòng thử lại.', 'Could not upload the image. Please try again.') }));
      return false;
    }
    // Same "bucket name baked into storage_path" convention the original
    // seed rows already use (event_photos.storage_path, migration 010) —
    // every read path (eventPhotoUrl/organizerPhotoUrl/etc.) already
    // strips this prefix defensively either way.
    const { error: rowErr } = await supabase.from('event_photos').insert({ event_id: eventId, storage_path: `${bucketId}/${path}`, sort_order: 0 });
    if (rowErr) {
      console.warn('uploadEventPhoto row failed:', rowErr);
      set(prev => ({ eventPhotoUploadBusy: { ...prev.eventPhotoUploadBusy, [eventId]: false }, eventPhotoUploadError: T('Không thể lưu ảnh. Vui lòng thử lại.', 'Could not save the photo. Please try again.') }));
      return false;
    }
    set(prev => ({
      eventPhotoUploadBusy: { ...prev.eventPhotoUploadBusy, [eventId]: false },
      eventPhotoUploaded: { ...prev.eventPhotoUploaded, [eventId]: true },
    }));
    setTimeout(() => set(prev => ({ eventPhotoUploaded: { ...prev.eventPhotoUploaded, [eventId]: false } })), 1800);
    return true;
  }, [set, s.user?.id, s.realEventsById, T]);

  /** Personal public profile screen — reachable by handle, works for a
   * signed-out visitor too (get_public_profile() is granted to anon,
   * migration 079). Personal-only (2026-09-27 hierarchy pass): never
   * shows an organizer edit/guest-preview affordance any more — the
   * organizer's own public page is `openOrganizerProfile` below. */
  const openPublicProfile = useCallback(async (handle, back = 'profile') => {
    set({ screen: 'publicProfile', publicProfile: null, publicProfileLoading: true, publicProfileError: '', publicProfileBack: back, publicProfileHandle: handle });
    const { data, error } = await supabase.rpc('get_public_profile', { p_handle: handle });
    if (error || data?.success === false) {
      set({ publicProfileLoading: false, publicProfileError: T('Không tìm thấy hồ sơ này.', "This profile couldn't be found.") });
      return;
    }
    set({ publicProfile: data, publicProfileLoading: false });
  }, [set, T]);
  const backFromPublicProfile = useCallback(() => set(prev => ({ screen: prev.publicProfileBack || 'profile' })), [set]);

  /** The organizer's own, separate public profile — reachable by
   * organizer_id (never the owner's personal handle), so a shared
   * /org/<id> link resolves without exposing or requiring any personal
   * profile field. Fetches only the core stats (get_organizer_profile);
   * the upcoming-events/photos "extras" are fetched by
   * loadOrganizerProfileExtras below, called from the screen's own mount
   * effect regardless of entry path (in-app nav or a deep link). */
  const openOrganizerProfile = useCallback(async (organizerId, back = 'profile') => {
    if (!organizerId) return;
    set({
      screen: 'organizerProfile', organizerProfile: null, organizerProfileLoading: true, organizerProfileError: '',
      organizerProfileBack: back, organizerProfileId: organizerId, organizerProfileExtrasLoadedFor: '', arrivedFromSharedLink: false,
    });
    const { data, error } = await supabase.rpc('get_organizer_profile', { p_organizer_id: organizerId });
    if (error || data?.success === false) {
      set({ organizerProfileLoading: false, organizerProfileError: T('Không tìm thấy tổ chức này.', "This organizer couldn't be found.") });
      return;
    }
    set({ organizerProfile: data, organizerProfileLoading: false });
  }, [set, T]);
  const backFromOrganizerProfile = useCallback(() => set(prev => ({ screen: prev.organizerProfileBack || 'profile' })), [set]);
  /** Live "track record" for an event's host (EventDetail's Track record row):
   * events published (live/ended) and the year of their first one, straight
   * from get_organizer_profile — never the catalogue's baked-in numbers.
   * Cached per event key in `eventOrgStats` ({ count, sinceYear } or null). */
  const loadEventOrgStats = useCallback(async (key) => {
    if (!key || key in s.eventOrgStats) return;
    let organizerId = s.realEventsById[key]?.organizerId;
    if (!organizerId) {
      const { data } = await supabase.from('events').select('organizer_id').eq('id', key).maybeSingle();
      organizerId = data?.organizer_id;
    }
    let stats = null;
    if (organizerId) {
      const { data } = await supabase.rpc('get_organizer_profile', { p_organizer_id: organizerId });
      if (data && data.success !== false) stats = { count: Number(data.event_count) || 0, sinceYear: data.hosting_since_year || null };
    }
    set(prev => ({ eventOrgStats: { ...prev.eventOrgStats, [key]: stats } }));
  }, [set, s.eventOrgStats, s.realEventsById]);

  /** Merged host profile — "Visit <host>" on Event Detail (and any other
   * place that only knows an event key). Resolves the organizer id from the
   * canonical realEventsById cache when present, otherwise from the
   * `events` row itself (covers the seeded demo-catalogue events too, which
   * carry no organizer id client-side). Unresolvable => stay put with a
   * toast rather than opening a broken profile. */
  const openOrganizerOfEvent = useCallback(async (key, back = 'event') => {
    const eventKey = key || s.eventKey;
    let organizerId = s.realEventsById[eventKey]?.organizerId;
    if (!organizerId) {
      const { data } = await supabase.from('events').select('organizer_id').eq('id', eventKey).maybeSingle();
      organizerId = data?.organizer_id;
    }
    if (!organizerId) { pushToast({ title: T('Không tìm thấy trang của người tổ chức', "Couldn't find this host's page"), body: '' }); return; }
    openOrganizerProfile(organizerId, back);
  }, [s.eventKey, s.realEventsById, openOrganizerProfile, pushToast, T]);

  // ==================== Interest surveys (Slice B) ====================
  const SURVEY_DRAFT_PREFIX = 'banbe.surveyDraft.';
  function loadSurveyDraftFromStorage(publicId) {
    try {
      const raw = sessionStorage.getItem(SURVEY_DRAFT_PREFIX + publicId);
      return raw ? JSON.parse(raw) : null;
    } catch { return null; }
  }
  function saveSurveyDraftToStorage(publicId, draft) {
    try { sessionStorage.setItem(SURVEY_DRAFT_PREFIX + publicId, JSON.stringify(draft)); } catch { /* private browsing, etc. */ }
  }
  function clearSurveyDraftFromStorage(publicId) {
    try { sessionStorage.removeItem(SURVEY_DRAFT_PREFIX + publicId); } catch { /* private browsing, etc. */ }
  }
  const DEFAULT_SURVEY_DRAFT = { interestLevel: null, dateOptions: [], groupSize: null, locationOptions: [], budgetOption: null, activities: [], freeText: '', contactConsent: false };

  /** In-app navigation to the same screen the dedicated browser route
   * (/surveys/<publicId>) uses — one screen, one backend, per the task's
   * own "reuse... using the SAME response backend" instruction (used by
   * the host's own preview and, later, a story's "Answer Survey" CTA). */
  const goSurveyPublic = useCallback(async (publicId, back = 'home', returnTab) => {
    set({
      ...(returnTab ? { surveysHostingReturnTab: returnTab } : {}),
      screen: 'surveyPublic', surveyPublic: null, surveyPublicLoading: true, surveyPublicError: '',
      surveyPublicBack: back, surveyPublicId: publicId,
      surveyDraft: loadSurveyDraftFromStorage(publicId) || DEFAULT_SURVEY_DRAFT,
      surveyResponseSuccess: false, surveyResponseError: '', surveyEditMode: false, surveyAsModal: false,
      surveyRespondStep: 'idle', surveyRespondEmail: '', surveyRespondCode: '', surveyRespondError: '', surveyRespondConsent: false,
    });
    const { data, error } = await supabase.rpc('get_survey_public', { p_public_id: publicId });
    if (error || data?.success === false) {
      set({ surveyPublicLoading: false, surveyPublicError: T('Không tìm thấy khảo sát này.', "This survey couldn't be found.") });
      return;
    }
    set({ surveyPublic: data, surveyPublicLoading: false });
  }, [set, T]);
  const backFromSurveyPublic = useCallback(() => set(prev => ({ screen: prev.surveyPublicBack || 'home' })), [set]);
  /** A signed-out visitor tapping submit — same authReturnScreen pattern
   * every other "this needs an account" action already uses (goReserve,
   * etc.), returning to THIS screen (surveyPublicId/surveyDraft are
   * untouched by the trip through Login, so nothing is lost). */
  const promptLoginForSurvey = useCallback(() => set({ screen: 'login', authMode: 'login', authReturnScreen: 'surveyPublic', authBackScreen: 'surveyPublic' }), [set]);
  // A fresh entry always starts on Active; only the back-from-Preview path
  // (which never goes through here) restores the remembered tab.
  const goSurveysHosting = useCallback(() => set({ screen: 'surveysHosting', surveysHostingReturnTab: null }), [set]);

  /** The signed-in respondent's own existing answer, if any — loaded
   * separately from get_survey_public (anon-reachable, must never carry
   * one respondent's data) once we know who's signed in. Pre-fills the
   * draft so re-opening an already-answered survey shows the real answer,
   * not a blank form. */
  const loadMySurveyResponse = useCallback(async (surveyId) => {
    if (!surveyId || !s.user?.id) return;
    set({ mySurveyResponseLoading: true });
    const { data, error } = await supabase
      .from('survey_responses').select('*')
      .eq('survey_id', surveyId).eq('respondent_id', s.user.id).maybeSingle();
    if (error) { set({ mySurveyResponseLoading: false }); return; }
    set(prev => ({
      mySurveyResponse: data || null, mySurveyResponseLoading: false,
      surveyDraft: data ? {
        interestLevel: data.interest_level, dateOptions: data.date_options || [], groupSize: data.group_size,
        locationOptions: data.location_options || [], budgetOption: data.budget_option, activities: data.activities || [],
        freeText: data.free_text || '', contactConsent: data.contact_consent || false,
      } : prev.surveyDraft,
    }));
  }, [set, s.user?.id]);

  const updateSurveyDraft = useCallback((patch) => set(prev => {
    const next = { ...prev.surveyDraft, ...patch };
    if (prev.surveyPublicId) saveSurveyDraftToStorage(prev.surveyPublicId, next);
    return { surveyDraft: next };
  }), [set]);

  /** The one submission path both the in-app screen and the dedicated
   * browser page call — server (submit_survey_response, migration 114) is
   * the real validation/closure gate, this is just the UI-facing wrapper.
   * Requires a signed-in identity; the screen itself is what prompts
   * sign-in first (this app has no anonymous-write path anywhere). */
  const submitSurveyResponseAction = useCallback(async () => {
    if (!s.surveyPublic?.survey_id) return;
    set({ surveyResponseSubmitting: true, surveyResponseError: '' });
    const d = s.surveyDraft;
    const { error } = await supabase.rpc('submit_survey_response', {
      p_survey_id: s.surveyPublic.survey_id,
      p_interest_level: d.interestLevel,
      p_date_options: d.dateOptions,
      p_group_size: d.groupSize,
      p_location_options: d.locationOptions,
      p_budget_option: d.budgetOption,
      p_activities: d.activities,
      p_free_text: d.freeText,
      p_contact_consent: d.contactConsent,
    });
    if (error) {
      const message = {
        NOT_AUTHENTICATED: T('Bạn cần đăng nhập để trả lời.', 'You need to sign in to respond.'),
        SURVEY_NOT_ACTIVE: T('Khảo sát này hiện không mở.', 'This survey isn’t open right now.'),
        SURVEY_CLOSED: T('Khảo sát này đã đóng.', 'This survey has closed.'),
        SURVEY_NOT_OPEN_YET: T('Khảo sát này chưa mở.', 'This survey hasn’t opened yet.'),
        DATE_OPTIONS_REQUIRED: T('Vui lòng chọn ít nhất một ngày.', 'Please pick at least one date.'),
        LOCATION_OPTIONS_REQUIRED: T('Vui lòng chọn ít nhất một địa điểm.', 'Please pick at least one location.'),
        BUDGET_REQUIRED: T('Vui lòng chọn mức ngân sách.', 'Please pick a budget range.'),
        ACTIVITIES_REQUIRED: T('Vui lòng chọn ít nhất một hoạt động.', 'Please pick at least one activity.'),
        GROUP_SIZE_REQUIRED: T('Vui lòng nhập số người.', 'Please enter a group size.'),
        INVALID_GROUP_SIZE: T('Số người không hợp lệ.', 'That group size isn’t valid.'),
        INTEREST_LEVEL_REQUIRED: T('Vui lòng chọn mức độ quan tâm.', 'Please pick an interest level.'),
      }[error.message] || T('Không thể gửi câu trả lời. Vui lòng thử lại.', 'Could not submit your response. Please try again.');
      set({ surveyResponseSubmitting: false, surveyResponseError: message });
      return;
    }
    clearSurveyDraftFromStorage(s.surveyPublicId);
    set({ surveyResponseSubmitting: false, surveyResponseSuccess: true });
  }, [set, s.surveyPublic, s.surveyDraft, s.surveyPublicId, T]);

  const toggleSurveyEditMode = useCallback((on) => set({ surveyEditMode: on }), [set]);

  /** Section 2 — open the same SurveyPublic content as a modal over the
   * current screen (a paused story) instead of navigating to it — the
   * story's "Answer Survey" CTA. Deliberately does NOT touch `state.screen`
   * (so Home/StoryViewer stay mounted underneath); StoryViewer.jsx pauses
   * on its own by watching `storySurveyModalPublicId`. */
  const openSurveyStoryModal = useCallback(async (publicId) => {
    set({
      surveyAsModal: true, storySurveyModalPublicId: publicId,
      surveyPublic: null, surveyPublicLoading: true, surveyPublicError: '', surveyPublicId: publicId,
      surveyDraft: loadSurveyDraftFromStorage(publicId) || DEFAULT_SURVEY_DRAFT,
      surveyResponseSuccess: false, surveyResponseError: '', surveyEditMode: false,
      surveyRespondStep: 'idle', surveyRespondEmail: '', surveyRespondCode: '', surveyRespondError: '', surveyRespondConsent: false,
    });
    const { data, error } = await supabase.rpc('get_survey_public', { p_public_id: publicId });
    if (error || data?.success === false) {
      set({ surveyPublicLoading: false, surveyPublicError: T('Không tìm thấy khảo sát này.', "This survey couldn't be found.") });
      return;
    }
    set({ surveyPublic: data, surveyPublicLoading: false });
  }, [set, T]);

  /** Closing the modal: if there are real unsent changes (a dirty draft, no
   * success yet), the caller (SurveyResponseModal.jsx) asks keep-vs-discard
   * first — this is the actual close, called either directly (nothing to
   * lose) or after that choice is made. `discard` clears the sessionStorage
   * draft too, so reopening the same survey from the same story doesn't
   * resurface answers the respondent explicitly threw away. */
  const closeSurveyStoryModal = useCallback((discard = false) => {
    if (discard && s.surveyPublicId) clearSurveyDraftFromStorage(s.surveyPublicId);
    set({ surveyAsModal: false, storySurveyModalPublicId: null, surveyPublic: null });
  }, [set, s.surveyPublicId]);

  // ---- Section 3: lightweight respondent email verification (outside
  // banbe, no password/profile/Hosting onboarding) ----
  const SURVEY_EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  /** Step 1 — request the code. Does NOT yet know (or claim) whether this
   * creates a new identity; the server resolves that and tells us via
   * `isNewAccount` so the NEXT screen (entering the code) can disclose it
   * honestly before the respondent confirms anything — task's own "disclose
   * accurately before confirmation, never call it anonymous" rule. Requires
   * `surveyRespondConsent` first (shown alongside the email field) — this
   * IS the explicit, additive consent path for a respondent who never saw
   * the ordinary Login/signup screen's own checkbox. */
  const sendSurveyRespondCode = useCallback(async (email) => {
    const clean = String(email || '').trim().toLowerCase();
    if (!SURVEY_EMAIL_RE.test(clean)) return set({ surveyRespondError: T('Nhập email hợp lệ.', 'Enter a valid email.') });
    if (!s.surveyRespondConsent) return set({ surveyRespondError: T('Vui lòng đồng ý trước khi tiếp tục.', 'Please agree before continuing.') });
    set({ surveyRespondSending: true, surveyRespondError: '' });
    try {
      const result = await requestAuthEmail({
        email: clean, mode: 'respond',
        displayName: T('Khách trả lời khảo sát', 'Survey respondent'),
      });
      set({
        surveyRespondSending: false, surveyRespondStep: 'codeSent',
        surveyRespondEmail: clean, surveyRespondIsNewAccount: Boolean(result?.isNewAccount),
      });
    } catch (e) {
      set({
        surveyRespondSending: false,
        surveyRespondError: e?.code === 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED'
          ? T('Không thể gửi email lúc này. Vui lòng thử lại sau.', 'Could not send email right now. Please try again later.')
          : T('Không thể gửi mã. Vui lòng thử lại.', 'Could not send the code. Please try again.'),
      });
    }
  }, [set, s.surveyRespondConsent, T]);

  /** Step 2 — verify. `type` mirrors verifyEmailCode's own isSignup branch:
   * a brand-new identity was created via the 'signup' linkType server-side
   * (see api/auth's isRespondMode branch), so it verifies the same way;
   * `onAuthStateChange` picks up the resulting real session exactly like
   * any other sign-in, and submit_survey_response then resolves identity
   * from that session's own auth.uid() — never a client-supplied id. */
  const verifySurveyRespondCode = useCallback(async () => {
    const email = s.surveyRespondEmail;
    const token = s.surveyRespondCode.trim();
    if (!token) return set({ surveyRespondError: T('Nhập mã đã gửi tới email của bạn.', 'Enter the code sent to your email.') });
    set({ surveyRespondSending: true, surveyRespondError: '' });
    const { error } = await supabase.auth.verifyOtp({ email, token, type: s.surveyRespondIsNewAccount ? 'signup' : 'email' });
    if (error) {
      set({ surveyRespondSending: false, surveyRespondError: T('Mã không đúng hoặc đã hết hạn.', 'That code is wrong or has expired.') });
      return;
    }
    set({ surveyRespondSending: false, surveyRespondStep: 'idle', surveyRespondCode: '' });
  }, [set, s.surveyRespondEmail, s.surveyRespondCode, s.surveyRespondIsNewAccount, T]);

  // ---- Host management: Hosting -> Surveys & Event Ideas ----
  const loadMySurveys = useCallback(async () => {
    if (!s.myOrganizerId) return;
    set({ mySurveysLoading: true });
    const { data, error } = await supabase
      .from('surveys').select('*').eq('organizer_id', s.myOrganizerId).order('created_at', { ascending: false });
    set({ mySurveys: error ? [] : (data || []), mySurveysLoading: false });
  }, [set, s.myOrganizerId]);

  const createSurveyAction = useCallback(async (input) => {
    if (!s.myOrganizerId) return null;
    set({ mySurveyCreateBusy: true, mySurveyCreateError: '' });
    const { data, error } = await supabase.rpc('create_survey', {
      p_organizer_id: s.myOrganizerId,
      p_title: input.title, p_description: input.description || '',
      p_opens_at: input.opensAt, p_closes_at: input.closesAt,
      p_timezone: 'Asia/Ho_Chi_Minh', p_config: input.config,
    });
    if (error) {
      set({ mySurveyCreateBusy: false, mySurveyCreateError: {
        TITLE_REQUIRED: T('Vui lòng nhập tiêu đề.', 'Please enter a title.'),
        INVALID_WINDOW: T('Hạn chót phải sau thời điểm mở.', 'The deadline must be after the opening time.'),
      }[error.message] || T('Không thể tạo khảo sát. Vui lòng thử lại.', 'Could not create the survey. Please try again.') });
      return null;
    }
    set({ mySurveyCreateBusy: false });
    await loadMySurveys();
    return data;
  }, [set, s.myOrganizerId, T, loadMySurveys]);

  const publishSurveyAction = useCallback(async (surveyId) => {
    const { error } = await supabase.rpc('publish_survey', { p_survey_id: surveyId });
    if (!error) await loadMySurveys();
    return !error;
  }, [loadMySurveys]);
  const closeSurveyAction = useCallback(async (surveyId) => {
    const { error } = await supabase.rpc('close_survey', { p_survey_id: surveyId });
    if (!error) await loadMySurveys();
    return !error;
  }, [loadMySurveys]);
  const archiveSurveyAction = useCallback(async (surveyId) => {
    const { error } = await supabase.rpc('archive_survey', { p_survey_id: surveyId });
    if (!error) await loadMySurveys();
    return !error;
  }, [loadMySurveys]);
  /** Draft-only (migration 116) — a published survey may already have real
   * respondent answers; archive_survey is the correct action once a
   * survey has ever been live, not delete. */
  const deleteSurveyAction = useCallback(async (surveyId) => {
    const { error } = await supabase.rpc('delete_survey', { p_survey_id: surveyId });
    if (!error) await loadMySurveys();
    return !error;
  }, [loadMySurveys]);

  /** Slice C — candidate drafts for the host's closed/archived surveys.
   * Read straight from survey_event_candidates (host/admin RLS); the
   * scoring itself runs server-side when a survey closes (migration 143). */
  const loadSurveyCandidates = useCallback(async () => {
    const ids = (s.mySurveys || []).filter(sv => sv.status === 'closed' || sv.status === 'archived').map(sv => sv.id);
    if (!ids.length) { set({ mySurveyCandidates: [], mySurveyCandidatesLoading: false, mySurveyCandidatesError: '' }); return; }
    set({ mySurveyCandidatesLoading: true, mySurveyCandidatesError: '' });
    const { data, error } = await supabase
      .from('survey_event_candidates').select('*').in('survey_id', ids)
      .order('score', { ascending: false });
    set({
      mySurveyCandidates: error ? [] : (data || []), mySurveyCandidatesLoading: false,
      mySurveyCandidatesError: error ? T('Không thể tải gợi ý sự kiện.', 'Could not load suggested event drafts.') : '',
    });
  }, [set, s.mySurveys, T]);

  const refreshSurveyCandidatesAction = useCallback(async (surveyId) => {
    set({ mySurveyCandidatesBusySurveyId: surveyId });
    const { error } = await supabase.rpc('generate_survey_candidates', { p_survey_id: surveyId });
    set({ mySurveyCandidatesBusySurveyId: null });
    if (error) { set({ mySurveyCandidatesError: T('Không thể làm mới gợi ý.', 'Could not refresh suggestions.') }); return false; }
    await loadSurveyCandidates();
    return true;
  }, [set, T, loadSurveyCandidates]);

  const dismissSurveyCandidateAction = useCallback(async (candidateId) => {
    const { error } = await supabase.rpc('set_survey_candidate_status', { p_candidate_id: candidateId, p_status: 'dismissed' });
    if (!error) set(prev => ({ mySurveyCandidates: prev.mySurveyCandidates.map(c => c.id === candidateId ? { ...c, status: 'dismissed' } : c) }));
    return !error;
  }, [set]);

  /** Dismissed drafts stay in the list (hidden behind "Show dismissed") so
   * a mis-tap is never permanent. */
  const restoreSurveyCandidateAction = useCallback(async (candidateId) => {
    const { error } = await supabase.rpc('set_survey_candidate_status', { p_candidate_id: candidateId, p_status: 'suggested' });
    if (!error) set(prev => ({ mySurveyCandidates: prev.mySurveyCandidates.map(c => c.id === candidateId ? { ...c, status: 'suggested' } : c) }));
    return !error;
  }, [set]);

  /** Dismiss / restore many drafts at once (dismiss selected, dismiss all). */
  const setSurveyCandidatesStatusAction = useCallback(async (ids, status) => {
    if (!ids.length) return true;
    const { error } = await supabase.rpc('set_survey_candidates_status', { p_candidate_ids: ids, p_status: status });
    if (!error) set(prev => ({ mySurveyCandidates: prev.mySurveyCandidates.map(c => ids.includes(c.id) ? { ...c, status } : c) }));
    return !error;
  }, [set]);

  /** Closed surveys -> Archived (one, several or all) and back. */
  const archiveSurveysAction = useCallback(async (ids) => {
    if (!ids.length) return true;
    const { error } = await supabase.rpc('archive_surveys', { p_survey_ids: ids });
    if (!error) await loadMySurveys();
    return !error;
  }, [loadMySurveys]);
  /** Permanent: archived surveys only (server enforces), cascades to the
   * survey's responses, ideas and story shares. Callers confirm first. */
  const deleteArchivedSurveysAction = useCallback(async (ids) => {
    if (!ids.length) return true;
    const { error } = await supabase.rpc('delete_archived_surveys', { p_survey_ids: ids });
    if (!error) {
      set(prev => ({ mySurveyCandidates: prev.mySurveyCandidates.filter(c => !ids.includes(c.survey_id)) }));
      await loadMySurveys();
    }
    return !error;
  }, [set, loadMySurveys]);
  /** Permanent: only ideas already in Archived ('used'). */
  const deleteSurveyCandidatesAction = useCallback(async (ids) => {
    if (!ids.length) return true;
    const { error } = await supabase.rpc('delete_survey_candidates', { p_candidate_ids: ids });
    if (!error) set(prev => ({ mySurveyCandidates: prev.mySurveyCandidates.filter(c => !ids.includes(c.id)) }));
    return !error;
  }, [set]);
  const unarchiveSurveyAction = useCallback(async (surveyId) => {
    const { error } = await supabase.rpc('unarchive_survey', { p_survey_id: surveyId });
    if (!error) await loadMySurveys();
    return !error;
  }, [loadMySurveys]);

  /** "Use This Idea" -> Create Event, pre-filled. Date options are the
   * host's own free-text labels ("Saturday evening"), not parseable
   * dates, and the location is a label, not a confirmed address — so
   * those go into the description as hints and the host still picks the
   * real date and confirms the real address; nothing is auto-submitted. */
  const applySurveyCandidateAction = useCallback(async (candidate, survey) => {
    const hints = [
      candidate.date_label && !candidate.date_value && `${T('Thời gian được quan tâm nhất', 'Most-wanted time')}: ${candidate.date_label}`,
      candidate.location_label && `${T('Khu vực', 'Area')}: ${candidate.location_label}`,
      candidate.budget_label && `${T('Ngân sách phổ biến', 'Common budget')}: ${candidate.budget_label}`,
      (candidate.activity_labels || []).length > 0 && `${T('Hoạt động', 'Activities')}: ${candidate.activity_labels.join(', ')}`,
    ].filter(Boolean).join('\n');
    goCreate();
    set({
      createName: survey?.title || '',
      createDesc: [survey?.description, hints].filter(Boolean).join('\n\n'),
      createLoc: candidate.location_label || '',
      // A location picked with the address search carries the full
      // structured address, so Create Event opens with it already
      // confirmed (same fields selectCreateAddressSuggestion sets).
      ...(candidate.location_data?.lat != null && candidate.location_data?.lng != null ? {
        createAddressLine: candidate.location_data.address_line || '', createDistrict: candidate.location_data.district || '',
        createCity: candidate.location_data.city || '', createPostalCode: candidate.location_data.postal_code || '',
        createCountryCode: candidate.location_data.country_code || '', createStateProvince: candidate.location_data.state_province || '',
        createNeighborhood: candidate.location_data.neighborhood || '',
        createLat: candidate.location_data.lat, createLng: candidate.location_data.lng,
        createLocLabel: candidate.location_label || '', createLocConfirmed: true,
      } : {}),
      // Structured slot picked by the host when building the survey — same
      // 'yyyy-MM-dd' / 'HH:mm' shapes the Create Event inputs use.
      ...(candidate.date_value ? { createEventDate: candidate.date_value } : {}),
      ...(candidate.time_value ? { createEventTime: candidate.time_value } : {}),
      createSeats: candidate.suggested_group_size ? String(candidate.suggested_group_size) : '',
      createKeywords: (candidate.activity_labels || []).join(', '),
    });
    await supabase.rpc('set_survey_candidate_status', { p_candidate_id: candidate.id, p_status: 'used' });
    set(prev => ({ mySurveyCandidates: prev.mySurveyCandidates.map(c => c.id === candidate.id ? { ...c, status: 'used' } : c) }));
  }, [set, T, goCreate]);

  /** Task 4 — "Share Link": native share sheet with a clipboard fallback,
   * same shape as shareOrganizerProfile below, but through the canonical
   * surveyPublicUrl() builder (the actual verified Vercel origin, never
   * banbe.app) since this link must genuinely resolve. */
  const shareSurveyLinkAction = useCallback(async (survey) => {
    const url = surveyPublicUrl(survey.public_id);
    try {
      if (navigator.share) { await navigator.share({ title: survey.title, url }); return; }
    } catch { /* user cancelled the native sheet — not an error */ }
    try {
      await navigator.clipboard.writeText(url);
      set({ mySurveyShareCopiedId: survey.id });
      setTimeout(() => set(prev => (prev.mySurveyShareCopiedId === survey.id ? { mySurveyShareCopiedId: null } : {})), 1800);
    } catch { /* clipboard unavailable — link already rendered as copyable text */ }
  }, [set]);

  /** Task 4 — "Share To Story": opens a preview, never posts automatically.
   * `surveyShareToStoryTarget` holds the survey the confirm sheet is
   * previewing; the actual story row is only created on explicit confirm. */
  const openShareToStoryConfirm = useCallback((survey) => set({ surveyShareToStoryTarget: survey, surveyShareToStoryError: '' }), [set]);
  const closeShareToStoryConfirm = useCallback(() => set({ surveyShareToStoryTarget: null, surveyShareToStoryError: '' }), [set]);
  const confirmShareSurveyToStory = useCallback(async () => {
    const survey = s.surveyShareToStoryTarget;
    if (!survey) return;
    set({ surveyShareToStoryBusy: true, surveyShareToStoryError: '' });
    const { error } = await supabase.rpc('create_survey_share_story', { p_survey_id: survey.id });
    if (error) {
      set({
        surveyShareToStoryBusy: false,
        surveyShareToStoryError: error.message === 'SURVEY_NOT_ACTIVE'
          ? T('Chỉ khảo sát đang mở mới có thể chia sẻ lên story.', 'Only an active survey can be shared to a story.')
          : T('Không thể đăng lên story. Vui lòng thử lại.', 'Could not post to story. Please try again.'),
      });
      return;
    }
    set({ surveyShareToStoryBusy: false, surveyShareToStoryTarget: null });
    await loadHomeStories();
  }, [set, s.surveyShareToStoryTarget, T, loadHomeStories]);

  /** Small preview content for the organizer public profile — real
   * upcoming events (published, soonest first), never invented. (The photo
   * library is loaded separately by loadOrganizerPhotos — the same grid the
   * retired Organizer screen showed.) Guarded on
   * `organizerProfileExtrasLoadedFor` so returning to an already-loaded
   * organizer (e.g. Back then forward again) doesn't re-fetch. */
  const loadOrganizerProfileExtras = useCallback(async (organizerId) => {
    if (!organizerId || s.organizerProfileExtrasLoadedFor === organizerId) return;
    set({ organizerProfileExtrasLoadedFor: organizerId });
    const { data: eventRows } = await withR2Columns(withR2 => supabase.from('events').select(realEventColumns(withR2)).eq('organizer_id', organizerId).eq('status', 'live').order('starts_at', { ascending: true }).limit(5));
    const rows = eventRows || [];
    const photoUrlByEvent = await firstPhotoUrlByEvent(rows.map(r => r.id));
    const upcoming = rows.map(r => shapeRealEvent(r, { photoUrl: photoUrlByEvent[r.id] }));
    set({ organizerProfileUpcoming: upcoming });
  }, [set, s.organizerProfileExtrasLoadedFor]);

  /** Native share sheet with a clipboard-copy fallback — same pattern as
   * sharePublicProfile, a separate organizer-specific URL (never
   * /u/<handle>) so this can't be mistaken for the owner's personal link. */
  const shareOrganizerProfile = useCallback(async (organizerId, name) => {
    const url = `https://banbe.app/org/${organizerId}`;
    const title = T('Trang tổ chức banbe của ' + (name || ''), (name || '') + '’s banbe organizer page');
    try {
      if (navigator.share) {
        await navigator.share({ title, url });
        return;
      }
    } catch { /* user cancelled the native sheet — not an error */ }
    try {
      await navigator.clipboard.writeText(url);
      set({ profileLinkCopiedFlash: true });
      setTimeout(() => set({ profileLinkCopiedFlash: false }), 2200);
    } catch { /* clipboard unavailable — nothing more to do */ }
  }, [set, T]);

  const toggleFollowOrganizer = useCallback(async (organizerId) => {
    if (!s.user?.id || !organizerId) return;
    const wasFollowing = !!(
      (s.publicProfile?.organizer?.id === organizerId && s.publicProfile.organizer.following)
      || (s.organizerProfile?.id === organizerId && s.organizerProfile.following)
    );
    // Optimistic — this is a plain, instantly-reversible social toggle
    // (unlike refund/payment state), reconciled by the real table write
    // below; reverted on failure. Bumps WHICHEVER of the two screens
    // (personal profile's merged organizer summary, or the organizer's
    // own standalone page) currently holds this organizer id — never both
    // unconditionally, since only one is ever the actual match.
    const bump = (sign) => (prev) => ({
      ...(prev.publicProfile?.organizer?.id === organizerId ? {
        publicProfile: { ...prev.publicProfile, organizer: { ...prev.publicProfile.organizer, following: sign > 0, follower_count: prev.publicProfile.organizer.follower_count + sign } },
      } : {}),
      ...(prev.organizerProfile?.id === organizerId ? {
        organizerProfile: { ...prev.organizerProfile, following: sign > 0, follower_count: prev.organizerProfile.follower_count + sign },
      } : {}),
    });
    set(bump(wasFollowing ? -1 : 1));
    const { error } = wasFollowing
      ? await supabase.from('follows').delete().eq('user_id', s.user.id).eq('organizer_id', organizerId)
      : await supabase.from('follows').insert({ user_id: s.user.id, organizer_id: organizerId });
    if (error) {
      console.warn('toggleFollowOrganizer failed:', error);
      set(bump(wasFollowing ? 1 : -1));
    }
  }, [set, s.user?.id, s.publicProfile, s.organizerProfile]);

  // ---- Account extension (2026-09-27, Stage 3) — KPI reports ----
  // One RPC (get_account_kpis, migration 097) serves the on-screen cards,
  // CSV, PDF and JSON export alike — reusing the SAME fetched payload for
  // all four, per the ticket's own "reuse one metrics payload" rule, so a
  // number on screen can never disagree with the same number in an export.
  const reportsRangeBounds = (rangeDays, customStart, customEnd) => {
    const now = new Date();
    if (rangeDays === 'custom' && customStart && customEnd) {
      return { start: new Date(customStart + 'T00:00:00'), end: new Date(customEnd + 'T23:59:59') };
    }
    const days = Number(rangeDays) || 30;
    return { start: new Date(now.getTime() - days * 86400000), end: now };
  };

  /** The one real fetch — takes scope/organizerId/range EXPLICITLY rather
   * than reading them back off `s` right after a `set()` that just changed
   * them (a stale-closure trap: `s` here is still the PREVIOUS render's
   * value until React commits) — same reason `openOrganizerProfile` takes
   * `organizerId` as a parameter instead of reading `s.organizerProfileId`
   * right after setting it. */
  const fetchAccountKpis = useCallback(async (scope, organizerId, rangeDays, customStart, customEnd) => {
    const { start, end } = reportsRangeBounds(rangeDays, customStart, customEnd);
    set({ reportsLoading: true, reportsError: '' });
    const { data, error } = await supabase.rpc('get_account_kpis', {
      p_scope: scope, p_start: start.toISOString(), p_end: end.toISOString(),
      p_organizer_id: scope === 'host' ? organizerId : null,
    });
    if (error || data?.success === false) {
      console.warn('fetchAccountKpis failed:', error || data);
      return set({
        reportsLoading: false, reportsData: null,
        reportsError: T('Không thể tải số liệu lúc này. Vui lòng thử lại.', "Couldn't load these numbers right now. Please try again."),
      });
    }
    set({ reportsLoading: false, reportsData: data, reportsError: '' });
  }, [set, T]);

  // Re-fetches with whatever scope/organizer/range are ALREADY committed in
  // state — safe here (unlike openReports below) because every caller of
  // this one (range-change, retry) runs on its own render, after the state
  // it reads was already set by a previous one.
  const loadAccountKpis = useCallback(() => {
    fetchAccountKpis(s.reportsScope, s.reportsOrganizerId, s.reportsRangeDays, s.reportsCustomStart, s.reportsCustomEnd);
  }, [fetchAccountKpis, s.reportsScope, s.reportsOrganizerId, s.reportsRangeDays, s.reportsCustomStart, s.reportsCustomEnd]);

  // Opening this from Cá nhân/Admin needs no organizer id; opening it from
  // Tổ chức always passes the account's real organizer_id — never guessed,
  // matching the prior ticket's own "never silently substitute the first
  // org" rule for a multi-organizer account.
  const openReports = useCallback((scope, organizerId, back = 'profile') => {
    set({
      screen: 'reports', reportsScope: scope, reportsOrganizerId: organizerId || '', reportsBack: back,
      reportsData: null, reportsError: '', reportsExpanded: new Set(),
    });
    fetchAccountKpis(scope, organizerId, s.reportsRangeDays, s.reportsCustomStart, s.reportsCustomEnd);
  }, [set, fetchAccountKpis, s.reportsRangeDays, s.reportsCustomStart, s.reportsCustomEnd]);
  const backFromReports = useCallback(() => set(prev => ({ screen: prev.reportsBack || 'profile' })), [set]);

  const setReportsRangeDays = useCallback((days) => {
    set({ reportsRangeDays: days });
    fetchAccountKpis(s.reportsScope, s.reportsOrganizerId, days, s.reportsCustomStart, s.reportsCustomEnd);
  }, [set, fetchAccountKpis, s.reportsScope, s.reportsOrganizerId, s.reportsCustomStart, s.reportsCustomEnd]);
  const setReportsCustomRange = useCallback((startStr, endStr) => {
    set({ reportsRangeDays: 'custom', reportsCustomStart: startStr, reportsCustomEnd: endStr });
    fetchAccountKpis(s.reportsScope, s.reportsOrganizerId, 'custom', startStr, endStr);
  }, [set, fetchAccountKpis, s.reportsScope, s.reportsOrganizerId]);

  const toggleReportCard = useCallback((key) => set(prev => {
    const next = new Set(prev.reportsExpanded);
    next.has(key) ? next.delete(key) : next.add(key);
    return { reportsExpanded: next };
  }), [set]);
  const expandAllReportCards = useCallback(() => set(prev => ({
    reportsExpanded: new Set((prev.reportsData?.metrics || []).map(m => m.key)),
  })), [set]);
  const collapseAllReportCards = useCallback(() => set({ reportsExpanded: new Set() }), [set]);

  // Spreadsheet-injection guard: Excel/Sheets treats a cell starting with
  // =, +, -, @, tab or CR as a FORMULA — a hostile event/organizer name
  // ("=cmd|...") could otherwise execute when the host opens their own
  // export. Prefixing with a bare `'` neutralizes it in every spreadsheet
  // app while staying invisible in a plain text viewer.
  const csvCell = (value) => {
    let str = value == null ? '' : String(value);
    if (/^[=+\-@\t\r]/.test(str)) str = `'${str}`;
    if (/[",\n]/.test(str)) str = `"${str.replace(/"/g, '""')}"`;
    return str;
  };
  const downloadTextFile = (filename, content, mime) => {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  };

  /** One metric card's own `rows` table as a real CSV — UTF-8 (BOM so Excel
   * on Windows/macOS reads Vietnamese diacritics correctly), one row per
   * underlying record, never a second, re-derived set of numbers. */
  const exportReportCardCsv = useCallback((metricKey) => {
    const metric = (s.reportsData?.metrics || []).find(m => m.key === metricKey);
    if (!metric) return;
    const rows = metric.rows || [];
    const columns = rows.length ? Object.keys(rows[0]) : ['value'];
    const lines = [columns.join(',')];
    if (rows.length) {
      for (const row of rows) lines.push(columns.map(c => csvCell(row[c])).join(','));
    } else {
      lines.push(csvCell(metric.value));
    }
    downloadTextFile(`banbe-${metricKey}.csv`, '﻿' + lines.join('\r\n'), 'text/csv;charset=utf-8');
  }, [s.reportsData]);

  const exportReportsJson = useCallback(() => {
    if (!s.reportsData) return;
    const payload = {
      schema_version: 1,
      role: s.reportsData.scope,
      range: s.reportsData.range,
      generated_at: new Date().toISOString(),
      metrics: s.reportsData.metrics,
    };
    downloadTextFile(`banbe-report-${s.reportsData.scope}.json`, JSON.stringify(payload, null, 2), 'application/json');
  }, [s.reportsData]);

  /** Client-side (jsPDF) — deliberately not a backend render (unlike
   * invoice/receipt PDFs, api/*-email.js's puppeteer path): this is one
   * user's own small, on-demand report, not a document another party
   * relies on receiving unattended. Reuses the SAME fetched metrics —
   * never a second query — so it can't disagree with the on-screen cards. */
  const exportReportsPdf = useCallback(async () => {
    if (!s.reportsData) return;
    set({ reportsExportBusy: 'pdf' });
    try {
      const { jsPDF } = await import('jspdf');
      const doc = new jsPDF({ unit: 'pt', format: 'a4' });
      const marginX = 40;
      let y = 50;
      try {
        const img = await new Promise((resolve, reject) => {
          const im = new Image();
          im.crossOrigin = 'anonymous';
          im.onload = () => resolve(im);
          im.onerror = reject;
          im.src = '/banbe-wordmark.png';
        });
        doc.addImage(img, 'PNG', marginX, y, 63, (63 * img.height) / img.width);
      } catch { /* logo optional — the report itself still generates without it */ }
      y += 50;
      doc.setFontSize(16);
      const roleLabel = { personal: T('Cá nhân', 'Personal'), host: T('Tổ chức', 'Host'), admin: T('Quản trị', 'Admin') }[s.reportsData.scope] || s.reportsData.scope;
      doc.text(T(`Báo cáo số liệu (${roleLabel})`, `KPI report (${roleLabel})`), marginX, y);
      y += 20;
      doc.setFontSize(10);
      const fmt = (iso) => new Date(iso).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });
      doc.text(`${T('Khoảng thời gian', 'Range')}: ${fmt(s.reportsData.range.start)} - ${fmt(s.reportsData.range.end)}`, marginX, y);
      y += 14;
      doc.text(`${T('Tạo lúc', 'Generated')}: ${new Date().toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}`, marginX, y);
      y += 24;
      for (const metric of s.reportsData.metrics) {
        if (y > 760) { doc.addPage(); y = 50; }
        doc.setFontSize(12);
        doc.text(metricLabel(metric, T), marginX, y);
        doc.setFontSize(11);
        const displayValue = metric.unit === 'vnd' ? `${Number(metric.value).toLocaleString('vi-VN')} đ` : String(metric.value);
        doc.text(displayValue, 400, y);
        y += 16;
        doc.setFontSize(8);
        doc.setTextColor(120);
        doc.text(T('Nguồn: get_account_kpis, dữ liệu thực trên máy chủ', 'Source: get_account_kpis, real server data'), marginX, y);
        doc.setTextColor(0);
        y += 18;
      }
      doc.save(`banbe-report-${s.reportsData.scope}.pdf`);
    } catch (e) {
      console.warn('exportReportsPdf failed:', e);
      set({ reportsError: T('Không thể tạo PDF lúc này.', "Couldn't generate the PDF right now.") });
    } finally {
      set({ reportsExportBusy: '' });
    }
  }, [s.reportsData, set, T]);

  // ---- Organizer Team pass (2026-09-27, Stage 1) ----
  // organizer_members (migration 098) — see that file's own doc comment
  // for the full privacy model. Nothing here infers membership from
  // follows/bookings/check-ins; every row is a real, explicit invite.

  /** This account's OWN pending invites + accepted memberships — a plain
   * RLS-backed select (organizer_members_select_own), not an RPC; the
   * table's own RLS already restricts this to rows where user_id = self.
   * Joins the organizer's real name/avatar for display (organizers is
   * publicly readable already). */
  const loadMyOrganizerMemberships = useCallback(async () => {
    if (!s.user?.id) return;
    const { data, error } = await supabase
      .from('organizer_members')
      .select('id, organizer_id, status, public_role, public_visible, joined_at, organizers(name, avatar_path)')
      .eq('user_id', s.user.id)
      .in('status', ['invited', 'accepted'])
      .order('invited_at', { ascending: false });
    if (error) { console.warn('loadMyOrganizerMemberships failed:', error); return; }
    const rows = data || [];
    set({
      myOrganizerInvites: rows.filter(r => r.status === 'invited'),
      myTeamMemberships: rows.filter(r => r.status === 'accepted'),
    });
  }, [set, s.user?.id]);

  const respondToOrganizerInvite = useCallback(async (membershipId, accept) => {
    const { data, error } = await supabase.rpc('respond_to_organizer_invite', { p_membership_id: membershipId, p_accept: accept });
    if (error || data?.success === false) { console.warn('respondToOrganizerInvite failed:', error || data); return false; }
    await loadMyOrganizerMemberships();
    return true;
  }, [loadMyOrganizerMemberships]);

  /** The member's OWN switch — optimistic, reconciled by the real RPC
   * result; this is the ONLY path that can ever turn public_visible on. */
  const setOrganizerMemberVisibility = useCallback(async (membershipId, visible) => {
    set(prev => ({ myTeamMemberships: prev.myTeamMemberships.map(m => m.id === membershipId ? { ...m, public_visible: visible } : m) }));
    const { data, error } = await supabase.rpc('set_organizer_member_visibility', { p_membership_id: membershipId, p_visible: visible });
    if (error || data?.success === false) {
      console.warn('setOrganizerMemberVisibility failed:', error || data);
      set(prev => ({ myTeamMemberships: prev.myTeamMemberships.map(m => m.id === membershipId ? { ...m, public_visible: !visible } : m) }));
    }
  }, [set]);

  // ---- Admin Team pass (2026-10-02, migration 121) ----
  // See that migration's own doc comment for the full RBAC model:
  // `role = 'admin'` and `can_manage_admins = true` are two different
  // things, checked separately server-side in every RPC below — this
  // client code never assumes/derives either, only ever reflects what the
  // server already decided.

  /** This account's OWN pending admin invite, if any — a plain RLS-backed
   * select (admin_invites_select_own), reachable regardless of current
   * role (the whole point: the invitee isn't an admin yet). */
  const loadMyAdminInvite = useCallback(async () => {
    if (!s.user?.id) return;
    const { data, error } = await supabase
      .from('admin_invites')
      .select('id, status, created_at, expires_at')
      .eq('invited_user_id', s.user.id)
      .eq('status', 'pending')
      .maybeSingle();
    if (error) { console.warn('loadMyAdminInvite failed:', error); return; }
    set({ myAdminInvite: data || null });
  }, [set, s.user?.id]);

  const respondToAdminInvite = useCallback(async (inviteId, accept) => {
    const { data, error } = await supabase.rpc('respond_to_admin_invite', { p_invite_id: inviteId, p_accept: accept });
    if (error || data?.success === false) { console.warn('respondToAdminInvite failed:', error || data); return false; }
    set({ myAdminInvite: null });
    // Accepting changes this account's own role server-side — patch the
    // client's cached copy immediately (a direct, targeted re-read, same
    // "don't just hide a tab until next login" requirement this
    // migration's own revoke_admin()/admin_access_revoked path also
    // honors below) rather than waiting for the next sign-in/token-refresh
    // cycle to pick up the new role.
    if (accept && s.user?.id) {
      const { data: profile } = await supabase.from('profiles').select('role, can_manage_admins').eq('id', s.user.id).maybeSingle();
      if (profile) set({ accountType: profile.role, canManageAdmins: profile.can_manage_admins === true });
    }
    return true;
  }, [set, s.user]);

  /** Manage-admins-capable admin only — both lists come back empty/denied
   * under RLS for anyone else; this is a convenience fetch, not the real
   * security boundary. */
  const loadAdminTeam = useCallback(async () => {
    if (!s.user?.id) return;
    set({ adminTeamLoading: true });
    const [{ data: roster, error: rosterError }, { data: invites, error: invitesError }] = await Promise.all([
      supabase.rpc('list_admin_roster'),
      supabase.from('admin_invites').select('id, invited_email, status, created_at, expires_at').order('created_at', { ascending: false }),
    ]);
    if (rosterError) console.warn('list_admin_roster failed:', rosterError);
    if (invitesError) console.warn('loadAdminTeam invites failed:', invitesError);
    set({ adminRoster: roster || [], adminInvites: invites || [], adminTeamLoading: false });
  }, [set, s.user?.id]);

  const setAdminInviteEmailDraft = useCallback((e) => set({ adminInviteEmailDraft: e.target.value, adminInviteError: '' }), [set]);

  // Explicit confirmation of the intended recipient before anything is
  // sent — opens a plain inline confirm (same lightweight pattern
  // Dashboard.jsx's withdraw-submission row already uses), never sends on
  // one tap.
  const requestAdminInviteConfirm = useCallback(() => {
    const email = s.adminInviteEmailDraft.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { set({ adminInviteError: T('Email không hợp lệ.', 'Invalid email address.') }); return; }
    set({ adminInviteConfirmEmail: email });
  }, [set, s.adminInviteEmailDraft, T]);
  const cancelAdminInviteConfirm = useCallback(() => set({ adminInviteConfirmEmail: null }), [set]);

  const ADMIN_INVITE_ERROR_MESSAGES = {
    NOT_AUTHORIZED: T('Bạn không có quyền mời quản trị viên.', "You don't have permission to invite admins."),
    INVALID_EMAIL: T('Email không hợp lệ.', 'Invalid email address.'),
    ALREADY_ADMIN: T('Tài khoản này đã là quản trị viên.', 'That account is already an admin.'),
    ALREADY_INVITED_PENDING: T('Đã có lời mời đang chờ cho email này.', 'There is already a pending invite for this email.'),
  };
  const confirmAdminInvite = useCallback(async () => {
    const email = s.adminInviteConfirmEmail;
    if (!email) return;
    set({ adminInviteBusy: true, adminInviteError: '' });
    const { data, error } = await supabase.rpc('create_admin_invite', { p_email: email });
    set({ adminInviteBusy: false, adminInviteConfirmEmail: null });
    if (error || data?.success === false) {
      const code = data?.error;
      set({ adminInviteError: ADMIN_INVITE_ERROR_MESSAGES[code] || T('Không gửi được lời mời.', 'Could not send the invite.') });
      return;
    }
    set({ adminInviteEmailDraft: '' });
    await loadAdminTeam();
  }, [set, s.adminInviteConfirmEmail, loadAdminTeam, T]);

  const requestRevokeAdminInviteConfirm = useCallback((id) => set({ revokeAdminInviteConfirmId: id }), [set]);
  const cancelRevokeAdminInviteConfirm = useCallback(() => set({ revokeAdminInviteConfirmId: null }), [set]);
  const confirmRevokeAdminInvite = useCallback(async () => {
    const id = s.revokeAdminInviteConfirmId;
    if (!id) return;
    const { data, error } = await supabase.rpc('revoke_admin_invite', { p_invite_id: id });
    set({ revokeAdminInviteConfirmId: null });
    if (error || data?.success === false) { console.warn('revoke_admin_invite failed:', error || data); return; }
    await loadAdminTeam();
  }, [set, s.revokeAdminInviteConfirmId, loadAdminTeam]);

  const requestRevokeAdminConfirm = useCallback((id) => set({ revokeAdminConfirmId: id }), [set]);
  const cancelRevokeAdminConfirm = useCallback(() => set({ revokeAdminConfirmId: null }), [set]);
  const REVOKE_ADMIN_ERROR_MESSAGES = {
    NOT_AUTHORIZED: T('Bạn không có quyền này.', "You don't have this permission."),
    CANNOT_REVOKE_SELF: T('Bạn không thể tự thu hồi quyền của chính mình.', 'You cannot revoke your own admin access.'),
    LAST_ADMIN_CANNOT_BE_REVOKED: T('Không thể thu hồi quản trị viên cuối cùng.', 'The last remaining admin cannot be revoked.'),
    TARGET_NOT_ADMIN: T('Tài khoản này không phải quản trị viên.', 'That account is not an admin.'),
  };
  const confirmRevokeAdmin = useCallback(async () => {
    const id = s.revokeAdminConfirmId;
    if (!id) return;
    const { data, error } = await supabase.rpc('revoke_admin', { p_user_id: id });
    set({ revokeAdminConfirmId: null });
    if (error || data?.success === false) {
      console.warn('revoke_admin failed:', error || data);
      set({ adminInviteError: REVOKE_ADMIN_ERROR_MESSAGES[data?.error] || T('Không thực hiện được thao tác.', 'Could not complete that action.') });
      return;
    }
    await loadAdminTeam();
  }, [set, s.revokeAdminConfirmId, loadAdminTeam, T]);

  /** Owner/co-owner only — the FULL roster (every status), never shown to
   * anyone else. Direct select relies on organizer_members_select_owner. */
  const loadOrgTeamRoster = useCallback(async (organizerId) => {
    if (!organizerId) return;
    set({ orgTeamRosterLoading: true });
    const { data, error } = await supabase
      .from('organizer_members')
      .select('id, user_id, status, public_role, public_visible, invited_at, joined_at, profiles!organizer_members_user_id_fkey(handle, display_name, avatar_url)')
      .eq('organizer_id', organizerId)
      .order('invited_at', { ascending: false });
    if (error) { console.warn('loadOrgTeamRoster failed:', error); return set({ orgTeamRosterLoading: false }); }
    set({ orgTeamRoster: data || [], orgTeamRosterLoading: false });
  }, [set]);

  const orgTeamInviteHandleType = useCallback((e) => set({ orgTeamInviteHandle: e.target.value, orgTeamInviteError: '' }), [set]);
  const orgTeamInviteRoleType = useCallback((e) => set({ orgTeamInviteRole: e.target.value }), [set]);

  const inviteOrganizerMember = useCallback(async (organizerId) => {
    const handle = s.orgTeamInviteHandle.trim();
    if (!handle) return;
    set({ orgTeamInviteBusy: true, orgTeamInviteError: '' });
    const { data, error } = await supabase.rpc('invite_organizer_member', {
      p_organizer_id: organizerId, p_handle: handle, p_public_role: s.orgTeamInviteRole.trim() || 'Thành viên',
    });
    if (error || data?.success === false) {
      const code = data?.error;
      set({
        orgTeamInviteBusy: false,
        orgTeamInviteError: code === 'USER_NOT_FOUND' ? T('Không tìm thấy người dùng với tên này.', 'No user found with that handle.')
          : code === 'ALREADY_MEMBER' ? T('Người này đã ở trong đội ngũ hoặc đang chờ phản hồi.', 'This person is already a member or has a pending invite.')
          : code === 'CANNOT_INVITE_OWNER' ? T('Không thể mời chính chủ sở hữu.', "You can't invite the owner.")
          : T('Không thể gửi lời mời lúc này. Vui lòng thử lại.', "Couldn't send the invite right now. Please try again."),
      });
      return false;
    }
    set({ orgTeamInviteBusy: false, orgTeamInviteHandle: '', orgTeamInviteRole: '' });
    await loadOrgTeamRoster(organizerId);
    return true;
  }, [set, s.orgTeamInviteHandle, s.orgTeamInviteRole, loadOrgTeamRoster, T]);

  const removeOrganizerMember = useCallback(async (membershipId, organizerId) => {
    const { data, error } = await supabase.rpc('remove_organizer_member', { p_membership_id: membershipId });
    if (error || data?.success === false) { console.warn('removeOrganizerMember failed:', error || data); return false; }
    await loadOrgTeamRoster(organizerId);
    return true;
  }, [loadOrgTeamRoster]);

  // ---- Organizer Team pass (2026-09-27, Stage 2) — public Team page + event credits ----

  /** get_organizer_team (098/101) — PUBLIC/anon-safe: accepted AND
   * public_visible members only, never a hidden roster/count. Reused
   * verbatim from the "Bởi <org> Team ›" row (OrganizerProfile.jsx) and a
   * standalone /team/<id>-style deep link alike. */
  const openOrganizerTeam = useCallback(async (organizerId, back = 'organizerProfile') => {
    set({ screen: 'organizerTeam', organizerTeam: null, organizerTeamLoading: true, organizerTeamError: '', organizerTeamBack: back, organizerTeamOrganizerId: organizerId });
    const { data, error } = await supabase.rpc('get_organizer_team', { p_organizer_id: organizerId });
    if (error || data?.success === false) {
      set({ organizerTeamLoading: false, organizerTeamError: T('Không tìm thấy đội ngũ này.', "This Team couldn't be found.") });
      return;
    }
    set({ organizerTeam: data, organizerTeamLoading: false });
  }, [set, T]);
  const backFromOrganizerTeam = useCallback(() => set(prev => ({ screen: prev.organizerTeamBack || 'organizerProfile' })), [set]);

  /** This account's OWN pending event-credit invites — a plain RLS-backed
   * select (event_credits_select_own), joined with the real event's name
   * for display. Never a credit this account didn't actually receive. */
  const loadMyEventCredits = useCallback(async () => {
    if (!s.user?.id) return;
    const { data, error } = await supabase
      .from('event_credits')
      .select('id, event_id, organizer_id, status, events(name), organizers(name)')
      .eq('user_id', s.user.id)
      .eq('status', 'invited')
      .order('created_at', { ascending: false });
    if (error) { console.warn('loadMyEventCredits failed:', error); return; }
    set({ myEventCredits: data || [] });
  }, [set, s.user?.id]);

  /** iPhone fix pass (2026-09-27), Issue 5 — the CONFIRMED half; same
   * table/RLS as loadMyEventCredits() above, just `status = 'accepted'`
   * instead of `'invited'`. This account's own PRIVATE view, regardless of
   * the separate public_visible opt-in (that only ever gates the PUBLIC
   * profile's own credited_events, get_public_profile migration 100). */
  const loadMyConfirmedEventCredits = useCallback(async () => {
    if (!s.user?.id) return;
    const { data, error } = await supabase
      .from('event_credits')
      .select('id, event_id, organizer_id, status, events(name), organizers(name)')
      .eq('user_id', s.user.id)
      .eq('status', 'accepted')
      .order('responded_at', { ascending: false });
    if (error) { console.warn('loadMyConfirmedEventCredits failed:', error); return; }
    set({ myConfirmedEventCredits: data || [] });
  }, [set, s.user?.id]);

  const respondToEventCredit = useCallback(async (creditId, accept) => {
    const { data, error } = await supabase.rpc('respond_to_event_credit', { p_credit_id: creditId, p_accept: accept });
    if (error || data?.success === false) { console.warn('respondToEventCredit failed:', error || data); return false; }
    // "refresh all views after the action" — an accept moves the row from
    // pending to confirmed; reloading only the pending side left an
    // accepted credit invisible until the next full reload.
    await loadMyEventCredits();
    await loadMyConfirmedEventCredits();
    return true;
  }, [loadMyEventCredits, loadMyConfirmedEventCredits]);

  /** Owner/co-owner only — credits a real ACCEPTED team member for a real
   * event they own. Never the owner "crediting" themselves; never a
   * stranger who hasn't accepted the Team invite in the first place. */
  const assignEventCredit = useCallback(async (eventId, userId) => {
    set({ orgEventCreditAssignBusy: eventId });
    const { data, error } = await supabase.rpc('assign_event_credit', { p_event_id: eventId, p_user_id: userId });
    set({ orgEventCreditAssignBusy: '' });
    if (error || data?.success === false) { console.warn('assignEventCredit failed:', error || data); return false; }
    return true;
  }, [set]);

  /** Native share sheet (mobile Safari/Chrome) with a clipboard-copy
   * fallback for browsers with no Web Share API (most desktop browsers). */
  const sharePublicProfile = useCallback(async (handle, displayName) => {
    const url = `https://banbe.app/u/${handle}`;
    const title = T('Hồ sơ banbe của ' + (displayName || ''), (displayName || '') + '’s banbe profile');
    try {
      if (navigator.share) {
        await navigator.share({ title, url });
        return;
      }
    } catch { /* user cancelled the native sheet — not an error */ }
    try {
      await navigator.clipboard.writeText(url);
      set({ profileLinkCopiedFlash: true });
      setTimeout(() => set({ profileLinkCopiedFlash: false }), 2200);
    } catch { /* clipboard unavailable — nothing more to do */ }
  }, [set, T]);

  // ---- notifications ----
  const loadNotifications = useCallback(async () => {
    if (!s.user?.id) return;
    const { data, error } = await supabase
      .from('notifications')
      .select('*')
      .eq('recipient_id', s.user.id)
      .order('created_at', { ascending: false })
      .limit(50);
    if (error) { console.warn('Failed to load notifications:', error); return; }
    // Filtered client-side, not queried server-side — muted_notification_kinds
    // (062) exists purely for this, no insert-side RPC change (BUG 4).
    const rows = (data || []).filter(n => !s.mutedNotificationKinds.includes(n.kind));
    // Instagram-style avatars (07-notifications.md's 2026-09-18 follow-up):
    // notifications has no actor/avatar column of its own, so this batches
    // the two joins avatarSourceFor() (src/lib/notifications.js) needs —
    // bookings (for its event_id/user_id) and, from there, event_photos'
    // cover image / profiles.avatar_url — instead of a query per row.
    const bookingIds = [...new Set(rows.map(n => n.data?.booking_id).filter(Boolean))];
    let bookingById = {};
    if (bookingIds.length) {
      const { data: bookings } = await supabase.from('bookings').select('id, event_id, user_id').in('id', bookingIds);
      bookingById = Object.fromEntries((bookings || []).map(b => [b.id, b]));
    }
    const eventIds = [...new Set([
      ...rows.map(n => n.data?.event_id).filter(Boolean),
      ...Object.values(bookingById).map(b => b.event_id).filter(Boolean),
    ])];
    let eventPhotoByEventId = {};
    if (eventIds.length) {
      // event_photos.storage_path lives in the PUBLIC 'event-photos' bucket
      // (005) — getPublicUrl() is a local URL-builder, not a network call,
      // so this is cheap even though it runs once per resolved event.
      // 2026-09-18 follow-up (BUG 1): confirmed live that migration 010's
      // seed rows store storage_path WITH the bucket name already baked in
      // ('event-photos/evt_001/cover.jpg') — unlike every other
      // storage_path/proof_path/file_path column in this schema (pay-proof,
      // payment-documents), which are bucket-RELATIVE. Passed as-is to
      // getPublicUrl(), this doubles the bucket segment
      // ('.../public/event-photos/event-photos/...'), a broken URL.
      // Stripped defensively so either convention resolves correctly.
      const { data: photos } = await withR2Columns(withR2 => supabase
        .from('event_photos').select(withR2 ? 'event_id, storage_path, r2_ref, sort_order' : 'event_id, storage_path, sort_order')
        .in('event_id', eventIds).order('sort_order', { ascending: true }));
      for (const p of photos || []) {
        if (!eventPhotoByEventId[p.event_id]) {
          // Strict invite-only events (migration 113) — a notification
          // thumbnail can legitimately belong to an invite-only event
          // (e.g. the recipient's own booking confirmation), so this must
          // resolve through the same async/private-bucket-aware helper,
          // not a bare getPublicUrl() that would silently 403 on it.
          eventPhotoByEventId[p.event_id] = await resolveEventPhotoUrlAsync(p.storage_path, p.r2_ref, 'card');
        }
      }
    }
    const guestUserIds = [...new Set(Object.values(bookingById).map(b => b.user_id).filter(Boolean))];
    let avatarByUserId = {};
    if (guestUserIds.length) {
      // profiles.avatar_url is stored as a full external URL already (seed
      // data confirms this — not a storage path), so no signing/join step
      // beyond this one query.
      const { data: profiles } = await supabase.from('profiles').select('id, avatar_url').in('id', guestUserIds);
      avatarByUserId = Object.fromEntries((profiles || []).filter(p => p.avatar_url).map(p => [p.id, p.avatar_url]));
    }

    // TASK 1 (2026-09-22 nineteenth follow-up) — proactively prune
    // notifications whose target has genuinely been deleted, using the SAME
    // NOTIFICATION_TARGET_FIELD table targetIsGone() consults reactively on
    // tap (openNotification() below) — one shared definition instead of two
    // independently-drifting lists. `bookingById` above already covers
    // every kind referencing `booking_id` for free (fetched for avatars,
    // regardless of kind); `payment_documents` wasn't previously fetched at
    // all for this batch, so one small new query covers every kind
    // referencing `document_id` (existence only, no need for the full row —
    // payment_confirmed/payment_document_uploaded/_replaced still do their
    // own richer fetch inline in openNotification(), see that table's own
    // comment for why they're excluded from it).
    const documentIds = [...new Set(
      rows.filter(n => n.kind === 'payment_document_uploaded' || n.kind === 'payment_document_replaced'
        || NOTIFICATION_TARGET_FIELD[n.kind]?.table === 'documents')
        .map(n => n.data?.document_id).filter(Boolean)
    )];
    let liveDocumentIds = new Set();
    if (documentIds.length) {
      const { data: docs } = await supabase.from('payment_documents').select('id').in('id', documentIds);
      liveDocumentIds = new Set((docs || []).map(d => d.id));
    }
    const staleTargetKinds = {
      payment_document_uploaded: 'document_id',
      payment_document_replaced: 'document_id',
      payment_confirmed: 'booking_id',
      ...Object.fromEntries(Object.entries(NOTIFICATION_TARGET_FIELD).map(([kind, spec]) => [kind, spec.field])),
    };
    const staleIds = [];
    const liveRows = rows.filter(n => {
      const field = staleTargetKinds[n.kind];
      const targetId = field && n.data?.[field];
      if (!field || !targetId) return true;
      const stillExists = field === 'document_id' ? liveDocumentIds.has(targetId) : !!bookingById[targetId];
      if (!stillExists) { staleIds.push(n.id); return false; }
      return true;
    });
    if (staleIds.length) {
      supabase.from('notifications').delete().in('id', staleIds)
        .then(({ error }) => { if (error) console.warn('Failed to prune stale notifications:', error); });
    }

    set({
      notifications: liveRows, unreadNotifications: liveRows.filter(n => !n.read_at).length,
      notificationBookingById: bookingById, notificationEventPhotoByEventId: eventPhotoByEventId, notificationAvatarByUserId: avatarByUserId,
    });
  }, [set, s.user?.id, s.mutedNotificationKinds]);
  const goNotifications = useCallback(() => {
    set({ screen: 'notifications' });
    loadNotifications();
  }, [set, loadNotifications]);
  // Marks one notification read — never all of them at once, and never just
  // from opening the screen. Read status is the visible signal of "have I
  // actually looked at this one", so it has to follow an actual tap on that
  // specific notification, not merely arriving on the list.
  const markNotificationRead = useCallback(async (id) => {
    const target = s.notifications.find(n => n.id === id);
    if (!target || target.read_at) return;
    const readAt = new Date().toISOString();
    set(prev => ({
      notifications: prev.notifications.map(n => (n.id === id ? { ...n, read_at: readAt } : n)),
      unreadNotifications: Math.max(0, prev.unreadNotifications - 1),
    }));
    const { error } = await supabase.from('notifications').update({ read_at: readAt }).eq('id', id);
    if (error) console.warn('Failed to mark notification read:', error);
  }, [set, s.notifications]);

  // The "•••" menu's "Đánh dấu chưa đọc" action (BUG 4) — the exact
  // reverse of markNotificationRead(). No new RPC/schema: notifications'
  // existing UPDATE RLS (notifications_update_own... actually
  // read_at-scoped to recipient, migration 019) already allows a plain
  // client-side write of NULL back onto a column it already lets the
  // recipient set.
  const markNotificationUnread = useCallback(async (id) => {
    const target = s.notifications.find(n => n.id === id);
    if (!target || !target.read_at) return;
    set(prev => ({
      notifications: prev.notifications.map(n => (n.id === id ? { ...n, read_at: null } : n)),
      unreadNotifications: prev.unreadNotifications + 1,
    }));
    const { error } = await supabase.from('notifications').update({ read_at: null }).eq('id', id);
    if (error) console.warn('Failed to mark notification unread:', error);
  }, [set, s.notifications]);

  // The "•••" menu's "Tắt loại thông báo này" action (BUG 4) —
  // profiles.muted_notification_kinds (062), filtered client-side only in
  // loadNotifications()/the toast poll below; no insert-side RPC change.
  const muteNotificationKind = useCallback(async (kind) => {
    if (!s.user?.id || s.mutedNotificationKinds.includes(kind)) return;
    const next = [...s.mutedNotificationKinds, kind];
    set(prev => {
      const remaining = prev.notifications.filter(n => n.kind !== kind);
      return { mutedNotificationKinds: next, notifications: remaining, unreadNotifications: remaining.filter(n => !n.read_at).length };
    });
    const { error } = await supabase.from('profiles').update({ muted_notification_kinds: next }).eq('id', s.user.id);
    if (error) console.warn('Failed to mute notification kind:', error);
  }, [set, s.user?.id, s.mutedNotificationKinds]);

  // A real, permanent delete — not audit-sensitive the way dispute_messages
  // is (05-notify-retention.md's 72h retention is a different table
  // entirely), so no soft-delete. RLS (notifications_delete_own, migration
  // 050) already scopes this to the caller's own rows; removed from local
  // state optimistically first, restored if the delete actually fails.
  const deleteNotification = useCallback(async (id) => {
    const prevNotifications = s.notifications;
    const target = prevNotifications.find(n => n.id === id);
    set(prev => ({
      notifications: prev.notifications.filter(n => n.id !== id),
      unreadNotifications: target && !target.read_at ? Math.max(0, prev.unreadNotifications - 1) : prev.unreadNotifications,
    }));
    const { error } = await supabase.from('notifications').delete().eq('id', id);
    if (error) {
      console.warn('Failed to delete notification:', error);
      set({ notifications: prevNotifications }); // put it back — the delete didn't actually happen
    }
  }, [set, s.notifications]);
  // TASK 2 (2026-09-22 seventeenth follow-up) — bulk delete for
  // Notifications' new selection mode. Same RLS-scoped
  // `.delete().in('id', ids)` pattern as deleteNotification() above
  // (notifications_delete_own already scopes DELETE to the caller's own
  // rows — not a manual filter here); bounded to exactly the ids the
  // caller passed (whatever was visibly loaded/selected on screen), never
  // a broader delete-everything query. Only removes notification rows —
  // never bookings/messages/events/documents/receipts.
  const deleteNotifications = useCallback(async (ids) => {
    if (!ids?.length) return;
    const idSet = new Set(ids);
    const prevNotifications = s.notifications;
    const removedUnreadCount = prevNotifications.filter(n => idSet.has(n.id) && !n.read_at).length;
    set(prev => ({
      notifications: prev.notifications.filter(n => !idSet.has(n.id)),
      unreadNotifications: Math.max(0, prev.unreadNotifications - removedUnreadCount),
    }));
    const { error } = await supabase.from('notifications').delete().in('id', ids);
    if (error) {
      console.warn('Failed to delete notifications:', error);
      set({ notifications: prevNotifications, unreadNotifications: prevNotifications.filter(n => !n.read_at).length });
    }
  }, [set, s.notifications]);

  // 2026-09-19 follow-up (07-notifications.md): openNotification() calls
  // this whenever a kind's target fetch comes back genuinely not-found
  // (RLS can't spuriously produce this for these specific kinds — see the
  // call sites — so an empty result really does mean the row is gone,
  // e.g. payment_documents' 24h/12-month purge cron, or this session's own
  // manual test-data cleanup, the real repro that surfaced this bug).
  // Deletes the dead notification outright (a link to nothing is useless
  // either way) and surfaces a toast so the tap isn't silently a no-op —
  // `notification: null` so tapping the toast itself doesn't re-attempt
  // opening the same now-deleted target.
  const reportStaleNotification = useCallback((n) => {
    deleteNotification(n.id);
    pushToast({ title: T('Nội dung này không còn tồn tại', 'This content no longer exists'), body: '' });
  }, [deleteNotification, pushToast, T]);

  // Consumed once by DisputeChatPanel.jsx after it actually scrolls to/
  // highlights the target message (or the bottom, if there's no
  // message_id) — otherwise every 4s poll re-render would re-trigger it.
  const clearChatHighlight = useCallback(() => set({ chatHighlight: null }), [set]);

  // ---- lang / area / location ----
  const toggleLang = useCallback(() => {
    const next = EN ? 'vi' : 'en';
    set({ lang: next });
    persistAccountPreference({ locale: next });
  }, [set, EN, persistAccountPreference]);
  const openArea = useCallback(() => set({ areaAsking: true }), [set]);
  // `s.area` is in-memory only (initialState 'all'; never written to
  // localStorage/`banbe.preferences` or the profile) — same mechanism as
  // before, just a location node id now. Old keys are migrated on the way
  // in so a stale caller/deep link can't store an unmatchable value.
  const pickArea = useCallback((key) => set({ area: migrateLegacyAreaKey(key), areaAsking: false }), [set]);
  const requestFreshCoords = useCallback(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => set({ userCoords: { lat: pos.coords.latitude, lng: pos.coords.longitude } }),
      () => {}, // permission revoked at the OS level, or a transient error — the
      // baked-in placeholder distance stays as the fallback, silently.
      { maximumAge: 5 * 60 * 1000, timeout: 10000 },
    );
  }, [set]);
  const allowLocation = useCallback(() => {
    set({ askingLocation: false, areaAsking: false, located: true });
    requestFreshCoords();
  }, [set, requestFreshCoords]);
  const denyLocation = useCallback(() => set({ askingLocation: false, located: false, userCoords: null }), [set]);

  // If location was already allowed in an earlier session, quietly get a
  // fresh position once per visit — the coordinates themselves are never
  // persisted, only the yes/no decision, so there's nothing to reuse from
  // localStorage.
  const initialLocated = useRef(s.located);
  useEffect(() => {
    if (initialLocated.current === true) requestFreshCoords();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // If it's never been decided, only ask when the user actually reaches for
  // a distance — an unprompted permission dialog on every fresh visit is the
  // kind of thing that trains people to reflexively deny it.
  const askLocation = useCallback(() => set({ askingLocation: true }), [set]);

  // ---- filter ----
  const pickFilter = useCallback((key) => set({ filter: key }), [set]);
  const clearFilters = useCallback(() => set({
    filter: 'all', area: LOCATION_ALL,
    filterAttending: false, filterSaved: false, filterSoldOut: false,
    filterNotConfirmed: false, filterUpcoming: false, filterEnded: false, filterForYou: false,
  }), [set]);
  // Home's second chip row (12-home-filters.md, extended 2026-09-21) — each
  // independent, AND-combined with `filter`/`area` and with each other, not
  // mutually exclusive.
  const toggleHomeFilter = useCallback((key) => set(prev => {
    if (key === 'forYou') return { filterForYou: !prev.filterForYou };
    const stateKey = HOME_FILTER_STATE_KEY[key];
    return stateKey ? { [stateKey]: !prev[stateKey] } : {};
  }), [set]);

  // ---- share ----
  const shareEvent = useCallback((ev) => {
    const url = 'https://banbe.app/' + ev.key;
    const done = () => {
      set({ shared: true });
      setTimeout(() => set({ shared: false }), 1800);
    };
    if (navigator.share) {
      navigator.share({ title: 'banbe ▪︎ ' + ev.name, text: ev.name + ' ▪︎ ' + ev.where, url }).catch(done);
    } else if (navigator.clipboard) {
      navigator.clipboard.writeText(url).then(done, done);
    } else { done(); }
  }, [set]);

  // Every account's own invite link — this account's share-with-friends
  // code, minted automatically at signup (migration 023). Redeemed by
  // whoever follows it via the module-level "?ref=" capture at the top of
  // this file + claimPendingReferralAndWelcome() above.
  const referralLink = s.referralCode ? `https://banbe-two.vercel.app/?ref=${s.referralCode}` : null;
  const shareReferral = useCallback(() => {
    if (!referralLink) return;
    const title = T('Tham gia banbe cùng mình', 'Join me on banbe');
    const text = T(
      'Mỗi tuần một vài buổi hay ho — supper club, phòng tranh, gig nhạc nhỏ. Tham gia qua link của mình nhé:',
      "A few good things happening every week — supper clubs, small galleries, tucked-away gigs. Join through my link:"
    );
    const done = () => {
      set({ referralShared: true });
      setTimeout(() => set({ referralShared: false }), 1800);
    };
    if (navigator.share) {
      navigator.share({ title, text, url: referralLink }).catch(done);
    } else if (navigator.clipboard) {
      navigator.clipboard.writeText(referralLink).then(done, done);
    } else { done(); }
  }, [set, referralLink, T]);

  // ---- reserve ----
  const resizeDrafts = (prev, qty) => {
    const drafts = prev.attendeeDrafts.slice(0, qty);
    while (drafts.length < qty) drafts.push({ name: '', dob: '' });
    return drafts;
  };
  const qtyMinus = useCallback(() => set(prev => {
    const qty = Math.max(1, prev.qty - 1);
    return { qty, attendeeDrafts: resizeDrafts(prev, qty) };
  }), [set]);
  const qtyPlus = useCallback(() => set(prev => {
    const qty = Math.min(6, prev.qty + 1);
    return { qty, attendeeDrafts: resizeDrafts(prev, qty) };
  }), [set]);
  const setAttendeeField = useCallback((index, field, value) => set(prev => ({
    attendeeDrafts: prev.attendeeDrafts.map((a, i) => (i === index ? { ...a, [field]: value } : a)),
    reserveError: '',
  })), [set]);
  const pickPayNow = useCallback(() => set({ payMode: 'now' }), [set]);
  const pickHold = useCallback(() => set({ payMode: 'hold' }), [set]);
  const formNameType = useCallback((e) => set({ formName: e.target.value, reserveNameError: '' }), [set]);
  // Reserve.jsx's Name field, for a guest whose profiles.display_name is
  // still empty (e.g. an OAuth sign-in that never carried a name, or a
  // handle_new_user() insert whose raw_user_meta_data had no display_name
  // key — see 01-hold-payment.md's 2026-09-17 follow-up #6 for how this
  // actually happens) — a real write via the same rename_display_name()
  // RPC saveDisplayName() (Account/EditName) uses, not a value that goes
  // nowhere. Deliberately does NOT navigate away (unlike saveDisplayName,
  // which returns to 'profile') — the guest is mid-hold-flow here.
  const setNameAtHold = useCallback(async (name) => {
    const newName = name.trim();
    if (!newName) return { success: false };
    set({ reserveNameSaving: true, reserveNameError: '' });
    const { data, error } = await supabase.rpc('rename_display_name', { p_new_name: newName });
    if (error) {
      set({ reserveNameSaving: false, reserveNameError: T('Không thể lưu tên lúc này. Vui lòng thử lại.', 'Could not save your name right now. Please try again.') });
      return { success: false };
    }
    set(prev => ({ reserveNameSaving: false, reserveNameError: '', user: { ...prev.user, name: data?.new_name || newName } }));
    return { success: true };
  }, [set, T]);
  const submitReserve = useCallback(async (formOk) => {
    if (!formOk) return;
    set({ loading: true, reserveError: '' });

    try {
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session?.user) throw new Error('AUTH_REQUIRED');
      // hold_seats() (migration 026), not the legacy claim_seats() — the
      // latter never touches payment_state/hold_expires_at at all, so every
      // booking it created sat at the column default (payment_state =
      // 'holding', hold_expires_at = NULL) forever, regardless of whether
      // the event was free, instantly approved, or later marked paid. That
      // is exactly what left the ticket screen showing "Holding your
      // spot"/00:00 permanently instead of ever reaching Confirmed/Ended.
      // hold_seats_with_attendees() (migration 151) validates the whole party,
      // holds the seats and records every attendee in ONE transaction — a
      // booking can't exist half-named.
      const attendees = s.attendeeDrafts.slice(0, s.qty).map(a => ({ name: a.name.trim(), dob: a.dob }));
      const { data: booking, error } = await supabase.rpc('hold_seats_with_attendees', {
        p_event: s.eventKey,
        p_attendees: attendees,
        p_note: null,
      });
      if (error) throw error;
      const holdDeadline = booking.hold_expires_at ? new Date(booking.hold_expires_at).getTime() : null;
      set(prev => ({
        loading: false,
        booking,
        screen: 'confirmed',
        holdDeadline,
        now: Date.now(),
        tickets: { ...prev.tickets, [prev.eventKey]: prev.qty },
        attending: prev.attending.includes(prev.eventKey) ? prev.attending : [...prev.attending, prev.eventKey],
      }));
    } catch (err) {
      console.warn('Supabase booking failed:', err);
      // hold_seats() (031:38) raises one of these as a plain
      // `RAISE EXCEPTION '<CODE>'` — no ERRCODE/DETAIL, so the code itself
      // is `err.message` verbatim. This used to fall straight through to
      // the guest as raw, untranslated text (or a generic fallback on iOS)
      // — mapped here the same way `submitPaymentProof`'s own RPC errors
      // already are, so a cancelled/ended event says so instead of a vague
      // "try again".
      // Host reservation criteria (migration 162): hold_seats raises CRITERIA_NOT_MET
      // with the eligibility JSON in DETAIL (PostgREST `.details`). Show the unmet
      // card (Reserve.jsx) instead of the generic failure message.
      if (String(err?.message || '').includes('CRITERIA_NOT_MET')) {
        let detail = null;
        try { detail = JSON.parse(err.details || ''); } catch { /* keep generic card */ }
        set(prev => ({
          loading: false, reserveError: '',
          eligibilityByKey: { ...prev.eligibilityByKey, [prev.eventKey]: { ...(detail || {}), success: true, eligible: false, mode: 'declared' } },
        }));
        return;
      }
      const message = {
        NOT_AUTHENTICATED: T('Bạn cần đăng nhập để giữ chỗ.', 'You need to sign in to hold a spot.'),
        INVALID_QTY: T('Số lượng chỗ không hợp lệ.', 'That number of spots isn’t valid.'),
        INVALID_ATTENDEES: T('Thông tin người tham dự không hợp lệ.', 'The attendee details aren’t valid.'),
        INVALID_ATTENDEE_NAME: T('Mỗi người tham dự cần có tên (ít nhất 2 ký tự).', 'Every attendee needs a name (at least 2 characters).'),
        INVALID_ATTENDEE_DOB: T('Ngày sinh của một người tham dự không hợp lệ.', 'One attendee’s date of birth isn’t valid.'),
        PROFILE_NOT_FOUND: T('Không tìm thấy hồ sơ của bạn. Vui lòng thử lại.', 'We couldn’t find your profile. Please try again.'),
        EVENT_NOT_FOUND: T('Không tìm thấy sự kiện này.', 'This event could not be found.'),
        EVENT_NOT_LIVE: T('Sự kiện này đã bị huỷ hoặc chưa mở.', 'This event has been cancelled or isn’t open.'),
        SOLD_OUT: T('Rất tiếc, chỗ vừa hết.', 'Sorry, this just sold out.'),
        // Strict invite-only events (migration 113) — hold_seats' own gate.
        // A truthful, specific message rather than the generic fallback:
        // this isn't "try again", it's "you need an invite," which no
        // amount of retrying fixes.
        INVITE_REQUIRED: T('Sự kiện này chỉ dành cho người được mời.', 'This event is invite-only.'),
      }[err.message] || T('Không thể giữ chỗ lúc này. Vui lòng thử lại.', 'Could not hold this spot right now. Please try again.');
      set({ loading: false, reserveError: message });
    }
  }, [set, s.eventKey, s.qty, s.attendeeDrafts]);

  // ---- named tickets & import (migrations 151/152) ----
  const loadBookingAttendees = useCallback(async (bookingId) => {
    if (!bookingId) return;
    const { data, error } = await supabase.from('booking_attendees').select('*').eq('booking_id', bookingId).order('seat_no', { ascending: true });
    if (error) { console.warn('loadBookingAttendees failed:', error); return; }
    set(prev => (prev.booking?.id === bookingId ? { bookingAttendees: data || [] } : {}));
  }, [set]);

  const loadImportedTickets = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_my_imported_tickets');
    if (error) { console.warn('loadImportedTickets failed:', error); return; }
    set({ importedTickets: data || [] });
  }, [set]);

  const openTicketImport = useCallback((code = '') => set({ importOpen: true, importCode: code, importError: '', importNotice: '' }), [set]);
  const closeTicketImport = useCallback(() => set({ importOpen: false, importBusy: false, importError: '' }), [set]);
  const setImportCode = useCallback((v) => set({ importCode: v, importError: '' }), [set]);
  const openImportedTicket = useCallback((t) => set({ importedTicketOpen: t }), [set]);
  const closeImportedTicket = useCallback(() => set({ importedTicketOpen: null }), [set]);

  const claimTicket = useCallback(async () => {
    const code = (s.importCode || '').trim().toUpperCase();
    if (!code) return set({ importError: T('Vui lòng nhập mã nhận vé.', 'Please enter the claim code.') });
    if (!s.user) {
      try { sessionStorage.setItem(PENDING_CLAIM_KEY, code); } catch { /* private browsing */ }
      return set({ importOpen: false, screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'home' });
    }
    set({ importBusy: true, importError: '', importNotice: '' });
    const { data, error } = await supabase.rpc('claim_ticket', { p_claim_code: code });
    if (error || !data) {
      return set({ importBusy: false, importError: T('Không thể nhận vé lúc này. Vui lòng thử lại.', "Couldn't import the ticket right now. Please try again.") });
    }
    if (!data.success) {
      const msg = {
        EMAIL_MISMATCH: T('Email tài khoản không khớp với email người nhận vé này.', 'Your account email does not match the recipient email for this gift.'),
        EMAIL_NOT_VERIFIED: T('Hãy xác minh email của tài khoản trước khi nhận vé.', 'Verify your account email before importing the ticket.'),
        INVALID_CLAIM_CODE: T('Mã nhận vé không hợp lệ hoặc không tồn tại.', 'Invalid or nonexistent claim code.'),
        ALREADY_CLAIMED: T('Vé này đã được nhận bởi một tài khoản khác.', 'This ticket has already been imported by another account.'),
        TICKET_CANCELLED: T('Vé không hợp lệ hoặc đã bị huỷ.', 'This ticket is not eligible or has been cancelled.'),
        EVENT_ENDED: T('Sự kiện đã kết thúc, không thể thực hiện thao tác này.', 'The event has ended, so this is unavailable.'),
        NOT_PAID_YET: T('Vé này chưa được xác nhận thanh toán nên chưa thể nhập.', "This ticket's payment isn't confirmed yet, so it can't be imported."),
        GATE_REQUIRED: T('Tài khoản của bạn chưa hoàn tất xác minh nên chưa thể nhập vé.', 'Finish verifying your account before importing a ticket.'),
      }[data.error] || T('Đã có lỗi xảy ra. Vui lòng thử lại.', 'Something went wrong. Please try again.');
      return set({ importBusy: false, importError: msg });
    }
    try { sessionStorage.removeItem(PENDING_CLAIM_KEY); } catch { /* ignore */ }
    set({
      importBusy: false, importCode: '',
      importNotice: data.already_claimed
        ? T('Vé này đã nằm trong tài khoản của bạn — không có vé nào khác được tạo thêm.', 'This ticket is already in your account — no extra ticket was created.')
        : T('Vé đã được thêm vào tài khoản của bạn. Không có vé nào khác được tạo thêm.', 'The ticket was added to your account. No extra ticket was created.'),
    });
    loadImportedTickets();
    loadPaymentBookings();
  }, [s.importCode, s.user, set, T, loadImportedTickets, loadPaymentBookings]);

  // A ticket PDF's link (?claim=…) or a claim parked across sign-in: once
  // there is a signed-in user, open the import sheet with the code filled in.
  useEffect(() => {
    if (!s.user?.id) return;
    let code = null;
    try { code = sessionStorage.getItem(PENDING_CLAIM_KEY); } catch { /* ignore */ }
    if (code) set({ importOpen: true, importCode: code, importError: '', importNotice: '' });
  }, [s.user?.id, set]);

  const payHoldNow = useCallback(() => set({ holdDeadline: null, payMode: 'now' }), [set]);
  const confirmPayment = useCallback(async (bookingId, payMethod = 'momo') => {
    try {
      const { data, error } = await supabase.rpc('confirm_payment', { p_booking: bookingId, p_method: payMethod });
      if (error) throw error;
      // 15-organizer-checkin.md follow-up: confirm_payment() (migration 060)
      // now flips payment_state to 'confirmed' server-side too, not just
      // status — but every "awaiting confirmation" surface (the guest's own
      // PaymentDetails countdown, both Home banners, the Verifications
      // queue) reads client-side state that's only ever refreshed by its
      // own poll/mount otherwise. Patch all three in place immediately so
      // none of them linger even for one poll cycle.
      set(prev => ({
        booking: prev.booking && prev.booking.id === bookingId
          ? { ...prev.booking, status: 'confirmed', payment_state: 'confirmed', paid_method: payMethod, hold_expires_at: null, verify_due_at: null }
          : prev.booking,
        paymentBookings: prev.paymentBookings.map(b => (b.id === bookingId
          ? { ...b, status: 'confirmed', payment_state: 'confirmed', paid_method: payMethod, hold_expires_at: null, verify_due_at: null }
          : b)),
        verifications: prev.verifications.filter(v => v.booking_id !== bookingId),
      }));
      return data;
    } catch (e) {
      console.warn('confirmPayment RPC failed:', e);
    }
  }, [set]);
  const cancelBooking = useCallback(async (bookingId, reason = '') => {
    try {
      const { data, error } = await supabase.rpc('cancel_booking', { p_booking: bookingId, p_reason: reason });
      if (error) throw error;
      set(prev => (prev.booking && prev.booking.id === bookingId ? { booking: { ...prev.booking, status: 'cancelled' } } : {}));
      return data;
    } catch (e) {
      console.warn('cancelBooking RPC failed:', e);
    }
  }, [set]);
  const cancelEvent = useCallback(async (eventId, reason = '') => {
    try {
      const { data, error } = await supabase.rpc('cancel_event', { p_event: eventId, p_reason: reason });
      if (error) throw error;
      return data;
    } catch (e) {
      console.warn('cancelEvent RPC failed:', e);
    }
  }, []);
  // Bug 3 (15-organizer-checkin.md follow-up): this used to just flip
  // `calAdded` to change the button's own label — no calendar event was
  // ever actually created. Opens a small picker (Google Calendar vs an
  // .ics file, the latter covering Apple Calendar and every other calendar
  // app that can import one) instead of silently pretending to add
  // anything.
  const openCalendarPicker = useCallback(() => set({ calendarPickerFor: s.eventKey }), [set, s.eventKey]);
  const closeCalendarPicker = useCallback(() => set({ calendarPickerFor: null }), [set]);

  const pad2 = (n) => String(n).padStart(2, '0');
  const toICSDate = (d) => (
    d.getUTCFullYear() + pad2(d.getUTCMonth() + 1) + pad2(d.getUTCDate())
    + 'T' + pad2(d.getUTCHours()) + pad2(d.getUTCMinutes()) + pad2(d.getUTCSeconds()) + 'Z'
  );
  const calendarEventFor = (ev) => {
    const start = ev.startDate || new Date();
    const end = new Date(start.getTime() + 2 * 60 * 60 * 1000); // 2h default — this catalogue has no end time of its own
    return { title: ev.name, start, end, location: ev.locationLabel || ev.where || '', description: ev.desc || '' };
  };

  const addToCalendarGoogle = useCallback((ev) => {
    const { title, start, end, location, description } = calendarEventFor(ev);
    const params = new URLSearchParams({
      action: 'TEMPLATE', text: title,
      dates: `${toICSDate(start)}/${toICSDate(end)}`,
      details: description, location,
    });
    window.open(`https://calendar.google.com/calendar/render?${params.toString()}`, '_blank', 'noopener');
    set({ calAdded: true, calendarPickerFor: null });
  }, [set]);

  const addToCalendarICS = useCallback((ev) => {
    const { title, start, end, location, description } = calendarEventFor(ev);
    const esc = (v) => String(v).replace(/[\\,;]/g, (m) => '\\' + m).replace(/\n/g, '\\n');
    const ics = [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//banbe//event//VI', 'BEGIN:VEVENT',
      `UID:${(crypto.randomUUID ? crypto.randomUUID() : String(Date.now()))}@banbe.app`,
      `DTSTAMP:${toICSDate(new Date())}`,
      `DTSTART:${toICSDate(start)}`,
      `DTEND:${toICSDate(end)}`,
      `SUMMARY:${esc(title)}`,
      `LOCATION:${esc(location)}`,
      `DESCRIPTION:${esc(description)}`,
      'END:VEVENT', 'END:VCALENDAR',
    ].join('\r\n');
    const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `${ev.key || 'event'}.ics`;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    URL.revokeObjectURL(url);
    set({ calAdded: true, calendarPickerFor: null });
  }, [set]);
  const giveTicket = useCallback((ev) => {
    const url = 'https://banbe.app/ve/' + ev.key + '-x7f2';
    if (navigator.share) navigator.share({ title: 'banbe ▪︎ ' + ev.name, text: T('Mình có vé cho bạn', 'I have a ticket for you'), url }).catch(() => {});
    else if (navigator.clipboard) navigator.clipboard.writeText(url).catch(() => {});
    set({ gaveTicket: true });
    setTimeout(() => set({ gaveTicket: false }), 2200);
  }, [set, T]);

  // ---- login ----
  const loginEmailType = useCallback((e) => set({ loginEmail: e.target.value }), [set]);
  const loginNicknameType = useCallback((e) => set({ loginNickname: e.target.value }), [set]);
  const loginPhoneType = useCallback((e) => set({ loginPhoneNumber: e.target.value }), [set]);
  const loginCodeType = useCallback((e) => set({ loginCode: e.target.value }), [set]);
  const loginEmailCodeType = useCallback((e) => set({ loginEmailCode: e.target.value }), [set]);
  const loginPasswordType = useCallback((e) => set({ loginPassword: e.target.value }), [set]);
  const loginPasswordConfirmType = useCallback((e) => set({ loginPasswordConfirm: e.target.value }), [set]);
  // The same pattern every /api/auth/* endpoint enforces, checked against
  // the trimmed value those endpoints actually receive. The old check
  // (/\S+@\S+\.\S+/) had no anchors, so "hello a@b.c world", "a@@b.c" and
  // " a@b.c " all passed here and were then rejected by the server — the
  // button lit up and the request bounced with a generic failure.
  const emailValid = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v).trim());
  const passwordValid = (v) => v.length >= 8;
  // Switching between "code" and "password" (or Login/Signup) always clears
  // whatever partial attempt was in flight — a stale error or a code sent
  // for the other method would otherwise linger and confuse the new one.
  const setAuthMethod = useCallback((authMethod) => set({
    authMethod, reserveError: '', loginSent: false, loginSentVia: null, loginEmailCode: '', resetRequested: false,
  }), [set]);
  const authEmailErrorMessage = useCallback((error, mode) => {
    const code = error?.code || error?.message;
    if (code === 'AUTH_ACCOUNT_NOT_FOUND' && mode !== 'signup') {
      return T('Không tìm thấy tài khoản với email này. Hãy chọn Đăng ký trước.', 'No account exists for this email. Choose Sign up first.');
    }
    if (code === 'AUTH_ACCOUNT_EXISTS') {
      return T('Email này đã có tài khoản. Hãy chọn Đăng nhập để tiếp tục.', 'This email already has an account. Choose Log in to continue.');
    }
    if (code === 'VALID_NAME_REQUIRED') {
      return T('Hãy nhập tên hiển thị của bạn.', 'Please enter a display name.');
    }
    if (code === 'VALID_PASSWORD_REQUIRED') {
      return T('Mật khẩu phải có ít nhất 8 ký tự.', 'Password must be at least 8 characters.');
    }
    if (code === 'AUTH_EMAIL_DELIVERY_FAILED') {
      return T('Không thể gửi email lúc này. Vui lòng thử lại sau.', 'We could not send the email right now. Please try again later.');
    }
    if (code === 'AUTH_ACCOUNT_LOOKUP_FAILED') {
      return T('Không thể kiểm tra tài khoản lúc này. Vui lòng thử lại sau.', 'We could not check the account right now. Please try again later.');
    }
    if (code === 'AUTH_EMAIL_REQUEST_FAILED') {
      return T('Không thể xử lý yêu cầu email. Vui lòng thử lại sau.', 'We could not process the email request. Please try again later.');
    }
    if (code === 'AUTH_LINK_GENERATION_FAILED') {
      return T('Không thể tạo mã xác thực. Vui lòng thử lại sau.', 'We could not create the verification code. Please try again later.');
    }
    if (code === 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED') {
      return T('Dịch vụ email chưa được cấu hình. Vui lòng thử lại sau.', 'The email service is not configured yet. Please try again later.');
    }
    if (mode === 'reset') {
      return T('Không thể gửi email đặt lại mật khẩu. Vui lòng thử lại sau.', 'We could not send the password reset email. Please try again later.');
    }
    return mode === 'signup'
      ? T('Không thể gửi mã đăng ký. Vui lòng thử lại sau.', 'We could not send the sign-up code. Please try again later.')
      : T('Không thể gửi mã đăng nhập. Vui lòng thử lại sau.', 'We could not send the sign-in code. Please try again later.');
  }, [T]);
  // "Code" method: request a 6-digit code by email, for either Login or
  // Signup. Verifying it (below) is what actually establishes the session.
  const codeRequestSubmit = useCallback(async () => {
    // Only Signup creates a brand-new profile (policy_accepted_at still
    // NULL) — a returning account on the Login tab already consented once,
    // so this defensive no-op (login-submit's own disabled styling already
    // reflects it) only applies to Signup, same as the email-validity check
    // right below.
    if (s.authMode === 'signup' && !s.policyConsent) return;
    if (!emailValid(s.loginEmail)) return;
    const email = s.loginEmail.trim();
    const displayName = s.loginNickname.trim();
    if (s.authMode === 'signup' && !displayName) {
      return set({ reserveError: authEmailErrorMessage({ code: 'VALID_NAME_REQUIRED' }, s.authMode) });
    }
    try {
      await requestAuthEmail({ email, mode: s.authMode, locale: s.lang, ...(s.authMode === 'signup' ? { displayName } : {}) });
      set({ loginSent: true, loginSentVia: 'email', pendingEmailMode: s.authMode, reserveError: '' });
    } catch (e) {
      set({ loginSent: false, loginSentVia: null, reserveError: authEmailErrorMessage(e, s.authMode) });
    }
  }, [set, s.loginEmail, s.loginNickname, s.authMode, s.policyConsent, authEmailErrorMessage]);
  // "Password" method, Signup: creates the account with the password
  // actually chosen, then — same as the code method — still requires
  // entering the emailed confirmation code once to finish.
  const passwordSignupSubmit = useCallback(async () => {
    if (!s.policyConsent) return;
    if (!emailValid(s.loginEmail)) return;
    const email = s.loginEmail.trim();
    const displayName = s.loginNickname.trim();
    if (!displayName) return set({ reserveError: authEmailErrorMessage({ code: 'VALID_NAME_REQUIRED' }, 'signup') });
    if (!passwordValid(s.loginPassword)) return set({ reserveError: authEmailErrorMessage({ code: 'VALID_PASSWORD_REQUIRED' }, 'signup') });
    if (s.loginPassword !== s.loginPasswordConfirm) {
      return set({ reserveError: T('Mật khẩu xác nhận không khớp.', 'Passwords do not match.') });
    }
    try {
      await requestPasswordSignup({ email, password: s.loginPassword, displayName, locale: s.lang });
      set({ loginSent: true, loginSentVia: 'email', pendingEmailMode: 'signup', reserveError: '' });
    } catch (e) {
      set({ loginSent: false, loginSentVia: null, reserveError: authEmailErrorMessage(e, 'signup') });
    }
  }, [set, s.loginEmail, s.loginNickname, s.loginPassword, s.loginPasswordConfirm, s.policyConsent, authEmailErrorMessage, T]);
  // "Password" method, Login: straight to Supabase, no code step — the
  // account already has a password. (The onAuthStateChange listener handles
  // moving off the Login screen once the session lands.)
  const passwordLoginSubmit = useCallback(async () => {
    // No consent gate here — signing in is never how a profile's
    // policy_accepted_at first gets set (see codeRequestSubmit above); an
    // account that can sign in already consented at signup.
    if (!emailValid(s.loginEmail)) return;
    if (!s.loginPassword) return set({ reserveError: T('Nhập mật khẩu của bạn.', 'Enter your password.') });
    const { error } = await supabase.auth.signInWithPassword({ email: s.loginEmail.trim(), password: s.loginPassword });
    if (error) {
      set({ reserveError: T('Sai email hoặc mật khẩu.', 'Wrong email or password.') });
      return;
    }
    set({ reserveError: '' });
  }, [set, s.loginEmail, s.loginPassword, T]);
  // Runs exactly once, right after a brand-new account's first sign-in
  // (never on an ordinary login — see the isSignup guard at the call site).
  // Redeems whatever referral code was stashed from the "?ref=" link they
  // followed (if any), then always sends the welcome email introducing
  // this account's own link, regardless of whether they arrived via
  // someone else's. Both dispatches are best-effort: a failure here never
  // blocks the sign-up itself, since the account already exists by the
  // time this runs.
  const claimPendingReferralAndWelcome = useCallback(async () => {
    let referredSomeone = false;
    try {
      const pendingCode = localStorage.getItem(REFERRAL_STORAGE_KEY);
      if (pendingCode) {
        localStorage.removeItem(REFERRAL_STORAGE_KEY);
        const { data, error } = await supabase.rpc('redeem_referral', { p_code: pendingCode });
        referredSomeone = !error && data?.success === true;
      }
    } catch { /* best-effort — the account itself is already created */ }

    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) return;
      fetch('/api/notify', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ type: 'welcome' }),
      }).catch(() => {});
      if (referredSomeone) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: 'referral_joined' }),
        }).catch(() => {});
      }
    } catch { /* best-effort; the account and any redemption already landed */ }
  }, []);
  // Finishes either code flow above — Login-by-code, Signup-by-code, or
  // Signup-by-password's confirmation step — by verifying the code directly
  // against Supabase itself; a real session comes back on success and the
  // onAuthStateChange listener takes it from there.
  const verifyEmailCode = useCallback(async () => {
    const email = s.loginEmail.trim();
    const token = s.loginEmailCode.trim();
    if (!token) return set({ reserveError: T('Nhập mã đã gửi tới email của bạn.', 'Enter the code sent to your email.') });
    const isSignup = s.pendingEmailMode === 'signup';
    const { error } = await supabase.auth.verifyOtp({ email, token, type: isSignup ? 'signup' : 'email' });
    if (error) {
      set({ reserveError: T('Mã không đúng hoặc đã hết hạn. Vui lòng thử lại.', 'That code is wrong or has expired. Please try again.') });
      return;
    }
    set({ reserveError: '', loginEmailCode: '' });
    if (isSignup) claimPendingReferralAndWelcome();
  }, [set, s.loginEmail, s.loginEmailCode, s.pendingEmailMode, T, claimPendingReferralAndWelcome]);
  // "Forgot password?" — always shows the same generic confirmation
  // regardless of whether the account actually exists (see
  // send-password-reset.js); only a real failure to even attempt sending
  // gets its own message.
  const requestPasswordResetSubmit = useCallback(async () => {
    if (!emailValid(s.loginEmail)) return set({ reserveError: T('Nhập email của bạn trước.', 'Enter your email first.') });
    try {
      await requestPasswordReset({ email: s.loginEmail.trim() });
      set({ resetRequested: true, reserveError: '' });
    } catch (e) {
      set({ resetRequested: false, reserveError: authEmailErrorMessage(e, 'reset') });
    }
  }, [set, s.loginEmail, authEmailErrorMessage, T]);
  // Single Enter-key / submit dispatcher for the Login screen — routes to
  // whichever action the currently-visible form actually needs.
  const submitCurrentForm = useCallback(() => {
    if (s.loginSentVia === 'email') { verifyEmailCode(); return; }
    if (s.authMethod === 'password') {
      if (s.authMode === 'signup') passwordSignupSubmit(); else passwordLoginSubmit();
      return;
    }
    codeRequestSubmit();
  }, [s.loginSentVia, s.authMethod, s.authMode, verifyEmailCode, passwordSignupSubmit, passwordLoginSubmit, codeRequestSubmit]);
  const loginEmailKey = useCallback((e) => { if (e.key === 'Enter') submitCurrentForm(); }, [submitCurrentForm]);
  const loginZalo = useCallback(() => set({ reserveError: T('Zalo chưa khả dụng. Hãy dùng email hoặc OTP điện thoại.', 'Zalo is not available yet. Use email or phone OTP.') }), [set, T]);
  const loginPhone = useCallback(async () => {
    const phone = s.loginPhoneNumber.trim();
    if (!phone) return set({ reserveError: T('Nhập số điện thoại trước.', 'Enter your phone number first.') });
    const { error } = await supabase.auth.signInWithOtp({ phone });
    set(error ? { reserveError: error.message } : { loginSent: true, loginSentVia: 'phone', reserveError: '' });
  }, [set, s.loginPhoneNumber, T]);
  const verifyLoginCode = useCallback(async () => {
    if (!s.loginPhoneNumber.trim() || !s.loginCode.trim()) return set({ reserveError: T('Nhập mã OTP.', 'Enter the OTP code.') });
    const { error } = await supabase.auth.verifyOtp({ phone: s.loginPhoneNumber.trim(), token: s.loginCode.trim(), type: 'sms' });
    if (error) set({ reserveError: error.message });
  }, [set, s.loginPhoneNumber, s.loginCode, T]);
  // Google/Facebook (note 10). Not gated on the consent checkbox at all —
  // unlike password/code, an OAuth attempt can't be pre-classified as
  // "just a login" ahead of time (Supabase creates the account right then
  // if the provider identity is new), and a *returning* user must be able
  // to click straight through with zero friction. Consent for a genuinely
  // new profile is handled after the redirect completes instead — see
  // syncUser()'s policyGateActive branch.
  const startOAuth = useCallback(async (provider) => {
    const { error } = await supabase.auth.signInWithOAuth({
      provider, options: { redirectTo: getAuthRedirectUrl() },
    });
    if (error) set({ reserveError: error.message });
    // No further state change on success: signInWithOAuth navigates the
    // whole page away immediately, so there's nothing left to update here.
  }, [set]);
  const loginGoogle = useCallback(() => startOAuth('google'), [startOAuth]);
  const loginFacebook = useCallback(() => startOAuth('facebook'), [startOAuth]);
  const loginInstagram = useCallback(() => set({ reserveError: T('Instagram chưa khả dụng. Hãy dùng email hoặc OTP điện thoại.', 'Instagram is not available yet. Use email or phone OTP.') }), [set, T]);

  // ---- Account deletion (Task 2, Account/Settings pass) ----
  // Lives inside Settings/Preferences (AccountGroup.jsx's `preferences`
  // case), not Login.jsx — reuses the SAME `supabase.auth.verifyOtp`
  // email-code mechanism Login already established (see `verifyEmailCode`
  // above) as the reauthentication step, rather than a parallel auth path.
  const openDeleteAccount = useCallback(() => {
    set({
      deleteAccountOpen: true, deleteAccountStep: 'intro', deleteAccountReasonCode: '', deleteAccountReasonText: '',
      deleteAccountPhraseInput: '', deleteAccountReauthSent: false, deleteAccountReauthCode: '', deleteAccountReauthVerified: false,
      deleteAccountReauthBusy: false, deleteAccountReauthError: '', deleteAccountSubmitting: false, deleteAccountError: '',
      // Only a Google/Facebook `identities` provider (note 10) changes the
      // reauth affordance shown — 'apple' is deliberately never checked
      // here, since this app does not offer Sign in with Apple anywhere
      // (confirmed by grep; see the report for this pass).
      deleteAccountOAuthProvider: (s.user?.identities || []).find(i => i.provider !== 'email')?.provider || null,
    });
  }, [set, s.user]);
  const closeDeleteAccount = useCallback(() => set({ deleteAccountOpen: false }), [set]);
  const setDeleteAccountStep = useCallback((step) => set({ deleteAccountStep: step }), [set]);
  const setDeleteAccountReasonCode = useCallback((code) => set({ deleteAccountReasonCode: code }), [set]);
  const setDeleteAccountReasonText = useCallback((e) => set({ deleteAccountReasonText: e.target.value.slice(0, 500) }), [set]);
  const setDeleteAccountPhraseInput = useCallback((e) => set({ deleteAccountPhraseInput: e.target.value }), [set]);
  const setDeleteAccountReauthCode = useCallback((e) => set({ deleteAccountReauthCode: e.target.value, deleteAccountReauthError: '' }), [set]);

  // Sends a fresh emailed login code to THIS account's own, already-known
  // email — never a client-supplied address — via the same `send_email_code`
  // endpoint/mode Login already uses for a returning user.
  const sendDeleteAccountReauthCode = useCallback(async () => {
    if (!s.user?.email) return set({ deleteAccountReauthError: T('Không tìm thấy email tài khoản.', 'Could not find this account’s email.') });
    set({ deleteAccountReauthBusy: true, deleteAccountReauthError: '' });
    try {
      await requestAuthEmail({ email: s.user.email, mode: 'login' });
      set({ deleteAccountReauthSent: true, deleteAccountReauthBusy: false });
    } catch (e) {
      set({ deleteAccountReauthBusy: false, deleteAccountReauthError: authEmailErrorMessage(e, 'login') });
    }
  }, [set, s.user, T, authEmailErrorMessage]);

  // Verifying the code refreshes the real Supabase session (a genuine,
  // server-checked proof of live control of the account's own credential —
  // never a local/biometric-only check, which is exactly this ticket's own
  // "Face ID alone is not sufficient server-side identity proof" rule).
  const verifyDeleteAccountReauthCode = useCallback(async () => {
    const email = s.user?.email;
    const token = s.deleteAccountReauthCode.trim();
    if (!token) return set({ deleteAccountReauthError: T('Nhập mã đã gửi tới email của bạn.', 'Enter the code sent to your email.') });
    set({ deleteAccountReauthBusy: true, deleteAccountReauthError: '' });
    const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' });
    if (error) {
      set({ deleteAccountReauthBusy: false, deleteAccountReauthError: T('Mã không đúng hoặc đã hết hạn.', 'That code is wrong or has expired.') });
      return;
    }
    set({ deleteAccountReauthBusy: false, deleteAccountReauthVerified: true, deleteAccountReauthError: '' });
  }, [set, s.user, s.deleteAccountReauthCode, T]);

  const DELETE_ACCOUNT_PHRASE = 'DELETE banbe';
  const deleteAccountPhraseMatches = s.deleteAccountPhraseInput.trim() === DELETE_ACCOUNT_PHRASE;
  // Final gate: phrase match AND reauth completed AND not already
  // submitting (the duplicate-submission guard — `deleteAccountSubmitting`
  // is set synchronously below, before the request even goes out).
  const deleteAccountReadyToSubmit = deleteAccountPhraseMatches && s.deleteAccountReauthVerified && !s.deleteAccountSubmitting;

  const confirmDeleteAccount = useCallback(async () => {
    if (!deleteAccountPhraseMatches || !s.deleteAccountReauthVerified || s.deleteAccountSubmitting) return;
    set({ deleteAccountSubmitting: true, deleteAccountError: '', deleteAccountStep: 'submitting' });
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) throw new Error('NO_SESSION');
      const response = await fetch('/api/auth', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          type: 'delete_account',
          reasonCode: s.deleteAccountReasonCode || null,
          reasonText: s.deleteAccountReasonText || null,
        }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) {
        if (payload.error === 'ACCOUNT_DELETION_BLOCKED_OPEN_EVENT') {
          const names = (payload.openEvents || []).map(e => e.name).filter(Boolean).join(', ');
          throw new Error(T(
            `Bạn vẫn đang tổ chức sự kiện đang mở${names ? ` (${names})` : ''}. Vui lòng hủy hoặc kết thúc sự kiện trước khi xóa tài khoản.`,
            `You still own an open event${names ? ` (${names})` : ''}. Please cancel or end it before deleting your account.`
          ));
        }
        throw new Error(payload.error || 'ACCOUNT_DELETION_FAILED');
      }
      // Truthful completion: the request has FULLY completed server-side
      // by this point (the endpoint only responds 200 after
      // admin.auth.admin.deleteUser() itself succeeded) — this is a real
      // "deleted", not merely "requested".
      set({ deleteAccountSubmitting: false, deleteAccountStep: 'done' });
      // Client-side session cleanup (per this ticket's own instruction):
      // sign out of the now-nonexistent session, clear the local session
      // cache, and drop any push-token registration this device holds for
      // this now-deleted account (see AppState+Push.swift's iOS mirror for
      // whether an equivalent exists there — web registers no push token
      // anywhere in this codebase today, confirmed by grep, so there is
      // nothing web-side to unregister).
      await supabase.auth.signOut().catch(() => {});
      try { navigator.serviceWorker?.controller?.postMessage('banbe-clear-storage-cache'); } catch { /* no SW — nothing cached */ }
      try { localStorage.clear(); sessionStorage.clear(); } catch { /* private mode / blocked storage — non-fatal */ }
    } catch (e) {
      set({ deleteAccountSubmitting: false, deleteAccountStep: 'confirm', deleteAccountError: e.message || String(e) });
    }
  }, [set, s.deleteAccountReauthVerified, s.deleteAccountSubmitting, s.deleteAccountReasonCode, s.deleteAccountReasonText, deleteAccountPhraseMatches, T]);

  // ---- Account > Security ----
  const securityPasswordType = useCallback((e) => set({ securityPassword: e.target.value, securityError: '', securitySaved: false }), [set]);
  const securityPasswordConfirmType = useCallback((e) => set({ securityPasswordConfirm: e.target.value, securityError: '', securitySaved: false }), [set]);

  // Deliberately one form for both cases this section has to serve: an
  // account that has only ever used emailed sign-in codes setting its first
  // password, and one replacing a password it already has. Supabase treats
  // both as the same update on the signed-in user, and nothing the client
  // can read reliably says which of the two an account is — so branching
  // here would mean guessing at the label and getting it wrong half the time.
  const saveSecurityPassword = useCallback(async () => {
    if (!passwordValid(s.securityPassword)) {
      return set({ securityError: T('Mật khẩu cần ít nhất 8 ký tự.', 'Passwords need at least 8 characters.'), securitySaved: false });
    }
    if (s.securityPassword !== s.securityPasswordConfirm) {
      return set({ securityError: T('Mật khẩu xác nhận không khớp.', 'Passwords do not match.'), securitySaved: false });
    }
    set({ securityBusy: true, securityError: '', securitySaved: false });
    const { error } = await supabase.auth.updateUser({ password: s.securityPassword });
    if (error) {
      return set({ securityBusy: false, securityError: T('Không lưu được mật khẩu lúc này. Vui lòng thử lại.', "We couldn't save that password right now. Please try again.") });
    }
    set({ securityBusy: false, securityPassword: '', securityPasswordConfirm: '', securitySaved: true });
  }, [set, s.securityPassword, s.securityPasswordConfirm, T]);

  // "Forgot your current password?" — emails the recovery link to this
  // account's own address. Shown as sent either way: the endpoint already
  // refuses to reveal whether an address has an account, and surfacing a
  // failure here would leak the same thing by omission.
  const sendSecurityPasswordReset = useCallback(async () => {
    const email = s.user?.email;
    if (!email) return;
    set({ securityBusy: true, securityError: '' });
    try {
      await requestPasswordReset({ email });
    } catch { /* same message either way — see above */ }
    set({ securityBusy: false, securityResetSent: true });
  }, [set, s.user?.email]);

  // ---- reset-password screen (landed on via the emailed recovery link —
  // see the PASSWORD_RECOVERY branch of onAuthStateChange above) ----
  const newPasswordType = useCallback((e) => set({ newPassword: e.target.value, resetPasswordError: '' }), [set]);
  const newPasswordConfirmType = useCallback((e) => set({ newPasswordConfirm: e.target.value, resetPasswordError: '' }), [set]);
  const submitNewPassword = useCallback(async () => {
    if (!passwordValid(s.newPassword)) {
      return set({ resetPasswordError: T('Mật khẩu phải có ít nhất 8 ký tự.', 'Password must be at least 8 characters.') });
    }
    if (s.newPassword !== s.newPasswordConfirm) {
      return set({ resetPasswordError: T('Mật khẩu không khớp.', 'Passwords do not match.') });
    }
    set({ resetPasswordBusy: true, resetPasswordError: '' });
    const { error } = await supabase.auth.updateUser({ password: s.newPassword });
    if (error) {
      set({ resetPasswordBusy: false, resetPasswordError: T('Không thể đặt mật khẩu mới. Vui lòng thử lại.', 'Could not set the new password. Please try again.') });
      return;
    }
    set({ resetPasswordBusy: false, newPassword: '', newPasswordConfirm: '', screen: 'home' });
  }, [set, s.newPassword, s.newPasswordConfirm, T]);

  // ---- chat ----
  // Real threads/messages (supabase/migrations/003_social_chat.sql) — this
  // used to be pure local state (`chats`) with no server backing at all.
  const chatOnType = useCallback((e) => set({ chatDraft: e.target.value }), [set]);
  // Task 1a — real read-tracking: messages.read_at was never written by any
  // code path in this app before this pass (confirmed by grep). Scoped to
  // "not sent by me" so a guest opening their own thread can never mark
  // their own outgoing messages read.
  const markThreadMessagesRead = useCallback(async (threadId) => {
    const uid = s.user?.id;
    if (!uid) return;
    // BUG (2026-09-22 sixteenth follow-up) — real root cause, confirmed
    // against real production data (dotrung1998@gmail.com, system rows like
    // "Dispute resolved"/"Confirmation email sent" with sender_id IS NULL
    // and read_at IS NULL): `.neq('sender_id', uid)` compiles to SQL
    // `sender_id <> uid`, which NULL semantics silently exclude from the
    // WHERE clause — a system message's read_at was NEVER actually
    // written, so every later refetch (loadInboxThreads, the dock poll
    // below) saw that same never-cleared row and correctly (per its own
    // client-side, NULL-safe `sender_id !== uid` check) reported the thread
    // unread again — the "reads, then reverts" bug. `.or(...)` updates a
    // message when it's a system row (sender_id IS NULL) OR a genuine
    // incoming message from someone else — never one this user authored.
    const { error } = await supabase.from('messages').update({ read_at: new Date().toISOString() }).eq('thread_id', threadId).is('read_at', null).or(`sender_id.is.null,sender_id.neq.${uid}`);
    if (error) return;
    // BUG 1 (2026-09-22 fourteenth follow-up) — real bug, confirmed by
    // reading: this write succeeds and the optimistic patch below runs
    // fine, but `loadInboxThreads()`/the dock badge's own 5s poll
    // (lastReadWriteAtRef's other call sites) can have a REQUEST already
    // in flight from BEFORE this UPDATE committed — its response arrives
    // AFTER this function's own optimistic patch and overwrites `unread:
    // false`/the decremented count with the stale, pre-write snapshot it
    // captured earlier. Not RLS (messages_update_participant, migration
    // 064, already correctly allows this), not a wrong predicate — a
    // genuine out-of-order response race. `lastReadWriteAtRef` records
    // when the most recent successful mark-read committed; both
    // `loadInboxThreads()` and the dock poll below stamp their own
    // request's start time and discard their result if it predates this,
    // letting the NEXT (guaranteed-later) fetch supply the authoritative
    // value instead of overwriting a newer truth with an older one.
    lastReadWriteAtRef.current = Date.now();
    // Task 6 (2026-09-22 twelfth follow-up) — one shared unread definition
    // (read_at IS NULL AND sender_id != me) already backs loadInboxThreads'
    // own `unread` flag and the dock badge's 5s poll (`unreadMessages`),
    // but neither of those local snapshots was ever patched when a thread
    // got marked read here — `chatBackFn` returns straight to 'inbox'
    // without re-calling `loadInboxThreads()`, so the Inbox row stayed
    // bold/dotted until Inbox was re-entered from OUTSIDE (a fresh
    // `goInbox()`), and the dock count only caught up on its own next
    // 5s tick. Patching both state slices here, right where read_at
    // actually gets written, is the one place every path that marks a
    // thread read (only this function does) can never skip it.
    set(prev => {
      const wasUnread = prev.inboxThreads.find(t => t.threadId === threadId)?.unread;
      return {
        inboxThreads: prev.inboxThreads.map(t => (t.threadId === threadId ? { ...t, unread: false } : t)),
        unreadMessages: wasUnread ? Math.max(0, prev.unreadMessages - 1) : prev.unreadMessages,
      };
    });
  }, [s.user?.id, set]);
  // `computeDivider`: only true for the FIRST load of a thread-open (see
  // openThread/openChatFor below) — captures chatUnreadDividerId once, from
  // whatever's unread at that moment, then immediately marks those rows
  // read. The 4s poll below calls this again with computeDivider left
  // false, so it only ever refreshes `chatMessages` and never moves the
  // divider while the thread stays open (07-notifications.md).
  // Task 4 (2026-09-21 follow-up) — signs every given 'chat-attachments'
  // path in one batched call, same pattern as signProofUrls/`proofUrls`.
  //
  // BUG FIX: `loadChatMessages` (below) calls this on EVERY invocation,
  // including the 4s poll while a thread stays open — re-signing a path
  // that was already signed produces a brand-new signed URL STRING every
  // time (same file, different token/expiry), and since `<img src>` in
  // Chat.jsx reads straight off `chatAttachmentUrls[path]`, a changing src
  // string makes the browser tear down and re-fetch the image from
  // scratch every ~4s — the reported "thumbnail appears/disappears
  // repeatedly, never tappable/savable" loop. Same root-cause SHAPE as the
  // signed-URL churn already diagnosed for payment receipts
  // (08-payment-documents.md) — not a loading-state wiring bug, a genuinely
  // unstable URL being fed to `src`. Fixed by never overwriting an
  // already-signed path — `acc` starts from the PREVIOUS
  // `chatAttachmentUrls`, so `!acc[row.path]` is true only for a path this
  // thread hasn't signed yet (a newly-arrived attachment).
  const signChatAttachmentUrls = useCallback(async (paths) => {
    const wanted = [...new Set((paths || []).filter(Boolean))];
    if (!wanted.length) return;
    const { data, error } = await supabase.storage.from('chat-attachments').createSignedUrls(wanted, 600);
    if (error) { console.warn('signChatAttachmentUrls failed:', error); return; }
    set(prev => ({
      chatAttachmentUrls: (data || []).reduce((acc, row) => {
        if (row.path && row.signedUrl && !row.error && !acc[row.path]) acc[row.path] = row.signedUrl;
        return acc;
      }, { ...prev.chatAttachmentUrls }),
    }));
  }, [set]);
  const loadChatMessages = useCallback(async (threadId, computeDivider) => {
    const { data, error } = await supabase
      .from('messages')
      .select('id, sender_id, body, kind, created_at, read_at, attachment_path, attachment_type, attachment_width, attachment_height, reply_to_message_id')
      .eq('thread_id', threadId)
      .order('created_at', { ascending: true });
    if (error) return;
    const rows = data || [];
    const uid = s.user?.id;
    if (computeDivider) {
      const firstUnread = rows.find(m => !m.read_at && m.sender_id !== uid);
      set({ chatMessages: rows, chatUnreadDividerId: firstUnread ? firstUnread.id : null });
      markThreadMessagesRead(threadId);
    } else {
      set({ chatMessages: rows });
    }
    // Efficiency half of the fix above: skip re-requesting a signed URL
    // this thread already has, not just skip overwriting it once the
    // (otherwise wasted) network round trip comes back — reads
    // `s.chatAttachmentUrls` via closure rather than adding it to this
    // callback's own deps, so the 4s poll's `setInterval` (which holds a
    // reference to this same function) doesn't get torn down and rebuilt
    // every time a new attachment gets signed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    const newPaths = rows.map(m => m.attachment_path).filter(p => p && !s.chatAttachmentUrls[p]);
    if (newPaths.length) signChatAttachmentUrls(newPaths);
  }, [set, s.user?.id, markThreadMessagesRead, signChatAttachmentUrls]);
  // Get-or-create the one thread between the signed-in guest and this
  // event's organizer. Never called for the organizer's own side of a
  // conversation — that always opens a specific, already-known thread
  // (see openThread, used from Inbox).
  const openChatFor = useCallback(async (key, back) => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'chat', authBackScreen: 'event' });
    // findEvent() falls back to EVENTS[0] ("Bếp Nhỏ") for any key that isn't a
    // catalogue event, so a real, host-created event used to get that demo
    // host's name as the chat title. Only trust it for genuine catalogue keys.
    const isCatalog = EVENTS.some(e => e.key === key);
    const otherName = (isCatalog ? findEvent(key)?.orgName : s.realEventsById[key]?.organizerName) || '';
    // Opening message pair (vi/en) — Chat.jsx picks by app language and falls
    // back to a built-in localized default (src/lib/chatGreeting.js).
    const knownReal = s.realEventsById[key];
    set({ screen: 'chat', eventKey: key, chatBack: back || 'event', chatThreadId: null, chatDraftOrganizerId: null, chatMessages: [], chatOtherName: otherName, chatGreeting: knownReal?.chatGreeting || '', chatGreetingEn: knownReal?.chatGreetingEn || '', chatGreetingFor: key, chatUnreadDividerId: null });
    // Async results only apply while this same chat is still the open one.
    const stillHere = (prev) => prev.screen === 'chat' && prev.eventKey === key;

    // Lazy creation (migration 156 pass): only LOOK for an existing thread
    // here. No row is inserted until the first real send (ensureChatThread).
    const { data: existing } = await supabase.from('threads').select('id').eq('event_id', key).eq('guest_id', s.user.id).maybeSingle();
    if (existing?.id) { set(prev => (stillHere(prev) ? { chatThreadId: existing.id, chatDraftOrganizerId: null } : {})); loadChatMessages(existing.id, true); }

    const { data: event } = await withR2Columns(() => {
      const cols = ['organizer_id', ...chatGreetingColumnList()].join(', ');
      return supabase.from('events').select(cols).eq('id', key).maybeSingle();
    });
    if (!event?.organizer_id) return; // no real DB row for this event yet — nothing to open
    if (!existing?.id) set(prev => (stillHere(prev) && !prev.chatThreadId ? { chatDraftOrganizerId: event.organizer_id } : {}));
    if (event.chat_greeting || event.chat_greeting_en) set(prev => (stillHere(prev) ? { chatGreeting: event.chat_greeting || '', chatGreetingEn: event.chat_greeting_en || '' } : {}));
    if (!otherName) {
      const { data: org } = await supabase.from('organizers').select('name').eq('id', event.organizer_id).maybeSingle();
      if (org?.name) set(prev => (stillHere(prev) && !prev.chatOtherName ? { chatOtherName: org.name } : {}));
    }
  }, [set, s.user, s.realEventsById, loadChatMessages]);
  // Inserts the threads row for an open "draft" chat — the only place a
  // conversation is ever created. Returns the thread id (or null on failure).
  // An in-flight promise is shared so a double tap can't insert twice.
  const ensureChatThread = useCallback(async () => {
    if (s.chatThreadId) return s.chatThreadId;
    const organizerId = s.chatDraftOrganizerId;
    const key = s.eventKey;
    if (!s.user || !organizerId) return null;
    if (chatThreadCreateRef.current?.key === key) return chatThreadCreateRef.current.promise;
    const promise = (async () => {
      let id = null;
      const { data: created, error } = await supabase
        .from('threads')
        .insert({ event_id: key, guest_id: s.user.id, organizer_id: organizerId })
        .select('id')
        .maybeSingle();
      if (error) {
        // Another tab/request created it first — fetch what's there now.
        const { data: retry } = await supabase.from('threads').select('id').eq('event_id', key).eq('guest_id', s.user.id).maybeSingle();
        id = retry?.id || null;
      } else {
        id = created?.id || null;
      }
      if (id) set(prev => (prev.screen === 'chat' && prev.eventKey === key ? { chatThreadId: id, chatDraftOrganizerId: null } : {}));
      return id;
    })();
    chatThreadCreateRef.current = { key, promise };
    promise.finally(() => { if (chatThreadCreateRef.current?.promise === promise) chatThreadCreateRef.current = null; });
    return promise;
  }, [set, s.user, s.chatThreadId, s.chatDraftOrganizerId, s.eventKey]);
  // "Message the host" from an event/organizer/refund screen — always about
  // whichever event is currently open.
  const goChat = useCallback(() => openChatFor(s.eventKey, 'event'), [openChatFor, s.eventKey]);
  // Opens a specific, already-known thread — used from Inbox, on either side
  // (guest continuing a conversation, or organizer replying to a guest).
  const openThread = useCallback((threadId, eventKey, back, otherName) => {
    const isCatalog = EVENTS.some(e => e.key === eventKey);
    set({ screen: 'chat', eventKey, chatBack: back || 'inbox', chatThreadId: threadId, chatDraftOrganizerId: null, chatMessages: [], chatOtherName: otherName || '', chatGreeting: '', chatGreetingEn: '', chatGreetingFor: null, chatUnreadDividerId: null });
    loadChatMessages(threadId, true);
    // The other participant's name and (for a guest) the host's opening
    // message aren't known to every caller (a 'new_message' notification tap
    // passes neither), so resolve them from the thread itself. Never falls
    // back to a demo persona: a real event's host name comes from its
    // organizer row.
    const stillHere = (prev) => prev.screen === 'chat' && prev.chatThreadId === threadId;
    (async () => {
      const uid = s.user?.id;
      const { data: t } = await supabase.from('threads').select('guest_id, organizer_id').eq('id', threadId).maybeSingle();
      if (!t) return;
      const iAmGuest = t.guest_id === uid;
      if (!otherName) {
        let name = '';
        if (iAmGuest) {
          const { data: org } = await supabase.from('organizers').select('name').eq('id', t.organizer_id).maybeSingle();
          name = (org?.name || '').trim();
          if (!name && isCatalog) name = findEvent(eventKey)?.orgName || '';
        } else {
          const { data: prof } = await supabase.from('profiles').select('display_name').eq('id', t.guest_id).maybeSingle();
          name = (prof?.display_name || '').trim() || 'Khách';
        }
        if (name) set(prev => (stillHere(prev) && !prev.chatOtherName ? { chatOtherName: name } : {}));
      }
      if (iAmGuest) {
        let vi = s.realEventsById[eventKey]?.chatGreeting || '';
        let en = s.realEventsById[eventKey]?.chatGreetingEn || '';
        if (!vi && !en && chatGreetingColumnList().length) {
          const res = await withR2Columns(() => supabase.from('events').select(['id', ...chatGreetingColumnList()].join(', ')).eq('id', eventKey).maybeSingle());
          vi = res.data?.chat_greeting || '';
          en = res.data?.chat_greeting_en || '';
        }
        set(prev => (stillHere(prev) ? { chatGreeting: vi, chatGreetingEn: en, chatGreetingFor: eventKey } : {}));
      }
    })();
  }, [set, s.user?.id, s.realEventsById, loadChatMessages]);
  // openNotification is defined further down (after openAttendance exists to
  // route 'booking_requested' taps to it) — see the notifications section.
  const chatSend = useCallback(async () => {
    const text = s.chatDraft.trim();
    if (!text || !(s.chatThreadId || s.chatDraftOrganizerId) || !s.user) return;
    set({ chatDraft: '' });
    // First send of a draft chat creates the thread (lazy creation).
    const threadId = await ensureChatThread();
    if (!threadId) { console.warn('Failed to create thread'); set({ chatDraft: text }); return; }
    const { data, error } = await supabase
      .from('messages')
      .insert({ thread_id: threadId, sender_id: s.user.id, body: text, kind: 'text' })
      .select('id, sender_id, body, created_at')
      .maybeSingle();
    if (error) {
      console.warn('Failed to send message:', error);
      set({ chatDraft: text });
      return;
    }
    set(prev => ({ chatMessages: [...prev.chatMessages, data] }));
    // No email here any more — the in-app notification (via the
    // notify_new_message trigger) is the only notification a new message
    // gets; tapping it now takes you straight to the thread.
  }, [set, s.chatDraft, s.chatThreadId, s.chatDraftOrganizerId, s.user, ensureChatThread]);
  // Task 3 (2026-09-22 follow-up) — the chat-photo viewer's own bottom
  // composer (text reply / quick emoji reaction). A separate function from
  // `chatSend` rather than threading a `replyTo` param through it: this
  // viewer has its own LOCAL text state (not `s.chatDraft`, which belongs
  // to the main Chat screen's composer and shouldn't be touched by
  // something typed from inside a fullscreen photo viewer), and always
  // sets `reply_to_message_id` — migration 067, the smallest explicit
  // reference rather than encoding "replying to X" in the body text.
  // Task 5 (2026-09-22 twelfth follow-up) — `isTypedReply` distinguishes a
  // typed reply (draft's `doSendReply`/`sendReply`) from a one-tap quick
  // reaction (`doQuickReaction`/`quickReaction`) — only the former should
  // ever force the chat composer's keyboard open on return.
  const sendChatViewerReply = useCallback(async (text, replyToMessageId, isTypedReply) => {
    const trimmed = (text || '').trim();
    if (!trimmed || !s.chatThreadId || !s.user) return { success: false };
    const { data, error } = await supabase
      .from('messages')
      .insert({ thread_id: s.chatThreadId, sender_id: s.user.id, body: trimmed, kind: 'text', reply_to_message_id: replyToMessageId || null })
      .select('id, sender_id, body, kind, created_at, read_at, attachment_path, attachment_type, attachment_width, attachment_height, reply_to_message_id')
      .maybeSingle();
    // On failure, ChatPhotoViewer.jsx's own caller keeps the viewer open and
    // shows its existing error messaging — nothing here navigates away.
    if (error) { console.warn('sendChatViewerReply failed:', error); return { success: false }; }
    // Success — close the viewer and return straight to the (already-
    // mounted-underneath, since the viewer is an overlay not a separate
    // screen) source thread, scrolled to this new message.
    set(prev => ({
      chatMessages: [...prev.chatMessages, data],
      chatPhotoViewer: null,
      chatScrollToMessageId: data.id,
      chatFocusComposer: !!isTypedReply,
    }));
    return { success: true };
  }, [set, s.chatThreadId, s.user]);
  // Task 4 (2026-09-21 follow-up) — the composer's "+" attach flow.
  // Reuses normalizeProofFile() (src/lib/proofUpload.js, already built for
  // this exact problem on the payment-proof/receipt upload paths: HEIC/oversized
  // photos re-encoded to a JPEG that fits) rather than writing a second
  // resize pipeline — its 5MB cap is more conservative than the
  // 'chat-attachments' bucket's own 20MB, which is fine. `body` can't be
  // empty (NOT NULL) so an attachment-only message gets a short placeholder
  // that still reads sensibly anywhere body is shown without attachment
  // awareness (Inbox snippet, notification preview).
  const sendChatAttachment = useCallback(async (file, replyToMessageId) => {
    if (!file || !(s.chatThreadId || s.chatDraftOrganizerId) || !s.user) return { success: false };
    try {
      const { blob, ext, contentType, width, height } = await normalizeProofFile(file);
      const threadId = await ensureChatThread();
      if (!threadId) throw new Error('could not create thread');
      const path = `${threadId}/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('chat-attachments').upload(path, blob, { contentType });
      if (upErr) throw upErr;
      const { data, error } = await supabase
        .from('messages')
        .insert({
          thread_id: threadId, sender_id: s.user.id, kind: 'text',
          body: contentType === 'application/pdf' ? T('Đã gửi một tệp', 'Sent a file') : T('Đã gửi một ảnh', 'Sent a photo'),
          attachment_path: path, attachment_type: contentType,
          attachment_width: width || null, attachment_height: height || null,
          reply_to_message_id: replyToMessageId || null,
        })
        .select('id, sender_id, body, kind, created_at, read_at, attachment_path, attachment_type, attachment_width, attachment_height, reply_to_message_id')
        .maybeSingle();
      if (error) throw error;
      // Task 5 (2026-09-22 twelfth follow-up) — same close/scroll handoff as
      // sendChatViewerReply, only when this send actually came from the
      // photo viewer's own reply-attach flow (replyToMessageId is never set
      // by Chat.jsx's own composer/camera attach paths).
      set(prev => ({
        chatMessages: [...prev.chatMessages, data],
        ...(replyToMessageId ? { chatPhotoViewer: null, chatScrollToMessageId: data.id, chatFocusComposer: false } : {}),
      }));
      signChatAttachmentUrls([path]);
      return { success: true };
    } catch (e) {
      console.warn('sendChatAttachment failed:', e);
      return { success: false };
    }
  }, [set, s.chatThreadId, s.chatDraftOrganizerId, s.user, T, signChatAttachmentUrls, ensureChatThread]);

  // 2026-09-21 follow-up — chat photo fullscreen viewer (Task 2,
  // 07-notifications.md / 14-photo-viewer.md). A SEPARATE state slice from
  // `photoViewer` (event-gallery photos) — see the field's own comment.
  const openChatPhoto = useCallback((item, originRect) => {
    set({ chatPhotoViewer: { ...item, originRect: originRect ? { top: originRect.top, left: originRect.left, width: originRect.width, height: originRect.height } : null, forwardOpen: false } });
  }, [set]);
  const closeChatPhoto = useCallback(() => set({ chatPhotoViewer: null }), [set]);

  // Save/Download — fetches the SAME authorized signed URL already shown
  // inline (never a public/permanent URL, per this ticket's own security
  // instruction) and downloads the real bytes, not a screenshot of the UI.
  const downloadChatPhoto = useCallback(async () => {
    const item = s.chatPhotoViewer;
    if (!item?.url) return;
    try {
      const res = await fetch(item.url);
      if (!res.ok) throw new Error('fetch failed');
      const blob = await res.blob();
      const ext = (item.attachmentPath || '').split('.').pop() || 'jpg';
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `banbe-photo-${item.messageId || Date.now()}.${ext}`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(a.href);
      return { success: true };
    } catch (e) {
      console.warn('downloadChatPhoto failed:', e);
      return { success: false };
    }
  }, [s.chatPhotoViewer]);

  // Share — Web Share API (with the real file, where the browser supports
  // sharing files) falling back to the same download path above.
  const shareChatPhoto = useCallback(async () => {
    const item = s.chatPhotoViewer;
    if (!item?.url) return { success: false };
    try {
      const res = await fetch(item.url);
      const blob = await res.blob();
      const ext = (item.attachmentPath || '').split('.').pop() || 'jpg';
      const file = new File([blob], `banbe-photo.${ext}`, { type: blob.type || 'image/jpeg' });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file] });
        return { success: true };
      }
    } catch (e) {
      // A user-cancelled share() rejects too — not a real failure, just no-op.
      if (e?.name === 'AbortError') return { success: false };
      console.warn('shareChatPhoto failed, falling back to download:', e);
    }
    return downloadChatPhoto();
  }, [s.chatPhotoViewer, downloadChatPhoto]);

  const openChatForward = useCallback(() => set(prev => ({ chatPhotoViewer: prev.chatPhotoViewer ? { ...prev.chatPhotoViewer, forwardOpen: true } : null })), [set]);
  const closeChatForward = useCallback(() => set(prev => ({ chatPhotoViewer: prev.chatPhotoViewer ? { ...prev.chatPhotoViewer, forwardOpen: false } : null })), [set]);

  // Forward — `chat_attachments_participant_read` (migration 065) grants
  // read access by the OBJECT'S OWN path prefix (the thread id it lives
  // under), not by the message row that references it — so a forwarded
  // message can't just point at the SOURCE thread's copy of the path,
  // or the target thread's other participant (who isn't in the source
  // thread) would get a permission-denied signing the URL. Copies the real
  // bytes (same authorized original — fetched via the same signed URL
  // already shown, never a public one) into a new object under the TARGET
  // thread's own path, so its normal RLS grants it there like any other
  // attachment. Only thread ids the sender is actually a participant of
  // are ever offered (s.inboxThreads).
  const forwardChatPhoto = useCallback(async (targetThreadId) => {
    const item = s.chatPhotoViewer;
    if (!item?.attachmentPath || !item?.url || !s.user || !targetThreadId) return { success: false };
    try {
      const res = await fetch(item.url);
      if (!res.ok) throw new Error('fetch failed');
      const blob = await res.blob();
      const ext = item.attachmentPath.split('.').pop() || 'jpg';
      const attachmentType = blob.type || (ext === 'pdf' ? 'application/pdf' : 'image/jpeg');
      const newPath = `${targetThreadId}/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('chat-attachments').upload(newPath, blob, { contentType: attachmentType });
      if (upErr) throw upErr;
      const { error } = await supabase.from('messages').insert({
        thread_id: targetThreadId, sender_id: s.user.id, kind: 'text',
        body: T('Đã chuyển tiếp một ảnh', 'Forwarded a photo'),
        attachment_path: newPath, attachment_type: attachmentType,
        attachment_width: item.width || null, attachment_height: item.height || null,
      });
      if (error) throw error;
      closeChatForward();
      return { success: true };
    } catch (e) {
      console.warn('forwardChatPhoto failed:', e);
      return { success: false };
    }
  }, [s.chatPhotoViewer, s.user, T, closeChatForward]);

  const chatOnKey = useCallback((e) => { if (e.key === 'Enter') chatSend(); }, [chatSend]);
  const chatBackFn = useCallback(() => set(prev => ({ screen: prev.chatBack === 'inbox' || prev.chatBack === 'notifications' || prev.chatBack === 'paymentDetails' ? prev.chatBack : 'event' })), [set]);

  // A real, permanent delete, own messages only — RLS (messages_delete_own,
  // migration 054) scopes this to `sender_id = auth.uid()`, which a system
  // message (sender_id NULL) can never match. Unlike dispute_messages
  // (05-notify-retention.md's 72h retention requirement), this table has no
  // documented retention requirement, so no soft-delete here either.
  const deleteMessage = useCallback(async (id) => {
    const prevMessages = s.chatMessages;
    set(prev => ({ chatMessages: prev.chatMessages.filter(m => m.id !== id) }));
    const { error } = await supabase.from('messages').delete().eq('id', id);
    if (error) {
      console.warn('Failed to delete message:', error);
      set({ chatMessages: prevMessages }); // put it back — the delete didn't actually happen
    }
  }, [set, s.chatMessages]);

  // While the chat screen is open, poll for messages the other side sent —
  // there's no realtime subscription here, just a simple refresh.
  useEffect(() => {
    if (s.screen !== 'chat' || !s.chatThreadId) return;
    const id = setInterval(() => loadChatMessages(s.chatThreadId), 4000);
    return () => clearInterval(id);
  }, [s.screen, s.chatThreadId, loadChatMessages]);

  // ---- create / org profile ----
  const orgRegNameType = useCallback((e) => set({ orgRegName: e.target.value }), [set]);
  const orgRegIgType = useCallback((e) => set({ orgRegIg: e.target.value }), [set]);
  const orgRegDescType = useCallback((e) => set({ orgRegDesc: e.target.value }), [set]);

  /**
   * Host tab's own profile card save (Stage D, migration 090) — a real
   * owner/admin-gated update, separate from create_event_draft's own
   * organizer-name side effect. Optionally uploads a new avatar first
   * (organizer-photos bucket, path-scoped to this organizer's own id —
   * never another host's, see migration 090's own storage policies).
   */
  const setAccountTab = useCallback((tab) => set({ accountTab: tab }), [set]);

  const saveOrganizerProfile = useCallback(async (avatarFile) => {
    if (!s.myOrganizerId) return;
    set({ orgProfileSaving: true, orgProfileError: '', orgProfileSaved: false });
    try {
      let avatarPath = null;
      let avatarR2Ref = '';
      if (avatarFile) {
        if (!['image/jpeg', 'image/png', 'image/webp'].includes(avatarFile.type)) throw new Error('INVALID_IMAGE_TYPE');
        if (avatarFile.size > 5 * 1024 * 1024) throw new Error('IMAGE_TOO_LARGE');
        // R2 media API first (server decides eligibility); legacy upload on `provider:'supabase'`.
        const viaApi = await tryMediaApiUpload({ kind: 'organizer_avatar', organizerId: s.myOrganizerId, file: avatarFile });
        if (viaApi.provider === 'r2') { avatarPath = viaApi.ref; avatarR2Ref = viaApi.ref; }
      }
      if (avatarFile && !avatarPath) {
        let blob = avatarFile, ext = (avatarFile.name.split('.').pop() || 'jpg').toLowerCase(), contentType = avatarFile.type;
        try {
          const normalized = await normalizeImageForUpload(avatarFile, AVATAR_UPLOAD_BUDGET);
          ({ blob, ext, contentType } = normalized);
        } catch {
          // CONVERT_FAILED — upload the original rather than block the host.
        }
        const path = `${s.myOrganizerId}/avatar-${Date.now()}.${ext}`;
        const { error: upErr } = await supabase.storage.from('organizer-photos').upload(path, blob, { upsert: true, contentType, cacheControl: '31536000' });
        if (upErr) throw upErr;
        avatarPath = path;
      }
      const links = s.orgRegLinks.filter(l => l.url.trim());
      const { data, error } = await supabase.rpc('update_organizer_profile', {
        p_organizer_id: s.myOrganizerId,
        p_name: s.orgRegName.trim(),
        p_intro: s.orgRegDesc.trim(),
        p_avatar_path: avatarPath,
        p_intro_long: s.orgRegIntroLong,
        p_social_links: links,
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
      // DATA FRESHNESS FIX — `organizerProfile` is a one-shot snapshot
      // fetched by openOrganizerProfile() when this screen was opened;
      // this RPC call is a real, successful DB write, but nothing was
      // ever patching that snapshot back afterward. Only
      // `myOrganizerAvatarPath` (the Account org-card's own source) used
      // to get refreshed here, so once this screen's local avatarPreview
      // was cleared post-save it fell back to `organizerProfile.avatar_path`
      // — the stale pre-save value — until the whole screen was re-opened
      // (a fresh RPC refetch). Fixed by patching ONLY the fields this save
      // actually changed onto the already-loaded record in place, rather
      // than a blanket refetch or leaving a stale local copy around.
      set(prev => ({
        orgProfileSaving: false, orgProfileSaved: true,
        myOrganizerAvatarPath: avatarPath || prev.myOrganizerAvatarPath,
        myOrganizerAvatarR2Ref: avatarPath ? avatarR2Ref : prev.myOrganizerAvatarR2Ref,
        organizerProfile: (prev.organizerProfile && prev.organizerProfile.id === prev.myOrganizerId)
          ? {
              ...prev.organizerProfile,
              name: prev.orgRegName.trim(),
              about: prev.orgRegDesc.trim(),
              avatar_path: avatarPath || prev.organizerProfile.avatar_path,
              avatar_r2_ref: avatarPath ? avatarR2Ref : prev.organizerProfile.avatar_r2_ref,
              intro_long: prev.orgRegIntroLong,
              social_links: links,
            }
          : prev.organizerProfile,
      }));
    } catch (err) {
      console.warn('saveOrganizerProfile failed:', err);
      const message = err.message === 'INVALID_NAME'
        ? T('Tên tổ chức không được để trống (tối đa 80 ký tự).', 'Organizer name is required (max 80 chars).')
        : err.message === 'INVALID_INTRO'
        ? T('Giới thiệu tối đa 2000 ký tự.', 'Introduction is limited to 2000 characters.')
        : err.message === 'INTRO_TOO_LONG'
        ? T('Giới thiệu dài quá (tối đa 4000 ký tự).', 'Intro is too long (4000 characters max).')
        : err.message === 'INVALID_LINKS'
        ? T('Một liên kết không hợp lệ. Chỉ chấp nhận đường dẫn https://.', 'One of the links is invalid. Only https:// links are accepted.')
        : err.message === 'INVALID_IMAGE_TYPE'
        ? T('Ảnh phải là JPEG, PNG hoặc WebP.', 'Photo must be JPEG, PNG, or WebP.')
        : err.message === 'IMAGE_TOO_LARGE'
        ? T('Ảnh tối đa 5MB.', 'Photo must be under 5MB.')
        : (err.message || T('Không thể lưu. Vui lòng thử lại.', 'Could not save. Please try again.'));
      set({ orgProfileSaving: false, orgProfileError: message });
    }
  }, [set, s.myOrganizerId, s.orgRegName, s.orgRegDesc, s.orgRegIntroLong, s.orgRegLinks, s.myOrganizerAvatarPath, T]);

  const orgRegIntroLongType = useCallback((e) => set({ orgRegIntroLong: e.target.value }), [set]);
  const toggleOrgRegLinksOpen = useCallback(() => set(prev => ({ orgRegLinksOpen: !prev.orgRegLinksOpen })), [set]);
  const addOrgRegLink = useCallback(() => set(prev => ({ orgRegLinks: [...prev.orgRegLinks, { platform: 'website', url: '' }] })), [set]);
  const setOrgRegLink = useCallback((index, field, value) => set(prev => ({
    orgRegLinks: prev.orgRegLinks.map((l, i) => i === index ? { ...l, [field]: value } : l),
  })), [set]);
  const removeOrgRegLink = useCallback((index) => set(prev => ({ orgRegLinks: prev.orgRegLinks.filter((_, i) => i !== index) })), [set]);

  /**
   * Stage 1 (2026-09-27 nav/discovery pass) — Account host card's own
   * "Tổ chức từ <year> ▪︎ <N> sự kiện", read straight from real event
   * rows by organizer_id (never a stored/static total), same published-
   * only rule (status IN live/ended) as get_public_profile's event_count/
   * hosting_since_year (migration 091) so both places always agree.
   * Re-run whenever Account's host tab loads, so an admin approval or
   * cancellation since the last visit shows up without needing a reload.
   */
  const loadMyOrgStats = useCallback(async () => {
    if (!s.myOrganizerId) { set({ myOrgPublishedEventCount: null, myOrgHostingSinceYear: null }); return; }
    const { data, error } = await supabase
      .from('events')
      .select('status, starts_at')
      .eq('organizer_id', s.myOrganizerId)
      .in('status', ['live', 'ended']);
    if (error) { console.warn('loadMyOrgStats failed:', error); return; }
    const rows = data || [];
    const years = rows.map(r => r.starts_at ? new Date(r.starts_at).getFullYear() : null).filter(Boolean);
    set({
      myOrgPublishedEventCount: rows.length,
      myOrgHostingSinceYear: years.length ? Math.min(...years) : null,
    });
  }, [set, s.myOrganizerId]);

  const createNameType = useCallback((e) => set({ createName: e.target.value }), [set]);
  const createDescType = useCallback((e) => set({ createDesc: e.target.value }), [set]);
  const createIntroType = useCallback((e) => set({ createIntro: e.target.value }), [set]);
  const createChatGreetingType = useCallback((e) => set({ createChatGreeting: e.target.value.slice(0, 500) }), [set]);
  const createChatGreetingEnType = useCallback((e) => set({ createChatGreetingEn: e.target.value.slice(0, 500) }), [set]);
  const createKeywordsType = useCallback((e) => set({ createKeywords: e.target.value }), [set]);

  // Address-autocomplete fix pass (2026-09-28) — same stale-response-
  // discarding convention this file already uses for refund queues
  // (refundQueueSeq/refundCenterSeq above): `createAddressSeq` is bumped
  // on every new search, and a response only gets applied if it's still
  // the CURRENT search when it resolves. `createAddressTimer` is the
  // debounce (500ms) — Nominatim's own usage policy is for occasional
  // lookups, not raw keystroke-rate traffic; debouncing plus this app
  // having no paid Places key is why this is "a few candidates after a
  // short pause," not true instant-per-keystroke autocomplete.
  const createAddressSeq = useRef(0);
  const createAddressTimer = useRef(null);

  /**
   * Nominatim's `addressdetails=1` breakdown -> this app's own candidate
   * shape. A result with a house number AND a road becomes a normal
   * street address; one with neither but a real name (a POI/venue tag,
   * or Nominatim's own `name`) becomes a "verified venue" suggestion —
   * the ticket's own "support a verified named venue/POI... when a
   * conventional house number genuinely does not exist" case. A result
   * with NONE of those (Nominatim only matched a bare district/city, or a
   * road with no identifying name at all) is filtered out entirely here —
   * never offered as a selectable suggestion, since it cannot resolve to
   * a genuinely precise point. Missing district/city also disqualifies a
   * hit — this app's whole address model requires both.
   */
  function shapeAddressSuggestion(hit) {
    const addr = hit.address || {};
    const houseNumber = (addr.house_number || '').trim();
    const road = (addr.road || '').trim();
    const venueName = (hit.name || addr.amenity || addr.shop || addr.tourism || addr.leisure || addr.building || '').trim();
    const district = (addr.suburb || addr.city_district || addr.quarter || addr.district || addr.town || '').trim();
    const city = (addr.city || addr.state || addr.province || '').trim();
    const postalCode = (addr.postcode || '').trim();
    // Location hierarchy (migration 112) — previously discarded. Nominatim
    // returns `country_code` lowercase ("vn"); `state`/`province` is often
    // ABSENT for Ho Chi Minh City rows (treated as a municipality) and
    // present elsewhere (Da Lat -> "Tỉnh Lâm Đồng"); `neighbourhood`/
    // `quarter` only sometimes. Any of these may legitimately be null —
    // never a reason to reject the suggestion.
    const countryCode = (addr.country_code || '').trim().toUpperCase().slice(0, 2) || null;
    const stateProvince = (addr.state || addr.province || '').trim().slice(0, 100) || null;
    const neighborhood = (addr.neighbourhood || addr.quarter || '').trim().slice(0, 100) || null;
    let addressLine = '';
    let isVenue = false;
    if (houseNumber && road) {
      addressLine = `${houseNumber} ${road}`;
    } else if (venueName) {
      addressLine = venueName;
      isVenue = true;
    } else {
      return null;
    }
    if (!district || !city) return null;
    const lat = parseFloat(hit.lat);
    const lng = parseFloat(hit.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    return {
      id: String(hit.place_id ?? `${lat},${lng}`),
      addressLine, district, city, postalCode, isVenue, lat, lng,
      countryCode, stateProvince, neighborhood,
      label: hit.display_name || [addressLine, district, city].filter(Boolean).join(', '),
    };
  }

  /** Same geocoder + result shape Create Event's address search uses, but
   * stateless (returns the suggestions instead of writing create* state) so
   * the survey form can pick structured locations without touching the
   * event draft. */
  const searchAddressSuggestions = useCallback(async (query) => {
    try {
      const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&limit=5&q=${encodeURIComponent(query + ', Việt Nam')}`;
      const res = await fetch(url, { headers: { Accept: 'application/json' } });
      if (!res.ok) throw new Error('GEOCODE_HTTP_' + res.status);
      const rows = await res.json();
      const suggestions = (rows || []).map(shapeAddressSuggestion).filter(Boolean);
      return { suggestions, error: suggestions.length ? '' : T('Không tìm thấy địa chỉ nào. Thử ghi rõ số nhà và đường.', 'No addresses found. Try including a house number and street.') };
    } catch (err) {
      console.warn('searchAddressSuggestions failed:', err);
      return { suggestions: [], error: T('Không thể tìm địa chỉ lúc này. Kiểm tra kết nối rồi thử lại.', "Couldn't search addresses right now. Check your connection and retry.") };
    }
  }, [T]);

  const searchCreateAddress = useCallback(async (query) => {
    const seq = ++createAddressSeq.current;
    set({ createAddressSearching: true, createAddressSearchError: '' });
    try {
      const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&limit=5&q=${encodeURIComponent(query + ', Việt Nam')}`;
      const res = await fetch(url, { headers: { Accept: 'application/json' } });
      if (seq !== createAddressSeq.current) return; // a newer search has since started
      if (!res.ok) throw new Error('GEOCODE_HTTP_' + res.status);
      const rows = await res.json();
      if (seq !== createAddressSeq.current) return;
      const suggestions = (rows || []).map(shapeAddressSuggestion).filter(Boolean);
      set({
        createAddressSearching: false, createAddressSuggestions: suggestions,
        createAddressSearchError: suggestions.length ? '' : T(
          'Không tìm thấy địa chỉ nào. Thử ghi rõ số nhà và đường.',
          'No addresses found. Try including a house number and street.'
        ),
      });
    } catch (err) {
      if (seq !== createAddressSeq.current) return;
      console.warn('searchCreateAddress failed:', err);
      set({ createAddressSearching: false, createAddressSuggestions: [], createAddressSearchError: T(
        'Không thể tìm địa chỉ lúc này. Kiểm tra kết nối rồi thử lại.',
        "Couldn't search addresses right now. Check your connection and retry."
      ) });
    }
  }, [set, T]);

  const createLocType = useCallback((e) => {
    const value = e.target.value;
    if (createAddressTimer.current) clearTimeout(createAddressTimer.current);
    // A stale confirmation/resolved point for a since-edited search is
    // worse than none — see createLocConfirmed's own comment (state init,
    // above).
    set({
      createLoc: value, createLocConfirmed: false, createLat: null, createLng: null,
      createLocLabel: '', createAddressLine: '', createDistrict: '', createCity: '', createPostalCode: '',
      createCountryCode: '', createStateProvince: '', createNeighborhood: '',
      createAddressSuggestions: [], createAddressSearchError: '',
    });
    const query = value.trim();
    if (query.length < 4) { set({ createAddressSearching: false }); return; }
    createAddressTimer.current = setTimeout(() => { searchCreateAddress(query); }, 500);
  }, [set, searchCreateAddress]);

  /** Explicit retry — e.g. after a transient network failure, without the host needing to retype anything. */
  const retryCreateAddressSearch = useCallback(() => {
    const query = s.createLoc.trim();
    if (query.length < 4) return;
    searchCreateAddress(query);
  }, [s.createLoc, searchCreateAddress]);

  const selectCreateAddressSuggestion = useCallback((suggestion) => {
    if (createAddressTimer.current) clearTimeout(createAddressTimer.current);
    createAddressSeq.current += 1; // invalidate any still-in-flight search
    set({
      createAddressLine: suggestion.addressLine, createDistrict: suggestion.district,
      createCity: suggestion.city, createPostalCode: suggestion.postalCode,
      createCountryCode: suggestion.countryCode || '', createStateProvince: suggestion.stateProvince || '',
      createNeighborhood: suggestion.neighborhood || '',
      createLat: suggestion.lat, createLng: suggestion.lng,
      createLocLabel: suggestion.label, createLocConfirmed: true,
      createAddressSuggestions: [], createAddressSearching: false, createAddressSearchError: '',
    });
  }, [set]);

  /** "Adjust" — clears the confirmed selection so the host can search again, without losing what they'd typed. */
  const clearCreateAddressSelection = useCallback(() => set({
    createAddressLine: '', createDistrict: '', createCity: '', createPostalCode: '',
    createCountryCode: '', createStateProvince: '', createNeighborhood: '',
    createLat: null, createLng: null, createLocLabel: '', createLocConfirmed: false,
  }), [set]);
  const createEventDateType = useCallback((e) => set({ createEventDate: e.target.value }), [set]);
  const createEventTimeType = useCallback((e) => set({ createEventTime: e.target.value }), [set]);
  const createPriceType = useCallback((e) => set({ createPrice: e.target.value }), [set]);
  const createSeatsType = useCallback((e) => set({ createSeats: e.target.value }), [set]);
  const pickCreateCat = useCallback((key) => set(prev => {
    let cats = prev.createCats.includes(key) ? prev.createCats.filter(x => x !== key) : [...prev.createCats, key];
    if (cats.length > 2) cats = [cats[0], key];
    return { createCats: cats };
  }), [set]);
  const pickCreatePalette = useCallback((key) => set({ createPalette: key }), [set]);
  const pickCreateVisibility = useCallback((v) => set({ createVisibility: v === 'invite' ? 'invite' : 'public' }), [set]);
  const tapPhotoSlot = useCallback((index) => set(prev => ({ createPhotos: index < prev.createPhotos ? prev.createPhotos : Math.min(8, prev.createPhotos + 1) })), [set]);

  // ---- structured "Bao gồm" (migration 087) — up to 3 { label, detail } ----
  const addCreateIncludedItem = useCallback(() => set(prev => (
    prev.createIncludedItems.length >= 3 ? prev : { createIncludedItems: [...prev.createIncludedItems, { label: '', detail: '' }] }
  )), [set]);
  const removeCreateIncludedItem = useCallback((index) => set(prev => ({
    createIncludedItems: prev.createIncludedItems.filter((_, i) => i !== index),
  })), [set]);
  const setCreateIncludedItem = useCallback((index, field, value) => set(prev => ({
    createIncludedItems: prev.createIncludedItems.map((it, i) => (i === index ? { ...it, [field]: value } : it)),
  })), [set]);

  /**
   * Excel bulk-create (Stage C) — fills the SAME create-form fields a
   * manual entry would, from `excelEventImport.js`'s own `parsed` shape.
   * Deliberately just a form fill, same as tapping every field by hand:
   * this alone never creates or submits anything — only the form's own
   * "Gửi để duyệt" (createSubmit) does that, after the host has reviewed
   * the filled-in preview and corrected anything the import flagged.
   */
  const importParsedEvent = useCallback((parsed) => set({
    createName: parsed.name || '',
    createCats: parsed.categoryKey ? [parsed.categoryKey] : [],
    createDesc: parsed.description || '',
    createLoc: parsed.location || '',
    createEventDate: parsed.eventDate || '',
    createEventTime: parsed.eventTime ? parsed.eventTime.slice(0, 5) : '',
    createPrice: parsed.priceVnd ? String(parsed.priceVnd) : '',
    createSeats: parsed.capacity ? String(parsed.capacity) : '',
    createIncludedItems: Array.isArray(parsed.inclusions) ? parsed.inclusions : [],
    createIntro: parsed.intro || '',
  }), [set]);

  /**
   * Real cover/gallery upload for the create-event flow (migration 087's
   * schema + `update_event_media_and_details`). `files` are plain browser
   * `File` objects (CreateEvent.jsx's own local staging state, never
   * serialized into this global store). Same validation
   * `uploadEventPhoto` already enforces (JPEG/PNG/WebP, <=50MB — the
   * `event-photos` bucket's own limit, migration 005) — kept independent
   * of that function rather than reusing it verbatim, since this one also
   * needs each upload's own storage path back (to set as cover_image) and
   * an incrementing `sort_order` across the whole batch, neither of which
   * `uploadEventPhoto` (Dashboard's single "add one more photo" flow)
   * returns or does today.
   *
   * Never rolls back the just-created event on a partial failure (that
   * would risk a real, already-submitted review-queue row disappearing
   * out from under the host) — returns per-file outcomes so the caller can
   * show an honest "submitted, but N photos didn't upload" message instead
   * of silently claiming full success.
   */
  /**
   * Reconciles an event's gallery against the host's current staged state
   * in one pass — used by BOTH first-time creation (no `removeIds`, no
   * `existingCoverPath`) and editing an already-submitted/owned event
   * (STAGE A iOS-media-parity follow-up, 2026-09-26), so the two paths
   * can't silently drift apart. Order: removals first (so a re-picked
   * cover can never collide with a stale row), then new uploads, then a
   * single cover write — never rolls back the event row itself on a
   * partial media failure (see this function's own prior history above).
   */
  const reconcileEventMedia = useCallback(async (eventId, { newFiles = [], coverIndex = -1, removeIds = [], existingCoverPath = '', visibility = 'public' } = {}) => {
    // Strict invite-only events (migration 113) — an invite-only event's
    // photos go to the SEPARATE, genuinely private 'event-photos-private'
    // bucket (RLS-gated by host/admin/invited-status), never the public
    // 'event-photos' bucket whose getPublicUrl() bypasses RLS entirely.
    // Public events are completely unaffected (same bucket/path as always).
    const bucketId = visibility === 'invite' ? 'event-photos-private' : 'event-photos';
    let removed = 0;
    for (const photoId of removeIds) {
      const row = (s.eventPhotos || []).find(p => p.id === photoId);
      if (row?.r2_ref) {
        // Best-effort: server deletes the public R2 objects and nulls refs; the row delete below still runs.
        let accessToken = null;
        try { accessToken = (await supabase.auth.getSession())?.data?.session?.access_token || null; } catch { /* ignore */ }
        await deleteViaMediaApi({ ref: row.r2_ref, accessToken });
      }
      if (row?.storage_path && !row.storage_path.startsWith('r2:')) {
        const [rowBucket, ...rest] = row.storage_path.split('/');
        const bucket = rowBucket === 'event-photos-private' ? 'event-photos-private' : 'event-photos';
        const relative = bucket === rowBucket ? rest.join('/') : row.storage_path.replace(/^event-photos\//, '');
        await supabase.storage.from(bucket).remove([relative]);
      }
      const { error } = await supabase.from('event_photos').delete().eq('id', photoId);
      if (!error) removed++;
    }
    let uploaded = 0;
    let newCoverPath = '';
    for (let i = 0; i < newFiles.length; i++) {
      const file = newFiles[i];
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) continue;
      if (file.size > 50 * 1024 * 1024) continue;
      // R2 media API first (server decides eligibility — drafts/invite-only stay in Supabase).
      try {
        const viaApi = await tryMediaApiUpload({ kind: 'event_photo', eventId, file, setCover: i === coverIndex, sortOrder: i });
        if (viaApi.provider === 'r2') {
          uploaded++;
          if (i === coverIndex) newCoverPath = viaApi.ref;
          continue;
        }
      } catch (err) {
        console.warn('reconcileEventMedia media api failed after upload:', err?.code || 'error');
        continue;
      }
      let blob = file, ext = (file.name.split('.').pop() || 'jpg').toLowerCase(), contentType = file.type;
      try {
        const normalized = await normalizeImageForUpload(file, EVENT_PHOTO_UPLOAD_BUDGET);
        ({ blob, ext, contentType } = normalized);
      } catch {
        // CONVERT_FAILED — upload the original rather than block the host.
      }
      const path = `${eventId}/${Date.now()}-${i}.${ext}`;
      const { error: upErr } = await supabase.storage.from(bucketId).upload(path, blob, { upsert: true, contentType, cacheControl: '31536000' });
      if (upErr) { console.warn('reconcileEventMedia storage failed:', upErr); continue; }
      const storagePath = `${bucketId}/${path}`;
      const { error: rowErr } = await supabase.from('event_photos').insert({ event_id: eventId, storage_path: storagePath, sort_order: i });
      if (rowErr) { console.warn('reconcileEventMedia row failed:', rowErr); continue; }
      uploaded++;
      if (i === coverIndex) newCoverPath = storagePath;
    }
    const finalCover = newCoverPath || existingCoverPath;
    if (finalCover) {
      const { error } = await supabase.rpc('update_event_media_and_details', { p_event_id: eventId, p_cover_image: finalCover });
      if (error) console.warn('reconcileEventMedia cover update failed:', error);
    }
    return { uploaded, failed: newFiles.length - uploaded, removed };
  }, [s.eventPhotos]);
  /**
   * Event review queue — branches on `s.createEditEventId`: a fresh
   * submission goes through create_event_draft (INSERT, status becomes
   * 'review' — migration 085), while editing a previously-REJECTED event
   * (goEditEvent below) goes through resubmit_event_for_review (UPDATE the
   * SAME row, ownership + `status = 'draft'` enforced server-side, never a
   * second duplicate event row for the same submission).
   */
  /**
   * `photoFiles`/`coverIndex` — CreateEvent.jsx's own locally-staged
   * `File[]`/cover pick (never round-tripped through this global store —
   * see `createIncludedItems`' own comment on why). Uploaded AFTER the
   * event row itself exists (its real id isn't known before then — see
   * `submitEventMedia`'s own comment), so a photo-upload failure can never
   * turn into a duplicate/missing event submission, only an honest
   * "submitted, but N photos didn't upload" — never silently claimed as
   * fully successful.
   */
  // ---- Reservation criteria (migration 162; .claude/notes/34-onboarding-for-you-criteria.md) ----
  // A missing column/function means "feature off": treat as Everyone / eligible.
  const isMissingCriteriaColumn = (error) => !!error && (error.code === '42703' || error.code === 'PGRST204' || /reservation_criteria/i.test(error.message || ''));
  const setCreateCriteria = useCallback((c) => set({ createCriteria: c }), [set]);
  /** Loads an event's criteria into the cache; resolves to the criteria (Everyone when unsupported). */
  const loadEventCriteria = useCallback(async (eventId) => {
    if (!eventId) return everyoneCriteria();
    const { data, error } = await supabase.from('events').select('reservation_criteria').eq('id', eventId).maybeSingle();
    if (error) {
      if (!isMissingCriteriaColumn(error)) console.warn('loadEventCriteria failed:', error);
      return isMissingCriteriaColumn(error) ? everyoneCriteria() : null;
    }
    const c = normalizeCriteria(data?.reservation_criteria);
    set(prev => ({ eventCriteriaByKey: { ...prev.eventCriteriaByKey, [eventId]: c } }));
    return c;
  }, [set]);
  /** Pre-check for the signed-in guest; never blocks unless the server says ineligible. */
  const checkReservationEligibility = useCallback(async (eventId) => {
    if (!eventId || !s.user) return;
    const { data, error } = await supabase.rpc('check_my_reservation_eligibility', { p_event_id: eventId });
    if (error) { if (!isEventPrefsFnMissing(error)) console.warn('check_my_reservation_eligibility failed:', error); return; }
    if (data?.success !== true) return;
    set(prev => ({ eligibilityByKey: { ...prev.eligibilityByKey, [eventId]: data } }));
  }, [set, s.user]);
  /** Host edit: load the event's current criteria, ignoring a stale answer if the host moved to another event. */
  const loadCreateCriteria = useCallback(async (eventId) => {
    set({ createCriteria: everyoneCriteria(), createCriteriaLoaded: everyoneCriteria(), createCriteriaLoad: 'loading' });
    const { data, error } = await supabase.from('events').select('reservation_criteria').eq('id', eventId).maybeSingle();
    if (error) {
      const missing = isMissingCriteriaColumn(error);
      if (!missing) console.warn('loadCreateCriteria failed:', error);
      set(prev => (prev.createEditEventId === eventId ? { createCriteriaLoad: missing ? 'unsupported' : 'failed' } : {}));
      return;
    }
    const c = normalizeCriteria(data?.reservation_criteria);
    set(prev => (prev.createEditEventId === eventId
      ? { createCriteria: c, createCriteriaLoaded: c, createCriteriaLoad: 'ready', eventCriteriaByKey: { ...prev.eventCriteriaByKey, [eventId]: c } }
      : {}));
  }, [set]);
  /** Does this submit need a set_event_reservation_criteria call? Create: only a restriction. Edit: only a change. */
  const criteriaNeedsSave = () => {
    const want = normalizeCriteria(s.createCriteria);
    if (s.createEditEventId) {
      return s.createCriteriaLoad === 'ready' && JSON.stringify(want) !== JSON.stringify(normalizeCriteria(s.createCriteriaLoaded));
    }
    return !criteriaIsEveryone(want);
  };
  /** Resolves null on success, or an error object. Missing function while a restriction is wanted is a failure (never silently unrestricted). */
  const saveCriteriaFor = async (eventId) => {
    const { error } = await supabase.rpc('set_event_reservation_criteria', {
      p_event_id: eventId, p_criteria: normalizeCriteria(s.createCriteria),
    });
    if (error) { console.warn('set_event_reservation_criteria failed:', error); return error; }
    set(prev => ({ eventCriteriaByKey: { ...prev.eventCriteriaByKey, [eventId]: normalizeCriteria(s.createCriteria) } }));
    return null;
  };
  const criteriaSaveFailedMessage = () => T(
    'Sự kiện đã được gửi nhưng điều kiện đặt chỗ chưa được lưu. Hãy thử lại, sự kiện sẽ không mở cho mọi người nếu bạn đã chọn giới hạn.',
    'Your event was submitted but the reservation criteria were not saved. Please try again, the event will not go out unrestricted.'
  );

  const createSubmit = useCallback(async (photoFiles = [], coverIndex = 0, mediaOpts = {}) => {
    if (!s.createName.trim()) return;
    // Retry of ONLY the criteria save for an event that is already submitted
    // (status 'review' is not resubmittable): no second create, no media rerun.
    if (s.createCriteriaRetryEventId) {
      if (createSubmitInFlightRef.current) return;
      createSubmitInFlightRef.current = true;
      set({ loading: true, createError: '' });
      try {
        if (criteriaNeedsSave()) {
          const err = await saveCriteriaFor(s.createCriteriaRetryEventId);
          if (err) { set({ loading: false, createError: criteriaSaveFailedMessage() }); return false; }
        }
        set({ loading: false, createSent: true, hasHosted: true, mode: 'host', createCriteriaRetryEventId: null });
        return true;
      } finally { createSubmitInFlightRef.current = false; }
    }
    // Client-side submit-in-flight guard (task 1) — a SYNCHRONOUS,
    // non-reactive check-and-set, same pattern this app's own organizer-
    // mode toggle uses for the identical "repeated tap before the first
    // call resolves" problem (see 17-ux-foundation-release.md's
    // `organizerModeInFlight`) — a plain `@Published`/state-backed flag set
    // via `set()` only takes effect on the NEXT render, which is too late
    // to stop a second synchronous click handled before that render lands.
    // This is a NICETY, not the real guard: migration 107's server-side
    // duplicate-pending-event check (create_event_draft) and its atomic
    // `FOR UPDATE` row lock (resubmit_event_for_review) are what actually
    // make a duplicate/concurrent submission impossible — this only avoids
    // the round trip (and the confusing double-toast) for the common case.
    if (createSubmitInFlightRef.current) return;
    createSubmitInFlightRef.current = true;
    const { removePhotoIds = [], existingCoverPath = '', defaultKeywordsLabel = '' } = mediaOpts;
    set({ loading: true, createError: '', createMediaError: '' });
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session?.user) throw new Error('AUTH_REQUIRED');
      const priceVnd = parseInt((s.createPrice.match(/[\d.]+/) || ['0'])[0].replace(/\./g, ''), 10) || 0;
      const capacity = parseInt(s.createSeats, 10) || 0;
      const eventDate = s.createEventDate || null;
      const eventTime = s.createEventTime ? `${s.createEventTime}:00` : null;
      // Client-side nicety only — the RPC (migration 087/088) is the real
      // gate, converting the SAME date+time AT TIME ZONE 'Asia/Ho_Chi_Minh'.
      // Approximated the same way here so an obviously-past pick is caught
      // before a round trip, without needing a timezone library.
      if (eventDate && eventTime) {
        const nowVn = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Ho_Chi_Minh' }));
        const pickedVn = new Date(`${eventDate}T${eventTime}`);
        if (pickedVn.getTime() < nowVn.getTime() - 5 * 60 * 1000) throw new Error('PAST_EVENT_NOT_ALLOWED');
      }
      // Mirrors migration 087's own server-side validation (max 3, label
      // 1-60, detail <=300) — the RPC is the real gate; this only avoids a
      // round trip for an obviously-invalid client state.
      const includedItems = s.createIncludedItems
        .map(it => ({ label: it.label.trim(), detail: it.detail.trim() }))
        .filter(it => it.label.length > 0);
      for (const it of includedItems) {
        if (it.label.length > 60 || it.detail.length > 300) throw new Error('INVALID_INCLUDED_ITEMS');
      }
      // Mirrors migration 088's own 4000-char cap on "Giới thiệu sự kiện" —
      // same client-side-is-a-nicety/RPC-is-the-real-gate reasoning above.
      const intro = s.createIntro.trim();
      if (intro.length > 4000) throw new Error('INVALID_INTRO');

      // Keyword-search fix (migration 108) — the event's own selected
      // category label(s) (`defaultKeywordsLabel`, resolved by the caller
      // from the SAME `createCatLabel` the review screen already shows —
      // never a second, separate category->label mapping) are always
      // included, so an event is never left with literally nothing to
      // match on beyond its name/district.
      // Search-matcher fix (Issue 2) — previously a non-blank
      // `createKeywords` field REPLACED the category default entirely
      // (`s.createKeywords.trim() ? ... : defaultKeywordsLabel...`), which
      // is a real root cause of "insufficient" keyword coverage: an
      // organizer who typed their own keywords (e.g. person names, a
      // vibe word) silently lost the category terms from `keywords`
      // altogether. Organizer-entered keywords now SUPPLEMENT the category
      // default, never replace it — deduped, same 20-item cap
      // `set_event_keywords` (migration 108) already enforces server-side.
      const categoryKeywords = defaultKeywordsLabel.split(' ▪︎ ').map(k => k.trim()).filter(Boolean);
      const organizerKeywords = s.createKeywords.trim()
        ? s.createKeywords.split(',').map(k => k.trim()).filter(Boolean)
        : [];
      const keywords = Array.from(new Set([...categoryKeywords, ...organizerKeywords])).slice(0, 20);

      // Address-autocomplete fix pass (2026-09-28) — client-side mirror of
      // migration 105's own ADDRESS_NOT_VERIFIED gate, to avoid a round
      // trip for an obviously-incomplete address (the RPC is the real
      // gate, same "client check is a nicety" reasoning the included-items/
      // intro checks just above already follow). `createLocConfirmed` only
      // ever becomes true via `selectCreateAddressSuggestion` (a real
      // suggestion the host picked, this session) or `goEditEvent`
      // pre-filling an event that ALREADY had a verified address — either
      // way, every other address field is guaranteed populated whenever
      // this is true, so there's nothing left to separately null-check.
      if (!s.createLocConfirmed || !s.createAddressLine.trim() || !s.createDistrict.trim() || !s.createCity.trim() || s.createLat == null || s.createLng == null) {
        throw new Error('ADDRESS_NOT_VERIFIED');
      }

      // Editing: never overwrite criteria the host has not actually seen.
      if (s.createEditEventId && s.createCriteriaLoad === 'loading') throw new Error('CRITERIA_LOADING');
      if (s.createEditEventId && s.createCriteriaLoad === 'failed') throw new Error('CRITERIA_LOAD_FAILED');
      let criteriaError = null;
      let eventId = s.createEditEventId;
      if (s.createEditEventId) {
        const { data, error } = await supabase.rpc('resubmit_event_for_review', {
          p_event_id: s.createEditEventId,
          p_name: s.createName.trim(), p_category: s.createCats[0] || 'supper',
          p_description: s.createDesc.trim(), p_location: s.createDistrict.trim(),
          p_event_date: eventDate, p_event_time: eventTime,
          p_price_vnd: priceVnd, p_capacity: capacity,
          p_included_items: includedItems, p_intro: intro,
          p_lat: s.createLat, p_lng: s.createLng,
          p_address_line: s.createAddressLine.trim(), p_city: s.createCity.trim(),
          p_postal_code: s.createPostalCode.trim(), p_address_verified: true,
          // Location hierarchy (migration 112) — optional trailing params.
          // NULL (never '') when unknown: resubmit_event_for_review
          // COALESCEs a NULL back to the row's existing value, while ''
          // would be NULLIF'd into actively clearing it.
          p_country_code: s.createCountryCode.trim() || null,
          p_state_province: s.createStateProvince.trim() || null,
          p_neighborhood: s.createNeighborhood.trim() || null,
        });
        if (error) throw error;
        if (data?.success === false) throw new Error(data.error);
      } else {
        // Publishing an event is the act of hosting, so make sure organizer
        // mode is on before create_event_draft checks the profile role.
        if (!canHost) await applyOrganizerMode(true);
        const { data, error } = await supabase.rpc('create_event_draft', {
          p_name: s.createName.trim(),
          p_category: s.createCats[0] || 'supper',
          p_description: s.createDesc.trim(),
          p_location: s.createDistrict.trim(),
          p_event_date: eventDate,
          p_event_time: eventTime,
          p_price_vnd: priceVnd,
          p_capacity: capacity,
          p_organizer_name: s.orgRegName.trim() || 'Organizer',
          p_instagram: s.orgRegIg.trim(),
          p_about: s.orgRegDesc.trim(),
          p_included_items: includedItems,
          p_intro: intro,
          p_lat: s.createLat, p_lng: s.createLng,
          p_address_line: s.createAddressLine.trim(), p_city: s.createCity.trim(),
          p_postal_code: s.createPostalCode.trim(), p_address_verified: true,
          // Location hierarchy (migration 112) — optional trailing params.
          // NULL (never '') when unknown: resubmit_event_for_review
          // COALESCEs a NULL back to the row's existing value, while ''
          // would be NULLIF'd into actively clearing it.
          p_country_code: s.createCountryCode.trim() || null,
          p_state_province: s.createStateProvince.trim() || null,
          p_neighborhood: s.createNeighborhood.trim() || null,
        });
        if (error) throw error;
        eventId = data?.id || null;
        // iPhone fix pass (Stage 1) — create_event_draft's RETURNING row
        // already carries the real organizer_id (it creates the organizer
        // row itself on a host's very first submission), but this used to
        // go unused: myOrganizerId stayed null until the NEXT syncUser()
        // cycle (a full reload/relogin), so Account > Tổ chức's persistent
        // organizer card wouldn't appear right after creating a first
        // event — only after leaving and coming back — looking like its
        // visibility depended on having gone through dock + > Tạo sự
        // kiện, rather than on real organizer-management ability.
        if (data?.organizer_id) set({ myOrganizerId: data.organizer_id });
      }

      // Keyword-search fix (migration 108) — a separate, additive RPC
      // rather than a new param on create_event_draft/resubmit_event_for_review
      // (both already large, multiply-extended functions this pass
      // deliberately doesn't touch): owner-checked, SECURITY DEFINER,
      // does one thing. Best-effort — a failure here shouldn't block the
      // event submission itself, which already succeeded above.
      if (eventId) {
        const { error: keywordsError } = await supabase.rpc('set_event_keywords', {
          p_event_id: eventId, p_keywords: keywords,
        });
        if (keywordsError) console.warn('set_event_keywords failed:', keywordsError);

        // Strict invite-only events (migration 113) — same "separate,
        // additive RPC" pattern as set_event_keywords just above, not a
        // new positional param on create_event_draft/resubmit_event_for_
        // review. Best-effort like keywords: a failure here shouldn't
        // block a submission that already succeeded, but IS surfaced as a
        // non-fatal note since visibility is a real privacy setting, not
        // cosmetic metadata.
        const { error: visibilityError } = await supabase.rpc('set_event_visibility', {
          p_event_id: eventId, p_visibility: s.createVisibility,
        });
        if (visibilityError) console.warn('set_event_visibility failed:', visibilityError);

        // Reservation criteria (migration 162). NOT best-effort: a restriction the
        // host chose must not silently go out unrestricted. The event is already
        // in review (not resubmittable), so on failure we finish the remaining
        // steps and then report an error that retries ONLY this call.
        if (criteriaNeedsSave()) criteriaError = await saveCriteriaFor(eventId);

        // Host's opening message (migration 156) — plain owner update on
        // events (events_update_own); best-effort like keywords/visibility.
        // Skipped when the column isn't deployed yet, and on create when
        // there's nothing to store (an edit still writes '' -> NULL so a
        // host can clear a previous greeting).
        const greeting = s.createChatGreeting.trim().slice(0, 500);
        const greetingEn = s.createChatGreetingEn.trim().slice(0, 500);
        const greetingCols = chatGreetingColumnList();
        if (greetingCols.length && (greeting || greetingEn || s.createEditEventId)) {
          const patch = { chat_greeting: greeting || null };
          if (greetingCols.includes('chat_greeting_en')) patch.chat_greeting_en = greetingEn || null;
          let { error: greetingError } = await supabase.from('events').update(patch).eq('id', eventId);
          // Only 156 applied: retry without the English column.
          if (greetingError && 'chat_greeting_en' in patch && /chat_greeting_en/i.test(greetingError.message || '')) {
            delete patch.chat_greeting_en;
            ({ error: greetingError } = await supabase.from('events').update(patch).eq('id', eventId));
          }
          if (greetingError) {
            console.warn('chat_greeting update failed (apply migrations 156/157?):', greetingError);
          } else {
            set(prev => (prev.realEventsById[eventId] ? { realEventsById: { ...prev.realEventsById, [eventId]: { ...prev.realEventsById[eventId], chatGreeting: greeting, chatGreetingEn: greetingEn } } } : {}));
          }
        }
        reconcileEventMediaFireAndForget(eventId);
      }

      let mediaNote = '';
      if (eventId && (photoFiles.length || removePhotoIds.length || existingCoverPath)) {
        const { uploaded, failed } = await reconcileEventMedia(eventId, {
          newFiles: photoFiles, coverIndex, removeIds: removePhotoIds, existingCoverPath,
          visibility: s.createVisibility,
        });
        if (failed > 0) {
          mediaNote = uploaded > 0
            ? T(`Đã gửi sự kiện, nhưng ${failed} ảnh chưa tải lên được.`, `Event submitted, but ${failed} photo(s) didn't upload.`)
            : T('Đã gửi sự kiện, nhưng không tải được ảnh nào.', "Event submitted, but no photos could be uploaded.");
        }
      }

      // TASK 3 (event creation validation pass) — the 3-8 photo invariant
      // enforced in the TRUSTED WRITE PATH, not just the UI (migration
      // 109's own comment explains why this has to be a separate,
      // post-reconciliation RPC rather than a gate inside create_event_draft
      // itself). A failure here withdraws the event back to 'draft' with a
      // real rejection_reason server-side — this is a genuine submission
      // FAILURE, not a success with a note, so it must NOT set createSent.
      if (eventId) {
        const { data: finalizeData, error: finalizeError } = await supabase.rpc('finalize_event_photo_count', { p_event_id: eventId });
        if (finalizeError) console.warn('finalize_event_photo_count failed:', finalizeError);
        else if (finalizeData?.success === false && finalizeData?.error === 'PHOTO_COUNT_INVALID') {
          set({
            loading: false,
            createError: T(
              `Sự kiện cần 3-8 ảnh khả dụng (hiện có ${finalizeData.count}). Sự kiện đã được chuyển về bản nháp — hãy thêm/bớt ảnh rồi gửi lại.`,
              `This event needs 3-8 available photos (it has ${finalizeData.count}). It's been moved back to draft — add or remove photos, then resubmit.`
            ),
            createCriteriaRetryEventId: null,
          });
          return false;
        }
      }
      if (criteriaError) {
        set({ loading: false, createError: criteriaSaveFailedMessage(), createCriteriaRetryEventId: eventId, hasHosted: true });
        return false;
      }
      set({ loading: false, createSent: true, hasHosted: true, mode: 'host', createMediaError: mediaNote, createCriteriaRetryEventId: null });
      // TASK 3 (event creation validation pass) — the post-submission
      // chooser (CreateEvent.jsx) needs a real success/failure signal,
      // not just `createSent` (which this same function also sets, so a
      // caller reading `state.createSent` right after `await` would only
      // ever see the value from ITS OWN stale render closure).
      return true;
    } catch (err) {
      console.warn('Event draft creation failed:', err);
      const message = err.message === 'CRITERIA_LOADING'
        ? T('Đang tải điều kiện đặt chỗ hiện tại. Vui lòng thử lại sau giây lát.', 'Still loading the current reservation criteria. Please try again in a moment.')
        : err.message === 'CRITERIA_LOAD_FAILED'
        ? T('Không tải được điều kiện đặt chỗ hiện tại nên chưa thể gửi lại. Hãy mở lại sự kiện để sửa.', 'Could not load the current reservation criteria, so this cannot be resubmitted yet. Reopen the event to edit it.')
        : err.message === 'PAST_EVENT_NOT_ALLOWED'
        ? T('Ngày giờ sự kiện đã ở trong quá khứ.', "This event's date/time is in the past.")
        : err.message === 'INVALID_INCLUDED_ITEMS'
        ? T('Mỗi mục "Bao gồm" cần tên (tối đa 60 ký tự) và mô tả tối đa 300 ký tự.', 'Each "Included" item needs a label (max 60 chars) and detail under 300 chars.')
        : err.message === 'INVALID_INTRO'
        ? T('Giới thiệu sự kiện tối đa 4000 ký tự.', 'The event introduction is limited to 4000 characters.')
        : err.message === 'ADDRESS_NOT_VERIFIED'
        ? T('Hãy chọn một địa chỉ gợi ý và xác nhận vị trí trên bản đồ trước khi đăng.', 'Select a suggested address and confirm its pin before publishing.')
        // Migration 107's atomic resubmission-limit rejection — a banbe
        // product policy (2 successful resubmissions per rolling 24h),
        // never phrased as a legal/Ticketbox requirement.
        : err.message?.startsWith('RESUBMISSION_LIMIT_REACHED')
        ? T('Bạn đã gửi lại tối đa 2 lần trong 24 giờ qua. Vui lòng thử lại sau.', "You've already resubmitted this event twice in the last 24 hours. Please try again later.")
        // Migration 107's duplicate-pending-event guard — surfaced as an
        // actionable message rather than a raw Postgres exception string.
        : err.message?.startsWith('DUPLICATE_PENDING_EVENT')
        ? T('Sự kiện này đã đang chờ duyệt. Hãy sửa & gửi lại sự kiện đó thay vì tạo mới.', 'This event is already pending review. Edit and resubmit it instead of creating a new one.')
        : (err.message || 'Unable to submit this event.');
      set({ loading: false, createError: message });
      return false;
    } finally {
      createSubmitInFlightRef.current = false;
    }
  }, [set, s.createName, s.createCats, s.createDesc, s.createLoc, s.createLocConfirmed, s.createAddressLine, s.createDistrict, s.createCity, s.createPostalCode, s.createCountryCode, s.createStateProvince, s.createNeighborhood, s.createLat, s.createLng, s.createDate, s.createPrice, s.createSeats, s.createIncludedItems, s.createIntro, s.createKeywords, s.createChatGreeting, s.createChatGreetingEn, s.createCriteria, s.createCriteriaLoaded, s.createCriteriaLoad, s.createCriteriaRetryEventId, s.orgRegName, s.orgRegIg, s.orgRegDesc, s.createEditEventId, canHost, applyOrganizerMode, reconcileEventMedia, T]);
  const requestVerify = useCallback(() => set({ orgVerifyRequested: true }), [set]);

  /**
   * Opens CreateEvent pre-filled with a previously-REJECTED (status
   * 'draft', rejection_reason set) event's own real data, from Dashboard's
   * "Sửa & gửi lại" action. `resubmit_event_for_review` itself re-checks
   * both ownership and `status = 'draft'` — this is only what lets the
   * host actually SEE their own fields to correct, not the enforcement.
   */
  const goEditEvent = useCallback(async (eventId) => {
    const real = s.realEventsById[eventId];
    if (!real) return;
    set({
      // This state field ('dashboard') used to be named `createBack` and
      // was never actually read by anything — createBack the FUNCTION
      // hardcoded its own destination instead. Now the real source of
      // truth createBack reads (see its own comment above).
      screen: 'create', createOriginScreen: 'dashboard',
      createEditEventId: eventId, createSent: false, createError: '',
      createName: real.name || '', createCats: real.catKey ? [real.catKey] : [],
      createDesc: real.description || '',
      // Address-autocomplete fix pass (2026-09-28) — an event that
      // already has a verified address (migration 105) pre-fills it as
      // ALREADY confirmed — `resubmit_event_for_review` preserves it via
      // COALESCE even if this edit session never re-touches it, so
      // there's no reason to make the host re-search an address that was
      // already resolved. The search box (`createLoc`) itself stays
      // empty either way — it's a live search field now, not a display
      // of the current value — except for a pre-105 event with no
      // structured address yet, where seeding it with the old free-text
      // `area` at least gives the host a starting point to re-search from.
      createLoc: real.addressVerified ? '' : (real.area || ''),
      createLat: real.lat ?? null, createLng: real.lng ?? null,
      createLocLabel: real.addressVerified ? [real.addressLine, real.area, real.city].filter(Boolean).join(', ') : '',
      createAddressLine: real.addressLine || '', createDistrict: real.area || '',
      createCity: real.city || '', createPostalCode: real.postalCode || '',
      createCountryCode: real.countryCode || '', createStateProvince: real.stateProvince || '',
      createNeighborhood: real.neighborhood || '',
      createLocConfirmed: !!real.addressVerified,
      createAddressSuggestions: [], createAddressSearching: false, createAddressSearchError: '',
      createEventDate: real.eventDate || '', createEventTime: real.eventTime ? real.eventTime.slice(0, 5) : '',
      createPrice: real.priceVnd ? String(real.priceVnd) : '',
      createSeats: real.capacity ? String(real.capacity) : '',
      createVisibility: real.visibility || 'public',
      // Root-cause fix (Stage A media-parity pass, 2026-09-26): this used
      // to leave createIncludedItems at whatever the PREVIOUS screen visit
      // left behind (often []), and createSubmit always sends the current
      // createIncludedItems verbatim — resubmit_event_for_review's own
      // `COALESCE(p_included_items, included_items)` only preserves the old
      // value on a NULL param, not an empty array, so an edit could silently
      // wipe an event's real "Bao gồm" items. Re-seeding here from the same
      // row's own includedItems closes that gap.
      createIncludedItems: Array.isArray(real.includedItems) ? real.includedItems.map(it => ({ label: it.label || '', detail: it.detail || '' })) : [],
      createIntro: real.intro || '',
      createKeywords: Array.isArray(real.keywords) ? real.keywords.join(', ') : '',
      createChatGreeting: real.chatGreeting || '',
      createChatGreetingEn: real.chatGreetingEn || '',
      createCriteriaRetryEventId: null,
    });
    loadEventPhotos(eventId);
    loadCreateCriteria(eventId);
  }, [set, s.realEventsById, loadEventPhotos, loadCreateCriteria]);

  /**
   * Owner-only withdrawal of a PENDING ('review') submission (migration
   * 107, `withdraw_event_submission`). Requires a non-empty reason (the RPC
   * itself re-enforces this — this is only the client-side prompt).
   * Preserves the event row (never deletes/recreates it): the RPC moves it
   * to 'draft', the same status a rejection uses, with `withdrawal_reason`/
   * `withdrawn_at` recorded separately from `rejection_reason` so a
   * Dashboard row can tell the two apart. Does NOT touch the resubmission
   * counter — withdrawing itself never counts against the 2-per-24h limit
   * (a banbe product policy, not a legal/Ticketbox requirement — see the
   * migration's own comment). After a successful withdrawal, `goEditEvent`
   * re-uses the SAME event id to edit-and-resubmit, exactly like a
   * rejection's "Sửa & gửi lại" already does.
   */
  const withdrawEventSubmission = useCallback(async (eventId, reason) => {
    const trimmed = (reason || '').trim();
    if (!trimmed) { set({ withdrawEventError: T('Vui lòng nhập lý do rút lại.', 'Please enter a reason to withdraw.') }); return false; }
    set({ withdrawEventBusy: true, withdrawEventError: '' });
    try {
      const { data, error } = await supabase.rpc('withdraw_event_submission', {
        p_event_id: eventId, p_reason: trimmed,
      });
      if (error) throw error;
      if (data?.success !== false) reconcileEventMediaFireAndForget(eventId);
      if (data?.success === false) {
        const message = data.error === 'NOT_PENDING'
          ? T('Sự kiện này không còn ở trạng thái chờ duyệt.', 'This event is no longer pending review.')
          : data.error === 'REASON_REQUIRED'
          ? T('Vui lòng nhập lý do rút lại.', 'Please enter a reason to withdraw.')
          : T('Không thể rút lại lúc này.', 'Unable to withdraw this submission right now.');
        set({ withdrawEventBusy: false, withdrawEventError: message });
        return false;
      }
      // Reflect the new 'draft' status locally without a full reload —
      // same cache `goEditEvent`/loadRealEventsById already write into.
      set(prev => ({
        withdrawEventBusy: false,
        realEventsById: prev.realEventsById[eventId]
          ? { ...prev.realEventsById, [eventId]: { ...prev.realEventsById[eventId], status: 'draft', rejectionReason: '' } }
          : prev.realEventsById,
      }));
      return true;
    } catch (err) {
      console.warn('withdraw_event_submission failed:', err);
      set({ withdrawEventBusy: false, withdrawEventError: T('Không thể rút lại lúc này.', 'Unable to withdraw this submission right now.') });
      return false;
    }
  }, [set, T]);

  /**
   * Read-only "N attempts left" / "next eligible at" lookup (migration 107,
   * `get_event_resubmission_status`) — surfaced on Dashboard next to the
   * "Sửa & gửi lại" action so an organizer sees the limit BEFORE hitting it,
   * not just as an error after a 3rd attempt is rejected. This is a banbe
   * product policy (2 successful resubmissions per event per rolling 24h),
   * never described to the organizer as a legal or Ticketbox requirement.
   */
  const loadResubmissionStatus = useCallback(async (eventId) => {
    const { data, error } = await supabase.rpc('get_event_resubmission_status', { p_event_id: eventId });
    if (error || data?.success === false) { console.warn('get_event_resubmission_status failed:', error || data?.error); return; }
    set(prev => ({ resubmissionStatusByEvent: { ...prev.resubmissionStatusByEvent, [eventId]: { remaining: data.remaining_attempts, nextEligibleAt: data.next_eligible_at } } }));
  }, [set]);

  // ---- attendance ----
  // The guest list is real bookings for this event (not the old fake
  // GUESTS() generator), resolved to display names via the profiles row a
  // check-in host is now allowed to read (see the RLS policy added
  // alongside check_in_guest()'s notification).
  // TASK D — root cause of the "No one has booked… then flickers" report:
  // loadAttendanceGuests() runs 3 sequential awaited queries with no
  // request-ordering guard at all. A fast poll re-fire (the 6s interval in
  // Attendance.jsx) or two overlapping calls (a fresh openAttendance() plus
  // an in-flight poll tick) could let an OLDER, SLOWER response resolve
  // AFTER a newer one and overwrite it with stale data — including
  // momentarily replacing a real guest list with `[]`, which the empty-
  // state text then (correctly, given what it was told) renders as "no
  // guests" before the newer response's already-in-flight result lands a
  // moment later. `attendanceGuestsSeq` makes only the NEWEST call's
  // response ever allowed to write state.
  const attendanceGuestsSeq = useRef(0);
  const loadAttendanceGuests = useCallback(async (key) => {
    const seq = ++attendanceGuestsSeq.current;
    set({ attendanceLoading: true });
    // 'pending' belongs here too: an unpaid guest is exactly the one the
    // organizer needs to find in order to mark them paid. Expired holds are
    // dropped below so the list doesn't fill up with seats nobody holds.
    const { data: bookings, error } = await supabase
      .from('bookings')
      .select('id, user_id, qty, status, total_vnd, code, expires_at, paid_marked_at, paid_method, proof_path')
      .eq('event_id', key)
      .in('status', ['pending', 'confirmed', 'attended']);
    if (error) {
      console.warn('Failed to load attendance list:', error);
      if (seq === attendanceGuestsSeq.current) set({ attendanceGuests: [], attendanceLoading: false });
      return;
    }
    const userIds = [...new Set((bookings || []).map(b => b.user_id).filter(Boolean))];
    let names = {};
    if (userIds.length) {
      const { data: profiles } = await supabase.from('profiles').select('id, display_name').in('id', userIds);
      names = Object.fromEntries((profiles || []).map(p => [p.id, p.display_name]));
    }
    // Upload Receipt's reason prompt (08-payment-documents.md's 2026-09-17
    // follow-up #5) needs to know, per booking, whether a *live* receipt
    // already exists — upload_payment_document() (056) requires a reason
    // exactly when one does — plus how many superseded-but-still-queryable
    // copies (056's 24h soft-delete window) are still pending deletion, to
    // show next to the upload control.
    const bookingIds = (bookings || []).map(b => b.id);
    let docsByBooking = {};
    if (bookingIds.length) {
      const nowIso = new Date().toISOString();
      const { data: docs } = await supabase
        .from('payment_documents')
        .select('id, booking_id, superseded_at, purge_after')
        .eq('kind', 'receipt')
        .in('booking_id', bookingIds)
        .or(`superseded_at.is.null,purge_after.gt.${nowIso}`)
        .order('issued_at', { ascending: false });
      for (const d of docs || []) {
        const entry = docsByBooking[d.booking_id] || { live: 0, pendingDelete: 0, receipts: [] };
        if (d.superseded_at) entry.pendingDelete += 1; else entry.live += 1;
        // Each row individually tappable/openable, not just counted
        // (08-payment-documents.md's 2026-09-17 follow-up #7 — BUG 1).
        entry.receipts.push({ id: d.id, isLive: !d.superseded_at });
        docsByBooking[d.booking_id] = entry;
      }
    }
    const now = Date.now();
    const guests = (bookings || [])
      .filter(b => b.status !== 'pending' || !b.expires_at || new Date(b.expires_at).getTime() > now)
      .map(b => {
        const docInfo = docsByBooking[b.id] || { live: 0, pendingDelete: 0, receipts: [] };
        return {
          id: b.id,
          name: (names[b.user_id] || '').trim() || 'Khách',
          qty: b.qty,
          checkedIn: b.status === 'attended',
          // Paid means the organizer confirmed the money arrived — which is
          // also what issued the receipt. hold_seats marks instant-approval
          // bookings 'confirmed' up front, so status alone isn't the answer.
          paid: !!b.paid_marked_at,
          payMethod: b.paid_method || '',
          totalVnd: b.total_vnd || 0,
          code: b.code || '',
          hasProof: !!b.proof_path,
          hasReceipt: docInfo.live > 0,
          receiptVersionCount: docInfo.live + docInfo.pendingDelete,
          receiptPendingDelete: docInfo.pendingDelete,
          receipts: docInfo.receipts,
        };
      });
    // Only the newest in-flight request may write the guest list — see this
    // function's own doc comment above.
    if (seq === attendanceGuestsSeq.current) set({ attendanceGuests: guests, attendanceLoading: false });
  }, [set]);
  const openAttendance = useCallback((key, back = 'dashboard') => {
    // attendanceLoading explicitly true here too (not just inside
    // loadAttendanceGuests) — the very first render of Attendance.jsx must
    // never see attendanceGuests:[] paired with attendanceLoading:false,
    // which is exactly what would render the (wrong, not-yet-resolved)
    // empty-state text for one frame.
    //
    // TASK A — real root cause of the "ghost TDK404 row": refundCenterClaims/
    // refundCenterSelected were never cleared here, only ever replaced by
    // loadRefundCenter()'s own async response. Switching Attendance from one
    // event (or host session) to another rendered the PREVIOUS event's/
    // account's stale claims — including a claim that has nothing to do
    // with the event now on screen — for the entire window between mount
    // and that response landing (or forever, if it errored). Cleared
    // synchronously now, exactly like attendanceGuests already was.
    set({
      screen: 'attendance', attendanceEventKey: key, attendanceGuests: [], attendanceLoading: true, attendanceBack: back,
      refundCenterClaims: [], refundCenterSelected: [], refundBatchError: '',
    });
    loadAttendanceGuests(key);
    // 15-organizer-checkin.md: Attendance.jsx used to render `findEvent(key)`
    // directly, whose own `|| EVENTS[0]` fallback silently substituted the
    // first demo event ("Bếp Nhỏ №12") for any real, host-created event's
    // key. Same canonical realEventsById cache/fetch `curEvent` already
    // uses for EventDetail — a no-op if `key` is a bundled catalogue id or
    // already cached/in flight.
    if (key && !isCosmeticCatalogMatch(key)) loadRealEventsById([key]);
  }, [set, loadAttendanceGuests, loadRealEventsById]);
  const backFromAttendance = useCallback(() => set(prev => ({ screen: prev.attendanceBack || 'dashboard' })), [set]);

  // Reopens the Confirmed/ticket screen for a specific booking — used when
  // a 'payment_confirmed' notification arrives (or is tapped) after the
  // guest has moved on elsewhere in the app, since the booking that just
  // unlocked its QR code isn't necessarily the one in state.booking any more.
  const openBookingConfirmed = useCallback(async (bookingId, eventKey, back = 'home') => {
    const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
    // 2026-09-19 follow-up: `data: null` here is unambiguous — this
    // booking's own RLS (bookings_select_guest, `auth.uid() = user_id`)
    // can never spuriously deny the booking's own guest, the only
    // recipient a `payment_confirmed` notification is ever sent to, so an
    // empty result really does mean the row is gone. Returned (not just a
    // silent `return`) so openNotification() can tell its caller the
    // target was missing and react instead of doing nothing.
    if (!data) return { success: false, notFound: true };
    set({
      screen: 'confirmed',
      eventKey: eventKey || data.event_id,
      booking: data,
      confirmedBack: back,
      // Bug 3 (15-organizer-checkin.md follow-up): this used to read the
      // legacy `expires_at` mirror column, which hold_seats() sets once at
      // creation and NOTHING ever clears afterward — not confirm_payment()
      // (migration 060), not reject_pending_guest(). An organizer accepting
      // quickly (well within the original 30-min hold window) landed the
      // guest here with `holdDeadline` re-armed to that stale future
      // timestamp, which Home.jsx's own `heldEv`/`heldKey` (unrelated to
      // Confirmed.jsx's own phase logic, which already correctly prefers
      // `booking.hold_expires_at`) reads in isolation — so leaving this
      // screen for Home showed a "Đang giữ chỗ"/holding tag on an
      // already-confirmed booking's event card until something else
      // happened to clear it. `hold_expires_at` is the actively-maintained
      // column (NULL once confirmed/rejected) — using it here instead
      // means a confirmed booking never re-arms this at all.
      holdDeadline: data.hold_expires_at ? new Date(data.hold_expires_at).getTime() : null,
      now: Date.now(),
    });
    return { success: true };
  }, [set]);
  const backFromConfirmed = useCallback(() => set(prev => ({ screen: prev.confirmedBack || 'home' })), [set]);

  /**
   * The client-side half of forfeiting a lapsed PHASE 1 hold. Called the
   * instant a ticking countdown (Confirmed, PaymentDetails, Home's banner)
   * notices its own deadline has passed while still 'holding'.
   *
   * Every screen that shows "Going"/a ticket/the Reserve-vs-ticket toggle
   * reads this same booking's payment_state/status out of shared state —
   * never off a live countdown — so patching them here is what makes all
   * three update immediately, together, regardless of which screen actually
   * noticed the expiry. The server call alongside it is what makes that
   * true durably instead of just visually: without it, this booking would
   * sit at status='confirmed' (instant-approval events set that immediately,
   * before payment) until the next minutely sweep, or forever if the sweep
   * ever failed on it.
   */
  const forfeitExpiredHold = useCallback((booking) => {
    if (!booking?.id) return;
    const eventKey = booking.event_id;
    set(prev => ({
      attending: eventKey ? prev.attending.filter(k => k !== eventKey) : prev.attending,
      booking: prev.booking?.id === booking.id
        ? { ...prev.booking, payment_state: 'expired', status: 'expired' } : prev.booking,
      paymentBookings: prev.paymentBookings.map(b => (
        b.id === booking.id ? { ...b, payment_state: 'expired', status: 'expired' } : b
      )),
    }));
    supabase.rpc('forfeit_my_expired_hold', { p_booking: booking.id })
      .then(({ data, error }) => {
        if (error || data?.success === false) {
          console.warn('forfeitExpiredHold RPC failed:', error || data?.error);
        }
      });
  }, [set]);

  // A watchdog for every screen that ISN'T one of the three above watching
  // its own local countdown (Confirmed, PaymentDetails, Home). EventDetail
  // and EventList, in particular, only ever read booking.status/attending —
  // they never notice a lapse themselves — so staying on one of those past
  // the deadline used to leave "Going" and the ticket code showing forever,
  // since nothing else was mounted to call forfeitExpiredHold. This runs
  // centrally off the same ticking `now` regardless of which screen is on
  // top, and is naturally idempotent with the per-screen effects (all of
  // them route through this same forfeitExpiredHold, which itself only acts
  // once per lapse since payment_state flips to 'expired' immediately).
  useEffect(() => {
    const isLapsed = (b) => b && b.payment_state === 'holding' && b.hold_expires_at
      && msUntil(b.hold_expires_at, state.now) === 0;
    // state.booking covers the event currently open in EventDetail/Confirmed
    // even before paymentBookings has ever loaded (e.g. landing straight on
    // EventDetail on a fresh launch, never having passed through Home) —
    // it's populated as soon as eventKey resolves, independent of
    // loadPaymentBookings(). paymentBookings covers every OTHER hold this
    // account has open elsewhere, which state.booking alone can't see.
    const justLapsed = (isLapsed(state.booking) && state.booking)
      || (state.paymentBookings || []).find(isLapsed);
    if (justLapsed) forfeitExpiredHold(justLapsed);
  }, [state.paymentBookings, state.booking, state.now, forfeitExpiredHold]);

  // Tapping a notification marks it read and, for the kinds that point at
  // somewhere real, takes you there — a 'new_message' notification opens the
  // actual thread it's about instead of just sitting there read.
  const openNotification = useCallback(async (n) => {
    markNotificationRead(n.id);
    // 01-hold-payment.md follow-up (bug 1): both organizer-only
    // destinations below used to navigate unconditionally — relying on
    // `openVerifications()`'s own ACCOUNT-level gate (organizerMode ||
    // admin || hasHosted) or, for `openAttendance()`, nothing at all — and
    // RLS silently no-opping the actual data fetch as the only real
    // backstop. That's an account-wide check ("is this person an
    // organizer of ANYTHING"), not an EVENT-specific one, so any dual-role
    // account (this app's own explicit design — "one account for
    // everything, switch on organizer mode from Account" — the shared
    // fast-suite test account is exactly this) could land on another
    // organizer's screen for an event it only ever booked as a guest.
    // `myOrgEventKeys` (loadMyEvents(), populated at sign-in) is the real,
    // per-event ownership list — checked here so a non-owner is blocked
    // from the navigation itself, not just left looking at buttons that
    // silently no-op under RLS.
    const iOrganize = (eventId) => s.myOrgEventKeys.includes(eventId);
    // TASK 1 (2026-09-22 nineteenth follow-up) — the ONE shared existence
    // check (NOTIFICATION_TARGET_FIELD/targetIsGone, module scope above),
    // run BEFORE the switch so every kind it covers gets pruned identically
    // without repeating the same query per branch. payment_confirmed/
    // payment_document_uploaded/_replaced aren't in that table (see its own
    // comment) — they do their own richer existence+fetch inline below.
    if (await targetIsGone(n)) { reportStaleNotification(n); return; }
    // Every branch below passes 'notifications' as its destination's own
    // back-target (attendanceBack/verificationsBack/paymentBack/
    // confirmedBack/documentBack/chatBack — same field/default-param
    // pattern documentBack/paymentDetailsBackTarget already established) —
    // a screen reached from the bell always returns to the bell specifically,
    // not Home or wherever else (07-notifications.md's 2026-09-18 follow-up).
    //
    // TASK 1 (2026-09-22 nineteenth follow-up) — full routing contract for
    // every "confirmed active production" kind (07-notifications.md has the
    // authoritative table). Three outcomes per kind, per this ticket's own
    // A/B/C framework:
    //  A. real actionable target -> route to it (every case below except
    //     the final one).
    //  B. informational only, no destination by design -> the
    //     markNotificationRead() at the top of this function is the whole
    //     "action" (it visibly un-bolds the row) — falls to `default`.
    //  C. required target confirmed gone -> handled uniformly by the
    //     targetIsGone() guard above, before this switch even runs.
    switch (n.kind) {
      case 'new_message':
        if (n.data?.thread_id) openThread(n.data.thread_id, n.data.event_id, 'notifications');
        break;
      case 'booking_requested':
        // The organizer's side: straight to the check-in list for that
        // event, where "mark as paid" already lives (see Attendance.jsx).
        if (n.data?.event_id && iOrganize(n.data.event_id)) openAttendance(n.data.event_id, 'notifications');
        break;
      case 'event_approved':
      case 'event_rejected':
        // Event review queue — Dashboard is the one place the host can
        // already see their own real (non-catalogue) event's status/
        // rejection reason (see Dashboard.jsx's myEvents), same per-event
        // ownership guard as every other organizer-bound kind here.
        if (n.data?.event_id && iOrganize(n.data.event_id)) goDashboard();
        break;
      case 'payment_awaiting_verification':
      case 'payment_verification_nudge':
        // 01-hold-payment.md follow-up: fired by submit_payment_proof()
        // (031:317) when a guest reports having transferred — the
        // organizer side, still shown/actioned from Verifications ("Money
        // received"/"Can't find it"), not Attendance's check-in list.
        // payment_verification_nudge is the SLA-reminder twin of the same
        // event, same destination.
        if (n.data?.event_id && iOrganize(n.data.event_id)) openVerifications('notifications');
        break;
      case 'hold_created':
      case 'payment_needs_info':
        // 01-hold-payment.md follow-up: hold_created is the guest's own
        // mirror of 'booking_requested' (hold_seats(), migration 053) —
        // straight back to their own timer/QR/payment screen. payment_needs_info
        // is the organizer asking the guest for more proof/info on that
        // same booking — same destination, the guest's own payment screen
        // is where they'd respond.
        if (n.data?.booking_id) openPaymentDetails(n.data.booking_id, 'notifications');
        break;
      case 'payment_confirmed': {
        // 2026-09-19 follow-up: bookings.id under this kind's own RLS
        // (auth.uid() = user_id, the recipient by construction) can't
        // spuriously come back empty — a genuine miss means the booking
        // row itself is gone, not an access issue.
        if (n.data?.booking_id) {
          const result = await openBookingConfirmed(n.data.booking_id, n.data.event_id, 'notifications');
          if (result?.notFound) reportStaleNotification(n);
        }
        break;
      }
      case 'checked_in':
      case 'checkin_undone':
        // Both are check-in-status changes on an already-confirmed
        // booking — the guest's own payment/ticket screen already reflects
        // current status live, no separate "checked in" screen exists.
        if (n.data?.booking_id) openPaymentDetails(n.data.booking_id, 'notifications');
        break;
      case 'dispute_message':
      case 'dispute_resolved':
      case 'payment_disputed':
        // Only the guest and organizer ever receive these (migration
        // 048/050 — admin is deliberately excluded), so accountType alone
        // decides which screen has this booking's chat panel.
        // message_id may be absent on a row from before migration 050 —
        // DisputeChatPanel.jsx falls back to scrolling to the bottom.
        //
        // A REFUND dispute's message (migration 129) is the one kind that
        // isn't reachable from the payment screens at all — until this
        // ticket the goer and host had no chat to open from anywhere — so
        // it routes straight to the pinned dispute section in Messages with
        // that one entry expanded, which is also the only place the chat
        // lives for a refund dispute.
        if (n.data?.refund_claim_id) {
          const { data: refundThread } = await supabase
            .from('dispute_threads').select('id').eq('refund_claim_id', n.data.refund_claim_id).maybeSingle();
          if (refundThread?.id) {
            set({ chatHighlight: { refundClaimId: n.data.refund_claim_id, messageId: n.data.message_id || null } });
            openDisputeChatInInbox(refundThread.id);
          }
        } else if (n.data?.booking_id) {
          set({ chatHighlight: { bookingId: n.data.booking_id, messageId: n.data.message_id || null } });
          if (s.accountType === 'organizer') openVerifications('notifications');
          else openPaymentDetails(n.data.booking_id, 'notifications');
        }
        break;
      case 'payment_document_uploaded':
      case 'payment_document_replaced': {
        // 2026-09-19 follow-up (the CONFIRMED real repro: a bulk
        // payment_documents cleanup this session directly deleted every
        // row, orphaning any notification of this kind created before it)
        // — same RLS reasoning as payment_confirmed above.
        if (n.data?.document_id) {
          const result = await openDocumentFromNotification(n.data.document_id, 'notifications');
          if (result?.notFound) reportStaleNotification(n);
        }
        break;
      }
      case 'payment_document_expiring_1d':
        // Already covered by the shared targetIsGone() guard above
        // (document_id, 'documents' table) — if we reach here the document
        // is still live, so this is just a heads-up straight to it.
        if (n.data?.document_id) {
          const result = await openDocumentFromNotification(n.data.document_id, 'notifications');
          if (result?.notFound) reportStaleNotification(n);
        }
        break;
      case 'receipt_requested':
        // The guest's own "Xem Receipt" (Confirmed.jsx) asked for one that
        // doesn't exist yet — straight to Check-in, same per-event
        // ownership guard as every other organizer-bound kind above, with
        // the specific booking's own "Upload receipt" control
        // auto-highlighted (Attendance.jsx's attendanceHighlightBookingId)
        // so the organizer doesn't have to hunt for it in a long list.
        if (n.data?.event_id && iOrganize(n.data.event_id)) {
          set({ attendanceHighlightBookingId: n.data.booking_id });
          openAttendance(n.data.event_id, 'notifications');
        }
        break;
      case 'booking_cancelled':
      case 'booking_declined':
      case 'hold_expired':
        // The booking/hold itself is gone (rejected/cancelled/expired) —
        // never a hard-deleted `events` row anywhere in this schema, so no
        // existence check needed. The event itself is still the one
        // meaningful place to land: "you can look at it again," same as
        // this app's own event-cancellation UX language elsewhere.
        if (n.data?.event_id) goEvent(n.data.event_id);
        break;
      case 'event_invite':
        // Strict invite-only events (migration 113) — straight to the
        // event itself; events_select_invited RLS already lets this
        // recipient load it (a pending invite is enough), and EventDetail
        // shows its own accept/decline banner once there by querying
        // event_invites for the signed-in user directly (never trusts
        // notification.data for the invite's live status).
        if (n.data?.event_id) goEvent(n.data.event_id);
        break;
      case 'refund_marked_sent':
        // Guest-facing: the host reported sending the refund — straight
        // back to the same booking's Payment screen, where the new
        // host_marked_sent card (with "Đã nhận tiền"/"Chưa nhận được")
        // lives. targetIsGone() above already confirmed the claim itself
        // still exists.
        if (n.data?.booking_id) openPaymentDetails(n.data.booking_id, 'notifications');
        break;
      case 'refund_confirmed':
      case 'refund_disputed':
      case 'refund_overdue':
        // Organizer-facing: all three land on the refund queue living
        // inside Verifications.jsx (this ticket's own "smallest possible
        // queue inside the already-relevant surface" ask, not a new
        // screen). Scoped to event ownership like every other
        // organizer-bound kind above.
        if (n.data?.event_id && iOrganize(n.data.event_id)) {
          set({ refundQueueFocusClaimId: n.data.claim_id || null });
          openVerifications('notifications');
        }
        break;
      case 'organizer_renamed': {
        // Stage D (2026-09-26) — this app has no standalone "view an
        // organizer's page by id" route at all (Organizer.jsx is entirely
        // anchored to curEvent — see its own ev.orgName-keyed reads); a
        // genuinely-real deep link here is the organizer's own soonest
        // real upcoming event, one tap ("Người tổ chức") from the actual
        // organizer page, rather than fabricating a route that doesn't
        // exist. Never fails silently: reportStaleNotification if this
        // organizer genuinely has no live event to land on.
        let landed = false;
        if (n.data?.organizer_id) {
          const { data: orgEvent } = await supabase
            .from('events').select('id')
            .eq('organizer_id', n.data.organizer_id).eq('status', 'live')
            .order('starts_at', { ascending: true }).limit(1).maybeSingle();
          if (orgEvent?.id) { goEvent(orgEvent.id); landed = true; }
        }
        if (!landed) reportStaleNotification(n);
        break;
      }
      // Organizer Team pass (2026-09-27, Stage 1) — the invitee's own
      // pending invite lives on Account's Cá nhân tab ("Lời mời Team"
      // section, Account.jsx); the owner's "someone responded" lands back
      // on their management page, scoped to organizer ownership like
      // every other organizer-bound kind above.
      case 'organizer_invite':
        set({ screen: 'profile', accountTab: 'personal' });
        break;
      case 'organizer_invite_response':
        if (n.data?.organizer_id && s.myOrganizerIds.includes(n.data.organizer_id)) goDashboard('notifications');
        break;
      case 'event_credit_invite':
        set({ screen: 'profile', accountTab: 'personal' });
        break;
      // Admin Team pass (2026-10-02) — the invitee's own pending invite
      // lives on the SAME "Cá nhân" tab banner as a Team invite (never an
      // admin-only destination — the whole point is this account isn't an
      // admin yet); "someone responded" lands the manager back on the
      // Admin Team group, permission-rechecked there like every other
      // admin-only surface (openAccountGroup/AccountGroup.jsx's own gate).
      case 'admin_invite':
        set({ screen: 'profile', accountTab: 'personal' });
        break;
      case 'admin_invite_response':
        if (s.canManageAdmins) { set({ accountTab: 'admin' }); openAccountGroup('adminTeam'); }
        break;
      case 'admin_access_revoked':
        // Already handled proactively by the toast poll itself (see its
        // own comment) the instant this notification is first seen — a
        // later tap on the same notification just lands on a truthful,
        // already-personal-tab Account screen.
        set({ screen: 'profile', accountTab: 'personal' });
        break;
      // 'guest_renamed': category B, informational only, no destination by
      // design — falls to default. markNotificationRead() above is the
      // whole "action."
      default:
        break;
    }
  }, [markNotificationRead, openThread, openAttendance, openBookingConfirmed, set, s.accountType, s.myOrgEventKeys, s.myOrganizerIds, s.canManageAdmins, openVerifications, openPaymentDetails, openDocumentFromNotification, reportStaleNotification, goEvent, goDashboard, openAccountGroup]);
  /**
   * The organizer's "mark as paid". confirm_payment issues the receipt in
   * the same transaction (migration 024) and notifies the guest, which is
   * why this is one action rather than a separate "now issue a receipt"
   * step the organizer could forget.
   */
  const markGuestPaid = useCallback(async (bookingId, payMethod = 'bank') => {
    const result = await confirmPayment(bookingId, payMethod);
    if (s.attendanceEventKey) await loadAttendanceGuests(s.attendanceEventKey);
    return result;
  }, [confirmPayment, loadAttendanceGuests, s.attendanceEventKey]);

  const notifyCheckIn = useCallback(async (bookingId) => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: 'check_in', bookingId }),
        }).catch(() => {});
      }
    } catch { /* best-effort email; the in-app notification already landed */ }
  }, []);
  // ---- reason-required status changes (undo check-in, cancel booking) ----
  // Reversing a check-in or cancelling an already-paid booking always
  // requires picking one of a fixed list of reasons (never free text), so
  // the guest's notification always says something concrete — see
  // UNDO_CHECKIN_REASONS / CANCEL_BOOKING_REASONS above.
  const openUndoCheckin = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'undoCheckin', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const openCancelBooking = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'cancelBooking', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  // 14-organizer-checkin.md (Bug 2b): "Có nhận khách này không?" ▪︎ "Từ
  // chối" — reject_pending_guest() (migration 059) halts every pending
  // process for the booking (sets both status AND payment_state to
  // 'cancelled', clears hold_expires_at/verify_due_at) and returns the
  // seat to the pool, then notifies the guest via chat + bell notification
  // itself — same reason-required shape as undo-check-in/cancel-booking
  // above, so the guest's notification always says something concrete.
  const openRejectGuest = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'rejectGuest', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const closeReasonPrompt = useCallback(() => set({ reasonPrompt: null, reasonPromptError: '' }), [set]);
  const submitReasonPrompt = useCallback(async (reasonLabel) => {
    const prompt = s.reasonPrompt;
    if (!prompt) return;
    set({ reasonPromptBusy: true, reasonPromptError: '' });

    const rpcName = prompt.kind === 'undoCheckin' ? 'undo_check_in'
      : prompt.kind === 'rejectGuest' ? 'reject_pending_guest'
      : 'cancel_booking';
    const rpcArgs = prompt.kind === 'undoCheckin'
      ? { p_booking_id: prompt.bookingId, p_reason: reasonLabel }
      : { p_booking: prompt.bookingId, p_reason: reasonLabel };
    const { data, error } = await supabase.rpc(rpcName, rpcArgs);
    // TASK 1 — real bug, confirmed by reading: `error` (a genuine thrown
    // PostgREST/transport/decode exception) and `!data?.success` (the RPC's
    // own typed `{success:false, error:'AUTH_REQUIRED'|...}` response) used
    // to collapse into the exact same generic message for cancel_booking,
    // discarding `data?.error` entirely — indistinguishable whether the
    // wrong booking id was sent, the caller lacked authority, the booking
    // was already terminal, or a real system error occurred. Handled
    // separately below for prompt.kind === 'cancelBooking' only —
    // undoCheckin/rejectGuest keep their exact prior behavior, unchanged,
    // per this ticket's own scope.
    if (error && prompt.kind === 'cancelBooking') {
      // TASK 2 — raw technical details (e.g. the CONFIRMED root cause
      // itself: `column "reason" is of type refund_reason but expression
      // is of type text`) are logged to the dev console only, never shown
      // to the user.
      console.warn('cancel_booking RPC threw:', error);
      set({
        reasonPromptBusy: false,
        reasonPromptError: T(
          'Hiện chưa thể huỷ vé do lỗi hệ thống. Vui lòng thử lại sau.',
          "Booking cancellation isn't available right now due to a system error. Please try again later.",
        ),
      });
      return;
    }
    if (error || !data?.success) {
      set({
        reasonPromptBusy: false,
        reasonPromptError: prompt.kind === 'undoCheckin'
          ? T('Không thể huỷ điểm danh. Vui lòng thử lại.', 'Could not undo the check-in. Please try again.')
          : prompt.kind === 'rejectGuest'
          ? T('Không thể từ chối yêu cầu này. Vui lòng thử lại.', 'Could not reject this request. Please try again.')
          : prompt.kind === 'cancelBooking'
          ? cancelBookingErrorMessage(data?.error, T)
          : T('Không thể huỷ vé. Vui lòng thử lại.', 'Could not cancel the booking. Please try again.'),
      });
      return;
    }

    set({ reasonPrompt: null, reasonPromptBusy: false });
    if (s.attendanceEventKey) loadAttendanceGuests(s.attendanceEventKey);
    // reject_pending_guest() already inserts the guest's chat message +
    // bell notification itself (migration 059) — no separate /api/notify
    // email call for this kind, unlike undo-check-in/cancel-booking below.
    if (prompt.kind === 'rejectGuest') return;
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      const notifyType = prompt.kind === 'undoCheckin' ? 'checkin_undo' : 'booking_cancelled';
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: notifyType, bookingId: prompt.bookingId, reason: reasonLabel }),
        }).catch(() => {});
      }
    } catch { /* best-effort email; the in-app notification already landed */ }
  }, [set, s.reasonPrompt, s.attendanceEventKey, loadAttendanceGuests, T]);

  /// The actual check_in_guest() call — factored out of toggleCheckin so
  /// both the confirm-dialog's "Yes" (below) and the (already-confirmed)
  /// manual flow share one path.
  const performCheckIn = useCallback(async (bookingId) => {
    set(prev => ({ attendanceGuests: prev.attendanceGuests.map(g => (g.id === bookingId ? { ...g, checkedIn: true } : g)) }));
    const { data, error } = await supabase.rpc('check_in_guest', { p_reservation_id: bookingId });
    if (error || !data?.success) {
      console.warn('Check-in failed:', error || data?.error);
      set(prev => ({ attendanceGuests: prev.attendanceGuests.map(g => (g.id === bookingId ? { ...g, checkedIn: false } : g)) }));
      return { success: false };
    }
    notifyCheckIn(bookingId);
    return { success: true };
  }, [set, notifyCheckIn]);

  // 14-organizer-checkin.md (Bug 3): a confirmation step before actually
  // marking a guest arrived — an accidental tap used to check someone in
  // instantly, with only the reason-required UNDO afterward as a backstop.
  // Reuses the same reasonPrompt/ReasonSheet shell as undo-check-in/cancel-
  // booking/reject-guest above, but this kind has no reason list — just a
  // plain yes/no (see ReasonSheet.jsx's own `confirmCheckin` branch).
  const openConfirmCheckin = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'confirmCheckin', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const confirmCheckin = useCallback(async () => {
    const prompt = s.reasonPrompt;
    if (!prompt || prompt.kind !== 'confirmCheckin') return;
    set({ reasonPrompt: null });
    await performCheckIn(prompt.bookingId);
  }, [s.reasonPrompt, set, performCheckIn]);

  const toggleCheckin = useCallback((bookingId, checked) => {
    if (checked) { openUndoCheckin(bookingId); return; } // reversing requires a reason — see below
    openConfirmCheckin(bookingId); // Bug 3: confirm before marking arrived
  }, [openUndoCheckin, openConfirmCheckin]);

  // ---- QR check-in ----
  // A guest's ticket QR encodes their booking id directly (Confirmed.jsx),
  // so scanning it calls the exact same, already-authorized RPC the manual
  // tap-to-check-in list uses — just without needing that guest to already
  // be visible in a loaded list first.
  const openQrScan = useCallback(() => set({ scanningQr: true, qrScanError: '' }), [set]);
  const closeQrScan = useCallback(() => set({ scanningQr: false }), [set]);
  const checkInByScan = useCallback(async (bookingId) => {
    const { data, error } = await supabase.rpc('check_in_guest', { p_reservation_id: bookingId });
    if (error || !data?.success) {
      return { success: false, error: (data && data.error) || error?.message || 'CHECK_IN_FAILED' };
    }
    notifyCheckIn(bookingId);
    if (s.attendanceEventKey) loadAttendanceGuests(s.attendanceEventKey);
    return { success: true };
  }, [notifyCheckIn, s.attendanceEventKey, loadAttendanceGuests]);

  const value = useMemo(() => ({
    state: s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea, locationTree,
    isSaved, isGoing, isAwaitingConfirmation, toggleFav, toggleFollow, loadHomeLiveEvents, loadOrganizerPhotos, loadEventPhotos, loadWeekendEvents, loadDiscoveryEvents, loadRealEventsById, uploadEventPhoto,
    goHome, goProfile, goInbox, backFromInbox, goEvent, backFromEvent, openOrganizerOfEvent, loadEventOrgStats, goReserve, backToEvent, goMapExplore, backFromMapExplore, setMapExploreState, openEventOnMap, openEventSearch,
    loadNotifications, loadInboxThreads,
    goChat, goLogin, goDashboard, goCreate, openAttendance, backFromAttendance, loadAttendanceGuests, openHeld, goHostIntro, createBack,
    goGoingList, goSavedList, goCompletedList, backFromEventList, eventListTitle,
    loadPaymentBookings, openPaymentDetails, backFromPaymentDetails, backFromBilling, copyPayField, uploadPaymentProof, openBookingConfirmed, backFromConfirmed,
    openBilling, billingNameType, billingAddressType, billingPhoneType, billingTaxCodeType, saveBillingDetails,
    openPayout, payoutField, savePayoutDetails,
    openDocuments, loadDocuments, openDocument, backFromDocument, backFromDocuments,
    currentDocument, downloadDocument, markGuestPaid, uploadPaymentDocument, openDocumentFromNotification, toggleAutoEmailDocuments,
    submitPaymentProof, paymentTxnType, vietQrFor, nudgeOrganizer, loadReceiptStatus, requestReceipt,
    openVerifications, openVerificationsRefunds, openVerificationDetail, backFromVerifications, loadVerifications, approvePayment, rejectPayment, escalateDispute, loadOrganizerHoldingSummary, forfeitExpiredHold,
    loadRefundQueue, markRefundSent, confirmRefundReceived, disputeRefund, loadPaymentRefundClaim,
    loadRefundDestinations, saveRefundDestination, deleteRefundDestination, setDefaultRefundDestination, selectRefundDestinationForClaim, reorderRefundDestinations,
    loadMyRefunds, openRefundAccounts, backFromRefundAccounts, openMyRefunds, backFromMyRefunds,
    loadRefundCenter, toggleRefundCenterSelect, selectAllEligibleRefundCenter, clearRefundCenterSelection, confirmRefundBatch, resendRefundTransferInfo,
    openDisputes, loadDisputes, resolveDispute, loadAuditTrail, loadDisputeChat, disputeChatDraftType, sendDisputeMessage,
    loadDisputeChats, toggleDisputeChat, openDisputeChatInInbox, loadRefundDisputeChat, sendRefundDisputeMessage,
    openAdminEvents, loadPendingEvents, loadPendingEventsCount, reviewEvent, goEditEvent, withdrawEventSubmission, loadResubmissionStatus,
    switchToHost, backFromDashboard, switchToGoer, becomeHost, logout, dismissSplash, notifyLogomotionComplete,
    goEditName, editNameType, saveDisplayName, openEditProfile, backFromEditProfile, editProfileIntroLongType, toggleEditProfileLinksOpen, addEditProfileLink, setEditProfileLink, removeEditProfileLink, saveProfileFields, uploadAvatar, removeAvatar, openPublicProfile, backFromPublicProfile, openOrganizerProfile, backFromOrganizerProfile, loadOrganizerProfileExtras, shareOrganizerProfile, toggleFollowOrganizer, sharePublicProfile, openReports, backFromReports, setReportsRangeDays, setReportsCustomRange, toggleReportCard, expandAllReportCards, collapseAllReportCards, exportReportCardCsv, exportReportsJson, exportReportsPdf, loadAccountKpis, loadMyOrganizerMemberships, respondToOrganizerInvite, setOrganizerMemberVisibility, loadOrgTeamRoster, loadMyAdminInvite, respondToAdminInvite, loadAdminTeam, setAdminInviteEmailDraft, requestAdminInviteConfirm, cancelAdminInviteConfirm, confirmAdminInvite, requestRevokeAdminInviteConfirm, cancelRevokeAdminInviteConfirm, confirmRevokeAdminInvite, requestRevokeAdminConfirm, cancelRevokeAdminConfirm, confirmRevokeAdmin, orgTeamInviteHandleType, orgTeamInviteRoleType, inviteOrganizerMember, removeOrganizerMember, openOrganizerTeam, backFromOrganizerTeam, loadMyEventCredits, loadMyConfirmedEventCredits, respondToEventCredit, assignEventCredit, goNotifications, markNotificationRead, markNotificationUnread, muteNotificationKind, deleteNotification, deleteNotifications, openNotification, clearChatHighlight, dismissToast, dismissAllToasts, markToastVisible, pauseToastTimer, resumeToastTimer, openDeleteAccount, closeDeleteAccount, setDeleteAccountStep, setDeleteAccountReasonCode, setDeleteAccountReasonText, setDeleteAccountPhraseInput, setDeleteAccountReauthCode, sendDeleteAccountReauthCode, verifyDeleteAccountReauthCode, confirmDeleteAccount, deleteAccountReadyToSubmit, deleteAccountPhraseMatches, DELETE_ACCOUNT_PHRASE,
    canHost, toggleOrganizerMode, enableOrganizerMode, retryEnsureOrganizer,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding, togglePolicyConsent, openPolicy, backFromPolicy, acceptPolicyGate, declinePolicyGate,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, askLocation, toggleTheme, pickTheme, openPreferences, openSecurity, openEventPreferences, loadEventPreferences, setCreateCriteria, loadEventCriteria, checkReservationEligibility, saveEventPreferences, completeSettingsOnboarding, completePreferencesOnboarding, openAccountGroup, openPhoto, closePhoto, showPhotoAt, togglePhotoLike, sharePhoto, loadPhotoEngagement,
    securityPasswordType, securityPasswordConfirmType, saveSecurityPassword, sendSecurityPasswordReset,
    pickFilter, clearFilters, toggleHomeFilter, shareEvent, referralLink, shareReferral,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, setNameAtHold, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    openCalendarPicker, closeCalendarPicker, addToCalendarGoogle, addToCalendarICS, giveTicket,
    setAttendeeField, loadBookingAttendees, loadImportedTickets, openTicketImport, closeTicketImport, setImportCode, openImportedTicket, closeImportedTicket, claimTicket,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType, loginPasswordType, loginPasswordConfirmType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginGoogle, loginInstagram, emailValid, passwordValid, setAuthMethod, codeRequestSubmit, passwordSignupSubmit, passwordLoginSubmit, verifyEmailCode, requestPasswordResetSubmit, submitCurrentForm, newPasswordType, newPasswordConfirmType, submitNewPassword,
    chatOnType, chatSend, chatOnKey, chatBackFn, deleteMessage, openChatFor, openThread, sendChatAttachment, openChatPhoto, closeChatPhoto, downloadChatPhoto, shareChatPhoto, openChatForward, closeChatForward, forwardChatPhoto, toggleThreadStar, archiveThread, unarchiveThread, deleteThreadForMe, setInboxView, submitFeedback, sendChatViewerReply, openPostToStoryConfirm, closePostToStoryConfirm, postChatPhotoToStory, loadHomeStories, loadHomeSurveyDiscovery, loadMoreHomeSurveyDiscovery, openStoryViewer, closeStoryViewer, storyNext, storyPrev, storyNextHost, storyPrevHost, openPulseViewer, closePulseViewer, setPulseTab, loadPulse, openPulseOrganizerSheet, closePulseOrganizerSheet, followPulseOrganizer, openPulsePhotoSheet, closePulsePhotoSheet,  markStoryViewedAt, pickStoryFile, cancelStoryCreate, openStoryLibraryPicker, openStoryCameraPicker, closeStoryPickerRequests, publishStory, createEventShareStory, goEventFromStory,
    orgRegNameType, orgRegIgType, orgRegDescType, orgRegIntroLongType, toggleOrgRegLinksOpen, addOrgRegLink, setOrgRegLink, removeOrgRegLink, saveOrganizerProfile, loadMyOrgStats, setAccountTab,
    createNameType, createDescType, createIntroType, createKeywordsType, createChatGreetingType, createChatGreetingEnType, createLocType, createEventDateType, createEventTimeType, createPriceType, createSeatsType,
    searchCreateAddress, retryCreateAddressSearch, selectCreateAddressSuggestion, clearCreateAddressSelection,
    pickCreateCat, pickCreatePalette, pickCreateVisibility, tapPhotoSlot, addCreateIncludedItem, removeCreateIncludedItem, setCreateIncludedItem, importParsedEvent, createSubmit, requestVerify,
    goSurveyPublic, backFromSurveyPublic, promptLoginForSurvey, goSurveysHosting, loadMySurveyResponse, updateSurveyDraft, submitSurveyResponseAction, toggleSurveyEditMode, openSurveyStoryModal, closeSurveyStoryModal, sendSurveyRespondCode, verifySurveyRespondCode, loadMySurveys, loadSurveyCandidates, refreshSurveyCandidatesAction, dismissSurveyCandidateAction, restoreSurveyCandidateAction, setSurveyCandidatesStatusAction, archiveSurveysAction, unarchiveSurveyAction, deleteArchivedSurveysAction, deleteSurveyCandidatesAction, searchAddressSuggestions, applySurveyCandidateAction, createSurveyAction, publishSurveyAction, closeSurveyAction, archiveSurveyAction, deleteSurveyAction, shareSurveyLinkAction, openShareToStoryConfirm, closeShareToStoryConfirm, confirmShareSurveyToStory,
    toggleCheckin, openQrScan, closeQrScan, checkInByScan, openCancelBooking, openRejectGuest, closeReasonPrompt, submitReasonPrompt, confirmCheckin,
  }), [
    s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea, locationTree,
    isSaved, isGoing, isAwaitingConfirmation, toggleFav, toggleFollow, loadHomeLiveEvents, loadOrganizerPhotos, loadEventPhotos, loadWeekendEvents, loadDiscoveryEvents, loadRealEventsById, uploadEventPhoto,
    goHome, goProfile, goInbox, backFromInbox, goEvent, backFromEvent, openOrganizerOfEvent, loadEventOrgStats, goReserve, backToEvent, goMapExplore, backFromMapExplore, setMapExploreState, openEventOnMap, openEventSearch,
    loadNotifications, loadInboxThreads,
    goChat, goLogin, goDashboard, goCreate, openAttendance, backFromAttendance, loadAttendanceGuests, openHeld, goHostIntro, createBack,
    goGoingList, goSavedList, goCompletedList, backFromEventList, eventListTitle,
    loadPaymentBookings, openPaymentDetails, backFromPaymentDetails, backFromBilling, copyPayField, uploadPaymentProof, openBookingConfirmed, backFromConfirmed,
    openBilling, billingNameType, billingAddressType, billingPhoneType, billingTaxCodeType, saveBillingDetails,
    openPayout, payoutField, savePayoutDetails,
    openDocuments, loadDocuments, openDocument, backFromDocument, backFromDocuments,
    currentDocument, downloadDocument, markGuestPaid, uploadPaymentDocument, openDocumentFromNotification, toggleAutoEmailDocuments,
    submitPaymentProof, paymentTxnType, vietQrFor, nudgeOrganizer, loadReceiptStatus, requestReceipt,
    openVerifications, openVerificationsRefunds, openVerificationDetail, backFromVerifications, loadVerifications, approvePayment, rejectPayment, escalateDispute, loadOrganizerHoldingSummary, forfeitExpiredHold,
    loadRefundQueue, markRefundSent, confirmRefundReceived, disputeRefund, loadPaymentRefundClaim,
    loadRefundDestinations, saveRefundDestination, deleteRefundDestination, setDefaultRefundDestination, selectRefundDestinationForClaim, reorderRefundDestinations,
    loadMyRefunds, openRefundAccounts, backFromRefundAccounts, openMyRefunds, backFromMyRefunds,
    loadRefundCenter, toggleRefundCenterSelect, selectAllEligibleRefundCenter, clearRefundCenterSelection, confirmRefundBatch, resendRefundTransferInfo,
    openDisputes, loadDisputes, resolveDispute, loadAuditTrail, loadDisputeChat, disputeChatDraftType, sendDisputeMessage,
    loadDisputeChats, toggleDisputeChat, openDisputeChatInInbox, loadRefundDisputeChat, sendRefundDisputeMessage,
    openAdminEvents, loadPendingEvents, loadPendingEventsCount, reviewEvent, goEditEvent, withdrawEventSubmission, loadResubmissionStatus,
    switchToHost, backFromDashboard, switchToGoer, becomeHost, logout, dismissSplash, notifyLogomotionComplete,
    goEditName, editNameType, saveDisplayName, openEditProfile, backFromEditProfile, editProfileIntroLongType, toggleEditProfileLinksOpen, addEditProfileLink, setEditProfileLink, removeEditProfileLink, saveProfileFields, uploadAvatar, removeAvatar, openPublicProfile, backFromPublicProfile, openOrganizerProfile, backFromOrganizerProfile, loadOrganizerProfileExtras, shareOrganizerProfile, toggleFollowOrganizer, sharePublicProfile, openReports, backFromReports, setReportsRangeDays, setReportsCustomRange, toggleReportCard, expandAllReportCards, collapseAllReportCards, exportReportCardCsv, exportReportsJson, exportReportsPdf, loadAccountKpis, loadMyOrganizerMemberships, respondToOrganizerInvite, setOrganizerMemberVisibility, loadOrgTeamRoster, loadMyAdminInvite, respondToAdminInvite, loadAdminTeam, setAdminInviteEmailDraft, requestAdminInviteConfirm, cancelAdminInviteConfirm, confirmAdminInvite, requestRevokeAdminInviteConfirm, cancelRevokeAdminInviteConfirm, confirmRevokeAdminInvite, requestRevokeAdminConfirm, cancelRevokeAdminConfirm, confirmRevokeAdmin, orgTeamInviteHandleType, orgTeamInviteRoleType, inviteOrganizerMember, removeOrganizerMember, openOrganizerTeam, backFromOrganizerTeam, loadMyEventCredits, loadMyConfirmedEventCredits, respondToEventCredit, assignEventCredit, goNotifications, markNotificationRead, markNotificationUnread, muteNotificationKind, deleteNotification, deleteNotifications, openNotification, clearChatHighlight, dismissToast, dismissAllToasts, markToastVisible, pauseToastTimer, resumeToastTimer, openDeleteAccount, closeDeleteAccount, setDeleteAccountStep, setDeleteAccountReasonCode, setDeleteAccountReasonText, setDeleteAccountPhraseInput, setDeleteAccountReauthCode, sendDeleteAccountReauthCode, verifyDeleteAccountReauthCode, confirmDeleteAccount, deleteAccountReadyToSubmit, deleteAccountPhraseMatches, DELETE_ACCOUNT_PHRASE,
    canHost, toggleOrganizerMode, enableOrganizerMode, retryEnsureOrganizer,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding, togglePolicyConsent, openPolicy, backFromPolicy, acceptPolicyGate, declinePolicyGate,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, askLocation, toggleTheme, pickTheme, openPreferences, openSecurity, openEventPreferences, loadEventPreferences, setCreateCriteria, loadEventCriteria, checkReservationEligibility, saveEventPreferences, completeSettingsOnboarding, completePreferencesOnboarding, openAccountGroup, openPhoto, closePhoto, showPhotoAt, togglePhotoLike, sharePhoto, loadPhotoEngagement,
    securityPasswordType, securityPasswordConfirmType, saveSecurityPassword, sendSecurityPasswordReset,
    pickFilter, clearFilters, toggleHomeFilter, shareEvent, referralLink, shareReferral,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, setNameAtHold, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    openCalendarPicker, closeCalendarPicker, addToCalendarGoogle, addToCalendarICS, giveTicket,
    setAttendeeField, loadBookingAttendees, loadImportedTickets, openTicketImport, closeTicketImport, setImportCode, openImportedTicket, closeImportedTicket, claimTicket,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType, loginPasswordType, loginPasswordConfirmType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginGoogle, loginInstagram, setAuthMethod, codeRequestSubmit, passwordSignupSubmit, passwordLoginSubmit, verifyEmailCode, requestPasswordResetSubmit, submitCurrentForm, newPasswordType, newPasswordConfirmType, submitNewPassword,
    chatOnType, chatSend, chatOnKey, chatBackFn, deleteMessage, openChatFor, openThread, sendChatAttachment, openChatPhoto, closeChatPhoto, downloadChatPhoto, shareChatPhoto, openChatForward, closeChatForward, forwardChatPhoto, toggleThreadStar, archiveThread, unarchiveThread, deleteThreadForMe, setInboxView, submitFeedback, sendChatViewerReply, openPostToStoryConfirm, closePostToStoryConfirm, postChatPhotoToStory, loadHomeStories, loadHomeSurveyDiscovery, loadMoreHomeSurveyDiscovery, openStoryViewer, closeStoryViewer, storyNext, storyPrev, storyNextHost, storyPrevHost, openPulseViewer, closePulseViewer, setPulseTab, loadPulse, openPulseOrganizerSheet, closePulseOrganizerSheet, followPulseOrganizer, openPulsePhotoSheet, closePulsePhotoSheet,  markStoryViewedAt, pickStoryFile, cancelStoryCreate, openStoryLibraryPicker, openStoryCameraPicker, closeStoryPickerRequests, publishStory, createEventShareStory, goEventFromStory,
    orgRegNameType, orgRegIgType, orgRegDescType, orgRegIntroLongType, toggleOrgRegLinksOpen, addOrgRegLink, setOrgRegLink, removeOrgRegLink, saveOrganizerProfile, loadMyOrgStats, setAccountTab,
    createNameType, createDescType, createIntroType, createKeywordsType, createChatGreetingType, createChatGreetingEnType, createLocType, createEventDateType, createEventTimeType, createPriceType, createSeatsType,
    searchCreateAddress, retryCreateAddressSearch, selectCreateAddressSuggestion, clearCreateAddressSelection,
    pickCreateCat, pickCreatePalette, pickCreateVisibility, tapPhotoSlot, addCreateIncludedItem, removeCreateIncludedItem, setCreateIncludedItem, importParsedEvent, createSubmit, requestVerify,
    goSurveyPublic, backFromSurveyPublic, promptLoginForSurvey, goSurveysHosting, loadMySurveyResponse, updateSurveyDraft, submitSurveyResponseAction, toggleSurveyEditMode, openSurveyStoryModal, closeSurveyStoryModal, sendSurveyRespondCode, verifySurveyRespondCode, loadMySurveys, loadSurveyCandidates, refreshSurveyCandidatesAction, dismissSurveyCandidateAction, restoreSurveyCandidateAction, setSurveyCandidatesStatusAction, archiveSurveysAction, unarchiveSurveyAction, deleteArchivedSurveysAction, deleteSurveyCandidatesAction, searchAddressSuggestions, applySurveyCandidateAction, createSurveyAction, publishSurveyAction, closeSurveyAction, archiveSurveyAction, deleteSurveyAction, shareSurveyLinkAction, openShareToStoryConfirm, closeShareToStoryConfirm, confirmShareSurveyToStory,
    toggleCheckin, openQrScan, closeQrScan, checkInByScan, openCancelBooking, openRejectGuest, closeReasonPrompt, submitReasonPrompt, confirmCheckin,
  ]);

  return <BanBeCtx.Provider value={value}>{children}</BanBeCtx.Provider>;
}

export function useBanBe() {
  const ctx = useContext(BanBeCtx);
  if (!ctx) throw new Error('useBanBe must be used within BanBeProvider');
  return ctx;
}

export { EVENTS, findEvent };
