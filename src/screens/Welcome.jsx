// Public welcome — web twin of iOS WelcomeView (notes 44 + 48). The first screen a signed-out visitor sees after the
// splash (and language/theme on a first visit): one headline, one sentence, "Explore events" (read-only guest
// browsing), "Create an account", and an equally visible one-tap "Log in". An optional two-page "How banbe works"
// story never auto-advances; once opened, its link is de-emphasised on later visits.
import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, inkButton } from '../theme.js';
import { track } from '../lib/analytics.js';
import { EVENTS } from '../data/events.js';

const GOLD = '#CC9E29';
// iOS WelcomeIllustration: three catalogue photos fanned out, the real For You chip below. No motion.
function WelcomeIllustration({ T }) {
  const photos = EVENTS.slice(0, 3).map(e => e.img);
  return (
    <div aria-hidden style={{ position: 'relative', height: 200, marginTop: 12 }}>
      {photos.map((src, i) => (
        <div key={i} style={{ position: 'absolute', left: '50%', top: '50%', width: 116, height: 150, marginLeft: -58, marginTop: -75, borderRadius: 18, overflow: 'hidden',
          transform: `translate(${(i - 1) * 78}px, ${i === 1 ? -6 : 8}px) rotate(${(i - 1) * 7}deg)`, zIndex: i === 1 ? 1 : 0,
          boxShadow: '0 4px 20px rgba(0,0,0,0.12)', background: `center / cover no-repeat url(${src})` }} />
      ))}
      <span style={{ position: 'absolute', left: '50%', top: '50%', transform: 'translate(-50%, 72px)', zIndex: 2, display: 'inline-flex', alignItems: 'center', gap: 4,
        padding: '7px 12px', borderRadius: 999, background: paper, border: `1px solid ${GOLD}b3`, fontSize: 12, fontWeight: 600, color: ink, whiteSpace: 'nowrap' }}>
        <span style={{ color: GOLD, fontSize: 12 }}>★</span>{T('Dành cho bạn', 'For You')}
      </span>
    </div>
  );
}

// Story pages lead with an emoji tile (note 53: a face for each idea, not another line icon).
const STORY_EMOJI = ['🌟', '🎟️'];
const STORY_TILE_BG = ['var(--bb-honey-bg)', 'var(--bb-clay-bg)'];

const STORY_SEEN_KEY = 'banbe.publicStory.seen.v1';
const readSeen = () => { try { return localStorage.getItem(STORY_SEEN_KEY) === '1'; } catch { return false; } };
const pill = { border: '1px solid rgba(var(--bb-fg-rgb),0.12)', background: 'var(--bb-field)', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, borderRadius: 999, padding: '0 12px', minHeight: 44, cursor: 'pointer' };
// Note 53, three clearly different levels: the solid primary is the one thing to do; the secondary is a quieter
// field-filled button with a hairline (it used to be a same-size, same-weight ink outline that read as a twin);
// "Log in" is text only.
const primaryBtn = { width: '100%', minHeight: 56, borderRadius: 18, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 17, fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 };
const secondaryBtn = { width: '100%', minHeight: 50, borderRadius: 18, border: '1px solid var(--bb-rule)', background: 'var(--bb-field)', color: ink, fontFamily: 'inherit', fontSize: 15.5, fontWeight: 600, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 };

export default function Welcome() {
  const { state: s, T, toggleLang, toggleTheme, browseAsGuest, openAuth } = useBanBe();
  const [page, setPage] = useState(null); // null = welcome; 0/1 = story page
  const [seen, setSeen] = useState(readSeen);
  const pages = [
    { title: T('Gợi ý hợp với bạn', 'Picks that fit you'), body: T('Sau khi đăng ký, trả lời tối đa 5 câu hỏi (không bắt buộc). banbe gắn sao ★ Dành cho bạn cho những sự kiện phù hợp. Câu trả lời chỉ bạn thấy.', 'After you sign up, answer up to 5 optional questions. banbe stars ★ For You on the events that fit. Only you see your answers.') },
    { title: T('Giữ chỗ và theo dõi kế hoạch', 'Hold a seat, keep your plans'), body: T('Giữ chỗ, thanh toán trực tiếp cho host và nhận vé QR khi host xác nhận. Kế hoạch của bạn hiện trong Lịch.', 'Hold a seat, pay the host directly and get a QR ticket once they confirm. Your plans show up in Schedule.') },
  ];
  useEffect(() => { if (page === pages.length - 1) track('public_story_completed'); }, [page, pages.length]);
  const openStory = () => {
    setPage(0);
    try { localStorage.setItem(STORY_SEEN_KEY, '1'); } catch { /* ignore */ }
    setSeen(true);
    track('public_story_opened');
  };
  const ctas = (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <button type="button" onClick={() => { track('public_entry_get_started'); browseAsGuest(); }} data-testid="welcome-explore" className="bb-press"
        style={primaryBtn}>{T('Khám phá sự kiện', 'Explore events')}<span aria-hidden>→</span></button>
      <button type="button" onClick={() => openAuth('signup', 'welcome')} data-testid="welcome-signup" className="bb-press"
        style={secondaryBtn}>
        <span aria-hidden>✨</span>{T('Tạo tài khoản', 'Create an account')}
      </button>
      <button type="button" onClick={() => { track('public_entry_login'); openAuth('login', 'welcome'); }} data-testid="welcome-login" className="bb-press"
        style={{ width: '100%', padding: 12, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 500, cursor: 'pointer', minHeight: 48 }}>
        <span style={{ opacity: 0.7 }}>{T('Đã có tài khoản? ', 'Already have an account? ')}</span>
        <span style={{ fontWeight: 700, textDecoration: 'underline', textUnderlineOffset: 3 }}>{T('Đăng nhập', 'Log in')}</span>
      </button>
    </div>
  );
  return (
    <div data-screen-label="Welcome" style={{ minHeight: '100%', background: paper, color: ink, display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 480, padding: '56px 24px 40px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {page !== null && (
            <button type="button" onClick={() => setPage(p => (p > 0 ? p - 1 : null))} aria-label={T('Quay lại', 'Back')} style={{ ...pill, background: 'none', border: 'none', fontSize: 22, padding: '0 10px' }}>‹</button>
          )}
          {page !== null && <span style={{ fontSize: 13, fontWeight: 600, opacity: 0.7 }}>{page + 1}/{pages.length}</span>}
          <span style={{ flex: 1 }} />
          <button type="button" onClick={toggleLang} data-testid="welcome-lang" style={pill}>{T('EN', 'VN')}</button>
          <button type="button" onClick={toggleTheme} data-testid="welcome-theme" style={pill}>{s.theme === 'dark' ? T('Sáng', 'Light') : T('Tối', 'Dark')}</button>
          {page !== null && (
            <button type="button" onClick={() => { track('public_story_skipped', { step: page }); setPage(null); }} style={{ ...pill, background: 'none', border: 'none', fontSize: 15 }}>{T('Bỏ qua', 'Skip')}</button>
          )}
        </div>

        {page === null ? (
          <>
            <WelcomeIllustration T={T} />
            <h1 data-testid="welcome-title" style={display(34, { margin: '28px 0 0', lineHeight: 1.15 })}>{T('Tìm những buổi gặp gỡ nhỏ đáng để đi', 'Find small gatherings worth going to')}</h1>
            <p style={{ fontSize: 17, lineHeight: 1.55, margin: '10px 0 0', opacity: 0.8 }}>
              {T('Supper club, triển lãm, nhạc và pop-up quanh bạn. Giữ chỗ chỉ trong vài chạm.', 'Supper clubs, galleries, music and pop-ups near you. Hold a seat in a few taps.')}
            </p>
            <div style={{ marginTop: 30 }}>{ctas}</div>
            <button type="button" onClick={openStory} data-testid="welcome-story"
              style={{ alignSelf: 'center', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: seen ? 13 : 15, fontWeight: 600, textDecoration: 'underline', padding: '14px 0', minHeight: 44, cursor: 'pointer', marginTop: 6 }}>
              {seen ? T('Xem lại banbe hoạt động thế nào', 'How banbe works') : T('Xem banbe hoạt động thế nào', 'See how banbe works')}
            </button>
          </>
        ) : (
          <>
            <div aria-hidden style={{ marginTop: 40, width: 84, height: 84, borderRadius: 26, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 42, background: STORY_TILE_BG[page] }}>{STORY_EMOJI[page]}</div>
            <h1 style={display(32, { margin: '14px 0 0', lineHeight: 1.15 })}>{pages[page].title}</h1>
            <p style={{ fontSize: 17, lineHeight: 1.6, margin: '14px 0 0', opacity: 0.8 }}>{pages[page].body}</p>
            <div style={{ marginTop: 24 }}>
              {page < pages.length - 1 ? (
                <button type="button" onClick={() => setPage(page + 1)} data-testid="welcome-story-next" className="bb-press" style={primaryBtn}>{T('Tiếp', 'Next')}<span aria-hidden>→</span></button>
              ) : (
                ctas
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
