import { createContext, useContext, useEffect, useMemo, useState, useCallback, useRef } from 'react';
import { EVENTS, findEvent, haversineKm } from '../data/events.js';
import { supabase } from '../lib/supabase.js';
import { requestAuthEmail, requestPasswordSignup, requestPasswordReset } from '../lib/authEmail.js';

const GocCtx = createContext(null);

// The one place a "?ref=CODE" link is ever read from — runs once at module
// load (before React even mounts), so it survives however many redirects
// onboarding takes before someone actually finishes signing up. Stashed in
// localStorage (not component state) for the same reason: the code has to
// outlive a full page reload if that happens mid-flow, and the referral
// isn't redeemed until claimPendingReferralAndWelcome() runs, well after
// this. The query param is stripped from the visible URL immediately so it
// doesn't linger if the page gets shared or bookmarked from here.
const REFERRAL_STORAGE_KEY = 'banbe.pendingReferral';
if (typeof window !== 'undefined') {
  const params = new URLSearchParams(window.location.search);
  const ref = params.get('ref');
  if (ref && /^[A-Za-z0-9]{4,12}$/.test(ref)) {
    try { localStorage.setItem(REFERRAL_STORAGE_KEY, ref.toUpperCase()); } catch { /* private browsing, etc. */ }
    params.delete('ref');
    const rest = params.toString();
    window.history.replaceState({}, '', window.location.pathname + (rest ? `?${rest}` : ''));
  }
}

const initialState = {
  screen: 'splash',
  mode: 'goer',
  hasHosted: false,
  eventKey: 'bepnho',
  eventBackScreen: 'home',
  // The "Going"/"Saved" cards on Account open a filtered list of events —
  // always entered from (and returned to) Account, so there's no need for
  // a whole back-stack, just which filter is showing.
  eventListMode: 'going',
  // Which screen to return to from Inbox/Dashboard — both are reachable
  // from more than one place (Home's message icon vs Account's "Messages"
  // row; Home's host-page link vs Account's "Hosting" card), so a single
  // hardcoded back target sends at least one of those callers somewhere
  // it didn't come from.
  inboxBack: 'home',
  dashboardBack: 'home',
  loading: false,
  filter: 'all',
  formName: '',
  formEmail: '',
  chatDraft: '',
  chatBack: 'organizer',
  shared: false,
  // Never pre-seeded: a brand-new, unregistered visitor should see only the
  // public event feed, not a "Your events" shelf built from placeholder
  // demo activity. Once signed in, these are replaced by that account's
  // real bookings (see the effect that loads them below).
  attending: [],
  tickets: {},
  myOrgEventKeys: [],
  located: null,
  askingLocation: false,
  userCoords: null,
  user: null,
  accountType: 'participant',
  organizerMode: false,
  organizerModeError: '',
  editNameValue: '',
  editNameError: '',
  editNameSaving: false,
  notifications: [],
  unreadNotifications: 0,
  // This account's own shareable code — null until signed in and loaded.
  referralCode: null,
  referralShared: false,
  authMode: 'login',
  authReturnScreen: 'home',
  authBackScreen: 'home',
  // 'code' (email a one-time code) or 'password' — a per-tab choice, not
  // persisted; every account can use either, regardless of which one it was
  // created with (password sign-up still confirms via an emailed code).
  authMethod: 'code',
  loginEmail: '',
  loginNickname: '',
  loginPhoneNumber: '',
  loginCode: '',
  loginEmailCode: '',
  loginPassword: '',
  loginPasswordConfirm: '',
  // Which supabase.auth.verifyOtp `type` the pending emailed code should be
  // verified as — set when the code is requested, since the login/signup
  // tab could in principle change before the code is entered.
  pendingEmailMode: null,
  resetRequested: false,
  newPassword: '',
  newPasswordConfirm: '',
  resetPasswordBusy: false,
  resetPasswordError: '',
  loginSent: false,
  loginSentVia: null,
  payMode: 'now',
  qty: 1,
  lang: 'vi',
  theme: 'light',
  area: 'all',
  createName: '',
  createCats: [],
  createPalette: 'concrete',
  createSent: false,
  createError: '',
  createDesc: '',
  createLoc: '',
  createDate: '',
  createPrice: '',
  createSeats: '',
  createPhotos: 0,
  orgRegName: '',
  orgRegIg: '',
  orgRegDesc: '',
  following: [],
  refunds: {},
  gaveTicket: false,
  areaAsking: false,
  holdDeadline: null,
  now: Date.now(),
  favorites: [],
  invited: [],
  orgVerifyRequested: false,
  attendanceEventKey: null,
  attendanceGuests: [],
  attendanceLoading: false,
  scanningQr: false,
  qrScanError: '',
  reasonPrompt: null,
  reasonPromptBusy: false,
  reasonPromptError: '',
  chatThreadId: null,
  chatMessages: [],
  inboxThreads: [],
  calAdded: false,
  booking: null,
  reserveError: '',
};

export const AREAS = [
  { key: 'all', label: 'Toàn Sài Gòn', match: () => true },
  { key: 'q1', label: 'Quận 1', match: e => e.meta.includes('Quận 1') },
  { key: 'thaodien', label: 'Thảo Điền', match: e => e.meta.includes('Thảo Điền') },
  { key: 'binhthanh', label: 'Bình Thạnh', match: e => e.meta.includes('Bình Thạnh') },
  { key: 'other', label: 'Quận khác', match: e => !e.meta.includes('Quận 1') && !e.meta.includes('Thảo Điền') && !e.meta.includes('Bình Thạnh') },
  { key: 'danang', label: 'Đà Nẵng', match: () => false },
];

// Predefined reasons — an organizer reversing a check-in or cancelling a paid
// booking must pick one of these (no free text) so the guest's notification
// always says something concrete.
export const UNDO_CHECKIN_REASONS = [
  { key: 'wrong_person', vi: 'Nhầm người', en: 'Wrong person' },
  { key: 'tapped_by_mistake', vi: 'Bấm nhầm', en: 'Tapped by mistake' },
  { key: 'not_arrived', vi: 'Khách chưa thực sự có mặt', en: "Guest hasn't actually arrived" },
  { key: 'other', vi: 'Khác', en: 'Other' },
];
export const CANCEL_BOOKING_REASONS = [
  { key: 'event_changed', vi: 'Sự kiện đổi lịch hoặc huỷ', en: 'Event rescheduled or cancelled' },
  { key: 'guest_requested', vi: 'Khách yêu cầu huỷ', en: 'Guest asked to cancel' },
  { key: 'payment_incomplete', vi: 'Không thanh toán đúng hạn', en: 'Payment not completed in time' },
  { key: 'policy_violation', vi: 'Vi phạm quy định', en: 'Policy violation' },
  { key: 'other', vi: 'Khác', en: 'Other' },
];

export function GocProvider({ children }) {
  const [state, setStateRaw] = useState(() => {
    try {
      const raw = localStorage.getItem('banbe.preferences');
      const saved = JSON.parse(raw || '{}');
      return {
        ...initialState,
        lang: saved.lang === 'en' ? 'en' : 'vi',
        theme: saved.theme === 'dark' ? 'dark' : 'light',
        // Remember only the yes/no decision, never the coordinates
        // themselves — matches what the location sheet promises ("not
        // stored"). A fresh position is requested again each session below.
        located: saved.located === true ? true : saved.located === false ? false : null,
        // A saved preferences record means this browser has been through
        // onboarding before — replaying the splash/language/theme pickers on
        // every single revisit is what made the choice look like it "resets"
        // even though the value itself was never actually lost.
        screen: raw !== null ? 'home' : 'splash',
      };
    } catch {
      return initialState;
    }
  });
  const s = state;
  const prefsRef = useRef({ lang: state.lang, theme: state.theme });
  useEffect(() => {
    prefsRef.current = { lang: state.lang, theme: state.theme };
  }, [state.lang, state.theme]);

  const set = useCallback((partial) => {
    setStateRaw(prev => ({ ...prev, ...(typeof partial === 'function' ? partial(prev) : partial) }));
  }, []);

  useEffect(() => {
    localStorage.setItem('banbe.preferences', JSON.stringify({ lang: state.lang, theme: state.theme, located: state.located }));
  }, [state.lang, state.theme, state.located]);

  useEffect(() => {
    const id = setInterval(() => {
      setStateRaw(prev => (prev.holdDeadline ? { ...prev, now: Date.now() } : prev));
    }, 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let active = true;
    const syncUser = async (user) => {
      if (!active) return;
      if (!user) {
        set({ user: null, referralCode: null });
        return;
      }
      const { data: profile } = await supabase
        .from('profiles')
        .select('role, locale, theme, prefs_saved, display_name, referral_code')
        .eq('id', user.id)
        .maybeSingle();
      const role =
        profile?.role ||
        user.user_metadata?.account_type ||
        user.raw_user_meta_data?.account_type ||
        'participant';
      const canHostNow = role === 'organizer' || role === 'admin';
      const displayName = (profile?.display_name || '').trim() || user.user_metadata?.display_name || '';
      set({
        user: { ...user, name: displayName }, accountType: role, organizerMode: canHostNow, mode: canHostNow ? 'host' : 'goer',
        referralCode: profile?.referral_code || null,
      });

      // The account's actual host page name — Account's "Hosting" card used
      // to always fall back to the generic "Bếp Nhỏ" placeholder here,
      // because orgRegName is otherwise only ever filled in locally while
      // filling out the create-event form, never restored for an organizer
      // returning on a new session.
      const { data: org } = await supabase
        .from('organizers')
        .select('name')
        .or(`owner_id.eq.${user.id},user_id.eq.${user.id}`)
        .limit(1)
        .maybeSingle();
      if (org?.name) set({ orgRegName: org.name, hasHosted: true });

      // Language & theme follow the account once it has a saved preference,
      // so signing in on any device restores them instead of falling back to
      // this browser's own (possibly never-set) local copy.
      if (profile?.prefs_saved) {
        set(prev => ({
          lang: profile.locale === 'en' ? 'en' : 'vi',
          theme: profile.theme === 'dark' ? 'dark' : 'light',
          screen: ['splash', 'langPick', 'themePick'].includes(prev.screen) ? 'home' : prev.screen,
        }));
      } else if (profile) {
        // First time this account is seen with no saved preference yet:
        // capture whatever this browser currently has (e.g. picked just now
        // during onboarding, or as a signed-out guest) as the account's
        // preference going forward, instead of silently leaving it unset.
        const { lang, theme } = prefsRef.current;
        const { error } = await supabase
          .from('profiles')
          .update({ locale: lang, theme, prefs_saved: true })
          .eq('id', user.id);
        if (error) console.warn('Failed to save initial preferences to account:', error);
      }
    };
    supabase.auth.getSession().then(({ data }) => syncUser(data.session?.user));
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active && session?.user) {
        // A password-reset link lands here as a real session too — but it
        // must go to the "choose a new password" screen, never straight
        // into whatever authReturnScreen was pending.
        set(prev => ({
          screen: _event === 'PASSWORD_RECOVERY' ? 'resetPassword' : (prev.screen === 'login' ? prev.authReturnScreen : prev.screen),
          loginSent: false,
          loginSentVia: null,
        }));
        syncUser(session.user);
      }
      if (active && !session) set({ user: null });
    });
    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, [set]);

  useEffect(() => {
    if (!s.user?.id) return;
    let active = true;
    (async () => {
      const { data: event } = await supabase.from('events').select('id').eq('slug', s.eventKey).maybeSingle();
      if (!event) { if (active) set({ booking: null, holdDeadline: null }); return; }
      const { data: booking } = await supabase.from('bookings').select('*').eq('event_id', event.id).eq('user_id', s.user.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
      // Always set (even to null) — this used to only update on a hit, so
      // navigating from a booked event to one you have no booking for kept
      // showing the previous event's stale booking/countdown.
      if (active) set({ booking: booking || null, holdDeadline: booking?.expires_at ? new Date(booking.expires_at).getTime() : null });
    })();
    return () => { active = false; };
  }, [set, s.user?.id, s.eventKey]);

  // Unread count for the notification bell — refreshed on login so the badge
  // is right without having to open the notifications screen first.
  useEffect(() => {
    if (!s.user?.id) { set({ notifications: [], unreadNotifications: 0 }); return; }
    let active = true;
    (async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('recipient_id', s.user.id)
        .order('created_at', { ascending: false })
        .limit(50);
      if (!active || error) return;
      set({ notifications: data || [], unreadNotifications: (data || []).filter(n => !n.read_at).length });
    })();
    return () => { active = false; };
  }, [set, s.user?.id]);

  // Real event assignment for the signed-in account: which of the catalogue
  // events they're attending (from actual bookings) and which they organize
  // (from owning the organizer row events.organizer_id points at). The
  // frontend catalogue (src/data/events.js) still supplies all the cosmetic
  // detail — photos, galleries, descriptions — that the database rows don't
  // duplicate; this only resolves *which* catalogue keys are genuinely
  // "mine", by real id, instead of from placeholder demo state.
  useEffect(() => {
    if (!s.user?.id) return;
    let active = true;
    (async () => {
      const [{ data: bookings }, { data: organizers }] = await Promise.all([
        supabase
          .from('bookings')
          .select('event_id, qty, status')
          .eq('user_id', s.user.id)
          .in('status', ['pending', 'confirmed', 'attended']),
        supabase
          .from('organizers')
          .select('id')
          .or(`owner_id.eq.${s.user.id},user_id.eq.${s.user.id}`),
      ]);
      if (!active) return;

      if (bookings?.length) {
        const attending = [...new Set(bookings.map(b => b.event_id))];
        const tickets = Object.fromEntries(bookings.map(b => [b.event_id, b.qty]));
        set(prev => ({ attending: [...new Set([...prev.attending, ...attending])], tickets: { ...tickets, ...prev.tickets } }));
      }

      const organizerIds = (organizers || []).map(o => o.id);
      if (organizerIds.length) {
        const { data: events } = await supabase.from('events').select('id').in('organizer_id', organizerIds);
        if (active && events?.length) set({ myOrgEventKeys: events.map(e => e.id) });
      }
    })();
    return () => { active = false; };
  }, [set, s.user?.id]);

  // Real conversations for the signed-in account, on either side: as the
  // guest (threads.guest_id = me) and as the organizer (threads.organizer_id
  // owned by me). Replaces the old local-only `chats` object.
  const loadInboxThreads = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return set({ inboxThreads: [] });

    const [{ data: asGuest }, { data: myOrgs }] = await Promise.all([
      supabase.from('threads').select('id, event_id, guest_id, organizer_id').eq('guest_id', uid),
      supabase.from('organizers').select('id').or(`owner_id.eq.${uid},user_id.eq.${uid}`),
    ]);

    const orgIds = (myOrgs || []).map(o => o.id);
    let asHost = [];
    if (orgIds.length) {
      const { data } = await supabase.from('threads').select('id, event_id, guest_id, organizer_id').in('organizer_id', orgIds);
      asHost = data || [];
    }
    const seen = new Set();
    const allThreads = [...(asGuest || []), ...asHost].filter(t => (seen.has(t.id) ? false : (seen.add(t.id), true)));
    if (!allThreads.length) return set({ inboxThreads: [] });

    const threadIds = allThreads.map(t => t.id);
    const { data: msgs } = await supabase
      .from('messages')
      .select('thread_id, body, sender_id, created_at')
      .in('thread_id', threadIds)
      .order('created_at', { ascending: false });
    const lastByThread = {};
    for (const m of msgs || []) if (!lastByThread[m.thread_id]) lastByThread[m.thread_id] = m;

    const guestIds = [...new Set(allThreads.filter(t => t.guest_id !== uid).map(t => t.guest_id).filter(Boolean))];
    let guestNames = {};
    if (guestIds.length) {
      const { data: profiles } = await supabase.from('profiles').select('id, display_name').in('id', guestIds);
      guestNames = Object.fromEntries((profiles || []).map(p => [p.id, p.display_name]));
    }

    const rows = allThreads.map(t => {
      const ev = findEvent(t.event_id);
      const last = lastByThread[t.id];
      const iAmGuest = t.guest_id === uid;
      const name = iAmGuest ? ev.orgName : ((guestNames[t.guest_id] || '').trim() || 'Khách');
      return {
        threadId: t.id,
        eventKey: t.event_id,
        name,
        img: ev.img,
        snippet: last ? ((last.sender_id === uid ? 'Bạn: ' : '') + last.body) : '',
        lastAt: last?.created_at || null,
      };
    }).sort((a, b) => new Date(b.lastAt || 0) - new Date(a.lastAt || 0));

    set({ inboxThreads: rows });
  }, [set, s.user?.id]);

  const splashTimer = useRef(null);
  useEffect(() => {
    splashTimer.current = setTimeout(() => {
      setStateRaw(prev => (prev.screen === 'splash' ? { ...prev, screen: 'langPick' } : prev));
    }, 2600);
    return () => clearTimeout(splashTimer.current);
  }, []);
  const dismissSplash = useCallback(() => {
    clearTimeout(splashTimer.current);
    set(prev => (prev.screen === 'splash' ? { screen: 'langPick' } : {}));
  }, [set]);

  // Once signed in, language & theme are account preferences, not just this
  // browser's — persist every change so it follows the account anywhere.
  const persistAccountPreference = useCallback((patch) => {
    if (!s.user?.id) return;
    supabase
      .from('profiles')
      .update({ ...patch, prefs_saved: true })
      .eq('id', s.user.id)
      .then(({ error }) => {
        if (error) console.warn('Failed to save preferences to account:', error);
      });
  }, [s.user?.id]);

  const pickVi = useCallback(() => { set({ lang: 'vi', screen: 'themePick' }); persistAccountPreference({ locale: 'vi' }); }, [set, persistAccountPreference]);
  const pickEn = useCallback(() => { set({ lang: 'en', screen: 'themePick' }); persistAccountPreference({ locale: 'en' }); }, [set, persistAccountPreference]);
  const pickLight = useCallback(() => { set({ theme: 'light' }); persistAccountPreference({ theme: 'light' }); }, [set, persistAccountPreference]);
  const pickDark = useCallback(() => { set({ theme: 'dark' }); persistAccountPreference({ theme: 'dark' }); }, [set, persistAccountPreference]);
  const finishOnboarding = useCallback(() => set({ screen: 'home' }), [set]);

  const EN = s.lang === 'en';
  const T = useCallback((vi, en) => (EN ? en : vi), [EN]);
  const toggleTheme = useCallback(() => {
    const next = s.theme === 'dark' ? 'light' : 'dark';
    set({ theme: next });
    persistAccountPreference({ theme: next });
  }, [set, s.theme, persistAccountPreference]);
  const pickTheme = useCallback((theme) => { set({ theme }); persistAccountPreference({ theme }); }, [set, persistAccountPreference]);
  const openPreferences = useCallback(() => set({ screen: 'preferences' }), [set]);

  const trStatus = useCallback((str) => {
    if (!EN) return str;
    return String(str)
      .replace(/Còn (\d+) chỗ/g, '$1 seats left')
      .replace(/Còn (\d+) ngày/g, 'In $1 days')
      .replace(/Hôm nay/g, 'Today').replace(/Ngày mai/g, 'Tomorrow')
      .replace(/(\d+) giờ trước/g, '$1h ago').replace(/(\d+) ngày trước/g, '$1d ago')
      .replace(/1 giờ trước/g, '1h ago').replace(/1 ngày trước/g, '1d ago')
      .replace(/Hết chỗ/g, 'Sold out').replace(/Đã hủy/g, 'Cancelled')
      .replace(/Đã hoàn tiền/g, 'Refunded').replace(/Đã diễn ra/g, 'Ended')
      .replace(/Đang giữ/g, 'On hold').replace(/Đã thanh toán/g, 'Paid')
      .replace(/Đã lưu/g, 'Saved').replace(/Đang tham gia/g, 'Going')
      .replace(/Trả để xác nhận/g, 'Pay to confirm')
      .replace(/(\d+) vé/g, '$1 tix')
      .replace(/Miễn phí/g, 'Free')
      .replace(/ km từ bạn/g, ' km away')
      .replace(/từ bạn/g, 'away')
      .replace(/Thời trang/g, 'Fashion')
      .replace(/Phòng tranh/g, 'Gallery')
      .replace(/^Nhạc$/g, 'Music').replace(/ ▪︎ Nhạc/g, ' ▪︎ Music');
  }, [EN]);

  const located = s.located === true;
  // With no location permission, the km segment is stripped out entirely (we
  // don't show the demo's placeholder number as if it meant something). Once
  // the user has shared their location, pass the event in too and its
  // baked-in placeholder distance is swapped for the real, computed one as
  // soon as a fresh position is available.
  const stripKm = useCallback((str, ev) => {
    if (!located) return str.replace(/ ▪︎ \d+[.,]\d+ km(?: từ bạn| away)?/g, '');
    const km = ev ? haversineKm(s.userCoords, ev) : null;
    if (km == null) return str;
    return str.replace(/\d+[.,]\d+(?= km)/, km.toFixed(1).replace('.', ','));
  }, [located, s.userCoords]);

  const curEvent = useMemo(() => findEvent(s.eventKey), [s.eventKey]);
  const palette = curEvent.palette;

  const isSaved = useCallback((k) => s.favorites.includes(k), [s.favorites]);
  const isGoing = useCallback((k) => s.attending.includes(k), [s.attending]);
  const toggleFav = useCallback((k) => set(prev => ({ favorites: prev.favorites.includes(k) ? prev.favorites.filter(x => x !== k) : [...prev.favorites, k] })), [set]);
  const toggleFollow = useCallback((k) => set(prev => ({ following: prev.following.includes(k) ? prev.following.filter(x => x !== k) : [...prev.following, k] })), [set]);

  const curArea = AREAS.find(a => a.key === s.area) || AREAS[0];

  // ---- organizer mode ----
  // Any account can host: organizer mode is a switch on the profile, so
  // sign-up and sign-in never have to know which "type" of account this is.
  const canHost = s.organizerMode || s.accountType === 'admin' || s.hasHosted;
  const applyOrganizerMode = useCallback(async (enabled) => {
    if (s.accountType === 'admin') return;
    const rollback = { organizerMode: s.organizerMode, accountType: s.accountType };
    set({ organizerMode: enabled, accountType: enabled ? 'organizer' : 'participant', mode: enabled ? 'host' : 'goer', organizerModeError: '', ...(enabled ? {} : { hasHosted: false }) });
    const { data, error } = await supabase.rpc('set_organizer_mode', { p_enabled: enabled });
    if (error) {
      // Rolling back in silence is what makes the switch look like it "turns
      // itself back off" — always say why it went back.
      console.warn('Organizer mode update failed:', error);
      const notMigrated = error.code === 'PGRST202';
      return set({
        ...rollback,
        mode: rollback.organizerMode ? 'host' : 'goer',
        organizerModeError: notMigrated
          ? T('Máy chủ chưa cài đặt chế độ tổ chức. Hãy chạy các migration Supabase còn thiếu.', 'Organizer mode is not installed on the server yet. Apply the pending Supabase migrations.')
          : T('Không thể đổi chế độ tổ chức lúc này. Vui lòng thử lại.', 'We could not change organizer mode right now. Please try again.'),
      });
    }
    if (data) set({ accountType: data, organizerMode: data === 'organizer' || data === 'admin', organizerModeError: '' });
  }, [set, s.accountType, s.organizerMode, T]);
  const enableOrganizerMode = useCallback(() => applyOrganizerMode(true), [applyOrganizerMode]);
  const toggleOrganizerMode = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'profile' });
    applyOrganizerMode(!canHost);
  }, [set, s.user, canHost, applyOrganizerMode]);

  // ---- navigation ----
  const goHome = useCallback(() => set({ screen: 'home' }), [set]);
  const goProfile = useCallback(() => set({ screen: 'profile' }), [set]);
  const goInbox = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'inbox', authBackScreen: 'home' });
    // Reached from both Home (message icon) and Account ("Messages" row) —
    // remember whichever it was so the way back matches the way in, instead
    // of always landing on Home regardless of where the tap came from.
    set(prev => ({ screen: 'inbox', inboxBack: prev.screen === 'profile' ? 'profile' : 'home' }));
    loadInboxThreads();
  }, [set, s.user, loadInboxThreads]);
  const backFromInbox = useCallback(() => set(prev => ({ screen: prev.inboxBack || 'home' })), [set]);
  // Event Detail is reached from several different sections (the home feed,
  // an organizer dashboard, an organizer profile, the create-event preview),
  // so remember whichever one we came from — its own back arrow used to be
  // hardcoded to Home, which is what made "back" feel like it always
  // returned to the very start regardless of where you'd drilled in from.
  const goEvent = useCallback((key) => set(prev => ({ screen: 'event', eventKey: key, eventBackScreen: prev.screen === 'event' ? prev.eventBackScreen : prev.screen })), [set]);
  const backFromEvent = useCallback(() => set(prev => ({ screen: prev.eventBackScreen || 'home' })), [set]);
  const goOrganizer = useCallback(() => set({ screen: 'organizer' }), [set]);
  const goReserve = useCallback(() => set(s.user ? { screen: 'reserve' } : { screen: 'login', authMode: 'login', authReturnScreen: 'reserve', authBackScreen: 'event' }), [set, s.user]);
  const backToEvent = useCallback(() => set({ screen: 'event' }), [set]);
  const backToOrganizer = useCallback(() => set({ screen: 'organizer' }), [set]);
  const goLogin = useCallback(() => set({ screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'home' }), [set]);
  const goDashboard = useCallback(() => set({ screen: 'dashboard' }), [set]);
  const goCreate = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'create', authBackScreen: 'hostIntro' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'create', mode: 'host' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const openHeld = useCallback(() => set({ screen: 'confirmed' }), [set]);
  const goHostIntro = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'hostIntro', authBackScreen: 'profile' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'hostIntro' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const createBack = useCallback(() => set(prev => ({ screen: prev.hasHosted ? 'dashboard' : 'hostIntro' })), [set]);

  // The "Going"/"Saved" cards on Account — always opened from (and closed
  // back to) Account, so unlike Inbox/Dashboard there's no other entry point
  // to remember.
  const goGoingList = useCallback(() => set({ screen: 'eventList', eventListMode: 'going' }), [set]);
  const goSavedList = useCallback(() => set({ screen: 'eventList', eventListMode: 'saved' }), [set]);
  const backFromEventList = useCallback(() => set({ screen: 'profile' }), [set]);

  // ---- roles ----
  // Reached from both Home's "Your host page" link and Account's "Hosting"
  // card — `back` says which one so the dashboard's back arrow returns
  // there instead of always landing on Home.
  const switchToHost = useCallback((back = 'home') => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'dashboard', authBackScreen: 'home' });
    if (!canHost) enableOrganizerMode();
    set({ mode: 'host', screen: 'dashboard', dashboardBack: back });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const backFromDashboard = useCallback(() => set(prev => ({ screen: prev.dashboardBack || 'home' })), [set]);
  const switchToGoer = useCallback(() => set({ mode: 'goer', screen: 'home' }), [set]);
  const becomeHost = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'hostIntro', authBackScreen: 'profile' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'hostIntro' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const logout = useCallback(async () => {
    await supabase.auth.signOut();
    // Roles belong to the account that just left; leaving them behind would
    // leak the previous user's hosting state into the next sign-in.
    set({ user: null, accountType: 'participant', organizerMode: false, hasHosted: false, mode: 'goer', screen: 'home', referralCode: null, orgRegName: '' });
  }, [set]);

  // ---- display name ----
  const goEditName = useCallback(() => set({ screen: 'editName', editNameValue: s.user?.name || '', editNameError: '' }), [set, s.user?.name]);
  const editNameType = useCallback((e) => set({ editNameValue: e.target.value }), [set]);
  const saveDisplayName = useCallback(async () => {
    const newName = s.editNameValue.trim();
    if (!newName) return set({ editNameError: T('Hãy nhập tên hiển thị.', 'Please enter a display name.') });
    if (newName === s.user?.name) return set({ screen: 'profile' });

    set({ editNameSaving: true, editNameError: '' });
    const oldName = s.user?.name || '';
    const { data, error } = await supabase.rpc('rename_display_name', { p_new_name: newName });
    if (error) {
      set({ editNameSaving: false, editNameError: T('Không thể đổi tên lúc này. Vui lòng thử lại.', 'We could not change your name right now. Please try again.') });
      return;
    }
    set({ editNameSaving: false, user: { ...s.user, name: data?.new_name || newName }, screen: 'profile' });

    // The in-app notification rows are already written by the RPC above —
    // this only dispatches the email side, and re-derives its own recipient
    // list server-side rather than trusting anything from this client.
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify-name-change', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ oldName, newName: data?.new_name || newName }),
        }).catch(() => {});
      }
    } catch { /* best-effort email dispatch; the in-app notification already landed */ }
  }, [set, s.editNameValue, s.user, T]);

  // ---- notifications ----
  const loadNotifications = useCallback(async () => {
    if (!s.user?.id) return;
    const { data, error } = await supabase
      .from('notifications')
      .select('*')
      .eq('recipient_id', s.user.id)
      .order('created_at', { ascending: false })
      .limit(50);
    if (error) { console.warn('Failed to load notifications:', error); return; }
    set({ notifications: data || [], unreadNotifications: (data || []).filter(n => !n.read_at).length });
  }, [set, s.user?.id]);
  const goNotifications = useCallback(() => {
    set({ screen: 'notifications' });
    loadNotifications();
  }, [set, loadNotifications]);
  // Marks one notification read — never all of them at once, and never just
  // from opening the screen. Read status is the visible signal of "have I
  // actually looked at this one", so it has to follow an actual tap on that
  // specific notification, not merely arriving on the list.
  const markNotificationRead = useCallback(async (id) => {
    const target = s.notifications.find(n => n.id === id);
    if (!target || target.read_at) return;
    const readAt = new Date().toISOString();
    set(prev => ({
      notifications: prev.notifications.map(n => (n.id === id ? { ...n, read_at: readAt } : n)),
      unreadNotifications: Math.max(0, prev.unreadNotifications - 1),
    }));
    const { error } = await supabase.from('notifications').update({ read_at: readAt }).eq('id', id);
    if (error) console.warn('Failed to mark notification read:', error);
  }, [set, s.notifications]);

  // ---- lang / area / location ----
  const toggleLang = useCallback(() => {
    const next = EN ? 'vi' : 'en';
    set({ lang: next });
    persistAccountPreference({ locale: next });
  }, [set, EN, persistAccountPreference]);
  const openArea = useCallback(() => set({ areaAsking: true }), [set]);
  const pickArea = useCallback((key) => set({ area: key, areaAsking: false }), [set]);
  const requestFreshCoords = useCallback(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => set({ userCoords: { lat: pos.coords.latitude, lng: pos.coords.longitude } }),
      () => {}, // permission revoked at the OS level, or a transient error — the
      // baked-in placeholder distance stays as the fallback, silently.
      { maximumAge: 5 * 60 * 1000, timeout: 10000 },
    );
  }, [set]);
  const allowLocation = useCallback(() => {
    set({ askingLocation: false, areaAsking: false, located: true });
    requestFreshCoords();
  }, [set, requestFreshCoords]);
  const denyLocation = useCallback(() => set({ askingLocation: false, located: false, userCoords: null }), [set]);

  // If location was already allowed in an earlier session, quietly get a
  // fresh position once per visit — the coordinates themselves are never
  // persisted, only the yes/no decision, so there's nothing to reuse from
  // localStorage.
  const initialLocated = useRef(s.located);
  useEffect(() => {
    if (initialLocated.current === true) requestFreshCoords();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // If it's never been decided, only ask when the user actually reaches for
  // a distance — an unprompted permission dialog on every fresh visit is the
  // kind of thing that trains people to reflexively deny it.
  const askLocation = useCallback(() => set({ askingLocation: true }), [set]);

  // ---- filter ----
  const pickFilter = useCallback((key) => set({ filter: key }), [set]);
  const clearFilters = useCallback(() => set({ filter: 'all', area: 'all' }), [set]);

  // ---- share ----
  const shareEvent = useCallback((ev) => {
    const url = 'https://banbe.app/' + ev.key;
    const done = () => {
      set({ shared: true });
      setTimeout(() => set({ shared: false }), 1800);
    };
    if (navigator.share) {
      navigator.share({ title: 'banbe ▪︎ ' + ev.name, text: ev.name + ' ▪︎ ' + ev.where, url }).catch(done);
    } else if (navigator.clipboard) {
      navigator.clipboard.writeText(url).then(done, done);
    } else { done(); }
  }, [set]);

  // Every account's own invite link — this account's share-with-friends
  // code, minted automatically at signup (migration 023). Redeemed by
  // whoever follows it via the module-level "?ref=" capture at the top of
  // this file + claimPendingReferralAndWelcome() above.
  const referralLink = s.referralCode ? `https://banbe-two.vercel.app/?ref=${s.referralCode}` : null;
  const shareReferral = useCallback(() => {
    if (!referralLink) return;
    const title = T('Tham gia banbe cùng mình', 'Join me on banbe');
    const text = T(
      'Mỗi tuần một vài buổi hay ho — supper club, phòng tranh, gig nhạc nhỏ. Tham gia qua link của mình nhé:',
      "A few good things happening every week — supper clubs, small galleries, tucked-away gigs. Join through my link:"
    );
    const done = () => {
      set({ referralShared: true });
      setTimeout(() => set({ referralShared: false }), 1800);
    };
    if (navigator.share) {
      navigator.share({ title, text, url: referralLink }).catch(done);
    } else if (navigator.clipboard) {
      navigator.clipboard.writeText(referralLink).then(done, done);
    } else { done(); }
  }, [set, referralLink, T]);

  // ---- reserve ----
  const qtyMinus = useCallback(() => set(prev => ({ qty: Math.max(1, prev.qty - 1) })), [set]);
  const qtyPlus = useCallback(() => set(prev => ({ qty: Math.min(6, prev.qty + 1) })), [set]);
  const pickPayNow = useCallback(() => set({ payMode: 'now' }), [set]);
  const pickHold = useCallback(() => set({ payMode: 'hold' }), [set]);
  const formNameType = useCallback((e) => set({ formName: e.target.value }), [set]);
  const formEmailType = useCallback((e) => set({ formEmail: e.target.value }), [set]);
  const submitReserve = useCallback(async (formOk) => {
    if (!formOk) return;
    set({ loading: true, reserveError: '' });

    try {
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session?.user) throw new Error('AUTH_REQUIRED');
      const { data: booking, error } = await supabase.rpc('claim_seats', {
        p_event: s.eventKey,
        p_qty: s.qty,
        p_note: null,
      });
      if (error) throw error;
      const holdDeadline = booking.expires_at ? new Date(booking.expires_at).getTime() : null;
      set(prev => ({
        loading: false,
        booking,
        screen: 'confirmed',
        holdDeadline,
        now: Date.now(),
        tickets: { ...prev.tickets, [prev.eventKey]: prev.qty },
        attending: prev.attending.includes(prev.eventKey) ? prev.attending : [...prev.attending, prev.eventKey],
      }));
    } catch (err) {
      console.warn('Supabase booking failed:', err);
      set({ loading: false, reserveError: err.message || 'Unable to reserve this event.' });
    }
  }, [set, s.eventKey, s.qty]);

  const payHoldNow = useCallback(() => set({ holdDeadline: null, payMode: 'now' }), [set]);
  const confirmPayment = useCallback(async (bookingId, payMethod = 'momo') => {
    try {
      const { data, error } = await supabase.rpc('confirm_payment', { p_booking: bookingId, p_method: payMethod });
      if (error) throw error;
      set(prev => (prev.booking && prev.booking.id === bookingId ? { booking: { ...prev.booking, status: 'confirmed', paid_method: payMethod } } : {}));
      return data;
    } catch (e) {
      console.warn('confirmPayment RPC failed:', e);
    }
  }, [set]);
  const cancelBooking = useCallback(async (bookingId, reason = '') => {
    try {
      const { data, error } = await supabase.rpc('cancel_booking', { p_booking: bookingId, p_reason: reason });
      if (error) throw error;
      set(prev => (prev.booking && prev.booking.id === bookingId ? { booking: { ...prev.booking, status: 'cancelled' } } : {}));
      return data;
    } catch (e) {
      console.warn('cancelBooking RPC failed:', e);
    }
  }, [set]);
  const cancelEvent = useCallback(async (eventId, reason = '') => {
    try {
      const { data, error } = await supabase.rpc('cancel_event', { p_event: eventId, p_reason: reason });
      if (error) throw error;
      return data;
    } catch (e) {
      console.warn('cancelEvent RPC failed:', e);
    }
  }, []);
  const addToCalendar = useCallback(() => set({ calAdded: true }), [set]);
  const giveTicket = useCallback((ev) => {
    const url = 'https://banbe.app/ve/' + ev.key + '-x7f2';
    if (navigator.share) navigator.share({ title: 'banbe ▪︎ ' + ev.name, text: T('Mình có vé cho bạn', 'I have a ticket for you'), url }).catch(() => {});
    else if (navigator.clipboard) navigator.clipboard.writeText(url).catch(() => {});
    set({ gaveTicket: true });
    setTimeout(() => set({ gaveTicket: false }), 2200);
  }, [set, T]);

  // ---- login ----
  const loginEmailType = useCallback((e) => set({ loginEmail: e.target.value }), [set]);
  const loginNicknameType = useCallback((e) => set({ loginNickname: e.target.value }), [set]);
  const loginPhoneType = useCallback((e) => set({ loginPhoneNumber: e.target.value }), [set]);
  const loginCodeType = useCallback((e) => set({ loginCode: e.target.value }), [set]);
  const loginEmailCodeType = useCallback((e) => set({ loginEmailCode: e.target.value }), [set]);
  const loginPasswordType = useCallback((e) => set({ loginPassword: e.target.value }), [set]);
  const loginPasswordConfirmType = useCallback((e) => set({ loginPasswordConfirm: e.target.value }), [set]);
  const emailValid = (v) => /\S+@\S+\.\S+/.test(v);
  const passwordValid = (v) => v.length >= 8;
  // Switching between "code" and "password" (or Login/Signup) always clears
  // whatever partial attempt was in flight — a stale error or a code sent
  // for the other method would otherwise linger and confuse the new one.
  const setAuthMethod = useCallback((authMethod) => set({
    authMethod, reserveError: '', loginSent: false, loginSentVia: null, loginEmailCode: '', resetRequested: false,
  }), [set]);
  const authEmailErrorMessage = useCallback((error, mode) => {
    const code = error?.code || error?.message;
    if (code === 'AUTH_ACCOUNT_NOT_FOUND' && mode !== 'signup') {
      return T('Không tìm thấy tài khoản với email này. Hãy chọn Đăng ký trước.', 'No account exists for this email. Choose Sign up first.');
    }
    if (code === 'AUTH_ACCOUNT_EXISTS') {
      return T('Email này đã có tài khoản. Hãy chọn Đăng nhập để tiếp tục.', 'This email already has an account. Choose Log in to continue.');
    }
    if (code === 'VALID_NAME_REQUIRED') {
      return T('Hãy nhập tên hiển thị của bạn.', 'Please enter a display name.');
    }
    if (code === 'VALID_PASSWORD_REQUIRED') {
      return T('Mật khẩu phải có ít nhất 8 ký tự.', 'Password must be at least 8 characters.');
    }
    if (code === 'AUTH_EMAIL_DELIVERY_FAILED') {
      return T('Không thể gửi email lúc này. Vui lòng thử lại sau.', 'We could not send the email right now. Please try again later.');
    }
    if (code === 'AUTH_ACCOUNT_LOOKUP_FAILED') {
      return T('Không thể kiểm tra tài khoản lúc này. Vui lòng thử lại sau.', 'We could not check the account right now. Please try again later.');
    }
    if (code === 'AUTH_EMAIL_REQUEST_FAILED') {
      return T('Không thể xử lý yêu cầu email. Vui lòng thử lại sau.', 'We could not process the email request. Please try again later.');
    }
    if (code === 'AUTH_LINK_GENERATION_FAILED') {
      return T('Không thể tạo mã xác thực. Vui lòng thử lại sau.', 'We could not create the verification code. Please try again later.');
    }
    if (code === 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED') {
      return T('Dịch vụ email chưa được cấu hình. Vui lòng thử lại sau.', 'The email service is not configured yet. Please try again later.');
    }
    if (mode === 'reset') {
      return T('Không thể gửi email đặt lại mật khẩu. Vui lòng thử lại sau.', 'We could not send the password reset email. Please try again later.');
    }
    return mode === 'signup'
      ? T('Không thể gửi mã đăng ký. Vui lòng thử lại sau.', 'We could not send the sign-up code. Please try again later.')
      : T('Không thể gửi mã đăng nhập. Vui lòng thử lại sau.', 'We could not send the sign-in code. Please try again later.');
  }, [T]);
  // "Code" method: request a 6-digit code by email, for either Login or
  // Signup. Verifying it (below) is what actually establishes the session.
  const codeRequestSubmit = useCallback(async () => {
    if (!emailValid(s.loginEmail)) return;
    const email = s.loginEmail.trim();
    const displayName = s.loginNickname.trim();
    if (s.authMode === 'signup' && !displayName) {
      return set({ reserveError: authEmailErrorMessage({ code: 'VALID_NAME_REQUIRED' }, s.authMode) });
    }
    try {
      await requestAuthEmail({ email, mode: s.authMode, locale: s.lang, ...(s.authMode === 'signup' ? { displayName } : {}) });
      set({ loginSent: true, loginSentVia: 'email', pendingEmailMode: s.authMode, reserveError: '' });
    } catch (e) {
      set({ loginSent: false, loginSentVia: null, reserveError: authEmailErrorMessage(e, s.authMode) });
    }
  }, [set, s.loginEmail, s.loginNickname, s.authMode, authEmailErrorMessage]);
  // "Password" method, Signup: creates the account with the password
  // actually chosen, then — same as the code method — still requires
  // entering the emailed confirmation code once to finish.
  const passwordSignupSubmit = useCallback(async () => {
    if (!emailValid(s.loginEmail)) return;
    const email = s.loginEmail.trim();
    const displayName = s.loginNickname.trim();
    if (!displayName) return set({ reserveError: authEmailErrorMessage({ code: 'VALID_NAME_REQUIRED' }, 'signup') });
    if (!passwordValid(s.loginPassword)) return set({ reserveError: authEmailErrorMessage({ code: 'VALID_PASSWORD_REQUIRED' }, 'signup') });
    if (s.loginPassword !== s.loginPasswordConfirm) {
      return set({ reserveError: T('Mật khẩu xác nhận không khớp.', 'Passwords do not match.') });
    }
    try {
      await requestPasswordSignup({ email, password: s.loginPassword, displayName, locale: s.lang });
      set({ loginSent: true, loginSentVia: 'email', pendingEmailMode: 'signup', reserveError: '' });
    } catch (e) {
      set({ loginSent: false, loginSentVia: null, reserveError: authEmailErrorMessage(e, 'signup') });
    }
  }, [set, s.loginEmail, s.loginNickname, s.loginPassword, s.loginPasswordConfirm, authEmailErrorMessage, T]);
  // "Password" method, Login: straight to Supabase, no code step — the
  // account already has a password. (The onAuthStateChange listener handles
  // moving off the Login screen once the session lands.)
  const passwordLoginSubmit = useCallback(async () => {
    if (!emailValid(s.loginEmail)) return;
    if (!s.loginPassword) return set({ reserveError: T('Nhập mật khẩu của bạn.', 'Enter your password.') });
    const { error } = await supabase.auth.signInWithPassword({ email: s.loginEmail.trim(), password: s.loginPassword });
    if (error) {
      set({ reserveError: T('Sai email hoặc mật khẩu.', 'Wrong email or password.') });
      return;
    }
    set({ reserveError: '' });
  }, [set, s.loginEmail, s.loginPassword, T]);
  // Runs exactly once, right after a brand-new account's first sign-in
  // (never on an ordinary login — see the isSignup guard at the call site).
  // Redeems whatever referral code was stashed from the "?ref=" link they
  // followed (if any), then always sends the welcome email introducing
  // this account's own link, regardless of whether they arrived via
  // someone else's. Both dispatches are best-effort: a failure here never
  // blocks the sign-up itself, since the account already exists by the
  // time this runs.
  const claimPendingReferralAndWelcome = useCallback(async () => {
    let referredSomeone = false;
    try {
      const pendingCode = localStorage.getItem(REFERRAL_STORAGE_KEY);
      if (pendingCode) {
        localStorage.removeItem(REFERRAL_STORAGE_KEY);
        const { data, error } = await supabase.rpc('redeem_referral', { p_code: pendingCode });
        referredSomeone = !error && data?.success === true;
      }
    } catch { /* best-effort — the account itself is already created */ }

    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) return;
      fetch('/api/notify-welcome', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
      }).catch(() => {});
      if (referredSomeone) {
        fetch('/api/notify-referral-joined', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
        }).catch(() => {});
      }
    } catch { /* best-effort; the account and any redemption already landed */ }
  }, []);
  // Finishes either code flow above — Login-by-code, Signup-by-code, or
  // Signup-by-password's confirmation step — by verifying the code directly
  // against Supabase itself; a real session comes back on success and the
  // onAuthStateChange listener takes it from there.
  const verifyEmailCode = useCallback(async () => {
    const email = s.loginEmail.trim();
    const token = s.loginEmailCode.trim();
    if (!token) return set({ reserveError: T('Nhập mã đã gửi tới email của bạn.', 'Enter the code sent to your email.') });
    const isSignup = s.pendingEmailMode === 'signup';
    const { error } = await supabase.auth.verifyOtp({ email, token, type: isSignup ? 'signup' : 'email' });
    if (error) {
      set({ reserveError: T('Mã không đúng hoặc đã hết hạn. Vui lòng thử lại.', 'That code is wrong or has expired. Please try again.') });
      return;
    }
    set({ reserveError: '', loginEmailCode: '' });
    if (isSignup) claimPendingReferralAndWelcome();
  }, [set, s.loginEmail, s.loginEmailCode, s.pendingEmailMode, T, claimPendingReferralAndWelcome]);
  // "Forgot password?" — always shows the same generic confirmation
  // regardless of whether the account actually exists (see
  // send-password-reset.js); only a real failure to even attempt sending
  // gets its own message.
  const requestPasswordResetSubmit = useCallback(async () => {
    if (!emailValid(s.loginEmail)) return set({ reserveError: T('Nhập email của bạn trước.', 'Enter your email first.') });
    try {
      await requestPasswordReset({ email: s.loginEmail.trim() });
      set({ resetRequested: true, reserveError: '' });
    } catch (e) {
      set({ resetRequested: false, reserveError: authEmailErrorMessage(e, 'reset') });
    }
  }, [set, s.loginEmail, authEmailErrorMessage, T]);
  // Single Enter-key / submit dispatcher for the Login screen — routes to
  // whichever action the currently-visible form actually needs.
  const submitCurrentForm = useCallback(() => {
    if (s.loginSentVia === 'email') { verifyEmailCode(); return; }
    if (s.authMethod === 'password') {
      if (s.authMode === 'signup') passwordSignupSubmit(); else passwordLoginSubmit();
      return;
    }
    codeRequestSubmit();
  }, [s.loginSentVia, s.authMethod, s.authMode, verifyEmailCode, passwordSignupSubmit, passwordLoginSubmit, codeRequestSubmit]);
  const loginEmailKey = useCallback((e) => { if (e.key === 'Enter') submitCurrentForm(); }, [submitCurrentForm]);
  const loginZalo = useCallback(() => set({ reserveError: T('Zalo chưa khả dụng. Hãy dùng email hoặc OTP điện thoại.', 'Zalo is not available yet. Use email or phone OTP.') }), [set, T]);
  const loginPhone = useCallback(async () => {
    const phone = s.loginPhoneNumber.trim();
    if (!phone) return set({ reserveError: T('Nhập số điện thoại trước.', 'Enter your phone number first.') });
    const { error } = await supabase.auth.signInWithOtp({ phone });
    set(error ? { reserveError: error.message } : { loginSent: true, loginSentVia: 'phone', reserveError: '' });
  }, [set, s.loginPhoneNumber, T]);
  const verifyLoginCode = useCallback(async () => {
    if (!s.loginPhoneNumber.trim() || !s.loginCode.trim()) return set({ reserveError: T('Nhập mã OTP.', 'Enter the OTP code.') });
    const { error } = await supabase.auth.verifyOtp({ phone: s.loginPhoneNumber.trim(), token: s.loginCode.trim(), type: 'sms' });
    if (error) set({ reserveError: error.message });
  }, [set, s.loginPhoneNumber, s.loginCode, T]);
  const loginFacebook = useCallback(() => set({ reserveError: T('Facebook chưa khả dụng. Hãy dùng email hoặc OTP điện thoại.', 'Facebook is not available yet. Use email or phone OTP.') }), [set, T]);
  const loginInstagram = useCallback(() => set({ reserveError: T('Instagram chưa khả dụng. Hãy dùng email hoặc OTP điện thoại.', 'Instagram is not available yet. Use email or phone OTP.') }), [set, T]);

  // ---- reset-password screen (landed on via the emailed recovery link —
  // see the PASSWORD_RECOVERY branch of onAuthStateChange above) ----
  const newPasswordType = useCallback((e) => set({ newPassword: e.target.value, resetPasswordError: '' }), [set]);
  const newPasswordConfirmType = useCallback((e) => set({ newPasswordConfirm: e.target.value, resetPasswordError: '' }), [set]);
  const submitNewPassword = useCallback(async () => {
    if (!passwordValid(s.newPassword)) {
      return set({ resetPasswordError: T('Mật khẩu phải có ít nhất 8 ký tự.', 'Password must be at least 8 characters.') });
    }
    if (s.newPassword !== s.newPasswordConfirm) {
      return set({ resetPasswordError: T('Mật khẩu không khớp.', 'Passwords do not match.') });
    }
    set({ resetPasswordBusy: true, resetPasswordError: '' });
    const { error } = await supabase.auth.updateUser({ password: s.newPassword });
    if (error) {
      set({ resetPasswordBusy: false, resetPasswordError: T('Không thể đặt mật khẩu mới. Vui lòng thử lại.', 'Could not set the new password. Please try again.') });
      return;
    }
    set({ resetPasswordBusy: false, newPassword: '', newPasswordConfirm: '', screen: 'home' });
  }, [set, s.newPassword, s.newPasswordConfirm, T]);

  // ---- chat ----
  // Real threads/messages (supabase/migrations/003_social_chat.sql) — this
  // used to be pure local state (`chats`) with no server backing at all.
  const chatOnType = useCallback((e) => set({ chatDraft: e.target.value }), [set]);
  const loadChatMessages = useCallback(async (threadId) => {
    const { data, error } = await supabase
      .from('messages')
      .select('id, sender_id, body, created_at')
      .eq('thread_id', threadId)
      .order('created_at', { ascending: true });
    if (!error) set({ chatMessages: data || [] });
  }, [set]);
  // Get-or-create the one thread between the signed-in guest and this
  // event's organizer. Never called for the organizer's own side of a
  // conversation — that always opens a specific, already-known thread
  // (see openThread, used from Inbox).
  const openChatFor = useCallback(async (key, back) => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'chat', authBackScreen: 'organizer' });
    set({ screen: 'chat', eventKey: key, chatBack: back || 'organizer', chatThreadId: null, chatMessages: [] });

    const { data: existing } = await supabase.from('threads').select('id').eq('event_id', key).eq('guest_id', s.user.id).maybeSingle();
    if (existing?.id) { set({ chatThreadId: existing.id }); loadChatMessages(existing.id); return; }

    const { data: event } = await supabase.from('events').select('organizer_id').eq('id', key).maybeSingle();
    if (!event?.organizer_id) return; // no real DB row for this event yet — nothing to open
    const { data: created, error } = await supabase
      .from('threads')
      .insert({ event_id: key, guest_id: s.user.id, organizer_id: event.organizer_id })
      .select('id')
      .maybeSingle();
    if (error) {
      // Another tab/request created it first — fetch what's there now.
      const { data: retry } = await supabase.from('threads').select('id').eq('event_id', key).eq('guest_id', s.user.id).maybeSingle();
      if (retry?.id) { set({ chatThreadId: retry.id }); loadChatMessages(retry.id); }
      return;
    }
    if (created?.id) { set({ chatThreadId: created.id }); loadChatMessages(created.id); }
  }, [set, s.user, loadChatMessages]);
  // "Message the host" from an event/organizer/refund screen — always about
  // whichever event is currently open.
  const goChat = useCallback(() => openChatFor(s.eventKey, 'organizer'), [openChatFor, s.eventKey]);
  // Opens a specific, already-known thread — used from Inbox, on either side
  // (guest continuing a conversation, or organizer replying to a guest).
  const openThread = useCallback((threadId, eventKey, back) => {
    set({ screen: 'chat', eventKey, chatBack: back || 'inbox', chatThreadId: threadId, chatMessages: [] });
    loadChatMessages(threadId);
  }, [set, loadChatMessages]);
  // Tapping a notification marks it read and, for the kinds that point at
  // somewhere real, takes you there — a 'new_message' notification opens the
  // actual thread it's about instead of just sitting there read.
  const openNotification = useCallback((n) => {
    markNotificationRead(n.id);
    if (n.kind === 'new_message' && n.data?.thread_id) {
      openThread(n.data.thread_id, n.data.event_id, 'inbox');
    }
  }, [markNotificationRead, openThread]);
  const chatSend = useCallback(async () => {
    const text = s.chatDraft.trim();
    if (!text || !s.chatThreadId || !s.user) return;
    set({ chatDraft: '' });
    const { data, error } = await supabase
      .from('messages')
      .insert({ thread_id: s.chatThreadId, sender_id: s.user.id, body: text, kind: 'text' })
      .select('id, sender_id, body, created_at')
      .maybeSingle();
    if (error) {
      console.warn('Failed to send message:', error);
      set({ chatDraft: text });
      return;
    }
    set(prev => ({ chatMessages: [...prev.chatMessages, data] }));
    // No email here any more — the in-app notification (via the
    // notify_new_message trigger) is the only notification a new message
    // gets; tapping it now takes you straight to the thread.
  }, [set, s.chatDraft, s.chatThreadId, s.user]);
  const chatOnKey = useCallback((e) => { if (e.key === 'Enter') chatSend(); }, [chatSend]);
  const chatBackFn = useCallback(() => set(prev => ({ screen: prev.chatBack === 'inbox' ? 'inbox' : 'organizer' })), [set]);

  // While the chat screen is open, poll for messages the other side sent —
  // there's no realtime subscription here, just a simple refresh.
  useEffect(() => {
    if (s.screen !== 'chat' || !s.chatThreadId) return;
    const id = setInterval(() => loadChatMessages(s.chatThreadId), 4000);
    return () => clearInterval(id);
  }, [s.screen, s.chatThreadId, loadChatMessages]);

  // ---- create / org profile ----
  const orgRegNameType = useCallback((e) => set({ orgRegName: e.target.value }), [set]);
  const orgRegIgType = useCallback((e) => set({ orgRegIg: e.target.value }), [set]);
  const orgRegDescType = useCallback((e) => set({ orgRegDesc: e.target.value }), [set]);
  const createNameType = useCallback((e) => set({ createName: e.target.value }), [set]);
  const createDescType = useCallback((e) => set({ createDesc: e.target.value }), [set]);
  const createLocType = useCallback((e) => set({ createLoc: e.target.value }), [set]);
  const createDateType = useCallback((e) => set({ createDate: e.target.value }), [set]);
  const createPriceType = useCallback((e) => set({ createPrice: e.target.value }), [set]);
  const createSeatsType = useCallback((e) => set({ createSeats: e.target.value }), [set]);
  const pickCreateCat = useCallback((key) => set(prev => {
    let cats = prev.createCats.includes(key) ? prev.createCats.filter(x => x !== key) : [...prev.createCats, key];
    if (cats.length > 2) cats = [cats[0], key];
    return { createCats: cats };
  }), [set]);
  const pickCreatePalette = useCallback((key) => set({ createPalette: key }), [set]);
  const tapPhotoSlot = useCallback((index) => set(prev => ({ createPhotos: index < prev.createPhotos ? prev.createPhotos : Math.min(8, prev.createPhotos + 1) })), [set]);
  const createSubmit = useCallback(async () => {
    if (!s.createName.trim()) return;
    set({ loading: true, createError: '' });
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session?.user) throw new Error('AUTH_REQUIRED');
      // Publishing an event is the act of hosting, so make sure organizer
      // mode is on before create_event_draft checks the profile role.
      if (!canHost) await applyOrganizerMode(true);
      const priceVnd = parseInt((s.createPrice.match(/[\d.]+/) || ['0'])[0].replace(/\./g, ''), 10) || 0;
      const capacity = parseInt(s.createSeats, 10) || 0;
      const dateMatch = s.createDate.match(/(\d{1,2})\.(\d{1,2})/);
      const timeMatch = s.createDate.match(/(\d{1,2}):(\d{2})/);
      const { error } = await supabase.rpc('create_event_draft', {
        p_name: s.createName.trim(),
        p_category: s.createCats[0] || 'supper',
        p_description: s.createDesc.trim(),
        p_location: s.createLoc.trim(),
        p_event_date: dateMatch ? `2026-${String(parseInt(dateMatch[2], 10)).padStart(2, '0')}-${String(parseInt(dateMatch[1], 10)).padStart(2, '0')}` : null,
        p_event_time: timeMatch ? `${timeMatch[1].padStart(2, '0')}:${timeMatch[2]}` : null,
        p_price_vnd: priceVnd,
        p_capacity: capacity,
        p_organizer_name: s.orgRegName.trim() || 'Organizer',
        p_instagram: s.orgRegIg.trim(),
        p_about: s.orgRegDesc.trim(),
      });
      if (error) throw error;
      set({ loading: false, createSent: true, hasHosted: true, mode: 'host' });
    } catch (err) {
      console.warn('Event draft creation failed:', err);
      set({ loading: false, createError: err.message || 'Unable to submit this event.' });
    }
  }, [set, s.createName, s.createCats, s.createDesc, s.createLoc, s.createDate, s.createPrice, s.createSeats, s.orgRegName, s.orgRegIg, s.orgRegDesc, canHost, applyOrganizerMode]);
  const requestVerify = useCallback(() => set({ orgVerifyRequested: true }), [set]);

  // ---- attendance ----
  // The guest list is real bookings for this event (not the old fake
  // GUESTS() generator), resolved to display names via the profiles row a
  // check-in host is now allowed to read (see the RLS policy added
  // alongside check_in_guest()'s notification).
  const loadAttendanceGuests = useCallback(async (key) => {
    set({ attendanceLoading: true });
    const { data: bookings, error } = await supabase
      .from('bookings')
      .select('id, user_id, qty, status')
      .eq('event_id', key)
      .in('status', ['confirmed', 'attended']);
    if (error) {
      console.warn('Failed to load attendance list:', error);
      set({ attendanceGuests: [], attendanceLoading: false });
      return;
    }
    const userIds = [...new Set((bookings || []).map(b => b.user_id).filter(Boolean))];
    let names = {};
    if (userIds.length) {
      const { data: profiles } = await supabase.from('profiles').select('id, display_name').in('id', userIds);
      names = Object.fromEntries((profiles || []).map(p => [p.id, p.display_name]));
    }
    const guests = (bookings || []).map(b => ({
      id: b.id,
      name: (names[b.user_id] || '').trim() || 'Khách',
      qty: b.qty,
      checkedIn: b.status === 'attended',
    }));
    set({ attendanceGuests: guests, attendanceLoading: false });
  }, [set]);
  const openAttendance = useCallback((key) => {
    set({ screen: 'attendance', attendanceEventKey: key, attendanceGuests: [] });
    loadAttendanceGuests(key);
  }, [set, loadAttendanceGuests]);
  const notifyCheckIn = useCallback(async (bookingId) => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify-check-in', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ bookingId }),
        }).catch(() => {});
      }
    } catch { /* best-effort email; the in-app notification already landed */ }
  }, []);
  // ---- reason-required status changes (undo check-in, cancel booking) ----
  // Reversing a check-in or cancelling an already-paid booking always
  // requires picking one of a fixed list of reasons (never free text), so
  // the guest's notification always says something concrete — see
  // UNDO_CHECKIN_REASONS / CANCEL_BOOKING_REASONS above.
  const openUndoCheckin = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'undoCheckin', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const openCancelBooking = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'cancelBooking', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const closeReasonPrompt = useCallback(() => set({ reasonPrompt: null, reasonPromptError: '' }), [set]);
  const submitReasonPrompt = useCallback(async (reasonLabel) => {
    const prompt = s.reasonPrompt;
    if (!prompt) return;
    set({ reasonPromptBusy: true, reasonPromptError: '' });

    const rpcName = prompt.kind === 'undoCheckin' ? 'undo_check_in' : 'cancel_booking';
    const rpcArgs = prompt.kind === 'undoCheckin'
      ? { p_booking_id: prompt.bookingId, p_reason: reasonLabel }
      : { p_booking: prompt.bookingId, p_reason: reasonLabel };
    const { data, error } = await supabase.rpc(rpcName, rpcArgs);
    if (error || !data?.success) {
      set({
        reasonPromptBusy: false,
        reasonPromptError: prompt.kind === 'undoCheckin'
          ? T('Không thể huỷ điểm danh. Vui lòng thử lại.', 'Could not undo the check-in. Please try again.')
          : T('Không thể huỷ vé. Vui lòng thử lại.', 'Could not cancel the booking. Please try again.'),
      });
      return;
    }

    set({ reasonPrompt: null, reasonPromptBusy: false });
    if (s.attendanceEventKey) loadAttendanceGuests(s.attendanceEventKey);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      const endpoint = prompt.kind === 'undoCheckin' ? '/api/notify-checkin-undo' : '/api/notify-booking-cancelled';
      if (token) {
        fetch(endpoint, {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ bookingId: prompt.bookingId, reason: reasonLabel }),
        }).catch(() => {});
      }
    } catch { /* best-effort email; the in-app notification already landed */ }
  }, [set, s.reasonPrompt, s.attendanceEventKey, loadAttendanceGuests, T]);

  const toggleCheckin = useCallback(async (bookingId, checked) => {
    if (checked) { openUndoCheckin(bookingId); return; } // reversing requires a reason — see below
    set(prev => ({ attendanceGuests: prev.attendanceGuests.map(g => (g.id === bookingId ? { ...g, checkedIn: true } : g)) }));
    const { data, error } = await supabase.rpc('check_in_guest', { p_reservation_id: bookingId });
    if (error || !data?.success) {
      console.warn('Check-in failed:', error || data?.error);
      set(prev => ({ attendanceGuests: prev.attendanceGuests.map(g => (g.id === bookingId ? { ...g, checkedIn: false } : g)) }));
      return;
    }
    notifyCheckIn(bookingId);
  }, [set, notifyCheckIn, openUndoCheckin]);

  // ---- QR check-in ----
  // A guest's ticket QR encodes their booking id directly (Confirmed.jsx),
  // so scanning it calls the exact same, already-authorized RPC the manual
  // tap-to-check-in list uses — just without needing that guest to already
  // be visible in a loaded list first.
  const openQrScan = useCallback(() => set({ scanningQr: true, qrScanError: '' }), [set]);
  const closeQrScan = useCallback(() => set({ scanningQr: false }), [set]);
  const checkInByScan = useCallback(async (bookingId) => {
    const { data, error } = await supabase.rpc('check_in_guest', { p_reservation_id: bookingId });
    if (error || !data?.success) {
      return { success: false, error: (data && data.error) || error?.message || 'CHECK_IN_FAILED' };
    }
    notifyCheckIn(bookingId);
    if (s.attendanceEventKey) loadAttendanceGuests(s.attendanceEventKey);
    return { success: true };
  }, [notifyCheckIn, s.attendanceEventKey, loadAttendanceGuests]);

  const value = useMemo(() => ({
    state: s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea,
    isSaved, isGoing, toggleFav, toggleFollow,
    goHome, goProfile, goInbox, backFromInbox, goEvent, backFromEvent, goOrganizer, goReserve, backToEvent, backToOrganizer,
    goChat, goLogin, goDashboard, goCreate, openAttendance, openHeld, goHostIntro, createBack,
    goGoingList, goSavedList, backFromEventList,
    switchToHost, backFromDashboard, switchToGoer, becomeHost, logout, dismissSplash,
    goEditName, editNameType, saveDisplayName, goNotifications, markNotificationRead, openNotification,
    canHost, toggleOrganizerMode, enableOrganizerMode,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, askLocation, toggleTheme, pickTheme, openPreferences,
    pickFilter, clearFilters, shareEvent, referralLink, shareReferral,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, formEmailType, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    addToCalendar, giveTicket,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType, loginPasswordType, loginPasswordConfirmType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginInstagram, emailValid, passwordValid, setAuthMethod, codeRequestSubmit, passwordSignupSubmit, passwordLoginSubmit, verifyEmailCode, requestPasswordResetSubmit, submitCurrentForm, newPasswordType, newPasswordConfirmType, submitNewPassword,
    chatOnType, chatSend, chatOnKey, chatBackFn, openChatFor, openThread,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, requestVerify,
    toggleCheckin, openQrScan, closeQrScan, checkInByScan, openCancelBooking, closeReasonPrompt, submitReasonPrompt,
  }), [
    s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea,
    isSaved, isGoing, toggleFav, toggleFollow,
    goHome, goProfile, goInbox, backFromInbox, goEvent, backFromEvent, goOrganizer, goReserve, backToEvent, backToOrganizer,
    goChat, goLogin, goDashboard, goCreate, openAttendance, openHeld, goHostIntro, createBack,
    goGoingList, goSavedList, backFromEventList,
    switchToHost, backFromDashboard, switchToGoer, becomeHost, logout, dismissSplash,
    goEditName, editNameType, saveDisplayName, goNotifications, markNotificationRead, openNotification,
    canHost, toggleOrganizerMode, enableOrganizerMode,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, askLocation, toggleTheme, pickTheme, openPreferences,
    pickFilter, clearFilters, shareEvent, referralLink, shareReferral,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, formEmailType, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    addToCalendar, giveTicket,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType, loginPasswordType, loginPasswordConfirmType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginInstagram, setAuthMethod, codeRequestSubmit, passwordSignupSubmit, passwordLoginSubmit, verifyEmailCode, requestPasswordResetSubmit, submitCurrentForm, newPasswordType, newPasswordConfirmType, submitNewPassword,
    chatOnType, chatSend, chatOnKey, chatBackFn, openChatFor, openThread,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, requestVerify,
    toggleCheckin, openQrScan, closeQrScan, checkInByScan, openCancelBooking, closeReasonPrompt, submitReasonPrompt,
  ]);

  return <GocCtx.Provider value={value}>{children}</GocCtx.Provider>;
}

export function useGoc() {
  const ctx = useContext(GocCtx);
  if (!ctx) throw new Error('useGoc must be used within GocProvider');
  return ctx;
}

export { EVENTS, findEvent };
