import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import BanbeLoadingVisual from '../../screens/BanbeLoadingVisual.jsx';

// The real admission QR (moved unchanged from Confirmed.jsx, note 78; `pad` is new so the paper ticket can draw it at 200px).
// QRCode.toDataURL is async, so for one tick `src` is null and the shared Banbe loading visual shows instead of a blank box.
export default function QrCode({ value, size = 76, pad = 6, testId }) {
  const [src, setSrc] = useState(null);
  useEffect(() => {
    let active = true;
    QRCode.toDataURL(value, { margin: 1, width: Math.max(152, size * 2), color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => { if (active) setSrc(url); })
      .catch(() => {});
    return () => { active = false; };
  }, [value]);
  return (
    <div data-testid={testId} style={{ flex: 'none', width: size, height: size, background: '#FFFFFF', padding: pad, boxSizing: 'border-box', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {src ? <img src={src} alt="QR" style={{ width: '100%', height: '100%', display: 'block' }} /> : <BanbeLoadingVisual size={40} />}
    </div>
  );
}
