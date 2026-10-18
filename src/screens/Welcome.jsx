// Public welcome — web twin of iOS WelcomeView (notes 44 + 48). The first screen a signed-out visitor sees after the
// splash (and language/theme on a first visit): one headline, one sentence, "Explore events" (read-only guest
// browsing), "Create an account", and an equally visible one-tap "Log in". An optional two-page "How banbe works"
// story never auto-advances; once opened, its link is de-emphasised on later visits.
import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, inkButton } from '../theme.js';
import { track } from '../lib/analytics.js';

const STORY_SEEN_KEY = 'banbe.publicStory.seen.v1';
const readSeen = () => { try { return localStorage.getItem(STORY_SEEN_KEY) === '1'; } catch { return false; } };
const pill = { border: 'none', background: 'var(--bb-field)', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, borderRadius: 999, padding: '8px 14px', minHeight: 36, cursor: 'pointer' };

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
      <button type="button" onClick={() => { track('public_entry_get_started'); browseAsGuest(); }} data-testid="welcome-explore"
        style={{ ...inkButton({ width: '100%', padding: 16, fontFamily: 'inherit', fontSize: 16 }) }}>{T('Khám phá sự kiện', 'Explore events')}</button>
      <button type="button" onClick={() => openAuth('signup', 'welcome')} data-testid="welcome-signup"
        style={{ width: '100%', padding: 14, borderRadius: 18, border: '1px solid rgba(var(--bb-fg-rgb),0.2)', background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
        {T('Tạo tài khoản', 'Create an account')}
      </button>
      <button type="button" onClick={() => { track('public_entry_login'); openAuth('login', 'welcome'); }} data-testid="welcome-login"
        style={{ width: '100%', padding: 12, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer', minHeight: 44 }}>
        {T('Đã có tài khoản? Đăng nhập', 'Already have an account? Log in')}
      </button>
    </div>
  );
  return (
    <div data-screen-label="Welcome" style={{ minHeight: '100%', background: paper, color: ink, display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 480, padding: '56px 24px 40px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {page !== null && (
            <button type="button" onClick={() => setPage(p => (p > 0 ? p - 1 : null))} aria-label={T('Quay lại', 'Back')} style={{ ...pill, background: 'none', fontSize: 20, padding: '4px 10px' }}>‹</button>
          )}
          {page !== null && <span style={{ fontSize: 13, fontWeight: 600, opacity: 0.7 }}>{page + 1}/{pages.length}</span>}
          <span style={{ flex: 1 }} />
          <button type="button" onClick={toggleLang} data-testid="welcome-lang" style={pill}>{T('EN', 'VN')}</button>
          <button type="button" onClick={toggleTheme} data-testid="welcome-theme" style={pill}>{s.theme === 'dark' ? T('Sáng', 'Light') : T('Tối', 'Dark')}</button>
          {page !== null && (
            <button type="button" onClick={() => { track('public_story_skipped', { step: page }); setPage(null); }} style={{ ...pill, background: 'none' }}>{T('Bỏ qua', 'Skip')}</button>
          )}
        </div>

        {page === null ? (
          <>
            <img src="/banbe-wordmark.png" alt="banbe" style={{ width: 110, height: 'auto', marginTop: 40 }} />
            <h1 data-testid="welcome-title" style={display(34, { margin: '22px 0 0', lineHeight: 1.12 })}>{T('Tìm những buổi gặp gỡ nhỏ đáng để đi', 'Find small gatherings worth going to')}</h1>
            <p style={{ fontSize: 16, lineHeight: 1.55, margin: '14px 0 0', opacity: 0.8 }}>
              {T('Supper club, triển lãm, nhạc và pop-up quanh bạn. Giữ chỗ chỉ trong vài chạm.', 'Supper clubs, galleries, music and pop-ups near you. Hold a seat in a few taps.')}
            </p>
            <button type="button" onClick={openStory} data-testid="welcome-story"
              style={{ alignSelf: 'flex-start', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: seen ? 500 : 600, textDecoration: 'underline', padding: '12px 0', minHeight: 44, cursor: 'pointer', opacity: seen ? 0.65 : 1, marginTop: 6 }}>
              {seen ? T('Xem lại banbe hoạt động thế nào', 'How banbe works') : T('Xem banbe hoạt động thế nào', 'See how banbe works')}
            </button>
            <div style={{ flex: 1, minHeight: 30 }} />
            {ctas}
          </>
        ) : (
          <>
            <h1 style={display(30, { margin: '48px 0 0', lineHeight: 1.15 })}>{pages[page].title}</h1>
            <p style={{ fontSize: 16, lineHeight: 1.6, margin: '14px 0 0' }}>{pages[page].body}</p>
            <div style={{ display: 'flex', gap: 6, marginTop: 22 }} aria-hidden>
              {pages.map((_, i) => <span key={i} style={{ width: i === page ? 22 : 8, height: 8, borderRadius: 4, background: i === page ? ink : 'rgba(var(--bb-fg-rgb),0.2)' }} />)}
            </div>
            <div style={{ flex: 1, minHeight: 30 }} />
            {page < pages.length - 1 ? (
              <button type="button" onClick={() => setPage(page + 1)} style={{ ...inkButton({ width: '100%', padding: 16, fontFamily: 'inherit' }) }}>{T('Tiếp', 'Next')}</button>
            ) : (
              ctas
            )}
          </>
        )}
      </div>
    </div>
  );
}
