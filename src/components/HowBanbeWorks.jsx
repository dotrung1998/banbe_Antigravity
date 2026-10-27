// "How banbe works" story body, shared by the public Welcome screen and Help & Legal (note 63).
// Version 1 = the original emoji tile + three text points per page. Version 2 = per section, a swipeable deck of
// small demo screens: the centred one is the focus, its neighbours peek in dimmed, scaled down and blurred. The
// admin switch `onboarding_v2` (migration 201) picks the version; hosts draw their own top bar (Back, N/4, Skip).
// iOS twin: apps/ios/BanbeApp/Views/HowBanbeWorksView.swift. Copy: src/data/howItWorks.js.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { paper, ink, display } from '../theme.js';
import { EVENTS } from '../data/events.js';
import { HIW_SECTIONS, HIW_STEP_NAMES, HIW_STEP_TIPS } from '../data/howItWorks.js';
import { ChoiceRow, QUESTION_COPY } from '../screens/EventOnboarding.jsx';
import { questionOptions } from '../lib/onboardingFlow.js';
import { prefLabel, optionEmoji } from '../lib/eventPrefs.js';
import { useReducedMotion } from '../lib/useReducedMotion.js';
import ConfettiBurst from './ui/ConfettiBurst.jsx';

const GOLD = '#CC9E29';
const EASE = 'cubic-bezier(.22,1,.36,1)';
export const HIW_PAGE_COUNT = HIW_SECTIONS.length;

// Same solid primary as Welcome's "Explore events" (note 53 button levels).
const nextBtn = { width: '100%', minHeight: 56, borderRadius: 18, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 17, fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 };

function NextButton({ T, onClick }) {
  return (
    <button type="button" onClick={onClick} data-testid="welcome-story-next" className="bb-press" style={nextBtn}>
      {T('Tiếp', 'Next')}<span aria-hidden>→</span>
    </button>
  );
}

// ---------------------------------------------------------------------------------------------------------- V1

export function HowBanbeWorksV1({ T, page, onNext, finale }) {
  const sec = HIW_SECTIONS[page];
  return (
    <>
      {/* Keyed by page, so the entrance plays once per page: the tile pops, then the points rise in turn.
          .bb-story-* animations are off under prefers-reduced-motion. */}
      <div key={page}>
        <div aria-hidden className="bb-story-pop" style={{ marginTop: 40, width: 84, height: 84, borderRadius: 26, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 42, background: sec.tile }}>{sec.emoji}</div>
        <h1 style={display(32, { margin: '14px 0 0', lineHeight: 1.15 })}>{T(sec.vi, sec.en)}</h1>
        <ul data-testid="welcome-story-points" style={{ listStyle: 'none', margin: '16px 0 0', padding: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {sec.points.map(([emoji, vi, en], i) => (
            <li key={i} className="bb-story-rise" style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 10, borderRadius: 18, background: 'var(--bb-field)', animationDelay: `${700 + i * 350}ms` }}>
              <span aria-hidden style={{ flex: 'none', width: 46, height: 46, borderRadius: 14, background: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24 }}>{emoji}</span>
              <span style={{ fontSize: 16.5, fontWeight: 500, lineHeight: 1.4 }}>{T(vi, en)}</span>
            </li>
          ))}
        </ul>
      </div>
      <div style={{ marginTop: 24 }}>{page < HIW_PAGE_COUNT - 1 ? <NextButton T={T} onClick={onNext} /> : finale}</div>
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------- V2

// Owner, 2026-10-24: "large, clear, easy to read": the centred screen takes ~3/4 of the width; neighbours still peek.
const CARD_W = 'min(76vw, 330px)';
const GAP = 14;

/** Section body: title, caption of the centred screen, the deck, dots, Next (or the host's finale on the last). */
export function HowBanbeWorksV2({ T, page, onNext, onFinish, finale }) {
  const sec = HIW_SECTIONS[page];
  const [active, setActive] = useState(0);
  const [swiped, setSwiped] = useState(false);
  useEffect(() => { setActive(0); setSwiped(false); }, [page]);
  const card = sec.cards[active] || sec.cards[0];
  return (
    <div key={page} style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
      <h1 className="bb-hiw-title" style={display(32, { margin: '22px 0 0', lineHeight: 1.12 })} data-testid="hiw-title">
        <span aria-hidden style={{ marginRight: 8 }}>{sec.emoji}</span>{T(sec.vi, sec.en)}
      </h1>
      {/* Caption follows the centred screen; aria-live so a screen reader hears it after a swipe. */}
      <p key={active} aria-live="polite" className="bb-hiw-caption" data-testid="hiw-caption"
        style={{ fontSize: 16, lineHeight: 1.45, margin: '8px 0 0', color: 'rgba(var(--bb-fg-rgb),0.78)', minHeight: 46 }}>{T(card.vi, card.en)}</p>
      <Deck T={T} cards={sec.cards} active={active} onActive={i => { setActive(i); if (i > 0) setSwiped(true); }} onPast={page < HIW_PAGE_COUNT - 1 ? onNext : onFinish || null} finishing={page === HIW_PAGE_COUNT - 1} />
      <Dots T={T} count={sec.cards.length} active={active} />
      <div aria-hidden style={{ textAlign: 'center', fontSize: 12.5, fontWeight: 600, opacity: swiped ? 0 : 0.55, transition: 'opacity .4s', marginTop: 6, minHeight: 18 }}>
        {T('Vuốt để xem tiếp', 'Swipe to see more')} ⟶
      </div>
      <div style={{ marginTop: 16 }}>{page < HIW_PAGE_COUNT - 1 ? <NextButton T={T} onClick={onNext} /> : finale}</div>
    </div>
  );
}

/** The closing beat (owner, 2026-10-24): a thank-you and a warm wish once the tour is done. */
export function HowBanbeWorksThanks({ T, children }) {
  return (
    <div data-testid="hiw-thanks" style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
      <div aria-hidden className="bb-hiw-cheer" style={{ position: 'relative', marginTop: 40, width: 100, height: 100, borderRadius: 30, background: 'var(--bb-honey-bg)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 52 }}>
        🎉<ConfettiBurst />
      </div>
      <h1 className="bb-hiw-title" style={display(32, { margin: '18px 0 0', lineHeight: 1.15, animationDelay: '.3s' })}>{T('Cảm ơn bạn đã xem hết!', 'Thanks for taking the tour!')}</h1>
      <p className="bb-hiw-title" style={{ fontSize: 19, lineHeight: 1.5, margin: '12px 0 0', color: 'rgba(var(--bb-fg-rgb),0.8)', animationDelay: '.5s' }}>
        {T('Giờ bạn đã biết banbe hoạt động thế nào. Chúc bạn có những buổi tối thật ấm áp, món ngon và những người bạn mới. Hẹn gặp bạn bên bàn tiệc! 🥂',
          'Now you know how banbe works. We wish you warm evenings, good food and new friends. See you at the table! 🥂')}
      </p>
      <div style={{ marginTop: 28 }}>{children}</div>
    </div>
  );
}

function Dots({ T, count, active }) {
  return (
    <div data-testid="hiw-dots" aria-label={T(`Màn ${active + 1}/${count}`, `Screen ${active + 1} of ${count}`)}
      style={{ display: 'flex', justifyContent: 'center', gap: 6, marginTop: 14 }}>
      {Array.from({ length: count }, (_, i) => (
        <span key={i} style={{ width: i === active ? 18 : 6, height: 6, borderRadius: 3, background: ink, opacity: i === active ? 0.85 : 0.2, transition: `width .35s ${EASE}, opacity .35s` }} />
      ))}
    </div>
  );
}

/** The swipeable deck. Native scroll-snap does the swiping; each frame, every card's distance from the centre sets
 *  its scale/opacity/blur directly on the DOM (no re-render while dragging). */
function Deck({ T, cards, active, onActive, onPast, finishing }) {
  const touch = useRef(null);
  const scroller = useRef(null);
  const refs = useRef([]);
  const frame = useRef(0);
  const reduce = useReducedMotion();

  const paint = useCallback(() => {
    frame.current = 0;
    const el = scroller.current;
    if (!el) return;
    const mid = el.scrollLeft + el.clientWidth / 2;
    let best = 0, bestD = Infinity;
    refs.current.forEach((c, i) => {
      if (!c) return;
      const w = c.offsetWidth + GAP;
      const d = Math.min(Math.abs((c.offsetLeft + c.offsetWidth / 2 - mid) / w), 1);
      if (d < bestD) { bestD = d; best = i; }
      c.style.transform = reduce ? 'none' : `scale(${1 - 0.14 * d})`;
      c.style.opacity = String(1 - 0.55 * d);
      c.style.filter = reduce || d < 0.02 ? 'none' : `blur(${(3 * d).toFixed(2)}px)`;
    });
    if (best !== active) onActive(best);
  }, [active, onActive, reduce]);

  useLayoutEffect(() => { paint(); }, [paint]);
  useEffect(() => {
    const onResize = () => paint();
    window.addEventListener('resize', onResize);
    return () => { window.removeEventListener('resize', onResize); cancelAnimationFrame(frame.current); };
  }, [paint]);

  const go = i => {
    const c = refs.current[Math.max(0, Math.min(cards.length - 1, i))];
    const el = scroller.current;
    if (!c || !el) return;
    el.scrollTo({ left: c.offsetLeft + c.offsetWidth / 2 - el.clientWidth / 2, behavior: reduce ? 'auto' : 'smooth' });
  };

  const last = active === cards.length - 1;
  // On the last screen a clear left swipe continues to the next section (Next stays the main way). Owner, 2026-10-24.
  // Remember which screen was centred when the touch began: the swipe that LANDS on the last screen must not skip on.
  const onTouchStart = e => { const t = e.touches[0]; touch.current = { x: t.clientX, y: t.clientY, wasLast: last }; };
  const onTouchEnd = e => {
    const start = touch.current; touch.current = null;
    if (!start || !onPast || !start.wasLast) return;
    const t = e.changedTouches[0]; const dx = t.clientX - start.x, dy = t.clientY - start.y;
    if (dx < -60 && Math.abs(dx) > Math.abs(dy) * 1.5) onPast();
  };
  return (
    <div className="bb-hiw-deck" style={{ margin: '14px -24px 0', position: 'relative' }} onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}>
      {/* Last screen of a section: a soft grey chevron pulses at the right edge ("swipe on"). Decorative. */}
      {onPast && last && !finishing && (
        <button type="button" data-testid="hiw-next-section-hint" aria-label={T('Phần tiếp theo', 'Next section')} onClick={onPast} className="bb-hiw-hint"
          style={{ position: 'absolute', right: 6, top: '50%', marginTop: -32, width: 30, height: 64, borderRadius: 15, border: 'none', zIndex: 2, cursor: 'pointer',
            background: 'rgba(var(--bb-fg-rgb),0.06)', color: 'rgba(var(--bb-fg-rgb),0.4)', fontSize: 26, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0 }}>›</button>
      )}
      {/* The very last screen: a clay "done" pill that hops (a springy bounce, not the grey pulse): swipe to finish. */}
      {onPast && last && finishing && (
        <button type="button" data-testid="hiw-finish-hint" aria-label={T('Hoàn tất', 'Finish')} onClick={onPast} className="bb-hiw-finish"
          style={{ position: 'absolute', right: 4, top: '50%', marginTop: -36, width: 34, height: 72, borderRadius: 17, zIndex: 2, cursor: 'pointer',
            background: 'var(--bb-clay-bg)', border: '1px solid color-mix(in srgb, var(--bb-clay) 35%, transparent)', color: 'var(--bb-clay)',
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2, padding: 0, fontWeight: 800 }}>
          <span style={{ fontSize: 14 }}>✓</span><span style={{ fontSize: 22, lineHeight: 1 }}>›</span>
        </button>
      )}
      <div ref={scroller} data-testid="hiw-deck" tabIndex={0} role="group" aria-roledescription={T('băng chuyền', 'carousel')}
        onScroll={() => { if (!frame.current) frame.current = requestAnimationFrame(paint); }}
        onKeyDown={e => {
          if (e.key === 'ArrowRight') { e.preventDefault(); if (last && onPast) onPast(); else go(active + 1); }
          if (e.key === 'ArrowLeft') { e.preventDefault(); go(active - 1); }
        }}
        className="bb-hiw-scroller"
        style={{ display: 'flex', gap: GAP, overflowX: 'auto', scrollSnapType: 'x mandatory', padding: `12px calc(50% - ${CARD_W} / 2) 40px`, marginBottom: -22, outline: 'none', WebkitOverflowScrolling: 'touch' }}>
        {cards.map((c, i) => (
          <div key={i} ref={n => { refs.current[i] = n; }} data-testid={`hiw-card-${i}`} data-active={i === active}
            aria-hidden={i !== active} onClick={() => i !== active && go(i)}
            style={{ flex: `0 0 ${CARD_W}`, aspectRatio: '10 / 13', scrollSnapAlign: 'center', borderRadius: 28, overflow: 'hidden', position: 'relative',
              background: paper, border: '1px solid var(--bb-rule)', boxShadow: '0 18px 40px rgba(0,0,0,0.13), 0 2px 6px rgba(0,0,0,0.06)',
              transition: 'box-shadow .3s', willChange: 'transform, opacity, filter', cursor: i === active ? 'default' : 'pointer' }}>
            <DemoScreen T={T} card={c} active={i === active} />
          </div>
        ))}
      </div>
    </div>
  );
}


// ---------------------------------------------------------------------------------------------- demo screens
// Small, self-contained mocks built from the catalogue (no live data, nothing is saved). The few controls inside
// (chips, ticket count, organizer switch) only change the mock. `active` starts each screen's little animation.

const vnd = n => `${n.toLocaleString('vi-VN')}₫`;
const priceOf = e => Number(String(e.price).replace(/\D/g, '')) || 0;
const shortWhen = e => String(e.when || '').replace('▪︎', '·');
const label = { fontSize: 12, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', opacity: 0.55 };
const fieldBox = { borderRadius: 14, background: 'var(--bb-field)', padding: '12px 14px', fontSize: 15, fontWeight: 500, display: 'flex', alignItems: 'center', gap: 10 };
const screenPad = { position: 'absolute', inset: 0, padding: 18, display: 'flex', flexDirection: 'column', gap: 12, boxSizing: 'border-box' };
const area = e => String(e.where || '').split('▪︎')[0].trim();
const grow = { flex: 1, minHeight: 0 };

function Photo({ src, h, r = 14, children, style, className }) {
  return <div className={className} style={{ height: h, borderRadius: r, background: `center / cover no-repeat url(${src})`, position: 'relative', flex: 'none', ...style }}>{children}</div>;
}

function ForYouChip({ T, stamp, delay = 0 }) {
  return (
    <span className={stamp ? 'bb-hiw-stamp' : undefined} style={{ display: 'inline-flex', alignItems: 'center', gap: 3, padding: '3px 8px', borderRadius: 999, background: paper,
      border: `1px solid ${GOLD}b3`, fontSize: 10.5, fontWeight: 700, color: ink, whiteSpace: 'nowrap', animationDelay: `${delay}ms` }}>
      <span style={{ color: GOLD }}>★</span>{T('Dành cho bạn', 'For You')}
    </span>
  );
}

function DemoScreen({ T, card, active }) {
  switch (card.kind) {
    case 'quiz': return <Quiz T={T} />;
    case 'stars': return <Stars T={T} active={active} />;
    case 'private': return <Private T={T} />;
    case 'tickets': return <Tickets T={T} />;
    case 'hold': return <Hold T={T} active={active} />;
    case 'pay': return <Pay T={T} />;
    case 'qr': return <Qr T={T} active={active} />;
    case 'organizer': return <Organizer T={T} />;
    case 'free': return <Free T={T} />;
    case 'direct': return <Direct T={T} active={active} />;
    case 'step': return <Step T={T} n={card.step} active={active} />;
    case 'recipe': return <Recipe T={T} active={active} />;
    case 'live': return <Live T={T} active={active} />;
    default: return null;
  }
}

// The REAL onboarding interests question (owner, 2026-10-24): the same bar, title, subtitle, ChoiceRow tiles and
// Continue as EventOnboarding's QuestionStep, laid out at phone width and scaled down into the card. Nothing saved.
const PHONE_W = 390;
function Quiz({ T }) {
  const box = useRef(null);
  const [scale, setScale] = useState(0.7);
  const [picked, setPicked] = useState(['supper', 'gallery']);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return undefined;
    const fit = () => setScale(el.clientWidth / PHONE_W);
    fit();
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(fit) : null;
    ro?.observe(el);
    return () => ro?.disconnect();
  }, []);
  const [[titleVi, titleEn], [subVi, subEn], , hero] = QUESTION_COPY.interests;
  const opts = questionOptions('interests');
  const vi = T('vi', 'en') === 'vi';
  const pct = Math.round((2 / 6) * 100);
  return (
    <div ref={box} style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
      <div style={{ width: PHONE_W, height: `${100 / scale}%`, transform: `scale(${scale})`, transformOrigin: 'top left', padding: '14px 24px 0', boxSizing: 'border-box', position: 'relative' }}>
        <div aria-hidden style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 24, width: 32 }}>‹</span>
          <div style={{ flex: 1, height: 6, borderRadius: 999, background: 'rgba(var(--bb-fg-rgb),0.12)', overflow: 'hidden' }}>
            <div style={{ width: `${pct}%`, height: '100%', background: ink, borderRadius: 999 }} />
          </div>
          <span style={{ fontSize: 12.5, fontWeight: 700, opacity: 0.7 }}>2/5</span>
          <span style={{ fontSize: 14, fontWeight: 600, opacity: 0.8 }}>{T('Bỏ qua', 'Skip')}</span>
        </div>
        <div aria-hidden style={{ fontSize: 52, lineHeight: 1, marginTop: 18 }}>{hero}</div>
        <div style={display(26, { margin: '14px 0 0', lineHeight: 1.2 })}>{T(titleVi, titleEn)}</div>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: 'rgba(var(--bb-fg-rgb),0.7)', margin: '6px 0 0' }}>{T(subVi, subEn)}</p>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginTop: 22 }}>
          {opts.map(o => (
            <ChoiceRow key={o.id} tile testId={`hiw-quiz-${o.id}`} title={prefLabel(o.id, opts, vi)} emoji={optionEmoji(o.id)}
              selected={picked.includes(o.id)}
              onClick={() => setPicked(p => (p.includes(o.id) ? p.filter(x => x !== o.id) : [...p, o.id]))} />
          ))}
        </div>
        <div aria-hidden style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '28px 24px 18px', background: 'linear-gradient(180deg, transparent, var(--bb-bg) 45%)' }}>
          <div style={{ minHeight: 52, borderRadius: 18, background: ink, color: paper, fontSize: 16, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{T('Tiếp tục', 'Continue')}</div>
        </div>
      </div>
    </div>
  );
}

function Stars({ T, active }) {
  const evs = [EVENTS[0], EVENTS[5], EVENTS[2]];
  return (
    <div style={{ ...screenPad, gap: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
        <div style={label}>{T('Trang chủ', 'Home')}</div><ForYouChip T={T} />
      </div>
      {evs.map((e, i) => (
        <div key={e.key} style={{ ...grow, display: 'flex', gap: 12, alignItems: 'center', borderTop: i ? '1px solid var(--bb-rule)' : 'none' }}>
          <Photo src={e.img} h={76} r={16} style={{ width: 76 }} />
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ fontSize: 16.5, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.name}</div>
            <div style={{ fontSize: 13, opacity: 0.6, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{shortWhen(e)} · {area(e)}</div>
            <div style={{ marginTop: 5, minHeight: 22 }}>
              {i !== 1 ? (active && <ForYouChip T={T} stamp delay={250 + i * 300} />) : <span style={{ fontSize: 13, fontWeight: 600, opacity: 0.75 }}>{e.price}</span>}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function Private({ T }) {
  return (
    <div style={screenPad}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 4 }}>
        <div style={{ width: 78, height: 78, borderRadius: 24, background: 'var(--bb-honey-bg)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 40, flex: 'none' }}>🔒</div>
        <div><div style={display(24)}>{T('Câu trả lời', 'Your answers')}</div><div style={{ fontSize: 14, opacity: 0.65 }}>{T('Riêng tư, chỉ mình bạn', 'Private, just for you')}</div></div>
      </div>
      <div style={{ ...fieldBox, ...grow }}>🙈 {T('Host không bao giờ thấy', 'Hosts never see them')}</div>
      <div style={{ ...fieldBox, ...grow }}>✏️ {T('Đổi trong Tài khoản', 'Change them in Account')}</div>
      <div style={{ ...fieldBox, ...grow }}>⭐ {T('Chỉ dùng để gắn ★ cho bạn', 'Only used to star picks for you')}</div>
    </div>
  );
}

function Tickets({ T }) {
  const e = EVENTS[0];
  const [n, setN] = useState(2);
  return (
    <div style={{ ...screenPad, padding: 0 }}>
      <Photo src={e.img} h="44%" r={0} />
      <div style={{ padding: '12px 16px 16px', display: 'flex', flexDirection: 'column', gap: 10, flex: 1 }}>
        <div>
          <div style={{ fontSize: 15.5, fontWeight: 700 }}>{e.name}</div>
          <div style={{ fontSize: 12, opacity: 0.6 }}>{shortWhen(e)} · {vnd(priceOf(e))}</div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {[1, 2, 3].map(k => (
            <button key={k} type="button" data-testid={`hiw-tickets-${k}`} aria-pressed={n === k} onClick={ev => { ev.stopPropagation(); setN(k); }}
              style={{ flex: 1, fontFamily: 'inherit', fontSize: 14, fontWeight: 700, padding: '8px 0', borderRadius: 12, cursor: 'pointer', color: n === k ? paper : ink,
                background: n === k ? ink : 'var(--bb-field)', border: 'none', transition: `all .25s ${EASE}` }}>{k} {T('vé', k === 1 ? 'ticket' : 'tickets')}</button>
          ))}
        </div>
        <div style={{ marginTop: 'auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={{ fontSize: 11, opacity: 0.55 }}>{T('Tổng', 'Total')}</div>
            <div key={n} className="bb-hiw-caption" style={{ fontSize: 18, fontWeight: 800 }}>{vnd(priceOf(e) * n)}</div>
          </div>
          <span style={{ padding: '10px 14px', borderRadius: 14, background: 'var(--bb-clay)', color: '#fff', fontSize: 13, fontWeight: 700 }}>{T('Giữ chỗ', 'Hold seats')}</span>
        </div>
      </div>
    </div>
  );
}

function useCountdown(active, from) {
  const [left, setLeft] = useState(from);
  useEffect(() => {
    if (!active) { setLeft(from); return undefined; }
    const id = setInterval(() => setLeft(l => (l > 0 ? l - 1 : from)), 1000);
    return () => clearInterval(id);
  }, [active, from]);
  return left;
}

function Hold({ T, active }) {
  const total = 30 * 60;
  const left = useCountdown(active, total - 1);
  const r = 78, c = 2 * Math.PI * r;
  const e = EVENTS[0];
  return (
    <div style={{ ...screenPad, alignItems: 'center' }}>
      <div style={label}>{T('Đang giữ chỗ cho bạn', 'Seat held for you')}</div>
      <div style={{ ...grow, display: 'flex', alignItems: 'center' }}>
        <div style={{ position: 'relative', width: 180, height: 180 }}>
          <svg width="180" height="180" viewBox="0 0 180 180" aria-hidden>
            <circle cx="90" cy="90" r={r} fill="none" stroke="var(--bb-field)" strokeWidth="14" />
            <circle cx="90" cy="90" r={r} fill="none" stroke="var(--bb-clay)" strokeWidth="14" strokeLinecap="round"
              strokeDasharray={c} strokeDashoffset={c * (1 - left / total)} transform="rotate(-90 90 90)" style={{ transition: 'stroke-dashoffset 1s linear' }} />
          </svg>
          <div data-testid="hiw-hold-clock" style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 38, fontWeight: 800, fontVariantNumeric: 'tabular-nums' }}>{String(Math.floor(left / 60)).padStart(2, '0')}:{String(left % 60).padStart(2, '0')}</span>
            <span style={{ fontSize: 13, fontWeight: 600, opacity: 0.55 }}>{T('còn lại', 'left')}</span>
          </div>
        </div>
      </div>
      <div style={{ ...fieldBox, width: '100%', boxSizing: 'border-box' }}>
        <Photo src={e.img} h={40} r={10} style={{ width: 40 }} />
        <div style={{ minWidth: 0 }}><div style={{ fontWeight: 700 }}>{e.name}</div><div style={{ fontSize: 12.5, opacity: 0.65 }}>{T('2 vé · thanh toán trước khi hết giờ', '2 tickets · pay before time runs out')}</div></div>
      </div>
    </div>
  );
}

function Pay({ T }) {
  const e = EVENTS[0];
  return (
    <div style={screenPad}>
      <div style={label}>{T('Chuyển khoản cho host', 'Transfer to the host')}</div>
      <div style={{ borderRadius: 20, padding: 18, color: '#fff', background: 'linear-gradient(135deg, #2b2a28, #55514a)', boxShadow: '0 10px 24px rgba(0,0,0,0.18)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13.5, fontWeight: 600, opacity: 0.75 }}><span>{e.orgName || e.host}</span><span>🏦</span></div>
        <div style={{ fontSize: 19, fontWeight: 700, marginTop: 6, letterSpacing: 1 }}>VCB •••• 6543</div>
        <div style={{ fontSize: 30, fontWeight: 800, marginTop: 10 }}>{vnd(priceOf(e) * 2)}</div>
      </div>
      <div style={fieldBox}><span style={{ opacity: 0.6 }}>{T('Nội dung', 'Note')}</span><b>BB-4821</b><span style={{ marginLeft: 'auto', opacity: 0.55 }}>⧉</span></div>
      <div style={{ ...fieldBox, background: 'var(--bb-clay-bg)' }}>⏱️ {T('Chỗ còn giữ 28:41', 'Seat still held 28:41')}</div>
      <div style={{ marginTop: 'auto', textAlign: 'center', padding: '14px 0', borderRadius: 15, background: ink, color: paper, fontSize: 16, fontWeight: 700 }}>
        {T('Tôi đã chuyển khoản', "I've transferred")}
      </div>
    </div>
  );
}

// A fixed, made-up QR-like pattern (finder squares + noise). Not a real code.
const QR_BITS = Array.from({ length: 121 }, (_, i) => ((i * 7919) % 13) % 3 === 0);
function Qr({ T, active }) {
  const finder = (x, y) => (x < 3 && y < 3) || (x > 7 && y < 3) || (x < 3 && y > 7);
  return (
    <div style={{ ...screenPad, alignItems: 'center' }}>
      <div style={label}>{T('Vé của bạn', 'Your ticket')}</div>
      <div style={{ padding: 12, borderRadius: 18, background: '#fff', boxShadow: '0 6px 20px rgba(0,0,0,0.10)' }}>
        <svg width="132" height="132" viewBox="0 0 11 11" aria-hidden shapeRendering="crispEdges">
          {QR_BITS.map((b, i) => { const x = i % 11, y = Math.floor(i / 11); return (finder(x, y) ? (x % 2 === 0 || y % 2 === 0) : b) && <rect key={i} x={x} y={y} width="1" height="1" fill="#1d1c1a" />; })}
        </svg>
      </div>
      <div style={{ fontSize: 14, fontWeight: 700 }}>{EVENTS[0].name}</div>
      <div style={{ marginTop: 'auto', width: '100%', display: 'flex', gap: 6 }}>
        {['T5', 'T6', 'T7', 'CN'].map((d, i) => (
          <div key={d} style={{ flex: 1, borderRadius: 12, background: i === 2 ? 'var(--bb-honey-bg)' : 'var(--bb-field)', padding: '8px 0', textAlign: 'center', fontSize: 12, fontWeight: 600 }}>
            {T(d, ['Thu', 'Fri', 'Sat', 'Sun'][i])}
            <div style={{ height: 8, display: 'flex', justifyContent: 'center', marginTop: 4 }}>
              {i === 2 && active && <span className="bb-hiw-stamp" style={{ width: 8, height: 8, borderRadius: 4, background: 'var(--bb-clay)', animationDelay: '500ms' }} />}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Organizer({ T }) {
  const [on, setOn] = useState(false);
  const row = { display: 'flex', alignItems: 'center', gap: 10, padding: '0 12px', minHeight: 46, fontSize: 14, fontWeight: 600 };
  const icon = { width: 24, textAlign: 'center', fontSize: 16 };
  const chev = <span style={{ marginLeft: 'auto', opacity: 0.35, fontSize: 14 }}>›</span>;
  const tool = (e, vi, en) => (
    <div style={{ flex: 1, borderRadius: 10, padding: '8px 0', textAlign: 'center', fontSize: 11, fontWeight: 600, background: `rgba(var(--bb-bg-rgb),${on ? 0.9 : 0.5})`, opacity: on ? 1 : 0.45, transition: 'all .35s' }}>
      <div style={{ fontSize: 16 }}>{e}</div>{T(vi, en)}
    </div>
  );
  return (
    <div style={{ ...screenPad, gap: 12 }}>
      <div style={label}>{T('Tài khoản', 'Account')}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <img src="/banbe-favicon.png" alt="" style={{ width: 40, height: 40, borderRadius: 20, objectFit: 'cover' }} />
        <div>
          <div style={{ fontSize: 15, fontWeight: 700 }}>{T('Bạn', 'You')}</div>
          <div style={{ fontSize: 12, opacity: 0.6 }}>{on ? T('Cá nhân · Host', 'Personal · Host') : T('Cá nhân', 'Personal')}</div>
        </div>
      </div>
      <div style={{ borderRadius: 16, background: 'var(--bb-field)', overflow: 'hidden' }}>
        <div style={row}><span style={icon}>👤</span>{T('Hồ sơ', 'Profile')}{chev}</div>
        <div style={{ ...row, borderTop: '1px solid var(--bb-rule)' }}>
          <span style={icon}>🎤</span><span style={{ whiteSpace: 'nowrap' }}>{T('Chế độ tổ chức', 'Organizer mode')}</span>
          <button type="button" role="switch" aria-checked={on} data-testid="hiw-organizer-switch" onClick={ev => { ev.stopPropagation(); setOn(v => !v); }}
            style={{ marginLeft: 'auto', flex: 'none', width: 50, height: 30, borderRadius: 15, border: 'none', padding: 3, cursor: 'pointer', background: on ? 'var(--bb-clay)' : 'rgba(var(--bb-fg-rgb),0.18)', transition: `background .3s ${EASE}` }}>
            <span style={{ display: 'block', width: 24, height: 24, borderRadius: 12, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)', transform: `translateX(${on ? 20 : 0}px)`, transition: `transform .35s ${EASE}` }} />
          </button>
        </div>
        <div style={{ ...row, borderTop: '1px solid var(--bb-rule)' }}><span style={icon}>💬</span>{T('Trợ giúp', 'Help')}{chev}</div>
      </div>
      <div style={{ marginTop: 'auto', borderRadius: 16, padding: 12, background: on ? 'var(--bb-clay-bg)' : 'var(--bb-field)', border: `1px dashed rgba(var(--bb-fg-rgb),${on ? 0 : 0.15})`, transition: 'background .35s' }}>
        <div style={{ fontSize: 12.5, fontWeight: 700, opacity: on ? 1 : 0.55, marginBottom: 8 }}>{on ? T('✨ Đã mở công cụ host', '✨ Host tools on') : T('Công cụ host', 'Host tools')}</div>
        <div style={{ display: 'flex', gap: 6 }}>{tool('➕', 'Tạo', 'Create')}{tool('👥', 'Khách', 'Guests')}{tool('📷', 'Soát vé', 'Check-in')}</div>
      </div>
    </div>
  );
}

function Free({ T }) {
  return (
    <div style={{ ...screenPad, background: 'linear-gradient(180deg, var(--bb-honey-bg), transparent 55%)' }}>
      <div style={label}>{T('Phí cho host', 'Host fees')}</div>
      <div style={{ ...grow, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
        <div style={display(80, { lineHeight: 1, letterSpacing: -2 })}>0₫</div>
        <div style={{ fontSize: 15, fontWeight: 600, opacity: 0.7 }}>{T('để đăng và bán vé', 'to list and sell tickets')}</div>
      </div>
      <div style={fieldBox}><span>{T('Phí đăng', 'Listing fee')}</span><b style={{ marginLeft: 'auto' }}>0₫</b></div>
      <div style={fieldBox}><span>{T('Phí giao dịch', 'Transaction fee')}</span><b style={{ marginLeft: 'auto' }}>0₫</b></div>
      <div style={{ ...fieldBox, background: 'var(--bb-clay-bg)' }}><span>{T('Bạn nhận', 'You receive')}</span><b style={{ marginLeft: 'auto' }}>100%</b></div>
    </div>
  );
}

// Guest → host money flow, top to bottom, with banbe standing aside (its real favicon, owner 2026-10-24).
function Direct({ T, active }) {
  const amount = vnd(priceOf(EVENTS[0]) * 2);
  const person = (emoji, bg, name, detail) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <div style={{ width: 44, height: 44, borderRadius: 22, background: bg, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22, flex: 'none' }}>{emoji}</div>
      <div><div style={{ fontSize: 14, fontWeight: 700 }}>{name}</div><div style={{ fontSize: 12, opacity: 0.65 }}>{detail}</div></div>
    </div>
  );
  return (
    <div style={{ ...screenPad, gap: 0 }}>
      <div style={{ ...label, marginBottom: 12 }}>{T('Tiền đi thẳng', 'Money goes direct')}</div>
      {person('🙋', 'var(--bb-field)', T('Khách', 'Guest'), T(`Chuyển khoản ${amount}`, `Transfers ${amount}`))}
      <div style={{ flex: 1, width: 44, position: 'relative', margin: '4px 0', display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: 2, height: '100%', background: 'rgba(var(--bb-fg-rgb),0.15)' }} />
        {active && <span className="bb-hiw-flow-down" style={{ position: 'absolute', left: 12, fontSize: 18 }}>💸</span>}
      </div>
      {person('🎤', 'var(--bb-clay-bg)', T('Bạn (host)', 'You (host)'), T(`Nhận đủ ${amount}`, `Receives all ${amount}`))}
      <div style={{ ...fieldBox, marginTop: 14, display: 'flex', alignItems: 'center', gap: 10 }}>
        <img src="/banbe-favicon.png" alt="" style={{ width: 36, height: 36, borderRadius: 18, objectFit: 'cover', outline: '1.5px dashed rgba(var(--bb-fg-rgb),0.35)', outlineOffset: 3, flex: 'none' }} />
        <div><div style={{ fontWeight: 700 }}>banbe · 0₫</div><div style={{ fontSize: 12, opacity: 0.65 }}>{T('Chỉ kết nối, không giữ tiền', 'Connects you, never holds money')}</div></div>
      </div>
    </div>
  );
}

function Ring({ value, size = 54 }) {
  const r = size / 2 - 4, c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--bb-field)" strokeWidth="6" />
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--bb-clay)" strokeWidth="6" strokeLinecap="round"
        strokeDasharray={c} strokeDashoffset={c * (1 - value)} transform={`rotate(-90 ${size / 2} ${size / 2})`} style={{ transition: `stroke-dashoffset .9s ${EASE}` }} />
    </svg>
  );
}

function Step({ T, n, active }) {
  const e = EVENTS[n % EVENTS.length];
  const [vi, en] = HIW_STEP_NAMES[n - 1];
  const col = { display: 'flex', flexDirection: 'column', gap: 10 };
  const body = {
    1: <div style={col}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><img src="/banbe-favicon.png" alt="" style={{ width: 52, height: 52, borderRadius: 26, objectFit: 'cover' }} />
        <div><div style={{ fontSize: 16.5, fontWeight: 700 }}>{e.orgName}</div><div style={{ fontSize: 13, opacity: 0.6 }}>Host</div></div></div>
      <div style={fieldBox}>📝 <span style={{ opacity: 0.75 }}>{T('Giới thiệu ngắn về bạn', 'A line about you')}</span></div>
      <div style={fieldBox}>📸 <span style={{ opacity: 0.75 }}>{e.orgIg || '@banbe.host'}</span></div></div>,
    2: <div style={col}><div style={fieldBox}><b>{e.name}</b></div>
      <div style={{ display: 'flex', gap: 6 }}>{[['🍽️', 'Supper club'], ['🎨', T('Nghệ thuật', 'Art')]].map(([em, t], i) => (
        <span key={t} style={{ fontSize: 13.5, fontWeight: 600, padding: '8px 10px', borderRadius: 999, whiteSpace: 'nowrap', background: i === 0 ? 'var(--bb-honey-bg)' : 'var(--bb-field)', border: `1.5px solid ${i === 0 ? ink : 'transparent'}` }}>{em} {t}</span>))}</div>
      <div style={fieldBox}><span style={{ opacity: 0.75 }}>{T('Bữa tối 6 món, 12 khách quanh một bàn dài.', 'A 6-course dinner, 12 guests at one long table.')}</span></div></div>,
    3: <div style={col}><div style={fieldBox}>📅 {shortWhen(e)}</div><div style={fieldBox}>📍 {area(e)}</div><div style={fieldBox}>⏳ {T('Khoảng 3 giờ', 'About 3 hours')}</div></div>,
    4: <div style={col}><div style={fieldBox}><span>{T('Giá', 'Price')}</span><b style={{ marginLeft: 'auto' }}>{vnd(priceOf(e))}</b></div>
      <div style={fieldBox}><span>{T('Số chỗ', 'Seats')}</span><b style={{ marginLeft: 'auto' }}>−&nbsp;&nbsp; 14 &nbsp;&nbsp;+</b></div>
      <div style={fieldBox}><span>{T('Hoàn tiền', 'Refunds')}</span><b style={{ marginLeft: 'auto' }}>{T('Trước 48 giờ', 'Up to 48h before')}</b></div></div>,
    5: <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>{[0, 1, 2, 4].map((k, i) => <Photo key={k} src={EVENTS[k].img} h={92} r={14} className={active ? 'bb-hiw-stamp' : undefined} style={{ animationDelay: `${i * 120}ms` }} />)}</div>,
  }[n];
  return (
    <div style={screenPad}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ position: 'relative' }}>
          <Ring value={active ? n / 5 : (n - 1) / 5} />
          <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, fontWeight: 800 }}>{n}/5</span>
        </div>
        <div><div style={label}>{T(`Bước ${n}`, `Step ${n}`)}</div><div style={display(23)}>{T(vi, en)}</div></div>
      </div>
      <div style={grow}>{body}</div>
      {n < 5 && (
        <div className={active ? 'bb-hiw-caption' : undefined} style={{ borderRadius: 14, background: 'var(--bb-honey-bg)', padding: '12px 14px', fontSize: 14, fontWeight: 600, lineHeight: 1.35, animationDelay: '400ms' }}>
          💡 {T(...HIW_STEP_TIPS[n - 1])}
        </div>
      )}
      <div style={{ display: 'flex', gap: 4 }}>
        {HIW_STEP_NAMES.map((_, i) => <span key={i} style={{ flex: 1, height: 5, borderRadius: 3, background: i < n ? 'var(--bb-clay)' : 'var(--bb-field)', transition: 'background .4s' }} />)}
      </div>
    </div>
  );
}

function Recipe({ T, active }) {
  const items = [['📸', 'Ảnh rõ, sáng', 'Bright, clear photos'], ['🕖', 'Giờ đẹp cuối tuần', 'A good weekend slot'], ['💬', 'Lời mời ấm áp', 'A warm opening line'], ['💰', 'Giá hợp khu vực', 'A fair local price']];
  return (
    <div style={{ ...screenPad, gap: 10 }}>
      <div style={label}>🧑‍🍳 {T('Công thức thành công', 'Recipe for success')}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}><span style={display(30)}>8/10</span><span style={{ fontSize: 14, fontWeight: 600, opacity: 0.65 }}>{T('nguyên liệu', 'ingredients')}</span></div>
      <div style={{ height: 14, borderRadius: 7, background: 'var(--bb-field)', overflow: 'hidden', flex: 'none' }}>
        <div style={{ height: '100%', width: active ? '80%' : '10%', borderRadius: 7, background: 'linear-gradient(90deg, var(--bb-honey), var(--bb-clay))', transition: `width 1.6s ${EASE} .2s` }} />
      </div>
      {items.map(([e, vi, en], i) => (
        <div key={i} style={{ ...fieldBox, ...grow }}>
          <span>{e}</span><span style={{ flex: 1 }}>{T(vi, en)}</span>
          {active && <span className="bb-hiw-stamp" style={{ color: 'var(--bb-clay)', fontWeight: 800, fontSize: 16, animationDelay: `${400 + i * 220}ms` }}>✓</span>}
        </div>
      ))}
    </div>
  );
}

function Live({ T, active }) {
  const steps = [['Đã gửi', 'Submitted'], ['banbe đang duyệt', 'banbe reviewing'], ['Đang mở bán', 'Live']];
  return (
    <div style={screenPad}>
      <div style={{ ...grow, borderRadius: 16, background: `center / cover no-repeat url(${EVENTS[0].img})`, position: 'relative' }}>
        {active && <span className="bb-hiw-stamp" style={{ position: 'absolute', top: 10, left: 10, display: 'inline-flex', alignItems: 'center', gap: 6, padding: '5px 11px', borderRadius: 999, background: paper, fontSize: 13, fontWeight: 800, animationDelay: '1300ms' }}>
          <span className="bb-hiw-pulse" style={{ width: 9, height: 9, borderRadius: 5, background: '#3c9a5f' }} />{T('Đang mở', 'Live')}
        </span>}
      </div>
      {steps.map(([vi, en], i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 16, fontWeight: 600 }}>
          <span className={active ? 'bb-hiw-stamp' : undefined} style={{ width: 26, height: 26, borderRadius: 13, flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13,
            background: i === 2 ? '#3c9a5f' : 'var(--bb-clay)', color: '#fff', animationDelay: `${200 + i * 500}ms` }}>✓</span>
          {T(vi, en)}
        </div>
      ))}
    </div>
  );
}
