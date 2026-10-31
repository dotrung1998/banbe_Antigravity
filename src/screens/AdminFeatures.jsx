import { useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, fieldGlass, alert, honey, inkButton } from '../theme.js';
import GlassSwitch from '../components/ui/GlassSwitch.jsx';
import { flagOn, onboardingVersion } from '../lib/featureFlags.js';
import { FLAG_CATEGORIES, ONBOARDING_CONTROL, keysOf } from '../lib/featureFlagCategories.js';
import { useReducedMotion } from '../lib/useReducedMotion.js';

// Admin > Feature switches (migration 187, note 51). One row per platform feature flag. Turning a switch off hides
// the feature everywhere (web + iOS, signed-in and signed-out) without a release; turning it on shows it again.
// The server decides who may flip it (is_platform_admin() inside admin_set_feature_flag, audited); this screen
// only calls it, and the switch moves only after the server accepted the change.
// Note 64: rows are grouped into collapsible categories (src/lib/featureFlagCategories.js), all collapsed on open.
const FLAGS = [
  {
    key: 'rewards',
    vi: 'Phần thưởng & huy hiệu',
    en: 'Rewards & badges',
    hintVi: 'Ẩn xu, chuỗi ngày, huy hiệu và mẫu móc khoá thưởng khỏi toàn bộ ứng dụng. Dữ liệu không bị xoá.',
    hintEn: 'Hides coins, streaks, badges and reward keychain designs everywhere in the app. No data is deleted.',
  },
  {
    key: 'rewards_v2',
    vi: 'Phần thưởng v2: chuỗi tuần, cấp huy hiệu, mục tiêu',
    en: 'Rewards v2: week streak, badge tiers, goals',
    hintVi: 'Chuỗi theo tuần với tuần nghỉ và khôi phục, huy hiệu nhiều cấp, huy hiệu tiếp theo và mục tiêu tháng (migration 192). Mặc định tắt. Cần bật Phần thưởng.',
    hintEn: 'Weekly streak with grace weeks and repair, tiered badges, next badge and a monthly goal (migration 192). Off by default. Needs Rewards on.',
    // Note 69: on while Rewards is off shows nothing anywhere; the row says so instead of "Visible to everyone".
    requires: 'rewards',
  },
  {
    key: 'push_enabled',
    vi: 'Thông báo đẩy (iPhone)',
    en: 'Push notifications (iPhone)',
    hintVi: 'Gửi thông báo đẩy qua Apple cho người đã cho phép, ngoài giờ yên lặng 22:00–07:00. Cần khoá APNs; khi chưa có khoá, hệ thống chỉ chạy thử và không gửi gì (migration 194). Mặc định tắt.',
    hintEn: 'Sends push notifications through Apple to people who allowed them, outside quiet hours 22:00–07:00. Needs the APNs key; without it the server only does a dry run and sends nothing (migration 194). Off by default.',
  },
  {
    key: 'app_events',
    vi: 'Đo lường sản phẩm (của banbe)',
    en: 'Product measurement (first-party)',
    hintVi: 'Ghi nhận ẩn danh hoá các thao tác chính (mở ứng dụng, mở sự kiện, mở vé…) vào cơ sở dữ liệu của banbe để đo tỉ lệ quay lại. Không dùng công cụ bên thứ ba, không ghi nội dung trò chuyện, ngân hàng hay câu trả lời. Mặc định tắt.',
    hintEn: "Records key actions (app opened, event opened, ticket opened…) in banbe's own database to measure how often people come back. No third-party tools; never chat, bank or answer content. Off by default.",
  },
  {
    key: 'event_reminders',
    vi: 'Nhắc lịch sự kiện',
    en: 'Event reminders',
    hintVi: 'Nhắc người có vé một ngày trước và khoảng 3 giờ trước sự kiện, trong ứng dụng (và thông báo đẩy khi đã bật). Người dùng tắt được từng loại. Mặc định bật.',
    hintEn: 'Reminds ticket holders the day before and about 3 hours before their event, in the app (and by push when push is on). People can mute each kind. On by default.',
  },
  {
    key: 'event_recap',
    vi: 'Tổng kết cho khách + cảm nhận riêng',
    en: 'Guest recap + private feedback',
    hintVi: 'Sau khi sự kiện kết thúc, khách có vé nhận một thông báo tổng kết và có thể gửi cảm nhận riêng cho host (host chỉ thấy khi có từ 3 người trả lời). Thu thập dữ liệu mới: cần quyết định về đồng ý lại theo Điều B12 trước khi bật. Mặc định tắt.',
    hintEn: 'After an event ends, ticket holders get a recap and can send private feedback to the host (shown to the host only from 3 answers). Collects new data: needs the B12 re-consent decision before turning on. Off by default.',
  },
  {
    key: 'host_recap',
    vi: 'Tổng kết cho host',
    en: 'Host recap',
    hintVi: 'Host nhận tổng kết sau sự kiện: số chỗ, số người vào cửa, người theo dõi mới, khách quay lại, cảm nhận (từ 3 người), và nút Tổ chức lại. Mặc định tắt.',
    hintEn: 'Hosts get a recap after the event: seats, check-ins, new followers, returning guests, feedback (from 3 answers) and Run it again. Off by default.',
  },
  {
    key: 'follow_alerts',
    vi: 'Báo sự kiện mới từ host đang theo dõi',
    en: 'Alerts from followed hosts',
    hintVi: 'Tối đa một thông báo gộp mỗi ngày, 09:00–20:00 giờ của người dùng, khi host họ theo dõi đăng sự kiện mới. Người dùng tắt được. Mặc định tắt.',
    hintEn: 'At most one bundled notice a day, 09:00–20:00 on the person\'s clock, when hosts they follow publish. People can mute it. Off by default.',
  },
  {
    key: 'weekly_digest',
    vi: 'Bản tin cuối tuần (quảng bá)',
    en: 'Weekly digest (promotional)',
    hintVi: 'Chỉ gửi cho người tự bật đồng ý, thứ Năm 18:00 giờ của họ, không gửi khi không có sự kiện. Là tin quảng bá: cần rà soát pháp lý (Nghị định 91/2020, CAN-SPAM) trước khi bật. Mặc định tắt.',
    hintEn: 'Sent only to people who opted in, Thursday 18:00 on their clock, never when there is nothing to show. Promotional: needs legal review (Decree 91/2020, CAN-SPAM) before turning on. Off by default.',
  },
  {
    key: 'intent_foryou',
    vi: 'Dành cho bạn theo mục tiêu',
    en: 'For You by goal',
    hintVi: 'Tiêu đề và lời giải thích của mục Dành cho bạn theo mục tiêu người dùng đã chọn khi bắt đầu (chỉ câu trả lời họ tự chọn). Mặc định tắt.',
    hintEn: 'For You title and explanation follow the goal people chose in onboarding (their own answers only). Off by default.',
  },
  {
    key: 'live_activity',
    vi: 'Thẻ ngày sự kiện trên Màn hình khoá (iPhone)',
    en: 'Event-day Lock Screen card (iPhone)',
    hintVi: 'Vào ngày sự kiện, iPhone hiện tên, giờ và địa điểm trên Màn hình khoá cho người có vé. Tạo ngay trên máy. Cần kiểm tra trên thiết bị thật trước khi bật. Mặc định tắt.',
    hintEn: 'On event day, the iPhone shows the event name, time and place on the Lock Screen for ticket holders. Created on the device. Check on a real device before turning on. Off by default.',
  },
  {
    key: 'market_share',
    vi: 'Chia sẻ qua Zalo / Nhắn tin',
    en: 'Share via Zalo / Text',
    hintVi: 'Thêm nút chia sẻ qua Zalo (sự kiện ở Việt Nam) và Nhắn tin cho bạn (sự kiện ở Mỹ) cạnh nút chia sẻ của hệ thống. Mặc định tắt.',
    hintEn: 'Adds Share via Zalo (Vietnam events) and Text a friend (US events) next to the system share. Off by default.',
  },
  {
    // Migration 201, note 63: a version picker on top of a boolean switch (off = Version 1, on = Version 2).
    key: 'onboarding_v2',
    vi: 'Bản giới thiệu: Phiên bản 2',
    en: 'Onboarding demo: Version 2',
    hintVi: 'Tắt = Phiên bản 1: màn Chào mừng tĩnh và 4 trang chữ "banbe hoạt động thế nào". Bật = Phiên bản 2: màn Chào mừng có chuyển động và mỗi phần có các màn demo vuốt qua lại. Mặc định tắt.',
    hintEn: 'Off = Version 1: still Welcome screen and the 4 text pages of "How banbe works". On = Version 2: animated Welcome entrance and swipeable demo screens in each section. Off by default.',
    stateOn: ['Đang dùng Phiên bản 2', 'Showing Version 2'],
    stateOff: ['Đang dùng Phiên bản 1', 'Showing Version 1'],
  },
  {
    // Migration 203, note 65.
    key: 'event_type_profiles',
    vi: 'Biểu mẫu theo loại sự kiện',
    en: 'Event-type forms',
    hintVi: 'Màn tạo sự kiện, trang sự kiện và Trang chủ thay đổi theo loại sự kiện. Hiện có Supper club: chế độ ăn, mang đồ uống, trang phục, bộ lọc riêng trên Trang chủ. Mặc định tắt.',
    hintEn: 'The create form, the event page and Home adapt to the kind of event. Supper club first: dietary options, BYO, dress code, its own Home filters. Off by default.',
  },
  {
    // Migration 206, note 66.
    key: 'simple_shell',
    vi: 'Bố cục gọn (Simple Shell)',
    en: 'Simple Shell layout',
    hintVi: 'Trang chủ gọn: nút chuyển Đi chơi | Tổ chức luôn hiện, một khối chính ở trên cùng, bản đồ là một kiểu xem của Trang chủ. Thanh dưới có 5 ô với nút "+" ở giữa cho mọi người. Mặc định tắt.',
    hintEn: 'Simpler Home: an always-visible Going out | Hosting switch, one main block at the top, and the map as a Home view. The dock has 5 slots with a "+" in the centre for everyone. Off by default.',
  },
  {
    // Migration 208, note 71.
    key: 'polaroid_cards',
    vi: 'Thẻ sự kiện kiểu polaroid',
    en: 'Polaroid event cards',
    hintVi: 'Thẻ sự kiện trên Trang chủ có khung giấy quanh ảnh và chú thích bên dưới, như ảnh polaroid. Chỉ đổi kiểu xem thẻ, không đổi danh sách. Mặc định tắt.',
    hintEn: 'Home event cards get a paper frame around the photo with the caption below, like a polaroid. Only the cards view changes, not the list. Off by default.',
  },
];

const ERRORS = {
  NOT_AUTHORIZED: ['Bạn không có quyền.', 'You are not allowed to do this.'],
  INVALID_VALUE: ['Giá trị không hợp lệ.', 'Invalid value.'],
  NOT_DEPLOYED: ['Máy chủ chưa có công tắc này. Cần chạy migration mới nhất.', "The server doesn't have this switch yet. Apply the latest migrations."],
  NETWORK: ['Không kết nối được. Thử lại nhé.', "Couldn't reach the server. Try again."],
  BUSY: ['Đang xử lý…', 'Working…'],
};

const VERSION_HINT = [
  'Phiên bản 1: màn Chào mừng tĩnh và 4 trang chữ "banbe hoạt động thế nào". Phiên bản 2: màn Chào mừng có chuyển động và các màn demo vuốt qua lại. Phiên bản 3: như Phiên bản 2, cộng thêm hướng dẫn trên giao diện thật ngay sau khi đăng nhập lần đầu.',
  'Version 1: still Welcome screen and the 4 text pages of "How banbe works". Version 2: animated Welcome and swipeable demo screens. Version 3: Version 2 plus a guided tour over the real app right after the first sign-in.',
];

const flagTitle = (key, T) => { const f = FLAGS.find(x => x.key === key); return f ? T(f.vi, f.en) : key; };

function FlagRow({ f, first, s, T, flip, askRequires }) {
  const on = flagOn(s.featureFlags, f.key);
  // Note 69: the switch this one needs, when that one is off (iOS twin AdminFeaturesView `requires`).
  const blockedBy = f.requires && !flagOn(s.featureFlags, f.requires) ? f.requires : null;
  return (
    <div data-testid={`admin-flag-${f.key}`} data-on={on}
      style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px', borderTop: first ? 'none' : '1px solid var(--bb-rule)' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 15.5, fontWeight: 600 }}>{T(f.vi, f.en)}</div>
        <div style={{ fontSize: 12.5, lineHeight: 1.45, opacity: 0.7, marginTop: 3 }}>{T(f.hintVi, f.hintEn)}</div>
        {on && blockedBy ? (
          <>
            <div data-testid={`admin-flag-${f.key}-state`} data-blocked="true" style={{ fontSize: 12, fontWeight: 600, marginTop: 6, color: honey }}>
              {T(`Chưa có tác dụng: hãy bật "${flagTitle(blockedBy, T)}" trước`, `No effect yet: turn on "${flagTitle(blockedBy, T)}" first`)}
            </div>
            <button type="button" data-testid={`admin-flag-${f.key}-enable-required`} disabled={!!s.featureFlagBusy}
              onClick={() => flip(blockedBy, true)}
              style={{ minHeight: 44, padding: 0, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, textDecoration: 'underline', cursor: 'pointer' }}>
              {T(`Bật "${flagTitle(blockedBy, T)}"`, `Turn on "${flagTitle(blockedBy, T)}"`)}
            </button>
          </>
        ) : (
          <div data-testid={`admin-flag-${f.key}-state`} style={{ fontSize: 12, fontWeight: 600, marginTop: 6, opacity: on ? 1 : 0.7 }}>
            {f.stateOn ? (on ? T(...f.stateOn) : T(...f.stateOff))
              : on ? T('Đang hiện cho mọi người', 'Visible to everyone') : T('Đang ẩn với mọi người', 'Hidden from everyone')}
          </div>
        )}
      </div>
      <GlassSwitch on={on} busy={s.featureFlagBusy === f.key} testId={`admin-flag-${f.key}-switch`}
        onPress={() => (!on && blockedBy ? askRequires(f) : flip(f.key, !on))} />
    </div>
  );
}

/** Migration 202: one 1/2/3 control instead of a v2 switch, so two versions can never be on at once. */
function OnboardingVersionRow({ first, s, T, pick }) {
  const v = onboardingVersion(s.featureFlags);
  const busy = s.featureFlagBusy === ONBOARDING_CONTROL;
  return (
    <div data-testid="admin-onboarding-version" data-version={v}
      style={{ padding: '16px 18px', borderTop: first ? 'none' : '1px solid var(--bb-rule)' }}>
      <div id="admin-onboarding-version-label" style={{ fontSize: 15.5, fontWeight: 600 }}>{T('Bản giới thiệu', 'Onboarding version')}</div>
      <div style={{ fontSize: 12.5, lineHeight: 1.45, opacity: 0.7, marginTop: 3 }}>{T(...VERSION_HINT)}</div>
      <div role="radiogroup" aria-labelledby="admin-onboarding-version-label" aria-busy={busy || undefined}
        style={{ display: 'flex', gap: 4, padding: 3, marginTop: 10, borderRadius: 999, background: 'rgba(var(--bb-fg-rgb),0.06)', opacity: busy ? 0.6 : 1 }}>
        {[1, 2, 3].map(n => (
          <button key={n} type="button" role="radio" aria-checked={v === n} data-testid={`admin-onboarding-version-${n}`}
            onClick={() => { if (!busy && v !== n) pick(n); }}
            style={{ flex: 1, minHeight: 40, borderRadius: 999, border: 'none', cursor: busy ? 'default' : 'pointer', fontFamily: 'inherit',
              fontSize: 13.5, fontWeight: v === n ? 700 : 500, color: ink,
              background: v === n ? 'var(--bb-bg)' : 'transparent', boxShadow: v === n ? '0 1px 3px rgba(27,25,22,0.18)' : 'none' }}>
            {T(`Phiên bản ${n}`, `Version ${n}`)}
          </button>
        ))}
      </div>
    </div>
  );
}

export default function AdminFeatures() {
  const { state: s, T, set, setFeatureFlag, setOnboardingVersion, loadFeatureFlags } = useBanBe();
  const [error, setError] = useState('');
  // Independent sections, every one collapsed when the screen opens.
  const [open, setOpen] = useState({});
  // Note 69: a switch turned on while the switch it needs is off ("Also turn on …?").
  const [pending, setPending] = useState(null);
  const reduce = useReducedMotion();
  if (s.accountType !== 'admin') return null;

  const fail = (r) => { const m = ERRORS[r.error] || ERRORS.NETWORK; setError(T(m[0], m[1])); loadFeatureFlags(); };
  const flip = async (key, enabled) => {
    setError('');
    const r = await setFeatureFlag(key, enabled);
    if (!r.ok) fail(r);
  };
  const pickVersion = async (n) => {
    setError('');
    const r = await setOnboardingVersion(n);
    if (!r.ok) fail(r);
  };
  // Until migration 202 is on the server (no onboarding_v3 key comes back), keep the old Version 2 switch.
  const versionDeployed = Object.prototype.hasOwnProperty.call(s.featureFlags || {}, 'onboarding_v3');
  const byKey = Object.fromEntries(FLAGS.map(f => [f.key, f]));

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin feature switches">
      <div onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminReview' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-features-back">
        ‹ {T('Quản trị', 'Admin')}
      </div>
      <div style={{ padding: '14px 22px 40px' }}>
        <h1 style={{ ...display(26, { margin: 0 }) }}>{T('Công tắc tính năng', 'Feature switches')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Bật hoặc tắt một tính năng cho mọi người dùng, không cần phát hành bản mới. Mọi thay đổi đều được ghi lại.',
            'Turn a feature on or off for every user without a release. Every change is logged.')}
        </p>
        {FLAG_CATEGORIES.map(cat => {
          const isOpen = !!open[cat.key];
          const keys = cat.flags.flatMap(keysOf);
          const switches = cat.flags.filter(k => k !== ONBOARDING_CONTROL);
          const onCount = switches.filter(k => flagOn(s.featureFlags, k)).length;
          const bodyId = `admin-cat-${cat.key}-body`;
          return (
            <section key={cat.key} data-testid={`admin-cat-${cat.key}`} data-open={isOpen} data-keys={keys.join(' ')}
              style={{ ...fieldGlass({ marginTop: 14, display: 'flex', flexDirection: 'column' }) }}>
              <h2 style={{ margin: 0 }}>
                <button type="button" data-testid={`admin-cat-${cat.key}-toggle`} aria-expanded={isOpen} aria-controls={bodyId}
                  onClick={() => setOpen(o => ({ ...o, [cat.key]: !o[cat.key] }))}
                  style={{ width: '100%', minHeight: 52, display: 'flex', alignItems: 'center', gap: 10, padding: '14px 18px', border: 'none',
                    background: 'none', color: ink, fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
                  <span style={{ flex: 1, fontSize: 15.5, fontWeight: 700 }}>{T(cat.vi, cat.en)}</span>
                  {switches.length > 0 && (
                    <span data-testid={`admin-cat-${cat.key}-count`} style={{ fontSize: 12.5, opacity: 0.65, fontVariantNumeric: 'tabular-nums' }}>
                      {T(`${onCount}/${switches.length} bật`, `${onCount}/${switches.length} on`)}
                    </span>
                  )}
                  <svg aria-hidden="true" width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"
                    style={{ transform: `rotate(${isOpen ? 90 : 0}deg)`, transition: reduce ? 'none' : 'transform .2s ease', opacity: 0.6 }}>
                    <path d="M9 6l6 6-6 6" />
                  </svg>
                </button>
              </h2>
              <div id={bodyId} hidden={!isOpen} style={{ borderTop: '1px solid var(--bb-rule)' }}>
                {isOpen && cat.flags.map((k, i) => (k === ONBOARDING_CONTROL
                  ? (versionDeployed
                    ? <OnboardingVersionRow key={k} first={i === 0} s={s} T={T} pick={pickVersion} />
                    : <FlagRow key="onboarding_v2" f={byKey.onboarding_v2} first={i === 0} s={s} T={T} flip={flip} askRequires={setPending} />)
                  : <FlagRow key={k} f={byKey[k]} first={i === 0} s={s} T={T} flip={flip} askRequires={setPending} />))}
              </div>
            </section>
          );
        })}
        {error && <p role="alert" data-testid="admin-features-error" style={{ fontSize: 12.5, color: alert, margin: '12px 2px 0' }}>{error}</p>}
        {pending && (
          <div onClick={() => setPending(null)} data-testid="admin-flag-requires-dialog"
            style={{ position: 'fixed', inset: 0, zIndex: 50, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, background: 'rgba(27,25,22,0.32)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)' }}>
            <div onClick={e => e.stopPropagation()} role="alertdialog" aria-modal="true" aria-labelledby="admin-requires-title"
              style={{ ...fieldGlass({ padding: 22, borderRadius: 26, maxWidth: 340, width: '100%', background: 'var(--bb-card)' }) }}>
              <div id="admin-requires-title" style={{ ...display(19, { margin: 0 }) }}>
                {T(`Bật cả "${flagTitle(pending.requires, T)}"?`, `Also turn on "${flagTitle(pending.requires, T)}"?`)}
              </div>
              <p style={{ fontSize: 12.5, lineHeight: 1.55, opacity: 0.8, margin: '8px 0 0' }}>
                {T(`"${T(pending.vi, pending.en)}" chỉ hiện khi "${flagTitle(pending.requires, T)}" đang bật.`,
                   `"${T(pending.vi, pending.en)}" only shows while "${flagTitle(pending.requires, T)}" is on.`)}
              </p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 18 }}>
                <button type="button" autoFocus data-testid="admin-flag-requires-both"
                  onClick={async () => { const f = pending; setPending(null); await flip(f.requires, true); await flip(f.key, true); }}
                  style={{ ...inkButton({ padding: 13, borderRadius: 16, fontSize: 14 }), border: 'none', fontFamily: 'inherit' }}>
                  {T('Bật cả hai', 'Turn on both')}
                </button>
                <button type="button" data-testid="admin-flag-requires-only"
                  onClick={() => { const f = pending; setPending(null); flip(f.key, true); }}
                  style={{ ...fieldGlass({ padding: 13, borderRadius: 16, fontSize: 14 }), border: 'none', color: ink, fontFamily: 'inherit', cursor: 'pointer' }}>
                  {T('Chỉ bật mục này', 'Only this one')}
                </button>
                <button type="button" data-testid="admin-flag-requires-cancel" onClick={() => setPending(null)}
                  style={{ minHeight: 44, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer' }}>
                  {T('Huỷ', 'Cancel')}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
