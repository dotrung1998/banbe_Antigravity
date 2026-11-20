// A suggestion card after a short hero pager (the big photo cards at the top of Home): same size, radius and snap as the
// event cards and the "See all N" card, a quiet glass card with the other way to look (Weekend, All events, Browse by
// type). Which cards appear, and their words, come from src/lib/listEnd.js heroSuggestions (shared with iOS, fixture
// tests/fixtures/list-end.json). iOS twin: HeroSuggestCard in Views/HomeV23Sections.swift.
// Owner 2026-11-20: the upper area carries the card's line-art sketch (src/lib/heroLineArt.js) so it is never empty.
import HeroLineArt from './HeroLineArt.jsx';

const ARROW = <path d="M5 12h14M13 6l6 6-6 6" />;

export default function HeroSuggestCard({ card, onOpen, T }) {
  const id = card.kind === 'tab' ? card.tab : 'browse';
  return (
    <button type="button" data-testid={`home-hero-suggest-${id}`} onClick={onOpen}
      aria-label={`${T(card.title.vi, card.title.en)}. ${T(card.detail.vi, card.detail.en)}`}
      style={{ flex: '0 0 268px', height: 360, borderRadius: 16, scrollSnapAlign: 'start', border: '1px solid rgba(255,255,255,.18)', background: 'rgba(255,255,255,.07)', color: '#fff',
        fontFamily: 'inherit', position: 'relative', overflow: 'hidden', cursor: 'pointer', textAlign: 'left', padding: 20, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', gap: 6 }}>
      <span style={{ position: 'absolute', top: 20, left: 20, fontSize: 'var(--bb-text-kicker)', fontWeight: 600, letterSpacing: '.14em', textTransform: 'uppercase', color: 'rgba(255,255,255,.62)' }}>
        {T('Thử xem', 'Try instead')}
      </span>
      <HeroLineArt kind={id} testId={`home-hero-suggest-art-${id}`} style={{ position: 'absolute', left: 20, top: 48, color: 'rgba(255,255,255,.62)' }} />
      <span style={{ fontFamily: "var(--bb-font-title, 'Be Vietnam Pro', system-ui, sans-serif)", fontSize: 26, fontWeight: 300, lineHeight: 1.12, letterSpacing: '-.01em' }}>{T(card.title.vi, card.title.en)}</span>
      <span style={{ fontSize: 13, color: 'rgba(255,255,255,.78)' }}>{T(card.detail.vi, card.detail.en)}</span>
      <span aria-hidden style={{ marginTop: 10, width: 40, height: 40, borderRadius: '50%', background: 'rgba(255,255,255,.14)', display: 'grid', placeItems: 'center' }}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{ARROW}</svg>
      </span>
    </button>
  );
}
