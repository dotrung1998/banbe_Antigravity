// Simple Shell (switch simple_shell, note 66): the Home header's "Going out | Hosting" segmented switch.
// Follow-up (owner, 2026-10-31): the switch is a Home VIEW (`homeView`, session-only, src/lib/homeMode.js), never
// organizer mode. Going out only changes the view; organizer mode stays on. Hosting with organizer mode on shows the
// host Home; with it off the segment is LOCKED (lock glyph, muted, still focusable) and opens the Start hosting
// invitation through the shared startHosting action (guest: the sign-in prompt first). Twin of iOS HomeModeSwitch.
import { useRef } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { effectiveHomeView, hostSegmentLocked } from '../../lib/homeMode.js';
import { ink, paper, surface2, ink2, ink3 } from '../../theme.js';

const LockGlyph = () => (
  <svg aria-hidden="true" width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
    <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" />
  </svg>
);

export default function HomeModeSwitch() {
  const { state: s, T, setHomeView, startHosting } = useBanBe();
  const view = effectiveHomeView(!!s.organizerMode, s.homeView);
  const locked = hostSegmentLocked(!!s.organizerMode);
  const refs = useRef({});
  const pick = (m) => {
    if (m === 'goer') { if (view !== 'goer') setHomeView('goer'); return; }
    if (locked) { if (!s.organizerModeBusy) startHosting({ land: 'home' }); return; }
    if (view !== 'host') setHomeView('host');
  };
  const segments = [
    { key: 'goer', label: T('Đi chơi', 'Going out'), testId: 'home-mode-goer' },
    { key: 'host', label: T('Tổ chức', 'Hosting'), testId: 'home-mode-host' },
  ];
  // Arrow keys move between the two radios (WAI-ARIA radio group); the move also selects, like a native radio,
  // except onto the locked Hosting segment: focus only, Enter/Space opens the invitation.
  const onKeyDown = (e) => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) return;
    e.preventDefault();
    const current = document.activeElement === refs.current.host ? 'host' : document.activeElement === refs.current.goer ? 'goer' : view;
    const next = current === 'goer' ? 'host' : 'goer';
    refs.current[next]?.focus();
    if (!(next === 'host' && locked)) pick(next);
  };
  return (
    <div role="radiogroup" aria-label={T('Chế độ', 'Mode')} data-testid="home-mode-switch" onKeyDown={onKeyDown}
      aria-busy={s.organizerModeBusy || undefined}
      style={{ display: 'flex', alignItems: 'stretch', padding: 2, gap: 2, borderRadius: 999, background: surface2, flex: '0 1 auto', minWidth: 0 }}>
      {segments.map((seg, i) => {
        const on = view === seg.key;
        const isLocked = seg.key === 'host' && locked;
        const label = isLocked
          ? T('Tổ chức, đã khoá, chạm hai lần để bắt đầu tổ chức', 'Hosting, locked, double-tap to start hosting')
          : T(`${seg.label}, ${i + 1} trên 2`, `${seg.label}, ${i + 1} of 2`);
        return (
          <button key={seg.key} ref={(el) => { refs.current[seg.key] = el; }} type="button" role="radio" aria-checked={on}
            aria-label={label} data-locked={seg.key === 'host' ? String(isLocked) : undefined}
            aria-haspopup={isLocked ? 'dialog' : undefined}
            title={isLocked ? T('Bắt đầu tổ chức để mở', 'Start hosting to unlock') : undefined}
            tabIndex={on ? 0 : -1} onClick={() => pick(seg.key)} data-testid={seg.testId} className="bb-press"
            style={{
              minHeight: 44, padding: '0 14px', borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit',
              fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis',
              display: 'inline-flex', alignItems: 'center', gap: isLocked ? 5 : 0,
              background: on ? ink : 'transparent', color: on ? paper : isLocked ? ink3 : ink2,
              transition: 'background-color .18s ease, color .18s ease, gap .2s ease',
            }}>
            {seg.key === 'host' && (
              // Unlock: the glyph fades and scales out (0.2s); Reduce Motion = a plain crossfade (index.css).
              <span className="bb-mode-lock" data-shown={isLocked ? 'true' : 'false'} aria-hidden="true"><LockGlyph /></span>
            )}
            {seg.label}
          </button>
        );
      })}
    </div>
  );
}
