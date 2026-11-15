// End-of-list cards (v2.3, note 81): a short last page ends with a card written for where you are, never blank paper.
// Only REAL actions: the prototype's "Notify me" has no backend (follow_alerts and push are off), so it is not here.
// Copy follows note 57 (no dash or semicolon between ideas). Every string is a { vi, en } pair for T().
//
// Actions (the component maps them): 'clear-filters' (drop Home's filters), 'types' (Browse every type),
// 'map' (open the Map with the same filters), 'host' (start hosting / Create), 'clear-search', 'type:<key>'.

const L = (vi, en) => ({ vi, en });

/**
 * Home Shortlist end card. The Shortlist follows Home's filters, not the hero tab, so its copy talks about events only.
 * @param {{ total: number, shown: number, filtersOn: boolean }} p
 *   total = every event Home lists before Home's filters, shown = after.
 */
export function shortlistEnd({ total, shown, filtersOn }) {
  const hidden = Math.max(0, total - shown);
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
    body: L('Duyệt theo loại hoặc mở bản đồ để xem thêm quanh bạn.', 'Browse by type or open the map to see more around you.'),
    actions: [{ act: 'types', label: L('Duyệt mọi loại', 'Browse every type'), primary: true }, { act: 'map', label: L('Mở bản đồ', 'Open the map') }],
  };
}

/** A slim card has room for one line and one action: the title and the primary action only. */
export function slimmed(card) {
  return { ...card, body: null, actions: card.actions.filter(a => a.primary).slice(0, 1) };
}
