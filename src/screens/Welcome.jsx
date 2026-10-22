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
// Pages 3–4 (2026-10-21) introduce hosting and how creating an event works. iOS twin: WelcomeView.storyPages.
const STORY_EMOJI = ['🌟', '🎟️', '🎤', '🛠️'];
const STORY_TILE_BG = ['var(--bb-honey-bg)', 'var(--bb-clay-bg)', 'var(--bb-field)', 'var(--bb-honey-bg)'];

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
  // A short title and three emoji points per page instead of a paragraph (owner, 2026-10-21: "too much text").
  // iOS twin: WelcomeView.storyPages.
  const pages = [
    { title: T('Gợi ý hợp với bạn', 'Picks that fit you'), points: [
      ['✍️', T('Trả lời 5 câu ngắn, không bắt buộc', 'Answer 5 quick, optional questions')],
      ['⭐', T('banbe gắn ★ Dành cho bạn lên sự kiện hợp', 'banbe stars ★ For You on events that fit')],
      ['🔒', T('Chỉ mình bạn thấy câu trả lời', 'Only you see your answers')],
    ] },
    { title: T('Giữ chỗ trong vài chạm', 'Hold a seat in a few taps'), points: [
      ['⏱️', T('Giữ chỗ 30 phút để bạn thanh toán', 'Your seat is held 30 minutes while you pay')],
      ['💸', T('Chuyển khoản thẳng cho host', 'Pay the host directly')],
      ['📲', T('Nhận vé QR, kế hoạch hiện trong Lịch', 'Get a QR ticket, plans land in Schedule')],
    ] },
    { title: T('Tự tổ chức sự kiện', 'Host your own events'), points: [
      ['⚙️', T('Bật Chế độ tổ chức trong Tài khoản', 'Turn on Organizer mode in Account')],
      ['🆓', T('Miễn phí: không phí đăng, không phí giao dịch', 'Free: no listing or transaction fees')],
      ['🤝', T('Khách trả thẳng cho bạn, banbe không giữ tiền', 'Guests pay you, banbe never holds money')],
    ] },
    { title: T('Tạo sự kiện trong 5 bước', 'Create an event in 5 steps'), points: [
      ['📝', T('Host → Cơ bản → Thời gian & nơi → Vé → Ảnh', 'Host → Basics → When & where → Tickets → Photos')],
      ['🧑‍🍳', T('Công thức thành công gợi ý cách lấp đầy chỗ', 'The Recipe for success helps fill seats')],
      ['✅', T('banbe duyệt rồi đưa lên sóng, báo cho bạn', 'banbe reviews it, then it goes live')],
    ] },
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
            {/* Keyed by page, so the entrance plays once per page: the tile pops, then the points rise in turn.
                .bb-story-* animations are off under prefers-reduced-motion. */}
            <div key={page}>
              <div aria-hidden className="bb-story-pop" style={{ marginTop: 40, width: 84, height: 84, borderRadius: 26, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 42, background: STORY_TILE_BG[page] }}>{STORY_EMOJI[page]}</div>
              <h1 style={display(32, { margin: '14px 0 0', lineHeight: 1.15 })}>{pages[page].title}</h1>
              <ul data-testid="welcome-story-points" style={{ listStyle: 'none', margin: '16px 0 0', padding: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
                {pages[page].points.map(([emoji, text], i) => (
                  <li key={i} className="bb-story-rise" style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 10, borderRadius: 18, background: 'var(--bb-field)', animationDelay: `${700 + i * 350}ms` }}>
                    <span aria-hidden style={{ flex: 'none', width: 46, height: 46, borderRadius: 14, background: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24 }}>{emoji}</span>
                    <span style={{ fontSize: 16.5, fontWeight: 500, lineHeight: 1.4 }}>{text}</span>
                  </li>
                ))}
              </ul>
            </div>
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
