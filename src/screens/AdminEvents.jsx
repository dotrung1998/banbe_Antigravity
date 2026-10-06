import { useEffect, useState } from 'react';
import { useGoc, resolveCoverUrl } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { withR2Columns } from '../lib/mediaUrls.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { mapsUrl } from '../data/events.js';
import { paper, ink, rule, display, alert } from '../theme.js';
import HostTitleIcon from './HostTitleIcon.jsx';
import { fieldGlass, cardGlass, insetField } from './hostStyle.js';

// Event submission -> admin review -> publish. A SEPARATE desk from
// Disputes.jsx (payment verification) — reviewing a new event submission
// is not the same job as ruling on a payment dispute, even though both are
// gated the same way server-side (is_platform_admin(), migrations 026/085).
//
// TASK 3 (event creation validation pass) — each event is now a compact
// identifying summary (name/organizer/status/submitted date/price) plus an
// expandable detailed section, reusing the SAME fold pattern Reports
// already established (toggleReportCard/expandAllReportCards/
// collapseAllReportCards, GocContext.jsx) — a local `Set` of expanded keys
// here instead, since this screen's own expand state has nothing to do
// with Reports' and doesn't need to survive a navigation away. Keyed by
// the event's own stable `key` (its real id), never row index, so
// approving/rejecting one row (which re-fetches and re-orders the list)
// never silently expands/collapses a DIFFERENT row that happened to land
// on the same index.
export default function AdminEvents() {
  const { state, T, loadPendingEvents, reviewEvent, backFromDocuments } = useGoc();
  const s = state;
  const [reasonByEvent, setReasonByEvent] = useState({});
  const [expanded, setExpanded] = useState(() => new Set());
  const [galleryByEvent, setGalleryByEvent] = useState({});

  useEffect(() => { loadPendingEvents(); }, [loadPendingEvents]);

  // Host reminders (remind_admin_event_review, migration 148): how many times
  // each pending event's host has nudged the admins, and when last. Read-only;
  // silently absent if migration 148 isn't applied (column missing).
  const [remindById, setRemindById] = useState({});
  const pendingKeys = s.adminEvents.map(e => e.key).join(',');
  useEffect(() => {
    if (!pendingKeys) return;
    let live = true;
    supabase.from('events').select('id, admin_remind_count, last_admin_reminded_at').in('id', pendingKeys.split(',')).then(({ data, error }) => {
      if (!live || error) return;
      setRemindById(Object.fromEntries((data || []).map(r => [r.id, r])));
    });
    return () => { live = false; };
  }, [pendingKeys]);

  const setReason = (key, value) => setReasonByEvent(prev => ({ ...prev, [key]: value }));

  const loadGallery = async (eventId) => {
    if (galleryByEvent[eventId]) return;
    const { data, error } = await withR2Columns(withR2 => supabase
      .from('event_photos').select(withR2 ? 'id, storage_path, r2_ref' : 'id, storage_path').eq('event_id', eventId).order('sort_order', { ascending: true }));
    if (error) { console.warn('AdminEvents loadGallery failed:', error); return; }
    setGalleryByEvent(prev => ({ ...prev, [eventId]: (data || []).map(p => resolveCoverUrl(p.storage_path, null, p.r2_ref, 'full')) }));
  };

  const toggleExpanded = (key) => {
    setExpanded(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key); else { next.add(key); loadGallery(key); }
      return next;
    });
  };
  const expandAll = () => {
    setExpanded(new Set(s.adminEvents.map(e => e.key)));
    s.adminEvents.forEach(e => loadGallery(e.key));
  };
  const collapseAll = () => setExpanded(new Set());

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin events">
      <div onClick={backFromDocuments} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-events-back">
        ‹ {T('Duyệt & Kiểm Duyệt', 'Review & Moderation')}
      </div>
      <div style={{ padding: '14px 22px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', gap: 10 }}>
        <div>
          <h1 style={{ ...display(24, { margin: 0, display: 'flex', alignItems: 'center', gap: 10 }) }} data-testid="admin-events-title"><HostTitleIcon kind="alertShield" group="adminReview" />{T('Sự Kiện Chờ Duyệt', 'Pending Events')}</h1>
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
            {T('Sự kiện chỉ hiển thị công khai sau khi được duyệt ở đây.', 'An event only shows publicly once approved here.')}
          </p>
        </div>
        {s.adminEvents.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6, flex: 'none' }}>
            <span onClick={expandAll} data-testid="admin-events-expand-all" style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Mở tất cả', 'Expand all')}</span>
            <span onClick={collapseAll} data-testid="admin-events-collapse-all" style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Thu gọn tất cả', 'Collapse all')}</span>
          </div>
        )}
      </div>

      {s.adminEventError && (
        <p style={{ fontSize: 11.5, color: alert, margin: '10px 22px 0' }} data-testid="admin-events-error">{s.adminEventError}</p>
      )}

      <div style={{ margin: '18px 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {s.adminEvents.map(e => {
          const reason = reasonByEvent[e.key] || '';
          const busy = s.adminEventBusy === e.key;
          const isOpen = expanded.has(e.key);
          const gallery = galleryByEvent[e.key] || (e.photoUrl ? [e.photoUrl] : []);
          const submittedLabel = e.submittedAt ? new Date(e.submittedAt).toLocaleString() : T('Không rõ', 'Unknown');
          const addressLabel = [e.addressLine, e.area, e.city].filter(Boolean).join(', ') || e.area || T('Không Có Thông Tin', 'Not Provided');
          return (
            <div key={e.key} style={{ ...cardGlass({ padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="admin-event-row">
              {/* Compact identifying summary — always visible. */}
              <div
                onClick={() => toggleExpanded(e.key)}
                data-testid="admin-event-summary"
                style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start', cursor: 'pointer' }}
              >
                <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                  <span style={{ ...display(16) }} data-testid="admin-event-name">{e.name}</span>
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{e.organizerName || T('Không rõ người tổ chức', 'Unknown host')}</span>
                  <span style={{ fontSize: 10.5, color: ink, opacity: 0.55 }}>
                    {T('Mã', 'ID')} {e.key} ▪︎ {T('Gửi lúc', 'Submitted')} {submittedLabel}
                  </span>
                  {remindById[e.key]?.admin_remind_count > 0 && (
                    <span data-testid={`admin-event-reminded-${e.key}`} style={{ fontSize: 11, fontWeight: 600, color: alert }}>
                      {T(`Host đã nhắc duyệt ${remindById[e.key].admin_remind_count}/2 lần`, `Host reminded ${remindById[e.key].admin_remind_count}/2 times`)}
                      {remindById[e.key].last_admin_reminded_at ? ` ▪︎ ${T('gần nhất', 'last')} ${new Date(remindById[e.key].last_admin_reminded_at).toLocaleString()}` : ''}
                    </span>
                  )}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4, flex: 'none' }}>
                  <span style={{ ...display(19, { whiteSpace: 'nowrap' }) }}>{e.priceVnd ? formatVnd(e.priceVnd) : T('Miễn phí', 'Free')}</span>
                  <span data-testid="admin-event-toggle" style={{ fontSize: 11, fontWeight: 600, color: ink, textDecoration: 'underline' }}>
                    {isOpen ? T('Thu gọn', 'Collapse') : T('Mở rộng', 'Expand')}
                  </span>
                </div>
              </div>

              {isOpen && (
                <>
                  {gallery.length > 0 ? (
                    <div style={{ display: 'flex', gap: 8, overflowX: 'auto' }} data-testid="admin-event-gallery">
                      {gallery.map((url, i) => (
                        <img key={url + i} src={url} alt={`${e.name} ${i + 1}`} style={{ width: 120, height: 90, objectFit: 'cover', borderRadius: 10, flex: 'none' }} />
                      ))}
                    </div>
                  ) : (
                    <div style={{ ...insetField({ padding: '30px 12px', textAlign: 'center' }) }}>
                      <span style={{ fontSize: 11.5, color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>
                    </div>
                  )}

                  <div style={{ ...insetField({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }}>
                    <Line label={T('Trạng thái', 'Status')} value={e.status} />
                    <Line label={T('Danh mục', 'Category')} value={e.catLabel || e.catKey || T('Không Có Thông Tin', 'Not Provided')} />
                    <Line label={T('Từ khoá', 'Keywords')} value={e.keywords?.length ? e.keywords.join(', ') : T('Không Có Thông Tin', 'Not Provided')} />
                    <Line label={T('Ngày', 'Date')} value={e.eventDate ? `${e.eventDate}${e.eventTime ? ' ▪︎ ' + e.eventTime.slice(0, 5) : ''}` : T('Chưa đặt', 'Not set')} />
                    <Line label={T('Sức chứa', 'Capacity')} value={e.capacity != null ? String(e.capacity) : T('Không Có Thông Tin', 'Not Provided')} />
                    <Line label={T('Hiển thị', 'Visibility')} value={e.visibility || T('Không Có Thông Tin', 'Not Provided')} />
                    <Line label={T('Chế độ duyệt vé', 'Booking approval')} value={e.approval || T('Không Có Thông Tin', 'Not Provided')} />
                    <Line label={T('Mô tả', 'Description')} value={e.description || T('Không Có Thông Tin', 'Not Provided')} />
                    <Line
                      label={T('Bao gồm', 'Included')}
                      value={e.includedItems?.length ? e.includedItems.map(it => it.label).join(' ▪︎ ') : (e.included || T('Không Có Thông Tin', 'Not Provided'))}
                    />
                  </div>

                  <div style={{ ...insetField({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }} data-testid="admin-event-address">
                    <Line label={T('Địa chỉ', 'Address')} value={addressLabel} />
                    <Line label={T('Đã xác minh (chủ nhà tự khai)', 'Address confirmed (host-provided)')} value={e.addressVerified ? T('Có', 'Yes') : T('Không', 'No')} />
                    {e.lat != null && e.lng != null && (
                      <a href={mapsUrl(e)} target="_blank" rel="noreferrer" style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
                        {T('Mở trên Google Maps', 'Open in Google Maps')} ({e.lat.toFixed(5)}, {e.lng.toFixed(5)})
                      </a>
                    )}
                  </div>

                  {e.intro && (
                    <div style={{ ...insetField({ padding: '10px 12px' }) }}>
                      <span style={{ fontSize: 10.5, color: ink, opacity: 0.65 }}>{T('Giới thiệu sự kiện', 'Event introduction')}</span>
                      <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, margin: '4px 0 0', whiteSpace: 'pre-wrap' }}>{e.intro}</p>
                    </div>
                  )}

                  {/* Host/organizer identity — self-declared fields only.
                      `organizerVerified` (the `verified` column) has NO real
                      write path anywhere in this schema (migration 109's own
                      comment) — labelled "Not verified" always, never implied
                      otherwise. Never shows bank/payout details here. */}
                  <div style={{ ...insetField({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }} data-testid="admin-event-organizer">
                    <Line label={T('Loại người tổ chức (tự khai)', 'Organizer type (self-declared)')} value={e.organizerType === 'business' ? T('Doanh nghiệp', 'Business') : T('Cá nhân', 'Individual')} />
                    <Line label={T('Đăng ký kinh doanh', 'Business registration')} value={e.organizerHasTaxCode ? T('Đã cung cấp mã số thuế (chưa xác minh)', 'Tax code provided (not verified)') : T('Chưa cung cấp', 'Not provided')} />
                    <Line label={T('Xác minh nền tảng', 'Platform verification')} value={T('Chưa xác minh', 'Not verified')} />
                  </div>

                  {(e.rejectionReason || e.withdrawalReason) && (
                    <div style={{ ...insetField({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }} data-testid="admin-event-history">
                      {e.rejectionReason && <Line label={T('Lý do từ chối trước đó', 'Previous rejection reason')} value={e.rejectionReason} />}
                      {e.withdrawalReason && <Line label={T('Lý do rút lại trước đó', 'Previous withdrawal reason')} value={e.withdrawalReason} />}
                    </div>
                  )}

                  <input
                    value={reason}
                    onChange={(ev) => setReason(e.key, ev.target.value)}
                    placeholder={T('Lý do từ chối (bắt buộc nếu từ chối)', 'Rejection reason (required if rejecting)')}
                    data-testid="admin-event-reason"
                    style={{ ...insetField({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
                  />
                  <div style={{ display: 'flex', gap: 8 }}>
                    <Action
                      label={busy ? T('Đang lưu…', 'Saving…') : T('Duyệt ▪︎ đăng công khai', 'Approve ▪︎ publish')}
                      testid="admin-event-approve"
                      disabled={busy}
                      onClick={() => { if (!busy) reviewEvent(e.key, true, ''); }}
                    />
                    <Action
                      label={T('Từ chối', 'Reject')}
                      ghost testid="admin-event-reject"
                      disabled={busy}
                      onClick={() => { if (!busy && reason.trim()) reviewEvent(e.key, false, reason); }}
                    />
                  </div>
                </>
              )}
            </div>
          );
        })}

        {s.adminEvents.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: 0 }} data-testid="admin-events-empty">
            {s.adminEventsLoading ? T('Đang tải…', 'Loading…') : T('Không có sự kiện nào đang chờ duyệt.', 'No pending events.')}
          </p>
        )}
      </div>
    </div>
  );
}

function Line({ label, value }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }}>
      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 600, color: ink, wordBreak: 'break-word', textAlign: 'right', maxWidth: '70%' }}>{value}</span>
    </div>
  );
}

function Action({ label, onClick, ghost, testid, disabled }) {
  return (
    <div onClick={disabled ? undefined : onClick} data-testid={testid}
         style={{
           flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, padding: '11px 10px',
           borderRadius: 12, cursor: disabled ? 'default' : 'pointer', lineHeight: 1.3,
           background: ghost ? 'transparent' : ink, color: ghost ? ink : paper,
           border: ghost ? `1px solid ${rule}` : 'none',
           opacity: disabled ? 0.6 : 1,
         }}>
      {label}
    </div>
  );
}
