import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { paper, ink, rule, display, cardGlass, inkButton } from '../theme.js';

export default function Organizer() {
  const { state, T, trStatus, stripKm, curEvent: ev, backToEvent, goEvent, goChat, toggleFollow, openPhoto } = useGoc();
  const s = state;

  const evOrgStats = T('Tổ chức từ ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' sự kiện', 'Hosting since ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' events');
  const following = s.following.includes(ev.key);
  const orgEvents = EVENTS.filter(e => e.orgName === ev.orgName && !e.cancelled && e.endedHoursAgo == null);

  return (
    <div style={{ animation: 'gocFade 0.3s ease both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Organizer">
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div onClick={backToEvent} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {ev.name}</div>
      {s.arrivedFromSharedLink && (
        // Only shown to someone who followed a shared "?org=" link. The
        // banbe:// scheme opens the installed app straight to this page;
        // there's no App Store listing to fall back to yet, so the second
        // line points at the web app someone is already looking at rather
        // than at a link that would 404.
        <div style={{ ...cardGlass({ margin: '14px 22px 0', padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 13, color: ink }}>{T('Xem trong ứng dụng banbe', 'Open in the banbe app')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Chưa có ứng dụng? Bạn vẫn xem được mọi thứ ngay tại đây.', "Don't have it? Everything here works in the browser too.")}</span>
          </div>
          <a
            href={`banbe://organizer/${ev.key}`}
            style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 16px', textDecoration: 'none' }}
          >{T('Mở', 'Open')}</a>
        </div>
      )}
      <div style={{ padding: '16px 22px 30px' }}>
        <span style={{ fontSize: 11.5, color: ink }}>{T('Người tổ chức', 'Organizer')}</span>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 8 }}>
          <h1 style={{ ...display(29, { lineHeight: 1.2, margin: 0 }) }}>{ev.orgName}</h1>
          {ev.orgTrusted && (
            <span style={{ fontSize: 13, fontWeight: 500, color: ink, whiteSpace: 'nowrap' }}>{T('Tổ chức lâu năm', 'Established host')}</span>
          )}
        </div>
        {ev.orgTrusted && <div style={{ fontSize: 12, color: ink, marginTop: 4 }}>{evOrgStats}</div>}
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', marginTop: 10 }}>
          <a href={'https://instagram.com/' + (ev.orgIg || '').replace('@', '')} target="_blank" rel="noopener" style={{ fontSize: 13, color: ink, textDecoration: 'none' }}>{ev.orgIg}</a>
          <span
            onClick={() => toggleFollow(ev.key)}
            style={{ fontSize: 12, fontWeight: 600, cursor: 'pointer', padding: '7px 14px', borderRadius: 999, border: following ? '1px solid transparent' : `1px solid ${rule}`, color: ink, background: 'transparent' }}
          >
            {following ? T('Đang theo dõi ▪︎ sẽ báo sự kiện mới', 'Following ▪︎ new events by email') : T('Theo dõi', 'Follow')}
          </span>
        </div>
        <p style={{ fontSize: 14, lineHeight: 1.555, color: ink, margin: '16px 0 0' }}>{ev.orgDesc}</p>
        <div style={{ marginTop: 26 }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện đang mở', 'Current events')}</span>
          <div style={{ display: 'flex', flexDirection: 'column', marginTop: 6 }}>
            {orgEvents.map((e, i, arr) => (
              <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '12px 0', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                <div style={bg(e.img, { flex: 'none', width: 52, height: 52 })} />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                  <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                  <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 30 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Ảnh của', 'Photos by')} {ev.orgName}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('do người tổ chức đăng', 'posted by the organizer')}</span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginTop: 14 }}>
          {ev.orgGallery.map((u, i) => (
            <div key={i} onClick={() => openPhoto(ev.orgGallery, i, ev.orgName, ev.key)} style={bg(u, { width: '100%', height: 158, cursor: 'pointer' })} />
          ))}
        </div>
      </div>
      </div>
      <div onClick={goChat} style={{ ...inkButton({ flex: 'none', margin: '0 20px 22px', padding: '15px 0' }) }}>
        {T('Nhắn cho', 'Message')} {ev.hostShort}
      </div>
    </div>
  );
}
