import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, rule, display, alert } from '../theme.js';
import { surveyPublicUrl } from '../lib/surveyLink.js';
import { supabase } from '../lib/supabase.js';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import SurveyStoryCard from './sheets/SurveyStoryCard.jsx';

function organizerAvatarUrl(path, r2Ref, variant = 'thumb') {
  return organizerAvatarPublicUrl(path, r2Ref, variant);
}

// One short word per tab so all four fit a single full-width segmented
// control on a phone (no wrapping, no dead space on the right).
const TABS = [
  { key: 'active', vi: 'Đang mở', en: 'Active' },
  { key: 'closed', vi: 'Đã đóng', en: 'Closed' },
  { key: 'drafts', vi: 'Gợi ý', en: 'Ideas' },
  { key: 'archived', vi: 'Lưu trữ', en: 'Archived' },
];

/** Equal-width action button — rows of these always fill the card edge to
 * edge instead of leaving ragged underlined links. */
function Pill({ children, onClick, kind = 'outline', testId, disabled }) {
  const filled = kind === 'filled';
  const danger = kind === 'danger';
  return (
    <div
      onClick={disabled ? undefined : onClick}
      data-testid={testId}
      style={{
        flex: 1, minWidth: 0, textAlign: 'center', padding: '9px 8px', borderRadius: 10,
        fontSize: 12.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.4 : 1,
        border: `1px solid ${danger ? alert : filled ? ink : rule}`,
        background: filled ? ink : 'transparent',
        color: filled ? paper : danger ? alert : ink,
      }}
    >{children}</div>
  );
}
/** Segmented tabs with a draggable liquid-glass droplet: translucent blur,
 * specular rim, and a squash-and-stretch while the pointer is down (wider
 * and flatter, like a drop being pushed), springing into place on release.
 * Tap works too; the tab switches live as the droplet passes each segment.
 * touch-action: pan-y keeps vertical page scroll native. */
function GlassTabs({ tabs, value, onChange }) {
  const ref = useRef(null);
  const [fingerX, setFingerX] = useState(null);
  const idx = Math.max(0, tabs.findIndex(x => x.key === value));
  const inset = 3;
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const measure = () => { if (ref.current) setWidth(ref.current.clientWidth); };
    measure();
    window.addEventListener('resize', measure);
    return () => window.removeEventListener('resize', measure);
  }, []);
  const segW = width ? (width - inset * 2) / tabs.length : 0;
  const dragging = fingerX != null;
  const left = dragging && segW
    ? Math.min(Math.max(fingerX - segW / 2, inset), width - inset - segW)
    : inset + segW * idx;
  const pick = (clientX) => {
    const r = ref.current.getBoundingClientRect();
    const x = clientX - r.left;
    setFingerX(x);
    const i = Math.min(Math.max(Math.floor((x - inset) / ((r.width - inset * 2) / tabs.length)), 0), tabs.length - 1);
    if (tabs[i].key !== value) onChange(tabs[i].key);
  };
  return (
    <div
      ref={ref}
      onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); pick(e.clientX); }}
      onPointerMove={(e) => { if (dragging) pick(e.clientX); }}
      onPointerUp={() => setFingerX(null)}
      onPointerCancel={() => setFingerX(null)}
      data-testid="survey-tabs"
      style={{ position: 'relative', display: 'flex', height: 44, marginBottom: 18, borderRadius: 16, border: `1px solid ${rule}`, background: 'rgba(127,127,127,0.07)', touchAction: 'pan-y', userSelect: 'none', cursor: 'pointer' }}
    >
      {segW > 0 && (
        <div
          style={{
            position: 'absolute', top: inset, left, width: segW, height: 44 - inset * 2 - 2, borderRadius: 13, pointerEvents: 'none',
            background: 'linear-gradient(180deg, rgba(255,255,255,0.75), rgba(255,255,255,0.28))',
            backdropFilter: 'blur(10px) saturate(1.6)', WebkitBackdropFilter: 'blur(10px) saturate(1.6)',
            border: '1px solid rgba(255,255,255,0.85)',
            boxShadow: dragging ? '0 6px 16px rgba(0,0,0,0.22), inset 0 1px 0 rgba(255,255,255,0.9)' : '0 2px 6px rgba(0,0,0,0.12), inset 0 1px 0 rgba(255,255,255,0.9)',
            transform: dragging ? 'scale(1.16, 0.9)' : 'scale(1, 1)',
            transition: dragging
              ? 'left .12s ease-out, transform .25s cubic-bezier(.34,1.56,.64,1), box-shadow .2s'
              : 'left .42s cubic-bezier(.34,1.56,.64,1), transform .3s cubic-bezier(.34,1.56,.64,1), box-shadow .2s',
          }}
        />
      )}
      {tabs.map(x => {
        const on = x.key === value;
        return (
          <div key={x.key} style={{ position: 'relative', flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, fontSize: 12.5, fontWeight: on ? 600 : 500, color: ink, opacity: on ? 1 : 0.55, whiteSpace: 'nowrap', pointerEvents: 'none' }}>
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{x.label}</span>
            {x.badge > 0 && <span style={{ fontSize: 10.5, fontWeight: 700, minWidth: 16, height: 16, lineHeight: '16px', borderRadius: 8, padding: '0 4px', background: ink, color: paper }}>{x.badge}</span>}
          </div>
        );
      })}
    </div>
  );
}

function PillRow({ children, small }) {
  return <div style={{ display: 'flex', gap: 8, marginTop: small ? 0 : 12, marginBottom: small ? 12 : 0, animation: small ? 'sgFade .26s cubic-bezier(.3,.9,.3,1)' : undefined }}>{children}</div>;
}

function parseOptionsInput(text) {
  return (text || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
    .map((label, i) => ({ id: `o${i + 1}`, label }));
}

function slotLabel(sl) {
  const [y, m, d] = sl.date.split('-');
  // ▪︎ is the app's own separator (same one event dates/places use).
  return `${d}/${m}/${y} ▪︎ ${sl.time}`;
}

function CreateSurveyForm({ T, onCreate, busy, error, searchAddressSuggestions }) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [closesInDays, setClosesInDays] = useState('7');
  // Structured slots (same native date/time inputs as Create Event), so a
  // suggested draft's date/time can be applied to the event verbatim.
  const [slots, setSlots] = useState([]);
  const [slotDate, setSlotDate] = useState('');
  const [slotTime, setSlotTime] = useState('');
  // Locations are picked with the same address search Create Event uses
  // (structured address + coordinates), not typed as free text.
  const [locations, setLocations] = useState([]);
  const [locQuery, setLocQuery] = useState('');
  const [locSuggestions, setLocSuggestions] = useState([]);
  const [locSearching, setLocSearching] = useState(false);
  const [locError, setLocError] = useState('');
  const locTimer = useRef(null);
  const locSeq = useRef(0);
  const onLocType = (value) => {
    setLocQuery(value);
    setLocSuggestions([]); setLocError('');
    if (locTimer.current) clearTimeout(locTimer.current);
    const q = value.trim();
    locSeq.current += 1;
    if (q.length < 4) { setLocSearching(false); return; }
    const seq = locSeq.current;
    setLocSearching(true);
    locTimer.current = setTimeout(async () => {
      const { suggestions, error: err } = await searchAddressSuggestions(q);
      if (seq !== locSeq.current) return;
      setLocSearching(false); setLocSuggestions(suggestions); setLocError(err);
    }, 500);
  };
  const addLocation = (sg) => {
    const label = [sg.addressLine, sg.district, sg.city].filter(Boolean).join(', ') || sg.label;
    if (locations.some(l => l.label === label)) return;
    setLocations([...locations, {
      label, address_line: sg.addressLine, district: sg.district, city: sg.city, postal_code: sg.postalCode,
      country_code: sg.countryCode || '', state_province: sg.stateProvince || '', neighborhood: sg.neighborhood || '',
      lat: sg.lat, lng: sg.lng,
    }]);
    locSeq.current += 1; setLocQuery(''); setLocSuggestions([]); setLocError(''); setLocSearching(false);
  };
  const [budgetOptions, setBudgetOptions] = useState('Dưới 300k, 300-600k, Trên 600k');
  const [activityOptions, setActivityOptions] = useState('');
  const [groupSizeMax, setGroupSizeMax] = useState('20');

  const submit = () => {
    const opensAt = new Date().toISOString();
    const days = Math.max(1, parseInt(closesInDays, 10) || 7);
    const closesAt = new Date(Date.now() + days * 86400000).toISOString();
    onCreate({
      title, description, opensAt, closesAt,
      config: {
        date_options: slots.map((sl, i) => ({ id: `o${i + 1}`, label: slotLabel(sl), date: sl.date, time: sl.time })),
        location_options: locations.map((l, i) => ({ id: `o${i + 1}`, ...l })),
        budget_options: parseOptionsInput(budgetOptions),
        activity_options: parseOptionsInput(activityOptions),
        group_size_min: 1,
        group_size_max: Math.max(1, parseInt(groupSizeMax, 10) || 20),
        required: { date_options: slots.length > 0, location_options: locations.length > 0 },
      },
    });
  };

  const inputStyle = { width: '100%', padding: '10px 12px', borderRadius: 8, border: `1px solid ${rule}`, fontSize: 13.5, boxSizing: 'border-box' };
  const labelStyle = { fontSize: 11.5, color: ink, opacity: 0.7, display: 'block', marginBottom: 5 };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, padding: 18, border: `1px solid ${rule}`, borderRadius: 12 }}>
      <div>
        <label style={labelStyle}>{T('Tiêu đề', 'Title')}</label>
        <input style={inputStyle} value={title} onChange={(e) => setTitle(e.target.value)} placeholder={T('Ý tưởng sự kiện cuối tuần', 'Weekend event idea')} />
      </div>
      <div>
        <label style={labelStyle}>{T('Mô tả', 'Description')}</label>
        <textarea style={{ ...inputStyle, resize: 'vertical' }} rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Đóng sau (ngày)', 'Closes in (days)')}</label>
        <input style={{ ...inputStyle, width: 100 }} type="number" min={1} value={closesInDays} onChange={(e) => setClosesInDays(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Lựa chọn ngày/giờ (có thể thêm nhiều)', 'Date/time options (add as many as you like)')}</label>
        <div style={{ display: 'flex', gap: 8 }}>
          <input type="date" style={{ ...inputStyle, flex: 1 }} value={slotDate} min={new Date().toISOString().slice(0, 10)} onChange={(e) => setSlotDate(e.target.value)} data-testid="survey-slot-date" />
          <input type="time" style={{ ...inputStyle, flex: 1 }} value={slotTime} onChange={(e) => setSlotTime(e.target.value)} data-testid="survey-slot-time" />
          <div
            onClick={slotDate && slotTime && !slots.some(sl => sl.date === slotDate && sl.time === slotTime) ? () => { setSlots([...slots, { date: slotDate, time: slotTime }].sort((a, b) => (a.date + a.time).localeCompare(b.date + b.time))); setSlotTime(''); } : undefined}
            data-testid="survey-slot-add"
            style={{ padding: '10px 14px', borderRadius: 8, background: ink, color: paper, fontSize: 13, fontWeight: 600, cursor: 'pointer', opacity: slotDate && slotTime ? 1 : 0.4, whiteSpace: 'nowrap' }}
          >{T('Thêm', 'Add')}</div>
        </div>
        {slots.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 8 }}>
            {slots.map(sl => (
              <span key={sl.date + sl.time} style={{ fontSize: 12, padding: '5px 10px', borderRadius: 999, border: `1px solid ${rule}` }}>
                {slotLabel(sl)} <span onClick={() => setSlots(slots.filter(x => x !== sl))} style={{ cursor: 'pointer', marginLeft: 4 }}>×</span>
              </span>
            ))}
          </div>
        )}
      </div>
      <div>
        <label style={labelStyle}>{T('Địa điểm (tìm địa chỉ, có thể thêm nhiều)', 'Locations (search an address, add as many as you like)')}</label>
        <input style={inputStyle} value={locQuery} onChange={(e) => onLocType(e.target.value)} placeholder={T('Nhập số nhà, đường, quận…', 'House number, street, district…')} data-testid="survey-location-search" />
        {locSearching && <div style={{ fontSize: 11.5, opacity: 0.6, marginTop: 6 }}>{T('Đang tìm…', 'Searching…')}</div>}
        {locError && <div style={{ fontSize: 11.5, color: alert, marginTop: 6 }}>{locError}</div>}
        {locSuggestions.length > 0 && (
          <div style={{ border: `1px solid ${rule}`, borderRadius: 8, marginTop: 6, overflow: 'hidden' }}>
            {locSuggestions.map((sg, i) => (
              <div key={i} onClick={() => addLocation(sg)} style={{ padding: '9px 12px', fontSize: 12.5, cursor: 'pointer', borderTop: i ? `1px solid ${rule}` : 'none' }}>
                <div style={{ fontWeight: 600 }}>{sg.addressLine || sg.label}</div>
                <div style={{ opacity: 0.6, fontSize: 11.5 }}>{[sg.district, sg.city].filter(Boolean).join(', ')}</div>
              </div>
            ))}
          </div>
        )}
        {locations.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 8 }}>
            {locations.map(l => (
              <span key={l.label} style={{ fontSize: 12, padding: '5px 10px', borderRadius: 999, border: `1px solid ${rule}` }}>
                {l.label} <span onClick={() => setLocations(locations.filter(x => x !== l))} style={{ cursor: 'pointer', marginLeft: 4 }}>×</span>
              </span>
            ))}
          </div>
        )}
      </div>
      <div>
        <label style={labelStyle}>{T('Mức ngân sách (cách nhau bởi dấu phẩy)', 'Budget ranges (comma-separated)')}</label>
        <input style={inputStyle} value={budgetOptions} onChange={(e) => setBudgetOptions(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Hoạt động mong muốn (cách nhau bởi dấu phẩy, không bắt buộc)', 'Desired activities (comma-separated, optional)')}</label>
        <input style={inputStyle} value={activityOptions} onChange={(e) => setActivityOptions(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Số người tối đa mỗi nhóm', 'Max group size')}</label>
        <input style={{ ...inputStyle, width: 100 }} type="number" min={1} value={groupSizeMax} onChange={(e) => setGroupSizeMax(e.target.value)} />
      </div>
      {error && <div style={{ fontSize: 12.5, color: alert }}>{error}</div>}
      <div
        onClick={busy || !title.trim() ? undefined : submit}
        style={{ textAlign: 'center', padding: 12, borderRadius: 10, background: ink, color: paper, fontSize: 13.5, fontWeight: 600, cursor: busy || !title.trim() ? 'default' : 'pointer', opacity: busy || !title.trim() ? 0.5 : 1 }}
      >
        {T('Tạo khảo sát (bản nháp)', 'Create survey (draft)')}
      </div>
    </div>
  );
}

/** Hosting -> Surveys & Event Ideas. "Suggested Event Drafts" lists the
 * candidates migration 143 generates server-side when a survey closes
 * (deterministic scoring of date x location over the responses); "Use This
 * Idea" pre-fills Create Event, it never creates anything by itself. */
export default function SurveysHosting() {
  const {
    state, T, goHome, mySurveys, mySurveysLoading, loadMySurveys,
    createSurveyAction, publishSurveyAction, closeSurveyAction, archiveSurveyAction, deleteSurveyAction,
    mySurveyCreateBusy, mySurveyCreateError, goSurveyPublic,
    shareSurveyLinkAction, openShareToStoryConfirm, closeShareToStoryConfirm, confirmShareSurveyToStory,
    mySurveyCandidates, mySurveyCandidatesLoading, mySurveyCandidatesError, mySurveyCandidatesBusySurveyId,
    loadSurveyCandidates, refreshSurveyCandidatesAction, dismissSurveyCandidateAction, restoreSurveyCandidateAction, applySurveyCandidateAction,
    setSurveyCandidatesStatusAction, archiveSurveysAction, unarchiveSurveyAction, deleteArchivedSurveysAction, deleteSurveyCandidatesAction, searchAddressSuggestions,
  } = useBanBe();
  const s = state;
  // Returning from a survey Preview restores the tab it was opened from
  // (e.g. Archived) rather than resetting to Active.
  const [tab, setTab] = useState(() => (TABS.some(x => x.key === state.surveysHostingReturnTab) ? state.surveysHostingReturnTab : 'active'));
  const [showCreate, setShowCreate] = useState(false);
  const [showDismissed, setShowDismissed] = useState(false);
  // Multi-select (Closed tab: archive; Suggested tab: dismiss). One mode
  // flag + one id list, reset whenever the tab changes.
  const [selectMode, setSelectMode] = useState(false);
  const [selected, setSelected] = useState([]);
  useEffect(() => { setSelectMode(false); setSelected([]); }, [tab]);
  const toggleSel = (id) => setSelected(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  const endSelect = () => { setSelectMode(false); setSelected([]); };

  useEffect(() => { loadMySurveys(); }, [loadMySurveys]);
  // Candidates follow the survey list (a close/archive changes which
  // surveys can have any), so the Suggested tab count is right before the
  // tab is opened.
  useEffect(() => { if (!mySurveysLoading) loadSurveyCandidates(); }, [mySurveysLoading, loadSurveyCandidates]);

  // Suggested tab = ideas from CLOSED surveys that are still open for a
  // decision (suggested/dismissed). A used idea moves to Archived on its
  // own; archiving a survey moves the survey there too.
  const closedSurveys = (mySurveys || []).filter(sv => sv.status === 'closed');
  const archivedSurveys = (mySurveys || []).filter(sv => sv.status === 'archived');
  const closedIds = closedSurveys.map(sv => sv.id);
  const decidable = (mySurveyCandidates || []).filter(c => closedIds.includes(c.survey_id) && c.status !== 'used');
  const dismissedCount = decidable.filter(c => c.status === 'dismissed').length;
  const activeCandidateCount = decidable.length - dismissedCount;
  const candidatesBySurvey = closedSurveys
    .map(sv => ({ sv, items: decidable.filter(c => c.survey_id === sv.id && (showDismissed || c.status !== 'dismissed')) }))
    .filter(g => g.items.length > 0);
  const suggestedIds = decidable.filter(c => c.status === 'suggested').map(c => c.id);
  const usedCandidates = (mySurveyCandidates || []).filter(c => c.status === 'used');
  const surveyTitle = (id) => (mySurveys || []).find(sv => sv.id === id)?.title || '';

  const filtered = (mySurveys || []).filter(sv => {
    if (tab === 'active') return sv.status === 'draft' || sv.status === 'active';
    if (tab === 'closed') return sv.status === 'closed';
    return false;
  });

  // Permanent deletes always confirm first.
  const confirmDeleteSurveys = async (ids) => {
    if (!window.confirm(T(
      `Xoá vĩnh viễn ${ids.length} khảo sát cùng toàn bộ câu trả lời và gợi ý của chúng? Không thể hoàn tác.`,
      `Permanently delete ${ids.length} survey${ids.length === 1 ? '' : 's'} with all their responses and ideas? This can't be undone.`,
    ))) return false;
    return deleteArchivedSurveysAction(ids);
  };
  const confirmDeleteIdeas = async (ids) => {
    if (!window.confirm(T(
      `Xoá vĩnh viễn ${ids.length} ý tưởng đã dùng? Không thể hoàn tác.`,
      `Permanently delete ${ids.length} used idea${ids.length === 1 ? '' : 's'}? This can't be undone.`,
    ))) return false;
    return deleteSurveyCandidatesAction(ids);
  };

  const linkStyle = { fontSize: 12, textDecoration: 'underline', cursor: 'pointer' };
  /** Shared "Select / <bulk> all" bar for the Closed and Suggested tabs. */
  const renderSelectBar = ({ ids, allLabel, bulkLabel, onBulk, testId, destructive }) => {
    // Two bars can share one select mode (Archived tab), so each only
    // counts/acts on its own section's ids.
    const mine = selected.filter(id => ids.includes(id));
    return ids.length === 0 ? null : (
      <PillRow small key={selectMode ? 'sel' : 'idle'}>
        <style>{'@keyframes sgFade{from{opacity:0;transform:translateY(-4px) scale(.97)}to{opacity:1;transform:none}}'}</style>
        {!selectMode ? (
          <>
            <Pill onClick={() => setSelectMode(true)} testId={`${testId}-select`}>{T('Chọn', 'Select')}</Pill>
            <Pill kind={destructive ? 'danger' : 'outline'} onClick={() => onBulk(ids)} testId={`${testId}-all`}>{allLabel}</Pill>
          </>
        ) : (
          <>
            <Pill onClick={() => setSelected(prev => mine.length === ids.length ? prev.filter(id => !ids.includes(id)) : [...new Set([...prev, ...ids])])}>
              {mine.length === ids.length ? T('Bỏ chọn hết', 'Deselect all') : T('Chọn tất cả', 'Select all')}
            </Pill>
            <Pill
              kind={destructive ? 'danger' : 'filled'} disabled={!mine.length} testId={`${testId}-selected`}
              onClick={async () => { if (await onBulk(mine)) endSelect(); }}
            >{bulkLabel} ({mine.length})</Pill>
            <Pill onClick={endSelect}>{T('Huỷ', 'Cancel')}</Pill>
          </>
        )}
      </PillRow>
    );
  };
  // Always mounted and collapsed to zero width when not selecting, so
  // entering Select mode slides the checkboxes in (and the card content
  // over) instead of popping them into the layout.
  const checkbox = (id, visible) => (
    <span style={{ width: visible ? 28 : 0, marginRight: 0, overflow: 'hidden', flexShrink: 0, display: 'flex', alignItems: 'flex-start', opacity: visible ? 1 : 0, transition: 'width .3s cubic-bezier(.3,.9,.3,1), opacity .25s ease', pointerEvents: visible ? 'auto' : 'none' }}>
      <span
        onClick={() => toggleSel(id)}
        style={{ width: 18, height: 18, borderRadius: 4, border: `1.5px solid ${ink}`, background: selected.includes(id) ? ink : 'transparent', color: paper, fontSize: 12, lineHeight: '15px', textAlign: 'center', cursor: 'pointer', flexShrink: 0, transition: 'background .15s ease', transform: visible ? 'scale(1)' : 'scale(0.5)' }}
      >{selected.includes(id) ? '✓' : ''}</span>
    </span>
  );

  const onCreate = async (input) => {
    const created = await createSurveyAction(input);
    if (created) setShowCreate(false);
  };

  return (
    <div style={{ minHeight: '100vh', background: paper, color: ink }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: `1px solid ${rule}` }}>
        <span onClick={goHome} style={{ cursor: 'pointer', fontSize: 18 }}>←</span>
        <h1 style={{ ...display(16, { margin: 0 }) }}>{T('Khảo Sát & Ý Tưởng Sự Kiện', 'Surveys & Event Ideas')}</h1>
        <span style={{ width: 18 }} />
      </div>

      <div style={{ maxWidth: 640, margin: '0 auto', padding: '18px 20px 60px' }}>
        <GlassTabs
          tabs={TABS.map(x => ({ key: x.key, label: T(x.vi, x.en), badge: x.key === 'drafts' ? activeCandidateCount : 0 }))}
          value={tab} onChange={setTab}
        />

        {tab === 'active' && (
          <div style={{ marginBottom: 18 }}>
            {!showCreate ? (
              <div onClick={() => setShowCreate(true)} style={{ textAlign: 'center', padding: 12, borderRadius: 10, border: `1px dashed ${rule}`, fontSize: 13, cursor: 'pointer' }}>
                {T('+ Tạo khảo sát mới', '+ Create a new survey')}
              </div>
            ) : (
              <CreateSurveyForm T={T} onCreate={onCreate} busy={mySurveyCreateBusy} error={mySurveyCreateError} searchAddressSuggestions={searchAddressSuggestions} />
            )}
          </div>
        )}

        {tab === 'drafts' && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            {dismissedCount > 0 && (
              <div onClick={() => setShowDismissed(v => !v)} data-testid="survey-candidates-toggle-dismissed" style={{ ...linkStyle, opacity: 0.75, alignSelf: 'flex-start' }}>
                {showDismissed ? T('Ẩn gợi ý đã bỏ qua', 'Hide dismissed') : T(`Hiện gợi ý đã bỏ qua (${dismissedCount})`, `Show dismissed (${dismissedCount})`)}
              </div>
            )}
            {renderSelectBar({
              ids: suggestedIds, testId: 'survey-candidates',
              allLabel: T('Bỏ qua tất cả', 'Dismiss all'), bulkLabel: T('Bỏ qua đã chọn', 'Dismiss selected'),
              onBulk: (ids) => setSurveyCandidatesStatusAction(ids, 'dismissed'),
            })}
            {mySurveyCandidatesError && <div style={{ fontSize: 12.5, color: alert }}>{mySurveyCandidatesError}</div>}
            {(mySurveysLoading || mySurveyCandidatesLoading) && candidatesBySurvey.length === 0 && (
              <div style={{ textAlign: 'center', fontSize: 13, opacity: 0.6, padding: 20 }}>{T('Đang tải…', 'Loading…')}</div>
            )}
            {!mySurveysLoading && !mySurveyCandidatesLoading && candidatesBySurvey.length === 0 && (
              <div style={{ padding: 16, fontSize: 13, opacity: 0.7, textAlign: 'center' }}>
                {closedSurveys.length === 0
                  ? T('Chưa có gợi ý — gợi ý sự kiện được tạo tự động khi một khảo sát đóng và có người trả lời.', 'No suggestions yet — event drafts are generated automatically when a survey closes with responses.')
                  : T('Không còn gợi ý nào cần xử lý. Có thể làm mới bên dưới để tạo lại.', 'No suggestions left to review. You can refresh below to generate them again.')}
              </div>
            )}
            {candidatesBySurvey.map(({ sv, items }) => (
              <div key={sv.id}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
                  <span style={{ fontSize: 13, fontWeight: 600 }}>{sv.title}</span>
                  <span
                    onClick={mySurveyCandidatesBusySurveyId ? undefined : () => refreshSurveyCandidatesAction(sv.id)}
                    style={{ fontSize: 11.5, textDecoration: 'underline', cursor: 'pointer', opacity: mySurveyCandidatesBusySurveyId === sv.id ? 0.4 : 0.7 }}
                  >
                    {mySurveyCandidatesBusySurveyId === sv.id ? T('Đang làm mới…', 'Refreshing…') : T('Làm mới', 'Refresh')}
                  </span>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {items.filter(c => c.status !== 'dismissed').concat(items.filter(c => c.status === 'dismissed')).map((c, i) => (
                    <div key={c.id} data-testid="survey-candidate-card" style={{ border: `1px solid ${rule}`, borderRadius: 12, padding: 14, display: 'flex', alignItems: 'flex-start' }}>
                      {c.status === 'suggested' && checkbox(c.id, selectMode)}
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                          <span style={{ fontSize: 14, fontWeight: 600 }}>
                            {[c.date_label, c.location_label].filter(Boolean).join(' ▪︎ ') || sv.title}
                          </span>
                          <span style={{ fontSize: 10.5, opacity: 0.6, textTransform: 'uppercase' }}>
                            {c.status === 'dismissed' ? T('Đã bỏ qua', 'Dismissed') : `#${i + 1}`}
                          </span>
                        </div>
                        <div style={{ fontSize: 12, opacity: 0.7, marginTop: 4 }}>
                          {T(`${c.supporter_count}/${c.response_total} người phù hợp`, `${c.supporter_count} of ${c.response_total} respondents fit`)}
                          {c.suggested_group_size ? ` · ${T('nhóm ~', 'group ~')}${c.suggested_group_size}` : ''}
                          {c.consent_count > 0 ? ` · ${T(`${c.consent_count} đồng ý liên hệ`, `${c.consent_count} OK'd contact`)}` : ''}
                        </div>
                        {(c.budget_label || (c.activity_labels || []).length > 0) && (
                          <div style={{ fontSize: 12, opacity: 0.6, marginTop: 3 }}>
                            {[c.budget_label, (c.activity_labels || []).join(', ')].filter(Boolean).join(' · ')}
                          </div>
                        )}
                        <PillRow>
                          <Pill kind="filled" onClick={() => applySurveyCandidateAction(c, sv)} testId="survey-candidate-use">{T('Dùng ý tưởng này', 'Use This Idea')}</Pill>
                          {c.status === 'dismissed'
                            ? <Pill onClick={() => restoreSurveyCandidateAction(c.id)} testId="survey-candidate-restore">{T('Khôi phục', 'Restore')}</Pill>
                            : <Pill onClick={() => dismissSurveyCandidateAction(c.id)}>{T('Bỏ qua', 'Dismiss')}</Pill>}
                        </PillRow>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
            {!mySurveysLoading && closedSurveys.filter(sv => !candidatesBySurvey.some(g => g.sv.id === sv.id)).map(sv => (
              <div key={sv.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, opacity: 0.7, padding: '0 2px' }}>
                <span>{sv.title}</span>
                <span
                  onClick={mySurveyCandidatesBusySurveyId ? undefined : () => refreshSurveyCandidatesAction(sv.id)}
                  style={{ textDecoration: 'underline', cursor: 'pointer' }}
                >
                  {mySurveyCandidatesBusySurveyId === sv.id ? T('Đang làm mới…', 'Refreshing…') : T('Tạo gợi ý', 'Generate suggestions')}
                </span>
              </div>
            ))}
          </div>
        )}

        {tab === 'closed' && renderSelectBar({
          ids: closedIds, testId: 'survey-closed',
          allLabel: T('Lưu trữ tất cả', 'Archive all'), bulkLabel: T('Lưu trữ đã chọn', 'Archive selected'),
          onBulk: archiveSurveysAction,
        })}

        {tab === 'archived' && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 22 }}>
            <div>
              <div style={{ fontSize: 12.5, fontWeight: 600, marginBottom: 8 }}>{T('Khảo sát đã lưu trữ', 'Archived surveys')}</div>
              {archivedSurveys.length === 0 && <div style={{ fontSize: 13, opacity: 0.6 }}>{T('Chưa có khảo sát nào được lưu trữ.', 'No archived surveys yet.')}</div>}
              {renderSelectBar({
                ids: archivedSurveys.map(sv => sv.id), testId: 'survey-archived', destructive: true,
                allLabel: T('Xoá tất cả', 'Delete all'), bulkLabel: T('Xoá đã chọn', 'Delete selected'),
                onBulk: confirmDeleteSurveys,
              })}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {archivedSurveys.map(sv => (
                  <div key={sv.id} style={{ border: `1px solid ${rule}`, borderRadius: 12, padding: 14, display: 'flex', alignItems: 'flex-start' }}>
                    {checkbox(sv.id, selectMode)}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 14, fontWeight: 600 }}>{sv.title}</div>
                      <PillRow>
                        <Pill onClick={() => goSurveyPublic(sv.public_id, 'surveysHosting', tab)}>{T('Xem trước', 'Preview')}</Pill>
                        <Pill onClick={() => unarchiveSurveyAction(sv.id)} testId="survey-unarchive">{T('Khôi phục', 'Restore')}</Pill>
                        <Pill kind="danger" onClick={() => confirmDeleteSurveys([sv.id])} testId="survey-delete-archived">{T('Xoá', 'Delete')}</Pill>
                      </PillRow>
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div>
              <div style={{ fontSize: 12.5, fontWeight: 600, marginBottom: 8 }}>{T('Ý tưởng sự kiện đã dùng', 'Used event ideas')}</div>
              {usedCandidates.length === 0 && <div style={{ fontSize: 13, opacity: 0.6 }}>{T('Ý tưởng đã dùng sẽ tự động chuyển vào đây.', 'Ideas you use move here automatically.')}</div>}
              {renderSelectBar({
                ids: usedCandidates.map(c => c.id), testId: 'survey-used-ideas', destructive: true,
                allLabel: T('Xoá tất cả', 'Delete all'), bulkLabel: T('Xoá đã chọn', 'Delete selected'),
                onBulk: confirmDeleteIdeas,
              })}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {usedCandidates.map(c => (
                  <div key={c.id} style={{ border: `1px solid ${rule}`, borderRadius: 12, padding: 14, display: 'flex', alignItems: 'flex-start' }}>
                    {checkbox(c.id, selectMode)}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 14, fontWeight: 600 }}>{[c.date_label, c.location_label].filter(Boolean).join(' ▪︎ ') || surveyTitle(c.survey_id)}</div>
                      <div style={{ fontSize: 12, opacity: 0.6, marginTop: 3 }}>{surveyTitle(c.survey_id)}</div>
                      <PillRow>
                        <Pill onClick={() => restoreSurveyCandidateAction(c.id)} testId="survey-candidate-unarchive">{T('Đưa về gợi ý', 'Move back')}</Pill>
                        <Pill kind="danger" onClick={() => confirmDeleteIdeas([c.id])} testId="survey-candidate-delete">{T('Xoá', 'Delete')}</Pill>
                      </PillRow>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {(tab === 'active' || tab === 'closed') && mySurveysLoading && (
          <div style={{ textAlign: 'center', fontSize: 13, opacity: 0.6, padding: 20 }}>{T('Đang tải…', 'Loading…')}</div>
        )}

        {(tab === 'active' || tab === 'closed') && !mySurveysLoading && filtered.length === 0 && (
          <div style={{ textAlign: 'center', fontSize: 13, opacity: 0.6, padding: 20 }}>
            {tab === 'active' ? T('Chưa có khảo sát nào đang mở.', 'No active surveys yet.') : T('Chưa có khảo sát đã đóng.', 'No closed surveys yet.')}
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {filtered.map(sv => (
            <div key={sv.id} style={{ border: `1px solid ${rule}`, borderRadius: 12, padding: 14, display: 'flex', alignItems: 'flex-start' }}>
              {tab === 'closed' && checkbox(sv.id, selectMode)}
              <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontSize: 14, fontWeight: 600 }}>{sv.title}</span>
                <span style={{ fontSize: 10.5, opacity: 0.6, textTransform: 'uppercase' }}>{sv.status}</span>
              </div>
              <div style={{ fontSize: 12, opacity: 0.6, marginTop: 4 }}>
                {T('Hạn', 'Deadline')}: {sv.closes_at ? new Date(sv.closes_at).toLocaleString('vi-VN') : '—'}
              </div>
              {sv.status !== 'draft' && (
                <div
                  onClick={() => { navigator.clipboard?.writeText(surveyPublicUrl(sv.public_id)); }}
                  style={{ fontSize: 11.5, opacity: 0.6, marginTop: 4, cursor: 'pointer', wordBreak: 'break-all' }}
                  title={T('Bấm để sao chép', 'Tap to copy')}
                >
                  {surveyPublicUrl(sv.public_id)}
                </div>
              )}
              {sv.status === 'draft' && (
                <PillRow>
                  <Pill kind="filled" onClick={() => publishSurveyAction(sv.id)}>{T('Xuất bản', 'Publish')}</Pill>
                  <Pill onClick={() => goSurveyPublic(sv.public_id, 'surveysHosting', tab)}>{T('Xem trước', 'Preview')}</Pill>
                  <Pill kind="danger" onClick={() => deleteSurveyAction(sv.id)}>{T('Xoá', 'Delete')}</Pill>
                </PillRow>
              )}
              {sv.status === 'active' && (
                <>
                  <PillRow>
                    <Pill kind="filled" onClick={() => openShareToStoryConfirm(sv)} testId="survey-open-share-to-story">{T('Chia sẻ lên story', 'Share To Story')}</Pill>
                    <Pill onClick={() => shareSurveyLinkAction(sv)}>{T('Chia sẻ liên kết', 'Share Link')}</Pill>
                  </PillRow>
                  <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                    <Pill onClick={() => goSurveyPublic(sv.public_id, 'surveysHosting', tab)}>{T('Xem trước', 'Preview')}</Pill>
                    <Pill onClick={() => closeSurveyAction(sv.id)}>{T('Đóng sớm', 'Close early')}</Pill>
                  </div>
                </>
              )}
              {sv.status === 'closed' && (
                <PillRow>
                  <Pill onClick={() => goSurveyPublic(sv.public_id, 'surveysHosting', tab)}>{T('Xem trước', 'Preview')}</Pill>
                  <Pill onClick={() => archiveSurveyAction(sv.id)}>{T('Lưu trữ', 'Archive')}</Pill>
                </PillRow>
              )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Section 4 redesign — "Show a preview and require explicit Publish;
          no automatic posting." The canvas reuses SurveyStoryCard (the
          SAME renderer StoryViewer.jsx's real in-story card uses, `fill`
          variant) with the host's OWN real organizer name/avatar
          (s.orgRegName/s.myOrganizerAvatarPath — this survey's own
          organizer, since a host only ever has one org context here),
          never a generic "Your organizer" placeholder. The card's own CTA
          is a no onAnswerSurvey handler (not a real action, not
          navigation) — Publish below is the only publishing action.
          Cancel/Publish are anchored in their own safe-area-aware bottom
          bar, outside the scrollable canvas, so a long title/description
          can never push them off-screen. */}
      {s.surveyShareToStoryTarget && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', zIndex: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div
            data-testid="survey-share-to-story-confirm"
            style={{
              background: paper, borderRadius: 24, width: '100%', maxWidth: 400, maxHeight: '92vh',
              display: 'flex', flexDirection: 'column', overflow: 'hidden',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 16px 10px', flexShrink: 0 }}>
              <span style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.7 }}>{T('Xem trước story', 'Story preview')}</span>
              <span onClick={closeShareToStoryConfirm} data-testid="survey-share-to-story-close" style={{ cursor: 'pointer', fontSize: 18, lineHeight: 1 }}>×</span>
            </div>

            {/* Full-bleed canvas — fills the available width, clipped to its
                own rounded bounds, aspect-ratio'd like a real story rather
                than a small padded card floating in empty space. */}
            <div style={{ padding: '0 16px', flex: '1 1 auto', minHeight: 0, display: 'flex' }}>
              <div style={{ width: '100%', aspectRatio: '9 / 15', maxHeight: '100%', margin: '0 auto', borderRadius: 20, overflow: 'hidden' }}>
                <SurveyStoryCard
                  T={T}
                  hostName={s.orgRegName}
                  hostAvatarUrl={organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref)}
                  title={s.surveyShareToStoryTarget.title}
                  description={s.surveyShareToStoryTarget.description}
                  closesAt={s.surveyShareToStoryTarget.closes_at}
                  status="active"
                  fill
                />
              </div>
            </div>

            {s.surveyShareToStoryError && (
              <div style={{ fontSize: 12, color: alert, padding: '10px 16px 0', flexShrink: 0 }}>{s.surveyShareToStoryError}</div>
            )}

            <div style={{ display: 'flex', gap: 8, padding: '14px 16px calc(14px + env(safe-area-inset-bottom))', flexShrink: 0 }}>
              <div onClick={closeShareToStoryConfirm} data-testid="survey-share-to-story-cancel" style={{ flex: 1, textAlign: 'center', padding: 13, borderRadius: 11, border: `1px solid ${rule}`, fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</div>
              <div
                onClick={s.surveyShareToStoryBusy ? undefined : confirmShareSurveyToStory}
                data-testid="survey-confirm-publish-to-story"
                style={{ flex: 1, textAlign: 'center', padding: 13, borderRadius: 11, background: ink, color: paper, fontSize: 13.5, fontWeight: 600, cursor: s.surveyShareToStoryBusy ? 'default' : 'pointer', opacity: s.surveyShareToStoryBusy ? 0.6 : 1 }}
              >
                {s.surveyShareToStoryBusy ? T('Đang đăng…', 'Posting…') : T('Xuất bản', 'Publish')}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
