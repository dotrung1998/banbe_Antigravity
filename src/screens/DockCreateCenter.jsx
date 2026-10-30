// Simple Shell (switch simple_shell, note 66): the centre "+" INSIDE the dock and its bottom sheet. Shown for everyone.
// It is a button, not a tab: never selected, skipped by scrub-to-select and by the root swipe (src/lib/dockLayout.js).
//
// The sheet follows the mode, with only existing features behind every row:
//   Going out (signed in): Add to my schedule · Invite friends · Host an event. No "Post a story" (stories are host-only).
//   Hosting: Create event (primary) · Post a story (library / camera) · Share one of my events · New survey.
//   Guest: the Going out rows; each opens the contextual sign-in prompt.
// Focus moves into the sheet and stays there (Tab wraps), Escape / scrim / drag-down close it, focus returns to the "+".
// Reduce Motion: fade only.
import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useBanBe } from '../state/BanBeContext.jsx';
import { useStartHosting } from '../components/home/HomeModeSwitch.jsx';
import { useReducedMotion } from '../lib/useReducedMotion.js';
import { EVENTS } from '../data/events.js';
import { ink, paper, ink2, surface2, divider, display, RADIUS } from '../theme.js';
import { AttachMenuIcon } from './Chat.jsx';

const DISC = 48;
const ENDED_AFTER_MS = 12 * 3600000;

const Icon = ({ d, size = 20 }) => (
  <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
);
const ICONS = {
  schedule: 'M4 6.5A1.5 1.5 0 0 1 5.5 5h13A1.5 1.5 0 0 1 20 6.5v12a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5zM4 10h16M8 3v4M16 3v4M12 13v4M10 15h4',
  invite: 'M4 6h16v12H4zM4 7l8 6 8-6',
  host: 'M12 3l2.5 5.2 5.5.8-4 3.9.9 5.6L12 15.9 7.1 18.5l.9-5.6-4-3.9 5.5-.8z',
  event: 'M12 5v14M5 12h14',
  story: 'M4 8a2 2 0 0 1 2-2h1.5l1-1.5h7l1 1.5H18a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2zM12 10a3 3 0 1 0 0 6 3 3 0 0 0 0-6z',
  share: 'M12 4v11M8 8l4-4 4 4M5 13v5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-5',
  survey: 'M6 4h12v16H6zM9 9h6M9 13h6M9 17h3',
};

function Row({ icon, title, desc, onClick, testId, primary = false, expanded }) {
  return (
    <button type="button" role="menuitem" onClick={onClick} data-testid={testId} className="bb-press" aria-expanded={expanded}
      style={{
        display: 'flex', alignItems: 'center', gap: 14, width: '100%', minHeight: primary ? 64 : 56, padding: '10px 14px',
        border: 'none', borderRadius: RADIUS.tile, cursor: 'pointer', fontFamily: 'inherit', textAlign: 'left',
        background: primary ? ink : 'transparent', color: primary ? paper : ink,
      }}>
      <span aria-hidden="true" style={{ flex: 'none', width: 40, height: 40, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', background: primary ? 'rgba(var(--bb-bg-rgb),0.16)' : surface2 }}>
        <Icon d={ICONS[icon]} />
      </span>
      <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span style={{ fontSize: 16, fontWeight: 600 }}>{title}</span>
        <span style={{ fontSize: 13, opacity: primary ? 0.8 : 1, color: primary ? paper : ink2 }}>{desc}</span>
      </span>
      {expanded != null && <span aria-hidden="true" style={{ flex: 'none', fontSize: 14, color: primary ? paper : ink2, transform: expanded ? 'rotate(90deg)' : 'none' }}>›</span>}
    </button>
  );
}

function SubRow({ children, onClick, testId, icon }) {
  return (
    <button type="button" role="menuitem" onClick={onClick} data-testid={testId} className="bb-press"
      style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', minHeight: 48, padding: '8px 12px', border: 'none', borderRadius: 10, background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 14.5, textAlign: 'left', cursor: 'pointer' }}>
      {icon}
      <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{children}</span>
    </button>
  );
}

export default function DockCreateCenter() {
  const {
    state: s, set, T, goCreate, goSchedule, goDashboard, promptSignIn, shareReferral, referralLink, shareEvent,
    openStoryLibraryPicker, openStoryCameraPicker, loadRealEventsById,
  } = useBanBe();
  const startHosting = useStartHosting();
  const reduce = useReducedMotion();
  const [open, setOpen] = useState(false);
  const [sub, setSub] = useState(null); // 'story' | 'share' | null
  const [dragY, setDragY] = useState(0);
  const dragRef = useRef(null);
  const buttonRef = useRef(null);
  const sheetRef = useRef(null);

  const mode = !s.user ? 'guest' : s.organizerMode ? 'host' : 'goer';
  const hiddenByOverlay = !!(s.storyViewer || s.scanningQr || s.photoViewer || s.chatPhotoViewer || s.reasonPrompt || s.pulseOpen);

  const close = (restore = true) => {
    setOpen(false); setSub(null); setDragY(0);
    if (restore) setTimeout(() => buttonRef.current?.focus?.({ preventScroll: true }), 0);
  };
  const run = (fn) => { close(false); fn(); };

  // Focus in on open; Escape closes; Tab wraps inside the sheet.
  useEffect(() => {
    if (!open) return undefined;
    const t = setTimeout(() => sheetRef.current?.querySelector('button')?.focus({ preventScroll: true }), 0);
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); close(); return; }
      if (e.key !== 'Tab' || !sheetRef.current) return;
      const f = [...sheetRef.current.querySelectorAll('button:not([disabled])')];
      if (!f.length) return;
      const first = f[0], last = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    window.addEventListener('keydown', onKey);
    return () => { clearTimeout(t); window.removeEventListener('keydown', onKey); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);
  useEffect(() => { if (hiddenByOverlay && open) close(false); }, [hiddenByOverlay]); // eslint-disable-line react-hooks/exhaustive-deps

  // "Share one of my events": the host's own live, not-yet-ended events (same realEventsById cache Dashboard uses).
  const myKeys = s.myOrgEventKeys || [];
  const missingReal = myKeys.filter(k => !EVENTS.some(e => e.key === k) && !(k in s.realEventsById));
  useEffect(() => {
    if (open && mode === 'host' && missingReal.length) loadRealEventsById(missingReal);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, mode, missingReal.join(',')]);
  const now = Date.now();
  const shareable = myKeys.map(k => s.realEventsById[k]).filter(r => r && r.status === 'live'
    && (!r.startsAt || Date.parse(r.startsAt) + ENDED_AFTER_MS > now));

  // Drag the sheet down to dismiss; the pointer is captured only once it really moves, so taps reach the rows.
  const onPointerDown = (e) => { dragRef.current = { startY: e.clientY, pointerId: e.pointerId, dragging: false }; };
  const onPointerMove = (e) => {
    const d = dragRef.current;
    if (!d) return;
    const dy = e.clientY - d.startY;
    if (!d.dragging) { if (dy < 8) return; d.dragging = true; e.currentTarget.setPointerCapture?.(d.pointerId); }
    setDragY(Math.max(0, dy));
  };
  const onPointerUp = () => {
    const d = dragRef.current;
    dragRef.current = null;
    if (!d?.dragging) return;
    if (dragY > 70) close(); else setDragY(0);
  };

  const goerRows = [
    {
      icon: 'schedule', testId: 'dock-create-menu-schedule',
      title: T('Thêm vào lịch của tôi', 'Add to my schedule'),
      desc: T('Lưu kế hoạch và xem theo ngày.', 'Keep your plans, day by day.'),
      onClick: () => run(() => (mode === 'guest' ? promptSignIn('schedule') : goSchedule())),
    },
    {
      icon: 'invite', testId: 'dock-create-menu-invite',
      title: T('Mời bạn bè', 'Invite friends'),
      desc: T('Gửi link mời của riêng bạn.', 'Send your own invite link.'),
      onClick: () => run(() => (mode === 'guest' ? promptSignIn('invite') : referralLink ? shareReferral() : set({ screen: 'profile' }))),
    },
    {
      icon: 'host', testId: 'dock-create-menu-host',
      title: T('Tổ chức sự kiện', 'Host an event'),
      desc: T('Miễn phí. Tắt lúc nào cũng được.', 'Free. Turn it off any time.'),
      onClick: () => run(startHosting),
    },
  ];

  const sheet = open && (
    <div onClick={() => close()} data-testid="dock-create-backdrop"
      style={{ position: 'fixed', inset: 0, zIndex: 2100, background: 'rgba(12,12,12,0.45)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
      <div ref={sheetRef} role="dialog" aria-modal="true" aria-labelledby="dock-create-title" data-testid="dock-create-menu"
        onClick={(e) => e.stopPropagation()}
        onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp} onPointerCancel={onPointerUp}
        style={{
          background: paper, color: ink, borderRadius: '22px 22px 0 0', padding: '8px 12px calc(20px + env(safe-area-inset-bottom, 0px))',
          maxHeight: '86%', overflowY: 'auto', boxShadow: '0 -8px 32px rgba(0,0,0,0.18)', touchAction: 'pan-y',
          transform: dragY ? `translateY(${dragY}px)` : undefined,
          animation: reduce ? 'banbeFade 0.2s ease both' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both',
        }}>
        <div aria-hidden="true" style={{ display: 'flex', justifyContent: 'center', padding: '2px 0 8px' }}>
          <div style={{ width: 36, height: 4, borderRadius: 2, background: divider }} />
        </div>
        <h2 id="dock-create-title" style={{ ...display(20), margin: '0 6px 8px' }}>
          {mode === 'host' ? T('Tạo mới', 'Create') : T('Bạn muốn làm gì?', 'What would you like to do?')}
        </h2>
        <div role="menu" aria-labelledby="dock-create-title" style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {mode === 'host' ? (
            <>
              <Row primary icon="event" testId="dock-create-menu-event" title={T('Tạo sự kiện', 'Create event')}
                desc={T('5 bước, có thể lưu nháp.', '5 steps, save a draft any time.')} onClick={() => run(goCreate)} />
              <Row icon="story" testId="dock-create-menu-story" title={T('Đăng story', 'Post a story')}
                desc={T('Ảnh từ thư viện hoặc camera.', 'A photo from your library or camera.')}
                expanded={sub === 'story'} onClick={() => setSub(v => (v === 'story' ? null : 'story'))} />
              {sub === 'story' && (
                <div style={{ padding: '0 8px 4px 62px', display: 'flex', flexDirection: 'column' }}>
                  <SubRow testId="dock-create-menu-story-library" icon={<AttachMenuIcon name="library" />} onClick={() => run(openStoryLibraryPicker)}>{T('Thư viện ảnh', 'Photo library')}</SubRow>
                  <SubRow testId="dock-create-menu-story-camera" icon={<AttachMenuIcon name="camera" />} onClick={() => run(openStoryCameraPicker)}>{T('Camera', 'Camera')}</SubRow>
                </div>
              )}
              <Row icon="share" testId="dock-create-menu-share-event" title={T('Chia sẻ một sự kiện của tôi', 'Share one of my events')}
                desc={T('Gửi link sự kiện đang mở.', 'Send the link to a live event.')}
                expanded={shareable.length ? sub === 'share' : undefined}
                onClick={() => (shareable.length ? setSub(v => (v === 'share' ? null : 'share')) : run(() => goDashboard('home')))} />
              {sub === 'share' && (
                <div data-testid="dock-create-share-list" style={{ padding: '0 8px 4px 62px', display: 'flex', flexDirection: 'column' }}>
                  {shareable.slice(0, 6).map(r => (
                    <SubRow key={r.key} testId={`dock-create-share-${r.key}`} onClick={() => run(() => shareEvent({ key: r.key, name: r.name, where: r.area || '' }))}>{r.name}</SubRow>
                  ))}
                  {shareable.length > 6 && (
                    <SubRow testId="dock-create-share-all" onClick={() => run(() => goDashboard('home'))}>{T('Xem tất cả sự kiện', 'See all my events')} ›</SubRow>
                  )}
                </div>
              )}
              <Row icon="survey" testId="dock-create-menu-survey" title={T('Khảo sát mới', 'New survey')}
                desc={T('Hỏi khách muốn gì cho buổi tới.', 'Ask guests what they want next.')}
                onClick={() => run(() => set({ screen: 'surveysHosting', surveysHostingReturnTab: null, surveysHostingOpenCreate: true }))} />
            </>
          ) : goerRows.map(r => <Row key={r.testId} {...r} />)}
        </div>
      </div>
    </div>
  );

  const target = typeof document !== 'undefined' ? (document.querySelector('.bb-screen') || document.body) : null;
  if (hiddenByOverlay) return null;
  return (
    <>
      <button ref={buttonRef} type="button" onClick={() => setOpen(v => !v)} data-testid="dock-create-button"
        aria-label={T('Tạo mới', 'Create')} aria-haspopup="dialog" aria-expanded={open} className="bb-press"
        style={{
          width: DISC, height: DISC, minWidth: 44, minHeight: 44, borderRadius: '50%', border: 'none', padding: 0, cursor: 'pointer',
          background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 4px 12px rgba(0,0,0,0.22)', flex: 'none',
        }}>
        <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
          <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
        </svg>
      </button>
      {sheet && target && createPortal(sheet, target)}
    </>
  );
}
