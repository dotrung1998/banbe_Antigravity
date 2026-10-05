import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, alert } from '../theme.js';

const chipStyle = (active) => ({
  padding: '8px 14px', borderRadius: 999, fontSize: 13, cursor: 'pointer',
  border: `1px solid ${active ? ink : rule}`,
  background: active ? ink : 'transparent',
  color: active ? paper : ink,
  userSelect: 'none',
});

function toggleInArray(arr, id) {
  return arr.includes(id) ? arr.filter(x => x !== id) : [...arr, id];
}

function formatDeadline(iso, timezone, T) {
  if (!iso) return '';
  try {
    const d = new Date(iso);
    const formatted = new Intl.DateTimeFormat('vi-VN', {
      timeZone: timezone || 'Asia/Ho_Chi_Minh', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
    }).format(d);
    return `${formatted} (${timezone || 'Asia/Ho_Chi_Minh'})`;
  } catch {
    return iso;
  }
}

/** Section 3 — lightweight, no-password/no-profile respondent email
 * verification for a signed-out visitor. Reuses the existing OTP-by-email
 * mechanism (api/auth, mode: 'respond') — never a separate auth system —
 * and discloses whether this creates a new banbe identity BEFORE the
 * respondent types the code (not after), per the task's own "disclose
 * accurately before confirmation" rule. The explicit consent checkbox here
 * IS the additive consent path for someone who never saw the ordinary
 * Login screen's own checkbox. */
function RespondVerifyInline({ T }) {
  const { state, set, sendSurveyRespondCode, verifySurveyRespondCode } = useGoc();
  const s = state;
  const [email, setEmail] = useState('');

  if (s.surveyRespondStep === 'codeSent') {
    return (
      <div style={{ padding: 14, border: `1px solid ${rule}`, borderRadius: 10, display: 'flex', flexDirection: 'column', gap: 10 }} data-testid="survey-respond-code-step">
        <div style={{ fontSize: 12.5 }}>
          {s.surveyRespondIsNewAccount
            ? T('Email này chưa có tài khoản banbe — chúng tôi sẽ tạo một tài khoản tối giản gắn với email này để lưu câu trả lời của bạn.', "This email doesn't have a banbe account yet — we'll create a minimal one tied to this email so your response can be saved.")
            : T('Email này đã có tài khoản banbe — nhập mã để xác nhận đó là bạn.', 'This email already has a banbe account — enter the code to confirm it’s you.')}
        </div>
        <input
          value={s.surveyRespondCode}
          onChange={(e) => set({ surveyRespondCode: e.target.value, surveyRespondError: '' })}
          placeholder={T('Mã 8 chữ số', '8-digit code')} data-testid="survey-respond-code-input"
          style={{ padding: '10px 12px', borderRadius: 8, border: `1px solid ${rule}`, fontSize: 13.5, boxSizing: 'border-box' }}
        />
        {s.surveyRespondError && <div style={{ fontSize: 12, color: alert }}>{s.surveyRespondError}</div>}
        <div
          onClick={s.surveyRespondSending ? undefined : verifySurveyRespondCode}
          data-testid="survey-respond-verify-code"
          style={{ textAlign: 'center', padding: 11, borderRadius: 9, background: ink, color: paper, fontSize: 13, fontWeight: 600, cursor: s.surveyRespondSending ? 'default' : 'pointer', opacity: s.surveyRespondSending ? 0.6 : 1 }}
        >
          {s.surveyRespondSending ? T('Đang xác nhận…', 'Verifying…') : T('Xác nhận mã', 'Confirm code')}
        </div>
      </div>
    );
  }
  return (
    <div style={{ padding: 14, border: `1px solid ${rule}`, borderRadius: 10, display: 'flex', flexDirection: 'column', gap: 10 }} data-testid="survey-respond-email-step">
      <div style={{ fontSize: 12.5, fontWeight: 600 }}>{T('Xác nhận email để gửi câu trả lời', 'Verify your email to submit')}</div>
      <input
        type="email" value={email} onChange={(e) => setEmail(e.target.value)}
        placeholder={T('Email của bạn', 'Your email')} data-testid="survey-respond-email-input"
        style={{ padding: '10px 12px', borderRadius: 8, border: `1px solid ${rule}`, fontSize: 13.5, boxSizing: 'border-box' }}
      />
      <label style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 11.5, cursor: 'pointer' }}>
        <input
          type="checkbox" checked={s.surveyRespondConsent}
          onChange={(e) => set({ surveyRespondConsent: e.target.checked })}
          style={{ marginTop: 2 }} data-testid="survey-respond-consent"
        />
        <span>
          {T(
            'Tôi đồng ý xác nhận email này để gửi câu trả lời. Nếu email chưa có tài khoản banbe, một tài khoản tối giản sẽ được tạo, theo Chính sách quyền riêng tư của banbe.',
            "I agree to verify this email to submit my response. If it doesn't have a banbe account, a minimal one will be created, under banbe's Privacy Policy."
          )}
        </span>
      </label>
      {s.surveyRespondError && <div style={{ fontSize: 12, color: alert }}>{s.surveyRespondError}</div>}
      <div
        onClick={s.surveyRespondSending ? undefined : () => sendSurveyRespondCode(email)}
        data-testid="survey-respond-send-code"
        style={{ textAlign: 'center', padding: 11, borderRadius: 9, background: ink, color: paper, fontSize: 13, fontWeight: 600, cursor: s.surveyRespondSending ? 'default' : 'pointer', opacity: s.surveyRespondSending ? 0.6 : 1 }}
      >
        {s.surveyRespondSending ? T('Đang gửi…', 'Sending…') : T('Gửi mã xác nhận', 'Send verification code')}
      </div>
    </div>
  );
}

/** Interest surveys (Slice B) — ONE screen for both the dedicated browser
 * route (/surveys/<publicId>, reachable signed out) and in-app navigation
 * (goSurveyPublic), sharing the exact same backend
 * (get_survey_public/submit_survey_response, migration 114). A survey is
 * NOT a live event/booking/ticket — this screen says so explicitly and
 * never touches the booking/claim path at all.
 *
 * Survey-sharing pass: this SAME component also renders inside
 * SurveyResponseModal.jsx (a story's "Answer Survey" popup) — `s.
 * surveyAsModal` only changes CLOSE behavior (closeSurveyStoryModal instead
 * of backFromSurveyPublic) and hides the "navigate to the full Login
 * screen" option (which would abandon the paused story behind the modal);
 * everything else — form, success, already-responded, edit — is identical,
 * per this ticket's own "keep the existing in-app survey screen reusable;
 * change its presentation, not the response backend" rule. */
export default function SurveyPublic() {
  const {
    state, T, backFromSurveyPublic, closeSurveyStoryModal, promptLoginForSurvey, loadMySurveyResponse, updateSurveyDraft,
    submitSurveyResponseAction, toggleSurveyEditMode,
  } = useGoc();
  const s = state;
  const survey = s.surveyPublic;
  const config = survey?.config || {};
  const draft = s.surveyDraft;
  const asModal = s.surveyAsModal;
  const [closeConfirmOpen, setCloseConfirmOpen] = useState(false);

  useEffect(() => {
    if (survey?.survey_id && s.user?.id) loadMySurveyResponse(survey.survey_id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [survey?.survey_id, s.user?.id]);

  const onSubmit = () => {
    if (!s.user) return; // inline verify widget handles this case instead
    submitSurveyResponseAction();
  };

  const isDraftDirty = Boolean(
    draft && (draft.interestLevel != null || draft.dateOptions.length || draft.groupSize != null
      || draft.locationOptions.length || draft.budgetOption || draft.activities.length
      || draft.freeText.trim() || draft.contactConsent)
  );
  const requestClose = () => {
    if (isDraftDirty && !s.surveyResponseSuccess) { setCloseConfirmOpen(true); return; }
    if (asModal) closeSurveyStoryModal(false); else backFromSurveyPublic();
  };
  const confirmClose = (discard) => {
    setCloseConfirmOpen(false);
    if (asModal) closeSurveyStoryModal(discard); else backFromSurveyPublic();
  };

  if (s.surveyPublicLoading) {
    return (
      <div style={{ minHeight: '100%', background: paper, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <span style={{ fontSize: 13, color: ink, opacity: 0.6 }}>{T('Đang tải…', 'Loading…')}</span>
      </div>
    );
  }

  if (s.surveyPublicError || !survey) {
    return (
      <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '66px 24px 24px', gap: 12 }}>
        <div style={{ alignSelf: 'stretch', display: 'flex', justifyContent: 'flex-end', padding: '0 0 8px' }}>
          <span onClick={requestClose} data-testid="survey-close" style={{ cursor: 'pointer', fontSize: 18, lineHeight: 1 }}>×</span>
        </div>
        <span style={{ fontSize: 15, color: ink, marginTop: 52, textAlign: 'center' }}>{s.surveyPublicError || T('Không tìm thấy khảo sát này.', "This survey couldn't be found.")}</span>
        <span onClick={requestClose} style={{ fontSize: 13, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Quay lại', 'Go back')}</span>
      </div>
    );
  }

  const isDraft = survey.status === 'draft';
  const isClosed = survey.status === 'closed';
  const notOpenYet = survey.status === 'not_open_yet';
  const canRespond = survey.status === 'active';
  const alreadyResponded = Boolean(s.mySurveyResponse) && !s.surveyEditMode && !s.surveyResponseSuccess;

  return (
    <div style={{ minHeight: '100%', background: paper, color: ink }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '66px 20px 8px' }}>
        <span style={{ fontSize: 12, opacity: 0.6 }}>{survey.host_name}</span>
        <span onClick={requestClose} data-testid="survey-close" style={{ cursor: 'pointer', fontSize: 18 }}>×</span>
      </div>

      {closeConfirmOpen && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <div style={{ background: paper, borderRadius: 14, padding: 20, maxWidth: 340, display: 'flex', flexDirection: 'column', gap: 12 }} data-testid="survey-close-confirm">
            <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Bạn có câu trả lời chưa gửi', 'You have unsent answers')}</div>
            <div style={{ fontSize: 12.5, opacity: 0.75 }}>{T('Giữ lại để tiếp tục sau, hay bỏ đi?', 'Keep them for later, or discard?')}</div>
            <div style={{ display: 'flex', gap: 8 }}>
              <div onClick={() => confirmClose(false)} data-testid="survey-close-keep" style={{ flex: 1, textAlign: 'center', padding: 10, borderRadius: 9, background: ink, color: paper, fontSize: 12.5, fontWeight: 600, cursor: 'pointer' }}>{T('Giữ nháp', 'Keep draft')}</div>
              <div onClick={() => confirmClose(true)} data-testid="survey-close-discard" style={{ flex: 1, textAlign: 'center', padding: 10, borderRadius: 9, border: `1px solid ${rule}`, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', color: alert }}>{T('Bỏ đi', 'Discard')}</div>
            </div>
          </div>
        </div>
      )}

      <div style={{ maxWidth: 560, margin: '0 auto', padding: '24px 20px 60px' }}>
        <h1 style={{ ...display(24, { margin: '0 0 10px' }) }}>{survey.title}</h1>
        {survey.description && <p style={{ fontSize: 14, lineHeight: 1.5, margin: '0 0 14px' }}>{survey.description}</p>}
        <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 4 }}>
          {T('Hạn trả lời', 'Deadline')}: {formatDeadline(survey.closes_at, survey.timezone, T)}
        </div>
        {/* The task's own required copy — a survey is not a reservation. */}
        <div style={{ fontSize: 12.5, fontWeight: 600, marginBottom: 20 }}>
          {T('Đây không phải là giữ chỗ.', 'This does not reserve a place.')}
        </div>

        {isDraft && (
          <div style={{ padding: 14, background: 'rgba(0,0,0,0.04)', borderRadius: 10, fontSize: 13.5 }}>
            {T('Đây là bản xem trước — khảo sát chưa được xuất bản.', "This is a preview — the survey hasn't been published yet.")}
          </div>
        )}
        {isClosed && (
          <div style={{ padding: 14, background: 'rgba(0,0,0,0.04)', borderRadius: 10, fontSize: 13.5 }}>
            {T('Khảo sát này đã đóng. Cảm ơn bạn đã quan tâm.', 'This survey is closed. Thanks for your interest.')}
          </div>
        )}
        {notOpenYet && (
          <div style={{ padding: 14, background: 'rgba(0,0,0,0.04)', borderRadius: 10, fontSize: 13.5 }}>
            {T('Khảo sát này chưa mở.', "This survey hasn't opened yet.")}
          </div>
        )}

        {/* Section 2's required success state — a distinct screen, never an
            inline banner the editable form still sits under, and never
            auto-closed/auto-advanced; the respondent decides when to leave. */}
        {s.surveyResponseSuccess && (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16, padding: '36px 0', textAlign: 'center' }} data-testid="survey-success">
            <div style={{ ...display(20) }}>{T('Đã Gửi Câu Trả Lời. Cảm Ơn Bạn!', 'Response Submitted. Thank You!')}</div>
            <div style={{ fontSize: 13, opacity: 0.75, maxWidth: 360 }}>
              {T('Bạn có thể quay lại chỉnh sửa trước khi khảo sát đóng.', 'You can come back and edit it before the survey closes.')}
            </div>
            <div
              onClick={requestClose} data-testid="survey-success-close"
              style={{ padding: '12px 28px', borderRadius: 10, background: ink, color: paper, fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}
            >
              {T('Đóng', 'Close')}
            </div>
          </div>
        )}

        {/* "You Have Already Responded" — a read-only summary of the saved
            answer, never a fresh-looking blank form that would suggest a
            second, independent submission. Edit Response re-opens the same
            editable form below, pre-filled (loadMySurveyResponse already
            pre-fills `draft` from the saved row), only while still active. */}
        {alreadyResponded && !isDraft && !isClosed && !notOpenYet && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }} data-testid="survey-already-responded">
            <div style={{ padding: 14, background: 'rgba(0,0,0,0.04)', borderRadius: 10, fontSize: 13.5, fontWeight: 600 }}>
              {T('Bạn Đã Trả Lời Khảo Sát Này', 'You Have Already Responded')}
            </div>
            <div style={{ fontSize: 12.5, display: 'flex', flexDirection: 'column', gap: 6, opacity: 0.85 }}>
              {s.mySurveyResponse.interest_level != null && <div>{T('Mức độ quan tâm', 'Interest level')}: {s.mySurveyResponse.interest_level}</div>}
              {(s.mySurveyResponse.date_options || []).length > 0 && <div>{T('Ngày/giờ', 'Date/time')}: {s.mySurveyResponse.date_options.map(id => config.date_options?.find(o => o.id === id)?.label || id).join(', ')}</div>}
              {(s.mySurveyResponse.location_options || []).length > 0 && <div>{T('Địa điểm', 'Location')}: {s.mySurveyResponse.location_options.map(id => config.location_options?.find(o => o.id === id)?.label || id).join(', ')}</div>}
              {s.mySurveyResponse.group_size != null && <div>{T('Số người', 'Group size')}: {s.mySurveyResponse.group_size}</div>}
              {s.mySurveyResponse.budget_option && <div>{T('Ngân sách', 'Budget')}: {config.budget_options?.find(o => o.id === s.mySurveyResponse.budget_option)?.label || s.mySurveyResponse.budget_option}</div>}
              {s.mySurveyResponse.free_text && <div>{T('Góp ý', 'Notes')}: {s.mySurveyResponse.free_text}</div>}
            </div>
            {canRespond && (
              <div
                onClick={() => toggleSurveyEditMode(true)} data-testid="survey-edit-response"
                style={{ alignSelf: 'flex-start', fontSize: 12.5, textDecoration: 'underline', cursor: 'pointer' }}
              >
                {T('Chỉnh sửa câu trả lời', 'Edit Response')}
              </div>
            )}
          </div>
        )}

        {canRespond && !s.surveyResponseSuccess && !alreadyResponded && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 22 }}>
            {/* Interest level */}
            <div>
              <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>{T('Mức độ quan tâm', 'Interest level')}</div>
              <div style={{ display: 'flex', gap: 8 }}>
                {[1, 2, 3, 4, 5].map(n => (
                  <div key={n} style={chipStyle(draft.interestLevel === n)} onClick={() => updateSurveyDraft({ interestLevel: n })}>{n}</div>
                ))}
              </div>
            </div>

            {/* Date options */}
            {(config.date_options || []).length > 0 && (
              <div>
                <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>{T('Ngày/giờ phù hợp', 'Preferred date/time')}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {config.date_options.map(o => (
                    <div key={o.id} style={chipStyle(draft.dateOptions.includes(o.id))} onClick={() => updateSurveyDraft({ dateOptions: toggleInArray(draft.dateOptions, o.id) })}>{o.label}</div>
                  ))}
                </div>
              </div>
            )}

            {/* Location options */}
            {(config.location_options || []).length > 0 && (
              <div>
                <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>{T('Địa điểm phù hợp', 'Preferred location')}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {config.location_options.map(o => (
                    <div key={o.id} style={chipStyle(draft.locationOptions.includes(o.id))} onClick={() => updateSurveyDraft({ locationOptions: toggleInArray(draft.locationOptions, o.id) })}>{o.label}</div>
                  ))}
                </div>
              </div>
            )}

            {/* Group size */}
            <div>
              <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>
                {T('Số người (tính cả bạn)', 'Group size (including you)')}
              </div>
              <input
                type="number" min={config.group_size_min || 1} max={config.group_size_max || 50}
                value={draft.groupSize ?? ''}
                onChange={(e) => updateSurveyDraft({ groupSize: e.target.value ? parseInt(e.target.value, 10) : null })}
                style={{ width: 100, padding: '8px 12px', borderRadius: 8, border: `1px solid ${rule}`, fontSize: 14 }}
              />
            </div>

            {/* Budget */}
            {(config.budget_options || []).length > 0 && (
              <div>
                <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>{T('Ngân sách', 'Budget')}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {config.budget_options.map(o => (
                    <div key={o.id} style={chipStyle(draft.budgetOption === o.id)} onClick={() => updateSurveyDraft({ budgetOption: o.id })}>{o.label}</div>
                  ))}
                </div>
              </div>
            )}

            {/* Activities */}
            {(config.activity_options || []).length > 0 && (
              <div>
                <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>{T('Hoạt động mong muốn', 'Desired activities')}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {config.activity_options.map(o => (
                    <div key={o.id} style={chipStyle(draft.activities.includes(o.id))} onClick={() => updateSurveyDraft({ activities: toggleInArray(draft.activities, o.id) })}>{o.label}</div>
                  ))}
                </div>
              </div>
            )}

            {/* Free text */}
            <div>
              <div style={{ fontSize: 12.5, opacity: 0.7, marginBottom: 8 }}>{T('Góp ý thêm (không bắt buộc)', 'Additional suggestions (optional)')}</div>
              <textarea
                value={draft.freeText} onChange={(e) => updateSurveyDraft({ freeText: e.target.value })}
                rows={3} maxLength={2000}
                style={{ width: '100%', padding: '10px 12px', borderRadius: 8, border: `1px solid ${rule}`, fontSize: 14, resize: 'vertical', boxSizing: 'border-box' }}
              />
            </div>

            {/* Contact consent — deliberately separate from answering. */}
            <label style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 12.5, cursor: 'pointer' }}>
              <input type="checkbox" checked={draft.contactConsent} onChange={(e) => updateSurveyDraft({ contactConsent: e.target.checked })} style={{ marginTop: 2 }} />
              <span>{T('Đồng ý để người tổ chức liên hệ về sự kiện này (không phải quảng cáo).', 'OK for the host to contact me about this specific event (not marketing).')}</span>
            </label>

            {s.surveyResponseError && <div style={{ fontSize: 12.5, color: alert }}>{s.surveyResponseError}</div>}

            {/* Section 3 — "offer existing sign-in OR email-code
                verification" for a signed-out respondent. The full Login
                screen is only offered OUTSIDE the story-popup modal — from
                inside the modal, navigating away would also abandon the
                paused story behind it, so the lightweight inline path is
                the only option there, which matches this ticket's own
                "no onboarding to merely respond" preference anyway. */}
            {!s.user ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                <RespondVerifyInline T={T} />
                {!asModal && (
                  <div onClick={promptLoginForSurvey} data-testid="survey-respond-use-login" style={{ textAlign: 'center', fontSize: 12.5, textDecoration: 'underline', cursor: 'pointer', opacity: 0.75 }}>
                    {T('Hoặc đăng nhập bằng tài khoản banbe có sẵn', 'Or sign in with an existing banbe account')}
                  </div>
                )}
              </div>
            ) : (
              <div
                onClick={s.surveyResponseSubmitting ? undefined : onSubmit}
                data-testid="survey-submit"
                style={{
                  textAlign: 'center', padding: '14px', borderRadius: 10, background: ink, color: paper,
                  fontSize: 14, fontWeight: 600, cursor: s.surveyResponseSubmitting ? 'default' : 'pointer',
                  opacity: s.surveyResponseSubmitting ? 0.6 : 1,
                }}
              >
                {s.mySurveyResponse ? T('Cập nhật câu trả lời', 'Update response') : T('Gửi câu trả lời', 'Submit response')}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
