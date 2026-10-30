// Simple Shell (switch simple_shell, note 66): the Home header's "Going out | Hosting" segmented switch.
// Mode = organizer mode (the same preference Account's toggle and the set_organizer_mode RPC own); nothing new is
// stored. Going out turns organizer mode off. Hosting: a guest gets the contextual sign-in prompt; a signed-in account
// turns organizer mode on through the existing toggle, which is also the "Start hosting · free" flow (first activation
// opens the host setup sheet).
import { useCallback, useRef } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { ink, paper, surface2, ink2 } from '../../theme.js';

/** Shared with the centre "+" sheet's "Host an event" row. */
export function useStartHosting() {
  const { state: s, promptSignIn, toggleOrganizerMode } = useBanBe();
  return useCallback(() => {
    if (!s.user) { promptSignIn('host'); return; }
    if (!s.organizerMode) toggleOrganizerMode();
  }, [s.user, s.organizerMode, promptSignIn, toggleOrganizerMode]);
}

export default function HomeModeSwitch() {
  const { state: s, T, toggleOrganizerMode } = useBanBe();
  const startHosting = useStartHosting();
  const mode = s.organizerMode ? 'host' : 'goer';
  const refs = useRef({});
  const pick = (m) => {
    if (m === mode || s.organizerModeBusy) return;
    if (m === 'goer') toggleOrganizerMode();
    else startHosting();
  };
  const segments = [
    { key: 'goer', label: T('Đi chơi', 'Going out'), testId: 'home-mode-goer' },
    { key: 'host', label: T('Tổ chức', 'Hosting'), testId: 'home-mode-host' },
  ];
  // Arrow keys move between the two radios (WAI-ARIA radio group); the move also selects, like a native radio.
  const onKeyDown = (e) => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) return;
    e.preventDefault();
    const next = mode === 'goer' ? 'host' : 'goer';
    refs.current[next]?.focus();
    pick(next);
  };
  return (
    <div role="radiogroup" aria-label={T('Chế độ', 'Mode')} data-testid="home-mode-switch" onKeyDown={onKeyDown}
      aria-busy={s.organizerModeBusy || undefined}
      style={{ display: 'flex', alignItems: 'stretch', padding: 2, gap: 2, borderRadius: 999, background: surface2, flex: '0 1 auto', minWidth: 0 }}>
      {segments.map((seg, i) => {
        const on = mode === seg.key;
        return (
          <button key={seg.key} ref={(el) => { refs.current[seg.key] = el; }} type="button" role="radio" aria-checked={on}
            aria-label={T(`${seg.label}, ${i + 1} trên 2`, `${seg.label}, ${i + 1} of 2`)}
            tabIndex={on ? 0 : -1} onClick={() => pick(seg.key)} data-testid={seg.testId} className="bb-press"
            style={{
              minHeight: 44, padding: '0 14px', borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit',
              fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis',
              background: on ? ink : 'transparent', color: on ? paper : ink2,
              transition: 'background-color .18s ease, color .18s ease',
            }}>
            {seg.label}
          </button>
        );
      })}
    </div>
  );
}
