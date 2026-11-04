// Event Project Hub on the web (note 76, phase 8): loading a project and every write. Web twin of
// apps/ios/BanbeApp/State/AppState+Project*.swift. Each write is ONE RPC from migrations 210/211 followed by a
// version-checked refresh; the server decides permissions, projectCan() only decides what the UI offers.
// State lives in BanBeContext (projectSnapshot, projectTab, ...; reset on sign-out with the other private keys).
//
// Demo mode (`projectDemo: true`): writes change the snapshot in memory and NOTHING reaches the server (no RPC, no table
// read, no storage). Two ways in:
// - dev server only: `window.__banbeDevSet({ projectDemo: true, projectSnapshot })` (tests/event-project.spec.js);
//   __banbeDevSet does not exist in production builds.
// - the admin "Project hub demo" (migration 216, switch project_hub_demo): openProjectDemo() below, which only opens
//   for an admin while the switch is on (projectDemoAllowed). BanBeContext ends it when the hub is left or the gate fails.
// Whatever the way in, `projectDemo === true` means offline: every server call goes through `db`, which in demo is a
// stub that refuses without touching the network, on top of the per-function demo branches.
import { useBanBe } from './BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { projectDemoAllowed, projectDemoState, PROJECT_DEMO_RESET, DEMO_PROJECT_FLAGS } from '../lib/projectDemo.js';
import { projectCan, dueLabel, daysToGo, moneySummary, projectInviteValue, doorGuests } from '../lib/projectPresentation.js';
import { flagOn } from '../lib/featureFlags.js';
import { normalizeProofFile } from '../lib/proofUpload.js';
import LIMITS from '../data/projectLimits.json' with { type: 'json' };

export const PENDING_PROJECT_INVITE_KEY = 'banbe.pendingProjectInvite';
const uuid = () => (globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`).toLowerCase();
const iso = (d) => new Date(d).toISOString();
const storage = () => { try { return globalThis.localStorage || null; } catch { return null; } };


/** Stands in for supabase while in demo: every call answers "refused" and nothing is sent. */
const DEMO_REFUSAL = { data: null, error: { message: 'DEMO_OFFLINE' } };
const refusedQuery = () => new Proxy(function refused() {}, {
  get: (_t, k) => (k === 'then' ? (ok) => Promise.resolve(DEMO_REFUSAL).then(ok) : refusedQuery()),
  apply: () => refusedQuery(),
});
export const demoDb = Object.freeze({
  rpc: async () => DEMO_REFUSAL,
  from: () => refusedQuery(),
  storage: { from: () => ({ upload: async () => DEMO_REFUSAL, createSignedUrl: async () => DEMO_REFUSAL, download: async () => DEMO_REFUSAL, remove: async () => DEMO_REFUSAL }) },
});

/** The project fixture is loaded only when an admin opens the demo (its own small chunk). */
const loadDemoFixture = () => import('../../tests/fixtures/project-snapshot.json').then(m => (m.default || m).snapshot);

export function useEventProject() {
  const ctx = useBanBe();
  const { state: raw, set, T } = ctx;
  const demo = raw.projectDemo === true;
  const demoAdmin = demo && raw.projectDemoAdmin === true;
  // Inside the admin demo every project switch counts as on; nowhere else changes.
  const s = demoAdmin ? { ...raw, featureFlags: { ...(raw.featureFlags || {}), ...DEMO_PROJECT_FLAGS } } : raw;
  const db = demo ? demoDb : supabase;
  const snap = s.projectSnapshot;
  const userId = s.user?.id ? String(s.user.id).toLowerCase() : null;
  const now = () => ((import.meta.env.DEV || demo) && s.projectNow ? new Date(s.projectNow) : new Date());
  const demoOnly = () => T('Không có trong bản demo.', 'Not available in the demo.');
  /** Links out of the hub (real screens, outside chat links) open real data, so the demo stops them with a notice. */
  const demoLinkBlocked = (e) => {
    if (!demo) return false;
    e?.preventDefault?.();
    set({ projectNotice: demoOnly() });
    return true;
  };
  const tz = snap?.event?.tz || 'Asia/Ho_Chi_Minh';

  const can = (action, target = {}) => projectCan(snap, action, target, { userId, flags: s.featureFlags || {}, now: now() });

  // ------------------------------------------------------------------ words
  const errorText = (code, kind) => {
    if (kind === 'post' && code === 'TITLE_INVALID') return T('Tiêu đề dài 3 đến 80 ký tự.', 'A title is 3 to 80 characters.');
    if (kind === 'ros' && code === 'TITLE_INVALID') return T('Tên mốc dài 2 đến 40 ký tự.', 'An item name is 2 to 40 characters.');
    const m = {
      FEATURE_OFF: T('Dự án sự kiện đang tạm tắt.', 'Event projects are switched off right now.'),
      NOT_AUTHORIZED: T('Bạn không có quyền làm việc này trong dự án.', "You can't do this in this project."),
      NOT_FOUND: T('Không tìm thấy mục này. Có thể nó vừa bị xoá.', "This item wasn't found. It may have just been removed."),
      READ_ONLY: T('Dự án đã chuyển sang chỉ xem (30 ngày sau sự kiện).', 'This project is read-only now (30 days after the event).'),
      ACCOUNT_GATE: T('Hãy hoàn tất xác minh tài khoản trước.', 'Finish verifying your account first.'),
      AUTH_REQUIRED: T('Hãy đăng nhập trước.', 'Log in first.'),
      ALREADY_STARTED: T('Sự kiện này đã có dự án.', 'This event already has a project.'),
      EVENT_CLOSED: T('Sự kiện đã huỷ hoặc bị gỡ.', 'This event was cancelled or removed.'),
      LANES_FULL: T('Đã đủ 10 hạng mục.', 'This project already has 10 lanes.'),
      LANE_NAME_TAKEN: T('Đã có hạng mục tên này.', 'A lane with this name already exists.'),
      LANE_HAS_OPEN_TASKS: T('Hạng mục còn việc chưa xong. Hãy xong hoặc chuyển chúng trước.', 'This lane still has open tasks. Finish or move them first.'),
      LANE_REQUIRED: T('Hãy chọn một hạng mục.', 'Pick a lane.'),
      REASON_REQUIRED: T('Hãy ghi lý do (ít nhất 3 ký tự).', 'Add a reason (at least 3 characters).'),
      TITLE_INVALID: T('Tên việc dài 3 đến 60 ký tự.', 'A title is 3 to 60 characters.'),
      CHANNELS_INVALID: T('Có liên kết không hợp lệ. Chỉ dùng liên kết https.', "A link isn't valid. Use https links only."),
      NOT_PENDING: T('Đề xuất này đã được xử lý.', 'This proposal was already handled.'),
      NOT_A_MEMBER: T('Bạn không còn trong dự án này.', "You're no longer in this project."),
      ADDRESSEE_INVALID: T('Hãy chọn một người trong dự án để hỏi.', 'Pick someone in the project to ask.'),
      OPTIONS_INVALID: T('Đề xuất cần 2 đến 4 lựa chọn.', 'A proposal needs 2 to 4 options.'),
      REPLIES_FULL: T('Bài đã đủ 10 phản hồi. Hãy chốt hoặc đóng bài.', 'This post has 10 replies. Settle or close it.'),
      NOT_OPEN: T('Bài này đã đóng.', 'This post is closed.'),
      ALREADY_ANSWERED: T('Đã có người phản hồi nên không sửa được nữa.', "Someone has responded, so it can't be edited now."),
      INVITE_NOT_FOUND: T('Không tìm thấy mã mời này. Hãy kiểm tra lại.', "This invite code wasn't found. Check it and try again."),
      INVITE_EXPIRED: T('Lời mời đã hết hạn. Hãy xin một mã mới.', 'This invite has expired. Ask for a new one.'),
      INVITE_USED: T('Lời mời đã được dùng hết.', 'This invite has already been used.'),
      INVITE_REVOKED: T('Lời mời đã bị huỷ.', 'This invite was cancelled.'),
      IS_HOST: T('Bạn là Chủ sự kiện này, không cần lời mời.', "You're the Host of this event, so you don't need an invite."),
      ALREADY_MEMBER: T('Bạn đã ở trong dự án này.', "You're already in this project."),
      RATE_LIMITED: T('Nhập sai quá nhiều lần. Hãy thử lại sau một giờ.', 'Too many wrong codes. Try again in an hour.'),
      TIME_INVALID: T('Kết thúc phải sau bắt đầu ít nhất 10 phút.', 'The end must be at least 10 minutes after the start.'),
      TIME_OUTSIDE_EVENT: T('Mốc phải nằm trong khoảng 12 giờ trước đến 24 giờ sau giờ bắt đầu sự kiện.', 'Items must sit between 12 hours before and 24 hours after the event starts.'),
      // Refunds (phase 9c, migration 215).
      APPROVAL_REQUIRED: T('Chủ sự kiện cần duyệt khoản hoàn tiền này. Hãy ghi nhận để chủ sự kiện duyệt.', 'The Host needs to approve this refund. Record it for Host approval.'),
      ALREADY_REQUESTED: T('Khoản hoàn tiền này đã được ghi nhận và đang chờ Chủ sự kiện.', 'This refund is already recorded and waiting for the Host.'),
      REFUND_DESTINATION_REQUIRED: T('Khách chưa thêm tài khoản nhận hoàn tiền.', "The guest hasn't added a refund account yet."),
      NO_REQUEST: T('Không còn bản ghi nào chờ duyệt cho khoản này.', 'There is no record waiting for approval on this refund.'),
      NO_OPEN_DISPUTE: T('Khoản này không còn tranh chấp đang mở.', 'This refund no longer has an open dispute.'),
      NOT_A_DELEGATE: T('Người này không có quyền tiền trong đội.', "This person doesn't have money access on the team."),
      INVALID_STATE: T('Khoản hoàn tiền này đã được xử lý.', 'This refund was already handled.'),
      INVALID_AMOUNT: T('Số tiền hoàn không hợp lệ. Hãy báo Chủ sự kiện.', "The refund amount isn't valid. Tell the Host."),
      INVALID_PROOF_PATH: T('Không đính kèm được biên lai. Hãy thử lại.', "The receipt couldn't be attached. Try again."),
      INVALID_VALUE: T('Giá trị không hợp lệ. Hãy thử lại.', "That value isn't valid. Try again."),
    };
    return m[code] || T('Chưa lưu được. Hãy thử lại.', "Couldn't save. Try again.");
  };
  const roleName = (r) => ({ host: T('Chủ sự kiện', 'Host'), manager: T('Quản lý', 'Manager'), finance: T('Tài chính & cổng', 'Finance & door'),
    lane_lead: T('Trưởng hạng mục', 'Lane lead'), helper: T('Hỗ trợ', 'Helper') }[r] || '');
  const roleNote = (r) => ({
    host: T('Toàn quyền, duyệt hạng mục và kênh, đổi tài khoản nhận tiền.', 'Full control. Approves lanes and channels, changes the payout account.'),
    manager: T('Điều phối việc và chủ đề, mời Trưởng hạng mục và Hỗ trợ, đề xuất hạng mục mới.', 'Coordinates tasks and topics, invites Lane leads and Helpers, proposes new lanes.'),
    finance: T('Xác nhận thanh toán, xử lý hoàn tiền, check-in khách, khi banbe bật các quyền này.', 'Confirms payments, handles refunds and checks guests in, once banbe turns these on.'),
    lane_lead: T('Phụ trách một hạng mục: tạo, giao và chốt việc trong hạng mục đó.', 'Owns one lane: creates, assigns and settles its work.'),
  }[r] || T('Làm việc được giao, hỏi và bỏ phiếu.', 'Does assigned work, asks and votes.'));
  const statusName = (st) => ({ done: T('Xong', 'Done'), doing: T('Đang làm', 'Doing'), blocked: T('Bị chặn', 'Blocked') }[st] || T('Cần làm', 'To do'));
  const typeName = (t) => ({ proposal: T('Đề xuất', 'Proposal'), question: T('Câu hỏi', 'Question'), update: T('Cập nhật', 'Update') }[t] || T('Quyết định', 'Decision'));
  const personName = (id) => {
    if (!id) return T('Chưa giao', 'Unassigned');
    const v = String(id).toLowerCase();
    if (v === userId) return T('Bạn', 'You');
    const p = [...(snap?.hosts || []), ...(snap?.members || [])].find(x => String(x.user_id).toLowerCase() === v);
    if (!p) return T('Người đã rời dự án', 'Former member');
    return p.display_name || p.handle || '—';
  };
  const laneName = (id) => (snap?.lanes || []).find(l => l.id === id)?.name || '';
  const dueText = (day) => {
    const l = dueLabel(day, now(), tz);
    if (!l) return null;
    if (l.kind === 'today') return T('Hôm nay', 'Today');
    if (l.kind === 'tomorrow') return T('Ngày mai', 'Tomorrow');
    if (l.kind === 'late') return T(`Trễ ${l.days} ngày`, l.days === 1 ? '1 day late' : `${l.days} days late`);
    const [y, m, d] = day.split('-').map(Number);
    return new Intl.DateTimeFormat(T('vi-VN', 'en-US'), { weekday: 'short', day: 'numeric', month: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d)));
  };
  const clock = (d) => new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz }).format(new Date(d));
  const headcount = (snap?.hosts?.length || 0) + (snap?.members?.length || 0);

  // ------------------------------------------------------------------ open / refresh
  const refresh = async (full = false, eventId = s.projectEventId) => {
    if (demo || !eventId) return;
    if (!s.projectSnapshot) set({ projectLoading: true });
    const { data, error } = await db.rpc('get_event_project', { p_event_id: eventId, p_since_version: full ? null : (s.projectSnapshot?.version ?? null) });
    set(prev => {
      if (prev.projectEventId !== eventId) return {};
      if (error || !data) return { projectLoading: false, projectError: prev.projectSnapshot ? '' : errorText(null) };
      if (!data.success) return { projectLoading: false, projectError: errorText(data.error) };
      if (data.unchanged) return { projectLoading: false };
      // Older post pages the user opened stay below the newest 20.
      const fresh = data.posts || [];
      let posts = fresh;
      if (fresh.length >= 20 && prev.projectSnapshot?.posts) {
        const oldest = Date.parse(fresh[fresh.length - 1].created_at);
        const ids = new Set(fresh.map(p => p.id));
        posts = [...fresh, ...prev.projectSnapshot.posts.filter(p => !ids.has(p.id) && Date.parse(p.created_at) < oldest)];
      }
      return { projectLoading: false, projectError: '', projectSnapshot: { ...data, posts }, projectRosVersion: null };
    });
  };

  const open = async (eventId, back = s.screen, tab = 'overview') => {
    const same = s.projectEventId === eventId;
    set({ screen: 'eventProject', projectEventId: eventId, projectBack: back === 'eventProject' ? s.projectBack : back, projectTab: tab,
          projectNotice: '', projectError: '', ...(same ? {} : { projectSnapshot: null, projectMoney: null, projectDayView: 'list', projectRosVersion: null }) });
    if (!demo) {
      const { data } = await db.rpc('get_event_project', { p_event_id: eventId, p_since_version: null });
      set(prev => prev.projectEventId !== eventId ? {} : (data?.success ? { projectSnapshot: data, projectError: '', projectLoading: false }
        : { projectError: errorText(data?.error), projectLoading: false }));
    }
  };

  const back = () => set({ screen: s.projectBack || 'home' });

  // ------------------------------------------------------------------ admin demo (migration 216)
  const demoAllowed = projectDemoAllowed(raw);
  /** Open the hub on the sample data as `as` (host | manager | finance | lane_lead | helper); `eventDay` puts the demo
   * clock on the event day. Only for an admin while project_hub_demo is on; never reads or writes the server. */
  const openProjectDemo = async ({ as = 'host', eventDay = false } = {}) => {
    if (!demoAllowed) return false;
    const fixture = await loadDemoFixture();
    set(prev => (projectDemoAllowed(prev) ? projectDemoState(fixture, { as, eventDay, userId: prev.user?.id }) : {}));
    return true;
  };
  /** Leave the demo: all demo state cleared, back to Account > Review & moderation. */
  const exitProjectDemo = () => set({ ...PROJECT_DEMO_RESET, screen: 'accountGroup', accountGroupKey: 'adminReview' });

  const loadMyProjects = async () => {
    if (demo) return; // the demo hub is not a real project and the real list is not read while it is open
    if (!userId || s.featureFlags?.event_project_hub !== true) { set({ myProjects: [], myProjectsLoaded: true }); return; }
    const { data } = await db.rpc('get_my_event_projects');
    set({ myProjects: data?.projects || [], myProjectsLoaded: true });
  };

  const defaultLanes = () => [T('Địa điểm', 'Venue'), T('Thực đơn & đồ uống', 'Menu & drinks'), T('Ngân sách', 'Budget'),
    T('Khách & vé', 'Guests & tickets'), T('Nhà cung cấp', 'Vendors'), T('Ngày diễn ra', 'Day-of')];

  // ------------------------------------------------------------------ writes
  const patchSnap = (fn) => set(prev => (prev.projectSnapshot ? { projectSnapshot: fn(prev.projectSnapshot) } : {}));

  /** One write RPC. On success the project refreshes; a refusal lands in projectNotice in plain words. */
  const write = async (fn, params, { refresh: again = true, kind } = {}) => {
    if (demo) { set({ projectNotice: demoOnly() }); return null; }
    set({ projectBusy: true, projectNotice: '' });
    const { data, error } = await db.rpc(fn, params);
    set({ projectBusy: false });
    if (error || !data?.success) { set({ projectNotice: errorText(data?.error, kind) }); return null; }
    if (again) await refresh(false);
    return data;
  };

  const startProject = async (eventId, backTo) => {
    const r = await write('start_event_project', { p_event_id: eventId, p_lane_names: defaultLanes() }, { refresh: false });
    if (r) { await loadMyProjects(); await open(eventId, backTo); }
    return !!r;
  };

  const setTaskStatus = async (taskId, status) => {
    if (demo) { patchSnap(p => ({ ...p, tasks: p.tasks.map(t => t.id === taskId ? { ...t, status } : t) })); return true; }
    return !!(await write('project_set_task_status', { p_task_id: taskId, p_status: status }));
  };
  const toggleTaskDone = (task) => {
    if (!can('task.status', { laneId: task.lane_id, assigneeId: task.assignee_id })) {
      set({ projectNotice: T('Chỉ người phụ trách, Trưởng hạng mục, Quản lý hoặc Chủ sự kiện đổi được việc này.', 'Only the assignee, the lane lead, a Manager or the Host can change this task.') });
      return Promise.resolve(false);
    }
    return setTaskStatus(task.id, task.status === 'done' ? 'todo' : 'done');
  };
  const saveTask = async ({ taskId = null, laneId, title, assigneeId = null, dueDate = null, status = null }) => {
    if (demo) {
      patchSnap(p => ({ ...p, tasks: taskId
        ? p.tasks.map(t => t.id === taskId ? { ...t, lane_id: laneId, title, assignee_id: assigneeId, due_date: dueDate, status: status || t.status } : t)
        : [...p.tasks, { id: uuid(), event_id: p.event?.id, lane_id: laneId, title, assignee_id: assigneeId, due_date: dueDate, status: status || 'todo' }] }));
      return true;
    }
    return !!(await write('project_upsert_task', { p_event_id: s.projectEventId, p_task_id: taskId, p_lane_id: laneId, p_title: title,
      p_assignee_id: assigneeId, p_due_date: dueDate, p_status: status }));
  };
  const deleteTask = async (taskId, reason) => {
    if (demo) { patchSnap(p => ({ ...p, tasks: p.tasks.filter(t => t.id !== taskId) })); return true; }
    return !!(await write('project_delete_task', { p_task_id: taskId, p_reason: reason }));
  };
  const saveChannels = async (channels) => {
    if (demo) { patchSnap(p => ({ ...p, project: { ...p.project, channels } })); return true; }
    return !!(await write('project_set_channels', { p_event_id: s.projectEventId, p_channels: channels }));
  };
  const addLane = async (name) => {
    if (demo) { patchSnap(p => ({ ...p, lanes: [...p.lanes, { id: uuid(), name, position: p.lanes.length }] })); return true; }
    return !!(await write('project_add_lane', { p_event_id: s.projectEventId, p_name: name }));
  };
  const renameLane = async (laneId, name) => {
    if (demo) { patchSnap(p => ({ ...p, lanes: p.lanes.map(l => (l.id === laneId ? { ...l, name } : l)) })); return true; }
    return !!(await write('project_rename_lane', { p_lane_id: laneId, p_name: name }));
  };
  const archiveLane = async (laneId, reason) => {
    if (demo) {
      if ((snap?.tasks || []).some(t => t.lane_id === laneId && t.status !== 'done')) { set({ projectNotice: errorText('LANE_HAS_OPEN_TASKS') }); return false; }
      patchSnap(p => ({ ...p, lanes: p.lanes.filter(l => l.id !== laneId) }));
      return true;
    }
    return !!(await write('project_archive_lane', { p_lane_id: laneId, p_reason: reason }));
  };
  const proposeChange = async ({ kind, laneId = null, name, url, channel, why }) => {
    const payload = {};
    if (name != null) payload.name = name;
    if (url != null) payload.url = url;
    if (channel != null) payload.channel = channel;
    if (demo) {
      patchSnap(p => ({ ...p, change_requests: [...(p.change_requests || []), { id: uuid(), event_id: p.event?.id, kind, lane_id: laneId, payload, why,
        status: 'pending', proposed_by: userId, proposed_at: iso(now()), decided_by: null, decided_at: null, decision_reason: null }] }));
      return true;
    }
    return !!(await write('project_propose_change', { p_event_id: s.projectEventId, p_kind: kind, p_lane_id: laneId, p_payload: payload, p_why: why }));
  };
  const reviewChange = async (requestId, approve, reason = null) => {
    if (demo) {
      const r = (snap?.change_requests || []).find(c => c.id === requestId);
      patchSnap(p => ({ ...p, change_requests: p.change_requests.filter(c => c.id !== requestId),
        lanes: approve && r?.kind === 'lane_add' ? [...p.lanes, { id: uuid(), name: r.payload.name, position: p.lanes.length }] : p.lanes }));
      return true;
    }
    return !!(await write('project_review_change', { p_request_id: requestId, p_approve: approve, p_reason: reason }));
  };
  const leave = async () => {
    if (demo) { set({ projectNotice: demoOnly() }); return; }
    if (await write('project_leave', { p_event_id: s.projectEventId }, { refresh: false })) {
      set({ projectSnapshot: null }); await loadMyProjects(); back();
    }
  };

  // ------------------------------------------------------------------ topics
  const loadPost = async (postId) => {
    if (demo) {
      const post = snap?.posts?.find(p => p.id === postId);
      return post ? { success: true, post, replies: (s.projectDemoReplies || {})[postId] || [], voters: [], seen_by: post.seen_by_me ? [userId] : [] } : null;
    }
    const { data } = await db.rpc('get_event_project_post', { p_post_id: postId });
    if (!data?.success) { set({ projectNotice: errorText(data?.error) }); return null; }
    return data;
  };
  const loadOlderPosts = async () => {
    const oldest = snap?.posts?.[snap.posts.length - 1]?.created_at;
    if (demo || !oldest) { set({ projectPostsExhausted: true }); return; }
    const { data } = await db.rpc('get_event_project_posts', { p_event_id: s.projectEventId, p_before: oldest, p_limit: 20 });
    const older = data?.posts || [];
    patchSnap(p => { const ids = new Set(p.posts.map(x => x.id)); return { ...p, posts: [...p.posts, ...older.filter(x => !ids.has(x.id))] }; });
    set({ projectPostsExhausted: older.length < 20 });
  };
  const editPostLocal = (postId, fn) => patchSnap(p => ({ ...p, posts: p.posts.map(x => x.id === postId ? fn(x) : x) }));
  const createPost = async ({ type, laneId, title, body, options = null, addresseeId = null, deadline = null }) => {
    if (demo) {
      const seen = type === 'update' || type === 'decision';
      patchSnap(p => ({ ...p, posts: [{ id: uuid(), event_id: p.event?.id, lane_id: laneId, type, title, body, author_id: userId,
        addressee_id: type === 'question' ? addresseeId : null, options: type === 'proposal' ? options : null, deadline: type === 'proposal' ? deadline : null,
        state: type === 'decision' ? 'locked' : 'open', created_at: iso(now()), edited_at: null,
        votes: type === 'proposal' ? options.map(() => 0) : null, my_vote: null, replies_count: 0, seen_count: seen ? 1 : 0, seen_by_me: seen, quiet: true }, ...p.posts] }));
      return true;
    }
    return !!(await write('project_create_post', { p_event_id: s.projectEventId, p_type: type, p_lane_id: laneId, p_title: title, p_body: body,
      p_options: options, p_addressee_id: addresseeId, p_deadline: deadline }, { kind: 'post' }));
  };
  const editPost = async (postId, title, body) => {
    if (demo) { editPostLocal(postId, x => ({ ...x, title, body, edited_at: iso(now()) })); return true; }
    return !!(await write('project_edit_post', { p_post_id: postId, p_title: title, p_body: body }, { kind: 'post' }));
  };
  const vote = async (postId, option) => {
    if (demo) {
      editPostLocal(postId, x => {
        const votes = [...(x.votes || [])];
        if (x.my_vote != null) votes[x.my_vote] -= 1;
        const mine = x.my_vote === option ? null : option;
        if (mine != null) votes[mine] += 1;
        return { ...x, votes, my_vote: mine, quiet: false };
      });
      return true;
    }
    return !!(await write('project_vote', { p_post_id: postId, p_option: option }, { kind: 'post' }));
  };
  const markSeen = async (postId) => {
    if (demo) { editPostLocal(postId, x => (x.seen_by_me ? x : { ...x, seen_by_me: true, seen_count: x.seen_count + 1, quiet: false })); return true; }
    return !!(await write('project_mark_seen', { p_post_id: postId }, { kind: 'post' }));
  };
  const reply = async (postId, body) => {
    if (demo) {
      set(prev => ({ projectDemoReplies: { ...(prev.projectDemoReplies || {}), [postId]: [...((prev.projectDemoReplies || {})[postId] || []), { id: uuid(), author_id: userId, body, created_at: iso(now()) }] } }));
      editPostLocal(postId, x => ({ ...x, replies_count: x.replies_count + 1, quiet: false }));
      return true;
    }
    return !!(await write('project_reply', { p_post_id: postId, p_body: body }, { kind: 'post' }));
  };
  const resolvePost = async (postId) => {
    if (demo) { editPostLocal(postId, x => ({ ...x, state: 'resolved' })); return true; }
    return !!(await write('project_resolve_post', { p_post_id: postId }, { kind: 'post' }));
  };
  const decide = async (postId) => {
    if (demo) {
      const p = snap?.posts?.find(x => x.id === postId);
      if (!p) return false;
      const votes = p.votes || [];
      let best = 0;
      votes.forEach((v, i) => { if (v > votes[best]) best = i; });
      editPostLocal(postId, x => ({ ...x, state: 'resolved' }));
      return createPost({ type: 'decision', laneId: p.lane_id, title: p.options[best], body: p.title });
    }
    return !!(await write('project_decide_proposal', { p_post_id: postId }, { kind: 'post' }));
  };
  const deletePost = async (postId, reason) => {
    if (demo) { patchSnap(p => ({ ...p, posts: p.posts.filter(x => x.id !== postId) })); return true; }
    return !!(await write('project_delete_post', { p_post_id: postId, p_reason: reason }, { kind: 'post' }));
  };

  // ------------------------------------------------------------------ team
  const createInvite = async (role, laneId = null, maxUses = 1) => {
    if (demo) {
      const n = (s.projectDemoInvites || 0) + 1;
      const inv = { invite_id: uuid(), token: `Fx7kQ2mN9pR4sT6vW8yZ1${n === 1 ? 'a' : 'b'}`, short_code: n === 1 ? 'BB-7K2Q' : `BB-M4${'ACDEFGHJ'[n % 8]}P`,
        role, lane_id: role === 'lane_lead' ? laneId : null, expires_at: iso(now().getTime() + LIMITS.inviteHours * 3600e3), max_uses: maxUses, uses: 0, created_by: userId };
      set(prev => ({ projectDemoInvites: n, projectInvites: [inv, ...(prev.projectInvites || [])] }));
      return inv;
    }
    set({ projectBusy: true, projectNotice: '' });
    const { data } = await db.rpc('project_create_invite', { p_event_id: s.projectEventId, p_role: role, p_lane_id: role === 'lane_lead' ? laneId : null, p_max_uses: maxUses });
    set({ projectBusy: false });
    if (!data?.success) { set({ projectNotice: errorText(data?.error) }); return null; }
    const inv = { ...data, uses: 0, created_by: userId };
    set(prev => ({ projectInvites: [inv, ...(prev.projectInvites || [])] }));
    return inv;
  };
  const loadInvites = async () => {
    if (demo || !can('invite.create', { role: 'helper' })) return;
    const { data } = await db.rpc('project_list_invites', { p_event_id: s.projectEventId });
    if (data?.success) set({ projectInvites: data.invites || [] });
  };
  const revokeInvite = async (inviteId) => {
    if (!demo && !(await write('project_revoke_invite', { p_invite_id: inviteId }, { refresh: false }))) return false;
    set(prev => ({ projectInvites: (prev.projectInvites || []).filter(i => i.invite_id !== inviteId) }));
    return true;
  };
  const setMember = async (memberId, { role, laneId = null, capMoney, capCheckin }) => {
    if (demo) {
      const fin = role === 'finance';
      patchSnap(p => ({ ...p, members: p.members.map(m => m.member_id === memberId
        ? { ...m, role, lane_id: role === 'lane_lead' ? laneId : null, cap_money: fin || capMoney, cap_checkin: fin || capCheckin } : m) }));
      return true;
    }
    return !!(await write('project_set_member', { p_member_id: memberId, p_role: role, p_lane_id: role === 'lane_lead' ? laneId : null,
      p_cap_money: capMoney, p_cap_checkin: capCheckin }));
  };
  const removeMember = async (memberId, reason) => {
    if (demo) {
      const uid = snap?.members?.find(m => m.member_id === memberId)?.user_id;
      patchSnap(p => ({ ...p, members: p.members.filter(m => m.member_id !== memberId),
        tasks: p.tasks.map(t => (t.assignee_id === uid && t.status !== 'done' ? { ...t, assignee_id: null } : t)) }));
      return true;
    }
    return !!(await write('project_remove_member', { p_member_id: memberId, p_reason: reason }));
  };
  const inviteShareText = (inv) => {
    const link = `https://www.banbe.app/join/${inv.token}`;
    const name = snap?.event?.name || '';
    return T(`Mời bạn vào đội của ${name} trên banbe (${roleName(inv.role)}). Mở liên kết: ${link} hoặc nhập mã ${inv.short_code}. Hết hạn sau 48 giờ.`,
      `Join the ${name} team on banbe as ${roleName(inv.role)}. Open ${link} or enter the code ${inv.short_code}. Expires in 48 hours.`);
  };
  const inviteExpiry = (at) => {
    const t = Date.parse(at);
    if (!Number.isFinite(t)) return null;
    const h = Math.ceil((t - now().getTime()) / 3600e3);
    return h <= 0 ? T('đã hết hạn', 'expired') : T(`còn ${h} giờ`, h === 1 ? '1 hour left' : `${h} hours left`);
  };

  // ------------------------------------------------------------------ join
  const openJoin = (input = '', backTo) => {
    const value = projectInviteValue(input) || String(input || '').trim();
    const b = backTo || (s.screen === 'projectJoin' ? s.projectJoinBack : (['login', 'welcome'].includes(s.screen) ? 'home' : s.screen));
    set({ screen: 'projectJoin', projectJoinCode: value, projectJoinPeek: null, projectJoinError: '', projectJoinBack: b });
    if (!userId) { if (value) storage()?.setItem(PENDING_PROJECT_INVITE_KEY, value); return; }
    if (value) peek(value);
  };
  const peek = async (raw = s.projectJoinCode) => {
    const code = projectInviteValue(raw);
    if (!code) { set({ projectJoinPeek: null, projectJoinError: T('Mã có dạng BB-XXXX (4 ký tự).', 'A code looks like BB-XXXX (4 characters).') }); return; }
    set({ projectJoinCode: code });
    if (demo) {
      const ok = code === 'BB-7K2Q' || code.startsWith('Fx7k'), expired = code === 'BB-XPRD';
      set(ok || expired ? { projectJoinError: '', projectJoinPeek: { success: true, state: ok ? 'ok' : 'expired', event_id: 'fx_project', event_name: 'Bếp Nhỏ №13',
        event_date: '2026-11-14', tz: 'Asia/Ho_Chi_Minh', organizer_name: 'Bếp Nhỏ', role: 'helper', lane_name: null, expires_at: iso(now().getTime() + 41 * 3600e3) } }
        : { projectJoinPeek: null, projectJoinError: errorText('INVITE_NOT_FOUND') });
      return;
    }
    set({ projectJoinLoading: true });
    const { data, error } = await db.rpc('peek_project_invite', { p_code: code });
    set({ projectJoinLoading: false });
    if (error) { set({ projectJoinError: T('Chưa kiểm tra được mã. Hãy thử lại.', "Couldn't check the code. Try again.") }); return; }
    set(data?.success ? { projectJoinPeek: data, projectJoinError: '' } : { projectJoinPeek: null, projectJoinError: errorText(data?.error) });
  };
  const join = async () => {
    const code = projectInviteValue(s.projectJoinCode);
    if (!code) return;
    if (demo) { storage()?.removeItem(PENDING_PROJECT_INVITE_KEY); set({ screen: 'eventProject', projectTab: 'overview', projectBack: 'home' }); return; }
    set({ projectJoinLoading: true });
    const { data } = await db.rpc('project_redeem_invite', { p_code: code });
    set({ projectJoinLoading: false });
    if (!data?.success) { set({ projectJoinError: errorText(data?.error) }); return; }
    storage()?.removeItem(PENDING_PROJECT_INVITE_KEY);
    await loadMyProjects();
    await open(data.event_id, s.projectJoinBack === 'projectJoin' ? 'home' : s.projectJoinBack);
  };

  // ------------------------------------------------------------------ day-of
  const liveSync = (visible) => !!visible && s.screen === 'eventProject' && s.projectTab === 'dayof' && daysToGo(snap?.event, now()) === 0;
  const pollRos = async () => {
    if (demo || !s.projectEventId) return;
    const { data } = await db.rpc('get_event_project_ros', { p_event_id: s.projectEventId, p_since_version: s.projectRosVersion ?? snap?.version ?? null });
    if (!data?.success) return;
    set(prev => (prev.projectEventId !== s.projectEventId ? {} : {
      projectRosVersion: data.version,
      ...(data.unchanged || !data.ros || !prev.projectSnapshot ? {} : { projectSnapshot: { ...prev.projectSnapshot, ros: data.ros } }),
    }));
  };
  const saveRos = async ({ itemId = null, title, ownerId = null, startsAt, endsAt }) => {
    if (demo) {
      const row = { title, owner_id: ownerId, starts_at: iso(startsAt), ends_at: iso(endsAt) };
      patchSnap(p => ({ ...p, ros: (itemId ? p.ros.map(r => (r.id === itemId ? { ...r, ...row } : r)) : [...p.ros, { id: uuid(), done_at: null, ...row }])
        .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at)) }));
      return true;
    }
    return !!(await write('project_upsert_ros_item', { p_event_id: s.projectEventId, p_item_id: itemId, p_title: title, p_owner_id: ownerId,
      p_starts_at: iso(startsAt), p_ends_at: iso(endsAt) }, { kind: 'ros' }));
  };
  const tickRos = async (itemId, done) => {
    if (demo) { patchSnap(p => ({ ...p, ros: p.ros.map(r => (r.id === itemId ? { ...r, done_at: done ? iso(now()) : null } : r)) })); return true; }
    return !!(await write('project_tick_ros_item', { p_item_id: itemId, p_done: done }));
  };
  const deleteRos = async (itemId, reason) => {
    if (demo) {
      const item = snap?.ros?.find(r => r.id === itemId);
      set(prev => ({ projectDemoTrash: [{ kind: 'ros', id: itemId, title: item?.title, by: userId, reason, at: iso(now()), starts_at: item?.starts_at }, ...(prev.projectDemoTrash || [])] }));
      patchSnap(p => ({ ...p, ros: p.ros.filter(r => r.id !== itemId) }));
      return true;
    }
    return !!(await write('project_delete_ros_item', { p_item_id: itemId, p_reason: reason }));
  };
  const loadTrash = async () => {
    if (demo) return s.projectDemoTrash || [];
    const { data } = await db.rpc('get_event_project_trash', { p_event_id: s.projectEventId });
    if (!data?.success) { set({ projectNotice: errorText(data?.error) }); return []; }
    return data.items || [];
  };
  const restore = async (item) => {
    if (demo) {
      set(prev => ({ projectDemoTrash: (prev.projectDemoTrash || []).filter(t => !(t.kind === item.kind && t.id === item.id)) }));
      if (item.kind === 'ros' && item.starts_at) {
        patchSnap(p => ({ ...p, ros: [...p.ros, { id: item.id, title: item.title, owner_id: null, starts_at: item.starts_at, ends_at: iso(Date.parse(item.starts_at) + 1800e3), done_at: null }]
          .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at)) }));
      }
      return true;
    }
    return !!(await write('project_restore', { p_kind: item.kind, p_id: item.id }));
  };
  const purge = async (item) => {
    if (demo) { set(prev => ({ projectDemoTrash: (prev.projectDemoTrash || []).filter(t => !(t.kind === item.kind && t.id === item.id)) })); return true; }
    return !!(await write('project_purge', { p_kind: item.kind, p_id: item.id }, { refresh: false }));
  };

  // ------------------------------------------------------------------ money (Host)
  // The Host's own view: the organizer accounts. A delegate with money access passes money.view too once 214 is on.
  const moneyAccess = snap?.is_host === true && can('money.view');
  const loadMoney = async () => {
    if (!moneyAccess) { set({ projectMoney: null }); return; }
    if (demo) { set({ projectMoney: { confirmedSeats: 9, confirmedAmount: 4410000, awaiting: 2, refunds: 1, refundsOverdue: 0, checkedIn: 0, seats: 11 } }); return; }
    const eventId = s.projectEventId;
    const { data: rows } = await db.from('bookings').select('qty, status, total_vnd, expires_at, paid_marked_at')
      .eq('event_id', eventId).in('status', ['pending', 'confirmed', 'attended']);
    let refunds = [];
    if (/^[0-9a-f-]{36}$/i.test(eventId)) {
      const { data } = await db.rpc('get_host_refund_claims', { p_event_id: eventId });
      const t = Date.now();
      refunds = (data?.claims || []).map(c => ({
        active: c.status === 'owed' || c.status === 'disputed',
        overdue: (c.status === 'owed' && c.refund_due_at && Date.parse(c.refund_due_at) < t) || (c.status === 'disputed' && c.host_response_due_at && Date.parse(c.host_response_due_at) < t),
      }));
    }
    set(prev => (prev.projectEventId !== eventId ? {} : { projectMoney: moneySummary(rows || [], refunds, new Date()) }));
  };

  // ------------------------------------------------------------------ door (phase 9a, migration 212)
  const doorAccess = snap?.is_host !== true && can('checkin');
  const loadDoor = async () => {
    if (!doorAccess) { set({ projectDoor: null }); return; }
    if (demo) {
      if (!s.projectDoor) set({ projectDoor: doorGuests([
        { booking_id: 'door-1', attendee_id: 'a1', name: 'Ngọc Anh', party: 1, checked_in: false },
        { booking_id: 'door-1', attendee_id: 'a2', name: 'Quốc Bảo', party: 1, checked_in: false },
        { booking_id: 'door-2', attendee_id: null, name: 'Thu Hà', party: 2, checked_in: true },
        { booking_id: 'door-3', attendee_id: null, name: 'Minh Khang', party: 1, checked_in: false }]) });
      return;
    }
    const { data } = await db.rpc('get_event_checkin_names', { p_event_id: s.projectEventId });
    if (data?.success) set({ projectDoor: doorGuests(data.guests || []) }); else set({ projectNotice: errorText(data?.error) });
  };
  /** Check a whole party in from the list (check_in_guest 'manual'; the server writes the audit row). */
  const checkInGuest = async (bookingId) => {
    if (demo) { set(prev => ({ projectDoor: (prev.projectDoor || []).map(g => (g.bookingId === bookingId ? { ...g, inside: g.party } : g)) })); return true; }
    set({ projectBusy: true });
    const { data } = await db.rpc('check_in_guest', { p_reservation_id: bookingId, p_source: 'manual' });
    set({ projectBusy: false });
    if (!data?.success) {
      set({ projectNotice: data?.error === 'Guest already checked in' ? T('Khách này đã vào rồi.', 'This guest is already in.')
        : data?.error === 'Not authorized' ? T('Quyền check-in của bạn đã hết hoặc đang tắt.', 'Your check-in access has ended or is switched off.') : errorText(null) });
    }
    await loadDoor();
    return !!data?.success;
  };

  // ------------------------------------------------------------------ payments (phase 9b, migration 214)
  const paymentsAccess = snap?.is_host !== true && can('money.confirm');
  const loadPayments = async () => {
    if (!paymentsAccess) { set({ projectPayments: null }); return; }
    if (demo) {
      if (!s.projectPayments) set({ projectPayments: { confirmed_amount: 4410000, confirmed_seats: 9, awaiting: [
        { booking_id: 'pay-1', name: 'Ngọc Anh', qty: 2, amount: 980000, payment_ref: 'BB1A2B', has_proof: true },
        { booking_id: 'pay-2', name: 'Minh Khang', qty: 1, amount: 490000, payment_ref: 'BB3C4D', has_proof: false }] } });
      return;
    }
    const { data } = await db.rpc('get_event_money_view', { p_event_id: s.projectEventId });
    if (data?.success) set({ projectPayments: data }); else set({ projectNotice: errorText(data?.error) });
  };
  /** "Money received" (verify_payment; the server checks access and writes the audit row). */
  const confirmPayment = async (bookingId) => {
    if (demo) {
      set(prev => {
        const v = prev.projectPayments; const row = v?.awaiting?.find(a => a.booking_id === bookingId);
        return row ? { projectPayments: { ...v, awaiting: v.awaiting.filter(a => a.booking_id !== bookingId), confirmed_amount: v.confirmed_amount + row.amount, confirmed_seats: v.confirmed_seats + row.qty } } : {};
      });
      return true;
    }
    set({ projectBusy: true });
    const { data } = await db.rpc('verify_payment', { p_booking: bookingId, p_via: 'project_team', p_actor_kind: 'organizer', p_meta: {} });
    set({ projectBusy: false });
    if (!data?.success) set({ projectNotice: data?.error === 'NOT_AUTHORIZED' ? T('Quyền tiền của bạn đã hết hoặc đang tắt.', 'Your money access has ended or is switched off.') : errorText(null) });
    await loadPayments();
    return !!data?.success;
  };
  /** One booking's transfer proof: the server logs the open first, then a short-lived signed link. */
  const openProof = async (bookingId) => {
    if (demo) return null;
    const { data } = await db.rpc('open_payment_proof', { p_booking_id: bookingId });
    if (!data?.success) {
      set({ projectNotice: data?.error === 'NO_PROOF' ? T('Khách chưa gửi ảnh chuyển khoản.', "The guest hasn't sent a transfer proof.")
        : data?.error === 'NOT_AWAITING' ? T('Khoản này không còn chờ xác nhận.', 'This payment is no longer waiting for a check.') : T('Bạn không mở được ảnh này.', "You can't open this proof.") });
      return null;
    }
    const { data: signed } = await db.storage.from(data.bucket || 'pay-proof').createSignedUrl(data.path, LIMITS.proofUrlSeconds);
    return signed?.signedUrl || null;
  };

  // ------------------------------------------------------------------ refunds (phase 9c, migration 215)
  // A money delegate sends refunds the Host owes: by default the Host approves each record (request_refund_send ->
  // approve/decline_refund_send); under 'finance_alone' the delegate marks it sent (mark_refund_sent). The Host's own
  // refund screen stays the full one; here the Host sees the team's records, the approval switch and dispute grants.
  const refundsFlag = flagOn(s.featureFlags || {}, 'project_delegate_refunds');
  const refundsAccess = snap?.is_host !== true && (can('refund.request') || can('refund.markSent'));
  const refundMode = snap?.project?.refund_approval === 'finance_alone' ? 'finance_alone' : 'host';
  const demoRefunds = () => {
    const due = (days) => iso(now().getTime() + days * 86400e3);
    const acct = { bank_name: 'Vietcombank', account_number: '0071000123456', account_holder_name: 'NGUYEN NGOC ANH' };
    const claims = [
      { claim_id: 'ref-1', booking_id: 'pay-1', name: 'Ngọc Anh', amount: 980000, status: 'owed', refund_due_at: due(2), dispute_open: false, account: acct,
        request: snap?.is_host === true ? { id: 'req-1', by: 'Hà', mine: false, note: 'Đã chuyển lúc 14:05', has_proof: true, at: iso(now()) } : null, last_declined: null },
      { claim_id: 'ref-2', booking_id: 'pay-2', name: 'Minh Khang', amount: 490000, status: 'disputed', refund_due_at: due(-1), dispute_open: true, account: null, request: null, last_declined: null },
    ];
    return { success: true, mode: refundMode, host: snap?.is_host === true, claims };
  };
  const loadRefunds = async () => {
    const host = snap?.is_host === true && moneyAccess;
    if (!refundsAccess && !host) { set({ projectRefunds: null }); return; }
    if (demo) { if (!s.projectRefunds) set({ projectRefunds: demoRefunds() }); return; }
    const eventId = s.projectEventId;
    const { data } = await db.rpc('get_event_refund_view', { p_event_id: eventId });
    if (data?.success) set(prev => (prev.projectEventId !== eventId ? {} : { projectRefunds: data }));
    else if (!host) set({ projectNotice: errorText(data?.error) });
  };
  const patchRefunds = (fn) => set(prev => (prev.projectRefunds ? { projectRefunds: { ...prev.projectRefunds, claims: fn(prev.projectRefunds.claims || []) } } : {}));
  const refundRpc = async (fn, params) => {
    if (demo) { set({ projectNotice: demoOnly() }); return null; }
    set({ projectBusy: true, projectNotice: '' });
    const { data, error } = await db.rpc(fn, params);
    set({ projectBusy: false });
    if (error || !data?.success) {
      set({ projectNotice: data?.error === 'NOT_AUTHORIZED' && snap?.is_host !== true ? T('Quyền hoàn tiền của bạn đã hết hoặc đang tắt.', 'Your refund access has ended or is switched off.') : errorText(data?.error) });
      await loadRefunds();
      return null;
    }
    await loadRefunds();
    return data;
  };
  /** Delegate: record the transfer for the Host (mode host) or mark it sent (finance_alone). The optional receipt goes to the
   * claim's own refund-proof folder first (refund_proof_delegate_insert: insert only, so never upsert). */
  const sendRefund = async (claimId, note = '', file = null) => {
    const markSent = (s.projectRefunds?.mode || refundMode) === 'finance_alone';
    const clean = String(note || '').trim().slice(0, 280);
    if (demo) {
      patchRefunds(cs => (markSent ? cs.filter(c => c.claim_id !== claimId)
        : cs.map(c => (c.claim_id === claimId ? { ...c, last_declined: null, request: { id: uuid(), by: personName(userId), mine: true, note: clean || null, has_proof: !!file, at: iso(now()) } } : c))));
      return true;
    }
    let proofPath = null;
    if (file) {
      set({ projectBusy: true });
      try {
        const { blob, ext, contentType } = await normalizeProofFile(file);
        proofPath = `${claimId}/team-${Date.now()}.${ext}`;
        const { error } = await db.storage.from('refund-proof').upload(proofPath, blob, { upsert: false, contentType });
        if (error) throw error;
      } catch {
        set({ projectBusy: false, projectNotice: T('Không tải được biên lai lên. Hãy thử lại hoặc gửi không kèm biên lai.', "The receipt didn't upload. Try again or send without it.") });
        return false;
      }
    }
    return !!(await refundRpc(markSent ? 'mark_refund_sent' : 'request_refund_send', { p_claim_id: claimId, p_note: clean, p_proof_path: proofPath }));
  };
  /** Host: approve a team record (approve_refund_send runs mark_refund_sent as the Host; the guest is told). */
  const approveRefund = async (claimId) => {
    if (demo) { patchRefunds(cs => cs.filter(c => c.claim_id !== claimId)); return true; }
    return !!(await refundRpc('approve_refund_send', { p_claim_id: claimId }));
  };
  /** Host: decline a team record with a reason the delegate sees. */
  const declineRefund = async (claimId, reason) => {
    if (demo) { patchRefunds(cs => cs.map(c => (c.claim_id === claimId ? { ...c, request: null } : c))); return true; }
    return !!(await refundRpc('decline_refund_send', { p_claim_id: claimId, p_reason: String(reason || '').trim() }));
  };
  /** Host: who may send refunds without the Host ('host' | 'finance_alone'). */
  const setRefundApproval = async (mode) => {
    if (demo) {
      patchSnap(p => ({ ...p, project: { ...p.project, refund_approval: mode } }));
      set(prev => (prev.projectRefunds ? { projectRefunds: { ...prev.projectRefunds, mode } } : {}));
      return true;
    }
    const r = await write('project_set_refund_approval', { p_event_id: s.projectEventId, p_mode: mode });
    if (r) await loadRefunds();
    return !!r;
  };
  /** Host: let one money member handle one disputed refund for `days` (<= disputeGrantMaxDays). */
  const extendDisputeGrant = async (claimId, memberUserId, days) => {
    const d = Math.max(1, Math.min(Number(days) || 7, LIMITS.disputeGrantMaxDays));
    const until = new Date(now().getTime() + d * 86400e3 - 60e3); // a minute under the cap, so the server's "<= now + max" holds
    if (demo) return true;
    const r = await write('project_extend_dispute_grant', { p_event_id: s.projectEventId, p_user_id: memberUserId, p_refund_claim_id: claimId, p_until: until.toISOString() }, { refresh: false });
    return !!r;
  };
  /** "Due Thu 12" in the event's zone. */
  const refundDueText = (at) => {
    if (!at) return null;
    const d = new Date(at);
    const wd = new Intl.DateTimeFormat(T('vi-VN', 'en-US'), { weekday: 'short', timeZone: tz }).format(d);
    const day = new Intl.DateTimeFormat('en-US', { day: 'numeric', timeZone: tz }).format(d);
    return T(`Hạn ${wd}, ngày ${day}`, `Due ${wd} ${day}`);
  };

  return {
    s, snap, set, T, userId, demo, now, tz, can, LIMITS, doorAccess, loadDoor, checkInGuest, paymentsAccess, loadPayments, confirmPayment, openProof,
    errorText, roleName, roleNote, statusName, typeName, personName, laneName, dueText, clock, headcount,
    open, back, refresh, loadMyProjects, startProject, write, demoAdmin, demoAllowed, demoOnly, demoLinkBlocked, openProjectDemo, exitProjectDemo,
    setTaskStatus, toggleTaskDone, saveTask, deleteTask, saveChannels, addLane, renameLane, archiveLane, proposeChange, reviewChange, leave,
    loadPost, loadOlderPosts, createPost, editPost, vote, markSeen, reply, resolvePost, decide, deletePost,
    createInvite, loadInvites, revokeInvite, setMember, removeMember, inviteShareText, inviteExpiry,
    openJoin, peek, join,
    liveSync, pollRos, saveRos, tickRos, deleteRos, loadTrash, restore, purge,
    moneyAccess, loadMoney,
    refundsFlag, refundsAccess, refundMode, loadRefunds, sendRefund, approveRefund, declineRefund, setRefundApproval, extendDisputeGrant, refundDueText,
  };
}
