import { passwordChecks } from '../lib/passwordRules.js';
import { ink, ink3 } from '../theme.js';

// Live checklist under a "new password" field (sign-up, Account › Security,
// reset link). Each item carries a ✓ or ○ glyph plus a text label, so it never
// relies on colour alone. aria-live reads changes as the user types.
// Twin: apps/ios/BanbeApp/Views/PasswordChecklist.swift.
export default function PasswordChecklist({ password, T }) {
  const checks = passwordChecks(password);
  const met = checks.filter((c) => c.ok).length;
  return (
    <ul
      aria-live="polite"
      aria-label={T('Yêu cầu mật khẩu', 'Password requirements')}
      data-testid="password-checklist"
      style={{ listStyle: 'none', padding: 0, margin: '10px 0 0', display: 'grid', gap: 4 }}
    >
      {checks.map((c) => (
        <li
          key={c.id}
          data-ok={c.ok ? 'true' : 'false'}
          style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5, lineHeight: 1.45, color: c.ok ? ink : ink3, fontWeight: c.ok ? 600 : 400 }}
        >
          <span aria-hidden="true" style={{ width: 14, textAlign: 'center' }}>{c.ok ? '✓' : '○'}</span>
          <span>
            {T(c.vi, c.en)}
            <span style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' }}>
              {c.ok ? T(' (đã đạt)', ' (met)') : T(' (chưa đạt)', ' (not met)')}
            </span>
          </span>
        </li>
      ))}
      <li style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' }}>
        {T(`Đạt ${met} trên ${checks.length} yêu cầu`, `${met} of ${checks.length} requirements met`)}
      </li>
    </ul>
  );
}
