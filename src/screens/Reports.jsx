import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, rule, alert, honey, honeyBg, display, fieldGlass, inkButton } from '../theme.js';
import HostTitleIcon from './HostTitleIcon.jsx';
import { metricLabel } from '../lib/reportMetricLabels.js';
import { PROFILE_PALETTE_COLORS } from '../lib/profileTheme.js';
import * as RP from '../lib/reportsPresentation.js';

// Metrics & Reports — a role-aware dashboard over the ONE canonical get_account_kpis payload (migration 097):
// header + range, one hero insight, KPI grid, needs attention, breakdowns, trends, all metrics, and a per-metric
// details sheet. Web port of the iOS dashboard (notes 43 + 46); every mapping/format rule lives in
// lib/reportsPresentation.js (unit-tested). The exports (CSV/JSON/PDF in BanBeContext, the chart PNG below) are
// unchanged: same functions, same bytes.

const MOSS = PROFILE_PALETTE_COLORS.moss;
const muted = (a) => `rgba(var(--bb-fg-rgb), ${a})`;

/// Unchanged from the previous screen: the canvas the "Save chart image" PNG is drawn from (title/range/labels
/// baked into the same draw, so the saved image always matches).
function MiniChart({ metric, rangeLabel, canvasRef, T }) {
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
    c.fillText(metricLabel(metric, T), 12, 20);
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
    const formatVnDate = (iso) => new Date(iso).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', day: '2-digit', month: '2-digit' });
    c.fillText(formatVnDate(series[0].d), chartLeft, H - 10);
    const lastLabel = formatVnDate(series[series.length - 1].d);
    c.fillText(lastLabel, chartRight - c.measureText(lastLabel).width, H - 10);
    c.globalAlpha = 1;
  }, [metric, rangeLabel, ref, T]);
  return <canvas ref={ref} style={{ width: '100%', maxWidth: 560, display: 'block', borderRadius: 10 }} />;
}

function saveCanvasPng(canvas, filename) {
  if (!canvas) return;
  const url = canvas.toDataURL('image/png');
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
}

// ---- glyphs (decoration only; always beside the metric's title) ----

const GLYPHS = {
  bookmark: 'M7 4h10v16l-5-3.5L7 20z',
  ticket: 'M4 8a2 2 0 0 0 0 4v4h16v-4a2 2 0 0 1 0-4V4H4zM10 4v12',
  check: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM8 12l3 3 5-6',
  calendar: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
  refund: 'M12 3a9 9 0 1 1-8.5 6M3 4v5h5',
  alert: 'M12 3l10 17H2zM12 10v5M12 18v.5',
  megaphone: 'M4 10v4h3l8 4V6L7 10zM18 9a4 4 0 0 1 0 6',
  people: 'M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM3 20a6 6 0 0 1 12 0M17 11a3 3 0 1 0 0-6M21 20a6 6 0 0 0-4-5.6',
  money: 'M3 6h18v12H3zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM6 9v.5M18 15v-.5',
  tray: 'M4 13l2-8h12l2 8v6H4zM4 13h5l1 2h4l1-2h5',
  dispute: 'M4 4h16v12H9l-5 4zM12 7v4M12 13.5v.5',
  hourglass: 'M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9s8 4 8 9',
  sparkle: 'M12 3l2 6 6 2-6 2-2 6-2-6-6-2 6-2z',
  chart: 'M4 20h16M7 16v-5M12 16V7M17 16v-8',
};

function Glyph({ name, size = 28 }) {
  return (
    <span aria-hidden style={{
      width: size, height: size, flex: '0 0 auto', borderRadius: '50%', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      background: `${MOSS}80`, color: muted(0.8),
    }}>
      <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d={GLYPHS[name] || GLYPHS.chart} />
      </svg>
    </span>
  );
}

const Chevron = () => <span aria-hidden style={{ fontSize: 15, opacity: 0.45, lineHeight: 1 }}>›</span>;

// ---- surfaces ----

const card = (extra) => ({
  background: 'var(--bb-field)', borderRadius: 20, padding: 16, boxShadow: '0 4px 12px var(--bb-shadow)',
  border: '1px solid rgba(var(--bb-fg-rgb), 0.06)', color: ink, ...extra,
});
const heroSurface = {
  ...card({ borderRadius: 24, padding: 20, boxShadow: '0 8px 18px var(--bb-shadow)' }),
  background: `linear-gradient(135deg, ${MOSS}8C, ${MOSS}00 70%), var(--bb-field)`,
};
const buttonReset = { appearance: 'none', font: 'inherit', textAlign: 'left', cursor: 'pointer', width: '100%', display: 'block' };

function SectionTitle({ children, count }) {
  return (
    <h2 style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '14px 0 0', fontSize: 14, fontWeight: 600, color: muted(0.75), fontFamily: 'inherit' }}>
      {children}
      {count != null && (
        <span style={{ fontSize: 11.5, fontWeight: 700, padding: '1px 7px', borderRadius: 999, background: muted(0.08), color: muted(0.7) }}>{count}</span>
      )}
    </h2>
  );
}

// ---- charts ----

/// Dashboard-only daily bars: data first, no axes or grid. Every day reaching the peak value is full-strength;
/// only the first of them (the day the stats name) carries the value. The first/last days name the range.
function DailyBars({ metric, height = 104, T }) {
  const pts = metric.series;
  const peak = metric.summary?.peak;
  const max = Math.max(1, ...pts.map(p => p.value));
  const top = max * 1.28; // headroom for the peak label
  const W = 100, gap = pts.length > 45 ? 0.15 : 0.38;
  const slot = W / pts.length;
  const bw = slot * (1 - gap);
  return (
    <div role="img" aria-label={`${metric.title}. ${RP.seriesSentence(metric, T)}`}>
      <div style={{ position: 'relative', height }}>
        <svg width="100%" height={height} viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" style={{ display: 'block' }}>
          {pts.map((p, i) => {
            const atPeak = peak && p.value === peak.value;
            const h = p.value > 0 ? (p.value / top) * height : Math.max(1, height * 0.03);
            return (
              <rect key={p.dayKey} x={i * slot + (slot - bw) / 2} y={height - h} width={bw} height={h}
                rx={pts.length > 45 ? 0.3 : 0.8}
                fill="currentColor" style={{ color: ink }} opacity={atPeak ? 0.95 : p.value > 0 ? 0.5 : 0.12} />
            );
          })}
        </svg>
        {peak && (() => {
          const i = pts.findIndex(p => p.dayKey === peak.dayKey);
          const h = (peak.value / top) * height;
          return (
            <span style={{
              position: 'absolute', left: `${((i + 0.5) * slot)}%`, bottom: h + 3, transform: 'translateX(-50%)',
              fontSize: 10.5, fontWeight: 700, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap',
            }}>{RP.compact(peak.value, metric.kind, T)}</span>
          );
        })()}
      </div>
      <div aria-hidden style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6, fontSize: 10.5, color: muted(0.55), fontVariantNumeric: 'tabular-nums' }}>
        <span>{RP.formatDay(pts[0].date)}</span>
        <span>{RP.formatDay(pts[pts.length - 1].date)}</span>
      </div>
    </div>
  );
}

/// Same idea as iOS's sparkline: compact bars, zero days as faint stubs.
function Sparkline({ metric, height = 22 }) {
  const pts = metric.series;
  const max = Math.max(1, ...pts.map(p => p.value));
  const slot = 100 / pts.length;
  return (
    <svg aria-hidden width="100%" height={height} viewBox={`0 0 100 ${height}`} preserveAspectRatio="none" style={{ display: 'block', color: ink }}>
      {pts.map((p, i) => {
        const h = p.value > 0 ? (p.value / max) * height : Math.max(1, height * 0.04);
        return <rect key={p.dayKey} x={i * slot + slot * 0.15} y={height - h} width={slot * 0.7} height={h} fill="currentColor" opacity={p.value > 0 ? 0.85 : 0.14} />;
      })}
    </svg>
  );
}

/// Peak / active days / daily average, read off the same series. Wraps to rows on a narrow screen.
function SeriesStats({ metric, T }) {
  const s = metric.summary;
  const items = [
    s.peak && [T('Cao nhất', 'Peak'), RP.compact(s.peak.value, metric.kind, T), RP.formatDay(s.peak.date)],
    [T('Hoạt động', 'Active days'), `${s.activeDays}/${s.dayCount}`, T('ngày', 'days')],
    [T('Trung bình', 'Daily average'), RP.dailyAverageText(s, metric.kind, T), null],
  ].filter(Boolean);
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', rowGap: 10 }}>
      {items.map(([label, value, detail], i) => (
        <div key={label} style={{ flex: '1 1 30%', minWidth: 92, paddingLeft: i ? 12 : 0, borderLeft: i ? `1px solid ${muted(0.12)}` : 'none' }}>
          <div style={{ fontSize: 11.5, color: muted(0.6), whiteSpace: 'nowrap' }}>{label}</div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 2 }}>
            <span style={{ fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{value}</span>
            {detail && <span style={{ fontSize: 11.5, color: muted(0.6) }}>{detail}</span>}
          </div>
        </div>
      ))}
    </div>
  );
}

const NoActivity = ({ T }) => (
  <p style={{ margin: 0, fontSize: 12.5, color: muted(0.65) }}>⊖ {T('Không có hoạt động trong khoảng này.', 'No activity in this range.')}</p>
);

// ---- cards ----

function PrimaryCard({ metric, role, onOpen, T }) {
  const meaning = RP.meaning(metric, role, T);
  return (
    <button type="button" onClick={onOpen} data-testid={`reports-primary-${metric.key}`}
      aria-label={`${metric.title}: ${metric.accessibilityValue}. ${meaning}. ${RP.seriesSentence(metric, T)}`}
      style={{ ...buttonReset, ...heroSurface }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <Glyph name={RP.symbolFor(metric.key)} size={30} />
        <span style={{ fontSize: 14.5, fontWeight: 600, flex: 1 }}>{metric.title}</span>
        <Chevron />
      </div>
      <div style={{ fontSize: 46, fontWeight: 700, letterSpacing: '-0.02em', fontVariantNumeric: 'tabular-nums', marginTop: 14, lineHeight: 1.05, overflowWrap: 'anywhere' }}>
        {metric.valueText}
      </div>
      <p style={{ margin: '4px 0 0', fontSize: 12.5, color: muted(0.7) }}>{meaning}</p>
      {metric.summary && (
        <div style={{ marginTop: 18 }}>
          {metric.summary.hasActivity ? (
            <>
              <DailyBars metric={metric} T={T} />
              <div style={{ height: 1, background: muted(0.08), margin: '14px 0' }} />
              <SeriesStats metric={metric} T={T} />
            </>
          ) : <NoActivity T={T} />}
        </div>
      )}
    </button>
  );
}

function KpiTile({ metric, role, onOpen, T }) {
  const meaning = RP.meaning(metric, role, T);
  return (
    <button type="button" onClick={onOpen} data-testid={`reports-kpi-${metric.key}`}
      aria-label={`${metric.title}: ${metric.accessibilityValue}. ${meaning}`}
      style={{ ...buttonReset, ...card({ padding: 14 }), display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: muted(0.78), flex: 1 }}>{metric.title}</span>
        <Glyph name={RP.symbolFor(metric.key)} size={26} />
      </div>
      {/* One line, stepping down for long amounts (iOS's minimumScaleFactor), so "₫" never wraps on its own. */}
      <div style={{ fontSize: metric.valueText.length > 10 ? 19 : metric.valueText.length > 7 ? 22 : 26, fontWeight: 700, fontVariantNumeric: 'tabular-nums', marginTop: 8, whiteSpace: 'nowrap', lineHeight: 1.1 }}>{metric.valueText}</div>
      <div style={{ fontSize: 11.5, color: muted(0.6), marginTop: 3 }}>{meaning}</div>
      <div style={{ flex: 1, minHeight: 10 }} />
      {metric.summary?.hasActivity && (
        <div data-testid={`reports-kpi-strip-${metric.key}`}><Sparkline metric={metric} /></div>
      )}
    </button>
  );
}

/// State in words (badge) + icon + leading rule; the tint only repeats it. Red only for late/conflicting items.
function AttentionCard({ item, onOpen, T }) {
  const calm = item.severity === 'pending';
  const tint = calm ? honey : alert;
  const badge = RP.severityBadge(item.severity, T);
  const action = RP.attentionAction(item, T);
  return (
    <button type="button" onClick={onOpen} data-testid={`reports-attention-${item.key}`}
      aria-label={`${badge}: ${item.title}. ${item.valueText}. ${item.message} ${action}`}
      style={{
        ...buttonReset, position: 'relative', borderRadius: 20, padding: '16px 16px 16px 20px', color: ink,
        background: calm ? `linear-gradient(0deg, ${honeyBg}B3, ${honeyBg}B3), var(--bb-field)` : 'linear-gradient(0deg, rgba(var(--bb-alert-rgb),0.07), rgba(var(--bb-alert-rgb),0.07)), var(--bb-field)',
        border: `1px solid color-mix(in srgb, ${tint} 22%, transparent)`,
      }}>
      <span aria-hidden style={{ position: 'absolute', left: 0, top: 16, bottom: 16, width: 4, borderRadius: 2, background: tint }} />
      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
        <span aria-hidden style={{
          width: 36, height: 36, borderRadius: 10, flex: '0 0 auto', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          color: tint, background: `color-mix(in srgb, ${tint} 14%, transparent)`,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={GLYPHS[item.symbol] || GLYPHS.alert} /></svg>
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 11.5, fontWeight: 700, color: tint, padding: '3px 8px', borderRadius: 999, background: `color-mix(in srgb, ${tint} 14%, transparent)` }}>{badge}</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 19, fontWeight: 700, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{item.valueText}</span>
          </div>
          <div style={{ fontSize: 14, fontWeight: 600, marginTop: 6 }}>{item.title}</div>
          <div style={{ fontSize: 12.5, color: muted(0.75), marginTop: 3 }}>{item.message}</div>
          <div style={{ fontSize: 12.5, fontWeight: 600, marginTop: 8 }}>{action} →</div>
        </div>
      </div>
    </button>
  );
}

function TrendCard({ metric, role, onOpen, T }) {
  return (
    <button type="button" onClick={onOpen} data-testid={`reports-trend-${metric.key}`}
      aria-label={`${metric.title}: ${metric.accessibilityValue}. ${RP.seriesSentence(metric, T)}`}
      style={{ ...buttonReset, ...card() }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <Glyph name={RP.symbolFor(metric.key)} size={26} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 600 }}>{metric.title}</div>
          <div style={{ fontSize: 11.5, color: muted(0.6) }}>{RP.meaning(metric, role, T)}</div>
        </div>
        <span style={{ fontSize: 19, fontWeight: 700, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{metric.valueText}</span>
      </div>
      <div style={{ marginTop: 12 }}>
        {metric.summary?.hasActivity ? (
          <>
            <DailyBars metric={metric} height={84} T={T} />
            <div style={{ marginTop: 12 }}><SeriesStats metric={metric} T={T} /></div>
          </>
        ) : <NoActivity T={T} />}
      </div>
    </button>
  );
}

/// A share (ring + "n/m") or a distribution (segmented bar + labelled legend). Every value is printed as text.
function InsightCard({ insight, onOpen, T }) {
  const shades = [0.9, 0.55, 0.32, 0.18];
  return (
    <button type="button" onClick={onOpen} data-testid={`reports-insight-${insight.id}`}
      aria-label={RP.insightSentence(insight, T)} style={{ ...buttonReset, ...card() }}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <span style={{ fontSize: 14, fontWeight: 600, flex: 1 }}>{insight.title}</span><Chevron />
      </div>
      {insight.type === 'share' ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 10 }}>
          <svg aria-hidden width="58" height="58" viewBox="0 0 58 58" style={{ color: ink, flex: '0 0 auto' }}>
            <circle cx="29" cy="29" r="25" fill="none" stroke="currentColor" strokeOpacity="0.12" strokeWidth="7" />
            <circle cx="29" cy="29" r="25" fill="none" stroke="currentColor" strokeWidth="7"
              strokeDasharray={`${2 * Math.PI * 25 * (insight.denominator ? insight.numerator / insight.denominator : 0)} ${2 * Math.PI * 25}`}
              transform="rotate(-90 29 29)" />
            <text x="29" y="33" textAnchor="middle" fontSize="12" fontWeight="700" fill="currentColor">{insight.numerator}/{insight.denominator}</text>
          </svg>
          <span style={{ fontSize: 12.5, color: muted(0.8) }}>{insight.caption}</span>
        </div>
      ) : (
        <div style={{ marginTop: 10 }}>
          <div aria-hidden style={{ display: 'flex', gap: 2, height: 12, borderRadius: 4, overflow: 'hidden' }}>
            {insight.segments.map((seg, i) => seg.count > 0 && (
              <span key={seg.id} style={{ flex: `${seg.count} 0 4px`, background: muted(shades[i % shades.length]) }} />
            ))}
          </div>
          {insight.segments.map((seg, i) => (
            <div key={seg.id} style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8, fontSize: 12.5 }}>
              <span aria-hidden style={{ width: 10, height: 10, borderRadius: 2, background: muted(shades[i % shades.length]) }} />
              <span style={{ flex: 1 }}>{seg.label}</span>
              <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{seg.count}</span>
            </div>
          ))}
        </div>
      )}
    </button>
  );
}

/// Same footprint as the loaded dashboard so nothing jumps when data arrives. Static (no shimmer).
function Skeleton({ T }) {
  const block = (h, r = 20) => (
    <div style={{ height: h, borderRadius: r, background: 'var(--bb-field)', padding: 16, boxSizing: 'border-box' }}>
      <div style={{ width: 110, height: 10, borderRadius: 5, background: muted(0.08) }} />
      <div style={{ width: 70, height: 18, borderRadius: 9, background: muted(0.12), marginTop: 8 }} />
    </div>
  );
  return (
    <div role="status" aria-label={T('Đang tải số liệu', 'Loading metrics')} data-testid="reports-skeleton" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {block(300, 24)}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>{[0, 1, 2, 3].map(i => <div key={i}>{block(150)}</div>)}</div>
      {block(200)}
    </div>
  );
}

// ---- details sheet ----

function DetailSheet({ raw, rangeLabel, pngRangeLabel, onClose, onCsv, T }) {
  const canvasRef = useRef(null);
  const m = RP.metric(raw, T);
  const rows = RP.rows(raw, T);
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div role="dialog" aria-modal="true" aria-label={m.title} data-testid="reports-detail"
      onClick={onClose}
      style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(0,0,0,0.32)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: '100%', maxWidth: 560, maxHeight: '88vh', overflowY: 'auto', background: paper, color: ink,
        borderRadius: '24px 24px 0 0', padding: '18px 20px 28px', boxSizing: 'border-box',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ ...display(19), flex: 1 }}>{m.title}</span>
          <button type="button" onClick={onClose} aria-label={T('Đóng', 'Close')} data-testid="reports-detail-close"
            style={{ appearance: 'none', border: 'none', width: 36, height: 36, borderRadius: '50%', background: muted(0.08), color: ink, fontSize: 17, cursor: 'pointer' }}>✕</button>
        </div>
        <div style={{ fontSize: 34, fontWeight: 700, fontVariantNumeric: 'tabular-nums', marginTop: 12 }} aria-label={m.accessibilityValue}>{m.valueText}</div>
        <div style={{ fontSize: 12, color: muted(0.65), marginTop: 2 }}>
          {m.isTimeSeries ? rangeLabel : T('Số liệu hiện tại, không theo thời gian.', 'A current total, not a time series.')}
        </div>
        {m.isTimeSeries && (
          <div style={{ marginTop: 14 }}>
            <MiniChart metric={raw} rangeLabel={pngRangeLabel} canvasRef={canvasRef} T={T} />
            <p style={{ fontSize: 12.5, color: muted(0.75), margin: '10px 0 0' }}>{RP.seriesSentence(m, T)}</p>
            <button type="button" onClick={() => saveCanvasPng(canvasRef.current, `banbe-${raw.key}.png`)} data-testid={`kpi-save-png-${raw.key}`}
              style={{ appearance: 'none', border: 'none', background: 'none', padding: '8px 0', color: ink, fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
              ⤓ {T('Lưu ảnh biểu đồ', 'Save chart image')}
            </button>
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'center', marginTop: 16 }}>
          <h3 style={{ flex: 1, margin: 0, fontSize: 15, fontWeight: 600 }}>{T('Dữ liệu chi tiết', 'Underlying data')}</h3>
          <button type="button" onClick={() => onCsv(raw.key)} data-testid={`kpi-export-csv-${raw.key}`}
            style={{ appearance: 'none', border: 'none', background: 'none', color: ink, fontSize: 13, fontWeight: 600, cursor: 'pointer', padding: '8px 0' }}>
            ▦ {T('Xuất CSV', 'Export CSV')}
          </button>
        </div>
        {rows.length === 0 ? (
          <p style={{ fontSize: 12.5, color: muted(0.65), margin: '6px 0 0' }}>{T('Không có bản ghi nào để hiển thị.', 'No records to show.')}</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 6 }}>
            {rows.slice(0, 100).map(row => (
              <div key={row.id} style={{ background: 'var(--bb-field)', borderRadius: 14, padding: 12 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                  <span style={{ flex: 1, fontSize: 13.5, fontWeight: 600 }}>{row.title}</span>
                  {row.flagged && <span style={{ fontSize: 11.5, fontWeight: 600, color: alert }}>⚠ {T('Quá hạn', 'Overdue')}</span>}
                </div>
                {row.fields.map((f, i) => (
                  <div key={i} style={{ display: 'flex', gap: 10, marginTop: 6, fontSize: 12.5 }}>
                    <span style={{ color: muted(0.65) }}>{f.label}</span>
                    <span style={{ flex: 1, textAlign: 'right', fontWeight: 500 }}>{f.value}</span>
                  </div>
                ))}
              </div>
            ))}
            {rows.length > 100 && (
              <p style={{ fontSize: 12.5, color: muted(0.65), margin: 0 }}>
                {T(`Hiển thị 100/${rows.length} bản ghi. Xuất CSV để xem tất cả.`, `Showing 100 of ${rows.length} records. Export CSV for all of them.`)}
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ---- screen ----

export default function Reports() {
  const {
    state, T, backFromReports, setReportsRangeDays, setReportsCustomRange, openReportDetail, closeReportDetail,
    exportReportCardCsv, exportReportsJson, exportReportsPdf, loadAccountKpis,
  } = useBanBe();
  const s = state;
  const data = s.reportsData;
  const [menuOpen, setMenuOpen] = useState(false);
  const [customOpen, setCustomOpen] = useState(s.reportsRangeDays === 'custom');
  const d = useMemo(() => (data ? RP.dashboard(data, s.reportsScope, T) : null), [data, s.reportsScope, T]);
  const role = RP.reportRole(data?.scope || s.reportsScope);
  const rangeLabel = RP.rangeText(data?.range);
  // The chart PNG keeps the exact range text it always had (an export must not change; see header comment).
  const pngRangeLabel = data
    ? `${new Date(data.range.start).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })} – ${new Date(data.range.end).toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}`
    : '';
  const refreshing = s.reportsLoading && !!data;
  const exportDisabled = !data || !!s.reportsExportBusy;
  const detailRaw = s.reportsDetailKey ? (data?.metrics || []).find(m => m.key === s.reportsDetailKey) : null;
  const open = (key) => openReportDetail(key);
  const loadedTime = s.reportsLoadedAt ? new Date(s.reportsLoadedAt).toLocaleTimeString(T('vi-VN', 'en-US'), { hour: '2-digit', minute: '2-digit' }) : '';

  const rangeChip = (label, selected, testId, onClick) => (
    <button type="button" key={testId} onClick={onClick} data-testid={testId} aria-pressed={selected}
      style={{
        appearance: 'none', border: 'none', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, padding: '8px 14px', minHeight: 36,
        borderRadius: 999, cursor: 'pointer', whiteSpace: 'nowrap',
        background: selected ? ink : 'transparent', color: selected ? paper : muted(0.75),
      }}>{label}</button>
  );

  const attention = (items) => items.length > 0 && (
    <>
      <SectionTitle count={items.length}>{T('Cần chú ý', 'Needs attention')}</SectionTitle>
      {items.map(item => <AttentionCard key={item.key} item={item} onOpen={() => open(item.targetKey)} T={T} />)}
    </>
  );

  return (
    <div style={{ minHeight: '100%', background: paper, color: ink, animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both' }} data-screen-label="Reports">
      <div style={{ padding: '66px 20px 0' }}>
        <button type="button" onClick={backFromReports} style={{ appearance: 'none', border: 'none', background: 'none', padding: 0, fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</button>
      </div>

      <div style={{ padding: '10px 20px 0', display: 'flex', alignItems: 'center', gap: 10, position: 'relative' }}>
        <h1 style={{ ...display(24, { display: 'flex', alignItems: 'center', gap: 10, margin: 0, flex: 1 }) }}>
          <HostTitleIcon kind="checklist" group="reports" />{T('Số liệu & báo cáo', 'Metrics & Reports')}
        </h1>
        <button type="button" onClick={() => setMenuOpen(o => !o)} aria-haspopup="menu" aria-expanded={menuOpen}
          aria-label={T('Xuất và tuỳ chọn khác', 'Export and more')} data-testid="reports-menu"
          style={{ appearance: 'none', border: `1.5px solid ${ink}`, background: 'none', color: ink, width: 30, height: 30, borderRadius: '50%', cursor: 'pointer', fontSize: 14, lineHeight: 1 }}>
          {s.reportsExportBusy ? '⧗' : '⋯'}
        </button>
        {menuOpen && (
          <>
            <div onClick={() => setMenuOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 40 }} />
            <div role="menu" style={{ ...fieldGlass({ position: 'absolute', right: 20, top: 46, zIndex: 41, minWidth: 210, padding: 6, borderRadius: 14 }) }}>
              {[
                ['↻', T('Làm mới', 'Refresh'), 'reports-refresh', loadAccountKpis, false],
                ['📄', T('Báo cáo PDF', 'PDF report'), 'kpi-export-pdf', exportReportsPdf, exportDisabled],
                ['{ }', T('Dữ liệu JSON', 'JSON data'), 'kpi-export-json', exportReportsJson, exportDisabled],
              ].map(([icon, label, testId, action, disabled]) => (
                <button key={testId} type="button" role="menuitem" data-testid={testId} disabled={disabled}
                  onClick={() => { setMenuOpen(false); action(); }}
                  style={{ appearance: 'none', border: 'none', background: 'none', color: ink, width: '100%', textAlign: 'left', padding: '10px 10px', fontSize: 13.5, fontFamily: 'inherit', cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.4 : 1, display: 'flex', gap: 10 }}>
                  <span aria-hidden style={{ width: 20, textAlign: 'center', opacity: 0.7 }}>{icon}</span>{label}
                </button>
              ))}
            </div>
          </>
        )}
      </div>

      <div data-testid="reports-subtitle" style={{ padding: '6px 20px 0', fontSize: 12.5, color: muted(0.7) }}>
        <strong style={{ fontWeight: 600 }}>{RP.roleLabel(role, T)}</strong>{rangeLabel ? `  ·  ${rangeLabel}` : ''}
        {s.reportsLoading && <span style={{ marginLeft: 8 }}>{T('Đang cập nhật…', 'Updating…')}</span>}
      </div>

      <div style={{ padding: '14px 20px 0', overflowX: 'auto' }}>
        <div data-testid="kpi-range-picker" style={{ display: 'inline-flex', gap: 4, padding: 4, borderRadius: 999, background: 'var(--bb-field)' }}>
          {[7, 30, 90].map(n => rangeChip(T(`${n} ngày`, `${n}d`), s.reportsRangeDays === n, `kpi-range-${n}`, () => { setCustomOpen(false); setReportsRangeDays(n); }))}
          {rangeChip(T('Tuỳ chọn…', 'Custom…'), s.reportsRangeDays === 'custom' || customOpen, 'kpi-range-custom', () => setCustomOpen(o => !o))}
        </div>
      </div>
      {customOpen && (
        <div style={{ display: 'flex', gap: 8, padding: '10px 20px 0', flexWrap: 'wrap', alignItems: 'center', fontSize: 12.5 }}>
          <label>{T('Từ ngày', 'From')}{' '}
            <input type="date" value={s.reportsCustomStart} data-testid="kpi-range-custom-start" max={s.reportsCustomEnd || undefined}
              onChange={(e) => setReportsCustomRange(e.target.value, s.reportsCustomEnd || e.target.value)}
              style={{ ...fieldGlass({ padding: '8px 10px', fontSize: 12.5, border: 'none', outline: 'none', color: ink, fontFamily: 'inherit' }) }} />
          </label>
          <label>{T('Đến ngày', 'To')}{' '}
            <input type="date" value={s.reportsCustomEnd} data-testid="kpi-range-custom-end" min={s.reportsCustomStart || undefined}
              onChange={(e) => setReportsCustomRange(s.reportsCustomStart || e.target.value, e.target.value)}
              style={{ ...fieldGlass({ padding: '8px 10px', fontSize: 12.5, border: 'none', outline: 'none', color: ink, fontFamily: 'inherit' }) }} />
          </label>
        </div>
      )}

      <div style={{ padding: '18px 20px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {data && s.reportsError && (
          <div data-testid="reports-stale" style={{ display: 'flex', gap: 10, alignItems: 'flex-start', padding: 14, borderRadius: 16, background: honeyBg }}>
            <span aria-hidden>⟲</span>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, fontWeight: 600 }}>{T('Chưa làm mới được.', "Couldn't refresh.")}</div>
              {loadedTime && <div style={{ fontSize: 12.5 }}>{T(`Đang hiện số liệu lúc ${loadedTime}.`, `Showing numbers from ${loadedTime}.`)}</div>}
            </div>
            <button type="button" onClick={loadAccountKpis} data-testid="reports-stale-retry"
              style={{ appearance: 'none', border: 'none', background: 'none', color: ink, fontWeight: 600, fontSize: 12.5, cursor: 'pointer', minHeight: 36 }}>{T('Thử lại', 'Retry')}</button>
          </div>
        )}

        {!data && s.reportsError && !s.reportsLoading && (
          <div style={card()}>
            <p style={{ fontSize: 13, color: alert, margin: 0 }} data-testid="reports-error">{s.reportsError}</p>
            <button type="button" onClick={loadAccountKpis} data-testid="reports-retry"
              style={{ ...inkButton({ marginTop: 12, padding: 11, fontSize: 13, width: '100%' }) }}>{T('Thử lại', 'Retry')}</button>
          </div>
        )}
        {!data && (s.reportsLoading || !s.reportsError) && <Skeleton T={T} />}

        {d && d.isEmpty && (
          <div data-testid="reports-empty" style={{ textAlign: 'center', padding: '50px 0', color: muted(0.7), fontSize: 13 }}>
            {T('Chưa có số liệu.', 'Nothing to show yet.')}
          </div>
        )}

        {d && !d.isEmpty && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, opacity: refreshing ? 0.5 : 1, pointerEvents: refreshing ? 'none' : 'auto', transition: 'opacity 0.2s' }}>
            {/* Admin's job is the backlog, so it stays above the hero (note 43). */}
            {d.attentionFirst && attention(d.attention)}
            {d.primary && <PrimaryCard metric={d.primary} role={d.role} onOpen={() => open(d.primary.key)} T={T} />}
            {d.overview.length > 0 && (
              <>
                <SectionTitle>{T('Tổng quan', 'Overview')}</SectionTitle>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 12, alignItems: 'stretch' }}>
                  {d.overview.map(m => <KpiTile key={m.key} metric={m} role={d.role} onOpen={() => open(m.key)} T={T} />)}
                </div>
              </>
            )}
            {!d.attentionFirst && attention(d.attention)}
            {d.insights.length > 0 && (
              <>
                <SectionTitle>{T('Phân tích', 'Breakdown')}</SectionTitle>
                {d.insights.map(i => <InsightCard key={i.id} insight={i} onOpen={() => open(i.key)} T={T} />)}
              </>
            )}
            {d.trends.length > 0 && (
              <>
                <SectionTitle>{T('Xu hướng', 'Trends')}</SectionTitle>
                {d.trends.map(m => <TrendCard key={m.key} metric={m} role={d.role} onOpen={() => open(m.key)} T={T} />)}
              </>
            )}
            <SectionTitle>{T('Tất cả số liệu', 'All metrics')}</SectionTitle>
            <div style={card({ padding: 0 })}>
              {d.all.map((m, i) => (
                <button key={m.key} type="button" onClick={() => open(m.key)} data-testid={`kpi-card-${m.key}`}
                  aria-label={`${m.title}: ${m.accessibilityValue}`}
                  style={{ ...buttonReset, border: 'none', background: 'none', color: ink, display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px', borderTop: i ? `1px solid ${rule}` : 'none' }}>
                  <span aria-hidden style={{ width: 22, opacity: 0.55, display: 'inline-flex' }}>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={GLYPHS[RP.symbolFor(m.key)]} /></svg>
                  </span>
                  <span style={{ flex: 1, fontSize: 14 }}>{m.title}</span>
                  <span data-testid={`kpi-card-value-${m.key}`} style={{ fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{m.valueText}</span>
                  <Chevron />
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {detailRaw && (
        <DetailSheet raw={detailRaw} rangeLabel={rangeLabel} pngRangeLabel={pngRangeLabel} onClose={closeReportDetail} onCsv={exportReportCardCsv} T={T} />
      )}
    </div>
  );
}
