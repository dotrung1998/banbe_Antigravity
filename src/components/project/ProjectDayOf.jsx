// Day-of tab of the web Event Project Hub (note 76): event week, event-day card (live only on the event day) with the
// team's call, List | Calendar of the run-of-show, item sheet, trash. Same rules as iOS ProjectDayOfTab / ProjectRosGrid,
// laid out by the shared rosLayout() (tests/fixtures/ros-layout.json). Times in the event's zone.
import { useEffect, useRef, useState } from 'react';
import { rosLayout } from '../../lib/rosLayout.js';
import { openTasks, daysToGo } from '../../lib/projectPresentation.js';
import { CHANNEL_NAMES } from '../../lib/projectChannels.js';
import { paper, ink, ink2, ink3, clay, clayBg, honey, honeyBg, alert, block, blockInset, divider, fieldSolid } from '../../theme.js';
import { Card, Chip, ChipRow, Rows, TaskRow, StatusCircle, Tag, Sheet, FieldLabel, TextField, ReasonField, reasonOk, Note, pillButton, dangerButton, linkButton, PeopleChips } from './ProjectUI.jsx';

const ms = (v) => (v ? Date.parse(v) : null);

function layout(items, now) {
  return rosLayout((items || []).map(r => ({ id: r.id, startsAt: ms(r.starts_at), endsAt: ms(r.ends_at), doneAt: ms(r.done_at) })), now.getTime());
}

function Tick({ p, item }) {
  const done = !!item.done_at;
  return (
    <button type="button" disabled={!p.can('ros.tick') || p.s.projectBusy} onClick={() => p.tickRos(item.id, !done)} data-testid={`project-ros-tick-${item.id}`}
      aria-pressed={done} aria-label={done ? p.T(`Bỏ đánh dấu xong: ${item.title}`, `Mark not done: ${item.title}`) : p.T(`Đánh dấu xong: ${item.title}`, `Mark done: ${item.title}`)}
      style={{ width: 44, height: 44, display: 'grid', placeItems: 'center', background: 'none', border: 0, cursor: 'pointer', padding: 0, flex: 'none' }}>
      <StatusCircle status={done ? 'done' : 'todo'} />
    </button>
  );
}

export default function ProjectDayOf({ p, ui }) {
  const { snap, T, tz } = p;
  const [day, setDay] = useState(null);
  const view = p.s.projectDayView || 'list';
  const editor = p.can('ros.edit');
  const eventDay = snap.event?.event_date;
  const days = [];
  if (eventDay) {
    const [y, m, d] = eventDay.split('-').map(Number);
    for (let i = 6; i >= 0; i--) days.push(new Date(Date.UTC(y, m - 1, d - i)).toISOString().slice(0, 10));
  }
  const toGo = daysToGo(snap.event, p.now()) ?? 0;
  const open = openTasks(snap.tasks || []);
  const channels = snap.project?.channels || [];
  const call = channels.find(c => c.primary) || channels[0];
  const fmt = (dstr, opts) => { const [y, m, d] = dstr.split('-').map(Number); return new Intl.DateTimeFormat(T('vi-VN', 'en-US'), { ...opts, timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d))); };
  const placed = Object.fromEntries(layout(snap.ros, p.now()).items.map(x => [x.id, x]));
  return (
    <div data-testid="project-dayof-tab">
      <Card style={{ padding: '14px 12px' }} data-testid="project-dayof-week">
        <div style={{ display: 'flex', justifyContent: 'space-between', padding: '0 4px 10px' }}>
          <strong>{T('Tuần diễn ra', 'Event week')}</strong>
          <Tag>{toGo > 0 ? T(`Còn ${toGo} ngày`, toGo === 1 ? 'In 1 day' : `In ${toGo} days`) : toGo === 0 ? T('Hôm nay', 'Today') : T('Đã qua', 'Over')}</Tag>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 4 }}>
          {days.map(dstr => {
            const due = open.filter(t => t.due_date === dstr).length, isEvent = dstr === eventDay, on = day === dstr;
            return (
              <button key={dstr} type="button" onClick={() => setDay(on ? null : dstr)} aria-pressed={on} data-testid={`project-dayof-day-${dstr}`}
                aria-label={fmt(dstr, { weekday: 'long', day: 'numeric', month: 'long' }) + (isEvent ? T(', ngày diễn ra', ', event day') : '') + (due ? T(`, ${due} việc đến hạn`, due === 1 ? ', 1 task due' : `, ${due} tasks due`) : '')}
                style={{ minHeight: 64, borderRadius: 14, border: 0, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2,
                  background: on ? ink : isEvent ? clayBg : fieldSolid, color: on ? paper : isEvent ? clay : ink }}>
                <span style={{ fontSize: 11, fontWeight: 700, opacity: 0.8 }}>{fmt(dstr, { weekday: 'narrow' })}</span>
                <strong style={{ fontSize: 17 }}>{Number(dstr.slice(8))}</strong>
                <span style={{ fontSize: 10.5, fontWeight: 700, minHeight: 12, whiteSpace: 'nowrap' }}>{due ? T(`${due} việc`, `${due} due`) : isEvent ? '★' : ''}</span>
              </button>
            );
          })}
        </div>
      </Card>
      {day && (<>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '16px 0 6px' }}>
          <h3 style={{ margin: 0 }}>{T('Việc đến hạn ', 'Tasks due ')}{p.dueText(day)}</h3>
          <button type="button" onClick={() => setDay(null)} style={linkButton} data-testid="project-dayof-clear-day">{T('Bỏ chọn', 'Clear')}</button>
        </div>
        {(snap.tasks || []).filter(t => t.due_date === day).length
          ? <Rows testId="project-dayof-due" items={(snap.tasks || []).filter(t => t.due_date === day)} render={t => <TaskRow task={t} p={p} onOpen={() => ui.openSheet({ kind: 'task', id: t.id })} />} />
          : <Card><Note tone="ink2">{T('Không có việc nào đến hạn ngày này.', 'Nothing is due that day.')}</Note></Card>}
      </>)}
      <div data-testid={ui.live ? 'project-dayof-live' : 'project-dayof-info'} style={{ marginTop: 14, padding: 16, borderRadius: 20, background: honeyBg }}>
        <strong style={{ display: 'block' }}>{ui.live ? T('Đang đồng bộ trực tiếp', 'Live now') : T('Chế độ ngày diễn ra', 'Event-day mode')}</strong>
        <span style={{ fontSize: 14, color: ink2 }}>{ui.live ? T(`Cập nhật mỗi ${p.LIMITS.pollSeconds} giây khi bạn mở thẻ này.`, `Updates every ${p.LIMITS.pollSeconds} seconds while this tab is open.`)
          : T(`Chỉ ngày ${eventDay ? fmt(eventDay, { day: 'numeric', month: 'short' }) : ''} mới đồng bộ trực tiếp để cả đội tick cùng lúc. Các ngày khác đồng bộ khi mở.`, `Only on ${eventDay ? fmt(eventDay, { day: 'numeric', month: 'short' }) : ''} does it sync live, so the team can tick together. Other days it syncs when you open it.`)}</span>
        {call && <div style={{ marginTop: 10 }}><a href={call.url} target="_blank" rel="noopener noreferrer" onClick={e => p.demoLinkBlocked(e)} data-testid="project-dayof-call"
          style={{ display: 'inline-flex', alignItems: 'center', minHeight: 44, padding: '0 14px', borderRadius: 999, background: paper, color: ink, textDecoration: 'none', fontWeight: 600 }}>
          📞 {T('Vào cuộc gọi · ', 'Join call · ')}{call.label || CHANNEL_NAMES[call.platform]}</a></div>}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, margin: '16px 0 10px', flexWrap: 'wrap' }}>
        <ChipRow>
          <Chip title={T('Danh sách', 'List')} selected={view === 'list'} onClick={() => p.set({ projectDayView: 'list' })} testId="project-dayof-view-list" />
          <Chip title={T('Lịch', 'Calendar')} selected={view === 'cal'} onClick={() => p.set({ projectDayView: 'cal' })} testId="project-dayof-view-cal" />
        </ChipRow>
        {editor && <button type="button" onClick={() => ui.openSheet({ kind: 'ros', id: null })} data-testid="project-dayof-add"
          style={{ marginLeft: 'auto', minHeight: 44, padding: '0 14px', borderRadius: 999, border: 0, background: clayBg, color: clay, fontWeight: 700, cursor: 'pointer' }}>＋ {T('Thêm mốc', 'Add item')}</button>}
      </div>
      {view === 'cal' ? <Grid p={p} ui={ui} /> : (
        (snap.ros || []).length ? (
          <Rows testId="project-dayof-list" items={snap.ros} render={r => {
            const pl = placed[r.id];
            return (
              <div data-testid={`project-ros-row-${r.id}`} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0' }}>
                <strong style={{ minWidth: 54, flex: 'none', whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>{p.clock(r.starts_at)}</strong>
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ display: 'block', fontWeight: 600, textDecoration: r.done_at ? 'line-through' : 'none', color: r.done_at ? ink2 : ink }}>{r.title}</span>
                  <span style={{ fontSize: 13, color: ink2 }}>{p.clock(r.starts_at)}–{p.clock(r.ends_at)} · {p.personName(r.owner_id)} {pl?.overrun && <Tag tone="alert">+{pl.overrunMin}′</Tag>}</span>
                </span>
                {editor && <button type="button" onClick={() => ui.openSheet({ kind: 'ros', id: r.id })} data-testid={`project-ros-edit-${r.id}`} aria-label={T(`Sửa ${r.title}`, `Edit ${r.title}`)}
                  style={{ width: 44, height: 44, borderRadius: '50%', border: 0, background: blockInset, color: ink, cursor: 'pointer' }}>✎</button>}
                <Tick p={p} item={r} />
              </div>
            );
          }} />
        ) : <Card><Note tone="ink2">{T('Chưa có mốc nào.', 'No items yet.')}</Note></Card>
      )}
      <div style={{ marginTop: 10 }}><Note>{editor ? T('Bạn thêm, sửa hoặc xoá được các mốc. Mọi người khác chỉ tick xong.', 'You can add, edit or delete items. Everyone else just ticks them off.')
        : T('Chỉ Chủ sự kiện và Quản lý sửa được mốc. Bạn tick khi xong.', "Only the Host and Managers can edit items. Tick yours when it's done.")}</Note></div>
    </div>
  );
}

/** The time grid: hour lines, blocks placed by rosLayout, the now line; redrawn every 30 s. */
function Grid({ p, ui }) {
  const { snap, T } = p;
  const [, setTick] = useState(0);
  useEffect(() => { const id = setInterval(() => setTick(t => t + 1), 30000); return () => clearInterval(id); }, []);
  const nowRef = useRef(null);
  const now = p.now();
  const res = layout(snap.ros, now);
  const editor = p.can('ros.edit');
  const PPM = 1.9, GUTTER = 52;
  if (!res.axis) return <Card><Note tone="ink2">{T('Chưa có mốc nào.', 'No items yet.')}</Note></Card>;
  const y = (t) => ((t - res.axis.start) / 60000) * PPM;
  const height = y(res.axis.end);
  const nowMs = now.getTime();
  const showNow = nowMs >= res.axis.start && nowMs <= res.axis.end;
  const hours = [];
  for (let t = res.axis.start; t <= res.axis.end; t += 1800000) if (p.clock(t).endsWith(':00')) hours.push(t);
  const titleOf = (id) => (snap.ros || []).find(r => r.id === id)?.title || '';
  return (
    <div data-testid="project-ros-grid">
      {showNow && <button type="button" data-testid="project-ros-jump-now" onClick={() => nowRef.current?.scrollIntoView({ block: 'center', behavior: 'smooth' })}
        style={{ minHeight: 44, padding: '0 12px', borderRadius: 999, border: 0, background: blockInset, color: ink, fontWeight: 600, cursor: 'pointer' }}>◎ {T('Về giờ hiện tại', 'Jump to now')}</button>}
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', fontSize: 12, color: ink2, margin: '10px 0' }}>
        {[[alert, T('Kéo dài', 'Overrun')], [honey, T('Bị rút', 'Squeezed')], [clay, T('Đang diễn ra', 'Now')], [ink3, T('Xong', 'Done')]].map(([c, l]) =>
          <span key={l} style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}><i style={{ width: 10, height: 10, borderRadius: 3, background: c, display: 'inline-block' }} />{l}</span>)}
      </div>
      {res.chips.length > 0 && (<>
        <h3 style={{ margin: '4px 0 8px' }}>{T('Lệch so với kế hoạch', 'Versus the plan')}</h3>
        <div data-testid="project-ros-chips" style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
          {res.chips.map((c, i) => <Tag key={i} tone={c.kind === 'squeezed' ? 'honey' : 'alert'}>{titleOf(c.id)} {c.kind === 'overrun' ? `+${c.minutes}′` : c.kind === 'squeezed' ? `−${c.minutes}′` : T('chồng giờ', 'overlaps')}</Tag>)}
        </div>
      </>)}
      <div style={{ position: 'relative', height, marginTop: 16 }}>
        {hours.map(t => (
          <div key={t} aria-hidden style={{ position: 'absolute', top: y(t) - 8, left: 0, right: 0, display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: GUTTER - 6, fontSize: 12, color: ink3, fontVariantNumeric: 'tabular-nums' }}>{p.clock(t)}</span>
            <span style={{ flex: 1, height: 1, background: divider }} />
          </div>
        ))}
        {res.items.map(pl => {
          const item = (snap.ros || []).find(r => r.id === pl.id);
          if (!item) return null;
          const edge = pl.done ? ink3 : pl.active ? clay : pl.overrun ? alert : pl.squeezed ? honey : ink3;
          const fill = pl.done ? blockInset : pl.active ? clayBg : pl.overrun ? 'color-mix(in srgb, var(--bb-alert) 12%, transparent)' : pl.squeezed ? honeyBg : block;
          const times = `${p.clock(pl.start)}–${p.clock(pl.end)}`;
          const label = [item.title, times, p.personName(item.owner_id), pl.done ? T('xong', 'done') : pl.active ? T('đang diễn ra', 'happening now') : null,
            pl.overrun ? T(`trễ ${pl.overrunMin} phút`, `${pl.overrunMin} minutes over`) : null, pl.squeezed ? T(`bị rút ${pl.squeezedMin} phút`, `squeezed by ${pl.squeezedMin} minutes`) : null,
            pl.overlap ? T('chồng giờ', 'overlaps') : null].filter(Boolean).join(', ');
          return (
            <div key={pl.id} style={{ position: 'absolute', top: y(pl.start), left: GUTTER, right: 0, height: Math.max(30, y(pl.end) - y(pl.start) - 3),
              display: 'flex', alignItems: 'flex-start', gap: 6, padding: '5px 4px 5px 11px', borderRadius: 14, background: fill, overflow: 'hidden',
              borderLeft: `5px solid ${edge}`, outline: pl.overlap ? `1.5px dashed ${alert}` : 'none', boxSizing: 'border-box' }}>
              <button type="button" disabled={!editor} onClick={() => ui.openSheet({ kind: 'ros', id: item.id })} data-testid={`project-ros-block-${item.id}`} aria-label={label}
                style={{ flex: 1, minWidth: 0, height: '100%', background: 'none', border: 0, color: ink, textAlign: 'left', cursor: editor ? 'pointer' : 'default', padding: 0 }}>
                <strong style={{ display: 'block', fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textDecoration: pl.done ? 'line-through' : 'none' }}>{item.title}</strong>
                <span style={{ fontSize: 12, color: ink2, whiteSpace: 'nowrap' }}>{times} · {p.personName(item.owner_id)} {pl.overrun ? <Tag tone="alert">+{pl.overrunMin}′</Tag> : pl.overlap ? <Tag tone="alert">{T('chồng giờ', 'overlap')}</Tag> : pl.squeezed ? <Tag tone="honey">−{pl.squeezedMin}′</Tag> : null}</span>
              </button>
              <Tick p={p} item={item} />
            </div>
          );
        })}
        {showNow && (
          <div ref={nowRef} data-testid="project-ros-now-line" role="img" aria-label={`${T('Bây giờ', 'Now')} ${p.clock(nowMs)}`}
            style={{ position: 'absolute', top: y(nowMs) - 11, left: 0, right: 0, display: 'flex', alignItems: 'center', pointerEvents: 'none', zIndex: 3 }}>
            <span style={{ background: clay, color: '#fff', fontSize: 12, fontWeight: 800, padding: '3px 6px', borderRadius: 7, fontVariantNumeric: 'tabular-nums' }}>{p.clock(nowMs)}</span>
            <span style={{ width: 10, height: 10, borderRadius: '50%', background: clay }} /><span style={{ flex: 1, height: 2.5, background: clay }} />
          </div>
        )}
      </div>
      <div style={{ marginTop: 12 }}><Note>{T('Việc chưa tick sẽ kéo dài theo giờ; chỉ việc ngay sau bị rút ngắn (tối thiểu 10 phút), các việc sau giữ nguyên. Tick xong thì chốt giờ kết thúc.', 'An unticked item stretches along the clock; only the very next one is squeezed (10 minutes at least), later ones stay put. Ticking it freezes its end.')}{editor ? T(' Chạm vào khối để sửa.', ' Tap a block to edit it.') : ''}</Note></div>
    </div>
  );
}

/** "2026-11-14T18:30" in the event's zone -> instant, and back (for <input type="datetime-local">). */
function toLocalInput(isoStr, tz) {
  const d = new Date(isoStr);
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(d).map(x => [x.type, x.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour === '24' ? '00' : parts.hour}:${parts.minute}`;
}
function fromLocalInput(value, tz) {
  const [date, time] = value.split('T');
  const [y, m, d] = date.split('-').map(Number), [hh, mm] = time.split(':').map(Number);
  const guess = Date.UTC(y, m - 1, d, hh, mm);
  const offset = (t) => { const s = toLocalInput(new Date(t).toISOString(), tz); const [dd, tt] = s.split('T'); const [Y, M, D] = dd.split('-').map(Number); const [H, Mi] = tt.split(':').map(Number); return Date.UTC(Y, M - 1, D, H, Mi) - t; };
  let t = guess - offset(guess);
  t = guess - offset(t);
  return new Date(t);
}
export { toLocalInput, fromLocalInput };

export function RosSheet({ itemId, close, p }) {
  const { T, snap, tz } = p;
  const L = p.LIMITS;
  const item = itemId ? (snap.ros || []).find(r => r.id === itemId) : null;
  const lastEnd = (snap.ros || []).map(r => Date.parse(r.ends_at)).reduce((a, b) => Math.max(a, b), 0);
  const base = item ? item.starts_at : new Date(lastEnd || Date.parse(snap.event?.starts_at) || p.now().getTime()).toISOString();
  const [title, setTitle] = useState(item?.title || '');
  const [owner, setOwner] = useState(item?.owner_id || null);
  const [start, setStart] = useState(toLocalInput(base, tz));
  const [end, setEnd] = useState(toLocalInput(item ? item.ends_at : new Date(Date.parse(base) + 1800e3).toISOString(), tz));
  const [deleting, setDeleting] = useState(false);
  const [reason, setReason] = useState('');
  const sAt = fromLocalInput(start, tz), eAt = fromLocalInput(end, tz);
  const titleOk = title.trim().length >= L.rosTitleMin && title.trim().length <= L.rosTitleMax;
  const timeOk = eAt.getTime() - sAt.getTime() >= L.rosMinMinutes * 60000;
  if (deleting) {
    return (
      <Sheet title={T('Xoá mốc', 'Delete item')} onClose={close} testId="project-ros-sheet">
        <h3 style={{ margin: 0 }}>{item?.title}</h3>
        <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Đổi lịch', 'Schedule changed'), T('Không cần nữa', 'No longer needed'), T('Viết sai', 'Written wrong')]} />
        <button type="button" disabled={!reasonOk(reason)} data-testid="project-ros-confirm-delete" style={dangerButton({ opacity: reasonOk(reason) ? 1 : 0.4 })}
          onClick={async () => { if (await p.deleteRos(itemId, reason.trim())) close(); }}>{T('Xoá mốc', 'Delete item')}</button>
        <button type="button" onClick={() => setDeleting(false)} style={linkButton}>{T('Không xoá', 'Keep it')}</button>
      </Sheet>
    );
  }
  return (
    <Sheet title={item ? T('Sửa mốc', 'Edit item') : T('Thêm mốc', 'Add item')} onClose={close} testId="project-ros-sheet">
      <TextField label={T('Việc', 'What')} value={title} onChange={setTitle} limit={L.rosTitleMax} placeholder={T('Ví dụ: Mở cửa đón khách', 'e.g. Doors open')} testId="project-ros-title" />
      <TextField type="datetime-local" label={T('Bắt đầu', 'Start')} value={start} testId="project-ros-start"
        onChange={(v) => { if (!v) return; const len = eAt.getTime() - sAt.getTime(); setStart(v); setEnd(toLocalInput(new Date(fromLocalInput(v, tz).getTime() + len).toISOString(), tz)); }} />
      <TextField type="datetime-local" label={T('Kết thúc', 'End')} value={end} onChange={(v) => v && setEnd(v)} testId="project-ros-end" />
      <Note tone={timeOk ? 'ink3' : 'alert'}>{T(`Giờ theo múi giờ sự kiện (${tz}). Kết thúc sau bắt đầu ít nhất ${L.rosMinMinutes} phút.`, `Times are in the event's zone (${tz}). The end is at least ${L.rosMinMinutes} minutes after the start.`)}</Note>
      <FieldLabel>{T('Người phụ trách', 'Who runs it')}</FieldLabel>
      <PeopleChips p={p} value={owner} onChange={setOwner} testId="project-ros-owner" />
      <button type="button" disabled={!titleOk || !timeOk || p.s.projectBusy} data-testid="project-ros-save" style={pillButton(true, { opacity: titleOk && timeOk ? 1 : 0.4 })}
        onClick={async () => { if (await p.saveRos({ itemId, title: title.trim(), ownerId: owner, startsAt: sAt, endsAt: eAt })) close(); }}>{T('Lưu', 'Save')}</button>
      {item && <button type="button" onClick={() => setDeleting(true)} data-testid="project-ros-delete" style={dangerButton()}>{T('Xoá mốc', 'Delete item')}</button>}
    </Sheet>
  );
}

export function TrashSheet({ close, p }) {
  const { T } = p;
  const [items, setItems] = useState(null);
  useEffect(() => { p.loadTrash().then(setItems); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const kind = (k) => ({ task: T('Việc', 'Task'), post: T('Bài', 'Post'), ros: T('Chương trình', 'Run-of-show') }[k] || T('Hạng mục', 'Lane'));
  return (
    <Sheet title={T('Thùng rác', 'Trash')} onClose={close} testId="project-trash">
      <Note tone="ink2">{T(`Mục bị xoá được giữ ${p.LIMITS.trashDays} ngày (tối đa ${p.LIMITS.trashMax} mục) rồi tự dọn. Mọi thao tác đều ghi người làm và lý do.`, `Deleted items are kept ${p.LIMITS.trashDays} days (${p.LIMITS.trashMax} at most), then cleared. Every action records who and why.`)}</Note>
      {items == null ? <Note>{T('Đang tải…', 'Loading…')}</Note> : items.length === 0 ? <Note testId="project-trash-empty">{T('Thùng rác trống.', 'The trash is empty.')}</Note> : (
        <Rows items={items.map(x => ({ ...x, id: `${x.kind}.${x.id}`, itemId: x.id }))} render={t => (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 0', flexWrap: 'wrap' }}>
            <span style={{ flex: '1 1 160px' }}><strong style={{ display: 'block' }}>{t.title}</strong><span style={{ fontSize: 13, color: ink2 }}>{[kind(t.kind), p.personName(t.by), t.reason ? `“${t.reason}”` : null].filter(Boolean).join(' · ')}</span></span>
            <button type="button" data-testid={`project-trash-restore-${t.itemId}`} onClick={async () => { if (await p.restore({ ...t, id: t.itemId })) setItems(items.filter(x => !(x.kind === t.kind && x.id === t.itemId))); }}
              style={{ minHeight: 44, padding: '0 12px', borderRadius: 999, border: 0, background: blockInset, color: ink, fontWeight: 600, cursor: 'pointer' }}>{T('Khôi phục', 'Restore')}</button>
            {p.can('trash.purge') && <button type="button" data-testid={`project-trash-purge-${t.itemId}`} aria-label={T(`Xoá vĩnh viễn ${t.title}`, `Delete ${t.title} for good`)}
              onClick={async () => { if (await p.purge({ ...t, id: t.itemId })) setItems(items.filter(x => !(x.kind === t.kind && x.id === t.itemId))); }}
              style={{ width: 44, height: 44, borderRadius: '50%', border: 0, background: 'color-mix(in srgb, var(--bb-alert) 12%, transparent)', color: alert, cursor: 'pointer' }}>🗑</button>}
          </div>
        )} />
      )}
    </Sheet>
  );
}
