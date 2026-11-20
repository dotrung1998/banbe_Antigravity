import { useEffect, useRef } from 'react';
import { dynaura } from 'dynaura';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, ink3, rule, display, fieldGlass, inkButton, alert } from '../theme.js';
import GlassSwitch from '../components/ui/GlassSwitch.jsx';
import { useIslandPrefs } from '../lib/useIslandPrefs.js';
import { islandEnabled, islandTheme, islandThemeVars, writeIslandPrefs } from '../lib/islandPrefs.js';
import { IslandPreview, IslandRealityNote, IslandThemeSwatches } from '../components/island/IslandThemeSwatches.jsx';

// Account › Notifications › Island style (note 101, switch island_toasts). A person's own display choice, stored per
// browser (src/lib/islandPrefs.js) — never the account: this is how notifications should look on THIS phone.
// Every pick applies immediately to the one mounted Toaster and fires one preview island, so choosing is seeing.
function Choice({ label, value, options, onChange, T, testId }) {
  return (
    <div style={{ marginTop: 18 }}>
      <div style={{ fontSize: 12.5, fontWeight: 600, color: ink, marginBottom: 7 }}>{label}</div>
      <div role="radiogroup" aria-label={label} style={{ display: 'flex', gap: 4, padding: 3, borderRadius: 999, background: 'rgba(var(--bb-fg-rgb),0.06)' }}>
        {options.map(o => (
          <button key={o.v} type="button" role="radio" aria-checked={value === o.v} data-testid={`${testId}-${o.v}`}
            onClick={() => onChange(o.v)}
            style={{
              flex: 1, minHeight: 40, borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit',
              fontSize: 13, fontWeight: value === o.v ? 700 : 500, color: ink,
              background: value === o.v ? 'var(--bb-bg)' : 'transparent',
              boxShadow: value === o.v ? '0 1px 3px rgba(27,25,22,0.18)' : 'none',
            }}>
            {T(o.vi, o.en)}
          </button>
        ))}
      </div>
    </div>
  );
}

function ToggleRow({ title, sub, on, onChange, testId, disabled = false }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 0', borderTop: `1px solid ${rule}`, opacity: disabled ? 0.55 : 1 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, fontWeight: 600, color: ink }}>{title}</div>
        <div style={{ fontSize: 12.5, lineHeight: 1.45, color: ink3, marginTop: 2 }}>{sub}</div>
      </div>
      <GlassSwitch on={on} onPress={() => !disabled && onChange(!on)} testId={testId} />
    </div>
  );
}

export default function IslandSettings() {
  const { state: s, T, set } = useBanBe();
  const prefs = useIslandPrefs();
  const previewTimer = useRef(0);
  const on = islandEnabled(s.featureFlags);
  // Leaving the screen must not fire a preview over whatever screen comes next.
  useEffect(() => () => clearTimeout(previewTimer.current), []);

  const preview = (themeId = prefs.theme, detail = prefs.detail) => {
    const theme = islandTheme(themeId);
    dynaura.success({
      title: T('Đã giữ chỗ', 'Seat held'),
      description: detail === 'title' ? undefined : T('3 vé · Bếp nhà Bông · T7 19:00', '3 tickets · Bếp nhà Bông · Sat 19:00'),
      button: { title: T('Xem vé', 'View ticket'), onClick: () => {} },
      duration: 4200,
      style: islandThemeVars(themeId),
      className: theme.glass ? 'bb-island-glass' : undefined,
    });
  };
  // Save first, preview after a frame so the global Toaster already carries the new theme (the inline vars cover the
  // gap in any case).
  const apply = (patch) => {
    writeIslandPrefs(patch);
    clearTimeout(previewTimer.current);
    previewTimer.current = window.setTimeout(() => preview(patch.theme || prefs.theme, patch.detail || prefs.detail), 60);
  };

  if (!on) {
    return (
      <div style={{ minHeight: '100%', background: paper, padding: '56px 22px 0' }} data-screen-label="Island settings off">
        <button type="button" onClick={() => set({ screen: 'notifPrefs' })} style={{ border: 'none', background: 'none', padding: '8px 0', color: ink, font: 'inherit', fontSize: 15, cursor: 'pointer' }}>
          ‹ {T('Thông báo', 'Notifications')}
        </button>
        <h1 style={{ ...display(28, { margin: '10px 0 8px' }) }}>{T('Đảo Động cho thông báo', 'Dynamic Island toasts')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: alert, margin: '0 0 12px' }}>
          {T('Tính năng này đang tắt bởi quản trị viên.', 'An admin has turned this feature off.')}
        </p>
      </div>
    );
  }

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Island settings">
      <div style={{ padding: 'max(14px, calc(66px - var(--bb-status-trim, 0px))) 22px 0' }}>
        <button type="button" data-testid="island-settings-back" onClick={() => set({ screen: 'notifPrefs' })}
          style={{ border: 'none', background: 'none', padding: '8px 0', color: ink, font: 'inherit', fontSize: 15, cursor: 'pointer' }}>
          ‹ {T('Thông báo', 'Notifications')}
        </button>
      </div>
      <div style={{ padding: '6px 22px 40px' }}>
        <h1 style={{ ...display(28, { margin: 0 }) }}>{T('Đảo Động cho thông báo', 'Dynamic Island toasts')}</h1>
        <p style={{ fontSize: 13, lineHeight: 1.55, color: ink3, margin: '8px 0 0' }}>
          {T('Chọn kiểu, vị trí và chuyển động cho thông báo hiện trên đảo. Lựa chọn này chỉ lưu trên trình duyệt này.', 'Choose how notices look on the island. This choice is saved on this browser only.')}
        </p>

        <div style={{ marginTop: 16 }}>
          <IslandPreview themeId={prefs.theme} T={T} detail={prefs.detail} />
        </div>

        <div style={{ ...fieldGlass({ marginTop: 16, padding: '16px 16px 18px' }) }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: ink, marginBottom: 8 }}>{T('Kiểu', 'Style')}</div>
          <IslandThemeSwatches value={prefs.theme} onChange={(id) => apply({ theme: id })} T={T} />

          <Choice label={T('Vị trí', 'Position')} value={prefs.position} onChange={(v) => apply({ position: v })} T={T} testId="island-position"
            options={[{ v: 'top', vi: 'Trên', en: 'Top' }, { v: 'bottom', vi: 'Dưới', en: 'Bottom' }]} />
          <Choice label={T('Nội dung', 'Detail')} value={prefs.detail} onChange={(v) => apply({ detail: v })} T={T} testId="island-detail"
            options={[{ v: 'full', vi: 'Đầy đủ', en: 'Full' }, { v: 'title', vi: 'Chỉ tiêu đề', en: 'Title only' }]} />
          <Choice label={T('Chuyển động', 'Motion')} value={prefs.motion} onChange={(v) => apply({ motion: v })} T={T} testId="island-motion"
            options={[{ v: 'spring', vi: 'Nảy', en: 'Spring' }, { v: 'calm', vi: 'Nhẹ', en: 'Calm' }]} />

          <div style={{ marginTop: 16 }}>
            <ToggleRow title={T('Vuốt để đóng', 'Swipe to dismiss')} sub={T('Vuốt viên đảo lên để tắt.', 'Swipe the island up to dismiss it.')}
              on={prefs.swipe} onChange={(v) => apply({ swipe: v })} testId="island-swipe" />
            <ToggleRow title={T('Rung khi hiện', 'Haptic on show')} sub={T('iPhone Safari không hỗ trợ rung cho web; Android thì có.', 'iPhone Safari does not vibrate for web pages; Android does.')}
              on={prefs.haptics} onChange={(v) => apply({ haptics: v })} testId="island-haptics" />
          </div>

          <button type="button" data-testid="island-preview-play" onClick={() => preview()}
            style={{ ...inkButton({ width: '100%', minHeight: 48, marginTop: 16 }), border: 'none', fontFamily: 'inherit' }}>
            {T('Xem thử trên đảo', 'Preview on the island')}
          </button>
        </div>

        {s.accountType === 'admin' && (
          <button type="button" data-testid="island-settings-demo" onClick={() => set({ screen: 'adminIslandDemo' })}
            style={{ ...fieldGlass({ width: '100%', marginTop: 14, padding: '15px 16px', display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', color: ink, fontFamily: 'inherit', textAlign: 'left' }) }}>
            <span style={{ flex: 1 }}>
              <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{T('Bản demo đầy đủ', 'Full demo')}</span>
              <span style={{ display: 'block', fontSize: 12, color: ink3, marginTop: 2 }}>{T('Mọi trường hợp thông báo, để bấm thử.', 'Every notification case, one tap each.')}</span>
            </span>
            <span aria-hidden style={{ color: ink3 }}>›</span>
          </button>
        )}

        <div style={{ ...fieldGlass({ marginTop: 14, padding: 16 }) }}>
          <IslandRealityNote T={T} />
          <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink3, margin: '8px 0 0' }}>
            {T('Hiệu ứng đảo: dynaura (MIT).', 'Island motion: dynaura (MIT).')}
          </p>
        </div>
      </div>
    </div>
  );
}
