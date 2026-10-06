import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS, CREATE_PALETTES, bg, mapsUrl } from '../data/events.js';
import { liveEventOverrides, formatVnEventDate } from '../lib/countdown.js';
import { supabase } from '../lib/supabase.js';
import { parseExcelOrZipPackage } from '../lib/excelEventImport.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, FACE, display, alert } from '../theme.js';
import { fieldGlass, cardGlass, insetField } from './hostStyle.js';

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

const CAT_DEFS = [
  { key: 'supper', vi: 'Supper club', en: 'Supper club' },
  { key: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { key: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { key: 'music', vi: 'Nhạc', en: 'Music' },
  { key: 'popup', vi: 'Pop-up', en: 'Pop-up' },
];

export default function CreateEvent() {
  const {
    state, T, trStatus, stripKm, curEvent: ev, createBack,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createIntroType, createKeywordsType, createLocType, createEventDateType, createEventTimeType, createPriceType, createSeatsType,
    retryCreateAddressSearch, selectCreateAddressSuggestion, clearCreateAddressSelection,
    pickCreateCat, pickCreatePalette, pickCreateVisibility,
    addCreateIncludedItem, removeCreateIncludedItem, setCreateIncludedItem, importParsedEvent,
    createSubmit, goEvent, loadHomeLiveEvents,
    goCreate, goHome, goDashboard, goProfile,
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
  const [items, setItems] = useState([]); // { kind, id?, file?, url, storagePath? }[]
  const [coverKey, setCoverKey] = useState(null); // items[i]'s own url, used as a stable key
  const [photoError, setPhotoError] = useState('');
  // "Review before submitting" step (task 1) — a plain local bool, not a
  // second screen/route: every field it shows already lives in the global
  // store (`s.create*`) or this component's own `items`/`coverKey` state,
  // so toggling back to the form loses nothing — there is no separate
  // draft to reconcile. Only the review step's own explicit "Xác nhận và
  // gửi" button ever calls createSubmit; the form's own primary button
  // only ever opens this step.
  const [reviewOpen, setReviewOpen] = useState(false);
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

  useEffect(() => () => {
    items.forEach(it => { if (it.kind === 'new') URL.revokeObjectURL(it.url); });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

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
          'Đã điền vào biểu mẫu bên dưới — kiểm tra các mục còn thiếu trước khi gửi.',
          'Filled in the form below — check the flagged fields before submitting.'
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
  const fieldErrors = {
    desc: !s.createDesc.trim(),
    dateTime: !s.createEventDate || !s.createEventTime,
    seats: !(parseInt(s.createSeats, 10) > 0),
    cats: s.createCats.length === 0,
    included: !s.createIncludedItems.some(it => (it.label || '').trim()),
    photos: photos.length < MIN_PHOTOS || photos.length > MAX_PHOTOS,
  };
  const hasFieldErrors = Object.values(fieldErrors).some(Boolean);
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

  const cur = CREATE_PALETTES.find(x => x.key === s.createPalette) || CREATE_PALETTES[0];
  const dark = cur.text !== '#1B1916';
  const btnText = cur.accent === '#1B1916' ? '#F7F4EC' : cur.bg;
  const createCatLabel = (s.createCats.length ? s.createCats : ['supper']).map(k => {
    const d = CAT_DEFS.find(c => c.key === k);
    return d ? T(d.vi, d.en) : k;
  }).join(' ▪︎ ');
  const createNameShown = s.createName.trim() || T('Tên sự kiện của bạn', 'Your event name');

  const createBtnStyle = {
    marginTop: 26, fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 15, borderRadius: 999,
    background: s.createSent ? 'rgba(27,25,22,0.16)' : (s.createName.trim() ? ink : 'rgba(27,25,22,0.16)'),
    color: s.createSent ? ink : (s.createName.trim() ? paper : ink),
    cursor: s.createName.trim() && !s.createSent ? 'pointer' : 'default', transition: 'background .15s',
  };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Create event">
      <div onClick={createBack} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {createBackLabel}</div>
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

        <div style={{ ...cardGlass({ marginTop: 22, padding: 16, display: 'flex', flexDirection: 'column', gap: 12 }) }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Hồ sơ người tổ chức', 'Organizer profile')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Hiện trên trang của bạn', 'Shown on your page')}</span>
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <Field style={{ flex: 1.2 }} label={T('Tên', 'Name')} value={s.orgRegName} onChange={orgRegNameType} placeholder="Bếp Nhỏ" />
            <Field style={{ flex: 1 }} label="Instagram" value={s.orgRegIg} onChange={orgRegIgType} placeholder="@bepnho.saigon" />
          </div>
          <Field label={T('Giới thiệu', 'About')} value={s.orgRegDesc} onChange={orgRegDescType} placeholder={T('Minh nấu cho người lạ từ 2021…', 'Minh has cooked for strangers since 2021…')} />
        </div>

        <div style={{ ...cardGlass({ marginTop: 22, padding: 16, display: 'flex', flexDirection: 'column', gap: 12 }) }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện', 'Event')}</span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 0 }}>
          <label style={labelStyle}>{T('Tên sự kiện', 'Event name')} <span style={{ color: alert }}>*</span></label>
          <input value={s.createName} onChange={createNameType} placeholder="Bếp Nhỏ №13" style={fieldInput} />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 0 }}>
          <label style={labelStyle}>{T('Mô tả', 'Description')} <span style={{ color: alert }}>*</span></label>
          <input value={s.createDesc} onChange={createDescType} placeholder={T('Mười bốn chỗ. Một ga-ra cải tạo…', 'Fourteen seats. A converted garage…')} style={fieldInput} />
          {attemptedReview && fieldErrors.desc && <p style={{ fontSize: 11, color: alert, margin: 0 }}>{T('Hãy nhập mô tả.', 'Please enter a description.')}</p>}
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <label style={labelStyle}>{T('Giới thiệu sự kiện', 'Event introduction')}</label>
            <span style={{ fontSize: 10.5, color: ink }}>{s.createIntro.length}/4000</span>
          </div>
          <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: 0, opacity: 0.75 }}>
            {T('Một đoạn giới thiệu dài hơn, hấp dẫn. Tách dòng trống giữa các đoạn. Không phải quảng cáo giả, không phải "Bao gồm".', 'A longer, attractive write-up. Leave a blank line between paragraphs. Not fabricated marketing copy, not the same as "Included".')}
          </p>
          <textarea
            value={s.createIntro} onChange={createIntroType} maxLength={4000} rows={6}
            placeholder={T('Một buổi tối ấm cúng cho mười bốn người lạ…\n\nMón chính là…', 'A cozy evening for fourteen strangers…\n\nThe main course is…')}
            style={{ ...fieldInput, resize: 'vertical', lineHeight: 1.5, fontFamily: FACE }}
          />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 0 }}>
          <label style={labelStyle}>{T('Địa điểm', 'Location')} <span style={{ color: alert }}>*</span></label>
          <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: 0, opacity: 0.75 }}>
            {T(
              'Gõ số nhà + tên đường (hoặc tên địa điểm nếu không có số nhà) rồi chọn một gợi ý — cần thiết để đăng sự kiện.',
              'Type a house number + street (or a venue name if there is no house number), then pick a suggestion — required to publish.'
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
            style={fieldInput} data-testid="create-location-input"
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
              {/* Nominatim's usage policy requires attribution wherever
                  its results are shown, same as MapExplore's own
                  MapLibre attribution elsewhere in this app. */}
              <div style={{ padding: '6px 12px', fontSize: 9.5, color: ink, opacity: 0.45, borderTop: `1px solid ${rule}` }}>
                © OpenStreetMap contributors
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
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 0 }}>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Ngày', 'Date')} <span style={{ color: alert }}>*</span></label>
            <input
              type="date" value={s.createEventDate} onChange={createEventDateType}
              min={new Date().toISOString().slice(0, 10)}
              data-testid="create-event-date" style={fieldInput}
            />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Giờ', 'Time')} <span style={{ color: alert }}>*</span></label>
            <input
              type="time" value={s.createEventTime} onChange={createEventTimeType}
              data-testid="create-event-time" style={fieldInput}
            />
          </div>
        </div>
        {attemptedReview && fieldErrors.dateTime && <p style={{ fontSize: 11, color: alert, margin: '6px 0 0' }}>{T('Hãy chọn ngày và giờ diễn ra.', 'Please pick a date and time.')}</p>}

        <div style={{ display: 'flex', gap: 10, marginTop: 0 }}>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Giá vé', 'Ticket price')}</label>
            <input value={s.createPrice} onChange={createPriceType} placeholder="500.000₫" style={fieldInput} />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Số chỗ', 'Seats')} <span style={{ color: alert }}>*</span></label>
            <input value={s.createSeats} onChange={createSeatsType} placeholder="14" style={fieldInput} />
          </div>
        </div>
        {attemptedReview && fieldErrors.seats && <p style={{ fontSize: 11, color: alert, margin: '6px 0 0' }}>{T('Hãy nhập số chỗ lớn hơn 0.', 'Please enter a number of seats greater than 0.')}</p>}

        {/* Strict invite-only events (migration 113) — Public vs Invite-Only
            is deliberately a peer of every other form field here, not a
            separate "advanced" section: it changes who can even discover
            the event, so it needs the same visibility a host gives price/
            capacity. Kept separate from approval mode (not exposed in this
            form at all) and from admin review — see set_event_visibility's
            own migration comment: private is not auto-approved. */}
        <div style={{ marginTop: 0 }}>
          <label style={labelStyle}>{T('Quyền riêng tư', 'Privacy')}</label>
          <div style={{ display: 'flex', gap: 8, marginTop: 0 }}>
            {[
              { key: 'public', vi: 'Công khai', en: 'Public' },
              { key: 'invite', vi: 'Chỉ mời', en: 'Invite-only' },
            ].map(opt => (
              <button
                key={opt.key}
                type="button"
                onClick={() => pickCreateVisibility(opt.key)}
                data-testid={`create-visibility-${opt.key}`}
                style={{
                  flex: 1, padding: '10px 12px', borderRadius: 10,
                  border: `1px solid ${s.createVisibility === opt.key ? ink : rule}`,
                  background: s.createVisibility === opt.key ? ink : 'transparent',
                  color: s.createVisibility === opt.key ? paper : ink,
                  fontSize: 13, cursor: 'pointer',
                }}
              >
                {T(opt.vi, opt.en)}
              </button>
            ))}
          </div>
          <p style={{ fontSize: 11, color: ink, opacity: 0.6, margin: '6px 0 0' }}>
            {s.createVisibility === 'invite'
              ? T('Chỉ người được mời mới thấy và đặt được sự kiện này. Bạn vẫn cần được banbe duyệt.', 'Only invited people can see or book this event. It still needs banbe approval.')
              : T('Ai cũng có thể tìm thấy và đặt sự kiện này.', 'Anyone can discover and book this event.')}
          </p>
        </div>

        <div style={{ marginTop: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Danh mục', 'Category')} <span style={{ color: alert }}>*</span></span>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Tối đa 2 danh mục', 'Max 2 categories')}</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 0 }}>
            {CAT_DEFS.map(c => {
              const on = s.createCats.includes(c.key);
              const isSecond = on && s.createCats[1] === c.key;
              return (
                <span key={c.key} onClick={() => pickCreateCat(c.key)} style={{ fontSize: 12.5, padding: '9px 14px', borderRadius: 999, cursor: 'pointer', border: on ? '1px solid transparent' : `1px solid ${rule}`, background: on ? ink : 'transparent', color: on ? paper : ink, fontWeight: on ? 600 : 400 }}>
                  {T(c.vi, c.en)}{isSecond ? ' ▪︎ +' : ''}
                </span>
              );
            })}
          </div>
          {attemptedReview && fieldErrors.cats && <p style={{ fontSize: 11, color: alert, margin: '6px 0 0' }}>{T('Hãy chọn ít nhất một danh mục.', 'Please pick at least one category.')}</p>}
        </div>

        {/* Keyword-search fix (migration 108) — so this event actually
            surfaces in Map's search box for terms beyond its literal
            name/district. Left blank, submission defaults it to the
            category label(s) picked just above (never silently empty). */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 0 }}>
          <label style={labelStyle}>{T('Từ khoá tìm kiếm', 'Search keywords')}</label>
          <input
            value={s.createKeywords} onChange={createKeywordsType}
            placeholder={T('vd. tiệc tối, rượu vang, ẩm thực Việt', 'e.g. supper club, wine, Vietnamese food')}
            style={fieldInput}
          />
          <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: 0, opacity: 0.75 }}>
            {T('Cách nhau bằng dấu phẩy. Để trống sẽ tự dùng danh mục đã chọn ở trên.', 'Comma-separated. Left blank, the category picked above is used instead.')}
          </p>
        </div>

        </div>

        {/* Photo-management cleanup (task 1, screenshot 1 follow-up) — a
            clean vertical list, one row per photo, replacing the old
            4-column grid where remove/reorder/cover controls were tiny
            absolutely-positioned pills stacked on top of each other and on
            top of the thumbnail itself. Each row's own thumbnail is a
            fixed, stable 64x64 square (same `bg()` cover-fit helper
            EventDetail's own photo strip uses — matches its presentation,
            just laid out as a row instead of a horizontal strip since this
            view also needs room for per-photo controls). Remove/reorder/
            set-cover are the SAME actions the old grid had (this data model
            has no drag-and-drop reordering — only up/down-swap — so nothing
            new was invented), just given their own normal flex-row space
            instead of overlapping the photo. */}
        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Hình ảnh', 'Photos')} <span style={{ color: alert }}>*</span></span>
            <span style={{ fontSize: 10.5, color: ink }}>{photos.length}/{MAX_PHOTOS} ({T(`tối thiểu ${MIN_PHOTOS}`, `min ${MIN_PHOTOS}`)})</span>
          </div>
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
        </div>

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Bao gồm', 'Included')} <span style={{ color: alert }}>*</span></span>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Tối đa 3 mục', 'Up to 3 items')}</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 10 }}>
            {s.createIncludedItems.map((it, i) => (
              <div key={i} style={{ ...cardGlass({ padding: 12, display: 'flex', flexDirection: 'column', gap: 6 }) }}>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                  <input
                    value={it.label} maxLength={60}
                    onChange={(e) => setCreateIncludedItem(i, 'label', e.target.value)}
                    placeholder={T('Tên mục (vd. Nước uống)', 'Label (e.g. Drinks)')}
                    style={{ ...insetField({ padding: '9px 11px' }), flex: 1, fontSize: 13, fontFamily: FACE, color: ink, outline: 'none', border: 'none', minWidth: 0 }}
                  />
                  <span onClick={() => removeCreateIncludedItem(i)} style={{ fontSize: 12, color: ink, opacity: 0.6, cursor: 'pointer', flex: 'none' }}>{T('Xoá', 'Remove')}</span>
                </div>
                <input
                  value={it.detail} maxLength={300}
                  onChange={(e) => setCreateIncludedItem(i, 'detail', e.target.value)}
                  placeholder={T('Giải thích rõ hơn (không bắt buộc)', 'Fuller explanation (optional)')}
                  style={{ ...insetField({ padding: '9px 11px' }), fontSize: 12.5, fontFamily: FACE, color: ink, outline: 'none', border: 'none' }}
                />
              </div>
            ))}
            {s.createIncludedItems.length < 3 && (
              <span onClick={addCreateIncludedItem} style={{ fontSize: 12.5, color: ink, fontWeight: 600, cursor: 'pointer' }}>+ {T('Thêm mục', 'Add item')}</span>
            )}
          </div>
          {attemptedReview && fieldErrors.included && <p style={{ fontSize: 11, color: alert, margin: '6px 0 0' }}>{T('Hãy thêm ít nhất một mục Bao gồm.', 'Please add at least one Included item.')}</p>}
        </div>

        <div style={{ marginTop: 22 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Bảng màu', 'Palette')}</span>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10, marginTop: 10 }}>
            {CREATE_PALETTES.map(d => (
              <div key={d.key} onClick={() => pickCreatePalette(d.key)} style={{ display: 'flex', flexDirection: 'column', gap: 4, cursor: 'pointer' }}>
                <div style={{ height: 46, background: d.bg, position: 'relative', overflow: 'hidden', borderRadius: 12, border: d.key === s.createPalette ? `2px solid ${ink}` : '1px solid rgba(27,25,22,0.16)' }}>
                  <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 9, background: d.accent }} />
                </div>
                <span style={{ fontSize: 11, color: ink, fontWeight: 500 }}>{d.name}</span>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 14, background: cur.bg, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, overflow: 'hidden' }}>
            <div style={{ padding: '12px 14px 14px', display: 'flex', flexDirection: 'column', gap: 3 }}>
              <span style={{ fontSize: 9, fontWeight: 600, color: dark ? 'rgba(247,244,236,0.72)' : ink }}>{createCatLabel}</span>
              <span style={{ ...display(19, { lineHeight: 1.25, color: cur.text }) }}>{createNameShown}</span>
              <div style={{ marginTop: 10, background: cur.accent, color: btnText, fontSize: 12, fontWeight: 600, textAlign: 'center', padding: 11, borderRadius: 999 }}>{T('Giữ chỗ', 'Reserve')}</div>
            </div>
          </div>
          <p style={{ fontSize: 11, lineHeight: 1.55, color: ink, margin: '12px 0 0' }}>{T('Sự kiện mới sẽ ở trạng thái chờ duyệt. Một tài khoản admin riêng của banbe sẽ kiểm tra trước khi mở bán.', 'New events enter review. A separate banbe admin account approves them before they go live.')}</p>
        </div>

        {/* Excel bulk-create upload — parses a filled-in .xlsx/.zip
            (src/lib/excelEventImport.js) and only fills the form above,
            never creates or submits an event by itself. TASK 3 (event
            creation validation pass) — the "Download the Excel template"
            link that used to sit above this is removed per this ticket's
            own instruction; the upload/parse path itself is untouched and
            still fully functional for anyone with their own filled-in copy
            of the template (still generated by scripts/generate-template.js
            for the iOS-bundled copy, which is unaffected). */}
        <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <input
            ref={importInputRef} type="file" accept=".xlsx,.zip" style={{ display: 'none' }} onChange={onImportFile}
          />
          <span
            onClick={() => !importBusy && importInputRef.current?.click()}
            data-testid="create-event-import"
            style={{ fontSize: 12.5, color: ink, textDecoration: 'underline', cursor: importBusy ? 'default' : 'pointer', opacity: importBusy ? 0.6 : 1 }}
          >
            {importBusy ? T('Đang đọc file…', 'Reading file…') : T('Tải lên file đã điền (xem trước trước khi gửi)', 'Upload a completed file (preview before submitting)')}
          </span>
          {importError && (
            <div data-testid="create-event-import-error" style={{ fontSize: 12, lineHeight: 1.5, color: alert }}>
              <p style={{ margin: 0 }}>{importError}</p>
              {Object.keys(importFieldErrors).length > 0 && (
                <ul style={{ margin: '6px 0 0', paddingLeft: 18 }}>
                  {Object.entries(importFieldErrors).map(([key, msg]) => (
                    <li key={key}>{IMPORT_FIELD_LABELS[key] ? T(...IMPORT_FIELD_LABELS[key]) : key}: {msg}</li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </div>

        {/* Address-autocomplete fix pass (2026-09-28) — a visible hint
            BEFORE the host attempts to submit, not only after a failed
            attempt (createError below still covers the server-side gate
            as a backstop). */}
        {!s.createLocConfirmed && (
          <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '0 0 10px', textAlign: 'center' }}>
            {T('Chọn một địa chỉ gợi ý ở trên trước khi đăng.', 'Pick a suggested address above before publishing.')}
          </p>
        )}
        {/* No SLA is actually monitored server-side — the previous "duyệt
            trong 48 giờ"/"reviews within 48h" copy promised a turnaround
            time nothing enforced. Accurate instead of reassuring. */}
        {/* "Review before submitting" step (task 1) — this button now only
            OPENS the review step below; only that step's own "Xác nhận và
            gửi" ever actually submits. Still gated on the same
            createName/createSent checks the old direct-submit button used.
            TASK 3 (event creation validation pass) — also blocked while any
            required field above is missing; a first click on an invalid
            form flips `attemptedReview` (surfacing every field-level error
            above) instead of opening Review at all. */}
        <div
          onClick={s.createSent ? undefined : () => {
            if (!s.createName.trim() || hasFieldErrors) { setAttemptedReview(true); return; }
            setReviewOpen(true);
          }}
          data-testid="create-open-review"
          style={createBtnStyle}
        >
          {s.createSent
            ? T('Đã gửi, đang chờ Banbe duyệt', 'Submitted, waiting for Banbe to review')
            : T('Xem lại trước khi gửi', 'Review before submitting')}
        </div>
        {s.createError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createError}</p>}
        {s.createMediaError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createMediaError}</p>}
        <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: '12px auto 0', textAlign: 'center', maxWidth: '23ch' }}>{T('Hoàn toàn miễn phí: không phí đăng, không phí giao dịch, không phí ẩn.', 'Completely free: no listing fee, no transaction fee, no hidden fees.')}</p>
      </div>
      {reviewOpen && (
        <ReviewStep
          T={T}
          trStatus={trStatus}
          stripKm={stripKm}
          s={s}
          items={items}
          coverKey={coverKey}
          createCatLabel={createCatLabel}
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
            if (!s.createName.trim() || hasFieldErrors) { setReviewOpen(false); setAttemptedReview(true); return; }
            const ok = await createSubmit(newFilesInOrder, coverIndex, { removePhotoIds: removedExistingIds, existingCoverPath, defaultKeywordsLabel: createCatLabel });
            if (ok) { setReviewOpen(false); setSuccessChooserOpen(true); }
          }}
        />
      )}
      {successChooserOpen && (
        <SubmitSuccessChooser
          T={T}
          onCreateAnother={() => {
            setSuccessChooserOpen(false);
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
function ReviewStep({ T, trStatus, stripKm, s, items, coverKey, createCatLabel, onBack, onConfirm }) {
  const [confirmBusy, setConfirmBusy] = useState(false);
  const [tab, setTab] = useState('private');
  const dateLabel = [s.createEventDate, s.createEventTime].filter(Boolean).join(' ▪︎ ') || T('Chưa chọn', 'Not set');
  const priceLabel = s.createPrice.trim() || T('Miễn phí', 'Free');
  const seatsLabel = s.createSeats.trim() || T('Chưa nhập', 'Not set');
  const addressLabel = s.createLocLabel || [s.createAddressLine, s.createDistrict, s.createCity].filter(Boolean).join(', ') || T('Chưa xác nhận địa chỉ', 'Address not confirmed');
  const includedItems = (s.createIncludedItems || []).filter(it => (it.label || '').trim());

  // Same parsing createSubmit itself uses (BanBeContext.jsx) — the public
  // preview's price must match exactly what gets persisted and later
  // rendered on the real Event Detail page, not a re-guess of the raw
  // free-text field.
  const priceVndDraft = parseInt((s.createPrice.match(/[\d.]+/) || ['0'])[0].replace(/\./g, ''), 10) || 0;
  const publicPriceLabel = priceVndDraft > 0 ? formatVnd(priceVndDraft) : T('Miễn phí', 'Free');
  const draftDateObj = (s.createEventDate && s.createEventTime) ? new Date(`${s.createEventDate}T${s.createEventTime}`) : null;
  const { dayLong, time: draftTimeLabel } = draftDateObj && !Number.isNaN(draftDateObj.getTime()) ? formatVnEventDate(draftDateObj) : {};
  // Same shape shapeRealEventAsCurEvent builds for a real event's `where`
  // (district ▪︎ live-km placeholder ▪︎ long date ▪︎ time) — stripKm below
  // replaces the placeholder with a real computed distance once location
  // is available, or strips it entirely, same contract as everywhere else.
  const publicWhereRaw = [s.createDistrict || '', draftDateObj ? '0,0 km từ bạn' : null, dayLong, draftTimeLabel].filter(Boolean).join(' ▪︎ ');
  const publicWhere = trStatus(stripKm(publicWhereRaw, { lat: s.createLat, lng: s.createLng }));
  const publicMapsUrl = (s.createLat != null && s.createLng != null) ? mapsUrl({ lat: s.createLat, lng: s.createLng }) : null;
  const publicSeatsLabel = s.createSeats.trim() ? T(`Còn ${s.createSeats.trim()} chỗ`, `${s.createSeats.trim()} seats left`) : '';
  const coverItem = items.find(p => p.url === coverKey) || items[0];
  const galleryRest = items.filter(p => p !== coverItem);

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
      <div style={{ padding: '14px 22px 0', flex: 'none' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Xem lại trước khi gửi', 'Review before submitting')}</span>
        <div style={{ display: 'flex', gap: 6, marginTop: 14, padding: 3, background: 'rgba(27,25,22,0.06)', borderRadius: 999 }}>
          {tabBtn('private', T('Nội bộ (Host)', 'Private (Host)'))}
          {tabBtn('public', T('Xem trước công khai', 'Public preview'))}
        </div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '14px 22px 24px' }}>
        {tab === 'private' ? (
          <>
            <h1 style={{ ...display(24, { margin: '4px 0 0' }) }}>{s.createName.trim() || T('(Chưa đặt tên)', '(Untitled)')}</h1>

            <div style={{ ...cardGlass({ marginTop: 18, padding: '4px 16px', display: 'flex', flexDirection: 'column' }) }}>
              {row(T('Danh mục', 'Category'), createCatLabel)}
              {row(T('Từ khoá tìm kiếm', 'Search keywords'), s.createKeywords.trim() || T(`(Tự dùng danh mục) ${createCatLabel}`, `(Defaults to category) ${createCatLabel}`))}
              {row(T('Ngày & giờ', 'Date & time'), dateLabel)}
              {row(T('Địa chỉ', 'Address'), addressLabel)}
              {row(T('Số chỗ', 'Capacity'), seatsLabel)}
              {row(T('Giá vé', 'Price'), priceLabel)}
              {row(T('Quyền riêng tư', 'Privacy'), s.createVisibility === 'invite' ? T('Chỉ mời', 'Invite-only') : T('Công khai', 'Public'))}
              {s.createDesc.trim() && row(T('Mô tả', 'Description'), s.createDesc.trim())}
              {s.createIntro.trim() && row(T('Giới thiệu sự kiện', 'Event introduction'), s.createIntro.trim())}
            </div>

            {includedItems.length > 0 && (
              <div style={{ marginTop: 22 }}>
                <span style={{ fontSize: 11.5, color: ink }}>{T('Bao gồm', 'Included')}</span>
                <div style={{ ...cardGlass({ marginTop: 10, padding: '4px 16px', display: 'flex', flexDirection: 'column' }) }}>
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
              <div style={{ marginTop: 22 }}>
                <span style={{ fontSize: 11.5, color: ink }}>{T('Thứ tự ảnh', 'Photo order')}</span>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 10 }}>
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
        ) : (
          <>
            {coverItem && (
              <div style={{ position: 'relative', width: '100%', aspectRatio: '1 / 1', borderRadius: 16, overflow: 'hidden', marginTop: 4 }}>
                <div style={bg(coverItem.url, { width: '100%', height: '100%' })} />
              </div>
            )}
            <span style={{ fontSize: 12, color: ink, opacity: 0.7, marginTop: 14, display: 'block' }}>{createCatLabel}</span>
            <h1 style={{ ...display(26, { margin: '4px 0 0' }) }}>{s.createName.trim() || T('(Chưa đặt tên)', '(Untitled)')}</h1>
            {publicMapsUrl ? (
              <a href={publicMapsUrl} target="_blank" rel="noreferrer" style={{ fontSize: 13, color: ink, textDecoration: 'underline', marginTop: 6, display: 'block' }}>
                {publicWhere} ↗
              </a>
            ) : (
              <div style={{ fontSize: 13, color: ink, marginTop: 6 }}>{publicWhere || T('Chưa xác nhận địa chỉ', 'Address not confirmed')}</div>
            )}
            {publicSeatsLabel && <div style={{ fontSize: 13, color: ink, marginTop: 4 }}>{publicSeatsLabel}</div>}

            {s.createIntro.trim() && (
              <p style={{ fontSize: 13.5, lineHeight: 1.6, color: ink, marginTop: 18, whiteSpace: 'pre-wrap' }}>{s.createIntro.trim()}</p>
            )}

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 22, paddingTop: 14, borderTop: `1px solid ${rule}` }}>
              <span style={{ fontSize: 13, color: ink }}>{T('Giá vé', 'Price')}</span>
              <span style={{ ...display(19) }}>{publicPriceLabel}</span>
            </div>

            {includedItems.length > 0 && (
              <div style={{ marginTop: 18 }}>
                <span style={{ fontSize: 11.5, color: ink }}>{T('Bao gồm', 'Included')}</span>
                <div style={{ ...cardGlass({ marginTop: 10, padding: '4px 16px', display: 'flex', flexDirection: 'column' }) }}>
                  {includedItems.map((it, i) => (
                    <div key={i} style={{ padding: '10px 0', borderBottom: i < includedItems.length - 1 ? `1px solid ${rule}` : 'none' }}>
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{it.label.trim()}</span>
                      {it.detail?.trim() && <p style={{ fontSize: 12.5, color: ink, margin: '2px 0 0' }}>{it.detail.trim()}</p>}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {s.createDesc.trim() && (
              <p style={{ fontSize: 13, lineHeight: 1.6, color: ink, marginTop: 18, whiteSpace: 'pre-wrap' }}>{s.createDesc.trim()}</p>
            )}

            {galleryRest.length > 0 && (
              <div style={{ marginTop: 18 }}>
                <span style={{ fontSize: 11.5, color: ink }}>{T('Ảnh', 'Photos')}</span>
                <div style={{ display: 'flex', gap: 8, marginTop: 10, overflowX: 'auto' }}>
                  {galleryRest.map(p => (
                    <div key={p.url} style={{ position: 'relative', flex: 'none', width: 96, height: 96, borderRadius: 12, overflow: 'hidden' }}>
                      <div style={bg(p.url, { width: '100%', height: '100%' })} />
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Confirm — the ONLY call site that actually submits, available from
          either tab. A local `confirmBusy` disables the button for the
          duration of this ONE click (on top of BanBeContext's own synchronous
          createSubmitInFlightRef guard), matching this screen's own
          "createSent" style-dimming convention rather than inventing a
          new one. */}
      <div style={{ flex: 'none', padding: '10px 22px 40px' }}>
        <div
          onClick={confirmBusy || s.createSent ? undefined : async () => { setConfirmBusy(true); await onConfirm(); setConfirmBusy(false); }}
          data-testid="create-review-confirm"
          style={{
            fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 16, borderRadius: 999,
            background: confirmBusy || s.createSent ? 'rgba(27,25,22,0.16)' : ink,
            color: confirmBusy || s.createSent ? ink : paper,
            cursor: confirmBusy || s.createSent ? 'default' : 'pointer',
          }}
        >
          {s.createSent
            ? T('Đã gửi, đang chờ Banbe duyệt', 'Submitted, waiting for Banbe to review')
            : T('Xác nhận và gửi', 'Confirm & submit')}
        </div>
        {s.createError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createError}</p>}
      </div>
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
  const rowBtnStyle = {
    fontSize: 14, fontWeight: 600, textAlign: 'left', padding: '13px 14px', borderRadius: 12,
    background: 'transparent', border: `1px solid ${rule}`, color: ink, cursor: 'pointer', width: '100%',
  };
  return (
    <dialog
      ref={dialogRef}
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
      style={{ border: 'none', borderRadius: 18, padding: 0, maxWidth: 320, width: '88%', background: paper, color: ink }}
    >
      <div style={{ padding: 22 }}>
        <p style={{ ...display(18, { margin: '0 0 4px' }) }}>{T('Đã gửi sự kiện!', 'Event submitted!')}</p>
        <p style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '0 0 18px' }}>
          {T('Đang chờ Banbe duyệt. Bạn muốn làm gì tiếp theo?', 'Waiting for Banbe to review. What would you like to do next?')}
        </p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <button onClick={onCreateAnother} data-testid="submit-chooser-create-another" style={rowBtnStyle}>{T('Tạo sự kiện khác', 'Create another event')}</button>
          <button onClick={onViewPending} data-testid="submit-chooser-pending" style={rowBtnStyle}>{T('Xem sự kiện đang chờ duyệt', 'View pending events')}</button>
          <button onClick={onGoHome} data-testid="submit-chooser-home" style={rowBtnStyle}>{T('Về Trang chủ', 'Go to Home')}</button>
          <button onClick={onGoAccount} data-testid="submit-chooser-account" style={rowBtnStyle}>{T('Về Tài khoản', 'Go to Account')}</button>
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
