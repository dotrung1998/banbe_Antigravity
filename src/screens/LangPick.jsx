import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display } from '../theme.js';

const choiceStyle = (active) => ({
  display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, borderRadius: 14, padding: 18, cursor: 'pointer',
  background: 'var(--bb-field)', boxSizing: 'border-box',
  border: active ? `1.5px solid ${ink}` : `1px solid ${rule}`,
});

export default function LangPick() {
  const { state, pickVi, pickEn } = useGoc();
  const lang = state.lang;

  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        zIndex: 38,
        background: paper,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'flex-start',
        padding: '78px 30px 0',
        animation: 'gocFade 0.4s ease both',
      }}
      data-screen-label="Language"
    >
      <img
        src="/banbe-mark.png"
        alt="banbe"
        crossOrigin="anonymous"
        style={{
          width: 44,
          height: 44,
          display: 'block',
          marginBottom: 26,
          animation: 'gocIn 0.6s cubic-bezier(.22,.61,.36,1) both',
        }}
      />
      <span style={{ ...display(27, { lineHeight: 1.2, color: ink }) }}>Chọn ngôn ngữ</span>
      <span
        style={{
          fontFamily: "'Be Vietnam Pro',sans-serif",
          fontWeight: 400,
          letterSpacing: '-0.01em',
          fontSize: 19,
          lineHeight: 1.2,
          color: ink,
          opacity: 0.52,
          marginTop: 5,
        }}
      >
        Choose your language
      </span>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 28 }}>
        <div
          onClick={pickVi} data-testid="lang-vi"
          style={{
            ...choiceStyle(lang === 'vi'),
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span style={{ ...display(19, { color: ink }) }}>Tiếng Việt</span>
            <span style={{ fontSize: 11.5, color: ink }}>Mặc định</span>
          </div>
          <span style={{ fontSize: 15, color: ink }}>›</span>
        </div>

        <div
          onClick={pickEn} data-testid="lang-en"
          style={{
            ...choiceStyle(lang === 'en'),
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span style={{ ...display(19, { color: ink }) }}>English</span>
            <span style={{ fontSize: 11.5, color: ink }}>Switch anytime</span>
          </div>
          <span style={{ fontSize: 15, color: ink }}>›</span>
        </div>
      </div>

    </div>
  );
}
