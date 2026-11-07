// Topics tab of the web Event Project Hub (note 76): structured posts only (Proposal, Question, Update, Decision), no
// free chat. Same rules as iOS ProjectTopicsTab / ProjectPostSheets: votes and "Seen" are counters, replies are capped
// at 10 × 140, a settled post locks, the author edits or deletes only while nobody has responded.
import { useEffect, useRef, useState } from 'react';
import { awaiting, ymd } from '../../lib/projectPresentation.js';
import { iconFor } from '../../lib/projectLanePresets.js';
import { ink, ink2, ink3, paper, clay, clayBg, block, blockInset, fieldSolid, divider, display } from '../../theme.js';
import { Card, CountHeader, Chip, ChipRow, Tag, TypeTag, POST_ICON, postTint, appScroller, Sheet, FieldLabel, TextField, ReasonField, reasonOk, Note, pillButton, dangerButton, linkButton, PeopleChips } from './ProjectUI.jsx';

export function postMeta(p, post) {
  const L = p.LIMITS;
  if (post.type === 'proposal') {
    const voted = (post.votes || []).reduce((a, b) => a + b, 0);
    const parts = [p.T(`${voted}/${p.headcount} đã bỏ phiếu`, `${voted}/${p.headcount} voted`)];
    if (post.deadline) parts.push(p.T(`Hạn ${p.dueText(post.deadline)}`, `Vote by ${p.dueText(post.deadline)}`));
    return parts.join(' · ');
  }
  if (post.type === 'question') return `${p.T('Hỏi', 'To')} ${p.personName(post.addressee_id)} · ${post.replies_count}/${L.repliesMax} ${p.T('phản hồi', 'replies')}`;
  return p.T(`${post.seen_count}/${p.headcount} đã xem`, `${post.seen_count}/${p.headcount} seen`);
}

function PostCard({ post, p, ui }) {
  return (
    <button type="button" onClick={() => ui.openSheet({ kind: 'post', id: post.id })} data-testid={`project-post-${post.id}`}
      style={{ display: 'flex', flexDirection: 'column', gap: 6, width: '100%', padding: 14, borderRadius: 18, border: 0, background: block, color: ink, textAlign: 'left', cursor: 'pointer' }}>
      <span style={{ display: 'flex', justifyContent: 'space-between', width: '100%' }}>
        <TypeTag type={post.type} label={p.typeName(post.type)} />
        {post.state !== 'open' && <Tag tone="ink">🔒 {post.state === 'locked' ? p.T('Đã khoá', 'Locked') : p.T('Đã giải quyết', 'Resolved')}</Tag>}
      </span>
      <strong style={{ fontSize: 15.5 }}>{post.title}</strong>
      <span style={{ fontSize: 13, color: ink2 }}>{p.laneName(post.lane_id)} · {p.personName(post.author_id)}</span>
      <span style={{ fontSize: 13, fontWeight: 600, color: ink3 }}>{postMeta(p, post)}</span>
    </button>
  );
}

export default function ProjectTopics({ p, ui }) {
  const { snap, T } = p;
  const [rules, setRules] = useState(false);
  // The lane filter lives in the hub, so New post can preselect it and glow while it's empty.
  const lane = ui.topicsLane || null;
  const setLane = ui.setTopicsLane;
  const lanes = [...(snap.lanes || [])].sort((a, b) => a.position - b.position);
  const chipsRef = useRef(null);
  const [pinned, setPinned] = useState(false);
  // The chips stick under the top once the rules card has scrolled away (position: sticky); a hairline shows then.
  useEffect(() => {
    const sc = appScroller();
    if (!sc) return undefined;
    const on = () => {
      const el = chipsRef.current;
      if (el) setPinned(el.getBoundingClientRect().top - sc.getBoundingClientRect().top <= (ui.stickyTop || 0) + 0.5 && sc.scrollTop > 0);
    };
    on();
    sc.addEventListener('scroll', on, { passive: true });
    return () => sc.removeEventListener('scroll', on);
  }, [ui.stickyTop]);
  const pick = (id) => {
    setLane(id);
    // Show the filtered list from its start.
    if (pinned) chipsRef.current?.parentElement?.querySelector('[data-topics-list-start]')?.scrollIntoView?.({ block: 'start', behavior: 'smooth' });
  };
  const posts = snap.posts || [];
  const shown = posts.filter(x => !lane || x.lane_id === lane);
  const waiting = lane ? [] : awaiting(snap, p.userId).filter(a => a.kind !== 'laneReview').map(a => posts.find(x => x.id === a.id)).filter(Boolean);
  const rest = shown.filter(x => !waiting.some(w => w.id === x.id));
  const L = p.LIMITS;
  return (
    <div data-testid="project-topics-tab">
      <Card padding={6}>
        <button type="button" onClick={() => setRules(r => !r)} aria-expanded={rules} data-testid="project-topics-rules"
          style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', minHeight: 44, background: 'none', border: 0, color: ink, cursor: 'pointer', textAlign: 'left', padding: 0 }}>
          <span aria-hidden style={{ color: clay }}>ⓘ</span><strong style={{ flex: 1 }}>{T('Kênh có cấu trúc, không chat tự do', 'Structured channel, no free chat')}</strong><span aria-hidden>{rules ? '−' : '+'}</span>
        </button>
        {rules && (
          <ul data-testid="project-topics-rules-body" style={{ margin: '4px 0 8px', paddingLeft: 20, color: ink2, fontSize: 14, lineHeight: 1.5 }}>
            <li>{T('4 loại bài: Đề xuất, Câu hỏi, Cập nhật, Quyết định.', '4 post types: Proposal, Question, Update, Decision.')}</li>
            <li>{T(`Bài tối đa ${L.postBodyMax} ký tự, phản hồi ${L.replyMax} ký tự, ${L.repliesMax} phản hồi mỗi bài.`, `Posts up to ${L.postBodyMax} characters, replies ${L.replyMax}, at most ${L.repliesMax} replies per post.`)}</li>
            <li>{T('Giải quyết xong thì bài khoá lại. Phiếu và “Đã xem” là bộ đếm, không phải tin nhắn.', 'Settled posts lock. Votes and “Seen” are counters, not messages.')}</li>
            <li>{T(`Không báo từng bài: gom vào bản tin lúc ${L.digestHour}:00 theo giờ của bạn. Chỉ việc bị chặn mới báo ngay.`, `No alert for each post: they're bundled into a ${L.digestHour}:00 digest on your own clock. Only a blocked task alerts at once.`)}</li>
          </ul>
        )}
      </Card>
      <div data-topics-list-start style={{ scrollMarginTop: (ui.stickyTop || 0) }} />
      <div ref={chipsRef} data-testid="project-topics-chips" data-pinned={pinned ? '1' : '0'}
        style={{ position: 'sticky', top: ui.stickyTop || 0, zIndex: 6, margin: '4px -18px 0', padding: '8px 18px', background: paper,
          boxShadow: pinned ? `inset 0 -1px 0 ${divider}` : 'none' }}>
        <ChipRow scroll>
          <Chip title={T('Tất cả', 'All')} selected={!lane} onClick={() => pick(null)} count={posts.length} testId="project-topics-lane-all" />
          {lanes.map(l => <Chip key={l.id} title={l.name} icon={iconFor(l.name)} count={posts.filter(x => x.lane_id === l.id).length} selected={lane === l.id} onClick={() => pick(l.id)} testId={`project-topics-lane-${l.id}`} />)}
        </ChipRow>
      </div>
      {waiting.length > 0 && (<>
        <CountHeader title={T('Chờ bạn', 'Waiting on you')} count={waiting.length} />
        <div data-testid="project-topics-waiting" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{waiting.map(x => <PostCard key={x.id} post={x} p={p} ui={ui} />)}</div>
      </>)}
      <CountHeader title={T('Tất cả bài', 'All posts')} count={shown.length} />
      {!shown.length ? <EmptyLane p={p} ui={ui} lane={lanes.find(l => l.id === lane)} />
        : rest.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{rest.map(x => <PostCard key={x.id} post={x} p={p} ui={ui} />)}</div>
          : <Note>{T('Mọi bài đều ở mục Chờ bạn.', 'Every post is in Waiting on you.')}</Note>}
      {posts.length >= 20 && !p.s.projectPostsExhausted && (
        <button type="button" onClick={p.loadOlderPosts} data-testid="project-topics-older" style={{ ...linkButton, width: '100%', marginTop: 10 }}>{T('Xem bài cũ hơn', 'Show older posts')}</button>
      )}
    </div>
  );
}

/** No posts under this filter yet: say so, suggest what to post, and offer the button (New post glows meanwhile). */
function EmptyLane({ p, ui, lane }) {
  const { T } = p;
  return (
    <Card data-testid="project-topics-empty" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, textAlign: 'center', padding: '22px 16px' }}>
      <span aria-hidden style={{ width: 56, height: 56, borderRadius: '50%', background: clayBg, color: clay, display: 'grid', placeItems: 'center', fontSize: 26 }}>{lane ? iconFor(lane.name) : '💬'}</span>
      <h3 style={{ ...display(19, { margin: 0 }) }}>{lane ? T(`Chưa có bài trong ${lane.name}`, `No posts in ${lane.name} yet`) : T('Chưa có bài nào', 'No posts yet')}</h3>
      <p style={{ margin: 0, fontSize: 14, lineHeight: 1.5, color: ink2 }}>{T('Hỏi một người, đề xuất để cả đội bỏ phiếu, hoặc báo một tin. Bài đầu tiên giúp cả đội bắt đầu.', 'Ask someone, put options to a vote, or share an update. The first post gets the team going.')}</p>
      {p.can('post.question') && (
        <button type="button" data-testid="project-topics-first-post" onClick={() => ui.openSheet({ kind: 'compose', laneId: lane?.id || null })}
          style={pillButton(true, { width: 'auto', minHeight: 44, padding: '0 18px', marginTop: 4 })}>✎ {T('Viết bài đầu tiên', 'Write the first post')}</button>
      )}
    </Card>
  );
}

export function PostSheet({ postId, close, p }) {
  const { T } = p;
  const post = (p.snap.posts || []).find(x => x.id === postId);
  const [detail, setDetail] = useState(null);
  const [reply, setReply] = useState('');
  const [mode, setMode] = useState('view');
  const [reason, setReason] = useState('');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const reload = async () => setDetail(await p.loadPost(postId));
  useEffect(() => { reload(); }, [postId]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!post) return <Sheet title={T('Bài', 'Post')} onClose={close}><Note>{T('Bài này không còn nữa.', 'This post is gone.')}</Note></Sheet>;

  const open = post.state === 'open';
  const target = { laneId: post.lane_id, authorId: post.author_id, addresseeId: post.addressee_id, type: post.type, state: post.state, quiet: post.quiet };
  const canEdit = p.can('post.edit', target), canDelete = p.can('post.delete', target);
  const L = p.LIMITS;

  if (mode === 'edit') {
    const ok = title.trim().length >= L.postTitleMin && title.trim().length <= L.postTitleMax;
    return (
      <Sheet title={T('Sửa bài', 'Edit post')} onClose={close} testId="project-thread">
        <TextField label={T('Tiêu đề', 'Title')} value={title} onChange={setTitle} limit={L.postTitleMax} testId="project-post-edit-title" />
        <TextField label={T('Chi tiết', 'Details')} value={body} onChange={setBody} limit={L.postBodyMax} multiline />
        <button type="button" disabled={!ok} style={pillButton(true, { opacity: ok ? 1 : 0.4 })} data-testid="project-post-edit-save"
          onClick={async () => { if (await p.editPost(post.id, title.trim(), body.trim())) setMode('view'); }}>{T('Lưu', 'Save')}</button>
        <Note>{T('Bài sẽ hiện nhãn “đã sửa”. Chỉ sửa được khi chưa ai phản hồi, bỏ phiếu hay xem.', 'The post shows an “edited” label. It can be edited only before anyone replies, votes or marks it seen.')}</Note>
      </Sheet>
    );
  }
  if (mode === 'delete') {
    return (
      <Sheet title={T('Xoá bài', 'Delete post')} onClose={close} testId="project-thread">
        <h3 style={{ margin: 0 }}>{post.title}</h3>
        <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Đăng nhầm', 'Posted by mistake'), T('Trùng bài', 'Duplicate'), T('Không còn đúng', 'No longer true')]} />
        <button type="button" disabled={!reasonOk(reason)} style={dangerButton({ opacity: reasonOk(reason) ? 1 : 0.4 })} data-testid="project-post-confirm-delete"
          onClick={async () => { if (await p.deletePost(post.id, reason.trim())) close(); }}>{T('Xoá bài', 'Delete post')}</button>
        <button type="button" onClick={() => setMode('view')} style={linkButton}>{T('Không xoá', 'Keep it')}</button>
      </Sheet>
    );
  }

  const votes = post.votes || [];
  const total = Math.max(votes.reduce((a, b) => a + b, 0), 1);
  // Demo mode (dev only) keeps replies in state, so read them live rather than from the last load.
  const replies = p.demo ? ((p.s.projectDemoReplies || {})[postId] || []) : (detail?.replies || []);
  return (
    <Sheet title={p.typeName(post.type)} onClose={close} testId="project-thread">
      <div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          <Tag>{p.laneName(post.lane_id)}</Tag>
          {!open && <Tag tone="ink">🔒 {post.state === 'locked' ? T('Đã khoá', 'Locked') : T('Đã giải quyết', 'Resolved')}</Tag>}
          {post.edited_at && <span data-testid="project-post-edited" style={{ fontSize: 12, fontStyle: 'italic', color: ink3, alignSelf: 'center' }}>{T('đã sửa', 'edited')}</span>}
        </div>
        <h3 style={{ margin: '10px 0 4px', fontSize: 20 }}>{post.title}</h3>
        {post.body && <p style={{ margin: 0, color: ink2 }}>{post.body}</p>}
        <Note>{p.personName(post.author_id)}{post.addressee_id ? ` → ${p.personName(post.addressee_id)}` : ''}</Note>
      </div>
      {post.type === 'proposal' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {(post.options || []).map((o, i) => {
            const n = votes[i] || 0, mine = post.my_vote === i;
            return (
              <button key={i} type="button" disabled={!open || !p.can('post.vote')} onClick={async () => { if (await p.vote(post.id, i)) reload(); }}
                data-testid={`project-post-option-${i}`} aria-pressed={mine} aria-label={`${o}, ${T(`${n} phiếu`, n === 1 ? '1 vote' : `${n} votes`)}${mine ? T(', phiếu của bạn', ', your vote') : ''}`}
                style={{ position: 'relative', overflow: 'hidden', display: 'flex', alignItems: 'center', gap: 10, minHeight: 50, padding: '0 14px', borderRadius: 14,
                  border: mine ? `1.5px solid ${clay}` : '1.5px solid transparent', background: fieldSolid, color: ink, cursor: open ? 'pointer' : 'default', textAlign: 'left' }}>
                <span aria-hidden style={{ position: 'absolute', inset: 0, width: `${(n * 100) / total}%`, background: mine ? clayBg : blockInset }} />
                <span style={{ position: 'relative', flex: 1, fontWeight: mine ? 700 : 600 }}>{mine ? '✓ ' : ''}{o}</span>
                <span style={{ position: 'relative', fontWeight: 700 }}>{n}</span>
              </button>
            );
          })}
          <Note>{open ? T('Mỗi người một phiếu. Bấm lại để rút phiếu, bấm lựa chọn khác để đổi.', 'One vote each. Tap again to take it back, or tap another option to switch.') : T('Đã chốt. Không bỏ phiếu được nữa.', 'Settled. Voting is closed.')}</Note>
        </div>
      )}
      {(post.type === 'update' || post.type === 'decision') && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <Note tone="ink2">{(detail?.seen_by || []).map(u => p.personName(u)).join(', ') || T('Chưa ai xem', 'Nobody has seen it yet')} · {T(`${post.seen_count}/${p.headcount} đã xem`, `${post.seen_count}/${p.headcount} seen`)}</Note>
          {post.seen_by_me ? <div data-testid="project-post-seen-done" style={pillButton(false, { display: 'grid', placeItems: 'center', color: ink2 })}>👁 {T('Bạn đã xem', "You've seen this")}</div>
            : p.can('post.seen') && <button type="button" data-testid="project-post-seen" style={pillButton(true)} onClick={async () => { if (await p.markSeen(post.id)) reload(); }}>{T('Đã xem', 'Mark as seen')}</button>}
        </div>
      )}
      {replies.length > 0 && (
        <div data-testid="project-post-replies" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {replies.map(r => (
            <div key={r.id} style={{ padding: 12, borderRadius: 14, background: blockInset }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: ink3 }}>{p.personName(r.author_id)}</div>
              <div style={{ fontSize: 14 }}>{r.body}</div>
            </div>
          ))}
        </div>
      )}
      {(post.type === 'question' || post.type === 'proposal') && open && p.can('post.reply') && (
        post.replies_count >= L.repliesMax ? <Note tone="ink2">{T(`Đủ ${L.repliesMax} phản hồi. Hãy chốt hoặc đóng bài.`, `${L.repliesMax} replies reached. Settle or close the post.`)}</Note> : (
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 }}>
            <div style={{ flex: 1 }}><TextField label={T('Phản hồi', 'Reply')} value={reply} onChange={setReply} limit={L.replyMax} placeholder={T('Một dòng ngắn…', 'One short line…')} testId="project-post-reply" /></div>
            <button type="button" aria-label={T('Gửi phản hồi', 'Send reply')} data-testid="project-post-send" disabled={!reply.trim()}
              onClick={async () => { if (await p.reply(post.id, reply.trim())) { setReply(''); reload(); } }}
              style={{ width: 50, height: 50, borderRadius: '50%', border: 0, background: ink, color: 'var(--bb-bg)', cursor: 'pointer', opacity: reply.trim() ? 1 : 0.4 }}>➤</button>
          </div>
        ))}
      {open && post.type === 'proposal' && p.can('post.decision', { laneId: post.lane_id }) && (<>
        <button type="button" data-testid="project-post-decide" style={pillButton(true)} onClick={async () => { if (await p.decide(post.id)) close(); }}>{T('Chốt phương án dẫn đầu', 'Decide on the leading option')}</button>
        <Note>{T('Bài đề xuất khoá lại và một Quyết định được ghi vào nhật ký. Hoà phiếu thì chọn lựa chọn đầu tiên.', 'The proposal locks and a Decision goes into the log. A tie picks the first option.')}</Note>
      </>)}
      {open && post.type === 'question' && p.can('post.resolve', target) && (
        <button type="button" data-testid="project-post-resolve" style={pillButton(false)} onClick={async () => { if (await p.resolvePost(post.id)) reload(); }}>✓ {T('Đánh dấu đã giải quyết', 'Mark as resolved')}</button>
      )}
      {(canEdit || canDelete) && (
        <div style={{ display: 'flex', gap: 10 }}>
          {canEdit && <button type="button" data-testid="project-post-edit" style={pillButton(false)} onClick={() => { setTitle(post.title); setBody(post.body); setMode('edit'); }}>✎ {T('Sửa bài', 'Edit')}</button>}
          {canDelete && <button type="button" data-testid="project-post-delete" style={dangerButton()} onClick={() => { setReason(''); setMode('delete'); }}>{T('Xoá bài', 'Delete')}</button>}
        </div>
      )}
    </Sheet>
  );
}

export function ComposeSheet({ close, p, presetLane = null }) {
  const { T, snap } = p;
  const L = p.LIMITS;
  const [type, setType] = useState(null);
  const [laneId, setLaneId] = useState('');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [options, setOptions] = useState(['', '']);
  const [to, setTo] = useState(null);
  const [deadline, setDeadline] = useState(ymd(p.now().getTime() + 2 * 86400e3, p.tz));
  const lanesFor = (t) => {
    const all = [...(snap.lanes || [])].sort((a, b) => a.position - b.position);
    return t === 'decision' && !snap.is_host && snap.me?.role === 'lane_lead' ? all.filter(l => l.id === snap.me.lane_id) : all;
  };
  if (!type) {
    const channels = snap.project?.channels || [];
    const primary = channels.find(c => c.primary) || channels[0];
    return (
      <Sheet title={T('Bạn muốn đăng gì?', 'What do you want to post?')} onClose={close} testId="project-compose">
        {['proposal', 'question', 'update', 'decision'].map(t => {
          const ok = p.can(`post.${t}`);
          const hint = ok ? { proposal: T('Nhiều lựa chọn, cả đội bỏ phiếu đến hạn chót.', 'Several options. The team votes by a deadline.'),
            question: T('Hỏi đúng một người. Có người trả lời thì đóng.', 'Ask one named person. Close it once answered.'),
            update: T('Báo tin một chiều. Mọi người chỉ bấm “Đã xem”.', 'One-way news. People just tap “Seen”.'),
            decision: T('Chốt một việc và khoá lại, lưu vào nhật ký.', 'Settle something, lock it and log it.') }[t]
            : t === 'proposal' ? T('Hỗ trợ không đăng đề xuất. Hãy hỏi Trưởng hạng mục.', "Helpers don't post proposals. Ask your lane lead.")
              : T('Chốt quyết định do Chủ sự kiện, Quản lý hoặc Trưởng hạng mục làm.', 'Decisions come from the Host, a Manager or a lane lead.');
          return (
            <button key={t} type="button" disabled={!ok} data-testid={`project-compose-type-${t}`} onClick={() => { setType(t); setLaneId(lanesFor(t).find(l => l.id === presetLane)?.id || lanesFor(t)[0]?.id || ''); }}
              style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: 14, borderRadius: 18, border: 0, background: block, color: ink, textAlign: 'left', cursor: ok ? 'pointer' : 'default', opacity: ok ? 1 : 0.5 }}>
              <span aria-hidden style={{ width: 40, height: 40, borderRadius: '50%', background: postTint(t)[1], color: postTint(t)[0], display: 'grid', placeItems: 'center', flex: 'none' }}>{POST_ICON[t]}</span>
              <span><strong style={{ display: 'block' }}>{p.typeName(t)}</strong><span style={{ fontSize: 14, color: ink2 }}>{hint}</span></span>
            </button>
          );
        })}
        <Note tone="ink2">{T('Muốn nói chuyện bâng quơ? Gặp trực tiếp hoặc dùng kênh của đội. Ở đây chỉ dành cho việc cần chốt.', 'For small talk, meet in person or use the team channel. This is for things that need settling.')}</Note>
        {primary && <a href={primary.url} target="_blank" rel="noopener noreferrer" onClick={e => p.demoLinkBlocked(e)} data-testid="project-compose-channel" style={{ ...pillButton(false, { display: 'grid', placeItems: 'center', textDecoration: 'none', width: 'auto', padding: '0 16px' }) }}>↗ {primary.label}</a>}
      </Sheet>
    );
  }
  const opts = options.map(o => o.trim()).filter(Boolean);
  const why = title.trim().length < L.postTitleMin ? T(`Tiêu đề ít nhất ${L.postTitleMin} ký tự.`, `A title needs at least ${L.postTitleMin} characters.`)
    : type === 'proposal' && opts.length < L.proposalOptionsMin ? T(`Cần ít nhất ${L.proposalOptionsMin} lựa chọn.`, `Add at least ${L.proposalOptionsMin} options.`)
      : type === 'question' && !to ? T('Hãy chọn người để hỏi.', 'Pick who to ask.') : null;
  return (
    <Sheet title={p.typeName(type)} onClose={close} testId="project-compose">
      <FieldLabel>{T('Hạng mục', 'Lane')}</FieldLabel>
      <ChipRow>{lanesFor(type).map(l => <Chip key={l.id} title={l.name} icon={iconFor(l.name)} selected={laneId === l.id} onClick={() => setLaneId(l.id)} testId={`project-compose-lane-${l.id}`} />)}</ChipRow>
      <TextField label={T('Tiêu đề', 'Title')} value={title} onChange={setTitle} limit={L.postTitleMax} placeholder={T('Nói gọn trong một câu', 'Say it in one line')} testId="project-compose-title" />
      <TextField label={T('Chi tiết', 'Details')} value={body} onChange={setBody} limit={L.postBodyMax} multiline placeholder={T('Chỉ thông tin người khác cần để quyết định', 'Only what others need to decide')} testId="project-compose-body" />
      {type === 'proposal' && (<>
        <FieldLabel>{T(`Lựa chọn (${L.proposalOptionsMin}–${L.proposalOptionsMax})`, `Options (${L.proposalOptionsMin}–${L.proposalOptionsMax})`)}</FieldLabel>
        {options.map((o, i) => <TextField key={i} label={T(`Lựa chọn ${i + 1}`, `Option ${i + 1}`)} value={o} limit={L.proposalOptionMax} testId={`project-compose-option-${i}`} onChange={v => setOptions(options.map((x, j) => (j === i ? v : x)))} />)}
        {options.length < L.proposalOptionsMax && <button type="button" onClick={() => setOptions([...options, ''])} style={linkButton} data-testid="project-compose-add-option">＋ {T('Thêm lựa chọn', 'Add option')}</button>}
        <TextField type="date" label={T('Hạn bỏ phiếu', 'Vote by')} value={deadline} onChange={setDeadline} />
      </>)}
      {type === 'question' && (<>
        <FieldLabel>{T('Hỏi ai', 'Ask whom')}</FieldLabel>
        <PeopleChips p={p} value={to} onChange={setTo} testId="project-compose-to" exclude={p.userId} />
      </>)}
      {type === 'decision' && <Note>{T('Quyết định khoá ngay và vào nhật ký. Mọi người chỉ bấm “Đã xem”.', 'A decision locks at once and goes into the log. People just tap “Seen”.')}</Note>}
      <button type="button" disabled={!!why || !laneId || p.s.projectBusy} data-testid="project-compose-post" style={pillButton(true, { opacity: why ? 0.4 : 1 })}
        onClick={async () => {
          const ok = await p.createPost({ type, laneId, title: title.trim(), body: body.trim(), options: type === 'proposal' ? opts : null,
            addresseeId: type === 'question' ? to : null, deadline: type === 'proposal' && deadline ? deadline : null });
          if (ok) close();
        }}>{T('Đăng', 'Post')}</button>
      {why && <Note>{why}</Note>}
      <button type="button" onClick={() => setType(null)} style={linkButton}>{T('Đổi loại bài', 'Change type')}</button>
    </Sheet>
  );
}
