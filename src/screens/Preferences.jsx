import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, cardGlass } from '../theme.js';

export default function Preferences() {
  const { state, T, set, pickTheme } = useGoc();
  const options = [
    { key: 'vi', title: 'Tiếng Việt', subtitle: T('Mặc định', 'Vietnamese') },
    { key: 'en', title: 'English', subtitle: T('Bạn có thể đổi lại bất cứ lúc nào', 'Switch anytime') },
  ];
  const themes = [
    { key: 'light', title: T('Sáng', 'Light'), subtitle: T('Nền giấy ấm', 'Warm paper') },
    { key: 'dark', title: T('Tối', 'Dark'), subtitle: T('Nền mực dịu mắt', 'Soft ink background') },
  ];

  return (
    <div style={{ animation: 'gocFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="Preferences">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '16px 30px 42px' }}>
        <h1 style={{ ...display(27, { margin: 0, lineHeight: 1.2 }) }}>{T('Ngôn ngữ & hiển thị', 'Language & appearance')}</h1>
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
      </div>
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

function Choice({ active, title, subtitle, onClick }) {
  return (
    <div onClick={onClick} style={{ ...cardGlass({ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '17px 18px', cursor: 'pointer' }), border: active ? `1.5px solid ${ink}` : `1px solid ${rule}` }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        <span style={{ ...display(17, { color: ink }) }}>{title}</span>
        <span style={{ fontSize: 11.5, color: ink }}>{subtitle}</span>
      </div>
      <span style={{ fontSize: 15, color: ink }}>{active ? '✓' : '›'}</span>
    </div>
  );
}
