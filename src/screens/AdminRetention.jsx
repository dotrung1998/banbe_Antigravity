import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, display, fieldGlass, alert, rule } from '../theme.js';
import {
  RANGE_DAYS, DEFAULT_RANGE_DAYS, rangeFor, orderedMarkets, marketRows, marketLabel, fmtCount, fmtMedian, reportError,
} from '../lib/retentionReport.js';

// Admin › Retention report (migration 196). Aggregate numbers only, straight from admin_retention_report: the server
// checks is_platform_admin(), excludes test accounts and hides every group under 20 people. iOS twin:
// apps/ios/BanbeApp/Views/AdminRetentionView.swift.
const ERRORS = {
  NOT_AUTHORIZED: ['Bạn không có quyền xem báo cáo này.', 'You are not allowed to see this report.'],
  NOT_DEPLOYED: ['Máy chủ chưa có báo cáo này (chạy migration 196).', 'The server does not have this report yet (apply migration 196).'],
  NETWORK: ['Không tải được báo cáo. Thử lại nhé.', "Couldn't load the report. Try again."],
};

export default function AdminRetention() {
  const { state: s, T, set } = useBanBe();
  const [days, setDays] = useState(DEFAULT_RANGE_DAYS);
  const [report, setReport] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const isAdmin = s.accountType === 'admin';

  useEffect(() => {
    if (!isAdmin) return undefined;
    let live = true;
    const { from, to } = rangeFor(days);
    setLoading(true);
    setError('');
    supabase.rpc('admin_retention_report', { p_from: from, p_to: to }).then(({ data, error: e }) => {
      if (!live) return;
      setLoading(false);
      const code = reportError(data, e);
      if (code) { setReport(null); setError(code); } else setReport(data);
    }, () => { if (live) { setLoading(false); setError('NETWORK'); } });
    return () => { live = false; };
  }, [isAdmin, days]);

  if (!isAdmin) return null;
  const msg = error ? (ERRORS[error] || ERRORS.NETWORK) : null;

  const chip = (n) => (
    <button type="button" key={n} onClick={() => setDays(n)} data-testid={`admin-retention-range-${n}`} aria-pressed={days === n}
      style={{
        appearance: 'none', border: 'none', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, padding: '8px 14px', minHeight: 36,
        borderRadius: 999, cursor: 'pointer', whiteSpace: 'nowrap', background: days === n ? ink : 'transparent', color: days === n ? paper : ink,
      }}>{T(`${n} ngày`, `${n} days`)}</button>
  );
  const cell = { padding: '10px 14px', fontSize: 13.5 };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin retention report">
      <div onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminReview' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-retention-back">
        ‹ {T('Quản trị', 'Admin')}
      </div>
      <div style={{ padding: '14px 22px 40px' }}>
        <h1 style={{ ...display(26, { margin: 0 }) }}>{T('Báo cáo quay lại', 'Retention report')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '8px 0 0' }} data-testid="admin-retention-privacy">
          {T('Nhóm dưới 20 người được ẩn để bảo vệ quyền riêng tư. Tài khoản thử nghiệm không được tính.',
            'Groups under 20 people are hidden to protect privacy. Test accounts are excluded.')}
        </p>
        <div role="group" style={{ display: 'flex', gap: 6, marginTop: 16, flexWrap: 'wrap' }}>{RANGE_DAYS.map(chip)}</div>
        {report && (
          <p style={{ fontSize: 12, opacity: 0.6, margin: '10px 2px 0' }} data-testid="admin-retention-period">
            {report.from} → {report.to}
          </p>
        )}
        {loading && !report && <p style={{ fontSize: 13, opacity: 0.7, marginTop: 18 }}>{T('Đang tải…', 'Loading…')}</p>}
        {msg && <p role="alert" data-testid="admin-retention-error" style={{ fontSize: 12.5, color: alert, margin: '14px 2px 0' }}>{T(msg[0], msg[1])}</p>}

        {report && orderedMarkets(report.markets).map(m => {
          const [vi, en] = marketLabel(m.market);
          return (
            <section key={m.market} data-testid={`admin-retention-market-${m.market}`} style={{ marginTop: 22 }}>
              <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 2px 8px' }}>{T(vi, en)}</h2>
              <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
                {marketRows(m).map((r, i) => (
                  <div key={r.key} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, borderTop: i ? `1px solid ${rule}` : 'none', ...cell }}>
                    <span style={{ opacity: 0.8 }}>{T(r.vi, r.en)}</span>
                    <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums', textAlign: 'right' }} data-testid={`admin-retention-${m.market}-${r.key}`}>{r.value}</span>
                  </div>
                ))}
              </div>
            </section>
          );
        })}

        {report && (
          <section style={{ marginTop: 28 }} data-testid="admin-retention-notifications">
            <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 2px 8px' }}>{T('Thông báo theo loại', 'Notifications by kind')}</h2>
            <div style={{ ...fieldGlass({ overflowX: 'auto' }) }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontVariantNumeric: 'tabular-nums' }}>
                <thead>
                  <tr style={{ fontSize: 11.5, textAlign: 'right', opacity: 0.7 }}>
                    <th style={{ ...cell, fontSize: 11.5, textAlign: 'left', fontWeight: 600 }}>{T('Loại', 'Kind')}</th>
                    <th style={{ ...cell, fontSize: 11.5, fontWeight: 600 }}>{T('Đã gửi', 'Sent')}</th>
                    <th style={{ ...cell, fontSize: 11.5, fontWeight: 600 }}>{T('Đã đọc', 'Read')}</th>
                    <th style={{ ...cell, fontSize: 11.5, fontWeight: 600 }}>{T('Phút tới khi đọc (trung vị)', 'Median min to read')}</th>
                  </tr>
                </thead>
                <tbody>
                  {(report.notifications || []).map(n => (
                    <tr key={n.kind} style={{ borderTop: `1px solid ${rule}`, textAlign: 'right' }} data-testid={`admin-retention-kind-${n.kind}`}>
                      <td style={{ ...cell, textAlign: 'left', wordBreak: 'break-word' }}>{n.kind}</td>
                      <td style={cell}>{fmtCount(n.sent)}</td>
                      <td style={cell}>{fmtCount(n.read)}</td>
                      <td style={cell}>{fmtMedian(n.read_minutes_median)}</td>
                    </tr>
                  ))}
                  {!(report.notifications || []).length && (
                    <tr><td colSpan={4} style={{ ...cell, opacity: 0.7 }}>{T('Chưa có loại nào đủ 20 người.', 'No kind has reached 20 people yet.')}</td></tr>
                  )}
                </tbody>
              </table>
            </div>
            {Number(report.notification_kinds_hidden) > 0 && (
              <p style={{ fontSize: 12, opacity: 0.65, margin: '8px 2px 0' }} data-testid="admin-retention-kinds-hidden">
                {T(`${report.notification_kinds_hidden} loại dưới 20 người được ẩn.`, `${report.notification_kinds_hidden} kind(s) under 20 people hidden.`)}
              </p>
            )}
          </section>
        )}
      </div>
    </div>
  );
}
