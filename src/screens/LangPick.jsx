import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, cardGlass, display } from '../theme.js';

export default function LangPick() {
  const { pickVi, pickEn } = useGoc();

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

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 30 }}>
        <div
          onClick={pickVi}
          style={{
            ...cardGlass({
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: 12,
              borderRadius: 15,
              padding: '17px 18px',
              cursor: 'pointer',
            }),
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ ...display(17, { color: ink }) }}>Tiếng Việt</span>
            <span style={{ fontSize: 11.5, color: ink, opacity: 0.58 }}>Mặc định</span>
          </div>
          <span style={{ fontSize: 14, color: ink }}>›</span>
        </div>

        <div
          onClick={pickEn}
          style={{
            ...cardGlass({
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: 12,
              borderRadius: 15,
              padding: '17px 18px',
              cursor: 'pointer',
            }),
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ ...display(17, { color: ink }) }}>English</span>
            <span style={{ fontSize: 11.5, color: ink, opacity: 0.58 }}>You can switch anytime</span>
          </div>
          <span style={{ fontSize: 14, color: ink }}>›</span>
        </div>
      </div>

      <span style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.58, marginTop: 18 }}>
        Đổi lại bất cứ lúc nào trong Tài khoản.
      </span>
    </div>
  );
}
