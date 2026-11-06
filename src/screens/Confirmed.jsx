import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { formatCountdown, msUntil, useTicking, daysUntilInZone } from '../lib/countdown.js';
import { paper, ink, ink2, ink3, display, cardGlass, alert, block, clay, clayBg, honey, plum, moss, mist } from '../theme.js';
import GlassMenu, { GlassMenuItem, glassMenuSurface } from '../components/GlassMenu.jsx';
import { MiniCalendarPage } from './EventPlanActions.jsx';
import { dateBlock, dateTileLabel, aboutSection, includedSection } from '../lib/eventDetailPresentation.js';
import { isBookingTicket } from '../lib/bookingTicket.js';
import { downloadTicketPdfs, googleCalendarUrl } from '../lib/ticketPdf.js';
import GiftTicketSheet from './sheets/GiftTicketSheet.jsx';
import { giftPdfData, isAppleWalletBrowser, addToAppleWallet, walletErrorMessage } from '../lib/giftTicket.js';
import { BookingJourneyProgress } from '../components/ui/FormControls.jsx';
import { track, ticketDayBucket } from '../lib/analytics.js';
import { rowTimeZone, VN_TIME_ZONE } from '../lib/eventMarket.js';
import { typicalWaitText, isCheckedIn } from '../lib/quickWins.js';
import { mapsUrl, haversineKm } from '../data/events.js';
import { ticketCase, formatEntryCode, ticketQrShowsToken, doorWatchOpen, inDoorWindow, showDistance } from '../lib/ticketStatus.js';
import { ticketCopy } from '../lib/ticketCopy.js';
import { TICKET_DEMO_RESET } from '../lib/ticketDemo.js';
import PaperTicket from '../components/ticket/PaperTicket.jsx';
import WhatsNextStrip from '../components/ticket/WhatsNextStrip.jsx';
import TicketQr from '../components/ticket/TicketQr.jsx';
import TicketStubPager from '../components/ticket/TicketStubPager.jsx';
import EventDetailsSheet from './sheets/EventDetailsSheet.jsx';

export default function Confirmed() {
  const {
    state, T, trStatus, set, curEvent: ev, backFromConfirmed: realBack, openCalendarPicker, closeCalendarPicker, addToCalendarGoogle, addToCalendarICS,
    openPaymentDetails: realOpenPay, forfeitExpiredHold: realForfeit, goReserve: realReserve,
    loadReceiptStatus: realLoadReceipt, requestReceipt: realRequestReceipt, openDocumentFromNotification: realOpenDoc, loadBookingAttendees: realLoadAttendees,
    loadMyRefunds: realLoadRefunds, openMyRefunds: realOpenRefunds, openChatFor: realOpenChat, goEvent: realGoEvent,
  } = useBanBe();
  const s = state;
  // Admin ticket demo (migration 217): sample booking, nothing reaches the server. Reads and polls are skipped, actions that
  // would write or leave the screen say "Not available in the demo". iOS twin: ConfirmedView `demoBlocked`.
  const demo = !!s.ticketDemo;
  const [demoNotice, setDemoNotice] = useState('');
  const blocked = () => { setDemoNotice(T('Không có trong bản demo.', 'Not available in the demo.')); setTimeout(() => setDemoNotice(''), 3000); };
  const g = (fn) => (demo ? blocked : fn);
  const quiet = (fn) => (demo ? () => {} : fn);
  const openPaymentDetails = g(realOpenPay);
  const goReserve = g(realReserve);
  const requestReceipt = g(realRequestReceipt);
  const openDocumentFromNotification = g(realOpenDoc);
  const openMyRefunds = g(realOpenRefunds);
  const openChatFor = g(realOpenChat);
  const goEvent = g(realGoEvent);
  const forfeitExpiredHold = quiet(realForfeit);
  const loadReceiptStatus = quiet(realLoadReceipt);
  const loadBookingAttendees = quiet(realLoadAttendees);
  const loadMyRefunds = quiet(realLoadRefunds);
  const backFromConfirmed = demo ? () => set({ ...TICKET_DEMO_RESET, eventKey: s.ticketDemoPrev || s.eventKey, ticketDemoPrev: null, screen: 'accountGroup', accountGroupKey: 'adminReview' }) : realBack;

  // payment_state is the source of truth for every phase distinction below;
  // paid_marked_at/status only exist as a fallback for a booking fetched
  // somewhere that hasn't picked up the new column yet (there shouldn't be
  // one, but a booking is the one object here worth a defensive read).
  const phase = s.booking?.payment_state
    || (s.booking?.paid_marked_at ? 'confirmed' : s.booking ? 'holding' : null);
  // TASK B (2026-10-01 UX foundation pass) — the ticket/QR is only ever
  // real once BOTH booking.status AND payment_state read 'confirmed'; see
  // isBookingTicket()'s own doc comment (src/lib/bookingTicket.js).
  // A checked-in booking is 'attended' (check_in_guest, migration 021) and is still the same paid ticket.
  const isPaid = isBookingTicket(s.booking) || (s.booking?.status === 'attended' && s.booking?.payment_state === 'confirmed');
  const isHolding = phase === 'holding';
  const isPendingVerification = phase === 'pending_verification';
  const isExpired = phase === 'expired';
  // Only a hold or a transfer the host has not confirmed yet is still payable; cancelled / disputed / expired are not.
  const showPayButton = !!s.booking?.id && (isHolding || isPendingVerification);

  // The countdown only ticks while there is something to actually count
  // down — PHASE 2 shows an SLA reassurance number that ticks too, so both
  // phases need the clock, but PAID/DISPUTED/nothing don't.
  const holdDeadlineIso = s.booking?.hold_expires_at
    || (s.holdDeadline ? new Date(s.holdDeadline).toISOString() : null);
  const now = useTicking(isHolding || isPendingVerification);
  const holdCountdown = formatCountdown(msUntil(holdDeadlineIso, now));
  const verifyMsLeft = msUntil(s.booking?.verify_due_at, now);
  const verifyCountdown = formatCountdown(verifyMsLeft);
  const verifyOverdue = !!s.booking?.verify_due_at && verifyMsLeft === 0;

  // The moment this screen's own ticking clock notices the hold has lapsed,
  // forfeit it immediately rather than leave the ticket sitting in a stale
  // "still holding" state until the next poll or the minutely server sweep
  // gets to it — this is what makes "Going" and the ticket both drop the
  // instant the countdown reaches 00:00, not up to a minute later.
  useEffect(() => {
    // isHolding flips to false the instant forfeitExpiredHold's own local
    // state patch lands (phase is derived straight from booking.payment_state),
    // so this self-guards against firing more than once per lapse.
    if (isHolding && msUntil(holdDeadlineIso, now) === 0) {
      forfeitExpiredHold(s.booking);
    }
  }, [isHolding, holdDeadlineIso, now, s.booking, forfeitExpiredHold]);

  // ticket_opened (migration 196): once per confirmed ticket shown, with the event's day vs today (venue zone).
  useEffect(() => {
    if (!isPaid || !s.booking?.id) return;
    const start = ev?.startDate instanceof Date ? ev.startDate.getTime() : NaN;
    const bucket = ticketDayBucket(start, Date.now(), rowTimeZone(s.realEventsById?.[ev?.key]));
    if (bucket) track('ticket_opened', { day_bucket: bucket });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isPaid, s.booking?.id]);

  // "Xem Receipt" needs to know, per booking, whether a live
  // payment_documents row already exists — reset on every booking change
  // (not just once) since this screen can be reopened for a different
  // booking without unmounting (openBookingConfirmed just patches state).
  useEffect(() => {
    if (isPaid && s.booking?.id) loadReceiptStatus(s.booking.id);
    else set({ receiptDoc: undefined, receiptRequestSent: false, receiptRequestError: '' });
  }, [isPaid, s.booking?.id, loadReceiptStatus, set]);

  // Bug 1 (15-organizer-checkin.md follow-up): a guest sitting on this exact
  // screen while the organizer uploads (from Attendance's own poll picking
  // up a "Xem Receipt"/request_receipt() ask, or unprompted) previously had
  // to leave and come back for the control to notice — matches this app's
  // established polling convention elsewhere (Attendance's own 6s poll,
  // 41340ee; PaymentDetails' 6s poll). Stops once a receipt is actually
  // found — nothing left to poll for once it exists.
  useEffect(() => {
    if (demo || !isPaid || !s.booking?.id || s.receiptDoc) return undefined;
    const bookingId = s.booking.id;
    const id = setInterval(() => loadReceiptStatus(bookingId), 6000);
    return () => clearInterval(id);
  }, [isPaid, s.booking?.id, s.receiptDoc, loadReceiptStatus]);

  // While a booking is sitting unpaid, poll for a phase change — the
  // organizer confirming, the bank webhook matching, or the guest freezing
  // it from another tab. The guest may already be looking at this exact
  // screen when any of those happen, and shouldn't have to leave and come
  // back via a notification to see it update. Generalised to sync the whole
  // row (not just paid_marked_at) so PHASE 1 -> PHASE 2 shows up live too.
  useEffect(() => {
    if (demo || !s.booking?.id || phase === 'confirmed' || phase === 'expired') return undefined;
    const bookingId = s.booking.id;
    let active = true;
    const id = setInterval(async () => {
      const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      if (!active || !data) return;
      // The server row can still read 'holding' past its own deadline for a
      // moment — the sweep hasn't reached it yet, or this same client's own
      // forfeit RPC (fired the instant the local countdown hit 0) hasn't
      // landed. Blindly copying that stale row over would revive a ticket
      // this tab already forfeited every 6 seconds until the server catches
      // up. Treat it as expired here too instead, and let forfeitExpiredHold
      // retry the RPC rather than regressing local state backwards.
      if (data.payment_state === 'holding' && msUntil(data.hold_expires_at) === 0) {
        forfeitExpiredHold(data);
        return;
      }
      if (data.payment_state !== phase) {
        set(prev => (prev.booking?.id === bookingId ? { booking: data } : {}));
      }
    }, 6000);
    return () => { active = false; clearInterval(id); };
  }, [s.booking?.id, phase, set, forfeitExpiredHold]);

  // Named tickets (migration 151): one card per attendee, each with its own QR
  // and PDF. Empty for a booking made before per-attendee tickets, which keeps
  // its single booking-level QR.
  useEffect(() => { if (s.booking?.id) loadBookingAttendees(s.booking.id); }, [s.booking?.id, loadBookingAttendees]);
  const attendees = (s.bookingAttendees || []).filter(a => a.booking_id === s.booking?.id);
  const hasNamed = attendees.length > 0;
  const [stubIdx, setStubIdx] = useState(0); // which attendee stub the pager shows (drives "Download this ticket")
  const [pdfBusy, setPdfBusy] = useState(false);
  useEffect(() => { setStubIdx(0); }, [s.booking?.id]);
  const [giftOpen, setGiftOpen] = useState(false);
  const [walletBusy, setWalletBusy] = useState(false);
  const [walletMsg, setWalletMsg] = useState('');
  const [giftedSeats, setGiftedSeats] = useState([]); // seats split off this booking and gifted away
  useEffect(() => { setGiftOpen(false); setWalletMsg(''); }, [s.booking?.id]);
  const reloadGiftedSeats = async (bookingId) => {
    const { data } = await supabase.from('bookings').select('*').eq('original_booking_id', bookingId).not('recipient_name', 'is', null).order('gifted_at', { ascending: true });
    setGiftedSeats(data || []);
  };
  useEffect(() => {
    let live = true;
    setGiftedSeats([]);
    if (!demo && isPaid && s.booking?.id) {
      supabase.from('bookings').select('*').eq('original_booking_id', s.booking.id).not('recipient_name', 'is', null).order('gifted_at', { ascending: true })
        .then(({ data }) => { if (live) setGiftedSeats(data || []); });
    }
    return () => { live = false; };
  }, [isPaid, s.booking?.id]);

  // Checked in at the door (booking 'attended', or one of its named tickets scanned). The strip says so; there is no separate
  // celebration card any more (note 78): the ticket stays calm and the strip carries the moment.
  const checkedIn = isPaid && isCheckedIn(s.booking, attendees);
  const reduceMotion = typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  // While the event is about to start or under way, the ticket screen watches for the door scan (same 6s convention
  // as the polls above); it stops once checked in. Outside that window nothing is polled.
  const startMs = ev?.startDate instanceof Date ? ev.startDate.getTime() : NaN;
  // Named tickets (migration 151) are scanned one by one (note 78): the booking only counts as checked in once ALL of them
  // are, and the door watch keeps going while any is still open and the door window lasts (src/lib/ticketStatus.js,
  // shared vectors). A booking without named tickets keeps the old rule and the old poll exactly.
  const pendingScans = hasNamed && attendees.some(a => !a.checked_in_at);
  const stripCheckedIn = isPaid && (hasNamed ? !pendingScans : checkedIn);
  const watchDoor = isPaid && doorWatchOpen({ namedScans: hasNamed ? attendees.map(a => !!a.checked_in_at) : null, checkedIn, startMs, nowMs: Date.now() });
  useEffect(() => {
    if (demo || !watchDoor || !s.booking?.id) return undefined;
    const bookingId = s.booking.id;
    const id = setInterval(async () => {
      // Named tickets: the window can close while this screen stays open, so stop at that very tick (the gate above only
      // runs when the effect starts). Single tickets are not touched.
      if (hasNamed && !inDoorWindow(startMs, Date.now())) { clearInterval(id); return; }
      const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      if (data && data.status !== s.booking?.status) set(prev => (prev.booking?.id === bookingId ? { booking: data } : {}));
      if (hasNamed) loadBookingAttendees(bookingId);
    }, 6000);
    return () => clearInterval(id);
  }, [watchDoor, startMs, s.booking?.id, s.booking?.status, hasNamed, set, loadBookingAttendees]);

  // Q2 honest waiting: this host's typical confirmation time (get_host_confirmation_time, migration 198), asked once
  // per screen open; below 5 confirmations, on error or before the migration exists, nothing extra is shown.
  const [typicalWait, setTypicalWait] = useState(null);
  const waitAskedFor = useRef(null);
  useEffect(() => {
    const eventId = s.booking?.event_id;
    if (demo || !isPendingVerification || !eventId || waitAskedFor.current === s.booking.id) return undefined;
    waitAskedFor.current = s.booking.id;
    let live = true;
    supabase.rpc('get_host_confirmation_time', { p_event_id: eventId })
      .then(({ data, error }) => { if (live && !error && data?.success) setTypicalWait(typicalWaitText(data.median_minutes)); }, () => {});
    return () => { live = false; };
  }, [isPendingVerification, s.booking?.id, s.booking?.event_id]);

  // The host's own note to guests and the exact address, if they wrote them (events.chat_greeting, migration 156; never the
  // built-in default). Read once per ticket, for a paid ticket only; shown in the Event details sheet.
  const [hostNote, setHostNote] = useState({ vi: '', en: '', address: '' });
  useEffect(() => {
    const eventId = s.booking?.event_id;
    setHostNote({ vi: '', en: '', address: '' });
    if (demo || !isPaid || !eventId) return undefined;
    let live = true;
    (async () => {
      let res = await supabase.from('events').select('address_line, chat_greeting, chat_greeting_en').eq('id', eventId).maybeSingle();
      if (res.error) res = await supabase.from('events').select('address_line').eq('id', eventId).maybeSingle();
      if (!live || !res.data) return;
      setHostNote({ vi: (res.data.chat_greeting || '').trim(), en: (res.data.chat_greeting_en || '').trim(), address: (res.data.address_line || '').trim() });
    })().catch(() => {});
    return () => { live = false; };
  }, [isPaid, s.booking?.event_id]);
  const noteText = s.lang === 'en' ? (hostNote.en || hostNote.vi) : (hostNote.vi || hostNote.en);
  const directionsUrl = mapsUrl(ev);

  // Note 78: which "What's next" case this booking is in (src/lib/ticketStatus.js), its approved copy, and its tone.
  const en = s.lang === 'en';
  const [whenDateRaw, whenTime] = (ev.when || '').split(' ▪︎ ');
  const areaText = trStatus((ev.where || '').split(' ▪︎ ')[0] || '');
  // The booking row's own status can say cancelled/expired even when payment_state has not caught up.
  const caseState = s.booking?.status === 'cancelled' ? 'cancelled' : s.booking?.status === 'expired' ? 'expired' : phase;
  const daysUntil = daysUntilInZone(whenDateRaw, startMs, ev.tz || VN_TIME_ZONE);
  const tCase = s.booking
    ? ticketCase({ paymentState: caseState, eventCancelled: !!ev.cancelled, endedHoursAgo: ev.endedHoursAgo ?? null, isPaid, checkedIn: stripCheckedIn, daysUntil })
    : null;
  // "Track refund" only when this booking really has an open refund claim (loaded on demand for a cancelled ticket).
  useEffect(() => {
    if (tCase?.key === 'cancelled' && s.booking?.id && s.user?.id) loadMyRefunds();
  }, [tCase?.key, s.booking?.id, s.user?.id, loadMyRefunds]);
  const hasRefund = (s.myRefunds || []).some(c => c.bookingId === s.booking?.id);
  const copy = tCase ? ticketCopy(tCase.key, {
    en, eventCancelled: !!ev.cancelled, dateText: dateTileLabel(whenDateRaw, en), timeText: whenTime || '', areaText, daysUntil,
    typicalWait, verifyOverdue, hasReceipt: !!s.receiptDoc, hasRefund, hasDirections: !!directionsUrl,
  }) : null;
  const toneColor = { alert, honey, plum, ink3, moss, clay, mist }[tCase?.tone] || ink3;
  const msToStart = Number.isFinite(startMs) ? startMs - Date.now() : NaN;
  const stripTail = tCase?.key === 'holding' ? { text: holdCountdown, id: 'confirmed-hold-countdown' }
    : tCase?.key === 'awaiting' && !verifyOverdue && s.booking?.verify_due_at ? { text: verifyCountdown, id: 'confirmed-verify-countdown' }
    : tCase?.key === 'today' && msToStart > 0 ? { text: msToStart >= 3600000 ? `${Math.floor(msToStart / 3600000)}h` : `${Math.max(1, Math.floor(msToStart / 60000))}m`, id: 'confirmed-today-countdown' }
    : null;
  const stripAction = {
    refunds: () => openMyRefunds('confirmed'),
    reserve: goReserve,
    pay: () => openPaymentDetails(s.booking.id, 'confirmed'),
    chat: () => openChatFor(ev.key, 'confirmed'),
    receipt: () => openDocumentFromNotification(s.receiptDoc.id, 'confirmed'),
    // The picker is anchored on the calendar tile, so bring that tile into view.
    calendar: () => { openCalendarPicker(); setTimeout(() => document.querySelector('[data-testid="confirmed-add-to-calendar"]')?.scrollIntoView({ block: 'center', behavior: reduceMotion ? 'auto' : 'smooth' }), 0); },
  };
  // A cancelled / ended / unconfirmed ticket never draws the real QR (TicketQr); an unmapped state is treated as void.
  const qrMode = tCase?.qr || 'void';
  const qrShows = ticketQrShowsToken(qrMode);
  const qrLabel = { ok: T('Mã QR vé', 'Ticket QR'), in: T('Bạn đã check-in', 'Checked in'), lock: T('QR sẽ mở khi host xác nhận', 'QR unlocks when the host confirms'), past: T('Đã kết thúc', 'Ended'), void: T('Vé không còn hiệu lực', 'Ticket void') }[qrMode];
  const [policyOpen, setPolicyOpen] = useState(false);
  // Event details sheet (note 78). It closes before the full Event Detail opens, so coming Back lands on the same ticket
  // with the sheet closed (goEvent records 'confirmed' as the back target; the booking in state is not touched).
  const [detailsOpen, setDetailsOpen] = useState(false);
  const detailsOpener = useRef(null); // the control that opened the sheet, so focus can go back to it
  const includedItems = ev.includedItems || [];
  const detailsAbout = aboutSection({ desc: ev.desc, intro: ev.intro, includedCount: includedItems.length });
  const detailsIncluded = includedSection(includedItems.length > 0 ? includedItems.map(it => it.label) : (ev.included || '').split(/\s*(?:▪︎|,|·)\s*/));
  // Distance only when it helps choose: the viewer is located and within 50 km (never "9662 km away").
  const detailsDistance = showDistance(s.located === true ? haversineKm(s.userCoords, ev) : null, s.located, en);
  const eventOver = !!ev.cancelled || ev.endedHoursAgo != null;

  const eventStart = ev.startDate || new Date();
  const calUrl = googleCalendarUrl({
    title: ev.name, start: eventStart, end: new Date(eventStart.getTime() + 2 * 3600 * 1000),
    location: ev.locationLabel || ev.where || '', description: ev.desc || '',
  });
  const pdfBase = {
    eventName: ev.name, organizer: ev.orgName || ev.host || '', whenText: ev.when, venue: ev.locationLabel || ev.where || '',
    isEN: s.lang === 'en', calendarUrl: calUrl,
  };
  const runDownload = async (list) => {
    if (!list.length || pdfBusy) return;
    setPdfBusy(true);
    try { await downloadTicketPdfs(list, `banbe-tickets-${s.booking?.code || 'booking'}.zip`); }
    catch (e) { console.warn('ticket PDF failed:', e); }
    setPdfBusy(false);
  };
  const attendeePdf = (a) => ({
    ...pdfBase, holderName: a.name, ticketCode: a.ticket_code, qrValue: a.admission_token, reference: a.id,
    importUrl: a.claim_code ? `${window.location.origin}/?claim=${encodeURIComponent(a.claim_code)}` : undefined,
  });
  const ownPdf = () => ({
    ...pdfBase, holderName: (s.user?.name || '').trim(), ticketCode: s.booking?.code || '', qrValue: s.booking?.admission_token || s.booking?.id, reference: s.booking?.id,
  });
  // This booking row IS a gifted seat (single-seat gift, or the split-off row).
  const isGifted = !!s.booking?.recipient_name;
  const giftPdfOf = (b) => giftPdfData(pdfBase, {
    recipientName: b.recipient_name, ticketCode: b.code, admissionToken: b.admission_token || b.id, claimCode: b.claim_code, reference: b.id,
  });
  // After a gift: refresh the open booking (qty drops for a multi-seat split; a
  // single seat becomes the gifted row) and the list of gifted seats.
  const onGifted = async () => {
    const id = s.booking?.id;
    if (!id) return;
    const { data } = await supabase.from('bookings').select('*').eq('id', id).maybeSingle();
    if (data) set(prev => (prev.booking?.id === id ? { booking: data } : {}));
    reloadGiftedSeats(id);
  };
  const walletEligible = isAppleWalletBrowser();
  const [moreOpen, setMoreOpen] = useState(false);
  const calBlock = dateBlock((ev.when || '').split(' ▪︎ ')[0], s.lang === 'en');
  const runWallet = async () => {
    if (demo) { blocked(); return; }
    if (walletBusy || !s.booking?.id) return;
    setWalletBusy(true); setWalletMsg('');
    const code = await addToAppleWallet(s.booking.id);
    setWalletBusy(false);
    if (code) setWalletMsg(walletErrorMessage(code, T));
  };
  // formName used to be a free-typed, never-persisted Reserve.jsx field —
  // s.user.name (real profiles.display_name, 01-hold-payment.md's
  // 2026-09-17 follow-up #6) is the actual identity now.
  const name = (s.user?.name || '').trim() || T('Bạn', 'You');
  // The policy paragraph, wording unchanged (note 78 only changes how it is displayed: collapsed under the ticket).
  const policyNote = T('banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.', 'banbe does not collect money. Pay the organizer directly using the instructions in chat. If they cancel, they are responsible for your refund.');

  const showQr = isPaid;
  const calendarLabel = s.calAdded ? T('Đã thêm vào lịch', 'Added to calendar') : T('Thêm vào lịch', 'Add to calendar');

  // Ticket status decides the buttons (the two tiles are the most useful actions for that status, "More" holds the rest):
  // upcoming/today: Wallet or PDF + calendar, More = give / PDF / receipt; ended or checked in: PDF + receipt, no calendar, no
  // gifting; holding / awaiting: calendar only; cancelled / expired / under review: nothing. iOS twin: ConfirmedView `actionsArea`.
  const tKey = tCase?.key || null;
  const live = tKey === 'upcoming' || tKey === 'today';
  const over = tKey === 'ended' || tKey === 'checkedIn';
  const actionable = showQr && !['cancelled', 'expired', 'review'].includes(tKey);
  const showCal = !over && !['cancelled', 'expired', 'review'].includes(tKey);
  const curAttendee = hasNamed ? attendees[Math.min(stubIdx, attendees.length - 1)] : null;
  const receiptItem = s.receiptDoc !== undefined && {
      testId: 'confirmed-view-receipt', icon: 'doc',
      label: s.receiptDoc ? T('Xem Receipt', 'View Receipt')
        : s.receiptRequestSending ? T('Đang gửi yêu cầu…', 'Sending request…')
        : s.receiptRequestSent ? T('Đã gửi yêu cầu ▪︎ Đang chờ người tổ chức', 'Request sent ▪︎ waiting on the organizer')
        : T('Yêu cầu Receipt', 'Request Receipt'),
      disabled: s.receiptRequestSending || (!s.receiptDoc && s.receiptRequestSent),
      onClick: () => { if (s.receiptDoc) openDocumentFromNotification(s.receiptDoc.id, 'confirmed'); else requestReceipt(s.booking.id); },
    };
  const receiptReady = actionable && over && !!receiptItem;
  const walletPrimary = live && !hasNamed && !isGifted && walletEligible;
  const pdfLabel = pdfBusy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải vé PDF', 'Download PDF');
  const moreItems = [
    live && !hasNamed && !isGifted && { testId: 'confirmed-give-ticket', icon: 'gift', label: T('Tặng vé cho bạn bè', 'Give a ticket to a friend'), onClick: () => (demo ? blocked() : setGiftOpen(true)) },
    walletPrimary && { testId: 'confirmed-download-pdf', icon: 'download', label: pdfLabel, onClick: () => runDownload([ownPdf()]) },
    actionable && hasNamed && attendees.length > 1 && { testId: 'confirmed-download-all', icon: 'download', label: T('Tải tất cả', 'Download all'), onClick: () => runDownload(attendees.map(attendeePdf)) },
    actionable && !over && receiptItem,
  ].filter(Boolean);
  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Confirmed">
      {/* Back, top-left — where the thumb and the OS convention expect it. */}
      {demo && (
        <div data-testid="ticket-demo-banner" style={{ margin: '10px 22px 0', padding: '8px 12px', borderRadius: 12, background: block, color: ink, fontSize: 12.5, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
          <span>{demoNotice || T('Demo · dữ liệu mẫu · không lưu gì', 'Demo · sample data · nothing is saved')}</span>
          <button type="button" onClick={backFromConfirmed} data-testid="ticket-demo-exit" style={{ border: 'none', background: 'none', color: ink, fontWeight: 700, fontSize: 12.5, cursor: 'pointer', minHeight: 44 }}>{T('Thoát demo', 'Exit demo')}</button>
        </div>
      )}
      <div onClick={backFromConfirmed} data-testid="confirmed-back" style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '14px 30px 0', fontSize: 14, color: ink, cursor: 'pointer', alignSelf: 'flex-start' }}>
        <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1.5 2 8l6 6.5" /></svg>
        {s.confirmedBack === 'notifications' ? T('Thông báo', 'Notifications')
          : s.confirmedBack === 'accountGroup' ? T('Tài khoản', 'Account')
          : T('Quay lại', 'Back')}
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '16px 22px 0' }}>
        {/* Note 48 (iOS parity): Event ✓ → Hold → Pay → Ticket; only while the booking is still on its way to a ticket. */}
        {s.booking && (isHolding || isPendingVerification) && (
          <div style={{ marginBottom: 14 }}><BookingJourneyProgress current={isPendingVerification ? 3 : 2} T={T} /></div>
        )}
        {/* Wordmark and the one-word status, in the tone of the case. */}
        {copy && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, margin: '0 6px 12px' }}>
            <img src="/banbe-wordmark.png" alt="banbe" crossOrigin="anonymous" style={{ width: 56, height: 'auto', display: 'block', flex: 'none', opacity: 0.7 }} />
            <span data-testid="confirmed-status" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5, fontWeight: 600, color: ink }}>
              <span aria-hidden style={{ width: 7, height: 7, borderRadius: '50%', background: toneColor }} />{copy.label}
            </span>
          </div>
        )}
        {s.booking && (
          <PaperTicket
            onOpenDetails={(el) => { detailsOpener.current = el; setDetailsOpen(true); }} viewLabel={T('Xem sự kiện', 'View event')}
            holderLabel={T('Vé của ', 'Ticket for ') + (isGifted ? s.booking.recipient_name : name)}
            title={ev.name}
            tiles={[
              { key: 'date', label: T('Ngày', 'Date'), value: dateTileLabel(whenDateRaw, en) },
              { key: 'time', label: T('Giờ', 'Time'), value: whenTime || '' },
              { key: 'area', label: T('Khu vực', 'Area'), value: areaText },
            ]}
            strip={copy && (
              <WhatsNextStrip key={tCase.key} caseKey={tCase.key} tone={toneColor} solid={tCase.key === 'checkedIn'}
                heading={copy.heading} sub={copy.sub} tail={stripTail?.text} tailTestId={stripTail?.id}
                detail={copy.detail} reduceMotion={reduceMotion}
                link={copy.link && (copy.link.kind === 'directions' ? { ...copy.link, href: directionsUrl } : copy.link)}
                onLink={copy.link ? stripAction[copy.link.kind] : undefined} />
            )}>
            {isPaid && hasNamed ? (
              <TicketStubPager attendees={attendees} qrMode={qrMode} qrLabel={qrLabel} reduceMotion={reduceMotion} onActive={setStubIdx} T={T} />
            ) : isPaid && isGifted ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }} data-testid="confirmed-gifted">
                <span style={{ fontSize: 11, fontWeight: 600, color: ink2 }}>{T('Đã tặng', 'Gifted')}</span>
                <span style={{ fontSize: 17, fontWeight: 600, color: ink, overflowWrap: 'anywhere' }}>{s.booking.recipient_name}</span>
              </div>
            ) : (
              <>
                <TicketQr mode={qrMode} value={s.booking.admission_token || s.booking.id} size={220} pad={10} label={qrLabel} />
                {s.booking.code && (
                  <>
                    <span style={{ marginTop: 16, fontSize: 11, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ink3 }}>{T('Mã vào cửa', 'Entry code')}</span>
                    {/* A locked / void / ended ticket shows a mask, never the real code. */}
                    <span data-testid="confirmed-entry-code" style={{ marginTop: 4, fontSize: 29, fontWeight: 600, letterSpacing: '0.14em', fontFamily: 'ui-monospace, Menlo, monospace', color: ink, opacity: qrShows ? 1 : 0.35, whiteSpace: 'nowrap' }}>
                      {qrShows ? formatEntryCode(s.booking.code) : '••• •••'}
                    </span>
                  </>
                )}
                {qrShows && <span style={{ marginTop: 8, fontSize: 11.5, color: ink2 }}>{T('Đưa mã này ở cửa', 'Show this code at the door')}</span>}
              </>
            )}
          </PaperTicket>
        )}
        {/* Money first: while a hold or an unconfirmed transfer is open, the payment details stay one tap away. */}
        {showPayButton && (
          <button type="button" className="bb-press" onClick={() => openPaymentDetails(s.booking.id, 'confirmed')} data-testid="confirmed-pay"
            style={{ marginTop: 14, width: '100%', boxSizing: 'border-box', minHeight: 52, padding: '10px 18px', border: 'none', borderRadius: 16, background: ink, color: paper, fontFamily: 'inherit', cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, textAlign: 'left' }}>
            <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
              <span style={{ fontSize: 14.5, fontWeight: 600 }}>{T('Xem thông tin chuyển khoản', 'See payment details')}</span>
              <span style={{ fontSize: 11.5, lineHeight: 1.4 }}>{T('Số tài khoản, số tiền và nội dung cần ghi.', 'Account number, amount and the reference to use.')}</span>
            </span>
            <span aria-hidden style={{ fontSize: 17, flex: 'none', lineHeight: 1 }}>›</span>
          </button>
        )}
        {isPaid && giftedSeats.length > 0 && !isGifted && (
          <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="confirmed-gifted-seats">
            {giftedSeats.map(g => (
              <div key={g.id} style={{ ...cardGlass({ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 12 }) }} data-testid={`confirmed-gifted-seat-${g.id}`}>
                <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.65 }}>{T('Đã tặng', 'Gifted')}</span>
                  <span style={{ fontSize: 14, fontWeight: 600, color: ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{g.recipient_name}</span>
                </div>
                <span onClick={() => runDownload([giftPdfOf(g)])} title={T('Tải lại vé PDF', 'Re-download the PDF')} data-testid={`confirmed-gifted-seat-download-${g.id}`}
                  style={{ flex: 'none', width: 34, height: 34, borderRadius: 17, background: 'var(--bb-field)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: pdfBusy ? 0.5 : 1 }}>
                  <Icon kind="download" size={16} />
                </span>
              </div>
            ))}
          </div>
        )}
        <div style={{ height: 20, flex: 'none' }} />
      </div>
      {/* Note 77: the ticket's actions as two tiles (the most used ones) and a "More" menu for the rest. No hairlines:
          the block fills and the gaps separate them. iOS twin: ConfirmedView `actionTile`. */}
      <div style={{ padding: '8px 22px 0', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'stretch' }}>
          {actionable && isGifted && (
            <ActionTile icon={<Icon kind="download" size={17} />} label={pdfBusy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải lại vé PDF', 'Re-download the PDF')} onClick={() => runDownload([giftPdfOf(s.booking)])} testId="confirmed-gifted-pdf" />
          )}
          {actionable && hasNamed && curAttendee && (
            <ActionTile icon={<Icon kind="download" size={17} />} label={pdfBusy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải vé này', 'Download this ticket')} onClick={() => runDownload([attendeePdf(curAttendee)])} testId="confirmed-download-current" />
          )}
          {walletPrimary && (
            <ActionTile icon={<Icon kind="wallet" size={17} />} label={walletBusy ? T('Đang tạo vé Wallet…', 'Preparing Wallet pass…') : T('Thêm vào Apple Wallet', 'Add to Apple Wallet')} onClick={runWallet} dim={walletBusy} testId="confirmed-add-to-wallet" />
          )}
          {actionable && !hasNamed && !isGifted && !walletPrimary && (
            <ActionTile icon={<Icon kind="download" size={17} />} label={pdfLabel} onClick={() => runDownload([ownPdf()])} testId="confirmed-download-pdf" />
          )}
          {receiptReady && (
            <ActionTile icon={<Icon kind="doc" size={17} />} label={receiptItem.label} onClick={receiptItem.disabled ? undefined : receiptItem.onClick} dim={receiptItem.disabled} testId="confirmed-view-receipt" />
          )}
          {/* Add to calendar: a glass popover that opens out of the tile and closes on a tap anywhere outside it. */}
          {showCal && <div style={{ position: 'relative', flex: 1, minWidth: 0, display: 'flex' }}>
            <ActionTile icon={<MiniCalendarPage day={calBlock?.day} month={calBlock?.weekday} size={36} done={!!s.calAdded} fixedLight />} bare
              label={calendarLabel} onClick={openCalendarPicker} testId="confirmed-add-to-calendar" />
            {s.calendarPickerFor === ev.key && (
              <>
                <div onClick={closeCalendarPicker} style={{ position: 'fixed', inset: 0, zIndex: 49 }} data-testid="calendar-pick-scrim" />
                <div role="menu" style={{ position: 'absolute', right: 0, width: 260, bottom: 'calc(100% + 6px)', zIndex: 50, transformOrigin: 'bottom right', animation: 'bbPopIn 0.2s cubic-bezier(.22,.61,.36,1) both', borderRadius: 22, padding: 8, overflow: 'hidden', ...glassMenuSurface }}>
                  <div role="menuitem" onClick={() => addToCalendarGoogle(ev)} data-testid="calendar-pick-google"
                       style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', borderRadius: 16, cursor: 'pointer', fontSize: 14, color: ink }}>
                    <Icon kind="globe" size={18} /> Google Calendar
                  </div>
                  <div role="menuitem" onClick={() => addToCalendarICS(ev)} data-testid="calendar-pick-apple"
                       style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', borderRadius: 16, cursor: 'pointer', fontSize: 14, color: ink }}>
                    <Icon kind="calendar" size={18} />
                    <span>{T('Lịch Apple ▪︎ Ứng dụng khác', 'Apple Calendar ▪︎ Other apps')}
                      <span style={{ display: 'block', fontSize: 11, opacity: 0.6, marginTop: 2 }}>{T('Tải file .ics', 'Downloads an .ics file')}</span>
                    </span>
                  </div>
                </div>
              </>
            )}
          </div>}
        </div>
        {moreItems.length > 0 && (
          <GlassMenu open={moreOpen} onOpenChange={setMoreOpen} top={52} width={280} wrapTestId="confirmed-more" menuTestId="confirmed-more-menu"
            trigger={(
              <button type="button" className="bb-press" onClick={() => setMoreOpen(v => !v)} aria-haspopup="menu" aria-expanded={moreOpen} data-testid="confirmed-more-button"
                style={{ width: '100%', minHeight: 44, borderRadius: 999, border: 'none', background: block, color: ink, fontFamily: 'inherit', fontSize: 14.5, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: 'pointer' }}>
                <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="19" cy="12" r="2" /></svg>
                {T('Thêm tuỳ chọn', 'More options')}
              </button>
            )}>
            {moreItems.map(it => (
              <GlassMenuItem key={it.testId} testId={it.testId} disabled={it.disabled} onClick={() => { setMoreOpen(false); it.onClick?.(); }}>
                <Icon kind={it.icon} size={17} /> {it.label}
              </GlassMenuItem>
            ))}
          </GlassMenu>
        )}
        {[walletMsg && showQr && !hasNamed && !isGifted && walletEligible ? walletMsg : '', s.receiptRequestError].filter(Boolean).map(m => (
          <p key={m} style={{ fontSize: 11, color: alert, textAlign: 'center', margin: 0 }}>{m}</p>
        ))}
      </div>
      {/* Note 78: the policy paragraph is unchanged and only collapsed. Hidden for an expired hold, as before (the strip explains it). */}
      {s.booking && !isExpired && (
        <div style={{ padding: '6px 22px 0', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <button type="button" onClick={() => setPolicyOpen(v => !v)} aria-expanded={policyOpen} aria-controls="confirmed-policy" data-testid="confirmed-policy-toggle"
            style={{ minHeight: 44, display: 'inline-flex', alignItems: 'center', gap: 6, padding: '0 8px', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, color: ink2, cursor: 'pointer' }}>
            {T('Về tiền và hoàn tiền', 'About money and refunds')}
            <svg aria-hidden width="8" height="14" viewBox="0 0 8 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
              style={{ transform: policyOpen ? 'rotate(90deg)' : 'none', transition: reduceMotion ? 'none' : 'transform .2s' }}><path d="M1.5 1.5 6.5 7l-5 5.5" /></svg>
          </button>
          {policyOpen && <p id="confirmed-policy" data-testid="confirmed-policy-text" style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '4px 0 0' }}>{policyNote}</p>}
        </div>
      )}
      <div style={{ height: 34 }} />
      {detailsOpen && (
        <EventDetailsSheet
          title={ev.name} cover={ev.img || null} reduceMotion={reduceMotion} returnFocusTo={detailsOpener.current} T={T}
          tiles={[
            { key: 'date', label: T('Ngày', 'Date'), value: dateTileLabel(whenDateRaw, en) },
            { key: 'time', label: T('Giờ', 'Time'), value: whenTime || '' },
            { key: 'place', label: T('Địa điểm', 'Place'), value: areaText },
          ]}
          about={detailsAbout} included={detailsIncluded} orgName={ev.orgName || ''}
          place={hostNote.address || areaText} hostNote={noteText} distance={detailsDistance} directionsUrl={directionsUrl}
          policyNote={isExpired ? '' : policyNote} over={eventOver}
          onMessage={() => { setDetailsOpen(false); openChatFor(ev.key, 'confirmed'); }}
          onOpenEvent={() => { setDetailsOpen(false); goEvent(ev.key); }}
          onClose={() => setDetailsOpen(false)}
        />
      )}
      {giftOpen && s.booking?.id && (
        <GiftTicketSheet
          bookingId={s.booking.id} seats={s.booking.qty || 1} eventName={ev.name} pdfBase={pdfBase}
          onGifted={onGifted} onClose={() => setGiftOpen(false)}
        />
      )}
    </div>
  );
}

// One action tile (note 77): the icon on a soft clay disc (or the mini calendar page), the label under it. Equal
// height side by side; a block fill instead of divider lines.
function ActionTile({ icon, label, onClick, testId, dim = false, bare = false }) {
  return (
    <button type="button" className="bb-press" onClick={onClick} data-testid={testId}
      style={{ flex: 1, minWidth: 0, minHeight: 56, boxSizing: 'border-box', padding: '10px 12px', border: 'none', borderRadius: 16, background: block, color: ink,
        fontFamily: 'inherit', fontSize: 14, fontWeight: 600, lineHeight: 1.25, textAlign: 'left', display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 10,
        cursor: onClick ? 'pointer' : 'default', opacity: dim ? 0.6 : 1 }}>
      {bare ? icon : (
        <span style={{ flex: 'none', width: 36, height: 36, borderRadius: 18, display: 'flex', alignItems: 'center', justifyContent: 'center', background: clayBg, color: clay }}>{icon}</span>
      )}
      <span>{label}</span>
    </button>
  );
}

const ICON_PATHS = {
  gift: <><rect x="3" y="9" width="18" height="12" rx="2" /><path d="M12 9v12M3 13h18M12 9c-2.5 0-4.5-1-4.5-3S9.5 3 12 6c2.5-3 4.5-1 4.5 0S14.5 9 12 9Z" /></>,
  download: <><path d="M6 3h9l4 4v14H6z" /><path d="M12 10v6m0 0-2.5-2.5M12 16l2.5-2.5" /></>,
  calendar: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>,
  calendarPlus: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4M12 13v5M9.5 15.5h5" /></>,
  calendarCheck: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4M9.5 15l2 2 3.5-3.5" /></>,
  globe: <><circle cx="12" cy="12" r="8.5" /><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.5 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.5-3.5-8.5s1-6 3.5-8.5Z" /></>,
  wallet: <><rect x="3" y="6" width="18" height="13" rx="2.5" /><path d="M3 10h18M16.5 14.5h.01" /></>,
  doc: <><path d="M6 3h9l4 4v14H6z" /><path d="M9 12h7M9 16h7" /></>,
};
function Icon({ kind, size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {ICON_PATHS[kind]}
    </svg>
  );
}
