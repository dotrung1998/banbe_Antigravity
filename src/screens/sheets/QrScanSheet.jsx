import { useEffect, useRef, useState } from 'react';
import jsQR from 'jsqr';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink } from '../../theme.js';

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

    async function handleDecoded(bookingId) {
      busyRef.current = true;
      const result = await checkInByScan(bookingId);
      setStatus(result.success
        ? { ok: true, message: T('Đã điểm danh ✓', 'Checked in ✓') }
        : { ok: false, message: T('Mã không hợp lệ hoặc đã điểm danh rồi.', 'Invalid code, or already checked in.') });
      // Brief pause so the same code isn't re-scanned a dozen times a second
      // while it's still in frame, then clear the flash and resume scanning.
      setTimeout(() => { busyRef.current = false; setStatus(null); }, 1800);
    }

    start();
    return () => {
      cancelled = true;
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      streamRef.current?.getTracks().forEach(t => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
        <div style={{ position: 'absolute', left: 20, right: 20, bottom: 30, padding: '14px 18px', borderRadius: 14, textAlign: 'center', fontSize: 14, fontWeight: 600, background: status.ok ? ink : '#9A3E2D', color: paper }}>
          {status.message}
        </div>
      )}
    </div>
  );
}
