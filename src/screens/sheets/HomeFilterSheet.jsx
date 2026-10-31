// Home filter sheet (note 50) — the "level D" filter from the "4 levels" video, adapted to events:
// - a sheet OVER the results (never a full page, never one page per filter), every filter in one scroll;
// - pills (no steppers) for every discrete choice, and EVERY pill shows its count before you tap it,
//   computed with all your other filters applied;
// - a price histogram behind the range, with a context line that follows the other filters
//   ("Music · median 250k · 12 of 41 events");
// - a CTA that says exactly what you'll get ("Show 23 events"), or which single filter to relax.
// Edits a local draft; nothing changes on Home until the CTA is pressed. iOS twin: Views/HomeFilterSheet.swift.
import { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { paper, ink, rule, display, inkButton, RADIUS } from '../../theme.js';
import {
  applyDiscoveryFilters, optionCounts, relaxationHints, priceHistogram, median, bucketIndex,
  normalizeFilters, DEFAULT_FILTERS, DATE_OPTIONS, dominantCurrency, pricesIn,
} from '../../lib/homeDiscovery.js';
import { formatMoneyShort } from '../../lib/eventMarket.js';
import { CategoryGlyph, CATEGORY_DEFS } from '../../components/home/HomeDiscoveryParts.jsx';
import AreaSheet from './AreaSheet.jsx';

export const DATE_LABELS = {
  any: ['Mọi lúc', 'Any time'], tonight: ['Tối nay', 'Tonight'], today: ['Hôm nay', 'Today'], tomorrow: ['Ngày mai', 'Tomorrow'],
  weekend: ['Cuối tuần này', 'This weekend'], week: ['7 ngày tới', 'Next 7 days'],
};
export const SORT_LABELS = {
  soonest: ['Sớm nhất', 'Soonest'], nearest: ['Gần nhất', 'Nearest'], popular: ['Nổi bật', 'Popular'], price: ['Giá thấp → cao', 'Price: low to high'],
};
export const RELAX_LABELS = {
  date: ['bỏ ngày', 'any date'], price: ['bỏ khoảng giá', 'any price'], free: ['bỏ "Miễn phí"', 'not only free'],
  cats: ['mọi danh mục', 'every category'], seatsLeft: ['cả sự kiện hết chỗ', 'include sold out'], almostFull: ['bỏ "Sắp hết"', 'not only almost full'],
  type: ['bỏ bộ lọc theo loại', 'no type filters'],
};
// Slider step in the price control's currency's minor unit: 50.000₫ / $5.
const PRICE_STEP = { VND: 50000, USD: 500 };

function Pill({ active, onClick, children, count, testId, disabled }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled} aria-pressed={active} data-testid={testId}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6, height: 38, padding: '0 14px', borderRadius: RADIUS.pill,
        border: active ? '1px solid transparent' : `1px solid ${rule}`, fontFamily: 'inherit', fontSize: 13.5, cursor: disabled ? 'default' : 'pointer',
        background: active ? 'rgba(var(--bb-fg-rgb), 0.9)' : 'transparent', color: active ? 'var(--bb-bg)' : ink,
        opacity: disabled && !active ? 0.4 : 1, fontWeight: active ? 600 : 500, whiteSpace: 'nowrap',
      }}>
      {children}
      {count != null && <span data-testid={testId ? `${testId}-count` : undefined} style={{ fontSize: 12, opacity: 0.65, fontVariantNumeric: 'tabular-nums' }}>{count}</span>}
    </button>
  );
}

const Section = ({ title, right, children }) => (
  <div style={{ padding: '18px 0', borderBottom: `1px solid ${rule}` }}>
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
      <span style={{ ...display(17) }}>{title}</span>
      {right}
    </div>
    {children}
  </div>
);

// Simple Shell (switch simple_shell, note 66): Sort lives in here (`simpleShell` adds the home-sort-button id to it).
// Follow-up: categories and the event-type chips are back on Home's own rows (one source of truth), so with the
// switch on this sheet has no Category / Event style sections. Off = the sheet as before 6028e9e.
// `mapMode` (Map redesign phase 3): the same draft sheet for the Map. The map itself is the location, and the list is
// soonest-first, so Location and Sort are hidden; "Tonight" joins the date pills; price reads per ticket; the counts and
// the CTA are over the events IN THE MAP AREA (the caller passes those `items`), so "Show N" is the resulting list.
const MAP_DATE_OPTIONS = ['any', 'tonight', 'today', 'tomorrow', 'weekend', 'week'];

export default function HomeFilterSheet({ items, filters, sort, onApply, onClose, T, now, canSortNearest, areaLabel, simpleShell = false, mapMode = false }) {
  const dateOptions = mapMode ? MAP_DATE_OPTIONS : DATE_OPTIONS;
  const [draft, setDraft] = useState(() => normalizeFilters(filters));
  const [draftSort, setDraftSort] = useState(sort || 'soonest');
  const [forTwo, setForTwo] = useState(false);
  // The location picker slides up OVER this sheet; this sheet (and its draft) stays mounted underneath.
  const [areaOpen, setAreaOpen] = useState(false);
  const patch = (p) => setDraft(d => normalizeFilters({ ...d, ...p }));

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape' && !areaOpen) onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, areaOpen]);

  const total = items.length;
  const resultCount = useMemo(() => applyDiscoveryFilters(items, draft, now).length, [items, draft, now]);
  const dateCounts = useMemo(() => optionCounts(items, draft, 'date', dateOptions, now), [items, draft, now, dateOptions]);
  const catKeys = CATEGORY_DEFS.filter(c => c.key !== 'all').map(c => c.key);
  const catCounts = useMemo(() => optionCounts(items, draft, 'cats', catKeys, now), [items, draft, now]); // eslint-disable-line react-hooks/exhaustive-deps
  const freeCount = useMemo(() => optionCounts(items, draft, 'free', null, now).true, [items, draft, now]);
  const seatsCount = useMemo(() => optionCounts(items, draft, 'seatsLeft', null, now).true, [items, draft, now]);
  const almostCount = useMemo(() => optionCounts(items, draft, 'almostFull', null, now).true, [items, draft, now]);
  const hints = useMemo(() => (resultCount === 0 ? relaxationHints(items, draft, now, undefined, 1) : []), [items, draft, now, resultCount]);

  // One currency for the whole price control (migration 195): VND unless every paid event listed is USD.
  // Bounds from another currency (the list changed since they were set) are ignored, never reinterpreted.
  const currency = useMemo(() => dominantCurrency(items), [items]);
  const step = PRICE_STEP[currency];
  const boundsMatch = (draft.priceCurrency === 'USD' ? 'USD' : 'VND') === currency;
  // Market behind the price control: everything that passes the OTHER filters, in that one currency.
  const priceMarket = useMemo(() => pricesIn(applyDiscoveryFilters(items, { ...draft, priceMin: null, priceMax: null, free: false }, now), currency),
    [items, draft, now, currency]);
  const hist = useMemo(() => priceHistogram(priceMarket, 14), [priceMarket]);
  const paidMedian = median(priceMarket.filter(p => p > 0));
  const sliderMax = hist ? Math.ceil(hist.max / step) * step : 0;
  const lo = (boundsMatch && draft.priceMin) || 0;
  const hi = (boundsMatch && draft.priceMax != null) ? draft.priceMax : sliderMax;
  const loIdx = bucketIndex(hist, lo);
  const hiIdx = bucketIndex(hist, hi);
  const shown = (v) => formatMoneyShort(forTwo ? v * 2 : v, currency);
  const inRangePaid = priceMarket.filter(p => p > 0 && p >= lo && p <= hi).length;
  const catLabel = draft.cats.length === 1 ? T(...(() => { const c = CATEGORY_DEFS.find(x => x.key === draft.cats[0]); return [c.vi, c.en]; })()) : null;
  const contextLine = [catLabel, areaLabel, paidMedian != null ? T(`trung vị ${shown(paidMedian)}`, `median ${shown(paidMedian)}`) : null]
    .filter(Boolean).join(' · ');

  const cta = resultCount > 0
    ? T(`Xem ${resultCount} sự kiện`, `Show ${resultCount} event${resultCount === 1 ? '' : 's'}`)
    : hints[0] ? T(`Không có sự kiện · thử ${RELAX_LABELS[hints[0].id][0]}`, `No events · try ${RELAX_LABELS[hints[0].id][1]}`) : T('Không có sự kiện', 'No events');
  const onCta = () => {
    if (resultCount > 0) { onApply(draft, draftSort); return; }
    if (hints[0]) setDraft(normalizeFilters(hints[0].filters));
  };

  const target = typeof document !== 'undefined' ? (document.querySelector('.bb-screen') || document.body) : null;
  if (!target) return null;
  return createPortal(
    <div onClick={onClose} data-testid="home-filter-backdrop"
      style={{ position: 'fixed', inset: 0, zIndex: 2100, background: 'rgba(12,12,12,0.45)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
      <div role="dialog" aria-modal="true" aria-label={T('Bộ lọc', 'Filters')} onClick={(e) => e.stopPropagation()} data-testid="home-filter-sheet"
        style={{ background: paper, color: ink, borderRadius: '22px 22px 0 0', maxHeight: '88%', display: 'flex', flexDirection: 'column', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        {/* Reset on the left, close (×) on the right; equal side columns keep the title centred. */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center', padding: '10px 14px 8px', borderBottom: `1px solid ${rule}` }}>
          <button type="button" onClick={() => { setDraft(normalizeFilters(DEFAULT_FILTERS)); setDraftSort('soonest'); }} data-testid="home-filter-reset"
            style={{ justifySelf: 'start', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, opacity: 0.75, cursor: 'pointer', padding: '8px 6px' }}>{T('Đặt lại', 'Reset')}</button>
          <span style={{ ...display(17), textAlign: 'center' }}>{T('Bộ lọc', 'Filters')}</span>
          <button type="button" onClick={onClose} aria-label={T('Đóng', 'Close')} data-testid="home-filter-close"
            style={{ justifySelf: 'end', width: 36, height: 36, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: ink, fontSize: 18, cursor: 'pointer' }}>×</button>
        </div>

        <div style={{ overflowY: 'auto', padding: '0 20px', flex: 1 }}>
          <Section title={T('Khi nào', 'When')}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {dateOptions.map(opt => (
                <Pill key={opt} active={draft.date === opt} onClick={() => patch({ date: opt })} count={opt === 'any' ? null : dateCounts[opt]}
                  disabled={opt !== 'any' && dateCounts[opt] === 0} testId={`home-filter-date-${opt}`}>
                  {T(...DATE_LABELS[opt])}
                </Pill>
              ))}
              <label style={{ position: 'relative', display: 'inline-flex' }}>
                <Pill active={draft.date.startsWith('on:')} testId="home-filter-date-pick" onClick={() => {}}>
                  {draft.date.startsWith('on:') ? draft.date.slice(3).split('-').reverse().slice(0, 2).join('/') : T('Chọn ngày', 'Pick a date')}
                </Pill>
                <input type="date" aria-label={T('Chọn ngày', 'Pick a date')} data-testid="home-filter-date-input"
                  onChange={(e) => patch({ date: e.target.value ? `on:${e.target.value}` : 'any' })}
                  style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer' }} />
              </label>
            </div>
          </Section>

          <Section title={mapMode ? T('Giá mỗi vé', 'Price per ticket') : T('Giá', 'Price')} right={
            <button type="button" onClick={() => setForTwo(v => !v)} aria-pressed={forTwo} data-testid="home-filter-for-two"
              style={{ border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, opacity: forTwo ? 1 : 0.6, cursor: 'pointer', padding: 0 }}>
              {forTwo ? '✓ ' : ''}{T('Giá cho 2 người', 'Price for 2')}
            </button>
          }>
            {hist ? (
              <>
                <div data-testid="home-filter-price-context" style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 10 }}>
                  {contextLine}{contextLine ? ' · ' : ''}<b style={{ fontWeight: 700, opacity: 1 }}>{T(`${inRangePaid} / ${priceMarket.filter(p => p > 0).length} sự kiện`, `${inRangePaid} of ${priceMarket.filter(p => p > 0).length} events`)}</b>
                </div>
                <div aria-hidden="true" style={{ display: 'flex', alignItems: 'flex-end', gap: 3, height: 56 }}>
                  {hist.counts.map((c, i) => {
                    const peak = Math.max(...hist.counts);
                    const on = !draft.free && i >= loIdx && i <= hiIdx;
                    return <div key={i} style={{ flex: 1, height: `${Math.max(6, (c / peak) * 100)}%`, borderRadius: 3, background: on ? 'rgba(var(--bb-fg-rgb),0.85)' : 'rgba(var(--bb-fg-rgb),0.16)' }} />;
                  })}
                </div>
                <div style={{ position: 'relative', height: 28, marginTop: 2 }}>
                  <input type="range" min={0} max={sliderMax} step={step} value={lo} aria-label={T('Giá thấp nhất', 'Minimum price')} data-testid="home-filter-price-min"
                    onChange={(e) => { const v = Math.min(Number(e.target.value), hi); patch({ priceMin: v > 0 ? v : null, priceMax: boundsMatch ? draft.priceMax : null, priceCurrency: currency, free: false }); }}
                    className="bb-range" style={{ position: 'absolute', inset: 0, width: '100%' }} />
                  <input type="range" min={0} max={sliderMax} step={step} value={hi} aria-label={T('Giá cao nhất', 'Maximum price')} data-testid="home-filter-price-max"
                    onChange={(e) => { const v = Math.max(Number(e.target.value), lo); patch({ priceMax: v < sliderMax ? v : null, priceMin: boundsMatch ? draft.priceMin : null, priceCurrency: currency, free: false }); }}
                    className="bb-range" style={{ position: 'absolute', inset: 0, width: '100%' }} />
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, fontWeight: 600 }}>
                  <span>{lo > 0 ? shown(lo) : T('Miễn phí', 'Free')}</span>
                  <span>{boundsMatch && draft.priceMax != null ? shown(hi) : T(`${shown(sliderMax)}+`, `${shown(sliderMax)}+`)}</span>
                </div>
              </>
            ) : <div style={{ fontSize: 12.5, opacity: 0.6 }}>{T('Chưa có sự kiện trả phí nào khớp.', 'No paid events match yet.')}</div>}
            <div style={{ marginTop: 12 }}>
              <Pill active={draft.free} onClick={() => patch({ free: !draft.free, priceMin: null, priceMax: null })} count={freeCount} disabled={!draft.free && freeCount === 0} testId="home-filter-free">
                {T('Chỉ miễn phí', 'Free only')}
              </Pill>
            </div>
          </Section>

          {!simpleShell && (
          <Section title={T('Danh mục', 'Category')}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {CATEGORY_DEFS.filter(c => c.key !== 'all').map(c => {
                const on = draft.cats.includes(c.key);
                return (
                  <Pill key={c.key} active={on} count={catCounts[c.key]} disabled={!on && catCounts[c.key] === 0} testId={`home-filter-cat-${c.key}`}
                    onClick={() => patch({ cats: on ? draft.cats.filter(k => k !== c.key) : [...draft.cats, c.key] })}>
                    <CategoryGlyph cat={c.key} size={16} />{T(c.vi, c.en)}
                  </Pill>
                );
              })}
            </div>
          </Section>
          )}

          <Section title={T('Chỗ ngồi', 'Seats')}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              <Pill active={draft.seatsLeft} onClick={() => patch({ seatsLeft: !draft.seatsLeft })} count={seatsCount} testId="home-filter-seats-left">{T('Còn chỗ', 'Seats left')}</Pill>
              <Pill active={draft.almostFull} onClick={() => patch({ almostFull: !draft.almostFull })} count={almostCount} disabled={!draft.almostFull && almostCount === 0} testId="home-filter-almost-full">{T('Sắp hết chỗ', 'Almost full')}</Pill>
            </div>
          </Section>

          {!mapMode && (
          <Section title={T('Khu vực', 'Location')}>
            <button type="button" onClick={() => setAreaOpen(true)} data-testid="home-filter-area"
              style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', minHeight: 44, border: `1px solid ${rule}`, borderRadius: RADIUS.tile, background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, padding: '0 14px', cursor: 'pointer' }}>
              <span>{areaLabel || T('Mọi nơi', 'Everywhere')}</span><span aria-hidden="true">›</span>
            </button>
          </Section>
          )}

          {!mapMode && (
          <Section title={T('Sắp xếp', 'Sort by')}>
            <div role={simpleShell ? 'group' : undefined} aria-label={simpleShell ? T('Sắp xếp', 'Sort by') : undefined}
              data-testid={simpleShell ? 'home-sort-button' : undefined} style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {Object.keys(SORT_LABELS).map(m => (
                <Pill key={m} active={draftSort === m} onClick={() => setDraftSort(m)} disabled={m === 'nearest' && !canSortNearest} testId={`home-sort-${m}`}>
                  {T(...SORT_LABELS[m])}
                </Pill>
              ))}
            </div>
            {!canSortNearest && <div style={{ fontSize: 11.5, opacity: 0.6, marginTop: 8 }}>{T('Bật vị trí để sắp xếp theo khoảng cách.', 'Turn on location to sort by distance.')}</div>}
          </Section>
          )}
          <div style={{ height: 12 }} />
        </div>

        <div style={{ padding: '12px 20px 26px', borderTop: `1px solid ${rule}` }}>
          <button type="button" onClick={onCta} data-testid="home-filter-apply" data-count={resultCount}
            style={{ ...inkButton({ width: '100%', padding: 15, borderRadius: RADIUS.pill }), border: 'none', fontFamily: 'inherit' }}>
            {cta}
          </button>
          <div style={{ fontSize: 11.5, opacity: 0.55, textAlign: 'center', marginTop: 8 }}>
            {mapMode
              ? T(`trên tổng ${total} sự kiện trong vùng bản đồ`, `out of ${total} event${total === 1 ? '' : 's'} in this map area`)
              : T(`trên tổng ${total} sự kiện`, `out of ${total} events`)}
          </div>
        </div>
      </div>
      {areaOpen && <AreaSheet embedded onDone={() => setAreaOpen(false)} />}
    </div>,
    target,
  );
}
