// Home Shortlist (v2.3, note 81, switch home_v23): every event Home lists, narrowed by Home's filters, four large rows
// a page at least (more when the screen has room, see fittedPageSize), in Home's own order (soonest, or the chosen
// sort). It is INDEPENDENT of the hero tabs above: those switch the
// rail only, so the list never empties (or changes) just because For You is the open tab. A short last page ends with an
// end card (src/lib/listEnd.js).
import Pager from '../list/Pager.jsx';
import EndCard from '../list/EndCard.jsx';
import EventRowV23, { ROW_HEIGHT } from '../list/EventRowV23.jsx';
import { shortlistEnd } from '../../lib/listEnd.js';

const SLIDERS = <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>;
export const TAB_LABEL = { foryou: { vi: 'Dành cho bạn', en: 'For You' }, tonight: { vi: 'Tối nay', en: 'Tonight' }, weekend: { vi: 'Cuối tuần', en: 'Weekend' } };

/**
 * @param {object} p
 * @param {Array} p.rows  shaped rows for EventRowV23, already filtered, in Home's order
 * @param {number} p.total  every event Home lists, before Home's filters
 * @param {number} p.filterBadge  how many filters are on
 * @param {(act: string) => void} p.onAction  end-card and empty-state actions
 * @param {(key: string) => void} [p.onToggleSave]  the row's heart (favorites)
 */
export default function ShortlistV23({ T, lang, rows, total, filterBadge, onFilters, onOpenEvent, onAction, onToggleSave }) {
  const n = rows.length;
  const filtersOn = filterBadge > 0;
  const card = shortlistEnd({ total, shown: n, filtersOn });
  return (
    <section data-testid="home-shortlist-section" aria-labelledby="home-shortlist-title" style={{ paddingTop: 28 }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: 12, padding: '0 20px 12px' }}>
        <div style={{ minWidth: 0 }}>
          <h3 id="home-shortlist-title" style={{ fontSize: 19, fontWeight: 400, margin: 0, letterSpacing: '-.01em' }}>{T('Gần bạn', 'Near you')}</h3>
          <button type="button" onClick={onFilters} data-testid="home-filter-summary"
            style={{ display: 'block', margin: '4px 0 0', padding: 0, border: 'none', background: 'none', color: 'var(--bb-fg-2)', fontFamily: 'inherit', fontSize: 12.5, cursor: 'pointer', textAlign: 'left' }}>
            {filtersOn && total > n
              ? T(`${n} trên ${total} sự kiện · gần nhất trước`, `${n} of ${total} events · soonest first`)
              : T(`${n} sự kiện · gần nhất trước`, `${n} ${n === 1 ? 'event' : 'events'} · soonest first`)}
          </button>
        </div>
        <button type="button" onClick={onFilters} data-testid="home-filters-button"
          aria-label={filterBadge ? T(`Bộ lọc, đang bật ${filterBadge}`, `Filters, ${filterBadge} on`) : T('Bộ lọc', 'Filters')}
          style={{ flex: 'none', minHeight: 44, padding: '0 14px', borderRadius: 999, border: 'none', background: 'var(--bb-block)', color: 'inherit', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
          <svg aria-hidden="true" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{SLIDERS}</svg>
          {T('Bộ lọc', 'Filters')}
          {filterBadge > 0 && (
            <span data-testid="home-filter-badge" style={{ minWidth: 20, height: 20, padding: '0 6px', borderRadius: 999, background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontSize: 12, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{filterBadge}</span>
          )}
        </button>
      </div>
      <Pager items={rows} getKey={r => r.key} lang={lang} T={T} testId="home-shortlist" rowHeight={ROW_HEIGHT}
        renderRow={r => <EventRowV23 row={r} T={T} onOpen={() => onOpenEvent(r.key)} onToggleSave={onToggleSave} />}
        renderEnd={end => <EndCard card={card} variant={end.variant} onAction={onAction} T={T} />}
        empty={(
          <EndCard variant="solo" onAction={onAction} T={T} card={filtersOn ? {
            kind: 'empty',
            eyebrow: { vi: 'Bộ lọc', en: 'Filters' },
            title: { vi: 'Không có sự kiện nào khớp bộ lọc.', en: 'Nothing matches these filters.' },
            body: { vi: 'Xoá bộ lọc để xem lại mọi thứ.', en: 'Clear the filters to see everything again.' },
            actions: [{ act: 'clear-filters', primary: true, testId: 'home-shortlist-clear', label: { vi: 'Xoá bộ lọc', en: 'Clear filters' } }],
          } : {
            kind: 'empty',
            eyebrow: { vi: 'Sự kiện', en: 'Events' },
            title: { vi: 'Chưa có sự kiện nào.', en: 'Nothing on yet.' },
            body: { vi: 'Duyệt theo loại để tìm thứ đang diễn ra.', en: 'Browse by type to find something on.' },
            actions: [{ act: 'types', primary: true, testId: 'home-shortlist-types', label: { vi: 'Duyệt theo loại', en: 'Browse by type' } }],
          }} />
        )} />
    </section>
  );
}
