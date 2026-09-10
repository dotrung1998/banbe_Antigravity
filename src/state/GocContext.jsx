import { createContext, useContext, useEffect, useMemo, useState, useCallback, useRef } from 'react';
import { EVENTS, findEvent } from '../data/events.js';
import { supabase } from '../lib/supabase.js';
import { requestAuthEmail } from '../lib/authEmail.js';

const GocCtx = createContext(null);

const initialState = {
  screen: 'splash',
  mode: 'goer',
  hasHosted: false,
  eventKey: 'bepnho',
  eventBackScreen: 'home',
  loading: false,
  filter: 'all',
  formName: '',
  formEmail: '',
  chatDraft: '',
  chatBack: 'organizer',
  chats: {
    bepnho: [
      { who: 'host', text: 'Chào bạn, mình là Minh. Cứ hỏi thoải mái nhé.' },
      { who: 'me', text: 'Tối thứ bảy còn chỗ cho 2 người không anh?' },
      { who: 'host', text: 'Còn đúng 2 chỗ, mình giữ cho bạn nhé.' },
    ],
    orbit: [
      { who: 'host', text: 'Rue Miche đây. Có gì cần hỏi về buổi diễn không?' },
      { who: 'me', text: 'Dress code có gì đặc biệt không?' },
    ],
  },
  shared: false,
  attending: ['bepnho', 'orbit'],
  tickets: { bepnho: 2, orbit: 1 },
  located: null,
  askingLocation: false,
  user: null,
  accountType: 'participant',
  organizerMode: false,
  organizerModeError: '',
  authMode: 'login',
  authReturnScreen: 'home',
  authBackScreen: 'home',
  loginEmail: '',
  loginPhoneNumber: '',
  loginCode: '',
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
  favorites: ['bepnho', 'bandai', 'motlop'],
  invited: ['banrieng'],
  orgVerifyRequested: false,
  attendanceEventKey: null,
  checkins: {},
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

export function GocProvider({ children }) {
  const [state, setStateRaw] = useState(() => {
    try {
      const raw = localStorage.getItem('banbe.preferences');
      const saved = JSON.parse(raw || '{}');
      return {
        ...initialState,
        lang: saved.lang === 'en' ? 'en' : 'vi',
        theme: saved.theme === 'dark' ? 'dark' : 'light',
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
    localStorage.setItem('banbe.preferences', JSON.stringify({ lang: state.lang, theme: state.theme }));
  }, [state.lang, state.theme]);

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
        set({ user: null });
        return;
      }
      const { data: profile } = await supabase
        .from('profiles')
        .select('role, locale, theme, prefs_saved')
        .eq('id', user.id)
        .maybeSingle();
      const role =
        profile?.role ||
        user.user_metadata?.account_type ||
        user.raw_user_meta_data?.account_type ||
        'participant';
      const canHostNow = role === 'organizer' || role === 'admin';
      set({ user, accountType: role, organizerMode: canHostNow, mode: canHostNow ? 'host' : 'goer' });

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
        set(prev => ({
          screen: prev.screen === 'login' ? prev.authReturnScreen : prev.screen,
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
      if (!event) return;
      const { data: booking } = await supabase.from('bookings').select('*').eq('event_id', event.id).eq('user_id', s.user.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
      if (active && booking) set({ booking, holdDeadline: booking.expires_at ? new Date(booking.expires_at).getTime() : null });
    })();
    return () => { active = false; };
  }, [set, s.user?.id, s.eventKey]);

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
  const stripKm = useCallback((str) => (located ? str : str.replace(/ ▪︎ \d+[.,]\d+ km(?: từ bạn| away)?/g, '')), [located]);

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
  const goInbox = useCallback(() => set(s.user ? { screen: 'inbox' } : { screen: 'login', authMode: 'login', authReturnScreen: 'inbox', authBackScreen: 'home' }), [set, s.user]);
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
  const goChat = useCallback(() => set({ screen: s.user ? 'chat' : 'login', chatBack: 'organizer' }), [set, s.user]);
  const goLogin = useCallback(() => set({ screen: 'login', authMode: 'login', authReturnScreen: 'profile', authBackScreen: 'home' }), [set]);
  const goDashboard = useCallback(() => set({ screen: 'dashboard' }), [set]);
  const goCreate = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'create', authBackScreen: 'hostIntro' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'create', mode: 'host' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const openAttendance = useCallback((key) => set({ screen: 'attendance', attendanceEventKey: key }), [set]);
  const openHeld = useCallback(() => set({ screen: 'confirmed' }), [set]);
  const goHostIntro = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'hostIntro', authBackScreen: 'profile' });
    if (!canHost) enableOrganizerMode();
    set({ screen: 'hostIntro' });
  }, [set, s.user, canHost, enableOrganizerMode]);
  const createBack = useCallback(() => set(prev => ({ screen: prev.hasHosted ? 'dashboard' : 'hostIntro' })), [set]);

  // ---- roles ----
  const switchToHost = useCallback(() => {
    if (!s.user) return set({ screen: 'login', authMode: 'login', authReturnScreen: 'dashboard', authBackScreen: 'home' });
    if (!canHost) enableOrganizerMode();
    set({ mode: 'host', screen: 'dashboard' });
  }, [set, s.user, canHost, enableOrganizerMode]);
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
    set({ user: null, accountType: 'participant', organizerMode: false, hasHosted: false, mode: 'goer', screen: 'home' });
  }, [set]);

  // ---- lang / area / location ----
  const toggleLang = useCallback(() => {
    const next = EN ? 'vi' : 'en';
    set({ lang: next });
    persistAccountPreference({ locale: next });
  }, [set, EN, persistAccountPreference]);
  const openArea = useCallback(() => set({ areaAsking: true }), [set]);
  const pickArea = useCallback((key) => set({ area: key, areaAsking: false }), [set]);
  const allowLocation = useCallback(() => {
    set({ askingLocation: false, areaAsking: false, located: true });
    if (navigator.geolocation) navigator.geolocation.getCurrentPosition(() => {}, () => {});
  }, [set]);
  const denyLocation = useCallback(() => set({ askingLocation: false, located: false }), [set]);

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
  const loginPhoneType = useCallback((e) => set({ loginPhoneNumber: e.target.value }), [set]);
  const loginCodeType = useCallback((e) => set({ loginCode: e.target.value }), [set]);
  const emailValid = (v) => /\S+@\S+\.\S+/.test(v);
  const authEmailErrorMessage = useCallback((error, mode) => {
    const code = error?.code || error?.message;
    if (code === 'AUTH_ACCOUNT_NOT_FOUND' && mode !== 'signup') {
      return T('Không tìm thấy tài khoản với email này. Hãy chọn Đăng ký trước.', 'No account exists for this email. Choose Sign up first.');
    }
    if (code === 'AUTH_ACCOUNT_EXISTS') {
      return T('Email này đã có tài khoản. Hãy chọn Đăng nhập để tiếp tục.', 'This email already has an account. Choose Log in to continue.');
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
      return T('Không thể tạo liên kết xác thực. Vui lòng thử lại sau.', 'We could not create the verification link. Please try again later.');
    }
    if (code === 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED') {
      return T('Dịch vụ email chưa được cấu hình. Vui lòng thử lại sau.', 'The email service is not configured yet. Please try again later.');
    }
    return mode === 'signup'
      ? T('Không thể gửi link đăng ký. Vui lòng thử lại sau.', 'We could not send the sign-up link. Please try again later.')
      : T('Không thể gửi link đăng nhập. Vui lòng thử lại sau.', 'We could not send the sign-in link. Please try again later.');
  }, [T]);
  const loginEmailSubmit = useCallback(async () => {
    if (!emailValid(s.loginEmail)) return;
    const email = s.loginEmail.trim();
    try {
      await requestAuthEmail({ email, mode: s.authMode });
      set({ loginSent: true, loginSentVia: 'email', reserveError: '' });
    } catch (e) {
      set({ loginSent: false, loginSentVia: null, reserveError: authEmailErrorMessage(e, s.authMode) });
    }
  }, [set, s.loginEmail, s.authMode, authEmailErrorMessage]);
  const loginEmailKey = useCallback((e) => { if (e.key === 'Enter') loginEmailSubmit(); }, [loginEmailSubmit]);
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

  // ---- chat ----
  const chatOnType = useCallback((e) => set({ chatDraft: e.target.value }), [set]);
  const chatSend = useCallback(() => {
    set(prev => {
      const t = prev.chatDraft.trim();
      if (!t) return prev;
      const chatKey = prev.eventKey;
      const ev = findEvent(chatKey);
      const thread = prev.chats[chatKey] || [{ who: 'host', text: ev.greeting }];
      return { chatDraft: '', chats: { ...prev.chats, [chatKey]: [...thread, { who: 'me', text: t }] } };
    });
  }, [set]);
  const chatOnKey = useCallback((e) => { if (e.key === 'Enter') chatSend(); }, [chatSend]);
  const chatBackFn = useCallback(() => set(prev => ({ screen: prev.chatBack === 'inbox' ? 'inbox' : 'organizer' })), [set]);
  const openChatFor = useCallback((key, back) => set({ screen: 'chat', eventKey: key, chatBack: back || 'organizer' }), [set]);

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
  const toggleCheckin = useCallback(async (eventKey, guestId, checked) => {
    set(prev => ({ checkins: { ...prev.checkins, [eventKey]: { ...(prev.checkins[eventKey] || {}), [guestId]: !checked } } }));
    try {
      if (!checked) {
        // If guestId is a valid UUID or reservation id, execute atomic check-in
        await supabase.rpc('check_in_guest', { p_reservation_id: guestId }).catch(() => {});
      }
    } catch (e) {
      console.log('Check-in RPC sync:', e);
    }
  }, [set]);

  const value = useMemo(() => ({
    state: s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea,
    isSaved, isGoing, toggleFav, toggleFollow,
    goHome, goProfile, goInbox, goEvent, backFromEvent, goOrganizer, goReserve, backToEvent, backToOrganizer,
    goChat, goLogin, goDashboard, goCreate, openAttendance, openHeld, goHostIntro, createBack,
    switchToHost, switchToGoer, becomeHost, logout, dismissSplash,
    canHost, toggleOrganizerMode, enableOrganizerMode,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, toggleTheme, pickTheme, openPreferences,
    pickFilter, clearFilters, shareEvent,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, formEmailType, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    addToCalendar, giveTicket,
    loginEmailType, loginEmailSubmit, loginEmailKey, loginPhoneType, loginCodeType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginInstagram, emailValid,
    chatOnType, chatSend, chatOnKey, chatBackFn, openChatFor,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, requestVerify,
    toggleCheckin,
  }), [
    s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea,
    isSaved, isGoing, toggleFav, toggleFollow,
    goHome, goProfile, goInbox, goEvent, backFromEvent, goOrganizer, goReserve, backToEvent, backToOrganizer,
    goChat, goLogin, goDashboard, goCreate, openAttendance, openHeld, goHostIntro, createBack,
    switchToHost, switchToGoer, becomeHost, logout, dismissSplash,
    canHost, toggleOrganizerMode, enableOrganizerMode,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, toggleTheme, pickTheme, openPreferences,
    pickFilter, clearFilters, shareEvent,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, formEmailType, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    addToCalendar, giveTicket,
    loginEmailType, loginEmailSubmit, loginEmailKey, loginPhoneType, loginCodeType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginInstagram,
    chatOnType, chatSend, chatOnKey, chatBackFn, openChatFor,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, requestVerify,
    toggleCheckin,
  ]);

  return <GocCtx.Provider value={value}>{children}</GocCtx.Provider>;
}

export function useGoc() {
  const ctx = useContext(GocCtx);
  if (!ctx) throw new Error('useGoc must be used within GocProvider');
  return ctx;
}

export { EVENTS, findEvent };
