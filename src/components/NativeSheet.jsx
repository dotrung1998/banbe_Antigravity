// Native modal sheet on <dialog> (Modern Web Guidance pass, note 90). The browser already provides what every
// hand-rolled sheet in this app rebuilt: top-layer rendering above everything, focus containment, page inertness,
// Esc / back-gesture dismissal, and focus return to the control that opened it.
//
// Two things this app adds on top of the platform:
//   1. The desktop phone frame. A top-layer box is laid out against the VIEWPORT, so on a MacBook it would centre in
//      the whole window instead of the 415px phone. The frame's rectangle (src/lib/viewport.js) is written as a
//      clip-path inset before showModal(), so the scrim and the sheet paint and hit-test only inside the phone.
//      On a real phone the insets are 0 and this is a no-op.
//   2. `role="dialog"` / `aria-modal` are kept DELIBERATELY, although the native element already implies both: this
//      repo's Playwright specs assert those attributes, and dropping them would be a contract change unrelated to
//      the modernization. They are redundant, not wrong.
//
//   3. Drag down to dismiss, like an iOS sheet. A downward pull on the panel follows the finger (the scrim fades with
//      it) and either snaps back or carries the panel off the bottom and closes. A pull that starts inside a scrolled
//      list never steals the scroll: the sheet only moves when that list is already at its top, which is iOS's own
//      rule. Sideways gestures are left alone (the filter sheet's price slider, photo tracks).
//
// Do NOT add a focus trap, an Escape listener or `inert` toggling around this component: showModal() supplies all
// three, and stacking a second trap on top fights the native one (see the dialog guide).
import { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { getFrameBox } from '../lib/viewport.js';

const FRAME_RADIUS = 55; // .bb-screen's border-radius in the desktop frame

/**
 * `open` false unmounts the dialog (the app's sheets are conditionally mounted, so this is usually always true).
 * `onClose` is called for Esc, the back gesture, and a press on the scrim — never for a press inside the panel.
 * `returnFocusTo` is the element that should get focus back; native dialogs restore focus to the previously focused
 * element, but Safari does not focus a button on click, so callers pass the clicked element explicitly.
 */
export default function NativeSheet({
  open = true, onClose, labelledBy, label, testId, bodyTestId, zIndex = 2300, returnFocusTo,
  align = 'end', pad = 0, scrim, blur = 0, children, style, className = '',
}) {
  const dialogRef = useRef(null);
  const bodyRef = useRef(null);
  // The live pointer gesture (which panel, where it started, how far it has travelled down).
  const dragRef = useRef(null);
  // Who opened it, captured before showModal() moves focus. Native dialogs already restore focus, but Safari does not
  // focus a button when it is clicked, so there the "previously focused" element is the page body; this fallback gives
  // every caller the trigger back without each one having to wire `returnFocusTo` by hand.
  const openerRef = useRef(null);
  if (openerRef.current === null && typeof document !== 'undefined') openerRef.current = document.activeElement;
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  const returnRef = useRef(returnFocusTo);
  returnRef.current = returnFocusTo;

  useEffect(() => {
    if (!open) return undefined;
    const el = dialogRef.current;
    if (!el || typeof el.showModal !== 'function' || el.open) return undefined;
    // Capture at open time too, in case the trigger only lost focus between render and this effect.
    if (!returnRef.current) openerRef.current = document.activeElement;

    // The phone frame, as insets from the four viewport edges.
    const box = getFrameBox();
    const vw = window.innerWidth || 0;
    const vh = window.innerHeight || 0;
    const framed = box.width > 0
      && (box.left > 0.5 || box.top > 0.5 || box.width < vw - 0.5 || box.height < vh - 0.5);
    const set = (k, v) => el.style.setProperty(k, v);
    set('--bb-dlg-t', `${framed ? Math.max(0, box.top) : 0}px`);
    set('--bb-dlg-r', `${framed ? Math.max(0, vw - box.left - box.width) : 0}px`);
    set('--bb-dlg-b', `${framed ? Math.max(0, vh - box.top - box.height) : 0}px`);
    set('--bb-dlg-l', `${framed ? Math.max(0, box.left) : 0}px`);
    set('--bb-dlg-radius', `${framed ? FRAME_RADIUS : 0}px`);

    el.showModal();
    return () => {
      // `el`, not dialogRef: React detaches the ref before this cleanup runs on unmount, and a dialog removed while still
      // open hands focus back to the page body afterwards — which would win over the focus call below.
      if (el.open) el.close();
      const back = returnRef.current || openerRef.current;
      if (back?.focus) { try { back.focus({ preventScroll: true }); } catch { /* element gone */ } }
    };
  }, [open]);

  // Drag down to dismiss (iOS parity). Lives here, on the shared sheet primitive, so every bottom sheet in the app
  // gets the same gesture as the native one; no caller has to wire anything. The panel is the body's first element
  // child, which is the shape every caller already uses (a sheet's own rounded panel div).
  useEffect(() => {
    if (!open || align !== 'end') return undefined;
    const el = dialogRef.current;
    const body = bodyRef.current;
    const firstPanel = body?.firstElementChild;
    if (!el || !body || !firstPanel) return undefined;
    // Re-read on every gesture: a caller may swap its panel (a sub-view) between renders, and the drag must move the
    // panel that is on screen now, not the node this effect first saw.
    const panelNow = () => body.firstElementChild;

    const reduced = typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    // A caller's own scrim colour is never touched; only the default scrim fades with the drag.
    const customScrim = !!scrim;
    let snapTimer = 0;
    let closeTimer = 0;
    // A drag ends with a pointerup, and the browser still fires a click on whatever row the finger started on. That
    // click must not run: pulling a sheet down should never also open the profile (or toggle a switch) underneath it.
    let swallowClick = false;

    // The nearest box that actually scrolls under the pointer. A pull that starts inside one is the list's scroll
    // until that list reaches its top; then the same pull belongs to the sheet, exactly as an iOS sheet behaves.
    const nearestScroller = (node) => {
      for (let n = node; n && n !== body; n = n.parentElement) {
        const overflowY = getComputedStyle(n).overflowY;
        if ((overflowY === 'auto' || overflowY === 'scroll') && n.scrollHeight > n.clientHeight + 1) return n;
      }
      return null;
    };
    const panelHeight = (p) => p.getBoundingClientRect().height || 1;
    const fadeScrim = (y, p) => {
      if (customScrim) return;
      const left = Math.max(0, Math.min(1, 1 - y / panelHeight(p)));
      el.style.background = `rgba(27,25,22,${(0.42 * left).toFixed(3)})`;
    };

    const onDown = (e) => {
      if (closeTimer) return; // already carrying the panel off the bottom
      // Only the click that closes the same gesture is swallowed (down, up, click); a drag that produced no click
      // must not eat the next, unrelated tap.
      if (swallowClick) swallowClick = false;
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      const p = panelNow();
      if (!p || !p.contains(e.target)) return; // a press on the scrim belongs to the dialog's click-to-close
      dragRef.current = { pointerId: e.pointerId, x: e.clientX, y: e.clientY, dy: 0, active: false, panel: p, scroller: nearestScroller(e.target) };
    };

    const onMove = (e) => {
      const d = dragRef.current;
      if (!d || d.pointerId !== e.pointerId || closeTimer) return;
      const dx = e.clientX - d.x;
      const dy = e.clientY - d.y;
      if (!d.active) {
        // Sideways: a price slider, a photo track. Not ours.
        if (Math.abs(dx) > 10 && Math.abs(dx) >= Math.abs(dy)) { dragRef.current = null; return; }
        // Up, or not far enough yet: leave the gesture to the content (scrolling up, taps).
        if (dy <= 8 || Math.abs(dy) <= Math.abs(dx)) return;
        if (d.scroller && d.scroller.scrollTop > 0) { dragRef.current = null; return; }
        d.active = true;
        try { body.setPointerCapture(e.pointerId); } catch { /* capture is best-effort */ }
        // A panel that still carries its entrance animation (`banbeIn … both`) would keep painting that animation's
        // transform over the drag; a CSS animation outranks an inline style. The drag owns the panel from here on.
        d.panel.style.animation = 'none';
        d.panel.style.transition = 'none';
        d.panel.style.willChange = 'transform';
        el.dataset.dragging = 'true';
      }
      d.dy = Math.max(0, dy);
      d.panel.style.transform = `translate3d(0, ${d.dy}px, 0)`;
      fadeScrim(d.dy, d.panel);
    };

    const finish = () => {
      const d = dragRef.current;
      dragRef.current = null;
      if (!d?.active) return;
      swallowClick = true;
      try { body.releasePointerCapture(d.pointerId); } catch { /* already released */ }
      el.dataset.dragging = 'false';
      const p = d.panel;
      const h = panelHeight(p);
      // Past a third of the panel (or 180 px) it goes; less and it springs back.
      const dismiss = d.dy > Math.min(180, h * 0.3);
      const ms = reduced ? 0 : 240;
      p.style.transition = `transform ${ms}ms cubic-bezier(.22,.61,.36,1)`;
      if (dismiss) {
        p.style.transform = `translate3d(0, ${h}px, 0)`;
        if (!customScrim) el.style.background = 'rgba(27,25,22,0)';
        // Unmount after the panel has left the screen (0 with Reduce Motion), not while it is still moving.
        closeTimer = window.setTimeout(() => closeRef.current?.(), reduced ? 0 : 180);
      } else {
        p.style.transform = '';
        if (!customScrim) el.style.background = '';
        snapTimer = window.setTimeout(() => { p.style.transition = ''; p.style.willChange = ''; }, ms + 20);
      }
    };

    // Pointer events do not stop a native touch scroll by themselves; while a drag is live, the sheet owns the move.
    const onTouchMove = (e) => { if (dragRef.current?.active && e.cancelable) e.preventDefault(); };
    // Capture phase, so the click never reaches the row's own handler (and never reaches the dialog's scrim close).
    const onClickCapture = (e) => {
      if (!swallowClick) return;
      swallowClick = false;
      e.stopPropagation();
      e.preventDefault();
    };

    body.addEventListener('pointerdown', onDown);
    body.addEventListener('pointermove', onMove);
    body.addEventListener('pointerup', finish);
    body.addEventListener('pointercancel', finish);
    body.addEventListener('touchmove', onTouchMove, { passive: false });
    body.addEventListener('click', onClickCapture, true);
    return () => {
      body.removeEventListener('pointerdown', onDown);
      body.removeEventListener('pointermove', onMove);
      body.removeEventListener('pointerup', finish);
      body.removeEventListener('pointercancel', finish);
      body.removeEventListener('touchmove', onTouchMove);
      body.removeEventListener('click', onClickCapture, true);
      window.clearTimeout(snapTimer);
      window.clearTimeout(closeTimer);
      dragRef.current = null;
      delete el.dataset.dragging;
      const p = panelNow() || firstPanel;
      p.style.transform = '';
      p.style.transition = '';
      p.style.willChange = '';
      p.style.animation = '';
      if (!customScrim) el.style.background = '';
    };
  }, [open, align, scrim]);

  if (!open) return null;
  const target = (typeof document !== 'undefined' && (document.querySelector('.bb-screen') || document.body)) || null;
  if (!target) return null;

  return createPortal(
    <dialog
      ref={dialogRef}
      className={`bb-native-sheet ${className}`.trim()}
      data-testid={testId}
      aria-labelledby={labelledBy}
      aria-label={labelledBy ? undefined : label}
      // Deliberate redundancy, see the header comment: the app's specs assert these.
      role="dialog"
      aria-modal="true"
      style={{
        zIndex,
        ...(scrim ? { background: scrim } : null),
        ...(blur ? { backdropFilter: `blur(${blur}px)`, WebkitBackdropFilter: `blur(${blur}px)` } : null),
        ...style,
      }}
      // Esc and the mobile back gesture: keep React's state in charge of unmounting, with its own close animation.
      onCancel={(e) => { e.preventDefault(); closeRef.current?.(); }}
      // A press on the scrim (the dialog itself, or the full-size body wrapper) dismisses. `closedby` would do this
      // natively but is Chrome/Firefox only; on Safari this is the portable path.
      onClick={(e) => { if (e.target === dialogRef.current || e.target === bodyRef.current) closeRef.current?.(); }}
    >
      <div
        ref={bodyRef}
        className="bb-native-sheet-body"
        data-testid={bodyTestId}
        style={{ justifyContent: align === 'center' ? 'center' : 'flex-end', padding: pad || undefined }}
      >{children}</div>
    </dialog>,
    target,
  );
}
