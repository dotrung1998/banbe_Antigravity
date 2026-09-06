import { useGoc, AREAS } from '../../state/GocContext.jsx';
import { EVENTS } from '../../data/events.js';
import { paper, ink, rule } from '../../theme.js';

export default function AreaSheet() {
  const { state, set, located, pickArea, allowLocation } = useGoc();
  const s = state;
  const closeArea = () => set({ areaAsking: false });

  // Area names/counts stay in Vietnamese regardless of language, matching the source prototype.
  const areas = AREAS.map(a => {
    const n = EVENTS.filter(e => a.match(e) && !e.cancelled && e.endedHoursAgo == null).length;
    return {
      key: a.key,
      label: a.label,
      count: a.key === 'danang' ? 'Sắp có' : (n + ' sự kiện'),
    };
  });

  const locationLabel2 = located ? 'Vị trí đang bật ▪︎ khoảng cách hiển thị' : 'Dùng vị trí của tôi để xem khoảng cách';

  return (
    <div onClick={closeArea} style={{ position: 'absolute', inset: 0, zIndex: 21, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '26px 24px 36px', display: 'flex', flexDirection: 'column', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>Khu vực</span>
        <div style={{ display: 'flex', flexDirection: 'column', marginTop: 10 }}>
          {areas.map(a => (
            <div key={a.key} onClick={() => pickArea(a.key)} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '13px 2px', borderBottom: `1px solid ${rule}`, cursor: 'pointer', fontSize: 14.5, color: ink, fontWeight: s.area === a.key ? 600 : 400 }}>
              <span>{a.label}</span>
              <span style={{ fontSize: 11, color: ink }}>{a.count}</span>
            </div>
          ))}
        </div>
        <div onClick={allowLocation} style={{ marginTop: 14, color: ink, fontSize: 13, textAlign: 'center', padding: 8, cursor: 'pointer' }}>{locationLabel2}</div>
      </div>
    </div>
  );
}
