import { paper, ink, display } from '../../theme.js';

// Section 4 redesign — ONE shared renderer for a survey story's card
// content, used by BOTH the host's publish-preview (SurveysHosting.jsx's
// ShareSurveyToStoryConfirmView) and the real in-story card
// (StoryViewer.jsx's SurveyShareCard), so the preview is never a different
// layout from what viewers actually see — same host identity row, same
// title/description region, same deadline/CTA placement. `fill` switches
// between the preview's full-bleed canvas (large typography, no outer
// shadow — it already sits inside the sheet's own rounded canvas) and the
// real story viewer's smaller floating card (unchanged visual size).
//
// The gradient is the SAME dusty-rose/sage/sand gradient Banbe Pulse's own
// ring already uses (Home.jsx) — this app's one existing "branded
// placeholder" gradient, reused here rather than inventing a new palette
// or requiring new uploaded artwork.
export const SURVEY_STORY_GRADIENT = 'linear-gradient(150deg, #E7C9C2, #E3CFA6 50%, #C8CBB2)';

export default function SurveyStoryCard({ T, hostName, hostAvatarUrl, title, description, closesAt, status, onAnswerSurvey, fill = false }) {
  const closed = Boolean(status) && status !== 'active';
  return (
    <div
      data-testid="survey-story-card"
      style={{
        position: 'relative', width: '100%', height: '100%',
        borderRadius: fill ? 26 : 18, overflow: 'hidden',
        background: SURVEY_STORY_GRADIENT, color: ink,
        display: 'flex', flexDirection: 'column',
        padding: fill ? '22px 22px 26px' : '18px',
        boxShadow: fill ? 'none' : '0 18px 44px rgba(0,0,0,0.5)',
        boxSizing: 'border-box',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
        {hostAvatarUrl ? (
          <img src={hostAvatarUrl} alt="" style={{ width: 34, height: 34, borderRadius: 10, objectFit: 'cover', flexShrink: 0 }} />
        ) : (
          <div style={{ width: 34, height: 34, borderRadius: 10, background: 'rgba(255,255,255,0.5)', flexShrink: 0 }} />
        )}
        <span style={{ fontSize: 12.5, fontWeight: 700, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {hostName || T('Người tổ chức', 'Organizer')}
        </span>
      </div>

      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 10, padding: '18px 0', overflowY: 'auto' }}>
        <div style={{ ...display(fill ? 25 : 18, { lineHeight: 1.2 }) }}>{title}</div>
        {description && <div style={{ fontSize: fill ? 14 : 12.5, lineHeight: 1.45, opacity: 0.85 }}>{description}</div>}
      </div>

      <div style={{ flexShrink: 0 }}>
        {closesAt && (
          <div style={{ fontSize: 12, opacity: 0.75, marginBottom: 12 }}>
            {T('Hạn trả lời', 'Deadline')}: {new Date(closesAt).toLocaleString('vi-VN')}
          </div>
        )}
        <div
          onClick={onAnswerSurvey}
          data-testid="survey-story-cta"
          style={{
            padding: '13px 0', textAlign: 'center', borderRadius: 12,
            background: closed ? 'transparent' : ink, color: closed ? ink : paper,
            border: closed ? `1.5px solid ${ink}` : 'none', fontSize: 14, fontWeight: 700,
            opacity: closed ? 0.7 : 1, cursor: onAnswerSurvey ? 'pointer' : 'default',
          }}
        >
          {closed ? T('Khảo sát đã đóng', 'Survey closed') : T('Trả lời khảo sát', 'Answer Survey')}
        </div>
      </div>
    </div>
  );
}
