import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { useKeychainManifest } from '../components/KeychainCharm.jsx';
import { designUrl, keychainFocus } from '../lib/keychain.js';
import { historyLabel, ruleLines, noCoinLines, redemptionTermsLines, streakLines, streakHint, shortfall, SUGGESTED_TIMEZONES, deviceTimezoneHint, normalizeTzSettings, TZ_ERRORS, splitRewardCatalog,
  normalizeWeekStreak, weekStreakHint, graceLine, weekStreakLines, weeksLabel, groupBadgesByFamily, BADGE_FAMILIES, nextBadgeLine, normalizeGoal, goalLine, GOAL_CHOICES, GOAL_ERRORS,
  celebrationDiff, readCelebrated, writeCelebrated } from '../lib/rewards.js';
import ConfettiBurst from '../components/ui/ConfettiBurst.jsx';
import { track } from '../lib/analytics.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';
import { RowIcon } from './Account.jsx';

const REDEEM_ERRORS = {
  INSUFFICIENT_BALANCE: ['Chưa đủ xu để đổi phần thưởng này.', "You don't have enough coins for this reward yet."],
  ITEM_NOT_FOUND: ['Phần thưởng này không còn nữa.', 'This reward is no longer available.'],
  NETWORK: ['Lỗi mạng. Chưa trừ xu. Vui lòng thử lại.', 'Network error. No coins were spent. Please try again.'],
  NOT_AVAILABLE: ['Đổi thưởng đang tạm tắt. Chưa trừ xu.', 'Redeeming is switched off right now. No coins were spent.'],
  TRY_AGAIN: ['Vui lòng thử lại.', 'Please try again.'],
};

// Account > Rewards & badges. Private to the signed-in account. Every number is server-computed
// (migration 165); coins are cosmetic only and never affect booking, priority or eligibility.
export default function Rewards() {
  const { state: s, T, set, loadRewards, redeemReward, setRewardTimezone, setOutingGoal, openEditProfile, rewardsEnabled, rewardsV2Enabled } = useBanBe();
  const manifest = useKeychainManifest();
  const [confirmCode, setConfirmCode] = useState(null);
  const [tzBusy, setTzBusy] = useState(false);
  const [tzError, setTzError] = useState('');
  const [goalBusy, setGoalBusy] = useState(false);
  const [goalError, setGoalError] = useState('');
  const [celebration, setCelebration] = useState(null); // { title, sub, n } — one at a time
  const celebrateTimer = useRef(null);

  useEffect(() => { if (s.user?.id) loadRewards(); }, [s.user?.id, loadRewards]);
  // Hidden by an admin (migration 187): leave through Back's own target, whether this was a deep link or the flag
  // flipped while the screen was open. Nothing is rendered meanwhile.
  useEffect(() => { if (!rewardsEnabled) set({ screen: s.rewardsBack === 'home' ? 'home' : 'profile' }); }, [rewardsEnabled]); // eslint-disable-line react-hooks/exhaustive-deps

  const r = s.rewards;
  const loading = s.rewardsStatus === 'loading' || s.rewardsStatus === 'idle';
  const lang = s.lang;
  const nameOf = (id) => { const d = manifest.designs.find(x => x.id === id); return d ? (lang === 'en' ? d.en : d.vi) : id; };
  const confirmItem = r?.catalog?.find(c => c.code === confirmCode) || null;
  const res = s.rewardsRedeemResult;
  const tz = normalizeTzSettings(r?.timezone_settings);
  const { designs, offers, showOffers } = splitRewardCatalog(r);
  const deviceHint = deviceTimezoneHint();
  const v2 = rewardsV2Enabled;
  const ws = v2 ? normalizeWeekStreak(r?.week_streak) : null;
  const goal = v2 ? normalizeGoal(r?.goal) : null;
  const nb = v2 && r?.next_badge && typeof r.next_badge.code === 'string' ? r.next_badge : null;

  // Celebrate a newly earned badge / week milestone ONCE per device (peak moment), never an existing collection on a
  // new device. Reduced motion: the confetti is hidden by CSS; the card still says what happened.
  const showCelebration = (c) => {
    clearTimeout(celebrateTimer.current);
    setCelebration({ ...c, n: (celebration?.n || 0) + 1 });
    celebrateTimer.current = setTimeout(() => setCelebration(null), 3600);
  };
  useEffect(() => () => clearTimeout(celebrateTimer.current), []);
  useEffect(() => {
    const uid = s.user?.id;
    if (!uid || !r || s.rewardsStatus !== 'loaded') return;
    const { show, keys } = celebrationDiff(r.badges, ws, readCelebrated(uid));
    writeCelebrated(uid, keys);
    if (!show.length) return;
    const first = show[0];
    if (first.kind === 'badge') {
      const b = r.badges.find(x => x.code === first.code);
      showCelebration({ title: T('Huy hiệu mới!', 'New badge!'), sub: b ? (lang === 'en' ? b.title_en : b.title_vi) : '' });
      track('rewards_badge_celebrated', { code: first.code });
    } else {
      showCelebration({ title: T(`Chuỗi ${first.weeks} tuần!`, `${first.weeks}-week streak!`), sub: T('Bạn đã ra ngoài đều đặn. Tuyệt!', "You've kept showing up. Nice!") });
      track('rewards_week_milestone', { weeks: first.weeks });
    }
  }, [r, s.rewardsStatus]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (res && res.ok && !res.already) showCelebration({ title: T('Đã mở khoá!', 'Unlocked!'), sub: T('Mẫu móc khoá mới đã sẵn sàng.', 'Your new keychain design is ready.') });
  }, [res]); // eslint-disable-line react-hooks/exhaustive-deps

  const pickGoal = async (g) => {
    if (goalBusy) return;
    setGoalBusy(true); setGoalError('');
    const out = await setOutingGoal(g);
    setGoalBusy(false);
    if (out && !out.ok) { const m = GOAL_ERRORS[out.error] || GOAL_ERRORS.NETWORK; setGoalError(T(m[0], m[1])); }
    else track('rewards_goal_set', { goal: g });
  };

  const doRedeem = async () => {
    const code = confirmCode;
    setConfirmCode(null);
    if (code) await redeemReward(code);
  };

  if (!rewardsEnabled) return null;

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Rewards">
      <div onClick={() => set({ screen: s.rewardsBack === 'home' ? 'home' : 'profile' })} role="button" style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="rewards-back">
        ‹ {s.rewardsBack === 'home' ? T('Trang chủ', 'Home') : T('Tài khoản', 'Account')}
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
                {r.balance < 0 && <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Số dư âm do điểm danh bị huỷ. Kiếm thêm để về 0.', 'Negative because a check-in was undone. Earn coins to get back to 0.')}</span>}
              </div>
              {ws ? (
                <div data-testid="rewards-week-streak" style={{ ...fieldGlass({ flex: 1, padding: '16px 16px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 4 }) }}>
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Chuỗi tuần', 'Week streak')}</span>
                  <span style={{ ...display(30), display: 'flex', alignItems: 'center', gap: 6 }} aria-label={weeksLabel(T, ws.current)}><span aria-hidden="true">🔥</span>{ws.current}</span>
                  <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T(`Dài nhất: ${ws.longest} tuần`, `Longest: ${weeksLabel(T, ws.longest)}`)}</span>
                  {(() => { const h = weekStreakHint(T, ws, lang); return (
                    <>
                      <span data-testid="rewards-streak-status" style={{ fontSize: 11.5, fontWeight: 600, color: ink, marginTop: 6 }}>{h.status}</span>
                      <span data-testid="rewards-streak-how" style={{ fontSize: 11, lineHeight: 1.4, color: ink, opacity: 0.75 }}>{h.how}</span>
                    </>
                  ); })()}
                  {ws.graceMax > 0 && (
                    <span data-testid="rewards-grace" style={{ fontSize: 11, color: ink, opacity: 0.75, marginTop: 4, display: 'flex', alignItems: 'center', gap: 4 }}>
                      <span aria-hidden="true">{'🛡'.repeat(ws.graceHeld)}{'·'.repeat(Math.max(0, ws.graceMax - ws.graceHeld))}</span>{graceLine(T, ws)}
                    </span>
                  )}
                </div>
              ) : (
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
                )}
            </div>
              )}
            </div>

            {/* Next badge (goal gradient, 192): the closest visible badge, with honest numbers. */}
            {nb && (
              <section data-testid="rewards-next-badge" style={{ ...fieldGlass({ padding: '14px 16px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 6 }) }}>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Huy hiệu tiếp theo', 'Next badge')}</span>
                <span style={{ fontSize: 14, fontWeight: 600, color: ink }}>{nextBadgeLine(T, nb, lang)}</span>
                <div role="progressbar" aria-valuemin={0} aria-valuemax={nb.target} aria-valuenow={nb.progress}
                  aria-label={`${lang === 'en' ? nb.title_en : nb.title_vi}: ${nb.progress} / ${nb.target}`}
                  style={{ height: 6, borderRadius: 3, background: rule, overflow: 'hidden' }}>
                  <div style={{ width: `${Math.round((Math.min(nb.progress, nb.target) / nb.target) * 100)}%`, height: '100%', background: ink }} />
                </div>
                <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{nb.progress} / {nb.target}</span>
              </section>
            )}

            {/* Monthly outing goal (192): self-chosen, no coins. */}
            {goal && (
              <section data-testid="rewards-goal" style={{ ...fieldGlass({ padding: '14px 16px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 10 }) }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  {goal.target !== null && (() => {
                    const pct = Math.min(goal.progress, goal.target) / goal.target; const R = 16; const C = 2 * Math.PI * R;
                    return (
                      <svg width="40" height="40" viewBox="0 0 40 40" aria-hidden="true" style={{ flex: 'none' }}>
                        <circle cx="20" cy="20" r={R} fill="none" stroke={rule} strokeWidth="4" />
                        <circle cx="20" cy="20" r={R} fill="none" stroke={ink} strokeWidth="4" strokeLinecap="round"
                          strokeDasharray={`${C * pct} ${C}`} transform="rotate(-90 20 20)" />
                      </svg>
                    );
                  })()}
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                    <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{T('Mục tiêu tháng này', 'My goal this month')}</span>
                    <span data-testid="rewards-goal-line" style={{ fontSize: 12, lineHeight: 1.45, color: ink, opacity: 0.8 }}>{goalLine(T, goal)}</span>
                  </div>
                </div>
                <div role="group" aria-label={T('Số sự kiện mỗi tháng', 'Events per month')} style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                  {[0, ...GOAL_CHOICES].map(g => {
                    const on = (goal.target ?? 0) === g;
                    return (
                      <span key={g} role="button" tabIndex={0} aria-pressed={on} aria-disabled={goalBusy} data-testid={`rewards-goal-${g}`}
                        onClick={() => !on && pickGoal(g)} onKeyDown={(e) => { if ((e.key === 'Enter' || e.key === ' ') && !on) { e.preventDefault(); pickGoal(g); } }}
                        style={{ fontSize: 12.5, fontWeight: 600, padding: '8px 14px', borderRadius: 999, cursor: on || goalBusy ? 'default' : 'pointer',
                          border: `1px solid ${on ? ink : rule}`, background: on ? ink : 'transparent', color: on ? paper : ink, opacity: goalBusy ? 0.6 : 1 }}>
                        {g === 0 ? T('Không đặt', 'None') : T(`${g} / tháng`, `${g} / month`)}
                      </span>
                    );
                  })}
                </div>
                {goalError && <span role="alert" style={{ fontSize: 12, color: alert }}>{goalError}</span>}
              </section>
            )}

            {/* Badges */}
            <section data-testid="rewards-badges">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 8px', color: ink }}>{T('Huy hiệu', 'Badges')}</h2>
              {v2 ? (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {groupBadgesByFamily(r.badges).map(g => {
                    const fam = BADGE_FAMILIES[g.family];
                    const head = g.next || g.top;
                    const famTitle = fam ? T(fam[0], fam[1]) : (lang === 'en' ? head.title_en : head.title_vi);
                    return (
                      <div key={g.family} data-testid={`badge-family-${g.family}`} style={{ ...fieldGlass({ padding: '12px 14px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 6 }) }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'center' }}>
                          <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{famTitle}</span>
                          <span aria-label={T(`Đã đạt ${g.earnedCount}/${g.badges.length} cấp`, `${g.earnedCount} of ${g.badges.length} tiers earned`)} style={{ display: 'flex', gap: 4 }}>
                            {g.badges.map(b => (
                              <span key={b.code} data-testid={`badge-${b.code}`} data-earned={b.earned ? 'true' : 'false'} title={lang === 'en' ? b.title_en : b.title_vi}
                                style={{ width: 10, height: 10, borderRadius: 5, border: `1.5px solid ${ink}`, background: b.earned ? ink : 'transparent' }} />
                            ))}
                          </span>
                        </div>
                        {g.top && <span style={{ fontSize: 12, color: ink }}>✓ {lang === 'en' ? g.top.title_en : g.top.title_vi}{g.top.earned_at ? ` ▪︎ ${new Date(g.top.earned_at).toLocaleDateString(lang === 'en' ? 'en-US' : 'vi-VN')}` : ''}</span>}
                        {g.next ? (
                          <>
                            <span style={{ fontSize: 12, color: ink, opacity: 0.75 }}>{T('Tiếp theo', 'Next')}: {lang === 'en' ? g.next.title_en : g.next.title_vi} ▪︎ {lang === 'en' ? g.next.desc_en : g.next.desc_vi}</span>
                            <div role="progressbar" aria-valuemin={0} aria-valuemax={g.next.target} aria-valuenow={Math.min(g.next.progress, g.next.target)}
                              aria-label={`${lang === 'en' ? g.next.title_en : g.next.title_vi}: ${Math.min(g.next.progress, g.next.target)} / ${g.next.target}`}
                              style={{ height: 6, borderRadius: 3, background: rule, overflow: 'hidden' }}>
                              <div style={{ width: `${Math.round((Math.min(g.next.progress, g.next.target) / g.next.target) * 100)}%`, height: '100%', background: ink }} />
                            </div>
                            <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{Math.min(g.next.progress, g.next.target)} / {g.next.target}</span>
                          </>
                        ) : <span style={{ fontSize: 12, color: ink, opacity: 0.75 }}>{T('Đã đạt mọi cấp ✓', 'Every tier earned ✓')}</span>}
                      </div>
                    );
                  })}
                </div>
              ) : (
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
              )}
            </section>

            {/* Redemption catalog */}
            <section data-testid="rewards-catalog">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 4px', color: ink }}>{T('Trang trí (móc khoá)', 'Decorations (keychain designs)')}</h2>
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
                {designs.map(c => {
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

            {/* Partner offers (migration 179): hidden unless the server sends any. Display only; there is no redemption yet. */}
            {showOffers && (
              <section data-testid="rewards-offers">
                <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 4px', color: ink }}>{T('Ưu đãi', 'Offers')}</h2>
                <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '0 0 10px' }}>
                  {T('Ưu đãi do đối tác cung cấp. Hiện chưa thể đổi.', 'Offers come from partners. They cannot be redeemed yet.')}
                </p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {offers.map(o => (
                    <div key={o.code} data-testid={`offer-${o.code}`} style={{ ...fieldGlass({ padding: '12px 14px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 4 }) }}>
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{lang === 'en' ? o.title_en : o.title_vi}</span>
                      {(lang === 'en' ? o.desc_en : o.desc_vi) && <span style={{ fontSize: 12, color: ink, opacity: 0.75 }}>{lang === 'en' ? o.desc_en : o.desc_vi}</span>}
                      <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Chưa khả dụng', 'Not available yet')}</span>
                    </div>
                  ))}
                </div>
              </section>
            )}

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

            {/* Time zone (suggestion only; nothing is assigned automatically) */}
            {tz && (
              <section data-testid="rewards-timezone">
                <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 8px', color: ink }}>{T('Múi giờ cho chuỗi ngày', 'Time zone for streak days')}</h2>
                <div style={{ ...fieldGlass({ padding: '12px 14px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 8 }) }}>
                  <select value={tz.pending || tz.effective} disabled={tzBusy || (tz.changesLeft === 0 && !tz.pending)} data-testid="rewards-timezone-select" aria-label={T('Múi giờ', 'Time zone')}
                    onChange={async (e) => {
                      setTzBusy(true); setTzError('');
                      const out = await setRewardTimezone(e.target.value);
                      setTzBusy(false);
                      if (out && !out.ok) { const m = TZ_ERRORS[out.error] || TZ_ERRORS.NETWORK; setTzError(T(m[0], m[1])); }
                    }}
                    style={{ fontSize: 13, color: ink, background: 'transparent', border: `1px solid ${rule}`, borderRadius: 10, padding: '9px 10px' }}>
                    {[...SUGGESTED_TIMEZONES, ...(SUGGESTED_TIMEZONES.some(z => z[0] === tz.effective) ? [] : [[tz.effective, tz.effective, tz.effective]])].map(([id, vi, en]) => (
                      <option key={id} value={id}>{T(vi, en)}{id === deviceHint ? T(' (gợi ý theo thiết bị)', ' (suggested from your device)') : ''}</option>
                    ))}
                  </select>
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }}>
                    {tz.pending
                      ? T(`Đổi sang ${tz.pending} có hiệu lực từ ngày kế tiếp.`, `The change to ${tz.pending} takes effect from the next day.`)
                      : tz.chosen ? T('Đổi múi giờ có hiệu lực từ ngày kế tiếp, tối đa 2 lần mỗi 30 ngày.', 'A change takes effect from the next day, at most twice per 30 days.')
                                  : T('Mặc định là giờ Việt Nam. Chọn múi giờ của bạn nếu khác.', 'Defaults to Vietnam time. Pick yours if different.')}
                  </span>
                  {tzError && <span role="alert" style={{ fontSize: 12, color: alert }}>{tzError}</span>}
                </div>
              </section>
            )}

            {/* Rules */}
            <section data-testid="rewards-rules">
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '0 0 8px', color: ink }}>{T('Cách kiếm xu', 'How earning works')}</h2>
              <ul style={{ margin: 0, paddingInlineStart: 18, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {[...ruleLines(r.rules, T), ...noCoinLines(T), ...(ws ? weekStreakLines(T, ws) : streakLines(T, r.streak?.current, r.streak?.timezone))].map((l, i) => (
                  <li key={i} style={{ fontSize: 12.5, lineHeight: 1.5, color: ink }}>{l}</li>
                ))}
              </ul>
              <h2 style={{ fontSize: 13, fontWeight: 600, margin: '16px 0 8px', color: ink }}>{T('Điều kiện đổi thưởng', 'Redemption terms')}</h2>
              <ul style={{ margin: 0, paddingInlineStart: 18, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {redemptionTermsLines(T, !!ws).map((l, i) => <li key={i} style={{ fontSize: 12.5, lineHeight: 1.5, color: ink }}>{l}</li>)}
              </ul>
              <p style={{ fontSize: 11, color: ink, opacity: 0.6, margin: '12px 0 0' }}>{T(`Phiên bản quy tắc ${r.rules?.version ?? 1}. Các con số là đề xuất MVP và có thể thay đổi. Mọi thay đổi có số phiên bản mới.`, `Rules version ${r.rules?.version ?? 1}. Numbers are an MVP proposal and may change. Any change gets a new version.`)}</p>
            </section>
          </>
        )}
      </div>

      {celebration && (
        <div role="status" aria-live="polite" data-testid="rewards-celebration" onClick={() => setCelebration(null)}
          style={{ position: 'fixed', left: 0, right: 0, top: 84, display: 'flex', justifyContent: 'center', zIndex: 55, padding: '0 16px', pointerEvents: 'auto' }}>
          <div style={{ position: 'relative', background: paper, color: ink, borderRadius: 16, padding: '14px 18px', boxShadow: '0 10px 30px rgba(27,25,22,0.18)',
            border: `1px solid ${rule}`, maxWidth: 340, width: '100%', display: 'flex', flexDirection: 'column', gap: 2, textAlign: 'center', animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
            <ConfettiBurst key={celebration.n} top={10} />
            <span style={{ ...display(18) }}>{celebration.title}</span>
            {celebration.sub && <span style={{ fontSize: 12.5, opacity: 0.8 }}>{celebration.sub}</span>}
          </div>
        </div>
      )}

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
