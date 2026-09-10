import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, CREATE_PALETTES, CREATE_PHOTO_SLOT_IDS, bg, img as imgUrl } from '../data/events.js';
import { paper, ink, rule, FACE, display, fieldGlass, cardGlass } from '../theme.js';

const CAT_DEFS = [
  { key: 'supper', vi: 'Supper club', en: 'Supper club' },
  { key: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { key: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { key: 'music', vi: 'Nhạc', en: 'Music' },
  { key: 'popup', vi: 'Pop-up', en: 'Pop-up' },
];

export default function CreateEvent() {
  const {
    state, T, trStatus, stripKm, curEvent: ev, createBack,
    orgRegNameType, orgRegIgType, orgRegDescType,
    createNameType, createDescType, createLocType, createDateType, createPriceType, createSeatsType,
    pickCreateCat, pickCreatePalette, tapPhotoSlot, createSubmit, goEvent,
  } = useGoc();
  const s = state;

  const createBackLabel = s.hasHosted ? T('Trang tổ chức của bạn', 'Your host page') : T('Trang tổ chức của bạn sẽ trông thế nào', 'Preview your organizer page');

  const upcoming = EVENTS.filter(e => e.orgName === ev.orgName && !e.cancelled && e.endedHoursAgo == null)
    .sort((a, c) => (a.until ?? 999) - (c.until ?? 999));
  const orgTrustNote = ev.orgTrusted
    ? T('Huy hiệu "Tổ chức lâu năm" ▪︎ ' + ev.orgCount + ' sự kiện từ ' + ev.orgSince, 'Established host badge ▪︎ ' + ev.orgCount + ' events since ' + ev.orgSince)
    : T('Còn ' + (20 - ev.orgCount) + ' sự kiện nữa để nhận huy hiệu "Tổ chức lâu năm".', (20 - ev.orgCount) + ' more events to earn the Established host badge.');

  const cur = CREATE_PALETTES.find(x => x.key === s.createPalette) || CREATE_PALETTES[0];
  const dark = cur.text !== '#1B1916';
  const btnText = cur.accent === '#1B1916' ? '#F7F4EC' : cur.bg;
  const createCatLabel = (s.createCats.length ? s.createCats : ['supper']).map(k => {
    const d = CAT_DEFS.find(c => c.key === k);
    return d ? T(d.vi, d.en) : k;
  }).join(' ▪︎ ');
  const createNameShown = s.createName.trim() || T('Tên sự kiện của bạn', 'Your event name');

  const createBtnStyle = {
    marginTop: 26, fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 16, borderRadius: 999,
    background: s.createSent ? 'rgba(27,25,22,0.16)' : (s.createName.trim() ? ink : 'rgba(27,25,22,0.16)'),
    color: s.createSent ? ink : (s.createName.trim() ? paper : ink),
    cursor: s.createName.trim() && !s.createSent ? 'pointer' : 'default', transition: 'background .15s',
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Create event">
      <div onClick={createBack} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {createBackLabel}</div>
      <div style={{ padding: '14px 22px 40px', display: 'flex', flexDirection: 'column' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Dành cho người tổ chức', 'For organizers')}</span>
        <h1 style={{ ...display(26, { margin: '8px 0 0' }) }}>{T('Tạo sự kiện, hoàn toàn miễn phí', 'Create an event, completely free')}</h1>

        <div style={{ ...cardGlass({ marginTop: 22, padding: 16, display: 'flex', flexDirection: 'column', gap: 12 }) }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Hồ sơ người tổ chức', 'Organizer profile')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Hiện trên trang của bạn', 'Shown on your page')}</span>
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <Field style={{ flex: 1.2 }} label={T('Tên', 'Name')} value={s.orgRegName} onChange={orgRegNameType} placeholder="Bếp Nhỏ" />
            <Field style={{ flex: 1 }} label="Instagram" value={s.orgRegIg} onChange={orgRegIgType} placeholder="@bepnho.saigon" />
          </div>
          <Field label={T('Giới thiệu', 'About')} value={s.orgRegDesc} onChange={orgRegDescType} placeholder={T('Minh nấu cho người lạ từ 2021…', 'Minh has cooked for strangers since 2021…')} />
        </div>

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện sắp tới', 'Upcoming events')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{upcoming.length}{T(' sự kiện', upcoming.length === 1 ? ' event' : ' events')}</span>
          </div>
          <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, margin: '6px 0 0' }}>{orgTrustNote}</p>
          <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
            {upcoming.map((e, i, arr) => (
              <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                <div style={bg(e.img, { flex: 'none', width: 52, height: 52 })} />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
                  <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                  <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))}</span>
                </div>
                <span style={{ fontSize: 11.5, color: ink, flex: 'none' }}>{trStatus(e.soldOut ? 'Hết chỗ' : e.seats)}</span>
              </div>
            ))}
            {upcoming.length === 0 && (
              <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{T('Bạn chưa có sự kiện nào sắp tới. Tạo bên dưới.', 'No upcoming events yet. Create one below.')}</p>
            )}
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 22 }}>
          <label style={labelStyle}>{T('Tên sự kiện', 'Event name')}</label>
          <input value={s.createName} onChange={createNameType} placeholder="Bếp Nhỏ №13" style={fieldInput} />
        </div>

        <div style={{ marginTop: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Danh mục', 'Category')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Tối đa 2 danh mục', 'Max 2 categories')}</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
            {CAT_DEFS.map(c => {
              const on = s.createCats.includes(c.key);
              const isSecond = on && s.createCats[1] === c.key;
              return (
                <span key={c.key} onClick={() => pickCreateCat(c.key)} style={{ fontSize: 12.5, padding: '8px 15px', borderRadius: 999, cursor: 'pointer', border: on ? `1.5px solid ${ink}` : '1px solid rgba(27,25,22,0.16)', background: on ? paper : 'transparent', color: ink, fontWeight: on ? 600 : 400 }}>
                  {T(c.vi, c.en)}{isSecond ? ' ▪︎ +' : ''}
                </span>
              );
            })}
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 20 }}>
          <label style={labelStyle}>{T('Mô tả', 'Description')}</label>
          <input value={s.createDesc} onChange={createDescType} placeholder={T('Mười bốn chỗ. Một ga-ra cải tạo…', 'Fourteen seats. A converted garage…')} style={fieldInput} />
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
          <div style={{ flex: 1.4, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Địa điểm', 'Location')}</label>
            <input value={s.createLoc} onChange={createLocType} placeholder="Bình Thạnh" style={fieldInput} />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Ngày ▪︎ giờ', 'Date ▪︎ time')}</label>
            <input value={s.createDate} onChange={createDateType} placeholder="18.07 ▪︎ 19:00" style={fieldInput} />
          </div>
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Giá vé', 'Ticket price')}</label>
            <input value={s.createPrice} onChange={createPriceType} placeholder="500.000₫" style={fieldInput} />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <label style={labelStyle}>{T('Số chỗ', 'Seats')}</label>
            <input value={s.createSeats} onChange={createSeatsType} placeholder="14" style={fieldInput} />
          </div>
        </div>

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Hình ảnh', 'Photos')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>{s.createPhotos}/8</span>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 6, marginTop: 10 }}>
            {CREATE_PHOTO_SLOT_IDS.map((id, i) => {
              const filled = i < s.createPhotos;
              return (
                <div
                  key={id}
                  onClick={() => tapPhotoSlot(i)}
                  style={Object.assign({
                    aspectRatio: '1', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
                    overflow: 'hidden', borderRadius: 12, background: filled ? 'transparent' : paper,
                    border: filled ? 'none' : `1px dashed ${ink}`,
                  }, filled ? bg(imgUrl(id)) : {})}
                >
                  {!filled && <span style={{ fontSize: 18, color: ink }}>+</span>}
                </div>
              );
            })}
          </div>
        </div>

        <div style={{ marginTop: 22 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Bảng màu', 'Palette')}</span>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10, marginTop: 10 }}>
            {CREATE_PALETTES.map(d => (
              <div key={d.key} onClick={() => pickCreatePalette(d.key)} style={{ display: 'flex', flexDirection: 'column', gap: 4, cursor: 'pointer' }}>
                <div style={{ height: 46, background: d.bg, position: 'relative', overflow: 'hidden', borderRadius: 12, border: d.key === s.createPalette ? `2px solid ${ink}` : '1px solid rgba(27,25,22,0.16)' }}>
                  <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 9, background: d.accent }} />
                </div>
                <span style={{ fontSize: 11, color: ink, fontWeight: 500 }}>{d.name}</span>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 14, background: cur.bg, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, overflow: 'hidden' }}>
            <div style={{ padding: '12px 14px 14px', display: 'flex', flexDirection: 'column', gap: 3 }}>
              <span style={{ fontSize: 9, fontWeight: 600, color: dark ? 'rgba(247,244,236,0.72)' : ink }}>{createCatLabel}</span>
              <span style={{ ...display(19, { lineHeight: 1.25, color: cur.text }) }}>{createNameShown}</span>
              <div style={{ marginTop: 10, background: cur.accent, color: btnText, fontSize: 12, fontWeight: 600, textAlign: 'center', padding: 11, borderRadius: 999 }}>{T('Giữ chỗ', 'Reserve')}</div>
            </div>
          </div>
          <p style={{ fontSize: 11, lineHeight: 1.55, color: ink, margin: '12px 0 0' }}>{T('Sự kiện mới sẽ ở trạng thái chờ duyệt. Một tài khoản admin riêng của banbe sẽ kiểm tra trước khi mở bán.', 'New events enter review. A separate banbe admin account approves them before they go live.')}</p>
        </div>

        <div onClick={createSubmit} style={createBtnStyle}>{s.createSent ? T('Đã gửi ▪︎ banbe duyệt trong 48 giờ', 'Sent ▪︎ banbe reviews within 48h') : T('Gửi để duyệt', 'Submit for review')}</div>
        {s.createError && <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '10px 0 0', textAlign: 'center' }}>{s.createError}</p>}
        <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: '12px auto 0', textAlign: 'center', maxWidth: '23ch' }}>{T('Hoàn toàn miễn phí: không phí đăng, không phí giao dịch, không phí ẩn.', 'Completely free: no listing fee, no transaction fee, no hidden fees.')}</p>
      </div>
    </div>
  );
}

function Field({ label, value, onChange, placeholder, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5, minWidth: 0, width: '100%', boxSizing: 'border-box', ...style }}>
      <label style={labelStyle}>{label}</label>
      <input value={value} onChange={onChange} placeholder={placeholder} style={{ ...fieldGlass({ padding: '11px 12px' }), fontSize: 13.5, fontFamily: FACE, color: ink, outline: 'none', minWidth: 0, width: '100%', boxSizing: 'border-box', border: 'none' }} />
    </div>
  );
}

const labelStyle = { fontSize: 11.5, color: ink };
const fieldInput = { ...fieldGlass({ padding: '13px 14px' }), fontSize: 14, fontFamily: FACE, color: ink, outline: 'none', minWidth: 0, width: '100%', boxSizing: 'border-box', border: 'none' };
