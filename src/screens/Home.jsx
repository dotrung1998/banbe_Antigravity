import { useMemo } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass, CHIP_COLORS, photoChip, lightChip } from '../theme.js';

const FILTER_DEFS = [
  { key: 'all', vi: 'Tất cả', en: 'All' },
  { key: 'supper', vi: 'Supper club', en: 'Supper club' },
  { key: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { key: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { key: 'music', vi: 'Nhạc', en: 'Music' },
];

export default function Home() {
  const {
    state, set, T, trStatus, stripKm, curArea, isSaved, isGoing, toggleFav,
    goProfile, goInbox, openArea, toggleLang, pickFilter, clearFilters,
    openHeld, becomeHost, switchToHost,
  } = useGoc();

  const s = state;
  const hasHosted = s.hasHosted;
  const openSaved = (sv) => set({ screen: sv.toEvent, eventKey: sv.key });
  const heldEv = s.holdDeadline && s.holdDeadline > s.now ? EVENTS.find(e => e.key === s.eventKey) : null;

  const filters = FILTER_DEFS.map(f => ({
    key: f.key,
    label: T(f.vi, f.en),
    style: {
      fontSize: 12.5, cursor: 'pointer', paddingBottom: 6, color: ink,
      fontWeight: s.filter === f.key ? 600 : 400,
      borderBottom: s.filter === f.key ? `2px solid ${ink}` : '2px solid transparent',
    },
  }));

  const demoted = e => (e.cancelled && (e.cancelledHoursAgo == null || e.cancelledHoursAgo >= 2)) ? 1 : 0;
  const feed = useMemo(() => EVENTS
    .filter(e => !e.inviteOnly && (s.filter === 'all' || e.catKey === s.filter || e.cat2Key === s.filter) && curArea.match(e))
    .sort((a, b) => demoted(a) - demoted(b))
    .map(e => {
      let seats = e.seats;
      if (e.cancelled) seats = 'Đã hủy';
      else if (e.soldOut) seats = 'Hết chỗ';
      else if (e.endedHoursAgo != null) seats = e.agoLabel(e.endedHoursAgo);
      else if (e.until != null) seats = e.seats + ' ▪︎ ' + e.untilLabel.replace(/^Còn /, '');
      const saved = isSaved(e.key);
      const going = isGoing(e.key) && !e.cancelled && e.endedHoursAgo == null;
      return {
        ...e,
        metaDisplay: trStatus(e.catDisplay) + ' ▪︎ ' + trStatus(stripKm(e.meta)),
        seatsDisplay: trStatus(seats),
        saved, going,
        goingLabel: trStatus('Đang tham gia' + ((s.tickets[e.key] || 1) > 1 ? ' ▪︎ ' + s.tickets[e.key] + ' vé' : '')),
        saveLabel: saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save'),
      };
    }), [s.filter, s.tickets, curArea, isSaved, isGoing, trStatus, stripKm, T]);

  const heldKey = heldEv ? heldEv.key : null;
  const savedKeys = [...new Set([...s.favorites, ...s.attending, ...s.invited, ...(heldKey ? [heldKey] : [])])];
  const savedList = savedKeys
    .map(k => EVENTS.find(e => e.key === k)).filter(Boolean)
    .filter(e => !(e.endedHoursAgo != null && e.endedHoursAgo > 48))
    .map(e => {
      const nTix = s.tickets[e.key] || 1;
      const tixStr = nTix > 1 ? ' ▪︎ ' + nTix + ' vé' : '';
      const invited = e.inviteOnly && s.invited.includes(e.key);
      let tag, status, chip;
      if (e.cancelled) { tag = 'Đã hủy'; status = 'Đã hoàn tiền'; chip = CHIP_COLORS.cancelled; }
      else if (e.endedHoursAgo != null) { tag = 'Đã diễn ra'; status = e.agoLabel(e.endedHoursAgo); chip = CHIP_COLORS.past; }
      else if (invited && !isGoing(e.key)) { tag = T('Riêng tư', 'Private'); status = T('Chỉ bạn và +1 ▪︎ ', 'Just you + 1 ▪︎ ') + e.untilLabel; chip = CHIP_COLORS.invite; }
      else if (e.key === heldKey) { tag = 'Đang giữ'; status = 'Trả để xác nhận' + tixStr; chip = CHIP_COLORS.hold; }
      else if (isGoing(e.key)) { tag = 'Đã thanh toán'; status = e.untilLabel + tixStr; chip = CHIP_COLORS.going; }
      else { tag = 'Đã lưu'; status = e.untilLabel; chip = CHIP_COLORS.saved; }
      return {
        key: e.key, name: e.name, img: e.img,
        status: trStatus(status), tag: trStatus(tag), chip,
        canRemove: !isGoing(e.key) && e.key !== heldKey && !invited,
        toEvent: e.cancelled ? 'refunded' : 'event',
      };
    });

  const feedEmptyMsg = T(
    'Chưa có buổi nào ở ' + (curArea.key === 'all' ? 'mục này' : curArea.label) + ' tuần này, thử mục khác xem sao!',
    'Nothing in ' + (curArea.key === 'all' ? 'this category' : curArea.label) + ' this week, try another one!'
  );

  const homeHostLinkLabel = hasHosted ? T('Trang tổ chức của bạn', 'Your host page') : T('Dành cho người tổ chức ▪︎ hoàn toàn miễn phí', 'For organizers ▪︎ completely free');
  const homeHostLink = hasHosted ? switchToHost : becomeHost;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Home">
      <div style={{ padding: '70px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <img src="/banbe-wordmark-sm.png" alt="banbe" crossOrigin="anonymous" style={{ width: 126, height: 'auto', display: 'block', margin: '0 0 2px' }} />
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
          <div style={{ display: 'flex', gap: 12, alignItems: 'baseline' }}>
            <span onClick={toggleLang} style={{ fontSize: 11, color: ink, cursor: 'pointer', letterSpacing: '0.06em' }}>{T('English', 'Tiếng Việt')}</span>
            <span onClick={openArea} style={{ fontSize: 11, color: ink, cursor: 'pointer' }}>banbe ▪︎ {curArea.key === 'all' ? 'Sài Gòn' : curArea.label} ▾</span>
          </div>
          <div style={{ display: 'flex', gap: 14, alignItems: 'baseline' }}>
            {!!s.user && <span onClick={goInbox} style={{ fontSize: 12, color: ink, cursor: 'pointer', borderBottom: `1px solid ${ink}`, paddingBottom: 2 }}>Tin nhắn</span>}
            <span onClick={goProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer', borderBottom: `1px solid ${ink}`, paddingBottom: 2 }}>{T('Tài khoản', 'Account')}</span>
          </div>
        </div>
      </div>

      {!!heldEv && (
        <div onClick={openHeld} style={{ ...fieldGlass({ margin: '14px 20px 0', padding: '12px 14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>Đang giữ chỗ</span>
            <span style={{ fontSize: 12.5, lineHeight: 1.4, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {heldEv.name}{s.qty > 1 ? ' ▪︎ ' + s.qty + T(' vé', ' tix') : ''}{T(' ▪︎ trả để xác nhận', ' ▪︎ pay to confirm')}
            </span>
          </div>
          <Countdown deadline={s.holdDeadline} now={s.now} />
        </div>
      )}

      {savedList.length > 0 && (
        <div style={{ padding: '16px 20px 4px', borderBottom: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <span style={{ ...display(15) }}>{T('Sự kiện của bạn', 'Your events')}</span>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Tự xóa sau 48 giờ', 'Clears after 48h')}</span>
          </div>
          <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 6 }}>
            {savedList.map(sv => (
              <div key={sv.key} onClick={() => openSaved(sv)} style={{ flex: 'none', width: 152, cursor: 'pointer' }}>
                <div style={{ position: 'relative' }}>
                  <div style={bg(sv.img, { width: 152, height: 96, borderRadius: 12, filter: 'none' })} />
                  <span style={photoChip(sv.chip, { top: 6, left: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 })}>{sv.tag}</span>
                  {sv.canRemove && (
                    <span onClick={(ev) => { ev.stopPropagation(); toggleFav(sv.key); }} style={lightChip({ top: 6, right: 6, fontSize: 10, padding: '4px 8px', borderRadius: 12 })}>{T('Bỏ', 'Remove')}</span>
                  )}
                </div>
                <div style={{ ...display(15, { marginTop: 7, lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{sv.name}</div>
                <div style={{ fontSize: 11, color: ink, marginTop: 1 }}>{sv.status}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      <div style={{ display: 'flex', gap: 20, padding: '16px 20px 14px' }}>
        {filters.map(f => (
          <span key={f.key} onClick={() => pickFilter(f.key)} style={f.style}>{f.label}</span>
        ))}
      </div>

      {feed.map(ev => (
        <div key={ev.key} onClick={() => set({ screen: 'event', eventKey: ev.key })} style={{ cursor: 'pointer', paddingBottom: 6 }}>
          <div style={{ position: 'relative' }}>
            <div style={bg(ev.img, { width: 'calc(100% - 40px)', height: 272, margin: '0 20px', borderRadius: '14px 14px 0 0' })} />
            <div style={{ position: 'absolute', left: 20, right: 20, bottom: 0, height: 58, background: `linear-gradient(to bottom, rgba(247,244,236,0) 0%, rgba(247,244,236,0.3) 62%, ${paper} 100%)`, pointerEvents: 'none' }} />
            <span
              onClick={(e) => { e.stopPropagation(); toggleFav(ev.key); }}
              style={ev.saved ? photoChip(CHIP_COLORS.going, { top: 12, right: 30 }) : lightChip({ top: 12, right: 30 })}
            >{ev.saveLabel}</span>
            {ev.going && (
              <span style={photoChip(CHIP_COLORS.going, { bottom: 12, left: 30 })}>{ev.goingLabel}</span>
            )}
          </div>
          <div style={{ padding: '14px 20px 18px', display: 'grid', gridTemplateColumns: '1fr auto', columnGap: 16 }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
              <span style={{ ...display(22, { lineHeight: 1.2 }) }}>{ev.name}</span>
              <span style={{ fontSize: 12.5, lineHeight: 1.35, color: ink, marginTop: 1 }}>{ev.metaDisplay}</span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4, paddingTop: 4 }}>
              <span style={{ fontSize: 13, color: ink, whiteSpace: 'nowrap' }}>{trStatus(ev.price)}</span>
              <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', textAlign: 'right' }}>{ev.seatsDisplay}</span>
            </div>
          </div>
        </div>
      ))}

      {feed.length === 0 && (
        <div style={{ padding: '60px 40px 70px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{feedEmptyMsg}</p>
          <span onClick={clearFilters} style={{ display: 'inline-block', marginTop: 10, fontSize: 12.5, color: ink, cursor: 'pointer' }}>{T('Xem tất cả', 'See all')}</span>
        </div>
      )}

      {feed.length > 0 && (
        <div style={{ padding: '34px 20px 6px', textAlign: 'center', borderTop: `1px solid ${rule}` }}>
          <p style={{ ...display(11.5, { margin: 0 }) }}>{T('Hết rồi, ra ngoài chơi thôi!', "That's it, go have fun!")}</p>
        </div>
      )}

      <div style={{ padding: '6px 20px 8px', fontSize: 11, color: ink }}>
        {T('Vài buổi vui dành cho riêng bạn tuần này. Không xếp hạng, không quảng cáo, không lướt vô tận.', 'A few fun gatherings made just for you this week. No ratings, no ads, no endless scrolling.')}
      </div>
      <div onClick={homeHostLink} style={{ padding: '4px 20px 44px', fontSize: 14.5, fontWeight: 600, letterSpacing: '-0.01em', color: ink, cursor: 'pointer' }}>{homeHostLinkLabel} ›</div>
    </div>
  );
}

function Countdown({ deadline, now }) {
  const ms = Math.max(0, (deadline || 0) - now);
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  const sec = Math.floor((ms % 60000) / 1000);
  const label = String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0') + ':' + String(sec).padStart(2, '0');
  return <span style={{ ...display(19, { fontVariantNumeric: 'tabular-nums', flex: 'none', marginLeft: 12 }) }}>{label}</span>;
}
