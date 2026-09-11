import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass } from '../theme.js';

const TITLES = {
  going: ['Đang tham gia', 'Going'],
  saved: ['Đã lưu', 'Saved'],
  completed: ['Sự kiện đã hoàn thành', 'Completed events'],
};
const EMPTY_MESSAGES = {
  going: ["Bạn chưa tham gia sự kiện nào.", "You're not going to any events yet."],
  saved: ['Bạn chưa lưu sự kiện nào.', "You haven't saved any events yet."],
  completed: ['Bạn chưa hoàn thành sự kiện nào.', "You haven't completed any events yet."],
};
const SCREEN_LABELS = { going: 'Going', saved: 'Saved', completed: 'Completed' };

// Opened from the "Going"/"Saved" cards and the "Sự kiện đã lưu"/"Completed
// events" row on Account — a plain list of the matching events, in its own
// view rather than redirecting to Home, so "back" is a single step to
// Account instead of losing the trip there.
export default function EventList() {
  const { state, T, trStatus, stripKm, goEvent, backFromEventList } = useGoc();
  const s = state;
  const mode = s.eventListMode;

  const keys = mode === 'going' ? s.attending
    : mode === 'completed'
    ? [...new Set([...(s.favorites || []), ...s.attending])]
    : (s.favorites || []);
  let list = keys.map(k => EVENTS.find(e => e.key === k)).filter(Boolean);
  // "Completed" means it already happened — anything still upcoming (or
  // just favorited but never actually attended/held) doesn't belong here.
  if (mode === 'completed') list = list.filter(e => e.endedHoursAgo != null);

  const title = T(...TITLES[mode]);
  const emptyMsg = T(...EMPTY_MESSAGES[mode]);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label={SCREEN_LABELS[mode]}>
      <div style={{ padding: '66px 20px 0', display: 'flex', alignItems: 'center', gap: 10 }}>
        <span onClick={backFromEventList} data-testid="event-list-back" style={{ fontSize: 15, color: ink, cursor: 'pointer', lineHeight: 1 }}>‹</span>
        <span style={{ ...display(24) }}>{title}</span>
      </div>

      {list.length > 0 ? (
        <div style={{ ...fieldGlass({ margin: '20px 20px 0', display: 'flex', flexDirection: 'column' }) }}>
          {list.map((e, i) => (
            <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < list.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
              <div style={bg(e.img, { flex: 'none', width: 52, height: 52, borderRadius: 10 })} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
                <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))}</span>
              </div>
              <span style={{ fontSize: 15, color: ink, flex: 'none', lineHeight: 1 }}>›</span>
            </div>
          ))}
        </div>
      ) : (
        <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, padding: '40px 20px', textAlign: 'center' }}>{emptyMsg}</p>
      )}
    </div>
  );
}
