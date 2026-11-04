// Shared pieces of the web Event Project Hub (note 76). Same tokens as the iOS hub: done = a filled ink check (the
// prototype's green has no token), doing = honey, blocked = alert, to do = an ink3 ring. 44 px touch targets.
import { projectPeople } from '../../lib/projectPresentation.js';
import { paper, ink, ink2, ink3, block, blockInset, divider, fieldSolid, clay, clayBg, honey, honeyBg, alert, display } from '../../theme.js';

export const TOKENS = { paper, ink, ink2, ink3, block, blockInset, divider, fieldSolid, clay, clayBg, honey, honeyBg, alert };

export function Card({ children, padding = 16, style, ...rest }) {
  return <div style={{ background: block, borderRadius: 20, padding: `${padding}px 16px`, ...style }} {...rest}>{children}</div>;
}

export function SectionHeader({ title, action, onAction, testId }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '22px 0 8px' }}>
      <h2 style={{ ...display(20, { margin: 0 }) }}>{title}</h2>
      {action && <button type="button" onClick={onAction} data-testid={testId} style={linkButton}>{action}</button>}
    </div>
  );
}

export function CountHeader({ title, count }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '20px 0 8px', fontSize: 12, fontWeight: 700, letterSpacing: 0.6, color: ink3 }}>
      <span role="heading" aria-level={3}>{title.toUpperCase()}</span><span>{count}</span>
    </div>
  );
}

export const linkButton = { background: 'none', border: 0, color: clay, fontWeight: 600, fontSize: 14, minHeight: 44, cursor: 'pointer', padding: 0 };
export const pillButton = (primary = false, extra) => ({
  minHeight: 50, borderRadius: 999, border: 0, cursor: 'pointer', fontWeight: 700, fontSize: 15, width: '100%',
  background: primary ? ink : blockInset, color: primary ? paper : ink, ...extra,
});
export const dangerButton = (extra) => pillButton(false, { background: 'color-mix(in srgb, var(--bb-alert) 12%, transparent)', color: alert, ...extra });

export function Chip({ title, selected, onClick, disabled, testId, style }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled} aria-pressed={!!selected} data-testid={testId}
      style={{ minHeight: 40, padding: '0 14px', borderRadius: 999, border: 0, cursor: disabled ? 'default' : 'pointer', whiteSpace: 'nowrap',
        fontSize: 14, fontWeight: 600, background: selected ? ink : blockInset, color: selected ? paper : ink, opacity: disabled ? 0.4 : 1, ...style }}>
      {title}
    </button>
  );
}

export function ChipRow({ children, scroll = false }) {
  return <div style={{ display: 'flex', gap: 8, flexWrap: scroll ? 'nowrap' : 'wrap', overflowX: scroll ? 'auto' : 'visible', paddingBottom: scroll ? 2 : 0 }}>{children}</div>;
}

export function StatusCircle({ status, size = 28 }) {
  const common = { width: size, height: size, borderRadius: '50%', boxSizing: 'border-box', display: 'grid', placeItems: 'center', flex: 'none' };
  if (status === 'done') return <span aria-hidden style={{ ...common, background: ink, color: paper, fontSize: 14, fontWeight: 900 }}>✓</span>;
  if (status === 'doing') return <span aria-hidden style={{ ...common, background: honeyBg, border: `2px solid ${honey}` }} />;
  if (status === 'blocked') return <span aria-hidden style={{ ...common, background: 'color-mix(in srgb, var(--bb-alert) 14%, transparent)', border: `2px solid ${alert}` }} />;
  return <span aria-hidden style={{ ...common, border: `2px solid ${ink3}` }} />;
}

export function StatusTag({ status, label }) {
  const [fg, bg] = status === 'done' ? [paper, ink] : status === 'doing' ? [honey, honeyBg]
    : status === 'blocked' ? [alert, 'color-mix(in srgb, var(--bb-alert) 14%, transparent)'] : [ink2, blockInset];
  return <span style={{ fontSize: 12, fontWeight: 700, padding: '4px 9px', borderRadius: 999, color: fg, background: bg, whiteSpace: 'nowrap' }}>{label}</span>;
}

export function Tag({ children, tone = 'clay', testId }) {
  const [fg, bg] = tone === 'clay' ? [clay, clayBg] : tone === 'alert' ? [alert, 'color-mix(in srgb, var(--bb-alert) 14%, transparent)']
    : tone === 'honey' ? [honey, honeyBg] : [ink2, blockInset];
  return <span data-testid={testId} style={{ fontSize: 12, fontWeight: 700, padding: '3px 9px', borderRadius: 999, color: fg, background: bg, whiteSpace: 'nowrap', display: 'inline-flex', gap: 4, alignItems: 'center' }}>{children}</span>;
}

export function Avatar({ name = '?', size = 42 }) {
  return (
    <span aria-hidden style={{ width: size, height: size, borderRadius: '50%', background: clayBg, color: clay, display: 'grid', placeItems: 'center',
      fontWeight: 700, fontSize: Math.round(size * 0.4), flex: 'none' }}>{String(name).slice(0, 1).toUpperCase()}</span>
  );
}

export function Rows({ items, render, testId }) {
  return (
    <Card padding={4} data-testid={testId}>
      {items.map((it, i) => (
        <div key={it.id ?? it.member_id ?? i}>
          {render(it)}
          {i < items.length - 1 && <div style={{ height: 1, background: divider }} />}
        </div>
      ))}
    </Card>
  );
}

/** One task: a 44 px tick, the title, "lane · person · due", and the status tag. */
export function TaskRow({ task, p, showLane = true, onOpen }) {
  const late = task.status !== 'done' && task.due_date && (p.dueText(task.due_date) || '').match(/trễ|late/i);
  const meta = [showLane ? p.laneName(task.lane_id) : null, p.personName(task.assignee_id), p.dueText(task.due_date)].filter(Boolean).join(' · ');
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '6px 0' }}>
      <button type="button" onClick={() => p.toggleTaskDone(task)} data-testid={`project-task-tick-${task.id}`} aria-label={task.status === 'done' ? p.T('Bỏ đánh dấu xong', 'Mark not done') : p.T('Đánh dấu xong', 'Mark done')}
        aria-pressed={task.status === 'done'} data-status={task.status}
        style={{ width: 44, height: 44, display: 'grid', placeItems: 'center', background: 'none', border: 0, cursor: 'pointer', padding: 0 }}>
        <StatusCircle status={task.status} />
      </button>
      <button type="button" onClick={onOpen} data-testid={`project-task-${task.id}`}
        style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 10, minHeight: 44, background: 'none', border: 0, cursor: 'pointer', textAlign: 'left', color: ink, padding: 0 }}>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{ display: 'block', fontWeight: 600, fontSize: 15.5, textDecoration: task.status === 'done' ? 'line-through' : 'none', color: task.status === 'done' ? ink2 : ink }}>{task.title}</span>
          <span style={{ display: 'block', fontSize: 13, color: late ? alert : ink2 }}>{meta}</span>
        </span>
        <StatusTag status={task.status} label={p.statusName(task.status)} />
      </button>
    </div>
  );
}

/** Bottom sheet over the hub (like the app's other web sheets). */
export function Sheet({ title, onClose, children, testId, closeTestId = 'project-sheet-close' }) {
  return (
    <div onClick={onClose} style={{ position: 'absolute', inset: 0, zIndex: 30, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
      <div role="dialog" aria-modal="true" aria-label={title} data-testid={testId} onClick={(e) => e.stopPropagation()}
        style={{ background: paper, color: ink, borderRadius: '22px 22px 0 0', maxHeight: '88%', display: 'flex', flexDirection: 'column', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 16px 6px 20px' }}>
          <strong style={{ fontSize: 16 }}>{title}</strong>
          <button type="button" onClick={onClose} aria-label="Close" data-testid={closeTestId}
            style={{ width: 44, height: 44, borderRadius: '50%', border: 0, background: blockInset, color: ink, cursor: 'pointer', fontSize: 16 }}>✕</button>
        </div>
        <div style={{ overflowY: 'auto', padding: '8px 20px 30px', display: 'flex', flexDirection: 'column', gap: 16 }}>{children}</div>
      </div>
    </div>
  );
}

export function FieldLabel({ children }) {
  return <div role="heading" aria-level={4} style={{ fontSize: 12, fontWeight: 700, letterSpacing: 0.6, color: ink3, textTransform: 'uppercase' }}>{children}</div>;
}

export function TextField({ label, value, onChange, limit, placeholder, multiline = false, testId, type = 'text' }) {
  const Tag = multiline ? 'textarea' : 'input';
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <span style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, fontWeight: 700, letterSpacing: 0.6, color: ink3 }}>
        <span>{label.toUpperCase()}</span>{limit ? <span aria-hidden>{(value || '').length}/{limit}</span> : null}
      </span>
      <Tag type={multiline ? undefined : type} value={value} placeholder={placeholder} maxLength={limit} rows={multiline ? 3 : undefined} data-testid={testId}
        onChange={(e) => onChange(limit ? e.target.value.slice(0, limit) : e.target.value)}
        style={{ font: 'inherit', fontSize: 16, padding: '13px 14px', borderRadius: 14, border: 0, background: fieldSolid, color: ink, resize: 'vertical', minHeight: 48, boxSizing: 'border-box', width: '100%' }} />
    </label>
  );
}

export const reasonOk = (s) => String(s || '').trim().length >= 3;

export function ReasonField({ reason, setReason, picks, T }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <ChipRow>{picks.map(pk => <Chip key={pk} title={pk} selected={reason === pk} onClick={() => setReason(pk)} testId="project-reason-pick" />)}</ChipRow>
      <TextField label={T('Lý do', 'Reason')} value={reason} onChange={setReason} limit={140} placeholder={T('Một dòng ngắn…', 'One short line…')} testId="project-reason" />
    </div>
  );
}

export function Note({ children, tone = 'ink3', testId }) {
  return <p data-testid={testId} style={{ margin: 0, fontSize: 13, lineHeight: 1.5, color: tone === 'alert' ? alert : tone === 'ink2' ? ink2 : ink3 }}>{children}</p>;
}

/** One chip per person in the project (Hosts, then members); tapping the selected one clears it. */
export function PeopleChips({ p, value, onChange, testId, exclude }) {
  return (
    <ChipRow>
      {projectPeople(p.snap).filter(x => String(x.user_id).toLowerCase() !== exclude).map(x => (
        <Chip key={x.user_id} title={p.personName(x.user_id)} selected={String(value || '').toLowerCase() === String(x.user_id).toLowerCase()}
          onClick={() => onChange(String(value || '').toLowerCase() === String(x.user_id).toLowerCase() ? null : x.user_id)} testId={`${testId}-${x.user_id}`} />
      ))}
    </ChipRow>
  );
}
