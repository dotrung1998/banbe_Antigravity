import { useCallback, useEffect, useMemo, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, fieldGlass, alert } from '../theme.js';
import { ChoiceChip, Button } from '../components/ui/FormControls.jsx';
import { ADMIN_EVENT_FILTERS, ORPHAN_FILTER, STATUS_LABELS, ERRORS, en, isBlocked, blockerLine, summarize, isOrphanEvent } from '../lib/adminEvents.js';
import { formatMoney, rowCurrency, rowTimeZone, VN_TIME_ZONE } from '../lib/eventMarket.js';
import { loadAdminManagedEvents, loadAdminEventChecks, runAdminEventAction } from '../lib/adminEventsApi.js';

// Admin > Manage events (migrations 188 + 189, note 54). Every event, any status: search, filter, select one or many,
// then Remove (reason required; hidden everywhere, records kept, host notified; refused while money is still in play
// and each row says why), Restore, or Delete permanently (only removed events that never had a booking).
// The TESTING-PHASE wipe is iOS-only on purpose. iOS twin: AdminManageEventsView.swift.
const QUICK_REASONS = [['Spam', 'Spam'], ['Trùng lặp', 'Duplicate'], ['Vi phạm quy định cộng đồng', 'Breaks community guidelines'], ['Sự kiện thử nghiệm', 'Test event']];

export default function AdminManageEvents() {
  const { state: s, T, set, goEvent, openAdminEvents } = useBanBe();
  const [filter, setFilter] = useState(null);
  const [search, setSearch] = useState('');
  const [rows, setRows] = useState([]);
  const [checks, setChecks] = useState({});
  const [selected, setSelected] = useState(() => new Set());
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [banner, setBanner] = useState('');
  const [busy, setBusy] = useState(false);
  const [reasonFor, setReasonFor] = useState(null); // 'remove' | 'purge'
  const [reason, setReason] = useState('');
  // Rows start collapsed (owner, 2026-10-21): summary first, the details one tap away.
  const [expanded, setExpanded] = useState(() => new Set());

  const reload = useCallback(async () => {
    setLoading(true);
    const { rows: loaded, error } = await loadAdminManagedEvents({ status: filter === ORPHAN_FILTER ? null : filter, search });
    // "Host deleted" isn't a status: load everything and keep the orphans.
    const list = filter === ORPHAN_FILTER ? loaded.filter(isOrphanEvent) : loaded;
    setRows(list);
    setLoadError(error ? T(...(ERRORS[error] || ERRORS.NETWORK)) : '');
    setSelected(prev => new Set([...prev].filter(id => list.some(r => r.id === id))));
    setChecks(list.length ? await loadAdminEventChecks(list.map(r => r.id)) : {});
    setLoading(false);
  }, [filter, search, T]);

  useEffect(() => {
    if (s.accountType !== 'admin') return undefined;
    const t = setTimeout(reload, search ? 300 : 0);  // don't reload on every keystroke
    return () => clearTimeout(t);
  }, [reload, search, s.accountType]);

  const sel = useMemo(() => rows.filter(r => selected.has(r.id)), [rows, selected]);
  const removeIds = sel.filter(r => r.status !== 'removed' && !isBlocked(checks[r.id])).map(r => r.id);
  const blockedCount = sel.filter(r => r.status !== 'removed' && isBlocked(checks[r.id])).length;
  const restoreIds = sel.filter(r => r.status === 'removed').map(r => r.id);
  const purgeIds = sel.filter(r => r.status === 'removed' && checks[r.id]?.purgeable).map(r => r.id);

  if (s.accountType !== 'admin') return null;

  const toggleExpanded = (id) => setExpanded(prev => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const allExpanded = rows.length > 0 && rows.every(r => expanded.has(r.id));
  // Event times read in the event's own zone (migration 195); admin bookkeeping times stay in Vietnam time.
  const dateTime = (iso, timeZone = VN_TIME_ZONE) => (iso ? new Date(iso).toLocaleString('vi-VN', { timeZone, dateStyle: 'short', timeStyle: 'short' }) : '—');

  const toggle = (id) => setSelected(prev => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const run = async (action, ids, why = '') => {
    setBusy(true);
    const outcome = await runAdminEventAction(action, ids, why);
    setBanner(outcome.error ? T(...(ERRORS[outcome.error] || ERRORS.NETWORK)) : summarize(action, outcome, T));
    if (!outcome.error) setSelected(new Set());
    setBusy(false);
    reload();
  };
  const restore = () => {
    if (window.confirm(T(`Khôi phục ${restoreIds.length} sự kiện về trạng thái trước khi bị gỡ? Người tổ chức sẽ được báo.`,
      `Restore ${en(restoreIds.length, 'event')} to the status they had before? The host is told.`))) run('restore', restoreIds);
  };
  const date = (iso, timeZone = VN_TIME_ZONE) => (iso ? new Date(iso).toLocaleDateString('vi-VN', { timeZone }) : '');

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper, paddingBottom: selected.size ? 220 : 40 }} data-screen-label="Admin manage events">
      <div onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminReview' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-manage-back">
        ‹ {T('Duyệt & Kiểm Duyệt', 'Review & Moderation')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(26, { margin: 0 }) }}>{T('Quản lý sự kiện', 'Manage events')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Gỡ một hay nhiều sự kiện khỏi ứng dụng. Đặt chỗ, thanh toán, hoàn tiền và lịch sử luôn được giữ lại.',
            'Take one or more events off the app. Bookings, payments, refunds and history are always kept.')}
        </p>
        <input value={search} onChange={(e) => setSearch(e.target.value)} type="search" data-testid="admin-manage-search"
          placeholder={T('Tìm theo tên sự kiện', 'Search by event name')} aria-label={T('Tìm sự kiện', 'Search events')}
          style={{ ...fieldGlass({ marginTop: 18, padding: '12px 14px', borderRadius: 14 }), width: '100%', boxSizing: 'border-box', border: 'none', fontSize: 15, color: ink, fontFamily: 'inherit' }} />
        <div style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 12, paddingBottom: 2 }}>
          {ADMIN_EVENT_FILTERS.map(f => (
            <ChoiceChip key={f.en} compact label={T(f.vi, f.en)} selected={filter === f.key} testId={`admin-manage-filter-${f.key || 'all'}`}
              onClick={() => { setFilter(f.key); setSelected(new Set()); }} />
          ))}
        </div>
        {banner && (
          <div role="status" data-testid="admin-manage-banner" style={{ ...fieldGlass({ marginTop: 12, padding: 12 }), fontSize: 13, fontWeight: 600 }}>{banner}</div>
        )}

        {loading && !rows.length ? (
          <p style={{ fontSize: 13.5, opacity: 0.7, marginTop: 24 }}>{T('Đang tải…', 'Loading…')}</p>
        ) : loadError ? (
          <p role="alert" data-testid="admin-manage-error" style={{ fontSize: 13, color: alert, marginTop: 16 }}>{loadError}</p>
        ) : !rows.length ? (
          <p style={{ fontSize: 14, opacity: 0.7, marginTop: 20 }}>{T('Không có sự kiện nào.', 'No events here.')}</p>
        ) : (
          <>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', margin: '16px 2px 8px' }}>
              <span style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.7 }}>{T(`${rows.length} sự kiện`, en(rows.length, 'event'))}</span>
              <span style={{ display: 'flex', gap: 4 }}>
                <button type="button" data-testid="admin-manage-expand-all" className="bb-press"
                  onClick={() => setExpanded(allExpanded ? new Set() : new Set(rows.map(r => r.id)))}
                  style={{ border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer', minHeight: 36, opacity: 0.75 }}>
                  {allExpanded ? T('Thu gọn tất cả', 'Collapse all') : T('Mở rộng tất cả', 'Expand all')}
                </button>
                <button type="button" data-testid="admin-manage-select-all" className="bb-press"
                  onClick={() => setSelected(selected.size === rows.length ? new Set() : new Set(rows.map(r => r.id)))}
                  style={{ border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer', minHeight: 36 }}>
                  {selected.size === rows.length ? T('Bỏ chọn tất cả', 'Deselect all') : T('Chọn tất cả', 'Select all')}
                </button>
              </span>
            </div>
            <div style={{ ...fieldGlass({ borderRadius: 16 }), display: 'flex', flexDirection: 'column' }}>
              {rows.map((r, i) => {
                const on = selected.has(r.id);
                const c = checks[r.id];
                const removed = r.status === 'removed';
                const orphan = isOrphanEvent(r);
                const open = expanded.has(r.id);
                const fact = (label, value) => (
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, fontSize: 12.5, padding: '5px 0', borderTop: '1px solid var(--bb-rule)' }}>
                    <span style={{ opacity: 0.65 }}>{label}</span><span style={{ fontWeight: 600, textAlign: 'right', overflowWrap: 'anywhere' }}>{value}</span>
                  </div>
                );
                const link = (label, testId, onClick) => (
                  <button type="button" onClick={onClick} data-testid={testId} className="bb-press"
                    style={{ flex: 1, minHeight: 38, borderRadius: 999, border: '1px solid var(--bb-clay)', background: 'none', color: 'var(--bb-clay)', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>{label}</button>
                );
                return (
                  <div key={r.id} data-testid={`admin-manage-row-${r.id}`} style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '12px 14px', borderTop: i ? '1px solid var(--bb-rule)' : 'none', color: ink }}>
                    <button type="button" onClick={() => toggle(r.id)} aria-pressed={on} aria-label={on ? T('Bỏ chọn', 'Deselect') : T('Chọn', 'Select')} data-testid={`admin-manage-select-${r.id}`}
                      style={{ flex: 'none', width: 32, height: 32, margin: '-6px 0 0 -6px', border: 'none', background: 'none', padding: 6, cursor: 'pointer' }}>
                      <span aria-hidden style={{ width: 20, height: 20, borderRadius: 10, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                        background: on ? ink : 'transparent', border: `1.5px solid ${on ? ink : 'rgba(var(--bb-fg-rgb),0.3)'}`, color: paper, fontSize: 12, boxSizing: 'border-box' }}>{on ? '✓' : ''}</span>
                    </button>
                    <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 }}>
                      <button type="button" onClick={() => toggleExpanded(r.id)} aria-expanded={open} data-testid={`admin-manage-expand-${r.id}`}
                        style={{ display: 'flex', flexDirection: 'column', gap: 4, textAlign: 'left', border: 'none', background: 'none', padding: 0, color: ink, fontFamily: 'inherit', cursor: 'pointer' }}>
                        <span style={{ display: 'flex', gap: 8, alignItems: 'baseline', width: '100%' }}>
                          <span style={{ flex: 1, fontSize: 15, fontWeight: 600 }}>{r.name}</span>
                          <span aria-hidden style={{ fontSize: 13, opacity: 0.5, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s ease' }}>›</span>
                        </span>
                        <span style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 12, flexWrap: 'wrap' }}>
                          <span style={{ fontSize: 11, fontWeight: 700, padding: '2px 7px', borderRadius: 999,
                            background: removed ? 'rgba(var(--bb-alert-rgb),0.14)' : 'rgba(var(--bb-fg-rgb),0.08)', color: removed ? alert : ink }}>
                            {T(...(STATUS_LABELS[r.status] || [r.status, r.status]))}
                          </span>
                          {orphan && (
                            <span data-testid={`admin-manage-orphan-${r.id}`} style={{ fontSize: 11, fontWeight: 700, padding: '2px 7px', borderRadius: 999, background: 'rgba(var(--bb-alert-rgb),0.12)', color: alert }}>
                              {T('Host đã xoá tài khoản', 'Host account deleted')}
                            </span>
                          )}
                          <span style={{ opacity: 0.7, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{[date(r.starts_at, rowTimeZone(r)), orphan ? '' : r.organizer_name].filter(Boolean).join(' · ')}</span>
                        </span>
                      </button>
                      {removed && <span style={{ fontSize: 12, opacity: 0.75 }}>{T('Lý do: ', 'Reason: ')}{r.removal_reason}</span>}
                      {removed && c?.purgeable && <span style={{ fontSize: 11.5, fontWeight: 600, opacity: 0.7 }}>{T('Chưa từng có đặt chỗ, có thể xoá vĩnh viễn.', 'Never booked, can be deleted permanently.')}</span>}
                      {!removed && isBlocked(c) && (
                        <span data-testid={`admin-manage-blocked-${r.id}`} style={{ fontSize: 12, fontWeight: 600, color: 'var(--bb-honey)' }}>{blockerLine(c, T, orphan)}</span>
                      )}
                      {open && (
                        <div data-testid={`admin-manage-details-${r.id}`} style={{ marginTop: 6, display: 'flex', flexDirection: 'column' }}>
                          {fact(T('Người tổ chức', 'Host'), orphan ? T('Đã xoá tài khoản', 'Account deleted') + (r.organizer_name && r.organizer_name !== 'Deleted organizer' ? ` (${r.organizer_name})` : '') : (r.organizer_name || '—'))}
                          {fact(T('Bắt đầu', 'Starts'), dateTime(r.starts_at, rowTimeZone(r)))}
                          {fact(T('Giá vé', 'Price'), r.price_vnd > 0 ? formatMoney(r.price_vnd, rowCurrency(r)) : T('Miễn phí', 'Free'))}
                          {fact(T('Chỗ', 'Seats'), r.capacity > 0 ? T(`${r.seats_remaining ?? '—'} còn / ${r.capacity}`, `${r.seats_remaining ?? '—'} left of ${r.capacity}`) : '—')}
                          {r.area && fact(T('Khu vực', 'Area'), r.area)}
                          {fact(T('Tạo lúc', 'Created'), dateTime(r.created_at))}
                          {r.submitted_at && fact(T('Gửi duyệt lúc', 'Submitted'), dateTime(r.submitted_at))}
                          {c && fact(T('Đặt chỗ', 'Bookings'), T(`${c.active_bookings} đang hiệu lực · ${c.bookings_ever} tổng`, `${c.active_bookings} active · ${c.bookings_ever} ever`))}
                          {c && (c.unsettled_refunds > 0 || c.open_disputes > 0) && fact(T('Hoàn tiền / tranh chấp', 'Refunds / disputes'), `${c.unsettled_refunds} / ${c.open_disputes}`)}
                          {removed && r.removed_at && fact(T('Gỡ lúc', 'Removed'), dateTime(r.removed_at))}
                          {fact('ID', r.id)}
                          <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                            {r.status === 'review' && link(T('Duyệt ngay', 'Review now'), `admin-manage-review-${r.id}`, () => openAdminEvents(r.id))}
                            {['live', 'ended', 'cancelled'].includes(r.status) && link(T('Xem trang sự kiện', 'View event page'), `admin-manage-open-${r.id}`, () => goEvent(r.id))}
                            {link(T('Sao chép ID', 'Copy ID'), `admin-manage-copy-${r.id}`, () => { try { navigator.clipboard?.writeText(r.id); setBanner(T('Đã sao chép ID.', 'ID copied.')); } catch { /* no clipboard */ } })}
                          </div>
                        </div>
                      )}
                    </span>
                  </div>
                );
              })}
            </div>
          </>
        )}
      </div>

      {selected.size > 0 && (
        <div style={{ position: 'fixed', left: 12, right: 12, bottom: 12, zIndex: 20, maxWidth: 456, margin: '0 auto', padding: '12px 16px 10px', borderRadius: 24,
          background: 'var(--bb-bg)', boxShadow: '0 10px 30px rgba(27,25,22,0.18)', border: '1px solid var(--bb-rule)', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.75, textAlign: 'center' }}>
            {T(`Đã chọn ${selected.size}`, `${selected.size} selected`)}
            {blockedCount > 0 && T(` · ${blockedCount} chưa gỡ được`, ` · ${blockedCount} can't be removed yet`)}
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            {removeIds.length > 0 && (
              <Button label={T(`Gỡ (${removeIds.length})`, `Remove (${removeIds.length})`)} testId="admin-manage-remove" disabled={busy}
                onClick={() => { setReason(''); setReasonFor('remove'); }} style={{ flex: 1, background: alert, color: 'var(--bb-on-alert)' }} />
            )}
            {restoreIds.length > 0 && (
              <Button label={T(`Khôi phục (${restoreIds.length})`, `Restore (${restoreIds.length})`)} testId="admin-manage-restore" disabled={busy} onClick={restore} style={{ flex: 1 }} />
            )}
            {purgeIds.length > 0 && (
              <Button label={T(`Xoá hẳn (${purgeIds.length})`, `Delete (${purgeIds.length})`)} testId="admin-manage-purge" disabled={busy}
                onClick={() => { setReason(''); setReasonFor('purge'); }} style={{ flex: 1, background: alert, color: 'var(--bb-on-alert)' }} />
            )}
          </div>
          <Button variant="tertiary" label={T('Bỏ chọn', 'Clear selection')} onClick={() => setSelected(new Set())} />
        </div>
      )}

      {reasonFor && (
        <div onClick={() => setReasonFor(null)} style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(12,12,12,0.45)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}>
          <div role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()} data-testid="admin-manage-reason-sheet"
            style={{ background: paper, color: ink, width: '100%', maxWidth: 480, borderRadius: '22px 22px 0 0', padding: 22, display: 'flex', flexDirection: 'column', gap: 14, animation: 'banbeSheetIn 0.3s cubic-bezier(.22,.61,.36,1) both' }}>
            <div style={display(22)}>
              {reasonFor === 'purge'
                ? T(`Xoá vĩnh viễn ${purgeIds.length} sự kiện`, `Permanently delete ${en(purgeIds.length, 'event')}`)
                : T(`Gỡ ${removeIds.length} sự kiện`, `Remove ${en(removeIds.length, 'event')}`)}
            </div>
            <p style={{ fontSize: 13.5, lineHeight: 1.5, opacity: 0.8, margin: 0 }}>
              {reasonFor === 'purge'
                ? T('Chỉ áp dụng cho sự kiện đã gỡ và chưa từng có đặt chỗ. Không thể hoàn tác. Hành động được ghi lại.', "Only for removed events that never had a booking. This can't be undone. It's logged.")
                : T('Sự kiện biến mất khỏi Trang chủ, Bản đồ, Tìm kiếm và trang host. Mọi đặt chỗ, thanh toán và lịch sử được giữ. Người tổ chức nhận lý do bên dưới.',
                  'They disappear from Home, Map, Search and host pages. All bookings, payments and history are kept. The host is sent the reason below.')}
            </p>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {QUICK_REASONS.map(q => <ChoiceChip key={q[1]} compact label={T(...q)} selected={reason === T(...q)} onClick={() => setReason(T(...q))} />)}
            </div>
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} maxLength={500} data-testid="admin-manage-reason"
              placeholder={T('Lý do (bắt buộc)', 'Reason (required)')}
              style={{ width: '100%', boxSizing: 'border-box', fontSize: 16, padding: '12px 14px', borderRadius: 14, border: '1px solid var(--bb-rule)', background: paper, color: ink, fontFamily: 'inherit', resize: 'vertical' }} />
            <div style={{ display: 'flex', gap: 10 }}>
              <Button variant="secondary" label={T('Huỷ', 'Cancel')} onClick={() => setReasonFor(null)} style={{ flex: 1 }} />
              <Button label={reasonFor === 'purge' ? T('Xoá vĩnh viễn', 'Delete permanently') : T('Gỡ sự kiện', 'Remove')} testId="admin-manage-reason-confirm"
                disabled={reason.trim().length < 3 || busy} style={{ flex: 1 }}
                onClick={() => { const ids = reasonFor === 'purge' ? purgeIds : removeIds; const a = reasonFor; setReasonFor(null); run(a, ids, reason); }} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
