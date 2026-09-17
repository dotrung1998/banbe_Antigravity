import { createContext, useContext, useEffect, useMemo, useState, useCallback, useRef } from 'react';
import { EVENTS, findEvent, haversineKm } from '../data/events.js';
import { supabase, getAuthRedirectUrl } from '../lib/supabase.js';
import { requestAuthEmail, requestPasswordSignup, requestPasswordReset } from '../lib/authEmail.js';
import { renderPaymentDocument } from '../lib/paymentDocument.js';
import { buildVietQrPayload } from '../lib/vietqr.js';
import { msUntil, liveEventOverrides } from '../lib/countdown.js';
import { normalizeProofFile } from '../lib/proofUpload.js';
import { POLICY_VERSION } from '../lib/policy.js';

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

// A shared photo's "?org=<eventKey>" link, read once at module load the same
// way "?ref=" is above. Unlike a referral this isn't stashed for later — it
// routes straight to that organizer's page below, so the param is consumed
// here and stripped from the visible URL.
let sharedOrgEventKey = null;
if (typeof window !== 'undefined') {
  const params = new URLSearchParams(window.location.search);
  const org = params.get('org');
  if (org && EVENTS.some(e => e.key === org)) {
    sharedOrgEventKey = org;
    params.delete('org');
    const rest = params.toString();
    window.history.replaceState({}, '', window.location.pathname + (rest ? `?${rest}` : ''));
  }
}

// Every screen a signed-out visitor may ever legitimately be on. Anything
// else while `!user` gets redirected to 'login' by the guard effect below
// — the enforcement point for "no guest browsing of any screen" (Task 1).
const GUEST_ALLOWED_SCREENS = new Set(['splash', 'langPick', 'themePick', 'login', 'resetPassword', 'policy']);

const initialState = {
  screen: 'splash',
  // Whether the checkbox on Login.jsx has been ticked this session — reset
  // whenever Login mounts fresh; gates submitCurrentForm alongside the
  // existing email/password validity checks.
  policyConsent: false,
  // True only for a brand-new OAuth profile with no policy_accepted_at yet
  // (syncUser()) — Policy.jsx renders as a mandatory, no-back-out gate
  // instead of the ordinary "view the policy" screen while this is set.
  policyGateActive: false,
  // Task 4 (migration 056): one-time, account-level opt-in — mirrors
  // profiles.auto_email_documents, loaded in syncUser() like locale/theme.
  autoEmailDocuments: false,
  // True only when Login was reached by force (the mandatory post-splash/
  // post-onboarding gate, or the guard effect catching an unauthenticated
  // screen change) rather than a deliberate "sign in to do X" prompt that
  // already has a real screen to fall back to — hides the Back link, since
  // there's nowhere legitimate for it to go.
  authMandatory: false,
  // Set once by the auth bootstrap effect's first resolution (real session
  // present or genuinely absent) — the guard effect waits for this so a
  // slow session check can't get misread as "signed out" and bounce a
  // returning user to Login before their restored session even arrives.
  sessionChecked: false,
  // Whether this browser has already been through language/theme
  // onboarding once (i.e. localStorage had a saved preferences record) —
  // read by the splash timer to decide whether to route into 'langPick'
  // or straight to 'home'/'login'. Overridden at init from that check.
  hasOnboarded: false,
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
  // Home's second, independent chip row (12-home-filters.md) — multi-select,
  // AND-combined with `filter`/`area` above, not folded into either.
  filterAttending: false,
  filterSaved: false,
  filterSoldOut: false,
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
  myOrganizerIds: [],

  // ---- payments & documents (supabase migration 024) ----
  // banbe still never touches the money. These carry the details a guest
  // needs to transfer directly to the organizer, and the paperwork both
  // sides keep afterwards.
  paymentBookings: [],
  paymentsLoading: false,
  paymentBookingId: null,
  paymentCopied: '',
  paymentProofUploading: false,
  paymentProofError: '',
  paymentBack: 'profile',
  billingName: '', billingAddress: '', billingPhone: '', billingTaxCode: '',
  billingSaving: false, billingSaved: false, billingError: '',
  payoutBankName: '', payoutAccountName: '', payoutAccountNo: '', payoutMomo: '',
  payoutNote: '', payoutAddress: '', payoutTaxCode: '',
  payoutSaving: false, payoutSaved: false, payoutError: '',
  documents: [],
  documentsLoading: false,
  documentsError: '',
  // Which of the two Account rows opened the list, and from which side.
  documentsKind: 'invoice',
  documentsRole: 'guest',
  documentId: null,
  // Bug 2 (15-organizer-checkin.md follow-up): which screen opened the
  // viewer — 'documents' (the Receipts/Invoices list, the old fixed
  // behavior) or 'confirmed' (the ticket screen's own "Xem Receipt").
  // backFromDocument() reads this instead of a single hardcoded target.
  documentBack: 'documents',
  // Signed URL for the current document's uploaded file (migration 056) —
  // '' while loading/absent (a legacy, pre-upload document has no
  // file_path at all and falls back to the old rendered-HTML viewer).
  documentFileUrl: '',
  documentUploadError: '',
  documentUploading: false,
  // How many buyers are currently holding a seat on this account's own
  // events, and how soon the nearest one lapses — the organizer half of the
  // Home countdown banners. null until loadOrganizerHoldingSummary() runs.
  organizerHoldingSummary: null,

  // ---- two-phase payment state machine (migrations 026/027) ----
  // PHASE 1 'holding' runs a countdown; PHASE 2 'pending_verification' has
  // no countdown at all — the seat is frozen until someone verifies it.
  paymentTxnId: '',
  paymentProofFile: null,
  paymentSubmitting: false,
  paymentSubmitError: '',
  // 14-organizer-checkin.md: the guest's rate-limited nudge while awaiting
  // the organizer's confirm window.
  nudgeSending: false,
  nudgeError: '',
  // 15-organizer-checkin.md follow-up: the guest's "Xem Receipt" button on
  // Confirmed.jsx — null while unchecked, a payment_documents row once one
  // is found, or `false` once checked and confirmed to not exist yet.
  receiptDoc: undefined,
  receiptRequestSending: false,
  receiptRequestError: '',
  receiptRequestSent: false,
  // The organizer's verification queue, and the admin dispute desk.
  verifications: [],
  verificationsLoading: false,
  verificationBusy: '',
  // 14-organizer-checkin.md: set by openVerificationDetail() (Attendance's
  // "Check payment" button) — narrows the queue below to exactly one
  // booking instead of the full list, whether it's the only pending item
  // or buried far down in it.
  verificationsFocusBookingId: null,
  disputes: [],
  disputesLoading: false,
  disputeBusy: '',
  disputeEmailError: '',
  // The temporary dispute chat — one per escalated booking, purged after
  // resolve_dispute() closes it out. Keyed separately from the ordinary
  // chat (state.chatMessages) since it's a different table entirely.
  disputeChatBookingId: null,
  disputeChatMessages: [],
  disputeChatLoading: false,
  disputeChatDraft: '',
  disputeChatError: '',
  // resolved_at/purge_after off the dispute_threads row itself — read-only,
  // drives the retention countdown label (DisputeChatPanel.jsx) instead of
  // a delete button, since dispute_messages must survive until the 72h
  // purge (05-notify-retention.md). null for an open/unresolved thread.
  disputeChatThread: null,
  auditTrail: [],
  auditBookingId: null,
  // pay-proof storage path -> signed viewable URL, for whichever rows
  // Verifications/Disputes last loaded — see signProofUrls.
  proofUrls: {},
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
  // Ephemeral in-app toasts, surfaced proactively (see the polling effect
  // near loadNotifications) — separate from `notifications` itself, which
  // stays the permanent, pull-based inbox (Notifications.jsx). Each entry:
  // { id, notification, leaving }. `leaving` drives the exit animation
  // before pushToast's own timeout actually removes it from this array.
  toasts: [],
  // Set by openNotification() for a 'dispute_message' notification —
  // DisputeChatPanel.jsx reads this itself (rather than every parent
  // screen threading a prop through) to scroll to and briefly highlight
  // `messageId`, or just scroll to the bottom if it's null (an older
  // notification row from before migration 050 added message_id). Cleared
  // once DisputeChatPanel has actually applied it.
  chatHighlight: null,
  // Set by openNotification()'s 'receipt_requested' branch — the same
  // scroll-to-and-highlight idea as chatHighlight above, but for
  // Attendance.jsx's per-guest "Upload receipt" control instead of a chat
  // message. Cleared once Attendance.jsx has applied it.
  attendanceHighlightBookingId: null,
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
  // Account > Security: setting this account's own password while already
  // signed in (the Login screen's fields are a separate, signed-out flow).
  securityPassword: '',
  securityPasswordConfirm: '',
  securityBusy: false,
  securityError: '',
  securitySaved: false,
  securityResetSent: false,
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
  // { url, organizer, eventKey } while a gallery photo is open in the viewer.
  photoViewer: null,
  // Snapshot of MapExplore.jsx's own local state (camera center/zoom, sheet
  // detent, filters, selected event, list scroll position), saved right
  // before navigating to Event Detail from the in-map preview card's CTA so
  // MapExplore can restore it instead of re-initializing from scratch on
  // return — App.jsx's Shell unmounts/remounts the whole screen component
  // on every `screen` change, so this has to live up here to survive that.
  // Explicitly cleared (not just left stale) on an intentional exit via the
  // "← Đóng" button, so reopening the map from Home later starts fresh.
  mapExploreState: null,
  // Liked photo URLs. Local-only: there's no table to hang a photo like on,
  // and inventing one would mean a migration that isn't live yet.
  photoLikes: [],
  photoShared: false,
  // True when this visit arrived on a shared "?org=" link, which is the only
  // time the organizer page offers to open the native app instead.
  arrivedFromSharedLink: false,
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
  // The real events row's own status/starts_at for whichever event is
  // currently open — null until fetched, or once no matching row exists
  // (a purely local/preview event). Kept separate from the static demo
  // catalogue (data/events.js) rather than merged into it, so curEvent can
  // layer a live ended/cancelled read on top without ever inventing cosmetic
  // fields (photos, description, …) the row doesn't have.
  liveEvent: null,
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
// 14-organizer-checkin.md (Bug 2b): "Có nhận khách này không?" ▪︎ "Từ chối".
export const REJECT_GUEST_REASONS = [
  { key: 'no_seats_left', vi: 'Hết chỗ thật sự', en: 'Actually out of seats' },
  { key: 'payment_mismatch', vi: 'Không khớp với sao kê', en: "Doesn't match the statement" },
  { key: 'suspected_fraud', vi: 'Nghi ngờ gian lận', en: 'Suspected fraud' },
  { key: 'other', vi: 'Khác', en: 'Other' },
];

// Shared by the splash timer and finishOnboarding() (Task 1 — no guest
// browsing of any screen): decides where to land once onboarding/splash is
// done — 'home' (or the shared-org-link target) if actually signed in,
// otherwise the mandatory Login gate. authReturnScreen preserves the
// intended destination so signing in lands there instead of always Home;
// authMandatory hides Login's own Back link, since there's nowhere
// legitimate to go back to from a forced gate like this one.
function postAuthDestination(prev) {
  const target = prev.arrivedFromSharedLink ? 'organizer' : 'home';
  // !prev.sessionChecked means the async getSession()/profile fetch hasn't
  // resolved yet — prev.user being null here doesn't mean signed-out, just
  // "not confirmed yet" (e.g. a fast click through langPick/themePick can
  // race ahead of that network round trip even for an already-authenticated
  // account). Only the blanket guard effect gets to call someone
  // signed-out, and only once sessionChecked is actually true — this just
  // goes to `target` optimistically in the meantime and lets that guard
  // correct course (bounce to Login) the moment it knows for sure.
  if (prev.user || !prev.sessionChecked) return { screen: target };
  return {
    screen: 'login', authMode: 'login', authMandatory: true,
    authReturnScreen: target, authBackScreen: target,
  };
}

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
        // onboarding (language/theme) before — that part is skipped on a
        // revisit, but the splash itself always shows now (Task 2) and
        // `screen` always starts 'splash' regardless (initialState's
        // default) — `hasOnboarded` is just what the splash timer below
        // reads to decide whether to route into 'langPick' or straight to
        // 'home'/'login'.
        hasOnboarded: raw !== null,
        // A shared "?org=" link is an explicit deep link someone tapped to
        // see one specific organizer right away — sitting it through the
        // splash/onboarding sequence first would defeat the point of a
        // fast-opening share preview, so this bypasses both entirely and
        // opens straight on Organizer (same as before Task 2's splash
        // change). The blanket guard still applies from here if it turns
        // out there's no session once that resolves.
        ...(sharedOrgEventKey ? { eventKey: sharedOrgEventKey, arrivedFromSharedLink: true, screen: 'organizer' } : {}),
      };
    } catch {
      return initialState;
    }
  });
  const s = state;
  const prefsRef = useRef({ lang: state.lang, theme: state.theme });

  // Liked photos live on this device only — see the note on photoLikes.
  useEffect(() => {
    try {
      const saved = JSON.parse(localStorage.getItem('banbe.photoLikes') || '[]');
      if (Array.isArray(saved) && saved.length) setStateRaw(prev => ({ ...prev, photoLikes: saved }));
    } catch { /* private browsing, or nothing saved yet */ }
  }, []);
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
      setStateRaw(prev => (
        // Gated on ANY holding booking, not just the single one the
        // currently-open screen happens to be looking at — a hold made on
        // event A must still tick (and get forfeited) while sitting on
        // event B's EventDetail, where prev.booking is B's, not A's.
        (prev.holdDeadline || prev.booking?.payment_state === 'holding'
          || (prev.paymentBookings || []).some(b => b.payment_state === 'holding'))
          ? { ...prev, now: Date.now() } : prev
      ));
    }, 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let active = true;
    const syncUser = async (user) => {
      if (!active) return;
      if (!user) {
        set({ user: null, referralCode: null, sessionChecked: true });
        return;
      }
      const { data: profile } = await supabase
        .from('profiles')
        .select('role, locale, theme, prefs_saved, display_name, referral_code, policy_accepted_at, policy_version, auto_email_documents')
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
        referralCode: profile?.referral_code || null, sessionChecked: true,
        autoEmailDocuments: profile?.auto_email_documents === true,
      });

      // Proof-of-consent bookkeeping (Task 1, migration 055,
      // banbe_User_Policy.md B1/B3). For an 'email'-provider session
      // (password/emailed-code, or a legacy row predating this column
      // entirely), the ONLY way to ever reach one at all is through
      // Login.jsx's mandatory, unticked-by-default consent checkbox
      // (submitCurrentForm is disabled until it's checked) — so any such
      // profile with no recorded consent yet just passed through that
      // gate, and can be stamped unconditionally.
      //
      // An OAuth session (note 10 — Google/Facebook) is different: nothing
      // client-side ran a submit function first, so a brand-new profile
      // here genuinely has never seen the policy. This used to try to gate
      // the OAuth *button* itself on a localStorage-stashed "was it ticked
      // before the redirect" flag — that was fragile (storage partitioning,
      // a cleared/blocked store, or simply losing the value across the
      // full-page round trip could all silently sign a real user back out
      // for no reason they could see) and, worse, required showing the
      // checkbox on the Login tab too just so it had somewhere to render,
      // regressing note 09's Signup-only fix. Fixed: consent for a new
      // OAuth profile is handled entirely AFTER the redirect, right here —
      // route to a mandatory one-time Policy screen (acceptPolicyGate()
      // stamps consent and continues) instead of trying to verify intent
      // before the fact. A *returning* OAuth sign-in never reaches this
      // block at all (its profile already has policy_accepted_at), so it's
      // exactly as frictionless as password login.
      if (profile && !profile.policy_accepted_at) {
        const provider = user.app_metadata?.provider;
        if (!provider || provider === 'email') {
          const { error } = await supabase
            .from('profiles')
            .update({ policy_accepted_at: new Date().toISOString(), policy_version: POLICY_VERSION })
            .eq('id', user.id);
          if (error) console.warn('Failed to record policy consent:', error);
        } else {
          set({ policyGateActive: true, screen: 'policy' });
          return;
        }
      }

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
      if (active && !session) set({ user: null, sessionChecked: true });
    });
    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, [set]);

  // Task 1 — no guest browsing of any screen: the single, centralized
  // enforcement point, rather than auditing every one of this file's many
  // `set({ screen: ... })` call sites individually. Catches cases the
  // targeted fixes (finishOnboarding, the splash timer, logout) don't —
  // e.g. goHome()'s plain `set({ screen: 'home' })`, callable from
  // anywhere, previously had no auth check at all. Waits for
  // `sessionChecked` so a slow-resolving session restore can't get
  // misread as "signed out" and bounce a returning user before their
  // session even arrives — the splash screen's own ~2.6s already covers
  // this in the common case, but this effect can fire independently of
  // splash (e.g. a stray screen change right as sessionChecked settles).
  useEffect(() => {
    if (s.sessionChecked && !s.user && !GUEST_ALLOWED_SCREENS.has(s.screen)) {
      set({
        screen: 'login', authMode: 'login', authMandatory: true,
        authReturnScreen: s.screen, authBackScreen: s.screen,
      });
    }
  }, [s.sessionChecked, s.user, s.screen, set]);

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

  // The real events row's own status/starts_at for whichever event is
  // currently open — unlike the booking fetch above, this runs for every
  // visitor (signed in or not), since "has this event ended/been cancelled"
  // is public information, not something tied to an account. Every one of
  // the 20 demo events also has a real row (seeded to match the frontend's
  // static STATUS overrides), so this resolves for those too — it's only a
  // pure client-side preview (e.g. the create-event flow) that has no row
  // and falls back to the static catalogue untouched.
  useEffect(() => {
    let active = true;
    (async () => {
      const { data } = await supabase.from('events')
        .select('status, starts_at, cancelled_at, cancel_reason')
        .eq('slug', s.eventKey).maybeSingle();
      if (active) set({ liveEvent: data || null });
    })();
    return () => { active = false; };
  }, [set, s.eventKey]);

  // A toast auto-dismisses in two steps: `leaving: true` swaps it to the
  // exit animation (gocToastOut, index.css), then a second timeout actually
  // drops it from the array once that animation has had time to finish.
  // Carries the source `notification` row (not just its title/body) so
  // ToastStack.jsx can tap it open — see openNotification/dismissToast.
  const pushToast = useCallback((notification) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    set(prev => ({ toasts: [...prev.toasts, { id, notification, leaving: false }] }));
    setTimeout(() => {
      set(prev => ({ toasts: prev.toasts.map(t => (t.id === id ? { ...t, leaving: true } : t)) }));
    }, 2200);
    setTimeout(() => {
      set(prev => ({ toasts: prev.toasts.filter(t => t.id !== id) }));
    }, 2500);
  }, [set]);

  // Tapping a toast shouldn't sit around for its own auto-dismiss timer —
  // it's already been acted on. Fires the same 'leaving' exit animation
  // immediately rather than yanking it out with no transition at all.
  const dismissToast = useCallback((id) => {
    set(prev => ({ toasts: prev.toasts.map(t => (t.id === id ? { ...t, leaving: true } : t)) }));
    setTimeout(() => {
      set(prev => ({ toasts: prev.toasts.filter(t => t.id !== id) }));
    }, 280);
  }, [set]);

  // Real event assignment for the signed-in account: which of the catalogue
  // events they're attending (from actual bookings) and which they organize
  // (from owning the organizer row events.organizer_id points at). The
  // frontend catalogue (src/data/events.js) still supplies all the cosmetic
  // detail — photos, galleries, descriptions — that the database rows don't
  // duplicate; this only resolves *which* catalogue keys are genuinely
  // "mine", by real id, instead of from placeholder demo state.
  //
  // `attending`/`tickets` REPLACE on every call, they do not merge with
  // whatever was there before — mirrors AppState+Data.swift's loadMyEvents()
  // (`attending = going`, a plain assignment). This used to union new
  // results into the previous array instead, which meant a booking that
  // stopped qualifying (e.g. an admin resolving a dispute as "Mở lại chỗ" /
  // "return to pool", `resolve_dispute()` setting `status='expired'` —
  // outside this filter, supabase/migrations/20260914000047_...sql:80-83)
  // could never leave `attending` for the rest of that session: the guest
  // kept seeing the event under "Going" even after losing the ticket, no
  // matter how many times this ran, because every re-run only ever added to
  // the set, never removed a stale key the fresh query no longer returned.
  //
  // Defined here (above the toast poll below, which now also calls it on a
  // fresh 'booking_declined' notification) rather than further down where
  // it originally sat — a const referenced inside an effect defined above
  // its own declaration is a temporal-dead-zone ReferenceError in JS, not
  // just a lint nit, since the effect's dependency array evaluates
  // `loadMyEvents` on every render, not only when the effect itself runs.
  const loadMyEvents = useCallback(async (uid) => {
    if (!uid) return;
    const [{ data: bookings }, { data: organizers }] = await Promise.all([
      supabase
        .from('bookings')
        .select('event_id, qty, status')
        .eq('user_id', uid)
        .in('status', ['pending', 'confirmed', 'attended']),
      supabase
        .from('organizers')
        .select('id')
        .or(`owner_id.eq.${uid},user_id.eq.${uid}`),
    ]);

    const attending = [...new Set((bookings || []).map(b => b.event_id))];
    const tickets = Object.fromEntries((bookings || []).map(b => [b.event_id, b.qty]));
    set({ attending, tickets });

    const organizerIds = (organizers || []).map(o => o.id);
    set({ myOrganizerIds: organizerIds });
    if (organizerIds.length) {
      const { data: events } = await supabase.from('events').select('id').in('organizer_id', organizerIds);
      set({ myOrgEventKeys: (events || []).map(e => e.id) });
    } else {
      set({ myOrgEventKeys: [] });
    }
  }, [set]);

  // Unread count for the notification bell, refreshed on login AND on a
  // 5s poll thereafter (matching this app's existing poll conventions —
  // DisputeChatPanel's 4s, PaymentDetails' 6s — since there is no realtime
  // subscription anywhere in this codebase; see 03-dispute-chat.md). The
  // poll is also what makes every event type that already writes a
  // `notifications` row (booking confirmed, dispute resolved, a dispute
  // chat message, etc. — see 07-notifications.md) actually surface as a
  // toast while the app is open, instead of sitting invisible until
  // someone happens to open the bell screen.
  useEffect(() => {
    if (!s.user?.id) { set({ notifications: [], unreadNotifications: 0, toasts: [] }); return; }
    let active = true;
    // Captured synchronously, before the first fetch even goes out — a
    // notification created while that first request is still in flight
    // still has to toast, since the person genuinely hasn't seen it yet.
    // Diffing against "whatever the previous poll happened to return"
    // instead (this used to) has exactly that race: a row landing in the
    // gap between mount and the first response arriving would already be
    // present on that very first poll and so get silently marked "already
    // seen," never toasting at all. Comparing each row's own `created_at`
    // against a fixed point captured before any request starts has no such
    // gap. `toastedIds` then guards against toasting the same row twice
    // across polls once it has been shown.
    const sessionStart = new Date();
    const toastedIds = new Set();
    const poll = async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('recipient_id', s.user.id)
        .order('created_at', { ascending: false })
        .limit(50);
      if (!active || error) return;
      const rows = data || [];
      let attendingStale = false;
      // reject_pending_guest() ('booking_declined') and cancel_booking()
      // ('booking_cancelled') are two separate RPCs — different code,
      // different notification kind — but both mean the exact same thing
      // from this poll's point of view: a booking that may already be
      // sitting in s.attending/s.tickets (the "Going" tag) or in s.booking
      // (EventDetail's own "View Ticket" vs "Reserve" bar) just stopped
      // being real. Treated as one shared category here rather than
      // hardcoding just the one kind each fix happened to be written for.
      const CANCELLATION_KINDS = new Set(['booking_declined', 'booking_cancelled']);
      for (const n of rows) {
        if (!toastedIds.has(n.id) && new Date(n.created_at) > sessionStart) {
          toastedIds.add(n.id);
          pushToast(n);
          // Nothing else refreshes s.attending/s.tickets outside of
          // loadMyEvents()'s own sign-in-mount effect or goGoingList()
          // opening the Going tab (80423dd) — a guest whose booking just
          // got declined/cancelled while already looking at Home would
          // keep seeing "Going" indefinitely otherwise. This poll already
          // runs every 5s regardless of whether the toast is tapped, so
          // it's the one place that can catch this without a real
          // realtime subscription (none exist anywhere in this codebase,
          // see 03-dispute-chat.md).
          if (CANCELLATION_KINDS.has(n.kind)) {
            attendingStale = true;
            // EventDetail.jsx's own "Xem vé của bạn"/"View your ticket" bar
            // reads straight off the single top-level s.booking object
            // (whichever booking was last loaded into it), not off
            // paymentBookings/a fresh per-event query — it has no poll or
            // mount effect of its own. If that's the exact booking that
            // just got declined/cancelled, patch it in place so the bar
            // flips to "Reserve" on the very next render.
            if (n.data?.booking_id) {
              set(prev => (prev.booking?.id === n.data.booking_id
                ? { booking: { ...prev.booking, status: 'cancelled' } }
                : {}));
            }
          }
        }
      }
      set({ notifications: rows, unreadNotifications: rows.filter(n => !n.read_at).length });
      if (attendingStale) loadMyEvents(s.user.id);
    };
    poll();
    const interval = setInterval(poll, 5000);
    return () => { active = false; clearInterval(interval); };
  }, [set, s.user?.id, pushToast, loadMyEvents]);

  useEffect(() => {
    if (!s.user?.id) return;
    let active = true;
    (async () => { if (active) await loadMyEvents(s.user.id); })();
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.user?.id]);

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
      setStateRaw(prev => {
        if (prev.screen !== 'splash') return prev;
        // First-ever visit still goes through language/theme regardless of
        // auth — the mandatory-login gate applies once that's done
        // (finishOnboarding), not before.
        if (!prev.hasOnboarded) return { ...prev, screen: 'langPick' };
        return { ...prev, ...postAuthDestination(prev) };
      });
    }, 2600);
    return () => clearTimeout(splashTimer.current);
  }, []);
  const dismissSplash = useCallback(() => {
    clearTimeout(splashTimer.current);
    set(prev => {
      if (prev.screen !== 'splash') return {};
      if (!prev.hasOnboarded) return { screen: 'langPick' };
      return postAuthDestination(prev);
    });
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
  // Task 1: no guest browsing of any screen — lands on the mandatory Login
  // gate instead of Home when not actually signed in, preserving where the
  // shared-org-link case wanted to go (postAuthDestination).
  const finishOnboarding = useCallback(() => set(prev => postAuthDestination(prev)), [set]);

  const EN = s.lang === 'en';
  const T = useCallback((vi, en) => (EN ? en : vi), [EN]);
  const toggleTheme = useCallback(() => {
    const next = s.theme === 'dark' ? 'light' : 'dark';
    set({ theme: next });
    persistAccountPreference({ theme: next });
  }, [set, s.theme, persistAccountPreference]);
  const pickTheme = useCallback((theme) => { set({ theme }); persistAccountPreference({ theme }); }, [set, persistAccountPreference]);

  // Task 1's consent checkbox (Login.jsx) — unticked by default, gates
  // submitCurrentForm alongside the existing email/password validity
  // checks. Recorded server-side in syncUser() once a session exists,
  // never here (this is only ever the transient, pre-session UI state).
  const togglePolicyConsent = useCallback(() => set(prev => ({ policyConsent: !prev.policyConsent })), [set]);
  const openPolicy = useCallback(() => set(prev => ({ screen: 'policy', policyBackScreen: prev.screen })), [set]);
  const backFromPolicy = useCallback(() => set(prev => ({ screen: prev.policyBackScreen || 'login' })), [set]);

  // The "I agree" button Policy.jsx shows only while policyGateActive
  // (syncUser()'s post-OAuth-redirect consent gate for a brand-new
  // Google/Facebook profile — see note 10). Stamps consent for real, then
  // hands off to the exact same postAuthDestination() every other sign-in
  // path uses, so this doesn't need its own bespoke "where do I go now".
  const acceptPolicyGate = useCallback(async () => {
    if (!s.user?.id) return;
    const { error } = await supabase
      .from('profiles')
      .update({ policy_accepted_at: new Date().toISOString(), policy_version: POLICY_VERSION })
      .eq('id', s.user.id);
    if (error) { console.warn('Failed to record policy consent:', error); return; }
    set(prev => ({ policyGateActive: false, ...postAuthDestination(prev) }));
  }, [set, s.user?.id]);
  // Tapping a photo in either gallery ("Hình ảnh" on an event, "Ảnh của X"
  // on an organizer page) opens it larger, over a dimmed backdrop, with the
  // whole gallery loaded in behind it so left/right swipes can move through
  // the rest without closing and reopening the viewer.
  // navigator.vibrate is the web's only haptic and iOS Safari doesn't
  // implement it, so this is a no-op there — the native app does it
  // properly (see AppState.openPhoto).
  // originRect: the tapped thumbnail's getBoundingClientRect() at click
  // time — where PhotoViewer's dismiss animation shrinks back to (see
  // 14-photo-viewer.md). Copied into a plain object immediately; a live
  // DOMRect is a view onto layout that can change/go stale, and this one
  // only ever needs to be read back later, never re-measured.
  const openPhoto = useCallback((gallery, index, organizer, eventKey, originRect) => {
    try { navigator.vibrate?.(8); } catch { /* unsupported — no haptic, no harm */ }
    const rect = originRect
      ? { top: originRect.top, left: originRect.left, width: originRect.width, height: originRect.height }
      : null;
    set({ photoViewer: { gallery, index, organizer, eventKey, originRect: rect } });
  }, [set]);
  const closePhoto = useCallback(() => set({ photoViewer: null }), [set]);
  const showPhotoAt = useCallback((index) => set(prev => {
    if (!prev.photoViewer) return {};
    const clamped = Math.max(0, Math.min(index, prev.photoViewer.gallery.length - 1));
    return { photoViewer: { ...prev.photoViewer, index: clamped } };
  }), [set]);

  const isPhotoLiked = useCallback((url) => s.photoLikes.includes(url), [s.photoLikes]);
  const togglePhotoLike = useCallback((url) => set(prev => {
    const photoLikes = prev.photoLikes.includes(url)
      ? prev.photoLikes.filter(x => x !== url)
      : [...prev.photoLikes, url];
    try { localStorage.setItem('banbe.photoLikes', JSON.stringify(photoLikes)); } catch { /* private browsing */ }
    return { photoLikes };
  }), [set]);

  // Shares the photo's organizer, not the photo file itself — a bare image
  // URL says nothing about who took it or where to find more. The link
  // carries "?org=<eventKey>", which lands on that organizer's page (see
  // the capture at the top of this file); the native app registers a
  // banbe:// scheme for the same destination, offered from that page.
  const sharePhotoOrganizer = useCallback(async () => {
    if (!s.photoViewer) return;
    const { organizer, eventKey, gallery, index } = s.photoViewer;
    // /api/photo-share carries Open Graph tags naming this photo as the
    // preview image and then forwards into the app. Sharing the plain
    // "/?org=" link instead left WhatsApp and friends scraping index.html,
    // which has no OG tags, so every shared photo previewed as the site
    // favicon — a black square with the banbe mark.
    const photoFile = (gallery[index] || '').split('/').pop();
    const url = `https://banbe-two.vercel.app/api/photo-share?org=${encodeURIComponent(eventKey)}`
      + `&photo=${encodeURIComponent(photoFile)}&by=${encodeURIComponent(organizer)}`;
    const title = T(`Ảnh của ${organizer} trên banbe`, `${organizer} on banbe`);
    const text = T(
      `Xem ảnh và các buổi sắp tới của ${organizer} trên banbe:`,
      `See ${organizer}'s photos and what they have coming up on banbe:`
    );
    const done = () => {
      set({ photoShared: true });
      setTimeout(() => set({ photoShared: false }), 1800);
    };
    // Deliberately a link share rather than a file attachment. Attaching
    // the photo put the picture in the message but cost the caption (share
    // targets take the attachment and drop the text), and on desktop the
    // browser handed the file over as a path that targets pasted as
    // literal text. The link carries the photo as its own preview image
    // instead, so both the picture and the caption survive.
    if (navigator.share) {
      try { await navigator.share({ title, text, url }); } catch { /* cancelled */ }
      done();
    } else if (navigator.clipboard) {
      navigator.clipboard.writeText(url).then(done, done);
    } else { done(); }
  }, [set, s.photoViewer, T]);

  // ---- payments & documents ----
  // The one rule the whole feature is built around: banbe is not a payment
  // processor and never becomes one here. Money moves directly between the
  // two people. What the app owns is telling the guest where to send it,
  // letting them show they did, letting the organizer confirm it, and
  // giving both sides a document afterwards.

  /** Every booking this account holds, with the organizer's payment details attached. */
  const loadPaymentBookings = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return set({ paymentBookings: [], paymentsLoading: false });
    set({ paymentsLoading: true });
    const { data, error } = await supabase
      .from('bookings')
      .select(`id, qty, total_vnd, code, status, expires_at, paid_marked_at, paid_method,
               proof_path, proof_uploaded_at, created_at, event_id,
               payment_state, payment_ref, hold_expires_at, transaction_id, verify_due_at, dispute_reason, cancel_reason, nudge_count,
               events(id, key, name, event_date, event_time, area, organizer_id,
                      organizers(id, name, pay_methods, bank_name, bank_account_name,
                                 bank_account_no, momo_phone, pay_note, pay_qr_path))`)
      .eq('user_id', uid)
      .order('created_at', { ascending: false });
    if (error) {
      console.warn('loadPaymentBookings failed:', error);
      return set({ paymentsLoading: false, paymentBookings: [] });
    }
    set({ paymentsLoading: false, paymentBookings: data || [] });
  }, [set, s.user?.id]);

  const openPaymentDetails = useCallback((bookingId, back = 'profile') => {
    set({ screen: 'paymentDetails', paymentBookingId: bookingId, paymentBack: back, paymentProofError: '' });
  }, [set]);
  // A rejected/cancelled booking is over — going back to whatever screen
  // sent the guest here (often the ticket/profile screen, which can itself
  // still be mid-transition off a now-dead timer UI) is exactly the
  // "lingering countdown before actually leaving" this was fixed for.
  // Straight to Home instead, every time, for this one terminal state.
  const backFromPaymentDetails = useCallback(() => set(prev => {
    const b = prev.paymentBookings.find(x => x.id === prev.paymentBookingId);
    // Bug 3 (15-organizer-checkin.md follow-up): a confirmed booking is as
    // terminal here as a cancelled one — the "Paid" card's own button (not
    // this back path) is how a guest reaches their ticket now, so leaving
    // via back should land on Home directly too, same reasoning as the
    // cancelled case above.
    const isTerminal = b?.payment_state === 'cancelled' || b?.payment_state === 'confirmed';
    return { screen: isTerminal ? 'home' : (prev.paymentBack || 'profile') };
  }), [set]);
  const backFromBilling = useCallback(() => set({ screen: 'paymentDetails' }), [set]);

  /** Copy-to-clipboard with a short "copied" flash, keyed by field. */
  const copyPayField = useCallback((field, value) => {
    const flash = () => {
      set({ paymentCopied: field });
      setTimeout(() => set(prev => (prev.paymentCopied === field ? { paymentCopied: '' } : {})), 1600);
    };
    if (navigator.clipboard) navigator.clipboard.writeText(String(value)).then(flash, flash);
    else flash();
  }, [set]);

  /**
   * The guest's "I've transferred" evidence. Note what this deliberately
   * does NOT do: mark the booking paid. Only the organizer, who can see
   * their own account, gets to say money arrived.
   */
  const uploadPaymentProof = useCallback(async (bookingId, file) => {
    if (!bookingId || !file) return;
    set({ paymentProofUploading: true, paymentProofError: '' });
    try {
      // Re-encodes anything outside the bucket's allowed image/jpeg,
      // image/png, image/webp, application/pdf (HEIC, GIF, BMP, a renamed
      // file with no MIME type at all, …) to a JPEG it will actually accept
      // — see proofUpload.js for why this beats rejecting those up front.
      const { blob, ext, contentType } = await normalizeProofFile(file);
      // The path's first segment is the booking id — that is exactly what
      // the bucket's RLS policies split on, so a file can only ever land
      // under a booking the uploader owns.
      const path = `${bookingId}/proof-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('pay-proof').upload(path, blob, { upsert: true, contentType });
      if (upErr) throw upErr;
      const { data, error } = await supabase.rpc('mark_payment_proof', { p_booking: bookingId, p_path: path, p_note: '' });
      if (error) throw error;
      if (data && data.success === false) throw new Error(data.error || 'PROOF_FAILED');
      set({ paymentProofUploading: false });
      await loadPaymentBookings();
    } catch (e) {
      console.warn('uploadPaymentProof failed:', e);
      set({
        paymentProofUploading: false,
        paymentProofError: e.message === 'CONVERT_FAILED'
          ? T('Không đọc được ảnh này. Thử một ảnh hoặc file khác.', "Couldn't read that file. Try a different photo or file.")
          : T('Không gửi được ảnh xác nhận. Thử lại nhé.', "Couldn't send that confirmation. Please try again."),
      });
    }
  }, [set, T, loadPaymentBookings]);

  /**
   * PHASE 1 -> PHASE 2. Uploads the proof, then calls submit_payment_proof,
   * which is what actually freezes the countdown server-side. The client
   * never decides this: a frozen timer that only exists in React state would
   * unfreeze on reload and the seat would be swept.
   */
  const submitPaymentProof = useCallback(async (bookingId, file, transactionId) => {
    const txn = String(transactionId || '').trim();
    if (!bookingId || !file || !txn) {
      return set({ paymentSubmitError: T('Cần cả mã giao dịch và ảnh biên lai.',
                                         'Both a transaction ID and a receipt image are required.') });
    }
    set({ paymentSubmitting: true, paymentSubmitError: '' });
    try {
      // Re-encodes anything outside the bucket's allowed image/jpeg,
      // image/png, image/webp, application/pdf (HEIC, GIF, BMP, a renamed
      // file with no MIME type at all, …) to a JPEG it will actually accept
      // — see proofUpload.js for why this beats rejecting those up front.
      // This is exactly what made an arbitrary test image fail to upload:
      // the bucket's storage RLS/allowlist silently rejected it, which
      // surfaced here only as the generic "Couldn't submit" fallback below.
      const { blob, ext, contentType } = await normalizeProofFile(file);
      const path = `${bookingId}/proof-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('pay-proof').upload(path, blob, { upsert: true, contentType });
      if (upErr) throw upErr;

      // The organizer's PHASE 2 response window — 60 minutes, not the
      // buyer's own PHASE 1 hold (30 minutes, hold_seats()'s hold_minutes).
      // These are two independent clocks on two different people; picking
      // the wrong one here silently gave the organizer a 15-minute window
      // instead of the intended 60.
      const { data, error } = await supabase.rpc('submit_payment_proof', {
        p_booking: bookingId, p_transaction_id: txn, p_proof_path: path,
        p_ip: null, p_user_agent: navigator.userAgent, p_sla_minutes: 60,
      });
      if (error) throw error;
      if (data?.success === false) {
        const message = {
          HOLD_EXPIRED_AND_SOLD_OUT: T('Rất tiếc, chỗ đã hết trong lúc chờ thanh toán. Hãy liên hệ người tổ chức để được hoàn tiền.',
                                       'Sorry — the seat sold out while this was pending. Contact the organizer for a refund.'),
          TRANSACTION_ID_REQUIRED: T('Cần mã giao dịch.', 'A transaction ID is required.'),
          PROOF_REQUIRED: T('Cần ảnh biên lai.', 'A receipt image is required.'),
        }[data.error] || T('Chưa gửi được. Thử lại nhé.', "Couldn't submit. Please try again.");
        throw new Error(message);
      }
      set({ paymentSubmitting: false, paymentTxnId: '' });
      // Patch `paymentBookings` in place FIRST, before the refetch below —
      // PaymentDetails derives `booking` straight from this array on every
      // render, so an immediate patch means the very next render (including
      // one after navigating away and straight back in, which remounts
      // PaymentDetails and fires its own loadPaymentBookings() again) can
      // never race an in-flight fetch and land on stale 'holding' data; it
      // already has the right phase before any network round trip returns.
      set(prev => ({
        paymentBookings: prev.paymentBookings.map(b => (b.id === bookingId
          ? { ...b, payment_state: 'pending_verification', transaction_id: txn, proof_path: path, verify_due_at: data?.verify_due_at || null }
          : b)),
      }));
      await loadPaymentBookings();
      // The ticket screen (Confirmed) keeps its own copy of this booking in
      // top-level state, set whenever it was reserved or last reopened — not
      // refreshed by loadPaymentBookings() above. Without this, submitting
      // proof here left that screen showing a PHASE 1 countdown for a
      // booking that had just been frozen into PHASE 2 until something else
      // happened to reload it.
      set(prev => (prev.booking?.id === bookingId
        ? { booking: { ...prev.booking, payment_state: 'pending_verification', transaction_id: txn, verify_due_at: data?.verify_due_at || null } }
        : {}));
      return data;
    } catch (e) {
      console.warn('submitPaymentProof failed:', e);
      const message = e.message === 'CONVERT_FAILED'
        ? T('Không đọc được ảnh này. Thử một ảnh hoặc file khác.', "Couldn't read that file. Try a different photo or file.")
        : e.message || T('Chưa gửi được. Thử lại nhé.', "Couldn't submit. Please try again.");
      set({ paymentSubmitting: false, paymentSubmitError: message });
    }
  }, [set, T, loadPaymentBookings]);

  const paymentTxnType = useCallback((e) => set({ paymentTxnId: e.target.value, paymentSubmitError: '' }), [set]);

  /**
   * 14-organizer-checkin.md (Bug 1 follow-up): the guest's ONE actionable
   * control while awaiting the organizer's confirm window — nudges the
   * organizer via the same in-app toast + bell notification every other
   * event in this lifecycle already uses (this app has no real push infra,
   * see 07-notifications.md). Rate-limited server-side to 2 uses per hold
   * (nudge_organizer() RPC, migration 059) — the button disables itself
   * once `nudge_count` reaches that, not just a client-side debounce that
   * would reset on reload.
   */
  const nudgeOrganizer = useCallback(async (bookingId) => {
    set({ nudgeSending: true, nudgeError: '' });
    const { data, error } = await supabase.rpc('nudge_organizer', { p_booking: bookingId });
    if (error || !data?.success) {
      set({
        nudgeSending: false,
        nudgeError: data?.error === 'NUDGE_LIMIT_REACHED'
          ? T('Bạn đã nhắc tối đa 2 lần cho lượt giữ chỗ này.', "You've already nudged the max 2 times for this hold.")
          : T('Không gửi được lời nhắc. Thử lại nhé.', "Couldn't send the nudge. Please try again."),
      });
      return;
    }
    set(prev => ({
      nudgeSending: false,
      paymentBookings: prev.paymentBookings.map(b => (b.id === bookingId ? { ...b, nudge_count: data.nudge_count } : b)),
    }));
  }, [set, T]);

  // 15-organizer-checkin.md follow-up: Confirmed.jsx's "Xem Receipt" needs
  // to know, per booking, whether a live payment_documents receipt already
  // exists before deciding whether tapping it opens that file or sends a
  // request instead.
  const loadReceiptStatus = useCallback(async (bookingId) => {
    const { data } = await supabase
      .from('payment_documents')
      .select('*')
      .eq('booking_id', bookingId).eq('kind', 'receipt').is('superseded_at', null)
      .maybeSingle();
    set({ receiptDoc: data || false });
  }, [set]);

  const requestReceipt = useCallback(async (bookingId) => {
    set({ receiptRequestSending: true, receiptRequestError: '' });
    const { data, error } = await supabase.rpc('request_receipt', { p_booking: bookingId });
    if (error || !data?.success) {
      set({
        receiptRequestSending: false,
        receiptRequestError: data?.error === 'ALREADY_REQUESTED_RECENTLY'
          ? T('Bạn vừa yêu cầu gần đây — hãy đợi người tổ chức phản hồi.', "You already asked recently — give the organizer a little time to respond.")
          : T('Không gửi được yêu cầu. Thử lại nhé.', "Couldn't send the request. Please try again."),
      });
      return;
    }
    set({ receiptRequestSending: false, receiptRequestSent: true });
  }, [set, T]);

  /**
   * The dynamic VietQR payload for a booking, or null when the organizer
   * hasn't given us a bank account we can build one from. Returns the raw
   * EMVCo string; the screen renders it with the same qrcode lib the ticket
   * QR already uses.
   */
  const vietQrFor = useCallback((booking) => {
    const org = booking?.events?.organizers;
    if (!org?.bank_account_no || !org?.bank_name) return null;
    try {
      return buildVietQrPayload({
        bank: org.bank_name,
        accountNumber: org.bank_account_no,
        amountVnd: booking.total_vnd,
        memo: booking.payment_ref || booking.code || '',
      });
    } catch (e) {
      // An unrecognised bank name is an organizer data problem, not a crash:
      // the screen falls back to showing the account details as text.
      console.warn('VietQR unavailable:', e.message);
      return null;
    }
  }, []);

  // ---- organizer verification queue ----
  // Guarded here, not just by the organizer-mode-gated UI that links here
  // (Home's banner, Account's "Awaiting verification" row) — this is the
  // one place that actually decides whether the screen opens at all, so a
  // participant navigating here by any other means (a stale link, a replayed
  // notification, …) still can't land on what is meant to be an
  // organizer-only management screen. RLS already limits what data such a
  // request could ever read (a participant only ever owns their own booking
  // row), but this keeps them from seeing the screen's organizer-framed
  // copy and action buttons ("Money received"/"Can't find it") over their
  // own payment at all, not just from acting on it.
  const openVerifications = useCallback(() => {
    if (!(s.organizerMode || s.accountType === 'admin' || s.hasHosted)) return;
    set({ screen: 'verifications', verifications: [], verificationsLoading: true, verificationsFocusBookingId: null });
  }, [set, s.organizerMode, s.accountType, s.hasHosted]);

  /**
   * 14-organizer-checkin.md: Attendance's "Check payment" — jumps straight
   * to this one booking's own row in Verifications, whether it's the only
   * pending item or buried far down a long queue, instead of leaving the
   * organizer to scroll and find it. Same event-ownership guard as bug 1's
   * openNotification() fix (myOrgEventKeys, not just the account-wide
   * organizerMode/hasHosted check) since this is reachable from a bell
   * notification tap too, not just Attendance's own (already-scoped) list.
   */
  const openVerificationDetail = useCallback((bookingId, eventKey) => {
    if (eventKey && !s.myOrgEventKeys.includes(eventKey)) return;
    if (!(s.organizerMode || s.accountType === 'admin' || s.hasHosted)) return;
    set({ screen: 'verifications', verifications: [], verificationsLoading: true, verificationsFocusBookingId: bookingId });
  }, [set, s.organizerMode, s.accountType, s.hasHosted, s.myOrgEventKeys]);

  /**
   * Signs every given 'pay-proof' path in one batched call and merges the
   * result into state.proofUrls (path -> viewable URL, 10 minutes — long
   * enough for one review pass, short enough not to matter if it leaks into
   * a log somewhere). Verifications.jsx and Disputes.jsx both call this
   * with whatever proof_path values their list just loaded — this is what
   * an organizer/admin actually needs to inspect the receipt before ruling
   * on it, which nothing rendered before this.
   */
  const signProofUrls = useCallback(async (paths) => {
    const wanted = [...new Set((paths || []).filter(Boolean))];
    if (!wanted.length) return;
    const { data, error } = await supabase.storage.from('pay-proof').createSignedUrls(wanted, 600);
    if (error) {
      console.warn('signProofUrls failed:', error);
      return;
    }
    set(prev => ({
      proofUrls: (data || []).reduce((acc, row) => {
        if (row.path && row.signedUrl && !row.error) acc[row.path] = row.signedUrl;
        return acc;
      }, { ...prev.proofUrls }),
    }));
  }, [set]);

  const loadVerifications = useCallback(async () => {
    if (!s.user?.id) return set({ verifications: [], verificationsLoading: false });
    // v_pending_verifications has no organizer filter of its own — it
    // relies on bookings' RLS, which is an OR of bookings_select_guest
    // (auth.uid() = user_id) and bookings_select_host (organizes the
    // event). That means a plain guest's OWN pending_verification booking
    // comes back too (via the guest policy), and got miscounted here as an
    // organizer-facing "awaiting your OK" item — the Home banner then
    // showed a guest the organizer-phrased card for their own booking.
    // Scope explicitly to organizer_id, same established pattern as
    // loadOrganizerHoldingSummary/loadDocuments below; admins alone see
    // every organizer's queue (bookings_select_admin RLS exists for this).
    if (s.accountType !== 'admin' && !s.myOrganizerIds.length) {
      return set({ verifications: [], verificationsLoading: false });
    }
    set({ verificationsLoading: true });
    let query = supabase
      .from('v_pending_verifications')
      .select('*')
      .order('proof_submitted_at', { ascending: true });
    if (s.accountType !== 'admin') query = query.in('organizer_id', s.myOrganizerIds);
    const { data, error } = await query;
    if (error) {
      console.warn('loadVerifications failed:', error);
      return set({ verifications: [], verificationsLoading: false });
    }
    set({ verifications: data || [], verificationsLoading: false });
    await signProofUrls((data || []).map(v => v.proof_path));
  }, [set, s.user?.id, s.accountType, s.myOrganizerIds, signProofUrls]);

  /**
   * The PHASE 1 counterpart of loadVerifications — how many buyers are
   * currently holding a seat on the organizer's own events, and how soon the
   * nearest one lapses. v_pending_verifications only ever covers PHASE 2, so
   * this reads bookings directly; bookings_select_host already scopes an
   * organizer to their own events' rows, same as it does everywhere else.
   */
  const loadOrganizerHoldingSummary = useCallback(async () => {
    if (!s.myOrganizerIds.length) return set({ organizerHoldingSummary: null });
    const { data, error, count } = await supabase
      .from('bookings')
      .select('hold_expires_at, events!inner(organizer_id)', { count: 'exact' })
      .eq('payment_state', 'holding')
      .in('events.organizer_id', s.myOrganizerIds)
      .order('hold_expires_at', { ascending: true })
      .limit(1);
    if (error) {
      console.warn('loadOrganizerHoldingSummary failed:', error);
      return set({ organizerHoldingSummary: null });
    }
    if (!count) return set({ organizerHoldingSummary: null });
    set({ organizerHoldingSummary: { count, soonestHoldExpiresAt: data?.[0]?.hold_expires_at || null } });
  }, [set, s.myOrganizerIds]);

  const approvePayment = useCallback(async (bookingId) => {
    set({ verificationBusy: bookingId });
    try {
      const { data, error } = await supabase.rpc('verify_payment', {
        p_booking: bookingId, p_via: 'organizer', p_actor_kind: 'organizer', p_meta: {},
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('approvePayment failed:', e);
    }
    set({ verificationBusy: '' });
    await loadVerifications();
  }, [set, loadVerifications]);

  /**
   * "Can't find it" — informational, not a verdict. reject_payment() (as of
   * migration 032) never touches payment_state; it only records the reason
   * and messages the guest, so this alone never puts banbe in the picture
   * or moves the booking into the admin dispute queue. See escalateDispute
   * below for the separate, explicit action that actually does that.
   */
  const rejectPayment = useCallback(async (bookingId, reason) => {
    set({ verificationBusy: bookingId });
    try {
      const { data, error } = await supabase.rpc('reject_payment', {
        p_booking: bookingId, p_reason: reason || '',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('rejectPayment failed:', e);
    }
    set({ verificationBusy: '' });
    await loadVerifications();
  }, [set, loadVerifications]);

  /**
   * The one deliberate action that actually brings banbe in — an organizer
   * reaches for this only once they and the guest genuinely can't resolve a
   * payment between themselves. Unlike rejectPayment, this does move the
   * booking to payment_state = 'disputed' and into the admin-only
   * v_disputes queue.
   */
  const escalateDispute = useCallback(async (bookingId, reason) => {
    set({ verificationBusy: bookingId });
    try {
      const { data, error } = await supabase.rpc('escalate_payment_dispute', {
        p_booking: bookingId, p_reason: reason || '',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('escalateDispute failed:', e);
    }
    set({ verificationBusy: '' });
    await loadVerifications();
  }, [set, loadVerifications]);

  // ---- admin dispute desk ----
  const openDisputes = useCallback(() => {
    set({ screen: 'disputes', disputes: [], disputesLoading: true });
  }, [set]);

  const loadDisputes = useCallback(async () => {
    set({ disputesLoading: true });
    const { data, error } = await supabase
      .from('v_disputes').select('*').order('disputed_at', { ascending: false });
    if (error) {
      console.warn('loadDisputes failed:', error);
      return set({ disputes: [], disputesLoading: false });
    }
    set({ disputes: data || [], disputesLoading: false });
    await signProofUrls((data || []).map(d => d.proof_path));
  }, [set, signProofUrls]);

  /**
   * resolve_dispute (the RPC) only flips database state — payment
   * confirmed/expired, the dispute thread marked resolved and scheduled for
   * purge, one note left in the guest's ordinary chat. The confirmation
   * email itself (with the transcript PDF and the receipt image attached)
   * is a separate step, api/dispute-resolved-email.js — best-effort here:
   * if it fails, the database resolution already stands and an admin can
   * see disputeEmailError and retry rather than the whole action rolling
   * back or silently never emailing anyone.
   */
  const resolveDispute = useCallback(async (bookingId, uphold, note, reasonCategory) => {
    set({ disputeBusy: bookingId, disputeEmailError: '' });
    try {
      const { data, error } = await supabase.rpc('resolve_dispute', {
        p_booking: bookingId, p_uphold: !!uphold, p_resolution: note || '',
        // Anonymized quality-review input (see dispute_resolution_stats,
        // migration 047) — never shown to guest/organizer, only feeds the
        // admin-only aggregate insights view. Falls back to 'other' rather
        // than block a resolution the admin actually wants to make now.
        p_reason_category: reasonCategory || 'other',
      });
      if (error) throw error;
      if (data?.success === false) throw new Error(data.error);
    } catch (e) {
      console.warn('resolveDispute failed:', e);
    }
    // The DB resolution above is the part the admin is actually waiting on
    // — it must update the screen (disputeBusy cleared, the row moved to
    // "Resolved") regardless of what happens next. The confirmation email
    // (api/dispute-resolved-email.js: puppeteer-core + @sparticuz/chromium,
    // never load-tested end-to-end — see 05-notify-retention.md) used to be
    // awaited INSIDE this same try block, ahead of these two lines: a slow
    // cold start or a hung request there silently blocked every visible
    // sign that the resolution had already succeeded, reading as "the
    // button does nothing" even though the dispute really was resolved.
    set({ disputeBusy: '' });
    await loadDisputes();

    sendDisputeResolvedEmail(bookingId);
  }, [set, loadDisputes]);

  /** Fire-and-forget half of resolveDispute — see the comment there. */
  const sendDisputeResolvedEmail = useCallback(async (bookingId) => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) return;
      const res = await fetch('/api/dispute-resolved-email', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ bookingId }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        set({ disputeEmailError: body.error || `HTTP_${res.status}` });
      }
    } catch (e) {
      console.warn('sendDisputeResolvedEmail failed:', e);
      set({ disputeEmailError: e.message || 'NETWORK_ERROR' });
    }
  }, [set]);

  /** The T1/T2/T3 trail for one booking — what a dispute is actually argued on. */
  const loadAuditTrail = useCallback(async (bookingId) => {
    set({ auditBookingId: bookingId, auditTrail: [] });
    const { data } = await supabase
      .from('payment_audit_log').select('*')
      .eq('booking_id', bookingId).order('at', { ascending: true });
    set({ auditTrail: data || [] });
  }, [set]);

  // ---- the temporary dispute chat (guest <-> organizer, while escalated) ----
  /**
   * escalate_payment_dispute() opens this thread server-side; this just
   * reads it back. RLS on dispute_threads/dispute_messages already limits
   * this to the guest, the event's organizer, or an admin — the same three
   * parties who could ever see a dispute at all.
   */
  const loadDisputeChat = useCallback(async (bookingId, _retried = false) => {
    set({ disputeChatBookingId: bookingId, disputeChatMessages: [], disputeChatLoading: true, disputeChatError: '', disputeChatThread: null });
    const { data: thread, error: threadError } = await supabase
      .from('dispute_threads').select('id, resolved_at, purge_after').eq('booking_id', bookingId).maybeSingle();
    if (threadError || !thread) {
      console.warn('loadDisputeChat failed:', threadError);
      // A denied-by-RLS row (a stale organizer_id/guest_id on this
      // dispute_threads row no longer matches this account — the ART10025
      // symptom) and a genuinely missing thread both read as "no data"
      // here. resolve_dispute()'s own repair only fires once a dispute is
      // closed, and reject_payment()/escalate_payment_dispute() refuse to
      // run again once payment_state = 'disputed' — so this is the one
      // place left that can reach a currently-open, mislinked thread.
      // resync_dispute_thread() has no state restriction and is safe to
      // call speculatively; if it fixes nothing, the retry just fails the
      // same way and disputeChatError still gets set below.
      if (!_retried) {
        const { data: resync } = await supabase.rpc('resync_dispute_thread', { p_booking: bookingId });
        if (resync?.success) return loadDisputeChat(bookingId, true);
      }
      return set({
        disputeChatLoading: false,
        disputeChatError: threadError ? T('Không tải được đoạn chat. Thử lại nhé.', "Couldn't load this chat. Please try again.") : '',
      });
    }
    const { data: messages, error } = await supabase
      .from('dispute_messages').select('*')
      .eq('dispute_thread_id', thread.id).order('created_at', { ascending: true });
    if (error) {
      console.warn('loadDisputeChat messages failed:', error);
      return set({
        disputeChatLoading: false,
        disputeChatError: T('Không tải được tin nhắn. Thử lại nhé.', "Couldn't load messages. Please try again."),
      });
    }
    set({
      disputeChatMessages: messages || [], disputeChatLoading: false,
      disputeChatThread: { resolvedAt: thread.resolved_at, purgeAfter: thread.purge_after },
    });
  }, [set, T]);

  const disputeChatDraftType = useCallback((e) => set({ disputeChatDraft: e.target.value }), [set]);

  const sendDisputeMessage = useCallback(async (bookingId) => {
    const body = s.disputeChatDraft.trim();
    if (!body) return;
    set({ disputeChatDraft: '', disputeChatError: '' });
    const { data, error } = await supabase.rpc('send_dispute_message', { p_booking: bookingId, p_body: body });
    if (error || data?.success === false) {
      console.warn('sendDisputeMessage failed:', error || data?.error);
      // Previously silent — a NOT_AUTHORIZED/NOT_DISPUTED from a
      // stale/mislinked dispute_threads row looked identical to a
      // successful send that just hadn't shown up yet.
      set({
        disputeChatDraft: body,
        disputeChatError: T('Chưa gửi được. Thử lại nhé.', "Couldn't send. Please try again."),
      });
      return;
    }
    await loadDisputeChat(bookingId);
  }, [set, s.disputeChatDraft, loadDisputeChat, T]);

  // ---- billing identity (the buyer block on every document) ----
  const openBilling = useCallback(async () => {
    set({ screen: 'billing', billingError: '', billingSaved: false });
    const uid = s.user?.id;
    if (!uid) return;
    const { data } = await supabase
      .from('profiles')
      .select('display_name, phone, billing_name, billing_address, billing_phone, billing_tax_code')
      .eq('id', uid).maybeSingle();
    if (!data) return;
    set({
      billingName: data.billing_name || data.display_name || '',
      billingAddress: data.billing_address || '',
      billingPhone: data.billing_phone || data.phone || '',
      billingTaxCode: data.billing_tax_code || '',
    });
  }, [set, s.user?.id]);

  const billingNameType = useCallback((e) => set({ billingName: e.target.value, billingSaved: false }), [set]);
  const billingAddressType = useCallback((e) => set({ billingAddress: e.target.value, billingSaved: false }), [set]);
  const billingPhoneType = useCallback((e) => set({ billingPhone: e.target.value, billingSaved: false }), [set]);
  const billingTaxCodeType = useCallback((e) => set({ billingTaxCode: e.target.value, billingSaved: false }), [set]);

  const saveBillingDetails = useCallback(async () => {
    set({ billingSaving: true, billingError: '', billingSaved: false });
    try {
      const { data, error } = await supabase.rpc('save_billing_details', {
        p_name: s.billingName, p_address: s.billingAddress,
        p_phone: s.billingPhone, p_tax_code: s.billingTaxCode,
      });
      if (error) throw error;
      if (data && data.success === false) throw new Error(data.error || 'SAVE_FAILED');
      set({ billingSaving: false, billingSaved: true });
    } catch (e) {
      console.warn('saveBillingDetails failed:', e);
      set({ billingSaving: false, billingError: T('Chưa lưu được. Thử lại nhé.', "Couldn't save. Please try again.") });
    }
  }, [set, T, s.billingName, s.billingAddress, s.billingPhone, s.billingTaxCode]);

  // ---- payout details (where the organizer wants to be paid) ----
  const openPayout = useCallback(async () => {
    set({ screen: 'payout', payoutError: '', payoutSaved: false });
    const orgId = s.myOrganizerIds[0];
    if (!orgId) return;
    const { data } = await supabase
      .from('organizers')
      .select('bank_name, bank_account_name, bank_account_no, momo_phone, pay_note, billing_address, tax_code')
      .eq('id', orgId).maybeSingle();
    if (!data) return;
    set({
      payoutBankName: data.bank_name || '', payoutAccountName: data.bank_account_name || '',
      payoutAccountNo: data.bank_account_no || '', payoutMomo: data.momo_phone || '',
      payoutNote: data.pay_note || '', payoutAddress: data.billing_address || '',
      payoutTaxCode: data.tax_code || '',
    });
  }, [set, s.myOrganizerIds]);

  const payoutField = useCallback((key) => (e) => set({ [key]: e.target.value, payoutSaved: false }), [set]);

  const savePayoutDetails = useCallback(async () => {
    const orgId = s.myOrganizerIds[0];
    if (!orgId) return set({ payoutError: T('Chưa có trang tổ chức.', 'No host page yet.') });
    set({ payoutSaving: true, payoutError: '', payoutSaved: false });
    try {
      const { data, error } = await supabase.rpc('save_organizer_payment', {
        p_organizer: orgId,
        p_bank_name: s.payoutBankName, p_bank_account_name: s.payoutAccountName,
        p_bank_account_no: s.payoutAccountNo, p_momo_phone: s.payoutMomo,
        p_pay_note: s.payoutNote, p_billing_address: s.payoutAddress, p_tax_code: s.payoutTaxCode,
      });
      if (error) throw error;
      if (data && data.success === false) throw new Error(data.error || 'SAVE_FAILED');
      set({ payoutSaving: false, payoutSaved: true });
    } catch (e) {
      console.warn('savePayoutDetails failed:', e);
      set({ payoutSaving: false, payoutError: T('Chưa lưu được. Thử lại nhé.', "Couldn't save. Please try again.") });
    }
  }, [set, T, s.myOrganizerIds, s.payoutBankName, s.payoutAccountName, s.payoutAccountNo,
      s.payoutMomo, s.payoutNote, s.payoutAddress, s.payoutTaxCode]);

  // ---- the documents themselves ----
  const openDocuments = useCallback((kind, role = 'guest') => {
    set({ screen: 'documents', documentsKind: kind, documentsRole: role, documents: [], documentsError: '' });
  }, [set]);

  const loadDocuments = useCallback(async () => {
    const uid = s.user?.id;
    if (!uid) return set({ documents: [], documentsLoading: false });
    set({ documentsLoading: true, documentsError: '' });

    // Documents are organizer-uploaded now (migration 056) — nothing to
    // mint here anymore. `superseded_at IS NULL` hides a replaced version
    // immediately (Task 5's soft-delete: the row itself still exists,
    // queryable for 24h, but never in this list).
    let query = supabase.from('payment_documents').select('*').eq('kind', s.documentsKind).is('superseded_at', null);
    if (s.documentsRole === 'host') {
      // An organizer is usually also a goer, so filtering by RLS alone would
      // mix their own tickets into the list of documents they issued.
      if (!s.myOrganizerIds.length) return set({ documentsLoading: false, documents: [] });
      query = query.in('organizer_id', s.myOrganizerIds);
    } else {
      query = query.eq('user_id', uid);
    }
    const { data, error } = await query.order('issued_at', { ascending: false });
    if (error) {
      console.warn('loadDocuments failed:', error);
      return set({ documentsLoading: false, documents: [], documentsError: T('Chưa tải được danh sách.', "Couldn't load the list.") });
    }
    set({ documentsLoading: false, documents: data || [] });
  }, [set, T, s.user?.id, s.documentsKind, s.documentsRole, s.myOrganizerIds]);

  const openDocument = useCallback((id, backTo = 'documents') => set({ screen: 'documentView', documentId: id, documentBack: backTo }), [set]);
  const backFromDocument = useCallback(() => set(prev => ({ screen: prev.documentBack || 'documents' })), [set]);
  const backFromDocuments = useCallback(() => set({ screen: 'profile' }), [set]);

  const currentDocument = useMemo(
    () => s.documents.find(d => d.id === s.documentId) || null,
    [s.documents, s.documentId],
  );

  /**
   * The organizer's replacement for the old auto-generation: uploads a real
   * file (PDF/image) to the private 'payment-documents' bucket, then
   * upload_payment_document() (migration 056) records it, supersedes
   * whatever live document of that kind existed for this booking (only
   * when `reason` is given — the RPC itself enforces that a reason is
   * required exactly when there's something to replace), and inserts the
   * in-app notification. The email (Task 4's opt-in, Task 6's always-sent
   * replacement notice) is a separate, best-effort call to /api/notify —
   * same "client calls it right after its own action succeeds" pattern
   * claimPendingReferralAndWelcome() already uses, not part of this
   * transaction.
   */
  const uploadPaymentDocument = useCallback(async (bookingId, kind, file, reason = '') => {
    if (!bookingId || !file) return { success: false, error: 'FILE_REQUIRED' };
    try {
      const { blob, ext, contentType } = await normalizeProofFile(file);
      const path = `${bookingId}/${kind}-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from('payment-documents').upload(path, blob, { upsert: true, contentType });
      if (upErr) throw upErr;

      const trimmedReason = reason.trim();
      const { data: doc, error } = await supabase.rpc('upload_payment_document', {
        p_booking: bookingId, p_kind: kind, p_file_path: path, p_upload_reason: trimmedReason || null,
      });
      if (error) throw error;

      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: trimmedReason ? 'document_replaced' : 'document_uploaded', documentId: doc.id }),
        }).catch(() => {});
      }
      return { success: true, doc };
    } catch (e) {
      console.warn('uploadPaymentDocument failed:', e);
      return { success: false, error: e.message === 'REASON_REQUIRED' ? 'REASON_REQUIRED' : 'UPLOAD_FAILED' };
    }
  }, []);

  // Deep-links a bell notification ('payment_document_uploaded'/'_replaced')
  // straight to the document it's about, without needing the full
  // Documents list loaded first — fetches the one row RLS allows this
  // account to see (the guest it belongs to) and opens the viewer on it.
  const openDocumentFromNotification = useCallback(async (documentId, backTo = 'documents') => {
    const { data, error } = await supabase.from('payment_documents').select('*').eq('id', documentId).maybeSingle();
    if (error || !data) return;
    set({ documents: [data], documentId: data.id, documentsKind: data.kind, documentsRole: 'guest', screen: 'documentView', documentBack: backTo });
  }, [set]);

  // Keeps documentFileUrl pointed at whichever document is open — a signed
  // URL, not a public one, since the bucket is private (RLS-scoped to the
  // booking's guest/organizer, migration 056). Re-signs whenever the open
  // document changes; a legacy document with no file_path just clears it,
  // which is what tells DocumentView.jsx to fall back to the old rendered-
  // HTML viewer instead.
  useEffect(() => {
    const path = currentDocument?.file_path;
    if (!path) { set({ documentFileUrl: '' }); return; }
    let active = true;
    supabase.storage.from('payment-documents').createSignedUrl(path, 600).then(({ data, error }) => {
      if (!active) return;
      if (error) { console.warn('document signed URL failed:', error); set({ documentFileUrl: '' }); return; }
      set({ documentFileUrl: data?.signedUrl || '' });
    });
    return () => { active = false; };
  }, [currentDocument?.file_path, set]);

  const toggleAutoEmailDocuments = useCallback(() => {
    set(prev => ({ autoEmailDocuments: !prev.autoEmailDocuments }));
    persistAccountPreference({ auto_email_documents: !s.autoEmailDocuments });
  }, [set, s.autoEmailDocuments, persistAccountPreference]);

  /**
   * Hands the rendered document to the browser's own print dialog, which is
   * also its "Save as PDF". Generating a PDF in-page would mean shipping a
   * PDF library and hand-laying the Vietnamese diacritics into it; the print
   * pipeline already renders the exact same HTML the viewer just looked at.
   */
  const downloadDocument = useCallback((doc) => {
    if (!doc) return;
    const html = renderPaymentDocument(doc, { lang: s.lang, origin: window.location.origin });
    const w = window.open('', '_blank');
    if (!w) return;
    w.document.write(html);
    w.document.close();
    // Let the wordmark land before the dialog freezes the page, or the
    // saved PDF has a broken-image box where the logo should be.
    w.addEventListener('load', () => setTimeout(() => w.print(), 120));
  }, [s.lang]);

  const openPreferences = useCallback(() => set({ screen: 'preferences' }), [set]);
  const openSecurity = useCallback(() => set({
    screen: 'security', securityPassword: '', securityPasswordConfirm: '',
    securityError: '', securitySaved: false, securityResetSent: false,
  }), [set]);

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

  const curEvent = useMemo(() => {
    const base = findEvent(s.eventKey);
    const overrides = liveEventOverrides(s.liveEvent, base);
    return overrides ? { ...base, ...overrides } : base;
  }, [s.eventKey, s.liveEvent]);
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
  const goMapExplore = useCallback(() => set({ screen: 'mapExplore' }), [set]);
  const backFromMapExplore = useCallback(() => set({ screen: 'home' }), [set]);
  // Plain setter, not map-specific logic — MapExplore.jsx owns deciding
  // *when* to save (right before its CTA navigates to Event Detail) and
  // when to clear (its own "← Đóng" wrapper), this just holds the snapshot
  // across the unmount/remount that switching `screen` away and back causes.
  const setMapExploreState = useCallback((snapshot) => set({ mapExploreState: snapshot }), [set]);
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
  // "organizer" is a pass-through, exactly like "event" itself already is:
  // entering an event from an organizer page keeps whatever back target
  // brought us into this event/organizer cluster in the first place.
  //
  // Pointing back at "organizer" instead is what trapped the two screens in
  // an inescapable loop. Organizer has no back target of its own — its back
  // link just re-opens whichever event is current — so event's back would
  // go to organizer, organizer's back would come straight back to the same
  // event, forever, with no way to reach Home. That's true whichever row of
  // its "Current events" list is tapped, including the event you arrived
  // from (that list contains it too).
  const goEvent = useCallback((key) => set(prev => ({
    screen: 'event',
    eventKey: key,
    eventBackScreen: (prev.screen === 'event' || prev.screen === 'organizer')
      ? prev.eventBackScreen
      : prev.screen,
  })), [set]);
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
  // The heading of whichever list is showing. Shared so the back pill on an
  // event opened from one can name it too — before this existed that pill
  // fell through to its "banbe" default and claimed it went Home, while
  // actually (and correctly) returning to the list.
  const eventListTitle = useMemo(() => ({
    going: T('Đang tham gia', 'Going'),
    saved: T('Đã lưu', 'Saved'),
    completed: T('Sự kiện đã hoàn thành', 'Completed events'),
  }[s.eventListMode] || T('Đang tham gia', 'Going')), [s.eventListMode, T]);

  // Re-fetches on every open, not just once at sign-in: this is the one
  // place a guest actually looks to check what they're still holding a
  // ticket for, and nothing else invalidates `attending` in between (no
  // realtime subscription, no polling — same "nothing pushes to this
  // client" situation as the dispute chat's own 4s poll, see
  // DisputeChatPanel.jsx). Without this, a dispute resolved against the
  // guest by an admin in a different session/tab never clears their
  // already-open app's "Going" list until they reload the whole page.
  const goGoingList = useCallback(() => {
    set({ screen: 'eventList', eventListMode: 'going' });
    if (s.user?.id) loadMyEvents(s.user.id);
  }, [set, s.user?.id, loadMyEvents]);
  const goSavedList = useCallback(() => set({ screen: 'eventList', eventListMode: 'saved' }), [set]);
  const goCompletedList = useCallback(() => set({ screen: 'eventList', eventListMode: 'completed' }), [set]);
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
    // leak the previous user's hosting state into the next sign-in. Lands
    // on Login, not Home — Task 1: no guest browsing after signing out.
    set({
      user: null, accountType: 'participant', organizerMode: false, hasHosted: false, mode: 'goer',
      screen: 'login', authMode: 'login', authMandatory: true, authReturnScreen: 'home', authBackScreen: 'home',
      referralCode: null, orgRegName: '',
    });
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
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: 'name_change', oldName, newName: data?.new_name || newName }),
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

  // A real, permanent delete — not audit-sensitive the way dispute_messages
  // is (05-notify-retention.md's 72h retention is a different table
  // entirely), so no soft-delete. RLS (notifications_delete_own, migration
  // 050) already scopes this to the caller's own rows; removed from local
  // state optimistically first, restored if the delete actually fails.
  const deleteNotification = useCallback(async (id) => {
    const prevNotifications = s.notifications;
    const target = prevNotifications.find(n => n.id === id);
    set(prev => ({
      notifications: prev.notifications.filter(n => n.id !== id),
      unreadNotifications: target && !target.read_at ? Math.max(0, prev.unreadNotifications - 1) : prev.unreadNotifications,
    }));
    const { error } = await supabase.from('notifications').delete().eq('id', id);
    if (error) {
      console.warn('Failed to delete notification:', error);
      set({ notifications: prevNotifications }); // put it back — the delete didn't actually happen
    }
  }, [set, s.notifications]);

  // Consumed once by DisputeChatPanel.jsx after it actually scrolls to/
  // highlights the target message (or the bottom, if there's no
  // message_id) — otherwise every 4s poll re-render would re-trigger it.
  const clearChatHighlight = useCallback(() => set({ chatHighlight: null }), [set]);

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
  const clearFilters = useCallback(() => set({
    filter: 'all', area: 'all', filterAttending: false, filterSaved: false, filterSoldOut: false,
  }), [set]);
  // Home's second chip row (12-home-filters.md) — each independent, AND-combined
  // with `filter`/`area` and with each other, not mutually exclusive.
  const toggleHomeFilter = useCallback((key) => set(prev => {
    if (key === 'attending') return { filterAttending: !prev.filterAttending };
    if (key === 'saved') return { filterSaved: !prev.filterSaved };
    if (key === 'soldOut') return { filterSoldOut: !prev.filterSoldOut };
    return {};
  }), [set]);

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
      // hold_seats() (migration 026), not the legacy claim_seats() — the
      // latter never touches payment_state/hold_expires_at at all, so every
      // booking it created sat at the column default (payment_state =
      // 'holding', hold_expires_at = NULL) forever, regardless of whether
      // the event was free, instantly approved, or later marked paid. That
      // is exactly what left the ticket screen showing "Holding your
      // spot"/00:00 permanently instead of ever reaching Confirmed/Ended.
      const { data: booking, error } = await supabase.rpc('hold_seats', {
        p_event: s.eventKey,
        p_qty: s.qty,
        p_note: null,
      });
      if (error) throw error;
      const holdDeadline = booking.hold_expires_at ? new Date(booking.hold_expires_at).getTime() : null;
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
      // hold_seats() (031:38) raises one of these as a plain
      // `RAISE EXCEPTION '<CODE>'` — no ERRCODE/DETAIL, so the code itself
      // is `err.message` verbatim. This used to fall straight through to
      // the guest as raw, untranslated text (or a generic fallback on iOS)
      // — mapped here the same way `submitPaymentProof`'s own RPC errors
      // already are, so a cancelled/ended event says so instead of a vague
      // "try again".
      const message = {
        NOT_AUTHENTICATED: T('Bạn cần đăng nhập để giữ chỗ.', 'You need to sign in to hold a spot.'),
        INVALID_QTY: T('Số lượng chỗ không hợp lệ.', 'That number of spots isn’t valid.'),
        PROFILE_NOT_FOUND: T('Không tìm thấy hồ sơ của bạn. Vui lòng thử lại.', 'We couldn’t find your profile. Please try again.'),
        EVENT_NOT_FOUND: T('Không tìm thấy sự kiện này.', 'This event could not be found.'),
        EVENT_NOT_LIVE: T('Sự kiện này đã bị huỷ hoặc chưa mở.', 'This event has been cancelled or isn’t open.'),
        SOLD_OUT: T('Rất tiếc, chỗ vừa hết.', 'Sorry — this just sold out.'),
      }[err.message] || T('Không thể giữ chỗ lúc này. Vui lòng thử lại.', 'Could not hold this spot right now. Please try again.');
      set({ loading: false, reserveError: message });
    }
  }, [set, s.eventKey, s.qty]);

  const payHoldNow = useCallback(() => set({ holdDeadline: null, payMode: 'now' }), [set]);
  const confirmPayment = useCallback(async (bookingId, payMethod = 'momo') => {
    try {
      const { data, error } = await supabase.rpc('confirm_payment', { p_booking: bookingId, p_method: payMethod });
      if (error) throw error;
      // 15-organizer-checkin.md follow-up: confirm_payment() (migration 060)
      // now flips payment_state to 'confirmed' server-side too, not just
      // status — but every "awaiting confirmation" surface (the guest's own
      // PaymentDetails countdown, both Home banners, the Verifications
      // queue) reads client-side state that's only ever refreshed by its
      // own poll/mount otherwise. Patch all three in place immediately so
      // none of them linger even for one poll cycle.
      set(prev => ({
        booking: prev.booking && prev.booking.id === bookingId
          ? { ...prev.booking, status: 'confirmed', payment_state: 'confirmed', paid_method: payMethod, hold_expires_at: null, verify_due_at: null }
          : prev.booking,
        paymentBookings: prev.paymentBookings.map(b => (b.id === bookingId
          ? { ...b, status: 'confirmed', payment_state: 'confirmed', paid_method: payMethod, hold_expires_at: null, verify_due_at: null }
          : b)),
        verifications: prev.verifications.filter(v => v.booking_id !== bookingId),
      }));
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
  // The same pattern every /api/auth/* endpoint enforces, checked against
  // the trimmed value those endpoints actually receive. The old check
  // (/\S+@\S+\.\S+/) had no anchors, so "hello a@b.c world", "a@@b.c" and
  // " a@b.c " all passed here and were then rejected by the server — the
  // button lit up and the request bounced with a generic failure.
  const emailValid = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v).trim());
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
    // Only Signup creates a brand-new profile (policy_accepted_at still
    // NULL) — a returning account on the Login tab already consented once,
    // so this defensive no-op (login-submit's own disabled styling already
    // reflects it) only applies to Signup, same as the email-validity check
    // right below.
    if (s.authMode === 'signup' && !s.policyConsent) return;
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
  }, [set, s.loginEmail, s.loginNickname, s.authMode, s.policyConsent, authEmailErrorMessage]);
  // "Password" method, Signup: creates the account with the password
  // actually chosen, then — same as the code method — still requires
  // entering the emailed confirmation code once to finish.
  const passwordSignupSubmit = useCallback(async () => {
    if (!s.policyConsent) return;
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
  }, [set, s.loginEmail, s.loginNickname, s.loginPassword, s.loginPasswordConfirm, s.policyConsent, authEmailErrorMessage, T]);
  // "Password" method, Login: straight to Supabase, no code step — the
  // account already has a password. (The onAuthStateChange listener handles
  // moving off the Login screen once the session lands.)
  const passwordLoginSubmit = useCallback(async () => {
    // No consent gate here — signing in is never how a profile's
    // policy_accepted_at first gets set (see codeRequestSubmit above); an
    // account that can sign in already consented at signup.
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
      fetch('/api/notify', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ type: 'welcome' }),
      }).catch(() => {});
      if (referredSomeone) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: 'referral_joined' }),
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
  // Google/Facebook (note 10). Not gated on the consent checkbox at all —
  // unlike password/code, an OAuth attempt can't be pre-classified as
  // "just a login" ahead of time (Supabase creates the account right then
  // if the provider identity is new), and a *returning* user must be able
  // to click straight through with zero friction. Consent for a genuinely
  // new profile is handled after the redirect completes instead — see
  // syncUser()'s policyGateActive branch.
  const startOAuth = useCallback(async (provider) => {
    const { error } = await supabase.auth.signInWithOAuth({
      provider, options: { redirectTo: getAuthRedirectUrl() },
    });
    if (error) set({ reserveError: error.message });
    // No further state change on success: signInWithOAuth navigates the
    // whole page away immediately, so there's nothing left to update here.
  }, [set]);
  const loginGoogle = useCallback(() => startOAuth('google'), [startOAuth]);
  const loginFacebook = useCallback(() => startOAuth('facebook'), [startOAuth]);
  const loginInstagram = useCallback(() => set({ reserveError: T('Instagram chưa khả dụng. Hãy dùng email hoặc OTP điện thoại.', 'Instagram is not available yet. Use email or phone OTP.') }), [set, T]);

  // ---- Account > Security ----
  const securityPasswordType = useCallback((e) => set({ securityPassword: e.target.value, securityError: '', securitySaved: false }), [set]);
  const securityPasswordConfirmType = useCallback((e) => set({ securityPasswordConfirm: e.target.value, securityError: '', securitySaved: false }), [set]);

  // Deliberately one form for both cases this section has to serve: an
  // account that has only ever used emailed sign-in codes setting its first
  // password, and one replacing a password it already has. Supabase treats
  // both as the same update on the signed-in user, and nothing the client
  // can read reliably says which of the two an account is — so branching
  // here would mean guessing at the label and getting it wrong half the time.
  const saveSecurityPassword = useCallback(async () => {
    if (!passwordValid(s.securityPassword)) {
      return set({ securityError: T('Mật khẩu cần ít nhất 8 ký tự.', 'Passwords need at least 8 characters.'), securitySaved: false });
    }
    if (s.securityPassword !== s.securityPasswordConfirm) {
      return set({ securityError: T('Mật khẩu xác nhận không khớp.', 'Passwords do not match.'), securitySaved: false });
    }
    set({ securityBusy: true, securityError: '', securitySaved: false });
    const { error } = await supabase.auth.updateUser({ password: s.securityPassword });
    if (error) {
      return set({ securityBusy: false, securityError: T('Không lưu được mật khẩu lúc này. Vui lòng thử lại.', "We couldn't save that password right now. Please try again.") });
    }
    set({ securityBusy: false, securityPassword: '', securityPasswordConfirm: '', securitySaved: true });
  }, [set, s.securityPassword, s.securityPasswordConfirm, T]);

  // "Forgot your current password?" — emails the recovery link to this
  // account's own address. Shown as sent either way: the endpoint already
  // refuses to reveal whether an address has an account, and surfacing a
  // failure here would leak the same thing by omission.
  const sendSecurityPasswordReset = useCallback(async () => {
    const email = s.user?.email;
    if (!email) return;
    set({ securityBusy: true, securityError: '' });
    try {
      await requestPasswordReset({ email });
    } catch { /* same message either way — see above */ }
    set({ securityBusy: false, securityResetSent: true });
  }, [set, s.user?.email]);

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
  // openNotification is defined further down (after openAttendance exists to
  // route 'booking_requested' taps to it) — see the notifications section.
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

  // A real, permanent delete, own messages only — RLS (messages_delete_own,
  // migration 054) scopes this to `sender_id = auth.uid()`, which a system
  // message (sender_id NULL) can never match. Unlike dispute_messages
  // (05-notify-retention.md's 72h retention requirement), this table has no
  // documented retention requirement, so no soft-delete here either.
  const deleteMessage = useCallback(async (id) => {
    const prevMessages = s.chatMessages;
    set(prev => ({ chatMessages: prev.chatMessages.filter(m => m.id !== id) }));
    const { error } = await supabase.from('messages').delete().eq('id', id);
    if (error) {
      console.warn('Failed to delete message:', error);
      set({ chatMessages: prevMessages }); // put it back — the delete didn't actually happen
    }
  }, [set, s.chatMessages]);

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
    // 'pending' belongs here too: an unpaid guest is exactly the one the
    // organizer needs to find in order to mark them paid. Expired holds are
    // dropped below so the list doesn't fill up with seats nobody holds.
    const { data: bookings, error } = await supabase
      .from('bookings')
      .select('id, user_id, qty, status, total_vnd, code, expires_at, paid_marked_at, paid_method, proof_path')
      .eq('event_id', key)
      .in('status', ['pending', 'confirmed', 'attended']);
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
    const now = Date.now();
    const guests = (bookings || [])
      .filter(b => b.status !== 'pending' || !b.expires_at || new Date(b.expires_at).getTime() > now)
      .map(b => ({
        id: b.id,
        name: (names[b.user_id] || '').trim() || 'Khách',
        qty: b.qty,
        checkedIn: b.status === 'attended',
        // Paid means the organizer confirmed the money arrived — which is
        // also what issued the receipt. hold_seats marks instant-approval
        // bookings 'confirmed' up front, so status alone isn't the answer.
        paid: !!b.paid_marked_at,
        payMethod: b.paid_method || '',
        totalVnd: b.total_vnd || 0,
        code: b.code || '',
        hasProof: !!b.proof_path,
      }));
    set({ attendanceGuests: guests, attendanceLoading: false });
  }, [set]);
  const openAttendance = useCallback((key) => {
    set({ screen: 'attendance', attendanceEventKey: key, attendanceGuests: [] });
    loadAttendanceGuests(key);
  }, [set, loadAttendanceGuests]);

  // Reopens the Confirmed/ticket screen for a specific booking — used when
  // a 'payment_confirmed' notification arrives (or is tapped) after the
  // guest has moved on elsewhere in the app, since the booking that just
  // unlocked its QR code isn't necessarily the one in state.booking any more.
  const openBookingConfirmed = useCallback(async (bookingId, eventKey) => {
    const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
    if (!data) return;
    set({
      screen: 'confirmed',
      eventKey: eventKey || data.event_id,
      booking: data,
      // Bug 3 (15-organizer-checkin.md follow-up): this used to read the
      // legacy `expires_at` mirror column, which hold_seats() sets once at
      // creation and NOTHING ever clears afterward — not confirm_payment()
      // (migration 060), not reject_pending_guest(). An organizer accepting
      // quickly (well within the original 30-min hold window) landed the
      // guest here with `holdDeadline` re-armed to that stale future
      // timestamp, which Home.jsx's own `heldEv`/`heldKey` (unrelated to
      // Confirmed.jsx's own phase logic, which already correctly prefers
      // `booking.hold_expires_at`) reads in isolation — so leaving this
      // screen for Home showed a "Đang giữ chỗ"/holding tag on an
      // already-confirmed booking's event card until something else
      // happened to clear it. `hold_expires_at` is the actively-maintained
      // column (NULL once confirmed/rejected) — using it here instead
      // means a confirmed booking never re-arms this at all.
      holdDeadline: data.hold_expires_at ? new Date(data.hold_expires_at).getTime() : null,
      now: Date.now(),
    });
  }, [set]);

  /**
   * The client-side half of forfeiting a lapsed PHASE 1 hold. Called the
   * instant a ticking countdown (Confirmed, PaymentDetails, Home's banner)
   * notices its own deadline has passed while still 'holding'.
   *
   * Every screen that shows "Going"/a ticket/the Reserve-vs-ticket toggle
   * reads this same booking's payment_state/status out of shared state —
   * never off a live countdown — so patching them here is what makes all
   * three update immediately, together, regardless of which screen actually
   * noticed the expiry. The server call alongside it is what makes that
   * true durably instead of just visually: without it, this booking would
   * sit at status='confirmed' (instant-approval events set that immediately,
   * before payment) until the next minutely sweep, or forever if the sweep
   * ever failed on it.
   */
  const forfeitExpiredHold = useCallback((booking) => {
    if (!booking?.id) return;
    const eventKey = booking.event_id;
    set(prev => ({
      attending: eventKey ? prev.attending.filter(k => k !== eventKey) : prev.attending,
      booking: prev.booking?.id === booking.id
        ? { ...prev.booking, payment_state: 'expired', status: 'expired' } : prev.booking,
      paymentBookings: prev.paymentBookings.map(b => (
        b.id === booking.id ? { ...b, payment_state: 'expired', status: 'expired' } : b
      )),
    }));
    supabase.rpc('forfeit_my_expired_hold', { p_booking: booking.id })
      .then(({ data, error }) => {
        if (error || data?.success === false) {
          console.warn('forfeitExpiredHold RPC failed:', error || data?.error);
        }
      });
  }, [set]);

  // A watchdog for every screen that ISN'T one of the three above watching
  // its own local countdown (Confirmed, PaymentDetails, Home). EventDetail
  // and EventList, in particular, only ever read booking.status/attending —
  // they never notice a lapse themselves — so staying on one of those past
  // the deadline used to leave "Going" and the ticket code showing forever,
  // since nothing else was mounted to call forfeitExpiredHold. This runs
  // centrally off the same ticking `now` regardless of which screen is on
  // top, and is naturally idempotent with the per-screen effects (all of
  // them route through this same forfeitExpiredHold, which itself only acts
  // once per lapse since payment_state flips to 'expired' immediately).
  useEffect(() => {
    const isLapsed = (b) => b && b.payment_state === 'holding' && b.hold_expires_at
      && msUntil(b.hold_expires_at, state.now) === 0;
    // state.booking covers the event currently open in EventDetail/Confirmed
    // even before paymentBookings has ever loaded (e.g. landing straight on
    // EventDetail on a fresh launch, never having passed through Home) —
    // it's populated as soon as eventKey resolves, independent of
    // loadPaymentBookings(). paymentBookings covers every OTHER hold this
    // account has open elsewhere, which state.booking alone can't see.
    const justLapsed = (isLapsed(state.booking) && state.booking)
      || (state.paymentBookings || []).find(isLapsed);
    if (justLapsed) forfeitExpiredHold(justLapsed);
  }, [state.paymentBookings, state.booking, state.now, forfeitExpiredHold]);

  // Tapping a notification marks it read and, for the kinds that point at
  // somewhere real, takes you there — a 'new_message' notification opens the
  // actual thread it's about instead of just sitting there read.
  const openNotification = useCallback((n) => {
    markNotificationRead(n.id);
    // 01-hold-payment.md follow-up (bug 1): both organizer-only
    // destinations below used to navigate unconditionally — relying on
    // `openVerifications()`'s own ACCOUNT-level gate (organizerMode ||
    // admin || hasHosted) or, for `openAttendance()`, nothing at all — and
    // RLS silently no-opping the actual data fetch as the only real
    // backstop. That's an account-wide check ("is this person an
    // organizer of ANYTHING"), not an EVENT-specific one, so any dual-role
    // account (this app's own explicit design — "one account for
    // everything, switch on organizer mode from Account" — the shared
    // fast-suite test account is exactly this) could land on another
    // organizer's screen for an event it only ever booked as a guest.
    // `myOrgEventKeys` (loadMyEvents(), populated at sign-in) is the real,
    // per-event ownership list — checked here so a non-owner is blocked
    // from the navigation itself, not just left looking at buttons that
    // silently no-op under RLS.
    const iOrganize = (eventId) => s.myOrgEventKeys.includes(eventId);
    if (n.kind === 'new_message' && n.data?.thread_id) {
      openThread(n.data.thread_id, n.data.event_id, 'inbox');
    } else if (n.kind === 'booking_requested' && n.data?.event_id && iOrganize(n.data.event_id)) {
      // The organizer's side: straight to the check-in list for that event,
      // where "mark as paid" already lives (see Attendance.jsx).
      openAttendance(n.data.event_id);
    } else if (n.kind === 'hold_created' && n.data?.booking_id) {
      // 01-hold-payment.md follow-up: the guest's own mirror of
      // 'booking_requested' above (hold_seats(), migration 053) — takes
      // the guest straight back to their own timer/QR/payment screen for
      // this exact hold, the same way `dispute_message` already does for
      // its own guest-facing case below.
      openPaymentDetails(n.data.booking_id);
    } else if (n.kind === 'payment_awaiting_verification' && n.data?.event_id && iOrganize(n.data.event_id)) {
      // 01-hold-payment.md follow-up: fired by submit_payment_proof()
      // (031:317) when a guest reports having transferred — the organizer
      // side of BUG 3, previously never wired at all. Same destination as
      // 'booking_requested' (this is the very next step in the same
      // request's lifecycle, still shown/actioned from Verifications —
      // "Money received"/"Can't find it" — not Attendance's check-in list,
      // so `openVerifications()` here, not `openAttendance()`).
      openVerifications();
    } else if (n.kind === 'payment_confirmed' && n.data?.booking_id) {
      openBookingConfirmed(n.data.booking_id, n.data.event_id);
    } else if (n.kind === 'dispute_message' && n.data?.booking_id) {
      // Only the guest and organizer ever receive this kind (migration
      // 048/050 — admin is deliberately excluded), so accountType alone
      // decides which screen has this booking's chat panel.
      // message_id may be absent on a row created before migration 050 —
      // DisputeChatPanel.jsx falls back to scrolling to the bottom instead.
      set({ chatHighlight: { bookingId: n.data.booking_id, messageId: n.data.message_id || null } });
      if (s.accountType === 'organizer') openVerifications();
      else openPaymentDetails(n.data.booking_id);
    } else if ((n.kind === 'payment_document_uploaded' || n.kind === 'payment_document_replaced') && n.data?.document_id) {
      openDocumentFromNotification(n.data.document_id);
    } else if (n.kind === 'receipt_requested' && n.data?.event_id && iOrganize(n.data.event_id)) {
      // The guest's own "Xem Receipt" (Confirmed.jsx) asked for one that
      // doesn't exist yet — straight to Check-in, same per-event ownership
      // guard as every other organizer-bound kind above, with the specific
      // booking's own "Upload receipt" control auto-highlighted (see
      // Attendance.jsx's attendanceHighlightBookingId effect) so the
      // organizer doesn't have to hunt for it in a long list.
      set({ attendanceHighlightBookingId: n.data.booking_id });
      openAttendance(n.data.event_id);
    }
  }, [markNotificationRead, openThread, openAttendance, openBookingConfirmed, set, s.accountType, s.myOrgEventKeys, openVerifications, openPaymentDetails, openDocumentFromNotification]);
  /**
   * The organizer's "mark as paid". confirm_payment issues the receipt in
   * the same transaction (migration 024) and notifies the guest, which is
   * why this is one action rather than a separate "now issue a receipt"
   * step the organizer could forget.
   */
  const markGuestPaid = useCallback(async (bookingId, payMethod = 'bank') => {
    const result = await confirmPayment(bookingId, payMethod);
    if (s.attendanceEventKey) await loadAttendanceGuests(s.attendanceEventKey);
    return result;
  }, [confirmPayment, loadAttendanceGuests, s.attendanceEventKey]);

  const notifyCheckIn = useCallback(async (bookingId) => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: 'check_in', bookingId }),
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
  // 14-organizer-checkin.md (Bug 2b): "Có nhận khách này không?" ▪︎ "Từ
  // chối" — reject_pending_guest() (migration 059) halts every pending
  // process for the booking (sets both status AND payment_state to
  // 'cancelled', clears hold_expires_at/verify_due_at) and returns the
  // seat to the pool, then notifies the guest via chat + bell notification
  // itself — same reason-required shape as undo-check-in/cancel-booking
  // above, so the guest's notification always says something concrete.
  const openRejectGuest = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'rejectGuest', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const closeReasonPrompt = useCallback(() => set({ reasonPrompt: null, reasonPromptError: '' }), [set]);
  const submitReasonPrompt = useCallback(async (reasonLabel) => {
    const prompt = s.reasonPrompt;
    if (!prompt) return;
    set({ reasonPromptBusy: true, reasonPromptError: '' });

    const rpcName = prompt.kind === 'undoCheckin' ? 'undo_check_in'
      : prompt.kind === 'rejectGuest' ? 'reject_pending_guest'
      : 'cancel_booking';
    const rpcArgs = prompt.kind === 'undoCheckin'
      ? { p_booking_id: prompt.bookingId, p_reason: reasonLabel }
      : { p_booking: prompt.bookingId, p_reason: reasonLabel };
    const { data, error } = await supabase.rpc(rpcName, rpcArgs);
    if (error || !data?.success) {
      set({
        reasonPromptBusy: false,
        reasonPromptError: prompt.kind === 'undoCheckin'
          ? T('Không thể huỷ điểm danh. Vui lòng thử lại.', 'Could not undo the check-in. Please try again.')
          : prompt.kind === 'rejectGuest'
          ? T('Không thể từ chối yêu cầu này. Vui lòng thử lại.', 'Could not reject this request. Please try again.')
          : T('Không thể huỷ vé. Vui lòng thử lại.', 'Could not cancel the booking. Please try again.'),
      });
      return;
    }

    set({ reasonPrompt: null, reasonPromptBusy: false });
    if (s.attendanceEventKey) loadAttendanceGuests(s.attendanceEventKey);
    // reject_pending_guest() already inserts the guest's chat message +
    // bell notification itself (migration 059) — no separate /api/notify
    // email call for this kind, unlike undo-check-in/cancel-booking below.
    if (prompt.kind === 'rejectGuest') return;
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      const notifyType = prompt.kind === 'undoCheckin' ? 'checkin_undo' : 'booking_cancelled';
      if (token) {
        fetch('/api/notify', {
          method: 'POST',
          headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ type: notifyType, bookingId: prompt.bookingId, reason: reasonLabel }),
        }).catch(() => {});
      }
    } catch { /* best-effort email; the in-app notification already landed */ }
  }, [set, s.reasonPrompt, s.attendanceEventKey, loadAttendanceGuests, T]);

  /// The actual check_in_guest() call — factored out of toggleCheckin so
  /// both the confirm-dialog's "Yes" (below) and the (already-confirmed)
  /// manual flow share one path.
  const performCheckIn = useCallback(async (bookingId) => {
    set(prev => ({ attendanceGuests: prev.attendanceGuests.map(g => (g.id === bookingId ? { ...g, checkedIn: true } : g)) }));
    const { data, error } = await supabase.rpc('check_in_guest', { p_reservation_id: bookingId });
    if (error || !data?.success) {
      console.warn('Check-in failed:', error || data?.error);
      set(prev => ({ attendanceGuests: prev.attendanceGuests.map(g => (g.id === bookingId ? { ...g, checkedIn: false } : g)) }));
      return { success: false };
    }
    notifyCheckIn(bookingId);
    return { success: true };
  }, [set, notifyCheckIn]);

  // 14-organizer-checkin.md (Bug 3): a confirmation step before actually
  // marking a guest arrived — an accidental tap used to check someone in
  // instantly, with only the reason-required UNDO afterward as a backstop.
  // Reuses the same reasonPrompt/ReasonSheet shell as undo-check-in/cancel-
  // booking/reject-guest above, but this kind has no reason list — just a
  // plain yes/no (see ReasonSheet.jsx's own `confirmCheckin` branch).
  const openConfirmCheckin = useCallback((bookingId) => {
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    set({ reasonPrompt: { kind: 'confirmCheckin', bookingId, guestName: guest?.name || '' }, reasonPromptError: '' });
  }, [set, s.attendanceGuests]);
  const confirmCheckin = useCallback(async () => {
    const prompt = s.reasonPrompt;
    if (!prompt || prompt.kind !== 'confirmCheckin') return;
    set({ reasonPrompt: null });
    await performCheckIn(prompt.bookingId);
  }, [s.reasonPrompt, set, performCheckIn]);

  const toggleCheckin = useCallback((bookingId, checked) => {
    if (checked) { openUndoCheckin(bookingId); return; } // reversing requires a reason — see below
    openConfirmCheckin(bookingId); // Bug 3: confirm before marking arrived
  }, [openUndoCheckin, openConfirmCheckin]);

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
    goHome, goProfile, goInbox, backFromInbox, goEvent, backFromEvent, goOrganizer, goReserve, backToEvent, backToOrganizer, goMapExplore, backFromMapExplore, setMapExploreState,
    goChat, goLogin, goDashboard, goCreate, openAttendance, loadAttendanceGuests, openHeld, goHostIntro, createBack,
    goGoingList, goSavedList, goCompletedList, backFromEventList, eventListTitle,
    loadPaymentBookings, openPaymentDetails, backFromPaymentDetails, backFromBilling, copyPayField, uploadPaymentProof,
    openBilling, billingNameType, billingAddressType, billingPhoneType, billingTaxCodeType, saveBillingDetails,
    openPayout, payoutField, savePayoutDetails,
    openDocuments, loadDocuments, openDocument, backFromDocument, backFromDocuments,
    currentDocument, downloadDocument, markGuestPaid, uploadPaymentDocument, openDocumentFromNotification, toggleAutoEmailDocuments,
    submitPaymentProof, paymentTxnType, vietQrFor, nudgeOrganizer, loadReceiptStatus, requestReceipt,
    openVerifications, openVerificationDetail, loadVerifications, approvePayment, rejectPayment, escalateDispute, loadOrganizerHoldingSummary, forfeitExpiredHold,
    openDisputes, loadDisputes, resolveDispute, loadAuditTrail, loadDisputeChat, disputeChatDraftType, sendDisputeMessage,
    switchToHost, backFromDashboard, switchToGoer, becomeHost, logout, dismissSplash,
    goEditName, editNameType, saveDisplayName, goNotifications, markNotificationRead, deleteNotification, openNotification, clearChatHighlight, dismissToast,
    canHost, toggleOrganizerMode, enableOrganizerMode,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding, togglePolicyConsent, openPolicy, backFromPolicy, acceptPolicyGate,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, askLocation, toggleTheme, pickTheme, openPreferences, openSecurity, openPhoto, closePhoto, showPhotoAt, isPhotoLiked, togglePhotoLike, sharePhotoOrganizer,
    securityPasswordType, securityPasswordConfirmType, saveSecurityPassword, sendSecurityPasswordReset,
    pickFilter, clearFilters, toggleHomeFilter, shareEvent, referralLink, shareReferral,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, formEmailType, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    addToCalendar, giveTicket,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType, loginPasswordType, loginPasswordConfirmType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginGoogle, loginInstagram, emailValid, passwordValid, setAuthMethod, codeRequestSubmit, passwordSignupSubmit, passwordLoginSubmit, verifyEmailCode, requestPasswordResetSubmit, submitCurrentForm, newPasswordType, newPasswordConfirmType, submitNewPassword,
    chatOnType, chatSend, chatOnKey, chatBackFn, deleteMessage, openChatFor, openThread,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, requestVerify,
    toggleCheckin, openQrScan, closeQrScan, checkInByScan, openCancelBooking, openRejectGuest, closeReasonPrompt, submitReasonPrompt, confirmCheckin,
  }), [
    s, set, EN, T, trStatus, located, stripKm, curEvent, palette, curArea,
    isSaved, isGoing, toggleFav, toggleFollow,
    goHome, goProfile, goInbox, backFromInbox, goEvent, backFromEvent, goOrganizer, goReserve, backToEvent, backToOrganizer, goMapExplore, backFromMapExplore, setMapExploreState,
    goChat, goLogin, goDashboard, goCreate, openAttendance, loadAttendanceGuests, openHeld, goHostIntro, createBack,
    goGoingList, goSavedList, goCompletedList, backFromEventList, eventListTitle,
    loadPaymentBookings, openPaymentDetails, backFromPaymentDetails, backFromBilling, copyPayField, uploadPaymentProof,
    openBilling, billingNameType, billingAddressType, billingPhoneType, billingTaxCodeType, saveBillingDetails,
    openPayout, payoutField, savePayoutDetails,
    openDocuments, loadDocuments, openDocument, backFromDocument, backFromDocuments,
    currentDocument, downloadDocument, markGuestPaid, uploadPaymentDocument, openDocumentFromNotification, toggleAutoEmailDocuments,
    submitPaymentProof, paymentTxnType, vietQrFor, nudgeOrganizer, loadReceiptStatus, requestReceipt,
    openVerifications, openVerificationDetail, loadVerifications, approvePayment, rejectPayment, escalateDispute, loadOrganizerHoldingSummary, forfeitExpiredHold,
    openDisputes, loadDisputes, resolveDispute, loadAuditTrail, loadDisputeChat, disputeChatDraftType, sendDisputeMessage,
    switchToHost, backFromDashboard, switchToGoer, becomeHost, logout, dismissSplash,
    goEditName, editNameType, saveDisplayName, goNotifications, markNotificationRead, deleteNotification, openNotification, clearChatHighlight, dismissToast,
    canHost, toggleOrganizerMode, enableOrganizerMode,
    pickVi, pickEn, pickLight, pickDark, finishOnboarding, togglePolicyConsent, openPolicy, backFromPolicy, acceptPolicyGate,
    toggleLang, openArea, pickArea, allowLocation, denyLocation, askLocation, toggleTheme, pickTheme, openPreferences, openSecurity, openPhoto, closePhoto, showPhotoAt, isPhotoLiked, togglePhotoLike, sharePhotoOrganizer,
    securityPasswordType, securityPasswordConfirmType, saveSecurityPassword, sendSecurityPasswordReset,
    pickFilter, clearFilters, toggleHomeFilter, shareEvent, referralLink, shareReferral,
    qtyMinus, qtyPlus, pickPayNow, pickHold, formNameType, formEmailType, submitReserve, payHoldNow, confirmPayment, cancelBooking, cancelEvent,
    addToCalendar, giveTicket,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType, loginPasswordType, loginPasswordConfirmType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginGoogle, loginInstagram, setAuthMethod, codeRequestSubmit, passwordSignupSubmit, passwordLoginSubmit, verifyEmailCode, requestPasswordResetSubmit, submitCurrentForm, newPasswordType, newPasswordConfirmType, submitNewPassword,
    chatOnType, chatSend, chatOnKey, chatBackFn, deleteMessage, openChatFor, openThread,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, requestVerify,
    toggleCheckin, openQrScan, closeQrScan, checkInByScan, openCancelBooking, openRejectGuest, closeReasonPrompt, submitReasonPrompt, confirmCheckin,
  ]);

  return <GocCtx.Provider value={value}>{children}</GocCtx.Provider>;
}

export function useGoc() {
  const ctx = useContext(GocCtx);
  if (!ctx) throw new Error('useGoc must be used within GocProvider');
  return ctx;
}

export { EVENTS, findEvent };
