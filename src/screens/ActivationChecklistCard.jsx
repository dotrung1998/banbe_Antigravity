// Home "Get started with banbe" checklist — web twin of iOS ActivationChecklistCard (note 43). Switched on only
// after the onboarding questions were answered (finishOnboardingFlow), hidden once done or dismissed. Web has no
// Face ID, so the items are: open an event, save an event.
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink } from '../theme.js';
import { CHECKLIST_ITEMS, checklistVisible, itemDone } from '../lib/activationChecklist.js';

export default function ActivationChecklistCard() {
  const { state: s, T, dismissActivationChecklist } = useBanBe();
  const hasSaved = (s.favorites || []).length > 0;
  if (!checklistVisible(s.activation, hasSaved)) return null;
  const done = CHECKLIST_ITEMS.filter(i => itemDone(i, s.activation, hasSaved)).length;
  const title = (i) => (i === 'openEvent' ? T('Mở một sự kiện hợp với bạn', 'Open an event that fits you') : T('Lưu một sự kiện bạn thích', 'Save an event you like'));
  return (
    <section data-testid="activation-card" aria-labelledby="activation-title"
      style={{ margin: '10px 20px 0', padding: '6px 4px 8px 16px', borderRadius: 20, background: 'var(--bb-field)', color: ink }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <h2 id="activation-title" style={{ flex: 1, margin: 0, fontSize: 16, fontWeight: 600 }}>{T('Bắt đầu với banbe', 'Get started with banbe')}</h2>
        <span aria-label={T(`Đã xong ${done} trên ${CHECKLIST_ITEMS.length}`, `${done} of ${CHECKLIST_ITEMS.length} done`)}
          style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.65 }}>{done}/{CHECKLIST_ITEMS.length}</span>
        <button type="button" onClick={dismissActivationChecklist} aria-label={T('Ẩn danh sách', 'Hide checklist')} data-testid="activation-dismiss"
          style={{ width: 44, height: 44, border: 'none', background: 'none', color: ink, fontSize: 14, cursor: 'pointer' }}>✕</button>
      </div>
      {CHECKLIST_ITEMS.map(i => {
        const isDone = itemDone(i, s.activation, hasSaved);
        return (
          <div key={i} data-testid={`activation-${i}`} style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: 36, paddingRight: 12, fontSize: 14 }}>
            <span aria-hidden style={{ fontSize: 16 }}>{isDone ? '✓' : '○'}</span>
            <span style={{ textDecoration: isDone ? 'line-through' : 'none', opacity: isDone ? 0.6 : 1 }}>{title(i)}</span>
            <span className="sr-only" style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }}>{isDone ? T('Đã xong', 'Done') : T('Chưa xong', 'Not done')}</span>
          </div>
        );
      })}
    </section>
  );
}
