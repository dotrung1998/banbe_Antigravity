// v2.3 Event Detail layout (note 81, switch home_v23), from docs/prototypes/homescreen-event-detail-motion-v2-3.html.
// One scroller: a 392 px cinematic hero (photo 140 % tall for the parallax, vignette + shade, category/age pills and a
// serif title that sinks and fades as it leaves), the ticket stub riding 22 px over it, then the editorial body (Good to
// know as a label/value list, About with Read more, the included items numbered 01 02 03, the host as one plain row,
// the photo strip, the protected-booking steps). Over it: one floating glass Back over the photo, handing off past
// 140 px to a glass nav with the title, Save, Share, ⋯, the section tabs and a reading-progress line. The reserve bar
// floats at the bottom (ReserveBarV23, or the single action for every other state).
// Presentational only: EventDetail.jsx owns the data, the refs, the scroll handler, the zoom and the pull-down.
import { useEffect, useState } from 'react';
import { bg } from '../../data/events.js';
import { SERIF, V23_CSS, glassBar } from './v23Style.js';
import { listNo } from '../../lib/eventDetailV23.js';
import GlassMenu from '../GlassMenu.jsx';

const ico = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round', viewBox: '0 0 24 24', 'aria-hidden': true };
const IconBack = () => (<svg {...ico} width={19} height={19} strokeWidth={1.9}><path d="m15 5-7 7 7 7" /></svg>);
const IconSave = ({ on }) => (<svg {...ico} width={20} height={20} fill={on ? 'currentColor' : 'none'}><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>);
const IconShare = () => (<svg {...ico} width={20} height={20}><path d="M12 16V4M12 4 8 8M12 4l4 4" /><path d="M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5" /></svg>);
const IconMore = () => (<svg {...ico} width={20} height={20}><circle cx="5.5" cy="12" r="1.3" fill="currentColor" /><circle cx="12" cy="12" r="1.3" fill="currentColor" /><circle cx="18.5" cy="12" r="1.3" fill="currentColor" /></svg>);
const IconChev = () => (<svg {...ico} width={13} height={13}><path d="m6 9 6 6 6-6" /></svg>);
const IconMsg = () => (<svg {...ico} width={14} height={14}><path d="M21 12a8 8 0 0 1-11.6 7.1L4 21l1.9-5.4A8 8 0 1 1 21 12Z" /></svg>);

const H = ({ children, action }) => (
  <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, margin: '0 0 14px' }}>
    <h2 style={{ margin: 0, fontSize: 11, letterSpacing: '0.16em', textTransform: 'uppercase', color: 'var(--bb-fg-2)', fontWeight: 700 }}>{children}</h2>
    {action}
  </div>
);
const nbtn = { width: 44, height: 44, borderRadius: '50%', display: 'grid', placeItems: 'center', flex: 'none', border: 'none', background: 'none', color: 'var(--bb-fg)', cursor: 'pointer', padding: 0 };

/** One section of the body: revealed on scroll (40 ms after it enters), hairline under all but the last. */
const Sec = ({ secRef, id, testId, last, children }) => (
  <section ref={secRef} data-section={id} data-v23-sec data-testid={testId} className="bbv23-sec"
    style={{ paddingBottom: last ? 0 : 30, marginBottom: last ? 0 : 30, borderBottom: last ? 'none' : '1px solid var(--bb-divider)' }}>
    {children}
  </section>
);

/** True once `url` is decoded. Starts true when the browser already holds it (the tapped row's thumbnail is the same
 *  URL), so the hero paints the cover on its first frame instead of fading it in over a placeholder. */
function useImageReady(url) {
  const peek = (u) => {
    if (!u || typeof Image === 'undefined') return false;
    const im = new Image(); im.src = u;
    return im.complete && im.naturalWidth > 0;
  };
  const [ready, setReady] = useState(() => ({ url, ok: peek(url) }));
  useEffect(() => {
    if (!url) return undefined;
    if (peek(url)) { setReady({ url, ok: true }); return undefined; }
    setReady({ url, ok: false });
    let live = true;
    const im = new Image();
    const done = () => { if (live) setReady({ url, ok: true }); };
    im.onload = done; im.onerror = done; // a broken URL settles on the quiet surface rather than waiting forever
    im.src = url;
    return () => { live = false; im.onload = null; im.onerror = null; };
  }, [url]);
  return ready.url === url && ready.ok;
}

export default function EventDetailV23View(p) {
  const { T, ev, entrance, dimRef, cardRef, scrollerRef, heroRef, heroImgRef, progressRef, tabRowRef, onScroll, collapsed,
    backLabel, onBack, saved, onSave, onShare, menuOpen, setMenuOpen, menuItems, toast,
    catLabel, minAge, inviteOnly, stub, afterStub, criteria, know, about, aboutExpanded, setAboutExpanded, introExtra = [], introCss = null,
    menuTitle, cards, host, afterHost, photos, protection, tabs, bar, overlays, inert = false, footer = null, scrollPad = 230 } = p;
  // The create-event preview (inert): every guest control shows but does nothing.
  const off = inert ? { pointerEvents: 'none' } : null;

  // Sections reveal on scroll, 40 ms apart, inside this scroller. A return visit or Reduce Motion shows them at once
  // (.bbv23-noent / the reduced-motion CSS).
  useEffect(() => {
    const sc = scrollerRef.current;
    if (!sc) return undefined;
    const els = Array.from(sc.querySelectorAll('[data-v23-sec]'));
    if (!entrance || typeof IntersectionObserver === 'undefined') { els.forEach(el => el.classList.add('in')); return undefined; }
    const io = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (!e.isIntersecting) return;
        const el = e.target;
        el.style.transitionDelay = '40ms';
        el.addEventListener('transitionend', () => { el.style.transitionDelay = '0ms'; }, { once: true });
        el.classList.add('in');
        io.unobserve(el);
      });
    }, { root: sc, threshold: 0.1 });
    els.forEach(el => io.observe(el));
    return () => io.disconnect();
  }, [ev.key]); // eslint-disable-line react-hooks/exhaustive-deps

  // The monogram plate is ONLY for an event with no photo (and a name: a still-loading row has neither). With a photo,
  // a quiet mat surface sits under it until it is decoded; the plate and its big initial used to show for a moment
  // before every cover loaded.
  const monogram = (ev.name || '').trim().charAt(0).toUpperCase();
  const heroReady = useImageReady(ev.img || '');
  const sections = [
    { id: 'overview', show: true },
    { id: 'menu', show: cards.length > 0 },
    { id: 'host', show: true },
    { id: 'photos', show: true },
    { id: 'safe', show: !!protection },
  ].filter(s => s.show);
  const lastId = sections[sections.length - 1].id;

  return (
    <div className={entrance ? undefined : 'bbv23-noent'} style={{ position: 'absolute', inset: 0 }} data-screen-label="Event">
      <style>{V23_CSS}</style>
      <div ref={dimRef} aria-hidden style={{ position: 'fixed', inset: 0, background: 'rgb(12,12,12)', opacity: 0, pointerEvents: 'none', zIndex: 0 }} />
      <div ref={cardRef} className={`bbv23${p.slideIn ? ' bbv23-in' : ''}`} data-testid="event-detail-v23" style={{ position: 'relative', zIndex: 1, height: '100%', overflow: 'hidden', isolation: 'isolate' }}>
        <div data-fade aria-hidden style={{ position: 'absolute', inset: 0, background: 'var(--bb-bg)', zIndex: -1 }} />
        <div ref={scrollerRef} data-testid="event-scroller" onScroll={onScroll} className="bbv23-scroll"
          style={{ position: 'absolute', inset: 0, overflowY: 'auto', overflowX: 'hidden', WebkitOverflowScrolling: 'touch', overscrollBehaviorY: 'contain', paddingBottom: `calc(${scrollPad}px + env(safe-area-inset-bottom, 0px))` }}>
          {/* Hero: the shared element the card zooms into. */}
          <div ref={heroRef} data-testid="event-hero" style={{ position: 'relative', height: 392, overflow: 'hidden', background: ev.img || !monogram ? 'var(--bb-mat)' : '#241E17' }}>
            {!ev.img && monogram && (
              <div aria-hidden style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', background: 'radial-gradient(120% 85% at 28% 6%, #4A3A2A 0%, #241E17 46%, #14110D 100%)' }}>
                <span style={{ fontSize: 190, fontWeight: 300, lineHeight: 1, letterSpacing: '-0.06em', color: 'rgba(247,244,236,.08)', transform: 'translateY(10px)' }}>{monogram}</span>
              </div>
            )}
            {ev.img && <div ref={heroImgRef} aria-hidden data-testid="event-hero-img" data-ready={heroReady ? 'true' : 'false'} className="bbv23-heroimg" style={bg(ev.img, { position: 'absolute', left: 0, top: '-20%', width: '100%', height: '140%', borderRadius: 0, willChange: 'transform', transformOrigin: 'center 30%', filter: 'saturate(1.06) contrast(1.02)', opacity: heroReady ? 1 : 0 })} />}
            <div aria-hidden style={{ position: 'absolute', inset: 0, background: 'radial-gradient(130% 90% at 50% 0%, transparent 32%, rgba(0,0,0,.42) 100%)' }} />
            {/* The prototype's shade, with the lower band held at >= 0.7 so the white title keeps 4.5:1 on a white photo
                (the same floor as HERO_SCRIM, note 70). */}
            <div aria-hidden data-testid="event-hero-scrim" style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(6,5,4,.68) 0%, rgba(6,5,4,.1) 30%, rgba(6,5,4,.7) 56%, rgba(6,5,4,.92) 100%)' }} />
            <div data-testid="event-hero-title" className="bbv23-ttl" style={{ position: 'absolute', left: 22, right: 22, bottom: 26, zIndex: 2, color: '#fff' }}>
              <div style={{ display: 'flex', gap: 7, marginBottom: 13, flexWrap: 'wrap' }}>
                {catLabel && <span data-testid="event-category" style={{ height: 26, padding: '0 10px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', fontSize: 11, fontWeight: 700, letterSpacing: '0.03em', background: 'rgba(247,244,236,.92)', color: '#1B1916', backdropFilter: 'blur(14px) saturate(1.6)', WebkitBackdropFilter: 'blur(14px) saturate(1.6)' }}>{catLabel}</span>}
                {minAge && <span data-testid={`event-type-fact-${minAge.id}`} aria-label={`${minAge.label} ${minAge.value}`} style={{ height: 26, padding: '0 10px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', fontSize: 11, fontWeight: 700, letterSpacing: '0.03em', background: 'rgba(0,0,0,.28)', color: '#fff', border: '1px solid rgba(255,255,255,.5)' }}>{minAge.value}</span>}
                {inviteOnly && <span data-testid="event-invite-chip" style={{ height: 26, padding: '0 10px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', fontSize: 11, fontWeight: 700, background: 'rgba(0,0,0,.28)', color: '#fff', border: '1px solid rgba(255,255,255,.5)' }}>{T('Riêng tư · theo lời mời', 'Private · invite only')}</span>}
              </div>
              <h1 style={{ margin: 0, fontFamily: SERIF, fontWeight: 400, fontSize: 40, lineHeight: 1.04, letterSpacing: '-0.025em', textWrap: 'balance', overflowWrap: 'anywhere' }}>{ev.name}</h1>
            </div>
          </div>

          <div data-fade>
            {stub}
            {afterStub}
            <div data-testid="event-sheet" style={{ padding: '26px 22px 0' }}>
              <Sec secRef={p.secRefs.overview} id="overview" last={lastId === 'overview'}>
                {criteria}
                {know.length > 0 && (
                  <div data-testid="event-type-facts">
                    <H>{T('Cần biết', 'Good to know')}</H>
                    <dl style={{ display: 'grid', gridTemplateColumns: '104px 1fr', gap: '15px 18px', margin: about.visible ? '0 0 28px' : 0 }}>
                      {know.map(r => (
                        <div key={r.key} data-testid={`event-type-fact-${r.key}`} style={{ display: 'contents' }}>
                          <dt style={{ fontSize: 10.5, letterSpacing: '0.13em', textTransform: 'uppercase', color: 'var(--bb-clay)', fontWeight: 700, paddingTop: 3 }}>{typeof r.label === 'string' ? r.label : T(r.label.vi, r.label.en)}</dt>
                          <dd style={{ margin: 0, fontSize: 14, lineHeight: 1.58, color: 'var(--bb-fg-2)', overflowWrap: 'anywhere' }}>{r.text}</dd>
                        </div>
                      ))}
                    </dl>
                  </div>
                )}
                {about.visible && (
                  <div>
                    <H>{T('Giới thiệu', 'About')}</H>
                    {about.body && (
                      <p data-testid="event-description" style={{ margin: 0, fontSize: 15, lineHeight: 1.66, color: 'var(--bb-fg-2)', ...((about.clampable || introExtra.length) && !aboutExpanded ? { display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' } : null) }}>{about.body}</p>
                    )}
                    {/* The host's longer introduction (their own font and colour, note 69), under Read more: it used to live
                        only in the About & Included sheet, which this page no longer needs. */}
                    {aboutExpanded && introExtra.length > 0 && (
                      <div data-testid="event-intro-section" style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
                        {introExtra.map((t, i) => <p key={i} style={{ margin: 0, fontSize: 15, lineHeight: 1.66, whiteSpace: 'pre-wrap', color: 'var(--bb-fg-2)', ...introCss }}>{t}</p>)}
                      </div>
                    )}
                    {(about.clampable || introExtra.length > 0) && (
                      <button type="button" onClick={() => setAboutExpanded(v => !v)} data-testid="event-read-more" aria-expanded={aboutExpanded} className="bbv23-more"
                        style={{ marginTop: 4, minHeight: 44, padding: 0, border: 'none', background: 'none', color: 'var(--bb-fg)', fontSize: 13, fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: 5, cursor: 'pointer' }}>
                        {aboutExpanded ? T('Thu gọn', 'Read less') : T('Xem thêm', 'Read more')} <IconChev />
                      </button>
                    )}
                  </div>
                )}
              </Sec>

              {cards.length > 0 && (
                <Sec secRef={p.secRefs.menu} id="menu" testId="event-included-items" last={lastId === 'menu'}>
                  <H>{menuTitle}</H>
                  <ol style={{ display: 'flex', flexDirection: 'column', gap: 19, margin: 0, padding: 0, listStyle: 'none' }}>
                    {cards.map((c, i) => (
                      <li key={i} data-testid={`event-included-item-${i}`} style={{ display: 'grid', gridTemplateColumns: '32px 1fr', gap: 12, alignItems: 'baseline' }}>
                        <span aria-hidden style={{ fontFamily: SERIF, fontSize: 17, lineHeight: 1.2, color: 'var(--bb-clay)', letterSpacing: '0.02em' }}>{listNo(i)}</span>
                        <span style={{ minWidth: 0 }}>
                          <b style={{ display: 'block', fontSize: 14.5, fontWeight: 600, letterSpacing: '-0.005em', overflowWrap: 'anywhere' }}>{c.label}</b>
                          {c.detail && <span style={{ display: 'block', fontSize: 13, color: 'var(--bb-fg-2)', marginTop: 2, lineHeight: 1.5, overflowWrap: 'anywhere' }}>{c.detail}</span>}
                        </span>
                      </li>
                    ))}
                  </ol>
                </Sec>
              )}

              <Sec secRef={p.secRefs.host} id="host" last={lastId === 'host'}>
                <H>{T('Chủ nhà', 'Hosted by')}</H>
                <div data-testid="event-host-section" style={{ display: 'flex', alignItems: 'center', gap: 12, ...off }}>
                  <div onClick={host.onOpen} data-testid="event-organizer-row" role="button" aria-label={host.ariaLabel} className="bbv23-press"
                    style={{ flex: 1, minWidth: 0, minHeight: 46, display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }}>
                    <span style={{ width: 46, height: 46, borderRadius: '50%', overflow: 'hidden', background: 'var(--bb-clay)', color: '#fff', display: 'grid', placeItems: 'center', fontSize: 16, fontWeight: 700, flex: 'none' }}>
                      {host.avatarUrl ? <img src={host.avatarUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : host.initial}
                    </span>
                    <span style={{ flex: 1, minWidth: 0 }}>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                        <b style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.01em', overflowWrap: 'anywhere' }}>{host.name}</b>
                        {host.badge}
                      </span>
                      <span data-testid="event-organizer-stats" style={{ display: 'block', fontSize: 12.5, color: 'var(--bb-fg-3)', marginTop: 2 }}>{host.sub}</span>
                    </span>
                  </div>
                  <button type="button" onClick={host.onMessage} data-testid="organizer-message" aria-label={host.messageLabel}
                    style={{ flex: 'none', minHeight: 44, padding: 0, border: 'none', background: 'none', color: 'var(--bb-clay)', fontSize: 13, fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: 5, cursor: 'pointer' }}>
                    <IconMsg />{T('Nhắn tin', 'Message')}
                  </button>
                </div>
                {afterHost}
              </Sec>

              <Sec secRef={p.secRefs.photos} id="photos" last={lastId === 'photos'}>
                <H>{T('Hình ảnh', 'Photos')}{photos.list.length > 0 ? ` · ${photos.list.length}` : ''}</H>
                {photos.loading ? (
                  <p style={{ fontSize: 13, color: 'var(--bb-fg-3)', margin: 0 }}>{T('Đang tải…', 'Loading…')}</p>
                ) : photos.list.length ? (
                  <div data-testid="event-photo-strip" style={{ display: 'flex', gap: 9, overflowX: 'auto', scrollbarWidth: 'none', margin: '0 -22px', padding: '0 22px 2px', ...(inert ? { cursor: 'default' } : null) }} data-hscroll>
                    {photos.list.map((ph, i) => (
                      <div key={ph.id} onClick={inert ? undefined : (e) => photos.onOpen(ph, e.currentTarget.getBoundingClientRect())} data-testid={`event-photo-${i}`} data-photo-thumb={ph.id} role="button" aria-label={T(`Ảnh ${i + 1}`, `Photo ${i + 1}`)} className="bbv23-photo"
                        style={bg(ph.url, { flex: 'none', width: 196, height: 142, borderRadius: 12, cursor: 'pointer', backgroundColor: 'var(--bb-surface-2)', position: 'relative' })}>
                        {ph.liked && (
                          <span style={{ position: 'absolute', top: 8, right: 8, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))' }}>
                            <svg width={15} height={15} viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                ) : (
                  <p style={{ fontSize: 13, color: 'var(--bb-fg-3)', margin: 0 }}>{T('Chưa có ảnh nào cho sự kiện này.', 'No photos for this event yet.')}</p>
                )}
              </Sec>

              {protection && (
                <Sec secRef={p.secRefs.safe} id="safe" testId="event-protection" last>
                  <H>{T('Đặt chỗ được bảo vệ', 'Protected booking')}</H>
                  <ol style={{ position: 'relative', display: 'flex', flexDirection: 'column', gap: 14, margin: 0, padding: '0 0 0 2px', listStyle: 'none' }}>
                    {protection.map(([title, sub], i) => (
                      <li key={i} style={{ position: 'relative', display: 'flex', gap: 12 }}>
                        {i < protection.length - 1 && <span aria-hidden style={{ position: 'absolute', left: 11, top: 26, bottom: -14, width: 1, background: 'var(--bb-rule)' }} />}
                        <span aria-hidden style={{ width: 23, height: 23, borderRadius: '50%', background: 'var(--bb-surface-2)', display: 'grid', placeItems: 'center', fontSize: 10.5, fontWeight: 700, flex: 'none', marginTop: 1 }}>{i + 1}</span>
                        <span style={{ minWidth: 0 }}>
                          <b style={{ display: 'block', fontSize: 13.5, fontWeight: 600 }}>{title}</b>
                          <span style={{ display: 'block', fontSize: 12.5, color: 'var(--bb-fg-2)', lineHeight: 1.5, marginTop: 2 }}>{sub}</span>
                        </span>
                      </li>
                    ))}
                  </ol>
                </Sec>
              )}
            </div>
          </div>
        </div>

        {/* Over the photo: one glass Back. */}
        <button type="button" data-fade onClick={onBack} aria-label={backLabel} data-testid="event-detail-back" className={`bbv23-back bbv23-press${collapsed ? ' hide' : ''}`} tabIndex={collapsed ? -1 : 0}
          style={{ position: 'absolute', top: p.overlayTop, left: 16, zIndex: 44, width: 44, height: 44, borderRadius: '50%', display: 'grid', placeItems: 'center', padding: 0, color: '#fff', cursor: 'pointer',
            background: 'var(--bb-rt-photo-control, rgba(0,0,0,.36))', border: '1px solid rgba(255,255,255,.26)', backdropFilter: 'var(--bb-rt-blur, blur(14px))', WebkitBackdropFilter: 'var(--bb-rt-blur, blur(14px))' }}>
          <IconBack />
        </button>

        {/* Past 140 px: the glass nav with the title, Save, Share, ⋯, the tabs and the reading progress. */}
        <header data-testid="event-nav-bar" aria-hidden={!collapsed} className={`bbv23-nav${collapsed ? ' on' : ''}`}
          style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 45, padding: `calc(${p.overlayTop} - 2px) 8px 0`, ...glassBar, borderBottom: '1px solid var(--v23-line)', boxShadow: '0 10px 30px rgba(24,20,16,.06)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 2, height: 48 }}>
            {/* In the preview only Back works (it returns to the host's Private tab). */}
            <button type="button" onClick={onBack} aria-label={backLabel} data-testid="event-nav-back" className="bbv23-press" style={nbtn} tabIndex={collapsed ? 0 : -1}><IconBack /></button>
            <div style={{ flex: 1, minWidth: 0, textAlign: 'center', fontSize: 14.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.name}</div>
            <span style={{ display: 'contents', ...off }}>
            <button type="button" onClick={onSave} aria-label={saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')} aria-pressed={saved} data-testid="event-detail-save" className="bbv23-press" tabIndex={collapsed ? 0 : -1}
              style={{ ...nbtn, ...off, color: saved ? 'var(--bb-clay)' : 'var(--bb-fg)' }}><IconSave on={saved} /></button>
            <button type="button" onClick={onShare} aria-label={T('Chia sẻ', 'Share')} data-testid="event-detail-share" className="bbv23-press" style={{ ...nbtn, ...off }} tabIndex={collapsed ? 0 : -1}><IconShare /></button>
            <GlassMenu open={menuOpen} onOpenChange={setMenuOpen} top={46} label={T('Tuỳ chọn sự kiện', 'Event options')} menuTestId="event-detail-menu" wrapStyle={off || undefined}
              trigger={(
                <button type="button" onClick={() => setMenuOpen(o => !o)} aria-haspopup="menu" aria-label={T('Thêm', 'More')} aria-expanded={menuOpen} data-testid="event-detail-more" className="bbv23-press" style={nbtn} tabIndex={collapsed ? 0 : -1}><IconMore /></button>
              )}>
              {menuItems}
            </GlassMenu>
            </span>
          </div>
          <div ref={tabRowRef} data-testid="event-tabs" role="navigation" aria-label={T('Các mục', 'Sections')} className="bbv23-tabs bbv23-scroll"
            style={{ display: 'flex', gap: 20, overflowX: 'auto', padding: '0 16px', scrollbarWidth: 'none' }}>
            {tabs.ids.map(id => {
              const on = tabs.active === id;
              return (
                <button key={id} type="button" data-tab={id} data-testid={`event-tab-${id}`} aria-current={on ? 'true' : undefined} tabIndex={collapsed ? 0 : -1} onClick={() => tabs.go(id)}
                  style={{ position: 'relative', flex: 'none', minHeight: 40, padding: '0 0 4px', border: 'none', background: 'none', fontSize: 13, fontWeight: on ? 700 : 500, color: on ? 'var(--bb-fg)' : 'var(--bb-fg-3)', cursor: 'pointer', whiteSpace: 'nowrap', transition: 'color .18s' }}>
                  {tabs.label[id]}
                  {on && <span aria-hidden style={{ position: 'absolute', left: 0, right: 0, bottom: 4, height: 2, borderRadius: 2, background: 'var(--bb-fg)' }} />}
                </button>
              );
            })}
          </div>
          <div aria-hidden style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 2, overflow: 'hidden', pointerEvents: 'none' }}>
            <i ref={progressRef} data-testid="event-read-progress" style={{ display: 'block', height: '100%', width: '100%', background: 'var(--bb-clay)', transform: 'scaleX(0)', transformOrigin: 'left', transition: 'transform 90ms linear' }} />
          </div>
        </header>

        {toast}
        {footer ? (
          // Preview: the (inactive) reserve bar guests will see, then the host's own Confirm & submit under it.
          <div data-testid="event-preview-bottom" style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 46, display: 'flex', flexDirection: 'column' }}>
            <div aria-hidden style={{ position: 'relative', height: 76, pointerEvents: 'none' }}>{bar}</div>
            <div data-testid="event-preview-footer" style={{ background: 'var(--bb-bg)', padding: '8px 16px calc(12px + env(safe-area-inset-bottom, 0px))', borderTop: '1px solid var(--bb-divider)' }}>{footer}</div>
          </div>
        ) : bar}
        {overlays}
      </div>
    </div>
  );
}
