// The v2.3 event row (note 81): thumbnail, then three lines that each own the full width beside it, so nothing is cut
// at phone width. Line 1 is WHEN first, in full ink (the one thing a reader cannot guess), then the type; if the line
// ever runs out it is the type that is cut, and the chips above already say the type. Line 2 is the name. Line 3 is
// the place (or the status: Almost full, Sold out) with the price at its right end, where the prices still line up
// down the list. The price used to stand in its own column beside all three lines, which is what cut the time off.
// No chevron. The unit the Shortlist pages and the type screens list. Keeps data-zoom-src so the photo still flies
// into the Event Detail hero, and the home-event-<key> test id the existing specs and tour use.
import { display, RADIUS } from '../../theme.js';

export const ROW_HEIGHT = 92;

/**
 * @param {object} p
 * @param {{ key, name, img, when, type, place, priceLabel, isFree, status }} p.row
 *   status: null | { tone: 'alert'|'honey', text } (Cancelled, Sold out, Almost full)
 */
export default function EventRowV23({ row, onOpen, testId }) {
  return (
    <div data-testid={testId || `home-event-${row.key}`} data-zoom-src={row.key} onClick={onOpen} role="link" tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter') onOpen(); }}
      style={{ height: ROW_HEIGHT, boxSizing: 'border-box', display: 'flex', gap: 12, alignItems: 'center', padding: '0 20px 12px', cursor: 'pointer' }}>
      <div aria-hidden="true" data-zoom-photo style={{ width: 80, height: 80, flex: 'none', borderRadius: RADIUS.thumb, background: row.img ? `var(--bb-block) center/cover no-repeat url("${row.img}")` : 'var(--bb-block)' }} />
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
        <span data-testid="event-row-kicker" style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {row.when ? <span data-testid="event-row-when">{row.when}</span> : null}
          {row.type ? <span style={{ opacity: 0.72 }}>{row.when ? ' · ' : ''}{row.type}</span> : null}
        </span>
        <span style={{ ...display(16, { lineHeight: 1.25, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{row.name}</span>
        <span style={{ display: 'flex', alignItems: 'baseline', gap: 8, fontSize: 12.5 }}>
          <span style={{ flex: 1, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {row.status
              ? <span style={{ fontWeight: 600, color: row.status.tone === 'alert' ? 'var(--bb-alert)' : 'var(--bb-honey)' }}>{row.status.text}</span>
              : <span style={{ opacity: 0.72 }}>{row.place}</span>}
          </span>
          {row.priceLabel ? <span data-testid="event-row-price" style={{ flex: 'none', fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap', color: row.isFree ? 'var(--bb-honey)' : 'inherit' }}>{row.priceLabel}</span> : null}
        </span>
      </div>
    </div>
  );
}
