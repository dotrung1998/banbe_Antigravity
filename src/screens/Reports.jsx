import { useEffect, useRef } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, alert, display, cardGlass, fieldGlass, inkButton } from '../theme.js';

const ROLE_LABEL = { personal: ['Cá nhân', 'Personal'], host: ['Tổ chức', 'Host'], admin: ['Quản trị', 'Admin'] };

function formatValue(metric, T) {
  if (metric.unit === 'vnd') return `${Number(metric.value || 0).toLocaleString('vi-VN')} đ`;
  if (metric.unit === 'days') return T(`${metric.value} ngày`, `${metric.value} days`);
  return String(metric.value ?? 0);
}

function formatVnDate(iso) {
  return new Date(iso).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', day: '2-digit', month: '2-digit' });
}

/// Account extension (2026-09-27, Stage 3) — one hand-rolled `<canvas>` bar
/// chart per card, no charting library: this app's KPI ranges (7-90 days,
/// a handful of metrics) don't need one, and a plain canvas is also what
/// makes "Lưu ảnh" trivial (`canvas.toDataURL()` — the title/range/labels
/// are baked into the SAME canvas draw, not a separate overlay, so the
/// saved PNG always matches what's on screen).
function MiniChart({ metric, rangeLabel, canvasRef }) {
  const localRef = useRef(null);
  const ref = canvasRef || localRef;
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas || !metric.series?.length) return;
    const dpr = window.devicePixelRatio || 1;
    const W = 560, H = 200;
    canvas.width = W * dpr; canvas.height = H * dpr;
    canvas.style.width = `${W}px`; canvas.style.height = `${H}px`;
    const c = canvas.getContext('2d');
    c.scale(dpr, dpr);
    c.fillStyle = paper;
    c.fillRect(0, 0, W, H);
    c.fillStyle = ink;
    c.font = '600 13px sans-serif';
    c.fillText(metric.label, 12, 20);
    c.font = '11px sans-serif';
    c.globalAlpha = 0.65;
    c.fillText(rangeLabel, 12, 36);
    c.globalAlpha = 1;

    const series = metric.series;
    const max = Math.max(1, ...series.map(p => p.v));
    const chartTop = 50, chartBottom = H - 26, chartLeft = 12, chartRight = W - 12;
    const barGap = 2;
    const barWidth = Math.max(1, (chartRight - chartLeft) / series.length - barGap);
    series.forEach((point, i) => {
      const h = ((point.v || 0) / max) * (chartBottom - chartTop);
      const x = chartLeft + i * (barWidth + barGap);
      c.fillStyle = ink;
      c.globalAlpha = point.v > 0 ? 0.82 : 0.12;
      c.fillRect(x, chartBottom - h, barWidth, Math.max(1, h));
      c.globalAlpha = 1;
    });
    c.strokeStyle = rule;
    c.beginPath(); c.moveTo(chartLeft, chartBottom); c.lineTo(chartRight, chartBottom); c.stroke();
    c.fillStyle = ink;
    c.globalAlpha = 0.6;
    c.font = '10px sans-serif';
    c.fillText(formatVnDate(series[0].d), chartLeft, H - 10);
    const lastLabel = formatVnDate(series[series.length - 1].d);
    c.fillText(lastLabel, chartRight - c.measureText(lastLabel).width, H - 10);
    c.globalAlpha = 1;
  }, [metric, rangeLabel, ref]);
  return <canvas ref={ref} style={{ width: '100%', maxWidth: 560, display: 'block', borderRadius: 10 }} />;
}

function saveCanvasPng(canvas, filename) {
  if (!canvas) return;
  const url = canvas.toDataURL('image/png');
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
}

function MetricCard({ metric, expanded, onToggle, rangeLabel, T, onExportCsv }) {
  const canvasRef = useRef(null);
  const rows = metric.rows || [];
  return (
    <div style={{ ...cardGlass({ padding: 0, overflow: 'hidden' }) }} data-testid={`kpi-card-${metric.key}`}>
      <div
        onClick={onToggle}
        style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 16px', cursor: 'pointer' }}
        data-testid={`kpi-card-toggle-${metric.key}`}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: ink }}>{metric.label}</span>
          <span style={{ fontSize: 11, color: ink, opacity: 0.6 }}>{rangeLabel}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 16, fontWeight: 700, color: ink }} data-testid={`kpi-card-value-${metric.key}`}>
            {formatValue(metric, T)}
          </span>
          <span aria-hidden style={{ fontSize: 13, color: ink, opacity: 0.55, transform: expanded ? 'rotate(180deg)' : 'none' }}>▾</span>
        </div>
      </div>
      {expanded && (
        <div style={{ padding: '0 16px 16px', borderTop: `1px solid ${rule}` }}>
          {metric.series?.length ? (
            <div style={{ paddingTop: 14 }}>
              <MiniChart metric={metric} rangeLabel={rangeLabel} canvasRef={canvasRef} />
              <div
                onClick={() => saveCanvasPng(canvasRef.current, `banbe-${metric.key}.png`)}
                data-testid={`kpi-save-png-${metric.key}`}
                style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer', marginTop: 6, display: 'inline-block' }}
              >
                {T('Lưu ảnh', 'Save image')}
              </div>
            </div>
          ) : (
            <p style={{ fontSize: 11.5, color: ink, opacity: 0.6, paddingTop: 14, margin: 0 }}>
              {T('Số liệu hiện tại, không theo biểu đồ thời gian.', 'A current total, not a time series.')}
            </p>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: 14 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Dữ liệu chi tiết', 'Underlying data')}</span>
            <div onClick={() => onExportCsv(metric.key)} data-testid={`kpi-export-csv-${metric.key}`} style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>
              {T('Tải CSV', 'Download CSV')}
            </div>
          </div>
          {rows.length === 0 ? (
            <p style={{ fontSize: 12, color: ink, opacity: 0.6, marginTop: 8 }}>{T('Không có dữ liệu trong khoảng thời gian này.', 'No data in this range.')}</p>
          ) : (
            <div style={{ marginTop: 8, maxHeight: 220, overflowY: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11.5 }}>
                <thead>
                  <tr>
                    {Object.keys(rows[0]).map(col => (
                      <th key={col} style={{ textAlign: 'left', padding: '4px 6px', color: ink, opacity: 0.6, borderBottom: `1px solid ${rule}`, whiteSpace: 'nowrap' }}>{col}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.slice(0, 50).map((row, i) => (
                    <tr key={i}>
                      {Object.keys(rows[0]).map(col => (
                        <td key={col} style={{ padding: '4px 6px', color: ink, borderBottom: `1px solid ${rule}`, whiteSpace: 'nowrap' }}>
                          {row[col] == null ? '' : typeof row[col] === 'boolean' ? (row[col] ? '✓' : '') : String(row[col])}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// Account extension (2026-09-27, Stage 3) — one role-scoped KPI dashboard,
// reused across all three roles (a "Số liệu & báo cáo" row on each visible
// Account tab opens this with s.reportsScope already set to which one).
// Every on-screen number, CSV row, PDF line and JSON field comes from the
// SAME s.reportsData payload (get_account_kpis, migration 097) — never a
// second, independently-computed source, so they can't disagree.
export default function Reports() {
  const {
    state, T, backFromReports, setReportsRangeDays, setReportsCustomRange, toggleReportCard,
    expandAllReportCards, collapseAllReportCards, exportReportCardCsv, exportReportsJson, exportReportsPdf, loadAccountKpis,
  } = useGoc();
  const s = state;
  const roleLabel = ROLE_LABEL[s.reportsScope] ? T(...ROLE_LABEL[s.reportsScope]) : s.reportsScope;
  const data = s.reportsData;

  const rangeLabel = data
    ? `${new Date(data.range.start).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })} – ${new Date(data.range.end).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}`
    : '';

  return (
    <div style={{ minHeight: '100%', background: paper, animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both' }} data-screen-label="Reports">
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span onClick={backFromReports} style={{ fontSize: 13, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</span>
      </div>
      <div style={{ padding: '10px 20px 0' }}>
        <span style={{ ...display(24) }}>{T('Số liệu & báo cáo', 'Metrics & reports')}</span>
        <p style={{ fontSize: 12, color: ink, opacity: 0.65, margin: '4px 0 0' }}>{roleLabel}</p>
      </div>

      <div style={{ display: 'flex', gap: 6, padding: '16px 20px 0', flexWrap: 'wrap' }} data-testid="kpi-range-picker">
        {[7, 30, 90].map(d => (
          <span
            key={d}
            onClick={() => setReportsRangeDays(d)}
            data-testid={`kpi-range-${d}`}
            style={{
              fontSize: 12, fontWeight: 600, padding: '7px 14px', borderRadius: 999, cursor: 'pointer',
              background: s.reportsRangeDays === d ? ink : 'transparent', color: s.reportsRangeDays === d ? paper : ink,
              border: s.reportsRangeDays === d ? 'none' : `1px solid ${rule}`,
            }}
          >{d} {T('ngày', 'd')}</span>
        ))}
        <input
          type="date" value={s.reportsCustomStart} data-testid="kpi-range-custom-start"
          onChange={(e) => setReportsCustomRange(e.target.value, s.reportsCustomEnd || e.target.value)}
          style={{ ...fieldGlass({ padding: '6px 8px', fontSize: 12 }) }}
        />
        <input
          type="date" value={s.reportsCustomEnd} data-testid="kpi-range-custom-end"
          onChange={(e) => setReportsCustomRange(s.reportsCustomStart || e.target.value, e.target.value)}
          style={{ ...fieldGlass({ padding: '6px 8px', fontSize: 12 }) }}
        />
      </div>

      <div style={{ display: 'flex', gap: 14, padding: '12px 20px 0' }}>
        <span onClick={expandAllReportCards} data-testid="kpi-expand-all" style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Mở tất cả', 'Expand all')}</span>
        <span onClick={collapseAllReportCards} data-testid="kpi-collapse-all" style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Thu gọn tất cả', 'Collapse all')}</span>
      </div>

      <div style={{ padding: '16px 20px 0', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {s.reportsLoading && !data && (
          <p style={{ fontSize: 13, color: ink, textAlign: 'center', padding: '40px 0' }}>{T('Đang tải…', 'Loading…')}</p>
        )}
        {s.reportsError && (
          <div style={{ ...cardGlass({ padding: 16 }) }}>
            <p style={{ fontSize: 12.5, color: alert, margin: 0 }}>{s.reportsError}</p>
            <div onClick={loadAccountKpis} style={{ ...inkButton({ marginTop: 10, padding: 10, fontSize: 12.5 }) }}>{T('Thử lại', 'Retry')}</div>
          </div>
        )}
        {data && !data.metrics.length && (
          <p style={{ fontSize: 13, color: ink, opacity: 0.6, textAlign: 'center', padding: '40px 0' }}>{T('Chưa có số liệu.', 'Nothing to show yet.')}</p>
        )}
        {data && data.metrics.map(metric => (
          <MetricCard
            key={metric.key}
            metric={metric}
            expanded={s.reportsExpanded.has(metric.key)}
            onToggle={() => toggleReportCard(metric.key)}
            rangeLabel={metric.series?.length ? rangeLabel : T('Hiện tại', 'Right now')}
            T={T}
            onExportCsv={exportReportCardCsv}
          />
        ))}
      </div>

      {data && (
        <div style={{ display: 'flex', gap: 10, padding: '18px 20px 40px' }}>
          <div onClick={exportReportsJson} data-testid="kpi-export-json" style={{ ...fieldGlass({ flex: 1, padding: 13, textAlign: 'center', fontSize: 12.5, fontWeight: 600, cursor: 'pointer' }) }}>
            {T('Tải dữ liệu JSON', 'Download JSON')}
          </div>
          <div
            onClick={s.reportsExportBusy ? undefined : exportReportsPdf}
            data-testid="kpi-export-pdf"
            style={{ ...inkButton({ flex: 1, padding: 13, fontSize: 12.5, opacity: s.reportsExportBusy ? 0.6 : 1 }) }}
          >
            {s.reportsExportBusy === 'pdf' ? T('Đang tạo…', 'Generating…') : T('Tải báo cáo PDF', 'Download PDF report')}
          </div>
        </div>
      )}
    </div>
  );
}
