import { useEffect, useState } from 'react';

// The iPhone-style status bar drawn above the app inside the desktop phone
// frame (hidden everywhere else by index.css). Purely decorative: it takes the
// place of the iOS status bar so each screen sits under a real-looking safe area.
function useClock() {
  const fmt = () => new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const [t, setT] = useState(fmt);
  useEffect(() => {
    const id = setInterval(() => setT(fmt()), 15000);
    return () => clearInterval(id);
  }, []);
  return t;
}

export default function PhoneStatusBar() {
  const time = useClock();
  return (
    <div className="bb-statusbar" aria-hidden="true">
      <span className="bb-statusbar-time">{time}</span>
      <span className="bb-island" />
      <span className="bb-statusbar-icons">
        <svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1" /><rect x="5" y="5.5" width="3" height="6.5" rx="1" /><rect x="10" y="3" width="3" height="9" rx="1" /><rect x="15" y="0" width="3" height="12" rx="1" /></svg>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M1.5 4.2a9.5 9.5 0 0 1 13 0" /><path d="M4 7a6 6 0 0 1 8 0" /><circle cx="8" cy="10" r="1.1" fill="currentColor" stroke="none" /></svg>
        <svg width="26" height="12" viewBox="0 0 26 12" fill="none"><rect x="0.6" y="0.6" width="21.8" height="10.8" rx="3.2" stroke="currentColor" strokeOpacity="0.45" /><rect x="2.2" y="2.2" width="18.6" height="7.6" rx="2" fill="currentColor" /><rect x="23.4" y="4" width="1.8" height="4" rx="0.9" fill="currentColor" fillOpacity="0.45" /></svg>
      </span>
    </div>
  );
}
