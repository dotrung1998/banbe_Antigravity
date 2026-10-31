// Localization-leak fix pass — `get_account_kpis()` (migration 097) returns
// every metric's `label` as a single hardcoded Vietnamese string, server-
// side, with no English counterpart in the payload at all — switching the
// app's language to English never touched these, since nothing client-side
// was even trying to translate them. No migration/schema change for this
// pass (out of scope) — translated here instead, keyed by the metric's own
// stable `key` (never its `label`, which is the untranslated value this
// fixes), shared by both Reports.jsx (on-screen cards/chart) and
// BanBeContext.jsx (PDF export) so the two can never show different English
// wording for the same metric. Falls back to the raw server label if a key
// is ever missing here (a future new metric), so this can never show a
// blank — only, at worst, temporarily untranslated until added below.
export const METRIC_LABEL_EN = {
  saved_events: 'Saved events',
  confirmed_bookings: 'Confirmed bookings',
  attended_events: 'Attended',
  upcoming_events: 'Upcoming',
  outstanding_refunds: 'Refunds pending',
  published_events: 'Published events',
  confirmed_seats: 'Confirmed seats',
  check_ins: 'Checked in',
  confirmed_payment_amount: 'Confirmed payment amount',
  refunds_owed: 'Refunds owed',
  refunds_overdue: 'Refunds overdue',
  pending_event_reviews: 'Events pending review',
  unresolved_disputes: 'Unresolved disputes',
  backlog_avg_age_days: 'Average backlog age (days)',
  platform_new_events: 'New events platform-wide',
  platform_new_bookings: 'New bookings platform-wide',
};

export function metricLabel(metric, T) {
  return T(metric.label, METRIC_LABEL_EN[metric.key] || metric.label);
}

// Note 66 follow-up (Simple Shell Host Home): SHORT labels for the three KPI tiles, so a tile label fits in two
// lines at phone width with no ellipsis. Full labels (above / the server's) stay in Reports and in each tile's
// accessible name. Covers every host metric Host Home can show (reportsPresentation layoutFor('host')); the iOS twin
// is ReportMetricLabels.swift. Missing key = null (callers fall back to the full label).
export const METRIC_SHORT_LABEL = {
  confirmed_seats: { vi: 'Chỗ đã xác nhận', en: 'Seats confirmed' },
  confirmed_payment_amount: { vi: 'Tiền đã xác nhận', en: 'Payments confirmed' },
  upcoming_events: { vi: 'Sắp diễn ra', en: 'Upcoming' },
  published_events: { vi: 'Đã đăng', en: 'Published' },
  check_ins: { vi: 'Đã điểm danh', en: 'Checked in' },
  refunds_owed: { vi: 'Cần hoàn tiền', en: 'Refunds owed' },
  refunds_overdue: { vi: 'Hoàn tiền trễ', en: 'Refunds late' },
};

export function shortMetricLabel(key, T) {
  const l = METRIC_SHORT_LABEL[key];
  return l ? T(l.vi, l.en) : null;
}
