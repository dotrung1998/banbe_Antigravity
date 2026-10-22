import { useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, fieldGlass, alert } from '../theme.js';
import GlassSwitch from '../components/ui/GlassSwitch.jsx';
import { flagOn } from '../lib/featureFlags.js';

// Admin > Feature switches (migration 187, note 51). One row per platform feature flag. Turning a switch off hides
// the feature everywhere (web + iOS, signed-in and signed-out) without a release; turning it on shows it again.
// The server decides who may flip it (is_platform_admin() inside admin_set_feature_flag, audited); this screen
// only calls it, and the switch moves only after the server accepted the change.
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
    hintVi: 'Chuỗi theo tuần với tuần nghỉ và khôi phục, huy hiệu nhiều cấp, huy hiệu tiếp theo và mục tiêu tháng (migration 192). Mặc định tắt; cần bật Phần thưởng.',
    hintEn: 'Weekly streak with grace weeks and repair, tiered badges, next badge and a monthly goal (migration 192). Off by default; needs Rewards on.',
  },
];

const ERRORS = {
  NOT_AUTHORIZED: ['Bạn không có quyền.', 'You are not allowed to do this.'],
  INVALID_VALUE: ['Giá trị không hợp lệ.', 'Invalid value.'],
  NOT_DEPLOYED: ['Máy chủ chưa có công tắc này (chạy migration 187/192).', 'The server does not have this switch yet (apply migration 187/192).'],
  NETWORK: ['Không kết nối được. Thử lại nhé.', "Couldn't reach the server. Try again."],
  BUSY: ['Đang xử lý…', 'Working…'],
};

export default function AdminFeatures() {
  const { state: s, T, set, setFeatureFlag, loadFeatureFlags } = useBanBe();
  const [error, setError] = useState('');
  if (s.accountType !== 'admin') return null;

  const flip = async (key, enabled) => {
    setError('');
    const r = await setFeatureFlag(key, enabled);
    if (!r.ok) { const m = ERRORS[r.error] || ERRORS.NETWORK; setError(T(m[0], m[1])); loadFeatureFlags(); }
  };

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
        <div style={{ ...fieldGlass({ marginTop: 22, display: 'flex', flexDirection: 'column' }) }}>
          {FLAGS.map((f, i) => {
            const on = flagOn(s.featureFlags, f.key);
            return (
              <div key={f.key} data-testid={`admin-flag-${f.key}`} data-on={on}
                style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px', borderTop: i ? '1px solid var(--bb-rule)' : 'none' }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 15.5, fontWeight: 600 }}>{T(f.vi, f.en)}</div>
                  <div style={{ fontSize: 12.5, lineHeight: 1.45, opacity: 0.7, marginTop: 3 }}>{T(f.hintVi, f.hintEn)}</div>
                  <div data-testid={`admin-flag-${f.key}-state`} style={{ fontSize: 12, fontWeight: 600, marginTop: 6, opacity: on ? 1 : 0.7 }}>
                    {on ? T('Đang hiện cho mọi người', 'Visible to everyone') : T('Đang ẩn với mọi người', 'Hidden from everyone')}
                  </div>
                </div>
                <GlassSwitch on={on} busy={s.featureFlagBusy === f.key} testId={`admin-flag-${f.key}-switch`} onPress={() => flip(f.key, !on)} />
              </div>
            );
          })}
        </div>
        {error && <p role="alert" data-testid="admin-features-error" style={{ fontSize: 12.5, color: alert, margin: '12px 2px 0' }}>{error}</p>}
      </div>
    </div>
  );
}
