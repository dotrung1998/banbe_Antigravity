// Home Shortlist (v2.3, note 81, switch home_v23): the tab's events (For You, Tonight, Weekend) narrowed by Home's
// filters, four large rows a page. The order is the tab's own order (page one is the best four). The rail above stays
// the tab's picks; only this list follows the filters. A short last page ends with an end card (src/lib/listEnd.js).
import Pager from '../list/Pager.jsx';
import EndCard from '../list/EndCard.jsx';
import EventRowV23, { ROW_HEIGHT } from '../list/EventRowV23.jsx';
import { shortlistEnd } from '../../lib/listEnd.js';

const SLIDERS = <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>;
export const TAB_LABEL = { foryou: { vi: 'Dành cho bạn', en: 'For You' }, tonight: { vi: 'Tối nay', en: 'Tonight' }, weekend: { vi: 'Cuối tuần', en: 'Weekend' } };
const TAB_SUB = { foryou: ['chọn cho bạn', 'picked for you'], tonight: ['tối nay', 'tonight'], weekend: ['cuối tuần này', 'this weekend'] };

/**
 * @param {object} p
 * @param {'foryou'|'tonight'|'weekend'} p.tab
 * @param {Array} p.rows  shaped rows for EventRowV23, already filtered, in tab order
 * @param {number} p.total  the tab's events before Home's filters
 * @param {number} p.filterBadge  how many filters are on
 * @param {(act: string) => void} p.onAction  end-card and empty-state actions
 */
export default function ShortlistV23({ T, lang, tab, rows, total, filterBadge, onFilters, onOpenEvent, onAction }) {
  const label = TAB_LABEL[tab] || TAB_LABEL.foryou;
  const sub = TAB_SUB[tab] || TAB_SUB.foryou;
  const n = rows.length;
  const card = shortlistEnd({ tab, tabLabel: label, total, shown: n, filtersOn: filterBadge > 0 });
  return (
    <section data-testid="home-shortlist-section" aria-labelledby="home-shortlist-title" style={{ paddingTop: 28 }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: 12, padding: '0 20px 12px' }}>
        <div style={{ minWidth: 0 }}>
          <h3 id="home-shortlist-title" style={{ fontSize: 19, fontWeight: 400, margin: 0, letterSpacing: '-.01em' }}>{T('Chọn lọc', 'Shortlist')}</h3>
          <button type="button" onClick={onFilters} data-testid="home-filter-summary"
            style={{ display: 'block', margin: '4px 0 0', padding: 0, border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 13, opacity: 0.72, cursor: 'pointer', textAlign: 'left' }}>
            {T(`${n} sự kiện · ${sub[0]}`, `${n} ${n === 1 ? 'event' : 'events'} · ${sub[1]}`)}
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
        renderRow={r => <EventRowV23 row={r} onOpen={() => onOpenEvent(r.key)} />}
        renderEnd={end => <EndCard card={card} variant={end.variant} onAction={onAction} T={T} />}
        empty={(
          <div style={{ margin: '0 20px', padding: '20px 16px', borderRadius: 16, background: 'var(--bb-block)', textAlign: 'center' }}>
            <div style={{ fontSize: 15.5, fontWeight: 600 }}>
              {total > 0 ? T(`Không có gì trong ${label.vi} khớp bộ lọc.`, `Nothing in ${label.en} matches these filters.`) : T(`${label.vi} chưa có sự kiện.`, `Nothing in ${label.en} yet.`)}
            </div>
            <button type="button" data-testid={total > 0 ? 'home-shortlist-clear' : 'home-shortlist-types'} onClick={() => onAction(total > 0 ? 'clear-filters' : 'types')}
              style={{ marginTop: 12, minHeight: 44, padding: '0 18px', borderRadius: 999, border: 'none', background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
              {total > 0 ? T('Xoá bộ lọc', 'Clear filters') : T('Duyệt theo loại', 'Browse by type')}
            </button>
          </div>
        )} />
    </section>
  );
}
