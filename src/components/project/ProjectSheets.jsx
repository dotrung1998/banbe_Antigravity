// Every sheet the web Event Project Hub opens (note 76). Task, lane, decline, leave and channel sheets live here; the
// post/compose sheets are in ProjectTopics.jsx, member/invite in ProjectTeam.jsx, run-of-show/trash in ProjectDayOf.jsx.
import { useState } from 'react';
import { validateChannel, detectChannelPlatform } from '../../lib/projectChannels.js';
import { ink2, alert, clay, clayBg } from '../../theme.js';
import { Sheet, Chip, ChipRow, FieldLabel, TextField, ReasonField, reasonOk, Note, pillButton, dangerButton, linkButton, PeopleChips } from './ProjectUI.jsx';
import { changeTitle } from './ProjectOverviewTasks.jsx';
import { PostSheet, ComposeSheet } from './ProjectTopics.jsx';
import { MemberSheet, InviteSheet } from './ProjectTeam.jsx';
import { RosSheet, TrashSheet } from './ProjectDayOf.jsx';

export default function ProjectSheetHost({ sheet, close, p, ui }) {
  switch (sheet.kind) {
    case 'task': return <TaskSheet taskId={sheet.id} close={close} p={p} />;
    case 'newTask': return <TaskSheet presetLane={sheet.laneId} close={close} p={p} />;
    case 'newLane': return <NewLaneSheet close={close} p={p} />;
    case 'manageLane': return <ManageLaneSheet laneId={sheet.id} close={close} p={p} />;
    case 'decline': return <DeclineSheet requestId={sheet.id} close={close} p={p} />;
    case 'leave': return <LeaveSheet close={close} p={p} />;
    case 'channels': return <ChannelsSheet close={close} p={p} />;
    case 'channelPropose': return <ChannelProposeSheet close={close} p={p} />;
    case 'post': return <PostSheet postId={sheet.id} close={close} p={p} />;
    case 'compose': return <ComposeSheet close={close} p={p} />;
    case 'member': return <MemberSheet memberId={sheet.id} close={close} p={p} />;
    case 'invite': return <InviteSheet close={close} p={p} />;
    case 'ros': return <RosSheet itemId={sheet.id} close={close} p={p} />;
    case 'trash': return <TrashSheet close={close} p={p} ui={ui} />;
    default: return null;
  }
}


function TaskSheet({ taskId, presetLane, close, p }) {
  const { snap, T } = p;
  const task = taskId ? (snap.tasks || []).find(t => t.id === taskId) : null;
  const lead = snap.me?.role === 'lane_lead' && !snap.is_host;
  const lanes = [...(snap.lanes || [])].sort((a, b) => a.position - b.position).filter(l => !lead || l.id === snap.me?.lane_id);
  const editable = task ? p.can('task.manage', { laneId: task.lane_id }) : p.can('task.manage', { laneId: presetLane });
  const [title, setTitle] = useState(task?.title || '');
  const [laneId, setLaneId] = useState(task?.lane_id || presetLane || lanes[0]?.id || '');
  const [assignee, setAssignee] = useState(task ? task.assignee_id : p.userId);
  const [due, setDue] = useState(task?.due_date || '');
  const [status, setStatus] = useState(task?.status || 'todo');
  const [deleting, setDeleting] = useState(false);
  const [reason, setReason] = useState('');
  const titleOk = title.trim().length >= 3 && title.trim().length <= 60;
  const sheetTitle = !task ? T('Việc mới', 'New task') : editable ? T('Sửa việc', 'Edit task') : T('Việc', 'Task');

  if (task && !editable) {
    const canStatus = p.can('task.status', { laneId: task.lane_id, assigneeId: task.assignee_id });
    return (
      <Sheet title={sheetTitle} onClose={close} testId="project-task-sheet">
        <div><h3 style={{ margin: 0, fontSize: 20 }}>{task.title}</h3>
          <Note tone="ink2">{[p.laneName(task.lane_id), p.personName(task.assignee_id), p.dueText(task.due_date)].filter(Boolean).join(' · ')}</Note></div>
        <FieldLabel>{T('Trạng thái', 'Status')}</FieldLabel>
        <ChipRow>{['todo', 'doing', 'blocked', 'done'].map(st => (
          <Chip key={st} title={p.statusName(st)} selected={task.status === st} disabled={!canStatus || p.s.projectBusy} testId={`project-task-status-${st}`} onClick={() => p.setTaskStatus(task.id, st)} />
        ))}</ChipRow>
        <Note>{canStatus ? T('Bạn đổi được trạng thái. Sửa tên, hạn hoặc xoá việc do Chủ sự kiện, Quản lý hoặc Trưởng hạng mục làm.', 'You can change the status. Editing or deleting is for the Host, a Manager or the lane lead.')
          : T('Bạn không phụ trách việc này nên chỉ xem được.', "You're not on this task, so it's view only.")}</Note>
      </Sheet>
    );
  }
  if (deleting) {
    return (
      <Sheet title={T('Xoá việc', 'Delete task')} onClose={close} testId="project-task-sheet">
        <h3 style={{ margin: 0 }}>{task.title}</h3>
        <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Viết sai', 'Written wrong'), T('Không cần nữa', 'No longer needed'), T('Trùng việc', 'Duplicate')]} />
        <button type="button" disabled={!reasonOk(reason) || p.s.projectBusy} data-testid="project-task-confirm-delete" style={dangerButton({ opacity: reasonOk(reason) ? 1 : 0.4 })}
          onClick={async () => { if (await p.deleteTask(task.id, reason.trim())) close(); }}>{T('Xoá việc', 'Delete task')}</button>
        <button type="button" onClick={() => setDeleting(false)} style={linkButton}>{T('Không xoá', 'Keep it')}</button>
      </Sheet>
    );
  }
  const dirty = !task || title.trim() !== task.title || laneId !== task.lane_id || (assignee || null) !== (task.assignee_id || null) || (due || null) !== (task.due_date || null) || status !== task.status;
  return (
    <Sheet title={sheetTitle} onClose={close} testId="project-task-sheet">
      <TextField label={T('Tên việc', 'Title')} value={title} onChange={setTitle} limit={60} placeholder={T('Làm gì?', 'What needs doing?')} testId="project-task-title" />
      <FieldLabel>{T('Hạng mục', 'Lane')}</FieldLabel>
      <ChipRow>{lanes.map(l => <Chip key={l.id} title={l.name} selected={laneId === l.id} onClick={() => setLaneId(l.id)} testId={`project-task-lane-${l.id}`} />)}</ChipRow>
      <FieldLabel>{T('Người phụ trách', 'Assignee')}</FieldLabel>
      <PeopleChips p={p} value={assignee} onChange={setAssignee} testId="project-task-assignee" />
      <TextField type="date" label={T('Hạn (theo ngày của sự kiện)', 'Due (event day)')} value={due} onChange={setDue} testId="project-task-due" />
      {task && (<>
        <FieldLabel>{T('Trạng thái', 'Status')}</FieldLabel>
        <ChipRow>{['todo', 'doing', 'blocked', 'done'].map(st => <Chip key={st} title={p.statusName(st)} selected={status === st} onClick={() => setStatus(st)} testId={`project-task-status-${st}`} />)}</ChipRow>
        {status === 'blocked' && <Note tone="alert">{T('Việc bị chặn báo ngay cho Chủ sự kiện.', 'A blocked task alerts the Host straight away.')}</Note>}
      </>)}
      <button type="button" data-testid="project-task-save" disabled={!titleOk || !laneId || !dirty || p.s.projectBusy} style={pillButton(true, { opacity: titleOk && dirty ? 1 : 0.4 })}
        onClick={async () => { if (await p.saveTask({ taskId: task?.id || null, laneId, title: title.trim(), assigneeId: assignee || null, dueDate: due || null, status: task ? status : null })) close(); }}>
        {task ? T('Lưu thay đổi', 'Save changes') : T('Tạo việc', 'Create task')}
      </button>
      {!titleOk && <Note>{T('Tên việc dài 3 đến 60 ký tự.', 'A title is 3 to 60 characters.')}</Note>}
      {task && (<>
        <button type="button" data-testid="project-task-delete" onClick={() => setDeleting(true)} style={dangerButton()}>{T('Xoá việc', 'Delete task')}</button>
        <Note>{T('Việc bị xoá vào thùng rác 7 ngày. Chủ sự kiện và Quản lý khôi phục được.', 'Deleted tasks stay in the trash for 7 days. The Host and Managers can restore them.')}</Note>
      </>)}
    </Sheet>
  );
}

function NewLaneSheet({ close, p }) {
  const { T, snap } = p;
  const direct = p.can('lane.manage');
  const [name, setName] = useState('');
  const [why, setWhy] = useState('');
  const n = (snap.lanes || []).length;
  const ok = name.trim().length >= 1 && name.trim().length <= 24 && n < 10 && (direct || reasonOk(why));
  return (
    <Sheet title={direct ? T('Thêm hạng mục', 'Add a lane') : T('Đề xuất hạng mục', 'Propose a lane')} onClose={close} testId="project-lane-sheet">
      {!direct && <div style={{ padding: 14, borderRadius: 16, background: clayBg, color: clay, fontSize: 14 }}>{T('Chủ sự kiện sẽ duyệt và trả lời kèm lý do. Hạng mục chỉ hiện cho cả đội sau khi được duyệt.', 'The Host reviews it and replies with a reason. The lane appears for the team once approved.')}</div>}
      <TextField label={T('Tên hạng mục', 'Lane name')} value={name} onChange={setName} limit={24} placeholder={T('Ví dụ: Truyền thông', 'e.g. Marketing')} testId="project-lane-name" />
      {!direct && <TextField label={T('Vì sao cần?', 'Why is it needed?')} value={why} onChange={setWhy} limit={140} multiline testId="project-lane-why" />}
      <Note>{T(`${n}/10 hạng mục.`, `${n}/10 lanes.`)}</Note>
      <button type="button" disabled={!ok || p.s.projectBusy} data-testid="project-lane-save" style={pillButton(true, { opacity: ok ? 1 : 0.4 })}
        onClick={async () => { const done = direct ? await p.addLane(name.trim()) : await p.proposeChange({ kind: 'lane_add', name: name.trim(), why: why.trim() }); if (done) close(); }}>
        {direct ? T('Thêm', 'Add') : T('Gửi đề xuất', 'Send proposal')}
      </button>
    </Sheet>
  );
}

function ManageLaneSheet({ laneId, close, p }) {
  const { T, snap } = p;
  const lane = (snap.lanes || []).find(l => l.id === laneId);
  const [name, setName] = useState(lane?.name || '');
  const [reason, setReason] = useState('');
  const open = (snap.tasks || []).filter(t => t.lane_id === laneId && t.status !== 'done').length;
  return (
    <Sheet title={T('Quản lý hạng mục', 'Manage lane')} onClose={close}>
      <TextField label={T('Tên hạng mục', 'Lane name')} value={name} onChange={setName} limit={24} />
      <button type="button" disabled={!name.trim() || name.trim() === lane?.name} style={pillButton(true, { opacity: name.trim() && name.trim() !== lane?.name ? 1 : 0.4 })}
        onClick={async () => { if (await p.renameLane(laneId, name.trim())) close(); }}>{T('Đổi tên', 'Rename')}</button>
      <strong>{T('Lưu trữ hạng mục', 'Archive lane')}</strong>
      <Note tone="ink2">{open > 0 ? T(`Còn ${open} việc chưa xong. Hãy xong hoặc chuyển sang hạng mục khác trước.`, `${open} open task(s) left. Finish them or move them to another lane first.`)
        : T('Lưu trữ sẽ ẩn hạng mục. Bạn khôi phục được từ thùng rác.', 'Archiving hides the lane. You can restore it from the trash.')}</Note>
      {open === 0 && (<>
        <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Gộp vào hạng mục khác', 'Merged into another lane'), T('Không cần nữa', 'No longer needed')]} />
        <button type="button" disabled={!reasonOk(reason)} style={dangerButton({ opacity: reasonOk(reason) ? 1 : 0.4 })}
          onClick={async () => { if (await p.archiveLane(laneId, reason.trim())) close(); }}>{T('Lưu trữ', 'Archive')}</button>
      </>)}
    </Sheet>
  );
}

function DeclineSheet({ requestId, close, p }) {
  const { T, snap } = p;
  const r = (snap.change_requests || []).find(c => c.id === requestId);
  const [reason, setReason] = useState('');
  return (
    <Sheet title={T('Từ chối đề xuất', 'Decline proposal')} onClose={close} testId="project-decline-sheet">
      {r && <h3 style={{ margin: 0 }}>{changeTitle(p, r)}</h3>}
      <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Đã nằm trong hạng mục khác', 'Already covered by another lane'), T('Chưa cần lúc này', 'Not needed right now'), T('Quá sát ngày diễn ra', 'Too close to the event')]} />
      <button type="button" disabled={!reasonOk(reason) || p.s.projectBusy} data-testid="project-decline-confirm" style={dangerButton({ opacity: reasonOk(reason) ? 1 : 0.4 })}
        onClick={async () => { if (await p.reviewChange(requestId, false, reason.trim())) close(); }}>{T('Từ chối', 'Decline')}</button>
      <Note>{T('Người đề xuất sẽ thấy lý do.', 'The proposer will see the reason.')}</Note>
    </Sheet>
  );
}

function LeaveSheet({ close, p }) {
  const { T } = p;
  return (
    <Sheet title={T('Rời dự án', 'Leave project')} onClose={close}>
      <p style={{ margin: 0 }}>{T('Việc đang giao cho bạn sẽ thành chưa giao. Bạn cần lời mời mới để vào lại.', "Tasks given to you become unassigned. You'll need a new invite to come back.")}</p>
      <button type="button" data-testid="project-leave-confirm" style={dangerButton()} onClick={() => { close(); p.leave(); }}>{T('Rời dự án', 'Leave project')}</button>
    </Sheet>
  );
}

const channelError = (T, e) => ({
  url: T('Dán một liên kết https đầy đủ.', 'Paste a full https link.'),
  platform: T('Liên kết không khớp với nền tảng đã chọn.', "The link doesn't match the platform."),
  label: T('Tên tối đa 30 ký tự.', 'A name is up to 30 characters.'),
}[e] || T('Liên kết chưa hợp lệ.', "That link isn't valid."));

/** Host: edit the list (up to 5, one primary). One write on Save. */
function ChannelsSheet({ close, p }) {
  const { T, snap } = p;
  const [list, setList] = useState(snap.project?.channels || []);
  const [url, setUrl] = useState('');
  const [label, setLabel] = useState('');
  const [err, setErr] = useState('');
  const add = () => {
    const r = validateChannel({ url: url.trim(), label, platform: detectChannelPlatform(url.trim()) || 'link', primary: list.length === 0 });
    if (!r.ok) { setErr(channelError(T, r.error)); return; }
    if (list.some(c => c.url === r.channel.url)) { setErr(T('Liên kết này đã có.', 'That link is already there.')); return; }
    setList([...list, r.channel]); setUrl(''); setLabel(''); setErr('');
  };
  return (
    <Sheet title={T('Kênh của đội', 'Team channels')} onClose={close} testId="project-channels-sheet">
      <Note tone="ink2">{T('Ai có liên kết đều vào được kênh. Chỉ thành viên dự án thấy các liên kết này.', 'Anyone with a link can join that channel. Only project members see these links.')}</Note>
      {list.map((c, i) => (
        <div key={c.url} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}><strong>{c.label}</strong><br /><span style={{ fontSize: 13, color: ink2 }}>{c.url}</span></span>
          <button type="button" aria-label={T('Đặt làm kênh chính', 'Make primary')} aria-pressed={c.primary} onClick={() => setList(list.map((x, j) => ({ ...x, primary: j === i })))}
            style={{ width: 44, height: 44, border: 0, borderRadius: '50%', background: 'none', color: c.primary ? clay : ink2, cursor: 'pointer', fontSize: 18 }}>{c.primary ? '★' : '☆'}</button>
          <button type="button" aria-label={T('Bỏ', 'Remove')} onClick={() => setList(list.filter((_, j) => j !== i))}
            style={{ width: 44, height: 44, border: 0, borderRadius: '50%', background: 'none', color: alert, cursor: 'pointer' }}>✕</button>
        </div>
      ))}
      {list.length < 5 && (<>
        <TextField label={T('Liên kết', 'Link')} value={url} onChange={setUrl} limit={300} placeholder="https://zalo.me/g/…" testId="project-channel-url" />
        <TextField label={T('Tên (không bắt buộc)', 'Name (optional)')} value={label} onChange={setLabel} limit={30} testId="project-channel-label" />
        {err && <Note tone="alert">{err}</Note>}
        <button type="button" onClick={add} disabled={!url.trim()} style={pillButton(false)} data-testid="project-channel-add">{T('Thêm vào danh sách', 'Add to the list')}</button>
      </>)}
      <Note>{T(`${list.length}/5 kênh.`, `${list.length} of 5 channels.`)}</Note>
      <button type="button" data-testid="project-channels-save" disabled={p.s.projectBusy} style={pillButton(true)}
        onClick={async () => { if (await p.saveChannels(list)) close(); }}>{T('Lưu', 'Save')}</button>
    </Sheet>
  );
}

/** Manager: suggest one channel with a reason; the Host approves or declines it. */
function ChannelProposeSheet({ close, p }) {
  const { T } = p;
  const [url, setUrl] = useState('');
  const [label, setLabel] = useState('');
  const [why, setWhy] = useState('');
  const [err, setErr] = useState('');
  return (
    <Sheet title={T('Đề xuất kênh', 'Suggest a channel')} onClose={close}>
      <TextField label={T('Liên kết', 'Link')} value={url} onChange={setUrl} limit={300} placeholder="https://meet.google.com/…" />
      <TextField label={T('Tên (không bắt buộc)', 'Name (optional)')} value={label} onChange={setLabel} limit={30} />
      <TextField label={T('Vì sao cần?', 'Why is it needed?')} value={why} onChange={setWhy} limit={140} multiline />
      {err && <Note tone="alert">{err}</Note>}
      <button type="button" disabled={!url.trim() || !reasonOk(why)} style={pillButton(true, { opacity: url.trim() && reasonOk(why) ? 1 : 0.4 })}
        onClick={async () => {
          const r = validateChannel({ url: url.trim(), label, platform: detectChannelPlatform(url.trim()) || 'link', primary: false });
          if (!r.ok) { setErr(channelError(T, r.error)); return; }
          if (await p.proposeChange({ kind: 'channel_add', url: r.channel.url, channel: r.channel, why: why.trim() })) close();
        }}>{T('Gửi đề xuất', 'Send proposal')}</button>
    </Sheet>
  );
}
