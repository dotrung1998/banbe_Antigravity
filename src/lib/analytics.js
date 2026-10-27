// Product analytics boundary — web mirror of iOS `Lib/Analytics.swift` (note 43).
// There is NO vendor. `track()` logs to the console in dev builds and hands the event to `sink`, a no-op until
// installAppEventsSink() (below) is installed for a signed-in account while the admin switch `app_events` is on
// (migration 196): then events go to banbe's own database through log_app_events, nowhere else. Events carry
// only ids, counts and buckets — never answers, names, emails or any other PII.

const devLog = (event) => {
  if (typeof import.meta !== 'undefined' && import.meta.env?.DEV) console.debug('[analytics]', event.name, event.props || {});
};
let sink = () => {};

export function setAnalyticsSink(fn) { sink = typeof fn === 'function' ? fn : () => {}; }

// Note 64: the v3 tour shows the real screens without the person using them, so nothing is measured meanwhile.
let paused = false;
export function setAnalyticsPaused(v) { paused = !!v; }

export function track(name, props) {
  if (paused) return;
  try { devLog({ name, props }); } catch { /* logging must never break the app */ }
  try { sink({ name, props }); } catch { /* analytics must never break the app */ }
}

/** Match counts are bucketed so no exact number leaves the device: 0 / 1-2 / 3-5 / 6-10 / 11+. */
export function matchBucket(n) {
  if (n <= 0) return '0';
  if (n <= 2) return '1-2';
  if (n <= 5) return '3-5';
  if (n <= 10) return '6-10';
  return '11+';
}

// ============ First-party measurement (migration 196) ============
// The ONLY event names and property keys that may leave the device. Same list as tests/fixtures/app-events.json
// (asserted by tests/unit/appEvents.test.mjs), iOS `AppEventsContract` and the server's app_event_names table.
// The server drops anything else too; filtering here means nothing unexpected is even sent.
export const APP_EVENT_PROPS = {
  app_opened: [],
  event_opened: ['event_id', 'source'],
  ticket_opened: ['day_bucket'],
  notification_opened: ['kind', 'source'],
  share_completed: ['channel', 'context'],
  follow_tapped: ['context'],
  onboarding_started: [],
  onboarding_question_viewed: ['question_id'],
  onboarding_question_answered: ['question_id', 'answer_count'],
  onboarding_question_skipped: ['question_id'],
  onboarding_completed: ['answered_questions', 'skipped_all'],
  personalized_results_viewed: ['match_bucket'],
  first_event_opened: [],
  first_event_saved: [],
  first_reservation_started: [],
  permission_prompted: ['permission'],
  permission_result: ['permission', 'result'],
  public_entry_viewed: [],
  public_entry_get_started: [],
  public_entry_login: [],
  public_story_opened: [],
  public_story_completed: [],
  public_story_skipped: ['step'],
  guest_browse_started: [],
  guest_signin_prompt_shown: ['context'],
  guest_signin_prompt_accepted: ['context'],
  create_event_started_blank: [],
  recipe_opened: [],
  recipe_fix_tapped: ['ingredient'],
  submit_recipe_score: ['bucket'],
  schedule_opened: [],
  schedule_mode_selected: ['mode'],
  schedule_day_selected: ['day_bucket'],
  schedule_conflict_shown: ['count_bucket'],
  banbe_schedule_add: [],
  banbe_schedule_remove: [],
  banbe_schedule_result: ['result'],
  system_calendar_editor_opened: [],
  system_calendar_editor_result: ['result'],
  rewards_badge_celebrated: ['code'],
  rewards_week_milestone: ['weeks'],
  rewards_goal_set: ['goal'],
};

const MAX_VALUE_LENGTH = 64; // same cap as log_app_events
const MAX_PER_CALL = 50; // same cap as log_app_events
const MAX_QUEUE = 200; // memory bound if flushing keeps failing

/** { name, props } with only whitelisted keys and short scalar values as strings, or null for an unknown name. */
export function filterAppEvent(name, props) {
  const allowed = Object.prototype.hasOwnProperty.call(APP_EVENT_PROPS, name) ? APP_EVENT_PROPS[name] : null;
  if (!allowed) return null;
  const out = {};
  if (props && typeof props === 'object') {
    for (const k of allowed) {
      const v = props[k];
      if (!['string', 'number', 'boolean'].includes(typeof v)) continue;
      if (typeof v === 'number' && !Number.isFinite(v)) continue;
      const str = String(v);
      if (str && str.length <= MAX_VALUE_LENGTH) out[k] = str;
    }
  }
  return { name, props: out };
}

/**
 * The batching sink. Nothing is queued or sent unless `isEnabled()` (the `app_events` switch) and `isSignedIn()`
 * both hold; a flush that finds either false drops the queue instead. Flushes every `flushMs`, as soon as
 * `batchSize` events are waiting, and when the page is hidden or unloaded. Never throws.
 */
export function createAppEventsSink({
  rpc, isEnabled, isSignedIn, platform = 'web', flushMs = 15000, batchSize = 20,
  timers = { setInterval, clearInterval }, target = typeof window !== 'undefined' ? window : null,
  doc = typeof document !== 'undefined' ? document : null,
}) {
  let queue = [];
  const allowed = () => { try { return !!isEnabled() && !!isSignedIn(); } catch { return false; } };

  const flush = () => {
    if (!allowed()) { queue = []; return Promise.resolve(); }
    const sends = [];
    while (queue.length) {
      const batch = queue.splice(0, MAX_PER_CALL);
      try {
        sends.push(Promise.resolve(rpc('log_app_events', { p_events: batch, p_platform: platform }))
          .then((r) => { if (r?.data?.error === 'DISABLED') queue = []; }, () => {}));
      } catch { /* a failed send loses that batch, never the app */ }
    }
    return Promise.all(sends).then(() => {});
  };

  const push = ({ name, props } = {}) => {
    if (!allowed()) { queue = []; return; }
    const ev = filterAppEvent(name, props);
    if (!ev) return;
    queue.push(ev);
    if (queue.length > MAX_QUEUE) queue = queue.slice(-MAX_QUEUE);
    if (queue.length >= batchSize) flush();
  };

  const onVisibility = () => { if (doc?.visibilityState === 'hidden') flush(); };
  const onPageHide = () => { flush(); };
  const timer = timers.setInterval(() => { if (queue.length) flush(); }, flushMs);
  doc?.addEventListener?.('visibilitychange', onVisibility);
  target?.addEventListener?.('pagehide', onPageHide);

  return {
    push,
    flush,
    size: () => queue.length,
    /** Stops the timer and listeners and drops whatever is still queued (sign-out, switch off). */
    dispose() {
      queue = [];
      try { timers.clearInterval(timer); } catch { /* already gone */ }
      doc?.removeEventListener?.('visibilitychange', onVisibility);
      target?.removeEventListener?.('pagehide', onPageHide);
    },
  };
}

/** Installs the sink as the analytics sink; returns the uninstall function (drops the queue, restores the no-op). */
export function installAppEventsSink(opts) {
  try {
    const s = createAppEventsSink(opts);
    setAnalyticsSink(s.push);
    return () => { s.dispose(); setAnalyticsSink(null); };
  } catch {
    return () => {};
  }
}

/** Local calendar day as YYYY-MM-DD (device time zone). */
export function localDayKey(now = new Date()) {
  const d = now instanceof Date ? now : new Date(now);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

const APP_OPENED_KEY = 'banbe_app_opened_day_v1';
/** True once per local day per device (and records that day). A missing/blocked store still answers true. */
export function claimAppOpenedToday(storage = typeof localStorage !== 'undefined' ? localStorage : null, now = new Date()) {
  const day = localDayKey(now);
  try {
    if (storage?.getItem(APP_OPENED_KEY) === day) return false;
    storage?.setItem(APP_OPENED_KEY, day);
  } catch { /* private mode: at worst one extra app_opened */ }
  return true;
}

/**
 * `event_opened.source` from the screen the event was opened from: home | search | map | schedule | link | other.
 * `nav` = { screen, searchOverlayOpen } of the screen being left; `link` is passed by the deep-link opener.
 */
export function eventOpenSource(nav) {
  if (!nav) return 'other';
  if (nav.screen === 'home') return nav.searchOverlayOpen ? 'search' : 'home';
  if (nav.screen === 'search') return 'search';
  if (nav.screen === 'mapExplore') return 'map';
  if (nav.screen === 'schedule') return 'schedule';
  return 'other';
}

/** `ticket_opened.day_bucket`: the event's day vs today, both as calendar days in `timeZone` (the event's zone). */
export function ticketDayBucket(startMs, nowMs, timeZone) {
  if (!Number.isFinite(startMs) || !Number.isFinite(nowMs)) return null;
  const day = (ms) => {
    try {
      const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: timeZone || undefined, year: 'numeric', month: '2-digit', day: '2-digit' })
        .formatToParts(new Date(ms)).map(x => [x.type, x.value]));
      return `${p.year}-${p.month}-${p.day}`;
    } catch { return localDayKey(new Date(ms)); }
  };
  const a = day(nowMs), b = day(startMs);
  return a === b ? 'day_of' : a < b ? 'before' : 'after';
}
