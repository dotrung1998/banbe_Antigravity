// Account search (web port of iOS AccountSearchEntry, AccountView.swift).
//
// Back navigation: the Account screen unmounts when a result opens another
// screen and remounts on the way back, so the open/query state can't live in
// the component. It lives here, module-level, and is only restored when the
// user left through a search result (`markReturnToSearch`) — a normal visit
// to Account always starts with search closed, same as iOS's accountSearchReturn.

/** Lowercase + strip diacritics (incl. Vietnamese đ). */
export function foldText(s) {
  return String(s || '')
    .replace(/đ/g, 'd').replace(/Đ/g, 'd')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase();
}

/** Every typed word must appear somewhere in the entry's text; empty matches all. */
export function entryMatches(entry, query, tab) {
  const tokens = foldText(query).split(/[^a-z0-9]+/).filter(Boolean);
  if (!tokens.length) return true;
  const hay = foldText([entry.vi, entry.en, entry.secVi, entry.secEn, tab.vi, tab.en, entry.keywords].join(' '));
  return tokens.every(t => hay.includes(t));
}

let saved = { open: false, query: '' };
let returning = false;

export function markReturnToSearch(query) { saved = { open: true, query }; returning = true; }
/** Called once on Account mount: the state to restore, or a closed search. */
export function takeSearchState() {
  const out = returning ? saved : { open: false, query: '' };
  returning = false;
  return out;
}
export function resetSearchState() { saved = { open: false, query: '' }; returning = false; }
