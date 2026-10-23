import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { withR2Columns, marketColumnList } from '../lib/mediaUrls.js';
import { rowTimeZone } from '../lib/eventMarket.js';
import { nextFromHost, whenLabel } from '../lib/quickWins.js';
import { flagOn } from '../lib/featureFlags.js';
import {
  FEEDBACK, FEEDBACK_PRIVACY, noteLength, clampNote, canSaveFeedback, feedbackWindowOpen, feedbackErrorText,
} from '../lib/coreLoops.js';
import { bg } from '../data/events.js';
import { paper, ink, rule, alert, clay, clayBg, display, fieldGlass, inkButton, RADIUS } from '../theme.js';

// L2 guest recap card (switch `event_recap`, migration 199): what a ticket holder sees after an event ends, from the
// event_recap notification or the ended Event Detail ("You went ✓"). The event, its photos, Follow host, Next from
// this host, and a PRIVATE 👍/👎 + note that only the host sees, as counts and unnamed notes, once 3 or more guests
// answered (the server enforces all of it). No public rating, no streak, no nudging. iOS twin: EventRecapView.swift.
export default function EventRecap() {
  const { state: s, T, backFromEventRecap, loadEventPhotos, openPhoto, toggleFollowOrganizer, goEvent } = useBanBe();
  const id = s.eventRecapId;
  const ev = id ? s.realEventsById[id] : null;
  const enabled = flagOn(s.featureFlags, 'event_recap');
  const orgId = ev?.organizerId || null;
  const followed = !!orgId && s.followedOrgIds.includes(orgId);

  useEffect(() => { if (id && enabled) loadEventPhotos(id); }, [id, enabled, loadEventPhotos]);
  const photos = (s.eventPhotos || []).filter(p => p.url).map(p => ({ id: p.id, url: p.url, eventId: id }));

  // Next from this host: the same rule and query as Event Detail's ended section (Phase 1 Q3).
  const [hostNext, setHostNext] = useState([]);
  useEffect(() => {
    setHostNext([]);
    if (!enabled || !orgId) return undefined;
    let live = true;
    withR2Columns(() => supabase.from('events').select(['id, name, starts_at, status', ...marketColumnList()].join(', '))
      .eq('organizer_id', orgId).eq('status', 'live').gt('starts_at', new Date().toISOString())
      .order('starts_at', { ascending: true }).limit(4))
      .then(({ data }) => {
        if (!live || !data) return;
        setHostNext(nextFromHost(data.map(r => ({ key: r.id, name: r.name, status: r.status, startsAt: r.starts_at, tz: rowTimeZone(r) })), Date.now(), id));
      }, () => {});
    return () => { live = false; };
  }, [enabled, orgId, id]);

  // The guest's own earlier answer (owner-only RPC). `saved` is what the server holds; rating/note are the draft.
  const [loaded, setLoaded] = useState(false);
  const [saved, setSaved] = useState(null);
  const [rating, setRating] = useState(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [closed, setClosed] = useState(false);
  const [justSaved, setJustSaved] = useState(false);
  useEffect(() => {
    setLoaded(false); setSaved(null); setRating(null); setNote(''); setError(''); setClosed(false); setJustSaved(false);
    if (!id || !enabled || !s.user?.id) return undefined;
    let live = true;
    supabase.rpc('get_my_event_feedback', { p_event_id: id }).then(({ data, error: e }) => {
      if (!live) return;
      setLoaded(true);
      const fb = !e && data?.success ? data.feedback : null;
      if (fb && (fb.rating === 1 || fb.rating === -1)) { setSaved(fb); setRating(fb.rating); setNote(fb.note || ''); }
    }, () => { if (live) setLoaded(true); });
    return () => { live = false; };
  }, [id, enabled, s.user?.id]);

  const windowOpen = feedbackWindowOpen(ev?.startsAt) && !closed;
  const dirty = rating !== (saved?.rating ?? null) || note.trim() !== (saved?.note || '').trim();
  const save = async () => {
    if (!canSaveFeedback(rating, note) || busy) return;
    setBusy(true); setError(''); setJustSaved(false);
    const { data, error: e } = await supabase.rpc('submit_event_feedback', { p_event_id: id, p_rating: rating, p_note: note.trim() })
      .then(r => r, () => ({ data: null, error: true }));
    setBusy(false);
    if (!e && data?.success) { setSaved({ rating, note: note.trim() }); setJustSaved(true); return; }
    const code = data?.error || 'NETWORK';
    if (code === 'NOT_OPEN') setClosed(true);
    const msg = feedbackErrorText(code);
    setError(T(msg.vi, msg.en));
  };

  const when = ev?.startsAt ? whenLabel(ev.startsAt, ev.tz || rowTimeZone(ev), s.lang === 'en') : '';
  const heading = display(20, { lineHeight: 1.25 });
  const ratingBtn = (value, label, emoji, testId) => {
    const on = rating === value;
    return (
      <button type="button" key={value} onClick={windowOpen ? () => { setRating(value); setJustSaved(false); } : undefined}
        disabled={!windowOpen} aria-pressed={on} aria-label={label} data-testid={testId}
        style={{
          flex: 1, minHeight: 48, borderRadius: RADIUS.pill, fontFamily: 'inherit', fontSize: 22, cursor: windowOpen ? 'pointer' : 'default',
          border: `1px solid ${on ? clay : rule}`, background: on ? clayBg : 'transparent', color: ink, opacity: !windowOpen && !on ? 0.5 : 1,
        }}>{emoji}</button>
    );
  };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Event recap">
      <div onClick={backFromEventRecap} role="button" data-testid="event-recap-back" style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>
        ‹ {s.eventRecapBack === 'notifications' ? T('Thông báo', 'Notifications') : s.eventRecapBack === 'event' ? T('Sự kiện', 'Event') : T('Quay lại', 'Back')}
      </div>
      <div style={{ padding: '14px 22px 48px' }}>
        {!enabled ? (
          <p style={{ fontSize: 13.5, color: ink, opacity: 0.7 }} data-testid="event-recap-off">{T('Tính năng này đang tạm tắt.', 'This is turned off for now.')}</p>
        ) : !ev ? (
          <p style={{ fontSize: 13.5, color: ink, opacity: 0.7 }}>{T('Đang tải…', 'Loading…')}</p>
        ) : (
          <>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7 }}>{T('Sự kiện đã kết thúc', 'This event has ended')}</span>
            <h1 onClick={() => goEvent(id)} role="link" data-testid="event-recap-title" style={{ ...display(26, { margin: '6px 0 0', cursor: 'pointer' }) }}>{ev.name}</h1>
            {when && <p style={{ fontSize: 13, color: ink, opacity: 0.7, margin: '6px 0 0' }}>{when}</p>}

            {/* Photos: the same event_photos the event page shows, opened in the same viewer. */}
            <div style={{ marginTop: 24 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                <span style={heading}>{T('Hình ảnh', 'Photos')}</span>
                {photos.length > 0 && <span style={{ fontSize: 13, color: ink, opacity: 0.6 }}>{photos.length}</span>}
              </div>
              {s.eventPhotosLoading ? (
                <p style={{ fontSize: 13, color: ink, opacity: 0.6, margin: '10px 0 0' }}>{T('Đang tải…', 'Loading…')}</p>
              ) : photos.length ? (
                <div data-testid="event-recap-photos" style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 10, paddingBottom: 4 }}>
                  {photos.map((p, i) => (
                    <div key={p.id} onClick={(e) => openPhoto(photos, i, ev.organizerName, e.currentTarget.getBoundingClientRect())} data-photo-thumb={p.id} style={{ flex: 'none' }}>
                      <div style={bg(p.url, { width: 116, height: 146, borderRadius: RADIUS.thumb, cursor: 'pointer' })} />
                    </div>
                  ))}
                </div>
              ) : (
                <p style={{ fontSize: 13, color: ink, opacity: 0.6, margin: '10px 0 0' }}>{T('Host chưa đăng ảnh nào.', "The host hasn't posted photos yet.")}</p>
              )}
            </div>

            {/* Private feedback: only the host sees it, as counts and unnamed notes, from 3 answers. */}
            <section data-testid="event-recap-feedback" style={{ ...fieldGlass({ marginTop: 28, padding: '16px 16px 14px' }) }}>
              <span style={heading}>{T('Buổi này thế nào?', 'How was it?')}</span>
              <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '6px 0 0' }} data-testid="event-recap-privacy">
                {T(FEEDBACK_PRIVACY.vi, FEEDBACK_PRIVACY.en)}
              </p>
              {!loaded ? (
                <p style={{ fontSize: 13, color: ink, opacity: 0.6, margin: '12px 0 0' }}>{T('Đang tải…', 'Loading…')}</p>
              ) : (
                <>
                  <div role="group" aria-label={T('Đánh giá riêng', 'Private rating')} style={{ display: 'flex', gap: 10, marginTop: 14 }}>
                    {ratingBtn(1, T('Thích', 'Liked it'), '👍', 'event-recap-up')}
                    {ratingBtn(-1, T('Không thích', "Didn't like it"), '👎', 'event-recap-down')}
                  </div>
                  {windowOpen ? (
                    <>
                      <textarea
                        value={note} onChange={(e) => { setNote(clampNote(e.target.value)); setJustSaved(false); }}
                        placeholder={T('Ghi chú cho host (không bắt buộc)', 'A note for the host (optional)')}
                        aria-label={T('Ghi chú cho host', 'Note for the host')} data-testid="event-recap-note" rows={3}
                        style={{ width: '100%', boxSizing: 'border-box', marginTop: 12, padding: '10px 12px', borderRadius: 12, border: `1px solid ${rule}`, background: paper, color: ink, fontFamily: 'inherit', fontSize: 14, lineHeight: 1.45, resize: 'vertical' }}
                      />
                      <div style={{ display: 'flex', justifyContent: 'flex-end', fontSize: 11.5, color: ink, opacity: 0.6, marginTop: 4 }} data-testid="event-recap-counter">
                        {noteLength(note)}/{FEEDBACK.noteMax}
                      </div>
                      <button type="button" onClick={save} disabled={!canSaveFeedback(rating, note) || !dirty || busy} data-testid="event-recap-save"
                        style={{ ...inkButton({ width: '100%', marginTop: 10, padding: '13px 12px', border: 'none', fontFamily: 'inherit', fontSize: 14.5, fontWeight: 600 }), opacity: (!canSaveFeedback(rating, note) || !dirty || busy) ? 0.45 : 1, cursor: 'pointer' }}>
                        {busy ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
                      </button>
                      {justSaved && !dirty && (
                        <p role="status" style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '8px 0 0' }} data-testid="event-recap-saved">
                          {T('Đã lưu. Bạn có thể sửa trong 14 ngày sau sự kiện.', 'Saved. You can change it for 14 days after the event.')}
                        </p>
                      )}
                    </>
                  ) : (
                    <>
                      {saved?.note ? <p style={{ fontSize: 13.5, color: ink, margin: '12px 0 0', whiteSpace: 'pre-wrap' }}>{saved.note}</p> : null}
                      <p style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '10px 0 0' }} data-testid="event-recap-closed">{T('Đã đóng phần cảm nhận cho sự kiện này.', 'Feedback for this event is closed.')}</p>
                    </>
                  )}
                  {error && !closed && <p role="alert" style={{ fontSize: 12.5, color: alert, margin: '8px 0 0' }} data-testid="event-recap-error">{error}</p>}
                </>
              )}
            </section>

            {orgId && (
              <div style={{ marginTop: 28 }}>
                <button type="button" onClick={() => toggleFollowOrganizer(orgId)} data-testid="event-recap-follow" aria-pressed={followed}
                  style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '100%', padding: '11px 14px', borderRadius: RADIUS.pill, cursor: 'pointer', fontFamily: 'inherit', border: `1px solid ${clay}`, background: followed ? clayBg : 'transparent', fontSize: 14, fontWeight: 600, color: clay }}>
                  {followed ? T('Đang theo dõi host ✓', 'Following this host ✓') : T('Theo dõi host', 'Follow host')}
                </button>
                {hostNext.length > 0 && (
                  <>
                    <div style={{ ...heading, marginTop: 24 }}>{T('Sự kiện tiếp theo của host', 'Next from this host')}</div>
                    <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column' }}>
                      {hostNext.map((r, i) => (
                        <div key={r.key} onClick={() => goEvent(r.key)} role="button" data-testid={`event-recap-next-${i}`}
                          style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '11px 0', borderTop: i > 0 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                          <span style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                            <span style={{ ...display(15), overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.name}</span>
                            <span style={{ fontSize: 12.5, color: ink, opacity: 0.65 }}>{whenLabel(r.startsAt, r.tz, s.lang === 'en')}</span>
                          </span>
                          <span aria-hidden style={{ color: clay, fontSize: 16, flex: 'none' }}>›</span>
                        </div>
                      ))}
                    </div>
                  </>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
