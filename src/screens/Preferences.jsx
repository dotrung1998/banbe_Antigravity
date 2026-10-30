import { useState } from 'react';
import { getGlassOpacity, setGlassOpacity, glassCapsuleInactive } from '../lib/glassOpacity.js';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, rule, display, cardGlass } from '../theme.js';

export default function Preferences() {
  const { state, T, set, pickTheme, toggleAutoEmailDocuments } = useBanBe();
  const options = [
    { key: 'vi', title: 'Tiếng Việt', subtitle: T('Mặc định', 'Vietnamese') },
    { key: 'en', title: 'English', subtitle: T('Bạn có thể đổi lại bất cứ lúc nào', 'Switch anytime') },
  ];
  const themes = [
    { key: 'system', title: T('Theo thiết bị', 'System'), subtitle: T('Tự đổi sáng/tối theo máy của bạn', 'Follows your device') },
    { key: 'light', title: T('Sáng', 'Light'), subtitle: T('Nền giấy ấm', 'Warm paper') },
    { key: 'dark', title: T('Tối', 'Dark'), subtitle: T('Nền mực dịu mắt', 'Soft ink background') },
  ];

  return (
    <div style={{ animation: 'banbeFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="Preferences">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '16px 30px 42px' }}>
        <h1 style={{ ...display(27, { margin: 0, lineHeight: 1.2 }) }}>{T('Ngôn Ngữ & Hiển Thị', 'Language & Appearance')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>{T('Chọn cách banbe xuất hiện với bạn. Bạn có thể đổi lại bất cứ lúc nào.', 'Choose how banbe looks. You can change it anytime.')}</p>

        <Section title={T('Ngôn ngữ', 'Language')}>
          {options.map(option => (
            <Choice key={option.key} active={state.lang === option.key} title={option.title} subtitle={option.subtitle} onClick={() => set({ lang: option.key })} />
          ))}
        </Section>

        <Section title={T('Hiển thị', 'Appearance')}>
          {themes.map(option => (
            <Choice key={option.key} active={state.theme === option.key} title={option.title} subtitle={option.subtitle} onClick={() => pickTheme(option.key)} />
          ))}
        </Section>

        <Section title={T('Liquid Glass', 'Liquid Glass')}>
          <GlassCard T={T} />
        </Section>

        <Section title={T('Chứng từ thanh toán', 'Payment documents')}>
          <Choice
            active={state.autoEmailDocuments}
            title={T('Tự động gửi email hoá đơn/biên nhận', 'Automatically email me a copy of invoices/receipts')}
            subtitle={T('Dùng làm bằng chứng thanh toán. Áp dụng cho mọi lượt đặt chỗ, không hỏi lại mỗi lần.', 'As proof of payment. Applies to every booking. You will not be asked again per booking.')}
            onClick={toggleAutoEmailDocuments}
            testId="preferences-auto-email-documents"
          />
        </Section>
      </div>
    </div>
  );
}

// iOS PreferencesView.liquidGlassPreview: title + percentage, a preview over a paper tile, the opacity slider.
function GlassCard({ T }) {
  const [pct, setPct] = useState(() => Math.round(getGlassOpacity() * 100));
  return (
    <div style={{ ...cardGlass({ padding: '15px 18px', display: 'flex', flexDirection: 'column', gap: 12 }), border: `1px solid ${rule}` }} data-testid="preferences-glass-card">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ ...display(17) }}>Liquid Glass</span>
        <span style={{ fontSize: 12, fontWeight: 600, color: ink, opacity: 0.65 }}>{pct}%</span>
      </div>
      <div style={{ height: 170, borderRadius: 22, background: paper, border: `1px solid ${rule}`, boxSizing: 'border-box', padding: 18, display: 'flex', flexDirection: 'column', gap: 8, justifyContent: 'flex-end', overflow: 'hidden' }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: ink, opacity: 0.6 }}>{T('Khu vực', 'Area')}</span>
        <span style={{ ...display(22) }}>{T('Tất cả khu vực', 'All areas')}</span>
        <span style={{ fontSize: 12, color: ink, opacity: 0.62 }}>{T('Chạm để mở bộ lọc khu vực', 'Tap to open the area filter')}</span>
        <span style={{ ...glassCapsuleInactive, alignSelf: 'flex-start', fontSize: 11.5, fontWeight: 600, color: ink, padding: '8px 12px', borderRadius: 999 }}>{T('Khu vực', 'Area')}</span>
      </div>
      <input
        type="range" min={0} max={100} step={5} value={pct}
        aria-label={T('Độ trong Liquid Glass', 'Liquid Glass opacity')} data-testid="preferences-glass-slider"
        onChange={e => { const v = Number(e.target.value); setPct(v); setGlassOpacity(v / 100); }}
        style={{ width: '100%', accentColor: 'var(--bb-fg)' }}
      />
      <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.68, margin: 0 }}>
        {T('Trong suốt hơn giúp nền hiển thị rõ hơn, đậm hơn tăng độ tương phản cho nội dung và nút.', 'Clear is more transparent, tinted increases opacity and contrast for content and controls.')}
      </p>
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ marginTop: 28 }}>
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{title}</span>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 10 }}>{children}</div>
    </div>
  );
}

function Choice({ active, title, subtitle, onClick, testId }) {
  return (
    <div onClick={onClick} data-testid={testId} style={{ ...cardGlass({ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '17px 18px', cursor: 'pointer' }), border: active ? `1.5px solid ${ink}` : `1px solid ${rule}` }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        <span style={{ ...display(17, { color: ink }) }}>{title}</span>
        <span style={{ fontSize: 11.5, color: ink }}>{subtitle}</span>
      </div>
      <span style={{ fontSize: 15, color: ink }}>{active ? '✓' : '›'}</span>
    </div>
  );
}
