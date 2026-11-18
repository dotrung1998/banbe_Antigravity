// Unified discovery on Home (note 99, switch `unified_discovery`, prototype docs/prototype/unified-home-map-prototype-v2.html):
// the state bar (what the shared search + filters are narrowing to), Browse by type that filters Home in place (the 5
// busiest types + an "All types" tile that becomes the picked type), the type sheet with its own search, and the map
// banner under the list. Pure rules: src/lib/unifiedDiscovery.js. iOS twin: Views/UnifiedHomeViews.swift.
import { useState } from 'react';
import NativeSheet from '../NativeSheet.jsx';
import { CategoryGlyph } from './HomeDiscoveryParts.jsx';
import { categoryDefs } from '../../lib/eventTypes.js';
import { topTypes, pickedTileType, typeSheetOrder } from '../../lib/unifiedDiscovery.js';

const DEFS = categoryDefs();
const DEF = Object.fromEntries(DEFS.map(d => [d.key, d]));
const KEYS = DEFS.map(d => d.key);
const Icon = ({ d, size = 18, sw = 1.6 }) => (
  <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">{d}</svg>
);
const SYNC = <><path d="M21 12a9 9 0 0 1-15 6.7L3 16M3 12a9 9 0 0 1 15-6.7L21 8" /><path d="M3 21v-5h5M21 3v5h-5" /></>;
const MAP = <><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z" /><path d="M9 4v14M15 6v14" /></>;
const X = <path d="m6 6 12 12M18 6 6 18" />;
const SEARCH = <><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></>;
const ARROW = <path d="M5 12h14M13 6l6 6-6 6" />;

const typeName = (k, T) => (DEF[k] ? T(DEF[k].vi, DEF[k].en) : k);
const evN = (n, T) => T(`${n} sự kiện`, `${n} ${n === 1 ? 'event' : 'events'}`);

/** "“jazz” · Âm nhạc · Tối nay · 3 sự kiện" + Map + clear. Shown while a query or an owned filter is on. */
export function UnifiedStateBar({ parts, count, onMap, onClear, T }) {
  return (
    <div data-testid="home-state-bar" style={{ margin: '16px 20px 0', minHeight: 52, display: 'flex', alignItems: 'center', gap: 10, padding: '6px 6px 6px 14px', borderRadius: 999, background: 'var(--bb-block)' }}>
      <span style={{ color: 'var(--bb-clay)', display: 'grid' }}><Icon d={SYNC} size={17} /></span>
      <span style={{ flex: 1, minWidth: 0, fontSize: 13.5, lineHeight: 1.3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {parts.map((p, i) => <span key={i}>{i ? ' · ' : ''}<b style={{ fontWeight: p.strong ? 600 : 400 }}>{p.text}</b></span>)}
        <span style={{ color: 'var(--bb-fg-3)' }}> · {evN(count, T)}</span>
      </span>
      <button type="button" onClick={onMap} data-testid="home-state-bar-map" className="bb-press"
        style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 6, minHeight: 40, padding: '0 14px', borderRadius: 999, border: 'none', background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>
        <Icon d={MAP} size={16} />{T('Bản đồ', 'Map')}
      </button>
      <button type="button" onClick={onClear} data-testid="home-state-bar-clear" aria-label={T('Xoá tìm kiếm và bộ lọc', 'Clear search and filters')}
        style={{ flex: 'none', width: 40, height: 40, borderRadius: '50%', border: 'none', background: 'none', color: 'var(--bb-fg-2)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
        <Icon d={X} size={16} />
      </button>
    </div>
  );
}

/** Browse by type that filters Home in place: 5 busiest types + "All types" (or the picked type when it is not a tile). */
export function UnifiedTypeGrid({ counts, selected, total, onPick, onClear, onOpenSheet, T }) {
  const tiles = topTypes(counts, KEYS);
  const picked = pickedTileType(selected, tiles);
  const tile = { padding: '14px 0 12px', border: 'none', borderRadius: 16, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 13, color: 'inherit', cursor: 'pointer' };
  const glyph = (on) => ({ width: 52, height: 52, display: 'grid', placeItems: 'center', marginBottom: 4, borderRadius: '50%',
    background: on ? 'var(--bb-fg)' : 'transparent', color: on ? 'var(--bb-bg)' : 'inherit', transition: 'background .2s, color .2s' });
  return (
    <div data-testid="home-browse" data-unified="1" style={{ padding: '28px 20px 0', scrollMarginTop: 'var(--bb-home-head-h)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <h3 style={{ fontSize: 19, fontWeight: 400, margin: 0, letterSpacing: '-.01em' }}>{T('Duyệt theo loại', 'Browse by type')}</h3>
        {selected && (
          <button type="button" data-testid="home-browse-all" onClick={onClear}
            style={{ minHeight: 44, padding: '0 4px', border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
            {T('Xem tất cả', 'See all')} <b>{total}</b>
          </button>
        )}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4 }}>
        {tiles.map(k => {
          const on = selected === k;
          const n = counts[k] || 0;
          return (
            <button key={k} type="button" data-testid={`home-browse-${k}`} aria-pressed={on} onClick={() => onPick(k)}
              style={{ ...tile, background: on ? 'var(--bb-block)' : 'none', opacity: n === 0 && !on ? 0.42 : 1 }}>
              <span style={glyph(on)}><CategoryGlyph cat={k} size={28} strokeWidth={1.5} /></span>
              <span style={{ fontWeight: on ? 600 : 400 }}>{typeName(k, T)}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{evN(n, T)}</small>
            </button>
          );
        })}
        {picked ? (
          <button type="button" data-testid="home-browse-find" data-picked={picked} aria-pressed="true" aria-haspopup="dialog" onClick={onOpenSheet}
            aria-label={T(`${typeName(picked, T)}, đang chọn. Đổi loại`, `${typeName(picked, T)}, selected. Change type`)}
            style={{ ...tile, background: 'var(--bb-block)' }}>
            <span style={glyph(true)}><CategoryGlyph cat={picked} size={28} strokeWidth={1.5} /></span>
            <span style={{ fontWeight: 600 }}>{typeName(picked, T)}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{evN(counts[picked] || 0, T)} · {T('đổi', 'change')}</small>
          </button>
        ) : (
          <button type="button" data-testid="home-browse-find" aria-pressed="false" aria-haspopup="dialog" onClick={onOpenSheet} style={{ ...tile, background: 'none' }}>
            <span style={{ ...glyph(false), border: '1.5px dashed var(--bb-rule)', boxSizing: 'border-box' }}><Icon d={SEARCH} size={26} sw={1.5} /></span>
            <span>{T('Tất cả loại', 'All types')}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{T(`${KEYS.length} loại`, `${KEYS.length} types`)}</small>
          </button>
        )}
      </div>
    </div>
  );
}

/** Every type with its count (types with events first, empty ones last and dimmed), with its own search. */
export function UnifiedTypeSheet({ counts, total, selected, onPick, onClose, T }) {
  const [q, setQ] = useState('');
  const keys = typeSheetOrder(counts, KEYS, k => `${DEF[k]?.vi || ''} ${DEF[k]?.en || ''}`, q);
  const row = (k, name, n, on) => (
    <button key={k} type="button" data-testid={`home-type-sheet-${k}`} aria-pressed={on} onClick={() => onPick(k)}
      aria-label={T(`${name}, ${n} sự kiện`, `${name}, ${n} event${n === 1 ? '' : 's'}`)}
      style={{ width: '100%', minHeight: 56, display: 'flex', alignItems: 'center', gap: 14, padding: '0 12px', border: 'none', borderRadius: 14,
        background: 'transparent', color: 'inherit', fontFamily: 'inherit', cursor: 'pointer', textAlign: 'left', opacity: n === 0 && k !== 'all' ? 0.5 : 1 }}>
      <span style={{ width: 40, height: 40, flex: 'none', borderRadius: '50%', display: 'grid', placeItems: 'center', background: on ? 'var(--bb-fg)' : 'var(--bb-block)', color: on ? 'var(--bb-bg)' : 'inherit' }}>
        {k === 'all' ? <Icon d={SEARCH} size={19} /> : <CategoryGlyph cat={k} size={20} />}
      </span>
      <span style={{ flex: 1, fontSize: 15.5, fontWeight: on ? 600 : 400 }}>{name}</span>
      <span style={{ fontSize: 13, color: 'var(--bb-fg-3)', fontVariantNumeric: 'tabular-nums' }}>{evN(n, T)}</span>
      <span aria-hidden="true" style={{ width: 18, color: 'var(--bb-clay)', fontWeight: 700 }}>{on ? '✓' : ''}</span>
    </button>
  );
  return (
    <NativeSheet open onClose={onClose} label={T('Tất cả loại', 'All types')} testId="home-type-sheet" zIndex={2100}>
      <div style={{ background: 'var(--bb-bg)', color: 'var(--bb-fg)', borderRadius: '26px 26px 0 0', maxHeight: '86%', width: '100%', display: 'flex', flexDirection: 'column', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ width: 38, height: 5, borderRadius: 3, background: 'var(--bb-rule)', margin: '10px auto 6px' }} />
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 16px 4px 20px' }}>
          <h2 style={{ fontSize: 19, fontWeight: 400, margin: 0 }}>{T('Tất cả loại', 'All types')}</h2>
          <button type="button" onClick={onClose} aria-label={T('Đóng', 'Close')} data-testid="home-type-sheet-close"
            style={{ width: 40, height: 40, borderRadius: '50%', border: 'none', background: 'var(--bb-block)', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer' }}><Icon d={X} size={16} /></button>
        </div>
        <label style={{ margin: '6px 16px 4px', display: 'flex', alignItems: 'center', gap: 10, height: 48, padding: '0 16px', borderRadius: 999, background: 'var(--bb-surface-2)' }}>
          <span style={{ color: 'var(--bb-clay)', display: 'grid' }}><Icon d={SEARCH} size={18} /></span>
          <input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder={T('Tìm một loại', 'Find a type')} aria-label={T('Tìm một loại', 'Find a type')}
            data-testid="home-type-sheet-search" autoComplete="off" enterKeyHint="search"
            style={{ flex: 1, minWidth: 0, height: '100%', border: 0, outline: 0, background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 16 }} />
        </label>
        <div style={{ overflowY: 'auto', padding: '4px 8px 32px' }}>
          {!q.trim() && row('all', T('Tất cả loại', 'All types'), total, !selected)}
          {keys.map(k => row(k, typeName(k, T), counts[k] || 0, selected === k))}
          {!keys.length && <p style={{ padding: '20px 12px', fontSize: 14, color: 'var(--bb-fg-2)', margin: 0 }}>{T(`Không có loại nào tên “${q.trim()}”.`, `No type called “${q.trim()}”.`)}</p>}
        </div>
      </div>
    </NativeSheet>
  );
}

/** "See on the map" under the list: the same result set, on the Map. */
export function UnifiedMapBanner({ count, areaLabel, onOpen, T }) {
  return (
    <div style={{ padding: '16px 20px 0' }}>
      <button type="button" onClick={onOpen} data-testid="home-map-banner" className="bb-press"
        style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 14, padding: '10px 14px 10px 10px', borderRadius: 16, border: 'none', background: 'var(--bb-block)', color: 'inherit', fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
        <span aria-hidden="true" style={{ position: 'relative', width: 76, height: 60, flex: 'none', borderRadius: 12, overflow: 'hidden', background: 'var(--bb-surface-3)' }}>
          <i style={{ position: 'absolute', left: -4, right: -4, top: 22, height: 5, background: 'var(--bb-surface-1)', transform: 'rotate(-6deg)' }} />
          <i style={{ position: 'absolute', top: -4, bottom: -4, left: 44, width: 5, background: 'var(--bb-surface-1)', transform: 'rotate(8deg)' }} />
          {[[14, 10, 'var(--bb-fg)'], [52, 30, 'var(--bb-clay)'], [26, 38, 'var(--bb-fg)']].map(([l, t, c]) => (
            <b key={l} style={{ position: 'absolute', left: l, top: t, width: 12, height: 12, borderRadius: '50% 50% 50% 0', transform: 'rotate(-45deg)', background: c, border: '2px solid var(--bb-surface-1)' }} />
          ))}
        </span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <b style={{ display: 'block', fontSize: 15, fontWeight: 600 }}>{T('Xem trên bản đồ', 'See on the map')}</b>
          <small style={{ display: 'block', fontSize: 12.5, color: 'var(--bb-fg-2)', marginTop: 2 }}>
            {areaLabel ? T(`${count} sự kiện quanh ${areaLabel} · cùng kết quả`, `${count} events around ${areaLabel} · same results`) : T(`${count} sự kiện · cùng kết quả`, `${count} events · same results`)}
          </small>
        </span>
        <span aria-hidden="true" style={{ width: 40, height: 40, borderRadius: '50%', display: 'grid', placeItems: 'center', background: 'var(--bb-fg)', color: 'var(--bb-bg)' }}><Icon d={ARROW} size={17} /></span>
      </button>
    </div>
  );
}
