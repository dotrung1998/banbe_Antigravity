import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useEventProject } from '../state/useEventProject.js';
import { awaiting } from '../lib/projectPresentation.js';
import { paper, ink, ink2, ink3, block, divider, alert, honeyBg } from '../theme.js';
import { pillButton } from '../components/project/ProjectUI.jsx';
import { ProjectOverview, ProjectTasks } from '../components/project/ProjectOverviewTasks.jsx';
import ProjectTopics from '../components/project/ProjectTopics.jsx';
import ProjectTeam from '../components/project/ProjectTeam.jsx';
import ProjectMoney from '../components/project/ProjectMoney.jsx';
import ProjectDayOf from '../components/project/ProjectDayOf.jsx';
import ProjectSheetHost from '../components/project/ProjectSheets.jsx';

// Event Project Hub, web (note 76, phase 8; switch event_project_hub). Layout from the v6 prototype, same as the iOS hub:
// a bar (back, event name, more), the six-tab row with EXACTLY five visible at rest (swipe/scroll for the sixth; a fade
// and chevron say "more this way" until the end), and one body per tab.
export default function EventProject() {
  const p = useEventProject();
  const { s, snap, T, set } = p;
  const [sheet, setSheet] = useState(null);
  const [menu, setMenu] = useState(false);
  const [addMenu, setAddMenu] = useState(false);
  // Topics' lane filter, owned here so New post can preselect it and glow while it has no posts.
  const [topicsLane, setTopicsLane] = useState(null);
  // Sticky strips (Tasks lane navigator, Topics chips) sit under the demo banner when it shows.
  const banner = useRef(null);
  const [stickyTop, setStickyTop] = useState(0);
  useLayoutEffect(() => { setStickyTop(p.demoAdmin ? banner.current?.offsetHeight || 0 : 0); }, [p.demoAdmin]);
  const [visible, setVisible] = useState(typeof document === 'undefined' || document.visibilityState === 'visible');

  // A pasted /e/<id>/project link or a fresh tab: load the project the URL names.
  useEffect(() => {
    const stale = snap && snap.event?.id && snap.event.id !== s.projectEventId;
    if ((!snap || stale) && s.projectEventId && !s.projectLoading && !s.projectError && !p.demo) p.open(s.projectEventId, s.projectBack || 'home', s.projectTab);
  }, [s.projectEventId]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const on = () => setVisible(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', on);
    return () => document.removeEventListener('visibilitychange', on);
  }, []);

  // Host: the money numbers drive the Money tab's dot, so they load with the project.
  useEffect(() => { if (snap?.is_host) p.loadMoney(); }, [snap?.is_host, s.projectEventId]); // eslint-disable-line react-hooks/exhaustive-deps

  // Event-day live sync: run-of-show only, every 15 s, only on Day-of, on the event day, while the tab is visible.
  const live = p.liveSync(visible);
  useEffect(() => {
    if (!live) return undefined;
    p.pollRos();
    const id = setInterval(() => p.pollRos(), p.LIMITS.pollSeconds * 1000);
    return () => clearInterval(id);
  }, [live]); // eslint-disable-line react-hooks/exhaustive-deps

  const tabs = snap ? [
    { id: 'overview', label: T('Tổng quan', 'Overview'), icon: '⌂' },
    { id: 'tasks', label: T('Việc', 'Tasks'), icon: '✓', dot: snap.is_host && (snap.change_requests || []).some(c => c.status === 'pending') },
    { id: 'topics', label: T('Chủ đề', 'Topics'), icon: '☑', dot: awaiting(snap, p.userId).some(a => a.kind !== 'laneReview') },
    { id: 'team', label: T('Đội', 'Team'), icon: '👥' },
    { id: 'money', label: T('Tiền & cổng', 'Money & door'), icon: '₫', dot: !!(s.projectMoney && (s.projectMoney.awaiting > 0 || s.projectMoney.refunds > 0)) },
    { id: 'dayof', label: T('Ngày G', 'Day-of'), icon: '🗓' },
  ] : [];
  const tab = s.projectTab || 'overview';
  const lanes = snap?.lanes || [];
  const topicsFilter = lanes.some(l => l.id === topicsLane) ? topicsLane : null;
  const ui = { openSheet: setSheet, live, stickyTop, topicsLane: topicsFilter, setTopicsLane };

  const lead = snap?.me?.role === 'lane_lead' ? snap.me.lane_id : null;
  const canAddTask = snap && p.can('task.manage', { laneId: lead }) && lanes.length > 0;
  // Adding a lane, or proposing one (a Manager).
  const canLane = snap && (p.can('lane.manage') || p.can('change.propose'));
  const topicsEmpty = snap && !(snap.posts || []).some(x => !topicsFilter || x.lane_id === topicsFilter);

  return (
    <div data-screen-label="EventProject" data-testid="project-hub"
      // `backwards`, not `both`: a transform animation that stays in effect makes this div the containing block of the
      // position:fixed sheets, which then sized themselves to the whole (tall) hub instead of the screen.
      style={{ position: 'relative', minHeight: '100%', overflowX: 'clip', background: paper, color: ink, animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) backwards' }}>
      {p.demoAdmin && (
        // Admin project hub demo (migration 216): always on screen while the demo is open.
        <div ref={banner} data-testid="project-demo-banner" role="status"
          style={{ position: 'sticky', top: 0, zIndex: 25, display: 'flex', alignItems: 'center', gap: 10, padding: '50px 14px 8px', background: honeyBg, color: ink }}>
          <span style={{ flex: 1, fontSize: 14, fontWeight: 600 }} data-testid="project-demo-banner-title">{T('Bản demo · dữ liệu mẫu · không lưu gì', 'Demo · sample data · nothing is saved')}</span>
          <button type="button" onClick={p.exitProjectDemo} data-testid="project-demo-exit"
            style={pillButton(false, { width: 'auto', minHeight: 44, padding: '0 16px', flex: 'none' })}>{T('Thoát bản demo', 'Exit demo')}</button>
        </div>
      )}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: p.demoAdmin ? '8px 12px 4px' : '58px 12px 4px' }}>
        <button type="button" onClick={p.back} aria-label={T('Quay lại', 'Back')} data-testid="project-back" style={circle}>‹</button>
        <h1 style={{ flex: 1, margin: 0, fontSize: 17, textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{snap?.event?.name || T('Dự án', 'Project')}</h1>
        <div style={{ position: 'relative' }}>
          <button type="button" onClick={() => setMenu(m => !m)} aria-label={T('Thêm', 'More')} aria-expanded={menu} data-testid="project-more" style={circle}>⋯</button>
          {menu && (
            <div role="menu" style={{ position: 'absolute', right: 0, top: 50, zIndex: 20, background: block, borderRadius: 14, padding: 6, minWidth: 190, boxShadow: '0 10px 30px rgba(0,0,0,.3)' }}>
              <MenuItem onClick={() => { setMenu(false); p.refresh(true); }}>{T('Tải lại', 'Refresh')}</MenuItem>
              {snap && p.can('trash.restore') && <MenuItem testId="project-menu-trash" onClick={() => { setMenu(false); setSheet({ kind: 'trash' }); }}>{T('Thùng rác', 'Trash')}</MenuItem>}
              {snap?.me && !snap.project?.read_only && <MenuItem danger testId="project-menu-leave" onClick={() => { setMenu(false); setSheet({ kind: 'leave' }); }}>{T('Rời dự án', 'Leave project')}</MenuItem>}
            </div>
          )}
        </div>
      </div>

      {snap ? (
        <>
          <TabBar tabs={tabs} selection={tab} onSelect={(id) => set({ projectTab: id })} T={T} />
          <div style={{ height: 1, background: divider }} />
          <div style={{ padding: '14px 18px 120px' }}>
            {s.projectNotice && (
              <div role="alert" data-testid="project-notice" style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '0 0 0 14px', marginBottom: 12, borderRadius: 16, background: 'color-mix(in srgb, var(--bb-alert) 12%, transparent)' }}>
                <span style={{ color: alert }} aria-hidden>●</span>
                <span style={{ flex: 1, fontSize: 14 }}>{s.projectNotice}</span>
                <button type="button" onClick={() => set({ projectNotice: '' })} aria-label={T('Đóng', 'Dismiss')} style={{ width: 44, height: 44, border: 0, background: 'none', color: ink, cursor: 'pointer' }}>✕</button>
              </div>
            )}
            {snap.project?.read_only && (
              <div data-testid="project-read-only" style={{ padding: 14, borderRadius: 16, background: honeyBg, marginBottom: 12, fontSize: 14 }}>
                🔒 {T('Dự án đã chuyển sang chỉ xem (30 ngày sau sự kiện).', 'This project is read-only now (30 days after the event).')}
              </div>
            )}
            {tab === 'tasks' ? <ProjectTasks p={p} ui={ui} />
              : tab === 'topics' ? <ProjectTopics p={p} ui={ui} />
              : tab === 'team' ? <ProjectTeam p={p} ui={ui} />
              : tab === 'money' ? <ProjectMoney p={p} />
              : tab === 'dayof' ? <ProjectDayOf p={p} ui={ui} />
              : <ProjectOverview p={p} ui={ui} />}
          </div>
          {tab === 'tasks' && (canAddTask || canLane) && (
            <AddMenu p={p} open={addMenu} setOpen={setAddMenu} canAddTask={canAddTask} canLane={canLane} lead={lead} openSheet={setSheet} />
          )}
          {tab === 'topics' && p.can('post.question') && (
            <Fab testId="project-new-post" glow={topicsEmpty} onClick={() => setSheet({ kind: 'compose', laneId: topicsFilter })}>＋ {T('Bài mới', 'New post')}</Fab>
          )}
        </>
      ) : s.projectLoading || (!s.projectError && s.projectEventId) ? (
        <div style={{ padding: 60, textAlign: 'center', color: ink3 }}>{T('Đang tải…', 'Loading…')}</div>
      ) : (
        <div data-testid="project-failed" style={{ padding: 40, textAlign: 'center' }}>
          <p>{s.projectError || T('Chưa tải được dự án.', "Couldn't load the project.")}</p>
          <button type="button" onClick={() => p.refresh(true)} style={pillButton(false, { width: 'auto', padding: '0 20px' })}>{T('Thử lại', 'Try again')}</button>
        </div>
      )}
      {sheet && <ProjectSheetHost sheet={sheet} close={() => setSheet(null)} p={p} ui={ui} />}
    </div>
  );
}

const circle = { width: 44, height: 44, borderRadius: '50%', border: 0, background: block, color: ink, fontSize: 20, cursor: 'pointer', flex: 'none' };

function MenuItem({ children, onClick, danger, testId }) {
  return <button type="button" role="menuitem" onClick={onClick} data-testid={testId}
    style={{ display: 'block', width: '100%', textAlign: 'left', minHeight: 44, padding: '0 12px', border: 0, background: 'none', color: danger ? alert : ink, fontSize: 15, cursor: 'pointer', borderRadius: 10 }}>{children}</button>;
}

const fabSpot = { position: 'sticky', float: 'right', bottom: 22, marginRight: 18, marginTop: -90, zIndex: 7 };
const fabButton = { position: 'relative', minHeight: 56, padding: '0 20px', borderRadius: 999, border: 0, background: ink, color: paper, fontWeight: 700, fontSize: 15, cursor: 'pointer' };

/** `glow`: a gold ring breathes around it (still under reduced motion), e.g. New post on an empty Topics filter. */
function Fab({ children, onClick, testId, glow }) {
  return (
    <button type="button" onClick={onClick} data-testid={testId} data-glow={glow ? '1' : '0'}
      style={{ ...fabSpot, ...fabButton, boxShadow: glow ? '0 6px 18px rgba(var(--bb-attn-rgb), .45)' : '0 6px 16px rgba(0,0,0,.25)' }}>
      {glow && <span aria-hidden className="bb-attn-ring" />}
      {children}
    </button>
  );
}

/** "Add task / lane" (iOS addTaskButton): one button, then a small menu above it. Each choice says why when it's at
 *  its limit, and otherwise how much of the limit is used. */
function AddMenu({ p, open, setOpen, canAddTask, canLane, lead, openSheet }) {
  const { T, snap, LIMITS } = p;
  const n = (snap.lanes || []).length;
  const taskFull = p.taskLimitText(lead);
  const lanesFull = n >= LIMITS.lanesMax;
  const pick = (sheet) => { setOpen(false); openSheet(sheet); };
  return (
    <div style={fabSpot}>
      {open && <div aria-hidden onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 0 }} />}
      {open && (
        <div role="menu" data-testid="project-add-menu"
          style={{ position: 'absolute', right: 0, bottom: 66, zIndex: 1, width: 'min(300px, calc(100vw - 36px))', background: block, borderRadius: 16, padding: 6, boxShadow: '0 10px 30px rgba(0,0,0,.3)' }}>
          {canAddTask && (
            <AddItem icon="✓" title={T('Việc mới', 'New task')} sub={taskFull || p.taskUsage(lead).text} disabled={!!taskFull}
              testId="project-add-task-task" onClick={() => pick({ kind: 'newTask', laneId: lead })} />
          )}
          {canLane && (
            <AddItem icon="▦" title={p.can('lane.manage') ? T('Hạng mục mới', 'New lane') : T('Đề xuất hạng mục', 'Propose a lane')}
              sub={lanesFull ? T(`Đã đủ ${LIMITS.lanesMax} hạng mục`, `${LIMITS.lanesMax} lanes, the most allowed`) : T(`${n}/${LIMITS.lanesMax} hạng mục`, `${n}/${LIMITS.lanesMax} lanes`)}
              disabled={lanesFull} testId="project-add-task-lane" onClick={() => pick({ kind: 'newLane' })} />
          )}
        </div>
      )}
      <button type="button" onClick={() => setOpen(o => !o)} data-testid="project-add-task" aria-haspopup="menu" aria-expanded={open}
        style={{ ...fabButton, zIndex: 1, boxShadow: '0 6px 16px rgba(0,0,0,.25)' }}>＋ {T('Thêm việc / hạng mục', 'Add task / lane')}</button>
    </div>
  );
}

function AddItem({ icon, title, sub, disabled, testId, onClick }) {
  return (
    <button type="button" role="menuitem" disabled={disabled} aria-disabled={disabled} onClick={onClick} data-testid={testId}
      style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', minHeight: 56, padding: '6px 10px', border: 0, borderRadius: 12, background: 'none',
        color: ink, textAlign: 'left', cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.45 : 1 }}>
      <span aria-hidden style={{ width: 24, textAlign: 'center', fontWeight: 800 }}>{icon}</span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontWeight: 600, fontSize: 15 }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, color: ink2 }}>{sub}</span>
      </span>
    </button>
  );
}

/** 11 px unless the label would overflow its slot (about 0.56 em per character at weight 600), down to 8 px. */
const labelSize = (label, slot) => (slot ? Math.max(8, Math.min(11, (slot - 6) / (String(label).length * 0.56))) : 11);

/** Icon over label, exactly five slots visible at rest, the row scrolls for more; the selected tab stays in view. */
function TabBar({ tabs, selection, onSelect, T }) {
  const row = useRef(null);
  const [atEnd, setAtEnd] = useState(tabs.length <= 5);
  // Exactly five slots in the visible width (10 px side padding, 4 px gaps), measured so it holds at every width.
  const [slot, setSlot] = useState(null);
  useEffect(() => {
    const el = row.current;
    if (!el) return undefined;
    const measure = () => setSlot((el.clientWidth - 20 - 16) / 5);
    measure();
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(measure) : null;
    ro?.observe(el);
    return () => ro?.disconnect();
  }, []);
  const check = () => { const el = row.current; if (el) setAtEnd(el.scrollLeft + el.clientWidth >= el.scrollWidth - 4); };
  useEffect(() => {
    const el = row.current?.querySelector(`[data-tab="${selection}"]`);
    el?.scrollIntoView?.({ block: 'nearest', inline: 'center', behavior: 'smooth' });
    const t = setTimeout(check, 350);
    return () => clearTimeout(t);
  }, [selection]);
  return (
    <div style={{ position: 'relative', padding: '6px 0' }} data-testid="project-tabs">
      <div ref={row} onScroll={check} role="tablist" style={{ display: 'flex', gap: 4, overflowX: 'auto', scrollSnapType: 'x mandatory', padding: '0 10px', scrollbarWidth: 'none', scrollPaddingLeft: 10 }}>
        {tabs.map((t, i) => {
          const on = t.id === selection;
          return (
            <button key={t.id} type="button" role="tab" aria-selected={on} data-tab={t.id} data-testid={`project-tab-${t.id}`} onClick={() => onSelect(t.id)}
              aria-label={T(`${t.label}, thẻ ${i + 1} trên ${tabs.length}`, `${t.label}, tab ${i + 1} of ${tabs.length}`) + (t.dot ? T(', cần chú ý', ', needs attention') : '')}
              style={{ flex: slot ? `0 0 ${slot}px` : '0 0 18%', scrollSnapAlign: 'start', scrollMarginLeft: 10, height: 54, boxSizing: 'border-box', borderRadius: 14, border: 0, cursor: 'pointer', position: 'relative',
                display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3, padding: '0 2px',
                background: on ? ink : block, color: on ? paper : ink }}>
              <span aria-hidden style={{ fontSize: 17, lineHeight: 1 }}>{t.icon}</span>
              {/* Always one line, so every tab is the same height ("Money & door" used to wrap and stand taller):
                  long labels shrink to fit the slot, an ellipsis is the last resort. */}
              <span style={{ fontSize: labelSize(t.label, slot), fontWeight: 600, lineHeight: 1.15, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>{t.label}</span>
              {t.dot && <span aria-hidden style={{ position: 'absolute', top: 6, right: 6, width: 9, height: 9, borderRadius: '50%', background: alert }} />}
            </button>
          );
        })}
      </div>
      <div aria-hidden data-testid={atEnd ? 'project-tabs-at-end' : 'project-tabs-more'}
        style={{ position: 'absolute', top: 0, bottom: 0, right: 0, width: 26, pointerEvents: 'none', display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
          background: `linear-gradient(to right, transparent, ${paper})`, color: ink3, opacity: atEnd ? 0 : 1, transition: 'opacity .2s' }}>›</div>
    </div>
  );
}
