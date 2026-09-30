import { useEffect } from 'react';
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

/** Interest surveys (Slice B) — ONE screen for both the dedicated browser
 * route (/surveys/<publicId>, reachable signed out) and in-app navigation
 * (goSurveyPublic), sharing the exact same backend
 * (get_survey_public/submit_survey_response, migration 114). A survey is
 * NOT a live event/booking/ticket — this screen says so explicitly and
 * never touches the booking/claim path at all. */
export default function SurveyPublic() {
  const {
    state, T, backFromSurveyPublic, promptLoginForSurvey, loadMySurveyResponse, updateSurveyDraft,
    submitSurveyResponseAction,
  } = useGoc();
  const s = state;
  const survey = s.surveyPublic;
  const config = survey?.config || {};
  const draft = s.surveyDraft;

  useEffect(() => {
    if (survey?.survey_id && s.user?.id) loadMySurveyResponse(survey.survey_id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [survey?.survey_id, s.user?.id]);

  const onSubmit = () => {
    if (!s.user) { promptLoginForSurvey(); return; }
    submitSurveyResponseAction();
  };

  if (s.surveyPublicLoading) {
    return (
      <div style={{ minHeight: '100vh', background: paper, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <span style={{ fontSize: 13, color: ink, opacity: 0.6 }}>{T('Đang tải…', 'Loading…')}</span>
      </div>
    );
  }

  if (s.surveyPublicError || !survey) {
    return (
      <div style={{ minHeight: '100vh', background: paper, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, gap: 12 }}>
        <span style={{ fontSize: 15, color: ink }}>{s.surveyPublicError || T('Không tìm thấy khảo sát này.', "This survey couldn't be found.")}</span>
        <span onClick={backFromSurveyPublic} style={{ fontSize: 13, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Quay lại', 'Go back')}</span>
      </div>
    );
  }

  const isClosed = survey.status === 'closed';
  const notOpenYet = survey.status === 'not_open_yet';
  const canRespond = survey.status === 'active';

  return (
    <div style={{ minHeight: '100vh', background: paper, color: ink }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: `1px solid ${rule}` }}>
        <span style={{ fontSize: 12, opacity: 0.6 }}>{survey.host_name}</span>
        <span onClick={backFromSurveyPublic} data-testid="survey-close" style={{ cursor: 'pointer', fontSize: 18 }}>×</span>
      </div>

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

        {s.surveyResponseSuccess && (
          <div style={{ padding: 14, background: 'rgba(0,0,0,0.04)', borderRadius: 10, fontSize: 13.5 }} data-testid="survey-success">
            {T('Đã ghi nhận câu trả lời của bạn. Bạn có thể quay lại chỉnh sửa trước khi khảo sát đóng.', 'Your response is recorded. You can come back and edit it before the survey closes.')}
          </div>
        )}

        {canRespond && !s.surveyResponseSuccess && (
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

            <div
              onClick={s.surveyResponseSubmitting ? undefined : onSubmit}
              data-testid="survey-submit"
              style={{
                textAlign: 'center', padding: '14px', borderRadius: 10, background: ink, color: paper,
                fontSize: 14, fontWeight: 600, cursor: s.surveyResponseSubmitting ? 'default' : 'pointer',
                opacity: s.surveyResponseSubmitting ? 0.6 : 1,
              }}
            >
              {!s.user
                ? T('Đăng nhập để gửi câu trả lời', 'Sign in to submit')
                : (s.mySurveyResponse ? T('Cập nhật câu trả lời', 'Update response') : T('Gửi câu trả lời', 'Submit response'))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
