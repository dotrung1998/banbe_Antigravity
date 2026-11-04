// Overview and Tasks tabs of the web Event Project Hub (note 76). Same content and rules as the iOS
// ProjectOverviewTab / ProjectTasksTab: proposals banner (Host), team channels, readiness + lane bars, needs attention,
// coming up, decision log; Tasks: lane proposals, All | Mine, lanes with their tasks.
import { useState } from 'react';
import { readiness, laneProgress, attention, comingUp, decisions, myOpenTasks } from '../../lib/projectPresentation.js';
import { CHANNEL_NAMES, channelHost } from '../../lib/projectChannels.js';
import { ink, ink2, ink3, clay, clayBg, blockInset, divider, alert } from '../../theme.js';
import { Card, SectionHeader, Chip, ChipRow, Rows, TaskRow, Note, linkButton, pillButton } from './ProjectUI.jsx';

export function changeTitle(p, r) {
  const n = r.payload?.name || r.payload?.channel?.label || r.payload?.url || '';
  const kind = {
    lane_add: p.T('Hạng mục mới', 'New lane'), lane_rename: p.T('Đổi tên hạng mục', 'Rename lane'), lane_archive: p.T('Lưu trữ hạng mục', 'Archive lane'),
    channel_add: p.T('Kênh mới', 'New channel'), channel_edit: p.T('Sửa kênh', 'Edit channel'), channel_remove: p.T('Bỏ kênh', 'Remove channel'),
  }[r.kind] || r.kind;
  return n ? `${kind}: ${n}` : kind;
}

export function ProjectOverview({ p, ui }) {
  const { snap, T } = p;
  const tasks = snap.tasks || [];
  const pending = snap.is_host ? (snap.change_requests || []).filter(c => c.status === 'pending') : [];
  const r = readiness(tasks);
  const lanes = laneProgress(snap.lanes || [], tasks);
  const att = attention(tasks, p.now(), p.tz);
  const next = comingUp(tasks);
  const log = decisions(snap.posts || []);
  return (
    <div data-testid="project-overview">
      {pending.length > 0 && (
        <div data-testid="project-overview-proposals" style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 10, padding: 14, borderRadius: 18, background: clayBg, color: clay, marginBottom: 4 }}>
          <span style={{ flex: '1 1 200px', fontWeight: 600, fontSize: 14 }}>{T(`${pending.length} đề xuất chờ bạn duyệt`, pending.length === 1 ? '1 proposal waits for your review' : `${pending.length} proposals wait for your review`)}</span>
          <button type="button" onClick={() => p.set({ projectTab: 'tasks' })} data-testid="project-overview-review" style={{ ...linkButton, color: clay }}>{T('Xem', 'Review')} ›</button>
        </div>
      )}
      <ChannelsCard p={p} ui={ui} />
      <SectionHeader title={T('Mức sẵn sàng', 'Readiness')} />
      <Card data-testid="project-overview-readiness">
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <Ring percent={r.percent} />
          <div style={{ fontSize: 14, color: ink2 }}>{T(`${r.done}/${r.total} việc xong`, `${r.done} of ${r.total} tasks done`)}</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 14 }}>
          {lanes.map(l => (
            <div key={l.laneId}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}><span>{l.name}</span><span style={{ color: ink2 }}>{l.done}/{l.total}</span></div>
              <div style={{ height: 6, borderRadius: 3, background: blockInset, marginTop: 4 }}>
                <div style={{ height: 6, borderRadius: 3, background: clay, width: `${l.total ? (l.done * 100) / l.total : 0}%` }} />
              </div>
            </div>
          ))}
        </div>
      </Card>
      {att.length > 0 && (<>
        <SectionHeader title={T('Cần chú ý', 'Needs attention')} />
        <Rows testId="project-overview-attention" items={att} render={t => <TaskRow task={t} p={p} onOpen={() => ui.openSheet({ kind: 'task', id: t.id })} />} />
      </>)}
      <SectionHeader title={T('Sắp tới', 'Coming up')} />
      {next.length ? <Rows items={next} render={t => <TaskRow task={t} p={p} onOpen={() => ui.openSheet({ kind: 'task', id: t.id })} />} />
        : <Note>{T('Không còn việc nào mở.', 'No open tasks.')}</Note>}
      {log.length > 0 && (<>
        <SectionHeader title={T('Nhật ký quyết định', 'Decision log')} />
        <Rows items={log} render={d => (
          <button type="button" onClick={() => ui.openSheet({ kind: 'post', id: d.id })} style={{ display: 'flex', gap: 10, alignItems: 'center', width: '100%', minHeight: 50, background: 'none', border: 0, color: ink, textAlign: 'left', cursor: 'pointer', padding: '6px 0' }}>
            <span aria-hidden>🔒</span><span style={{ flex: 1 }}><span style={{ display: 'block', fontWeight: 600 }}>{d.title}</span><span style={{ fontSize: 13, color: ink2 }}>{p.laneName(d.lane_id)} · {p.personName(d.author_id)}</span></span>
          </button>
        )} />
      </>)}
    </div>
  );
}

function Ring({ percent }) {
  const r = 26, c = 2 * Math.PI * r;
  return (
    <svg width="64" height="64" viewBox="0 0 64 64" role="img" aria-label={`${percent}%`}>
      <circle cx="32" cy="32" r={r} fill="none" stroke="var(--bb-block-inset)" strokeWidth="7" />
      <circle cx="32" cy="32" r={r} fill="none" stroke="var(--bb-clay)" strokeWidth="7" strokeDasharray={`${(c * percent) / 100} ${c}`} strokeLinecap="round" transform="rotate(-90 32 32)" />
      <text x="32" y="37" textAnchor="middle" fontSize="15" fontWeight="700" fill="var(--bb-fg)">{percent}%</text>
    </svg>
  );
}

/** Team channels: the Host edits, a Manager suggests, everyone opens. Opens outside banbe. */
export function ChannelsCard({ p, ui }) {
  const { snap, T } = p;
  const channels = snap.project?.channels || [];
  const host = p.can('channels.edit');
  const manager = p.can('change.propose');
  if (!channels.length && !host) return null;
  return (
    <>
      <SectionHeader title={T('Kênh của đội', 'Team channels')}
        action={host ? T('Sửa', 'Edit') : manager ? T('Đề xuất kênh', 'Suggest a channel') : null}
        onAction={() => ui.openSheet({ kind: host ? 'channels' : 'channelPropose' })} testId="project-channels-edit" />
      <Card padding={4} data-testid="project-channels">
        {channels.length === 0 && <div style={{ padding: '14px 0' }}><Note tone="ink2">{T('Thêm Zalo, Zoom hay Meet để đội nói chuyện thêm khi cần.', 'Add a Zalo group, Zoom or Meet so the team can talk things through.')}</Note></div>}
        {channels.map((c, i) => (
          <div key={c.url}>
            <a href={c.url} target="_blank" rel="noopener noreferrer" data-testid="project-channel-link"
              style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 56, color: ink, textDecoration: 'none' }}>
              <span aria-hidden style={{ width: 36, height: 36, borderRadius: 10, background: clayBg, color: clay, display: 'grid', placeItems: 'center', fontWeight: 800 }}>{(CHANNEL_NAMES[c.platform] || '↗').slice(0, 1)}</span>
              <span style={{ flex: 1, minWidth: 0 }}>
                <span style={{ display: 'block', fontWeight: 600 }}>{c.label || CHANNEL_NAMES[c.platform] || T('Liên kết', 'Link')}{c.primary ? ' ★' : ''}</span>
                <span style={{ display: 'block', fontSize: 13, color: ink3 }}>{channelHost(c.url) || ''}</span>
              </span>
              <span style={{ color: clay, fontWeight: 600, fontSize: 14 }}>{T('Mở', 'Open')} ↗</span>
            </a>
            {i < channels.length - 1 && <div style={{ height: 1, background: divider }} />}
          </div>
        ))}
      </Card>
      {channels.length > 0 && <Note>{T('Mở ngoài banbe. banbe không thấy các tin nhắn đó.', "Opens outside banbe. banbe doesn't see those messages.")}</Note>}
    </>
  );
}

export function ProjectTasks({ p, ui }) {
  const { snap, T } = p;
  const [filter, setFilter] = useState('all');
  const tasks = snap.tasks || [];
  const lanes = [...(snap.lanes || [])].sort((a, b) => a.position - b.position);
  const shown = filter === 'mine' ? myOpenTasks(tasks, p.userId).concat(tasks.filter(t => t.status === 'done' && String(t.assignee_id || '').toLowerCase() === p.userId)) : tasks;
  const requests = snap.change_requests || [];
  const pendingForHost = snap.is_host ? requests.filter(r => r.status === 'pending') : [];
  const mine = snap.is_host ? [] : requests.filter(r => String(r.proposed_by || '').toLowerCase() === p.userId);
  return (
    <div data-testid="project-tasks-tab">
      {pendingForHost.length > 0 && (<>
        <SectionHeader title={T('Đề xuất chờ duyệt', 'Proposals to review')} />
        <Rows items={pendingForHost} render={r => (
          <div style={{ padding: '10px 0', display: 'flex', flexDirection: 'column', gap: 8 }}>
            <strong>{changeTitle(p, r)}</strong>
            <span style={{ fontSize: 13, color: ink2 }}>“{r.why}” · {p.personName(r.proposed_by)}</span>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <button type="button" data-testid={`project-proposal-approve-${r.id}`} onClick={() => p.reviewChange(r.id, true)} style={pillButton(true, { flex: '1 1 140px', width: 'auto' })}>{T('Duyệt', 'Approve')}</button>
              <button type="button" data-testid={`project-proposal-decline-${r.id}`} onClick={() => ui.openSheet({ kind: 'decline', id: r.id })} style={pillButton(false, { flex: '1 1 140px', width: 'auto' })}>{T('Từ chối', 'Decline')}</button>
            </div>
          </div>
        )} />
      </>)}
      {mine.length > 0 && (<>
        <SectionHeader title={T('Đề xuất của bạn', 'Your proposals')} />
        <Rows items={mine} render={r => (
          <div style={{ padding: '10px 0' }}>
            <strong>{changeTitle(p, r)}</strong>
            <div style={{ fontSize: 13, color: r.status === 'declined' ? alert : ink2 }}>
              {r.status === 'pending' ? T('Đang chờ Chủ sự kiện', 'Waiting for the Host') : r.status === 'approved' ? T('Đã duyệt', 'Approved') : T('Bị từ chối', 'Declined')}
              {r.decision_reason ? ` · “${r.decision_reason}”` : ''}
            </div>
          </div>
        )} />
      </>)}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, flexWrap: 'wrap', margin: '16px 0 4px' }}>
        <ChipRow>
          <Chip title={T('Tất cả', 'All')} selected={filter === 'all'} onClick={() => setFilter('all')} testId="project-tasks-all" />
          <Chip title={T('Của tôi', 'Mine')} selected={filter === 'mine'} onClick={() => setFilter('mine')} testId="project-tasks-mine" />
        </ChipRow>
        {(p.can('lane.manage') || p.can('change.propose')) && (
          <button type="button" data-testid="project-lane-add" onClick={() => ui.openSheet({ kind: 'newLane' })} style={linkButton}>
            ＋ {p.can('lane.manage') ? T('Thêm hạng mục', 'Add lane') : T('Đề xuất hạng mục', 'Propose a lane')}
          </button>
        )}
      </div>
      {lanes.map(l => {
        const list = shown.filter(t => t.lane_id === l.id);
        if (!list.length && filter === 'mine') return null;
        return (
          <div key={l.id}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '18px 0 8px', fontSize: 12, fontWeight: 700, letterSpacing: 0.6, color: ink3 }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>{l.name.toUpperCase()}
                {p.can('lane.manage') && <button type="button" aria-label={T(`Quản lý ${l.name}`, `Manage ${l.name}`)} onClick={() => ui.openSheet({ kind: 'manageLane', id: l.id })}
                  style={{ width: 36, height: 36, borderRadius: '50%', border: 0, background: blockInset, color: ink, cursor: 'pointer' }}>✎</button>}
              </span>
              <span>{list.filter(t => t.status === 'done').length}/{list.length}</span>
            </div>
            {list.length ? <Rows items={list} render={t => <TaskRow task={t} p={p} showLane={false} onOpen={() => ui.openSheet({ kind: 'task', id: t.id })} />} />
              : <Card><Note>{T('Hạng mục mới, chưa có việc.', 'New lane, no tasks yet.')}</Note></Card>}
          </div>
        );
      })}
    </div>
  );
}
