// The v2.3 event row (note 81): thumbnail, kicker (type · when), title, place, and the price centred on the row.
// No chevron. The unit the Shortlist pages and the type screens list. Keeps data-zoom-src so the photo still flies
// into the Event Detail hero, and the home-event-<key> test id the existing specs and tour use.
import { display, RADIUS } from '../../theme.js';

export const ROW_HEIGHT = 92;

/**
 * @param {object} p
 * @param {{ key, name, img, kicker, place, priceLabel, isFree, status }} p.row
 *   status: null | { tone: 'alert'|'honey', text } (Cancelled, Sold out, Almost full)
 */
export default function EventRowV23({ row, onOpen, testId }) {
  return (
    <div data-testid={testId || `home-event-${row.key}`} data-zoom-src={row.key} onClick={onOpen} role="link" tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter') onOpen(); }}
      style={{ height: ROW_HEIGHT, boxSizing: 'border-box', display: 'flex', gap: 12, alignItems: 'center', padding: '0 20px 12px', cursor: 'pointer' }}>
      <div aria-hidden="true" style={{ width: 80, height: 80, flex: 'none', borderRadius: RADIUS.thumb, background: row.img ? `var(--bb-block) center/cover no-repeat url("${row.img}")` : 'var(--bb-block)' }} />
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', opacity: 0.72, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{row.kicker}</span>
        <span style={{ ...display(16, { lineHeight: 1.25, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{row.name}</span>
        <span style={{ fontSize: 12.5, opacity: 0.72, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {row.status
            ? <span style={{ fontWeight: 600, color: row.status.tone === 'alert' ? 'var(--bb-alert)' : 'var(--bb-honey)', opacity: 1 }}>{row.status.text}</span>
            : row.place}
        </span>
      </div>
      <span style={{ flex: 'none', alignSelf: 'center', fontSize: 14, fontWeight: 700, whiteSpace: 'nowrap', color: row.isFree ? 'var(--bb-honey)' : 'inherit' }}>{row.priceLabel}</span>
    </div>
  );
}
