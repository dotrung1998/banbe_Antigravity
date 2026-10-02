import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, alert } from '../theme.js';
import { surveyPublicUrl } from '../lib/surveyLink.js';
import { supabase } from '../lib/supabase.js';
import SurveyStoryCard from './sheets/SurveyStoryCard.jsx';

function organizerAvatarUrl(path) {
  if (!path) return '';
  return supabase.storage.from('organizer-photos').getPublicUrl(path).data.publicUrl;
}

const TABS = [
  { key: 'active', vi: 'Đang mở', en: 'Active Surveys' },
  { key: 'closed', vi: 'Đã đóng', en: 'Closed Surveys' },
  { key: 'drafts', vi: 'Gợi ý sự kiện', en: 'Suggested Event Drafts' },
];

function parseOptionsInput(text) {
  return (text || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
    .map((label, i) => ({ id: `o${i + 1}`, label }));
}

function CreateSurveyForm({ T, onCreate, busy, error }) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [closesInDays, setClosesInDays] = useState('7');
  const [dateOptions, setDateOptions] = useState('');
  const [locationOptions, setLocationOptions] = useState('');
  const [budgetOptions, setBudgetOptions] = useState('Dưới 300k, 300-600k, Trên 600k');
  const [activityOptions, setActivityOptions] = useState('');
  const [groupSizeMax, setGroupSizeMax] = useState('20');

  const submit = () => {
    const opensAt = new Date().toISOString();
    const days = Math.max(1, parseInt(closesInDays, 10) || 7);
    const closesAt = new Date(Date.now() + days * 86400000).toISOString();
    onCreate({
      title, description, opensAt, closesAt,
      config: {
        date_options: parseOptionsInput(dateOptions),
        location_options: parseOptionsInput(locationOptions),
        budget_options: parseOptionsInput(budgetOptions),
        activity_options: parseOptionsInput(activityOptions),
        group_size_min: 1,
        group_size_max: Math.max(1, parseInt(groupSizeMax, 10) || 20),
        required: { date_options: true, location_options: true },
      },
    });
  };

  const inputStyle = { width: '100%', padding: '10px 12px', borderRadius: 8, border: `1px solid ${rule}`, fontSize: 13.5, boxSizing: 'border-box' };
  const labelStyle = { fontSize: 11.5, color: ink, opacity: 0.7, display: 'block', marginBottom: 5 };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, padding: 18, border: `1px solid ${rule}`, borderRadius: 12 }}>
      <div>
        <label style={labelStyle}>{T('Tiêu đề', 'Title')}</label>
        <input style={inputStyle} value={title} onChange={(e) => setTitle(e.target.value)} placeholder={T('Ý tưởng sự kiện cuối tuần', 'Weekend event idea')} />
      </div>
      <div>
        <label style={labelStyle}>{T('Mô tả', 'Description')}</label>
        <textarea style={{ ...inputStyle, resize: 'vertical' }} rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Đóng sau (ngày)', 'Closes in (days)')}</label>
        <input style={{ ...inputStyle, width: 100 }} type="number" min={1} value={closesInDays} onChange={(e) => setClosesInDays(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Lựa chọn ngày/giờ (cách nhau bởi dấu phẩy)', 'Date/time options (comma-separated)')}</label>
        <input style={inputStyle} value={dateOptions} onChange={(e) => setDateOptions(e.target.value)} placeholder={T('Thứ Bảy tối, Chủ Nhật trưa', 'Saturday evening, Sunday afternoon')} />
      </div>
      <div>
        <label style={labelStyle}>{T('Lựa chọn địa điểm (cách nhau bởi dấu phẩy)', 'Location options (comma-separated)')}</label>
        <input style={inputStyle} value={locationOptions} onChange={(e) => setLocationOptions(e.target.value)} placeholder={T('Quận 1, Quận 3', 'District 1, District 3')} />
      </div>
      <div>
        <label style={labelStyle}>{T('Mức ngân sách (cách nhau bởi dấu phẩy)', 'Budget ranges (comma-separated)')}</label>
        <input style={inputStyle} value={budgetOptions} onChange={(e) => setBudgetOptions(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Hoạt động mong muốn (cách nhau bởi dấu phẩy, không bắt buộc)', 'Desired activities (comma-separated, optional)')}</label>
        <input style={inputStyle} value={activityOptions} onChange={(e) => setActivityOptions(e.target.value)} />
      </div>
      <div>
        <label style={labelStyle}>{T('Số người tối đa mỗi nhóm', 'Max group size')}</label>
        <input style={{ ...inputStyle, width: 100 }} type="number" min={1} value={groupSizeMax} onChange={(e) => setGroupSizeMax(e.target.value)} />
      </div>
      {error && <div style={{ fontSize: 12.5, color: alert }}>{error}</div>}
      <div
        onClick={busy || !title.trim() ? undefined : submit}
        style={{ textAlign: 'center', padding: 12, borderRadius: 10, background: ink, color: paper, fontSize: 13.5, fontWeight: 600, cursor: busy || !title.trim() ? 'default' : 'pointer', opacity: busy || !title.trim() ? 0.5 : 1 }}
      >
        {T('Tạo khảo sát (bản nháp)', 'Create survey (draft)')}
      </div>
    </div>
  );
}

/** Hosting -> Surveys & Event Ideas (Slice B host side). "Suggested Event
 * Drafts" (Slice C — candidate generation) is intentionally an honest
 * empty state here: that pipeline is not implemented in this pass (see
 * .claude/notes/21-invite-only-events-and-surveys.md) — this tab is not
 * hidden, since the IA position itself is real, but it never claims
 * candidates exist that don't. */
export default function SurveysHosting() {
  const {
    state, T, goHome, mySurveys, mySurveysLoading, loadMySurveys,
    createSurveyAction, publishSurveyAction, closeSurveyAction, archiveSurveyAction, deleteSurveyAction,
    mySurveyCreateBusy, mySurveyCreateError, goSurveyPublic,
    shareSurveyLinkAction, openShareToStoryConfirm, closeShareToStoryConfirm, confirmShareSurveyToStory,
  } = useGoc();
  const s = state;
  const [tab, setTab] = useState('active');
  const [showCreate, setShowCreate] = useState(false);

  useEffect(() => { loadMySurveys(); }, [loadMySurveys]);

  const filtered = (mySurveys || []).filter(sv => {
    if (tab === 'active') return sv.status === 'draft' || sv.status === 'active';
    if (tab === 'closed') return sv.status === 'closed' || sv.status === 'archived';
    return false;
  });

  const onCreate = async (input) => {
    const created = await createSurveyAction(input);
    if (created) setShowCreate(false);
  };

  return (
    <div style={{ minHeight: '100vh', background: paper, color: ink }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: `1px solid ${rule}` }}>
        <span onClick={goHome} style={{ cursor: 'pointer', fontSize: 18 }}>←</span>
        <h1 style={{ ...display(16, { margin: 0 }) }}>{T('Khảo Sát & Ý Tưởng Sự Kiện', 'Surveys & Event Ideas')}</h1>
        <span style={{ width: 18 }} />
      </div>

      <div style={{ maxWidth: 640, margin: '0 auto', padding: '18px 20px 60px' }}>
        <div style={{ display: 'flex', gap: 8, marginBottom: 18 }}>
          {TABS.map(t => (
            <div
              key={t.key} onClick={() => setTab(t.key)}
              style={{
                padding: '8px 14px', borderRadius: 999, fontSize: 12.5, cursor: 'pointer',
                border: `1px solid ${tab === t.key ? ink : rule}`,
                background: tab === t.key ? ink : 'transparent',
                color: tab === t.key ? paper : ink,
              }}
            >
              {T(t.vi, t.en)}
            </div>
          ))}
        </div>

        {tab === 'active' && (
          <div style={{ marginBottom: 18 }}>
            {!showCreate ? (
              <div onClick={() => setShowCreate(true)} style={{ textAlign: 'center', padding: 12, borderRadius: 10, border: `1px dashed ${rule}`, fontSize: 13, cursor: 'pointer' }}>
                {T('+ Tạo khảo sát mới', '+ Create a new survey')}
              </div>
            ) : (
              <CreateSurveyForm T={T} onCreate={onCreate} busy={mySurveyCreateBusy} error={mySurveyCreateError} />
            )}
          </div>
        )}

        {tab === 'drafts' && (
          <div style={{ padding: 16, fontSize: 13, opacity: 0.7, textAlign: 'center' }}>
            {T(
              'Chưa có gợi ý sự kiện nào — tính năng tạo gợi ý tự động từ kết quả khảo sát chưa được xây dựng.',
              'No suggested event drafts yet — automatic candidate generation from survey results has not been built yet.'
            )}
          </div>
        )}

        {tab !== 'drafts' && mySurveysLoading && (
          <div style={{ textAlign: 'center', fontSize: 13, opacity: 0.6, padding: 20 }}>{T('Đang tải…', 'Loading…')}</div>
        )}

        {tab !== 'drafts' && !mySurveysLoading && filtered.length === 0 && (
          <div style={{ textAlign: 'center', fontSize: 13, opacity: 0.6, padding: 20 }}>
            {tab === 'active' ? T('Chưa có khảo sát nào đang mở.', 'No active surveys yet.') : T('Chưa có khảo sát đã đóng.', 'No closed surveys yet.')}
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {filtered.map(sv => (
            <div key={sv.id} style={{ border: `1px solid ${rule}`, borderRadius: 12, padding: 14 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontSize: 14, fontWeight: 600 }}>{sv.title}</span>
                <span style={{ fontSize: 10.5, opacity: 0.6, textTransform: 'uppercase' }}>{sv.status}</span>
              </div>
              <div style={{ fontSize: 12, opacity: 0.6, marginTop: 4 }}>
                {T('Hạn', 'Deadline')}: {sv.closes_at ? new Date(sv.closes_at).toLocaleString('vi-VN') : '—'}
              </div>
              {sv.status !== 'draft' && (
                <div
                  onClick={() => { navigator.clipboard?.writeText(surveyPublicUrl(sv.public_id)); }}
                  style={{ fontSize: 11.5, opacity: 0.6, marginTop: 4, cursor: 'pointer', wordBreak: 'break-all' }}
                  title={T('Bấm để sao chép', 'Tap to copy')}
                >
                  {surveyPublicUrl(sv.public_id)}
                </div>
              )}
              <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
                <span onClick={() => goSurveyPublic(sv.public_id, 'surveysHosting')} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer' }}>{T('Xem trước', 'Preview')}</span>
                {sv.status === 'draft' && (
                  <>
                    <span onClick={() => publishSurveyAction(sv.id)} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer' }}>{T('Xuất bản', 'Publish')}</span>
                    <span onClick={() => deleteSurveyAction(sv.id)} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer', color: alert }}>{T('Xoá', 'Delete')}</span>
                  </>
                )}
                {sv.status === 'active' && (
                  <>
                    <span onClick={() => shareSurveyLinkAction(sv)} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer' }}>{T('Chia sẻ liên kết', 'Share Link')}</span>
                    <span onClick={() => openShareToStoryConfirm(sv)} data-testid="survey-open-share-to-story" style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer' }}>{T('Chia sẻ lên story', 'Share To Story')}</span>
                    <span onClick={() => closeSurveyAction(sv.id)} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer' }}>{T('Đóng sớm', 'Close early')}</span>
                  </>
                )}
                {sv.status === 'closed' && (
                  <span onClick={() => archiveSurveyAction(sv.id)} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer' }}>{T('Lưu trữ', 'Archive')}</span>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Section 4 redesign — "Show a preview and require explicit Publish;
          no automatic posting." The canvas reuses SurveyStoryCard (the
          SAME renderer StoryViewer.jsx's real in-story card uses, `fill`
          variant) with the host's OWN real organizer name/avatar
          (s.orgRegName/s.myOrganizerAvatarPath — this survey's own
          organizer, since a host only ever has one org context here),
          never a generic "Your organizer" placeholder. The card's own CTA
          is a no onAnswerSurvey handler (not a real action, not
          navigation) — Publish below is the only publishing action.
          Cancel/Publish are anchored in their own safe-area-aware bottom
          bar, outside the scrollable canvas, so a long title/description
          can never push them off-screen. */}
      {s.surveyShareToStoryTarget && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', zIndex: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div
            data-testid="survey-share-to-story-confirm"
            style={{
              background: paper, borderRadius: 24, width: '100%', maxWidth: 400, maxHeight: '92vh',
              display: 'flex', flexDirection: 'column', overflow: 'hidden',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 16px 10px', flexShrink: 0 }}>
              <span style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.7 }}>{T('Xem trước story', 'Story preview')}</span>
              <span onClick={closeShareToStoryConfirm} data-testid="survey-share-to-story-close" style={{ cursor: 'pointer', fontSize: 18, lineHeight: 1 }}>×</span>
            </div>

            {/* Full-bleed canvas — fills the available width, clipped to its
                own rounded bounds, aspect-ratio'd like a real story rather
                than a small padded card floating in empty space. */}
            <div style={{ padding: '0 16px', flex: '1 1 auto', minHeight: 0, display: 'flex' }}>
              <div style={{ width: '100%', aspectRatio: '9 / 15', maxHeight: '100%', margin: '0 auto', borderRadius: 20, overflow: 'hidden' }}>
                <SurveyStoryCard
                  T={T}
                  hostName={s.orgRegName}
                  hostAvatarUrl={organizerAvatarUrl(s.myOrganizerAvatarPath)}
                  title={s.surveyShareToStoryTarget.title}
                  description={s.surveyShareToStoryTarget.description}
                  closesAt={s.surveyShareToStoryTarget.closes_at}
                  status="active"
                  fill
                />
              </div>
            </div>

            {s.surveyShareToStoryError && (
              <div style={{ fontSize: 12, color: alert, padding: '10px 16px 0', flexShrink: 0 }}>{s.surveyShareToStoryError}</div>
            )}

            <div style={{ display: 'flex', gap: 8, padding: '14px 16px calc(14px + env(safe-area-inset-bottom))', flexShrink: 0 }}>
              <div onClick={closeShareToStoryConfirm} data-testid="survey-share-to-story-cancel" style={{ flex: 1, textAlign: 'center', padding: 13, borderRadius: 11, border: `1px solid ${rule}`, fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</div>
              <div
                onClick={s.surveyShareToStoryBusy ? undefined : confirmShareSurveyToStory}
                data-testid="survey-confirm-publish-to-story"
                style={{ flex: 1, textAlign: 'center', padding: 13, borderRadius: 11, background: ink, color: paper, fontSize: 13.5, fontWeight: 600, cursor: s.surveyShareToStoryBusy ? 'default' : 'pointer', opacity: s.surveyShareToStoryBusy ? 0.6 : 1 }}
              >
                {s.surveyShareToStoryBusy ? T('Đang đăng…', 'Posting…') : T('Xuất bản', 'Publish')}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
