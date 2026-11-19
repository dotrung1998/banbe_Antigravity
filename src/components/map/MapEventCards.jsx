// Unified discovery (note 99, switch `unified_discovery`): what a pin tap shows at the bottom of the Map.
// - MapCarousel: one compact card per result (thumbnail, WHEN · TYPE, name, place or seat status + price, like
//   EventRowV23), scrolled to the selected event, which wears a 2 px ink ring. Tapping a card opens its preview.
// - MapPreview: the preview card (when · type · distance, name, a two-line blurb, area + host chips, a ticket stub and
//   the actions). "Xem chi tiết" for every event, "Giữ chỗ" beside it for a paid one; "‹ Danh sách" goes back.
// Pure presentation: MapExplore owns selection, the result set and navigation.
import { useEffect, useRef } from 'react';
import { CATEGORY_DEFS } from '../home/HomeDiscoveryParts.jsx';
import { cardDateBadge, formatMoney, zonedParts, VN_TIME_ZONE } from '../../lib/eventMarket.js';
import { MAP_DIM } from '../../lib/mapLayout.js';
import { ink, ink2, paper, alert, honey, clay, block, rule, RADIUS, display } from '../../theme.js';

const reduceMotion = () => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
const catName = (key, T) => { const c = CATEGORY_DEFS.find(d => d.key === key && d.key !== 'all'); return c ? T(c.vi, c.en) : null; };
const kickOf = (ev, T) => [ev.startsAt ? cardDateBadge(Date.parse(ev.startsAt), ev.tz, T) : null, catName(ev.catKey, T)].filter(Boolean).join(' · ');
const priceOf = (ev, T) => (ev.priceVnd > 0 ? formatMoney(ev.priceVnd, ev.currency) : T('Miễn phí', 'Free'));

/** Seat status words + tone from seat facts ({ left, soldOut, almostFull } or null). */
export function seatStatus(f, T) {
  if (!f) return null;
  if (f.soldOut) return { text: T('Hết chỗ', 'Sold out'), color: alert };
  if (f.left != null && f.almostFull) return { text: T(`Còn ${f.left} chỗ`, `${f.left} left`), color: honey };
  if (f.left != null) return { text: T(`Còn ${f.left} chỗ`, `${f.left} seats left`), color: ink2 };
  return null;
}

const kickStyle = { fontSize: 'var(--bb-text-kicker)', fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: clay, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' };

export function MapCarousel({ events, selectedId, onOpen, seatsOf, isHit, T, style }) {
  const scrollerRef = useRef(null);
  // Keep the selected card in the middle of the strip (a new pin, or coming back from the preview).
  useEffect(() => {
    const sc = scrollerRef.current;
    const card = sc?.querySelector(`[data-card="${CSS.escape(String(selectedId || ''))}"]`);
    if (!sc || !card) return;
    const left = card.offsetLeft - (sc.clientWidth - card.offsetWidth) / 2;
    sc.scrollTo({ left: Math.max(0, left), behavior: reduceMotion() ? 'auto' : 'smooth' });
  }, [selectedId, events.length]);
  return (
    <div ref={scrollerRef} data-hscroll="true" data-testid="map-carousel" className="bb-noscroll" role="list" aria-label={T('Sự kiện trên bản đồ', 'Events on the map')}
      style={{ position: 'absolute', left: 0, right: 0, zIndex: 3, display: 'flex', gap: 10, overflowX: 'auto', scrollSnapType: 'x mandatory', scrollPadding: '0 16px', padding: '3px 16px 6px', scrollbarWidth: 'none', ...style }}>
      {events.map(ev => {
        const sel = ev.id === selectedId;
        const st = seatStatus(seatsOf(ev), T);
        const few = st && st.color !== ink2;
        return (
          <div key={ev.id} role="listitem" style={{ flex: 'none', display: 'flex' }}>
            <button type="button" data-card={ev.id} data-testid={`map-mcard-${ev.id}`} aria-pressed={sel} onClick={() => onOpen(ev.id)}
              aria-label={T(`${ev.name}, xem trước`, `${ev.name}, preview`)} data-dim={isHit(ev.id) ? undefined : 'true'}
              style={{ width: 'min(292px, calc(100vw - 56px))', height: 104, scrollSnapAlign: 'center', display: 'flex', gap: 12, alignItems: 'center', padding: '10px 14px 10px 10px', boxSizing: 'border-box', borderRadius: 18, background: paper, border: `1px solid ${rule}`, color: ink, textAlign: 'left', fontFamily: 'inherit', cursor: 'pointer',
                boxShadow: sel ? `0 0 0 2px var(--bb-fg), 0 4px 14px rgba(27,25,22,0.18)` : '0 4px 14px rgba(27,25,22,0.16)', opacity: isHit(ev.id) ? 1 : MAP_DIM.rowOpacity, transition: 'box-shadow 0.2s ease, opacity 0.2s ease' }}>
              <span aria-hidden="true" style={{ width: 84, height: 84, flex: 'none', borderRadius: RADIUS.thumb, background: ev.img ? `center / cover no-repeat url("${ev.img}")` : block }} />
              <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
                <span style={kickStyle}>{kickOf(ev, T)}</span>
                <span style={{ fontSize: 15, fontWeight: 600, lineHeight: 1.25, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{ev.name}</span>
                <span style={{ display: 'flex', alignItems: 'baseline', gap: 8, fontSize: 12.5 }}>
                  <span style={{ flex: 1, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', color: few ? st.color : ink2, fontWeight: few ? 600 : 400 }}>
                    {few ? st.text : (ev.area || '')}
                  </span>
                  <span style={{ flex: 'none', fontWeight: 700, color: ink }}>{priceOf(ev, T)}</span>
                </span>
              </span>
            </button>
          </div>
        );
      })}
    </div>
  );
}

export function MapPreview({ ev, distance, seatsOf, onBack, onDetails, onReserve, T, style }) {
  const headRef = useRef(null);
  useEffect(() => { headRef.current?.focus({ preventScroll: true }); }, [ev.id]);
  const paid = ev.priceVnd > 0;
  const f = seatsOf(ev);
  const st = seatStatus(f, T);
  const canReserve = paid && !(f && f.soldOut);
  const blurb = String(ev.intro || ev.description || '').trim();
  const ms = ev.startsAt ? Date.parse(ev.startsAt) : NaN;
  const p = Number.isFinite(ms) ? zonedParts(ms, ev.tz || VN_TIME_ZONE) : null;
  const wd = p ? T(['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][p.weekday], ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'][p.weekday]) : '';
  const kick = [kickOf(ev, T), distance].filter(Boolean).join(' · ');
  const tag = { height: 28, padding: '0 10px', borderRadius: 999, background: block, fontSize: 12, fontWeight: 500, display: 'inline-flex', alignItems: 'center', maxWidth: '100%', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' };
  const btn = { flex: 1, minHeight: 48, borderRadius: 999, border: 'none', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' };
  return (
    <section data-testid="map-preview" data-event={ev.id} role="region" aria-label={T(`Xem trước ${ev.name}`, `Preview of ${ev.name}`)}
      style={{ position: 'absolute', left: 12, right: 12, zIndex: 4, padding: '14px 16px 14px', borderRadius: 24, background: paper, color: ink, border: `1px solid ${rule}`, boxShadow: '0 10px 30px rgba(27,25,22,0.22)', maxHeight: '62%', overflowY: 'auto', boxSizing: 'border-box',
        animation: reduceMotion() ? 'none' : 'bbMapPreviewIn 0.32s cubic-bezier(.22,.61,.36,1)', ...style }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
        <span style={{ ...kickStyle, minWidth: 0 }}>{kick}</span>
        <button type="button" onClick={onBack} data-testid="map-preview-back"
          style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 4, minHeight: 44, padding: '0 12px 0 8px', marginRight: -8, border: 'none', borderRadius: 999, background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>
          <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round"><path d="m15 6-6 6 6 6" /></svg>
          {T('Danh sách', 'List')}
        </button>
      </div>
      <h3 ref={headRef} tabIndex={-1} data-testid="map-preview-title" style={{ margin: '2px 0 6px', outline: 'none', ...display(24, { fontWeight: 300, letterSpacing: '-0.015em', lineHeight: 1.15 }) }}>{ev.name}</h3>
      {blurb && <p style={{ margin: '0 0 10px', fontSize: 13.5, lineHeight: 1.5, color: ink2, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{blurb}</p>}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
        {ev.area && <span style={tag}>{ev.area}</span>}
        {ev.organizerName && <span style={tag}>{T(`Host ${ev.organizerName}`, `Host ${ev.organizerName}`)}</span>}
      </div>
      <div data-testid="map-preview-stub" style={{ display: 'flex', alignItems: 'center', gap: 12, paddingTop: 12, borderTop: `1px dashed ${rule}` }}>
        {p && (
          <span aria-hidden="true" style={{ width: 52, height: 56, flex: 'none', borderRadius: 12, background: block, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
            <small style={{ fontSize: 'var(--bb-text-meta)', fontWeight: 700, letterSpacing: '0.1em', color: clay }}>{wd}</small>
            <b style={{ fontSize: 20, fontWeight: 600, lineHeight: 1 }}>{p.day}</b>
          </span>
        )}
        <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
          <b data-testid="map-preview-price" style={{ fontSize: 16, fontWeight: 700 }}>{priceOf(ev, T)}{paid ? <span style={{ fontWeight: 400, fontSize: 13, color: ink2 }}> {T('/ vé', '/ ticket')}</span> : null}</b>
          {st && <small data-testid="map-preview-seats" style={{ fontSize: 12.5, fontWeight: 600, color: st.color }}>{st.text}</small>}
        </span>
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
        <button type="button" onClick={onDetails} data-testid="map-preview-details" style={{ ...btn, background: canReserve ? block : ink, color: canReserve ? ink : paper }}>
          {T('Xem chi tiết', 'See details')}
        </button>
        {canReserve && (
          <button type="button" onClick={onReserve} data-testid="map-preview-reserve" style={{ ...btn, background: ink, color: paper }}>
            {T('Giữ chỗ', 'Reserve')}
          </button>
        )}
      </div>
    </section>
  );
}
