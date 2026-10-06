import { useEffect, useState } from 'react';
import { useBanBe, resolveCoverUrl } from '../../state/BanBeContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { withR2Columns } from '../../lib/mediaUrls.js';
import { formatVnd } from '../../lib/paymentDocument.js';
import { paper, ink, rule, display, alert, honeyBg } from '../../theme.js';
import { inkButton } from '../hostStyle.js';

// Web port of iOS PendingEventDetailSheet (DashboardView.swift, commit
// 7fd7086): what the host submitted, read-only, plus the "remind admin"
// control backed by remind_admin_event_review (migration 148).
//
// Migration 148 semantics: at most 2 reminders per event (the count is stored
// on the event as admin_remind_count; there is NO time-based cooldown — the
// only "cooldown" is the 2-reminder cap), only while status = 'review'. Each
// reminder is an in-app notification to every admin. The count is read straight
// from events.admin_remind_count; if that column doesn't exist yet (migration
// 148 not applied) the remind block is hidden entirely, like iOS.

export const REMIND_MAX = 2;

export function remindErrorMessage(code, T) {
  switch (code) {
    case 'REMIND_LIMIT_REACHED': return T('Bạn đã nhắc tối đa 2 lần cho sự kiện này.', 'You have already reminded the admins the maximum 2 times for this event.');
    case 'NOT_PENDING': return T('Sự kiện này không còn ở trạng thái chờ duyệt.', 'This event is no longer waiting for review.');
    case 'NOT_AUTHORIZED': return T('Chỉ chủ sự kiện mới nhắc được.', 'Only the event owner can send a reminder.');
    case 'EVENT_NOT_FOUND': return T('Không tìm thấy sự kiện.', 'Event not found.');
    case 'AUTH_REQUIRED': return T('Hãy đăng nhập lại.', 'Please sign in again.');
    default: return T('Không gửi được. Thử lại nhé.', "Couldn't send. Please try again.");
  }
}

export default function PendingEventSheet({ eventId, name, onClose, onChanged }) {
  const { T } = useBanBe();
  const locale = T('vi-VN', 'en-GB');
  const [ev, setEv] = useState(null);
  const [photos, setPhotos] = useState([]);
  const [remindCount, setRemindCount] = useState(null); // null = unknown / column missing
  const [lastReminded, setLastReminded] = useState(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [msgBad, setMsgBad] = useState(false);

  useEffect(() => {
    let live = true;
    (async () => {
      const [{ data: row }, { data: ph }] = await Promise.all([
        supabase.from('events').select('*').eq('id', eventId).maybeSingle(),
        withR2Columns(withR2 => supabase.from('event_photos').select(withR2 ? 'storage_path, r2_ref' : 'storage_path').eq('event_id', eventId).order('sort_order', { ascending: true })),
      ]);
      if (!live) return;
      if (row) {
        setEv(row);
        if (typeof row.admin_remind_count === 'number') setRemindCount(row.admin_remind_count);
        setLastReminded(row.last_admin_reminded_at || null);
      }
      setPhotos((ph || []).map(p => resolveCoverUrl(p.storage_path, null, p.r2_ref, 'full')).filter(Boolean));
    })();
    return () => { live = false; };
  }, [eventId]);

  const left = remindCount == null ? 0 : Math.max(0, REMIND_MAX - remindCount);
  const stillPending = !ev || ev.status === 'review';

  const remind = async () => {
    if (busy || left <= 0) return;
    setBusy(true); setMsg('');
    const { data, error } = await supabase.rpc('remind_admin_event_review', { p_event_id: eventId });
    setBusy(false);
    if (error || !data?.success) {
      const code = data?.error;
      if (code === 'REMIND_LIMIT_REACHED') setRemindCount(data?.remind_count ?? REMIND_MAX);
      setMsgBad(true);
      setMsg(remindErrorMessage(error ? 'FAILED' : code, T));
      return;
    }
    setRemindCount(data.remind_count ?? ((remindCount || 0) + 1));
    setLastReminded(new Date().toISOString());
    setMsgBad(false);
    setMsg(T('Đã nhắc quản trị viên.', 'Reminder sent to the admin.'));
    onChanged?.();
  };

  const line = (label, value) => (value ? (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ fontSize: 11, color: ink, opacity: 0.6 }}>{label}</span>
      <span style={{ fontSize: 14, color: ink, whiteSpace: 'pre-wrap' }}>{value}</span>
    </div>
  ) : null);
  const fmt = (iso) => (iso ? new Date(iso).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' }) : '');
  const when = ev ? (ev.starts_at ? fmt(ev.starts_at) : [ev.event_date, ev.event_time].filter(Boolean).join(' ▪︎ ')) : '';
  const included = ev && Array.isArray(ev.included_items) ? ev.included_items.map(i => i?.label).filter(Boolean).join(' ▪︎ ') : '';

  return (
    <div onClick={onClose} data-testid="pending-event-sheet" style={{ position: 'fixed', inset: 0, zIndex: 70, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'flex-end', animation: 'banbeFade 0.22s ease both' }}>
      <div onClick={e => e.stopPropagation()} style={{ background: paper, width: '100%', maxHeight: '90%', overflowY: 'auto', borderRadius: '22px 22px 0 0', padding: '18px 20px 28px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: ink }}>{T('Sự kiện đã gửi', 'Submitted event')}</span>
          <span onClick={onClose} data-testid="pending-event-close" style={{ fontSize: 12, color: ink, cursor: 'pointer', padding: '4px 2px' }}>{T('Đóng', 'Close')}</span>
        </div>

        {photos.length > 0 && (
          <div style={{ display: 'flex', gap: 10, overflowX: 'auto', scrollSnapType: 'x mandatory' }}>
            {photos.map(u => (
              <img key={u} src={u} alt="" style={{ flex: 'none', width: photos.length === 1 ? '100%' : '82%', height: 200, objectFit: 'cover', borderRadius: 14, scrollSnapAlign: 'start' }} />
            ))}
          </div>
        )}

        <span style={{ ...display(24) }}>{ev?.name || name}</span>
        {stillPending ? (
          <span style={{ fontSize: 12, fontWeight: 600, color: ink, opacity: 0.75 }}>⏳ {T('Đang chờ Banbe duyệt', 'Waiting for Banbe to review')}</span>
        ) : (
          <span style={{ fontSize: 12, fontWeight: 600, color: alert }}>{T('Sự kiện không còn chờ duyệt — làm mới danh sách.', 'This event is no longer waiting for review — refresh the list.')}</span>
        )}

        {stillPending && (
          <div style={{ background: honeyBg, borderRadius: 14, padding: 14, display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="pending-event-remind-block">
            <span style={{ fontSize: 12.5, color: ink, opacity: 0.85, lineHeight: 1.5 }}>
              {T('Banbe sẽ có quyết định trong vòng 7 ngày. Bạn có thể nhắc quản trị viên tối đa 2 lần cho mỗi sự kiện.', 'A decision will be made within 7 days. You can remind the admin up to twice per event.')}
            </span>
            {remindCount != null && (
              <>
                <div
                  onClick={left > 0 && !busy ? remind : undefined}
                  data-testid={`pending-event-remind-${eventId}`}
                  aria-disabled={left === 0 || busy}
                  style={{ ...inkButton({ borderRadius: 12, padding: '12px 14px', fontSize: 13, textAlign: 'center' }), cursor: left > 0 && !busy ? 'pointer' : 'default', opacity: left > 0 ? (busy ? 0.6 : 1) : 0.4 }}
                >
                  {left > 0
                    ? T(`Nhắc quản trị viên (còn ${left} lần)`, `Remind admin (${left} left)`)
                    : T('Đã nhắc tối đa 2 lần', 'Reminded the maximum 2 times')}
                </div>
                {lastReminded && (
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.65 }}>{T(`Nhắc lần gần nhất: ${fmt(lastReminded)}`, `Last reminded: ${fmt(lastReminded)}`)}</span>
                )}
              </>
            )}
            {msg && <span role="status" style={{ fontSize: 11.5, color: msgBad ? alert : ink, opacity: msgBad ? 1 : 0.75 }}>{msg}</span>}
          </div>
        )}

        {ev && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 4, borderTop: `1px solid ${rule}` }}>
            {line(T('Thời gian', 'When'), when)}
            {line(T('Khu vực', 'Area'), ev.area)}
            {line(T('Địa chỉ', 'Address'), [ev.address_line, ev.city].filter(Boolean).join(', '))}
            {line(T('Danh mục', 'Category'), ev.cat_label)}
            {line(T('Giá', 'Price'), ev.price_vnd > 0 ? formatVnd(ev.price_vnd) : T('Miễn phí', 'Free'))}
            {line(T('Sức chứa', 'Capacity'), ev.capacity != null ? String(ev.capacity) : '')}
            {line(T('Mô tả', 'Description'), ev.description)}
            {line(T('Giới thiệu', 'About'), ev.intro)}
            {line(T('Bao gồm', 'Included'), included)}
            {line(T('Gửi lúc', 'Submitted'), fmt(ev.submitted_at))}
          </div>
        )}
      </div>
    </div>
  );
}
