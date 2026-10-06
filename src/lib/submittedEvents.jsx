import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS } from '../data/events.js';
import { supabase } from './supabase.js';
import { paper, ink, rule, alert, display, fieldGlass } from '../theme.js';
import PendingEventSheet from '../screens/sheets/PendingEventSheet.jsx';

// Host-side review tracking (web port of iOS myPendingEvents /
// myNeedsFixEvents + the "Submitted Events" row, commit 7fd7086).
//
// Reads this account's own events straight from `events` (RLS lets an owner
// read their own pending/draft rows) instead of the realEventsById cache,
// which is only filled once and would never notice an admin approving or
// sending an event back. Polled every 30s (same cadence as iOS) and on tab
// focus, so the badge drops/rises on its own.
//   pending  = status 'review'                           (waiting for admin)
//   needsFix = status 'draft' AND a rejection_reason     (admin sent it back)

const COLS = 'id, name, status, submitted_at, reviewed_at, rejection_reason, withdrawn_at';
const COLS_REMIND = `${COLS}, admin_remind_count, last_admin_reminded_at`;
const POLL_MS = 30000;

export function useSubmittedEvents(enabled = true) {
  const { state: s } = useBanBe();
  const keys = useMemo(() => (s.myOrgEventKeys || []).filter(k => !EVENTS.some(e => e.key === k)), [s.myOrgEventKeys]);
  const keyStr = keys.join(',');
  const [rows, setRows] = useState([]);
  const [loaded, setLoaded] = useState(false);
  const noRemindCols = useRef(false); // migration 148 not applied -> don't retry with those columns

  const refresh = useCallback(async () => {
    if (!enabled || !keyStr) { setRows([]); setLoaded(true); return; }
    const ids = keyStr.split(',');
    const run = (cols) => supabase.from('events').select(cols).in('id', ids).in('status', ['review', 'draft']);
    let res = await run(noRemindCols.current ? COLS : COLS_REMIND);
    if (res.error && !noRemindCols.current) {
      noRemindCols.current = true;
      res = await run(COLS);
    }
    if (res.error) { console.warn('submitted events load failed:', res.error.message); return; }
    setRows(res.data || []);
    setLoaded(true);
  }, [enabled, keyStr]);

  useEffect(() => {
    refresh();
    if (!enabled || !keyStr) return undefined;
    const t = setInterval(refresh, POLL_MS);
    const onVis = () => { if (document.visibilityState === 'visible') refresh(); };
    document.addEventListener('visibilitychange', onVis);
    return () => { clearInterval(t); document.removeEventListener('visibilitychange', onVis); };
  }, [refresh, enabled, keyStr]);

  const pending = useMemo(() => rows.filter(r => r.status === 'review')
    .sort((a, b) => new Date(b.submitted_at || 0) - new Date(a.submitted_at || 0)), [rows]);
  const needsFix = useMemo(() => rows.filter(r => r.status === 'draft' && (r.rejection_reason || '').trim()), [rows]);
  return { pending, needsFix, total: pending.length + needsFix.length, loaded, refresh };
}

export function useFormatWhen() {
  const { T } = useBanBe();
  const locale = T('vi-VN', 'en-GB');
  return (iso) => (iso ? new Date(iso).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' }) : '');
}

/** Expandable "Submitted Events" row for the Host tab. */
export function SubmittedEventsRow({ submitted }) {
  const { T, goDashboard } = useBanBe();
  const fmt = useFormatWhen();
  const [open, setOpen] = useState(false);
  const [viewing, setViewing] = useState(null);
  const { pending, needsFix, total, refresh } = submitted;

  return (
    <div data-testid="account-submitted-events" style={{ ...fieldGlass({ margin: '8px 20px 0', display: 'flex', flexDirection: 'column', overflow: 'hidden' }) }}>
      <div
        onClick={() => setOpen(v => !v)}
        data-testid="account-group-submittedEvents"
        style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', cursor: 'pointer' }}
      >
        <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}>
          <span aria-hidden style={{ width: 22, textAlign: 'center', opacity: 0.72 }}>⏳</span>
          {T('Sự Kiện Đã Gửi Chờ Duyệt', 'Submitted Events')}
        </span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {total > 0 && (
            <span
              role="status"
              aria-label={T(`${total} mục mới`, `${total} new item(s)`)}
              title={String(total)}
              data-testid="account-group-submittedEvents-badge"
              style={{ fontSize: 11, fontWeight: 700, color: paper, background: alert, borderRadius: 999, padding: '2px 7px', minWidth: 18, textAlign: 'center' }}
            >
              {total > 99 ? '99+' : total}
            </span>
          )}
          <span style={{ fontSize: 15, color: ink, lineHeight: 1, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>›</span>
        </span>
      </div>

      {open && (
        <div>
          {total === 0 && (
            <p style={{ fontSize: 12, color: ink, opacity: 0.65, margin: 0, padding: '0 16px 14px' }}>
              {T('Không có sự kiện nào đang chờ duyệt.', 'No events are waiting for review.')}
            </p>
          )}
          {pending.map(r => (
            <div key={r.id} data-testid={`account-pending-${r.id}`} style={{ borderTop: `1px solid ${rule}`, padding: '13px 16px', display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'center' }}>
                <span style={{ ...display(15) }}>{r.name}</span>
                <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.65, flex: 'none' }}>{T('Đang chờ Banbe duyệt', 'Waiting for Banbe to review')}</span>
              </div>
              {r.submitted_at && <span style={{ fontSize: 11, color: ink, opacity: 0.6 }}>{T(`Gửi lúc ${fmt(r.submitted_at)}`, `Submitted ${fmt(r.submitted_at)}`)}</span>}
              <span onClick={() => setViewing(r)} data-testid={`account-view-pending-${r.id}`} style={{ fontSize: 12, fontWeight: 600, color: ink, border: `1px solid ${rule}`, borderRadius: 999, padding: '7px 16px', alignSelf: 'flex-start', cursor: 'pointer' }}>
                {T('Xem', 'View')}
              </span>
            </div>
          ))}
          {needsFix.length > 0 && (
            <div
              onClick={() => goDashboard('profile')}
              data-testid="account-needs-fix-link"
              style={{ borderTop: `1px solid ${rule}`, padding: '13px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }}
            >
              <span style={{ fontSize: 12.5, fontWeight: 600, color: alert, textDecoration: 'underline' }}>
                {T(`${needsFix.length} sự kiện cần chỉnh sửa — sửa & gửi lại`, `${needsFix.length} event(s) need fixing — fix & resubmit`)}
              </span>
              <span style={{ fontSize: 13, color: ink, opacity: 0.5 }}>›</span>
            </div>
          )}
        </div>
      )}
      {viewing && <PendingEventSheet eventId={viewing.id} name={viewing.name} onClose={() => setViewing(null)} onChanged={refresh} />}
    </div>
  );
}
