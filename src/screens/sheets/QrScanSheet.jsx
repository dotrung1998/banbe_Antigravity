import { useEffect, useRef, useState } from 'react';
import jsQR from 'jsqr';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, alert } from '../../theme.js';

// Full-screen camera scanner for the organizer check-in flow. Reads whatever
// a guest's ticket QR (Confirmed.jsx) encodes — the booking's own id — and
// calls the exact same check_in_guest() RPC the manual tap-to-check-in list
// already uses, so both paths share one authorization/notification path.
export default function QrScanSheet() {
  const { T, closeQrScan, checkInByScan } = useGoc();
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const streamRef = useRef(null);
  const rafRef = useRef(null);
  const busyRef = useRef(false);
  const [cameraError, setCameraError] = useState('');
  const [status, setStatus] = useState(null); // { ok: boolean, message: string } | null
  // 14-organizer-checkin.md (Bug 3): the same confirm-before-check-in step
  // Attendance.jsx's manual tap now requires (reasonPrompt kind
  // 'confirmCheckin') — a decoded QR used to check the guest in instantly,
  // with no chance to catch a misread or an accidental scan. Local state,
  // not the app-wide reasonPrompt: this sheet is already its own full-
  // screen overlay, and resuming the scan loop on cancel is simplest kept
  // entirely inside this component.
  const [pendingBookingId, setPendingBookingId] = useState(null);

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
      if (!video || !canvas || video.readyState !== video.HAVE_ENOUGH_DATA) {
        rafRef.current = requestAnimationFrame(tick);
        return;
      }
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      const frame = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const code = jsQR(frame.data, frame.width, frame.height);
      if (code?.data && !busyRef.current) {
        handleDecoded(code.data);
      }
      rafRef.current = requestAnimationFrame(tick);
    }

    function handleDecoded(bookingId) {
      // Bug 3: pauses the scan loop (busyRef already true) and waits for an
      // explicit yes/no instead of checking the guest in the instant a code
      // is decoded — see the confirm/cancel handlers below.
      busyRef.current = true;
      setPendingBookingId(bookingId);
    }

    start();
    return () => {
      cancelled = true;
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      streamRef.current?.getTracks().forEach(t => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const confirmPendingCheckin = async () => {
    const bookingId = pendingBookingId;
    setPendingBookingId(null);
    const result = await checkInByScan(bookingId);
    setStatus(result.success
      ? { ok: true, message: T('Đã điểm danh ✓', 'Checked in ✓') }
      : { ok: false, message: T('Mã không hợp lệ hoặc đã điểm danh rồi.', 'Invalid code, or already checked in.') });
    // Brief pause so the same code isn't re-scanned a dozen times a second
    // while it's still in frame, then clear the flash and resume scanning.
    setTimeout(() => { busyRef.current = false; setStatus(null); }, 1800);
  };
  const cancelPendingCheckin = () => {
    setPendingBookingId(null);
    busyRef.current = false;
  };

  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 22, background: '#000', display: 'flex', flexDirection: 'column' }}>
      <video ref={videoRef} muted playsInline style={{ flex: 1, width: '100%', objectFit: 'cover', background: '#000' }} />
      <canvas ref={canvasRef} style={{ display: 'none' }} />

      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, padding: '20px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 13, color: paper, fontWeight: 600 }}>{T('Quét mã QR của khách', "Scan a guest's QR")}</span>
        <span onClick={closeQrScan} style={{ fontSize: 13, color: paper, cursor: 'pointer', padding: '8px 12px', background: 'rgba(255,255,255,0.15)', borderRadius: 999 }}>{T('Đóng', 'Close')}</span>
      </div>

      {cameraError && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 40 }}>
          <p style={{ color: paper, fontSize: 14, lineHeight: 1.6, textAlign: 'center' }}>{cameraError}</p>
        </div>
      )}

      {status && (
        <div style={{ position: 'absolute', left: 20, right: 20, bottom: 30, padding: '14px 18px', borderRadius: 14, textAlign: 'center', fontSize: 14, fontWeight: 600, background: status.ok ? ink : alert, color: paper }}>
          {status.message}
        </div>
      )}

      {/* Bug 3 (14-organizer-checkin.md): confirm before actually marking
          this guest arrived — mirrors Attendance.jsx's own manual-tap
          confirm step, kept local to this sheet rather than the app-wide
          reasonPrompt (see the `pendingBookingId` state comment above). */}
      {pendingBookingId && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 1, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <div style={{ background: paper, borderRadius: 16, padding: '22px 20px', maxWidth: 320, width: '100%' }}>
            <p style={{ fontSize: 14.5, fontWeight: 600, color: ink, margin: 0, lineHeight: 1.5 }}>
              {T('Bạn có chắc muốn xác nhận khách này đã tới?', 'Are you sure you want to check this guest in?')}
            </p>
            <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
              <div onClick={confirmPendingCheckin} data-testid="qrscan-confirm-checkin"
                   style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px', borderRadius: 12, cursor: 'pointer', background: ink, color: paper }}>
                {T('Xác nhận', 'Confirm')}
              </div>
              <div onClick={cancelPendingCheckin} data-testid="qrscan-cancel-checkin"
                   style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px', borderRadius: 12, cursor: 'pointer', border: '1px solid rgba(27,25,22,0.16)', color: ink }}>
                {T('Để sau', 'Not now')}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
