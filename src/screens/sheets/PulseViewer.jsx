import { useGoc } from '../../state/GocContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { paper, ink, rule, display, cardGlass } from '../../theme.js';

function eventPhotoUrl(path) {
  if (!path) return null;
  const relative = path.replace(/^event-photos\//, '');
  return supabase.storage.from('event-photos').getPublicUrl(relative).data.publicUrl;
}

// TASK E (2026-10-01 UX foundation pass) — Banbe Pulse: two tabs ("Hôm
// nay"/"Tuần này") of ranked public event/organizer cards. Tapping an
// unfollowed organizer's identity opens a compact sheet with a Follow CTA
// (never navigates away immediately — rule E8); tapping the event card
// itself navigates straight to the event page.
export default function PulseViewer() {
  const { state, T, closePulseViewer, setPulseTab, openPulseOrganizerSheet, closePulseOrganizerSheet, followPulseOrganizer, goEvent } = useGoc();
  const s = state;
  if (!s.pulseOpen) return null;
  const items = s.pulseTab === 'weekly' ? s.pulseWeekly : s.pulseDaily;

  return (
    <div style={{ position: 'fixed', inset: 0, background: paper, zIndex: 60, display: 'flex', flexDirection: 'column' }} data-testid="pulse-viewer">
      <div style={{ padding: '20px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ ...display(20) }}>{T('Banbe Pulse', 'Banbe Pulse')}</span>
        <span onClick={closePulseViewer} data-testid="pulse-close" style={{ fontSize: 22, color: ink, cursor: 'pointer' }}>×</span>
      </div>

      <div style={{ display: 'flex', gap: 8, padding: '16px 20px 0' }}>
        {[{ key: 'daily', vi: 'Hôm nay', en: 'Today' }, { key: 'weekly', vi: 'Tuần này', en: 'This week' }].map(tab => (
          <span
            key={tab.key}
            onClick={() => setPulseTab(tab.key)}
            data-testid={`pulse-tab-${tab.key}`}
            style={{
              fontSize: 12.5, fontWeight: 600, padding: '9px 16px', borderRadius: 999, cursor: 'pointer',
              background: s.pulseTab === tab.key ? ink : 'transparent',
              color: s.pulseTab === tab.key ? paper : ink,
              border: s.pulseTab === tab.key ? 'none' : `1px solid ${rule}`,
            }}
          >
            {T(tab.vi, tab.en)}
          </span>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 20px 40px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {!items.length && (
          <p style={{ fontSize: 13, color: ink, opacity: 0.7, textAlign: 'center', marginTop: 60 }}>
            {T('Chưa có dữ liệu xếp hạng.', 'Nothing ranked yet.')}
          </p>
        )}
        {items.map((item, i) => (
          <div key={item.event_id} style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden' }) }} data-testid="pulse-card">
            <div onClick={() => { closePulseViewer(); goEvent(item.event_id); }} style={{ width: 88, height: 88, flex: 'none', cursor: 'pointer', background: `center/cover url(${eventPhotoUrl(item.photo_path)})` }} />
            <div style={{ flex: 1, minWidth: 0, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 11, fontWeight: 700, color: ink, opacity: 0.5 }}>#{i + 1}</span>
                <span onClick={() => { closePulseViewer(); goEvent(item.event_id); }} style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', cursor: 'pointer' }) }}>{item.event_name}</span>
              </div>
              <span
                onClick={() => openPulseOrganizerSheet(item)}
                data-testid="pulse-organizer-identity"
                style={{ fontSize: 11.5, color: ink, opacity: 0.75, cursor: 'pointer' }}
              >
                {item.organizer_name}{item.organizer_verified ? ' ✓' : ''}
              </span>
            </div>
          </div>
        ))}
      </div>

      {s.pulseOrganizerSheet && (
        <div onClick={closePulseOrganizerSheet} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', zIndex: 70 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, width: '100%', borderRadius: '18px 18px 0 0', padding: '20px 22px 34px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2 }} />
            <span style={{ ...display(19), marginTop: 8 }}>{s.pulseOrganizerSheet.organizer_name}</span>
            {s.pulseOrganizerSheet.organizer_verified && (
              <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Đã xác minh', 'Verified')}</span>
            )}
            <div
              onClick={() => followPulseOrganizer(s.pulseOrganizerSheet.organizer_id)}
              data-testid="pulse-follow"
              style={{
                marginTop: 8, fontSize: 13, fontWeight: 600, padding: '10px 28px', borderRadius: 999, cursor: 'pointer',
                background: s.pulseOrganizerSheet.following ? 'transparent' : ink,
                color: s.pulseOrganizerSheet.following ? ink : paper,
                border: s.pulseOrganizerSheet.following ? `1px solid ${rule}` : 'none',
              }}
            >
              {s.pulseOrganizerSheet.following ? T('Đang theo dõi', 'Following') : T('Theo dõi', 'Follow')}
            </div>
            <div
              onClick={() => { closePulseViewer(); goEvent(s.pulseOrganizerSheet.event_id); }}
              style={{ marginTop: 4, fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
            >
              {T('Xem sự kiện', 'View event')}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
