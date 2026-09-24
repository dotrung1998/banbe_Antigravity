import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd, formatShortDate } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';

const STATUS_LABEL = {
  owed: ['Khoản hoàn tiền này đang cần được xử lý', 'This refund is still being processed'],
  host_marked_sent: ['Đang chờ bạn xác nhận đã nhận tiền', "Awaiting your confirmation"],
  disputed: ['Đang tranh chấp', 'Disputed'],
};

// Refund MVP (product rule A) — a persistent list of every active refund
// claim for the signed-in goer, reachable from Account and from Payment &
// refund accounts, independent of any notification.
export default function MyRefunds() {
  const { state, T, backFromMyRefunds, loadMyRefunds, openPaymentDetails } = useGoc();
  const s = state;

  useEffect(() => { loadMyRefunds(); }, [loadMyRefunds]);
  useEffect(() => {
    const id = setInterval(() => loadMyRefunds(), 6000);
    return () => clearInterval(id);
  }, [loadMyRefunds]);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="MyRefunds">
      <div onClick={backFromMyRefunds} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="my-refunds-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>{T('Hoàn tiền', 'Refunds')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Các khoản hoàn tiền đang cần xử lý của bạn.', 'Your refund claims that are still active.')}
        </p>
      </div>

      <div style={{ margin: '18px 22px 40px' }}>
        {s.myRefunds.length === 0 ? (
          <div style={{ ...fieldGlass({ padding: '20px 16px', textAlign: 'center' }) }}>
            <p style={{ fontSize: 13, color: ink, margin: 0 }}>
              {s.myRefundsLoading ? T('Đang tải…', 'Loading…') : T('Không có khoản hoàn tiền nào đang xử lý.', 'No refunds in progress.')}
            </p>
          </div>
        ) : (
          <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
            {s.myRefunds.map((c, i, arr) => {
              const label = STATUS_LABEL[c.status] || ['—', '—'];
              const overdue = (c.status === 'owed' && c.refund_due_at && new Date(c.refund_due_at).getTime() < Date.now())
                || (c.status === 'disputed' && c.host_response_due_at && new Date(c.host_response_due_at).getTime() < Date.now());
              return (
                <div
                  key={c.id}
                  onClick={() => c.bookingId && openPaymentDetails(c.bookingId)}
                  style={{ padding: '14px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}
                  data-testid="my-refunds-row"
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }}>
                    <span style={{ ...display(14) }}>{c.eventName || T('Sự kiện', 'Event')}</span>
                    <span style={{ fontSize: 13, fontWeight: 600, color: ink }}>{formatVnd(c.amount_vnd)}</span>
                  </div>
                  <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
                    <span style={{ fontSize: 11.5, fontWeight: 600, color: overdue ? alert : ink, opacity: overdue ? 1 : 0.7 }}>
                      {overdue ? T('Quá hạn hoàn tiền.', 'Refund overdue.') : T(...label)}
                    </span>
                  </div>
                  {c.status === 'owed' && c.refund_due_at && (
                    <p style={{ fontSize: 11, color: ink, opacity: 0.6, margin: '4px 0 0' }}>
                      {T(`Trước ${formatShortDate(c.refund_due_at)}`, `Before ${formatShortDate(c.refund_due_at, 'en')}`)}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
