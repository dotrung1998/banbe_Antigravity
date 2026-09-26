import { useEffect, useMemo, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, CREATE_PALETTES, bg } from '../data/events.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { supabase } from '../lib/supabase.js';
import { parseExcelOrZipPackage } from '../lib/excelEventImport.js';
import { paper, ink, rule, FACE, display, fieldGlass, cardGlass, alert } from '../theme.js';

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
    createNameType, createDescType, createIntroType, createLocType, createEventDateType, createEventTimeType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette,
    addCreateIncludedItem, removeCreateIncludedItem, setCreateIncludedItem, importParsedEvent,
    createSubmit, goEvent, loadHomeLiveEvents,
  } = useGoc();
  const s = state;

  // Unified gallery staging — a single ordered list mixing the event's
  // ALREADY-UPLOADED photos (when editing an owned event, `kind: 'existing'`,
  // seeded below from `s.eventPhotos`) and newly-picked local files
  // (`kind: 'new'`), so remove/reorder/cover-pick works the same way on
  // both. Never round-tripped through the global store itself (see
  // GocContext.jsx's own comment on `createIncludedItems`) — only the
  // final File[]/removed-id list/cover reference are handed to createSubmit
  // on actual submit.
  const [items, setItems] = useState([]); // { kind, id?, file?, url, storagePath? }[]
  const [coverKey, setCoverKey] = useState(null); // items[i]'s own url, used as a stable key
  const [photoError, setPhotoError] = useState('');
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
    const seeded = (s.eventPhotos || []).map(p => ({
      kind: 'existing', id: p.id, storagePath: p.storage_path,
      url: supabase.storage.from('event-photos').getPublicUrl(p.storage_path.replace(/^event-photos\//, '')).data.publicUrl,
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
  // 2026-09-25 fix pass (Task 0 audit) — this screen can be reached
  // directly (not only via Home, which is the only other place that calls
  // this), so `s.homeLiveEvents` can't be assumed already populated; same
  // own-fetch Dashboard.jsx already does.
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);

  const createBackLabel = s.hasHosted ? T('Trang tổ chức của bạn', 'Your host page') : T('Trang tổ chức của bạn sẽ trông thế nào', 'Preview your organizer page');

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
    marginTop: 26, fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 16, borderRadius: 999,
    background: s.createSent ? 'rgba(27,25,22,0.16)' : (s.createName.trim() ? ink : 'rgba(27,25,22,0.16)'),
    color: s.createSent ? ink : (s.createName.trim() ? paper : ink),
    cursor: s.createName.trim() && !s.createSent ? 'pointer' : 'default', transition: 'background .15s',
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Create event">
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

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện sắp tới', 'Upcoming events')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{upcoming.length}{T(' sự kiện', upcoming.length === 1 ? ' event' : ' events')}</span>
          </div>
          <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, margin: '6px 0 0' }}>{orgTrustNote}</p>
          <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
            {upcoming.map((e, i, arr) => (
              <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                <div style={bg(e.img, { flex: 'none', width: 52, height: 52 })} />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
                  <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                  <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))}</span>
                </div>
                <span style={{ fontSize: 11.5, color: ink, flex: 'none' }}>{trStatus(e.soldOut ? 'Hết chỗ' : e.seats)}</span>
              </div>
            ))}
            {upcoming.length === 0 && (
              <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{T('Bạn chưa có sự kiện nào sắp tới. Tạo bên dưới.', 'No upcoming events yet. Create one below.')}</p>
            )}
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 22 }}>
          <label style={labelStyle}>{T('Tên sự kiện', 'Event name')}</label>
          <input value={s.createName} onChange={createNameType} placeholder="Bếp Nhỏ №13" style={fieldInput} />
        </div>

        <div style={{ marginTop: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Danh mục', 'Category')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Tối đa 2 danh mục', 'Max 2 categories')}</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
            {CAT_DEFS.map(c => {
              const on = s.createCats.includes(c.key);
              const isSecond = on && s.createCats[1] === c.key;
              return (
                <span key={c.key} onClick={() => pickCreateCat(c.key)} style={{ fontSize: 12.5, padding: '8px 15px', borderRadius: 999, cursor: 'pointer', border: on ? `1.5px solid ${ink}` : '1px solid rgba(27,25,22,0.16)', background: on ? paper : 'transparent', color: ink, fontWeight: on ? 600 : 400 }}>
                  {T(c.vi, c.en)}{isSecond ? ' ▪︎ +' : ''}
                </span>
              );
            })}
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 20 }}>
          <label style={labelStyle}>{T('Mô tả', 'Description')}</label>
          <input value={s.createDesc} onChange={createDescType} placeholder={T('Mười bốn chỗ. Một ga-ra cải tạo…', 'Fourteen seats. A converted garage…')} style={fieldInput} />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <label style={labelStyle}>{T('Giới thiệu sự kiện', 'Event introduction')}</label>
            <span style={{ fontSize: 10.5, color: ink }}>{s.createIntro.length}/4000</span>
          </div>
          <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: 0, opacity: 0.75 }}>
            {T('Một đoạn giới thiệu dài hơn, hấp dẫn — tách dòng trống giữa các đoạn. Không phải quảng cáo giả, không phải "Bao gồm".', 'A longer, attractive write-up — leave a blank line between paragraphs. Not fabricated marketing copy, not the same as "Included".')}
          </p>
          <textarea
            value={s.createIntro} onChange={createIntroType} maxLength={4000} rows={6}
            placeholder={T('Một buổi tối ấm cúng cho mười bốn người lạ…\n\nMón chính là…', 'A cozy evening for fourteen strangers…\n\nThe main course is…')}
            style={{ ...fieldInput, resize: 'vertical', lineHeight: 1.5, fontFamily: FACE }}
          />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 14 }}>
          <label style={labelStyle}>{T('Địa điểm', 'Location')}</label>
          <input value={s.createLoc} onChange={createLocType} placeholder="Bình Thạnh" style={fieldInput} />
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Ngày', 'Date')}</label>
            <input
              type="date" value={s.createEventDate} onChange={createEventDateType}
              min={new Date().toISOString().slice(0, 10)}
              data-testid="create-event-date" style={fieldInput}
            />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Giờ', 'Time')}</label>
            <input
              type="time" value={s.createEventTime} onChange={createEventTimeType}
              data-testid="create-event-time" style={fieldInput}
            />
          </div>
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Giá vé', 'Ticket price')}</label>
            <input value={s.createPrice} onChange={createPriceType} placeholder="500.000₫" style={fieldInput} />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Số chỗ', 'Seats')}</label>
            <input value={s.createSeats} onChange={createSeatsType} placeholder="14" style={fieldInput} />
          </div>
        </div>

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Hình ảnh', 'Photos')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{photos.length}/{MAX_PHOTOS}</span>
          </div>
          <input
            ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" multiple
            style={{ display: 'none' }} onChange={onPickPhotos}
          />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 6, marginTop: 10 }}>
            {photos.map((p, i) => (
              <div key={p.url} style={{ position: 'relative', aspectRatio: '1', borderRadius: 12, overflow: 'hidden' }}>
                <div style={bg(p.url, { width: '100%', height: '100%' })} />
                <span
                  onClick={() => removePhoto(i)}
                  style={{ position: 'absolute', top: 4, right: 4, width: 20, height: 20, borderRadius: 999, background: 'rgba(12,12,12,0.55)', color: '#fff', fontSize: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                >×</span>
                {i > 0 && (
                  <span
                    onClick={() => setItems(prev => { const next = [...prev]; [next[i - 1], next[i]] = [next[i], next[i - 1]]; return next; })}
                    style={{ position: 'absolute', top: 4, left: 4, width: 20, height: 20, borderRadius: 999, background: 'rgba(12,12,12,0.55)', color: '#fff', fontSize: 11, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                  >‹</span>
                )}
                <span
                  onClick={() => setCoverKey(p.url)}
                  style={{
                    position: 'absolute', bottom: 4, left: 4, right: 4, fontSize: 9, fontWeight: 600, textAlign: 'center',
                    padding: '3px 4px', borderRadius: 8, cursor: 'pointer',
                    background: p.url === coverKey ? ink : 'rgba(247,244,236,0.85)', color: p.url === coverKey ? paper : ink,
                  }}
                >{p.url === coverKey ? T('Ảnh bìa', 'Cover') : T('Đặt làm ảnh bìa', 'Set as cover')}</span>
              </div>
            ))}
            {photos.length < MAX_PHOTOS && (
              <div
                onClick={() => fileInputRef.current?.click()}
                style={{ aspectRatio: '1', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', borderRadius: 12, background: paper, border: `1px dashed ${ink}` }}
              >
                <span style={{ fontSize: 18, color: ink }}>+</span>
              </div>
            )}
          </div>
          {photoError && <p style={{ fontSize: 11.5, color: alert, margin: '8px 0 0' }}>{photoError}</p>}
        </div>

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Bao gồm', 'Included')}</span>
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
                    style={{ ...fieldGlass({ padding: '9px 11px' }), flex: 1, fontSize: 13, fontFamily: FACE, color: ink, outline: 'none', border: 'none', minWidth: 0 }}
                  />
                  <span onClick={() => removeCreateIncludedItem(i)} style={{ fontSize: 12, color: ink, opacity: 0.6, cursor: 'pointer', flex: 'none' }}>{T('Xoá', 'Remove')}</span>
                </div>
                <input
                  value={it.detail} maxLength={300}
                  onChange={(e) => setCreateIncludedItem(i, 'detail', e.target.value)}
                  placeholder={T('Giải thích rõ hơn (không bắt buộc)', 'Fuller explanation (optional)')}
                  style={{ ...fieldGlass({ padding: '9px 11px' }), fontSize: 12.5, fontFamily: FACE, color: ink, outline: 'none', border: 'none' }}
                />
              </div>
            ))}
            {s.createIncludedItems.length < 3 && (
              <span onClick={addCreateIncludedItem} style={{ fontSize: 12.5, color: ink, fontWeight: 600, cursor: 'pointer' }}>+ {T('Thêm mục', 'Add item')}</span>
            )}
          </div>
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

        {/* Excel bulk-create — real .xlsx template (public/templates/), not
            a renamed CSV, generated by scripts/generate-template.js (the
            SAME generator that produces the iOS-bundled copy). Upload
            parses it (src/lib/excelEventImport.js) and only fills the form
            above — never creates or submits an event by itself. */}
        <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <a
            href="/templates/banbe_event_template.xlsx" download
            style={{ fontSize: 12.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
          >{T('Tải mẫu Excel để tạo hàng loạt', 'Download the Excel template for bulk creation')}</a>
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

        {/* No SLA is actually monitored server-side — the previous "duyệt
            trong 48 giờ"/"reviews within 48h" copy promised a turnaround
            time nothing enforced. Accurate instead of reassuring. */}
        <div onClick={() => createSubmit(newFilesInOrder, coverIndex, { removePhotoIds: removedExistingIds, existingCoverPath })} style={createBtnStyle}>
          {s.createSent
            ? T('Đã gửi, đang chờ Banbe duyệt', 'Submitted, waiting for Banbe to review')
            : (s.createEditEventId ? T('Gửi lại để duyệt', 'Resubmit for review') : T('Gửi để duyệt', 'Submit for review'))}
        </div>
        {s.createError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createError}</p>}
        {s.createMediaError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0', textAlign: 'center' }}>{s.createMediaError}</p>}
        <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: '12px auto 0', textAlign: 'center', maxWidth: '23ch' }}>{T('Hoàn toàn miễn phí: không phí đăng, không phí giao dịch, không phí ẩn.', 'Completely free: no listing fee, no transaction fee, no hidden fees.')}</p>
      </div>
    </div>
  );
}

function Field({ label, value, onChange, placeholder, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5, minWidth: 0, width: '100%', boxSizing: 'border-box', ...style }}>
      <label style={labelStyle}>{label}</label>
      <input value={value} onChange={onChange} placeholder={placeholder} style={{ ...fieldGlass({ padding: '11px 12px' }), fontSize: 13.5, fontFamily: FACE, color: ink, outline: 'none', minWidth: 0, width: '100%', boxSizing: 'border-box', border: 'none' }} />
    </div>
  );
}

const labelStyle = { fontSize: 11.5, color: ink };
const fieldInput = { ...fieldGlass({ padding: '13px 14px' }), fontSize: 14, fontFamily: FACE, color: ink, outline: 'none', minWidth: 0, width: '100%', boxSizing: 'border-box', border: 'none' };
