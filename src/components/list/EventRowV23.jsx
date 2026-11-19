// The v2.3 event row (note 81): thumbnail, then three lines that each own the full width beside it, so nothing is cut
// at phone width. Line 1 is WHEN first, in full ink (the one thing a reader cannot guess), then the type; if the line
// ever runs out it is the type that is cut, and the chips above already say the type. Line 2 is the name. Line 3 is
// the place (or the status: Almost full, Sold out) with the price at its right end, where the prices still line up
// down the list. The price used to stand in its own column beside all three lines, which is what cut the time off.
// No chevron. The unit the Shortlist pages and the type screens list. Keeps data-zoom-src so the photo still flies
// into the Event Detail hero, and the home-event-<key> test id the existing specs and tour use.
// Save (2026-11-17): a row in a list that can be saved carries a heart at its trailing edge (`onToggleSave`). It is
// the same favorites write Event Detail's heart and the Home cards' Save chip use (isSaved/toggleFav), so a saved row
// reads Saved everywhere. Host-profile rows pass no `onToggleSave`, and then the row is exactly as it was.
import { display, RADIUS } from '../../theme.js';

export const ROW_HEIGHT = 92;

const HEART = 'M12 20.3 4.9 13.5A4.6 4.6 0 0 1 12 7.1a4.6 4.6 0 0 1 7.1 6.4z';
const EN = (vi, en) => en;

/**
 * @param {object} p
 * @param {{ key, name, img, when, type, place, priceLabel, isFree, status, saved }} p.row
 *   status: null | { tone: 'alert'|'honey', text } (Cancelled, Sold out, Almost full)
 * @param {(key: string) => void} [p.onToggleSave]  present = show the heart; absent = no save (host profile rows)
 * @param {(vi:string, en:string) => string} [p.T]
 */
export default function EventRowV23({ row, onOpen, testId, T = EN, onToggleSave }) {
  const saved = !!row.saved;
  return (
    <div data-testid={testId || `home-event-${row.key}`} data-zoom-src={row.key}
      style={{ height: ROW_HEIGHT, boxSizing: 'border-box', display: 'flex', gap: 12, alignItems: 'center', padding: '0 20px 12px' }}>
      {/* The link owns the photo and the words; the heart is its sibling, never inside it (no nested interactive). */}
      <div onClick={onOpen} role="link" tabIndex={0}
        onKeyDown={(e) => { if (e.key === 'Enter') onOpen(); }}
        style={{ flex: 1, minWidth: 0, display: 'flex', gap: 12, alignItems: 'center', cursor: 'pointer' }}>
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
              : <span data-testid="event-row-place" style={{ opacity: 0.72 }}>{row.place}</span>}
          </span>
          {row.priceLabel ? <span data-testid="event-row-price" style={{ flex: 'none', fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap', color: row.isFree ? 'var(--bb-honey)' : 'inherit' }}>{row.priceLabel}</span> : null}
        </span>
      </div>
      </div>
      {onToggleSave && (
        <button type="button" data-testid={`event-row-save-${row.key}`} aria-pressed={saved}
          aria-label={saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
          title={saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
          onClick={() => onToggleSave(row.key)}
          className="bb-press"
          style={{ flex: 'none', width: 40, height: 44, marginRight: -10, padding: 0, border: 'none', borderRadius: '50%', background: 'none',
            color: saved ? 'var(--bb-clay)' : 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
          <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill={saved ? 'currentColor' : 'none'}
            stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d={HEART} /></svg>
        </button>
      )}
    </div>
  );
}
