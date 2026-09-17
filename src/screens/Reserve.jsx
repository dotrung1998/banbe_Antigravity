import { useGoc } from '../state/GocContext.jsx';
import { bg } from '../data/events.js';
import { paper, ink, FACE, display, fieldGlass, alert } from '../theme.js';

export default function Reserve() {
  const {
    state, T, trStatus, curEvent: ev, backToEvent,
    qtyMinus, qtyPlus, formNameType, setNameAtHold, submitReserve, goEditName,
  } = useGoc();
  const s = state;

  // 01-hold-payment.md's 2026-09-17 follow-up #6: Name/Email used to be
  // free-typed fields that never persisted anywhere (bookings has no such
  // columns) — every organizer-facing view of a guest's name is meant to be
  // a live join to profiles.display_name (6c6b932), and the registered
  // email already exists on the authenticated session. A guest with a real
  // display_name gets it read-only here; one without (e.g. an OAuth
  // sign-in whose provider never supplied a name) gets a real input that
  // actually writes via rename_display_name() — the same RPC Account's
  // "Đổi tên" uses — rather than a value that goes nowhere. Hold stays
  // disabled until a real name exists either way.
  const hasName = !!(s.user?.name || '').trim();
  const formOk = hasName;
  const submitNameAtHold = async () => {
    await setNameAtHold(s.formName);
  };
  const priceNum = parseInt((ev.price.match(/[\d.]+/) || ['0'])[0].replace(/\./g, ''), 10) || 0;
  const isFree = /Miễn phí/.test(ev.price);
  const totalStr = isFree ? 'Miễn phí' : (priceNum * s.qty).toLocaleString('vi-VN') + '₫';
  const qtyTotalLabel = s.qty > 1 ? (T('Tổng ', 'Total ') + trStatus(totalStr)) : trStatus(ev.price);

  // Matches events.hold_minutes' default (migration 031 reverted this back
  // to 30 after migration 026 had briefly bumped it to 60 without updating
  // this copy — the button said 60 while the server actually held for 30,
  // the kind of mismatch a buyer only discovers under pressure). PHASE 2's
  // own verification window is the separate 60-minute number — see
  // PaymentDetails.jsx/Confirmed.jsx, never this screen.
  const reserveBtnLabel = T('Giữ chỗ ▪︎ 30 phút', 'Hold ▪︎ 30 minutes');
  const reserveBtnStyle = {
    margin: '18px 22px 0', fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 16, borderRadius: 999,
    background: formOk ? ink : 'rgba(27,25,22,0.16)',
    color: formOk ? paper : ink,
    cursor: formOk ? 'pointer' : 'default', transition: 'background .15s',
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Reserve">
      <div onClick={backToEvent} style={{ padding: '70px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</div>
      <div style={{ padding: '16px 22px 0' }}>
        <h2 style={{ ...display(24, { margin: 0 }) }}>{T('Gần xong rồi.', 'Almost there.')}</h2>
      </div>
      <div style={{ ...fieldGlass({ display: 'flex', gap: 14, alignItems: 'center', margin: '18px 22px 0', padding: 13 }) }}>
        <div style={bg(ev.img, { flex: 'none', width: 52, height: 52 })} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ ...display(15) }}>{ev.name}</span>
          <span style={{ fontSize: 11.5, color: ink }}>{ev.when} ▪︎ {s.qty} chỗ ▪︎ {trStatus(totalStr)}</span>
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, margin: '20px 22px 0' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <label style={{ fontSize: 11.5, color: ink }}>{T('Tên', 'Name')}</label>
            {hasName && (
              <span onClick={goEditName} style={{ fontSize: 11, color: ink, opacity: 0.6, cursor: 'pointer' }} data-testid="reserve-name-change-in-account">
                {T('Đổi trong Tài khoản', 'Change in Account')}
              </span>
            )}
          </div>
          {hasName ? (
            <div style={{ ...fieldGlass({ padding: '13px 14px' }), fontSize: 14, fontFamily: FACE, color: ink }} data-testid="reserve-name-readonly">
              {s.user.name}
            </div>
          ) : (
            <>
              <input
                value={s.formName} onChange={formNameType} placeholder={T('Tên của bạn', 'Your name')}
                style={inputStyle} data-testid="reserve-name-input"
              />
              <div
                onClick={s.reserveNameSaving ? undefined : submitNameAtHold}
                style={{
                  alignSelf: 'flex-start', fontSize: 11.5, fontWeight: 600, color: ink,
                  border: '1px solid rgba(27,25,22,0.16)', borderRadius: 10, padding: '6px 10px',
                  cursor: s.reserveNameSaving ? 'default' : 'pointer', opacity: s.reserveNameSaving ? 0.6 : 1,
                }}
                data-testid="reserve-name-save"
              >
                {s.reserveNameSaving ? T('Đang lưu…', 'Saving…') : T('Lưu tên', 'Save name')}
              </div>
              {s.reserveNameError && (
                <span style={{ fontSize: 11, color: alert }}>{s.reserveNameError}</span>
              )}
            </>
          )}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
          <label style={{ fontSize: 11.5, color: ink }}>Email</label>
          <div style={{ ...fieldGlass({ padding: '13px 14px' }), fontSize: 14, fontFamily: FACE, color: ink, opacity: 0.75 }} data-testid="reserve-email-readonly">
            {s.user?.email || ''}
          </div>
        </div>
      </div>
      <div style={{ margin: '22px 22px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Số vé', 'Tickets')}</span>
        <div style={{ ...fieldGlass({ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 12, padding: '12px 14px' }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ fontSize: 14, fontWeight: 600, color: ink }}>{s.qty} {T('vé', 'tickets')}</span>
            <span style={{ fontSize: 11.5, color: ink }}>{qtyTotalLabel}</span>
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <span onClick={qtyMinus} style={{ width: 32, height: 32, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, cursor: s.qty > 1 ? 'pointer' : 'default', color: s.qty > 1 ? ink : 'rgba(27,25,22,0.16)', border: '1px solid rgba(27,25,22,0.16)', userSelect: 'none' }}>−</span>
            <span style={{ ...display(18, { minWidth: 20, textAlign: 'center' }) }}>{s.qty}</span>
            <span onClick={qtyPlus} style={{ width: 32, height: 32, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, cursor: s.qty < 6 ? 'pointer' : 'default', color: s.qty < 6 ? ink : 'rgba(27,25,22,0.16)', border: '1px solid rgba(27,25,22,0.16)', userSelect: 'none' }}>+</span>
          </div>
        </div>
      </div>
      <div style={{ margin: '22px 22px 0', fontSize: 12, lineHeight: 1.55, color: ink }}>
        {T('banbe không thu tiền. Bạn giữ chỗ 30 phút để chuyển khoản trực tiếp cho người tổ chức. Bấm "Tôi đã chuyển khoản" là đồng hồ dừng và chỗ được khoá cho tới khi người tổ chức xác nhận.', 'banbe does not collect money. Your seat is held for 30 minutes while you transfer to the organizer directly. Tapping "I have transferred" stops the clock and locks your seat until they confirm.')}
      </div>
      <div onClick={() => submitReserve(formOk)} style={reserveBtnStyle}>{reserveBtnLabel}</div>
      {s.reserveError && <div style={{ margin: '12px 22px 0', fontSize: 12, lineHeight: 1.5, color: alert }}>{s.reserveError}</div>}
      <div style={{ height: 40 }} />
    </div>
  );
}

const inputStyle = { ...fieldGlass({ padding: '13px 14px', border: 'none' }), fontSize: 14, fontFamily: FACE, color: ink, outline: 'none' };
