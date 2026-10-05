import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, inkButton } from '../theme.js';

// Mirrors iOS ThemePickView: caption, title, helper, two stacked choice rows
// (name + subtitle, "✓"/"›" trailing), then a full-width ink Continue button.
export default function ThemePick() {
  const { state, T, pickLight, pickDark, finishOnboarding } = useGoc();
  const isDark = state.theme === 'dark';

  const choice = (title, subtitle, active, onClick, id) => (
    <div
      onClick={onClick}
      data-testid={id}
      style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, borderRadius: 14, padding: 18,
        cursor: 'pointer', boxSizing: 'border-box', background: 'var(--bb-field)',
        border: active ? `1.5px solid ${ink}` : `1px solid ${rule}`,
      }}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        <span style={{ ...display(19, { color: ink }) }}>{title}</span>
        <span style={{ fontSize: 11.5, color: ink }}>{subtitle}</span>
      </div>
      <span style={{ fontSize: 15, color: ink }}>{active ? '✓' : '›'}</span>
    </div>
  );

  return (
    <div
      style={{
        position: 'absolute', inset: 0, zIndex: 38, background: paper, display: 'flex', flexDirection: 'column',
        justifyContent: 'flex-start', padding: '78px 30px 0', animation: 'gocFade 0.4s ease both',
      }}
      data-screen-label="Appearance"
    >
      <span style={{ fontSize: 11.5, color: ink }}>{T('Hiển thị', 'Appearance')}</span>
      <span style={{ ...display(27, { lineHeight: 1.2, color: ink, marginTop: 8 }) }}>
        {T('Bạn thích nền sáng hay tối?', 'Light or dark?')}
      </span>
      <span style={{ fontSize: 13.5, lineHeight: 1.5, color: ink, marginTop: 10 }}>
        {T('Bạn có thể đổi lại bất cứ lúc nào trong Tài khoản.', 'You can change this anytime in your account.')}
      </span>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 28 }}>
        {choice(T('Sáng', 'Light'), T('Nền giấy ấm', 'Warm paper'), !isDark, pickLight, 'theme-light')}
        {choice(T('Tối', 'Dark'), T('Nền mực dịu mắt', 'Soft ink background'), isDark, pickDark, 'theme-dark')}
      </div>

      <div onClick={finishOnboarding} data-testid="onboarding-continue" style={{ ...inkButton({ marginTop: 26, padding: '15px 0', borderRadius: 18 }) }}>
        {T('Tiếp tục', 'Continue')}
      </div>
    </div>
  );
}
