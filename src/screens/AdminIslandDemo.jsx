import { useEffect, useRef, useState } from 'react';
import { dynaura } from 'dynaura';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, ink3, rule, display, fieldGlass, inkButton } from '../theme.js';
import { ISLAND_CASES, ISLAND_CASE_GROUPS } from '../lib/islandCases.js';
import { islandEnabled, islandTheme, islandThemeVars } from '../lib/islandPrefs.js';
import { useIslandPrefs } from '../lib/useIslandPrefs.js';
import { IslandRealityNote, IslandThemeSwatches } from '../components/island/IslandThemeSwatches.jsx';

// Admin › Review & moderation › Dynamic Island demo (note 101, switch island_toasts). Every case dynaura can show,
// one tap each, on the real island — sample copy only, nothing saved and nothing sent. The demo has its own style
// picker so a style can be shown to a colleague without changing that admin's saved preference.
function SeatMeter({ T }) {
  return (
    <div style={{ padding: '14px 16px', minWidth: 232 }}>
      <div aria-hidden style={{ display: 'flex', gap: 4, marginBottom: 9 }}>
        {[0, 1, 2, 3, 4, 5, 6, 7].map(i => (
          <span key={i} style={{ flex: 1, height: 20, borderRadius: 5, background: i < 5 ? 'var(--dynaura-success)' : 'var(--dynaura-btn)' }} />
        ))}
      </div>
      <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Còn 3 chỗ', '3 seats left')}</div>
      <div style={{ fontSize: 12, color: 'var(--dynaura-muted)', marginTop: 2 }}>{T('Bếp nhà Bông · 8 chỗ', 'Bếp nhà Bông · 8 seats')}</div>
    </div>
  );
}

export default function AdminIslandDemo() {
  const { state: s, T, set } = useBanBe();
  const prefs = useIslandPrefs();
  const [themeId, setThemeId] = useState(prefs.theme);
  const [playing, setPlaying] = useState('');
  const timers = useRef([]);
  const shown = useRef(new Set());
  const allowed = s.accountType === 'admin' && islandEnabled(s.featureFlags);

  const remember = (id) => { if (id) shown.current.add(id); return id; };
  const later = (fn, ms) => {
    const id = setTimeout(() => { timers.current = timers.current.filter(x => x !== id); fn(); }, ms);
    timers.current.push(id);
    return id;
  };
  const stopAll = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
    shown.current.forEach(id => { try { dynaura.dismiss(id, 'api'); } catch { /* already gone */ } });
    shown.current.clear();
    setPlaying('');
  };

  useEffect(() => {
    if (!allowed) set({ screen: 'accountGroup', accountGroupKey: 'adminReview' });
  }, [allowed, set]);
  // Leaving the demo must never leave a sticky sample island over the rest of the app.
  useEffect(() => () => {
    timers.current.forEach(clearTimeout);
    shown.current.forEach(id => { try { dynaura.dismiss(id, 'api'); } catch { /* already gone */ } });
  }, []);

  if (!allowed) return null;

  const play = (c) => {
    // A second tap cancels the first case's pending steps (progress ticks, a promise resolving late) instead of
    // letting two sample flows patch the same island.
    timers.current.forEach(clearTimeout);
    timers.current = [];
    const pair = p => T(p[0], p[1]);
    const theme = islandTheme(themeId);
    const base = { style: islandThemeVars(themeId), className: theme.glass ? 'bb-island-glass' : undefined };
    const id = `bbdemo-${c.key}`;
    const tap = (label) => remember(dynaura.success({
      ...base, id: `${id}-tap`, duration: 1900,
      title: T('Đã nhấn', 'Tapped'), description: label,
    }));
    const button = c.action && c.key !== 'sticky' ? { title: pair(c.action), onClick: () => tap(pair(c.action)) } : undefined;
    const secondary = c.secondary ? { title: pair(c.secondary), onClick: () => tap(pair(c.secondary)) } : undefined;
    setPlaying(c.key);
    later(() => setPlaying(''), 3200);

    if (c.mode === 'toast') {
      remember(dynaura[c.type || 'info']({
        ...base, id,
        title: pair(c.title),
        description: c.description ? pair(c.description) : undefined,
        trailing: c.trailing ? pair(c.trailing) : undefined,
        duration: c.duration === null ? null : (c.duration || 4200),
        button: c.key === 'sticky' ? { title: pair(c.action), onClick: () => {} } : button,
        secondaryButton: secondary,
        confetti: !!c.confetti,
        typing: !!c.typing,
        avatar: c.avatars
          ? c.avatars.map((name, i) => ({ name, presence: i === 0 ? 'online' : i === 1 ? 'away' : 'offline' }))
          : c.avatar ? { name: c.avatar, presence: 'online' } : undefined,
        avatarMax: c.avatarMax,
      }));
      return;
    }

    if (c.mode === 'promise') {
      remember(`${id}-loading`);
      dynaura.promise(new Promise(resolve => { later(() => resolve('ok'), 1600); }), {
        loading: { ...base, id: `${id}-loading`, title: pair(c.title), duration: null },
        success: { ...base, id: `${id}-loading`, title: pair(c.successTitle), description: pair(c.successDescription), duration: 4200 },
        error: { ...base, id: `${id}-loading`, type: 'error', title: pair(c.errorTitle), duration: 4200 },
      });
      return;
    }

    if (c.mode === 'progress') {
      remember(id);
      dynaura.loading({ ...base, id, title: pair(c.title), progress: 0 });
      const step = (p) => {
        if (p >= 1) {
          dynaura.update(id, { type: 'success', title: pair(c.successTitle), progress: undefined, duration: 3500 });
          return;
        }
        dynaura.update(id, { progress: p });
        later(() => step(Math.round((p + 0.1) * 10) / 10), 180);
      };
      later(() => step(0.1), 180);
      return;
    }

    if (c.mode === 'update') {
      remember(id);
      dynaura.loading({ ...base, id, title: pair(c.title) });
      later(() => dynaura.update(id, { type: 'success', title: pair(c.successTitle), duration: 3500 }), 1600);
      return;
    }

    if (c.mode === 'live') {
      remember(dynaura.live({
        ...base, id, kind: c.liveKind || 'timer',
        title: pair(c.title), description: pair(c.description),
        button: c.action ? { title: pair(c.action), onClick: () => tap(pair(c.action)) } : undefined,
      }));
      return;
    }

    if (c.mode === 'queue') {
      const items = [
        ['Lan mời bạn vào dự án', 'Lan invited you to a project'],
        ['Minh vừa gửi ảnh', 'Minh sent photos'],
        ['Nhắc: mai có sự kiện', 'Reminder: an event tomorrow'],
      ];
      items.forEach((title, i) => {
        remember(dynaura.info({ ...base, id: `${id}-${i}`, queue: true, duration: 1400, title: T(title[0], title[1]) }));
      });
      return;
    }

    if (c.mode === 'card-ticket') {
      remember(dynaura.info({
        ...base, id, variant: 'card', duration: c.duration || 9000,
        title: pair(c.title), trailing: pair(c.trailing), button,
        description: (
          <div style={{ display: 'grid', gap: 8, minWidth: 226 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 }}>
              <b style={{ fontSize: 15 }}>{T('Bếp nhà Bông', 'Bếp nhà Bông')}</b>
              <span style={{ fontSize: 12, color: 'var(--dynaura-muted)' }}>{T('2 vé', '2 tickets')}</span>
            </div>
            <span style={{ fontSize: 12, color: 'var(--dynaura-muted)' }}>{T('T7, 22/11 · 19:00', 'Sat, 22 Nov · 19:00')}</span>
            <div style={{ borderTop: '2px dashed color-mix(in srgb, currentColor 20%, transparent)', paddingTop: 8, display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
              <span>{T('Ghế 12A · 12B', 'Seat 12A · 12B')}</span>
              <span style={{ color: 'var(--dynaura-muted)' }}>BB-4821</span>
            </div>
          </div>
        ),
      }));
      return;
    }

    if (c.mode === 'card-host') {
      remember(dynaura.info({
        ...base, id, avatarPosition: 'card', duration: c.duration || 9000,
        title: pair(c.title), description: pair(c.description), button,
        avatar: { name: T('Lan', 'Lan'), presence: 'online' },
      }));
      return;
    }

    if (c.mode === 'custom-seats') {
      remember(dynaura.custom(<SeatMeter T={T} />, { ...base, id, duration: 7000 }));
    }
  };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin island demo">
      <div style={{ padding: 'max(14px, calc(66px - var(--bb-status-trim, 0px))) 22px 0' }}>
        <button type="button" data-testid="admin-island-demo-back" onClick={() => { stopAll(); set({ screen: 'accountGroup', accountGroupKey: 'adminReview' }); }}
          style={{ border: 'none', background: 'none', padding: '8px 0', color: ink, font: 'inherit', fontSize: 15, cursor: 'pointer' }}>
          ‹ {T('Duyệt & Kiểm Duyệt', 'Review & Moderation')}
        </button>
      </div>
      <div style={{ padding: '6px 22px 44px' }}>
        <h1 style={{ ...display(27, { margin: 0 }) }} data-testid="admin-island-demo-title">{T('Bản demo Đảo Động', 'Dynamic Island demo')}</h1>
        <p style={{ fontSize: 13, lineHeight: 1.55, color: ink3, margin: '8px 0 0' }}>
          {T('Bấm từng trường hợp để xem trên đảo thật. Dữ liệu mẫu, không lưu gì và không gửi gì cho ai.', 'Tap any case to see it on the real island. Sample data; nothing is saved or sent to anyone.')}
        </p>

        <div style={{ ...fieldGlass({ marginTop: 16, padding: 16 }) }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: ink, marginBottom: 8 }}>{T('Kiểu đang xem', 'Preview style')}</div>
          <IslandThemeSwatches value={themeId} onChange={setThemeId} T={T} testId="island-demo-theme" />
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <button type="button" data-testid="island-demo-clear" onClick={stopAll}
              style={{ ...fieldGlass({ flex: 1, minHeight: 44, color: ink, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }) }}>
              {T('Xoá tất cả', 'Clear all')}
            </button>
            <button type="button" data-testid="island-demo-settings" onClick={() => { stopAll(); set({ screen: 'islandSettings' }); }}
              style={{ ...inkButton({ flex: 1, minHeight: 44, padding: '0 14px', fontSize: 13.5 }), border: 'none', fontFamily: 'inherit' }}>
              {T('Kiểu của tôi', 'My style')}
            </button>
          </div>
          <div style={{ marginTop: 12 }}><IslandRealityNote T={T} /></div>
        </div>

        {ISLAND_CASE_GROUPS.map(group => {
          const cases = ISLAND_CASES.filter(c => c.group === group.key);
          return (
            <section key={group.key} data-testid={`island-demo-group-${group.key}`} style={{ marginTop: 20 }}>
              <h2 style={{ margin: '0 0 8px', fontSize: 13, fontWeight: 700, letterSpacing: '0.02em', color: ink }}>{T(group.vi, group.en)}</h2>
              <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
                {cases.map((c, i) => (
                  <button key={c.key} type="button" data-testid={`island-demo-${c.key}`} onClick={() => play(c)}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 12, width: '100%', minHeight: 58, padding: '11px 14px',
                      border: 'none', borderTop: i === 0 ? 'none' : `1px solid ${rule}`, background: 'none',
                      color: ink, fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer',
                    }}>
                    <span style={{ flex: 1, minWidth: 0 }}>
                      <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{T(c.vi, c.en)}</span>
                      <span style={{ display: 'block', fontSize: 12, lineHeight: 1.4, color: ink3, marginTop: 2 }}>{T(c.noteVi, c.noteEn)}</span>
                    </span>
                    <span aria-hidden style={{
                      flex: 'none', width: 30, height: 30, borderRadius: '50%', display: 'grid', placeItems: 'center',
                      background: playing === c.key ? 'var(--bb-fg)' : 'rgba(var(--bb-fg-rgb),0.08)',
                      color: playing === c.key ? 'var(--bb-bg)' : ink, fontSize: 11, paddingLeft: 2,
                    }}>{playing === c.key ? '•••' : '▶'}</span>
                  </button>
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
