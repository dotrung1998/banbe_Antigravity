// "Before you go" pop-up shown when someone taps Delete account (owner, 2026-10-21). It shows what they would lose,
// asks why, and offers the one fix for that reason. "Continue deleting" is always visible and opens the existing
// DeleteAccountSheet at its confirm step with the reason filled in. Logic: src/lib/accountRetention.js;
// iOS twin: apps/ios/BanbeApp/Views/DeleteAccountStayView.swift.
import { useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, clay, alert, display, inkButton } from '../../theme.js';
import { DELETE_REASONS, QUIETED_NOTIFICATION_KINDS, lossRows, retentionOffer } from '../../lib/accountRetention.js';
import { setHostPromoConsent } from '../../lib/accountGate.js';

const ICONS = { bookedEvents: '🎟️', hostedEvents: '🎪', savedEvents: '♡', followedHosts: '👥', coins: '⭐' };

export default function DeleteAccountStaySheet() {
  const { state: s, T, closeDeleteAccountStay, openDeleteAccount, muteNotificationKind,
    openEventPreferences, openSecurity, logout, rewardsEnabled } = useBanBe();
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [quieted, setQuieted] = useState(false);

  const rows = lossRows({
    bookedEvents: (s.attending || []).length, savedEvents: (s.favorites || []).length,
    followedHosts: (s.followedHosts || []).length, coins: s.rewardsSummary?.balance ?? null,
    rewardsEnabled, hostedEvents: s.myOrgPublishedEventCount || 0,
  });
  const offer = retentionOffer(reason);

  const label = ({ kind, count: n }) => ({
    bookedEvents: T(`${n} sự kiện bạn đã đặt chỗ`, n === 1 ? "1 event you've booked" : `${n} events you've booked`),
    hostedEvents: T(`${n} sự kiện bạn tổ chức`, n === 1 ? '1 event you host' : `${n} events you host`),
    savedEvents: T(`${n} sự kiện đã lưu`, n === 1 ? '1 saved event' : `${n} saved events`),
    followedHosts: T(`${n} host bạn theo dõi`, n === 1 ? '1 host you follow' : `${n} hosts you follow`),
    coins: T(`${n} xu thưởng`, n === 1 ? '1 reward coin' : `${n} reward coins`),
  }[kind]);

  const COPY = {
    quieterNotifications: {
      title: T('Bớt thông báo, giữ tài khoản', 'Fewer notifications, same account'),
      body: T('Tắt tin quảng bá từ host và thông báo chung của sự kiện. Thông báo về vé, thanh toán và hoàn tiền vẫn giữ.',
        'Turn off host promos and event announcements. Ticket, payment and refund alerts stay on.'),
      button: T('Tắt bớt thông báo', 'Quiet my notifications'),
    },
    retuneForYou: {
      title: T('Gợi ý chưa hợp với bạn?', 'Suggestions not a fit?'),
      body: T('Trả lời lại 5 câu ngắn để ★ Dành cho bạn chọn sự kiện sát hơn.', 'Re-answer 5 quick questions so ★ For You picks closer matches.'),
      button: T('Chỉnh lại gợi ý', 'Retune my suggestions'),
    },
    reviewPrivacy: {
      title: T('Bạn kiểm soát những gì được chia sẻ', "You control what's shared"),
      body: T('Sở thích của bạn chỉ mình bạn thấy. Xem và chỉnh cài đặt bảo mật và tin quảng bá.',
        'Your preferences are only visible to you. Review security and promo settings.'),
      button: T('Mở cài đặt bảo mật', 'Open security settings'),
    },
    takeABreak: {
      title: T('Cần nghỉ một chút?', 'Need a break?'),
      body: T('Đăng xuất thay vì xoá. Vé, lịch sử và sự kiện đã lưu vẫn còn khi bạn quay lại.',
        "Sign out instead of deleting. Your tickets, history and saved events are here when you're back."),
      button: T('Đăng xuất', 'Sign out'),
    },
  };

  const run = async () => {
    if (offer === 'quieterNotifications') {
      setBusy(true);
      for (const kind of QUIETED_NOTIFICATION_KINDS) await muteNotificationKind(kind);
      await setHostPromoConsent(false);
      setBusy(false);
      setQuieted(true);
    } else if (offer === 'retuneForYou') { closeDeleteAccountStay(); openEventPreferences(); }
    else if (offer === 'reviewPrivacy') { closeDeleteAccountStay(); openSecurity(); }
    else if (offer === 'takeABreak') { closeDeleteAccountStay(); await logout(); }
  };

  return (
    <div role="presentation" onClick={closeDeleteAccountStay}
      style={{ position: 'fixed', inset: 0, zIndex: 95, background: 'rgba(0,0,0,0.42)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16, animation: 'banbeFade .2s' }}>
      <div role="dialog" aria-modal="true" aria-labelledby="delete-stay-title" data-testid="delete-stay-sheet" onClick={(e) => e.stopPropagation()}
        style={{ width: '100%', maxWidth: 440, maxHeight: '92vh', overflowY: 'auto', background: paper, color: ink, borderRadius: 24, padding: '22px 20px 16px',
          boxShadow: '0 18px 50px rgba(0,0,0,0.25)', boxSizing: 'border-box', animation: 'bbRiseIn .32s cubic-bezier(.2,.8,.2,1)' }} className="bb-rise">
        <div aria-hidden style={{ fontSize: 40, lineHeight: 1 }}>🥺</div>
        <h2 id="delete-stay-title" style={display(24, { margin: '10px 0 4px' })}>{T('Trước khi bạn đi…', 'Before you go…')}</h2>
        <p style={{ margin: 0, fontSize: 14, lineHeight: 1.5, opacity: 0.75 }}>
          {T('Xoá tài khoản là vĩnh viễn và không thể khôi phục.', "Deleting your account is permanent and can't be undone.")}
        </p>

        {rows.length > 0 && (
          <div data-testid="delete-stay-losses" style={{ marginTop: 16, padding: 16, borderRadius: 18, background: 'var(--bb-field)' }}>
            <div style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.7, marginBottom: 8 }}>{T('Bạn sẽ mất', "You'd lose")}</div>
            {rows.map(r => (
              <div key={r.kind} style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '5px 0' }}>
                <span aria-hidden style={{ width: 24, textAlign: 'center', color: clay, fontSize: 16 }}>{ICONS[r.kind]}</span>
                <div>
                  <div style={{ fontSize: 14, fontWeight: 600 }}>{label(r)}</div>
                  {r.kind === 'hostedEvents' && (
                    <div style={{ fontSize: 12, opacity: 0.7, marginTop: 2 }}>
                      {T('Sự kiện đang mở cần được huỷ hoặc kết thúc trước khi xoá.', 'Open events must be cancelled or ended before you can delete.')}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        <div style={{ marginTop: 18 }}>
          <div style={{ fontSize: 16, fontWeight: 600 }}>{T('Vì sao bạn muốn rời đi?', 'Why are you leaving?')}</div>
          <div style={{ fontSize: 12, opacity: 0.7, marginTop: 2 }}>{T('Không bắt buộc, giúp chúng tôi gợi ý cách khắc phục.', 'Optional, helps us suggest a fix.')}</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
            {DELETE_REASONS.map(r => {
              const on = r.code === reason;
              return (
                <button key={r.code} type="button" aria-pressed={on} data-testid={`delete-stay-reason-${r.code}`}
                  onClick={() => { setReason(on ? '' : r.code); setQuieted(false); }}
                  style={{ minHeight: 40, padding: '0 14px', borderRadius: 999, fontFamily: 'inherit', fontSize: 13, fontWeight: on ? 600 : 400, cursor: 'pointer',
                    background: on ? ink : 'var(--bb-field)', color: on ? paper : ink, border: on ? '1px solid transparent' : `1px solid ${rule}` }}>
                  {T(r.vi, r.en)}
                </button>
              );
            })}
          </div>
        </div>

        {offer && (
          <div data-testid={`delete-stay-offer-${offer}`} className="bb-rise"
            style={{ marginTop: 16, padding: 16, borderRadius: 18, border: '1.5px solid rgba(var(--bb-clay-rgb),0.5)', animation: 'bbRiseIn .28s ease-out' }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>{COPY[offer].title}</div>
            <div style={{ fontSize: 12.5, lineHeight: 1.5, opacity: 0.75, marginTop: 4 }}>{COPY[offer].body}</div>
            {offer === 'quieterNotifications' && quieted ? (
              <div data-testid="delete-stay-quieted" role="status" style={{ marginTop: 10, fontSize: 12.5, fontWeight: 600 }}>
                ✓ {T('Đã tắt. Bạn vẫn nhận thông báo về vé, thanh toán và hoàn tiền.', "Done. You'll still get ticket, payment and refund alerts.")}
              </div>
            ) : (
              <button type="button" disabled={busy} onClick={run} data-testid="delete-stay-offer-action"
                style={{ marginTop: 12, width: '100%', minHeight: 48, borderRadius: 16, border: `1px solid ${rule}`, background: 'var(--bb-field)', color: ink,
                  fontFamily: 'inherit', fontSize: 14.5, fontWeight: 600, cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.6 : 1 }}>
                {COPY[offer].button}
              </button>
            )}
          </div>
        )}

        <button type="button" onClick={closeDeleteAccountStay} data-testid="delete-stay-keep"
          style={{ ...inkButton({ marginTop: 20, borderRadius: 16, padding: 14, fontSize: 15, width: '100%', border: 'none', fontFamily: 'inherit', cursor: 'pointer' }) }}>
          {T('Giữ tài khoản của tôi', 'Keep my account')}
        </button>
        <button type="button" onClick={() => openDeleteAccount({ fromStay: true, reasonCode: reason })} data-testid="delete-stay-continue"
          style={{ display: 'block', width: '100%', minHeight: 44, marginTop: 6, background: 'none', border: 'none', color: alert, fontFamily: 'inherit',
            fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
          {T('Tiếp tục xoá tài khoản', 'Continue deleting my account')}
        </button>
      </div>
    </div>
  );
}
