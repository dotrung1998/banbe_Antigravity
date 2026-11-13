// Browse by type / See all (v2.3, note 81): one screen for "Browse by type" (the whole catalogue) and "See all" (one Home
// tab). Pure helpers over Home's discovery items ({ key, catKeys, startsAt, priceVnd, ev: { name, area, organizerId,
// organizerName, organizerAvatarUrl, catDisplay } }), so the list, its counts, the host deck and the end card all read
// the same rules. Copy is { vi, en } pairs for T(), and follows note 57 (no dash or semicolon between ideas).
import { foldText } from './mapDiscovery.js';
import { applyDiscoveryFilters, DEFAULT_FILTERS } from './homeDiscovery.js';

export const SCOPES = ['all', 'foryou', 'tonight', 'weekend'];
export const DECK_SHOWN = 4;
const L = (vi, en) => ({ vi, en });

/** Events of one type ('all' = every type). An event's second category counts too (note 69). */
export function ofType(items, type) {
  return type === 'all' ? items : items.filter(it => (it.catKeys || []).includes(type));
}

/** How many events each type has in this scope (primary + second category), for the chips. */
export function typeCounts(items) {
  const out = {};
  for (const it of items) for (const k of new Set(it.catKeys || [])) out[k] = (out[k] || 0) + 1;
  return out;
}

/** Search reads titles, hosts, areas and types, accent-insensitive ("bep nho" finds "Bếp Nhỏ"). */
export function matchesQuery(it, q) {
  const needle = foldText(q);
  if (!needle) return true;
  const e = it.ev || {};
  const hay = foldText([e.name, e.organizerName, e.area, e.locationLabel, e.catDisplay].filter(Boolean).join(' '));
  return needle.split(' ').every(w => hay.includes(w));
}

/**
 * The Browse list: scope items → type → search → Browse's own filters (When, Price, Seats only: the chips choose the
 * type, so `cats` is always cleared). `hidden` = how many the filters hide (the end card says so).
 */
export function browseList({ items, type, query, filters, now }) {
  const searched = ofType(items, type).filter(it => matchesQuery(it, query));
  const list = applyDiscoveryFilters(searched, browseFilters(filters), now);
  return { list, searched: searched.length, hidden: searched.length - list.length };
}

/** Browse's filters: Home's shape, with the type and category parts switched off. */
export function browseFilters(f) {
  return { ...DEFAULT_FILTERS, ...(f || {}), cats: [], typeFilters: [] };
}

/** How many Browse filters are on (When, Price, Seats), for the badge. */
export function browseFilterCount(f) {
  const x = browseFilters(f);
  let n = 0;
  if (x.date && x.date !== 'any') n++;
  if (x.free || x.priceMin != null || x.priceMax != null) n++;
  if (x.seatsLeft) n++;
  if (x.almostFull) n++;
  return n;
}

/**
 * Hosts of the events in this list, busiest first, then by name. Only real hosts (an organizer id) count: the
 * built-in demo catalogue has no host profile to open.
 */
export function hostsOf(items, lang = 'vi') {
  const map = new Map();
  for (const it of items) {
    const e = it.ev || {};
    if (!e.organizerId) continue;
    const h = map.get(e.organizerId) || { id: e.organizerId, name: e.organizerName || '', avatarUrl: e.organizerAvatarUrl || '', events: [] };
    h.events.push(it.key);
    if (!h.avatarUrl && e.organizerAvatarUrl) h.avatarUrl = e.organizerAvatarUrl;
    map.set(e.organizerId, h);
  }
  return [...map.values()].sort((a, b) => b.events.length - a.events.length || a.name.localeCompare(b.name, lang));
}

/** The deck line: "AEIE Studios, Bàn Dài" + "and 16 more hosts". */
export function deckLine(hosts) {
  const names = hosts.slice(0, 2).map(h => h.name).join(', ');
  const rest = hosts.length - Math.min(2, hosts.length);
  if (!hosts.length) return { names: L('Chưa có host', 'No hosts yet'), more: L('', '') };
  if (rest > 0) return { names: L(names, names), more: L(`và ${rest} host khác`, `and ${rest} more ${rest === 1 ? 'host' : 'hosts'}`) };
  if (hosts.length === 1) return { names: L(names, names), more: L('tổ chức mọi sự kiện ở đây', 'hosts every event here') };
  return { names: L(names, names), more: L('tổ chức các sự kiện này', 'host these events') };
}

/** Faces drawn in the deck (four overlapping) and the "+N" after them. */
export function deckFaces(hosts, shown = DECK_SHOWN) {
  return { faces: hosts.slice(0, shown), more: Math.max(0, hosts.length - shown) };
}

/** The deck turns over: the first host moves to the end. */
export const rotateHosts = hosts => (hosts.length > 1 ? [...hosts.slice(1), hosts[0]] : hosts);

/** A stable tint per host name for the monogram fallback (index into the caller's token list). */
export function tintIndex(name, n) {
  let h = 0;
  for (const ch of String(name || '')) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  return n > 0 ? h % n : 0;
}

/** Hosts in the searchable host list (accent-insensitive name match). */
export function filterHosts(hosts, q) {
  const needle = foldText(q);
  return needle ? hosts.filter(h => foldText(h.name).includes(needle)) : hosts;
}

/**
 * End card for a Browse list. No "Notify me" (no backend). Actions: 'clear-filters', 'clear-search', 'type:<key>',
 * 'type:all', 'host' (start hosting), 'map'.
 * @param {{ type: string, typeName: {vi,en}|null, list: Array, hidden: number, query: string,
 *           others: Array<{ key, name: {vi,en}, count }> }} p  others = the other types in this scope, biggest first
 */
export function browseEnd({ type, typeName, list, hidden, query, others }) {
  const n = list.length;
  if (!query && hidden > 0) {
    return {
      kind: 'filters',
      eyebrow: L(`Đang hiện ${n} trên ${n + hidden}`, `${n} of ${n + hidden} shown`),
      title: hidden === 1 ? L('Còn 1 sự kiện nằm ngay ngoài bộ lọc.', '1 more is just outside your filters.')
        : L(`Còn ${hidden} sự kiện nằm ngay ngoài bộ lọc.`, `${hidden} more are just outside your filters.`),
      body: L('Nới một bộ lọc là chúng quay lại, mọi thứ khác giữ nguyên.', 'Loosen one and they come straight back, nothing else changes.'),
      actions: [{ act: 'clear-filters', label: L(`Hiện cả ${n + hidden}`, `Show all ${n + hidden}`), primary: true }],
    };
  }
  if (query) {
    const q = query.trim();
    return {
      kind: 'search',
      eyebrow: L(`${n} kết quả cho “${q}”`, `${n} ${n === 1 ? 'match' : 'matches'} for “${q}”`),
      title: L('Chưa đúng ý? Thử tên host, khu vực hoặc món ăn.', 'Not quite it? Try a host, an area or a dish.'),
      body: type === 'all' ? L('Tìm theo tên sự kiện, host, khu vực và loại.', 'Search reads titles, hosts, areas and types.')
        : L(`Bạn đang tìm trong ${typeName.vi}.`, `You are searching ${typeName.en} only.`),
      actions: [{ act: 'clear-search', label: L('Xoá tìm kiếm', 'Clear search'), primary: true }]
        .concat(type === 'all' ? [] : [{ act: 'type:all', label: L('Tìm mọi loại', 'Search every type') }]),
    };
  }
  if (type === 'all') {
    return {
      kind: 'all',
      eyebrow: L('Hết danh sách', 'That’s the whole list'),
      title: L('Không còn gì để cuộn. Vẫn còn điều để bắt đầu.', 'Nothing left to scroll. Something left to start.'),
      body: L('Những buổi hay nhất ở đây bắt đầu từ một host và vài chiếc ghế. Buổi tiếp theo có thể là của bạn.', 'The best nights here began with one host and a few chairs. The next one could be yours.'),
      actions: [{ act: 'host', label: L('Tổ chức một buổi', 'Host a night'), primary: true }, { act: 'map', label: L('Mở bản đồ', 'Open the map') }],
    };
  }
  const top = others[0];
  return {
    kind: 'type',
    eyebrow: L(`Mọi ${typeName.vi.toLowerCase()} đang mở`, `Every ${typeName.en.toLowerCase()} on now`),
    title: top ? L(`Vẫn tò mò? ${top.name.vi} có ${top.count} sự kiện.`, `Still curious? ${top.name.en} has ${top.count} on.`)
      : L('Loại này chỉ có vậy.', 'That’s all for this type.'),
    body: L('Cùng khu phố, một kiểu buổi tối khác.', 'Same neighbourhoods, a different kind of night.'),
    actions: others.slice(0, 2).map((o, i) => ({ act: `type:${o.key}`, label: L(`${o.name.vi} · ${o.count}`, `${o.name.en} · ${o.count}`), primary: i === 0 }))
      .concat([{ act: 'type:all', label: L('Mọi loại', 'All types'), primary: others.length === 0 }]),
  };
}
