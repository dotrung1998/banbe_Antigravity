import { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react';
import AsyncSuccessButton from '../components/ui/AsyncSuccessButton.jsx';
import { flushSync } from 'react-dom';
import { ReservationCriteriaPicker } from './ReservationCriteria.jsx';
import { criteriaSummary, normalizeCriteria, CATEGORY_EMOJI } from '../lib/eventPrefs.js';
import { useBanBe, createFormMarket } from '../state/BanBeContext.jsx';
import { EVENTS, CREATE_PALETTES, bg } from '../data/events.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { supabase } from '../lib/supabase.js';
import { parseExcelOrZipPackage } from '../lib/excelEventImport.js';
import { formatMoney, formatMoneyShort, parsePriceInput, priceInputText, priceQuickPicks, todayInZone, wallClockToMs, VN_TIME_ZONE } from '../lib/eventMarket.js';
import { paper, ink, rule, FACE, display, alert, clay, fieldSolid } from '../theme.js';
import { fieldGlass, cardGlass, insetField } from './hostStyle.js';
import { loadMapKit } from '../lib/mapkit.js';
import { CountStepper, StepProgress } from '../components/ui/FormControls.jsx';
import { SEAT_QUICK_PICKS, TIME_QUICK_PICKS, dateQuickPicks, similarPriceRange, createDraftMatchesDefaults } from '../lib/smartDefaults.js';
import { recipeChecks, recipeCopy, estimateOutcome, pricePosition, slotLabel, hasBenchmarks, HOST_GOALS, priceToFraction, fractionToPrice, priceSliderStep, localParts } from '../lib/eventRecipe.js';
import { useHostBenchmarks } from '../lib/useHostBenchmarks.js';
import { track } from '../lib/analytics.js';
import { stepOfField, isTextField } from '../lib/createFieldGuide.js';
import { computeCreateProgress, missingLabel, newlyCompleted } from '../lib/createProgress.js';
import { categoryDefs, profileFor, requiredFields, keywordSuggestions, droppedDetailTypes, cleanDetails, detailFacts, localized, missingDetails } from '../lib/eventTypes.js';
import { flagOn } from '../lib/featureFlags.js';
import RecipeSheet, { RecipeMeter, RecipeList } from './sheets/RecipeSheet.jsx';
import ConfettiBurst from '../components/ui/ConfettiBurst.jsx';
import { listDrafts, saveDraft, deleteDraft, draftFields, draftPhotoItems } from '../lib/eventDrafts.js';
import { DraftSavedCard, EventDraftsSheet } from './sheets/EventDrafts.jsx';
import { mirrorCreateDraft, releaseCreateDraft, peekCreateDraftRestore, clearCreateDraftRestore } from '../lib/createDraftUndo.js';
import EventDetail from './EventDetail.jsx';
import { shapeDraftAsCurEvent, draftPriceVnd as parseDraftPriceVnd } from '../lib/draftPreview.js';

// Optional per-event goal (note 50). Weights the recipe; stored host-only (migration 186), never shown to guests.
const GOAL_LABELS = {
  fill_seats: ['Kín mọi chỗ', 'Fill every seat'],
  regular_crowd: ['Xây nhóm khách quen', 'Build a regular crowd'],
  try_idea: ['Thử ý tưởng mới', 'Try a new idea'],
  small_premium: ['Nhỏ & cao cấp', 'Small & premium'],
};
// The date field's tag: Vietnam time, or the US venue's own zone (migration 195) — "Venue time (PDT)".
function zoneTag(timeZone, T) {
  if (timeZone === VN_TIME_ZONE) return T('Giờ Việt Nam', 'Vietnam time');
  let abbr = '';
  try { abbr = new Intl.DateTimeFormat('en-US', { timeZone, timeZoneName: 'short' }).formatToParts(new Date()).find(p => p.type === 'timeZoneName')?.value || ''; } catch { /* unknown zone */ }
  return abbr ? T(`Giờ tại nơi tổ chức (${abbr})`, `Venue time (${abbr})`) : T('Giờ tại nơi tổ chức', 'Venue time');
}
const POSITION_LABELS = { free: ['miễn phí', 'free'], below: ['dưới mức thường', 'below typical'], typical: ['mức thường gặp', 'typical'], premium: ['cao cấp', 'premium'] };

const IMPORT_FIELD_LABELS = {
  name: ['Tên sự kiện', 'Event name'],
  location: ['Địa điểm', 'Location'],
  event_date: ['Ngày', 'Date'],
  event_time: ['Giờ', 'Time'],
  price_vnd: ['Giá vé', 'Ticket price'],
  capacity: ['Số chỗ', 'Seats'],
  cover_image: ['Ảnh bìa', 'Cover photo'],
  intro: ['Giới thiệu sự kiện', 'Event introduction'],
};

const MAX_PHOTOS = 8;
const MIN_PHOTOS = 3;
const ALLOWED_PHOTO_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const MAX_PHOTO_BYTES = 50 * 1024 * 1024; // event-photos bucket's own cap, migration 005

const CAT_DEFS = categoryDefs(); // src/data/eventTypeProfiles.json

export default function CreateEvent() {
  const {
    state, T, EN, curEvent: ev, createBack,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createIntroType, createKeywordsType, createChatGreetingType, createChatGreetingEnType, createLocType, createEventDateType, createEventTimeType, createPriceType, createSeatsType,
    retryCreateAddressSearch, selectCreateAddressSuggestion, clearCreateAddressSelection,
    pickCreateCat, pickCreatePalette, pickCreateVisibility, setCreateCriteria,
    addCreateIncludedItem, removeCreateIncludedItem, setCreateIncludedItem, setCreateDetail, dismissCreateKeyword, importParsedEvent,
    createSubmit, goEvent, loadHomeLiveEvents,
    goCreate, goHome, goDashboard, goProfile, set, clearCreateDefaults,
  } = useBanBe();
  const s = state;

  // Unified gallery staging — a single ordered list mixing the event's
  // ALREADY-UPLOADED photos (when editing an owned event, `kind: 'existing'`,
  // seeded below from `s.eventPhotos`) and newly-picked local files
  // (`kind: 'new'`), so remove/reorder/cover-pick works the same way on
  // both. Never round-tripped through the global store itself (see
  // BanBeContext.jsx's own comment on `createIncludedItems`) — only the
  // final File[]/removed-id list/cover reference are handed to createSubmit
  // on actual submit.
  // Undo after leaving (lib/createDraftUndo.js): a draft handed back by the toast's Undo seeds the
  // photos, cover and step this screen keeps locally (its text fields never left BanBeContext).
  const [restored] = useState(() => peekCreateDraftRestore());
  useEffect(() => { clearCreateDraftRestore(); }, []);
  const [items, setItems] = useState(() => restored?.items || []); // { kind, id?, file?, url, storagePath? }[]
  const [coverKey, setCoverKey] = useState(() => restored?.coverKey ?? null); // items[i]'s own url, used as a stable key
  const [photoError, setPhotoError] = useState('');
  // "Review before submitting" step (task 1) — a plain local bool, not a
  // second screen/route: every field it shows already lives in the global
  // store (`s.create*`) or this component's own `items`/`coverKey` state,
  // so toggling back to the form loses nothing — there is no separate
  // draft to reconcile. Only the review step's own explicit "Xác nhận và
  // gửi" button ever calls createSubmit; the form's own primary button
  // only ever opens this step.
  const [reviewOpen, setReviewOpen] = useState(false);
  // True only when Apple MapKit is enabled and authorised (else the OpenStreetMap credit stays).
  const [usingMapKit, setUsingMapKit] = useState(false);
  useEffect(() => { let on = true; loadMapKit().then(m => { if (on && m) setUsingMapKit(true); }); return () => { on = false; }; }, []);
  // TASK 3 (event creation validation pass) — required-field errors only
  // render after a real attempt to proceed (never on first paint of a
  // blank form), same "show after attempt" convention the address hint
  // below already follows for `createLocConfirmed`.
  const [attemptedReview, setAttemptedReview] = useState(false);
  // TASK 3 (event creation validation pass) — the post-submission chooser;
  // opened only by a real createSubmit() success (see ReviewStep's
  // onConfirm below), never merely because the request finished.
  const [successChooserOpen, setSuccessChooserOpen] = useState(false);
  const fileInputRef = useRef(null);
  const seededForEventId = useRef(null);
  const seededExistingIds = useRef([]); // event_photos ids present when this edit session was seeded

  // Editing an owned event — seed the gallery from its real event_photos
  // rows (loaded by goEditEvent) once per edit session, so removing/
  // reordering/re-covering acts on what's ACTUALLY there instead of an
  // empty local list a host could only ever add on top of.
  useEffect(() => {
    if (!s.createEditEventId) { seededForEventId.current = null; return; }
    if (seededForEventId.current === s.createEditEventId) return;
    if (s.eventPhotosLoading) return;
    seededForEventId.current = s.createEditEventId;
    const real = s.realEventsById[s.createEditEventId];
    // Strict invite-only events (migration 113) — loadEventPhotos already
    // resolves each row's display url (public getPublicUrl or a private-
    // bucket signed url), so this no longer needs its own synchronous
    // (and, for a private path, simply wrong) getPublicUrl() call.
    const seeded = (s.eventPhotos || []).filter(p => p.url).map(p => ({
      kind: 'existing', id: p.id, storagePath: p.storage_path, url: p.url,
    }));
    setItems(seeded);
    seededExistingIds.current = seeded.map(it => it.id);
    const coverRow = seeded.find(it => it.storagePath === real?.coverImage);
    setCoverKey((coverRow || seeded[0])?.url || null);
  }, [s.createEditEventId, s.eventPhotos, s.eventPhotosLoading, s.realEventsById]);

  const mountedRef = useRef(true);
  useEffect(() => { mountedRef.current = true; return () => { mountedRef.current = false; }; }, []);
  // L3 "Run it again" (BanBeContext runItAgain): the original event's cover becomes this new draft's first photo, as
  // an ordinary staged file the host can remove or replace. Fetched once; a failure just leaves the gallery empty.
  useEffect(() => {
    const url = s.createSeedCoverUrl;
    if (!url || s.createEditEventId) return undefined;
    // Cleared at once so it is used once; the fetch below is not tied to this effect's cleanup (clearing the url
    // re-runs it), only to the screen still being mounted.
    set({ createSeedCoverUrl: null });
    fetch(url).then(r => (r.ok ? r.blob() : null)).then((blob) => {
      if (!mountedRef.current || !blob || !ALLOWED_PHOTO_TYPES.has(blob.type) || blob.size > MAX_PHOTO_BYTES) return;
      const ext = blob.type === 'image/png' ? 'png' : blob.type === 'image/webp' ? 'webp' : 'jpg';
      const file = new File([blob], `cover.${ext}`, { type: blob.type });
      const item = { kind: 'new', file, url: URL.createObjectURL(file) };
      setItems(prev => (prev.length ? prev : [item]));
      setCoverKey(prev => prev ?? item.url);
    }, () => {});
    return undefined;
  }, [s.createSeedCoverUrl, s.createEditEventId, set]);

  // Photo object URLs are freed on unmount unless the draft is held for Undo (createDraftUndo decides).
  const itemsRef = useRef(items);
  itemsRef.current = items;
  useEffect(() => () => releaseCreateDraft(itemsRef.current), []);

  const onPickPhotos = (e) => {
    const picked = Array.from(e.target.files || []);
    e.target.value = '';
    if (!picked.length) return;
    setPhotoError('');
    const room = MAX_PHOTOS - items.length;
    if (picked.length > room) {
      setPhotoError(T(`Chỉ có thể thêm tối đa ${MAX_PHOTOS} ảnh.`, `You can add up to ${MAX_PHOTOS} photos total.`));
    }
    const accepted = [];
    for (const file of picked.slice(0, Math.max(0, room))) {
      if (!ALLOWED_PHOTO_TYPES.has(file.type)) {
        setPhotoError(T('Ảnh phải là JPEG, PNG hoặc WebP.', 'Photos must be JPEG, PNG, or WebP.'));
        continue;
      }
      if (file.size > MAX_PHOTO_BYTES) {
        setPhotoError(T('Mỗi ảnh tối đa 50MB.', 'Each photo must be under 50MB.'));
        continue;
      }
      accepted.push({ kind: 'new', file, url: URL.createObjectURL(file) });
    }
    if (accepted.length) {
      setItems(prev => {
        const next = [...prev, ...accepted];
        if (coverKey == null) setCoverKey(next[0].url);
        return next;
      });
    }
  };
  const removePhoto = (i) => {
    setItems(prev => {
      const removedItem = prev[i];
      if (removedItem.kind === 'new') URL.revokeObjectURL(removedItem.url);
      const next = prev.filter((_, idx) => idx !== i);
      setCoverKey(prevCover => (prevCover === removedItem.url ? (next[0]?.url ?? null) : prevCover));
      return next;
    });
  };
  // Excel bulk-create (Stage C) — upload alone only FILLS this same form
  // (importParsedEvent) and stages any extracted images into the SAME
  // gallery editor above; nothing is created/submitted until the host
  // reviews the filled-in preview and presses "Gửi để duyệt" themselves.
  const [importBusy, setImportBusy] = useState(false);
  const [importError, setImportError] = useState('');
  const [importFieldErrors, setImportFieldErrors] = useState({});
  const importInputRef = useRef(null);
  const MAX_IMPORT_BYTES = 25 * 1024 * 1024; // generous for a few embedded photos, small enough to reject an abusive upload outright
  const onImportFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (file.size > MAX_IMPORT_BYTES) {
      setImportError(T('File quá lớn (tối đa 25MB).', 'File is too large (25MB max).'));
      return;
    }
    setImportBusy(true);
    setImportError('');
    setImportFieldErrors({});
    try {
      const buf = await file.arrayBuffer();
      const result = await parseExcelOrZipPackage(buf, file.name);
      importParsedEvent(result.parsed);
      const newItems = [];
      if (result.images.cover) {
        const coverFile = new File([result.images.cover], 'cover.jpg', { type: result.images.cover.type || 'image/jpeg' });
        newItems.push({ kind: 'new', file: coverFile, url: URL.createObjectURL(coverFile) });
      }
      (result.images.gallery || []).forEach((blob, i) => {
        const f = new File([blob], `photo-${i}.jpg`, { type: blob.type || 'image/jpeg' });
        newItems.push({ kind: 'new', file: f, url: URL.createObjectURL(f) });
      });
      if (newItems.length) {
        setItems(prev => {
          const next = [...prev, ...newItems].slice(0, MAX_PHOTOS);
          return next;
        });
        setCoverKey(prev => prev ?? newItems[0]?.url ?? null);
      }
      setImportFieldErrors(result.errors || {});
      if (!result.isValid) {
        setImportError(T(
          'Đã điền vào biểu mẫu bên dưới. Kiểm tra các mục còn thiếu trước khi gửi.',
          'Filled in the form below. Check the flagged fields before submitting.'
        ));
      }
    } catch (err) {
      console.warn('Excel import failed:', err);
      setImportError(err?.message || T('Không thể đọc file này.', 'Could not read this file.'));
    } finally {
      setImportBusy(false);
    }
  };
  const photos = items; // local alias kept short for the JSX below
  const keptExistingIds = useMemo(() => new Set(items.filter(it => it.kind === 'existing').map(it => it.id)), [items]);
  const removedExistingIds = seededExistingIds.current.filter(id => !keptExistingIds.has(id));
  const newFilesInOrder = items.filter(it => it.kind === 'new').map(it => it.file);
  const coverItem = items.find(it => it.url === coverKey) || null;
  const coverIndex = coverItem?.kind === 'new' ? newFilesInOrder.indexOf(coverItem.file) : -1;
  const existingCoverPath = coverItem?.kind === 'existing' ? coverItem.storagePath : '';
  // TASK 3 (event creation validation pass) — these five are genuinely
  // required (not decorative asterisks): each is checked here, blocks
  // opening Review, and re-checked at Review's own "Xác nhận và gửi" (a
  // host can still get here via Review's own Back). `photos` already
  // excludes removed items (splice, not a soft-delete flag) and only ever
  // holds locally-staged/already-uploaded ones — there's nothing "failed/
  // in-progress" to separately exclude before a real upload attempt exists.
  // The venue's market (migration 195): its zone for every date/time check and the price's currency.
  const market = createFormMarket(s);
  // Event type profiles (switch event_type_profiles, migration 203): the first picked category shapes the form.
  // Off, or a type with no profile: everything below behaves exactly as before.
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const typesOn = flagOn(s.featureFlags, 'event_type_profiles');
  const typeKey = s.createCats[0] || '';
  const typeProfile = typesOn && typeKey ? profileFor(typeKey) : null;
  const typeDetails = (s.createDetails || {})[typeKey] || {};
  const fmtMoney = (v) => formatMoney(v, market.currency);
  const fmtShort = (v) => formatMoneyShort(v, market.currency);
  // Price typed for this currency, in minor units: 0 when empty (free), null when a dollar amount isn't a price.
  // VND keeps its old lenient reading (digits only; no digits = free), so it never shows an error.
  const parsedPrice = !s.createPrice.trim() ? 0
    : market.currency === 'USD' ? parsePriceInput(s.createPrice, 'USD') : (parsePriceInput(s.createPrice, 'VND') ?? 0);
  const fieldErrors = {
    desc: !s.createDesc.trim(),
    dateTime: !s.createEventDate || !s.createEventTime,
    seats: !(parseInt(s.createSeats, 10) > 0),
    cats: s.createCats.length === 0,
    // Required unless the event type says otherwise (a music night lists its lineup instead).
    included: requiredFields(typeProfile).includes('included') && !s.createIncludedItems.some(it => (it.label || '').trim()),
    photos: photos.length < MIN_PHOTOS || photos.length > MAX_PHOTOS,
    // A dollar amount must read like 12.50; a VND field keeps its old reading (digits only, never an error).
    price: parsedPrice == null,
  };
  // Event types on: the type's required facts (alcohol, minimum age…) gate Review like every other required field.
  const typeMissing = typeProfile ? missingDetails(typeProfile, typeDetails) : {};
  const hasFieldErrors = Object.values(fieldErrors).some(Boolean) || Object.values(typeMissing).some(Boolean);
  // 2026-09-25 fix pass (Task 0 audit) — this screen can be reached
  // directly (not only via Home, which is the only other place that calls
  // this), so `s.homeLiveEvents` can't be assumed already populated; same
  // own-fetch Dashboard.jsx already does.
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);

  // Stage 1 fix — this label used to name a fixed destination
  // ("Trang tổ chức của bạn"/"Dashboard"), which stopped being true once
  // createBack started returning to the REAL originating tab (Home, Map,
  // Inbox, Account, …) instead of always landing on Dashboard/HostIntro.
  // A plain "Back" reads correctly no matter which tab that turns out to be.
  const createBackLabel = T('Quay lại', 'Back');

  // 2026-09-25 fix pass (Task 0 audit) — this used to filter/sort the RAW
  // static catalogue (`EVENTS`), with no `liveEventOverrides` merge at
  // all: both the `!e.cancelled`/`endedHoursAgo == null` eligibility check
  // AND every displayed date below it (via `e.meta`) came from the frozen
  // catalogue, never the real `starts_at`/`status`. Same merge Dashboard.jsx
  // already applies to its own "your events" lists.
  const upcoming = EVENTS
    .map(e => { const overrides = liveEventOverrides(s.homeLiveEvents[e.key], e); return overrides ? { ...e, ...overrides } : e; })
    .filter(e => e.orgName === ev.orgName && !e.cancelled && e.endedHoursAgo == null)
    .sort((a, c) => (a.until ?? 999) - (c.until ?? 999));
  const orgTrustNote = ev.orgTrusted
    ? T('Huy hiệu "Tổ chức lâu năm" ▪︎ ' + ev.orgCount + ' sự kiện từ ' + ev.orgSince, 'Established host badge ▪︎ ' + ev.orgCount + ' events since ' + ev.orgSince)
    : T('Còn ' + (20 - ev.orgCount) + ' sự kiện nữa để nhận huy hiệu "Tổ chức lâu năm".', (20 - ev.orgCount) + ' more events to earn the Established host badge.');

  const createCatLabel = (s.createCats.length ? s.createCats : ['supper']).map(k => {
    const d = CAT_DEFS.find(c => c.key === k);
    return d ? T(d.vi, d.en) : k;
  }).join(' ▪︎ ');

  // Same rule as iOS: Review stays dimmed until the name, a confirmed address and every required field are in.
  // Tapping it while dimmed still flips `attemptedReview` so the missing fields are flagged.
  const canReview = !!s.createName.trim() && !!s.createLocConfirmed && !hasFieldErrors;

  // Note 48 — named, tappable progress sections (goal gradient), a "still
  // needed" summary instead of a silent grey button, and honest loss framing
  // when leaving a draft.
  const nameOk = !!s.createName.trim();
  // One calculation (src/lib/createProgress.js) behind the ring, "N steps left", "Still needed here" and the
  // Review summary, so they can never disagree.
  const progress = computeCreateProgress({
    hostName: !(s.orgRegName || '').trim(), name: !nameOk, description: fieldErrors.desc, categories: fieldErrors.cats,
    included: fieldErrors.included, location: !s.createLocConfirmed, date: fieldErrors.dateTime, price: fieldErrors.price,
    seats: fieldErrors.seats, photos: fieldErrors.photos,
    // The type's own required facts (alcohol + minimum age for every type; lineup, artists or brands for some).
    ...typeMissing,
  }, requiredFields(typeProfile));
  const MISSING_LABEL = (id) => missingLabel(id, T, MIN_PHOTOS);
  const sectionTitles = [T('Host', 'Host'), T('Cơ bản', 'Basics'), T('Thời gian & nơi', 'When & where'), T('Vé', 'Tickets'), T('Ảnh', 'Photos')];
  const sections = progress.steps.map((x, i) => ({ id: ['create-section-host', 'create-section-basics', 'create-section-when', 'create-section-tickets', 'create-section-photos'][i], title: sectionTitles[i], done: x.done }));
  // Note 53: always open on step 1 (Host), even when it's already ticked from the organizer profile, so the
  // host can check it; the head start (Host ✓, 20%) still shows. This replaces note 48's "skip Host".
  const [step, setStep] = useState(() => restored?.step ?? 0);
  const topRef = useRef(null);
  const goTo = (i) => {
    if (i < 0 || i >= sections.length) return;
    document.activeElement?.blur?.();
    setStep(i);
    requestAnimationFrame(() => topRef.current?.scrollIntoView({ block: 'start' }));
  };
  // Note 53: take the host to the exact field (a recipe Fix, or Review with gaps): open its step, focus it when it
  // takes typing, centre it, and point at it with the For You halo + a "👇" tip for ~4s. The step is rendered
  // synchronously (flushSync) so the focus happens inside the tap itself: iOS Safari only opens the keyboard for a
  // focus() made during the user's gesture.
  const [attn, setAttn] = useState(null); // { field, hint }
  const attnTimer = useRef(null);
  useEffect(() => () => clearTimeout(attnTimer.current), []);
  const guideTo = (field, hint) => {
    const target = stepOfField(field);
    if (target == null) return;
    document.activeElement?.blur?.();
    flushSync(() => { setRecipeOpen(false); setReviewOpen(false); setAttn(null); });
    void document.body.offsetHeight; // a fresh style pass, so the halo replays when the same field is picked again
    flushSync(() => { setStep(target); setAttn({ field, hint }); });
    const el = document.querySelector(`[data-field="${field}"]`);
    if (el) {
      if (isTextField(field)) el.querySelector('input:not([type="date"]):not([type="time"]):not([type="file"]), textarea')?.focus({ preventScroll: true });
      const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
      el.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' });
    }
    clearTimeout(attnTimer.current);
    attnTimer.current = setTimeout(() => setAttn(null), 4200);
  };
  const { doneCount, stepsLeft: left } = progress;
  const progressMessage = doneCount === 0 ? T('Bắt đầu thôi! ✨', "Let's get started! ✨")
    : left === 0 ? T('Xong hết rồi, xem lại nhé! 🎉', 'All set, time to review! 🎉')
      : left === 1 ? T('Sắp xong rồi, còn 1 bước 🔥', 'Almost there, 1 step left 🔥')
        : T(`Bạn đang làm rất tốt, còn ${left} bước 🔥`, `You're doing great, ${left} steps left 🔥`);
  // What's still missing on THIS step (shown above Next; never blocks it — fill in any order).
  const stepGaps = progress.steps[step].missing;
  // A tap on a "Still needed" chip lands on that field (same guide as a recipe Fix).
  const goToMissing = (field) => {
    track('create_event_still_needed_tapped', { field });
    guideTo(field, T('Còn thiếu: ', 'Still needed: ') + MISSING_LABEL(field));
  };
  const missing = progress.missing;
  // Note 66 (Revolut-style feedback): a required field that turns complete earns a small ✓ next to its label and
  // one polite screen-reader line. Same single source as the ring and chips. A field that was already complete
  // when the form opened never animates; one completed later pops once.
  const requiredSet = useMemo(() => new Set(requiredFields(typeProfile)), [typeProfile]);
  const prevMissingRef = useRef(undefined);
  const [freshDone, setFreshDone] = useState([]);
  const [doneAnnounce, setDoneAnnounce] = useState('');
  const missingKey = missing.join(',');
  useEffect(() => {
    const fresh = newlyCompleted(prevMissingRef.current, missing);
    prevMissingRef.current = missing;
    if (!fresh.length) return undefined;
    setFreshDone(fresh);
    const names = fresh.map(MISSING_LABEL).join(', ');
    setDoneAnnounce(left === 0
      ? T(`Xong: ${names}. Đã đủ mọi bước.`, `Done: ${names}. Every step is complete.`)
      : T(`Xong: ${names}. Còn ${left} bước.`, `Done: ${names}. ${left} ${left === 1 ? 'step' : 'steps'} left.`));
    const t = setTimeout(() => setFreshDone([]), 900);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingKey]);
  const doneMarks = useMemo(() => ({
    done: (field) => requiredSet.has(field) && !missing.includes(field),
    fresh: (field) => freshDone.includes(field),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [requiredSet, missingKey, freshDone]);
  // ---- Recipe for success (note 50) ----------------------------------------------------------------
  const primaryCat = s.createCats[0] || '';
  const { benchmarks, demand } = useHostBenchmarks(primaryCat, s.createCity, !!s.user && !s.createSent, market.currency);
  const bench = hasBenchmarks(benchmarks) ? benchmarks : null;
  // The host's wall clock read in the venue's zone (the server does the same with events.tz).
  const draftStartsAt = s.createEventDate && s.createEventTime
    ? wallClockToMs(s.createEventDate, String(s.createEventTime).slice(0, 5), market.timeZone) : null;
  const draftPriceVnd = parsedPrice || 0; // minor units of market.currency
  const draftKeywords = (s.createKeywords || '').split(',').map(k => k.trim()).filter(Boolean);
  const recipe = useMemo(() => recipeChecks({
    name: s.createName, description: s.createDesc, intro: s.createIntro,
    includedCount: (s.createIncludedItems || []).filter(it => (it.label || '').trim()).length,
    keywords: draftKeywords, priceVnd: draftPriceVnd,
    seats: parseInt(String(s.createSeats || '').replace(/\D/g, ''), 10) || 0,
    startsAt: Number.isFinite(draftStartsAt) ? draftStartsAt : null,
    photos: items.length, chatGreeting: `${s.createChatGreeting || ''}${s.createChatGreetingEn || ''}`,
    timeZone: market.timeZone, currency: market.currency, details: typeDetails,
  }, bench, s.createHostGoal, Date.now(), typeProfile),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  [s.createName, s.createDesc, s.createIntro, s.createIncludedItems, s.createKeywords, draftPriceVnd, s.createSeats, draftStartsAt, items.length, s.createChatGreeting, s.createChatGreetingEn, bench, s.createHostGoal, market.timeZone, market.currency, typeDetails, typeProfile]);
  const recipeById = Object.fromEntries(recipe.map(c => [c.id, c]));
  // Keyword ideas: with event types on, the type's own seeds + the area + what other hosts use (also on a cold
  // start, with no benchmarks), each dismissible; off, only what other hosts use, as before.
  const keywordIdeas = typesOn
    ? keywordSuggestions({ profile: typeProfile, lang, area: s.createNeighborhood || s.createDistrict, benchmark: recipeById.keywords?.suggestions || [],
      typed: draftKeywords, dismissed: s.createKwDismissed || [] })
    : (recipeById.keywords?.suggestions || []);
  const [recipeOpen, setRecipeOpen] = useState(false);
  const openRecipe = () => { setRecipeOpen(true); track('recipe_opened'); };
  const fixIngredient = (c) => {
    track('recipe_fix_tapped', { ingredient: c.id });
    if (stepOfField(c.fix.field) != null) guideTo(c.fix.field, recipeCopy(c, T).title);
    else { setReviewOpen(false); goTo(c.fix.step); }
  };
  // Editing: show the goal the host picked last time (host-only read).
  useEffect(() => {
    if (!s.createEditEventId || !s.user) return;
    let live = true;
    supabase.rpc('get_event_host_goal', { p_event_id: s.createEditEventId })
      .then(({ data, error }) => { if (live && !error && HOST_GOALS.includes(data)) set({ createHostGoal: data }); })
      .catch(() => {});
    return () => { live = false; };
  }, [s.createEditEventId, s.user, set]);
  const outcome = estimateOutcome(draftPriceVnd, parseInt(String(s.createSeats || '').replace(/\D/g, ''), 10) || 0, bench?.fill?.median_fill ?? null);
  const slotFill = (dateStr, timeStr) => {
    if (!bench || !dateStr || !timeStr) return null;
    const ms = wallClockToMs(dateStr, timeStr, market.timeZone);
    if (!Number.isFinite(ms)) return null;
    const { dow, slot } = localParts(ms, market.timeZone);
    return (bench.slots || []).find(c => c.dow === dow && c.slot === slot) || null;
  };

  const hasUnsavedInput = !s.createEditEventId && !s.createSent && (
    [s.createName, s.createDesc, s.createLoc, s.createIntro, s.createKeywords].some(v => (v || '').trim())
    || photos.length > 0 || (s.createAppliedDefaults && !createDraftMatchesDefaults(s)));
  // Mirrored for the Undo toast: BanBeContext holds this draft when the screen leaves Create.
  useEffect(() => { mirrorCreateDraft({ items, coverKey, step, hasUnsavedInput }); }, [items, coverKey, step, hasUnsavedInput]);
  // Leaves straight away; with input, an Undo toast follows (it replaced the "Discard this event?" question).
  const leaveCreate = () => createBack();

  // Drafts (iOS parity): up to 5 saved new events in this browser (lib/eventDrafts.js).
  const uid = s.user?.id;
  const [drafts, setDrafts] = useState([]);
  const [draftsOpen, setDraftsOpen] = useState(false);
  const [draftSavedOpen, setDraftSavedOpen] = useState(false);
  const [draftFull, setDraftFull] = useState(false);
  const refreshDrafts = () => listDrafts(uid).then(setDrafts);
  useEffect(() => { refreshDrafts(); }, [uid]); // eslint-disable-line react-hooks/exhaustive-deps
  const saveDraftNow = async () => {
    const coverIndex = Math.max(0, items.filter(it => it.kind === 'new').findIndex(it => it.url === coverKey));
    const res = await saveDraft(uid, { id: s.createDraftId, fields: draftFields(s), photos: items, coverIndex, step });
    if (!res.ok) { if (res.reason === 'full') setDraftFull(true); return; }
    setDraftFull(false);
    set({ createDraftId: res.id });
    await refreshDrafts();
    setDraftSavedOpen(true);
  };
  const openDraft = (d) => {
    items.forEach(it => { if (it.kind === 'new') URL.revokeObjectURL(it.url); });
    const photos = draftPhotoItems(d);
    set({ ...d.fields, createDraftId: d.id, createEditEventId: null, createSent: false, createError: '',
      createDefaultsSource: null, createAppliedDefaults: null, createUndoOffer: null });
    setItems(photos);
    setCoverKey(photos[Math.min(d.coverIndex || 0, photos.length - 1)]?.url ?? null);
    setPhotoError(''); setAttemptedReview(false);
    setStep(Math.min(Math.max(d.step || 0, 0), 4));
    setDraftsOpen(false);
  };
  const removeDraft = async (d) => {
    await deleteDraft(d.id);
    if (s.createDraftId === d.id) set({ createDraftId: null });
    await refreshDrafts();
  };
  const startNewDraft = () => {
    setDraftSavedOpen(false);
    items.forEach(it => { if (it.kind === 'new') URL.revokeObjectURL(it.url); });
    setItems([]); setCoverKey(null); setPhotoError(''); setAttemptedReview(false);
    seededExistingIds.current = [];
    setStep(0);
    goCreate();
  };
  const exitAfterDraft = () => {
    setDraftSavedOpen(false);
    // Everything is in the draft: leaving needs no Undo toast.
    mirrorCreateDraft({ items, coverKey, step, hasUnsavedInput: false });
    createBack();
  };
  const draftPill = { display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 34, padding: '0 12px', borderRadius: 999, background: 'var(--bb-field)', border: `1px solid ${rule}`, color: ink, fontSize: 12.5, fontWeight: 600, fontFamily: 'inherit', cursor: 'pointer' };
  // Price chosen by a pick/slider, written the way the field shows it ("450000" for VND as before, "12.50" for USD).
  const priceText = (v) => (market.currency === 'USD' ? priceInputText(v, 'USD') : String(v));
  const seatsNum = parseInt(String(s.createSeats || '').replace(/\D/g, ''), 10) || 0;
  const similar = s.createCats.length
    // Same-currency events only: a dong price never informs a dollar suggestion.
    ? similarPriceRange((s.discoveryEvents || []).filter(e => s.createCats.includes(e.catKey) && (e.currency || 'VND') === market.currency).map(e => e.priceVnd || 0))
    : null;
  const createBtnStyle = {
    marginTop: 26, fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 15, borderRadius: 999,
    background: s.createSent ? 'rgba(27,25,22,0.16)' : (canReview ? ink : 'rgba(27,25,22,0.16)'),
    color: s.createSent ? ink : (canReview ? paper : ink),
    cursor: canReview && !s.createSent ? 'pointer' : 'default', transition: 'background .15s',
  };

  // fill-mode `backwards`, not `both`: banbeIn animates transform, and a transform animation that is still
  // "filling" after it ends keeps this element the containing block of position:fixed children (the Review step
  // below) in Safari. Review then spanned this whole tall form instead of the screen, which showed up as a
  // screen-high blank gap and a confirm button far below. The end state is identical (opacity 1, no transform).
  return (
    <DoneMarks.Provider value={doneMarks}>
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) backwards', minHeight: '100%', background: paper }} data-screen-label="Create event">
      <div role="status" aria-live="polite" data-testid="create-done-announce" style={visuallyHidden}>{doneAnnounce}</div>
      <div ref={topRef} style={{ padding: '58px 22px 0', display: 'flex', alignItems: 'center', gap: 8 }}>
        <span onClick={leaveCreate} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {createBackLabel}</span>
        <span style={{ flex: 1 }} />
        {!s.createEditEventId && drafts.length > 0 && (
          <button type="button" onClick={() => setDraftsOpen(true)} data-testid="create-drafts" className="bb-press" style={draftPill}>
            🗂️ {T(`Bản nháp (${drafts.length}/5)`, `Drafts (${drafts.length}/5)`)}
          </button>
        )}
        {!s.createEditEventId && (
          <button type="button" onClick={saveDraftNow} data-testid="create-save-draft" className="bb-press" style={draftPill}>
            💾 {T('Lưu nháp', 'Save draft')}
          </button>
        )}
      </div>
      {draftFull && (
        <p role="alert" data-testid="create-drafts-full" style={{ fontSize: 12.5, lineHeight: 1.5, color: alert, margin: '10px 22px 0' }}>
          {T('Đã đủ 5 bản nháp. Xoá một bản để lưu bản mới. ', 'You have 5 drafts. Delete one to save another. ')}
          <span onClick={() => { setDraftFull(false); setDraftsOpen(true); }} style={{ textDecoration: 'underline', fontWeight: 600, cursor: 'pointer' }}>{T('Xem bản nháp', 'Manage drafts')}</span>
        </p>
      )}
      {/* Note 48 (iOS parity): a 5-step flow, one section per page. The sticky numbered bar shows %, an encouraging
          line and a ✓ per finished step; tap any step to jump there. */}
      {!s.createSent && (
        <div style={{ position: 'sticky', top: 0, zIndex: 5, background: paper, padding: '10px 22px 12px' }}>
          <StepProgress testId="create-progress" steps={sections.map(x => x.title)} completed={sections.map(x => x.done)}
            current={step} message={progressMessage} onSelect={goTo} />
          {/* On every step (note 53), so the header never changes height and appears with the rest of the page. */}
          <RecipeMeter checks={recipe} onOpen={openRecipe} T={T} />
        </div>
      )}
      <div style={{ padding: '14px 22px 40px', display: 'flex', flexDirection: 'column' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Dành cho người tổ chức', 'For organizers')}</span>
        <h1 style={{ ...display(26, { margin: '8px 0 0' }) }}>
          {s.createEditEventId ? T('Chỉnh sửa và gửi lại', 'Correct and resubmit') : T('Tạo sự kiện, hoàn toàn miễn phí', 'Create an event, completely free')}
        </h1>
        {s.createEditEventId && s.realEventsById[s.createEditEventId]?.rejectionReason && (
          <p style={{ fontSize: 12, lineHeight: 1.55, color: alert, margin: '10px 0 0', background: 'rgba(178,58,42,0.08)', padding: '10px 12px', borderRadius: 10 }}>
            {T('Bị từ chối: ', 'Rejected: ') + s.realEventsById[s.createEditEventId].rejectionReason}
          </p>
        )}
        {(step === 2 || step === 3) && !s.createEditEventId && !s.createSent && s.createAppliedDefaults && (
          <div data-testid="create-defaults-notice" style={{ ...cardGlass({ marginTop: 14, padding: 12 }), fontSize: 12.5, lineHeight: 1.5, color: ink }}>
            {s.createDefaultsSource
              ? T(`Đã điền sẵn thời gian và giá từ "${s.createDefaultsSource}". Đổi bất cứ gì bạn muốn.`, `Time and price are pre-filled from "${s.createDefaultsSource}". Change anything you like.`)
              : T('Đã chọn sẵn Thứ Bảy tới lúc 19:00. Đổi bất cứ lúc nào bạn muốn.', 'We picked next Saturday at 19:00. Change it any time.')}
            <button type="button" onClick={clearCreateDefaults} data-testid="create-start-blank"
              style={{ display: 'block', marginTop: 4, padding: 0, background: 'none', border: 'none', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>
              {T('Bắt đầu trống', 'Start blank')}
            </button>
          </div>
        )}

        {step === 0 && (
          <StepCard title={T('Hồ sơ người tổ chức', 'Organizer profile')} id="create-section-host">
            {sections[0].done && (
              <p data-testid="create-host-prefilled" style={{ ...hintText, opacity: 0.85, marginTop: -8 }}>
                ✓ {T('Đã điền từ hồ sơ người tổ chức của bạn. Kiểm tra lại rồi tiếp tục.', 'Filled from your organizer profile. Check it and continue.')}
              </p>
            )}
            <Guided field="hostName" attn={attn}>
              <BigField icon="person" field="hostName" label={T('Tên', 'Name')} value={s.orgRegName} onChange={orgRegNameType} placeholder="Bếp Nhỏ" />
            </Guided>
            <BigField icon="at" label="Instagram" value={s.orgRegIg} onChange={orgRegIgType} placeholder="@bepnho.saigon" />
            <BigField icon="quote" label={T('Giới thiệu', 'About')} value={s.orgRegDesc} onChange={orgRegDescType} placeholder={T('Minh nấu cho người lạ từ 2021…', 'Minh has cooked for strangers since 2021…')} />
          </StepCard>
        )}

        {step === 1 && (
          <StepCard title={T('Cơ bản', 'Basics')} id="create-section-basics">
            <Guided field="name" attn={attn}>
              <BigField icon="sparkles" field="name" label={T('Tên sự kiện', 'Event name')} required value={s.createName} onChange={createNameType} placeholder="Bếp Nhỏ №13" testId="create-name"
                invalid={attemptedReview && !nameOk} />
            </Guided>
            <div style={fieldCol} data-testid="create-goal">
              <FormLabel icon="target" text={T('Điều quan trọng nhất với sự kiện này?', 'What matters most for this event?')} tag={T('Tuỳ chọn', 'Optional')} />
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {HOST_GOALS.map(g => {
                  const on = s.createHostGoal === g;
                  return (
                    <button key={g} type="button" aria-pressed={on} data-testid={`create-goal-${g}`} onClick={() => set({ createHostGoal: on ? null : g })}
                      style={{ fontSize: 14, fontFamily: 'inherit', padding: '10px 14px', borderRadius: 999, cursor: 'pointer',
                        border: on ? '1px solid transparent' : `1px solid ${rule}`, background: on ? ink : paper, color: on ? paper : ink, fontWeight: on ? 600 : 400 }}>
                      {T(...GOAL_LABELS[g])}
                    </button>
                  );
                })}
              </div>
              <p style={hintText}>{T('Chỉ bạn thấy. Giúp banbe đưa gợi ý phù hợp hơn.', 'Only you see this. It tunes the tips below to what you want.')}</p>
            </div>
            <Guided field="description" attn={attn}>
              <BigField icon="text" field="description" label={T('Mô tả', 'Description')} required value={s.createDesc} onChange={createDescType} placeholder={T('Mười bốn chỗ. Một ga-ra cải tạo…', 'Fourteen seats. A converted garage…')}
                invalid={attemptedReview && fieldErrors.desc} describedBy="create-desc-error" />
              {attemptedReview && fieldErrors.desc && <p id="create-desc-error" style={errText}>{T('Hãy nhập mô tả.', 'Please enter a description.')}</p>}
            </Guided>
            <Guided field="intro" attn={attn} style={fieldCol}>
              <FormLabel icon="doc" text={T('Giới thiệu sự kiện', 'Event introduction')} tag={`${s.createIntro.length}/4000`}
                tagTone={s.createIntro.length >= 4000 ? 'error' : s.createIntro.length >= 3800 ? 'warning' : null} />
              <p style={hintText}>{T('Một đoạn giới thiệu dài hơn, hấp dẫn. Tách dòng trống giữa các đoạn. Không phải quảng cáo giả, không phải "Bao gồm".', 'A longer, attractive write-up. Leave a blank line between paragraphs. Not fabricated marketing copy, not the same as "Included".')}</p>
              <textarea value={s.createIntro} onChange={createIntroType} maxLength={4000} rows={6}
                placeholder={T('Một buổi tối ấm cúng cho mười bốn người lạ…\n\nMón chính là…', 'A cozy evening for fourteen strangers…\n\nThe main course is…')}
                data-testid="create-intro" style={{ ...bigInput, resize: 'vertical', lineHeight: 1.5 }} />
            </Guided>
            <Guided field="greeting" attn={attn} style={fieldCol}>
              <FormLabel icon="bubble" text={T('Lời nhắn mở đầu', 'Opening message')} tag={T('Tuỳ chọn', 'Optional')} />
              <p style={hintText}>{T('Hiện như tin nhắn đầu tiên từ bạn khi khách bấm "Nhắn cho người tổ chức", theo ngôn ngữ của khách. Để trống cả hai sẽ dùng lời chào mặc định.', 'Shown as the first message from you when a guest taps "Message host", in the guest\'s language. Leave both blank for a default greeting.')}</p>
              <div style={subLabel}><span>{T('Tiếng Việt', 'Vietnamese')}</span><span style={{ opacity: 0.6 }}>{s.createChatGreeting.length}/500</span></div>
              <textarea value={s.createChatGreeting} onChange={createChatGreetingType} maxLength={500} rows={3} data-testid="create-chat-greeting"
                placeholder="Chào bạn! Mình sẽ trả lời sớm nhất có thể…" style={{ ...bigInput, resize: 'vertical', lineHeight: 1.5 }} />
              <div style={subLabel}><span>{T('Tiếng Anh', 'English')}</span><span style={{ opacity: 0.6 }}>{s.createChatGreetingEn.length}/500</span></div>
              <textarea value={s.createChatGreetingEn} onChange={createChatGreetingEnType} maxLength={500} rows={3} data-testid="create-chat-greeting-en"
                placeholder="Hi! Happy to answer any questions, I'll reply as soon as I can." style={{ ...bigInput, resize: 'vertical', lineHeight: 1.5 }} />
            </Guided>
            <Guided field="categories" attn={attn} style={fieldCol}>
              <FormLabel icon="grid" field="categories" text={T('Danh mục', 'Categories')} required tag={T('Tối đa 2', 'Up to 2')} />
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {CAT_DEFS.map(c => {
                  const on = s.createCats.includes(c.key);
                  return (
                    <button key={c.key} type="button" onClick={() => pickCreateCat(c.key)} aria-pressed={on} data-testid={`create-cat-${c.key}`}
                      style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 15, fontFamily: 'inherit', padding: '12px 16px', borderRadius: 999, cursor: 'pointer',
                        border: on ? '1px solid transparent' : `1px solid ${rule}`, background: on ? ink : paper, color: on ? paper : ink, fontWeight: on ? 600 : 400 }}>
                      <span aria-hidden>{CAT_EMOJI[c.key] || '✦'}</span>{T(c.vi, c.en)}
                    </button>
                  );
                })}
              </div>
              {attemptedReview && fieldErrors.cats && <p style={errText}>{T('Hãy chọn ít nhất một danh mục.', 'Please pick at least one category.')}</p>}
              {demand != null && primaryCat && (
                <p data-testid="create-audience-demand" style={{ ...hintText, fontWeight: 600, opacity: 0.85 }}>
                  {T(`${demand}+ người trên banbe thích ${(CAT_DEFS.find(c => c.key === primaryCat) || {}).vi || primaryCat}.`, `${demand}+ people on banbe are into ${(CAT_DEFS.find(c => c.key === primaryCat) || {}).en || primaryCat}.`)}
                </p>
              )}
            </Guided>
            <Guided field="keywords" attn={attn} style={fieldCol}>
              <BigField icon="search" label={T('Từ khoá tìm kiếm', 'Search keywords')} value={s.createKeywords} onChange={createKeywordsType}
                placeholder={T('vd. tiệc tối, rượu vang, ẩm thực Việt', 'e.g. supper club, wine, Vietnamese food')} />
              <p style={hintText}>{T('Cách nhau bằng dấu phẩy. Để trống sẽ tự dùng danh mục đã chọn ở trên.', 'Comma-separated. Left blank, the category picked above is used instead.')}</p>
              {keywordIdeas.length > 0 && (
                <div data-testid="create-keyword-suggestions" style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' }}>
                  <span style={{ ...hintText, margin: 0 }}>{typesOn ? T('Gợi ý:', 'Ideas:') : T('Host khác hay dùng:', 'Other hosts use:')}</span>
                  {keywordIdeas.map(k => (
                    <span key={k} style={{ display: 'inline-flex', alignItems: 'center', borderRadius: 999, border: `1px solid ${rule}` }}>
                      <button type="button" data-testid="create-keyword-suggestion"
                        onClick={() => set({ createKeywords: [...draftKeywords, k].join(', ') })}
                        style={{ minHeight: 36, fontSize: 12.5, fontFamily: 'inherit', padding: typesOn ? '0 4px 0 10px' : '0 10px', border: 'none', background: 'none', color: ink, cursor: 'pointer' }}>+ {k}</button>
                      {typesOn && (
                        <button type="button" data-testid="create-keyword-dismiss" onClick={() => dismissCreateKeyword(k)}
                          aria-label={T(`Bỏ gợi ý ${k}`, `Dismiss ${k}`)}
                          style={{ minWidth: 32, minHeight: 36, fontSize: 13, fontFamily: 'inherit', border: 'none', background: 'none', color: ink, opacity: 0.5, cursor: 'pointer' }}>×</button>
                      )}
                    </span>
                  ))}
                </div>
              )}
            </Guided>
            <Guided field="included" attn={attn} style={fieldCol}>
              <FormLabel icon="checklist" field="included" text={typeProfile?.wizard?.includedTitle ? localized(typeProfile.wizard.includedTitle, lang) : T('Bao gồm', 'Included')}
                required={requiredFields(typeProfile).includes('included')} tag={`${s.createIncludedItems.length}/3`} />
              {s.createIncludedItems.map((it, i) => (
                <div key={i} className="bb-focus-ring" style={{ display: 'flex', alignItems: 'flex-start', gap: 12, padding: '14px 8px 14px 16px', borderRadius: 14, background: paper, border: `1px solid ${rule}` }}>
                  <span aria-hidden style={{ fontSize: 18, lineHeight: '24px' }}>✅</span>
                  <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
                    <input value={it.label} maxLength={60} onChange={(e) => setCreateIncludedItem(i, 'label', e.target.value)}
                      placeholder={typeProfile?.wizard?.includedPlaceholder ? localized(typeProfile.wizard.includedPlaceholder, lang) : T('Tên mục (vd. 5 món)', 'Label (e.g. 5 courses)')} data-testid={`create-included-${i}-label`} data-bare
                      style={{ border: 'none', background: 'none', outline: 'none', fontFamily: FACE, fontSize: 16, fontWeight: 600, color: ink, padding: 0 }} />
                    <div style={{ height: 1, background: rule }} />
                    <input value={it.detail} maxLength={300} onChange={(e) => setCreateIncludedItem(i, 'detail', e.target.value)}
                      placeholder={T('Mô tả (không bắt buộc)', 'Detail (optional)')} data-testid={`create-included-${i}-detail`} data-bare
                      style={{ border: 'none', background: 'none', outline: 'none', fontFamily: FACE, fontSize: 15, color: ink, opacity: 0.85, padding: 0 }} />
                  </div>
                  <button type="button" onClick={() => removeCreateIncludedItem(i)} aria-label={T('Xoá mục', 'Remove item')}
                    style={{ width: 44, height: 44, marginTop: -10, border: 'none', background: 'none', color: ink, opacity: 0.4, fontSize: 18, cursor: 'pointer' }}>ⓧ</button>
                </div>
              ))}
              {s.createIncludedItems.length < 3 && (
                <button type="button" onClick={addCreateIncludedItem} data-testid="create-included-add"
                  style={{ minHeight: 52, borderRadius: 14, border: `1.2px dashed rgba(var(--bb-fg-rgb),0.3)`, background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
                  ⊕ {T('Thêm mục', 'Add item')}
                </button>
              )}
              {attemptedReview && fieldErrors.included && <p style={errText}>{T('Hãy thêm ít nhất một mục Bao gồm.', 'Please add at least one Included item.')}</p>}
            </Guided>
            {typeProfile?.wizard?.details?.length > 0 && (
              <TypeDetailsEditor profile={typeProfile} values={typeDetails} lang={lang} T={T} attn={attn}
                showErrors={attemptedReview} required={requiredFields(typeProfile)}
                onChange={(field, value) => setCreateDetail(typeKey, field, value)} />
            )}
          </StepCard>
        )}

        {step === 2 && (
          <StepCard title={T('Thời gian & địa điểm', 'When & where')} id="create-section-when">
        <Guided field="location" attn={attn} style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 0 }}>
          <FormLabel icon="pin" field="location" text={T('Địa điểm', 'Location')} required />
          <p style={hintText}>
            {T(
              'Gõ số nhà + tên đường (hoặc tên địa điểm nếu không có số nhà) rồi chọn một gợi ý. Cần thiết để đăng sự kiện.',
              'Type a house number + street (or a venue name if there is no house number), then pick a suggestion. Required to publish.'
            )}
          </p>
          {/* Address-autocomplete fix pass (2026-09-28) — replaces the old
              single-shot "type free text, tap Confirm, get ONE geocode
              result" flow. `createLocType` (BanBeContext.jsx) debounces a
              live Nominatim search as the host types; a real, structured
              address must be SELECTED from the results below before
              publishing is possible at all — there is no more "Skip",
              since this ticket makes a verified address mandatory. */}
          <input
            value={s.createLoc} onChange={createLocType}
            placeholder={T('12 Nguyễn Văn Đậu, hoặc tên địa điểm…', '12 Nguyễn Văn Đậu, or a venue name…')}
            style={bigInput} data-testid="create-location-input" aria-invalid={attemptedReview && !s.createLocConfirmed ? true : undefined}
            autoComplete="off"
          />
          {s.createAddressSearching && (
            <p style={{ fontSize: 11, color: ink, opacity: 0.6, margin: 0 }}>{T('Đang tìm địa chỉ…', 'Searching addresses…')}</p>
          )}
          {s.createAddressSearchError && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <p style={{ fontSize: 11, color: alert, margin: 0, flex: 1 }}>{s.createAddressSearchError}</p>
              <span onClick={retryCreateAddressSearch} data-testid="create-location-retry" style={{ fontSize: 11, fontWeight: 600, color: ink, cursor: 'pointer', textDecoration: 'underline', flexShrink: 0 }}>
                {T('Thử lại', 'Retry')}
              </span>
            </div>
          )}
          {s.createAddressSuggestions.length > 0 && (
            <div style={{ ...cardGlass({ padding: 0 }), overflow: 'hidden' }} data-testid="create-location-suggestions">
              {s.createAddressSuggestions.map((sug, i) => (
                <div
                  key={sug.id}
                  onClick={() => selectCreateAddressSuggestion(sug)}
                  data-testid="create-location-suggestion"
                  style={{
                    padding: '10px 12px', cursor: 'pointer',
                    borderTop: i > 0 ? `1px solid ${rule}` : 'none',
                    display: 'flex', flexDirection: 'column', gap: 2,
                  }}
                >
                  <span style={{ fontSize: 13, fontWeight: 600, color: ink }}>
                    {sug.addressLine}{sug.isVenue ? ' ' + T('(địa điểm)', '(venue)') : ''}
                  </span>
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>
                    {[sug.district, sug.city, sug.postalCode].filter(Boolean).join(', ')}
                  </span>
                </div>
              ))}
              {/* Nominatim's usage policy requires attribution wherever its results are shown, same as
                  MapExplore's own MapLibre attribution elsewhere in this app. With MapKit live the results
                  are Apple Maps data, so the credit says that instead. */}
              <div style={{ padding: '6px 12px', fontSize: 9.5, color: ink, opacity: 0.45, borderTop: `1px solid ${rule}` }}>
                {usingMapKit ? T('Kết quả từ Apple Maps', 'Results from Apple Maps') : '© OpenStreetMap contributors'}
              </div>
            </div>
          )}
          {s.createLocConfirmed && (
            <div style={{ ...cardGlass({ padding: 10 }), display: 'flex', flexDirection: 'column', gap: 6 }} data-testid="create-location-confirmed">
              <span style={{ fontSize: 11.5, color: ink, opacity: 0.85 }}>✓ {s.createLocLabel}</span>
              <span style={{ fontSize: 10.5, color: ink, opacity: 0.6 }}>
                {T('Sẽ hiện ghim trên bản đồ tại toạ độ này.', 'Will show a map pin at this exact point.')}
              </span>
              <div onClick={clearCreateAddressSelection} data-testid="create-location-adjust" style={{ alignSelf: 'flex-start', fontSize: 11, fontWeight: 600, color: ink, cursor: 'pointer', textDecoration: 'underline', opacity: 0.75 }}>
                {T('Đổi địa chỉ', 'Change address')}
              </div>
            </div>
          )}
        </Guided>

            <Guided field="date" attn={attn} style={fieldCol}>
              <FormLabel icon="calendar" field="date" text={T('Ngày & giờ', 'Date & time')} required tag={zoneTag(market.timeZone, T)} />
              <div style={{ display: 'flex', gap: 10 }}>
                <input type="date" value={s.createEventDate} onChange={createEventDateType} min={todayInZone(market.timeZone)}
                  data-testid="create-event-date" aria-label={T('Ngày', 'Date')} style={{ ...bigInput, flex: 1.3 }} />
                <input type="time" value={s.createEventTime} onChange={createEventTimeType}
                  data-testid="create-event-time" aria-label={T('Giờ', 'Time')} style={{ ...bigInput, flex: 1 }} />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }} data-testid="create-date-quickpicks">
                {dateQuickPicks(new Date(), market.timeZone).map(p => {
                  const cell = slotFill(p.date, (s.createEventTime || '19:00').slice(0, 5));
                  return (
                    <PickTile key={p.en} label={T(p.vi, p.en)} sub={cell ? T(`kín ${Math.round(cell.median_fill * 100)}%`, `fills ${Math.round(cell.median_fill * 100)}%`) : null}
                      selected={s.createEventDate === p.date} onClick={() => set({ createEventDate: p.date })} />
                  );
                })}
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 8 }} data-testid="create-time-quickpicks">
                {TIME_QUICK_PICKS.map(t => (
                  <PickTile key={t} label={t} selected={(s.createEventTime || '').slice(0, 5) === t} onClick={() => set({ createEventTime: t })} />
                ))}
              </div>
              {attemptedReview && fieldErrors.dateTime && <p style={errText}>{T('Hãy chọn ngày và giờ diễn ra.', 'Please pick a date and time.')}</p>}
              {recipeById.timing?.status !== 'missing' && (
                <Insight testId="create-timing-insight" check={recipeById.timing} T={T}
                  line={recipeById.timing.source === 'data'
                    ? T(`${slotLabel(recipeById.timing.dow, recipeById.timing.slot, T)} thường kín ${Math.round(recipeById.timing.ownFill * 100)}%.`, `${slotLabel(recipeById.timing.dow, recipeById.timing.slot, T)} usually fills ${Math.round(recipeById.timing.ownFill * 100)}%.`)
                    : null} />
              )}
              {recipeById.lead?.status === 'improve' && (
                <Insight testId="create-lead-insight" check={recipeById.lead} T={T}
                  line={T(`Còn ${Math.max(recipeById.lead.days, 0)} ngày. Sự kiện kín chỗ thường đăng trước ~${recipeById.lead.target} ngày.`, `${Math.max(recipeById.lead.days, 0)} days to go. Events that fill are usually posted ~${recipeById.lead.target} days ahead.`)} />
              )}
            </Guided>
          </StepCard>
        )}

        {step === 3 && (
          <StepCard title={T('Vé & ai được đặt', 'Tickets & who can book')} id="create-section-tickets">
            <Guided field="price" attn={attn} style={fieldCol}>
              <FormLabel icon="tag" field="price" text={T('Giá vé', 'Price')} tag={similar ? T('Gợi ý', 'Suggested') : null} />
              {bench?.price && <PriceMarket price={bench.price} mine={draftPriceVnd} T={T} catLabel={createCatLabel} currency={market.currency} onChange={(v) => set({ createPrice: priceText(v), createPriceCurrency: market.currency })} />}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
                {priceQuickPicks(market.currency).map(v => {
                  const pos = bench?.price ? pricePosition(v, bench.price) : null;
                  return (
                    <PickTile key={v} testId={`create-price-${v}`} label={v === 0 ? T('Miễn phí', 'Free') : (pos ? fmtShort(v) : fmtMoney(v))}
                      sub={pos && v > 0 ? T(...POSITION_LABELS[pos]) : null}
                      selected={s.createPrice !== '' && parsedPrice === v} onClick={() => set({ createPrice: priceText(v), createPriceCurrency: market.currency })} />
                  );
                })}
              </div>
              <input value={s.createPrice} onChange={createPriceType}
                placeholder={market.currency === 'USD' ? T('Giá khác (USD), vd. 12.50', 'Other price (USD), e.g. 12.50') : T('Giá khác, vd. 450.000', 'Other price, e.g. 450,000')}
                aria-label={T('Giá vé', 'Ticket price')} inputMode={market.currency === 'USD' ? 'decimal' : 'numeric'} data-testid="create-price-input"
                aria-invalid={fieldErrors.price || undefined} style={bigInput} />
              {fieldErrors.price && <p data-testid="create-price-error" style={errText}>{T('Nhập giá dạng 12.50', 'Enter a price like 12.50')}</p>}
              <span data-testid="create-price-hint" style={hintText}>
                {bench?.price
                  ? T(`Thường gặp: ${fmtShort(bench.price.p25)}–${fmtShort(bench.price.p75)} (${bench.price.n} sự kiện tương tự). Để trống là miễn phí.`, `Typical: ${fmtShort(bench.price.p25)}–${fmtShort(bench.price.p75)} (${bench.price.n} similar events). Leave empty for a free event.`)
                  : similar
                    ? T(`Sự kiện tương tự: ${fmtMoney(similar[0])}–${fmtMoney(similar[1])}`, `Similar events: ${fmtMoney(similar[0])}–${fmtMoney(similar[1])}`)
                    : T('Để trống là miễn phí.', 'Leave empty for a free event.')}
              </span>
            </Guided>
            <Guided field="seats" attn={attn} style={fieldCol}>
              <FormLabel icon="people" field="seats" text={T('Số chỗ', 'Seats')} required />
              <div style={{ padding: '10px 14px', borderRadius: 14, background: paper, border: `1px solid ${rule}` }}>
                <CountStepper testId="create-seats-stepper" value={seatsNum} min={0} max={500} unit={T('chỗ', 'seats')}
                  onChange={(n) => set({ createSeats: n ? String(n) : '' })} />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
                {SEAT_QUICK_PICKS.map(n => (
                  <PickTile key={n} testId={`create-seats-${n}`} label={String(n)} selected={seatsNum === n} onClick={() => set({ createSeats: String(n) })} />
                ))}
              </div>
              {attemptedReview && fieldErrors.seats && <p style={errText}>{T('Hãy nhập số chỗ lớn hơn 0.', 'Please enter a number of seats greater than 0.')}</p>}
              <Insight testId="create-seats-insight" check={recipeById.seats} T={T}
                line={recipeById.seats.typicalGuests != null ? T(`Sự kiện tương tự thường đón ~${recipeById.seats.typicalGuests} khách.`, `Similar events usually welcome ~${recipeById.seats.typicalGuests} guests.`) : null} />
              {outcome && (
                <div data-testid="create-outcome" data-basis={outcome.basis} style={{ ...cardGlass({ padding: '12px 14px' }), fontSize: 13.5, lineHeight: 1.45 }}>
                  <b>{outcome.basis === 'similar'
                    ? T(`~${outcome.guests} khách${draftPriceVnd > 0 ? ` · ~${fmtShort(outcome.revenueVnd)}` : ''}`, `~${outcome.guests} guests${draftPriceVnd > 0 ? ` · ~${fmtShort(outcome.revenueVnd)}` : ''}`)
                    : T(`${outcome.guests} khách${draftPriceVnd > 0 ? ` · ${fmtShort(outcome.revenueVnd)}` : ''}`, `${outcome.guests} guests${draftPriceVnd > 0 ? ` · ${fmtShort(outcome.revenueVnd)}` : ''}`)}</b>
                  <span style={{ opacity: 0.7 }}>{' '}{outcome.basis === 'similar'
                    ? T(`nếu kín như sự kiện tương tự (~${Math.round(outcome.fill * 100)}%)`, `if it fills like similar events (~${Math.round(outcome.fill * 100)}%)`)
                    : T('nếu bán hết chỗ', 'if every seat sells')}{draftPriceVnd > 0 ? T(', trước mọi khoản phí.', ', before any fees.') : '.'}</span>
                </div>
              )}
            </Guided>
            <div style={fieldCol}>
              <FormLabel icon="lock" text={T('Quyền riêng tư', 'Privacy')} />
              <div style={{ display: 'flex', gap: 8 }}>
                {[{ key: 'public', vi: 'Công khai', en: 'Public', icon: '🌏' }, { key: 'invite', vi: 'Chỉ mời', en: 'Invite-only', icon: '✉️' }].map(opt => {
                  const on = s.createVisibility === opt.key;
                  return (
                    <button key={opt.key} type="button" onClick={() => pickCreateVisibility(opt.key)} data-testid={`create-visibility-${opt.key}`} aria-pressed={on}
                      style={{ flex: 1, minHeight: 76, borderRadius: 16, border: on ? '1px solid transparent' : `1px solid ${rule}`, background: on ? ink : paper, color: on ? paper : ink,
                        fontFamily: 'inherit', fontSize: 15, fontWeight: on ? 600 : 400, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
                      <span aria-hidden style={{ fontSize: 20 }}>{opt.icon}</span>{T(opt.vi, opt.en)}
                    </button>
                  );
                })}
              </div>
              <p style={hintText}>
                {s.createVisibility === 'invite'
                  ? T('Chỉ người được mời mới thấy và đặt được sự kiện này. Bạn vẫn cần được banbe duyệt.', 'Only invited people can see or book this event. It still needs banbe approval.')
                  : T('Ai cũng có thể tìm thấy và đặt sự kiện này.', 'Anyone can discover and book this event.')}
              </p>
            </div>
            <ReservationCriteriaPicker criteria={s.createCriteria} onChange={setCreateCriteria} loadState={s.createCriteriaLoad} />
          </StepCard>
        )}

        {step === 4 && (
        <Guided field="photos" attn={attn} id="create-section-photos" style={{ marginTop: 22, scrollMarginTop: 90 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <FormLabel icon="photo" field="photos" text={T('Hình ảnh', 'Photos')} required />
            <span style={{ fontSize: 10.5, color: ink }}>{photos.length}/{MAX_PHOTOS} ({T(`tối thiểu ${MIN_PHOTOS}`, `min ${MIN_PHOTOS}`)})</span>
          </div>
          <Insight testId="create-photos-insight" check={recipeById.photos} T={T}
            line={recipeById.photos.source === 'data'
              ? T(`Sự kiện kín chỗ thường có ${recipeById.photos.target}+ ảnh.`, `Events that filled well had ${recipeById.photos.target}+ photos.`)
              : T(`Mẹo: ${recipeById.photos.target}+ ảnh cho khách thấy không khí.`, `Tip: ${recipeById.photos.target}+ photos show guests the vibe.`)} />
          <input
            ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" multiple
            style={{ display: 'none' }} onChange={onPickPhotos}
          />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 10 }}>
            {photos.map((p, i) => {
              const isCover = p.url === coverKey;
              return (
                <div key={p.url} data-testid={`create-photo-row-${i}`} style={{ ...fieldGlass({ padding: 8, display: 'flex', alignItems: 'center', gap: 10 }) }}>
                  <div style={{ position: 'relative', flex: 'none', width: 64, height: 64, borderRadius: 10, overflow: 'hidden' }}>
                    <div style={bg(p.url, { width: '100%', height: '100%' })} />
                    {isCover && (
                      <span style={{ position: 'absolute', bottom: 0, left: 0, right: 0, fontSize: 8.5, fontWeight: 700, textAlign: 'center', padding: '2px 0', background: ink, color: paper }}>
                        {T('Ảnh bìa', 'Cover')}
                      </span>
                    )}
                  </div>
                  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
                    <span style={{ fontSize: 11.5, color: ink, opacity: 0.65 }}>{T(`Ảnh ${i + 1}`, `Photo ${i + 1}`)}</span>
                    <span
                      onClick={() => setCoverKey(p.url)}
                      data-testid={`create-photo-set-cover-${i}`}
                      style={{
                        fontSize: 11, fontWeight: 600, cursor: isCover ? 'default' : 'pointer', alignSelf: 'flex-start',
                        padding: '4px 10px', borderRadius: 999, border: `1px solid ${isCover ? 'transparent' : 'rgba(27,25,22,0.16)'}`,
                        background: isCover ? ink : 'transparent', color: isCover ? paper : ink,
                      }}
                    >
                      {isCover ? T('Đang là ảnh bìa', 'Currently the cover') : T('Đặt làm ảnh bìa', 'Set as cover')}
                    </span>
                  </div>
                  {/* Reorder — up/down, not left/right (this is a vertical
                      list now); disabled (not hidden) at the ends so the
                      control layout never jumps between rows. */}
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4, flex: 'none' }}>
                    <span
                      onClick={i === 0 ? undefined : () => setItems(prev => { const next = [...prev]; [next[i - 1], next[i]] = [next[i], next[i - 1]]; return next; })}
                      data-testid={`create-photo-move-up-${i}`}
                      style={{ width: 26, height: 26, borderRadius: 8, background: paper, border: `1px solid ${rule}`, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: i === 0 ? 'default' : 'pointer', opacity: i === 0 ? 0.3 : 1, fontSize: 13, color: ink }}
                    >↑</span>
                    <span
                      onClick={i === photos.length - 1 ? undefined : () => setItems(prev => { const next = [...prev]; [next[i], next[i + 1]] = [next[i + 1], next[i]]; return next; })}
                      data-testid={`create-photo-move-down-${i}`}
                      style={{ width: 26, height: 26, borderRadius: 8, background: paper, border: `1px solid ${rule}`, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: i === photos.length - 1 ? 'default' : 'pointer', opacity: i === photos.length - 1 ? 0.3 : 1, fontSize: 13, color: ink }}
                    >↓</span>
                  </div>
                  <span
                    onClick={() => removePhoto(i)}
                    data-testid={`create-photo-remove-${i}`}
                    style={{ width: 26, height: 26, borderRadius: 999, background: 'rgba(12,12,12,0.06)', color: alert, fontSize: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', flex: 'none' }}
                  >×</span>
                </div>
              );
            })}
            {photos.length < MAX_PHOTOS && (
              <div
                onClick={() => fileInputRef.current?.click()}
                data-testid="create-photo-add"
                style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: 'pointer', borderRadius: 12, padding: '14px 0', background: paper, border: `1px dashed ${ink}` }}
              >
                <span style={{ fontSize: 16, color: ink }}>+</span>
                <span style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{T('Thêm ảnh', 'Add photo')}</span>
              </div>
            )}
          </div>
          {photoError && <p style={{ fontSize: 11.5, color: alert, margin: '8px 0 0' }}>{photoError}</p>}
          {!photoError && attemptedReview && fieldErrors.photos && (
            <p style={{ fontSize: 11.5, color: alert, margin: '8px 0 0' }}>
              {T(`Cần tối thiểu ${MIN_PHOTOS} và tối đa ${MAX_PHOTOS} ảnh khả dụng.`, `Minimum ${MIN_PHOTOS}, maximum ${MAX_PHOTOS} available photos.`)}
            </p>
          )}
        </Guided>

        )}

        {step < 4 && !s.createSent && (
          <div style={{ marginTop: 24, display: 'flex', flexDirection: 'column', gap: 10 }}>
            {stepGaps.length > 0 && (
              <MissingChips testId="create-step-gaps" lead={T('Còn thiếu ở bước này:', 'Still needed here:')} fields={stepGaps}
                label={MISSING_LABEL} onPick={goToMissing} T={T} />
            )}
            <div style={{ display: 'flex', gap: 10 }}>
              {step > 0 && (
                <button type="button" onClick={() => goTo(step - 1)} data-testid="create-step-back" aria-label={T('Quay lại: ', 'Back: ') + sections[step - 1].title} className="bb-press"
                  style={{ width: 54, height: 52, flex: 'none', borderRadius: 999, border: `1px solid ${rule}`, background: 'transparent', color: ink, fontSize: 18, cursor: 'pointer' }}>‹</button>
              )}
              <button type="button" onClick={() => goTo(step + 1)} data-testid="create-step-next" className="bb-press"
                style={{ flex: 1, minHeight: 52, borderRadius: 999, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
                {step === 0 && sections[0].done
                  ? T('Ổn rồi · Tiếp: ', 'Looks good · Next: ') + sections[1].title
                  : T('Tiếp: ', 'Next: ') + sections[step + 1].title}
              </button>
            </div>
          </div>
        )}

        {(step === 4 || s.createSent) && (
          <>
            {!s.createSent && (
              <button type="button" onClick={() => goTo(3)} data-testid="create-step-back"
                style={{ alignSelf: 'flex-start', marginTop: 18, minHeight: 44, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
                ‹ {T('Quay lại: Vé', 'Back: Tickets')}
              </button>
            )}
            <div
              onClick={s.createSent ? undefined : () => {
                if (!canReview) {
                  setAttemptedReview(true);
                  const field = progress.firstMissing;
                  if (field) guideTo(field, T('Còn thiếu: ', 'Still needed: ') + MISSING_LABEL(field));
                  return;
                }
                setReviewOpen(true);
              }}
              data-testid="create-open-review"
              style={createBtnStyle}
            >
              {s.createSent
                ? T('Đã gửi, đang chờ Banbe duyệt', 'Submitted, waiting for Banbe to review')
                : T('Xem lại sự kiện của bạn', 'Review your event')}
            </div>
            {!s.createSent && missing.length > 0 && (
              <MissingChips testId="create-missing-summary" lead={T('Còn thiếu:', 'Still needed:')} fields={missing}
                label={MISSING_LABEL} onPick={goToMissing} T={T} tone={attemptedReview ? 'error' : 'plain'} style={{ marginTop: 8 }} />
            )}
          </>
        )}
        {s.createError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createError}</p>}
        {s.createMediaError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createMediaError}</p>}
        <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: '12px auto 0', textAlign: 'center', maxWidth: '23ch' }}>{T('Hoàn toàn miễn phí: không phí đăng, không phí giao dịch, không phí ẩn.', 'Completely free: no listing fee, no transaction fee, no hidden fees.')}</p>
      </div>
      {reviewOpen && (
        <ReviewStep
          T={T}
          s={s}
          items={items}
          coverKey={coverKey}
          createCatLabel={createCatLabel}
          recipe={recipe}
          onFixRecipe={fixIngredient}
          onBack={() => setReviewOpen(false)}
          // TASK 3 (event creation validation pass) — defense-in-depth:
          // Review's own fields are read-only display, but re-check here
          // too rather than trust that nothing changed between opening
          // Review and this tap (e.g. a state update from elsewhere). Only
          // a REAL RPC-confirmed success (createSubmit's own return value,
          // not just "the request finished") opens the post-submission
          // chooser — a failure leaves Review open with data intact and
          // s.createError already showing, never the chooser.
          onConfirm={async () => {
            if (!s.createName.trim() || hasFieldErrors) { setReviewOpen(false); setAttemptedReview(true); return false; }
            const good = recipe.filter(c => c.status === 'good').length;
            track('submit_recipe_score', { bucket: good >= 9 ? '9-10' : good >= 7 ? '7-8' : good >= 4 ? '4-6' : '0-3' });
            const ok = await createSubmit(newFilesInOrder, coverIndex, { removePhotoIds: removedExistingIds, existingCoverPath, defaultKeywordsLabel: createCatLabel, noLoader: true });
            if (ok) {
              // A submitted draft is no longer a draft.
              if (s.createDraftId) { deleteDraft(s.createDraftId).then(refreshDrafts); set({ createDraftId: null }); }
            }
            return ok === true;
          }}
          // Note 64: present-modal class. The chooser opens once the ✓ ("Sent") has drawn; review stays under it.
          onConfirmed={() => setSuccessChooserOpen(true)}
        />
      )}
      {recipeOpen && (
        <RecipeSheet checks={recipe} hasData={!!bench} n={bench?.n} onFix={fixIngredient} onClose={() => setRecipeOpen(false)} T={T} />
      )}
      {draftSavedOpen && (
        <DraftSavedCard T={T} count={drafts.length}
          onExit={exitAfterDraft} onNew={startNewDraft}
          onViewDrafts={() => { setDraftSavedOpen(false); setDraftsOpen(true); }}
          onDismiss={() => setDraftSavedOpen(false)} />
      )}
      {draftsOpen && (
        <EventDraftsSheet T={T} EN={EN} drafts={drafts} onOpen={openDraft} onDelete={removeDraft} onClose={() => setDraftsOpen(false)} />
      )}
      {successChooserOpen && (
        <SubmitSuccessChooser
          T={T}
          onCreateAnother={() => {
            setSuccessChooserOpen(false); setReviewOpen(false);
            setItems([]); setCoverKey(null); setPhotoError(''); setAttemptedReview(false);
            seededExistingIds.current = [];
            goCreate();
          }}
          onGoHome={() => { setSuccessChooserOpen(false); goHome(); }}
          onViewPending={() => { setSuccessChooserOpen(false); goDashboard('create'); }}
          onGoAccount={() => { setSuccessChooserOpen(false); goProfile(); }}
        />
      )}
    </div>
    </DoneMarks.Provider>
  );
}

/**
 * "Review before submitting" step (task 1) — TWO tabs (2026-09-29 follow-up):
 * "Nội bộ" (private/host) shows EXACTLY the fields that will be sent (title,
 * gallery order + cover marker, description/intro, full resolved address,
 * date/time, capacity, price, category, included items), the original
 * content of this screen; "Xem trước công khai" (public preview) renders
 * the SAME draft data shaped the way a normal viewer would see it on the
 * real Event Detail page (`EventDetail.jsx`) once approved — same "district
 * ▪︎ live km ▪︎ long date ▪︎ time" where-line format, same price-or-"Miễn
 * phí" rule, same cover/gallery — so a host can sanity-check the public
 * result before ever submitting. Both tabs share one back/confirm footer;
 * only the explicit "Xác nhận và gửi" tap (available from either tab)
 * calls createSubmit. Rendered as a full-screen overlay over CreateEvent's
 * own scroll container rather than a separate route, so there is no
 * navigation/back-stack state to reconcile.
 */
/** Small section heading in the Review step's Private tab (event name / recipe / details / included / photos). */
const reviewHeading = { fontSize: 11.5, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase', color: ink, opacity: 0.6 };

function ReviewStep({ T, s, items, coverKey, createCatLabel, recipe, onFixRecipe, onBack, onConfirm, onConfirmed }) {
  const [tab, setTab] = useState('private');
  const dateLabel = [s.createEventDate, s.createEventTime].filter(Boolean).join(' ▪︎ ') || T('Chưa chọn', 'Not set');
  const market = createFormMarket(s);
  const reviewPrice = s.createPrice.trim() ? (parsePriceInput(s.createPrice, market.currency) ?? 0) : 0;
  const priceLabel = reviewPrice > 0 ? formatMoney(reviewPrice, market.currency) : (s.createPrice.trim() || T('Miễn phí', 'Free'));
  const seatsLabel = s.createSeats.trim() || T('Chưa nhập', 'Not set');
  const addressLabel = s.createLocLabel || [s.createAddressLine, s.createDistrict, s.createCity].filter(Boolean).join(', ') || T('Chưa xác nhận địa chỉ', 'Address not confirmed');
  const includedItems = (s.createIncludedItems || []).filter(it => (it.label || '').trim());
  // Event type facts exactly as guests will see them, and a warning for answers kept for another type that will
  // NOT be published (switching the category never throws them away silently).
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const typesOn = flagOn(s.featureFlags, 'event_type_profiles');
  const primaryType = s.createCats[0] || 'supper';
  const typeDetails = typesOn ? cleanDetails(profileFor(primaryType), (s.createDetails || {})[primaryType]) : {};
  const typeFacts = typesOn ? detailFacts(profileFor(primaryType), typeDetails, lang) : [];
  const droppedTypes = typesOn ? droppedDetailTypes(primaryType, s.createDetails) : [];
  const typeName = (k) => { const c = CAT_DEFS.find(x => x.key === k); return c ? T(c.vi, c.en) : k; };

  // Public preview (owner, 2026-10-21): the REAL Event Detail, rendered from this draft (src/lib/draftPreview.js).
  // The wall clock read in the venue's zone, and shown in that zone (same as the published page will).
  const draftMs = (s.createEventDate && s.createEventTime) ? wallClockToMs(s.createEventDate, String(s.createEventTime).slice(0, 5), market.timeZone) : null;
  const draftDateObj = draftMs != null ? new Date(draftMs) : null;
  const firstCat = CAT_DEFS.find(c => c.key === (s.createCats[0] || 'supper'));
  const coverItem = items.find(p => p.url === coverKey) || items[0];
  const previewPhotos = (coverItem ? [coverItem, ...items.filter(p => p !== coverItem)] : items).map(p => ({ id: p.url, url: p.url }));
  const draftEv = shapeDraftAsCurEvent({
    name: s.createName.trim() || T('(Chưa đặt tên)', '(Untitled)'),
    catKey: firstCat?.key, catLabel: firstCat?.vi || '',
    area: s.createDistrict || '', lat: s.createLat, lng: s.createLng, startsAt: draftDateObj,
    priceVnd: parseDraftPriceVnd(s.createPrice, market.currency), seats: parseInt(s.createSeats, 10) || null,
    timeZone: market.timeZone, currency: market.currency,
    description: s.createDesc.trim(), intro: s.createIntro.trim(), includedItems,
    inviteOnly: s.createVisibility === 'invite', organizerName: (s.orgRegName || '').trim(),
    coverUrl: coverItem?.url || '',
    details: typeDetails,
  });

  // Confirm — the ONLY call site that actually submits, available from either tab (the Public preview shows the same
  // block under the page). AsyncSuccessButton refuses a second activation while pending (on top of
  // BanBeContext's own synchronous createSubmitInFlightRef guard).
  const confirmBlock = (
    <>
      {/* Note 64: the ✓ means "sent for review" (it says "Sent"), never "live": banbe still has to approve it. */}
      <AsyncSuccessButton testId="create-review-confirm"
        label={s.createSent ? T('Đã gửi, đang chờ Banbe duyệt', 'Submitted, waiting for Banbe to review') : T('Xác nhận và gửi', 'Confirm & submit')}
        enabled={!s.createSent} run={onConfirm} onSuccessAnimationComplete={onConfirmed}
        pendingLabel={T('Đang gửi…', 'Submitting…')} successLabel={T('Đã gửi để duyệt', 'Sent for review')}
        style={{ borderRadius: 999, padding: 16, fontSize: 15 }} />
      {s.createError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createError}</p>}
    </>
  );

  const row = (label, value) => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 3, padding: '12px 0', borderBottom: `1px solid ${rule}` }}>
      <span style={{ fontSize: 10.5, color: ink, opacity: 0.6 }}>{label}</span>
      <span style={{ fontSize: 13.5, color: ink, lineHeight: 1.5, whiteSpace: 'pre-wrap' }}>{value}</span>
    </div>
  );

  const tabBtn = (key, label) => (
    <div
      onClick={() => setTab(key)}
      data-testid={`create-review-tab-${key}`}
      style={{
        flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, padding: '10px 0', cursor: 'pointer',
        color: tab === key ? paper : ink,
        background: tab === key ? ink : 'transparent',
        borderRadius: 999,
      }}
    >
      {label}
    </div>
  );

  return (
    <div
      data-testid="create-review-step"
      style={{ position: 'fixed', inset: 0, background: paper, zIndex: 40, display: 'flex', flexDirection: 'column', animation: 'banbeIn 0.25s cubic-bezier(.22,.61,.36,1) both' }}
    >
      <div onClick={onBack} data-testid="create-review-back" style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer', flex: 'none' }}>
        ‹ {T('Quay lại chỉnh sửa', 'Back to edit')}
      </div>
      {/* The scrolling content starts below a hairline, never right against the tabs (owner, 2026-10-21). */}
      <div style={{ padding: '14px 22px 12px', flex: 'none', borderBottom: `1px solid ${rule}` }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Xem lại trước khi gửi', 'Review before submitting')}</span>
        <div style={{ display: 'flex', gap: 6, marginTop: 14, padding: 3, background: 'rgba(27,25,22,0.06)', borderRadius: 999 }}>
          {tabBtn('private', T('Nội bộ (Host)', 'Private (Host)'))}
          {tabBtn('public', T('Xem trước công khai', 'Public preview'))}
        </div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '18px 22px 24px' }}>
        {tab === 'private' ? (
          <>
            {/* Each block gets its own small heading, so the name, the recipe and the details read as sections. */}
            <div style={reviewHeading}>{T('Tên sự kiện', 'Event name')}</div>
            <h1 style={{ ...display(24, { margin: '6px 0 0' }) }}>{s.createName.trim() || T('(Chưa đặt tên)', '(Untitled)')}</h1>

            {recipe && (
              <>
              <div style={{ ...reviewHeading, marginTop: 26 }}>{T('Công thức thành công', 'Recipe for success')}</div>
              <div data-testid="create-review-recipe" style={{ ...cardGlass({ marginTop: 8, padding: '12px 16px 6px' }) }}>
                <div style={{ fontSize: 12.5, fontWeight: 700 }}>
                  {`${recipe.filter(c => c.status === 'good').length}/${recipe.length}`}
                  <span style={{ fontWeight: 400, opacity: 0.65 }}>{' · '}{T('không bắt buộc để gửi', 'never required to submit')}</span>
                </div>
                <RecipeList checks={recipe} onFix={onFixRecipe} T={T} compact />
              </div>
              </>
            )}

            <div style={{ ...reviewHeading, marginTop: 26 }}>{T('Chi tiết sự kiện', 'Event details')}</div>
            <div data-testid="create-review-details" style={{ ...cardGlass({ marginTop: 8, padding: '4px 16px 6px', display: 'flex', flexDirection: 'column' }) }}>
              {row(T('Danh mục', 'Category'), createCatLabel)}
              {row(T('Từ khoá tìm kiếm', 'Search keywords'), s.createKeywords.trim() || T(`(Tự dùng danh mục) ${createCatLabel}`, `(Defaults to category) ${createCatLabel}`))}
              {row(T('Ngày & giờ', 'Date & time'), dateLabel)}
              {row(T('Địa chỉ', 'Address'), addressLabel)}
              {row(T('Số chỗ', 'Capacity'), seatsLabel)}
              {row(T('Giá vé', 'Price'), priceLabel)}
              {row(T('Quyền riêng tư', 'Privacy'), s.createVisibility === 'invite' ? T('Chỉ mời', 'Invite-only') : T('Công khai', 'Public'))}
              {row(T('Ai có thể đặt', 'Who can reserve'), criteriaSummary(normalizeCriteria(s.createCriteria), T(true, false)))}
              {s.createDesc.trim() && row(T('Mô tả', 'Description'), s.createDesc.trim())}
              {s.createIntro.trim() && row(T('Giới thiệu sự kiện', 'Event introduction'), s.createIntro.trim())}
              {typeFacts.map(f => <div key={f.id} data-testid={`create-review-fact-${f.id}`}>{row(f.label, f.value)}</div>)}
            </div>
            {droppedTypes.length > 0 && (
              <p role="note" data-testid="create-review-dropped-details" style={{ fontSize: 12.5, lineHeight: 1.5, color: 'var(--bb-honey)', margin: '10px 2px 0' }}>
                {T(`Thông tin bạn đã nhập cho ${droppedTypes.map(typeName).join(', ')} sẽ không được đăng, vì loại chính là ${typeName(primaryType)}. Chúng vẫn được giữ trong bản nháp nếu bạn đổi lại.`,
                  `What you entered for ${droppedTypes.map(typeName).join(', ')} won't be published, since the main type is ${typeName(primaryType)}. It stays in this draft if you switch back.`)}
              </p>
            )}

            {includedItems.length > 0 && (
              <div style={{ marginTop: 26 }}>
                <div style={reviewHeading}>{T('Bao gồm', 'Included')}</div>
                <div style={{ ...cardGlass({ marginTop: 8, padding: '4px 16px', display: 'flex', flexDirection: 'column' }) }}>
                  {includedItems.map((it, i) => (
                    <div key={i} style={{ padding: '10px 0', borderBottom: i < includedItems.length - 1 ? `1px solid ${rule}` : 'none' }}>
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{it.label.trim()}</span>
                      {it.detail?.trim() && <p style={{ fontSize: 12.5, color: ink, margin: '2px 0 0' }}>{it.detail.trim()}</p>}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {items.length > 0 && (
              <div style={{ marginTop: 26 }}>
                <div style={reviewHeading}>{T('Thứ tự ảnh', 'Photo order')}</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
                  {items.map((p, i) => (
                    <div key={p.url} style={{ ...insetField({ padding: 8, display: 'flex', alignItems: 'center', gap: 10 }) }}>
                      <div style={{ position: 'relative', flex: 'none', width: 56, height: 56, borderRadius: 10, overflow: 'hidden' }}>
                        <div style={bg(p.url, { width: '100%', height: '100%' })} />
                      </div>
                      <span style={{ fontSize: 12.5, color: ink }}>
                        {p.url === coverKey ? T('Ảnh bìa', 'Cover photo') : T(`Ảnh ${i + 1}`, `Photo ${i + 1}`)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        ) : null}
      </div>

      <div style={{ flex: 'none', padding: '10px 22px 40px' }}>{confirmBlock}</div>

      {tab === 'public' && (
        <div data-testid="create-review-public" style={{ position: 'fixed', inset: 0, zIndex: 41, background: paper }}>
          <EventDetail preview={{
            ev: draftEv,
            photos: previewPhotos,
            capacity: parseInt(s.createSeats, 10) || null,
            backLabel: T('Nội bộ (Host)', 'Private (Host)'),
            onBack: () => setTab('private'),
            footer: (
              <>
                <div style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.6, textAlign: 'center', margin: '0 0 8px' }}>
                  {T('Xem trước: khách sẽ thấy đúng trang này', 'Preview: this is exactly what guests will see')}
                </div>
                {confirmBlock}
              </>
            ),
          }} />
        </div>
      )}
    </div>
  );
}

/**
 * TASK 3 (event creation validation pass) — the post-submission chooser.
 * Uses the real native `<dialog>` element (`showModal()`), not a hand-rolled
 * overlay imitating a platform picker — this ticket's own instruction is a
 * "supported platform API," and `<dialog>` is the browser's own native
 * modal primitive (top-layer rendering, native Escape-to-cancel via the
 * `cancel` event, native focus trapping) — closest web equivalent to
 * iOS's `UIAlertController`/`confirmationDialog`. Only ever mounted by a
 * REAL createSubmit() success (see CreateEvent's own `onConfirm`) — a
 * failed submission never reaches this component at all.
 */
function SubmitSuccessChooser({ T, onCreateAnother, onGoHome, onViewPending, onGoAccount }) {
  const dialogRef = useRef(null);
  useEffect(() => { dialogRef.current?.showModal(); }, []);
  // 2026-10-23 (owner, iOS SubmittedChooserCard parity): wide card, next steps as a list, one icon per
  // choice, a bouncy entrance (.bb-bounce-in; a plain fade under Reduce Motion).
  const btnBase = {
    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, width: '100%', minHeight: 50,
    fontSize: 15, fontWeight: 600, fontFamily: 'inherit', borderRadius: 18, cursor: 'pointer',
  };
  const secondary = { ...btnBase, background: fieldSolid, border: `1px solid ${rule}`, color: ink };
  const steps = [
    ['✈️', T('Đã gửi cho banbe', 'Sent to banbe')],
    ['🔎', T('banbe duyệt sự kiện', 'banbe reviews it')],
    ['🔔', T('Lên sóng, bạn sẽ nhận thông báo', 'It goes live and we notify you')],
    ['🔗', T('Chia sẻ được ngay khi được duyệt', "Sharing opens once it's approved")],
  ];
  return (
    <dialog
      ref={dialogRef}
      className="bb-bounce-in"
      data-testid="submit-success-chooser"
      // Native Escape-to-cancel — this ticket's own instruction: "On
      // cancellation of the chooser, default to the pending-events
      // destination" (an unambiguous success outcome, not a dead end).
      onCancel={(e) => { e.preventDefault(); onViewPending(); }}
      // A native `<dialog>` doesn't auto-close on a backdrop click; this
      // treats a click landing on the dialog's own backdrop box (not its
      // inner content, which is a normal-flow child that fully occupies
      // its own box) the same as Escape — same destination, same reasoning.
      onClick={(e) => { if (e.target === dialogRef.current) onViewPending(); }}
      style={{ border: `1px solid ${rule}`, borderRadius: 28, padding: 0, maxWidth: 520, width: 'calc(100% - 40px)', background: paper, color: ink, boxShadow: '0 10px 40px rgba(0,0,0,0.18)' }}
    >
      {/* The end of creating an event is its peak (note 53, peak-end rule): a moment of celebration, then what
          happens next, honestly. The event is still pending review, so there's no link to share yet: the copy says sharing opens at approval (Phase 1 Q5). */}
      <div style={{ padding: 22, position: 'relative' }}>
        <ConfettiBurst top={30} />
        <p style={{ ...display(22, { margin: '0 0 16px' }) }}>🎉 {T('Đã gửi sự kiện!', 'Event submitted!')}</p>
        <ul data-testid="submit-next-steps" style={{ listStyle: 'none', margin: '0 0 16px', padding: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {steps.map(([icon, text]) => (
            <li key={text} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14.5, lineHeight: 1.35 }}>
              <span aria-hidden style={{ flex: 'none', width: 28, height: 28, borderRadius: '50%', background: fieldSolid, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13 }}>{icon}</span>
              {text}
            </li>
          ))}
        </ul>
        <p style={{ fontSize: 13.5, fontWeight: 600, opacity: 0.75, margin: '0 0 12px' }}>{T('Bạn muốn làm gì tiếp theo?', 'What would you like to do next?')}</p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <button onClick={onViewPending} data-testid="submit-chooser-pending" className="bb-press" style={{ ...btnBase, background: ink, color: paper, border: 'none' }}>
            <span aria-hidden>⏳</span>{T('Xem sự kiện đang chờ duyệt', 'View pending events')}
          </button>
          <button onClick={onCreateAnother} data-testid="submit-chooser-create-another" className="bb-press" style={secondary}>
            <span aria-hidden>➕</span>{T('Tạo sự kiện khác', 'Create another event')}
          </button>
          <div style={{ display: 'flex', gap: 10 }}>
            <button onClick={onGoHome} data-testid="submit-chooser-home" className="bb-press" style={secondary}>
              <span aria-hidden>🏠</span>{T('Trang chủ', 'Home')}
            </button>
            <button onClick={onGoAccount} data-testid="submit-chooser-account" className="bb-press" style={secondary}>
              <span aria-hidden>👤</span>{T('Tài khoản', 'Account')}
            </button>
          </div>
        </div>
      </div>
    </dialog>
  );
}

function Field({ label, value, onChange, placeholder, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5, minWidth: 0, width: '100%', boxSizing: 'border-box', ...style }}>
      <label style={labelStyle}>{label}</label>
      <input value={value} onChange={onChange} placeholder={placeholder} style={{ ...insetField({ padding: '11px 12px' }), fontSize: 13.5, fontFamily: FACE, color: ink, outline: 'none', minWidth: 0, width: '100%', boxSizing: 'border-box', border: 'none' }} />
    </div>
  );
}

const labelStyle = { fontSize: 11.5, color: ink };
const fieldInput = { ...insetField({ padding: '13px 14px' }), fontSize: 14, fontFamily: FACE, color: ink, outline: 'none', minWidth: 0, width: '100%', boxSizing: 'border-box', border: 'none' };

// Note 48 form style (iOS parity): icon + uppercase label, large rounded outlined inputs, big pick tiles.
const bigInput = { width: '100%', boxSizing: 'border-box', fontSize: 16, padding: '15px 16px', borderRadius: 14, border: `1px solid ${rule}`, background: paper, color: ink, fontFamily: FACE, outline: 'none' };
const fieldCol = { display: 'flex', flexDirection: 'column', gap: 8 };
const hintText = { fontSize: 12.5, lineHeight: 1.5, color: ink, margin: 0, opacity: 0.7 };
const errText = { fontSize: 11.5, color: alert, margin: '6px 0 0' };
const subLabel = { display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 500, color: ink, marginTop: 4 };
// One emoji per category everywhere (note 53): shared with the onboarding answers.
const CAT_EMOJI = CATEGORY_EMOJI;

const ICON_PATHS = {
  person: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 8a7 7 0 0 1 14 0',
  at: 'M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Zm0 0v1.5a2.5 2.5 0 0 0 5 0V12a9 9 0 1 0-3.5 7.1',
  quote: 'M7 7h4v4H8a3 3 0 0 0-1 2.2V17M14 7h4v4h-3a3 3 0 0 0-1 2.2V17',
  sparkles: 'M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2 2M16 16l2 2M6 18l2-2M16 8l2-2',
  text: 'M4 6h16M4 10h16M4 14h12M4 18h9',
  doc: 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h6',
  bubble: 'M4 5h16v11H9l-5 4z',
  pin: 'M12 21s7-6.2 7-12a7 7 0 1 0-14 0c0 5.8 7 12 7 12Zm0-9a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
  calendar: 'M4 6h16v15H4zM4 10h16M8 3v4M16 3v4',
  tag: 'M3 12V4h8l10 10-8 8zM7.5 7.5h.01',
  people: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm-6 9a6 6 0 0 1 12 0M16 4.5a3.5 3.5 0 0 1 0 6.5M18 20a6 6 0 0 0-2.5-4.9',
  lock: 'M6 11h12v10H6zM8 11V8a4 4 0 0 1 8 0v3',
  grid: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z',
  search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14Zm5-2 5 5',
  checklist: 'M4 6l2 2 3-3M4 13l2 2 3-3M12 7h8M12 14h8M12 20h8',
  photo: 'M3 5h18v14H3zM8 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4ZM21 16l-5-5-9 8',
  target: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Zm0-4a5 5 0 1 0 0-10 5 5 0 0 0 0 10Zm0-4a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z',
};

function Icon({ name }) {
  return (
    <svg aria-hidden width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none' }}>
      <path d={ICON_PATHS[name] || ICON_PATHS.sparkles} />
    </svg>
  );
}

// Note 66: which required fields are complete (and which just became so), from CreateEvent's single progress result.
const DoneMarks = createContext(null);
const visuallyHidden = { position: 'absolute', width: 1, height: 1, padding: 0, margin: -1, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap', border: 0 };

/** The small ✓ after a complete required field's label. `pop` draws it once (a plain fade under Reduce Motion). */
function DoneMark({ field, pop }) {
  return (
    <span aria-hidden data-testid={`create-done-${field}`} data-pop={pop ? 'true' : undefined} className={pop ? 'bb-done-mark bb-done-pop' : 'bb-done-mark'}>
      <svg width="10" height="10" viewBox="0 0 12 12" fill="none"><path d="M2.5 6.4 5 8.8l4.5-5.3" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></svg>
    </span>
  );
}

function FormLabel({ icon, text, required, tag, tagTone, field }) {
  const marks = useContext(DoneMarks);
  const done = !!(field && marks?.done(field));
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: ink, opacity: 0.85 }}>
      <Icon name={icon} />
      <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.05em', textTransform: 'uppercase' }}>{text}</span>
      {required && !done && <span style={{ color: alert, fontSize: 12, fontWeight: 600 }}>*</span>}
      {done && <DoneMark field={field} pop={marks.fresh(field)} />}
      <span style={{ flex: 1 }} />
      {tag && (
        <span data-tone={tagTone || undefined} style={{ fontSize: 11, fontWeight: 600, padding: '3px 8px', borderRadius: 999, fontVariantNumeric: 'tabular-nums',
          background: tagTone === 'error' ? 'rgba(var(--bb-alert-rgb),0.14)' : tagTone === 'warning' ? 'var(--bb-honey-bg)' : 'rgba(var(--bb-fg-rgb),0.08)',
          color: tagTone === 'error' ? 'var(--bb-alert)' : tagTone === 'warning' ? 'var(--bb-honey)' : undefined }}>{tag}</span>
      )}
    </div>
  );
}

function BigField({ icon, label, required, value, onChange, placeholder, testId, invalid, describedBy, field }) {
  return (
    <label style={fieldCol}>
      <FormLabel icon={icon} text={label} required={required} field={field} />
      <input value={value} onChange={onChange} placeholder={placeholder} data-testid={testId} style={bigInput}
        aria-invalid={invalid ? true : undefined} aria-describedby={invalid && describedBy ? describedBy : undefined} />
    </label>
  );
}

// Note 53: an anchor for "take me to this field" (recipe Fix, Review with gaps). While it's the target it carries
// the For You halo (.bb-attn in index.css) and a small "👇" tip floating ABOVE it, out of the layout, so nothing
// moves while the host types.
function Guided({ field, attn, id, style, children }) {
  const on = attn?.field === field;
  return (
    <div data-field={field} id={id} className={on ? 'bb-attn' : undefined} style={{ ...style, ...(on ? { position: 'relative' } : null) }}>
      {on && attn.hint && (
        <div className="bb-coach" data-testid="create-coach" role="status"
          style={{ position: 'absolute', left: 0, bottom: 'calc(100% + 12px)', zIndex: 3, maxWidth: '100%', padding: '7px 12px', borderRadius: 12,
            background: ink, color: paper, fontSize: 12.5, fontWeight: 600, lineHeight: 1.35, boxShadow: '0 6px 18px rgba(27,25,22,0.18)', pointerEvents: 'none' }}>
          👇 {attn.hint}
        </div>
      )}
      {children}
    </div>
  );
}

// `sub` (note 50): the option's outcome BEFORE it's chosen ("fills 85%", "typical"), like a filter pill's count.
function PickTile({ label, sub, selected, onClick, testId }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId}
      style={{ minHeight: 48, padding: '4px 4px', borderRadius: 14, fontFamily: 'inherit', fontSize: 15, fontWeight: selected ? 600 : 400, cursor: 'pointer',
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 1,
        border: selected ? '1px solid transparent' : `1px solid ${rule}`, background: selected ? ink : paper, color: selected ? paper : ink }}>
      <span style={{ maxWidth: '100%', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</span>
      {sub && <span data-testid={testId ? `${testId}-sub` : undefined} style={{ fontSize: 10.5, fontWeight: 500, opacity: 0.7 }}>{sub}</span>}
    </button>
  );
}

// One insight line per field (note 50, the video's "busier" caveat): the line is short; the evidence and the
// full reasoning sit behind "Why?". A data line only appears when the benchmark slice exists; otherwise the
// recipe's general tip (no numbers) is shown, and nothing at all when the ingredient is already fine and
// there is no data to add.
function Insight({ check, line, T, testId }) {
  const [open, setOpen] = useState(false);
  if (!check) return null;
  const copy = recipeCopy(check, T);
  const text = line || (check.status !== 'good' ? copy.title : null);
  if (!text) return null;
  return (
    <div data-testid={testId} data-source={check.source} data-status={check.status} style={{ fontSize: 12.5, lineHeight: 1.5, color: ink }}>
      <span aria-hidden="true" style={{ color: check.status === 'good' ? ink : 'var(--bb-honey)', marginInlineEnd: 6 }}>{check.status === 'good' ? '✓' : '✦'}</span>
      <span style={{ opacity: 0.85 }}>{text}</span>{' '}
      <button type="button" onClick={() => setOpen(v => !v)} aria-expanded={open}
        style={{ border: 'none', background: 'none', padding: 0, color: ink, fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, textDecoration: 'underline', cursor: 'pointer', opacity: 0.75 }}>
        {T('Vì sao?', 'Why?')}
      </button>
      {open && <div style={{ marginTop: 4, opacity: 0.7 }}>{copy.detail}</div>}
    </div>
  );
}

// Price histogram of similar events (get_host_benchmarks) with this event's own price marked — the market
// behind the decision, same idea as the Home filter's histogram.
// The market histogram is also the price slider (owner, 2026-10-21): drag the clay knob (or tap the track, or use the
// arrow keys) to set the price; quick picks and the typed field stay in sync through createPrice. Bars and marker are
// inset by half a knob so the marker sits exactly under the native thumb's centre.
const KNOB = 26;
function PriceMarket({ price, mine, T, catLabel, currency = 'VND', onChange }) {
  const [dragging, setDragging] = useState(false);
  const counts = price.histogram || [];
  const peak = Math.max(1, ...counts);
  const step = priceSliderStep(currency);
  const short = (v) => formatMoneyShort(v, currency);
  const lowest = Math.ceil(price.min / step) * step;
  const highest = Math.floor(price.max / step) * step;
  const narrow = !(highest > lowest);
  const unset = !(mine > 0);
  const value = unset ? fractionToPrice(priceToFraction(price.median ?? price.min, price) ?? 0.5, price, step) : mine;
  const f = priceToFraction(value, price) ?? 0.5;
  const at = `calc(${KNOB / 2}px + ${f} * (100% - ${KNOB}px))`;
  return (
    <div data-testid="create-price-market" style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <span style={{ ...hintText, opacity: 0.8 }}>
        {T(`${catLabel} · trung vị ${short(price.median)} · ${price.n} sự kiện`, `${catLabel} · median ${short(price.median)} · ${price.n} events`)}
      </span>
      <div style={{ position: 'relative', paddingTop: 6 }}>
        <div aria-hidden="true" style={{ position: 'relative', display: 'flex', alignItems: 'flex-end', gap: 3, height: 44, padding: `0 ${KNOB / 2}px` }}>
          {counts.map((c, i) => {
            // Bars up to the chosen price are filled in: the part of the market you are priced against.
            const reached = !unset && (i + 0.5) / Math.max(1, counts.length) <= f;
            return <div key={i} style={{ flex: 1, height: `${Math.max(6, (c / peak) * 100)}%`, borderRadius: 3, background: reached ? 'rgba(var(--bb-clay-rgb),0.55)' : 'rgba(var(--bb-fg-rgb),0.2)', transition: 'background .15s ease' }} />;
          })}
          <div data-testid="create-price-marker" style={{ position: 'absolute', top: -4, bottom: -14, left: `calc(${at} - 1px)`, width: 2, borderRadius: 1, background: unset ? 'rgba(var(--bb-fg-rgb),0.3)' : clay }} />
        </div>
        {dragging && (
          <div aria-hidden="true" style={{ position: 'absolute', top: -22, left: at, transform: 'translateX(-50%)', fontSize: 12, fontWeight: 700, color: paper, background: ink, borderRadius: 999, padding: '3px 9px', whiteSpace: 'nowrap', pointerEvents: 'none' }}>
            {short(value)}
          </div>
        )}
        <input
          type="range" className={`bb-range bb-price${unset ? ' bb-price-unset' : ''}`} data-testid="create-price-slider"
          min={narrow ? price.min : lowest} max={narrow ? price.max : highest} step={narrow ? 1 : step} value={value}
          aria-label={T('Kéo để chọn giá vé', 'Drag to set the ticket price')} aria-valuetext={short(value)}
          onChange={(e) => onChange?.(Number(e.target.value))}
          onPointerDown={() => setDragging(true)} onPointerUp={() => setDragging(false)} onPointerCancel={() => setDragging(false)} onBlur={() => setDragging(false)}
          style={{ display: 'block', width: '100%', marginTop: 2 }}
        />
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, opacity: 0.6 }}>
        <span>{short(price.min)}</span>
        <span style={{ fontWeight: 600 }}>{T('‹ Kéo để chọn giá ›', '‹ Drag to set your price ›')}</span>
        <span>{short(price.max)}</span>
      </div>
    </div>
  );
}

function StepCard({ title, id, children }) {
  return (
    <div id={id} style={{ ...cardGlass({ marginTop: 22, padding: 18, display: 'flex', flexDirection: 'column', gap: 18 }) }}>
      <h2 style={display(20, { margin: 0 })}>{title}</h2>
      {children}
    </div>
  );
}

/** "Still needed" as tappable chips: each one takes the host to that field. */
function MissingChips({ testId, lead, fields, label, onPick, T, tone = 'plain', style }) {
  const color = tone === 'error' ? alert : ink;
  return (
    <div data-testid={testId} role="group" aria-label={lead}
      style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'center', gap: 6, ...style }}>
      <span style={{ fontSize: 12.5, color, opacity: tone === 'error' ? 1 : 0.7 }}>{lead}</span>
      {fields.map(id => (
        <button key={id} type="button" onClick={() => onPick(id)} data-testid={`${testId}-${id}`} className="bb-press"
          aria-label={T('Đi tới: ', 'Go to: ') + label(id)}
          style={{ minHeight: 44, padding: '0 12px', borderRadius: 999, border: `1px solid ${tone === 'error' ? alert : rule}`, background: 'transparent',
            color, fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
          {label(id)}<span aria-hidden style={{ opacity: 0.6 }}>›</span>
        </button>
      ))}
    </div>
  );
}

/** The event type's own facts (a supper club: dietary options, BYO, dress code). All optional. */
function TypeDetailsEditor({ profile, values, lang, T, onChange, attn, showErrors, required }) {
  const fields = profile.detailFields || {};
  const chip = (on) => ({
    minHeight: 44, padding: '0 14px', borderRadius: 999, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer',
    border: `1px solid ${on ? ink : rule}`, background: on ? ink : 'transparent', color: on ? paper : ink, fontWeight: on ? 600 : 400,
  });
  const isEmpty = (v) => v == null || (Array.isArray(v) ? !v.some(x => String(x).trim()) : !String(v).trim());
  return (
    <div data-testid="create-type-details" style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
      <p style={{ ...hintText, margin: 0 }}>{T('Khách hay hỏi những điều này trước khi đặt chỗ.', 'Guests often ask about these before booking.')}</p>
      {profile.wizard.details.map(id => {
        const def = fields[id];
        if (!def) return null;
        const label = localized(def.label, lang);
        const req = required.includes(id);
        const err = showErrors && req && isEmpty(values[id]);
        const cur = values[id];
        let body;
        if (def.kind === 'text') {
          body = (
            <input value={cur || ''} maxLength={def.max || 80} onChange={(e) => onChange(id, e.target.value)}
              placeholder={def.placeholder ? localized(def.placeholder, lang) : ''} data-testid={`create-detail-${id}`} style={bigInput} />
          );
        } else if (def.kind === 'list') {
          const items = Array.isArray(cur) && cur.length ? cur : [''];
          body = (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {items.map((it, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <input value={it} maxLength={def.itemMax || 60} data-testid={`create-detail-${id}-${i}`}
                    aria-label={`${label} ${i + 1}`} placeholder={def.placeholder ? localized(def.placeholder, lang) : ''}
                    onChange={(e) => onChange(id, items.map((x, j) => (j === i ? e.target.value : x)))} style={{ ...bigInput, flex: 1 }} />
                  {items.length > 1 && (
                    <button type="button" onClick={() => onChange(id, items.filter((_, j) => j !== i))} aria-label={T('Xoá', 'Remove')}
                      style={{ width: 44, height: 44, border: 'none', background: 'none', color: ink, opacity: 0.45, fontSize: 18, cursor: 'pointer' }}>ⓧ</button>
                  )}
                </div>
              ))}
              {items.length < (def.max || 6) && (
                <button type="button" data-testid={`create-detail-${id}-add`} onClick={() => onChange(id, [...items, ''])}
                  style={{ minHeight: 44, borderRadius: 14, border: '1.2px dashed rgba(var(--bb-fg-rgb),0.3)', background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
                  ⊕ {T('Thêm', 'Add')}
                </button>
              )}
            </div>
          );
        } else {
          const multi = def.kind === 'multi';
          body = (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {def.options.map(o => {
                const on = multi ? Array.isArray(cur) && cur.includes(o.id) : cur === o.id;
                const next = multi
                  ? (on ? cur.filter(x => x !== o.id) : [...(Array.isArray(cur) ? cur : []), o.id])
                  : (on ? null : o.id);
                return (
                  <button key={o.id} type="button" aria-pressed={on} data-testid={`create-detail-${id}-${o.id}`}
                    onClick={() => onChange(id, next)} style={chip(on)}>{localized(o, lang)}</button>
                );
              })}
            </div>
          );
        }
        return (
          <Guided key={id} field={id} attn={attn} style={fieldCol}>
            <div role={def.kind === 'text' ? undefined : 'group'} aria-label={label} style={fieldCol}>
              <FormLabel icon="sparkles" field={id} text={label} required={req} />
              {def.hint && <p style={{ ...hintText, margin: 0 }}>{localized(def.hint, lang)}</p>}
              {body}
              {err && <p style={errText}>{T(`Hãy chọn ${label.toLowerCase()}.`, `Please fill in ${label.toLowerCase()}.`)}</p>}
            </div>
          </Guided>
        );
      })}
    </div>
  );
}
