// Event Detail "plan" row — web twin of iOS EventPlanTitleRow (notes 44/45): where this event stands in the banbe
// Schedule (Discover / In My schedule · source) with Add / Remove (manual adds only), plus "Add to calendar"
// (.ics download or Google). Real events only; adding to the banbe Schedule needs an account.
import { useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink } from '../theme.js';
import { sourceLabel, canAdd } from '../lib/schedulePresentation.js';
import { CalendarExportButtons } from './Schedule.jsx';

const linkBtn = { border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer', padding: '8px 0', minHeight: 36 };

export default function EventPlanActions({ eventKey }) {
  const { state: s, T, scheduleSnapshot, scheduleInfoFor, addToBanbeSchedule, removeFromBanbeSchedule } = useBanBe();
  const [msg, setMsg] = useState('');
  const real = s.realEventsById?.[eventKey];
  const info = scheduleInfoFor(real);
  if (!info) return null;
  const item = scheduleSnapshot.mine.items.find(i => i.id === eventKey);
  const flash = (m) => { setMsg(m); setTimeout(() => setMsg(''), 6000); };
  const add = () => {
    const r = addToBanbeSchedule(eventKey);
    flash(r === 'added' ? T('Đã thêm vào lịch banbe trên trình duyệt này.', 'Added to your banbe Schedule in this browser.')
      : r === 'ineligible' ? T('Sự kiện này không thêm vào lịch được.', "This event can't be added.") : '');
  };
  return (
    <div data-testid="event-plan" style={{ margin: '0 0 12px' }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '0 16px' }}>
        {item ? (
          <span data-testid="event-plan-status" style={{ fontSize: 13, fontWeight: 600, padding: '8px 0' }}>
            ✓ {T('Trong lịch của tôi', 'In My schedule')} · {sourceLabel(item.source, T)}
          </span>
        ) : s.user && canAdd(info) ? (
          <button type="button" onClick={add} data-testid="event-plan-add" style={linkBtn}
            title={T('Lưu vào lịch trong app. Không phải đặt chỗ.', 'Saves to your in-app schedule. Not a reservation.')}>
            ＋ {T('Thêm vào lịch banbe', 'Add to banbe Schedule')}
          </button>
        ) : null}
        {item?.source === 'added' && (
          <button type="button" onClick={() => removeFromBanbeSchedule(eventKey)} data-testid="event-plan-remove" style={linkBtn}>⊖ {T('Bỏ khỏi lịch', 'Remove')}</button>
        )}
        {!info.ended && !info.cancelled && <CalendarExportButtons info={info} T={T} compact />}
      </div>
      {msg && <p role="status" style={{ fontSize: 12, opacity: 0.75, margin: '2px 0 0' }}>{msg}</p>}
    </div>
  );
}
