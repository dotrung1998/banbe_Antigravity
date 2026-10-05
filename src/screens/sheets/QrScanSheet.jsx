import { useEffect, useRef, useState } from 'react';
import jsQR from 'jsqr';
import { useGoc } from '../../state/GocContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { paper, ink, rule, alert, cardGlass } from '../../theme.js';

// Web port of apps/ios/BanbeApp/Views/QRScannerView.swift: a card-based
// pop-up (camera on top, result + Confirm / Not now below) instead of the old
// full-screen camera.
//
// Flow: decode -> get_checkin_guest_info(code) (name, age, already-checked-in)
// -> host taps Confirm -> check_in_guest(code, 'scan').
//
// What a ticket QR encodes: since migration 151 each attendee's PDF carries
// that attendee's own admission_token (admits ONE person); older bookings carry
// the booking's admission_token / id. Both RPCs resolve either, so the decoded
// string is passed through untouched (after a UUID shape check).
//
// Privacy: get_checkin_guest_info returns the date of birth so door staff can
// verify age. It is turned into an AGE immediately and never stored in state,
// logged, or persisted — only the age is kept.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GREEN = '#21944f';

function ageFromIso(iso) {
  if (typeof iso !== 'string') return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const now = new Date();
  let age = now.getFullYear() - y;
  if (now.getMonth() + 1 < mo || (now.getMonth() + 1 === mo && now.getDate() < d)) age -= 1;
  return age >= 0 && age < 150 ? age : null;
}

export default function QrScanSheet() {
  const { T, closeQrScan, state, loadAttendanceGuests } = useGoc();
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const streamRef = useRef(null);
  const rafRef = useRef(null);
  const busyRef = useRef(false);          // true while a guest is pending / a call is in flight
  const lastRef = useRef({ code: '', at: 0 });
  const clearTimerRef = useRef(null);
  const eventKeyRef = useRef(state.attendanceEventKey);
  eventKeyRef.current = state.attendanceEventKey;
  const reloadRef = useRef(loadAttendanceGuests);
  reloadRef.current = loadAttendanceGuests;

  const [cameraError, setCameraError] = useState('');
  const [lookingUp, setLookingUp] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [guest, setGuest] = useState(null);       // { code, bookingId, attendeeId, name, age, alreadyCheckedIn }
  const [okMessage, setOkMessage] = useState('');
  const [errMessage, setErrMessage] = useState('');

  const clearSoon = (ms) => {
    clearTimeout(clearTimerRef.current);
    clearTimerRef.current = setTimeout(() => { setOkMessage(''); setErrMessage(''); }, ms);
  };

  // ---- bilingual error strings ----
  const lookupError = (code) => {
    switch (code) {
      case 'RATE_LIMITED': return T('Bạn đã tra cứu quá nhiều. Thử lại sau.', 'Too many lookups. Try again later.');
      case 'NOT_ELIGIBLE': return T('Vé này chưa được xác nhận hoặc không còn hiệu lực.', "This ticket isn't confirmed or is no longer valid.");
      case 'CREDENTIAL_INVALIDATED': return T('Mã QR này đã bị thay thế (vé đã được tặng). Hãy quét mã mới.', 'This QR was replaced (the ticket was gifted). Scan the new one.');
      case 'AUTH_REQUIRED': return T('Hãy đăng nhập lại.', 'Please sign in again.');
      case 'GATE_REQUIRED': return T('Tài khoản của bạn cần hoàn tất bước xác nhận trước.', 'Your account needs to finish its sign-up checks first.');
      case 'NETWORK': return T('Không có kết nối. Thử quét lại.', 'No connection. Try scanning again.');
      case 'WRONG_EVENT': return T('Vé này không thuộc sự kiện đang điểm danh.', "This ticket isn't for the event you're checking in.");
      case 'NOT_QR': return T('Đây không phải mã vé banbe.', "That isn't a banbe ticket code.");
      default: return T('Mã không hợp lệ hoặc không phải khách của sự kiện này.', 'Invalid code, or not a guest of this event.');
    }
  };
  const checkInError = (raw) => {
    const e = String(raw || '');
    if (e === "Scan each attendee's own QR") return T('Vé có nhiều người: hãy quét mã QR riêng của từng khách.', "This booking has named attendees — scan each attendee's own QR.");
    if (e === 'Guest already checked in') return T('Khách này đã được điểm danh rồi.', 'This guest is already checked in.');
    if (e === 'Credential invalidated') return T('Mã QR này đã bị thay thế (vé đã được tặng). Hãy quét mã mới.', 'This QR was replaced (the ticket was gifted). Scan the new one.');
    if (e === 'Not authorized') return T('Bạn không có quyền điểm danh cho sự kiện này.', "You aren't allowed to check guests in for this event.");
    if (e === 'Booking not found') return T('Không tìm thấy vé này.', 'Ticket not found.');
    if (e === 'Booking is not eligible for check-in') return T('Vé này chưa được xác nhận hoặc không còn hiệu lực.', "This ticket isn't confirmed or is no longer valid.");
    if (/rate|too many|429/i.test(e)) return T('Bạn thao tác quá nhiều. Thử lại sau.', 'Too many attempts. Try again later.');
    return T('Chưa điểm danh được. Mã không hợp lệ hoặc khách đã được điểm danh.', "Couldn't check in. Invalid code, or already checked in.");
  };

  async function lookup(code) {
    if (!UUID_RE.test(code.trim())) return { error: 'NOT_QR' };
    const id = code.trim();
    let data; let error;
    try {
      ({ data, error } = await supabase.rpc('get_checkin_guest_info', { p_booking_id: id }));
    } catch { return { error: 'NETWORK' }; }
    if (error) {
      // Migration 125/151 not deployed: no guest info available.
      return { error: /could not find the function/i.test(error.message || '') ? 'NOT_FOUND' : 'NETWORK' };
    }
    if (!data?.success) return { error: data?.error || 'NOT_FOUND' };
    // Wrong-event guard: the RPC admits any event this host runs, so compare
    // the booking's event with the one whose door this is (hosts can read
    // their own events' bookings).
    const evKey = eventKeyRef.current;
    if (evKey && data.booking_id) {
      const { data: b } = await supabase.from('bookings').select('event_id').eq('id', data.booking_id).maybeSingle();
      if (b?.event_id && b.event_id !== evKey) return { error: 'WRONG_EVENT' };
    }
    return {
      info: {
        code: id,
        bookingId: data.booking_id || null,
        attendeeId: data.attendee_id || null,
        name: data.name || '',
        age: ageFromIso(data.date_of_birth), // DOB deliberately dropped here
        alreadyCheckedIn: data.already_checked_in === true || (!data.attendee_id && data.status === 'attended'),
      },
    };
  }

  async function handleDecoded(code) {
    const now = Date.now();
    if (code === lastRef.current.code && now - lastRef.current.at < 3000) return;
    busyRef.current = true;
    clearTimeout(clearTimerRef.current);
    setOkMessage(''); setErrMessage('');
    setLookingUp(true);
    const res = await lookup(code);
    setLookingUp(false);
    lastRef.current = { code, at: Date.now() };
    if (res.info) {
      setGuest(res.info);              // stays busy until Confirm / Not now
    } else {
      setErrMessage(lookupError(res.error));
      clearSoon(2500);
      busyRef.current = false;
    }
  }

  const confirm = async () => {
    const g = guest;
    if (!g || g.alreadyCheckedIn || confirming) return;
    setConfirming(true);
    let data; let error;
    try {
      ({ data, error } = await supabase.rpc('check_in_guest', { p_reservation_id: g.code, p_source: 'scan' }));
    } catch { error = { message: 'network' }; }
    setConfirming(false);
    setGuest(null);
    lastRef.current = { code: g.code, at: Date.now() };
    if (error || !data?.success) {
      setErrMessage(checkInError(data?.error || error?.message));
      clearSoon(3500);
    } else {
      const name = g.name || data.name || T('Khách', 'Guest');
      setOkMessage(T(`✓ Đã điểm danh · ${name}`, `✓ Checked in · ${name}`));
      clearSoon(3500);
      if (eventKeyRef.current) reloadRef.current(eventKeyRef.current);
      // Whole-booking QR only: the booking-level email/notification fires once on
      // the first person through; an attendee QR must not re-send it per person.
      if (!g.attendeeId && (data.booking_id || g.bookingId)) {
        supabase.auth.getSession().then(({ data: sd }) => {
          const token = sd?.session?.access_token;
          if (token) {
            fetch('/api/notify', {
              method: 'POST',
              headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
              body: JSON.stringify({ type: 'check_in', bookingId: data.booking_id || g.bookingId }),
            }).catch(() => {});
          }
        }).catch(() => {});
      }
    }
    busyRef.current = false;
  };

  const notNow = () => {
    if (confirming) return;
    setGuest(null);
    lastRef.current = { code: guest?.code || '', at: Date.now() };
    busyRef.current = false;
  };
  const close = () => { if (!confirming) closeQrScan(); };

  useEffect(() => {
    let cancelled = false;

    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setCameraError(T('Trình duyệt này không hỗ trợ camera.', 'This browser does not support camera access.'));
        return;
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
        if (cancelled) { stream.getTracks().forEach(t => t.stop()); return; }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play().catch(() => {});
        }
        tick();
      } catch {
        if (!cancelled) setCameraError(T('Không thể mở camera. Hãy cho phép quyền truy cập camera.', 'Could not open the camera. Please allow camera access.'));
      }
    }

    function tick() {
      const video = videoRef.current;
      const canvas = canvasRef.current;
      if (!video || !canvas || video.readyState !== video.HAVE_ENOUGH_DATA || busyRef.current) {
        rafRef.current = requestAnimationFrame(tick);
        return;
      }
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      const frame = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const code = jsQR(frame.data, frame.width, frame.height);
      if (code?.data && !busyRef.current) handleDecoded(code.data);
      rafRef.current = requestAnimationFrame(tick);
    }

    start();
    return () => {
      cancelled = true;
      clearTimeout(clearTimerRef.current);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      streamRef.current?.getTracks().forEach(t => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const canConfirm = !!guest && !guest.alreadyCheckedIn && !confirming;
  const canDismiss = !!guest && !confirming;

  let message;
  if (okMessage) {
    message = <div data-testid="scanner-success" style={{ background: GREEN, color: '#fff', borderRadius: 12, padding: '12px 12px', fontSize: 14.5, fontWeight: 600, textAlign: 'center' }}>{okMessage}</div>;
  } else if (errMessage) {
    message = <div data-testid="scanner-error" role="alert" style={{ color: alert, fontSize: 13.5, fontWeight: 600, textAlign: 'center' }}>{errMessage}</div>;
  } else if (guest) {
    message = (
      <div data-testid="scanner-guest" style={{ textAlign: 'center', color: ink, display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{ fontSize: 17, fontWeight: 700 }}>{guest.name || T('Khách', 'Guest')}</span>
        <span style={{ fontSize: 14 }} data-testid="scanner-guest-age">
          {guest.age != null ? T(`${guest.age} tuổi`, `Age ${guest.age}`) : T('Chưa có ngày sinh trong hồ sơ', 'No date of birth on file')}
        </span>
        {guest.attendeeId && <span style={{ fontSize: 11.5, opacity: 0.65 }}>{T('Vé cá nhân (1 người)', 'Individual ticket (1 person)')}</span>}
        {guest.alreadyCheckedIn && <span style={{ fontSize: 12.5, color: alert }}>{T('Khách này đã được điểm danh.', 'This guest is already checked in.')}</span>}
      </div>
    );
  } else if (lookingUp) {
    message = <span style={{ fontSize: 14, color: ink }}>{T('Đang kiểm tra vé…', 'Checking ticket…')}</span>;
  } else {
    message = <span data-testid="scanner-instruction" style={{ fontSize: 14.5, fontWeight: 500, color: ink, textAlign: 'center' }}>{T('Đưa mã QR của khách lên để quét', "Hold up and scan the goer's QR code")}</span>;
  }

  return (
    <div
      onClick={close}
      data-testid="qr-scan-sheet"
      style={{ position: 'absolute', inset: 0, zIndex: 22, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{ ...cardGlass({ padding: 0, overflow: 'hidden' }), background: paper, width: '100%', maxWidth: 380, maxHeight: '100%', borderRadius: 26, display: 'flex', flexDirection: 'column', boxShadow: '0 12px 44px rgba(0,0,0,0.28)' }}
      >
        <div style={{ position: 'relative', background: '#000', aspectRatio: '3 / 4', maxHeight: '58vh', width: '100%' }}>
          <video ref={videoRef} muted playsInline style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
          <canvas ref={canvasRef} style={{ display: 'none' }} />
          <div style={{ position: 'absolute', left: '50%', top: '50%', width: '62%', aspectRatio: '1 / 1', transform: 'translate(-50%, -50%)', borderRadius: 22, border: `2px solid rgba(255,255,255,${guest ? 0.25 : 0.75})`, pointerEvents: 'none' }} />
          <div
            onClick={close}
            role="button"
            aria-label={T('Đóng', 'Close')}
            data-testid="scanner-close"
            style={{ position: 'absolute', top: 8, right: 8, width: 38, height: 38, borderRadius: '50%', background: paper, color: ink, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 600, cursor: 'pointer' }}
          >✕</div>
          {cameraError && (
            <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 30, background: 'rgba(0,0,0,0.7)' }}>
              <p style={{ color: '#fff', fontSize: 14, lineHeight: 1.6, textAlign: 'center', margin: 0 }}>{cameraError}</p>
            </div>
          )}
        </div>

        <div style={{ padding: '14px 18px 18px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ minHeight: 58, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>{message}</div>
          <div style={{ display: 'flex', gap: 10 }}>
            <div
              onClick={canConfirm ? confirm : undefined}
              data-testid="qrscan-confirm-checkin"
              aria-disabled={!canConfirm}
              style={{ flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 600, padding: '13px 12px', borderRadius: 14, background: ink, color: paper, cursor: canConfirm ? 'pointer' : 'default', opacity: canConfirm ? 1 : 0.35 }}
            >
              {confirming ? T('Đang xác nhận…', 'Confirming…') : T('Xác nhận', 'Confirm')}
            </div>
            <div
              onClick={canDismiss ? notNow : undefined}
              data-testid="qrscan-cancel-checkin"
              aria-disabled={!canDismiss}
              style={{ flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 600, padding: '13px 12px', borderRadius: 14, border: `1px solid ${rule}`, color: ink, cursor: canDismiss ? 'pointer' : 'default', opacity: canDismiss ? 1 : 0.35 }}
            >
              {T('Để sau', 'Not now')}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
