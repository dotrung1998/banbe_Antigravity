// Home discovery building blocks (note 50): category glyph row, search bar, event card (photo on top,
// details underneath), compact list row, and the "Next up" reminder banner. iOS twins live in
// apps/ios/BanbeApp/Views/HomeDiscoveryViews.swift.
//
// Card rule from the "4 levels" video (staff variant): the name and numbers come OFF the photo so every card
// reads the same whatever the host uploaded. On the photo: only small badges (date, Save, Almost full).
import { ink, display, fieldGlass, cardGlass, CHIP_COLORS, photoChip, lightChip, RADIUS } from '../../theme.js';
import { bg } from '../../data/events.js';
import { REMINDER_CSS } from '../../lib/eventReminder.js';
import { setSearchOrigin } from '../../lib/searchOrigin.js';
import { categoryDefs } from '../../lib/eventTypes.js';

// ---- category glyphs: one stroke weight, line style, original drawings -------------------
const GLYPH_PATHS = {
  all: ['M4 4h7v7H4z', 'M13 4h7v7h-7z', 'M4 13h7v7H4z', 'M13 13h7v7h-7z'],
  supper: ['M7 3v7a2 2 0 0 0 4 0V3', 'M9 10v11', 'M16 3c-1.7 1.2-2.5 3.3-2.5 6.2V13H17V3', 'M17 13v8'],
  fashion: ['M12 6.5a1.8 1.8 0 1 1 1.8-1.8c0 1.2-1.8 1.6-1.8 3', 'M12 7.7 3.6 14.2c-.8.6-.4 1.8.6 1.8h15.6c1 0 1.4-1.2.6-1.8L12 7.7'],
  gallery: ['M4 5h16v14H4z', 'M4 15.5l4.5-4.5 4 4 2.5-2.5L20 17.5', 'M15.5 9.5h.01'],
  music: ['M9 18V5.5l11-2v12', 'M9 18a2.5 2.5 0 1 1-2.5-2.5A2.5 2.5 0 0 1 9 18z', 'M20 15.5a2.5 2.5 0 1 1-2.5-2.5 2.5 2.5 0 0 1 2.5 2.5z'],
  popup: ['M3 10l2-5h14l2 5', 'M3 10c0 1.4 1.3 2.5 3 2.5S9 11.4 9 10c0 1.4 1.3 2.5 3 2.5s3-1.1 3-2.5c0 1.4 1.3 2.5 3 2.5s3-1.1 3-2.5', 'M5 12.5V20h14v-7.5', 'M10 20v-4.5h4V20'],
};

export function CategoryGlyph({ cat, size = 22, strokeWidth = 1.7 }) {
  const paths = GLYPH_PATHS[cat] || GLYPH_PATHS.all;
  return (
    <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      {paths.map((d, i) => <path key={i} d={d} />)}
    </svg>
  );
}

export const CATEGORY_DEFS = categoryDefs({ withAll: true }); // src/data/eventTypeProfiles.json

/** Quiet tinted rounded-square tiles; they stay out of the way of the event photos below. */
export function CategoryRow({ values = [], onPick, T }) {
  return (
    <div data-hscroll="true" data-testid="home-category-row" role="tablist" aria-label={T('Danh mục', 'Categories')}
      style={{ display: 'flex', gap: 6, overflowX: 'auto', scrollbarWidth: 'none', padding: '12px 14px 4px' }}>
      {CATEGORY_DEFS.map(c => {
        const active = c.key === 'all' ? values.length === 0 : values.includes(c.key);
        return (
          <button key={c.key} type="button" role="tab" aria-selected={active} onClick={() => onPick(c.key)}
            data-testid={`home-category-${c.key}`}
            style={{ flex: 'none', width: 64, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, padding: '2px 0', border: 'none', background: 'none', cursor: 'pointer', color: ink, fontFamily: 'inherit' }}>
            <span style={{
              width: 52, height: 52, borderRadius: RADIUS.tile, display: 'flex', alignItems: 'center', justifyContent: 'center',
              background: active ? 'rgba(var(--bb-fg-rgb), 0.9)' : 'rgba(var(--bb-fg-rgb), 0.06)',
              color: active ? 'var(--bb-bg)' : ink,
              boxShadow: active ? '0 2px 6px rgba(27,25,22,0.18)' : 'inset 0 0 0 1px rgba(var(--bb-fg-rgb), 0.06)',
              transition: 'background 0.15s ease, color 0.15s ease',
            }}>
              <CategoryGlyph cat={c.key} />
            </span>
            <span style={{ fontSize: 11.5, fontWeight: active ? 600 : 500, lineHeight: 1.2, maxWidth: '100%', textAlign: 'center', overflowWrap: 'anywhere', opacity: active ? 1 : 0.8 }}>{T(c.vi, c.en)}</span>
          </button>
        );
      })}
    </div>
  );
}

/** Full-width search entry. The placeholder says what you can actually search for. */
export function HomeSearchBar({ onOpen, T }) {
  return (
    // Remembers where the bar is so Search can glide its own field up from here (src/lib/searchOrigin.js).
    <button type="button" onClick={(e) => { setSearchOrigin(e.currentTarget.getBoundingClientRect()); onOpen(); }} data-testid="home-search-bar"
      aria-label={T('Tìm sự kiện, host, khu vực', 'Search events, hosts, areas')}
      style={{ ...fieldGlass({ borderRadius: RADIUS.pill }), height: 46, width: '100%', display: 'flex', alignItems: 'center', gap: 10, padding: '0 16px', border: 'none', cursor: 'text', color: ink, fontFamily: 'inherit', textAlign: 'left' }}>
      <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.7, flex: 'none' }}>
        <circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" />
      </svg>
      <span style={{ fontSize: 14.5, opacity: 0.6, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {T('Tìm sự kiện, host, khu vực, vibe…', 'Search events, hosts, areas, vibes…')}
      </span>
    </button>
  );
}

// ---- event card -------------------------------------------------------------------------
const badgeBase = { fontSize: 10.5, padding: '5px 9px', borderRadius: RADIUS.pill, letterSpacing: '0.03em' };

function Photo({ ev, height, T, radius, compact = false }) {
  if (ev.img) return <div style={bg(ev.img, { width: '100%', height, borderRadius: radius, filter: 'none' })} />;
  return (
    <div aria-label={compact ? T('Chưa có ảnh', 'No photo yet') : undefined} style={{ ...cardGlass({ width: '100%', height, borderRadius: radius }), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {compact
        ? <svg aria-hidden="true" width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} style={{ color: ink, opacity: 0.35 }}><path d="M4 5h16v14H4z" /><path d="M4 15.5l4.5-4.5 4 4 2.5-2.5L20 17.5" /></svg>
        : <span style={{ fontSize: 12, color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>}
    </div>
  );
}

/**
 * ev: { key, name, img, dateBadge, priceLabel, isFree, metaLine, fill: {almostFull, left, going, soldOut},
 *       cancelled, saved, going, label ('best' | 'popular' | null) }
 */
export function DiscoveryCard({ ev, onOpen, onToggleSave, T }) {
  return (
    <div data-testid={`home-event-${ev.key}`} data-zoom-src={ev.key} onClick={onOpen} role="link" tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter') onOpen(); }}
      style={{ cursor: 'pointer', padding: '0 20px 22px' }}>
      <div style={{ position: 'relative', aspectRatio: '16 / 10' }}>
        <Photo ev={ev} height="100%" T={T} radius={RADIUS.card} />
        {ev.dateBadge && <span data-testid="home-card-date" style={lightChip({ ...badgeBase, top: 10, left: 10, cursor: 'inherit', fontWeight: 700 })}>{ev.dateBadge}</span>}
        <span role="button" aria-pressed={ev.saved} data-testid={`home-save-${ev.key}`}
          onClick={(e) => { e.stopPropagation(); onToggleSave(); }}
          style={ev.saved ? photoChip(CHIP_COLORS.going, { ...badgeBase, top: 10, right: 10 }) : lightChip({ ...badgeBase, top: 10, right: 10 })}>
          {ev.saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
        </span>
        {ev.cancelled ? (
          <span style={photoChip(CHIP_COLORS.cancelled, { ...badgeBase, bottom: 10, left: 10, cursor: 'inherit' })}>{T('Đã hủy', 'Cancelled')}</span>
        ) : ev.fill?.soldOut ? (
          <span style={photoChip(CHIP_COLORS.past, { ...badgeBase, bottom: 10, left: 10, cursor: 'inherit' })}>{T('Hết chỗ', 'Sold out')}</span>
        ) : ev.fill?.almostFull ? (
          <span data-testid="home-card-almost-full" style={photoChip(CHIP_COLORS.hold, { ...badgeBase, bottom: 10, left: 10, cursor: 'inherit' })}>
            {T(`Sắp hết · còn ${ev.fill.left}`, `Almost full · ${ev.fill.left} left`)}
          </span>
        ) : ev.going ? (
          <span style={photoChip(CHIP_COLORS.going, { ...badgeBase, bottom: 10, left: 10, cursor: 'inherit' })}>{T('Bạn sẽ đến', "You're going")}</span>
        ) : null}
      </div>
      {ev.label && (
        <div data-testid={`home-card-label-${ev.label}`} style={{ marginTop: 10, fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', display: 'flex', alignItems: 'center', gap: 5 }}>
          <span aria-hidden="true" style={{ color: 'var(--bb-honey)' }}>{ev.label === 'best' ? '★' : '✦'}</span>
          {ev.label === 'best' ? T('Hợp với bạn nhất', 'Best match for you') : T('Nổi bật tuần này', 'Popular this week')}
        </div>
      )}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr auto', columnGap: 12, alignItems: 'baseline', marginTop: ev.label ? 4 : 10 }}>
        <span style={{ ...display(18, { lineHeight: 1.25, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{ev.name}</span>
        <span style={{ fontSize: 15, fontWeight: 700, whiteSpace: 'nowrap', color: ev.isFree ? 'var(--bb-honey)' : ink }}>{ev.priceLabel}</span>
      </div>
      {ev.metaLine && <div style={{ fontSize: 12.5, color: ink, opacity: 0.68, marginTop: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.metaLine}</div>}
      {/* What kind of evening it is (event type profiles), e.g. "Bàn 8 người · Có món chay · BYO". */}
      {ev.typeLine && <div data-testid="home-card-type-line" style={{ fontSize: 12.5, color: ink, opacity: 0.8, marginTop: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.typeLine}</div>}
      {ev.fill?.going != null && !ev.cancelled && (
        <div data-testid="home-card-going" style={{ fontSize: 11.5, color: ink, opacity: 0.6, marginTop: 3 }}>{T(`${ev.fill.going} người sẽ đến`, `${ev.fill.going} going`)}</div>
      )}
    </div>
  );
}

/** Compact row for comparing quickly. 72px thumbnail: big enough to recognise, not to crowd. */
export function DiscoveryRow({ ev, onOpen, T }) {
  return (
    <div data-testid={`home-event-${ev.key}`} data-zoom-src={ev.key} onClick={onOpen} role="link" tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter') onOpen(); }}
      style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '0 20px 14px', cursor: 'pointer' }}>
      <div style={{ width: 72, height: 72, flex: 'none', position: 'relative' }}>
        <Photo ev={ev} height={72} T={T} radius={RADIUS.thumb} compact />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'baseline' }}>
          <span style={{ ...display(15.5, { lineHeight: 1.25, flex: 1, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{ev.name}</span>
          <span style={{ fontSize: 13.5, fontWeight: 700, whiteSpace: 'nowrap', color: ev.isFree ? 'var(--bb-honey)' : ink }}>{ev.priceLabel}</span>
        </div>
        <span style={{ fontSize: 12, opacity: 0.68, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{[ev.dateBadge, ev.metaLine].filter(Boolean).join(' · ')}</span>
        {ev.typeLine && <span style={{ fontSize: 12, opacity: 0.8, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.typeLine}</span>}
        {(ev.cancelled || ev.fill?.soldOut || ev.fill?.almostFull) && (
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ev.cancelled ? 'var(--bb-alert)' : 'var(--bb-honey)' }}>
            {ev.cancelled ? T('Đã hủy', 'Cancelled') : ev.fill.soldOut ? T('Hết chỗ', 'Sold out') : T(`Sắp hết · còn ${ev.fill.left}`, `Almost full · ${ev.fill.left} left`)}
          </span>
        )}
      </div>
    </div>
  );
}

/** Shown only while the note-37 reminder rule fires (24h before → 12h after start) for a confirmed ticket. */
// onShowTicket (L7, switch live_activity): set only on the event's own day for a confirmed ticket; the banner then
// carries a "Show ticket" button that opens the ticket QR in one tap (the rest of the card still opens the event).
export function NextUpBanner({ item, onOpen, onShowTicket, T }) {
  if (!item) return null;
  const live = item.reminder === 'live';
  return (
    <div style={{ padding: '12px 20px 0' }}>
      <style>{REMINDER_CSS}</style>
      <div className="bb-rem-card" data-testid="home-event-reminder" data-reminder={item.reminder}
        onClick={onOpen} role="button" tabIndex={0} onKeyDown={(e) => { if (e.key === 'Enter') onOpen(); }}
        style={{ '--bb-rem-r': `${RADIUS.card}px`, position: 'relative', display: 'flex', alignItems: 'center', gap: 12, padding: 10, borderRadius: RADIUS.card, cursor: 'pointer', ...cardGlass({ borderRadius: RADIUS.card }) }}>
        <div style={{ width: 52, height: 52, flex: 'none' }}>
          <Photo ev={{ img: item.photoUrl }} height={52} T={T} radius={RADIUS.thumb} compact />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'var(--bb-honey)' }}>
            <span aria-hidden="true">★ </span>{live ? T('Đang diễn ra', 'Happening now') : T('Sắp diễn ra', 'Starting soon')}
          </div>
          <div style={{ ...display(15.5, { marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{item.name}</div>
          {item.when && <div style={{ fontSize: 12, opacity: 0.7, marginTop: 1 }}>{item.when}</div>}
        </div>
        {onShowTicket ? (
          <button type="button" data-testid="home-event-reminder-ticket"
            onClick={(e) => { e.stopPropagation(); onShowTicket(); }} onKeyDown={(e) => e.stopPropagation()}
            style={{ flex: 'none', minHeight: 36, padding: '0 14px', borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit',
              fontSize: 13, fontWeight: 700, whiteSpace: 'nowrap', color: 'var(--bb-bg)', background: 'rgba(var(--bb-fg-rgb),0.92)' }}>
            {T('Hiện vé', 'Show ticket')}
          </button>
        ) : (
          <span style={{ fontSize: 12.5, fontWeight: 600, whiteSpace: 'nowrap' }}>{T('Xem vé', 'Your ticket')} ›</span>
        )}
      </div>
    </div>
  );
}

