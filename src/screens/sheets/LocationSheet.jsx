import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, display, inkButton } from '../../theme.js';

export default function LocationSheet() {
  const { allowLocation, denyLocation } = useGoc();

  return (
    <div onClick={denyLocation} style={{ position: 'absolute', inset: 0, zIndex: 20, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '28px 24px 40px', display: 'flex', flexDirection: 'column', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <span style={{ fontSize: 11.5, color: ink }}>Vị trí</span>
        <h2 style={{ ...display(23, { margin: '8px 0 0', lineHeight: 1.25 }) }}>Cho banbe biết bạn đang ở đâu?</h2>
        <p style={{ fontSize: 13.5, lineHeight: 1.5, color: ink, margin: '12px 0 0' }}>Chỉ để hiện khoảng cách tới mỗi sự kiện. Không lưu, không chia sẻ với người tổ chức.</p>
        <div onClick={allowLocation} style={{ ...inkButton({ marginTop: 22, borderRadius: 18, padding: 16 }) }}>Dùng vị trí của tôi</div>
        <div onClick={denyLocation} style={{ marginTop: 10, color: ink, fontSize: 13.5, textAlign: 'center', padding: 8, cursor: 'pointer' }}>Để sau</div>
      </div>
    </div>
  );
}
