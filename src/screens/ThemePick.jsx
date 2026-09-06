import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, inkButton } from '../theme.js';

export default function ThemePick() {
  const { state, T, pickLight, pickDark, finishOnboarding } = useGoc();
  const isDark = state.theme === 'dark';

  const lightCardStyle = {
    flex: 1,
    cursor: 'pointer',
    padding: '10px',
    borderRadius: '15px',
    border: !isDark ? '1.5px solid var(--bb-fg)' : '1px solid var(--bb-rule)',
    background: !isDark ? 'var(--bb-card)' : 'var(--bb-card2)',
    display: 'flex',
    flexDirection: 'column',
  };

  const darkCardStyle = {
    flex: 1,
    cursor: 'pointer',
    padding: '10px',
    borderRadius: '15px',
    border: isDark ? '1.5px solid var(--bb-fg)' : '1px solid var(--bb-rule)',
    background: isDark ? 'var(--bb-card)' : 'var(--bb-card2)',
    display: 'flex',
    flexDirection: 'column',
  };

  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        zIndex: 38,
        background: paper,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        padding: '0 30px',
        animation: 'gocFade 0.4s ease both',
      }}
      data-screen-label="Appearance"
    >
      <span style={{ ...display(27, { lineHeight: 1.2, color: ink }) }}>
        {T('Sáng hay tối?', 'Light or dark?')}
      </span>
      <span
        style={{
          fontSize: 12.5,
          lineHeight: 1.5,
          color: ink,
          opacity: 0.58,
          marginTop: 7,
        }}
      >
        {T(
          'Chọn kiểu hiển thị bạn thích. Đổi lại bất cứ lúc nào trong Tài khoản.',
          'Pick how banbe looks. You can change it anytime in Account.'
        )}
      </span>

      <div style={{ display: 'flex', gap: 10, marginTop: 26 }}>
        {/* Light Mode Card */}
        <div onClick={pickLight} style={lightCardStyle}>
          <div
            style={{
              height: 74,
              borderRadius: 9,
              border: '1px solid rgba(27,25,22,0.16)',
              background: '#F7F4EC',
              padding: 9,
              display: 'flex',
              flexDirection: 'column',
              gap: 5,
            }}
          >
            <div style={{ height: 8, width: '60%', borderRadius: 3, background: '#1B1916' }} />
            <div style={{ height: 6, width: '88%', borderRadius: 3, background: 'rgba(27,25,22,0.22)' }} />
            <div
              style={{
                flex: 1,
                borderRadius: 6,
                background: 'rgba(224,214,194,0.58)',
                border: '1px solid rgba(27,25,22,0.16)',
              }}
            />
          </div>
          <span style={{ ...display(15, { color: ink, marginTop: 12 }) }}>{T('Sáng', 'Light')}</span>
        </div>

        {/* Dark Mode Card */}
        <div onClick={pickDark} style={darkCardStyle}>
          <div
            style={{
              height: 74,
              borderRadius: 9,
              border: '1px solid rgba(242,237,225,0.2)',
              background: '#14120E',
              padding: 9,
              display: 'flex',
              flexDirection: 'column',
              gap: 5,
            }}
          >
            <div style={{ height: 8, width: '60%', borderRadius: 3, background: '#F2EDE1' }} />
            <div style={{ height: 6, width: '88%', borderRadius: 3, background: 'rgba(242,237,225,0.28)' }} />
            <div
              style={{
                flex: 1,
                borderRadius: 6,
                background: 'rgba(74,68,57,0.55)',
                border: '1px solid rgba(242,237,225,0.2)',
              }}
            />
          </div>
          <span style={{ ...display(15, { color: ink, marginTop: 12 }) }}>{T('Tối', 'Dark')}</span>
        </div>
      </div>

      <div
        onClick={finishOnboarding}
        style={{
          ...inkButton({
            marginTop: 26,
            padding: 15,
            borderRadius: 14,
            fontSize: 15,
            fontWeight: 600,
          }),
        }}
      >
        {T('Tiếp tục', 'Continue')}
      </div>
    </div>
  );
}
