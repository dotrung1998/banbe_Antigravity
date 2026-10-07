import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { useKeychainManifest } from '../components/KeychainCharm.jsx';
import { designUrl, keychainFocus } from '../lib/keychain.js';
import { historyLabel, ruleLines, noCoinLines, redemptionTermsLines, streakLines, streakHint, shortfall } from '../lib/rewards.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';
import { RowIcon } from './Account.jsx';

const REDEEM_ERRORS = {
  INSUFFICIENT_BALANCE: ['Chưa đủ xu để đổi phần thưởng này.', "You don't have enough coins for this reward yet."],
  ITEM_NOT_FOUND: ['Phần thưởng này không còn nữa.', 'This reward is no longer available.'],
  NETWORK: ['Lỗi mạng. Chưa trừ xu. Vui lòng thử lại.', 'Network error. No coins were spent. Please try again.'],
  TRY_AGAIN: ['Vui lòng thử lại.', 'Please try again.'],
};

// Account > Rewards & badges. Private to the signed-in account. Every number is server-computed
// (migration 165); coins are cosmetic only and never affect booking, priority or eligibility.
export default function Rewards() {
  const { state: s, T, set, loadRewards, redeemReward, openEditProfile } = useBanBe();
  const manifest = useKeychainManifest();
  const [confirmCode, setConfirmCode] = useState(null);

  useEffect(() => { if (s.user?.id) loadRewards(); }, [s.user?.id, loadRewards]);

  const r = s.rewards;
  const loading = s.rewardsStatus === 'loading' || s.rewardsStatus === 'idle';
  const lang = s.lang;
  const nameOf = (id) => { const d = manifest.designs.find(x => x.id === id); return d ? (lang === 'en' ? d.en : d.vi) : id; };
  const confirmItem = r?.catalog?.find(c => c.code === confirmCode) || null;
  const res = s.rewardsRedeemResult;

  const doRedeem = async () => {
    const code = confirmCode;
    setConfirmCode(null);
    if (code) await redeemReward(code);
  };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Rewards">
      <div onClick={() => set({ screen: 'profile' })} role="button" style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="rewards-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0, display: 'flex', alignItems: 'center', gap: 10 }) }}>
          <RowIcon kind="coin" size={26} />{T('Phần thưởng & huy hiệu', 'Rewards & badges')}
        </h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Chỉ mình bạn thấy trang này. Huy hiệu và lịch sử không hiển thị công khai.', 'Only you can see this page. Badges and history are never shown publicly.')}
        </p>
      </div>

      <div style={{ margin: '16px 22px 40px', display: 'flex', flexDirection: 'column', gap: 20 }}>
        {s.rewardsStatus === 'unavailable' && (
          <div data-testid="rewards-unavailable" style={{ ...fieldGlass({ padding: 18, borderRadius: 14 }), fontSize: 13, color: ink }}>
            {T('Phần thưởng chưa khả dụng. Vui lòng quay lại sau.', "Rewards aren't available yet. Please check back later.")}
          </div>
        )}
        {s.rewardsStatus === 'error' && (
          <div role="alert" data-testid="rewards-error" style={{ ...fieldGlass({ padding: 16, borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 8 }) }}>
            <span style={{ fontSize: 13, color: alert }}>{T('Không tải được phần thưởng.', "Couldn't load your rewards.")}</span>
            <span onClick={loadRewards} role="button" data-testid="rewards-retry" style={{ fontSize: 13, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Thử lại', 'Retry')}</span>
          </div>
        )}
        {loading && !r && <div data-testid="rewards-loading" style={{ ...fieldGlass({ padding: 20, textAlign: 'center', borderRadius: 14 }), fontSize: 13, color: ink }}>{T('Đang tải…', 'Loading…')}</div>}

        {r && (
          <>
            {/* Balance + streak */}
            <div style={{ display: 'flex', gap: 10 }}>
              <div data-testid="rewards-balance" style={{ ...fieldGlass({ flex: 1, padding: '16px 16px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 4 }) }}>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Số dư xu', 'Coin balance')}</span>
                <span style={{ ...display(30) }} aria-label={T(`${r.balance} xu`, `${r.balance} coins`)}>{r.balance}</span>
                {r.balance < 0 && <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Số dư âm do điểm danh bị huỷ; kiếm thêm để về 0.', 'Negative because a check-in was undone; earn coins to get back to 0.')}</span>}
              </div>
              <div data-testid="rewards-streak" style={{ ...fieldGlass({ flex: 1, padding: '16px 16px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 4 }) }}>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Chuỗi ngày', 'Streak')}</span>
                <span style={{ ...display(30), display: 'flex', alignItems: 'center', gap: 6 }}><span aria-hidden="true">🔥</span>{r.streak?.current ?? 0}</span>
                <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T(`Dài nhất: ${r.streak?.longest ?? 0} ngày`, `Longest: ${r.streak?.longest ?? 0} days`)}</span>
                {(() => { const h = streakHint(T, r.streak?.active_today === true); return (
                  <>
                    <span data-testid="rewards-streak-status" style={{ fontSize: 11.5, fontWeight: 600, color: ink, marginTop: 6 }}>{h.status}</span>
                    <span data-testid="rewards-streak-how" style={{ fontSize: 11, lineHeight: 1.4, color: ink, opacity: 0.75 }}>{h.how}</span>
                  </>
                ); })()}
              </div>
            </div>

            {/* Badges */}
            <section data-testid="rewards-badges">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 8px', color: ink }}>{T('Huy hiệu', 'Badges')}</h2>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {r.badges.map(b => {
                  const pct = Math.round((Math.min(b.progress, b.target) / b.target) * 100);
                  return (
                    <div key={b.code} data-testid={`badge-${b.code}`} data-earned={b.earned ? 'true' : 'false'}
                      style={{ ...fieldGlass({ padding: '12px 14px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 6, opacity: b.earned ? 1 : 0.92 }) }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'center' }}>
                        <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{b.earned ? '✓ ' : ''}{lang === 'en' ? b.title_en : b.title_vi}</span>
                        <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.8 }}>{b.earned ? T('Đã đạt', 'Earned') : T('Chưa đạt', 'Locked')}</span>
                      </div>
                      <span style={{ fontSize: 12, color: ink, opacity: 0.75 }}>{lang === 'en' ? b.desc_en : b.desc_vi}</span>
                      <div role="progressbar" aria-valuemin={0} aria-valuemax={b.target} aria-valuenow={Math.min(b.progress, b.target)}
                        aria-label={`${lang === 'en' ? b.title_en : b.title_vi}: ${Math.min(b.progress, b.target)} / ${b.target}`}
                        style={{ height: 6, borderRadius: 3, background: rule, overflow: 'hidden' }}>
                        <div style={{ width: `${pct}%`, height: '100%', background: ink }} />
                      </div>
                      <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{Math.min(b.progress, b.target)} / {b.target}</span>
                    </div>
                  );
                })}
              </div>
            </section>

            {/* Redemption catalog */}
            <section data-testid="rewards-catalog">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 4px', color: ink }}>{T('Đổi thưởng (móc khoá)', 'Redeem (keychain designs)')}</h2>
              <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '0 0 10px' }}>
                {T('Tuỳ chọn, chỉ để trang trí. 24 mẫu miễn phí vẫn luôn dùng được.', 'Optional and cosmetic only. The 24 free charms always stay available.')}
              </p>
              {res && !res.ok && (
                <div role="alert" data-testid="rewards-redeem-error" style={{ fontSize: 12.5, color: alert, margin: '0 0 8px' }}>
                  {(() => { const e = REDEEM_ERRORS[res.error] || REDEEM_ERRORS.TRY_AGAIN; return T(e[0], e[1]); })()}
                </div>
              )}
              {res && res.ok && !res.already && <div role="status" data-testid="rewards-redeem-ok" style={{ fontSize: 12.5, color: ink, margin: '0 0 8px' }}>{T('Đã mở khoá!', 'Unlocked!')}</div>}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {r.catalog.map(c => {
                  const need = shortfall(r.balance, c.price);
                  const busy = s.rewardsRedeemBusy === c.code;
                  return (
                    <div key={c.code} data-testid={`catalog-${c.code}`} style={{ ...fieldGlass({ padding: '12px 14px', borderRadius: 14, display: 'flex', alignItems: 'center', gap: 12 }) }}>
                      <img src={designUrl(manifest, c.design_id)} alt="" style={{ width: 40, height: 60, objectFit: 'contain', flex: 'none' }} />
                      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{nameOf(c.design_id)}</span>
                        <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }}>
                          {c.unlocked ? T('Đã mở khoá', 'Unlocked') : need > 0 ? T(`${c.price} xu ▪︎ cần thêm ${need}`, `${c.price} coins ▪︎ ${need} more needed`) : T(`${c.price} xu`, `${c.price} coins`)}
                        </span>
                      </div>
                      {c.unlocked ? (
                        <span onClick={() => { keychainFocus.pending = true; openEditProfile(); }} role="button" data-testid={`catalog-use-${c.code}`}
                          style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: ink, border: `1px solid ${rule}`, borderRadius: 999, padding: '9px 14px', cursor: 'pointer' }}>{T('Dùng', 'Use')}</span>
                      ) : (
                        <span onClick={need > 0 || busy ? undefined : () => setConfirmCode(c.code)} role="button" aria-disabled={need > 0 || busy} data-testid={`catalog-redeem-${c.code}`}
                          style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: need > 0 ? ink : paper, background: need > 0 ? 'transparent' : ink, border: need > 0 ? `1px solid ${rule}` : 'none', borderRadius: 999, padding: '9px 14px', opacity: need > 0 || busy ? 0.55 : 1, cursor: need > 0 || busy ? 'default' : 'pointer' }}>
                          {busy ? T('Đang xử lý…', 'Working…') : T('Đổi', 'Redeem')}
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            </section>

            {/* Recent history */}
            <section data-testid="rewards-history">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 8px', color: ink }}>{T('Lịch sử gần đây', 'Recent history')}</h2>
              {r.history.length === 0 ? (
                <div data-testid="rewards-history-empty" style={{ ...fieldGlass({ padding: 16, borderRadius: 14 }), fontSize: 12.5, color: ink, opacity: 0.8 }}>
                  {T('Chưa có hoạt động nào. Tham dự một sự kiện để bắt đầu.', 'No activity yet. Attend an event to get started.')}
                </div>
              ) : (
                <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column', borderRadius: 14 }) }}>
                  {r.history.map((h, i, arr) => (
                    <div key={h.id} data-testid="rewards-history-row" style={{ display: 'flex', justifyContent: 'space-between', gap: 10, padding: '11px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                        <span style={{ fontSize: 12.5, color: ink }}>{h.type === 'redemption' && h.item_code ? `${historyLabel(h, T)} ▪︎ ${nameOf(h.item_code)}` : historyLabel(h, T)}</span>
                        <span style={{ fontSize: 11, color: ink, opacity: 0.6 }}>{new Date(h.created_at).toLocaleDateString(lang === 'en' ? 'en-US' : 'vi-VN')}</span>
                      </div>
                      <span style={{ fontSize: 13, fontWeight: 700, color: ink, flex: 'none' }} aria-label={T(`${h.amount} xu`, `${h.amount} coins`)}>{h.amount > 0 ? `+${h.amount}` : h.amount}</span>
                    </div>
                  ))}
                </div>
              )}
            </section>

            {/* Rules */}
            <section data-testid="rewards-rules">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 8px', color: ink }}>{T('Cách kiếm xu', 'How earning works')}</h2>
              <ul style={{ margin: 0, paddingInlineStart: 18, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {[...ruleLines(r.rules, T), ...noCoinLines(T), ...streakLines(T, r.streak?.current, r.streak?.timezone)].map((l, i) => (
                  <li key={i} style={{ fontSize: 12.5, lineHeight: 1.5, color: ink }}>{l}</li>
                ))}
              </ul>
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '16px 0 8px', color: ink }}>{T('Điều kiện đổi thưởng', 'Redemption terms')}</h2>
              <ul style={{ margin: 0, paddingInlineStart: 18, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {redemptionTermsLines(T).map((l, i) => <li key={i} style={{ fontSize: 12.5, lineHeight: 1.5, color: ink }}>{l}</li>)}
              </ul>
              <p style={{ fontSize: 11, color: ink, opacity: 0.6, margin: '12px 0 0' }}>{T(`Phiên bản quy tắc ${r.rules?.version ?? 1}. Các con số là đề xuất MVP và có thể thay đổi; mọi thay đổi có số phiên bản mới.`, `Rules version ${r.rules?.version ?? 1}. Numbers are an MVP proposal and may change; any change gets a new version.`)}</p>
            </section>
          </>
        )}
      </div>

      {confirmItem && (
        <div role="dialog" aria-modal="true" aria-label={T('Xác nhận đổi thưởng', 'Confirm redemption')} data-testid="rewards-confirm"
          onClick={() => setConfirmCode(null)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 60, padding: 24 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, borderRadius: 16, padding: 22, maxWidth: 340, width: '100%', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <span style={{ ...display(18) }}>{T('Đổi phần thưởng?', 'Redeem this reward?')}</span>
            <span style={{ fontSize: 13, lineHeight: 1.5, color: ink }}>
              {T(`Dùng ${confirmItem.price} xu để mở khoá "${nameOf(confirmItem.design_id)}". Việc này không thể hoàn tác và không đổi lại thành tiền.`,
                `Spend ${confirmItem.price} coins to unlock "${nameOf(confirmItem.design_id)}". This can't be undone and isn't refundable as cash.`)}
            </span>
            <div style={{ display: 'flex', gap: 10 }}>
              <span onClick={() => setConfirmCode(null)} role="button" data-testid="rewards-confirm-cancel" style={{ flex: 1, textAlign: 'center', padding: '12px 0', borderRadius: 12, border: `1px solid ${rule}`, fontSize: 13.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</span>
              <span onClick={doRedeem} role="button" data-testid="rewards-confirm-ok" style={{ flex: 1, textAlign: 'center', padding: '12px 0', borderRadius: 12, background: ink, fontSize: 13.5, fontWeight: 600, color: paper, cursor: 'pointer' }}>{T('Đổi', 'Redeem')}</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
