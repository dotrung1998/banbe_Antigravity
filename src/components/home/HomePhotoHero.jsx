// Home photo hero (note 80, from the v5 prototype): the current card's photo blurred behind a row of text tabs
// (For You | Tonight | Weekend) and a snap-scrolling rail of event cards, ending in a "See all" card. Pure view:
// Home.jsx hands it already-ranked/filtered lists, so it adds no data fetching and no new filters of its own.
import { useEffect, useRef, useState } from 'react';

const TABS = [['foryou', 'Dành cho bạn', 'For You'], ['tonight', 'Tối nay', 'Tonight'], ['weekend', 'Cuối tuần', 'Weekend']];
const NIGHT = '#16140f';

/**
 * @param {{ lists: Record<'foryou'|'tonight'|'weekend', Array<object>>, T: Function, onOpen: (key: string) => void,
 *   onSeeAll: (tab: string) => void }} props — list items: { key, name, img, dateBadge, priceLabel, metaLine, left }
 */
export default function HomePhotoHero({ lists, T, onOpen, onSeeAll }) {
  const [tab, setTab] = useState('foryou');
  const [idx, setIdx] = useState(0);
  const rail = useRef(null);
  const list = lists[tab] || [];
  const cur = list[Math.min(idx, Math.max(list.length - 1, 0))];

  // Back to the first card whenever the tab or its contents change (the list refills as events load).
  const sig = list.map(e => e.key).join('|');
  useEffect(() => { setIdx(0); if (rail.current) rail.current.scrollLeft = 0; }, [tab, sig]);
  const onScroll = () => {
    const el = rail.current;
    if (!el || !list.length) return;
    const card = el.firstElementChild;
    const step = card ? card.getBoundingClientRect().width + 12 : 280;
    setIdx(Math.min(list.length - 1, Math.max(0, Math.round(el.scrollLeft / step))));
  };

  return (
    <section data-testid="home-photo-hero" data-tab={tab} aria-label={T('Gợi ý nổi bật', 'Featured events')}
      style={{ position: 'relative', overflow: 'hidden', background: NIGHT, color: '#fff', borderRadius: 24, margin: '8px 12px 0' }}>
      <div aria-hidden style={{ position: 'absolute', inset: -30, transform: 'scale(1.1)', transition: 'background-image .5s',
        background: cur?.img ? `center/cover no-repeat url("${cur.img}")` : 'linear-gradient(180deg,#2b2721,#16140f)',
        filter: cur?.img ? 'blur(18px) brightness(.45) saturate(.9)' : 'none' }} />
      <div style={{ position: 'relative' }}>
        <div role="tablist" style={{ display: 'flex', gap: 20, padding: '16px 20px 4px', overflowX: 'auto', scrollbarWidth: 'none' }}>
          {TABS.map(([k, vi, en]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k} data-testid={`home-hero-tab-${k}`} onClick={() => setTab(k)}
              style={{ flex: 'none', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 17, padding: '6px 0', cursor: 'pointer', color: tab === k ? '#fff' : 'rgba(255,255,255,.58)',
                fontWeight: tab === k ? 500 : 300, borderBottom: `2px solid ${tab === k ? '#fff' : 'transparent'}` }}>
              {T(vi, en)}
            </button>
          ))}
        </div>
        <div ref={rail} onScroll={onScroll} data-hscroll data-testid="home-hero-rail"
          style={{ display: 'flex', gap: 12, overflowX: 'auto', scrollSnapType: 'x mandatory', padding: '16px 20px 0', scrollPaddingLeft: 20, scrollbarWidth: 'none' }}>
          {list.map((e, i) => (
            <button key={e.key} type="button" data-testid={`home-hero-card-${e.key}`} onClick={() => onOpen(e.key)}
              style={{ flex: '0 0 252px', height: 330, borderRadius: 16, position: 'relative', overflow: 'hidden', scrollSnapAlign: 'start', border: 'none', padding: 0,
                textAlign: 'left', color: '#fff', fontFamily: 'inherit', cursor: 'pointer', opacity: i === idx ? 1 : 0.6, transition: 'opacity .3s',
                background: e.img ? `#2a2620 center/cover no-repeat url("${e.img}")` : '#2a2620' }}>
              <span aria-hidden style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg,rgba(0,0,0,.25) 0%,rgba(0,0,0,0) 30%,rgba(0,0,0,.05) 50%,rgba(0,0,0,.78) 100%)' }} />
              {e.dateBadge && (
                <span style={{ position: 'absolute', top: 12, left: 12, height: 28, padding: '0 10px', borderRadius: 999, background: 'rgba(247,244,236,.85)', color: '#1B1916',
                  fontSize: 11.5, fontWeight: 700, display: 'flex', alignItems: 'center' }}>{e.dateBadge}</span>
              )}
              <span style={{ position: 'absolute', left: 16, right: 16, bottom: 16, display: 'block' }}>
                {e.metaLine && <span style={{ display: 'block', fontSize: 11, letterSpacing: '.1em', textTransform: 'uppercase', opacity: 0.85, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.metaLine}</span>}
                <span style={{ display: 'block', fontSize: 24, fontWeight: 300, lineHeight: 1.12, margin: '6px 0', letterSpacing: '-.01em' }}>{e.name}</span>
                <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8, fontSize: 13, opacity: 0.9 }}>
                  <span>{e.priceLabel}</span><span>{e.left}</span>
                </span>
              </span>
            </button>
          ))}
          {list.length > 0 && (
            <button type="button" data-testid="home-hero-see-all" onClick={() => onSeeAll(tab)}
              style={{ flex: '0 0 252px', height: 330, borderRadius: 16, scrollSnapAlign: 'start', border: '1px dashed rgba(255,255,255,.3)', background: 'rgba(255,255,255,.08)',
                color: '#fff', fontFamily: 'inherit', fontSize: 15, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: 'pointer' }}>
              <span aria-hidden style={{ fontSize: 26 }}>→</span>
              <span>{T('Xem tất cả', 'See all')}</span>
            </button>
          )}
          {!list.length && (
            <div data-testid="home-hero-empty" style={{ flex: '1 0 100%', minHeight: 140, borderRadius: 16, border: '1px dashed rgba(255,255,255,.3)', background: 'rgba(255,255,255,.08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: 20, fontSize: 14, lineHeight: 1.5 }}>
              {tab === 'foryou' ? T('Chưa có gợi ý. Trả lời vài câu hỏi trong Tài khoản › Sở thích sự kiện.', 'No picks yet. Answer a few questions in Account › Event preferences.')
                : tab === 'tonight' ? T('Tối nay chưa có sự kiện nào.', 'Nothing on tonight.') : T('Cuối tuần này chưa có sự kiện nào.', 'Nothing on this weekend.')}
            </div>
          )}
        </div>
        <div aria-hidden style={{ display: 'flex', justifyContent: 'center', gap: 6, padding: '16px 0 18px' }}>
          {list.map((e, i) => <i key={e.key} style={{ width: i === idx ? 30 : 20, height: 3, borderRadius: 2, background: i === idx ? '#fff' : 'rgba(255,255,255,.32)', transition: 'width .2s' }} />)}
        </div>
      </div>
    </section>
  );
}
