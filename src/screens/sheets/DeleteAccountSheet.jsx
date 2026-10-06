import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, cardGlass, fieldGlass, inkButton, alert, display } from '../../theme.js';

// Account deletion (Task 2, Account/Settings pass) — a full-screen sheet
// opened from AccountGroup.jsx's `preferences` case, a new "Account
// Management" subsection there. Deliberately its OWN small file, not
// folded into AccountGroup.jsx, since this is a multi-step wizard with its
// own local step machine (`s.deleteAccountStep`) rather than a single row.
//
// SAFETY: this UI can genuinely complete the real deletion (POSTs to
// /api/auth's `delete_account` action) — it was never exercised end-to-end
// this session (no isolated test account to safely destroy). Verified by
// reading, not by running it.

const REASONS = [
  { code: 'not_using', vi: 'Tôi không còn dùng banbe nữa', en: "I don't use banbe anymore" },
  { code: 'privacy', vi: 'Lo ngại về quyền riêng tư', en: 'Privacy concerns' },
  { code: 'found_alternative', vi: 'Tôi dùng ứng dụng khác', en: 'I use a different app' },
  { code: 'too_many_notifications', vi: 'Quá nhiều thông báo/email', en: 'Too many notifications/emails' },
  { code: 'other', vi: 'Khác', en: 'Other' },
  { code: 'prefer_not_say', vi: 'Không muốn cung cấp', en: 'Prefer not to say' },
];

const DELETE_PHRASE = 'DELETE banbe';

function SheetShell({ onClose, children }) {
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 90, background: paper, overflowY: 'auto' }} data-testid="delete-account-sheet">
      <div style={{ padding: '54px 20px 40px', maxWidth: 480, margin: '0 auto' }}>
        {children}
      </div>
    </div>
  );
}

export default function DeleteAccountSheet() {
  const { state: s, T, closeDeleteAccount, setDeleteAccountStep,
    setDeleteAccountReasonCode, setDeleteAccountReasonText, setDeleteAccountPhraseInput,
    setDeleteAccountReauthCode, sendDeleteAccountReauthCode, verifyDeleteAccountReauthCode,
    confirmDeleteAccount, deleteAccountPhraseMatches, goHome } = useBanBe();

  if (!s.deleteAccountOpen) return null;

  const step = s.deleteAccountStep;
  const identityLabel = s.user?.name || s.user?.email || T('tài khoản của bạn', 'your account');

  if (step === 'intro') {
    return (
      <SheetShell>
        <div onClick={closeDeleteAccount} data-testid="delete-account-cancel" style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Huỷ', 'Cancel')}</div>
        <h1 style={{ ...display(24, { margin: '18px 0 0' }) }}>{T('Xóa tài khoản', 'Delete account')}</h1>
        <div style={{ ...cardGlass({ marginTop: 18, padding: '14px 16px' }) }} data-testid="delete-account-identity">
          <span style={{ fontSize: 11, opacity: 0.65, color: ink }}>{T('Tài khoản đang đăng nhập', 'Currently signed in as')}</span>
          <div style={{ fontSize: 15, fontWeight: 600, color: ink, marginTop: 2 }}>{identityLabel}</div>
          {s.user?.email && <div style={{ fontSize: 12, color: ink, opacity: 0.7 }}>{s.user.email}</div>}
        </div>
        <p style={{ fontSize: 13, lineHeight: 1.6, color: ink, marginTop: 18 }}>
          {T(
            'Đây là hành động vĩnh viễn. Sau khi xóa: các đặt chỗ/tin nhắn của bạn sẽ được tách khỏi danh tính (không hiển thị tên bạn nữa) thay vì bị xóa hoàn toàn khi cần giữ hồ sơ giao dịch; các dữ liệu cá nhân khác (hồ sơ, ảnh đại diện, mục yêu thích) sẽ bị xóa hẳn. Nếu bạn đang sở hữu một sự kiện còn đang mở, bạn sẽ cần hủy/kết thúc sự kiện đó trước.',
            'This is permanent. After deletion: your bookings/messages are detached from your identity (your name no longer shows) rather than fully erased where a transaction record needs to stay; other personal data (profile, avatar, favorites) is erased outright. If you currently own an open event, you’ll need to cancel/end it first.'
          )}
        </p>
        <div onClick={() => setDeleteAccountStep('reason')} data-testid="delete-account-continue" style={{ ...inkButton({ marginTop: 20, borderRadius: 16, padding: 14, fontSize: 14, background: alert }) }}>
          {T('Tiếp tục', 'Continue')}
        </div>
      </SheetShell>
    );
  }

  if (step === 'reason') {
    return (
      <SheetShell>
        <div onClick={() => setDeleteAccountStep('intro')} data-testid="delete-account-back-reason" style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</div>
        <h1 style={{ ...display(22, { margin: '18px 0 4px' }) }}>{T('Vì sao bạn muốn rời đi?', 'Why are you leaving?')}</h1>
        <p style={{ fontSize: 12.5, color: ink, opacity: 0.7, margin: '0 0 14px' }}>{T('Không bắt buộc — chỉ để chúng tôi cải thiện.', 'Optional — just helps us improve.')}</p>
        {REASONS.map(r => (
          <div
            key={r.code}
            onClick={() => setDeleteAccountReasonCode(r.code)}
            data-testid={`delete-account-reason-${r.code}`}
            style={{ ...fieldGlass({ marginTop: 8, padding: '13px 15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }),
              border: s.deleteAccountReasonCode === r.code ? `1.5px solid ${ink}` : `1px solid ${rule}` }}
          >
            <span style={{ fontSize: 13.5, color: ink }}>{T(r.vi, r.en)}</span>
            {s.deleteAccountReasonCode === r.code && <span style={{ fontSize: 14 }}>✓</span>}
          </div>
        ))}
        {s.deleteAccountReasonCode === 'other' && (
          <textarea
            value={s.deleteAccountReasonText}
            onChange={setDeleteAccountReasonText}
            data-testid="delete-account-reason-text"
            placeholder={T('Cho chúng tôi biết thêm (không bắt buộc)', 'Tell us more (optional)')}
            style={{ ...fieldGlass({ marginTop: 10, padding: '12px 14px', width: '100%', minHeight: 70, fontSize: 13, color: ink, resize: 'vertical' }) }}
          />
        )}
        <div onClick={() => setDeleteAccountStep('confirm')} data-testid="delete-account-reason-continue" style={{ ...inkButton({ marginTop: 20, borderRadius: 16, padding: 14, fontSize: 14, background: alert }) }}>
          {T('Tiếp tục', 'Continue')}
        </div>
      </SheetShell>
    );
  }

  if (step === 'confirm' || step === 'submitting') {
    const submitting = step === 'submitting' || s.deleteAccountSubmitting;
    return (
      <SheetShell>
        <div onClick={() => !submitting && setDeleteAccountStep('reason')} data-testid="delete-account-back-confirm" style={{ fontSize: 12, color: ink, cursor: submitting ? 'default' : 'pointer', opacity: submitting ? 0.4 : 1 }}>‹ {T('Quay lại', 'Back')}</div>
        <h1 style={{ ...display(22, { margin: '18px 0 4px' }) }}>{T('Xác nhận xóa', 'Confirm deletion')}</h1>

        {/* Reauthentication — reuses the SAME emailed login-code flow
            Login.jsx uses (Login.jsx's own verifyEmailCode), not a parallel
            mechanism. An OAuth-only account is told plainly that a fresh
            sign-in is required instead, since this app has no OAuth
            re-consent path of its own to reuse (confirmed by reading
            Login.jsx's Google/Facebook flow — signInWithOAuth alone, no
            distinct "re-authenticate" variant). Face ID/biometric (if the
            device has an app-level lock) is a LOCAL convenience only and is
            never treated as proof here — see FaceIDLockView's own scope,
            nothing server-side ever reads it. */}
        <div style={{ ...cardGlass({ marginTop: 14, padding: '14px 16px' }) }} data-testid="delete-account-reauth">
          <span style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{T('Bước 1 — Xác minh danh tính', 'Step 1 — Verify it’s you')}</span>
          {s.deleteAccountOAuthProvider ? (
            <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, marginTop: 8 }}>
              {T(
                `Tài khoản này đăng nhập qua ${s.deleteAccountOAuthProvider}. Vui lòng đăng xuất và đăng nhập lại gần đây trước khi xóa tài khoản (banbe chưa hỗ trợ xác thực lại qua ${s.deleteAccountOAuthProvider} ngay tại đây).`,
                `This account signs in via ${s.deleteAccountOAuthProvider}. Please sign out and sign back in recently before deleting (banbe doesn’t yet support re-authenticating via ${s.deleteAccountOAuthProvider} right here).`
              )}
            </p>
          ) : s.deleteAccountReauthVerified ? (
            <p style={{ fontSize: 12.5, color: ink, marginTop: 8 }} data-testid="delete-account-reauth-done">✓ {T('Đã xác minh', 'Verified')}</p>
          ) : !s.deleteAccountReauthSent ? (
            <div onClick={sendDeleteAccountReauthCode} data-testid="delete-account-reauth-send" style={{ ...inkButton({ marginTop: 10, borderRadius: 12, padding: 11, fontSize: 13 }), opacity: s.deleteAccountReauthBusy ? 0.6 : 1 }}>
              {s.deleteAccountReauthBusy ? T('Đang gửi…', 'Sending…') : T('Gửi mã xác minh tới email', 'Send verification code to email')}
            </div>
          ) : (
            <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
              <input
                value={s.deleteAccountReauthCode}
                onChange={setDeleteAccountReauthCode}
                data-testid="delete-account-reauth-code"
                placeholder={T('Nhập mã 8 số', 'Enter the 8-digit code')}
                style={{ ...fieldGlass({ padding: '11px 13px', fontSize: 14, color: ink }) }}
              />
              <div onClick={verifyDeleteAccountReauthCode} data-testid="delete-account-reauth-verify" style={{ ...inkButton({ borderRadius: 12, padding: 11, fontSize: 13 }), opacity: s.deleteAccountReauthBusy ? 0.6 : 1 }}>
                {s.deleteAccountReauthBusy ? T('Đang kiểm tra…', 'Checking…') : T('Xác minh', 'Verify')}
              </div>
              {s.deleteAccountReauthError && <span style={{ fontSize: 11.5, color: alert }}>{s.deleteAccountReauthError}</span>}
            </div>
          )}
        </div>

        {/* Exact-phrase gate */}
        <div style={{ ...cardGlass({ marginTop: 14, padding: '14px 16px' }) }} data-testid="delete-account-phrase-block">
          <span style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{T('Bước 2 — Gõ để xác nhận', 'Step 2 — Type to confirm')}</span>
          <p style={{ fontSize: 12, color: ink, opacity: 0.75, marginTop: 6 }}>
            {T('Gõ chính xác cụm sau:', 'Type the exact phrase:')} <b style={{ userSelect: 'all' }} data-testid="delete-account-phrase-target">{DELETE_PHRASE}</b>
          </p>
          <input
            value={s.deleteAccountPhraseInput}
            onChange={setDeleteAccountPhraseInput}
            data-testid="delete-account-phrase-input"
            placeholder={DELETE_PHRASE}
            style={{ ...fieldGlass({ marginTop: 8, padding: '11px 13px', fontSize: 14, color: ink, width: '100%' }) }}
          />
        </div>

        {s.deleteAccountError && <p style={{ fontSize: 12.5, color: alert, marginTop: 14 }} data-testid="delete-account-error">{s.deleteAccountError}</p>}

        {/* Final button — disabled until BOTH gates pass, disabled again
            immediately on tap (submitting=true), real loading state, never
            claims "deleted" until the server call has actually returned
            200 (confirmDeleteAccount only sets step 'done' after that). */}
        <div
          onClick={(!deleteAccountPhraseMatches || !s.deleteAccountReauthVerified || submitting) ? undefined : confirmDeleteAccount}
          data-testid="delete-account-final"
          style={{
            ...inkButton({ marginTop: 20, borderRadius: 16, padding: 14, fontSize: 14, background: alert }),
            opacity: (!deleteAccountPhraseMatches || !s.deleteAccountReauthVerified || submitting) ? 0.4 : 1,
            cursor: (!deleteAccountPhraseMatches || !s.deleteAccountReauthVerified || submitting) ? 'default' : 'pointer',
          }}
        >
          {submitting ? T('Đang xóa…', 'Deleting…') : T('Xóa vĩnh viễn tài khoản', 'Permanently delete account')}
        </div>
      </SheetShell>
    );
  }

  if (step === 'done') {
    return (
      <SheetShell>
        <h1 style={{ ...display(24, { margin: '40px 0 12px' }) }}>{T('Đã xóa tài khoản', 'Account deleted')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.6, color: ink }} data-testid="delete-account-done-message">
          {T('Tài khoản của bạn đã được xóa. Cảm ơn bạn đã dùng banbe.', 'Your account has been deleted. Thanks for using banbe.')}
        </p>
        <div onClick={() => { closeDeleteAccount(); goHome(); }} data-testid="delete-account-done-close" style={{ ...inkButton({ marginTop: 20, borderRadius: 16, padding: 14, fontSize: 14 }) }}>
          {T('Đóng', 'Close')}
        </div>
      </SheetShell>
    );
  }

  return null;
}
