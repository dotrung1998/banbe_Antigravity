// End-of-list cards (v2.3, note 81): a short last page ends with a card written for where you are, never blank paper.
// Only REAL actions: the prototype's "Notify me" has no backend (follow_alerts and push are off), so it is not here.
// Copy follows note 57 (no dash or semicolon between ideas). Every string is a { vi, en } pair for T().
//
// Actions (the component maps them): 'clear-filters' (drop Home's filters), 'types' (Browse every type),
// 'map' (open the Map with the same filters), 'host' (start hosting / Create), 'clear-search', 'type:<key>',
// 'tab:all' (switch Home to the All events tab), 'area' (open the area picker).

const L = (vi, en) => ({ vi, en });

/**
 * Home Shortlist end card. The Shortlist follows Home's filters, not the hero tab, so its copy talks about events only.
 * @param {{ total: number, shown: number, filtersOn: boolean, tab?: string|null }} p
 *   total = every event Home lists before Home's filters, shown = after. tab = the open Home tab: on 'all' the list
 *   already holds every event, so the second action is "Change area"; on any other tab it is "See all events" (the
 *   All events tab). There is no map action here, a "See on the map" card sits right under the list.
 */
export function shortlistEnd({ total, shown, filtersOn, tab = null }) {
  const hidden = Math.max(0, total - shown);
  const onAll = tab === 'all';
  if (filtersOn && hidden > 0) {
    return {
      kind: 'filters',
      eyebrow: L(`Đang hiện ${shown} trên ${total}`, `${shown} of ${total} shown`),
      title: hidden === 1
        ? L('Còn 1 sự kiện nằm ngay ngoài bộ lọc.', '1 more is just outside your filters.')
        : L(`Còn ${hidden} sự kiện nằm ngay ngoài bộ lọc.`, `${hidden} more are just outside your filters.`),
      body: L('Nới một bộ lọc là chúng quay lại, mọi thứ khác giữ nguyên.', 'Loosen one and they come straight back, nothing else changes.'),
      actions: [{ act: 'clear-filters', label: L(`Hiện cả ${total}`, `Show all ${total}`), primary: true }, { act: 'types', label: L('Duyệt theo loại', 'Browse by type') }],
    };
  }
  return {
    kind: 'end',
    eyebrow: L(`Tất cả ${total} sự kiện`, `${total} ${total === 1 ? 'event' : 'events'} in all`),
    title: L('Bạn đã xem hết các sự kiện.', 'You’ve seen every event.'),
    body: onAll
      ? L('Duyệt theo loại hoặc thử khu vực khác để tìm thêm.', 'Browse by type or try another area to find more.')
      : L('Duyệt theo loại hoặc xem tất cả sự kiện để tìm thêm.', 'Browse by type or see all events to find more.'),
    actions: [
      { act: 'types', label: L('Duyệt mọi loại', 'Browse every type'), primary: true },
      onAll ? { act: 'area', label: L('Đổi khu vực', 'Change area') } : { act: 'tab:all', label: L('Xem tất cả sự kiện', 'See all events') },
    ],
  };
}

/** The hero tabs' own words, for the suggestion cards (the same pairs the tab row uses). */
const TAB_WORDS = { tonight: L('Tối nay', 'Tonight'), weekend: L('Cuối tuần', 'Weekend'), all: L('Tất cả sự kiện', 'All events') };
const evCount = n => L(`${n} sự kiện`, `${n} ${n === 1 ? 'event' : 'events'}`);

/**
 * Suggestion cards that follow a short hero pager (the big photo cards at the top of Home), after the event cards and
 * the "See all N" end card. A tab with fewer than 3 events (but at least one, an empty tab has its own card) offers
 * other ways out, in this order: Weekend (when not on it and it has events), All events (when not on it and it holds
 * more than this tab shows), then Browse by type, which is always there. Each card is { kind: 'tab', tab, title,
 * detail } (switches the tab in place) or { kind: 'browse', title, detail } (opens Browse by type).
 * iOS twin: ListEnd.heroSuggestions. Shared fixture: tests/fixtures/list-end.json.
 * @param {{ tab: string, shown: number, counts: { weekend?: number, all?: number } }} p
 */
export function heroSuggestions({ tab, shown, counts }) {
  if (!(shown >= 1 && shown < 3)) return [];
  const c = counts || {};
  const out = [];
  if (tab !== 'weekend' && (c.weekend || 0) > 0) out.push({ kind: 'tab', tab: 'weekend', title: TAB_WORDS.weekend, detail: evCount(c.weekend) });
  if (tab !== 'all' && (c.all || 0) > shown) out.push({ kind: 'tab', tab: 'all', title: TAB_WORDS.all, detail: evCount(c.all) });
  out.push({ kind: 'browse', title: L('Duyệt theo loại', 'Browse by type'), detail: L('Mọi loại sự kiện', 'Every type of event') });
  return out;
}

/** A slim card has room for one line and one action: the title and the primary action only. */
export function slimmed(card) {
  return { ...card, body: null, actions: card.actions.filter(a => a.primary).slice(0, 1) };
}
